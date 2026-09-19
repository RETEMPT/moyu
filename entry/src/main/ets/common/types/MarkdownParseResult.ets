export interface MarkdownHeading {
  level: number;
  text: string;
  line: number;
}

export interface MarkdownTag {
  value: string;
  line: number;
}

export interface MarkdownLink {
  target: string;
  label: string;
  line: number;
}

export interface MarkdownParseResult {
  title: string;
  headings: MarkdownHeading[];
  tags: MarkdownTag[];
  links: MarkdownLink[];
}
