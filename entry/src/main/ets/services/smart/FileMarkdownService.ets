import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { SMART_INPUT_LIMIT } from '../../common/constants/ContentLimits';
import { OfficeDocumentService } from '../document/OfficeDocumentService';
import { PdfDocumentService } from '../document/PdfDocumentService';
import { TextDocumentService } from '../document/TextDocumentService';
import { OcrService } from '../ocr/OcrService';
import { DocumentExtractService, PdfExtractionChunk, PdfExtractionCursor } from './DocumentExtractService';
import { LocalTextFormatter } from './LocalTextFormatter';
import { TextImportPolicy } from './TextImportPolicy';

export interface FileMarkdown { title: string; markdown: string; }

export class FileMarkdownService {
  static readonly MAX_TEXT: number = 600000;

  static async read(context: common.UIAbilityContext, uri: string, cancelled: () => boolean,
    progress: (message: string) => void): Promise<FileMarkdown> {
    const name = new fileUri.FileUri(uri).name;
    const suffix = (name.match(/\.[^.]+$/)?.[0] || '').toLowerCase();
    const title = name.slice(0, name.length - suffix.length).replace(/[\r\n]/g, ' ').trim() || '识别文稿';
    const imageFile = ['.png', '.jpg', '.jpeg', '.webp', '.bmp', '.heic', '.heif'].includes(suffix);
    let text: string;
    if (imageFile) {
      progress('正在识别图片文字…');
      text = await OcrService.getInstance().recognizeTextFromUri(uri);
    } else if (suffix === '.pdf') {
      text = await FileMarkdownService.pdf(context, uri, cancelled, progress);
    } else if (suffix === '.docx' || suffix === '.pptx') {
      progress('正在读取文档…');
      text = await OfficeDocumentService.read(uri, suffix === '.pptx');
    } else if (['.txt', '.md', '.markdown'].includes(suffix)) {
      progress('正在读取文字…');
      text = TextImportPolicy.parse(await TextDocumentService.read(uri, FileMarkdownService.MAX_TEXT * 4), FileMarkdownService.MAX_TEXT);
    } else { throw new Error('暂不支持这种文件。请选择图片、PDF、文字、DOCX 或 PPTX。'); }
    if (cancelled()) { throw new Error('已取消识别'); }
    return { title, markdown: FileMarkdownService.format(text, title, suffix, imageFile) };
  }

  static format(text: string, title: string, suffix: string, imageFile: boolean = false): string {
    if (text.includes('\u0000')) { throw new Error('文字编码无法识别，请另存为 UTF-8 后重新选择'); }
    if (!text.trim()) { throw new Error('没有发现可转换的文字'); }
    if (text.length > FileMarkdownService.MAX_TEXT) { throw new Error('文字超过 60 万字，请分段后再识别'); }
    return suffix === '.md' || suffix === '.markdown' ? LocalTextFormatter.normalize(text) :
      LocalTextFormatter.format(text, title, 'study', imageFile);
  }

  private static async pdf(context: common.UIAbilityContext, uri: string, cancelled: () => boolean,
    progress: (message: string) => void): Promise<string> {
    const service = PdfDocumentService.getInstance();
    const copy = await service.copyPdfToSandbox(context, uri, (message: string) => {
      if (cancelled()) { throw new Error('已取消识别'); }
      progress(message);
    });
    try {
      const info = await service.getPdfInfo(copy.path, cancelled);
      const ocr = OcrService.isHardwareSupported();
      const chunks: string[] = [];
      let length = 0;
      let cursor: PdfExtractionCursor | null = { page: 1, offset: 0 };
      while (cursor) {
        if (cancelled()) { throw new Error('已取消识别'); }
        const chunk: PdfExtractionChunk = await DocumentExtractService.readPdf(copy.path, info.pageCount, cursor, SMART_INPUT_LIMIT, ocr,
          cancelled, (page: number) => progress(`正在识别第 ${page} / ${info.pageCount} 页…`));
        if (chunk.text) {
          length += chunk.text.length + 2;
          if (length > FileMarkdownService.MAX_TEXT) { throw new Error('PDF 文字超过 60 万字，请分段后再识别'); }
          chunks.push(chunk.text);
        }
        cursor = chunk.next;
      }
      if (!chunks.length && !ocr) { throw new Error('PDF 没有文字层，当前设备不支持扫描页识别'); }
      return chunks.join('\n\n');
    } finally {
      try { await service.removeManagedPdf(context, copy.path); } catch { console.warn('识别临时 PDF 清理失败'); }
    }
  }
}
