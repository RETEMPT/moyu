export type SourceLineKind = 'text' | 'blank' | 'code' | 'math' | 'table' | 'heading' | 'list' | 'quote' | 'divider' | 'reference';
export interface SourceTextLine { text: string; line: number; kind: SourceLineKind; }

/** Conservative block boundaries shared by local formatting, extraction and indexing.
 * Fences follow CommonMark's matching-character/length rule. This is not a full Markdown parser.
 */
export class SourceTextStructure {
  /** Unicode mandatory line/paragraph separators remain explicit in Markdown output. */
  static normalizeBreaks(text: string): string {
    return SourceTextStructure.scan(text).map(row => row.kind === 'text' || row.kind === 'heading' || row.kind === 'blank' ?
      row.text.replace(/[\u0085\u2028]/g, '  \n').replace(/\u2029/g, '\n\n') : row.text).join('\n');
  }

  static scan(text: string): SourceTextLine[] {
    const rows = text.replace(/\r\n?/g, '\n').split('\n');
    const result: SourceTextLine[] = [];
    let fence = ''; let math = ''; let comment = false;
    for (let index = 0; index < rows.length; index++) {
      const raw = rows[index]; const value = raw.trim();
      const marker = raw.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
      let kind: SourceLineKind = 'text';
      if (fence) {
        kind = 'code';
        if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length && !marker[2].trim()) { fence = ''; }
      } else if (comment) {
        kind = 'code'; if (value.includes('-->')) { comment = false; }
      } else if (math) {
        kind = 'math'; if (value.endsWith(math)) { math = ''; }
      } else if (marker && (marker[1][0] !== '`' || !marker[2].includes('`'))) {
        fence = marker[1]; kind = 'code';
      } else if (value.startsWith('$$') || value.startsWith('\\[')) {
        const closing = value.startsWith('$$') ? '$$' : '\\]';
        if (!(value.length >= 4 && value.endsWith(closing))) { math = closing; }
        kind = 'math';
      } else if (value.startsWith('<!--')) {
        kind = 'code'; comment = !value.includes('-->');
      } else if (!value) { kind = 'blank'; }
      else if (/^(?: {4}|\t)/.test(raw)) { kind = 'code'; }
      else if (/^>/.test(value)) { kind = 'quote'; }
      else if (/^(?:\*[ \t]*){3,}$|^(?:-[ \t]*){3,}$|^(?:_[ \t]*){3,}$/.test(value)) { kind = 'divider'; }
      else if (/^#{1,6}(?:\s|$)/.test(value)) { kind = 'heading'; }
      else if (/^(?:[-*+•▪●·]|\d+[.)、])\s+/.test(value)) { kind = 'list'; }
      else if (/^\[[^\]]+\]:/.test(value)) { kind = 'reference'; }
      else if (value.includes('|')) { kind = 'table'; }
      // Setext headings are a boundary too; their underline must not be merged into OCR prose.
      if (kind === 'text' && index + 1 < rows.length && /^ {0,3}(?:=+|-+)[ \t]*$/.test(rows[index + 1])) { kind = 'heading'; }
      if (kind === 'text' && /^ {0,3}=+[ \t]*$/.test(raw)) { kind = 'divider'; }
      result.push({ text: raw, line: index + 1, kind });
    }
    return result;
  }
}
