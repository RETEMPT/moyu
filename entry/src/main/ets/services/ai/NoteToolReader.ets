import { NoteItem } from '../../common/types/NoteItem';

export class NoteToolReader {
  static resolve(notes: NoteItem[], identifier: string): NoteItem {
    const key = identifier.trim().toLowerCase();
    if (!key) { throw new Error('请指定完整标题或笔记 ID'); }
    const byId = notes.find((note: NoteItem) => note.id.toLowerCase() === key);
    if (byId) { return byId; }
    const matches = notes.filter((note: NoteItem) => note.title.toLowerCase() === key);
    if (matches.length !== 1) { throw new Error(matches.length > 1 ? '有多篇同名笔记，请指定唯一 ID' : `未找到笔记「${identifier}」，请提供完整标题或 ID`); }
    return matches[0];
  }

  static outline(note: NoteItem): string {
    const lines = note.contentDetail.split('\n');
    const headings: string[] = [];
    let fence = '';
    for (let i = 0; i < lines.length; i++) {
      const mark = /^\s*(`{3,}|~{3,})/.exec(lines[i]);
      if (mark) {
        if (!fence) { fence = mark[1]; }
        else if (mark[1][0] === fence[0] && mark[1].length >= fence.length) { fence = ''; }
        continue;
      }
      const heading = /^(#{1,6})\s+(.+)$/.exec(lines[i]);
      if (!fence && heading) { headings.push(`第 ${i + 1} 行 · ${heading[1]} ${heading[2]}`); }
    }
    return `《${note.title}》 · ID ${note.id}\n${headings.length > 0 ? headings.slice(0, 100).join('\n') : '正文没有 Markdown 标题'}`;
  }
}
