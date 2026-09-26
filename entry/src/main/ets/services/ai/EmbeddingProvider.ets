/**
 * 向量化（Embedding）抽象
 *
 * 与 ModelProvider 同范式：业务层只依赖 EmbeddingProvider 接口。
 * Anthropic 没有公开的 embedding 端点，因此该协议下 createEmbeddingProvider 返回 null，
 * 调用方据此退化为关键词检索，而不是抛错中断整条问答链路。
 */
import { http } from '@kit.NetworkKit';
import { ModelProfile, ProviderProtocol } from '../../common/types/ModelConfig';

export interface EmbeddingProvider {
  /** 批量向量化，返回顺序与入参一致 */
  embed(profile: ModelProfile, texts: string[]): Promise<number[][]>;
}

interface OpenAiEmbeddingItem {
  index: number;
  embedding: number[];
}

interface OpenAiEmbeddingResponse {
  data: OpenAiEmbeddingItem[];
  error?: OpenAiEmbeddingError;
}

interface OpenAiEmbeddingError {
  message: string;
}

interface GeminiEmbedding {
  values: number[];
}

interface GeminiBatchEmbedResponse {
  embeddings: GeminiEmbedding[];
  error?: GeminiEmbeddingError;
}

interface GeminiEmbeddingError {
  message: string;
}

interface GeminiEmbedRequest {
  model: string;
  content: GeminiEmbedContent;
}

interface GeminiEmbedContent {
  parts: GeminiEmbedPart[];
}

interface GeminiEmbedPart {
  text: string;
}

/** OpenAI 兼容：POST {base}/embeddings  { model, input: string[] } */
class OpenAiEmbeddingProvider implements EmbeddingProvider {
  async embed(profile: ModelProfile, texts: string[]): Promise<number[][]> {
    if (texts.length === 0) {
      return [];
    }
    const clean: string = profile.baseUrl.endsWith('/') ? profile.baseUrl.slice(0, -1) : profile.baseUrl;
    const url: string = `${clean}/embeddings`;
    const body: string = JSON.stringify({
      model: profile.embeddingModelId ?? '',
      input: texts
    });
    const resp: http.HttpResponse = await http.createHttp().request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${profile.apiKey}`
      },
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 60000
    });
    if (resp.responseCode !== 200) {
      throw new Error(`HTTP ${resp.responseCode}: ${String(resp.result).slice(0, 160)}`);
    }
    const parsed: OpenAiEmbeddingResponse = JSON.parse(String(resp.result)) as OpenAiEmbeddingResponse;
    if (parsed.error !== undefined) {
      throw new Error(parsed.error.message);
    }
    if (parsed.data === undefined || parsed.data.length === 0) {
      return [];
    }
    // 服务端不保证返回顺序，按 index 归位
    const ordered: number[][] = new Array<number[]>(texts.length);
    for (const item of parsed.data) {
      if (item.index >= 0 && item.index < texts.length) {
        ordered[item.index] = item.embedding;
      }
    }
    const result: number[][] = [];
    for (let i = 0; i < ordered.length; i++) {
      result.push(ordered[i] ?? []);
    }
    return result;
  }
}

/** Gemini：POST {base}/models/{model}:batchEmbedContents */
class GeminiEmbeddingProvider implements EmbeddingProvider {
  async embed(profile: ModelProfile, texts: string[]): Promise<number[][]> {
    if (texts.length === 0) {
      return [];
    }
    const model: string = profile.embeddingModelId ?? '';
    const clean: string = profile.baseUrl.endsWith('/') ? profile.baseUrl.slice(0, -1) : profile.baseUrl;
    const base: string = (clean.endsWith('/v1beta') || clean.endsWith('/v1')) ? clean : `${clean}/v1beta`;
    const url: string = `${base}/models/${model}:batchEmbedContents`;

    const requests: GeminiEmbedRequest[] = [];
    for (const t of texts) {
      requests.push({
        model: `models/${model}`,
        content: { parts: [{ text: t }] }
      });
    }
    const resp: http.HttpResponse = await http.createHttp().request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'x-goog-api-key': profile.apiKey
      },
      extraData: JSON.stringify({ requests }),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 60000
    });
    if (resp.responseCode !== 200) {
      throw new Error(`HTTP ${resp.responseCode}: ${String(resp.result).slice(0, 160)}`);
    }
    const parsed: GeminiBatchEmbedResponse = JSON.parse(String(resp.result)) as GeminiBatchEmbedResponse;
    if (parsed.error !== undefined) {
      throw new Error(parsed.error.message);
    }
    if (parsed.embeddings === undefined) {
      return [];
    }
    const result: number[][] = [];
    for (const e of parsed.embeddings) {
      result.push(e.values);
    }
    return result;
  }
}

/** Anthropic 无 embedding 端点，返回 null 表示「本协议不支持向量检索」 */
export function createEmbeddingProvider(protocol: ProviderProtocol): EmbeddingProvider | null {
  if (protocol === 'gemini') {
    return new GeminiEmbeddingProvider();
  }
  if (protocol === 'anthropic') {
    return null;
  }
  return new OpenAiEmbeddingProvider();
}
