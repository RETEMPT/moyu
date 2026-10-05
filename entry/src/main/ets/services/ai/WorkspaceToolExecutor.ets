import { AgentToolExecutor, AgentToolResult } from '../../common/types/AgentTypes';
import { ToolArgumentValidator } from './ToolArgumentValidator';
import { toolDisplayName } from './ToolRegistry';

export interface WorkspaceToolPorts {
  search: (query: string, limit: number) => string;
  list: (category: string) => string;
  read: (identifier: string) => string;
  summarize: () => string;
  outline: (identifier: string) => string;
  todos: (date: string, status: string) => string;
  createTodo: (date: string, title: string) => Promise<string>;
  addTag: (identifier: string, tags: string) => Promise<string>;
  createLink: (source: string, target: string, reason?: string) => Promise<string>;
  categorize: (identifier: string, category: string) => Promise<string>;
  createNote: (title: string, category: string, tag: string, content: string) => Promise<string>;
  progress: (text: string) => void;
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
        case 'list_notes': content = this.ports.list((a.category || '').trim()); break;
        case 'read_note': content = this.ports.read(a.identifier!.trim()); break;
        case 'summarize_vault': content = this.ports.summarize(); break;
        case 'note_outline': content = this.ports.outline(a.identifier!.trim()); break;
        case 'list_todos': content = this.ports.todos(a.date || '', a.status || 'all'); break;
        case 'create_todo': content = await this.ports.createTodo(ToolArgumentValidator.date(a.date), a.title!.trim()); break;
        case 'add_tag_to_note': content = await this.ports.addTag(a.identifier!.trim(), a.tags!.trim()); break;
        case 'create_link': content = await this.ports.createLink(a.sourceIdentifier!.trim(), a.targetTitle!.trim(), a.reason); break;
        case 'categorize_note': content = await this.ports.categorize(a.identifier!.trim(), a.category!.trim()); break;
        case 'create_note': content = await this.ports.createNote(a.title!.trim(), (a.category || '未分类').trim(), a.tag || '', a.content!); break;
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
