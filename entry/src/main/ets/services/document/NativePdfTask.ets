import { fileIo as fs } from '@kit.CoreFileKit';
import { pdfService } from '@kit.PDFKit';
import { image } from '@kit.ImageKit';

export interface NativePdfResult {
  pageCount: number;
  fileSize: number;
  pixelMap?: image.PixelMap;
  aspectRatio?: number;
  text?: string;
  texts?: string[];
}

/** All PDFKit objects are created, used and released on this background thread. */
@Concurrent
export function readNativePdf(filePath: string, action: string, pageIndex: number, endPage: number = -1): NativePdfResult {
  let size = 0;
  try { size = fs.statSync(filePath).size; } catch { /* Report the same missing-source action. */ }
  if (!filePath || size <= 0) { throw new Error('PDF 原文件不存在或不可读，请重新关联原 PDF。'); }
  const document = new pdfService.PdfDocument();
  try {
    const parsed = document.loadDocument(filePath);
    if (parsed === pdfService.ParseResult.PARSE_ERROR_PASSWORD) { throw new Error('此 PDF 需要密码，请先解锁后再导入'); }
    if (parsed !== pdfService.ParseResult.PARSE_SUCCESS) { throw new Error('PDF 无法读取：内容损坏或格式不受支持'); }
    const count = document.getPageCount();
    if (!Number.isInteger(count) || count <= 0 || count > 10000) { throw new Error('PDF 页数无效或超过 10000 页'); }
    const result: NativePdfResult = { pageCount: count, fileSize: size };
    if (action === 'info') { return result; }
    if (action === 'texts') {
      const first = pageIndex;
      const last = endPage >= first ? endPage : first;
      if (!Number.isInteger(first) || !Number.isInteger(last) || first < 0 || last >= count || last - first >= 30) {
        throw new Error('PDF 页码超出范围');
      }
      const texts: string[] = [];
      for (let index = first; index <= last; index++) {
        const page = document.getPage(index);
        try {
          const text = page.getTextContent().trim();
          if (text.length > 80000) { throw new Error(`第 ${index + 1} 页文字过多，请缩小页面内容`); }
          texts.push(text);
        } finally { page.release(); }
      }
      result.texts = texts;
      return result;
    }
    // 'cover' validates an import and returns page 1's bitmap in the same parse, so opening
    // the new note does not have to parse the whole file again on the UI-critical path.
    const index = action === 'cover' ? 0 : pageIndex;
    if (!Number.isInteger(index) || index < 0 || index >= count) { throw new Error('PDF 页码超出范围'); }
    const page = document.getPage(index);
    try {
      if (action === 'text') {
        const text = page.getTextContent().trim();
        if (text.length > 80000) { throw new Error(`第 ${pageIndex + 1} 页文字过多，请缩小页面内容`); }
        result.text = text;
        return result;
      }
      const width = page.getWidth();
      const height = page.getHeight();
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
        throw new Error('PDF 页面尺寸无效');
      }
      const scale = Math.min(1200 / width, 1800 / height);
      const matrix = new pdfService.PdfMatrix();
      matrix.x = 0; matrix.y = 0; matrix.rotate = 0;
      matrix.width = Math.max(1, Math.round(width * scale));
      matrix.height = Math.max(1, Math.round(height * scale));
      result.pixelMap = page.getCustomPagePixelMap(matrix, false, true);
      result.aspectRatio = width / height;
      return result;
    } finally { page.release(); }
  } finally { document.releaseDocument(); }
}
