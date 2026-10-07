import { SseHttpClient } from '../SseHttpClient';
import { RemoteAiPolicy } from '../RemoteAiPolicy';
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
    RemoteAiPolicy.assertAllowed(profile);
    const url: string = `${this.cleanBase(profile.baseUrl)}/models/${encodeURIComponent(profile.modelId)}:generateContent`;
    const body: string = this.buildBody(profile, request);
    const client = http.createHttp();
    let resp: http.HttpResponse;
    try { resp = await client.request(url, {
      method: http.RequestMethod.POST,
      header: this.buildHeaders(profile),
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      maxRedirects: 0,
        connectTimeout: 15000,
      readTimeout: 60000
    }); } finally { client.destroy(); }
    if (resp.responseCode !== 200) {
      throw new Error(`AI 服务返回 HTTP ${resp.responseCode}，请核对密钥、模型与服务额度`);
    }
    const parsed: GeminiResponse = JSON.parse(String(resp.result)) as GeminiResponse;
    if (parsed.error !== undefined) {
      throw new Error('AI 服务未能完成请求，请核对配置和额度');
    }
    if (parsed.candidates === undefined || parsed.candidates.length === 0) {
      return '';
    }
    const parts: GeminiPart[] = parsed.candidates[0].content.parts;
    return parts.map((p: GeminiPart) => p.text).join('');
  }

  async completeStream(profile: ModelProfile, request: ChatCompletionRequest,
    onChunk: (chunk: ChatCompletionChunk) => void): Promise<StreamHandle> {
    RemoteAiPolicy.assertAllowed(profile);
    const url = `${this.cleanBase(profile.baseUrl)}/models/${encodeURIComponent(profile.modelId)}:streamGenerateContent?alt=sse`;
    return SseHttpClient.open(profile, url, this.buildHeaders(profile), this.buildBody(profile, request), (json: string): boolean => {
      const parsed = JSON.parse(json) as GeminiResponse;
      if (parsed.error) { throw new Error('provider error'); }
      if (!parsed.candidates || !parsed.candidates.length) { return false; }
      const candidate = parsed.candidates[0];
      const text = candidate.content?.parts?.map((part: GeminiPart) => part.text || '').join('') || '';
      if (text) { onChunk({ delta: text, done: false }); }
      return !!candidate.finishReason;
    }, (error?: string) => onChunk({ delta: '', done: true, error }));
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
