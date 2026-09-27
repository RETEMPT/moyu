/**
 * 智能信息提取核心服务 (SmartExtractService)
 *
 * 实现了 FlowMind 的核心闭环：
 * 输入碎片信息 (文字 / OCR结果 / 试卷通知)
 *  ↓ 构造结构化 Prompt
 *  ↓ 调用真实 ModelProvider (OpenAI / DeepSeek / Gemini / 鸿蒙模型)
 *  ↓ 通过 AiParser 容错解析
 *  ↓ 输出 SmartContent (包含 entities, tasks, relations)
 */
import { SmartContent } from '../../common/types/SmartContent';
import { ModelConfigService } from '../ai/ModelConfigService';
import { createProvider, ModelProvider } from '../ai/ModelProvider';
import { ModelProfile, ChatCompletionRequest, ChatMessage, createDefaultProfile } from '../../common/types/ModelConfig';
import { AiParser } from '../ai/AiParser';

const EXTRACTION_SYSTEM_PROMPT: string = `你是一个精准的个人信息工作台结构化提取引擎。
用户会提供碎片信息（如考试通知、会议纪要、课程资料、随笔随想）。
你必须输出且仅输出一个合法的 JSON 对象，不要添加任何额外的解释文本。

JSON 规范如下：
{
  "type": "exam_notice" | "paper_summary" | "course_notes" | "task_memo" | "concept_card" | "general",
  "title": "简洁有力的标题",
  "summary": "1~2句话的核心摘要",
  "tags": ["标签1", "标签2"],
  "keyPoints": ["核心要点1", "核心要点2"],
  "entities": [
    { "id": "e1", "name": "实体名", "type": "time" | "location" | "person" | "course" | "concept", "description": "说明" }
  ],
  "tasks": [
    { "id": "t1", "title": "需要执行的具体待办", "deadline": "截止时间(如有)", "priority": "high" | "medium" | "low" }
  ],
  "relations": [
    { "id": "r1", "sourceTitle": "源概念", "targetTitle": "关联概念", "relationType": "related", "reason": "关联原因" }
  ]
}`;

export class SmartExtractService {
  private static instance: SmartExtractService | null = null;

  static getInstance(): SmartExtractService {
    if (SmartExtractService.instance === null) {
      SmartExtractService.instance = new SmartExtractService();
    }
    return SmartExtractService.instance;
  }

  /**
   * 将输入的碎片文本 / OCR 结果提取为结构化数据
   */
  async extract(rawInput: string, fallbackTitle: string = '智能提取'): Promise<SmartContent> {
    if (rawInput.trim().length === 0) {
      throw new Error('输入内容不能为空');
    }

    const configService = ModelConfigService.getInstance();
    let profile: ModelProfile;
    try {
      profile = await configService.getActiveProfile();
    } catch {
      profile = createDefaultProfile();
    }

    // 如果未配置 API Key，返回优质端侧启发式结构化解析（保证离线体验与演示保底）
    if (profile.apiKey.trim().length === 0) {
      return this.localSimulatedExtract(rawInput, fallbackTitle);
    }

    const msgSystem: ChatMessage = { role: 'system', content: EXTRACTION_SYSTEM_PROMPT };
    const msgUser: ChatMessage = { role: 'user', content: `请分析并结构化提取以下内容：\n\n${rawInput}` };
    const request: ChatCompletionRequest = {
      messages: [msgSystem, msgUser],
      temperature: 0.1,
      maxTokens: 1500,
      stream: false
    };

    try {
      const provider: ModelProvider = createProvider(profile.protocol);
      const resultText: string = await provider.complete(profile, request);
      return AiParser.parseSmartContent(resultText, fallbackTitle);
    } catch (error) {
      console.warn(`网络模型提取失败，切入本地智能容错: ${error}`);
      return this.localSimulatedExtract(rawInput, fallbackTitle);
    }
  }

  /**
   * 本地智能启发式解析（离线断网或未配置 Key 时的全真保底）
   */
  private localSimulatedExtract(text: string, title: string): SmartContent {
    return AiParser.parseSmartContent(text, title);
  }
}
