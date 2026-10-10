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
  { name: 'note_outline', description: '读取指定笔记的标题大纲，快速定位章节。', permission: 'read',
    params: [{ name: 'identifier', jsonType: 'string', description: '笔记完整标题或 ID', required: true }] },
  { name: 'list_todos', description: '列出真实待办、日期与完成状态，便于规划复习。', permission: 'read',
    params: [{ name: 'date', jsonType: 'string', description: 'YYYY-MM-DD，留空查看全部日期', required: false },
      { name: 'status', jsonType: 'string', description: 'all、pending 或 done', required: false },
      { name: 'offset', jsonType: 'number', description: '从第几条开始，默认 0', required: false },
      { name: 'limit', jsonType: 'number', description: '每次 1–50 条，默认 50，按下一起点继续查询', required: false }] },
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
      { name: 'category', jsonType: 'string', description: '只看某个项目下的笔记，留空表示全部', required: false },
      { name: 'offset', jsonType: 'number', description: '从第几条开始，默认 0；用于遍历整个资料库', required: false },
      { name: 'limit', jsonType: 'number', description: '每次 1–50 条，默认 20', required: false }
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
    description: '分页读取指定笔记正文及 updatedAt；长文按下一起点继续读取到末尾。可传完整标题或唯一 ID。',
    permission: 'read',
    params: [
      { name: 'identifier', jsonType: 'string', description: '笔记的完整标题或 ID', required: true },
      { name: 'offset', jsonType: 'number', description: '正文字符起点，默认 0；继续读取用响应里的下一起点', required: false },
      { name: 'limit', jsonType: 'number', description: '每次 1–12000 字符，默认 12000', required: false }
    ]
  },
  {
    name: 'summarize_vault',
    description: '获取当前知识库的宏观统计概览（笔记总量、分类结构、常用标签分布），用于快速盘点知识库。',
    permission: 'read',
    params: []
  },
  {
    name: 'add_tag_to_note',
    description: '协助用户为指定笔记添加一个或多个知识标签（逗号分隔），用于多维知识分类。',
    permission: 'write',
    params: [
      { name: 'identifier', jsonType: 'string', description: '笔记标题或 ID', required: true },
      { name: 'tags', jsonType: 'string', description: '要追加的标签，多个用逗号隔开，如"机器学习,算法"', required: true }
    ]
  },
  {
    name: 'create_link',
    description: '在文字笔记末尾追加 [[目标笔记或概念]] 双链语法，建立知识关联。PDF、手写及正在编辑的正文不接受覆盖。',
    permission: 'write',
    params: [
      { name: 'sourceIdentifier', jsonType: 'string', description: '源笔记标题或 ID', required: true },
      { name: 'targetTitle', jsonType: 'string', description: '目标笔记或概念标题', required: true },
      { name: 'reason', jsonType: 'string', description: '建立双链的关联原因说明', required: false }
    ]
  },
  {
    name: 'categorize_note',
    description: '将笔记归档至指定的项目分类文件夹。',
    permission: 'write',
    params: [
      { name: 'identifier', jsonType: 'string', description: '笔记标题或 ID', required: true },
      { name: 'category', jsonType: 'string', description: '目标项目/文件夹分类名称', required: true }
    ]
  },
  {
    name: 'create_note',
    description: '新建一篇 Markdown 知识笔记。',
    permission: 'write',
    params: [
      { name: 'title', jsonType: 'string', description: '笔记标题', required: true },
      { name: 'category', jsonType: 'string', description: '所属项目分类，默认未分类', required: false },
      { name: 'tag', jsonType: 'string', description: '笔记标签，多个用逗号分隔', required: false },
      { name: 'content', jsonType: 'string', description: '笔记 Markdown 正文内容', required: true }
    ]
  },
  { name: 'rename_note', description: '重命名现有笔记，确认后保存；不修改正文或笔迹。', permission: 'write',
    params: [{ name: 'identifier', jsonType: 'string', description: '笔记 ID 或完整标题', required: true },
      { name: 'title', jsonType: 'string', description: '新的完整标题', required: true }] },
  { name: 'update_note', description: '更新 Markdown 笔记正文。先读取笔记取得 updatedAt，版本相同且用户确认后才能保存。PDF、手写、正在编辑的笔记不接受正文覆盖。', permission: 'write',
    params: [{ name: 'identifier', jsonType: 'string', description: '笔记 ID', required: true },
      { name: 'content', jsonType: 'string', description: '完整的新 Markdown 正文，不能省略未修改部分', required: true },
      { name: 'expectedUpdatedAt', jsonType: 'number', description: '读取返回的 updatedAt；版本变化时拒绝覆盖', required: true }] },
  { name: 'set_note_flag', description: '设置资料收藏或置顶，确认后更新。', permission: 'write',
    params: [{ name: 'identifier', jsonType: 'string', description: '笔记 ID 或完整标题', required: true },
      { name: 'flag', jsonType: 'string', description: 'favorite 或 pinned', required: true },
      { name: 'value', jsonType: 'string', description: 'yes 或 no', required: true }] },
  { name: 'set_todo_status', description: '按唯一待办 ID 设置完成状态，重复设置不会反转。', permission: 'write',
    params: [{ name: 'identifier', jsonType: 'string', description: 'list_todos 返回的待办 ID', required: true },
      { name: 'status', jsonType: 'string', description: 'pending 或 done', required: true }] }
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

    const paramsSchema: string = `{"type":"object","properties":{${properties}},"required":${JSON.stringify(required)},"additionalProperties":false}`;
    out += `{"type":"function","function":{"name":${JSON.stringify(t.name)},`
      + `"description":${JSON.stringify(t.description)},"parameters":${paramsSchema}}}`;
  }
  out += ']';
  return out;
}

/** 取工具调用的展示名（用于确认弹窗标题） */
export function toolDisplayName(name: string): string {
  if (name === 'note_outline') { return '读取章节大纲'; }
  if (name === 'list_todos') { return '查看待办日程'; }
  if (name === 'rename_note') { return '重命名笔记'; }
  if (name === 'update_note') { return '更新笔记正文'; }
  if (name === 'set_note_flag') { return '设置收藏或置顶'; }
  if (name === 'set_todo_status') { return '更新待办状态'; }
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
  if (name === 'add_tag_to_note') {
    return '添加分类标签';
  }
  if (name === 'create_link') {
    return '建立双链引用';
  }
  if (name === 'categorize_note') {
    return '调整所属项目';
  }
  if (name === 'create_note') {
    return '新建知识笔记';
  }
  return name;
}

/** 把工具结果包装成 role=tool 的消息回灌给模型 */
export function buildToolResultMessage(toolCallId: string, content: string): ChatMessage {
  return { role: 'tool', content, toolCallId };
}
