import { NoteItem } from '../../common/types/NoteItem';
import { LibraryPolicy } from './LibraryPolicy';
import { SourceTextStructure } from '../document/SourceTextStructure';
import { NoteTagPresentation } from './NoteTagPresentation';

export interface MemoDay { key: string; day: number; count: number; inMonth: boolean; }
export interface MemoTagCount { tag: string; count: number; }
type MemoExcerptKind = 'text' | 'reference';
export interface MemoExcerptPart { text: string; kind: MemoExcerptKind; }

/** The date feed includes text notes and imported documents. */
export class MemoFeedPolicy {
  static cardTags(note: NoteItem): string[] {
    return LibraryPolicy.tags(note).slice(0, 8);
  }

  static excerpt(note: NoteItem): MemoExcerptPart[] {
    if (LibraryPolicy.type(note) !== 'Markdown') {
      return [{ text: note.pageInfo || note.previewText || LibraryPolicy.type(note), kind: 'text' }];
    }
    const footerTags = MemoFeedPolicy.cardTags(note);
    const source = NoteTagPresentation.displayBody(note.contentDetail || note.previewText || '', footerTags).slice(0, 1600).trim();
    const rows = SourceTextStructure.scan(source);
    const first = rows[0]?.text.replace(/^#{1,6}\s+/, '');
    const parts: MemoExcerptPart[] = [];
    let remaining = 260;
    const append = (text: string, kind: MemoExcerptKind): void => {
      if (!text || remaining <= 0) { return; }
      const previous = parts[parts.length - 1];
      let value = text.replace(/\s+/g, ' ');
      if (!previous || previous.text.endsWith(' ')) { value = value.trimStart(); }
      value = value.slice(0, remaining).replace(/[\uD800-\uDBFF]$/, '');
      if (!value) { return; }
      remaining -= value.length;
      if (previous && previous.kind === 'text' && kind === 'text') { previous.text += value; }
      else { parts.push({ text: value, kind }); }
    };
    for (let index = first === NoteTagPresentation.displayTitle(note.title || '', footerTags) ? 1 : 0;
      index < rows.length && remaining > 0; index++) {
      const row = rows[index];
      if (row.kind === 'blank' || row.kind === 'divider') { continue; }
      if (parts.length > 0) { append(' ', 'text'); }
      if (row.kind === 'code' || row.kind === 'math') { append(row.text.trim(), 'text'); continue; }
      const line = row.text.trim().replace(/^(?:#{1,6}\s+|>\s?|[-*+]\s+|\d+\.\s+)/, '');
      const tokens = NoteTagPresentation.bodyTokens();
      let start = 0;
      let match = tokens.exec(line);
      while (match && remaining > 0) {
        append(MemoFeedPolicy.cleanExcerptText(line.slice(start, match.index)), 'text');
        if (match[2] !== undefined) { append(match[2], 'text'); }
        else if (match[3] !== undefined) { append(match[4]?.trim() || match[3].trim(), 'reference'); }
        else if (match[5] !== undefined) { append(match[5], 'text'); }
        else if (match[7] === undefined) { append(match[0], 'text'); }
        start = tokens.lastIndex;
        match = tokens.exec(line);
      }
      append(MemoFeedPolicy.cleanExcerptText(line.slice(start)), 'text');
    }
    if (parts.length) { parts[parts.length - 1].text = parts[parts.length - 1].text.trimEnd(); }
    return parts;
  }

  private static cleanExcerptText(text: string): string {
    return text.replace(/\*\*([^*]+)\*\*|__([^_]+)__/g, '$1$2').replace(/\*([^*]+)\*/g, '$1');
  }

  static dateKey(time: number): string {
    if (!Number.isFinite(time) || time <= 0) { return ''; }
    const date = new Date(time);
    if (!Number.isFinite(date.getTime())) { return ''; }
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }
  static query(notes: NoteItem[], date: string = '', tag: string = '', pinned: boolean = false): NoteItem[] {
    const tagKey = LibraryPolicy.tagKey(tag);
    return LibraryPolicy.query(notes, { sort: 'create', ascending: false, pinnedFirst: false }).filter((note: NoteItem) => {
      const type = LibraryPolicy.type(note);
      return (type === 'Markdown' || type === 'PDF' || type === '图片') &&
        (!date || MemoFeedPolicy.dateKey(note.createdAt || note.updatedAt || 0) === date) &&
        (!pinned || note.isPinned === true) && (!tagKey ||
          MemoFeedPolicy.cardTags(note).some((value: string) => LibraryPolicy.tagKey(value) === tagKey));
    });
  }
  static tags(notes: NoteItem[]): MemoTagCount[] {
    const counts = new Map<string, MemoTagCount>();
    MemoFeedPolicy.query(notes).forEach((note: NoteItem) => {
      MemoFeedPolicy.cardTags(note).forEach((tag: string) => {
        const key = LibraryPolicy.tagKey(tag);
        const previous = counts.get(key);
        counts.set(key, { tag: previous?.tag || tag, count: (previous?.count || 0) + 1 });
      });
    });
    return Array.from(counts.values()).sort((a: MemoTagCount, b: MemoTagCount) => b.count - a.count || a.tag.localeCompare(b.tag));
  }
  static month(notes: NoteItem[], year: number, month: number): MemoDay[] {
    const counts = new Map<string, number>();
    MemoFeedPolicy.query(notes).forEach((note: NoteItem) => {
      const key = MemoFeedPolicy.dateKey(note.createdAt || note.updatedAt || 0);
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
