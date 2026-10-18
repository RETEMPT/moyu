/**
 * 待办与日期备忘的本地存储服务
 *
 * 待办、笔记关联和日期备忘存入统一关系数据库；旧 Preferences 仅用于首次校验迁移。
 */
import { Context } from '@kit.AbilityKit';
import { TodoItem, DayNote } from '../common/types/TodoItem';
import { DomainStorage } from './storage/DomainStorage';

const PREFERENCES_NAME: string = 'flowmind_todos';
const TODOS_KEY: string = 'todos';
const DAYNOTES_KEY: string = 'daynotes';

export class TodoStorageService {
  private domain: DomainStorage = new DomainStorage();

  /** 读取全部待办；缺失时返回空数组，损坏时报错并保留原数据 */
  async loadTodos(context: Context): Promise<TodoItem[]> {
    return await this.domain.load<TodoItem[]>(context, TODOS_KEY, PREFERENCES_NAME, TODOS_KEY, (value: TodoItem[]) => this.isTodoArray(value)) || [];
  }

  /** 写入全部待办 */
  async saveTodos(context: Context, todos: TodoItem[]): Promise<void> {
    await this.domain.save<TodoItem[]>(context, TODOS_KEY, PREFERENCES_NAME, TODOS_KEY, todos, (value: TodoItem[]) => this.isTodoArray(value));
  }

  /** 读取全部日期备忘；缺失时返回空数组，损坏时报错并保留原数据 */
  async loadDayNotes(context: Context): Promise<DayNote[]> {
    return await this.domain.load<DayNote[]>(context, DAYNOTES_KEY, PREFERENCES_NAME, DAYNOTES_KEY, (value: DayNote[]) => this.isDayNoteArray(value)) || [];
  }

  /** 写入全部日期备忘 */
  async saveDayNotes(context: Context, dayNotes: DayNote[]): Promise<void> {
    await this.domain.save<DayNote[]>(context, DAYNOTES_KEY, PREFERENCES_NAME, DAYNOTES_KEY, dayNotes, (value: DayNote[]) => this.isDayNoteArray(value));
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
        || typeof item.done !== 'boolean'
        || (item.noteRefs !== undefined && (!Array.isArray(item.noteRefs) || !item.noteRefs.every((id: string) => typeof id === 'string')))) {
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
