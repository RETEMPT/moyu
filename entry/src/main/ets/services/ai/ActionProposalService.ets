import { AgentToolExecutor, AgentToolResult } from '../../common/types/AgentTypes';
import { ToolArguments } from './ToolArgumentValidator';

export interface ProposedActionItem {
  id: string; type: string; title: string; desc: string;
  target?: string; value?: string; source?: string; date?: string; content?: string;
}
export interface ActionProposalData { summary: string; actions: ProposedActionItem[]; }

export class ActionProposalService {
  static async execute(action: ProposedActionItem, executor: AgentToolExecutor): Promise<AgentToolResult> {
    let name = '';
    let args: ToolArguments = {};
    switch (action.type) {
      case 'todo': name = 'create_todo'; args = { title: action.title || action.desc, date: action.date || '' }; break;
      case 'tag': name = 'add_tag_to_note'; args = { identifier: action.target || action.title, tags: action.value || action.desc }; break;
      case 'link': name = 'create_link'; args = { sourceIdentifier: action.source || action.title, targetTitle: action.target || action.value, reason: action.desc }; break;
      case 'category': name = 'categorize_note'; args = { identifier: action.target || action.title, category: action.value || action.desc }; break;
      case 'note': name = 'create_note'; args = { title: action.title, category: action.target || '未分类', tag: action.value || '', content: action.content || action.desc }; break;
      default: return { ok: false, content: '方案包含不支持的操作类型' };
    }
    return await executor.execute(name, JSON.stringify(args));
  }
}
