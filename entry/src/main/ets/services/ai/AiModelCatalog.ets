import { ModelProfile } from '../../common/types/ModelConfig';

export interface AiCatalogModel {
  id: string;
  family: string;
  name: string;
  provider: string;
  modelId: string;
  apiEndpoint: string;
  setupHint: string;
  source: string;
}

// A local directory, not an active cloud provider. No discovery, telemetry or requests.
// Check provider documentation before updating IDs. Availability depends on the user's account.
const MODELS: AiCatalogModel[] = [
  { id: 'seed-pro', family: 'Seed', name: 'Seed 2.1 Pro', provider: '火山方舟',
    modelId: 'doubao-seed-2-1-pro-260915', apiEndpoint: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
    setupHint: '使用方舟通用 API Key，核对控制台中的模型 ID 或推理接入点。',
    source: 'https://docs.volcengine.com/docs/82379/1159178?lang=en' },
  { id: 'seed-lite', family: 'Seed', name: 'Seed 2.1 Lite', provider: '火山方舟',
    modelId: 'doubao-seed-2-1-lite-260915', apiEndpoint: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions',
    setupHint: '使用方舟通用 API Key，核对控制台中的模型 ID 或推理接入点。',
    source: 'https://docs.volcengine.com/docs/ark/text-generation?lang=en' },
  { id: 'qwen-max', family: 'Qwen', name: 'Qwen 3.8 Max', provider: '阿里云百炼',
    modelId: 'qwen3.8-max', apiEndpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    setupHint: '示例为北京地域通用接口；请按百炼业务空间、地域和密钥调整地址。',
    source: 'https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions' },
  { id: 'qwen-flash', family: 'Qwen', name: 'Qwen 3.8 Flash', provider: '阿里云百炼',
    modelId: 'qwen3.8-flash', apiEndpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    setupHint: '示例为北京地域通用接口；请按百炼业务空间、地域和密钥调整地址。',
    source: 'https://help.aliyun.com/zh/model-studio/text-generation-model' },
  { id: 'deepseek-pro', family: 'DeepSeek', name: 'DeepSeek V4 Pro', provider: 'DeepSeek',
    modelId: 'deepseek-v4-pro', apiEndpoint: 'https://api.deepseek.com/v1',
    setupHint: '填写 DeepSeek API Key；模型可用性、额度和费用以控制台为准。',
    source: 'https://api-docs.deepseek.com/zh-cn/' },
  { id: 'deepseek-flash', family: 'DeepSeek', name: 'DeepSeek Flash', provider: 'DeepSeek',
    modelId: 'deepseek-flash', apiEndpoint: 'https://api.deepseek.com/v1',
    setupHint: '填写 DeepSeek API Key；模型可用性、额度和费用以控制台为准。',
    source: 'https://api-docs.deepseek.com/zh-cn/' },
  { id: 'glm', family: 'GLM', name: 'GLM 5.3', provider: '智谱开放平台',
    modelId: 'glm-5.3', apiEndpoint: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    setupHint: '使用通用 API Key。编程订阅套餐的专用端点不适用于此示例。',
    source: 'https://docs.bigmodel.cn/cn/api/introduction' }
];

export class AiModelCatalog {
  static readonly CLOUD_AVAILABLE: boolean = false;
  static readonly CHECKED_AT: string = '2026-10-07';
  static readonly FAMILIES: string[] = ['Seed', 'Qwen', 'DeepSeek', 'GLM'];
  private static sequence: number = 0;

  static list(family: string = ''): AiCatalogModel[] {
    return MODELS.filter((m: AiCatalogModel) => !family || m.family === family)
      .map((m: AiCatalogModel) => JSON.parse(JSON.stringify(m)) as AiCatalogModel);
  }

  static find(id: string): AiCatalogModel | null {
    const item = MODELS.find((m: AiCatalogModel) => m.id === id);
    return item ? JSON.parse(JSON.stringify(item)) as AiCatalogModel : null;
  }

  // Explicitly creates a fresh API draft: never reuses keys, consent or an existing profile.
  static createApiDraft(id: string): ModelProfile | null {
    const item = AiModelCatalog.find(id);
    if (!item) { return null; }
    const now = Date.now();
    return { id: `catalog_${item.id}_${now}_${++AiModelCatalog.sequence}`, label: item.name,
      protocol: 'openai-compat', modelId: item.modelId, baseUrl: item.apiEndpoint, apiKey: '',
      temperature: 0.7, maxTokens: 8192, stream: true, systemPrompt: '',
      semanticSearch: false, toolAccess: 'confirm-write', maxToolRounds: 5,
      createdAt: now, updatedAt: now };
  }
}
