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
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import {
  ChatSession,
  StoredMessage,
  ChatCitation,
  createEmptySession,
  createMessage
} from '../../common/types/ChatSession';
import { ModelProfile } from '../../common/types/ModelConfig';
import { WorkspaceToolExecutor } from '../../services/ai/WorkspaceToolExecutor';
import { ModelProfilePolicy } from '../../services/ai/ModelProfilePolicy';
import { RemoteAiPolicy } from '../../services/ai/RemoteAiPolicy';
import { NoteToolReader } from '../../services/ai/NoteToolReader';
import { ActionProposalService, ActionProposalData, ProposedActionItem } from '../../services/ai/ActionProposalService';
import { AgentOrchestrator, AgentLayer, AgentRunContext, CurrentDocContext } from '../../services/ai/AgentOrchestrator';
import { ChatSessionService } from '../../services/ai/ChatSessionService';
import { ModelConfigService, ACTIVE_STORAGE_KEY } from '../../services/ai/ModelConfigService';
import { RagRetriever } from '../../services/ai/RagRetriever';
import { StreamHandle } from '../../services/ai/ModelProvider';
import { NoteItem } from '../../common/types/NoteItem';
import { StudySourceService } from '../../services/study/StudySourceService';
import { ReviewCard } from '../../common/types/StudyTypes';
import { ReviewPolicy } from '../../services/study/ReviewPolicy';
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

function pad2(value: number): string { return String(value).padStart(2, '0'); }
const QUICK_PROMPTS: QuickPrompt[] = [
  { title: '自测题卡', badge: '自测', desc: '从资料生成题目和参考答案', query: '请根据我附加的笔记生成 5 道自测题，分别列出参考答案与依据。不足以出题时先说明缺少哪些资料。' },
  { title: '比较观点', badge: '比较', desc: '并列比较多份笔记的异同', query: '请比较我附加的笔记：并列列出共同结论、分歧与各自依据，并标注来源；不要补充资料里没有的信息。' },
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
  reviewCards: ReviewCard[] = [];
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
  onCreateTodo: (dateKey: string, title: string) => Promise<void> = async () => {};
  onAddTagToNote: (identifier: string, tags: string) => Promise<void> = async () => {};
  onCreateLinkBetweenNotes: (sourceIdentifier: string, targetTitle: string) => Promise<void> = async () => {};
  onCategorizeNote: (identifier: string, category: string) => Promise<void> = async () => {};
  onCreateNewNote: (title: string, category: string, tag: string, content: string) => Promise<void> = async () => {};
  onOpenSearch: () => void = () => {};
  onSmartExtract: () => void = () => {};
  onOpenCitation: (citation: ChatCitation) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp(ACTIVE_STORAGE_KEY) @Watch('onActiveProfileChanged') activeProfileId: string = '';
  @StorageProp('flowmindModelRevision') @Watch('onActiveProfileChanged') modelRevision: number = 0;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  @State messages: StoredMessage[] = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  @State streamingText: string = '';
  @State streamingReasoning: string = '';
  @State currentAgentMode: AgentLayer | 'auto' = 'auto';
  @State modelLabel: string = '';
  @State modelReady: boolean = false;
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
  @State showAllPrompts: boolean = false;
  @State historyBusy: boolean = false;
  @State selectedThinkingBudget: number = 16384;
  @State applyingProposal: string = '';
  @State proposalFeedback: string = '';

  private orchestrator: AgentOrchestrator = new AgentOrchestrator();
  private sessionService: ChatSessionService = ChatSessionService.getInstance();
  private retriever: RagRetriever = new RagRetriever();
  private streamHandle: StreamHandle | null = null;
  private scroller: Scroller = new Scroller();
  private loadedSessionId: string = '';
  private servicesReady: boolean = false;
  private cancelled: boolean = false;
  private blinkTimer: number = -1;
  private alive: boolean = true;
  private requestId: number = 0;

  aboutToAppear(): void {
    this.alive = true;
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
    this.alive = false;
    this.cancelStream();
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
    this.cancelStream();
    this.loadSessionById(this.activeSessionId);
  }

  private async loadModelLabel(): Promise<void> {
    try {
      this.profiles = await ModelConfigService.getInstance().loadProfiles();
      const profile = await ModelConfigService.getInstance().getActiveProfile();
      const invalid = ModelProfilePolicy.validate(profile).length > 0 || profile.credentialUnavailable === true;
      this.modelReady = !invalid && RemoteAiPolicy.consented(profile);
      this.modelLabel = `${profile.label} · ${invalid ? '待配置' : this.modelReady ? '自配 API' : '待授权'}`;
      this.isModelReasoningType = (profile.protocol === 'openai-compat' || profile.protocol === 'custom') &&
        profile.isReasoningModel === true && (/^(o1|o3|o4)/i.test(profile.modelId) || /codex/i.test(profile.modelId));
    } catch {
      this.modelLabel = '未配置模型';
      this.modelReady = false;
      this.isModelReasoningType = false;
      this.profiles = [];
    }
    this.emitContext();
  }

  private async switchActiveProfile(profileId: string): Promise<void> {
    if (this.isLoading || this.applyingProposal.length > 0) { return; }
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

  private async retrieve(query: string, profile: ModelProfile, cancelled: () => boolean): Promise<ChatCitation[]> {
    const docs: MarkdownDocument[] = StudySourceService.documents(this.allNotes);
    const hits: RetrievalHit[] = await this.retriever.searchHybrid(docs, query, profile, 6, cancelled);
    const citations: ChatCitation[] = [];
    for (const h of hits) {
      citations.push({
        noteId: h.chunk.noteId,
        noteTitle: h.chunk.noteTitle,
        headingPath: h.chunk.headingPath,
        chunkText: h.chunk.text,
        score: h.score,
        pageNumber: h.chunk.pageNumber,
        startLine: h.chunk.startLine
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
      content: StudySourceService.context(this.currentNote),
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
    out += '\n【课程自测记录】\n以下是用户的复习自评，不等同于考试成绩或完整能力测评。\n';
    for (const course of ReviewPolicy.courses(this.allNotes, this.reviewCards, this.todos).slice(0, 15)) {
      out += `- ${course.name}：${course.cardCount} 道已建题卡，${course.dueCount} 道到期复习。\n`;
    }
    return out;
  }

  // ------------------------------------------------------------------
  // 问答调度
  // ------------------------------------------------------------------

  private async sendMessage(): Promise<void> {
    const query = this.inputText.trim();
    if (!query || this.isLoading || this.historyBusy || this.applyingProposal.length > 0) { return; }
    const request = ++this.requestId;
    const session = this.loadedSessionId;
    this.cancelled = false; this.isLoading = true; this.toolStatus = '准备上下文…';
    const current = (): boolean => this.alive && !this.cancelled && request === this.requestId && session === this.loadedSessionId;
    try {
      const configured = await ModelConfigService.getInstance().getActiveProfile();
      if (!current()) { return; }
      const error = ModelProfilePolicy.validate(configured);
      if (error) { this.toolStatus = ''; promptAction.showToast({ message: error }); return; }
      try { RemoteAiPolicy.assertAllowed(configured); }
      catch (e) { this.toolStatus = ''; promptAction.showToast({ message: (e as Error).message }); return; }
      const profile = ModelProfilePolicy.restore(configured)!;
      if (this.isModelReasoningType) { profile.thinkingBudget = this.selectedThinkingBudget; }
      let layer: AgentLayer = this.currentAgentMode === 'auto' ? this.orchestrator.classify(query) : this.currentAgentMode;
      if (layer === 'L1' && !this.currentNote) { layer = 'L3'; }
      this.runningLayer = layer;
      const history = this.messages.slice();
      this.messages = [...this.messages, createMessage('user', query)]; this.inputText = '';
      this.streamingText = ''; this.streamingReasoning = ''; this.scrollToBottom();
      const pinned = this.pinnedNotes.map((note: NoteItem) => `【${note.title}】\n${StudySourceService.context(note)}`);
      let hits: ChatCitation[] = [];
      if (layer === 'L3') { this.toolStatus = '正在检索笔记…'; hits = await this.retrieve(query, profile, () => !current()); }
      if (!current()) { return; }
      this.lastCitations = hits; this.emitContext(); this.toolStatus = '模型正在生成…';
      const ctx: AgentRunContext = { query, history, profile,
        currentDoc: layer === 'L1' ? this.buildCurrentDocContext() : undefined,
        pinnedNotes: pinned, retrievalHits: hits,
        learningContext: layer === 'L2' ? this.buildLearningContext() : undefined,
        tools: this.toolsEnabled ? AGENT_TOOLS : [], executor: this.buildExecutor(),
        isCancelled: () => !current(),
        confirm: (name: string, args: string) => this.confirmTool(name, args) };
      await this.orchestrator.run(layer, ctx,
        (text: string, done: boolean, reasoning?: string) => {
          if (!current()) { return; }
          this.streamingText = text; this.streamingReasoning = reasoning || '';
          if (done) {
            const message = createMessage('assistant', text); message.agentLayer = layer;
            if (reasoning) { message.reasoningContent = reasoning; message.reasoningFolded = true; }
            if (hits.length) { message.citations = hits; }
            this.messages = [...this.messages, message];
            this.streamingText = ''; this.streamingReasoning = ''; this.toolStatus = '';
            this.scrollToBottom(); this.persistSession();
          }
        }, (handle: StreamHandle) => { if (current()) { this.streamHandle = handle; } else { handle.abort(); } });
    } catch (error) {
      if (current()) {
        this.streamingText = ''; this.streamingReasoning = ''; this.toolStatus = '';
        this.appendError(error instanceof Error ? error.message : '智能体请求失败'); this.persistSession();
      }
    } finally { if (request === this.requestId && this.alive) { this.isLoading = false; this.streamHandle = null; } }
  }
  private buildExecutor(): WorkspaceToolExecutor {
    return new WorkspaceToolExecutor({
      search: (query: string, limit: number) => this.toolSearchNotes(query, limit),
      list: (category: string) => this.toolListNotes(category),
      read: (identifier: string) => this.toolReadNote(identifier),
      summarize: () => this.toolSummarizeVault(),
      outline: (identifier: string) => this.toolNoteOutline(identifier),
      todos: (date: string, status: string) => this.toolListTodos(date, status),
      createTodo: (date: string, title: string) => this.toolCreateTodo(date, title),
      addTag: (identifier: string, tags: string) => this.toolAddTagToNote(identifier, tags),
      createLink: (source: string, target: string, reason?: string) => this.toolCreateLink(source, target, reason),
      categorize: (identifier: string, category: string) => this.toolCategorizeNote(identifier, category),
      createNote: (title: string, category: string, tag: string, content: string) => this.toolCreateNote(title, category, tag, content),
      progress: (text: string) => { if (this.alive) { this.toolStatus = text; } }
    });
  }

  private toolSearchNotes(query: string, limit: number): string {
    const docs: MarkdownDocument[] = StudySourceService.documents(this.allNotes);
    const hits: RetrievalHit[] = this.retriever.search(docs, query, limit);
    if (hits.length === 0) {
      return `未检索到与「${query}」相关的笔记切片。`;
    }
    let out: string = '';
    for (const h of hits) {
      out += `〔${h.chunk.noteTitle} · ${h.chunk.pageNumber ? `第 ${h.chunk.pageNumber} 页` : h.chunk.headingPath || '正文'}〕\n`
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
    const note = NoteToolReader.resolve(this.allNotes, identifier);
    const body = StudySourceService.context(note, 24000);
    return `【${note.title}】 ID: ${note.id}\n分类: ${note.category || '未分类'}\n标签: ${note.tag || '无'}\n正文:\n${body || '（空文档）'}${body.length < note.contentDetail.length ? '\n（内容较长，已截取前 24000 字符）' : ''}`;
  }

  private toolNoteOutline(identifier: string): string { return NoteToolReader.outline(NoteToolReader.resolve(this.allNotes, identifier)); }

  private toolListTodos(date: string, status: string): string {
    const tasks = this.todos.filter((todo: TodoItem) => (!date || todo.date === date) &&
      (status === 'all' || (status === 'done' ? todo.done : !todo.done)));
    return tasks.length ? tasks.slice(0, 50).map((todo: TodoItem) =>
      `${todo.done ? '[x]' : '[ ]'} ${todo.date} · ${todo.title}`).join('\n') : '没有符合条件的待办';
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

  private async toolCreateTodo(date: string, title: string): Promise<string> {
    await this.onCreateTodo(date, title);
    return `已成功创建待办：[${date}] ${title}`;
  }

  private async toolAddTagToNote(identifier: string, tags: string): Promise<string> {
    await this.onAddTagToNote(identifier, tags);
    return `已为笔记「${identifier}」添加标签：${tags}`;
  }

  private async toolCreateLink(sourceIdentifier: string, targetTitle: string, reason?: string): Promise<string> {
    await this.onCreateLinkBetweenNotes(sourceIdentifier, targetTitle);
    return `已在笔记「${sourceIdentifier}」中追加双向链接 [[${targetTitle}]]`;
  }

  private async toolCategorizeNote(identifier: string, category: string): Promise<string> {
    await this.onCategorizeNote(identifier, category);
    return `已将笔记「${identifier}」归档入项目「${category}」`;
  }

  private async toolCreateNote(title: string, category: string, tag: string, content: string): Promise<string> {
    await this.onCreateNewNote(title, category, tag, content);
    return `已成功新建笔记「${title}」`;
  }

  private async confirmTool(toolName: string, argsJson: string): Promise<boolean> {
    if (this.cancelled) {
      return false;
    }
    const result = await promptAction.showDialog({ title: `确认${toolDisplayName(toolName)}`,
      message: this.describeToolArgs(toolName, argsJson).slice(0, 600),
      buttons: [{ text: '取消', color: this.palette().inkSecondary }, { text: '执行', color: this.palette().accent }] });
    return !this.cancelled && this.alive && result.index === 1;
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
  private async applyProposal(msgId: string, proposal: ActionProposalData): Promise<void> {
    if (this.applyingProposal || this.isLoading) { return; }
    const message = this.messages.find((item: StoredMessage) => item.id === msgId);
    if (!message || message.proposalStatus === 'accepted' || !Array.isArray(proposal.actions)) { return; }
    const session = this.loadedSessionId;
    this.applyingProposal = msgId; this.proposalFeedback = '';
    try {
      const profile = await ModelConfigService.getInstance().getActiveProfile();
      if (profile.toolAccess === 'none' || profile.toolAccess === 'read') { throw new Error('当前档案只允许读取，请在工具设置中开启“写入前确认”'); }
      const executor = this.buildExecutor();
      const completed = message.proposalAppliedIds || [];
      for (let i = 0; i < proposal.actions.length; i++) {
        if (!this.alive || session !== this.loadedSessionId) { throw new Error('已停止应用此方案'); }
        const action = proposal.actions[i]; const key = `${i}:${action.id || action.type}`;
        if (completed.includes(key)) { continue; }
        this.proposalFeedback = `正在执行 ${i + 1}/${proposal.actions.length}…`;
        const result = await ActionProposalService.execute(action, executor);
        if (!result.ok) { throw new Error(`第 ${i + 1} 项未完成：${result.content}`); }
        completed.push(key); message.proposalAppliedIds = completed.slice(); this.messages = this.messages.slice();
        await this.persistSession(true);
      }
      message.proposalStatus = 'accepted'; this.messages = this.messages.slice(); await this.persistSession(true);
      this.proposalFeedback = `已保存 ${completed.length} 项变更`;
    } catch (error) {
      this.proposalFeedback = `${error instanceof Error ? error.message : '执行失败'}。已完成的项目会保留，重试时跳过。`;
    } finally { this.applyingProposal = ''; this.toolStatus = ''; }
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
    this.requestId++;
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

  private async persistSession(strict: boolean = false): Promise<void> {
    if (!this.servicesReady) {
      return;
    }
    try {
      if (this.loadedSessionId.length === 0) {
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
          if (s.id === this.loadedSessionId) {
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
      if (strict) { throw new Error('变更已完成，但执行记录未能保存，请勿重复创建'); }
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
    if (this.applyingProposal.length > 0) { return; }
    if (this.isLoading) {
      this.cancelStream();
    }
    this.loadedSessionId = '';
    this.modelMenuOpen = false; this.plusMenuOpen = false; this.inputText = '';
    this.messages = [];
    this.lastCitations = [];
    this.streamingText = '';
    this.streamingReasoning = '';
    this.pinnedNotes = [];
    this.onPinnedNotesChange([]);
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

        // 建议操作卡 (Codex / Claude Code 交互式协同)
        this.proposalCard(msg)

        // 引用来源芯片
        if (msg.citations !== undefined && msg.citations !== null && msg.citations.length > 0) {
          Column({ space: 4 }) {
            Text('引用溯源')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 6, unit: 1 }, cross: { value: 4, unit: 1 } } }) {
              ForEach(msg.citations, (c: ChatCitation) => {
                Text(`〔${c.noteTitle} · ${c.pageNumber ? `第 ${c.pageNumber} 页` : c.headingPath || '正文'}〕`)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().accent)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(6)
                  .backgroundColor(this.palette().accentSoft)
                  .constraintSize({ minHeight: 44 })
                  .accessibilityText(`查看${c.noteTitle}${c.pageNumber ? `第 ${c.pageNumber} 页` : '原文'}`)
                  .onClick(() => this.onOpenCitation(c))
              }, (c: ChatCitation) => `${c.noteId}-${c.pageNumber || 0}-${c.headingPath}-${c.startLine || 0}`)
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
          Text('建议操作')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Text('确认后写入')
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
              Text(act.type === 'todo' ? '☐ 待办' : (act.type === 'tag' ? '＃ 标签' : (act.type === 'link' ? '↔ 双链' : (act.type === 'category' ? '▦ 归档' : '✎ 新建'))))
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

      if (this.proposalFeedback.length > 0) {
        Text(this.proposalFeedback).fontSize(12).lineHeight(18).fontColor(this.palette().inkSecondary).width('100%')
      }
      // 操作交互栏：接受并应用 / 拒绝
      if (msg.proposalStatus !== 'accepted' && msg.proposalStatus !== 'dismissed') {
        Row({ space: 10 }) {
          Row({ space: 6 }) {
            Text('✓')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text(this.applyingProposal === msg.id ? '正在保存…' : '确认执行方案')
              .fontSize(TypographyTokens.CAPTION)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .height(44).enabled(!this.isLoading && this.applyingProposal.length === 0)
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
          .height(44).enabled(this.applyingProposal.length === 0)
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
          Text('建议操作在下方，请核对后确认。')
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
    .width('47%')
    .padding(14)
    .borderRadius(12)
    .backgroundColor(this.palette().surfaceSubtle)
    .border({ width: 1, color: this.palette().borderSubtle })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.inputText = qp.query;
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
          .width(44).height(44)
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
                    Text('推理')
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
            .constraintSize({ minHeight: 52 })
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

      if (this.isModelReasoningType) {
        Text('推理强度').fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
        Row({ space: 6 }) {
          ForEach(THINKING_BUDGETS.slice(0, 3), (item: ThinkingBudgetPreset, index: number) => {
            Button(index === 0 ? '轻量' : index === 1 ? '均衡' : '深入').height(44).layoutWeight(1).fontSize(12)
              .type(ButtonType.Normal).borderRadius(8)
              .backgroundColor(this.getBudgetShortLabel(this.selectedThinkingBudget) === item.label ? this.palette().accentSoft : this.palette().surfaceSubtle)
              .fontColor(this.palette().inkPrimary).onClick(() => { this.selectedThinkingBudget = item.val; })
          }, (item: ThinkingBudgetPreset) => item.key)
        }.width('100%')
        Text('仅对已配置且支持 reasoning_effort 的兼容模型生效。').fontSize(11).fontColor(this.palette().inkSecondary).width('100%')
      }

      Row({ space: 6 }) {
        Image($r('app.media.ic_sparkle')).width(18).height(18).fillColor(this.palette().inkSecondary)
        Text('AI 设置与模型目录')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().accent)
      }
      .width('100%')
      .constraintSize({ minHeight: 44 })
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(6)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.modelMenuOpen = false;
        this.onOpenModelSettings();
      })
    }
    .width(this.isPhone ? '92%' : 300)
    .padding(10)
    .borderRadius(12)
    .backgroundColor(this.palette().surface)
    .border({ width: 1, color: this.palette().border })
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.18)' })
    .margin({ top: 54, right: this.isPhone ? 12 : 20 })
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

  private async rewindLastMessage(): Promise<void> {
    if (this.isLoading || this.historyBusy || this.applyingProposal || !this.servicesReady) { return; }
    if (!this.loadedSessionId) { promptAction.showToast({ message: '正在保存对话，请稍后重试' }); return; }
    if (this.messages.length === 0) {
      promptAction.showToast({ message: '暂无消息可撤销' });
      return;
    }
    const original = this.messages.slice();
    const sessionId = this.loadedSessionId;
    if (this.messages[this.messages.length - 1].role === 'assistant') {
      this.messages.pop();
    }
    if (this.messages.length > 0 && this.messages[this.messages.length - 1].role === 'user') {
      this.messages.pop();
    }
    this.messages = [...this.messages];
    const next = this.messages;
    this.historyBusy = true;
    try {
      const saved = await this.sessionService.replaceMessages(sessionId, next);
      if (!this.alive || this.loadedSessionId !== sessionId || this.messages !== next) { return; }
      this.onSessionSaved(saved);
      const last = this.messages.slice().reverse().find((m: StoredMessage) => m.role === 'assistant');
      this.lastCitations = last?.citations || []; this.emitContext();
      promptAction.showToast({ message: '已撤回上一轮消息，已创建的笔记和待办保留' });
    } catch {
      if (!this.alive || this.loadedSessionId !== sessionId || this.messages !== next) { return; }
      this.messages = original;
      promptAction.showToast({ message: '消息撤回未能保存，原对话已保留' });
    } finally { if (this.alive) { this.historyBusy = false; } }
  }

  @Builder
  attachmentAction(title: string, icon: Resource, action: () => void) {
    Row({ space: 10 }) {
      Image(icon).width(18).height(18).fillColor(this.palette().inkSecondary)
      Text(title).fontSize(14).fontColor(this.palette().inkPrimary).layoutWeight(1)
    }.width('100%').height(48).padding({ left: 12, right: 12 }).borderRadius(8)
      .hoverEffect(HoverEffect.Highlight).onClick(action)
  }

  @Builder
  plusActionMenu() {
    Column({ space: 4 }) {
      this.attachmentAction('图片识别与整理', $r('app.media.ic_sparkle'), () => {
        this.plusMenuOpen = false; this.onSmartExtract();
      })
      this.attachmentAction('引用库内资料', $r('app.media.ic_note'), () => {
        this.plusMenuOpen = false; this.onToggleContextPanel();
      })
      this.attachmentAction('导入外部文件', $r('app.media.ic_import'), () => {
        this.plusMenuOpen = false; this.importExternalFile();
      })
      if (this.messages.length > 0) {
        Divider().color(this.palette().borderSubtle)
        this.attachmentAction('撤回上一轮消息', $r('app.media.ic_note'), () => {
          this.plusMenuOpen = false; this.rewindLastMessage();
        })
      }
    }.width(this.isPhone ? '100%' : 280).padding(8).borderRadius(12)
      .backgroundColor(this.palette().surface).border({ width: 1, color: this.palette().border })
      .alignSelf(ItemAlign.Start).enabled(!this.isLoading && !this.historyBusy && !this.applyingProposal)
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 }))
        .animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('AI 墨客').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
            Row({ space: 6 }) {
              Text(this.modelLabel).fontSize(12).fontColor(this.palette().inkSecondary).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              Text('▾').fontSize(12).fontColor(this.palette().inkMuted)
            }.layoutWeight(1).height(44).padding({ left: 10, right: 10 }).borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle).enabled(!this.isLoading && !this.historyBusy && !this.applyingProposal)
              .accessibilityText('切换模型档案').onClick(() => { this.plusMenuOpen = false; this.modelMenuOpen = !this.modelMenuOpen; })
            Text('+').fontSize(22).fontColor(this.palette().inkPrimary).width(44).height(44).textAlign(TextAlign.Center)
              .accessibilityText('新对话').enabled(!this.applyingProposal).onClick(() => this.startNewChat())
            if (!this.isPhone) {
              Image($r('app.media.ic_note')).width(44).height(44).padding(12).fillColor(this.palette().inkSecondary)
                .accessibilityText('查看来源与上下文').onClick(() => this.onToggleContextPanel())
            }
            Image($r('app.media.ic_menu')).width(44).height(44).padding(12).fillColor(this.palette().inkSecondary)
              .accessibilityText('模型与工具设置').enabled(!this.isLoading && !this.historyBusy && !this.applyingProposal).onClick(() => this.onOpenModelSettings())
          }.width('100%')
          Row({ space: 4 }) {
            ForEach(MODE_TABS, (item: AgentModeTabItem) => {
              Text(item.title).fontSize(13).fontWeight(this.currentAgentMode === item.mode ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.currentAgentMode === item.mode ? this.palette().inkPrimary : this.palette().inkMuted)
                .layoutWeight(1).height(44).textAlign(TextAlign.Center).borderRadius(8)
                .backgroundColor(this.currentAgentMode === item.mode ? this.palette().surfaceSubtle : Color.Transparent)
                .enabled(!this.isLoading && !this.historyBusy && !this.applyingProposal)
                .onClick(() => { this.currentAgentMode = item.mode as AgentLayer | 'auto'; })
            }, (item: AgentModeTabItem) => item.mode)
          }.width('100%')
        }.width('100%').padding({ left: this.isPhone ? 12 : 20, right: this.isPhone ? 12 : 20, top: 6, bottom: 6 })
          .backgroundColor(this.palette().surface)
          .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })
      // 2. 消息流与欢迎看板
      if (this.messages.length === 0 && !this.isLoading) {
        Scroll() {
        Column({ space: 16 }) {
          Image($r('app.media.ic_sparkle')).width(32).height(32).fillColor(this.palette().accent)

          Column({ space: 4 }) {
            Text('把资料变成学习收获')
              .fontSize(TypographyTokens.TITLE_SUB)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)
            Text('提炼要点、比较观点，或准备一组自测题。')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkMuted)
          }
          .alignItems(HorizontalAlign.Center)

          if (this.currentNote !== null && this.currentNote !== undefined) {
            Row({ space: 6 }) {
              Text('▣ 伴读文档')
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
            ForEach(this.showAllPrompts ? QUICK_PROMPTS : QUICK_PROMPTS.slice(0, 4), (qp: QuickPrompt) => {
              this.quickPromptCard(qp)
            }, (qp: QuickPrompt) => qp.title)
          }
          .constraintSize({ maxWidth: 560 })
          .width('100%')
          .padding({ left: 16, right: 16 })
          Button(this.showAllPrompts ? '收起更多用法' : '更多用法').height(44).fontSize(12).type(ButtonType.Normal)
            .backgroundColor(Color.Transparent).fontColor(this.palette().inkSecondary).onClick(() => { this.showAllPrompts = !this.showAllPrompts; })
          Text('选择用法后，可补充问题再发送。').fontSize(12).fontColor(this.palette().inkMuted)
          if (!this.modelReady) {
            Button('配置 AI 或浏览模型目录').height(44).fontSize(13).type(ButtonType.Normal).borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary).onClick(() => this.onOpenModelSettings())
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 24, bottom: 24 })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
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

      Column({ space: 8 }) {
        if (this.plusMenuOpen) { this.plusActionMenu() }
        if (this.pinnedNotes.length > 0) {
          Row({ space: 8 }) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.pinnedNotes, (n: NoteItem) => {
                  Row({ space: 4 }) {
                    Text(n.title).fontSize(12).fontColor(this.palette().inkPrimary).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 130 })
                    Text('×').fontSize(18).fontColor(this.palette().inkSecondary).width(44).height(44).textAlign(TextAlign.Center)
                      .enabled(!this.isLoading && !this.historyBusy && !this.applyingProposal).accessibilityText(`移除引用资料：${n.title}`)
                      .onClick(() => {
                        this.pinnedNotes = this.pinnedNotes.filter((p: NoteItem) => p.id !== n.id);
                        this.onPinnedNotesChange(this.pinnedNotes);
                      })
                  }.padding({ left: 10 }).borderRadius(8).backgroundColor(this.palette().accentSoft)
                }, (n: NoteItem) => `cockpit-pin-${n.id}`)
              }
            }.layoutWeight(1).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
            Button('清空').height(44).fontSize(12).type(ButtonType.Normal).backgroundColor(Color.Transparent)
              .fontColor(this.palette().inkSecondary).enabled(!this.isLoading && !this.historyBusy && !this.applyingProposal).onClick(() => {
                this.pinnedNotes = []; this.onPinnedNotesChange([]);
              })
          }.width('100%')
        }
        Column({ space: 4 }) {
          TextArea({ text: this.inputText, placeholder: '提问，或添加资料后让 AI 整理…' })
            .height(this.isPhone ? 80 : 88).width('100%').fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkPrimary).placeholderColor(this.palette().inkMuted)
            .backgroundColor(Color.Transparent).onChange((v: string) => { this.inputText = v; })
          Row({ space: 8 }) {
            Button(this.plusMenuOpen ? '×' : '+').width(44).height(44).fontSize(22).type(ButtonType.Normal).borderRadius(8)
              .backgroundColor(this.plusMenuOpen ? this.palette().accentSoft : this.palette().surfaceSubtle)
              .fontColor(this.palette().inkSecondary).enabled(!this.isLoading && !this.historyBusy && !this.applyingProposal)
              .accessibilityText('添加资料与对话操作').onClick(() => {
                this.modelMenuOpen = false;
                animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => { this.plusMenuOpen = !this.plusMenuOpen; });
              })
            Text(this.pinnedNotes.length > 0 ? `已引用 ${this.pinnedNotes.length} 篇资料` : '资料可选')
              .fontSize(12).fontColor(this.palette().inkMuted).layoutWeight(1)
            if (this.isLoading) {
              Button('停止').height(44).fontSize(14).type(ButtonType.Normal).borderRadius(8)
                .backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().danger).onClick(() => this.cancelStream())
            } else {
              Button('发送 ↑').height(44).fontSize(14).type(ButtonType.Normal).borderRadius(8).fontColor(Color.White)
                .backgroundColor(this.palette().accent).enabled(this.inputText.trim().length > 0 && !this.historyBusy && !this.applyingProposal)
                .onClick(() => this.sendMessage())
            }
          }.width('100%')
        }.width('100%').padding(10).borderRadius(14).backgroundColor(this.palette().surface)
          .border({ width: 1, color: this.palette().border })
      }.width('100%').constraintSize({ maxWidth: 800 }).alignSelf(ItemAlign.Center)
        .padding({ left: this.isPhone ? 12 : 20, right: this.isPhone ? 12 : 20, bottom: this.isPhone ? 12 : 16, top: 6 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)

    // 4. 模型快速切换下拉浮层
    if (this.modelMenuOpen) {
      Column().width('100%').height('100%').onClick(() => { this.modelMenuOpen = false; })
      this.modelSelectMenu()
    }
  }
  .width('100%')
  .height('100%')
}
}

