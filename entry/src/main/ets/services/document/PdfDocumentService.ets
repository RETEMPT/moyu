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
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { PdfPageModel } from '../../common/types/PdfAnnotationTypes';
import { PdfTextPage } from '../../common/types/StudyTypes';
import { OcrService } from '../ocr/OcrService';

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

export class PdfDocumentService {
  private static instance: PdfDocumentService | null = null;

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
    if (!fs.accessSync(docDir)) {
      fs.mkdirSync(docDir);
    }

    const sanitizedName = targetName.replace(/[\\/:*?"<>|]/g, '_');
    const destPath: string = `${docDir}/${Date.now()}_${Math.floor(Math.random() * 1000000)}_${sanitizedName}`;

    const srcFile = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
    try {
      await fs.copyFile(srcFile.fd, destPath);
      return destPath;
    } catch {
      try { fs.unlinkSync(destPath); } catch { /* 未创建目标 */ }
      throw new Error('PDF 复制失败，请检查存储空间或文件权限');
    } finally {
      fs.closeSync(srcFile);
    }
  }

  /**
   * 显式导入内置阅读测试文件，不在首次启动时创建笔记
   */
  async saveBundledExample(context: Context): Promise<string> {
    const data = await context.resourceManager.getRawFileContent('example-course.pdf');
    if (data.length < 5 || data[0] !== 37 || data[1] !== 80 || data[2] !== 68 || data[3] !== 70) { throw new Error('测试 PDF 资源不可读'); }
    const directory = `${context.filesDir}/documents`;
    if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
    const path = `${directory}/${Date.now()}_${Math.floor(Math.random() * 1000000)}_example-course.pdf`;
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      const written = fs.writeSync(file.fd, data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
      if (written !== data.byteLength) { throw new Error('PDF 写入不完整'); }
    }
    catch { try { fs.unlinkSync(path); } catch {} throw new Error('测试 PDF 保存失败，请检查存储空间'); }
    finally { fs.closeSync(file); }
    return path;
  }

  async getPdfInfo(filePath: string): Promise<PdfDocumentInfo> {
    let size = 0;
    try {
      const stat = fs.statSync(filePath);
      size = stat.size;
    } catch (e) {
      // ignore
    }

    const document = new pdfService.PdfDocument();
    try {
      this.loadDocument(document, filePath);
      const count = document.getPageCount();
      if (count <= 0) { throw new Error('PDF 没有可读页面'); }
      return { filePath: filePath, fileName: filePath.split('/').pop() || 'document.pdf',
        fileSize: size, pageCount: count };
    } finally {
      document.releaseDocument();
    }
  }

  renderPage(filePath: string, pageIndex: number): RenderedPdfPage {
    const document = new pdfService.PdfDocument();
    let page: pdfService.PdfPage | null = null;
    try {
      this.loadDocument(document, filePath);
      if (pageIndex < 0 || pageIndex >= document.getPageCount()) { throw new Error('PDF 页码超出范围'); }
      page = document.getPage(pageIndex);
      const width = page.getWidth();
      const height = page.getHeight();
      if (width <= 0 || height <= 0) { throw new Error('PDF 页面尺寸无效'); }
      const scale = Math.min(1200 / width, 1800 / height);
      const matrix = new pdfService.PdfMatrix();
      matrix.x = 0; matrix.y = 0; matrix.width = Math.max(1, Math.round(width * scale));
      matrix.height = Math.max(1, Math.round(height * scale)); matrix.rotate = 0;
      const pixelMap = page.getCustomPagePixelMap(matrix, false, true);
      return { pixelMap: pixelMap, aspectRatio: width / height };
    } finally {
      if (page !== null) { page.release(); }
      document.releaseDocument();
    }
  }

  private loadDocument(document: pdfService.PdfDocument, filePath: string): void {
    const result = document.loadDocument(filePath);
    if (result === pdfService.ParseResult.PARSE_ERROR_PASSWORD) {
      throw new Error('此 PDF 需要密码，请先解锁后再导入');
    }
    if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
      throw new Error('PDF 无法读取，请检查文件是否损坏或设备是否支持 PDFKit');
    }
  }

  /** Bounded batches keep extraction cancellable; reviewed results alone enter the index. */
  async extractPages(filePath: string, start: number, end: number, scanOcr: boolean,
    cancelled: () => boolean, progress: (page: number) => void): Promise<PdfTextPage[]> {
    if (!Number.isInteger(start) || !Number.isInteger(end) || start < 1 || end < start || end - start >= 30) {
      throw new Error('每次请选择 1～30 页');
    }
    const document = new pdfService.PdfDocument();
    const result: PdfTextPage[] = [];
    try {
      this.loadDocument(document, filePath);
      if (end > document.getPageCount()) { throw new Error('页码超出资料范围'); }
      for (let pageNumber = start; pageNumber <= end; pageNumber++) {
        if (cancelled()) { throw new Error('已取消提取'); }
        progress(pageNumber);
        let page: pdfService.PdfPage | null = null;
        try {
          page = document.getPage(pageNumber - 1);
          let text = page.getTextContent().trim();
          let method: 'text' | 'ocr' = 'text';
          if (!text && scanOcr) {
            const rendered = this.renderPage(filePath, pageNumber - 1);
            try { text = await OcrService.getInstance().recognizePixelMap(rendered.pixelMap); method = 'ocr'; }
            finally { await rendered.pixelMap.release(); }
          }
          if (text.length > 80000) { throw new Error(`第 ${pageNumber} 页文字过多，请缩小页面内容`); }
          result.push({ pageNumber: pageNumber, text: text, method: method, extractedAt: Date.now() });
        } finally { if (page !== null) { page.release(); } }
        // Yield between synchronous PDF calls for cancel/input events on the UI thread.
        await new Promise<void>((resolve) => setTimeout(resolve, 0));
      }
      if (cancelled()) { throw new Error('已取消提取'); }
      return result;
    } finally { document.releaseDocument(); }
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
