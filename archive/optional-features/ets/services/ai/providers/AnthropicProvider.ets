import { SseHttpClient } from '../SseHttpClient';
import { RemoteAiPolicy } from '../RemoteAiPolicy';
/**
 * Anthropic 协议 Provider
 *
 * POST {base}/v1/messages
 * 流式：同端点，"stream": true
 * 鉴权：x-api-key 头 + anthropic-version 头
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  ModelProfile,
  ChatCompletionRequest,
  ChatCompletionChunk,
  ChatMessage,
  ModelTestResult
} from '../../../common/types/ModelConfig';
import { ModelProvider, StreamHandle, StreamHandleImpl } from '../ModelProvider';

interface AnthropicResponse {
  content: AnthropicBlock[];
  stop_reason: string;
  error?: AnthropicError;
}

interface AnthropicBlock {
  type: string;
  text: string;
}

interface AnthropicError {
  type: string;
  message: string;
}

interface AnthropicSSEDelta {
  text?: string;
}

interface AnthropicSSEEvent {
  type?: string;
  delta?: AnthropicSSEDelta;
}

interface SerializedMessage {
  role: string;
  content: string;
}

export class AnthropicProvider implements ModelProvider {

  async testConnection(profile: ModelProfile): Promise<ModelTestResult> {
    const start: number = Date.now();
    try {
      const result: string = await this.complete(profile, {
        messages: [{ role: 'user', content: '你好' }],
        maxTokens: 8,
        temperature: 0
      });
      return { ok: true, latencyMs: Date.now() - start, message: '连通', sampleText: result.slice(0, 40) };
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      return { ok: false, latencyMs: Date.now() - start, message: `连接失败: ${msg}` };
    }
  }

  async complete(profile: ModelProfile, request: ChatCompletionRequest, onHandle?: (handle: StreamHandle) => void): Promise<string> {
    RemoteAiPolicy.assertAllowed(profile);
    const url: string = `${this.cleanBase(profile.baseUrl)}/v1/messages`;
    const body: string = this.buildBody(profile, request, false);
    const client = http.createHttp();
    let closed = false;
    const close = (): void => { if (!closed) { closed = true; client.destroy(); } };
    if (onHandle) { onHandle(new StreamHandleImpl(close)); }
    if (closed) { throw new Error('已停止生成'); }
    let resp: http.HttpResponse;
    try { resp = await client.request(url, {
      method: http.RequestMethod.POST,
      header: this.buildHeaders(profile),
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      maxRedirects: 0,
        connectTimeout: 15000,
      readTimeout: 60000
    }); } finally { close(); }
    if (resp.responseCode !== 200) {
      throw new Error(`AI 服务返回 HTTP ${resp.responseCode}，请核对密钥、模型与服务额度`);
    }
    const parsed: AnthropicResponse = JSON.parse(String(resp.result)) as AnthropicResponse;
    if (parsed.error !== undefined) {
      throw new Error('AI 服务未能完成请求，请核对配置和额度');
    }
    return parsed.content
      .filter((b: AnthropicBlock) => b.type === 'text')
      .map((b: AnthropicBlock) => b.text)
      .join('');
  }

  async completeStream(profile: ModelProfile, request: ChatCompletionRequest,
    onChunk: (chunk: ChatCompletionChunk) => void): Promise<StreamHandle> {
    RemoteAiPolicy.assertAllowed(profile);
    const url = `${this.cleanBase(profile.baseUrl)}/v1/messages`;
    return SseHttpClient.open(profile, url, this.buildHeaders(profile), this.buildBody(profile, request, true), (json: string): boolean => {
      const parsed = JSON.parse(json) as AnthropicSSEEvent;
      if (parsed.type === 'error') { throw new Error('provider error'); }
      if (parsed.type === 'content_block_delta' && parsed.delta?.text) { onChunk({ delta: parsed.delta.text, done: false }); }
      return parsed.type === 'message_stop';
    }, (error?: string) => onChunk({ delta: '', done: true, error }));
  }

  private cleanBase(baseUrl: string): string {
    const clean: string = baseUrl.endsWith('/') ? baseUrl.slice(0, -1) : baseUrl;
    return clean.endsWith('/v1') ? clean : `${clean}/v1`;
  }

  private buildHeaders(profile: ModelProfile): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      'x-api-key': profile.apiKey,
      'anthropic-version': '2023-06-01'
    };
  }

  private buildBody(profile: ModelProfile, request: ChatCompletionRequest, stream: boolean): string {
    let systemPrompt: string = '';
    const messages: Array<SerializedMessage> = [];
    for (const m of request.messages) {
      if (m.role === 'system') {
        systemPrompt = m.content;
      } else {
        const msg: SerializedMessage = {
          role: m.role === 'assistant' ? 'assistant' : 'user',
          content: m.content
        };
        messages.push(msg);
      }
    }
    let body: string = `{"model":${JSON.stringify(profile.modelId)},"messages":${JSON.stringify(messages)},`
      + `"max_tokens":${request.maxTokens ?? profile.maxTokens},`
      + `"temperature":${request.temperature ?? profile.temperature},`
      + `"stream":${stream}`;
    if (systemPrompt.length > 0) {
      body += `,"system":${JSON.stringify(systemPrompt)}`;
    }
    body += '}';
    return body;
  }
}
