import { MarkdownDocument } from '../common/types/MarkdownDocument';
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
    const lines: string[] = document.content.split('\n');
    let firstHeading: string = '';
    // 是否处于 ``` 围栏代码块内（与 MarkdownReader 的围栏判定保持一致）
    let inFence: boolean = false;
    // 缩进代码块不能打断段落：仅当前面是空行或同为缩进代码时才成立
    let previousBlankOrCode: boolean = true;

    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index];
      const lineNumber: number = index + 1;

      if (this.isFenceMarker(line)) {
        inFence = !inFence;
        previousBlankOrCode = false;
        continue;
      }
      if (inFence) {
        previousBlankOrCode = false;
        continue;
      }
      if (line.trim().length === 0) {
        previousBlankOrCode = true;
        continue;
      }
      if (previousBlankOrCode && this.isIndentedCode(line)) {
        previousBlankOrCode = true;
        continue;
      }
      previousBlankOrCode = false;

      const heading: MarkdownHeading | null = this.parseHeading(line, lineNumber);
      if (heading !== null) {
        headings.push(heading);
        if (firstHeading.length === 0 && heading.level === 1) {
          firstHeading = heading.text;
        }
      }
      this.parseTags(line, lineNumber, tags);
      this.parseLinks(line, lineNumber, links);
    }

    return {
      title: firstHeading.length > 0 ? firstHeading : document.title,
      headings,
      tags,
      links
    };
  }

  /** 是否为代码围栏标记行（与 MarkdownReader.parseBlocks 的判定完全一致） */
  private isFenceMarker(line: string): boolean {
    return line.trim().startsWith('```');
  }

  /** 是否为缩进代码行（4 个空格或 1 个制表符起始） */
  private isIndentedCode(line: string): boolean {
    return line.startsWith('    ') || line.startsWith('\t');
  }

  private parseHeading(line: string, lineNumber: number): MarkdownHeading | null {
    const trimmed: string = line.trim();
    let level: number = 0;
    while (level < trimmed.length && trimmed.charAt(level) === HEADING_PREFIX) {
      level++;
    }
    if (level === 0 || level > 6 || trimmed.charAt(level) !== ' ') {
      return null;
    }
    const text: string = trimmed.substring(level).trim().replace(/#+$/, '').trim();
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
