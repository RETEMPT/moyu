import { ModelProfile } from '../../common/types/ModelConfig';
import { AgentToolSpec } from '../../common/types/AgentTypes';

export class ModelProfilePolicy {
  static restore(p: ModelProfile): ModelProfile | null {
    if (p === null || typeof p !== 'object' || typeof p.id !== 'string' || !p.id || typeof p.label !== 'string') { return null; }
    if (!['openai-compat', 'gemini', 'anthropic', 'custom'].includes(p.protocol)) { return null; }
    return { id: p.id, label: p.label, protocol: p.protocol, isReasoningModel: p.isReasoningModel === true,
      thinkingBudget: Number.isFinite(p.thinkingBudget) ? p.thinkingBudget : undefined,
      baseUrl: typeof p.baseUrl === 'string' ? p.baseUrl : '',
      apiKey: typeof p.apiKey === 'string' && !p.apiKey.includes('*') ? p.apiKey : '',
      modelId: typeof p.modelId === 'string' ? p.modelId : '',
      embeddingModelId: typeof p.embeddingModelId === 'string' ? p.embeddingModelId : '',
      semanticSearch: p.semanticSearch === true,
      temperature: Number.isFinite(p.temperature) && p.temperature >= 0 && p.temperature <= 2 ? p.temperature : 0.7,
      maxTokens: Number.isInteger(p.maxTokens) && p.maxTokens >= 256 && p.maxTokens <= 65536 ? p.maxTokens : 8192,
      stream: p.stream !== false, systemPrompt: typeof p.systemPrompt === 'string' ? p.systemPrompt.slice(0, 12000) : '',
      toolAccess: p.toolAccess === 'none' || p.toolAccess === 'read' ? p.toolAccess : 'confirm-write',
      maxToolRounds: ModelProfilePolicy.rounds(p), createdAt: Number.isFinite(p.createdAt) ? p.createdAt : Date.now(),
      updatedAt: Number.isFinite(p.updatedAt) ? p.updatedAt : Date.now() };
  }
  static validate(p: ModelProfile): string {
    if (!p.label.trim()) { return '请填写档案名称'; }
    if (!/^https?:\/\/[^\s/?#@]+(?:\/[^\s?#]*)?$/.test(p.baseUrl.trim())) { return '服务地址需为完整的 http 或 https 地址，不含密钥、查询参数或片段'; }
    if (!p.modelId.trim() || /[\r\n]/.test(p.modelId)) { return '请填写服务商实际提供的模型 ID'; }
    if (!p.apiKey.trim() && !/^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(?::\d+)?\//.test(p.baseUrl)) { return '请填写 API Key；本机服务可留空'; }
    if (!Number.isFinite(p.temperature) || p.temperature < 0 || p.temperature > 2) { return '温度需在 0–2 之间'; }
    if (!Number.isInteger(p.maxTokens) || p.maxTokens < 256 || p.maxTokens > 65536) { return '输出上限需为 256–65536 的整数'; }
    if (p.systemPrompt.length > 12000) { return '附加提示词最多 12000 字符'; }
    if (p.semanticSearch && (!p.embeddingModelId?.trim() || p.protocol === 'anthropic')) { return '语义检索需填写向量模型 ID，并使用兼容 API 或 Gemini'; }
    if (!Number.isInteger(p.maxToolRounds ?? 5) || (p.maxToolRounds ?? 5) < 1 || (p.maxToolRounds ?? 5) > 6) { return '工具轮数需在 1–6 之间'; }
    return '';
  }

  static availableTools(p: ModelProfile, tools: AgentToolSpec[]): AgentToolSpec[] {
    // These two providers currently return text only; no native tool events.
    if (!p.stream || (p.protocol !== 'openai-compat' && p.protocol !== 'custom') || p.toolAccess === 'none') { return []; }
    return tools.filter((tool: AgentToolSpec) => p.toolAccess !== 'read' || tool.permission === 'read');
  }

  static rounds(p: ModelProfile): number { return Number.isFinite(p.maxToolRounds) ? Math.max(1, Math.min(6, Math.floor(p.maxToolRounds!))) : 5; }
}
