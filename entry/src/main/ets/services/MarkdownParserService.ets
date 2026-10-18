import { MarkdownDocument } from '../common/types/MarkdownDocument';
import { SourceTextStructure } from './document/SourceTextStructure';
import {
  MarkdownHeading,
  MarkdownLink,
  MarkdownParseResult,
  MarkdownTag
} from '../common/types/MarkdownParseResult';

const HEADING_PREFIX: string = '#';

export class MarkdownParserService {
  /**
   * 解析 Markdown 正文，抽取标题、标签与双链。
   * 代码块（``` 围栏或 4 空格缩进）内的内容一律跳过，
   * 避免代码示例中的 [[X]] 与 #include 被误判为双链和标签。
   * @param document 待解析的 Markdown 文档
   * @returns 标题、标题列表、标签列表与双链列表
   */
  parse(document: MarkdownDocument): MarkdownParseResult {
    const headings: MarkdownHeading[] = [];
    const tags: MarkdownTag[] = [];
    const links: MarkdownLink[] = [];
    const lines = SourceTextStructure.scan(document.content);
    let firstHeading: string = '';
    for (let index: number = 0; index < lines.length; index++) {
      const row = lines[index]; const line = row.text;
      const lineNumber: number = index + 1;

      if (row.kind === 'code' || row.kind === 'math' || row.kind === 'blank' || row.kind === 'reference') { continue; }

      let heading: MarkdownHeading | null = this.parseHeading(line, lineNumber);
      if (heading === null && row.kind === 'heading' && index + 1 < lines.length) {
        const underline = lines[index + 1].text.match(/^ {0,3}(=+|-+)[ \t]*$/);
        if (underline) { heading = { level: underline[1][0] === '=' ? 1 : 2, text: line.trim(), line: lineNumber }; }
      }
      if (heading !== null) {
        headings.push(heading);
        if (firstHeading.length === 0 && heading.level === 1) {
          firstHeading = heading.text;
        }
      }
      const inline = line.replace(/(`+).*?\1/g, '');
      this.parseTags(inline, lineNumber, tags);
      this.parseLinks(inline, lineNumber, links);
    }

    return {
      title: firstHeading.length > 0 ? firstHeading : document.title,
      headings,
      tags,
      links
    };
  }

  private parseHeading(line: string, lineNumber: number): MarkdownHeading | null {
    const trimmed: string = line.trim();
    let level: number = 0;
    while (level < trimmed.length && trimmed.charAt(level) === HEADING_PREFIX) {
      level++;
    }
    if (level === 0 || level > 6 || !/[ \t]/.test(trimmed.charAt(level))) {
      return null;
    }
    const text: string = trimmed.substring(level).trim().replace(/[ \t]+#+[ \t]*$/, '').trim();
    if (text.length === 0) {
      return null;
    }
    return { level, text, line: lineNumber };
  }

  private parseTags(line: string, lineNumber: number, tags: MarkdownTag[]): void {
    const tagPattern: RegExp = /(^|\s)#([^\s#.,!?;:()[\]{}]+)/g;
    let match: RegExpExecArray | null = tagPattern.exec(line);
    while (match !== null) {
      tags.push({ value: `#${match[2]}`, line: lineNumber });
      match = tagPattern.exec(line);
    }
  }

  private parseLinks(line: string, lineNumber: number, links: MarkdownLink[]): void {
    const linkPattern: RegExp = /\[\[([^\]|#]+)(?:\|([^\]]+))?\]\]/g;
    let match: RegExpExecArray | null = linkPattern.exec(line);
    while (match !== null) {
      const target: string = match[1].trim();
      const label: string = match[2] === undefined ? target : match[2].trim();
      if (target.length > 0) {
        links.push({ target, label, line: lineNumber });
      }
      match = linkPattern.exec(line);
    }
  }
}
