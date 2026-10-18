import { SourceLineKind, SourceTextStructure } from '../document/SourceTextStructure';

export type LocalLayoutStyle = 'faithful' | 'study';
export interface LocalTextLine { text: string; protected: boolean; kind: SourceLineKind; }

/** Conservative layout only: no generated facts, summaries, symbol correction or date guesses. */
export class LocalTextFormatter {
  static normalize(text: string): string {
    const rows = SourceTextStructure.normalizeBreaks(text.replace(/^\uFEFF/, '')).split('\n');
    let start = 0; let end = rows.length;
    while (start < end && rows[start].trim().length === 0) { start++; }
    while (end > start && rows[end - 1].trim().length === 0) { end--; }
    return rows.slice(start, end).join('\n');
  }
  static lines(text: string): LocalTextLine[] {
    return SourceTextStructure.scan(text).map((row): LocalTextLine => ({ text: row.text, kind: row.kind,
      protected: row.kind === 'code' || row.kind === 'math' || row.kind === 'table' || row.kind === 'reference' ||
        /[`$]|\\\(|!\[|\]\(/.test(row.text) }));
  }

  static format(text: string, title: string, style: LocalLayoutStyle = 'faithful', mergeWrappedLines: boolean = false): string {
    const source = LocalTextFormatter.normalize(text);
    const rows = LocalTextFormatter.lines(source);
    const body: string[] = [];
    let previousPlain: boolean = false;
    for (let index = 0; index < rows.length; index++) {
      const row = rows[index];
      const trimmed = row.text.trim();
      const plain = !row.protected && row.kind === 'text' && trimmed.length > 0 && !LocalTextFormatter.structural(trimmed);
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
    if (end.length < 12 || /[。！？!?；;：:]$| {2}$|[\u00A0\u202F\u2060]$/.test(left) ||
      /^(?: {2}|\t|[\u00A0\u202F\u2060])/.test(right)) { return false; }
    // Do not repair hyphenated words or join standalone values/dates. The source remains available for correction.
    return /[\u3400-\u9FFF]$/.test(end) && /^[\u3400-\u9FFF]/.test(start) ||
      /[A-Za-z,]$/.test(end) && /^[a-z]/.test(start);
  }
}
