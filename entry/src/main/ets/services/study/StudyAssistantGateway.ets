import { bundleManager } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import BuildProfile from 'BuildProfile';
import { LearningResult } from '../../common/types/LearningResult';
import { LearningResultPolicy } from './LearningResultPolicy';

const DEMO_GATEWAY: string = 'http://10.0.2.2:8765/v1';

export interface StudyAssistantFragment {
  id: string;
  text: string;
}

export interface StudyAssistantRequest {
  operation: string;
  goal: string;
  sources: StudyAssistantFragment[];
  context?: StudyChatMessage[];
  focus?: StudySourceFocusTarget;
}

export interface StudySourceFocusTarget { source_id: string; quote: string; }

interface StudyGatewayError { error: string; }

export interface StudyGatewayModel {
  id: string;
  label: string;
  agent: boolean;
  reasoning?: boolean;
  webSearch?: boolean;
}

export interface StudyGatewaySelection {
  pairingCode: string;
  models: StudyGatewayModel[];
  model: string;
}

export interface StudyRunStep { kind: string; title: string; detail: string; }
export interface StudyWebSource { title: string; url: string; }
export interface StudyChatMessage { role: string; content: string; trace?: StudyRunStep[]; webSources?: StudyWebSource[]; }

interface StudyChatRequest { model: string; messages: StudyChatMessage[]; effort?: string; web?: boolean; }
export interface StudyChatResponse { reply: string; sources?: StudyWebSource[]; }

/** Keep complete recent turns in the request while leaving the local transcript intact. */
export function studyChatContext(history: StudyChatMessage[], question: string, limit: number = 7000,
  turns: number = 6): StudyChatMessage[] {
  const context: StudyChatMessage[] = [{ role: 'user', content: question }];
  let units = question.length;
  for (let index = history.length - 2; index >= 0 && context.length < turns * 2 + 1; index -= 2) {
    const user = history[index];
    const answer = history[index + 1];
    units += user.content.length + answer.content.length;
    if (units > limit) { break; }
    context.unshift(user, answer);
  }
  return context;
}

interface StudyGatewayCatalog { models: StudyGatewayModel[]; }

interface StudyGatewayGeneration {
  model: string;
  operation: string;
  goal: string;
  sources: StudyAssistantFragment[];
  context?: StudyChatMessage[];
  focus?: StudySourceFocusTarget;
  effort?: string;
}

export interface StudyAgentResponse {
  result: LearningResult;
  tools: string[];
}

type StudyStepListener = (step: StudyRunStep, append?: boolean) => void;

interface StudyStreamEvent {
  event: string;
  step?: StudyRunStep;
  payload?: Object;
  message?: string;
}

export class StudyAssistantGateway {
  private active: http.HttpRequest | null = null;

  static previewEnabled(): boolean { return BuildProfile.DEBUG; }

  static async enabled(): Promise<boolean> {
    if (!BuildProfile.DEBUG) { return false; }
    try {
      const info = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION);
      return info.reqPermissionDetails.some(permission => permission.name === 'ohos.permission.INTERNET');
    } catch { return false; }
  }

  cancel(): void {
    const request = this.active;
    this.active = null;
    if (request) {
      try { request.destroy(); } catch { /* A completed request can already be closed. */ }
    }
  }

  async models(pairingCode: string): Promise<StudyGatewayModel[]> {
    const raw = await this.request('/models', pairingCode);
    try {
      const catalog = JSON.parse(raw) as StudyGatewayCatalog;
      if (!catalog || !Array.isArray(catalog.models) || catalog.models.length < 1 || catalog.models.length > 12 ||
        new Set(catalog.models.map(model => model.id)).size !== catalog.models.length ||
        !catalog.models.every(model => model && typeof model.id === 'string' && /^[A-Za-z0-9][A-Za-z0-9._:/-]{0,159}$/.test(model.id) &&
          typeof model.label === 'string' && model.label.trim().length > 0 && model.label.length <= 180 &&
          typeof model.agent === 'boolean' && (model.reasoning === undefined || typeof model.reasoning === 'boolean') &&
          (model.webSearch === undefined || typeof model.webSearch === 'boolean'))) {
        throw new Error('Invalid model catalog');
      }
      return catalog.models;
    } catch { throw new Error('电脑网关的模型列表无效，请确认正在运行新版网关。'); }
  }

  async generate(payload: StudyAssistantRequest, pairingCode: string, model: string): Promise<LearningResult> {
    const generation: StudyGatewayGeneration = { model, operation: payload.operation, goal: payload.goal, sources: payload.sources };
    const raw = await this.request('/study', pairingCode, JSON.stringify(generation));
    return this.validateResult(raw, payload);
  }

  async generateAgent(payload: StudyAssistantRequest, pairingCode: string, model: string,
    onStep?: StudyStepListener, effort?: string): Promise<StudyAgentResponse> {
    const generation: StudyGatewayGeneration = { model, operation: payload.operation, goal: payload.goal, sources: payload.sources,
      effort, focus: payload.focus, context: payload.context?.map((message: StudyChatMessage): StudyChatMessage =>
        ({ role: message.role, content: message.content })) };
    const raw = onStep ? await this.requestStream('/agent/run', pairingCode, JSON.stringify(generation), onStep) :
      await this.request('/agent', pairingCode, JSON.stringify(generation));
    const response = JSON.parse(raw) as StudyAgentResponse;
    if (!response?.result || !Array.isArray(response.tools) || response.tools.length > 2 ||
      !response.tools.every((tool: string) => tool === 'search_selected_sources' || tool === 'read_selected_source')) {
      throw new Error('网关返回的工具记录无效，请检查网关版本。');
    }
    return { result: this.validateResult(JSON.stringify(response.result), payload), tools: response.tools };
  }

  private validateResult(raw: string, payload: StudyAssistantRequest): LearningResult {
    const result = LearningResultPolicy.parse(raw);
    if (result.operation !== payload.operation || result.sources.length !== payload.sources.length ||
      !result.sources.every(source => payload.sources.some(fragment => fragment.id === source.id && fragment.text === source.text))) {
      throw new Error('结果与已确认的资料片段不一致，请重新准备请求。');
    }
    return result;
  }

  async chat(messages: StudyChatMessage[], pairingCode: string, model: string, onStep?: StudyStepListener,
    effort?: string): Promise<string> {
    return (await this.chatReply(messages, pairingCode, model, onStep, effort)).reply;
  }

  async search(messages: StudyChatMessage[], pairingCode: string, model: string, onStep: StudyStepListener,
    effort?: string): Promise<StudyChatResponse> {
    return this.chatReply(messages, pairingCode, model, onStep, effort, true);
  }

  private async chatReply(messages: StudyChatMessage[], pairingCode: string, model: string, onStep?: StudyStepListener,
    effort?: string, web?: boolean): Promise<StudyChatResponse> {
    const payload: StudyChatRequest = { model, effort, web,
      messages: messages.map((item: StudyChatMessage): StudyChatMessage => ({ role: item.role, content: item.content })) };
    const raw = onStep ? await this.requestStream('/chat/run', pairingCode, JSON.stringify(payload), onStep) :
      await this.request('/chat', pairingCode, JSON.stringify(payload));
    try {
      const value = JSON.parse(raw) as StudyChatResponse;
      if (!value || typeof value.reply !== 'string' || !value.reply.trim() || value.reply.length > 4800) {
        throw new Error('Invalid reply');
      }
      if (web && (!Array.isArray(value.sources) || value.sources.length > 12 ||
        !value.sources.every((source: StudyWebSource) => source && typeof source.title === 'string' &&
          source.title.trim().length > 0 && source.title.length <= 320 && typeof source.url === 'string' && source.url.length <= 3000 &&
          /^https?:\/\/[a-z0-9.-]+(?::[0-9]+)?(?:[/?#][^\s<>\\]*)?$/i.test(source.url)))) {
        throw new Error('Invalid sources');
      }
      return value;
    } catch { throw new Error('电脑网关返回的对话格式无效，请使用新版网关重试。'); }
  }

  private openRequest(pairingCode: string): http.HttpRequest {
    if (!BuildProfile.DEBUG) { throw new Error('当前构建未开启模拟器网关。'); }
    if (!/^[a-f0-9]{32}$/.test(pairingCode)) { throw new Error('请输入电脑网关显示的 32 位配对码。'); }
    if (this.active) { throw new Error('已有一个请求在处理。'); }
    const request = http.createHttp();
    this.active = request;
    return request;
  }

  private async requestStream(path: string, pairingCode: string, body: string,
    onStep: StudyStepListener): Promise<string> {
    const request = this.openRequest(pairingCode);
    const decoder = util.TextDecoder.create('utf-8', { fatal: true });
    let raw = '';
    let result = '';
    let failure = '';
    let size = 0;
    let steps = 0;
    request.on('dataReceive', (data: ArrayBuffer): void => {
      if (failure || this.active !== request) { return; }
      try {
        size += data.byteLength;
        if (size > 262144) { throw new Error('运行轨迹超过大小限制'); }
        raw += decoder.decodeToString(new Uint8Array(data), { stream: true });
        let end = raw.indexOf('\n');
        while (end !== -1) {
          const event = JSON.parse(raw.slice(0, end)) as StudyStreamEvent;
          raw = raw.slice(end + 1);
          if (result || !event) { throw new Error('收到重复或无效的运行事件'); }
          if (event.event === 'result' && event.payload) { result = JSON.stringify(event.payload); }
          else if (event.event === 'error' && typeof event.message === 'string' && event.message.length <= 400) {
            failure = event.message || '生成失败'; return;
          } else if ((event.event === 'step' || event.event === 'reasoning_delta') && event.step &&
            (event.event === 'step' ? ++steps <= 24 : event.step.kind === 'reasoning') &&
            ['prepare', 'model', 'reasoning', 'tool', 'verify'].includes(event.step.kind) &&
            typeof event.step.title === 'string' && event.step.title.length <= 80 &&
            typeof event.step.detail === 'string' && event.step.detail.length <= 9000) {
            onStep(event.step, event.event === 'reasoning_delta');
          } else { throw new Error('网关返回的运行轨迹格式无效'); }
          end = raw.indexOf('\n');
        }
      } catch (error) { failure = (error as Error).message || '网关运行轨迹无法读取'; }
    });
    try {
      const status = await request.requestInStream(DEMO_GATEWAY + path, {
        method: http.RequestMethod.POST, extraData: body,
        header: { 'Content-Type': 'application/json', 'X-Moyu-Pairing': pairingCode, 'X-Moyu-Trace': 'live-v1' },
        usingProxy: false, maxRedirects: 0, maxLimit: 262144, connectTimeout: 5000,
        readTimeout: 105000, usingCache: false
      }).catch(() => { throw new Error('无法连接电脑网关，或生成超时。请确认网关在运行。'); });
      if (status !== 200) {
        let detail = '';
        try { detail = (JSON.parse(raw) as StudyGatewayError).error; } catch { /* Status is enough. */ }
        throw new Error(status === 404 ? '请启动支持运行轨迹的新版电脑网关。' : (detail || `网关 HTTP ${status}`));
      }
      if (failure) { throw new Error(failure); }
      if (!result || raw.trim()) { throw new Error('运行中断，可重试或修改问题。'); }
      return result;
    } finally {
      if (this.active === request) { this.cancel(); }
    }
  }

  private async request(path: string, pairingCode: string, body: string = ''): Promise<string> {
    const request = this.openRequest(pairingCode);
    try {
      const options: http.HttpRequestOptions = {
        method: body ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: { 'Content-Type': 'application/json', 'X-Moyu-Pairing': pairingCode },
        expectDataType: http.HttpDataType.STRING,
        usingProxy: false, maxRedirects: 0, maxLimit: LearningResultPolicy.MAX_BYTES,
        connectTimeout: 5000, readTimeout: body ? 105000 : 5000, usingCache: false
      };
      if (body) { options.extraData = body; }
      const response = await request.request(DEMO_GATEWAY + path, options)
        .catch(() => { throw new Error('无法连接电脑网关，或生成超时。请确认网关在运行。'); });
      const raw = typeof response.result === 'string' ? response.result : '';
      if (response.responseCode !== 200) {
        let detail = '';
        try { detail = (JSON.parse(raw) as StudyGatewayError).error; } catch { /* Status is enough. */ }
        throw new Error(typeof detail === 'string' && detail.length > 0 && detail.length < 240 ?
          detail : `电脑网关返回错误 ${response.responseCode}。`);
      }
      return raw;
    } finally {
      if (this.active === request) { this.cancel(); }
    }
  }
}
