import { AgentToolExecutor, AgentToolResult } from '../../common/types/AgentTypes';
import { ToolArgumentValidator } from './ToolArgumentValidator';
import { toolDisplayName } from './ToolRegistry';

export interface WorkspaceToolPorts {
  search: (query: string, limit: number) => string;
  list: (category: string, offset?: number, limit?: number) => string;
  read: (identifier: string, offset?: number, limit?: number) => string;
  summarize: () => string;
  outline: (identifier: string) => string;
  todos: (date: string, status: string, offset?: number, limit?: number) => string;
  createTodo: (date: string, title: string) => Promise<string>;
  addTag: (identifier: string, tags: string) => Promise<string>;
  createLink: (source: string, target: string, reason?: string) => Promise<string>;
  categorize: (identifier: string, category: string) => Promise<string>;
  createNote: (title: string, category: string, tag: string, content: string) => Promise<string>;
  progress: (text: string) => void;
  manageNote?: (operation: string, identifier: string, value: string, expectedUpdatedAt: number) => Promise<string>;
  setTodoStatus?: (identifier: string, status: string) => Promise<string>;
}

export class WorkspaceToolExecutor implements AgentToolExecutor {
  private ports: WorkspaceToolPorts;
  constructor(ports: WorkspaceToolPorts) { this.ports = ports; }
  async execute(name: string, json: string): Promise<AgentToolResult> {
    try {
      const a = ToolArgumentValidator.parse(name, json);
      this.ports.progress(`正在${toolDisplayName(name)}…`);
      let content = '';
      switch (name) {
        case 'search_notes': content = this.ports.search(a.query!.trim(), a.limit || 5); break;
        case 'list_notes': content = this.ports.list((a.category || '').trim(), a.offset || 0, a.limit || 20); break;
        case 'read_note': content = this.ports.read(a.identifier!.trim(), a.offset || 0, a.limit || 12000); break;
        case 'summarize_vault': content = this.ports.summarize(); break;
        case 'note_outline': content = this.ports.outline(a.identifier!.trim()); break;
        case 'list_todos': content = this.ports.todos(a.date || '', a.status || 'all', a.offset || 0, a.limit || 50); break;
        case 'create_todo': content = await this.ports.createTodo(ToolArgumentValidator.date(a.date), a.title!.trim()); break;
        case 'add_tag_to_note': content = await this.ports.addTag(a.identifier!.trim(), a.tags!.trim()); break;
        case 'create_link': content = await this.ports.createLink(a.sourceIdentifier!.trim(), a.targetTitle!.trim(), a.reason); break;
        case 'categorize_note': content = await this.ports.categorize(a.identifier!.trim(), a.category!.trim()); break;
        case 'create_note': content = await this.ports.createNote(a.title!.trim(), (a.category || '未分类').trim(), a.tag || '', a.content!); break;
        case 'rename_note': case 'update_note': case 'set_note_flag':
          if (!this.ports.manageNote) { throw new Error('当前工作区不支持此修改'); }
          content = await this.ports.manageNote(name, a.identifier!.trim(), name === 'rename_note' ? a.title!.trim() :
            name === 'update_note' ? a.content! : `${a.flag}:${a.value}`, a.expectedUpdatedAt || 0); break;
        case 'set_todo_status':
          if (!this.ports.setTodoStatus) { throw new Error('当前工作区不支持修改待办'); }
          content = await this.ports.setTodoStatus(a.identifier!.trim(), a.status!); break;
      }
      this.ports.progress(`${toolDisplayName(name)}已完成`);
      return { ok: true, content };
    } catch (error) {
      const message = error instanceof Error ? error.message : '操作失败';
      this.ports.progress(`${toolDisplayName(name)}失败：${message}`);
      return { ok: false, content: message };
    }
  }
}
