import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PdfDocumentService } from '../document/PdfDocumentService';
import { MarkerImportPolicy } from './MarkerImportPolicy';
import { SMART_INPUT_LIMIT } from './SmartExtractService';

export interface DocumentExtractResult { text: string; notice: string; }

/** Bounded local imports. A temporary PDF copy is always released; no cloud upload occurs. */
export class DocumentExtractService {
  static async read(context: Context, uri: string, start: number, end: number,
    cancelled: () => boolean, progress: (page: number) => void): Promise<DocumentExtractResult> {
    let name = uri.split('/').pop() || '';
    try { name = decodeURIComponent(name); } catch { /* Keep an opaque picker name. */ }
    if (cancelled()) { throw new Error('已取消导入'); }
    const handle = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let pdf = false;
    try {
      const size = fs.statSync(handle.fd).size;
      if (size <= 0 || size > 20 * 1024 * 1024) { throw new Error('请选择非空且不超过 20 MB 的文件'); }
      const header = new ArrayBuffer(5); fs.readSync(handle.fd, header);
      const bytes = new Uint8Array(header);
      pdf = bytes[0] === 37 && bytes[1] === 80 && bytes[2] === 68 && bytes[3] === 70 && bytes[4] === 45;
      if (!pdf && size > 1024 * 1024) { throw new Error('文字结果文件最多 1 MB，请分段导出'); }
    } finally { fs.closeSync(handle); }
    if (!pdf) {
      if (!/\.(md|txt|json)$/i.test(name)) { throw new Error('支持 PDF、Markdown、TXT 和 Marker Markdown 响应 JSON'); }
      const raw = await fs.readText(uri);
      if (cancelled()) { throw new Error('已取消导入'); }
      return { text: MarkerImportPolicy.parse(raw, /\.json$/i.test(name)),
        notice: '文字已导入，请校对后整理。Marker 的表格与公式保留在 Markdown 中；配套图片须另外保管。' };
    }
    if (!Number.isInteger(start) || !Number.isInteger(end) || start < 1 || end < start || end - start >= 5) {
      throw new Error('每次提取 1–5 页，请填写正确的 PDF 页范围');
    }
    const service = PdfDocumentService.getInstance();
    const copy = await service.savePdfToSandbox(context, uri, 'smart-extract.pdf');
    try {
      if (cancelled()) { throw new Error('已取消导入'); }
      const pages = await service.extractPages(copy, start, end, true, cancelled, progress);
      const text = pages.map(page => `## 第 ${page.pageNumber} 页\n\n${page.text || '（本页未识别到文字）'}`).join('\n\n');
      if (!pages.some(page => page.text.trim())) { throw new Error('这些页面没有识别到文字，请检查扫描清晰度或使用 Marker 转换结果'); }
      if (text.length > SMART_INPUT_LIMIT) { throw new Error('页面文字过多，请缩小页范围，原输入已保留'); }
      return { text, notice: '使用本机 PDF 文字层与鸿蒙 OCR 提取，请核对阅读顺序、表格、公式及数字；扫描结果未自动视为已校对。' };
    } finally { await service.removeManagedPdf(context, copy); }
  }
}
