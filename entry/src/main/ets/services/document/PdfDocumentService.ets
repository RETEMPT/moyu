/**
 * PDF 真实文档管理服务 (PdfDocumentService)
 *
 * 负责：
 *   1. 原始 PDF 文件在沙箱内的持久化复制与管理 (files/documents/)
 *   2. 读取 PDF 元数据、页数与页面尺寸
 *   3. 页面模型动态加载：与 HarmonyOS PDF Kit 架构对接
 *   4. 原文失败时报告错误；示例页面仅用于明确标注的演示资料
 */
import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';
import { PdfPageModel } from '../../common/types/PdfAnnotationTypes';

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
    const destPath: string = `${docDir}/${Date.now()}_${sanitizedName}`;

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
   * 解析 PDF 真实页数与基本元信息
   */
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
        sections: [
          {
            type: 'header',
            title: i === 0 ? `《${title}》· 核心研读` : `第 ${i + 1} 部分 · 要点深研`,
            text: i === 0
              ? '请在下方文档正文中进行划线、荧光高亮或使用手写笔直接演算。'
              : '本页包含推导公式、关键结论与对应习题，可在答题留白区直接作答。'
          },
          {
            type: 'question',
            tag: i % 2 === 0 ? '重点考点 · 原理分析' : '推导计算 · 核心考查',
            score: `${(i + 1) * 5}分`,
            text: `[第 ${i + 1} 页核心内容]\n1. 重点研读定理及推导公式；\n2. 结合左侧文档结构与右侧 AI 伴读展开精读分析。`
          },
          {
            type: 'blank',
            text: '【手写演算与批注专区】请在此处落笔书写解题思路与要点草稿...'
          }
        ]
      });
    }
    return pages;
  }
}
