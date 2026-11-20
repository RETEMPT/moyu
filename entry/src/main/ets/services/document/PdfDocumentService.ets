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
import { deviceInfo } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { image } from '@kit.ImageKit';
import { PdfPageModel } from '../../common/types/PdfAnnotationTypes';
import { PdfTextPage } from '../../common/types/StudyTypes';
import { OcrService } from '../ocr/OcrService';
import { DebugPdfPreviewService } from './DebugPdfPreviewService';
import { LocalPdfEngine, pdfFailureKind } from './LocalPdfEngine';
import { NativePdfLoader } from './NativePdfLoader';
import { NativePdfResult } from './NativePdfTask';
import BuildProfile from 'BuildProfile';

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
  stamp: string;
  bytes: number;
  pixelMap: image.PixelMap;
  aspectRatio: number;
}

interface PageStamp { source: string; epoch: number; }
interface PdfSourceState { size: number; stamp: string; }

export class PdfDocumentService {
  private static instance: PdfDocumentService | null = null;
  private debugPreview: DebugPdfPreviewService = new DebugPdfPreviewService();
  private nativeLoader: NativePdfLoader = new NativePdfLoader();
  private nativeUnavailable: boolean = false;
  // The reader keeps only visible pages alive. Reusing a page across a tab switch or a short
  // scroll-back avoids another full parse of the source file. Ownership is transferred out of
  // this cache to exactly one PdfPageBackground, which releases it when it leaves the viewport.
  private readonly PAGE_CACHE_LIMIT: number = 6;
  private readonly pageCacheBudget: number = (deviceInfo?.deviceType === 'tablet' ? 48 : 24) * 1024 * 1024;
  private pageCache: Map<string, CachedPage> = new Map();
  private cachedBytes: number = 0;
  private bitmapStamps: WeakMap<image.PixelMap, PageStamp> = new WeakMap();
  private cacheEpoch: number = 0;

  bindContext(context: Context): void { this.debugPreview.bindContext(context); LocalPdfEngine.getInstance().bindContext(context); }

  private async tryNative(path: string, action: string, page: number, cancelled: () => boolean,
    endPage: number = -1): Promise<NativePdfResult | null> {
    if (this.nativeUnavailable || !canIUse('SystemCapability.OfficeService.PDFService.Core')) { return null; }
    const result = await this.nativeLoader.run(path, action, page, cancelled, endPage);
    if (!result.unavailable) { return result; }
    this.nativeUnavailable = true;
    return null;
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

    let srcFile: fs.File;
    try { srcFile = fs.openSync(srcUri, fs.OpenMode.READ_ONLY); }
    catch { throw new Error('所选 PDF 无法打开，请确认文件仍可访问后重新选择'); }
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

  /** Hash the saved copy in chunks so large PDFs do not require a second copy in memory. */
  async fingerprint(path: string): Promise<string> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(file.fd).size;
      if (size <= 0) { throw new Error('PDF 文件为空'); }
      const md = cryptoFramework.createMd('SHA256');
      const buffer = new ArrayBuffer(Math.min(size, 256 * 1024));
      let offset = 0;
      while (offset < size) {
        const read = await fs.read(file.fd, buffer, { offset, length: Math.min(size - offset, buffer.byteLength) });
        if (read <= 0) { throw new Error('PDF 未完整读取，请重试'); }
        await md.update({ data: new Uint8Array(buffer, 0, read) });
        offset += read;
      }
      if (fs.statSync(file.fd).size !== size) { throw new Error('PDF 在校验时发生变化，请重试'); }
      const hash = await md.digest();
      return Array.from(hash.data).map((byte: number) => byte.toString(16).padStart(2, '0')).join('');
    } finally { await fs.close(file); }
  }

  /** A readable damaged legacy copy cannot establish the original file's identity. */
  async verifyLegacyOriginal(path: string, replacementHash: string): Promise<boolean> {
    if (await this.fingerprint(path) === replacementHash) { return true; }
    try { await this.getPdfInfo(path); }
    catch (error) {
      const kind = pdfFailureKind(error instanceof Error ? error.message : '');
      if (kind === 'missing' || kind === 'damaged') { return false; }
      throw error instanceof Error ? error : new Error('无法校验旧 PDF，请重试');
    }
    throw new Error('所选 PDF 与这份资料的原文件不同。请选择原文件，其他资料可单独导入。');
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
    const result = await this.tryNative(filePath, 'info', 0, cancelled);
    if (result !== null) {
      return { filePath, fileName: filePath.split('/').pop() || 'document.pdf', fileSize: result.fileSize, pageCount: result.pageCount };
    }
    const size = await this.requireSource(filePath);
    const count = this.debugPreview.pageCount(filePath);
    if (count > 0) {
      return { filePath, fileName: filePath.split('/').pop() || 'document.pdf', fileSize: size, pageCount: count };
    }
    const offline = await LocalPdfEngine.getInstance().inspect(filePath, cancelled);
    if (!Number.isInteger(offline.pageCount) || (offline.pageCount || 0) <= 0 || (offline.pageCount || 0) > 10000) { throw new Error('PDF 页数无效或超过 10000 页'); }
    return { filePath, fileName: filePath.split('/').pop() || 'document.pdf', fileSize: size, pageCount: offline.pageCount! };
  }

  async renderPageAsync(filePath: string, pageIndex: number, cancelled: () => boolean = () => false): Promise<RenderedPdfPage> {
    if (!Number.isInteger(pageIndex) || pageIndex < 0) { throw new Error('PDF 页码超出范围'); }
    if (cancelled()) { throw new Error('页面已离开'); }
    const epoch = this.cacheEpoch;
    const stamp = (await this.sourceState(filePath)).stamp;
    if (cancelled()) { throw new Error('页面已离开'); }
    const cached = this.takeCachedPage(filePath, pageIndex);
    if (cached !== null) {
      if (cached.stamp === stamp) { return { pixelMap: cached.pixelMap, aspectRatio: cached.aspectRatio }; }
      cached.pixelMap.release().catch(() => {});
      this.evictPages(filePath);
    }
    const result = await this.tryNative(filePath, 'page', pageIndex, cancelled);
    if (result !== null) {
      if (result.pixelMap === undefined || result.aspectRatio === undefined) { throw new Error('PDF 页面读取失败，请重试'); }
      this.bitmapStamps.set(result.pixelMap, { source: stamp, epoch: epoch });
      return { pixelMap: result.pixelMap, aspectRatio: result.aspectRatio };
    }
    const preview = await this.debugPreview.renderPage(filePath, pageIndex);
    const rendered = preview !== null ? preview : await LocalPdfEngine.getInstance().render(filePath, pageIndex, cancelled);
    if (cancelled()) { await rendered.pixelMap.release(); throw new Error('页面已离开'); }
    this.bitmapStamps.set(rendered.pixelMap, { source: stamp, epoch: epoch });
    return rendered;
  }

  /** Import validates the page count and first image in the same renderer request. */
  async validateImport(filePath: string): Promise<PdfDocumentInfo> {
    const epoch = this.cacheEpoch;
    const source = await this.sourceState(filePath);
    const result = await this.tryNative(filePath, 'cover', 0, () => false);
    let pageCount: number;
    let cover: RenderedPdfPage;
    let engine: string;
    if (result !== null) {
      if (result.pixelMap === undefined || result.aspectRatio === undefined) { throw new Error('PDF 页面读取失败，请重试'); }
      pageCount = result.pageCount;
      cover = { pixelMap: result.pixelMap, aspectRatio: result.aspectRatio };
      engine = 'PDF Kit';
    } else {
      const preview = await this.debugPreview.renderPage(filePath, 0);
      const rendered = preview ?? await LocalPdfEngine.getInstance().cover(filePath);
      pageCount = rendered.pageCount;
      cover = { pixelMap: rendered.pixelMap, aspectRatio: rendered.aspectRatio };
      engine = preview ? '内置样本预渲染' : 'PDF.js';
    }
    this.bitmapStamps.set(cover.pixelMap, { source: source.stamp, epoch: epoch });
    if (!this.recyclePage(filePath, 0, cover.pixelMap, cover.aspectRatio)) { await cover.pixelMap.release(); }
    if (BuildProfile.DEBUG) { console.info('墨屿 PDF 导入渲染：' + engine); }
    return { filePath, fileName: filePath.split('/').pop() || 'document.pdf', fileSize: source.size, pageCount };
  }

  /**
   * Return a recently released page to the cache instead of destroying it. The caller transfers
   * ownership; the cache releases the bitmap when it is evicted or the reader closes.
   */
  recyclePage(filePath: string, pageIndex: number, pixelMap: image.PixelMap, aspectRatio: number): boolean {
    const stamp = this.bitmapStamps.get(pixelMap);
    if (!filePath || !Number.isInteger(pageIndex) || pageIndex < 0 || !Number.isFinite(aspectRatio) || aspectRatio <= 0 ||
      stamp === undefined || stamp.epoch !== this.cacheEpoch) {
      return false;
    }
    let bytes: number;
    try { bytes = pixelMap.getPixelBytesNumber(); }
    catch { return false; }
    if (!Number.isSafeInteger(bytes) || bytes <= 0 || bytes > this.pageCacheBudget) { return false; }

    const key = this.cacheKey(filePath, pageIndex);
    const previous = this.removeCachedPage(key);
    if (previous !== null && previous.pixelMap !== pixelMap) { previous.pixelMap.release().catch(() => {}); }
    this.pageCache.set(key, { path: filePath, stamp: stamp.source, bytes, pixelMap, aspectRatio });
    this.cachedBytes += bytes;
    for (const oldest of this.pageCache.keys()) {
      if (this.cachedBytes <= this.pageCacheBudget && this.pageCache.size <= this.PAGE_CACHE_LIMIT) { break; }
      this.removeCachedPage(oldest)?.pixelMap.release().catch(() => {});
    }
    return true;
  }

  /** Drop every retained page (reader exit, source replacement, or low-memory reset). */
  clearPageCache(): void {
    this.cacheEpoch++;
    for (const entry of this.pageCache.values()) { entry.pixelMap.release().catch(() => {}); }
    this.pageCache.clear();
    this.cachedBytes = 0;
  }

  private cacheKey(filePath: string, pageIndex: number): string {
    return filePath + '#' + pageIndex;
  }

  private takeCachedPage(filePath: string, pageIndex: number): CachedPage | null {
    return this.removeCachedPage(this.cacheKey(filePath, pageIndex));
  }

  private removeCachedPage(key: string): CachedPage | null {
    const entry = this.pageCache.get(key);
    if (entry === undefined) { return null; }
    this.pageCache.delete(key);
    this.cachedBytes -= entry.bytes;
    return entry;
  }

  private evictPages(filePath: string): void {
    for (const key of this.pageCache.keys()) {
      if (this.pageCache.get(key)?.path === filePath) {
        this.removeCachedPage(key)?.pixelMap.release().catch(() => {});
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

  private async sourceState(filePath: string): Promise<PdfSourceState> {
    if (!filePath) { throw new Error('这份资料缺少 PDF 原文件，请重新关联原 PDF。'); }
    try {
      const stat = await fs.stat(filePath);
      if (stat.size <= 0) { throw new Error('missing'); }
      return { size: stat.size, stamp: `${stat.size}:${stat.mtime || 0}` };
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
    // One parse for the whole reviewed range instead of one loadDocument per page.
    const batch = await this.tryNative(filePath, 'texts', start - 1, cancelled, end - 1);
    if (batch !== null) {
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
