/**
 * 日历工具：日期键（YYYY-MM-DD）与月历网格计算
 *
 * 待办模块统一用本地时区的 YYYY-MM-DD 作为日期归属键，
 * 避免各处各自格式化导致同一天的待办对不上。
 */
import { CalendarCell } from '../types/TodoItem';

/** 周日开头的星期表头 */
export const WEEK_LABELS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

export class CalendarUtil {
  private static pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  /** Date → YYYY-MM-DD（本地时区） */
  static dateKey(date: Date): string {
    return `${date.getFullYear()}-${CalendarUtil.pad2(date.getMonth() + 1)}-${CalendarUtil.pad2(date.getDate())}`;
  }

  /** 今天的 YYYY-MM-DD */
  static todayKey(): string {
    return CalendarUtil.dateKey(new Date());
  }

  /** YYYY-MM-DD → 本地 Date（解析失败回退为今天，绝不返回非法日期） */
  static keyToDate(key: string): Date {
    const parts: string[] = key.split('-');
    if (parts.length !== 3) {
      return new Date();
    }
    const year: number = Number.parseInt(parts[0], 10);
    const month: number = Number.parseInt(parts[1], 10);
    const day: number = Number.parseInt(parts[2], 10);
    if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day)) {
      return new Date();
    }
    return new Date(year, month - 1, day);
  }

  /** 月份标题，month 为 0 基 */
  static monthTitle(year: number, month: number): string {
    return `${year}年${month + 1}月`;
  }

  /** 日期键的中文长文案：2026年9月19日 周六 */
  static formatKeyCn(key: string): string {
    const date: Date = CalendarUtil.keyToDate(key);
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 周${WEEK_LABELS[date.getDay()]}`;
  }

  /**
   * 构建某月的日历网格（周日开头）。
   * 月初按首日星期补齐前置占位格，月末补齐到整周，保证每行 7 格。
   * @param year 四位年份
   * @param month 0 基月份
   */
  static buildMonthCells(year: number, month: number): CalendarCell[] {
    const cells: CalendarCell[] = [];
    const today: string = CalendarUtil.todayKey();
    const firstWeekday: number = new Date(year, month, 1).getDay();
    const daysInMonth: number = new Date(year, month + 1, 0).getDate();

    for (let i = 0; i < firstWeekday; i++) {
      const blank: CalendarCell = { day: 0, dateKey: '', inMonth: false, isToday: false };
      cells.push(blank);
    }
    for (let day = 1; day <= daysInMonth; day++) {
      const key: string = CalendarUtil.dateKey(new Date(year, month, day));
      const cell: CalendarCell = { day: day, dateKey: key, inMonth: true, isToday: key === today };
      cells.push(cell);
    }
    while (cells.length % 7 !== 0) {
      const tail: CalendarCell = { day: 0, dateKey: '', inMonth: false, isToday: false };
      cells.push(tail);
    }
    return cells;
  }
}
