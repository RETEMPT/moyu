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
  | 'custom';         // 用户自定义 HTTP 模板

/** 一个可保存的模型配置档案 */
export interface ModelProfile {
  id: string;
  label: string;
  protocol: ProviderProtocol;
  baseUrl: string;
  apiKey: string;
  modelId: string;
  /** 向量化模型 id（跨库语义检索用） */
  embeddingModelId?: string;
  temperature: number;
  maxTokens: number;
  stream: boolean;
  systemPrompt: string;
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
    {
      name: 'DeepSeek V4 Pro (旗舰)',
      description: '主流 API 最新 V4 Pro 旗舰版（deepseek-v4-pro），长上下文与深逻辑研读',
      profile: {
        id: `preset_ds_v4_pro_${now}`,
        label: 'DeepSeek V4 Pro',
        protocol: 'openai-compat',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: '',
        modelId: 'deepseek-v4-pro',
        embeddingModelId: '',
        temperature: 0.7,
        maxTokens: 8192,
        stream: true,
        isReasoningModel: false,
        systemPrompt: '',
        createdAt: now,
        updatedAt: now
      }
    },
    {
      name: 'DeepSeek Flash (极速)',
      description: '主流 API 最新 Flash 极速版（deepseek-flash），高吞吐低延迟即时问答',
      profile: {
        id: `preset_ds_flash_${now}`,
        label: 'DeepSeek Flash',
        protocol: 'openai-compat',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: '',
        modelId: 'deepseek-flash',
        embeddingModelId: '',
        temperature: 0.7,
        maxTokens: 8192,
        stream: true,
        isReasoningModel: false,
        systemPrompt: '',
        createdAt: now,
        updatedAt: now
      }
    },
    {
      name: 'DeepSeek 官方 (主力通用)',
      description: '官方推荐主力通道（deepseek-chat），平滑升级最新旗舰版，最稳妥',
      profile: {
        id: `preset_ds_chat_${now}`,
        label: 'DeepSeek 官方',
        protocol: 'openai-compat',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: '',
        modelId: 'deepseek-chat',
        embeddingModelId: '',
        temperature: 0.7,
        maxTokens: 8192,
        stream: true,
        isReasoningModel: false,
        systemPrompt: '',
        createdAt: now,
        updatedAt: now
      }
    },
    {
      name: 'DeepSeek 官方 (深度思考)',
      description: '官方深度思考模型（deepseek-reasoner），链式思考推演与严谨数理证明',
      profile: {
        id: `preset_ds_reasoner_${now}`,
        label: 'DeepSeek 思考',
        protocol: 'openai-compat',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: '',
        modelId: 'deepseek-reasoner',
        embeddingModelId: '',
        temperature: 0.6,
        maxTokens: 8192,
        stream: true,
        isReasoningModel: true,
        thinkingBudget: 4096,
        systemPrompt: '',
        createdAt: now,
        updatedAt: now
      }
    },
    {
      name: '硅基流动 (SiliconFlow 专线)',
      description: '国内高速中转专线，稳定高并发，支持免翻免配',
      profile: {
        id: `preset_sf_${now}`,
        label: 'SiliconFlow 专线',
        protocol: 'openai-compat',
        baseUrl: 'https://api.siliconflow.cn/v1',
        apiKey: '',
        modelId: 'deepseek-ai/DeepSeek-V3',
        embeddingModelId: 'BAAI/bge-m3',
        temperature: 0.7,
        maxTokens: 8192,
        stream: true,
        isReasoningModel: false,
        systemPrompt: '',
        createdAt: now,
        updatedAt: now
      }
    },
    {
      name: 'Ollama 本地 (DeepSeek)',
      description: '纯本地端侧离线运行，免 API Key 零成本保护隐私',
      profile: {
        id: `preset_ollama_${now}`,
        label: 'Ollama 本地',
        protocol: 'openai-compat',
        baseUrl: 'http://127.0.0.1:11434/v1',
        apiKey: 'ollama',
        modelId: 'deepseek-r1:latest',
        embeddingModelId: 'nomic-embed-text',
        temperature: 0.5,
        maxTokens: 8192,
        stream: true,
        isReasoningModel: true,
        systemPrompt: '',
        createdAt: now,
        updatedAt: now
      }
    }
  ];
}

/** 生成一个默认模型档案（默认采用主流 V4 Pro 旗舰版） */
export function createDefaultProfile(): ModelProfile {
  return getPresetTemplates()[0].profile;
}

