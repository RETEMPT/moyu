/**
 * 三层智能体调度核心
 *
 * L1 伴读：针对当前打开文档的问答（上下文=当前文档）
 * L2 学情：学习分析（上下文=笔记元数据+标签+待办+链接图）
 * L3 跨库：全库 RAG 问答（上下文=检索片段+来源引用）
 *
 * 调度流程：意图判定 → 层选择 → 构建上下文 → 模型流式补全 → 归一化消息
 * 工具循环：模型返回 tool_call → 框架执行 → 结果回灌 → 模型继续（最多5轮）
 */
import {
  ChatMessage,
  ChatCompletionChunk,
  ModelProfile,
  ToolCallRequest
} from '../../common/types/ModelConfig';
import {
  StoredMessage,
  ChatCitation,
  createMessage
} from '../../common/types/ChatSession';
import { AgentToolSpec, AgentToolExecutor, AgentToolResult } from '../../common/types/AgentTypes';
import { ModelProvider, StreamHandle, createProvider } from './ModelProvider';
import { ModelConfigService } from './ModelConfigService';
import { buildOpenAiToolsJson, findTool } from './ToolRegistry';

/** Agent 层级 */
export type AgentLayer = 'L1' | 'L2' | 'L3';

/** 当前文档上下文（L1） */
export interface CurrentDocContext {
  title: string;
  content: string;
  outline: string;
}

/** Agent 运行上下文 */
export interface AgentRunContext {
  /** 用户提问 */
  query: string;
  /** 当前文档内容（L1） */
  currentDoc?: CurrentDocContext;
  /** 用户强制上下文（@ 指定的笔记） */
  pinnedNotes?: string[];
  /** 检索片段（L3） */
  retrievalHits?: ChatCitation[];
  /** 学情数据（L2） */
  learningContext?: string;
  /** 历史消息（多轮对话） */
  history: StoredMessage[];
  /** 本轮允许模型调用的工具；为空则不带工具字段，模型只能纯文本作答 */
  tools?: AgentToolSpec[];
  /** 工具执行器（由 UI 层注入，负责真正读写本地数据） */
  executor?: AgentToolExecutor;
  /** 写操作的确认回调；返回 false 则拒绝执行。未提供时写操作一律拒绝 */
  confirm?: ToolConfirmCallback;
}

/** 工具确认回调：返回 true 则执行 */
export type ToolConfirmCallback = (toolName: string, argsJson: string) => Promise<boolean>;

/** 单轮流式的结果 */
interface AgentRound {
  text: string;
  reasoningText: string;
  toolCalls: ToolCallRequest[];
}

const MAX_TOOL_ROUNDS: number = 5;

/** L1 伴读系统提示词 */
const L1_SYSTEM_PROMPT: string = `<system_instructions>
你是「FlowMind 墨客 · 伴读助手」，专注于研读与文档分析，正在陪同用户阅读当前文档。

<grounding_rules>
1. 【严格事实闭环】：你必须且只能依据下面给出的 <current_document> 内容回答。文档中未明确记录的信息，绝不主观推测或捏造。
2. 【未知内容引导】：当用户提问超出该文档范围时，明确告知：「当前文档未收录相关内容」，并建议切换至跨库检索或 @ 关联笔记。
3. 【段落定位标注】：引用文档要点、结论或定理时，在句末使用小节索引标注：〔§小节名〕。
4. 【严谨公式推导】：遇到数学/物理/推导内容，必须使用标准 LaTeX 围栏语法 $$公式$$ 独立居中渲染，行内公式采用 $公式$。
5. 【纯本地安全准则】：严禁声称自身可以实时联网或访问外部私有系统。
</grounding_rules>

<output_format>
- 结构化分条陈述，核心论点前置。
- 公式推导逻辑严密，每一步给出文档依据。
</output_format>
</system_instructions>`;

/** L2 学情系统提示词 */
const L2_SYSTEM_PROMPT: string = `<system_instructions>
你是「FlowMind 墨客 · 学情教练」，专注于个性化学习分析与复习规划。

<grounding_rules>
1. 【依据真实数据】：严格依据 <learning_analytics> 中汇总的笔记数、更新时序、双链网络及待办完成率作答。
2. 【杜绝虚构统计】：不得无中生有编造未在上下文中出现的分数、答题正确率或虚假学习时长。
3. 【行动导向建议】：复习计划必须精准落地到具体关联笔记标题与明确的时间节点。
4. 【写操作前置提示】：若准备帮助用户创建复习待办，必须在文字中先行列出待办清单，再通过工具发起。
</grounding_rules>

<output_format>
采用结构化卡片排版：
1. 现状概览（知识库规模与活跃度）
2. 薄弱点与断层分析（孤立笔记/滞后待办）
3. 推荐复习计划（可执行清单）
</output_format>
</system_instructions>`;

/** L3 跨库系统提示词 */
const L3_SYSTEM_PROMPT: string = `<system_instructions>
你是「FlowMind 墨客 · 跨库研究员」，专注于全库知识检索与综合研读。

<grounding_rules>
1. 【事实依据与引文】：答案必须完全根植于 <knowledge_excerpts> 命中的笔记切片以及用户强制绑定的 @ 笔记。
2. 【精确溯源角标】：每条关键结论或事实陈述末尾，必须标注来源角标，格式统一为：〔来源：笔记标题 · 章节〕。
3. 【检索未命中应对】：若命中的片段不足以回答用户提问，务必诚实回复：「在当前知识库中未检索到充分依据」，并给出 2~3 个建议检索关键词。
4. 【冲突如实呈现】：若多篇笔记记载存在差异，如实指明不同笔记的表述，不擅自主观修改或盲目合并。
5. 【数学排版】：公式使用 LaTeX $$...$$ 独立居中排版。
</grounding_rules>

<output_format>
- 结论先行，分层剖析。
- 综合多篇笔记时以小标题或分块罗列，保持 Obsidian 极简商务美感。
</output_format>
</system_instructions>`;

export class AgentOrchestrator {

  /**
   * 运行 Agent：构建消息数组 → 流式补全（含思考流 + 正文流） → 工具循环。
   *
   * 每轮把模型的文本增量与 DeepSeek-R1 思考流通过 onDelta 推出；
   * 若模型请求了工具，执行结果会作为 role=tool 消息回灌后进入下一轮。
   *
   * @param onDelta (text: 正文全文, done: 是否结束, reasoningText?: 思考链全文)
   * @param onHandle 每轮开始流式时回调，供调用方拿到取消句柄
   */
  async run(
    layer: AgentLayer,
    ctx: AgentRunContext,
    onDelta: (text: string, done: boolean, reasoningText?: string) => void,
    onHandle?: (handle: StreamHandle) => void
  ): Promise<StoredMessage> {
    const configService: ModelConfigService = ModelConfigService.getInstance();
    const profile: ModelProfile = await configService.getActiveProfile();
    const provider: ModelProvider = createProvider(profile.protocol);

    const messages: ChatMessage[] = this.buildMessages(layer, ctx);
    const toolsJson: string = ctx.tools !== undefined ? buildOpenAiToolsJson(ctx.tools) : '';

    const assistantMsg: StoredMessage = createMessage('assistant', '');
    assistantMsg.agentLayer = layer;
    assistantMsg.modelProfileId = profile.id;
    assistantMsg.streaming = true;

    let rounds: number = 0;
    while (rounds < MAX_TOOL_ROUNDS) {
      rounds++;
      const prefix: string = assistantMsg.text;
      const round: AgentRound = await this.runRound(
        provider,
        profile,
        messages,
        toolsJson,
        onHandle,
        (roundText: string) => {
          onDelta(prefix.length > 0 ? `${prefix}\n\n${roundText}` : roundText, false, assistantMsg.reasoningContent);
        },
        (roundReasoning: string) => {
          assistantMsg.reasoningContent = roundReasoning;
          onDelta(assistantMsg.text, false, roundReasoning);
        }
      );

      if (round.text.length > 0) {
        assistantMsg.text = prefix.length > 0 ? `${prefix}\n\n${round.text}` : round.text;
      }
      if (round.reasoningText.length > 0) {
        assistantMsg.reasoningContent = round.reasoningText;
      }
      if (round.toolCalls.length === 0) {
        break;
      }

      // 把模型这一轮的决策原样回灌
      messages.push({
        role: 'assistant',
        content: round.text,
        reasoningContent: round.reasoningText.length > 0 ? round.reasoningText : undefined,
        toolCalls: round.toolCalls
      });
      for (const call of round.toolCalls) {
        const result: AgentToolResult = await this.executeTool(call, ctx);
        messages.push({ role: 'tool', content: result.content, toolCallId: call.id });
      }
    }

    assistantMsg.streaming = false;
    if (assistantMsg.text.trim().length === 0) {
      if (assistantMsg.reasoningContent !== undefined && assistantMsg.reasoningContent.trim().length > 0) {
        assistantMsg.text = '（已完成深度思考推演。可在上方展开查看完整推理过程；若需提炼特定文档，请在右侧栏确认伴读文档或 @ 关联笔记）';
      } else {
        assistantMsg.text = '未能从当前知识库切片或模型获取到有效内容，建议在右侧栏绑定伴读文档或使用「+ 附加笔记」补充上下文。';
      }
    }
    onDelta(assistantMsg.text, true, assistantMsg.reasoningContent);
    return assistantMsg;
  }

  /** 跑一轮流式补全，把正文、DeepSeek 思考链与工具调用片段分别归集 */
  private async runRound(
    provider: ModelProvider,
    profile: ModelProfile,
    messages: ChatMessage[],
    toolsJson: string,
    onHandle: ((handle: StreamHandle) => void) | undefined,
    onRoundText: (text: string) => void,
    onRoundReasoning: (reasoning: string) => void
  ): Promise<AgentRound> {
    let text: string = '';
    let reasoningText: string = '';
    const argBuf: Map<number, string> = new Map();
    const nameBuf: Map<number, string> = new Map();
    const idBuf: Map<number, string> = new Map();

    return new Promise<AgentRound>((resolve, reject) => {
      let settled: boolean = false;
      const finish = (): void => {
        if (settled) {
          return;
        }
        settled = true;
        const indices: number[] = Array.from(argBuf.keys()).sort((a: number, b: number) => a - b);
        const calls: ToolCallRequest[] = [];
        for (const idx of indices) {
          const name: string = nameBuf.get(idx) ?? '';
          if (name.length === 0) {
            continue;
          }
          calls.push({
            id: idBuf.get(idx) ?? `call_${idx}`,
            name,
            arguments: argBuf.get(idx) ?? '{}'
          });
        }
        resolve({ text, reasoningText, toolCalls: calls });
      };

      provider.completeStream(
        profile,
        {
          messages,
          temperature: profile.temperature,
          maxTokens: profile.maxTokens,
          stream: true,
          toolsJson: toolsJson.length > 0 ? toolsJson : undefined
        },
        (chunk: ChatCompletionChunk) => {
          if (chunk.error !== undefined && chunk.error.length > 0) {
            if (!settled) {
              settled = true;
              reject(new Error(chunk.error));
            }
            return;
          }
          // DeepSeek R1 思考流增量
          if (chunk.reasoningDelta !== undefined && chunk.reasoningDelta.length > 0) {
            reasoningText += chunk.reasoningDelta;
            onRoundReasoning(reasoningText);
          }
          // 正文增量
          if (chunk.delta.length > 0) {
            text += chunk.delta;
            onRoundText(text);
          }
          const tc = chunk.toolCall;
          if (tc !== undefined) {
            if (tc.id !== undefined && tc.id.length > 0) {
              idBuf.set(tc.index, tc.id);
            }
            if (tc.name !== undefined && tc.name.length > 0) {
              nameBuf.set(tc.index, tc.name);
            }
            if (tc.argumentsFragment !== undefined) {
              argBuf.set(tc.index, (argBuf.get(tc.index) ?? '') + tc.argumentsFragment);
            }
          }
          if (chunk.done) {
            finish();
          }
        }
      ).then((handle: StreamHandle) => {
        if (onHandle !== undefined) {
          onHandle(handle);
        }
      }).catch((err: Error) => {
        if (!settled) {
          settled = true;
          reject(err);
        }
      });
    });
  }

  /** 执行一次工具调用：写操作必须先拿到用户确认，拿不到就拒绝 */
  private async executeTool(call: ToolCallRequest, ctx: AgentRunContext): Promise<AgentToolResult> {
    const spec: AgentToolSpec | null = findTool(call.name);
    if (spec === null) {
      return { ok: false, content: `没有名为 ${call.name} 的工具，请改用已有工具或直接作答。` };
    }
    if (ctx.executor === undefined) {
      return { ok: false, content: '当前没有可用的工具执行器，请直接作答。' };
    }
    if (spec.permission === 'write') {
      if (ctx.confirm === undefined) {
        return { ok: false, content: '该操作需要用户授权，但当前无法发起确认，已取消。请改用文字说明。' };
      }
      let approved: boolean = false;
      try {
        approved = await ctx.confirm(call.name, call.arguments);
      } catch {
        approved = false;
      }
      if (!approved) {
        return { ok: false, content: '用户拒绝了该操作，不要重试，改用文字说明。' };
      }
    }
    try {
      return await ctx.executor.execute(call.name, call.arguments);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : '未知错误';
      return { ok: false, content: `工具执行失败: ${msg}` };
    }
  }

  /** 构建各层的完整消息数组 */
  private buildMessages(layer: AgentLayer, ctx: AgentRunContext): ChatMessage[] {
    const systemPrompt: string = this.buildSystemPrompt(layer, ctx);
    const messages: ChatMessage[] = [];

    // system
    messages.push({ role: 'system', content: systemPrompt });

    // 历史（最近8条）
    const history: StoredMessage[] = ctx.history.slice(-8);
    for (const h of history) {
      if (h.role === 'user' || h.role === 'assistant') {
        messages.push({ role: h.role, content: h.text });
      }
    }

    // 当前提问
    messages.push({ role: 'user', content: ctx.query });

    return messages;
  }

  private buildSystemPrompt(layer: AgentLayer, ctx: AgentRunContext): string {
    let prompt: string = '';
    if (layer === 'L1') {
      prompt = L1_SYSTEM_PROMPT;
      if (ctx.currentDoc !== undefined) {
        prompt += `\n\n<current_document>\n标题：${ctx.currentDoc.title}\n大纲：${ctx.currentDoc.outline}\n\n正文：\n${ctx.currentDoc.content}\n</current_document>`;
      }
    } else if (layer === 'L2') {
      prompt = L2_SYSTEM_PROMPT;
      if (ctx.learningContext !== undefined && ctx.learningContext.length > 0) {
        prompt += `\n\n<learning_analytics>\n${ctx.learningContext}\n</learning_analytics>`;
      }
    } else {
      // L3
      prompt = L3_SYSTEM_PROMPT;
      if (ctx.retrievalHits !== undefined && ctx.retrievalHits.length > 0) {
        prompt += `\n\n<knowledge_excerpts>\n`;
        for (let i = 0; i < ctx.retrievalHits.length; i++) {
          const h: ChatCitation = ctx.retrievalHits[i];
          prompt += `〔片段 ${i + 1}〕${h.noteTitle} · ${h.headingPath}\n${h.chunkText}\n\n`;
        }
        prompt += `</knowledge_excerpts>`;
      } else {
        prompt += `\n\n<knowledge_excerpts>\n（本次检索未命中任何知识库切片）\n</knowledge_excerpts>`;
      }
    }

    // 注入工程挂载文档（所有模式均优先感知）
    if (ctx.pinnedNotes !== undefined && ctx.pinnedNotes.length > 0) {
      prompt += `\n\n<workspace_project_context>\n【已挂载参考文档共 ${ctx.pinnedNotes.length} 篇】\n${ctx.pinnedNotes.join('\n---\n')}\n\n【研读指令】：以上为已挂载参考文档，请优先结合文档内容解答，并标明出处。\n</workspace_project_context>`;
    }

    return prompt;
  }

  /**
   * 意图分类（极简实现，走 L1 默认）
   * TODO: 接模型分类器（附录 D.4），此处先用关键词规则兜底
   */
  classify(query: string): AgentLayer {
    const q: string = query.toLowerCase();
    // L2: 学情/复习/计划/待办
    if (/复习|计划|学情|掌握|薄弱|待办|进度|学习/.test(q)) {
      return 'L2';
    }
    // L3: 全库/综合/跨/所有/我的笔记
    if (/全部|所有|综合|跨|我的笔记|知识图谱|关联/.test(q)) {
      return 'L3';
    }
    // L1: 指向当前文档
    if (/这篇|当前|这段|本文档|改写|总结|推导/.test(q)) {
      return 'L1';
    }
    // 默认 L3（跨库问答是主入口）
    return 'L3';
  }
}
