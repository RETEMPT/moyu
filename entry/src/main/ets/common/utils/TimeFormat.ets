/**
 * 时间格式化工具
 *
 * 阅读器元数据行、列表时间戳与元数据快照落盘共用同一套格式，
 * 避免各视图各自实现导致「更新于」显示不一致。
 */

export class TimeFormat {
  /**
   * 将时间格式化为「M月D日 HH:mm」形式的本地时间字符串。
   * @param date 待格式化的时间对象
   * @returns 形如 `9月18日 17:09` 的时间字符串
   */
  static format(date: Date): string {
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const hour: string = date.getHours() < 10 ? `0${date.getHours()}` : `${date.getHours()}`;
    const minute: string = date.getMinutes() < 10 ? `0${date.getMinutes()}` : `${date.getMinutes()}`;
    return `${month}月${day}日 ${hour}:${minute}`;
  }

  /**
   * 以当前系统时间生成「刚刚修改」的时间戳文案。
   * @returns 形如 `9月18日 17:09` 的当前时间字符串
   */
  static now(): string {
    return TimeFormat.format(new Date());
  }
}
