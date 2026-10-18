import { NoteItem } from '../../common/types/NoteItem';
import { LibraryPolicy } from './LibraryPolicy';

export interface MemoDay { key: string; day: number; count: number; inMonth: boolean; }
export interface MemoTagCount { tag: string; count: number; }

/** Local calendar dates and tags are derived from the same text-only feed. */
export class MemoFeedPolicy {
  static dateKey(time: number): string {
    if (!Number.isFinite(time) || time <= 0) { return ''; }
    const date = new Date(time);
    if (!Number.isFinite(date.getTime())) { return ''; }
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }
  static query(notes: NoteItem[], date: string = '', tag: string = '', pinned: boolean = false): NoteItem[] {
    return LibraryPolicy.query(notes, { type: 'Markdown', sort: 'create', ascending: false, pinnedFirst: false,
      tags: tag ? [tag] : [] }).filter((note: NoteItem) =>
      (!date || MemoFeedPolicy.dateKey(note.createdAt || 0) === date) && (!pinned || note.isPinned === true));
  }
  static tags(notes: NoteItem[]): MemoTagCount[] {
    const counts = new Map<string, number>();
    MemoFeedPolicy.query(notes).forEach((note: NoteItem) => {
      LibraryPolicy.tags(note).forEach((tag: string) => counts.set(tag, (counts.get(tag) || 0) + 1));
    });
    const tags: MemoTagCount[] = [];
    counts.forEach((count: number, tag: string) => tags.push({ tag, count }));
    return tags.sort((a: MemoTagCount, b: MemoTagCount) => b.count - a.count || a.tag.localeCompare(b.tag));
  }
  static month(notes: NoteItem[], year: number, month: number): MemoDay[] {
    const counts = new Map<string, number>();
    MemoFeedPolicy.query(notes).forEach((note: NoteItem) => {
      const key = MemoFeedPolicy.dateKey(note.createdAt || 0);
      if (key) { counts.set(key, (counts.get(key) || 0) + 1); }
    });
    const start = new Date(year, month, 1);
    const result: MemoDay[] = [];
    const days = Math.ceil((start.getDay() + new Date(year, month + 1, 0).getDate()) / 7) * 7;
    for (let i = 0; i < days; i++) {
      const date = new Date(year, month, i - start.getDay() + 1);
      const key = MemoFeedPolicy.dateKey(date.getTime());
      result.push({ key, day: date.getDate(), count: counts.get(key) || 0, inMonth: date.getMonth() === month });
    }
    return result;
  }
}
