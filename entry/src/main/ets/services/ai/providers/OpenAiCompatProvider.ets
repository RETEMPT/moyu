import { SseHttpClient } from '../SseHttpClient';
import { RemoteAiPolicy } from '../RemoteAiPolicy';
/**
 * OpenAI 兼容协议 Provider（HTTP/SSE）
 *
 * 覆盖 DeepSeek、Qwen、Moonshot、GLM、Ollama、vLLM、One-API 等
 * 所有 POST {base}/chat/completions 形态的服务。
 *
 * 流式使用 http.createHttp() 的 dataReceive 事件增量接收 SSE data: 行。
 */
import { http } from '@kit.NetworkKit';
import {
  ModelProfile,
  ChatCompletionRequest,
  ChatCompletionChunk,
  ChatMessage,
  ModelTestResult
} from '../../../common/types/ModelConfig';
import { ModelProvider, StreamHandle } from '../ModelProvider';

interface OpenAiStreamDelta {
  id: string;
  choices: OpenAiChoice[];
  error?: OpenAiError;
}

interface OpenAiChoice {
  index: number;
  delta: OpenAiDelta;
  finish_reason: string | null;
}

interface OpenAiDelta {
  content?: string;
  reasoning_content?: string;
  role?: string;
  tool_calls?: OpenAiToolCallDelta[];
}

interface OpenAiToolCallDelta {
  index: number;
  id?: string;
  type?: string;
  function?: OpenAiFunctionDelta;
}

interface OpenAiFunctionDelta {
  name?: string;
  arguments?: string;
}

interface OpenAiResponse {
  id: string;
  choices: OpenAiRespChoice[];
  error?: OpenAiError;
}

interface OpenAiRespChoice {
  index: number;
  message: OpenAiRespMessage;
  finish_reason: string;
}

interface OpenAiRespMessage {
  role: string;
  content: string;
  reasoning_content?: string;
}

interface OpenAiError {
  message: string;
  type: string;
}

interface SerializedMessage {
  role: string;
  content: string;
  tool_call_id?: string;
  tool_calls?: SerializedToolCall[];
}

interface SerializedToolCall {
  id: string;
  type: string;
  function: SerializedFunctionCall;
}

interface SerializedFunctionCall {
  name: string;
  arguments: string;
}

interface StreamState {
  inThinkTag: boolean;
  finishReason?: string;
}

export class OpenAiCompatProvider implements ModelProvider {

  async testConnection(profile: ModelProfile): Promise<ModelTestResult> {
    const start: number = Date.now();
    const apiKey: string = (profile.apiKey ?? '').trim();
    const cleanUrl: string = (profile.baseUrl ?? '').trim();
    const modelId: string = (profile.modelId ?? '').trim();
    const isLocal: boolean = cleanUrl.includes('127.0.0.1') || cleanUrl.includes('localhost');

    if (apiKey.length === 0 && !isLocal) {
      return {
        ok: false,
        latencyMs: 0,
        message: '未填写 API Key，请先输入密钥'
      };
    }
    if (cleanUrl.length === 0) {
      return {
        ok: false,
        latencyMs: 0,
        message: '未填写 Base URL，请输入接口地址'
      };
    }
    if (modelId.length === 0) {
      return {
        ok: false,
        latencyMs: 0,
        message: '未填写模型 ID，请输入模型标识'
      };
    }

    try {
      const result: string = await this.complete(profile, {
        messages: [{ role: 'user', content: 'Hi' }],
        maxTokens: 64,
        temperature: profile.isReasoningModel ? 0.6 : 0.7
      });
      return {
        ok: true,
        latencyMs: Date.now() - start,
        message: '连通正常',
        sampleText: result.slice(0, 40)
      };
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      let hint: string = msg;
      if (msg.includes('23000') || msg.includes('connect') || msg.includes('Failed') || msg.includes('Network')) {
        hint += '（若在 DevEco 预览器运行，因沙箱无网络协议栈会导致失败，请切换至【本地模拟器】或【真机】调试）';
      }
      return { ok: false, latencyMs: Date.now() - start, message: hint };
    }
  }

  async complete(profile: ModelProfile, request: ChatCompletionRequest): Promise<string> {
    RemoteAiPolicy.assertAllowed(profile);
    const url: string = this.buildUrl(profile.baseUrl);
    const body: string = this.buildBody(profile, request, false);
    let resp: http.HttpResponse;
    const client = http.createHttp();
    try {
      resp = await client.request(url, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(profile),
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        maxRedirects: 0,
        connectTimeout: 15000,
        readTimeout: 60000
      });
    } catch (netErr) {
      const netMsg: string = netErr instanceof Error ? netErr.message : String(netErr);
      throw new Error('网络请求失败，请检查连接后重试');
    } finally { client.destroy(); }

    if (resp.responseCode !== 200) {
      throw new Error(this.describeHttpResponse(resp.responseCode, resp.result));
    }
    const parsed: OpenAiResponse = JSON.parse(String(resp.result)) as OpenAiResponse;
    if (parsed.error !== undefined) {
      throw new Error('AI 服务未能完成请求，请核对配置和额度');
    }
    if (parsed.choices === undefined || parsed.choices.length === 0) {
      return '';
    }
    const choice: OpenAiRespChoice = parsed.choices[0];
    const content: string = choice.message.content ?? '';
    const reasoning: string = choice.message.reasoning_content ?? '';
    return content.length > 0 ? content : reasoning;
  }

  async completeStream(
    profile: ModelProfile,
    request: ChatCompletionRequest,
    onChunk: (chunk: ChatCompletionChunk) => void
  ): Promise<StreamHandle> {
    const state: StreamState = { inThinkTag: false };
    return SseHttpClient.open(profile, this.buildUrl(profile.baseUrl), this.buildHeaders(profile),
      this.buildBody(profile, request, true),
      (json: string): boolean => this.parseSsePayload(json, onChunk, state),
      (error?: string) => onChunk({ delta: '', done: true, error, finishReason: state.finishReason }));
  }

  private parseSsePayload(payload: string, onChunk: (chunk: ChatCompletionChunk) => void,
    state: StreamState): boolean {
    const parsed = JSON.parse(payload) as OpenAiStreamDelta;
    if (parsed.error) { throw new Error('provider error'); }
    if (parsed.choices !== undefined && parsed.choices.length > 0) {
      const choice: OpenAiChoice = parsed.choices[0];
      const rawDelta = (choice.delta ?? {}) as Record<string, Object>;
      let delta: string = (rawDelta.content as string) ?? '';
      let reasoningDelta: string = (rawDelta.reasoning_content as string)
        ?? (rawDelta.reasoning as string)
        ?? (rawDelta.thought as string)
        ?? (rawDelta.thinking as string)
        ?? '';

      // 处理混在 content 里的 <think> 标签流
      if (delta.includes('<think>')) {
        state.inThinkTag = true;
        const parts: string[] = delta.split('<think>');
        if (parts[0].length > 0) {
          onChunk({ delta: parts[0], done: false });
        }
        delta = parts[1] ?? '';
      }
      if (state.inThinkTag) {
        if (delta.includes('</think>')) {
          state.inThinkTag = false;
          const parts: string[] = delta.split('</think>');
          reasoningDelta += parts[0];
          delta = parts[1] ?? '';
        } else {
          reasoningDelta += delta;
          delta = '';
        }
      }

      const finish: string | null = choice.finish_reason;

      if (reasoningDelta.length > 0) {
        onChunk({ delta: '', reasoningDelta, done: false });
      }
      if (delta.length > 0) {
        onChunk({ delta, done: false });
      }
      const rawCalls: OpenAiToolCallDelta[] | undefined = choice.delta?.tool_calls;
      if (rawCalls !== undefined) {
        for (const rc of rawCalls) {
          onChunk({
            delta: '',
            done: false,
            toolCall: {
              index: rc.index,
              id: rc.id,
              name: rc.function !== undefined ? rc.function.name : undefined,
              argumentsFragment: rc.function !== undefined ? rc.function.arguments : undefined
            }
          });
        }
      }
      if (finish !== null && finish !== undefined) {
        state.finishReason = finish;
        return true;
      }
    }
    return false;
  }

  /** 将 HTTP 状态码与响应体解析为对开发者友好、清晰的中文排障指导 */
  private describeHttpResponse(code: number, rawResult: Object | string | ArrayBuffer | undefined): string {
    if (code === 401 || code === 403) { return '认证失败，请核对密钥及服务权限'; }
    if (code === 404) { return '端点或模型不存在，请核对服务地址和模型 ID'; }
    if (code === 429) { return '服务配额或速率受限，请稍后重试或核对额度'; }
    if (code >= 500) { return 'AI 服务暂时不可用，请稍后重试'; }
    return `AI 服务返回 HTTP ${code}，请核对配置`;
  }

  private buildUrl(baseUrl: string): string {
    let clean: string = baseUrl.trim().replace(/^["']|["']$/g, '');
    while (clean.endsWith('/')) {
      clean = clean.slice(0, -1);
    }
    if (clean.endsWith('/chat/completions')) {
      return clean;
    }
    if (clean.endsWith('/v1')) {
      return `${clean}/chat/completions`;
    }
    if (clean.includes('/v1/')) {
      return `${clean}/chat/completions`;
    }
    // 主流 OpenAI 兼容网关（SiliconFlow、OpenAI、Ollama、OneAPI等）标准端点均要求 /v1/chat/completions
    // DeepSeek 官方 API 同样全面兼容 /v1/chat/completions，自动补全 /v1 是最稳妥的兼容规范
    return `${clean}/v1/chat/completions`;
  }

  private buildHeaders(profile: ModelProfile): Record<string, string> {
    const key: string = (profile.apiKey ?? '').trim();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (key) { headers['Authorization'] = `Bearer ${key}`; }
    return headers;
  }

  private buildBody(profile: ModelProfile, request: ChatCompletionRequest, stream: boolean): string {
    const model: string = (profile.modelId ?? '').trim();
    let body: string = `{"model":${JSON.stringify(model)},`
      + `"messages":${JSON.stringify(this.serializeMessages(request.messages))},`
      + `"temperature":${request.temperature ?? profile.temperature},`
      + `"max_tokens":${request.maxTokens ?? profile.maxTokens},`
      + `"stream":${stream}`;
    if (request.toolsJson !== undefined && request.toolsJson.length > 0) {
      body += `,"tools":${request.toolsJson},"tool_choice":"auto"`;
    }
    if (profile.isReasoningModel) {
      const lowerModel: string = model.toLowerCase();
      if (lowerModel.startsWith('o1') || lowerModel.startsWith('o3') || lowerModel.startsWith('o4') || lowerModel.includes('codex')) {
        let effort: string = 'medium';
        const budget: number = profile.thinkingBudget ?? 16384;
        if (budget <= 8192) {
          effort = 'low';
        } else if (budget <= 24576) {
          effort = 'medium';
        } else {
          effort = 'high';
        }
        body += `,"reasoning_effort":${JSON.stringify(effort)}`;
      }
    }
    body += '}';
    return body;
  }

  private serializeMessages(messages: ChatMessage[]): Array<SerializedMessage> {
    const arr: Array<SerializedMessage> = [];
    for (const m of messages) {
      const msg: SerializedMessage = { role: m.role, content: m.content };
      if (m.toolCallId !== undefined && m.toolCallId.length > 0) {
        msg.tool_call_id = m.toolCallId;
      }
      if (m.toolCalls !== undefined && m.toolCalls.length > 0) {
        const calls: SerializedToolCall[] = [];
        for (const c of m.toolCalls) {
          calls.push({
            id: c.id,
            type: 'function',
            function: { name: c.name, arguments: c.arguments }
          });
        }
        msg.tool_calls = calls;
      }
      arr.push(msg);
    }
    return arr;
  }

}
