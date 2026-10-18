/**
 * PDF 真实文档管理服务 (PdfDocumentService)
 *
 * 负责：
 *   1. 原始 PDF 文件在沙箱内的持久化复制与管理 (files/documents/)
 *   2. 读取 PDF 元数据、页数与页面尺寸
 *   3. 页面模型动态加载：与 HarmonyOS PDF Kit 架构对接
 *   4. 原文失败时报告错误，不展示替代的模拟页面
 */
import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { PdfPageModel } from '../../common/types/PdfAnnotationTypes';
import { PdfTextPage } from '../../common/types/StudyTypes';
import { OcrService } from '../ocr/OcrService';
import { DebugPdfPreviewService } from './DebugPdfPreviewService';
import { LocalPdfEngine } from './LocalPdfEngine';
import { NativePdfLoader } from './NativePdfLoader';

export interface PdfDocumentInfo {
  filePath: string;
  fileName: string;
  fileSize: number;
  pageCount: number;
}

export interface RenderedPdfPage {
  pixelMap: image.PixelMap;
  aspectRatio: number;
}

interface CachedPage {
  path: string;
  page: number;
  stamp: string;
  pixelMap: image.PixelMap;
  aspectRatio: number;
}

export class PdfDocumentService {
  private static instance: PdfDocumentService | null = null;
  private debugPreview: DebugPdfPreviewService = new DebugPdfPreviewService();
  private nativeLoader: NativePdfLoader = new NativePdfLoader();
  // The reader keeps only visible pages alive. Reusing a page across a tab switch or a short
  // scroll-back avoids another full parse of the source file. Ownership is transferred out of
  // this cache to exactly one PdfPageBackground, which releases it when it leaves the viewport.
  private readonly PAGE_CACHE_LIMIT: number = 3;
  private pageCache: Map<string, CachedPage> = new Map();
  private pageCacheOrder: string[] = [];
  private bitmapStamps: WeakMap<image.PixelMap, string> = new WeakMap();

  bindContext(context: Context): void { this.debugPreview.bindContext(context); LocalPdfEngine.getInstance().bindContext(context); }

  private nativeAvailable(): boolean {
    return canIUse('SystemCapability.OfficeService.PDFService.Core');
  }

  static getInstance(): PdfDocumentService {
    if (PdfDocumentService.instance === null) {
      PdfDocumentService.instance = new PdfDocumentService();
    }
    return PdfDocumentService.instance;
  }

  /**
   * 将外部选择的 PDF 复制到应用沙箱的 documents 目录
   */
  async savePdfToSandbox(context: Context, srcUri: string, targetName: string): Promise<string> {
    const docDir: string = `${context.filesDir}/documents`;
    this.ensureDirectory(docDir);

    const sanitizedName = targetName.replace(/[\\/:*?"<>|]/g, '_');
    const destPath: string = `${docDir}/${Date.now()}_${Math.floor(Math.random() * 1000000)}_${sanitizedName}`;

    const srcFile = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
    try {
      const expectedSize = fs.statSync(srcFile.fd).size;
      if (expectedSize <= 0) { throw new Error('PDF 文件为空'); }
      await fs.copyFile(srcFile.fd, destPath);
      const copy = fs.openSync(destPath, fs.OpenMode.READ_WRITE);
      try {
        if (fs.statSync(copy.fd).size !== expectedSize) { throw new Error('PDF 复制不完整'); }
        await fs.fsync(copy.fd);
      } finally { fs.closeSync(copy); }
      return destPath;
    } catch (error) {
      try { fs.unlinkSync(destPath); } catch { /* 未创建目标 */ }
      throw new Error(error instanceof Error ? `PDF 复制失败：${error.message}` : 'PDF 复制失败，请检查存储空间或文件权限');
    } finally {
      fs.closeSync(srcFile);
    }
  }

  /**
   * 保存内置阅读测试文件；调试版启动时会自动加入一份
   */
  async saveBundledExample(context: Context, snapshot: boolean = false): Promise<string> {
    this.bindContext(context);
    const name = snapshot ? 'example-snapshot.pdf' : 'example-course.pdf';
    const data = await context.resourceManager.getRawFileContent(name);
    if (data.length < 5 || data[0] !== 37 || data[1] !== 80 || data[2] !== 68 || data[3] !== 70) { throw new Error('测试 PDF 资源不可读'); }
    const directory = `${context.filesDir}/documents`;
    this.ensureDirectory(directory);
    const path = `${directory}/${Date.now()}_${Math.floor(Math.random() * 1000000)}_${name}`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      const written = fs.writeSync(file.fd, data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
      if (written !== data.byteLength) { throw new Error('PDF 写入不完整'); }
      fs.fsyncSync(file.fd);
    }
    catch { try { fs.unlinkSync(path); } catch {} throw new Error('测试 PDF 保存失败，请检查存储空间'); }
    finally { fs.closeSync(file); }
    return path;
  }

  async getPdfInfo(filePath: string, cancelled: () => boolean = () => false): Promise<PdfDocumentInfo> {
    if (cancelled()) { throw new Error('页面已离开'); }
    // An info probe is an explicit re-read of the source (import, extraction, replacement).
    // Drop retained page bitmaps so a rewritten file can never be served from the cache.
    this.evictPages(filePath);
    if (this.nativeAvailable()) {
      const result = await this.nativeLoader.run(filePath, 'info', 0, cancelled);
      return { filePath, fileName: filePath.split('/').pop() || 'document.pdf', fileSize: result.fileSize, pageCount: result.pageCount };
    }
    const size = await this.requireSource(filePath);
    const count = this.debugPreview.pageCount(filePath);
    if (count > 0) {
      return { filePath, fileName: filePath.split('/').pop() || 'document.pdf', fileSize: size, pageCount: count };
    }
    const result = await LocalPdfEngine.getInstance().inspect(filePath, cancelled);
    if (!Number.isInteger(result.pageCount) || (result.pageCount || 0) <= 0 || (result.pageCount || 0) > 10000) { throw new Error('PDF 页数无效或超过 10000 页'); }
    return { filePath, fileName: filePath.split('/').pop() || 'document.pdf', fileSize: size, pageCount: result.pageCount! };
  }

  async renderPageAsync(filePath: string, pageIndex: number, cancelled: () => boolean = () => false): Promise<RenderedPdfPage> {
    if (!Number.isInteger(pageIndex) || pageIndex < 0) { throw new Error('PDF 页码超出范围'); }
    if (cancelled()) { throw new Error('页面已离开'); }
    const stamp = await this.sourceStamp(filePath);
    if (cancelled()) { throw new Error('页面已离开'); }
    const cached = this.takeCachedPage(filePath, pageIndex);
    if (cached !== null) {
      if (cached.stamp === stamp) { return { pixelMap: cached.pixelMap, aspectRatio: cached.aspectRatio }; }
      cached.pixelMap.release().catch(() => {});
      this.evictPages(filePath);
    }
    if (this.nativeAvailable()) {
      const result = await this.nativeLoader.run(filePath, 'page', pageIndex, cancelled);
      if (result.pixelMap === undefined || result.aspectRatio === undefined) { throw new Error('PDF 页面读取失败，请重试'); }
      this.bitmapStamps.set(result.pixelMap, stamp);
      return { pixelMap: result.pixelMap, aspectRatio: result.aspectRatio };
    }
    const preview = await this.debugPreview.renderPage(filePath, pageIndex);
    const rendered = preview !== null ? preview : await LocalPdfEngine.getInstance().render(filePath, pageIndex, cancelled);
    if (cancelled()) { await rendered.pixelMap.release(); throw new Error('页面已离开'); }
    this.bitmapStamps.set(rendered.pixelMap, stamp);
    return rendered;
  }

  /** The caller publishes a source only after native parsing and a real first-page render succeed. */
  async validateImport(filePath: string): Promise<PdfDocumentInfo> {
    if (this.nativeAvailable()) {
      const stamp = await this.sourceStamp(filePath);
      // One loadDocument supplies both the page count and the cover bitmap. The cover is kept
      // for the reader so tapping the freshly imported note paints immediately.
      const result = await this.nativeLoader.run(filePath, 'cover', 0, () => false);
      if (result.pixelMap === undefined || result.aspectRatio === undefined) { throw new Error('PDF 页面读取失败，请重试'); }
      this.bitmapStamps.set(result.pixelMap, stamp);
      this.rememberCachedPage(filePath, 0, result.pixelMap, result.aspectRatio);
      return { filePath: filePath, fileName: filePath.split('/').pop() || 'document.pdf',
        fileSize: result.fileSize, pageCount: result.pageCount };
    }
    const info = await this.getPdfInfo(filePath);
    const preview = await this.renderPageAsync(filePath, 0);
    this.rememberCachedPage(filePath, 0, preview.pixelMap, preview.aspectRatio);
    return info;
  }

  /**
   * Return a recently released page to the cache instead of destroying it. The caller transfers
   * ownership; the cache releases the bitmap when it is evicted or the reader closes.
   */
  recyclePage(filePath: string, pageIndex: number, pixelMap: image.PixelMap, aspectRatio: number): boolean {
    if (!filePath || !Number.isInteger(pageIndex) || pageIndex < 0 || !Number.isFinite(aspectRatio) || aspectRatio <= 0 || !this.bitmapStamps.has(pixelMap)) {
      return false;
    }
    this.rememberCachedPage(filePath, pageIndex, pixelMap, aspectRatio);
    return true;
  }

  /** Drop every retained page (reader exit, source replacement, or low-memory reset). */
  clearPageCache(): void {
    for (const entry of this.pageCache.values()) { entry.pixelMap.release().catch(() => {}); }
    this.pageCache.clear();
    this.pageCacheOrder = [];
  }

  private cacheKey(filePath: string, pageIndex: number): string {
    return filePath + '#' + pageIndex;
  }

  private takeCachedPage(filePath: string, pageIndex: number): CachedPage | null {
    const key = this.cacheKey(filePath, pageIndex);
    const entry = this.pageCache.get(key);
    if (entry === undefined) { return null; }
    this.pageCache.delete(key);
    const index = this.pageCacheOrder.indexOf(key);
    if (index >= 0) { this.pageCacheOrder.splice(index, 1); }
    return entry;
  }

  private rememberCachedPage(filePath: string, pageIndex: number, pixelMap: image.PixelMap, aspectRatio: number): void {
    const key = this.cacheKey(filePath, pageIndex);
    const previous = this.pageCache.get(key);
    if (previous !== undefined) {
      if (previous.pixelMap !== pixelMap) { previous.pixelMap.release().catch(() => {}); }
      this.pageCache.delete(key);
      const previousIndex = this.pageCacheOrder.indexOf(key);
      if (previousIndex >= 0) { this.pageCacheOrder.splice(previousIndex, 1); }
    }
    this.pageCache.set(key, { path: filePath, page: pageIndex, stamp: this.bitmapStamps.get(pixelMap) || '', pixelMap: pixelMap, aspectRatio: aspectRatio });
    this.pageCacheOrder.push(key);
    while (this.pageCacheOrder.length > this.PAGE_CACHE_LIMIT) {
      const oldest = this.pageCacheOrder.shift();
      if (oldest === undefined) { break; }
      const entry = this.pageCache.get(oldest);
      if (entry !== undefined) {
        this.pageCache.delete(oldest);
        entry.pixelMap.release().catch(() => {});
      }
    }
  }

  private evictPages(filePath: string): void {
    const keys: string[] = [];
    for (const key of this.pageCache.keys()) {
      const entry = this.pageCache.get(key);
      if (entry !== undefined && entry.path === filePath) { keys.push(key); }
    }
    for (const key of keys) {
      const entry = this.pageCache.get(key);
      if (entry !== undefined) {
        this.pageCache.delete(key);
        const index = this.pageCacheOrder.indexOf(key);
        if (index >= 0) { this.pageCacheOrder.splice(index, 1); }
        entry.pixelMap.release().catch(() => {});
      }
    }
  }

  /** Cleanup may only touch direct files created inside our PDF directory. */
  async removeManagedPdf(context: Context, filePath: string): Promise<void> {
    this.evictPages(filePath);
    const prefix = `${context.filesDir}/documents/`;
    const name = filePath.startsWith(prefix) ? filePath.substring(prefix.length) : '';
    if (!name || name === '.' || name === '..' || name.includes('/') || name.includes('\\')) { return; }
    if (fs.accessSync(filePath)) { await fs.unlink(filePath); }
  }

  private ensureDirectory(directory: string): void {
    if (fs.accessSync(directory)) { return; }
    try { fs.mkdirSync(directory); }
    catch { if (!fs.accessSync(directory)) { throw new Error('PDF 保存目录无法创建，请检查存储空间'); } }
  }

  private async requireSource(filePath: string): Promise<number> {
    if (!filePath) { throw new Error('这份资料缺少 PDF 原文件，请重新关联原 PDF。'); }
    try {
      const stat = await fs.stat(filePath);
      if (stat.size <= 0) { throw new Error('missing'); }
      return stat.size;
    } catch { throw new Error('PDF 原文件不存在或不可读，请重新关联原 PDF。'); }
  }

  private async sourceStamp(filePath: string): Promise<string> {
    if (!filePath) { throw new Error('这份资料缺少 PDF 原文件，请重新关联原 PDF。'); }
    try {
      const stat = await fs.stat(filePath);
      if (stat.size <= 0) { throw new Error('missing'); }
      return `${stat.size}:${stat.mtime || 0}`;
    } catch {
      this.evictPages(filePath);
      throw new Error('PDF 原文件不存在或不可读，请重新关联原 PDF。');
    }
  }

  /** Bounded batches keep extraction cancellable; reviewed results alone enter the index. */
  async extractPages(filePath: string, start: number, end: number, scanOcr: boolean,
    cancelled: () => boolean, progress: (page: number) => void): Promise<PdfTextPage[]> {
    if (!Number.isInteger(start) || !Number.isInteger(end) || start < 1 || end < start || end - start >= 30) {
      throw new Error('每次请选择 1～30 页');
    }
    let texts: string[] | null = null;
    let pageCount = 0;
    if (this.nativeAvailable()) {
      // One parse for the whole reviewed range instead of one loadDocument per page.
      const batch = await this.nativeLoader.run(filePath, 'texts', start - 1, cancelled, end - 1);
      pageCount = batch.pageCount;
      texts = batch.texts || [];
    } else {
      const info = await this.getPdfInfo(filePath, cancelled);
      pageCount = info.pageCount;
    }
    if (end > pageCount) { throw new Error('页码超出资料范围'); }
    const pages: PdfTextPage[] = [];
    for (let number = start; number <= end; number++) {
      if (cancelled()) { throw new Error('已取消提取'); }
      progress(number);
      if (cancelled()) { throw new Error('已取消提取'); }
      let text = texts !== null ? (texts[number - start] || '') :
        (await LocalPdfEngine.getInstance().text(filePath, number - 1, cancelled)).trim();
      let method: 'text' | 'ocr' = 'text';
      if (!text && scanOcr) {
        const preview = await this.renderPageAsync(filePath, number - 1, cancelled);
        try { text = await OcrService.getInstance().recognizePixelMap(preview.pixelMap); method = 'ocr'; }
        finally { await preview.pixelMap.release(); }
      }
      if (text.length > 80000) { throw new Error(`第 ${number} 页文字过多，请缩小页面内容`); }
      pages.push({ pageNumber: number, text, method, extractedAt: Date.now() });
    }
    if (cancelled()) { throw new Error('已取消提取'); }
    return pages;
  }

  /**
   * 生成指定页数的排版数据模型
   */
  generatePageModels(pageCount: number, title: string): PdfPageModel[] {
    const pages: PdfPageModel[] = [];
    const count = Math.max(1, pageCount);

    for (let i = 0; i < count; i++) {
      pages.push({
        pageIndex: i,
        pageNumberText: `第 ${i + 1} 页 · 共 ${count} 页`,
        sections: []
      });
    }
    return pages;
  }
}
