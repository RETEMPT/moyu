import { SmartContent } from '../../common/types/SmartContent';
import { SmartTask } from '../../common/types/SmartTask';
import { NoteItem } from '../../common/types/NoteItem';
import { TodoItem } from '../../common/types/TodoItem';
import { SmartNoteBuilder } from './SmartNoteBuilder';

/** 平台存储通过接口注入，可独立验证失败与重试的写入顺序。 */
export interface SmartCaptureStorage {
  currentNotes: () => NoteItem[];
  currentTodos: () => TodoItem[];
  writeDocument: (note: NoteItem) => Promise<void>;
  writeNotes: (notes: NoteItem[]) => Promise<void>;
  writeTodos: (todos: TodoItem[]) => Promise<void>;
}

export class SmartCaptureService {
  static async commit(content: SmartContent, tasks: SmartTask[], storage: SmartCaptureStorage): Promise<NoteItem> {
    const note = SmartNoteBuilder.buildNote(content, tasks);
    try {
      await storage.writeDocument(note);
      await storage.writeNotes([note].concat(storage.currentNotes().filter((item: NoteItem) => item.id !== note.id)));
    } catch {
      throw new Error('笔记保存未成功，排版内容已保留，请重试。');
    }
    const currentTodos = storage.currentTodos();
    const nextTodos = SmartNoteBuilder.buildTodos(tasks, note.id)
      .concat(currentTodos.filter((item: TodoItem) => !item.id.startsWith(note.id + '-todo-')));
    try {
      if (tasks.length > 0 || nextTodos.length !== currentTodos.length) {
        await storage.writeTodos(nextTodos);
      }
    } catch {
      throw new Error('笔记已保存，但待办同步失败。请重试，已有笔记不会重复创建。');
    }
    return note;
  }
}
