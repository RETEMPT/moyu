export interface NoteItem {
  id: string;
  title: string;
  category: string;
  type: string;
  previewText: string;
  tag: string;
  tagColor: string;
  updateTime: string;
  contentDetail: string;
  pageInfo?: string;
  extraInfo?: string;
  coverUrl?: string;
  strokes?: string;
  scratchpadStrokes?: string;
  pageAnnotations?: string;
  /** 软删除时间戳（毫秒）。存在且 > 0 表示该笔记在回收站中；未删除时省略。 */
  deletedAt?: number;
  /** 收藏（星标）标记。true 表示已收藏，出现在「收藏」工作区；未收藏时省略。 */
  favorite?: boolean;
  /** 多标签列表（功能6）。缺失时回退到单值 tag 派生。 */
  tags?: string[];
  /** 创建时间戳（毫秒，功能11 排序用）。旧数据缺失时由 bootstrap 回填。 */
  createdAt?: number;
  /** 更新时间戳（毫秒，功能11 排序用）。旧数据缺失时由 bootstrap 回填。 */
  updatedAt?: number;
  /** 是否置顶在主页网格顶部。true 表示置顶。 */
  isPinned?: boolean;
  /** 真实文档文件在沙箱或系统中的 URI */
  sourceUri?: string;
  /** 文档原始来源类型 ('pdf' | 'doc' | 'image' | 'markdown') */
  sourceType?: string;
  /** 真实文档总页数 */
  pageCount?: number;
  /** 文档元数据 JSON（如尺寸、大小、原文件名等） */
  documentMeta?: string;
  /** AI 自动生成的摘要 */
  aiSummary?: string;
  /** AI 自动分析的智能标签列表 */
  aiTags?: string[];
  /** 已校对的 PDF 页文字，JSON 序列化 PdfTextPage[]；不替换批注正文。 */
  pdfTextJson?: string;
}

