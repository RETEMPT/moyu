/**
 * 应用沙箱中的 Markdown 正文文档。
 */
export interface MarkdownDocument {
  id: string;
  title: string;
  fileName: string;
  filePath: string;
  content: string;
  updatedAt: number;
}

export type DocumentTransferStatus = 'imported' | 'exported' | 'unsupported' | 'cancelled' | 'failed';

export interface DocumentTransferResult {
  status: DocumentTransferStatus;
  document?: MarkdownDocument;
  fileName?: string;
  /**
   * 导入后应写入 NoteItem.type 的类型标识（'Markdown' | 'PDF' | 'Doc' …）。
   *
   * 必须由服务层回传：`MarkdownDocument` 本身只有正文与路径，不含类型，
   * 调用方若自行猜测就只能一律填 'Markdown'，导致导入的 PDF 被标成普通笔记，
   * 从而永远走不进 PDF 原盘批注阅读器（ReaderWorkspace 按 type 分流）。
   */
  noteType?: string;
  message: string;
}
