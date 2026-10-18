import { NoteItem } from '../types/NoteItem';

/** Note content and ink are immutable strings; only tags need an independent array. */
export function copyNote(note: NoteItem): NoteItem {
  return { id: note.id, title: note.title, category: note.category, type: note.type, previewText: note.previewText,
    tag: note.tag, tagColor: note.tagColor, updateTime: note.updateTime, contentDetail: note.contentDetail,
    pageInfo: note.pageInfo, extraInfo: note.extraInfo, coverUrl: note.coverUrl, strokes: note.strokes,
    scratchpadStrokes: note.scratchpadStrokes, paperStyle: note.paperStyle, scratchpadPaperStyle: note.scratchpadPaperStyle,
    pageAnnotations: note.pageAnnotations, deletedAt: note.deletedAt, favorite: note.favorite,
    tags: note.tags === undefined ? undefined : note.tags.slice(), createdAt: note.createdAt, updatedAt: note.updatedAt,
    lastReadAt: note.lastReadAt, readPage: note.readPage, isPinned: note.isPinned, sourceUri: note.sourceUri,
    sourceFileName: note.sourceFileName, sourceType: note.sourceType, pageCount: note.pageCount,
    documentMeta: note.documentMeta, pdfTextJson: note.pdfTextJson };
}
