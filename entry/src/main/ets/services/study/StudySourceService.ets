import { NoteItem } from '../../common/types/NoteItem';
import { PdfTextPage } from '../../common/types/StudyTypes';
import { MarkdownDocument } from '../../common/types/MarkdownDocument';

export class StudySourceService {
  static pages(note: NoteItem): PdfTextPage[] {
    try {
      const rows = JSON.parse(note.pdfTextJson || '[]') as PdfTextPage[];
      if (!Array.isArray(rows)) { return []; }
      const result: PdfTextPage[] = [];
      for (const row of rows) {
        if (row && Number.isInteger(row.pageNumber) && row.pageNumber > 0 &&
          row.pageNumber <= (note.pageCount || 10000) && typeof row.text === 'string' && row.text.length <= 80000 &&
          (row.method === 'text' || row.method === 'ocr') && !result.some((p: PdfTextPage) => p.pageNumber === row.pageNumber)) {
          result.push({ pageNumber: row.pageNumber, text: row.text, method: row.method,
            extractedAt: Number.isFinite(row.extractedAt) ? row.extractedAt : 0 });
        }
      }
      return result.sort((a: PdfTextPage, b: PdfTextPage) => a.pageNumber - b.pageNumber);
    } catch { return []; }
  }

  static documents(notes: NoteItem[]): MarkdownDocument[] {
    const docs: MarkdownDocument[] = [];
    for (const note of notes) {
      docs.push({ id: note.id, title: note.title, fileName: `${note.id}.md`, filePath: '',
        content: note.contentDetail || '', updatedAt: note.updatedAt || 0 });
      for (const page of StudySourceService.pages(note)) {
        if (page.text.trim()) {
          docs.push({ id: note.id, title: note.title, fileName: `${note.id}.pdf`, filePath: '',
            content: page.text, updatedAt: page.extractedAt, pageNumber: page.pageNumber });
        }
      }
    }
    return docs;
  }

  static context(note: NoteItem, limit: number = 16000): string {
    let result = note.contentDetail || '';
    for (const page of StudySourceService.pages(note)) {
      if (result.length >= limit) { break; }
      result += `\n\n【第 ${page.pageNumber} 页 · ${page.method === 'ocr' ? 'OCR 校对文字' : '文字层'}】\n${page.text}`;
    }
    return result.slice(0, limit);
  }

  static merge(note: NoteItem, pages: PdfTextPage[]): string {
    const merged = StudySourceService.pages(note).filter((p: PdfTextPage) =>
      !pages.some((incoming: PdfTextPage) => incoming.pageNumber === p.pageNumber));
    return JSON.stringify(merged.concat(pages).sort((a: PdfTextPage, b: PdfTextPage) => a.pageNumber - b.pageNumber));
  }
}
