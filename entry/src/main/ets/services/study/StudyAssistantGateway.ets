import { bundleManager } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
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
}

interface StudyGatewayError { error: string; }

export interface StudyGatewayModel {
  id: string;
  label: string;
  agent: boolean;
}

export interface StudyChatMessage { role: string; content: string; }

interface StudyChatRequest { model: string; messages: StudyChatMessage[]; }
interface StudyChatResponse { reply: string; }

/** Keep complete recent turns in the request while leaving the local transcript intact. */
export function studyChatContext(history: StudyChatMessage[], question: string): StudyChatMessage[] {
  const context: StudyChatMessage[] = [{ role: 'user', content: question }];
  let units = question.length;
  for (let index = history.length - 2; index >= 0 && context.length < 13; index -= 2) {
    const user = history[index];
    const answer = history[index + 1];
    units += user.content.length + answer.content.length;
    if (units > 7000) { break; }
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
}

export class StudyAssistantGateway {
  private active: http.HttpRequest | null = null;

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
          typeof model.agent === 'boolean')) {
        throw new Error('Invalid model catalog');
      }
      return catalog.models;
    } catch { throw new Error('电脑网关的模型列表无效，请确认正在运行新版网关。'); }
  }

  async generate(payload: StudyAssistantRequest, pairingCode: string, model: string): Promise<LearningResult> {
    const generation: StudyGatewayGeneration = { model, operation: payload.operation, goal: payload.goal, sources: payload.sources };
    const raw = await this.request('/study', pairingCode, JSON.stringify(generation));
    const result = LearningResultPolicy.parse(raw);
    if (result.operation !== payload.operation || result.sources.length !== payload.sources.length ||
      !result.sources.every(source => payload.sources.some(fragment => fragment.id === source.id && fragment.text === source.text))) {
      throw new Error('结果与已确认的资料片段不一致，请重新准备请求。');
    }
    return result;
  }

  async chat(messages: StudyChatMessage[], pairingCode: string, model: string): Promise<string> {
    const payload: StudyChatRequest = { model, messages };
    const raw = await this.request('/chat', pairingCode, JSON.stringify(payload));
    try {
      const value = JSON.parse(raw) as StudyChatResponse;
      if (!value || typeof value.reply !== 'string' || !value.reply.trim() || value.reply.length > 4800) {
        throw new Error('Invalid reply');
      }
      return value.reply;
    } catch { throw new Error('电脑网关返回的对话格式无效，请使用新版网关重试。'); }
  }

  private async request(path: string, pairingCode: string, body: string = ''): Promise<string> {
    if (!BuildProfile.DEBUG) { throw new Error('当前构建未开启模拟器网关。'); }
    if (!/^[a-f0-9]{32}$/.test(pairingCode)) { throw new Error('请输入电脑网关显示的 32 位配对码。'); }
    if (this.active) { throw new Error('已有一个请求在处理。'); }
    const request = http.createHttp();
    this.active = request;
    try {
      const options: http.HttpRequestOptions = {
        method: body ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: { 'Content-Type': 'application/json', 'X-Moyu-Pairing': pairingCode },
        expectDataType: http.HttpDataType.STRING,
        usingProxy: false, maxRedirects: 0, maxLimit: LearningResultPolicy.MAX_BYTES,
        connectTimeout: 5000, readTimeout: body ? 70000 : 5000, usingCache: false
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
