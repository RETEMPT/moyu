import { ModelProfile, createDefaultProfile } from '../../common/types/ModelConfig';

export interface AiCatalogEntry { id: string; label: string; baseUrl: string; modelId: string; hint: string; docsUrl: string; }
// Explicit user templates, checked 2026-10-09. Not a live availability/pricing directory or a team cloud service.
const ENTRIES: AiCatalogEntry[] = [
  { id: 'seed', label: 'Seed · 豆包', baseUrl: 'https://ark.cn-beijing.volces.com/api/v3/chat/completions', modelId: '',
    hint: '在方舟控制台填写已开通的 Seed 模型 ID 或推理接入点。', docsUrl: 'https://docs.volcengine.com/docs/ark/model-list?lang=zh' },
  { id: 'qwen-max', label: 'Qwen 3.8 Max', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', modelId: 'qwen3.8-max',
    hint: '模板使用北京兼容地址，请按业务空间、地域和密钥调整地址。', docsUrl: 'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope' },
  { id: 'deepseek-flash', label: 'DeepSeek Flash', baseUrl: 'https://api.deepseek.com/chat/completions', modelId: 'deepseek-flash',
    hint: '填写 DeepSeek 开放平台密钥，核对模型开通状态。', docsUrl: 'https://api-docs.deepseek.com/' },
  { id: 'deepseek-pro', label: 'DeepSeek V4 Pro', baseUrl: 'https://api.deepseek.com/chat/completions', modelId: 'deepseek-v4-pro',
    hint: '由你的服务账号调用，费用与可用性按服务商规则。', docsUrl: 'https://api-docs.deepseek.com/' },
  { id: 'glm', label: 'GLM 5.3 · 智谱', baseUrl: 'https://open.bigmodel.cn/api/paas/v4/chat/completions', modelId: 'glm-5.3',
    hint: '使用通用模型 API 密钥；Coding Plan 并非通用接口。', docsUrl: 'https://docs.bigmodel.cn/api-reference/模型-api/对话补全' }
];

export class AiProviderCatalog {
  static list(): AiCatalogEntry[] {
    return ENTRIES.map((entry: AiCatalogEntry) => {
      const copy: AiCatalogEntry = { id: entry.id, label: entry.label, baseUrl: entry.baseUrl,
        modelId: entry.modelId, hint: entry.hint, docsUrl: entry.docsUrl };
      return copy;
    });
  }
  static createDraft(id: string, uniqueId: string): ModelProfile | null {
    const entry = ENTRIES.find((item: AiCatalogEntry) => item.id === id);
    if (!entry || uniqueId.trim().length === 0) { return null; }
    const draft = createDefaultProfile();
    draft.id = uniqueId; draft.label = entry.label; draft.baseUrl = entry.baseUrl; draft.modelId = entry.modelId;
    // Templates do not carry credentials, consent, semantic indexing or automatically enabled write tools.
    draft.toolAccess = 'none';
    return draft;
  }
}
