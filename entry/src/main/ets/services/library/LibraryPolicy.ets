import { FILTER_ALL } from '../../common/constants/WorkspaceConstants';
import { NoteItem } from '../../common/types/NoteItem';
import { StudySourceService } from '../study/StudySourceService';
import { ReadingProgressPolicy, ReadingStatus } from '../document/ReadingProgressPolicy';
import { SourceTextStructure } from '../document/SourceTextStructure';
import { NoteTagPresentation } from './NoteTagPresentation';

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
  static tagKey(tag: string): string { return tag.trim().replace(/^#(?=\S)/, '').toLowerCase(); }

  static type(note: NoteItem): string {
    const type = note.type.toLowerCase();
    if (note.sourceType === 'image' || type === 'image') { return '图片'; }
    if (note.sourceType === 'pdf' || type === 'pdf') { return 'PDF'; }
    if (['handwriting', 'canvas', '白板', '白纸笔记', '稿纸'].includes(type)) { return '手写'; }
    if (['doc', 'docx', 'word'].includes(type)) { return 'Word'; }
    return ['markdown', 'text', 'md', 'txt'].includes(type) ? 'Markdown' : note.type;
  }

  static tags(note: NoteItem): string[] {
    const tags = note.tags || [];
    const legacy = (note.tag || '').trim();
    // Older smart notes also stored the complete tag list in the single-tag field.
    const values = tags.length > 1 && legacy === tags.join(', ') ? tags : [legacy].concat(tags);
    const result: string[] = [];
    const seen = new Set<string>();
    for (const value of values) {
      const tag = value.trim().replace(/^#(?=\S)/, '');
      if (tag.length > 0 && !seen.has(tag.toLowerCase())) { seen.add(tag.toLowerCase()); result.push(tag); }
    }
    const source = note.contentDetail || note.previewText || '';
    if (!/(?:^|\s)#[^\s#]/.test(source) || LibraryPolicy.type(note) !== 'Markdown') { return result; }
    const pattern = NoteTagPresentation.bodyTokens();
    for (const row of SourceTextStructure.scan(source)) {
      if (row.kind === 'code' || row.kind === 'math' || !row.text.includes('#')) { continue; }
      pattern.lastIndex = 0;
      let match = pattern.exec(row.text);
      while (match) {
        const tag = match[7];
        if (tag !== undefined && !seen.has(tag.toLowerCase())) {
          seen.add(tag.toLowerCase());
          result.push(tag);
        }
        match = pattern.exec(row.text);
      }
    }
    return result;
  }

  static availableTags(notes: NoteItem[], category: string = '', type: string = ''): string[] {
    const values = new Map<string, string>();
    for (const note of notes) {
      if (!LibraryPolicy.inScope(note, category, type)) { continue; }
      for (const tag of LibraryPolicy.tags(note)) {
        const key = LibraryPolicy.tagKey(tag);
        if (!values.has(key)) { values.set(key, tag); }
      }
    }
    return Array.from(values.values()).sort((a: string, b: string) => a.localeCompare(b));
  }

  private static inScope(note: NoteItem, category: string, type: string): boolean {
    return !note.deletedAt && (!category || note.category === category) &&
      (!type || type === FILTER_ALL || LibraryPolicy.type(note) === type);
  }

  static query(notes: NoteItem[], options: LibraryQuery): NoteItem[] {
    const keyword = (options.keyword || '').trim().toLowerCase();
    const tagQuery = keyword.startsWith('#') && keyword.length > 1;
    const tagText = tagQuery ? keyword.substring(1) : keyword;
    const selectedTags = new Set((options.tags || []).map((tag: string) => LibraryPolicy.tagKey(tag)));
    const result = notes.filter((note: NoteItem): boolean => {
      if (!LibraryPolicy.inScope(note, options.category || '', options.type || '')) { return false; }
      if (options.status && options.status !== 'all' && ReadingProgressPolicy.status(note) !== options.status) { return false; }
      const textMatches = !keyword || (!tagQuery && [note.title, note.previewText, note.category, note.contentDetail]
        .some((text: string) => (text || '').toLowerCase().includes(keyword)));
      if (textMatches && selectedTags.size === 0) { return true; }
      const tags = LibraryPolicy.tags(note).map((tag: string) => LibraryPolicy.tagKey(tag));
      if (selectedTags.size > 0 && !tags.some((tag: string) => selectedTags.has(tag))) { return false; }
      return textMatches || tags.some((tag: string) => tag.includes(tagText)) ||
        (!tagQuery && StudySourceService.pages(note).some((page) => page.text.toLowerCase().includes(keyword)));
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
