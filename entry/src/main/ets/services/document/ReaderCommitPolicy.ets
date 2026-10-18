import { NoteItem } from '../../common/types/NoteItem';
import { ReaderSaveKind } from '../../common/types/ReaderSaveKind';
import { copyNote } from '../../common/utils/NoteSnapshot';
import { ReadingProgressPolicy } from './ReadingProgressPolicy';

/** Pure field ownership policy; persistence and publication belong to the commit service. */
export class ReaderCommitPolicy {
  static merge(current: NoteItem, input: NoteItem, kind: ReaderSaveKind, now: number): NoteItem {
    if (!['markdown', 'pdf', 'pdf-source', 'handwriting', 'scratchpad', 'reading'].includes(kind)) { throw new Error('不支持的资料保存类型'); }
    const result = copyNote(current);
    if (kind === 'reading') {
      if (ReadingProgressPolicy.hasRead(input) && (input.lastReadAt || 0) >= (current.lastReadAt || 0)) {
        result.lastReadAt = input.lastReadAt;
        if (Number.isInteger(input.readPage) && (input.readPage || 0) > 0) {
          result.readPage = input.readPage;
          result.readPage = ReadingProgressPolicy.page(result);
        }
      }
      return result;
    }
    if (kind === 'markdown') { result.title = input.title; result.contentDetail = input.contentDetail; result.previewText = input.previewText; }
    else if (kind === 'pdf') { result.pageAnnotations = input.pageAnnotations; }
    else if (kind === 'pdf-source') {
      result.sourceUri = input.sourceUri; result.sourceFileName = input.sourceFileName; result.sourceType = input.sourceType;
      result.pageCount = input.pageCount; result.type = input.type; result.pdfTextJson = input.pdfTextJson;
      result.pageInfo = input.pageInfo; result.documentMeta = input.documentMeta;
    }
    else if (kind === 'scratchpad') { result.scratchpadStrokes = input.scratchpadStrokes; result.scratchpadPaperStyle = input.scratchpadPaperStyle; }
    else {
      result.strokes = input.strokes;
      result.paperStyle = input.paperStyle;
      const type = current.type.toLowerCase();
      if (['canvas', '白板', '白纸笔记', 'handwriting', '稿纸'].includes(type)) {
        result.title = input.title; result.contentDetail = input.contentDetail; result.previewText = input.previewText;
      }
    }
    result.updateTime = input.updateTime; result.updatedAt = now;
    if (result.createdAt === undefined) { result.createdAt = result.updatedAt; }
    return result;
  }
}
