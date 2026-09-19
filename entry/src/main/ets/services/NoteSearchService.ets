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

  async search(context: Context, notes: NoteItem[], query: string): Promise<NoteSearchResult[]> {
    const normalizedQuery: string = query.trim().toLocaleLowerCase();
    if (normalizedQuery.length === 0) {
      return [];
    }
    const results: NoteSearchResult[] = [];
    for (const note of notes) {
      const document: MarkdownDocument = await this.readDocument(context, note);
      const parsed: MarkdownParseResult = this.parser.parse(document);
      const titleMatch: boolean = note.title.toLocaleLowerCase().includes(normalizedQuery);
      const contentMatch: boolean = document.content.toLocaleLowerCase().includes(normalizedQuery);
      const matchedTags: string[] = [];
      for (const tag of parsed.tags) {
        if (tag.value.toLocaleLowerCase().includes(normalizedQuery)
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
          preview: this.preview(document.content, normalizedQuery)
        });
      }
    }
    return results;
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

  private preview(content: string, query: string): string {
    const normalizedContent: string = content.replace(/\s+/g, ' ').trim();
    const position: number = normalizedContent.toLocaleLowerCase().indexOf(query);
    if (position < 0) {
      return normalizedContent.substring(0, 120);
    }
    const start: number = Math.max(0, position - 40);
    return normalizedContent.substring(start, Math.min(normalizedContent.length, start + 160));
  }
}
