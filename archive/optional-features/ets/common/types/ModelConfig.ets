/**
 * 模型接入配置类型
 *
 * 所有 AI 能力的模型档案类型。协议无关：业务层只依赖本文件的类型，
 * 具体厂商差异封装在 services/ai/providers/ 内。
 */

/** 模型调用协议档位 */
export type ProviderProtocol =
  | 'openai-compat'   // POST {base}/chat/completions，SSE stream
  | 'gemini'          // POST {base}/models/{id}:generateContent
  | 'anthropic'       // POST {base}/v1/messages
  | 'custom';         // 旧版档案，按 OpenAI 兼容协议处理

/** 一个可保存的模型配置档案 */
export interface ModelProfile {
  id: string;
  label: string;
  protocol: ProviderProtocol;
  baseUrl: string;
  apiKey: string;
  /** API key exists only in runtime profiles; persisted metadata holds this opaque reference. */
  credentialRef?: string;
  credentialUnavailable?: boolean;
  remoteConsentVersion?: number;
  remoteConsentEndpoint?: string;
  remoteConsentProtocol?: ProviderProtocol;
  remoteConsentedAt?: number;
  modelId: string;
  /** 向量化模型 id（跨库语义检索用） */
  embeddingModelId?: string;
  semanticSearch?: boolean;
  temperature: number;
  maxTokens: number;
  stream: boolean;
  systemPrompt: string;
  toolAccess?: 'none' | 'read' | 'confirm-write';
  maxToolRounds?: number;
  /** 是否为 DeepSeek-R1 等深度思考/推理模型 */
  isReasoningModel?: boolean;
  /** 思考 token 预算，留空为自动 */
  thinkingBudget?: number;
  createdAt: number;
  updatedAt: number;
}

/** 运行时请求（与厂商无关） */
export interface ChatCompletionRequest {
  messages: ChatMessage[];
  temperature?: number;
  maxTokens?: number;
  stream?: boolean;
  /**
   * 工具的 JSON Schema 数组（已序列化）。
   * ArkTS 不允许无类型对象字面量，所以这里直接携带最终字符串，
   * 由 ToolRegistry.buildOpenAiToolsJson() 生成。
   */
  toolsJson?: string;
}

/** 角色定义 */
export type ChatRole = 'system' | 'user' | 'assistant' | 'tool';

/** 模型发起的一次工具调用 */
export interface ToolCallRequest {
  id: string;
  name: string;
  /** 模型给出的实参，JSON 字符串（未经校验，执行前必须解析校验） */
  arguments: string;
}

/** 单条对话消息（运行时，不含持久化字段） */
export interface ChatMessage {
  role: ChatRole;
  content: string;
  /** DeepSeek R1 思考内容（可选） */
  reasoningContent?: string;
  /** role=assistant 时模型请求调用的工具 */
  toolCalls?: ToolCallRequest[];
  /** role=tool 时对应的工具调用 id */
  toolCallId?: string;
}

/** 流式返回的工具调用增量（参数按片段下发，需按 index 拼接） */
export interface ToolCallDelta {
  index: number;
  id?: string;
  name?: string;
  argumentsFragment?: string;
}

/** 流式增量结果 */
export interface ChatCompletionChunk {
  delta: string;
  /** DeepSeek R1 / Reasoner 思考流增量 */
  reasoningDelta?: string;
  done: boolean;
  finishReason?: string;
  toolCall?: ToolCallDelta;
  /**
   * 终止性错误。
   *
   * completeStream 必须在请求发出前就把取消句柄交回去（否则用户无法中断），
   * 这意味着 HTTP 层面的失败已经无法通过 Promise reject 上报——Promise 早已 settle。
   * 所以错误改由最后一个 chunk 带出，done=true 且 error 非空。
   */
  error?: string;
}

/** 连接测试结果 */
export interface ModelTestResult {
  ok: boolean;
  latencyMs: number;
  message: string;
  sampleText?: string;
}

/** 预设渠道类型 */
export interface ModelPresetTemplate {
  name: string;
  description: string;
  profile: ModelProfile;
}

/** 获取开箱即用的预设配置模版 */
export function getPresetTemplates(): ModelPresetTemplate[] {
  const now = Date.now();
  return [
    { name: '兼容 API', description: '填写服务地址与实际模型 ID', profile: {
      id: 'preset-compat', label: '自配模型', protocol: 'openai-compat', baseUrl: '', apiKey: '', modelId: '',
      temperature: 0.7, maxTokens: 4096, stream: true, systemPrompt: '', createdAt: now, updatedAt: now
    } },
    { name: '本机兼容服务', description: '服务必须运行在当前设备；电脑服务请使用实际 HTTPS 地址', profile: {
      id: 'preset-local', label: '本机模型', protocol: 'openai-compat', baseUrl: 'http://127.0.0.1:11434/v1', apiKey: '', modelId: '',
      temperature: 0.7, maxTokens: 4096, stream: true, systemPrompt: '', createdAt: now, updatedAt: now
    } }
  ];
}

/** Empty, stable configuration draft. No model or paid service is selected on a fresh install. */
export function createDefaultProfile(): ModelProfile {
  const now = Date.now();
  return { id: 'profile-default', label: '自配模型', protocol: 'openai-compat', baseUrl: '', apiKey: '', modelId: '',
    temperature: 0.7, maxTokens: 4096, stream: true, semanticSearch: false, systemPrompt: '',
    createdAt: now, updatedAt: now };
}

