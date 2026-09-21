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
}

