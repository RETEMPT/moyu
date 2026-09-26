/**
 * 对话会话类型
 *
 * 覆盖单条消息、单个会话以及引用片段的完整数据模型。
 * ChatMessage 的 role 与运行时 ModelConfig 中的角色对齐，
 * 但增加了持久化字段（id、citations、streaming 等）。
 */

/** 来源引用 */
export interface ChatCitation {
  noteId: string;
  noteTitle: string;
  headingPath: string;
  chunkText: string;
  score: number;
}

/** 持久化消息 */
export interface StoredMessage {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  text: string;
  /** DeepSeek R1 / Reasoner 链式思考内容 */
  reasoningContent?: string;
  /** 思考耗时毫秒数 */
  reasoningDurationMs?: number;
  /** UI 思考过程折叠状态 */
  reasoningFolded?: boolean;
  formula?: string;
  bullets?: string[];
  citations?: ChatCitation[];
  agentLayer?: 'L1' | 'L2' | 'L3';
  modelProfileId?: string;
  createdAt: number;
  streaming?: boolean;
  error?: string;
}

/** 会话 */
export interface ChatSession {
  id: string;
  title: string;
  pinned: boolean;
  agentMode: 'auto' | 'L1' | 'L2' | 'L3';
  messages: StoredMessage[];
  createdAt: number;
  updatedAt: number;
}

/** 创建空白会话 */
export function createEmptySession(): ChatSession {
  return {
    id: `session_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
    title: '新对话',
    pinned: false,
    agentMode: 'auto',
    messages: [],
    createdAt: Date.now(),
    updatedAt: Date.now()
  };
}

/** 消息角色联合类型 */
export type MessageRole = 'user' | 'assistant' | 'system' | 'tool';

/** 创建用户消息 */
export function createMessage(role: MessageRole, text: string): StoredMessage {
  return {
    id: `msg_${Date.now()}_${Math.floor(Math.random() * 1000)}`,
    role,
    text,
    createdAt: Date.now()
  };
}
