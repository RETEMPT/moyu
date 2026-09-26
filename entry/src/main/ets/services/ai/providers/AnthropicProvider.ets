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

  async complete(profile: ModelProfile, request: ChatCompletionRequest): Promise<string> {
    const url: string = `${this.cleanBase(profile.baseUrl)}/v1/messages`;
    const body: string = this.buildBody(profile, request, false);
    const resp: http.HttpResponse = await http.createHttp().request(url, {
      method: http.RequestMethod.POST,
      header: this.buildHeaders(profile),
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 60000
    });
    if (resp.responseCode !== 200) {
      throw new Error(`HTTP ${resp.responseCode}: ${String(resp.result).slice(0, 200)}`);
    }
    const parsed: AnthropicResponse = JSON.parse(String(resp.result)) as AnthropicResponse;
    if (parsed.error !== undefined) {
      throw new Error(parsed.error.message);
    }
    return parsed.content
      .filter((b: AnthropicBlock) => b.type === 'text')
      .map((b: AnthropicBlock) => b.text)
      .join('');
  }

  async completeStream(
    profile: ModelProfile,
    request: ChatCompletionRequest,
    onChunk: (chunk: ChatCompletionChunk) => void
  ): Promise<StreamHandle> {
    const url: string = `${this.cleanBase(profile.baseUrl)}/v1/messages`;
    const body: string = this.buildBody(profile, request, true);
    const httpRequest = http.createHttp();
    let aborted: boolean = false;
    let buffer: string = '';

    return new Promise<StreamHandle>((resolve) => {
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        if (aborted) {
          return;
        }
        buffer += new util.TextDecoder('utf-8').decode(new Uint8Array(data));
        const lines: string[] = buffer.split('\n');
        buffer = lines.pop() ?? '';
        for (const line of lines) {
          const trimmed: string = line.trim();
          if (!trimmed.startsWith('data:')) {
            continue;
          }
          const payload: string = trimmed.slice(5).trim();
          try {
            const parsed: AnthropicSSEEvent = JSON.parse(payload) as AnthropicSSEEvent;
            const type: string = parsed.type ?? '';
            if (type === 'content_block_delta') {
              const delta: AnthropicSSEDelta = parsed.delta ?? { text: '' };
              const text: string = delta.text ?? '';
              if (text.length > 0) {
                onChunk({ delta: text, done: false });
              }
            } else if (type === 'message_stop') {
              onChunk({ delta: '', done: true });
            }
          } catch {
            // skip
          }
        }
      });

      httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(profile),
        extraData: body,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 120000
      }).then((resp: http.HttpResponse) => {
        if (aborted) {
          return;
        }
        if (resp.responseCode !== 200) {
          onChunk({ delta: '', done: true, error: this.describeError(resp) });
          return;
        }
        onChunk({ delta: '', done: true });
      }).catch((err: Error) => {
        if (!aborted) {
          onChunk({ delta: '', done: true, error: err.message });
        }
      });

      resolve(new StreamHandleImpl(() => { aborted = true; httpRequest.destroy(); }));
    });
  }

  /** 非 200 响应整理成可读错误（ARRAY_BUFFER 下 result 是二进制，直接拼串会得到 [object ArrayBuffer]） */
  private describeError(resp: http.HttpResponse): string {
    let body: string = '';
    if (resp.result instanceof ArrayBuffer) {
      body = new util.TextDecoder('utf-8').decode(new Uint8Array(resp.result));
    } else if (resp.result !== undefined) {
      body = String(resp.result);
    }
    return body.length > 0
      ? `HTTP ${resp.responseCode}: ${body.slice(0, 200)}`
      : `HTTP ${resp.responseCode}`;
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
    let body: string = `{"model":"${profile.modelId}","messages":${JSON.stringify(messages)},`
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
