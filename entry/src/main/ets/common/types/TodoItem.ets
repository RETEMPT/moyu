/**
 * 待办日历模块的数据模型
 *
 * 与笔记（NoteItem）解耦：待办按日期归属，可引用多篇笔记形成跳转链接，
 * 每个日期另有一段可编辑备忘文本（DayNote）。全部本地存储，不联网。
 */

/** 单条待办事项 */
export interface TodoItem {
  id: string;
  /** 归属日期，格式 YYYY-MM-DD（本地时区） */
  date: string;
  /** 标题：未完成显示红字，完成后显示绿字 */
  title: string;
  /** 是否已完成 */
  done: boolean;
  /** 引用笔记的 id 列表，用于跳转到相关笔记 */
  noteRefs: string[];
  createdAt: number;
  updatedAt: number;
}

/** 某个日期的可编辑备忘文本（显示为该日期的「最后编辑文本」） */
export interface DayNote {
  /** 归属日期，格式 YYYY-MM-DD */
  date: string;
  text: string;
  updatedAt: number;
}

/** 月历网格中的一个单元格 */
export interface CalendarCell {
  /** 日号；占位格为 0 */
  day: number;
  /** 日期键 YYYY-MM-DD；占位格为空串 */
  dateKey: string;
  /** 是否属于当前显示的月份（占位格为 false） */
  inMonth: boolean;
  /** 是否为今天 */
  isToday: boolean;
}
