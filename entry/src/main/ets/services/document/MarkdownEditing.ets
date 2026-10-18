export interface MarkdownEdit {
  text: string;
  start: number;
  end: number;
}

/** Pure source edits. Offsets use UTF-16, matching ArkUI TextArea selections. */
export class MarkdownEditing {
  static toggleTask(value: MarkdownEdit, line: number): MarkdownEdit {
    const rows = value.text.split('\n');
    if (!Number.isInteger(line) || line < 0 || line >= rows.length) { return value; }
    rows[line] = rows[line].replace(/^([ \t]*[-*+][ \t]+\[)([ xX])(\])/, (_: string, prefix: string, state: string, suffix: string): string =>
      prefix + (state === ' ' ? 'x' : ' ') + suffix);
    return { text: rows.join('\n'), start: value.start, end: value.end };
  }
  static selection(text: string, start: number, end: number): MarkdownEdit {
    const left = Math.max(0, Math.min(text.length, Math.min(start, end)));
    return { text, start: left, end: Math.max(left, Math.min(text.length, Math.max(start, end))) };
  }

  static wrap(value: MarkdownEdit, open: string, close: string, placeholder: string = ''): MarkdownEdit {
    const v = MarkdownEditing.selection(value.text, value.start, value.end);
    const before = v.text.slice(0, v.start), selected = v.text.slice(v.start, v.end), after = v.text.slice(v.end);
    if (close && selected.startsWith(open) && selected.endsWith(close) && selected.length >= open.length + close.length) {
      const inner = selected.slice(open.length, -close.length);
      return { text: before + inner + after, start: v.start, end: v.start + inner.length };
    }
    if (close && before.endsWith(open) && after.startsWith(close)) {
      return { text: before.slice(0, -open.length) + selected + after.slice(close.length),
        start: v.start - open.length, end: v.end - open.length };
    }
    const inner = selected || placeholder;
    return { text: before + open + inner + close + after, start: v.start + open.length, end: v.start + open.length + inner.length };
  }

  static lines(value: MarkdownEdit, marker: string): MarkdownEdit {
    const v = MarkdownEditing.selection(value.text, value.start, value.end);
    const from = v.start === 0 ? 0 : v.text.lastIndexOf('\n', v.start - 1) + 1;
    // A selection ending at the next line's start does not include that line.
    const last = v.end > v.start && v.text[v.end - 1] === '\n' ? v.end - 1 : v.end;
    const newline = v.text.indexOf('\n', last);
    const to = newline < 0 ? v.text.length : newline;
    const rows = v.text.slice(from, to).split('\n');
    const ordered = marker === '1. ';
    const same = (row: string): boolean => ordered ? /^\s*\d+\.\s/.test(row) : row.trimStart().startsWith(marker);
    const remove = rows.some((row: string) => row.trim().length > 0) && rows.every((row: string) => !row.trim() || same(row));
    const changed = rows.map((row: string, index: number): string => {
      const indent = row.match(/^[ \t]*/); const prefix = indent ? indent[0] : '';
      const body = row.slice(prefix.length);
      if (remove) { return prefix + (ordered ? body.replace(/^\d+\.\s/, '') : body.slice(marker.length)); }
      const stripped = body.replace(/^(?:#{1,6}[ \t]+|[-*+][ \t]+(?:\[[ xX]\][ \t]*)?|\d+[.)][ \t]+|>[ \t]?)/, '');
      return prefix + (ordered ? `${index + 1}. ` : marker) + stripped;
    }).join('\n');
    const delta = changed.length - (to - from);
    return { text: v.text.slice(0, from) + changed + v.text.slice(to),
      start: v.start === v.end ? Math.max(from, v.start + delta) : from,
      end: v.start === v.end ? Math.max(from, v.start + delta) : from + changed.length };
  }

  static insertBlock(value: MarkdownEdit, body: string): MarkdownEdit {
    const v = MarkdownEditing.selection(value.text, value.start, value.end);
    const before = v.text.slice(0, v.start), after = v.text.slice(v.end);
    const eol = v.text.includes('\r\n') ? '\r\n' : '\n';
    const prefix = before && !before.endsWith(eol + eol) ? before.endsWith(eol) ? eol : eol + eol : '';
    const suffix = after && !after.startsWith(eol + eol) ? after.startsWith(eol) ? eol : eol + eol : '';
    const inserted = body.replace(/\n/g, eol);
    return { text: before + prefix + inserted + suffix + after,
      start: before.length + prefix.length, end: before.length + prefix.length + inserted.length };
  }

  static command(value: MarkdownEdit, action: string): MarkdownEdit {
    if (action === 'bold') { return MarkdownEditing.wrap(value, '**', '**'); }
    if (action === 'italic') { return MarkdownEditing.wrap(value, '*', '*'); }
    if (action === 'strike') { return MarkdownEditing.wrap(value, '~~', '~~'); }
    if (action === 'code') { return MarkdownEditing.wrap(value, '`', '`'); }
    if (action === 'link') { return MarkdownEditing.wrap(value, '[[', ']]', '待连接笔记'); }
    if (action === 'url') { return MarkdownEditing.wrap(value, '[', '](https://example.com)', '链接文字'); }
    if (action === 'tag') { return MarkdownEditing.wrap(value, '#', '', '标签'); }
    if (action === 'table') { return MarkdownEditing.insertBlock(value, '| 标题 | 内容 |\n| --- | --- |\n| 项目 | 说明 |'); }
    if (action === 'fence') { return MarkdownEditing.insertBlock(value, '```text\n' + value.text.slice(value.start, value.end) + '\n```'); }
    if (action === 'divider') { return MarkdownEditing.insertBlock(value, '---'); }
    let marker = '';
    if (/^h[1-6]$/.test(action)) { marker = '#'.repeat(Number(action[1])) + ' '; }
    if (action === 'bullet') { marker = '- '; }
    if (action === 'ordered') { marker = '1. '; }
    if (action === 'task') { marker = '- [ ] '; }
    if (action === 'quote') { marker = '> '; }
    return marker ? MarkdownEditing.lines(value, marker) : value;
  }
}

interface HistoryChange { from: number; removed: string; inserted: string; beforeStart: number; beforeEnd: number; afterStart: number; afterEnd: number; }

/** Stores bounded changes rather than a copy of the entire document per keystroke. */
export class MarkdownHistory {
  private undoStack: HistoryChange[] = [];
  private redoStack: HistoryChange[] = [];
  private characters: number = 0;
  private lastInputAt: number = 0;
  reset(): void { this.undoStack = []; this.redoStack = []; this.characters = 0; this.lastInputAt = 0; }
  canUndo(): boolean { return this.undoStack.length > 0; }
  canRedo(): boolean { return this.redoStack.length > 0; }
  record(before: MarkdownEdit, after: MarkdownEdit, typing: boolean = false, now: number = Date.now()): void {
    if (before.text === after.text) { return; }
    let from = 0, tail = 0;
    while (from < before.text.length && from < after.text.length && before.text[from] === after.text[from]) { from++; }
    while (tail < before.text.length - from && tail < after.text.length - from &&
      before.text[before.text.length - 1 - tail] === after.text[after.text.length - 1 - tail]) { tail++; }
    const change: HistoryChange = { from, removed: before.text.slice(from, before.text.length - tail),
      inserted: after.text.slice(from, after.text.length - tail), beforeStart: before.start, beforeEnd: before.end,
      afterStart: after.start, afterEnd: after.end };
    if (change.removed.length + change.inserted.length > 2 * 1024 * 1024) { this.reset(); return; }
    // Group adjacent insertions, with an explicit boundary for every toolbar action.
    const previous = this.undoStack[this.undoStack.length - 1];
    if (typing && this.lastInputAt > 0 && now - this.lastInputAt < 750 && previous && !change.removed && !previous.removed &&
      change.from === previous.from + previous.inserted.length && !change.inserted.includes('\n')) {
      previous.inserted += change.inserted; previous.afterStart = after.start; previous.afterEnd = after.end;
    } else { this.undoStack.push(change); }
    for (const discarded of this.redoStack) { this.characters -= discarded.removed.length + discarded.inserted.length; }
    this.characters += change.removed.length + change.inserted.length;
    this.redoStack = []; this.lastInputAt = typing ? now : 0;
    while (this.undoStack.length > 100 || (this.characters > 2 * 1024 * 1024 && this.undoStack.length > 1)) {
      const removed = this.undoStack.shift();
      if (removed) { this.characters -= removed.removed.length + removed.inserted.length; }
    }
  }
  undo(current: MarkdownEdit): MarkdownEdit | null { return this.move(current, true); }
  redo(current: MarkdownEdit): MarkdownEdit | null { return this.move(current, false); }
  private move(current: MarkdownEdit, undo: boolean): MarkdownEdit | null {
    const source = undo ? this.undoStack : this.redoStack;
    const change = source.pop(); if (!change) { return null; }
    const old = undo ? change.inserted : change.removed, next = undo ? change.removed : change.inserted;
    if (current.text.slice(change.from, change.from + old.length) !== old) { this.reset(); return null; }
    (undo ? this.redoStack : this.undoStack).push(change); this.lastInputAt = 0;
    return { text: current.text.slice(0, change.from) + next + current.text.slice(change.from + old.length),
      start: undo ? change.beforeStart : change.afterStart, end: undo ? change.beforeEnd : change.afterEnd };
  }
}
