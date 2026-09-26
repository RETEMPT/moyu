import { Context } from '@kit.AbilityKit';
import { LinkGraph, Backlink, UnresolvedLink } from '../common/types/LinkGraph';
import { MarkdownDocument } from '../common/types/MarkdownDocument';
import { MarkdownParseResult } from '../common/types/MarkdownParseResult';
import { NoteItem } from '../common/types/NoteItem';
import { NoteSearchResult } from '../common/types/NoteSearchResult';
import { NoteStorageService } from './NoteStorageService';
import { MarkdownParserService } from './MarkdownParserService';

export class NoteSearchService {
  private readonly storage: NoteStorageService;
  private readonly parser: MarkdownParserService;

  constructor(storage: NoteStorageService = new NoteStorageService(),
    parser: MarkdownParserService = new MarkdownParserService()) {
    this.storage = storage;
    this.parser = parser;
  }

  async search(context: Context, notes: NoteItem[], query: string, useRegex: boolean = false): Promise<NoteSearchResult[]> {
    const trimmedQuery: string = query.trim();
    if (trimmedQuery.length === 0) {
      return [];
    }
    const normalizedQuery: string = trimmedQuery.toLocaleLowerCase();
    // 正则模式下预编译一次；非法正则直接返回空结果，绝不让弹窗崩溃
    let regex: RegExp | null = null;
    if (useRegex) {
      try {
        regex = new RegExp(trimmedQuery, 'i');
      } catch (error) {
        console.error(`非法正则，忽略本次检索: ${JSON.stringify(error)}`);
        return [];
      }
    }
    const results: NoteSearchResult[] = [];
    for (const note of notes) {
      const document: MarkdownDocument = await this.readDocument(context, note);
      const parsed: MarkdownParseResult = this.parser.parse(document);
      const titleMatch: boolean = this.matches(note.title, normalizedQuery, regex);
      const contentMatch: boolean = this.matches(document.content, normalizedQuery, regex);
      const matchedTags: string[] = [];
      for (const tag of parsed.tags) {
        if (this.matches(tag.value, normalizedQuery, regex)
          && matchedTags.indexOf(tag.value) < 0) {
          matchedTags.push(tag.value);
        }
      }
      if (titleMatch || contentMatch || matchedTags.length > 0) {
        results.push({
          noteId: note.id,
          title: parsed.title,
          fileName: document.fileName,
          matchedTitle: titleMatch,
          matchedContent: contentMatch,
          matchedTags,
          preview: this.preview(document.content, normalizedQuery, regex)
        });
      }
    }
    return results;
  }

  /** 统一匹配：正则模式用 regex.test，否则用大小写不敏感的子串包含 */
  private matches(text: string, normalizedQuery: string, regex: RegExp | null): boolean {
    if (regex !== null) {
      return regex.test(text);
    }
    return text.toLocaleLowerCase().includes(normalizedQuery);
  }

  async buildLinkGraph(context: Context, notes: NoteItem[]): Promise<LinkGraph> {
    const documents: MarkdownDocument[] = [];
    for (const note of notes) {
      documents.push(await this.readDocument(context, note));
    }
    const backlinks: Backlink[] = [];
    const unresolvedLinks: UnresolvedLink[] = [];
    for (const document of documents) {
      const parsed: MarkdownParseResult = this.parser.parse(document);
      for (const link of parsed.links) {
        const target: NoteItem | null = this.findNote(notes, link.target);
        if (target === null) {
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

  private findNote(notes: NoteItem[], target: string): NoteItem | null {
    const normalizedTarget: string = target.trim().toLocaleLowerCase();
    for (const note of notes) {
      const fileName: string = `${note.id}.md`.toLocaleLowerCase();
      if (note.id.toLocaleLowerCase() === normalizedTarget
        || note.title.toLocaleLowerCase() === normalizedTarget
        || fileName === normalizedTarget) {
        return note;
      }
    }
    return null;
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
