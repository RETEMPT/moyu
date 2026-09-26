/**
 * 模型调用抽象接口 + 工厂
 *
 * 业务层只依赖 ModelProvider 接口，不直接触碰 HTTP。
 * createProvider() 是唯一知道厂商协议差异的入口。
 */
import {
  ModelProfile,
  ChatCompletionRequest,
  ChatCompletionChunk,
  ModelTestResult,
  ProviderProtocol
} from '../../common/types/ModelConfig';
import { OpenAiCompatProvider } from './providers/OpenAiCompatProvider';
import { GeminiProvider } from './providers/GeminiProvider';
import { AnthropicProvider } from './providers/AnthropicProvider';

/** 流式回调句柄 */
export interface StreamHandle {
  /** 取消请求 */
  abort(): void;
}

/** StreamHandle 默认实现 */
export class StreamHandleImpl implements StreamHandle {
  private cancelFn: () => void;

  constructor(cancelFn: () => void) {
    this.cancelFn = cancelFn;
  }

  abort(): void {
    this.cancelFn();
  }
}

/** 厂商无关的模型补全接口 */
export interface ModelProvider {
  /** 连通性测试 */
  testConnection(profile: ModelProfile): Promise<ModelTestResult>;

  /** 流式补全，通过 onChunk 推送增量 */
  completeStream(
    profile: ModelProfile,
    request: ChatCompletionRequest,
    onChunk: (chunk: ChatCompletionChunk) => void
  ): Promise<StreamHandle>;

  /** 非流式补全，返回完整文本 */
  complete(profile: ModelProfile, request: ChatCompletionRequest): Promise<string>;
}

/** 工厂：按 protocol 分派 */
export function createProvider(protocol: ProviderProtocol): ModelProvider {
  if (protocol === 'gemini') {
    return new GeminiProvider();
  }
  if (protocol === 'anthropic') {
    return new AnthropicProvider();
  }
  // openai-compat 和 custom 都走 OpenAI 兼容协议（custom 的 URL/Header 由 profile.baseUrl 承载）
  return new OpenAiCompatProvider();
}
