/**
 * 待办与日期备忘的本地存储服务
 *
 * 与笔记正文（.md 文件）分开：待办数据量小、结构固定，直接用 Preferences
 * 存 JSON 快照。损坏数据阻止覆盖并报告错误；写入失败恢复缓存。
 */
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TodoItem, DayNote } from '../common/types/TodoItem';
import { SnapshotStore } from './storage/SnapshotStore';

const PREFERENCES_NAME: string = 'flowmind_todos';
const TODOS_KEY: string = 'todos';
const DAYNOTES_KEY: string = 'daynotes';

export class TodoStorageService {
  private todoPreferences: preferences.Preferences | null = null;
  private snapshots: SnapshotStore = new SnapshotStore();

  private async ensure(context: Context): Promise<preferences.Preferences> {
    let prefs: preferences.Preferences | null = this.todoPreferences;
    if (prefs === null) {
      prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      this.todoPreferences = prefs;
    }
    return prefs;
  }

  /** 读取全部待办；缺失时返回空数组，损坏时报错并保留原数据 */
  async loadTodos(context: Context): Promise<TodoItem[]> {
    try { return await this.readTodos(context); }
    catch (error) { this.snapshots.block(TODOS_KEY); throw new Error(error instanceof Error ? error.message : '待办读取失败'); }
  }

  private async readTodos(context: Context): Promise<TodoItem[]> {
    const prefs: preferences.Preferences = await this.ensure(context);
    return await this.snapshots.read<TodoItem[]>(prefs, TODOS_KEY, (value: TodoItem[]) => this.isTodoArray(value)) || [];
  }

  /** 写入全部待办 */
  async saveTodos(context: Context, todos: TodoItem[]): Promise<void> {
    const prefs: preferences.Preferences = await this.ensure(context);
    await this.snapshots.write(prefs, TODOS_KEY, JSON.stringify(todos));
  }

  /** 读取全部日期备忘；缺失时返回空数组，损坏时报错并保留原数据 */
  async loadDayNotes(context: Context): Promise<DayNote[]> {
    try { return await this.readDayNotes(context); }
    catch (error) { this.snapshots.block(DAYNOTES_KEY); throw new Error(error instanceof Error ? error.message : '日期备忘读取失败'); }
  }

  private async readDayNotes(context: Context): Promise<DayNote[]> {
    const prefs: preferences.Preferences = await this.ensure(context);
    return await this.snapshots.read<DayNote[]>(prefs, DAYNOTES_KEY, (value: DayNote[]) => this.isDayNoteArray(value)) || [];
  }

  /** 写入全部日期备忘 */
  async saveDayNotes(context: Context, dayNotes: DayNote[]): Promise<void> {
    const prefs: preferences.Preferences = await this.ensure(context);
    await this.snapshots.write(prefs, DAYNOTES_KEY, JSON.stringify(dayNotes));
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
