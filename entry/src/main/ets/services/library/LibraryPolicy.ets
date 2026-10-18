import { NoteItem } from '../../common/types/NoteItem';
import { StudySourceService } from '../study/StudySourceService';
import { ReadingProgressPolicy, ReadingStatus } from '../document/ReadingProgressPolicy';

export interface LibraryQuery {
  keyword?: string;
  category?: string;
  type?: string;
  tags?: string[];
  status?: ReadingStatus;
  sort?: string;
  ascending?: boolean;
  pinnedFirst?: boolean;
}

/** Shared, immutable query for the library and home shelf. No file reads during rendering. */
export class LibraryPolicy {
  static type(note: NoteItem): string {
    const type = note.type.toLowerCase();
    if (note.sourceType === 'image' || type === 'image') { return '图片'; }
    if (note.sourceType === 'pdf' || type === 'pdf') { return 'PDF'; }
    if (['handwriting', 'canvas', '白板', '白纸笔记', '稿纸'].includes(type)) { return '手写'; }
    if (['doc', 'docx', 'word'].includes(type)) { return 'Word'; }
    return ['markdown', 'text', 'md', 'txt'].includes(type) ? 'Markdown' : note.type;
  }

  static tags(note: NoteItem): string[] {
    const values: string[] = [note.tag || ''].concat(note.tags || []);
    const result: string[] = [];
    for (const value of values) {
      const tag = value.trim();
      if (tag.length > 0 && !result.includes(tag)) { result.push(tag); }
    }
    return result;
  }

  static availableTags(notes: NoteItem[]): string[] {
    const values: Set<string> = new Set();
    for (const note of notes) { LibraryPolicy.tags(note).forEach((tag: string) => values.add(tag)); }
    return Array.from(values).sort((a: string, b: string) => a.localeCompare(b));
  }

  static query(notes: NoteItem[], options: LibraryQuery): NoteItem[] {
    const keyword = (options.keyword || '').trim().toLowerCase();
    const tagQuery = keyword.startsWith('#') && keyword.length > 1;
    const result = notes.filter((note: NoteItem): boolean => {
      if (note.deletedAt || (options.category && note.category !== options.category)) { return false; }
      if (options.type && options.type !== '全部' && LibraryPolicy.type(note) !== options.type) { return false; }
      if (options.status && options.status !== 'all' && ReadingProgressPolicy.status(note) !== options.status) { return false; }
      const tags = LibraryPolicy.tags(note);
      if (options.tags && options.tags.length && !options.tags.some((tag: string) => tags.includes(tag))) { return false; }
      if (!keyword) { return true; }
      if (tagQuery) { return tags.some((tag: string) => tag.toLowerCase().includes(keyword.substring(1))); }
      if ([note.title, note.previewText, note.category, note.contentDetail].some((text: string) => (text || '').toLowerCase().includes(keyword)) ||
        tags.some((tag: string) => tag.toLowerCase().includes(keyword))) { return true; }
      return StudySourceService.pages(note).some((page) => page.text.toLowerCase().includes(keyword));
    });
    result.sort((a: NoteItem, b: NoteItem): number => {
      if (options.pinnedFirst && (a.isPinned === true) !== (b.isPinned === true)) { return a.isPinned === true ? -1 : 1; }
      let compared: number = 0;
      if (options.sort === 'title') { compared = a.title.localeCompare(b.title); }
      else if (options.sort === 'create') { compared = LibraryPolicy.time(a.createdAt) - LibraryPolicy.time(b.createdAt); }
      else if (options.sort === 'read') { compared = LibraryPolicy.time(a.lastReadAt) - LibraryPolicy.time(b.lastReadAt); }
      else { compared = LibraryPolicy.time(a.updatedAt) - LibraryPolicy.time(b.updatedAt); }
      if (compared !== 0) { return options.ascending ? compared : -compared; }
      return a.id.localeCompare(b.id);
    });
    return result;
  }

  private static time(value: number | undefined): number { return Number.isFinite(value) ? value || 0 : 0; }
}
