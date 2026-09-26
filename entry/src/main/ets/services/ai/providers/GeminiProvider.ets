/**
 * Gemini 协议 Provider
 *
 * POST {base}/models/{modelId}:generateContent
 * 流式：POST {base}/models/{modelId}:streamGenerateContent?alt=sse
 * 鉴权：x-goog-api-key 头
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

interface GeminiResponse {
  candidates: GeminiCandidate[];
  error?: GeminiError;
}

interface GeminiCandidate {
  content: GeminiContent;
  finishReason: string;
}

interface GeminiContent {
  parts: GeminiPart[];
  role: string;
}

interface GeminiPart {
  text: string;
}

interface GeminiError {
  message: string;
  code: number;
}

export class GeminiProvider implements ModelProvider {

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
    const url: string = `${this.cleanBase(profile.baseUrl)}/models/${profile.modelId}:generateContent`;
    const body: string = this.buildBody(profile, request);
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
    const parsed: GeminiResponse = JSON.parse(String(resp.result)) as GeminiResponse;
    if (parsed.error !== undefined) {
      throw new Error(parsed.error.message);
    }
    if (parsed.candidates === undefined || parsed.candidates.length === 0) {
      return '';
    }
    const parts: GeminiPart[] = parsed.candidates[0].content.parts;
    return parts.map((p: GeminiPart) => p.text).join('');
  }

  async completeStream(
    profile: ModelProfile,
    request: ChatCompletionRequest,
    onChunk: (chunk: ChatCompletionChunk) => void
  ): Promise<StreamHandle> {
    const url: string = `${this.cleanBase(profile.baseUrl)}/models/${profile.modelId}:streamGenerateContent?alt=sse`;
    const body: string = this.buildBody(profile, request);
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
            const parsed: GeminiResponse = JSON.parse(payload) as GeminiResponse;
            if (parsed.candidates !== undefined && parsed.candidates.length > 0) {
              const text: string = parsed.candidates[0].content.parts
                .map((p: GeminiPart) => p.text).join('');
              const finish: string = parsed.candidates[0].finishReason;
              if (text.length > 0 || finish.length > 0) {
                onChunk({ delta: text, done: finish === 'STOP', finishReason: finish });
              }
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
    return clean.endsWith('/v1beta') || clean.endsWith('/v1') ? clean : `${clean}/v1beta`;
  }

  private buildHeaders(profile: ModelProfile): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      'x-goog-api-key': profile.apiKey
    };
  }

  private buildBody(profile: ModelProfile, request: ChatCompletionRequest): string {
    let contentsJson: string = '[';
    let first: boolean = true;
    for (const m of request.messages) {
      if (m.role === 'system') {
        continue;
      }
      if (!first) {
        contentsJson += ',';
      }
      first = false;
      const role: string = m.role === 'assistant' ? 'model' : 'user';
      contentsJson += `{"role":"${role}","parts":[{"text":${JSON.stringify(m.content)}}]}`;
    }
    contentsJson += ']';

    let body: string = `{"contents":${contentsJson},`
      + `"generationConfig":{"temperature":${request.temperature ?? profile.temperature},`
      + `"maxOutputTokens":${request.maxTokens ?? profile.maxTokens}}`;

    // system 消息放在 systemInstruction 字段
    for (const m of request.messages) {
      if (m.role === 'system') {
        body += `,"systemInstruction":{"parts":[{"text":${JSON.stringify(m.content)}}]}`;
        break;
      }
    }
    body += '}';
    return body;
  }
}
