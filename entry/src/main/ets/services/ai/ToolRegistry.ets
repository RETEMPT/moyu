/**
 * 工具注册表
 *
 * 只声明「模型能请求什么」，不含执行逻辑——执行由调用方（AiWorkspace）注入，
 * 因为工具要读写的笔记与待办状态归 Index 持有。
 *
 * 权限分级决定是否需要用户确认：
 *   read  —— 只读查询，自动执行
 *   write —— 会产生副作用，必须先弹确认
 */
import { AgentToolSpec } from '../../common/types/AgentTypes';
import { ChatMessage } from '../../common/types/ModelConfig';

/** 内置工具清单 */
export const AGENT_TOOLS: AgentToolSpec[] = [
  {
    name: 'search_notes',
    description: '在当前资料库中按关键词检索笔记片段，返回命中的笔记标题、章节与正文摘录。用于回答关于用户笔记内容的问题。',
    permission: 'read',
    params: [
      { name: 'query', jsonType: 'string', description: '检索关键词', required: true },
      { name: 'limit', jsonType: 'number', description: '最多返回几条，默认 5', required: false }
    ]
  },
  {
    name: 'list_notes',
    description: '列出资料库中的笔记清单（标题、所属项目、标签、更新时间）。用于了解用户有哪些笔记。',
    permission: 'read',
    params: [
      { name: 'category', jsonType: 'string', description: '只看某个项目下的笔记，留空表示全部', required: false }
    ]
  },
  {
    name: 'create_todo',
    description: '为用户新建一条待办事项。这是写操作，会真实改变用户数据。',
    permission: 'write',
    params: [
      { name: 'title', jsonType: 'string', description: '待办标题', required: true },
      { name: 'date', jsonType: 'string', description: '日期，格式 YYYY-MM-DD；留空表示今天', required: false }
    ]
  },
  {
    name: 'read_note',
    description: '读取指定笔记的完整正文内容。可传入笔记标题 title 或唯一 ID。用于深入精读并全面回答问题。',
    permission: 'read',
    params: [
      { name: 'identifier', jsonType: 'string', description: '笔记的完整标题或 ID', required: true }
    ]
  },
  {
    name: 'summarize_vault',
    description: '获取当前知识库的宏观统计概览（笔记总量、分类结构、常用标签分布），用于快速盘点知识库。',
    permission: 'read',
    params: []
  }
];

/** 按名称查工具定义 */
export function findTool(name: string): AgentToolSpec | null {
  for (const t of AGENT_TOOLS) {
    if (t.name === name) {
      return t;
    }
  }
  return null;
}

/**
 * 生成 OpenAI 兼容协议的 tools 字段（JSON 数组字符串）。
 * 没有工具时返回空串，调用方据此不携带 tools 字段。
 */
export function buildOpenAiToolsJson(tools: AgentToolSpec[]): string {
  if (tools.length === 0) {
    return '';
  }
  let out: string = '[';
  let first: boolean = true;
  for (const t of tools) {
    if (!first) {
      out += ',';
    }
    first = false;

    let properties: string = '';
    const required: string[] = [];
    let firstParam: boolean = true;
    for (const p of t.params) {
      if (!firstParam) {
        properties += ',';
      }
      firstParam = false;
      properties += `${JSON.stringify(p.name)}:{"type":${JSON.stringify(p.jsonType)},"description":${JSON.stringify(p.description)}}`;
      if (p.required) {
        required.push(p.name);
      }
    }

    const paramsSchema: string = `{"type":"object","properties":{${properties}},"required":${JSON.stringify(required)}}`;
    out += `{"type":"function","function":{"name":${JSON.stringify(t.name)},`
      + `"description":${JSON.stringify(t.description)},"parameters":${paramsSchema}}}`;
  }
  out += ']';
  return out;
}

/** 取工具调用的展示名（用于确认弹窗标题） */
export function toolDisplayName(name: string): string {
  if (name === 'search_notes') {
    return '检索笔记';
  }
  if (name === 'list_notes') {
    return '列出笔记';
  }
  if (name === 'create_todo') {
    return '新建待办';
  }
  if (name === 'read_note') {
    return '阅读笔记全文';
  }
  if (name === 'summarize_vault') {
    return '知识库概览';
  }
  return name;
}

/** 把工具结果包装成 role=tool 的消息回灌给模型 */
export function buildToolResultMessage(toolCallId: string, content: string): ChatMessage {
  return { role: 'tool', content, toolCallId };
}
