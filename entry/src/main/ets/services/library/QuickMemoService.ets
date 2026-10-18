import { NoteItem } from '../../common/types/NoteItem';
import { MarkdownParserService } from '../MarkdownParserService';
import { TimeFormat } from '../../common/utils/TimeFormat';

export interface MemoDraft { id: string; content: string; }
export interface QuickMemoPorts {
  notes: () => NoteItem[];
  create: (note: NoteItem) => Promise<void>;
  saveNotes: (notes: NoteItem[]) => Promise<void>;
  publish: (notes: NoteItem[]) => void;
}

/** A title-free capture becomes an ordinary local Markdown note after both writes succeed. */
export class QuickMemoService {
  static note(draft: MemoDraft, now: number): NoteItem {
    const content = draft.content;
    if (!/^memo_[a-zA-Z0-9_-]{1,70}$/.test(draft.id) || !content.trim() || content.length > 12000) {
      throw new Error('随手记需为 1–12000 字，请分段记录');
    }
    const firstLine = content.split('\n').find((line: string) => line.trim().length > 0) || '随手记';
    const title = firstLine.replace(/^\s*(?:#{1,6}\s+|[-*+]\s+(?:\[[ xX]\]\s*)?|>\s*)/, '').slice(0, 60).trim() || '随手记';
    const parsed = new MarkdownParserService().parse({ id: draft.id, title, content, fileName: '', filePath: '', updatedAt: now });
    const tags: string[] = [];
    for (const item of parsed.tags) {
      const tag = item.value.substring(1).slice(0, 199);
      if (tag && !tags.includes(tag) && tags.length < 100) { tags.push(tag); }
    }
    return { id: draft.id, title, contentDetail: content, category: '随手记', type: 'Markdown',
      previewText: content.replace(/\s+/g, ' ').slice(0, 160), tags, tag: tags[0] || '', tagColor: '',
      createdAt: now, updatedAt: now, updateTime: TimeFormat.format(new Date(now)) };
  }

  /** Caller serializes this operation with other library mutations. The draft ID makes retries idempotent. */
  static async commit(draft: MemoDraft, ports: QuickMemoPorts): Promise<void> {
    const note = QuickMemoService.note(draft, Date.now());
    const existing = ports.notes().find((item: NoteItem) => item.id === note.id);
    if (existing) {
      if (existing.contentDetail === note.contentDetail) { return; }
      throw new Error('这份草稿已保存，请打开原笔记继续编辑');
    }
    await ports.create(note);
    const next = [note].concat(ports.notes());
    await ports.saveNotes(next);
    ports.publish(next);
  }
}
