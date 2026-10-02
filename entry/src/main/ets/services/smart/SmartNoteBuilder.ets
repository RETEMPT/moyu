import { SmartContent } from '../../common/types/SmartContent';
import { SmartTask } from '../../common/types/SmartTask';
import { NoteItem } from '../../common/types/NoteItem';
import { TodoItem } from '../../common/types/TodoItem';

/** 预览与保存共用正文生成逻辑，保留可追溯的原文。 */
export class SmartNoteBuilder {
  static buildNote(content: SmartContent, tasks: SmartTask[]): NoteItem {
    const now = Date.now();
    const body = SmartNoteBuilder.buildMarkdown(content, tasks, true);
    return { id: `smart-note-${content.id}`, title: content.title.trim(), category: content.category || '未分类',
      type: 'Markdown', previewText: content.summary || body.slice(0, 100),
      tag: content.tags.join(', '), tagColor: '#4F46E5', updateTime: '刚刚', contentDetail: body,
      tags: content.tags, aiSummary: content.summary, aiTags: content.tags,
      createdAt: content.createdAt, updatedAt: now };
  }

  static buildTodos(tasks: SmartTask[], noteId: string, now: Date = new Date()): TodoItem[] {
    return tasks.map((task: SmartTask) => {
      const deadline = task.deadline || '';
      const todo: TodoItem = { id: `${noteId}-todo-${task.id}`,
        date: SmartNoteBuilder.resolveDeadline(deadline, now) || SmartNoteBuilder.dateKey(now),
        title: task.title + (deadline.length > 0 ? ` [截止: ${deadline}]` : ''), done: false,
        noteRefs: [noteId], createdAt: now.getTime(), updatedAt: now.getTime() };
      return todo;
    });
  }

  static buildMarkdown(content: SmartContent, tasks: SmartTask[], includeRelations: boolean = false): string {
    let body = (content.formattedMarkdown || content.rawMarkdown || '').trim();
    if (/^#\s+[^\n]*/.test(body)) {
      body = body.replace(/^#\s+[^\n]*/, () => `# ${content.title.trim()}`);
    } else {
      body = `# ${content.title.trim()}\n\n${body}`;
    }
    if (tasks.length > 0) {
      body += '\n\n## 已选日历待办\n\n';
      for (const task of tasks) {
        body += `- [ ] ${task.title}${task.deadline ? '（' + task.deadline + '）' : ''}\n`;
      }
    }
    if (includeRelations && content.relations.length > 0) {
      body += '\n\n## 关联笔记\n\n';
      for (const relation of content.relations) {
        body += `- [[${relation.targetTitle}]]${relation.reason ? '：' + relation.reason : ''}\n`;
      }
    }
    if (content.rawMarkdown && content.rawMarkdown.length > 0) {
      body += '\n\n---\n\n## 识别与输入原文\n\n';
      body += content.rawMarkdown.split('\n').map((line: string) => `> ${line}`).join('\n');
    }
    return body.trim() + '\n';
  }

  /** 只自动采用明确年月日和相对天数，模糊日期留给用户确认。 */
  static resolveDeadline(deadline: string, reference: Date = new Date()): string {
    const text = deadline.trim();
    const relativeDays: string[] = ['今天', '明天', '后天'];
    const relativeIndex = relativeDays.indexOf(text);
    if (relativeIndex >= 0) {
      return SmartNoteBuilder.dateKey(new Date(reference.getFullYear(), reference.getMonth(), reference.getDate() + relativeIndex));
    }
    const match = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/) ||
      text.match(/^(\d{4})年(\d{1,2})月(\d{1,2})日(?:前)?$/);
    if (!match) {
      return '';
    }
    const year = Number(match[1]);
    const month = Number(match[2]);
    const day = Number(match[3]);
    const date = new Date(year, month - 1, day);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
      return '';
    }
    return SmartNoteBuilder.dateKey(date);
  }

  static dateKey(date: Date): string {
    return `${date.getFullYear()}-${('0' + (date.getMonth() + 1)).slice(-2)}-${('0' + date.getDate()).slice(-2)}`;
  }
}
