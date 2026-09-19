/**
 * 正文大纲条目
 * 由 MarkdownReader 解析正文标题后回传，供 OutlinePanel 生成目录树。
 */
export interface MarkdownOutlineItem {
  /** 标题层级：1 / 2 / 3 */
  level: number;
  text: string;
  /** 在正文中的起始行号（0 基），用于锚点定位 */
  line: number;
}
