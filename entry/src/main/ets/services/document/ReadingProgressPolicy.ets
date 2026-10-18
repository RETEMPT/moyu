import { NoteItem } from '../../common/types/NoteItem';

export type ReadingStatus = 'all' | 'unread' | 'reading' | 'finished';

/** Reading activity is independent of edits, favorites and annotation timestamps. */
export class ReadingProgressPolicy {
  static hasRead(note: NoteItem): boolean {
    return Number.isFinite(note.lastReadAt) && (note.lastReadAt || 0) > 0;
  }

  static page(note: NoteItem): number {
    const total = Number.isInteger(note.pageCount) && (note.pageCount || 0) > 0 ? note.pageCount || 1 : 1;
    const saved = Number.isInteger(note.readPage) && (note.readPage || 0) > 0 ? note.readPage || 1 : 1;
    return Math.min(saved, total);
  }

  static status(note: NoteItem): ReadingStatus {
    if (!ReadingProgressPolicy.hasRead(note)) { return 'unread'; }
    return (note.pageCount || 0) > 1 && ReadingProgressPolicy.page(note) === note.pageCount ? 'finished' : 'reading';
  }

  static label(note: NoteItem): string {
    if (!ReadingProgressPolicy.hasRead(note)) { return '未打开'; }
    if ((note.pageCount || 0) > 0 && Number.isInteger(note.readPage) && (note.readPage || 0) > 0) {
      return `第 ${ReadingProgressPolicy.page(note)} / ${note.pageCount} 页`;
    }
    return '最近打开';
  }

  static latest(notes: NoteItem[]): NoteItem | null {
    let latest: NoteItem | null = null;
    for (const note of notes) {
      if (!note.deletedAt && ReadingProgressPolicy.hasRead(note) &&
        (latest === null || (note.lastReadAt || 0) > (latest.lastReadAt || 0))) { latest = note; }
    }
    return latest;
  }
}
