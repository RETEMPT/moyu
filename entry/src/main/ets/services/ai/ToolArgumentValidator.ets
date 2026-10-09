import { findTool } from './ToolRegistry';

export interface ToolArguments {
  query?: string; limit?: number; category?: string; identifier?: string;
  title?: string; date?: string; tags?: string; sourceIdentifier?: string;
  targetTitle?: string; reason?: string; tag?: string; content?: string; status?: string;
  offset?: number; expectedUpdatedAt?: number; flag?: string; value?: string;
}

export class ToolArgumentValidator {
  private static value(a: ToolArguments, key: string): string | number | undefined {
    switch (key) {
      case 'query': return a.query; case 'limit': return a.limit; case 'category': return a.category;
      case 'identifier': return a.identifier; case 'title': return a.title; case 'date': return a.date;
      case 'tags': return a.tags; case 'sourceIdentifier': return a.sourceIdentifier;
      case 'targetTitle': return a.targetTitle; case 'reason': return a.reason;
      case 'tag': return a.tag; case 'content': return a.content; case 'status': return a.status;
      case 'offset': return a.offset; case 'expectedUpdatedAt': return a.expectedUpdatedAt;
      case 'flag': return a.flag; case 'value': return a.value;
      default: return undefined;
    }
  }

  static parse(name: string, json: string): ToolArguments {
    const tool = findTool(name);
    if (tool === null) { throw new Error('工具不存在'); }
    if (json.length > 32000) { throw new Error('工具参数过长'); }
    const args = JSON.parse(json) as ToolArguments;
    if (args === null || typeof args !== 'object' || Array.isArray(args)) { throw new Error('工具参数必须是 JSON 对象'); }
    for (const key of Object.keys(args)) {
      if (!tool.params.some((param) => param.name === key)) { throw new Error(`不支持的参数：${key}`); }
    }
    for (const param of tool.params) {
      const value = ToolArgumentValidator.value(args, param.name);
      if (value === undefined) { if (param.required) { throw new Error(`缺少参数：${param.name}`); } continue; }
      if (typeof value !== param.jsonType) { throw new Error(`参数 ${param.name} 类型错误`); }
      if (typeof value === 'string') {
        if (param.required && !value.trim()) { throw new Error(`参数 ${param.name} 不能为空`); }
        if (value.length > (param.name === 'content' ? 20000 : 2000)) { throw new Error(`参数 ${param.name} 过长`); }
      } else {
        const min = param.name === 'offset' || param.name === 'expectedUpdatedAt' ? 0 : 1;
        const max = param.name === 'offset' ? 1000000 : param.name === 'expectedUpdatedAt' ? Number.MAX_SAFE_INTEGER :
          name === 'read_note' ? 12000 : name === 'list_notes' || name === 'list_todos' ? 50 : 10;
        if (!Number.isSafeInteger(value) || value < min || value > max) { throw new Error(`参数 ${param.name} 需为 ${min}–${max} 的整数`); }
      }
    }
    if (args.date && args.date.trim()) { args.date = ToolArgumentValidator.date(args.date); }
    if (name === 'create_link' && /[\[\]\r\n]/.test(args.targetTitle || '')) { throw new Error('双链目标不能包含括号或换行'); }
    if (args.status && !['all', 'pending', 'done'].includes(args.status)) { throw new Error('待办状态需为 all、pending 或 done'); }
    if (name === 'set_todo_status' && !['pending', 'done'].includes(args.status || '')) { throw new Error('请选择 pending 或 done'); }
    if (name === 'set_note_flag' && (!['favorite', 'pinned'].includes(args.flag || '') || !['yes', 'no'].includes(args.value || ''))) { throw new Error('收藏/置顶参数无效'); }
    if (name === 'rename_note' && /[\r\n]/.test(args.title || '')) { throw new Error('笔记标题不能包含换行'); }
    return args;
  }

  static date(value: string = ''): string {
    const today = new Date();
    if (!value.trim() || value.trim() === '今天' || value.trim() === '明天') {
      if (value.trim() === '明天') { today.setDate(today.getDate() + 1); }
      return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    }
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
    if (!match) { throw new Error('请提供明确的 YYYY-MM-DD 日期'); }
    const year = Number(match[1]); const month = Number(match[2]); const day = Number(match[3]);
    const date = new Date(year, month - 1, day);
    if (year < 1900 || date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) { throw new Error('日期不存在'); }
    return value.trim();
  }
}
