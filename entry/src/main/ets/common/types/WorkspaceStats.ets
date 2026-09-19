/**
 * 工作台统计模型
 * 由 Index 依据本地笔记与双链图谱计算，供首页 / 图谱视图展示。
 */
export interface WorkspaceStats {
  noteCount: number;
  linkCount: number;
  unresolvedCount: number;
  tagCount: number;
}
