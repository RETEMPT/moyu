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
}

