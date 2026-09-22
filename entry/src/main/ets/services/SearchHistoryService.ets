/**
 * 搜索历史的本地存储（功能8）
 *
 * 与待办一样走 Preferences 存 JSON 数组：数据量小、结构固定。
 * 只保留最近若干条、去重、最新在前；解析失败一律回退为空数组。
 */
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME: string = 'flowmind_search';
const HISTORY_KEY: string = 'history';
const MAX_HISTORY: number = 12;

export class SearchHistoryService {
  private prefs: preferences.Preferences | null = null;

  private async ensure(context: Context): Promise<preferences.Preferences> {
    let p: preferences.Preferences | null = this.prefs;
    if (p === null) {
      p = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      this.prefs = p;
    }
    return p;
  }

  /** 读取历史；缺失或损坏时返回空数组 */
  async load(context: Context): Promise<string[]> {
    const p: preferences.Preferences = await this.ensure(context);
    const stored = await p.get(HISTORY_KEY, '');
    if (typeof stored !== 'string' || stored.length === 0) {
      return [];
    }
    try {
      const parsed: string[] = JSON.parse(stored) as string[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const out: string[] = [];
      for (let i = 0; i < parsed.length; i++) {
        if (typeof parsed[i] === 'string' && parsed[i].length > 0) {
          out.push(parsed[i]);
        }
      }
      return out;
    } catch (error) {
      console.error(`搜索历史解析失败: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /** 写入整份历史 */
  async save(context: Context, history: string[]): Promise<void> {
    const p: preferences.Preferences = await this.ensure(context);
    await p.put(HISTORY_KEY, JSON.stringify(history));
    await p.flush();
  }

  /**
   * 记录一条查询：去重后置顶，超过上限截断，落盘并返回最新历史。
   * 空串忽略。
   */
  async push(context: Context, current: string[], keyword: string): Promise<string[]> {
    const kw: string = keyword.trim();
    if (kw.length === 0) {
      return current;
    }
    const next: string[] = [kw];
    for (let i = 0; i < current.length; i++) {
      if (current[i] !== kw) {
        next.push(current[i]);
      }
    }
    const capped: string[] = next.length > MAX_HISTORY ? next.slice(0, MAX_HISTORY) : next;
    await this.save(context, capped);
    return capped;
  }

  /** 清空历史并落盘 */
  async clear(context: Context): Promise<void> {
    await this.save(context, []);
  }
}
