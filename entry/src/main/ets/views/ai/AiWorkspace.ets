/**
 * AI 墨客主操作台 (AiWorkspace)
 *
 * 融合 DeepSeek-Harness 极客架构与 Obsidian × Notion 高端商务美学：
 * 1. 顶栏：悬浮分段模式滑块（✦ 自动调度 / ▤ 伴读模式 / ◇ 学情分析 / ⊡ 跨库知识）+ 连通性模型芯片
 * 2. 深度思考流 (Reasoning Stream)：原生渲染 DeepSeek-R1 思考流，微光呼吸灯指示 + 折叠展开交互卡片
 * 3. 工具可视化：工具执行步进徽标与结果摘要卡片
 * 4. 交互式空态看板：几何徽标 + 伴读锁定提示 + 4 大生产力场景卡
 * 5. 悬浮岛输入控制台 (Floating Cockpit)：多行自适应输入 + 顶置 @ 笔记药丸 + 深度思考指示灯
 */
import { curves, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import {
  ChatSession,
  StoredMessage,
  ChatCitation,
  createEmptySession,
  createMessage
} from '../../common/types/ChatSession';
import { ModelProfile } from '../../common/types/ModelConfig';
import { AgentOrchestrator, AgentLayer, AgentRunContext, CurrentDocContext } from '../../services/ai/AgentOrchestrator';
import { ChatSessionService } from '../../services/ai/ChatSessionService';
import { ModelConfigService, ACTIVE_STORAGE_KEY } from '../../services/ai/ModelConfigService';
import { RagRetriever } from '../../services/ai/RagRetriever';
import { StreamHandle } from '../../services/ai/ModelProvider';
import { NoteItem } from '../../common/types/NoteItem';
import { TodoItem } from '../../common/types/TodoItem';
import { WorkspaceStats } from '../../common/types/WorkspaceStats';
import { MarkdownDocument } from '../../common/types/MarkdownDocument';
import { RetrievalHit } from '../../common/types/RagTypes';
import { AgentToolExecutor, AgentToolResult } from '../../common/types/AgentTypes';
import { AGENT_TOOLS, toolDisplayName } from '../../services/ai/ToolRegistry';
import { DocumentImportService } from '../../services/document/DocumentImportService';

interface QuickPrompt {
  title: string;
  badge: string;
  desc: string;
  query: string;
}

interface AgentModeTabItem {
  mode: string;
  title: string;
}

interface ThinkingBudgetPreset {
  key: string;
  label: string;
  val: number;
}

const THINKING_BUDGETS: ThinkingBudgetPreset[] = [
  { key: 'low', label: 'Low', val: 4096 },
  { key: 'medium', label: 'Medium', val: 16384 },
  { key: 'high', label: 'High', val: 32768 },
  { key: 'max', label: 'Max', val: 65536 }
];

const MODE_TABS: AgentModeTabItem[] = [
  { mode: 'auto', title: '自动' },
  { mode: 'L1', title: '伴读' },
  { mode: 'L2', title: '学情' },
  { mode: 'L3', title: '跨库' }
];

interface SearchNotesArgs {
  query?: string;
  limit?: number;
}

interface ListNotesArgs {
  category?: string;
}

interface ReadNoteArgs {
  identifier?: string;
}

interface CreateTodoArgs {
  title?: string;
  date?: string;
}

interface AddTagArgs {
  identifier?: string;
  tags?: string;
}

interface CreateLinkArgs {
  sourceIdentifier?: string;
  targetTitle?: string;
  reason?: string;
}

interface CategorizeNoteArgs {
  identifier?: string;
  category?: string;
}

interface CreateNoteArgs {
  title?: string;
  category?: string;
  tag?: string;
  content?: string;
}

/** 智能体协同规划条目 */
export interface ProposedActionItem {
  id: string;
  type: string; // 'todo' | 'tag' | 'link' | 'category' | 'note'
  title: string;
  desc: string;
  target?: string;
  value?: string;
  source?: string;
  date?: string;
  content?: string;
}

/** 智能体方案提案数据 */
export interface ActionProposalData {
  summary: string;
  actions: ProposedActionItem[];
}

/**
 * 智能体工具执行器
 */
class WorkspaceToolExecutor implements AgentToolExecutor {
  private searchFn: (query: string, limit: number) => string;
  private listFn: (category: string) => string;
  private readFn: (identifier: string) => string;
  private summarizeFn: () => string;
  private createTodoFn: (date: string, title: string) => string;
  private addTagFn: (identifier: string, tags: string) => string;
  private createLinkFn: (sourceIdentifier: string, targetTitle: string, reason?: string) => string;
  private categorizeFn: (identifier: string, category: string) => string;
  private createNoteFn: (title: string, category: string, tag: string, content: string) => string;
  private onProgress: (text: string) => void;

  constructor(
    searchFn: (query: string, limit: number) => string,
    listFn: (category: string) => string,
    readFn: (identifier: string) => string,
    summarizeFn: () => string,
    createTodoFn: (date: string, title: string) => string,
    addTagFn: (identifier: string, tags: string) => string,
    createLinkFn: (sourceIdentifier: string, targetTitle: string, reason?: string) => string,
    categorizeFn: (identifier: string, category: string) => string,
    createNoteFn: (title: string, category: string, tag: string, content: string) => string,
    onProgress: (text: string) => void
  ) {
    this.searchFn = searchFn;
    this.listFn = listFn;
    this.readFn = readFn;
    this.summarizeFn = summarizeFn;
    this.createTodoFn = createTodoFn;
    this.addTagFn = addTagFn;
    this.createLinkFn = createLinkFn;
    this.categorizeFn = categorizeFn;
    this.createNoteFn = createNoteFn;
    this.onProgress = onProgress;
  }

  async execute(toolName: string, argsJson: string): Promise<AgentToolResult> {
    if (toolName === 'search_notes') {
      let args: SearchNotesArgs = {};
      try {
        args = JSON.parse(argsJson) as SearchNotesArgs;
      } catch {
        return { ok: false, content: '参数不是合法 JSON，请重新给出符合 schema 的参数。' };
      }
      const query: string = (args.query ?? '').trim();
      if (query.length === 0) {
        return { ok: false, content: 'query 不能为空。' };
      }
      this.onProgress(`正在检索「${query}」…`);
      const limit: number = args.limit !== undefined && args.limit > 0 ? Math.min(args.limit, 10) : 5;
      const content: string = this.searchFn(query, limit);
      this.onProgress('');
      return { ok: true, content };
    }

    if (toolName === 'list_notes') {
      let args: ListNotesArgs = {};
      try {
        args = JSON.parse(argsJson) as ListNotesArgs;
      } catch {
        return { ok: false, content: '参数不是合法 JSON，请重新给出符合 schema 的参数。' };
      }
      this.onProgress('正在读取笔记目录…');
      const content: string = this.listFn((args.category ?? '').trim());
      this.onProgress('');
      return { ok: true, content };
    }

    if (toolName === 'read_note') {
      let args: ReadNoteArgs = {};
      try {
        args = JSON.parse(argsJson) as ReadNoteArgs;
      } catch {
        return { ok: false, content: '参数不是合法 JSON，请重新给出符合 schema 的参数。' };
      }
      const iden: string = (args.identifier ?? '').trim();
      if (iden.length === 0) {
        return { ok: false, content: 'identifier 不能为空。' };
      }
      this.onProgress(`正在研读笔记「${iden}」…`);
      const content: string = this.readFn(iden);
      this.onProgress('');
      return { ok: true, content };
    }

    if (toolName === 'summarize_vault') {
      this.onProgress('正在盘点知识库全景…');
      const content: string = this.summarizeFn();
      this.onProgress('');
      return { ok: true, content };
    }

    if (toolName === 'create_todo') {
      let args: CreateTodoArgs = {};
      try {
        args = JSON.parse(argsJson) as CreateTodoArgs;
      } catch {
        return { ok: false, content: '参数不是合法 JSON，请重新给出符合 schema 的参数。' };
      }
      const title: string = (args.title ?? '').trim();
      if (title.length === 0) {
        return { ok: false, content: 'title 不能为空。' };
      }
      this.onProgress('正在创建待办事项…');
      const content: string = this.createTodoFn(this.normalizeDate(args.date), title);
      this.onProgress('');
      return { ok: true, content };
    }

    if (toolName === 'add_tag_to_note') {
      let args: AddTagArgs = {};
      try {
        args = JSON.parse(argsJson) as AddTagArgs;
      } catch {
        return { ok: false, content: '参数不是合法 JSON。' };
      }
      const iden: string = (args.identifier ?? '').trim();
      const tags: string = (args.tags ?? '').trim();
      if (iden.length === 0 || tags.length === 0) {
        return { ok: false, content: 'identifier 与 tags 均不能为空。' };
      }
      this.onProgress(`正在为「${iden}」追加标签…`);
      const content: string = this.addTagFn(iden, tags);
      this.onProgress('');
      return { ok: true, content };
    }

    if (toolName === 'create_link') {
      let args: CreateLinkArgs = {};
      try {
        args = JSON.parse(argsJson) as CreateLinkArgs;
      } catch {
        return { ok: false, content: '参数不是合法 JSON。' };
      }
      const src: string = (args.sourceIdentifier ?? '').trim();
      const tgt: string = (args.targetTitle ?? '').trim();
      if (src.length === 0 || tgt.length === 0) {
        return { ok: false, content: 'sourceIdentifier 与 targetTitle 均不能为空。' };
      }
      this.onProgress(`正在建立指向「${tgt}」的双链…`);
      const content: string = this.createLinkFn(src, tgt, args.reason);
      this.onProgress('');
      return { ok: true, content };
    }

    if (toolName === 'categorize_note') {
      let args: CategorizeNoteArgs = {};
      try {
        args = JSON.parse(argsJson) as CategorizeNoteArgs;
      } catch {
        return { ok: false, content: '参数不是合法 JSON。' };
      }
      const iden: string = (args.identifier ?? '').trim();
      const cat: string = (args.category ?? '').trim();
      if (iden.length === 0 || cat.length === 0) {
        return { ok: false, content: 'identifier 与 category 均不能为空。' };
      }
      this.onProgress(`正在将「${iden}」分类归入「${cat}」…`);
      const content: string = this.categorizeFn(iden, cat);
      this.onProgress('');
      return { ok: true, content };
    }

    if (toolName === 'create_note') {
      let args: CreateNoteArgs = {};
      try {
        args = JSON.parse(argsJson) as CreateNoteArgs;
      } catch {
        return { ok: false, content: '参数不是合法 JSON。' };
      }
      const title: string = (args.title ?? '').trim();
      const contentText: string = (args.content ?? '').trim();
      if (title.length === 0) {
        return { ok: false, content: 'title 不能为空。' };
      }
      this.onProgress(`正在创建新笔记「${title}」…`);
      const content: string = this.createNoteFn(title, args.category ?? '未分类', args.tag ?? '', contentText);
      this.onProgress('');
      return { ok: true, content };
    }

    return { ok: false, content: `未注册工具: ${toolName}` };
  }

  private normalizeDate(raw: string | undefined): string {
    const d: Date = new Date();
    const today: string = `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
    if (raw === undefined) {
      return today;
    }
    const trimmed: string = raw.trim();
    if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
      return trimmed;
    }
    if (trimmed === '明天') {
      const t: Date = new Date(d.getTime() + 24 * 60 * 60 * 1000);
      return `${t.getFullYear()}-${pad2(t.getMonth() + 1)}-${pad2(t.getDate())}`;
    }
    return today;
  }
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

const QUICK_PROMPTS: QuickPrompt[] = [
  { title: '智能规划', badge: '规划', desc: '梳理分类、双链与待办', query: '请深度分析我的知识库现状，提出具体的分类标签、双向链接与待办复习规划，并以 action_proposal 格式输出协同方案供我一键确认。' },
  { title: '文档提炼', badge: '提炼', desc: '总结核心要点与逻辑', query: '请帮我提炼当前文档的核心结论与主要推导步骤。' },
  { title: '双链关联', badge: '关联', desc: '挖掘笔记间的潜在联系', query: '检索我的全部笔记，分析其中可能存在的跨学科或双向关联概念。' },
  { title: '知识全景', badge: '全景', desc: '宏观汇总知识资产分布', query: '调用知识库概览工具，帮我统计知识库结构与重点分类。' }
];

@Component
export struct AiWorkspace {
  currentNote: NoteItem | null = null;
  allNotes: NoteItem[] = [];
  todos: TodoItem[] = [];
  stats: WorkspaceStats = { noteCount: 0, linkCount: 0, unresolvedCount: 0, tagCount: 0 };

  @Prop @Watch('onActiveSessionIdChanged') activeSessionId: string = '';
  @Prop @Watch('onExternalPinnedNotesChanged') externalPinnedNotes: NoteItem[] = [];
  @Prop @Watch('onPrefilledPromptChanged') prefilledPrompt: string = '';
  @Prop toolsEnabled: boolean = true;
  @Prop contextPanelOpen: boolean = false;

  onSessionSaved: (session: ChatSession) => void = () => {};
  onContextChange: (citations: ChatCitation[], pinned: NoteItem[], layerLabel: string, modelLabel: string) => void =
    () => {};
  onPinnedNotesChange: (pinned: NoteItem[]) => void = () => {};
  onToggleContextPanel: () => void = () => {};
  onOpenModelSettings: () => void = () => {};
  onCreateTodo: (dateKey: string, title: string) => void = () => {};
  onAddTagToNote: (identifier: string, tags: string) => void = () => {};
  onCreateLinkBetweenNotes: (sourceIdentifier: string, targetTitle: string) => void = () => {};
  onCategorizeNote: (identifier: string, category: string) => void = () => {};
  onCreateNewNote: (title: string, category: string, tag: string, content: string) => void = () => {};
  onOpenSearch: () => void = () => {};
  onSmartExtract: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp(ACTIVE_STORAGE_KEY) @Watch('onActiveProfileChanged') activeProfileId: string = '';

  @State messages: StoredMessage[] = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  @State streamingText: string = '';
  @State streamingReasoning: string = '';
  @State currentAgentMode: AgentLayer | 'auto' = 'auto';
  @State modelLabel: string = '';
  @State isModelReasoningType: boolean = false;
  @State lastCitations: ChatCitation[] = [];
  @State runningLayer: AgentLayer = 'L3';
  @State pinnedNotes: NoteItem[] = [];
  @State pickerOpen: boolean = false;
  @State pickerKeyword: string = '';
  @State toolStatus: string = '';
  @State cursorBlink: boolean = true;
  @State profiles: ModelProfile[] = [];
  @State modelMenuOpen: boolean = false;
  @State plusMenuOpen: boolean = false;
  @State selectedThinkingBudget: number = 16384;
  @State isThinkingEnabled: boolean = true;

  private orchestrator: AgentOrchestrator = new AgentOrchestrator();
  private sessionService: ChatSessionService = ChatSessionService.getInstance();
  private retriever: RagRetriever = new RagRetriever();
  private streamHandle: StreamHandle | null = null;
  private scroller: Scroller = new Scroller();
  private loadedSessionId: string = '';
  private servicesReady: boolean = false;
  private cancelled: boolean = false;
  private blinkTimer: number = -1;

  aboutToAppear(): void {
    this.pinnedNotes = this.externalPinnedNotes.slice();
    if (this.prefilledPrompt.length > 0) {
      this.inputText = this.prefilledPrompt;
    }
    this.initServices();
    this.blinkTimer = setInterval(() => {
      if (this.isLoading) {
        this.cursorBlink = !this.cursorBlink;
      }
    }, 500);
  }

  aboutToDisappear(): void {
    if (this.blinkTimer !== -1) {
      clearInterval(this.blinkTimer);
    }
  }

  private onExternalPinnedNotesChanged(): void {
    this.pinnedNotes = this.externalPinnedNotes.slice();
  }

  private onPrefilledPromptChanged(): void {
    if (this.prefilledPrompt.length > 0) {
      this.inputText = this.prefilledPrompt;
    }
  }

  private async initServices(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await this.sessionService.init(ctx);
      await ModelConfigService.getInstance().init(ctx);
    } catch (error) {
      console.error(`AI 服务自初始化跳过: ${JSON.stringify(error)}`);
    }
    this.servicesReady = true;
    await this.loadModelLabel();
    await this.loadSessionById(this.activeSessionId);
  }

  private onActiveProfileChanged(): void {
    this.loadModelLabel();
  }

  private onActiveSessionIdChanged(): void {
    if (this.activeSessionId === this.loadedSessionId) {
      return;
    }
    this.loadSessionById(this.activeSessionId);
  }

  private async loadModelLabel(): Promise<void> {
    try {
      this.profiles = await ModelConfigService.getInstance().loadProfiles();
      const profile = await ModelConfigService.getInstance().getActiveProfile();
      this.modelLabel = profile.apiKey.length === 0 ? `${profile.label} (未配密钥)` : profile.label;
      this.isModelReasoningType = profile.isReasoningModel ?? (profile.modelId.includes('reasoner') || profile.modelId.includes('r1'));
    } catch {
      this.modelLabel = '未配置模型';
      this.isModelReasoningType = false;
      this.profiles = [];
    }
    this.emitContext();
  }

  private async switchActiveProfile(profileId: string): Promise<void> {
    this.modelMenuOpen = false;
    try {
      await ModelConfigService.getInstance().setActiveProfileId(profileId);
      await this.loadModelLabel();
      promptAction.showToast({ message: `已切换至 ${this.modelLabel}` });
    } catch {
      promptAction.showToast({ message: '切换模型失败' });
    }
  }

  private emitContext(): void {
    const citations: ChatCitation[] = this.lastCitations;
    const pinned: NoteItem[] = this.pinnedNotes;
    const layer: string = this.layerTitle(this.runningLayer);
    const model: string = this.modelLabel;
    setTimeout(() => {
      this.onContextChange(citations, pinned, layer, model);
    }, 0);
  }

  private async loadSessionById(id: string): Promise<void> {
    if (this.isLoading) {
      return;
    }
    if (id.length === 0) {
      this.loadedSessionId = '';
      this.messages = [];
      this.lastCitations = [];
      this.streamingText = '';
      this.streamingReasoning = '';
      this.currentAgentMode = 'auto';
      this.emitContext();
      return;
    }
    try {
      const sessions: ChatSession[] = await this.sessionService.loadSessions();
      for (const s of sessions) {
        if (s && s.id === id) {
          this.loadedSessionId = id;
          const rawMessages: StoredMessage[] = (s.messages && Array.isArray(s.messages)) ? s.messages : [];
          const safeMessages: StoredMessage[] = [];
          for (let i = 0; i < rawMessages.length; i++) {
            const m: StoredMessage = rawMessages[i];
            if (!m || typeof m !== 'object') {
              continue;
            }
            const msgItem: StoredMessage = {
              id: m.id || `msg_${Date.now()}_${Math.floor(Math.random() * 10000)}`,
              role: m.role || 'assistant',
              text: (typeof m.text === 'string') ? m.text : '',
              reasoningContent: (typeof m.reasoningContent === 'string') ? m.reasoningContent : undefined,
              reasoningDurationMs: typeof m.reasoningDurationMs === 'number' ? m.reasoningDurationMs : undefined,
              reasoningFolded: m.reasoningFolded ?? true,
              formula: m.formula,
              bullets: Array.isArray(m.bullets) ? m.bullets : undefined,
              citations: Array.isArray(m.citations) ? m.citations : [],
              agentLayer: m.agentLayer,
              modelProfileId: m.modelProfileId,
              createdAt: typeof m.createdAt === 'number' ? m.createdAt : Date.now(),
              streaming: false,
              error: (typeof m.error === 'string') ? m.error : undefined,
              proposalStatus: m.proposalStatus
            };
            safeMessages.push(msgItem);
          }
          this.messages = safeMessages;
          this.currentAgentMode = s.agentMode || 'auto';
          this.lastCitations = [];
          this.streamingText = '';
          this.streamingReasoning = '';
          this.emitContext();
          this.scrollToBottom();
          return;
        }
      }
    } catch (error) {
      console.error(`会话装载失败: ${JSON.stringify(error)}`);
    }
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private layerTitle(layer: AgentLayer | undefined): string {
    if (layer === 'L1') {
      return '伴读模式';
    }
    if (layer === 'L2') {
      return '学情模式';
    }
    return '跨库模式';
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  // ------------------------------------------------------------------
  // 上下文与检索
  // ------------------------------------------------------------------

  private async retrieve(query: string): Promise<ChatCitation[]> {
    const docs: MarkdownDocument[] = [];
    for (const n of this.allNotes) {
      docs.push({
        id: n.id,
        title: n.title,
        fileName: `${n.title}.md`,
        filePath: '',
        content: n.contentDetail ?? '',
        updatedAt: 0
      });
    }
    const hits: RetrievalHit[] = this.retriever.search(docs, query, 6);
    const citations: ChatCitation[] = [];
    for (const h of hits) {
      citations.push({
        noteId: h.chunk.noteId,
        noteTitle: h.chunk.noteTitle,
        headingPath: h.chunk.headingPath,
        chunkText: h.chunk.text,
        score: h.score
      });
    }
    return citations;
  }

  private buildCurrentDocContext(): CurrentDocContext | undefined {
    if (this.currentNote === null || this.currentNote === undefined) {
      return undefined;
    }
    return {
      title: this.currentNote.title,
      content: this.currentNote.contentDetail ?? '',
      outline: ''
    };
  }

  private buildLearningContext(): string {
    let out: string = `【知识库统计】\n共 ${this.stats.noteCount} 篇笔记，${this.stats.linkCount} 条双向链接，${this.stats.tagCount} 个标签。\n\n`;
    out += `【最近笔记】\n`;
    for (const n of this.allNotes.slice(0, 15)) {
      out += `- ${n.title}（分类：${n.category.length > 0 ? n.category : '未分类'}，更新时间：${n.updateTime}）\n`;
    }
    out += `\n【待办任务】\n共 ${this.todos.length} 项：\n`;
    for (const t of this.todos.slice(0, 15)) {
      out += `- [${t.done ? 'x' : ' '}] ${t.title}（日期：${t.date}）\n`;
    }
    return out;
  }

  // ------------------------------------------------------------------
  // 问答调度
  // ------------------------------------------------------------------

  private async sendMessage(): Promise<void> {
    const q: string = this.inputText.trim();
    if (q.length === 0 || this.isLoading) {
      return;
    }

    const userMsg: StoredMessage = createMessage('user', q);
    this.messages = [...this.messages, userMsg];
    this.inputText = '';
    this.isLoading = true;
    this.streamingText = '';
    this.streamingReasoning = '';
    this.scrollToBottom();

    let layer: AgentLayer;
    if (this.currentAgentMode === 'auto') {
      layer = this.orchestrator.classify(q);
      if (layer === 'L1' && (this.currentNote === null || this.currentNote === undefined)) {
        layer = 'L3';
      }
    } else {
      layer = this.currentAgentMode;
    }
    this.runningLayer = layer;

    const docCtx: CurrentDocContext | undefined = layer === 'L1' ? this.buildCurrentDocContext() : undefined;
    const pinned: string[] = [];
    for (const n of this.pinnedNotes) {
      pinned.push(`【${n.title}】（所属工程/分类：${n.category.length > 0 ? n.category : '未分类'}）\n${n.contentDetail ?? ''}`);
    }

    let hits: ChatCitation[] = [];
    if (layer === 'L3') {
      this.toolStatus = '检索切片中…';
      hits = await this.retrieve(q);
      this.toolStatus = '';
      if (this.loadedSessionId !== this.activeSessionId) {
        this.isLoading = false;
        this.streamingText = '';
        this.streamingReasoning = '';
        return;
      }
    }
    this.lastCitations = hits;
    this.emitContext();

    const ctx: AgentRunContext = {
      query: q,
      history: this.messages.slice(0, -1),
      currentDoc: docCtx,
      pinnedNotes: pinned,
      retrievalHits: hits,
      learningContext: layer === 'L2' ? this.buildLearningContext() : undefined,
      tools: this.toolsEnabled ? AGENT_TOOLS : undefined,
      executor: this.buildExecutor(),
      confirm: (toolName: string, argsJson: string) => this.confirmTool(toolName, argsJson)
    };

    try {
      const activeProf = await ModelConfigService.getInstance().getActiveProfile();
      if (this.selectedThinkingBudget > 0) {
        activeProf.thinkingBudget = this.selectedThinkingBudget;
        activeProf.maxTokens = Math.max(activeProf.maxTokens, this.selectedThinkingBudget + 2048);
      } else {
        activeProf.thinkingBudget = 0;
      }
      await ModelConfigService.getInstance().upsertProfile(activeProf);
    } catch {
      // ignore
    }

    this.cancelled = false;
    try {
      await this.orchestrator.run(
        layer,
        ctx,
        (text: string, done: boolean, reasoningText?: string) => {
          this.streamingText = text;
          if (reasoningText !== undefined && reasoningText.length > 0) {
            this.streamingReasoning = reasoningText;
          }
          if (done) {
            this.isLoading = false;
            this.toolStatus = '';
            const aiMsg: StoredMessage = createMessage('assistant', text);
            aiMsg.agentLayer = layer;
            if (reasoningText !== undefined && reasoningText.length > 0) {
              aiMsg.reasoningContent = reasoningText;
              aiMsg.reasoningFolded = true;
            }
            if (hits.length > 0) {
              aiMsg.citations = hits;
            }
            this.messages = [...this.messages, aiMsg];
            this.streamingText = '';
            this.streamingReasoning = '';
            this.scrollToBottom();
            this.persistSession();
          }
        },
        (handle: StreamHandle) => {
          this.streamHandle = handle;
        }
      );
    } catch (err) {
      this.isLoading = false;
      this.streamingText = '';
      this.streamingReasoning = '';
      this.toolStatus = '';
      this.appendError(err instanceof Error ? err.message : '智能体请求失败');
    }
  }

  private buildExecutor(): WorkspaceToolExecutor {
    return new WorkspaceToolExecutor(
      (query: string, limit: number) => this.toolSearchNotes(query, limit),
      (category: string) => this.toolListNotes(category),
      (identifier: string) => this.toolReadNote(identifier),
      () => this.toolSummarizeVault(),
      (date: string, title: string) => this.toolCreateTodo(date, title),
      (identifier: string, tags: string) => this.toolAddTagToNote(identifier, tags),
      (sourceIdentifier: string, targetTitle: string, reason?: string) => this.toolCreateLink(sourceIdentifier, targetTitle, reason),
      (identifier: string, category: string) => this.toolCategorizeNote(identifier, category),
      (title: string, category: string, tag: string, content: string) => this.toolCreateNote(title, category, tag, content),
      (text: string) => {
        this.toolStatus = text;
      }
    );
  }

  private toolSearchNotes(query: string, limit: number): string {
    const docs: MarkdownDocument[] = [];
    for (const n of this.allNotes) {
      docs.push({
        id: n.id,
        title: n.title,
        fileName: `${n.title}.md`,
        filePath: '',
        content: n.contentDetail ?? '',
        updatedAt: 0
      });
    }
    const hits: RetrievalHit[] = this.retriever.search(docs, query, limit);
    if (hits.length === 0) {
      return `未检索到与「${query}」相关的笔记切片。`;
    }
    let out: string = '';
    for (const h of hits) {
      out += `〔${h.chunk.noteTitle} · ${h.chunk.headingPath.length > 0 ? h.chunk.headingPath : '正文'}〕\n`
        + `${h.chunk.text.slice(0, 800)}\n\n`;
    }
    return out;
  }

  private toolListNotes(category: string): string {
    const filtered: NoteItem[] = [];
    for (const n of this.allNotes) {
      if (category.length === 0 || n.category === category) {
        filtered.push(n);
      }
    }
    if (filtered.length === 0) {
      return category.length > 0 ? `项目「${category}」下无笔记。` : '资料库暂无笔记。';
    }
    let out: string = `知识库笔记清单（共 ${filtered.length} 篇）：\n`;
    for (const n of filtered.slice(0, 40)) {
      out += `- ${n.title} | 分类: ${n.category || '未分类'} | 标签: ${n.tag || '无'} | 更新于: ${n.updateTime}\n`;
    }
    return out;
  }

  private toolReadNote(identifier: string): string {
    const target: string = identifier.trim().toLowerCase();
    for (const n of this.allNotes) {
      if (n.id.toLowerCase() === target || n.title.toLowerCase() === target) {
        return `【${n.title}】\n所属分类: ${n.category || '未分类'}\n标签: ${n.tag || '无'}\n更新时间: ${n.updateTime}\n正文全文:\n${n.contentDetail || '（空文档）'}`;
      }
    }
    for (const n of this.allNotes) {
      if (n.title.toLowerCase().includes(target)) {
        return `【${n.title}】\n所属分类: ${n.category || '未分类'}\n标签: ${n.tag || '无'}\n更新时间: ${n.updateTime}\n正文全文:\n${n.contentDetail || '（空文档）'}`;
      }
    }
    return `未在知识库中找到名为「${identifier}」的笔记。`;
  }

  private toolSummarizeVault(): string {
    const catMap: Map<string, number> = new Map();
    const tagSet: Set<string> = new Set();
    for (const n of this.allNotes) {
      const cat: string = n.category.length > 0 ? n.category : '未分类';
      catMap.set(cat, (catMap.get(cat) ?? 0) + 1);
      if (n.tag.length > 0) {
        for (const t of n.tag.split(',')) {
          const trimT = t.trim();
          if (trimT.length > 0) {
            tagSet.add(trimT);
          }
        }
      }
    }
    let catList: string = '';
    catMap.forEach((cnt: number, cat: string) => {
      catList += `\n  - ${cat}: ${cnt} 篇`;
    });
    return `【FlowMind 知识库全景概览】\n- 笔记总数: ${this.allNotes.length} 篇\n- 分类统计:${catList}\n- 标签数量: ${tagSet.size} 个\n- 待办事项: ${this.todos.length} 项 (未完成 ${this.todos.filter((t: TodoItem) => !t.done).length} 项)`;
  }

  private toolCreateTodo(date: string, title: string): string {
    this.onCreateTodo(date, title);
    return `已成功创建待办：[${date}] ${title}`;
  }

  private toolAddTagToNote(identifier: string, tags: string): string {
    this.onAddTagToNote(identifier, tags);
    return `已为笔记「${identifier}」添加标签：${tags}`;
  }

  private toolCreateLink(sourceIdentifier: string, targetTitle: string, reason?: string): string {
    this.onCreateLinkBetweenNotes(sourceIdentifier, targetTitle);
    return `已在笔记「${sourceIdentifier}」中追加双向链接 [[${targetTitle}]]`;
  }

  private toolCategorizeNote(identifier: string, category: string): string {
    this.onCategorizeNote(identifier, category);
    return `已将笔记「${identifier}」归档入项目「${category}」`;
  }

  private toolCreateNote(title: string, category: string, tag: string, content: string): string {
    this.onCreateNewNote(title, category, tag, content);
    return `已成功新建笔记「${title}」`;
  }

  private async confirmTool(toolName: string, argsJson: string): Promise<boolean> {
    if (this.cancelled) {
      return false;
    }
    // 用户已全局授权自动同意：直接放行执行，无需弹窗打断
    return true;
  }

  private describeToolArgs(toolName: string, argsJson: string): string {
    if (toolName === 'create_todo') {
      try {
        const args: CreateTodoArgs = JSON.parse(argsJson) as CreateTodoArgs;
        return `智能体请求新建待办：「${args.title ?? ''}」，日期：${args.date ?? '今天'}`;
      } catch {
        return argsJson;
      }
    }
    if (toolName === 'add_tag_to_note') {
      try {
        const args: AddTagArgs = JSON.parse(argsJson) as AddTagArgs;
        return `智能体请求为笔记「${args.identifier ?? ''}」添加标签：${args.tags ?? ''}`;
      } catch {
        return argsJson;
      }
    }
    if (toolName === 'create_link') {
      try {
        const args: CreateLinkArgs = JSON.parse(argsJson) as CreateLinkArgs;
        return `智能体请求在笔记「${args.sourceIdentifier ?? ''}」中追加双向链接：[[${args.targetTitle ?? ''}]]`;
      } catch {
        return argsJson;
      }
    }
    if (toolName === 'categorize_note') {
      try {
        const args: CategorizeNoteArgs = JSON.parse(argsJson) as CategorizeNoteArgs;
        return `智能体请求将笔记「${args.identifier ?? ''}」归档至项目：「${args.category ?? ''}」`;
      } catch {
        return argsJson;
      }
    }
    if (toolName === 'create_note') {
      try {
        const args: CreateNoteArgs = JSON.parse(argsJson) as CreateNoteArgs;
        return `智能体请求新建知识笔记：「${args.title ?? ''}」，归属分类：${args.category ?? '未分类'}`;
      } catch {
        return argsJson;
      }
    }
    return argsJson;
  }

  private getTodayDateString(): string {
    const d: Date = new Date();
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
  }

  /** 从文本中解析 Codex / Claude Code 风格协同方案 */
  private extractProposal(text: string): ActionProposalData | null {
    if (!text || typeof text !== 'string') {
      return null;
    }
    if (!text.includes('action_proposal') && !text.includes('"actions"')) {
      return null;
    }
    try {
      let rawData: ActionProposalData | null = null;
      const fenceMatch = text.match(/```(?:action_proposal|json)?\s*(\{[\s\S]*?"actions"[\s\S]*?\})\s*```/);
      if (fenceMatch && fenceMatch[1]) {
        rawData = JSON.parse(fenceMatch[1]) as ActionProposalData;
      } else {
        const jsonStart = text.indexOf('{"summary"');
        if (jsonStart !== -1) {
          const jsonEnd = text.lastIndexOf('}');
          if (jsonEnd > jsonStart) {
            const raw = text.substring(jsonStart, jsonEnd + 1);
            rawData = JSON.parse(raw) as ActionProposalData;
          }
        }
      }
      if (!rawData || typeof rawData !== 'object' || !Array.isArray(rawData.actions)) {
        return null;
      }
      const safeSummary: string = typeof rawData.summary === 'string' ? rawData.summary : '';
      const safeActions: ProposedActionItem[] = [];
      for (let i = 0; i < rawData.actions.length; i++) {
        const item = rawData.actions[i];
        if (!item || typeof item !== 'object') {
          continue;
        }
        const safeTitle = typeof item.title === 'string' ? item.title : '';
        const safeDesc = typeof item.desc === 'string' ? item.desc : '';
        const safeTarget = typeof item.target === 'string' ? item.target : '';
        const safeValue = typeof item.value === 'string' ? item.value : '';
        const safeSource = typeof item.source === 'string' ? item.source : '';
        const safeDate = typeof item.date === 'string' ? item.date : '';
        const safeContent = typeof item.content === 'string' ? item.content : '';
        const safeType = typeof item.type === 'string' ? item.type : 'note';
        const safeId = typeof item.id === 'string' && item.id.length > 0 ? item.id : `act_${i}_${Date.now()}`;
        const actItem: ProposedActionItem = {
          id: safeId,
          type: safeType,
          title: safeTitle,
          desc: safeDesc,
          target: safeTarget,
          value: safeValue,
          source: safeSource,
          date: safeDate,
          content: safeContent
        };
        safeActions.push(actItem);
      }
      const resProposal: ActionProposalData = {
        summary: safeSummary,
        actions: safeActions
      };
      return resProposal;
    } catch {
      return null;
    }
  }

  /** 一键采纳并应用协同方案 */
  private applyProposal(msgId: string, proposal: ActionProposalData): void {
    if (!proposal || !proposal.actions || !Array.isArray(proposal.actions)) {
      return;
    }
    let count: number = 0;
    for (let i = 0; i < proposal.actions.length; i++) {
      const act = proposal.actions[i];
      if (!act) {
        continue;
      }
      const title = (typeof act.title === 'string') ? act.title : '';
      const desc = (typeof act.desc === 'string') ? act.desc : '';
      const target = (typeof act.target === 'string') ? act.target : '';
      const value = (typeof act.value === 'string') ? act.value : '';
      const source = (typeof act.source === 'string') ? act.source : '';
      const dateStr = (typeof act.date === 'string') ? act.date : '';
      const content = (typeof act.content === 'string') ? act.content : '';

      if (act.type === 'todo') {
        const d = dateStr.length > 0 ? dateStr : this.getTodayDateString();
        this.toolCreateTodo(d, title.length > 0 ? title : desc);
        count++;
      } else if (act.type === 'tag') {
        const iden = target.length > 0 ? target : title;
        const tags = value.length > 0 ? value : desc;
        if (iden.length > 0 && tags.length > 0) {
          this.toolAddTagToNote(iden, tags);
          count++;
        }
      } else if (act.type === 'link') {
        const src = source.length > 0 ? source : title;
        const tgt = target.length > 0 ? target : value;
        if (src.length > 0 && tgt.length > 0) {
          this.toolCreateLink(src, tgt, desc);
          count++;
        }
      } else if (act.type === 'category') {
        const iden = target.length > 0 ? target : title;
        const cat = value.length > 0 ? value : desc;
        if (iden.length > 0 && cat.length > 0) {
          this.toolCategorizeNote(iden, cat);
          count++;
        }
      } else if (act.type === 'note') {
        const noteContent = content.length > 0 ? content : (desc.length > 0 ? desc : `# ${title}\n\n`);
        const cat = target.length > 0 ? target : '未分类';
        const tag = value.length > 0 ? value : '';
        if (title.length > 0) {
          this.toolCreateNote(title, cat, tag, noteContent);
          count++;
        }
      }
    }
    const next: StoredMessage[] = [];
    for (const m of this.messages) {
      if (m.id === msgId) {
        m.proposalStatus = 'accepted';
      }
      next.push(m);
    }
    this.messages = next;
    this.persistSession();
    promptAction.showToast({ message: `✓ 已全部接受并应用 ${count} 项知识库变更！` });
  }

  /** 忽略协同方案 */
  private dismissProposal(msgId: string): void {
    const next: StoredMessage[] = [];
    for (const m of this.messages) {
      if (m.id === msgId) {
        m.proposalStatus = 'dismissed';
      }
      next.push(m);
    }
    this.messages = next;
    this.persistSession();
    promptAction.showToast({ message: '已忽略此协同建议' });
  }

  private appendError(message: string): void {
    const errMsg: StoredMessage = createMessage('assistant', '');
    errMsg.error = message;
    errMsg.agentLayer = this.runningLayer;
    this.messages = [...this.messages, errMsg];
  }

  private cancelStream(): void {
    this.cancelled = true;
    if (this.streamHandle !== null) {
      this.streamHandle.abort();
      this.streamHandle = null;
    }
    this.isLoading = false;
    this.toolStatus = '';
    const partial: string = this.streamingText;
    const partialReasoning: string = this.streamingReasoning;
    this.streamingText = '';
    this.streamingReasoning = '';
    if (partial.length > 0 || partialReasoning.length > 0) {
      const aiMsg: StoredMessage = createMessage('assistant', partial);
      aiMsg.agentLayer = this.runningLayer;
      if (partialReasoning.length > 0) {
        aiMsg.reasoningContent = partialReasoning;
        aiMsg.reasoningFolded = false;
      }
      this.messages = [...this.messages, aiMsg];
      this.persistSession();
    }
  }

  private async persistSession(): Promise<void> {
    if (!this.servicesReady) {
      return;
    }
    try {
      if (this.activeSessionId.length === 0) {
        const session: ChatSession = createEmptySession();
        session.messages = this.messages;
        session.agentMode = this.currentAgentMode;
        if (this.messages.length > 0 && this.messages[0].role === 'user') {
          session.title = this.messages[0].text.slice(0, 30);
        }
        await this.sessionService.saveSession(session);
        this.loadedSessionId = session.id;
        this.onSessionSaved(session);
      } else {
        const sessions: ChatSession[] = await this.sessionService.loadSessions();
        for (const s of sessions) {
          if (s.id === this.activeSessionId) {
            s.messages = this.messages;
            s.agentMode = this.currentAgentMode;
            s.updatedAt = Date.now();
            if (s.title.length === 0 && this.messages.length > 0 && this.messages[0].role === 'user') {
              s.title = this.messages[0].text.slice(0, 30);
            }
            await this.sessionService.saveSession(s);
            this.onSessionSaved(s);
            return;
          }
        }
      }
    } catch (error) {
      console.error(`会话保存失败: ${JSON.stringify(error)}`);
    }
  }

  private toggleReasoningFold(msgId: string): void {
    const next: StoredMessage[] = [];
    for (const m of this.messages) {
      if (m.id === msgId) {
        m.reasoningFolded = !(m.reasoningFolded ?? true);
      }
      next.push(m);
    }
    this.messages = next;
  }

  private togglePin(note: NoteItem): void {
    const next: NoteItem[] = [];
    let removed: boolean = false;
    for (const n of this.pinnedNotes) {
      if (n.id === note.id) {
        removed = true;
      } else {
        next.push(n);
      }
    }
    if (!removed) {
      next.push(note);
    }
    this.pinnedNotes = next;
    this.emitContext();
    this.onPinnedNotesChange(this.pinnedNotes);
  }

  private pickerCandidates(): NoteItem[] {
    const keyword: string = this.pickerKeyword.trim().toLowerCase();
    const pickedIds: Set<string> = new Set(this.pinnedNotes.map((n: NoteItem) => n.id));
    const result: NoteItem[] = [];
    for (const n of this.allNotes) {
      if (pickedIds.has(n.id)) {
        continue;
      }
      if (keyword.length > 0) {
        const hit: boolean = n.title.toLowerCase().includes(keyword)
          || n.tag.toLowerCase().includes(keyword)
          || n.category.toLowerCase().includes(keyword);
        if (!hit) {
          continue;
        }
      }
      result.push(n);
      if (result.length >= 30) {
        break;
      }
    }
    return result;
  }

  private copyToClipboard(text: string): void {
    if (text.length === 0) {
      return;
    }
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData).then(() => {
        promptAction.showToast({ message: '已复制回答到剪贴板' });
      }).catch(() => {
        promptAction.showToast({ message: '复制失败' });
      });
    } catch {
      promptAction.showToast({ message: '剪贴板调用失败' });
    }
  }

  private async regenerateLastResponse(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    try {
      const active = await ModelConfigService.getInstance().getActiveProfile();
      if (active.modelId === 'deepseek-v4') {
        active.modelId = 'deepseek-v4-pro';
        await ModelConfigService.getInstance().upsertProfile(active);
        await this.loadModelLabel();
      }
    } catch {
      // ignore
    }

    let lastUserQuery: string = '';
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].role === 'user') {
        lastUserQuery = this.messages[i].text;
        break;
      }
    }
    if (lastUserQuery.length > 0) {
      this.inputText = lastUserQuery;
      this.sendMessage();
    } else {
      promptAction.showToast({ message: '暂无可重新生成的提问' });
    }
  }

  private async switchModelAndRetry(targetModelId: string): Promise<void> {
    if (this.isLoading) {
      return;
    }
    try {
      const active = await ModelConfigService.getInstance().getActiveProfile();
      active.modelId = targetModelId;
      await ModelConfigService.getInstance().upsertProfile(active);
      await this.loadModelLabel();
      promptAction.showToast({ message: `已自动切换为 ${targetModelId} 并发起请求` });
    } catch {
      // ignore
    }
    this.regenerateLastResponse();
  }

  private startNewChat(): void {
    if (this.isLoading) {
      this.cancelStream();
    }
    this.loadedSessionId = '';
    this.messages = [];
    this.lastCitations = [];
    this.streamingText = '';
    this.streamingReasoning = '';
    this.pinnedNotes = [];
    this.emitContext();
    promptAction.showToast({ message: '已开启新对话' });
  }

  // ------------------------------------------------------------------
  // UI 渲染
  // ------------------------------------------------------------------

  @Builder
  reasoningCard(msg: StoredMessage) {
    if (msg.reasoningContent !== undefined && msg.reasoningContent.length > 0) {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('🧠')
            .fontSize(TypographyTokens.TINY)
          Text('深度思考')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkMuted)
          Blank()
          Text((msg.reasoningFolded ?? true) ? '展开 ›' : '收起 ▼')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().accent)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor(this.palette().surfaceSubtle)
        .onClick(() => this.toggleReasoningFold(msg.id))

        if (!(msg.reasoningFolded ?? true)) {
          Column() {
            Text(msg.reasoningContent)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
              .fontFamily('monospace')
              .width('100%')
              .lineHeight(19)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)')
          .border({ width: { left: 2 }, color: { left: this.palette().accent } })
        }
      }
      .width('100%')
      .margin({ bottom: 6 })
    }
  }

  @Builder
  messageBubble(msg: StoredMessage) {
    if (msg.role === 'user') {
      Row() {
        Blank()
        Text(msg.text ?? '')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(14)
          .backgroundColor(this.palette().accent)
          .constraintSize({ maxWidth: '80%' })
      }
      .width('100%')
    } else {
      Column({ space: 6 }) {
        // 智能体层级标签
        Row({ space: 6 }) {
          Text(this.layerTitle(msg.agentLayer))
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().accent)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(6)
            .backgroundColor(this.palette().accentSoft)

          if (msg.streaming === true) {
            Text('正在组织回答…')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
        }

        // 思考链展示卡片
        this.reasoningCard(msg)

        if (msg.error !== undefined && msg.error !== null && msg.error.length > 0) {
          Text(`⚠ ${msg.error}`)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor('#EF4444')
            .width('100%')
        }

        if (msg.text && msg.text.length > 0) {
          this.renderMarkdownText(msg.text, false)
        }

        // 墨语智能协同方案卡 (Codex / Claude Code 交互式协同)
        this.proposalCard(msg)

        // 引用来源芯片
        if (msg.citations !== undefined && msg.citations !== null && msg.citations.length > 0) {
          Column({ space: 4 }) {
            Text('引用溯源')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 4, unit: 1 } } }) {
              ForEach(msg.citations, (c: ChatCitation) => {
                Text(`〔${c.noteTitle} · ${c.headingPath || '正文'}〕`)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().accent)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(6)
                  .backgroundColor(this.palette().accentSoft)
              }, (c: ChatCitation) => `${c.noteId}-${c.headingPath}`)
            }
          }
          .width('100%')
          .margin({ top: 4 })
        }

        // 操作栏（一键复制 / 重新生成 / 错误重试）
        if (msg.streaming !== true) {
          Row({ space: 8 }) {
            if (msg.text && msg.text.length > 0) {
              Row({ space: 4 }) {
                Text('⎘')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
                Text('复制')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.palette().surfaceSubtle)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.copyToClipboard(msg.text ?? ''))
            }

            Row({ space: 4 }) {
              Text('↻')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
              Text('重新生成')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
            }
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor(this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.regenerateLastResponse())

            if (msg.error !== undefined && msg.error !== null && msg.error.length > 0) {
              if (msg.error.includes('deepseek-v4-pro') || msg.error.includes('deepseek-flash') || msg.error.includes('deepseek-v4')) {
                Row({ space: 4 }) {
                  Text('⚡')
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().accent)
                  Text('切换为 deepseek-v4-pro 重试')
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().accent)
                }
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(6)
                .backgroundColor(this.palette().accentSoft)
                .hoverEffect(HoverEffect.Highlight)
                .onClick(() => this.switchModelAndRetry('deepseek-v4-pro'))
              }

              Row({ space: 4 }) {
                Text('⚡')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor('#EF4444')
                Text('重试请求')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor('#EF4444')
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor('rgba(239, 68, 68, 0.08)')
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.regenerateLastResponse())
            }
          }
          .margin({ top: 4 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 4, bottom: 4 })
    }
  }

  /** Codex / Claude Code 交互式协同方案卡片 */
  @Builder
  proposalCard(msg: StoredMessage) {
    if (msg.text && typeof msg.text === 'string' && this.extractProposal(msg.text) !== null) {
      this.renderProposalCardContent(msg, this.extractProposal(msg.text)!)
    }
  }

  @Builder
  renderProposalCardContent(msg: StoredMessage, proposal: ActionProposalData) {
    Column({ space: 10 }) {
      // 顶栏：标题与状态标签
      Row() {
        Row({ space: 6 }) {
          Text('✦')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
          Text('墨语智能协同方案')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Text('CLAUDE CODE 协同模式')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(4)
            .backgroundColor(this.palette().accentSoft)
        }
        .layoutWeight(1)

        Blank()

        if (msg.proposalStatus === 'accepted') {
          Row({ space: 4 }) {
            Text('✓')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('已全部采纳并写入')
              .fontSize(TypographyTokens.TINY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(6)
          .backgroundColor('#059669')
        } else if (msg.proposalStatus === 'dismissed') {
          Text('✕ 已忽略')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(6)
            .backgroundColor(this.palette().surfaceSubtle)
        } else {
          Row({ space: 4 }) {
            Text('⏳')
              .fontSize(11)
            Text('待用户确认')
              .fontSize(TypographyTokens.TINY)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accent)
          }
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(6)
          .backgroundColor(this.palette().accentSoft)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 方案概述
      if (proposal.summary && proposal.summary.length > 0) {
        Text(proposal.summary)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkSecondary)
          .width('100%')
      }

      // 方案执行清单
      Column({ space: 6 }) {
        ForEach(proposal.actions || [], (act: ProposedActionItem, idx: number) => {
          Row({ space: 8 }) {
            // 类型徽标
            Row() {
              Text(act.type === 'todo' ? '📅 待办' : (act.type === 'tag' ? '🏷 标签' : (act.type === 'link' ? '🔗 双链' : (act.type === 'category' ? '📁 归档' : '📝 新建'))))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(act.type === 'todo' ? '#059669' : (act.type === 'tag' ? '#D97706' : (act.type === 'link' ? '#6366F1' : this.palette().accent)))
            }
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(act.type === 'todo' ? 'rgba(5,150,105,0.1)' : (act.type === 'tag' ? 'rgba(217,119,6,0.1)' : (act.type === 'link' ? 'rgba(99,102,241,0.1)' : this.palette().accentSoft)))

            Column({ space: 2 }) {
              Text((act.title && act.title.length > 0) ? act.title : (act.target && act.target.length > 0 ? `${act.target}: ${act.value ?? ''}` : (act.desc ?? '')))
                .fontSize(TypographyTokens.CAPTION)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().inkPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              if (act.desc && act.desc.length > 0) {
                Text(act.desc)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(8)
          .backgroundColor(this.palette().surface)
          .border({ width: 1, color: this.palette().borderSubtle })
        }, (act: ProposedActionItem, idx: number) => `act-${idx}-${act.id || act.type}`)
      }
      .width('100%')

      // 操作交互栏：接受并应用 / 拒绝
      if (msg.proposalStatus !== 'accepted' && msg.proposalStatus !== 'dismissed') {
        Row({ space: 10 }) {
          Row({ space: 6 }) {
            Text('✓')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('接受并执行变更 (Accept & Apply)')
              .fontSize(TypographyTokens.CAPTION)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor(this.palette().accent)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.applyProposal(msg.id, proposal);
          })

          Row({ space: 4 }) {
            Text('✕')
              .fontSize(12)
              .fontColor(this.palette().inkMuted)
            Text('忽略此方案')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkMuted)
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor(this.palette().surface)
          .border({ width: 1, color: this.palette().borderSubtle })
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.dismissProposal(msg.id);
          })
        }
        .width('100%')
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor(this.palette().surfaceSubtle)
    .border({ width: 1, color: this.palette().borderSubtle })
    .shadow({ radius: 8, color: this.isDarkMode ? 'rgba(0,0,0,0.35)' : 'rgba(0,0,0,0.03)', offsetY: 2 })
    .margin({ top: 8, bottom: 4 })
  }

  @Builder
  renderMarkdownText(text: string, isStreamingText: boolean) {
    Column({ space: 4 }) {
      ForEach(this.parseBlocks(text), (block: string, idx: number) => {
        this.renderBlock(block)
      }, (block: string, idx: number) => `blk-${idx}-${block.length}`)

      if (isStreamingText) {
        Text(this.cursorBlink ? '▌' : ' ')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().accent)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private parseBlocks(text: string): string[] {
    if (!text || typeof text !== 'string') {
      return [];
    }
    const lines: string[] = text.split('\n');
    const blocks: string[] = [];
    let fenced: boolean = false;
    let buffer: string[] = [];
    for (const line of lines) {
      if (line.trim().startsWith('```')) {
        if (fenced) {
          buffer.push(line);
          blocks.push(buffer.join('\n'));
          buffer = [];
          fenced = false;
        } else {
          fenced = true;
          buffer.push(line);
        }
        continue;
      }
      if (fenced) {
        buffer.push(line);
      } else {
        blocks.push(line);
      }
    }
    if (buffer.length > 0) {
      blocks.push(buffer.join('\n'));
    }
    return blocks;
  }

  private isFormulaBlock(block: string): boolean {
    const trimmed: string = block.trim();
    return trimmed.startsWith('```math') || trimmed.startsWith('$$\n')
      || (trimmed.startsWith('$$') && trimmed.endsWith('$$') && trimmed.length > 4);
  }

  private stripFence(block: string): string {
    const lines: string[] = block.split('\n');
    const inner: string[] = [];
    for (const line of lines) {
      const t: string = line.trim();
      if (t.startsWith('```') || t === '$$') {
        continue;
      }
      inner.push(line);
    }
    let joined: string = inner.join('\n').trim();
    if (joined.startsWith('$$')) {
      joined = joined.slice(2);
    }
    if (joined.endsWith('$$')) {
      joined = joined.slice(0, -2);
    }
    return joined.trim();
  }

  @Builder
  renderBlock(block: string) {
    if (block.startsWith('```')) {
      if (block.startsWith('```action_proposal')) {
        // 结构化协同方案由下方的交互式卡片承载呈现，此处展示提示标签
        Row({ space: 6 }) {
          Text('✦')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
          Text('已生成结构化协同方案，请在下方【墨语智能协同方案卡】中核对并一键应用')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().accent)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(8)
        .backgroundColor(this.palette().accentSoft)
        .border({ width: 1, color: this.palette().borderSubtle })
        .margin({ top: 4, bottom: 4 })
      } else if (this.isFormulaBlock(block)) {
        Column() {
          Text(this.stripFence(block))
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().accent)
            .fontFamily('monospace')
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
        .padding({ top: 12, bottom: 12, left: 16, right: 16 })
        .borderRadius(10)
        .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)')
        .margin({ top: 4, bottom: 4 })
      } else {
        Column() {
          Text(this.stripFence(block))
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkPrimary)
            .fontFamily('monospace')
            .width('100%')
        }
        .width('100%')
        .padding(12)
        .borderRadius(8)
        .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)')
        .margin({ top: 4, bottom: 4 })
      }
    } else if (block.startsWith('# ')) {
      Text(block.slice(2))
        .fontSize(TypographyTokens.TITLE_SUB)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().inkPrimary)
        .width('100%')
        .margin({ top: 8, bottom: 2 })
    } else if (block.startsWith('## ')) {
      Text(block.slice(3))
        .fontSize(TypographyTokens.BODY_LARGE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().inkPrimary)
        .width('100%')
        .margin({ top: 6, bottom: 2 })
    } else if (block.startsWith('### ')) {
      Text(block.slice(4))
        .fontSize(TypographyTokens.BODY_REGULAR)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().inkSecondary)
        .width('100%')
    } else if (block.startsWith('- ') || block.startsWith('• ') || block.startsWith('* ')) {
      Row({ space: 8 }) {
        Text('•').fontColor(this.palette().accent).fontSize(TypographyTokens.BODY_REGULAR)
        Text(block.slice(2))
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkSecondary)
          .lineHeight(22)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    } else if (block.trim().length === 0) {
      Blank().height(4)
    } else {
      Text(block)
        .fontSize(TypographyTokens.BODY_REGULAR)
        .fontColor(this.palette().inkSecondary)
        .lineHeight(22)
        .width('100%')
    }
  }

  @Builder
  quickPromptCard(qp: QuickPrompt) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(qp.badge)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().accent)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.palette().accentSoft)
        Text(qp.title)
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
      }
      Text(qp.desc)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .maxLines(2)
    }
    .width(260)
    .padding(14)
    .borderRadius(12)
    .backgroundColor(this.palette().surfaceSubtle)
    .border({ width: 1, color: this.palette().borderSubtle })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.inputText = qp.query;
      this.sendMessage();
    })
  }

  @Builder
  modelSelectMenu() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text('已配置模型')
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkMuted)
          .layoutWeight(1)
        Text('✕')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width(20).height(20)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.modelMenuOpen = false;
          })
      }
      .width('100%')
      .padding({ bottom: 4 })

      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.profiles, (p: ModelProfile) => {
            Row({ space: 8 }) {
              Circle({ width: 6, height: 6 })
                .fill(p.id === this.activeProfileId ? this.palette().accent : '#9CA3AF')

              Column({ space: 1 }) {
                Row({ space: 4 }) {
                  Text(p.label)
                    .fontSize(TypographyTokens.TINY)
                    .fontWeight(p.id === this.activeProfileId ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.palette().inkPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (p.isReasoningModel) {
                    Text('🧠')
                      .fontSize(TypographyTokens.TINY)
                  }
                }
                Text(p.modelId)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
                  .maxLines(1)
                  .fontFamily('monospace')
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (p.id === this.activeProfileId) {
                Text('✓')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().accent)
                  .fontWeight(FontWeight.Bold)
              }
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(8)
            .backgroundColor(p.id === this.activeProfileId ? this.palette().accentSoft : Color.Transparent)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.switchActiveProfile(p.id);
            })
          }, (p: ModelProfile) => p.id)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 240 })
      .scrollBar(BarState.Auto)

      Divider().color(this.palette().borderSubtle).margin({ top: 4, bottom: 4 })

      Row({ space: 6 }) {
        Text('⚙')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().accent)
        Text('管理更多模型配置…')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().accent)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(6)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.modelMenuOpen = false;
        this.onOpenModelSettings();
      })
    }
    .width(280)
    .padding(10)
    .borderRadius(12)
    .backgroundColor(this.palette().surface)
    .border({ width: 1, color: this.palette().border })
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.18)' })
    .margin({ top: 54, right: 80 })
  }

  private getBudgetShortLabel(budget: number): string {
    switch (budget) {
      case 4096:
        return 'Low';
      case 16384:
        return 'Medium';
      case 32768:
        return 'High';
      case 65536:
        return 'Max';
      default:
        if (budget <= 8192) {
          return 'Low';
        } else if (budget <= 24576) {
          return 'Medium';
        } else if (budget <= 49152) {
          return 'High';
        } else {
          return 'Max';
        }
    }
  }

  private getBudgetPreset(budget: number): ThinkingBudgetPreset {
    const label: string = this.getBudgetShortLabel(budget);
    const found: ThinkingBudgetPreset | undefined = THINKING_BUDGETS.find((b: ThinkingBudgetPreset) => b.label === label);
    return found ?? THINKING_BUDGETS[1];
  }

  private getBudgetStep(budget: number): number {
    switch (budget) {
      case 4096:
        return 0;
      case 16384:
        return 1;
      case 32768:
        return 2;
      case 65536:
        return 3;
      default:
        if (budget <= 8192) {
          return 0;
        } else if (budget <= 24576) {
          return 1;
        } else if (budget <= 49152) {
          return 2;
        } else {
          return 3;
        }
    }
  }

  private setThinkingBudgetByStep(step: number, showToast: boolean = false): void {
    const list: number[] = [4096, 16384, 32768, 65536];
    const clampedStep: number = Math.max(0, Math.min(3, Math.round(step)));
    const newBudget: number = list[clampedStep];
    if (this.selectedThinkingBudget !== newBudget) {
      this.selectedThinkingBudget = newBudget;
      if (showToast) {
        const item: ThinkingBudgetPreset = this.getBudgetPreset(this.selectedThinkingBudget);
        promptAction.showToast({ message: `思考深度: ${item.label}` });
      }
    }
  }

  private getKnobOffset(step: number): number {
    switch (step) {
      case 0:
        return 2;
      case 1:
        return 21;
      case 2:
        return 40;
      case 3:
      default:
        return 58;
    }
  }

  private getFillWidth(step: number): number {
    switch (step) {
      case 0:
        return 18;
      case 1:
        return 37;
      case 2:
        return 56;
      case 3:
      default:
        return 76;
    }
  }

  private async importExternalFile(): Promise<void> {
    this.plusMenuOpen = false;
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      const note = await DocumentImportService.getInstance().pickAndImport(ctx, 'AI外部参考');
      if (note !== null) {
        if (!this.pinnedNotes.some((n: NoteItem) => n.id === note.id)) {
          this.pinnedNotes = [...this.pinnedNotes, note];
          this.emitContext();
          this.onPinnedNotesChange(this.pinnedNotes);
          promptAction.showToast({ message: `已导入外部文件并挂载：${note.title}` });
        } else {
          promptAction.showToast({ message: '该文件已在参考列表中' });
        }
      }
    } catch (err) {
      console.error(`导入外部文件异常: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '导入外部文件取消或失败' });
    }
  }

  private rewindLastMessage(): void {
    if (this.messages.length === 0) {
      promptAction.showToast({ message: '暂无消息可撤销' });
      return;
    }
    if (this.messages[this.messages.length - 1].role === 'assistant') {
      this.messages.pop();
    }
    if (this.messages.length > 0 && this.messages[this.messages.length - 1].role === 'user') {
      this.messages.pop();
    }
    this.messages = [...this.messages];
    promptAction.showToast({ message: '已撤销上一轮对话' });
  }

  private cycleThinkingBudget(): void {
    const list: number[] = [4096, 16384, 32768, 65536];
    let currentIndex: number = list.indexOf(this.selectedThinkingBudget);
    if (currentIndex === -1) {
      currentIndex = 1;
    }
    const nextIndex: number = (currentIndex + 1) % list.length;
    this.selectedThinkingBudget = list[nextIndex];
    const item: ThinkingBudgetPreset = this.getBudgetPreset(this.selectedThinkingBudget);
    promptAction.showToast({ message: `推演深度: ${item.label}` });
  }

  /** 极简操作舱面板 (中文极简，区分库内与外部文件，支持思考深度胶囊滑块) */
  @Builder
  plusActionMenu() {
    Column({ space: 2 }) {
      // 滚动操作列表
      Scroll() {
        Column({ space: 2 }) {
          // ---- 区块一：资料与识别 ----
          Text('资料与识别')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkMuted)
            .padding({ left: 10, top: 4, bottom: 2 })
            .width('100%')

          // 1. 智能识别 (拍照/选图并进行 OCR 与多模态提取)
          Row() {
            Text('智能识别')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkPrimary)
          }
          .width('100%')
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(6)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.plusMenuOpen = false;
            this.onSmartExtract();
          })

          // 2. 引用库内资料 (程序内已有笔记与文档)
          Row() {
            Text('引用库内资料')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkPrimary)
            Blank()
            if (this.pinnedNotes.length > 0) {
              Text(`已引 ${this.pinnedNotes.length} 篇`)
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().accent)
            }
          }
          .width('100%')
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(6)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.plusMenuOpen = false;
            this.onToggleContextPanel();
          })

          // 3. 导入外部文件 (调起系统选择器，导入程序外的 PDF/TXT/MD 等)
          Row() {
            Text('导入外部文件')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkPrimary)
          }
          .width('100%')
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(6)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.importExternalFile();
          })

          // 4. 清空对话
          Row() {
            Text('清空对话')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkPrimary)
          }
          .width('100%')
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(6)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.messages = [];
            this.streamingText = '';
            this.streamingReasoning = '';
            this.plusMenuOpen = false;
            promptAction.showToast({ message: '已清空对话' });
          })

          // 5. 撤销上一轮
          Row() {
            Text('撤销上一轮')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkPrimary)
          }
          .width('100%')
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(6)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.plusMenuOpen = false;
            this.rewindLastMessage();
          })

          // 分割线
          Divider()
            .color(this.palette().borderSubtle)
            .margin({ top: 4, bottom: 4 })

          // ---- 区块二：模型设置 ----
          Text('模型设置')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkMuted)
            .padding({ left: 10, top: 4, bottom: 2 })
            .width('100%')

          // 切换模型
          Row() {
            Text('切换模型')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkPrimary)
            Blank()
            Text(this.modelLabel.length > 0 ? this.modelLabel : '默认推荐')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 120 })
          }
          .width('100%')
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(6)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.plusMenuOpen = false;
            this.modelMenuOpen = true;
          })

          // 思考深度 (Low / Medium / High / Max) 胶囊滑块
          Row() {
            Text(`思考深度 (${this.getBudgetShortLabel(this.selectedThinkingBudget)})`)
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.isThinkingEnabled ? this.palette().inkPrimary : this.palette().inkMuted)

            Blank()

            // 紧凑胶囊滑块 (76vp x 18vp，底轨 + 动态蓝色填充条 + 4个刻度点 + 实体滑动圆标)
            Stack({ alignContent: Alignment.Start }) {
              // 底轨
              Row()
                .width('100%')
                .height('100%')
                .borderRadius(9)
                .backgroundColor(this.isDarkMode ? '#334155' : '#E2E8F0')

              // 动态蓝色填充条 (右拖长度直接反映思考深度)
              Row()
                .width(this.isThinkingEnabled ? this.getFillWidth(this.getBudgetStep(this.selectedThinkingBudget)) : 0)
                .height('100%')
                .borderRadius(9)
                .backgroundColor(this.palette().accent)
                .animation({ curve: curves.springMotion(0.24, 0.72) })

              // 四个刻度点
              Row() {
                Circle({ width: 3, height: 3 })
                  .fill(this.getBudgetStep(this.selectedThinkingBudget) >= 0 ? Color.White : '#64748B')
                  .opacity(0.65)
                Blank()
                Circle({ width: 3, height: 3 })
                  .fill(this.getBudgetStep(this.selectedThinkingBudget) >= 1 ? Color.White : '#64748B')
                  .opacity(0.65)
                Blank()
                Circle({ width: 3, height: 3 })
                  .fill(this.getBudgetStep(this.selectedThinkingBudget) >= 2 ? Color.White : '#64748B')
                  .opacity(0.65)
                Blank()
                Circle({ width: 3, height: 3 })
                  .fill(this.getBudgetStep(this.selectedThinkingBudget) >= 3 ? Color.White : '#64748B')
                  .opacity(0.65)
              }
              .width('100%')
              .height('100%')
              .padding({ left: 8, right: 8 })

              // 实体滑动圆标
              Row()
                .width(16)
                .height(16)
                .borderRadius(8)
                .backgroundColor(this.isDarkMode ? '#E2E8F0' : '#2D3748')
                .shadow({ radius: 4, color: 'rgba(0,0,0,0.25)', offsetY: 1 })
                .margin({ left: this.getKnobOffset(this.getBudgetStep(this.selectedThinkingBudget)) })
                .animation({ curve: curves.springMotion(0.24, 0.72) })
            }
            .width(76)
            .height(18)
            .onTouch((event: TouchEvent) => {
              if (!this.isThinkingEnabled) {
                return;
              }
              const touch = event.touches[0];
              if (!touch) {
                return;
              }
              const ratio: number = Math.max(0, Math.min(1, touch.x / 76));
              const step: number = Math.min(3, Math.floor(ratio * 4));
              animateTo({ curve: curves.springMotion(0.24, 0.72) }, () => {
                this.setThinkingBudgetByStep(step, false);
              });
            })
            .onClick(() => {
              if (!this.isThinkingEnabled) {
                return;
              }
              const nextStep: number = (this.getBudgetStep(this.selectedThinkingBudget) + 1) % 4;
              animateTo({ curve: curves.springMotion(0.24, 0.72) }, () => {
                this.setThinkingBudgetByStep(nextStep, false);
              });
            })
          }
          .width('100%')
          .height(32)
          .padding({ left: 10, right: 10 })

          // 深度思考 (开关)
          Row() {
            Text('深度思考')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkPrimary)

            Blank()

            Toggle({ type: ToggleType.Switch, isOn: this.isThinkingEnabled })
              .selectedColor(this.palette().accent)
              .onChange((isOn: boolean) => {
                this.isThinkingEnabled = isOn;
                if (!isOn) {
                  this.selectedThinkingBudget = 0;
                } else {
                  this.selectedThinkingBudget = 16384;
                }
              })
          }
          .width('100%')
          .height(32)
          .padding({ left: 10, right: 10 })
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 340 })
      .scrollBar(BarState.Auto)
    }
    .width(280)
    .padding(6)
    .borderRadius(10)
    .backgroundColor(this.palette().surface)
    .border({ width: 1, color: this.palette().border })
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.18)' })
    .alignSelf(ItemAlign.Start)
    .margin({ bottom: 8, left: 16 })
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.92, y: 0.92, centerX: '24vp', centerY: '100%' }))
        .combine(TransitionEffect.translate({ y: 12 }))
        .animation({ curve: curves.springMotion(0.28, 0.72) })
    )
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        // 1. 顶栏 (Header)
        Row({ space: 10 }) {
          Row({ space: 6 }) {
            Text('✦')
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontColor(this.palette().accent)
            Text('AI 墨客')
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)
          }

          // 分段滑块模式切换 (Segmented Tabs)
          Row({ space: 4 }) {
            ForEach(MODE_TABS, (item: AgentModeTabItem) => {
              Text(item.title)
                .fontSize(TypographyTokens.TINY)
                .fontWeight(this.currentAgentMode === item.mode ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.currentAgentMode === item.mode ? this.palette().accent : this.palette().inkMuted)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(8)
                .backgroundColor(this.currentAgentMode === item.mode ? this.palette().accentSoft : Color.Transparent)
                .animation({ duration: 180, curve: Curve.EaseInOut })
                .onClick(() => {
                  this.currentAgentMode = item.mode as AgentLayer | 'auto';
                })
            }, (item: AgentModeTabItem) => item.mode)
          }
          .padding(3)
          .borderRadius(10)
          .backgroundColor(this.palette().surfaceSubtle)

          // 新对话快捷按键
          Row({ space: 4 }) {
            Text('+')
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontColor(this.palette().accent)
            Text('新对话')
              .fontSize(TypographyTokens.TINY)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkPrimary)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(8)
          .backgroundColor(this.palette().surfaceSubtle)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.startNewChat())

          Blank()

          // 模型切换快捷芯片 (带下拉箭头)
          Row({ space: 6 }) {
            Circle({ width: 8, height: 8 })
              .fill(this.modelLabel.includes('未配') ? '#F59E0B' : '#22C55E')
            Text(this.modelLabel)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.isModelReasoningType) {
              Text(`✦ ${this.getBudgetShortLabel(this.selectedThinkingBudget)}`)
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().accent)
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(4)
                .backgroundColor(this.palette().accentSoft)
            }
            Text(this.modelMenuOpen ? '▲' : '▼')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(12)
          .backgroundColor(this.modelMenuOpen ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.modelMenuOpen = !this.modelMenuOpen;
          })

          // 上下文侧栏切换快捷按键
          Row({ space: 4 }) {
            Text('▤')
              .fontSize(TypographyTokens.BODY_REGULAR)
              .fontColor(this.pinnedNotes.length > 0 ? this.palette().accent : this.palette().inkMuted)
            Text('上下文')
              .fontSize(TypographyTokens.TINY)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkPrimary)
            if (this.pinnedNotes.length > 0) {
              Text(`${this.pinnedNotes.length}`)
                .fontSize(TypographyTokens.TINY)
                .fontColor(Color.White)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .borderRadius(8)
                .backgroundColor(this.palette().accent)
            }
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(8)
          .backgroundColor(this.contextPanelOpen ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.onToggleContextPanel();
          })

          // 独立快速检索图标按钮（防止挤压）
          Row() {
            Text('⌕')
              .fontSize(TypographyTokens.TITLE_SUB)
              .fontColor(this.palette().inkSecondary)
          }
          .width(32).height(32)
          .justifyContent(FlexAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.palette().surfaceSubtle)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onOpenSearch())

          // 设置按钮
          Text('⚙')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .width(32).height(32)
            .textAlign(TextAlign.Center)
            .borderRadius(8)
            .backgroundColor(this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onOpenModelSettings())
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.palette().surface)
        .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

      // 2. 消息流与欢迎看板
      if (this.messages.length === 0 && !this.isLoading) {
        Column({ space: 16 }) {
          Text('✦')
            .fontSize(36)
            .fontColor(this.palette().accent)

          Column({ space: 4 }) {
            Text('FlowMind 墨客')
              .fontSize(TypographyTokens.TITLE_SUB)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)
            Text('智能文档研读与知识推演')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkMuted)
          }
          .alignItems(HorizontalAlign.Center)

          if (this.currentNote !== null && this.currentNote !== undefined) {
            Row({ space: 6 }) {
              Text('📌 伴读锁定')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().accent)
              Text(`《${this.currentNote.title}》`)
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkPrimary)
            }
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(this.palette().accentSoft)
          }

          Flex({
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Center,
            space: { main: { value: 12, unit: 1 }, cross: { value: 12, unit: 1 } }
          }) {
            ForEach(QUICK_PROMPTS, (qp: QuickPrompt) => {
              this.quickPromptCard(qp)
            }, (qp: QuickPrompt) => qp.title)
          }
          .constraintSize({ maxWidth: 560 })
          .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 40 })
      } else {
        Scroll(this.scroller) {
          Column({ space: 14 }) {
            ForEach(this.messages, (msg: StoredMessage) => {
              this.messageBubble(msg)
            }, (msg: StoredMessage) => msg.id)

            // 流式生成中
            if (this.isLoading) {
              Column({ space: 8 }) {
                Row({ space: 6 }) {
                  Text(this.layerTitle(this.runningLayer))
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().accent)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .backgroundColor(this.palette().accentSoft)

                  Text(this.toolStatus.length > 0 ? `⚙ ${this.toolStatus}` : '生成中…')
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().inkMuted)
                }

                // 流式思考链卡片
                if (this.streamingReasoning.length > 0) {
                  Column({ space: 4 }) {
                    Row({ space: 6 }) {
                      Circle({ width: 6, height: 6 })
                        .fill(this.palette().accent)
                      Text('正在思考…')
                        .fontSize(TypographyTokens.TINY)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.palette().accent)
                    }
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })

                    Column() {
                      Text(this.streamingReasoning)
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().inkMuted)
                        .fontFamily('monospace')
                        .width('100%')
                        .lineHeight(19)
                    }
                    .width('100%')
                    .padding(10)
                    .borderRadius(8)
                    .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)')
                    .border({ width: { left: 2 }, color: { left: this.palette().accent } })
                  }
                  .width('100%')
                }

                // 流式正文
                if (this.streamingText.length > 0) {
                  this.renderMarkdownText(this.streamingText, true)
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: 800 })
          .padding({ left: 20, right: 20, top: 16, bottom: 16 })
          .alignSelf(ItemAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
      }

      // 3. 悬浮岛输入控制台 (Floating Cockpit - Codex 极简复刻)
      Column({ space: 4 }) {
        // 加号操作舱浮层
        if (this.plusMenuOpen) {
          this.plusActionMenu()
        }

        // 挂载工程上下文纤薄 Chip 贴附栏（有文档时才显示）
        if (this.pinnedNotes.length > 0) {
          Row({ space: 6 }) {
            Text('📁')
              .fontSize(TypographyTokens.TINY)

            ForEach(this.pinnedNotes, (n: NoteItem) => {
              Row({ space: 4 }) {
                Text(n.title)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 120 })
                Text('✕')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
                  .onClick(() => {
                    this.pinnedNotes = this.pinnedNotes.filter((p: NoteItem) => p.id !== n.id);
                    this.onPinnedNotesChange(this.pinnedNotes);
                  })
              }
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .backgroundColor(this.palette().accentSoft)
            }, (n: NoteItem) => `cockpit-pin-${n.id}`)

            Blank()

            Text('清空')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.pinnedNotes = [];
                this.onPinnedNotesChange([]);
              })
          }
          .width('100%')
          .padding({ left: 8, right: 8, bottom: 2 })
        }

        // 核心输入卡片
        Row({ space: 8 }) {
          // Codex 风格「+」多功能操作按钮 (带弹出弹簧动画与旋转反馈)
          Row({ space: 3 }) {
            Text(this.plusMenuOpen ? '✕' : '+')
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.plusMenuOpen || this.pinnedNotes.length > 0 ? this.palette().accent : this.palette().inkSecondary)
              .rotate({ angle: this.plusMenuOpen ? 90 : 0 })
              .animation({ curve: curves.springMotion(0.28, 0.72) })
            if (this.pinnedNotes.length > 0) {
              Text(`${this.pinnedNotes.length}`)
                .fontSize(TypographyTokens.TINY)
                .fontColor(Color.White)
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(6)
                .backgroundColor(this.palette().accent)
            }
          }
          .height(34)
          .padding({ left: 10, right: 10 })
          .justifyContent(FlexAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.plusMenuOpen ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            animateTo({ curve: curves.springMotion(0.28, 0.72) }, () => {
              this.plusMenuOpen = !this.plusMenuOpen;
            });
          })

          TextInput({
            text: this.inputText,
            placeholder: '输入问题或需求…'
          })
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkPrimary)
            .placeholderColor(this.palette().inkMuted)
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onChange((v: string) => { this.inputText = v; })
            .onSubmit(() => this.sendMessage())

          // 紧凑推演深度微型徽标（Codex 风格，点击即展开拖拽滑块弹窗）
          Row({ space: 4 }) {
            Text('✦')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().accent)
            Text(this.getBudgetShortLabel(this.selectedThinkingBudget))
              .fontSize(TypographyTokens.TINY)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkSecondary)
          }
          .padding({ left: 7, right: 7, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor(this.plusMenuOpen ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            animateTo({ curve: curves.springMotion(0.28, 0.72) }, () => {
              this.plusMenuOpen = !this.plusMenuOpen;
            });
          })

          if (this.isLoading) {
            Button('■ 停止')
              .type(ButtonType.Normal)
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(Color.White)
              .backgroundColor('#EF4444')
              .borderRadius(8)
              .height(34)
              .onClick(() => this.cancelStream())
          } else {
            Button('↑')
              .type(ButtonType.Normal)
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(36).height(36)
              .borderRadius(18)
              .backgroundColor(this.inputText.trim().length > 0 ? this.palette().accent : this.palette().surfaceSubtle)
              .enabled(this.inputText.trim().length > 0)
              .onClick(() => this.sendMessage())
          }
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(14)
        .backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().border })
        .shadow({ radius: 24, color: 'rgba(0,0,0,0.12)' })
      }
      .width('100%')
      .constraintSize({ maxWidth: 800 })
      .alignSelf(ItemAlign.Center)
      .padding({ left: 16, right: 16, bottom: 16, top: 6 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)

    // 4. 模型快速切换下拉浮层
    if (this.modelMenuOpen) {
      this.modelSelectMenu()
    }
  }
  .width('100%')
  .height('100%')
}
}

