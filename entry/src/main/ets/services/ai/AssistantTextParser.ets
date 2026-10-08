export interface AssistantBlock {
  kind: string; text: string; level: number; marker: string; language: string; rows: string[][]; line: number; endLine: number;
}
export interface AssistantSpan { text: string; style: string; }

/** Preserves source order, including multiple formula/code blocks and partial streams. */
export class AssistantTextParser {
  static parse(text: string): AssistantBlock[] {
    const lines = text.replace(/\r\n/g, '\n').split('\n');
    const blocks: AssistantBlock[] = [];
    let index = 0;
    while (index < lines.length) {
      const raw = lines[index]; const line = raw.trim();
      if (!line) { index++; continue; }
      const block: AssistantBlock = { kind: 'paragraph', text: raw, level: 0, marker: '', language: '', rows: [], line: index, endLine: index };
      const fence = line.match(/^(`{3,}|~{3,})(.*)$/);
      if (fence) {
        block.language = fence[2].trim(); block.kind = block.language === 'math' ? 'math' : 'code';
        const content: string[] = []; index++;
        while (index < lines.length && !lines[index].trim().startsWith(fence[1])) { content.push(lines[index++]); }
        if (index < lines.length) { index++; }
        block.text = content.join('\n');
      } else if (line.startsWith('$$')) {
        block.kind = 'math';
        if (line.length > 4 && line.endsWith('$$')) { block.text = line.slice(2, -2); index++; }
        else {
          const content: string[] = []; const first = line.slice(2); if (first) { content.push(first); }
          index++;
          while (index < lines.length && !lines[index].trim().endsWith('$$')) { content.push(lines[index++]); }
          if (index < lines.length) { const last = lines[index++].trim().slice(0, -2); if (last) { content.push(last); } }
          block.text = content.join('\n');
        }
      } else if (index + 1 < lines.length && line.includes('|') && /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(lines[index + 1])) {
        block.kind = 'table'; block.rows.push(AssistantTextParser.cells(raw)); index += 2;
        while (index < lines.length && lines[index].trim().includes('|')) { block.rows.push(AssistantTextParser.cells(lines[index++])); }
        block.text = block.rows.map((row: string[]) => row.join(' | ')).join('\n');
      } else {
        const heading = line.match(/^(#{1,6})\s+(.+)$/);
        const list = line.match(/^([-*+•]|\d+[.)])\s+(.+)$/);
        if (heading) { block.kind = 'heading'; block.level = heading[1].length; block.text = heading[2]; }
        else if (list) { block.kind = 'list'; block.marker = /^\d/.test(list[1]) ? list[1] : '•'; block.text = list[2]; }
        else if (line.startsWith('>')) { block.kind = 'quote'; block.text = line.replace(/^>\s?/, ''); }
        else if (/^([-*_])\1{2,}$/.test(line)) { block.kind = 'divider'; block.text = ''; }
        index++;
      }
      block.endLine = index - 1; blocks.push(block);
    }
    return blocks;
  }

  private static cells(line: string): string[] {
    return line.trim().replace(/^\|/, '').replace(/\|$/, '').split(/(?<!\\)\|/)
      .map((cell: string) => cell.trim().replace(/\\\|/g, '|'));
  }

  static spans(text: string): AssistantSpan[] {
    const result: AssistantSpan[] = []; const pattern = /(`[^`\n]+`|\*\*[^*\n]+\*\*|__[^_\n]+__|~~[^~\n]+~~|\*[^*\n]+\*)/g;
    let cursor = 0; let match: RegExpExecArray | null = pattern.exec(text);
    while (match) {
      if (match.index > cursor) { result.push({ text: text.slice(cursor, match.index), style: 'plain' }); }
      const token = match[0]; const double = token.startsWith('**') || token.startsWith('__') || token.startsWith('~~');
      result.push({ text: token.slice(double ? 2 : 1, double ? -2 : -1),
        style: token.startsWith('`') ? 'code' : token.startsWith('~~') ? 'strike' : double ? 'bold' : 'italic' });
      cursor = match.index + token.length; match = pattern.exec(text);
    }
    if (cursor < text.length) { result.push({ text: text.slice(cursor), style: 'plain' }); }
    return result;
  }
}
