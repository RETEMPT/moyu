/**
 * Agent 工具调用类型
 *
 * 工具清单与执行结果的公共形状。执行逻辑不在这里：工具要读写的笔记与待办
 * 归 Index 持有，因此由调用方注入执行器（见 AgentOrchestrator 的 AgentToolExecutor）。
 */

/** 工具权限分级：read 自动执行，write 必须先经用户确认 */
export type ToolPermission = 'read' | 'write';

/** 工具的一个入参 */
export interface AgentToolParam {
  name: string;
  /** JSON Schema 类型，当前只用到 'string' | 'number' */
  jsonType: string;
  description: string;
  required: boolean;
}

/** 一个可被模型请求的工具 */
export interface AgentToolSpec {
  name: string;
  description: string;
  permission: ToolPermission;
  params: AgentToolParam[];
}

/** 工具执行结果。content 会原样回灌给模型，因此必须是模型能读懂的自然语言或 JSON */
export interface AgentToolResult {
  ok: boolean;
  content: string;
}

/** 工具执行器：由 UI 层实现，负责真正读写本地数据 */
export interface AgentToolExecutor {
  execute(toolName: string, argsJson: string): Promise<AgentToolResult>;
}
