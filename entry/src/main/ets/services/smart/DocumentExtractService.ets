import { SMART_INPUT_LIMIT } from '../../common/constants/ContentLimits';
import { PdfTextPage } from '../../common/types/StudyTypes';
import { PdfDocumentService } from '../document/PdfDocumentService';

export interface PdfExtractionCursor { page: number; offset: number; }
export interface PdfExtractionChunk { text: string; next: PdfExtractionCursor | null; }

/** Use real PDF pages and stop when the editor has enough text or the current scan batch ends. */
export class DocumentExtractService {
  static async readPdf(path: string, pageCount: number, cursor: PdfExtractionCursor, budget: number, scanOcr: boolean,
    cancelled: () => boolean, progress: (page: number) => void): Promise<PdfExtractionChunk> {
    if (budget < 32 || budget > SMART_INPUT_LIMIT) { throw new Error('请先整理当前文字，再继续提取'); }
    if (cursor.page > pageCount) { return { text: '', next: null }; }
    const end = Math.min(pageCount, cursor.page + 11);
    let text = '';
    let next: PdfExtractionCursor | null = null;
    await PdfDocumentService.getInstance().extractPages(path, cursor.page, end, scanOcr, cancelled, progress,
      (page: PdfTextPage): boolean => {
        const offset = page.pageNumber === cursor.page ? cursor.offset : 0;
        const remaining = page.text.slice(offset);
        if (remaining.trim()) {
          const heading = (text ? '\n\n' : '') + `## 第 ${page.pageNumber} 页` + (offset > 0 ? '（续）' : '') + '\n\n';
          const available = budget - text.length - heading.length;
          if (available < 2) { next = { page: page.pageNumber, offset }; return false; }
          let count = Math.min(available, remaining.length);
          if (count < remaining.length) {
            const paragraph = remaining.lastIndexOf('\n', count - 1);
            if (paragraph >= count / 2) { count = paragraph + 1; }
            const unit = remaining.charCodeAt(count - 1);
            if (unit >= 0xD800 && unit <= 0xDBFF) { count--; }
          }
          text += heading + remaining.slice(0, count);
          if (count < remaining.length) { next = { page: page.pageNumber, offset: offset + count }; return false; }
        }
        next = page.pageNumber < pageCount ? { page: page.pageNumber + 1, offset: 0 } : null;
        return true;
      });
    return { text, next };
  }
}
