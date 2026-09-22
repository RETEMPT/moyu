/**
 * 待办与日期备忘的本地存储服务
 *
 * 与笔记正文（.md 文件）分开：待办数据量小、结构固定，直接用 Preferences
 * 存 JSON 快照即可。解析失败一律回退为空数组，绝不因脏数据让模块崩溃。
 */
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TodoItem, DayNote } from '../common/types/TodoItem';

const PREFERENCES_NAME: string = 'flowmind_todos';
const TODOS_KEY: string = 'todos';
const DAYNOTES_KEY: string = 'daynotes';

export class TodoStorageService {
  private todoPreferences: preferences.Preferences | null = null;

  private async ensure(context: Context): Promise<preferences.Preferences> {
    let prefs: preferences.Preferences | null = this.todoPreferences;
    if (prefs === null) {
      prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      this.todoPreferences = prefs;
    }
    return prefs;
  }

  /** 读取全部待办；缺失或损坏时返回空数组 */
  async loadTodos(context: Context): Promise<TodoItem[]> {
    const prefs: preferences.Preferences = await this.ensure(context);
    const stored = await prefs.get(TODOS_KEY, '');
    if (typeof stored !== 'string' || stored.length === 0) {
      return [];
    }
    try {
      const parsed: TodoItem[] = JSON.parse(stored) as TodoItem[];
      return this.isTodoArray(parsed) ? parsed : [];
    } catch (error) {
      console.error(`待办快照解析失败: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /** 写入全部待办 */
  async saveTodos(context: Context, todos: TodoItem[]): Promise<void> {
    const prefs: preferences.Preferences = await this.ensure(context);
    await prefs.put(TODOS_KEY, JSON.stringify(todos));
    await prefs.flush();
  }

  /** 读取全部日期备忘；缺失或损坏时返回空数组 */
  async loadDayNotes(context: Context): Promise<DayNote[]> {
    const prefs: preferences.Preferences = await this.ensure(context);
    const stored = await prefs.get(DAYNOTES_KEY, '');
    if (typeof stored !== 'string' || stored.length === 0) {
      return [];
    }
    try {
      const parsed: DayNote[] = JSON.parse(stored) as DayNote[];
      return this.isDayNoteArray(parsed) ? parsed : [];
    } catch (error) {
      console.error(`日期备忘快照解析失败: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /** 写入全部日期备忘 */
  async saveDayNotes(context: Context, dayNotes: DayNote[]): Promise<void> {
    const prefs: preferences.Preferences = await this.ensure(context);
    await prefs.put(DAYNOTES_KEY, JSON.stringify(dayNotes));
    await prefs.flush();
  }

  private isTodoArray(value: TodoItem[]): boolean {
    if (!Array.isArray(value)) {
      return false;
    }
    for (const item of value) {
      if (item === null
        || typeof item.id !== 'string'
        || typeof item.date !== 'string'
        || typeof item.title !== 'string'
        || typeof item.done !== 'boolean') {
        return false;
      }
    }
    return true;
  }

  private isDayNoteArray(value: DayNote[]): boolean {
    if (!Array.isArray(value)) {
      return false;
    }
    for (const item of value) {
      if (item === null || typeof item.date !== 'string' || typeof item.text !== 'string') {
        return false;
      }
    }
    return true;
  }
}
