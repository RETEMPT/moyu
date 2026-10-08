import { NoteItem } from '../../common/types/NoteItem';
import { ChatCitation } from '../../common/types/ChatSession';
import { TodoItem } from '../../common/types/TodoItem';
import { MarkdownDocument } from '../../common/types/MarkdownDocument';
import { Chunk } from '../../common/types/RagTypes';
import { searchTerms } from '../../common/utils/SearchTerms';
import { StudySourceService } from '../study/StudySourceService';
import { ChunkIndexService } from './ChunkIndexService';
import { AiParser } from './AiParser';

export interface LocalAssistantContext {
  notes: NoteItem[];
  pinned: NoteItem[];
  currentNote?: NoteItem;
  todos?: TodoItem[];
}
export interface LocalAssistantResult { text: string; citations: ChatCitation[]; }
interface LocalHit { chunk: Chunk; score: number; }

/** Offline, extractive operations only. Never constructs a model provider or sends a network request. */
export class LocalAssistantService {
  private indexer: ChunkIndexService = new ChunkIndexService();

  async answer(query: string, context: LocalAssistantContext, cancelled: () => boolean = () => false): Promise<LocalAssistantResult> {
    if (/资料概览|知识全景|知识库结构|统计.*笔记/.test(query)) {
      const categories: Map<string, number> = new Map();
      for (const note of context.notes) {
        const category = note.category || '未分类';
        categories.set(category, (categories.get(category) || 0) + 1);
      }
      const lines: string[] = [];
      categories.forEach((count: number, name: string) => { lines.push(`- ${name}：${count} 篇`); });
      return { text: `共 ${context.notes.length} 篇资料，${(context.todos || []).filter((t: TodoItem) => !t.done).length} 项待办。${lines.length ? '\n\n' + lines.slice(0, 20).join('\n') : '\n先新建笔记或导入 PDF。'}`, citations: [] };
    }
    const scope = context.pinned.length ? context.pinned :
      context.currentNote ? [context.currentNote] : context.notes;
    if (!scope.length) { return { text: '先新建笔记或导入资料，再提取要点、整理待办或搜索原文。', citations: [] }; }
    const docs = StudySourceService.documents(scope).filter((doc: MarkdownDocument) => {
      const note = scope.find((n: NoteItem) => n.id === doc.id);
      const binary = note?.sourceType === 'pdf' || /^(pdf|canvas|handwriting|白纸笔记|稿纸)$/i.test(note?.type || '');
      return doc.content.trim().length > 0 && (!binary || doc.pageNumber !== undefined);
    });
    if (!docs.length) { return { text: '这些资料还没有可检索文字。PDF 请先提取并校对页面文字；手写内容可用图片识别后整理。', citations: [] }; }
    if (/整理待办|提取待办|提取.*任务|待办清单/.test(query)) {
      const lines: string[] = [];
      const citations: ChatCitation[] = [];
      for (const doc of docs.slice(0, 30)) {
        await new Promise<void>((resolve) => { setTimeout(resolve, 0); });
        if (cancelled()) { return { text: '', citations: [] }; }
        const parsed = AiParser.fromSource(doc.content.slice(0, 12000), doc.title);
        for (const task of parsed.tasks.slice(0, 6)) {
          lines.push(`- ${task.title}${task.deadline ? `（${task.deadline}）` : ''} · ${doc.title}${doc.pageNumber ? ` 第 ${doc.pageNumber} 页` : ''}`);
        }
        if (parsed.tasks.length) {
          const chunk = this.indexer.build(doc)[0];
          if (chunk) { citations.push(this.citation({ chunk, score: 1 })); }
        }
      }
      return { text: lines.length ? `原文明示的待办（未自动创建）：\n\n${lines.slice(0, 20).join('\n')}` : '原文中没有识别到明确待办。可在“待办”中手动添加。', citations: citations.slice(0, 6) };
    }
    const extract = /提取要点|提炼|总结|知识卡|本页|大纲/.test(query);
    const terms = searchTerms(query);
    const hits: LocalHit[] = [];
    let scanned = 0;
    for (const doc of docs) {
      if (scanned++ % 8 === 0) {
        await new Promise<void>((resolve) => { setTimeout(resolve, 0); });
        if (cancelled()) { return { text: '', citations: [] }; }
      }
      for (const chunk of this.indexer.build(doc)) {
        const lower = `${chunk.noteTitle} ${chunk.headingPath} ${chunk.text}`.toLocaleLowerCase();
        const matched = terms.filter((term: string) => lower.includes(term)).length;
        if (extract || matched) { hits.push({ chunk, score: matched / Math.max(1, terms.length) }); }
      }
    }
    if (!hits.length) { return { text: '未找到匹配原文。试试课程名、术语或更短的关键词，也可先引用一篇资料。', citations: [] }; }
    hits.sort((a: LocalHit, b: LocalHit) => b.score - a.score);
    const selected = hits.slice(0, 6);
    const paragraphs = selected.map((hit: LocalHit, index: number) => {
      const c = hit.chunk;
      return `### ${index + 1}. ${c.noteTitle}${c.pageNumber ? ` · 第 ${c.pageNumber} 页` : ''}${c.headingPath ? ` · ${c.headingPath}` : ''}\n\n${c.text.slice(0, 900)}${c.text.length > 900 ? '\n…（点击来源查看全文）' : ''}`;
    });
    return { text: `${extract ? '原文要点摘录' : '匹配的原文片段'} · 本地检索\n\n${paragraphs.join('\n\n')}`, citations: selected.map((hit: LocalHit) => this.citation(hit)) };
  }

  private citation(hit: LocalHit): ChatCitation {
    const chunk = hit.chunk;
    return { noteId: chunk.noteId, noteTitle: chunk.noteTitle, headingPath: chunk.headingPath,
      chunkText: chunk.text, score: hit.score, pageNumber: chunk.pageNumber, startLine: chunk.startLine };
  }
}
