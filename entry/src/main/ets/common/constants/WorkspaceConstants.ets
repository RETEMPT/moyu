/**
 * 工作台导航与视图常量
 * 统一导航键、资料筛选项与保存状态文案，避免视图层出现魔法字符串。
 */

/** 主导航键（同时作为 activeNav 的取值） */
export const NAV_HOME: string = '首页';
export const NAV_LIBRARY: string = '资料库';
export const NAV_GRAPH: string = '图谱';
/** 这两个页面尚未实现，Index 会落到 PendingWorkspace 并如实标注，而不是静默失败 */
export const NAV_CANVAS: string = '白板';
export const NAV_AI: string = 'AI墨客';
/** 待办日历与回收站导航键 */
export const NAV_TODO: string = '待办';
export const NAV_TRASH: string = '回收站';
/** 收藏（置顶/星标）快捷入口导航键 */
export const NAV_FAVORITE: string = '收藏';

/** 回收站保留天数：超期由 Index 在启动时自动彻底删除 */
export const TRASH_RETENTION_DAYS: number = 30;

/** 未归类笔记的默认分类名 */
export const CATEGORY_UNFILED: string = '未分类';

/** 资料库筛选项 */
export const FILTER_ALL: string = '全部';
export const NOTE_FILTERS: string[] = [FILTER_ALL, '手写', 'PDF', 'Word', 'Markdown'];

/** Markdown 落盘状态文案 */
export const SAVE_IDLE: string = '已保存';
export const SAVE_SAVING: string = '保存中';
export const SAVE_FAILED: string = '保存失败';
