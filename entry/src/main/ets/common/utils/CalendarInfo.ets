import { intl } from '@kit.LocalizationKit';
export interface CalendarInfoValue { lunar: string; festival: string; schedule: string; lunarLong: string; }
interface HolidayRange { start: string; end: string; name: string; }
// 国办发明电〔2025〕7号；全国安排，地方与单位安排由使用者另行核对。
const HOLIDAYS_2026: HolidayRange[] = [
  { start: '2026-01-01', end: '2026-01-03', name: '元旦' },
  { start: '2026-02-15', end: '2026-02-23', name: '春节' },
  { start: '2026-04-04', end: '2026-04-06', name: '清明' },
  { start: '2026-05-01', end: '2026-05-05', name: '劳动节' },
  { start: '2026-06-19', end: '2026-06-21', name: '端午' },
  { start: '2026-09-25', end: '2026-09-27', name: '中秋' },
  { start: '2026-10-01', end: '2026-10-07', name: '国庆' }
];
const WORKDAYS_2026: string[] = ['2026-01-04', '2026-02-14', '2026-02-28', '2026-05-09', '2026-09-20', '2026-10-10'];
const DAY_NAMES: string[] = ['初一','初二','初三','初四','初五','初六','初七','初八','初九','初十','十一','十二','十三','十四','十五','十六','十七','十八','十九','二十','廿一','廿二','廿三','廿四','廿五','廿六','廿七','廿八','廿九','三十'];

export class CalendarInfo {
  static readonly HOLIDAY_SOURCE: string = 'https://www.beijing.gov.cn/cs/gncs/zcwj/202603/t20260327_4568275.html';
  private static cache: Map<string, CalendarInfoValue> = new Map();
  private static formatter: intl.DateTimeFormat | null = null;
  static forDate(key: string): CalendarInfoValue {
    const cached = CalendarInfo.cache.get(key); if (cached) { return cached; }
    const result: CalendarInfoValue = { lunar: '', festival: '', schedule: '', lunarLong: '' };
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) { return result; }
    // Calendar labels describe the China date key, independent of the device time zone.
    const date = new Date(`${key}T12:00:00+08:00`);
    if (isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== key) { return result; }
    try {
      if (!CalendarInfo.formatter) { CalendarInfo.formatter = new intl.DateTimeFormat('zh-CN-u-ca-chinese', { timeZone: 'Asia/Shanghai', month: 'long', day: 'numeric' }); }
      const formatted = CalendarInfo.formatter.format(date);
      const lunar = formatted.match(/([正冬腊閏闰一二三四五六七八九十]+月)\s*(\d{1,2})/);
      if (lunar) {
        const day = Number(lunar[2]); const dayName = DAY_NAMES[day - 1] || '';
        result.lunar = day === 1 ? lunar[1] : dayName; result.lunarLong = `${lunar[1]}${dayName}`;
        if (lunar[1] === '正月' && day === 1) { result.festival = '春节'; }
        else if (lunar[1] === '正月' && day === 15) { result.festival = '元宵'; }
        else if (lunar[1] === '五月' && day === 5) { result.festival = '端午'; }
        else if (lunar[1] === '七月' && day === 7) { result.festival = '七夕'; }
        else if (lunar[1] === '八月' && day === 15) { result.festival = '中秋'; }
        else if (lunar[1] === '九月' && day === 9) { result.festival = '重阳'; }
      }
    } catch { /* Keep verified public holiday data available if the ICU calendar is unavailable. */ }
      const fixed = key.slice(5);
      if (fixed === '01-01') { result.festival = '元旦'; }
      else if (fixed === '05-01') { result.festival = '劳动节'; }
      else if (fixed === '10-01') { result.festival = '国庆'; }
      if (WORKDAYS_2026.includes(key)) { result.schedule = '班'; }
      else {
        const holiday = HOLIDAYS_2026.find((range: HolidayRange) => key >= range.start && key <= range.end);
        if (holiday) { result.schedule = '休'; if (!result.festival) { result.festival = holiday.name; } }
      }
    if (CalendarInfo.cache.size >= 800) { CalendarInfo.cache.clear(); }
    CalendarInfo.cache.set(key, result); return result;
  }
}
