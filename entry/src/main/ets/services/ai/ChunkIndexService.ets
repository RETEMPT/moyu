import { MarkdownParserService } from '../MarkdownParserService';
import { MarkdownDocument } from '../../common/types/MarkdownDocument';
import { MarkdownParseResult, MarkdownHeading } from '../../common/types/MarkdownParseResult';
import { Chunk } from '../../common/types/RagTypes';

export class ChunkIndexService {
  private parser: MarkdownParserService = new MarkdownParserService();

  build(document: MarkdownDocument): Chunk[] {
    const parsed: MarkdownParseResult = this.parser.parse(document);
    const lines: string[] = document.content.split('\n');
    const chunks: Chunk[] = [];
    let headingPath: string[] = [];
    let buffer: string[] = [];
    let startLine: number = 1;
    const flush = (): void => {
      const text: string = buffer.join('\n').trim();
      if (text.length > 0) {
        chunks.push({
          id: `${document.id}:${startLine}:${chunks.length}`,
          noteId: document.id,
          noteTitle: document.title,
          headingPath: headingPath.join(' > '),
          text,
          startLine,
          tokenEstimate: Math.ceil(text.length / 2)
        });
      }
      buffer = [];
    };
    for (let index = 0; index < lines.length; index++) {
      const line: string = lines[index];
      const heading: MarkdownHeading | undefined = parsed.headings.find(
        (item: MarkdownHeading) => item.line === index + 1);
      if (heading !== undefined) {
        flush();
        headingPath = headingPath.slice(0, Math.max(0, heading.level - 1));
        headingPath.push(heading.text);
        startLine = index + 1;
        continue;
      }
      if (buffer.length === 0) {
        startLine = index + 1;
      }
      buffer.push(line);
      if (buffer.join('\n').length >= 1600) {
        flush();
      }
    }
    flush();
    return chunks;
  }
}
