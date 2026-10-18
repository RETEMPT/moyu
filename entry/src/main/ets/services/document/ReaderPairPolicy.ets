import { NoteItem } from '../../common/types/NoteItem';

export interface ReaderPair { primaryId: string; secondaryId: string; }

/** Two distinct supported documents retain independent source files and save ownership. */
export class ReaderPairPolicy {
  static isPdf(note: NoteItem): boolean {
    return !note.deletedAt && note.sourceType !== 'image' && note.sourceType !== 'doc' && (note.sourceType === 'pdf' || note.type.toLowerCase() === 'pdf');
  }
  static isMarkdown(note: NoteItem): boolean {
    return !note.deletedAt && !['pdf', 'image', 'doc'].includes(note.sourceType || '') &&
      ['markdown', 'md', 'text', 'txt', '笔记'].includes(note.type.toLowerCase());
  }
  static isReadable(note: NoteItem): boolean {
    return !note.deletedAt && (ReaderPairPolicy.isPdf(note) || ReaderPairPolicy.isMarkdown(note) ||
      note.sourceType === 'image' || ['image', 'canvas', 'handwriting', '白板', '白纸笔记', '稿纸'].includes(note.type.toLowerCase()));
  }
  static pair(first: NoteItem, second: NoteItem): ReaderPair {
    if (first.id === second.id) { throw new Error('请选择另一份资料'); }
    if (!ReaderPairPolicy.isReadable(first) || !ReaderPairPolicy.isReadable(second)) { throw new Error('资料格式暂不支持阅读'); }
    return { primaryId: first.id, secondaryId: second.id };
  }
  static rememberTabs(ids: string[], primaryId: string, secondaryId: string): string[] {
    const tabs: string[] = [];
    for (const id of ids.concat([primaryId, secondaryId])) { if (!tabs.includes(id)) { tabs.push(id); } }
    while (tabs.length > 8) {
      const oldest = tabs.findIndex((id: string) => id !== primaryId && id !== secondaryId);
      if (oldest < 0) { break; }
      tabs.splice(oldest, 1);
    }
    return tabs;
  }
  static candidates(notes: NoteItem[], source: NoteItem, keyword: string): NoteItem[] {
    const query = keyword.trim().toLowerCase();
    return notes.filter((note: NoteItem) => note.id !== source.id &&
      ReaderPairPolicy.isReadable(source) && ReaderPairPolicy.isReadable(note) &&
      (!query || `${note.title} ${note.category}`.toLowerCase().includes(query)))
      .sort((left: NoteItem, right: NoteItem) => (right.updatedAt || 0) - (left.updatedAt || 0) || left.id.localeCompare(right.id));
  }
}
