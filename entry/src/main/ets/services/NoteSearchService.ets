import { Context } from '@kit.AbilityKit';
import { LinkGraph, Backlink, UnresolvedLink } from '../common/types/LinkGraph';
import { MarkdownDocument } from '../common/types/MarkdownDocument';
import { MarkdownParseResult } from '../common/types/MarkdownParseResult';
import { NoteItem } from '../common/types/NoteItem';
import { NoteSearchResult } from '../common/types/NoteSearchResult';
import { NoteStorageService } from './NoteStorageService';
import { MarkdownParserService } from './MarkdownParserService';
import { StudySourceService } from './study/StudySourceService';

export interface NoteSearchOptions {
  cancelled?: () => boolean;
  onUnreadable?: (noteId: string) => void;
}
interface RankedSearchResult { result: NoteSearchResult; rank: number; order: number; }

export class NoteSearchService {
  private readonly storage: NoteStorageService;
  private readonly parser: MarkdownParserService;

  constructor(storage: NoteStorageService = new NoteStorageService(),
    parser: MarkdownParserService = new MarkdownParserService()) {
    this.storage = storage;
    this.parser = parser;
  }

  async search(context: Context, notes: NoteItem[], query: string, useRegex: boolean = false,
    options: NoteSearchOptions = {}): Promise<NoteSearchResult[]> {
    const trimmedQuery: string = query.trim();
    if (trimmedQuery.length === 0) {
      return [];
    }
    const normalizedQuery: string = trimmedQuery.toLocaleLowerCase();
    // A malformed expression is a correctable input error, not an empty library.
    let regex: RegExp | null = null;
    if (useRegex) {
      try {
        regex = new RegExp(trimmedQuery, 'i');
      } catch (error) {
        throw new Error('正则表达式无效，请检查括号和转义，或关闭正则模式。');
      }
    }
    const results: RankedSearchResult[] = [];
    let next = 0;
    const active = (): boolean => !options.cancelled || !options.cancelled();
    const worker = async (): Promise<void> => {
      while (active() && next < notes.length) {
        const order = next++; const note = notes[order];
        let document: MarkdownDocument;
        try { document = await this.storage.read(context, note); }
        catch {
          if (!active()) { return; }
          if (options.onUnreadable) { options.onUnreadable(note.id); }
          // Title, tags and corrected PDF pages remain usable when one Markdown file is unreadable.
          document = { id: note.id, title: note.title, fileName: `${note.id}.md`, filePath: '', content: '', updatedAt: note.updatedAt || 0 };
        }
        if (!active()) { return; }
        const parsed: MarkdownParseResult = this.parser.parse(document);
        const titleMatch: boolean = this.matches(note.title, normalizedQuery, regex);
        const bodyMatch = this.matches(document.content, normalizedQuery, regex);
        const pageMatch = StudySourceService.pages(note).find((page) => this.matches(page.text, normalizedQuery, regex));
        const contentMatch: boolean = bodyMatch || pageMatch !== undefined;
        const matchedTags: string[] = [];
        const tags = parsed.tags.map(tag => tag.value).concat(note.tags || [], (note.tag || '').split(/[,，]/));
        for (const tag of tags) {
          const value = tag.trim();
          if (value && this.matches(value, normalizedQuery, regex) && matchedTags.indexOf(value) < 0) {
            matchedTags.push(value);
          }
        }
        if (titleMatch || contentMatch || matchedTags.length > 0) {
          const result: NoteSearchResult = {
            noteId: note.id,
            title: parsed.title,
            fileName: document.fileName,
            matchedTitle: titleMatch,
            matchedContent: contentMatch,
            matchedTags,
            preview: this.preview(!bodyMatch && pageMatch ? pageMatch.text : document.content, normalizedQuery, regex),
            pageNumber: !bodyMatch && pageMatch ? pageMatch.pageNumber : undefined
          };
          const exactTitle = !useRegex && note.title.trim().toLocaleLowerCase() === normalizedQuery;
          results.push({ result, order, rank: exactTitle ? 4 : titleMatch ? 3 : matchedTags.length > 0 ? 2 : 1 });
        }
      }
    };
    // Bounded asynchronous reads keep an old request from monopolizing the library or file handles.
    const workers: Promise<void>[] = [];
    for (let index = 0; index < Math.min(4, notes.length); index++) { workers.push(worker()); }
    await Promise.all(workers);
    if (!active()) { return []; }
    return results.sort((a: RankedSearchResult, b: RankedSearchResult) => b.rank - a.rank || a.order - b.order)
      .map((entry: RankedSearchResult) => entry.result);
  }

  /** 统一匹配：正则模式用 regex.test，否则用大小写不敏感的子串包含 */
  private matches(text: string, normalizedQuery: string, regex: RegExp | null): boolean {
    if (regex !== null) {
      return regex.test(text);
    }
    return text.toLocaleLowerCase().includes(normalizedQuery);
  }

  async buildLinkGraph(context: Context, notes: NoteItem[], cancelled: () => boolean = () => false): Promise<LinkGraph> {
    const documents: MarkdownDocument[] = [];
    const targets = new Map<string, NoteItem>();
    for (const note of notes) {
      if (cancelled()) { return { backlinks: [], unresolvedLinks: [] }; }
      documents.push(await this.readDocument(context, note));
      for (const alias of [note.id, note.title, `${note.id}.md`]) {
        const key = alias.trim().toLocaleLowerCase();
        if (key && !targets.has(key)) { targets.set(key, note); }
      }
    }
    const backlinks: Backlink[] = [];
    const unresolvedLinks: UnresolvedLink[] = [];
    for (const document of documents) {
      if (cancelled()) { return { backlinks: [], unresolvedLinks: [] }; }
      const parsed: MarkdownParseResult = this.parser.parse(document);
      for (const link of parsed.links) {
        const target = targets.get(link.target.trim().toLocaleLowerCase());
        if (target === undefined) {
          unresolvedLinks.push({
            sourceNoteId: document.id,
            sourceTitle: document.title,
            target: link.target,
            label: link.label
          });
        } else {
          backlinks.push({
            sourceNoteId: document.id,
            sourceTitle: document.title,
            targetNoteId: target.id,
            targetTitle: target.title,
            label: link.label
          });
        }
      }
    }
    return { backlinks, unresolvedLinks };
  }

  private async readDocument(context: Context, note: NoteItem): Promise<MarkdownDocument> {
    try {
      return await this.storage.read(context, note);
    } catch (error) {
      console.error(`检索读取 Markdown 失败 (${note.id}): ${JSON.stringify(error)}`);
      throw new Error(`无法读取笔记 ${note.id} 的 Markdown 正文`);
    }
  }

  private preview(content: string, query: string, regex: RegExp | null = null): string {
    const normalizedContent: string = content.replace(/\s+/g, ' ').trim();
    let position: number;
    if (regex !== null) {
      const m: RegExpExecArray | null = regex.exec(normalizedContent);
      position = m !== null ? m.index : -1;
    } else {
      position = normalizedContent.toLocaleLowerCase().indexOf(query);
    }
    if (position < 0) {
      return normalizedContent.substring(0, 120);
    }
    const start: number = Math.max(0, position - 40);
    return normalizedContent.substring(start, Math.min(normalizedContent.length, start + 160));
  }
}
