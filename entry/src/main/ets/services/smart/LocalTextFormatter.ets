export type LocalLayoutStyle = 'faithful' | 'study';
export interface LocalTextLine { text: string; protected: boolean; }

/** Conservative layout only: no generated facts, summaries, symbol correction or date guesses. */
export class LocalTextFormatter {
  static normalize(text: string): string {
    const rows = text.replace(/\r\n?/g, '\n').split('\n');
    let start = 0; let end = rows.length;
    while (start < end && rows[start].trim().length === 0) { start++; }
    while (end > start && rows[end - 1].trim().length === 0) { end--; }
    return rows.slice(start, end).join('\n');
  }
  static lines(text: string): LocalTextLine[] {
    const result: LocalTextLine[] = [];
    let fence: string = '';
    let math: string = '';
    for (const raw of text.replace(/\r\n?/g, '\n').split('\n')) {
      const line = raw.trim();
      const marker = line.match(/^(`{3,}|~{3,})/);
      if (fence.length > 0) {
        result.push({ text: raw, protected: true });
        if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length &&
          line.slice(marker[1].length).trim().length === 0) { fence = ''; }
      } else if (marker) {
        fence = marker[1]; result.push({ text: raw, protected: true });
      } else if (math.length > 0) {
        result.push({ text: raw, protected: true });
        if (line.endsWith(math)) { math = ''; }
      } else if (line.startsWith('$$') || line.startsWith('\\[')) {
        const closing = line.startsWith('$$') ? '$$' : '\\]';
        if (!(line.length > 4 && line.endsWith(closing))) { math = closing; }
        result.push({ text: raw, protected: true });
      } else {
        result.push({ text: raw, protected: /^(?: {4}|\t)/.test(raw) || /[|`$]|\\\(|!\[|\]\(/.test(raw) });
      }
    }
    return result;
  }

  static format(text: string, title: string, style: LocalLayoutStyle = 'faithful', mergeWrappedLines: boolean = false): string {
    const source = LocalTextFormatter.normalize(text);
    const rows = LocalTextFormatter.lines(source);
    const body: string[] = [];
    let previousPlain: boolean = false;
    for (const row of rows) {
      const trimmed = row.text.trim();
      const plain = !row.protected && trimmed.length > 0 && !LocalTextFormatter.structural(trimmed);
      let rendered = row.text;
      if (style === 'study' && !row.protected && trimmed.length > 0) {
        if (LocalTextFormatter.sectionHeading(trimmed)) { rendered = `## ${trimmed}`; }
        else { rendered = row.text.replace(/^(\s*)[•▪●·]\s+/, '$1- '); }
      }
      const last = body.length > 0 ? body[body.length - 1] : '';
      if (mergeWrappedLines && plain && previousPlain && LocalTextFormatter.canJoin(last, rendered)) {
        const separator = /[\u3400-\u9FFF]$/.test(last.trim()) && /^[\u3400-\u9FFF]/.test(rendered.trim()) ? '' : ' ';
        body[body.length - 1] = last.trimEnd() + separator + rendered.trimStart();
      } else {
        if (style === 'study' && rendered.startsWith('## ') && last.trim().length > 0) { body.push(''); }
        body.push(rendered);
      }
      previousPlain = plain;
    }
    const formatted = body.join('\n');
    return /^#\s/.test(formatted) ? formatted : `# ${title}\n\n${formatted}`;
  }

  private static sectionHeading(line: string): boolean {
    return line.length <= 48 && (/^【[^】]+】$/.test(line) ||
      /^(?:[一二三四五六七八九十百]+[、．.]|[（(][一二三四五六七八九十]+[）)])\s*\S/.test(line) && !/[。！？!?；;]$/.test(line));
  }
  private static structural(line: string): boolean {
    return /^(?:#{1,6}\s|>\s?|[-*+•▪●·]\s|\d+[.)、]\s*|[-*_]{3,}$)/.test(line) ||
      LocalTextFormatter.sectionHeading(line) || /^.{1,20}[：:]$/.test(line);
  }
  private static canJoin(left: string, right: string): boolean {
    const end = left.trim(); const start = right.trim();
    if (end.length < 12 || /[。！？!?；;：:]$| {2}$/.test(left) || /^(?: {2}|\t)/.test(right)) { return false; }
    // Do not repair hyphenated words or join standalone values/dates. The source remains available for correction.
    return /[\u3400-\u9FFF]$/.test(end) && /^[\u3400-\u9FFF]/.test(start) ||
      /[A-Za-z,]$/.test(end) && /^[a-z]/.test(start);
  }
}
