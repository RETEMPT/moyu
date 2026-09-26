/**
 * OpenAI 兼容协议 Provider（HTTP/SSE）
 *
 * 覆盖 DeepSeek、Qwen、Moonshot、GLM、Ollama、vLLM、One-API 等
 * 所有 POST {base}/chat/completions 形态的服务。
 *
 * 流式使用 http.createHttp() 的 dataReceive 事件增量接收 SSE data: 行。
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

interface OpenAiStreamDelta {
  id: string;
  choices: OpenAiChoice[];
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
  hasEmittedAnyChunk: boolean;
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
    const url: string = this.buildUrl(profile.baseUrl);
    const body: string = this.buildBody(profile, request, false);
    let resp: http.HttpResponse;
    try {
      resp = await http.createHttp().request(url, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(profile),
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 60000
      });
    } catch (netErr) {
      const netMsg: string = netErr instanceof Error ? netErr.message : String(netErr);
      throw new Error(`网络请求异常: ${netMsg}`);
    }

    if (resp.responseCode !== 200) {
      throw new Error(this.describeHttpResponse(resp.responseCode, resp.result));
    }
    const parsed: OpenAiResponse = JSON.parse(String(resp.result)) as OpenAiResponse;
    if (parsed.error !== undefined) {
      throw new Error(parsed.error.message);
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
    const url: string = this.buildUrl(profile.baseUrl);
    const body: string = this.buildBody(profile, request, true);
    const httpRequest = http.createHttp();
    let aborted: boolean = false;
    let buffer: string = '';
    const state: StreamState = { inThinkTag: false, hasEmittedAnyChunk: false };
    let responseStatusCode: number = 200;
    let rawErrorBody: string = '';
    let decoder: util.TextDecoder | null = null;
    try {
      decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    } catch {
      decoder = null;
    }

    return new Promise<StreamHandle>((resolve) => {
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        if (aborted) {
          return;
        }
        let text: string = '';
        if (decoder !== null) {
          try {
            const view: Uint8Array = new Uint8Array(data);
            text = decoder.decodeToString(view, { stream: true });
          } catch {
            text = this.arrayBufferToString(data);
          }
        } else {
          text = this.arrayBufferToString(data);
        }

        if (responseStatusCode >= 400) {
          rawErrorBody += text;
          return;
        }

        buffer += text;
        const lines: string[] = buffer.split('\n');
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          this.parseSseLine(line, onChunk, state);
        }
      });

      httpRequest.on('dataEnd', () => {
        if (aborted) {
          return;
        }
        if (buffer.trim().length > 0) {
          this.parseSseLine(buffer, onChunk, state);
          buffer = '';
        }
        if (responseStatusCode >= 400) {
          onChunk({ delta: '', done: true, error: this.describeHttpResponse(responseStatusCode, rawErrorBody) });
          return;
        }
        if (!state.hasEmittedAnyChunk && rawErrorBody.length > 0) {
          this.parseFallbackFullBody(rawErrorBody, onChunk, state);
        }
        onChunk({ delta: '', done: true });
      });

      // 发起流式请求：使用 requestInStream，确保 dataReceive 在运行时实时触发
      httpRequest.requestInStream(url, {
        method: http.RequestMethod.POST,
        header: this.buildHeaders(profile),
        extraData: body,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 15000,
        readTimeout: 120000
      }).then((code: number) => {
        responseStatusCode = code;
        if (code >= 400 && rawErrorBody.length > 0) {
          onChunk({ delta: '', done: true, error: this.describeHttpResponse(code, rawErrorBody) });
        }
      }).catch((err: Error) => {
        if (!aborted) {
          let msg: string = err.message;
          if (msg.includes('23000') || msg.includes('connect')) {
            msg += '（若在 DevEco 预览器运行，请切换至【本地模拟器】或【真机】调试）';
          }
          onChunk({ delta: '', done: true, error: msg });
        }
      });

      resolve(new StreamHandleImpl(() => {
        aborted = true;
        httpRequest.destroy();
      }));
    });
  }

  private parseSseLine(
    line: string,
    onChunk: (chunk: ChatCompletionChunk) => void,
    state: StreamState
  ): boolean {
    const trimmed: string = line.trim();
    if (trimmed.length === 0 || !trimmed.startsWith('data:')) {
      return false;
    }
    const payload: string = trimmed.slice(5).trim();
    if (payload === '[DONE]') {
      onChunk({ delta: '', done: true });
      return true;
    }
    try {
      const parsed: OpenAiStreamDelta = JSON.parse(payload) as OpenAiStreamDelta;
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
            state.hasEmittedAnyChunk = true;
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
          state.hasEmittedAnyChunk = true;
          onChunk({ delta: '', reasoningDelta, done: false });
        }
        if (delta.length > 0) {
          state.hasEmittedAnyChunk = true;
          onChunk({ delta, done: false });
        }
        const rawCalls: OpenAiToolCallDelta[] | undefined = choice.delta?.tool_calls;
        if (rawCalls !== undefined) {
          for (const rc of rawCalls) {
            state.hasEmittedAnyChunk = true;
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
        if (finish !== null) {
          onChunk({ delta: '', done: true, finishReason: finish });
          return true;
        }
      }
    } catch {
      // 非法 JSON 行跳过
    }
    return false;
  }

  private parseFallbackFullBody(
    bodyStr: string,
    onChunk: (chunk: ChatCompletionChunk) => void,
    state: StreamState
  ): void {
    const trimmed: string = bodyStr.trim();
    if (trimmed.startsWith('{')) {
      try {
        const fullParsed = JSON.parse(trimmed) as OpenAiResponse;
        if (fullParsed.choices !== undefined && fullParsed.choices.length > 0) {
          const choiceMsg = fullParsed.choices[0].message;
          const r: string = choiceMsg.reasoning_content ?? '';
          const c: string = choiceMsg.content ?? '';
          if (r.length > 0) {
            state.hasEmittedAnyChunk = true;
            onChunk({ delta: '', reasoningDelta: r, done: false });
          }
          if (c.length > 0) {
            state.hasEmittedAnyChunk = true;
            onChunk({ delta: c, done: false });
          }
        }
      } catch {
        // ignore
      }
    } else if (trimmed.includes('data:')) {
      const lines: string[] = trimmed.split('\n');
      for (const line of lines) {
        this.parseSseLine(line, onChunk, state);
      }
    }
  }

  /** 将 HTTP 状态码与响应体解析为对开发者友好、清晰的中文排障指导 */
  private describeHttpResponse(code: number, rawResult: Object | string | ArrayBuffer | undefined): string {
    let bodyText = '';
    if (rawResult instanceof ArrayBuffer) {
      bodyText = this.arrayBufferToString(rawResult);
    } else if (rawResult !== undefined && rawResult !== null) {
      bodyText = String(rawResult);
    }

    let serverErrMsg = '';
    if (bodyText.length > 0) {
      try {
        const json = JSON.parse(bodyText) as Record<string, Object>;
        if (json.error !== undefined && typeof json.error === 'object') {
          const errObj = json.error as Record<string, Object>;
          if (typeof errObj.message === 'string') {
            serverErrMsg = errObj.message;
          }
        } else if (typeof json.message === 'string') {
          serverErrMsg = json.message as string;
        }
      } catch {
        serverErrMsg = bodyText.slice(0, 160);
      }
    }

    if (code === 401) {
      return `[401 认证失败] API Key 无效或未生效。${serverErrMsg.length > 0 ? `服务商提示: ${serverErrMsg}` : '请检查 Key 是否完整复制，勿遗漏前缀。'}`;
    }
    if (code === 404) {
      return `[404 端点未找到] 路径或模型不存在。${serverErrMsg.length > 0 ? `服务商提示: ${serverErrMsg}` : '请检查 Base URL (建议带 /v1) 或模型 ID 是否正确。'}`;
    }
    if (code === 429) {
      return `[429 配额限制] 速率超限或账户余额不足。${serverErrMsg.length > 0 ? `服务商提示: ${serverErrMsg}` : '请检查服务商控制台余额。'}`;
    }
    if (code === 400) {
      return `[400 参数拒绝] 请求参数不被当前模型网关支持。${serverErrMsg.length > 0 ? `服务商提示: ${serverErrMsg}` : '请检查温度或模型 ID。'}`;
    }
    if (code >= 500) {
      return `[${code} 服务端异常] 上游模型服务暂时过载或故障。${serverErrMsg.length > 0 ? `服务商提示: ${serverErrMsg}` : '请稍后重试。'}`;
    }
    return `HTTP ${code}${serverErrMsg.length > 0 ? `: ${serverErrMsg}` : ''}`;
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
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${key}`
    };
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

  private arrayBufferToString(buf: ArrayBuffer): string {
    const view: Uint8Array = new Uint8Array(buf);
    return new util.TextDecoder('utf-8').decode(view);
  }
}
