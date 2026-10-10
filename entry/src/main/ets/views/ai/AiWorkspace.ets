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
import { WorkspaceToolExecutor } from '../../services/ai/WorkspaceToolExecutor';
import { ToolArgumentValidator } from '../../services/ai/ToolArgumentValidator';
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
import { AssistantModeService, ASSISTANT_MODE_KEY } from '../../services/ai/AssistantModeService';
import { AiReferenceSearch } from '../../services/ai/AiReferenceSearch';
import { LocalAssistantService } from '../../services/ai/LocalAssistantService';
import { REMOTE_AI_ENABLED } from '../../common/constants/RuntimeCapabilities';
import { AssistantText } from '../common/AssistantText';
import { IconButton } from '../common/IconButton';
import { AppIcon } from '../common/AppIcon';

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

const LOCAL_PROMPTS: QuickPrompt[] = [
  { title: '提取要点', badge: '摘录', desc: '查看资料的原文要点', query: '提取要点' },
  { title: '整理待办', badge: '待办', desc: '提取原文明示的任务', query: '整理待办' },
  { title: '搜索原文', badge: '检索', desc: '输入课程名或关键词', query: '' },
  { title: '资料概览', badge: '概览', desc: '查看分类与待办数量', query: '资料概览' }
];

@Component
export struct AiWorkspace {
  @Prop currentNote: NoteItem | null = null;
  @Prop allNotes: NoteItem[] = [];
  @Prop todos: TodoItem[] = [];
  @Prop reviewCards: ReviewCard[] = [];
  @Prop stats: WorkspaceStats = { noteCount: 0, linkCount: 0, unresolvedCount: 0, tagCount: 0 };

  @Prop @Watch('onActiveSessionIdChanged') activeSessionId: string = '';
  @Prop @Watch('onExternalPinnedNotesChanged') externalPinnedNotes: NoteItem[] = [];
  @Prop @Watch('onPrefilledPromptChanged') prefilledPrompt: string = '';
  @Prop toolsEnabled: boolean = true;
  @Prop contextPanelOpen: boolean = false;
  @Prop @Watch('handleBackRequest') backRequestToken: number = 0;
  onNavigateBack: () => void = () => {};
  onNewSession: () => void = () => {};
  @Prop historyOpen: boolean = false;
  onToggleHistory: () => void = () => {};
  onDeleteSession: (id: string) => void = () => {};
  onImportExternal: () => Promise<NoteItem | null> = async () => null;

  onSessionSaved: (session: ChatSession, activate?: boolean) => void = () => {};
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
  onManageNote: (operation: string, identifier: string, value: string, expectedUpdatedAt: number) => Promise<string> = async () => { throw new Error('资料管理未连接'); };
  onSetTodoStatus: (identifier: string, status: string) => Promise<string> = async () => { throw new Error('待办管理未连接'); };
  onOpenSearch: () => void = () => {};
  onSmartExtract: () => void = () => {};
  onOpenCitation: (citation: ChatCitation) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  @StorageProp(ACTIVE_STORAGE_KEY) @Watch('onActiveProfileChanged') activeProfileId: string = '';
  @StorageProp('flowmindModelRevision') @Watch('onActiveProfileChanged') modelRevision: number = 0;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;
  @StorageProp(ASSISTANT_MODE_KEY) @Watch('onActiveProfileChanged') assistantMode: string = 'local';

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
  @State conversationMenuOpen: boolean = false;
  @State attachmentBusy: boolean = false;
  @State modelSwitchBusy: boolean = false;
  @State workspaceWidth: number = 360;
  @State showAllPrompts: boolean = false;
  @State historyBusy: boolean = false;
  @State sessionLoadBusy: boolean = false;
  @State sessionLoadError: string = '';
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
  private attachmentRequestId: number = 0;
  private modelSwitchRequestId: number = 0;
  private contextRevision: number = 0;
  private sessionLoadRequestId: number = 0;
  private persistQueue: Promise<void> = Promise.resolve();
  private unsavedSessions: Map<string, ChatSession> = new Map();

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
    this.closeComposerMenus(); this.pickerOpen = false;
    this.attachmentRequestId++;
    this.modelSwitchRequestId++;
    this.contextRevision++; this.sessionLoadRequestId++;
    this.attachmentBusy = false;
    this.modelSwitchBusy = false;
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
      await AssistantModeService.getInstance().init(ctx);
      await this.sessionService.init(ctx);
      if (REMOTE_AI_ENABLED) { await ModelConfigService.getInstance().init(ctx); }
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
    this.closeComposerMenus(); this.pickerOpen = false;
    this.attachmentRequestId++;
    this.attachmentBusy = false;
    this.cancelStream();
    this.inputText = ''; this.pinnedNotes = []; this.onPinnedNotesChange([]);
    this.loadSessionById(this.activeSessionId);
  }

  private async loadModelLabel(): Promise<void> {
    if (!REMOTE_AI_ENABLED) {
      this.modelLabel = '本地助手 · 离线'; this.modelReady = true;
      this.isModelReasoningType = false; this.profiles = []; this.emitContext(); return;
    }
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
    if (this.assistantMode === 'local') {
      this.modelLabel = '本地助手 · 离线';
      this.modelReady = true;
      this.isModelReasoningType = false;
    }
    this.emitContext();
  }

  private async switchActiveProfile(profileId: string): Promise<void> {
    if (!this.menuActionsAvailable()) { return; }
    this.modelMenuOpen = false;
    this.modelSwitchBusy = true;
    const request = ++this.modelSwitchRequestId;
    try {
      await ModelConfigService.getInstance().setActiveProfileId(profileId);
      if (!this.alive || request !== this.modelSwitchRequestId) { return; }
      const profile = await ModelConfigService.getInstance().getActiveProfile();
      if (!this.alive || request !== this.modelSwitchRequestId) { return; }
      if (ModelProfilePolicy.validate(profile) || profile.credentialUnavailable || !RemoteAiPolicy.consented(profile)) {
        promptAction.showToast({ message: '请先配置模型并确认发送授权' });
        this.onOpenModelSettings();
        return;
      }
      await AssistantModeService.getInstance().setMode('remote');
      if (!this.alive || request !== this.modelSwitchRequestId) { return; }
      await this.loadModelLabel();
      if (!this.alive || request !== this.modelSwitchRequestId) { return; }
      promptAction.showToast({ message: `已切换至 ${this.modelLabel}` });
    } catch {
      if (this.alive && request === this.modelSwitchRequestId) { promptAction.showToast({ message: '切换模型失败' }); }
    } finally { if (this.alive && request === this.modelSwitchRequestId) { this.modelSwitchBusy = false; } }
  }

  private async switchLocalAssistant(): Promise<void> {
    if (!this.menuActionsAvailable()) { return; }
    this.modelMenuOpen = false;
    this.modelSwitchBusy = true;
    const request = ++this.modelSwitchRequestId;
    try {
      await AssistantModeService.getInstance().setMode('local');
      if (!this.alive || request !== this.modelSwitchRequestId) { return; }
      await this.loadModelLabel();
    } catch {
      if (this.alive && request === this.modelSwitchRequestId) { promptAction.showToast({ message: '助手设置保存失败，请重试' }); }
    } finally { if (this.alive && request === this.modelSwitchRequestId) { this.modelSwitchBusy = false; } }
  }

  private menuActionsAvailable(): boolean {
    return this.alive && !this.isLoading && !this.historyBusy && !this.sessionLoadBusy && !this.sessionLoadError && !this.attachmentBusy && !this.modelSwitchBusy && !this.applyingProposal;
  }

  private closeComposerMenus(): void {
    this.plusMenuOpen = false;
    this.modelMenuOpen = false;
    this.conversationMenuOpen = false;
  }

  private toggleComposerMenu(menu: string): void {
    if (!this.menuActionsAvailable()) { return; }
    const wasOpen = menu === 'plus' ? this.plusMenuOpen : menu === 'model' ? this.modelMenuOpen : this.conversationMenuOpen;
    this.closeComposerMenus();
    this.pickerOpen = false;
    if (menu === 'plus') { this.plusMenuOpen = !wasOpen; }
    else if (menu === 'model') { this.modelMenuOpen = !wasOpen; }
    else if (menu === 'conversation') { this.conversationMenuOpen = !wasOpen; }
  }

  private menuWidth(): number { return Math.max(128, Math.min(300, this.workspaceWidth - 32)); }

  private emitContext(): void {
    const revision = ++this.contextRevision;
    setTimeout(() => {
      if (this.alive && revision === this.contextRevision) {
        this.onContextChange(this.lastCitations, this.pinnedNotes, this.layerTitle(this.runningLayer), this.modelLabel);
      }
    }, 0);
  }

  private async loadSessionById(id: string): Promise<void> {
    if (!this.alive || this.isLoading) { return; }
    const request = ++this.sessionLoadRequestId;
    this.sessionLoadBusy = id.length > 0;
    this.sessionLoadError = '';
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
    this.loadedSessionId = id; this.messages = []; this.lastCitations = [];
    this.streamingText = ''; this.streamingReasoning = ''; this.inputText = ''; this.emitContext();
    try {
      const sessions: ChatSession[] = await this.sessionService.loadSessions();
      if (!this.alive || request !== this.sessionLoadRequestId || id !== this.activeSessionId) { return; }
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
          this.lastCitations = safeMessages.slice().reverse().find((message: StoredMessage) => message.role === 'assistant')?.citations || [];
          this.streamingText = '';
          this.streamingReasoning = '';
          this.emitContext();
          this.scrollToBottom();
          return;
        }
      }
      this.sessionLoadError = '这段对话已不存在，请从记录中重新选择';
    } catch (error) {
      if (this.alive && request === this.sessionLoadRequestId) { this.sessionLoadError = '对话读取失败，请重试，原记录已保留'; }
    } finally { if (this.alive && request === this.sessionLoadRequestId) { this.sessionLoadBusy = false; } }
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private layerTitle(layer: AgentLayer | undefined): string {
    if (this.assistantMode === 'local' || !REMOTE_AI_ENABLED) { return '本地整理'; }
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
    if (!query || !this.menuActionsAvailable()) { return; }
    this.closeComposerMenus();
    const request = ++this.requestId;
    const session = this.loadedSessionId;
    this.cancelled = false; this.isLoading = true; this.toolStatus = '准备上下文…';
    const current = (): boolean => this.alive && !this.cancelled && request === this.requestId && session === this.loadedSessionId;
    try {
      if (this.assistantMode === 'local' || !REMOTE_AI_ENABLED) {
        this.messages = [...this.messages, createMessage('user', query)]; this.inputText = '';
        // Yield once so the sending state is visible before scanning local documents.
        await new Promise<void>((resolve) => { setTimeout(resolve, 0); });
        if (!current()) { return; }
        const result = await new LocalAssistantService().answer(query, { notes: this.allNotes,
          pinned: this.pinnedNotes, currentNote: this.currentNote || undefined, todos: this.todos }, () => !current());
        if (!current()) { return; }
        const response = createMessage('assistant', result.text);
        response.modelProfileId = 'local-assistant'; response.citations = result.citations;
        this.messages = [...this.messages, response]; this.lastCitations = result.citations;
        this.toolStatus = ''; this.emitContext(); this.scrollToBottom(); await this.persistSession();
        return;
      }
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
        const partial = this.streamingText; const reasoning = this.streamingReasoning;
        this.streamingText = ''; this.streamingReasoning = ''; this.toolStatus = '';
        this.appendError(error instanceof Error ? error.message : '请求失败，请重试', partial, reasoning); this.persistSession();
      }
    } finally { if (request === this.requestId && this.alive) { this.isLoading = false; this.streamHandle = null; } }
  }
  private buildExecutor(): WorkspaceToolExecutor {
    return new WorkspaceToolExecutor({
      search: (query: string, limit: number) => this.toolSearchNotes(query, limit),
      list: (category: string, offset?: number, limit?: number) => this.toolListNotes(category, offset, limit),
      read: (identifier: string, offset?: number, limit?: number) => this.toolReadNote(identifier, offset, limit),
      summarize: () => this.toolSummarizeVault(),
      outline: (identifier: string) => this.toolNoteOutline(identifier),
      todos: (date: string, status: string, offset?: number, limit?: number) => this.toolListTodos(date, status, offset, limit),
      createTodo: (date: string, title: string) => this.toolCreateTodo(date, title),
      addTag: (identifier: string, tags: string) => this.toolAddTagToNote(identifier, tags),
      createLink: (source: string, target: string, reason?: string) => this.toolCreateLink(source, target, reason),
      categorize: (identifier: string, category: string) => this.toolCategorizeNote(identifier, category),
      createNote: (title: string, category: string, tag: string, content: string) => this.toolCreateNote(title, category, tag, content),
      manageNote: (operation: string, identifier: string, value: string, expectedUpdatedAt: number) => this.onManageNote(operation, identifier, value, expectedUpdatedAt),
      setTodoStatus: (identifier: string, status: string) => this.onSetTodoStatus(identifier, status),
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

  private toolListNotes(category: string, offset: number = 0, limit: number = 20): string {
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
    for (const n of filtered.slice(offset, offset + limit)) {
      out += `- ID: ${n.id} | ${n.title} | 分类: ${n.category || '未分类'} | 标签: ${n.tag || '无'} | updatedAt: ${n.updatedAt || 0}\n`;
    }
    out += offset + limit < filtered.length ? `下一起点 offset=${offset + limit}` : '已到清单末尾';
    return out;
  }

  private toolReadNote(identifier: string, offset: number = 0, limit: number = 12000): string {
    const note = NoteToolReader.resolve(this.allNotes, identifier);
    const source = StudySourceService.context(note, offset + limit + 1);
    const body = source.slice(offset, offset + limit);
    return `【${note.title}】 ID: ${note.id} · updatedAt: ${note.updatedAt || 0}\n分类: ${note.category || '未分类'}\n标签: ${note.tag || '无'}\n正文（起点 ${offset}）:\n${body || '（此范围无文字）'}\n${source.length > offset + limit ? `下一起点 offset=${offset + limit}` : '已到正文末尾'}`;
  }

  private toolNoteOutline(identifier: string): string { return NoteToolReader.outline(NoteToolReader.resolve(this.allNotes, identifier)); }

  private toolListTodos(date: string, status: string, offset: number = 0, limit: number = 50): string {
    const tasks = this.todos.filter((todo: TodoItem) => (!date || todo.date === date) &&
      (status === 'all' || (status === 'done' ? todo.done : !todo.done)));
    if (!tasks.length) { return '没有符合条件的待办'; }
    const body = tasks.slice(offset, offset + limit).map((todo: TodoItem) =>
      `${todo.done ? '[x]' : '[ ]'} ID: ${todo.id} · ${todo.date} · ${todo.title}`).join('\n');
    return `待办清单（共 ${tasks.length} 项）：\n${body}\n${offset + limit < tasks.length ? `下一起点 offset=${offset + limit}` : '已到待办末尾'}`;
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
    if (['rename_note', 'update_note', 'set_note_flag', 'set_todo_status'].includes(toolName)) {
      try {
        const args = ToolArgumentValidator.parse(toolName, argsJson);
        return `目标：${args.identifier || ''}\n${toolName === 'rename_note' ? `新标题：${args.title}` :
          toolName === 'update_note' ? `读取版本：${args.expectedUpdatedAt}\n新正文：\n${args.content}` :
          toolName === 'set_todo_status' ? `状态：${args.status}` : `${args.flag}：${args.value}`}`;
      } catch { return '参数无效，操作不会执行'; }
    }
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

  private appendError(message: string, partial: string = '', reasoning: string = ''): void {
    const errMsg: StoredMessage = createMessage('assistant', partial);
    if (reasoning) { errMsg.reasoningContent = reasoning; errMsg.reasoningFolded = true; }
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
    if (!this.servicesReady) { if (strict) { throw new Error('对话存储尚未准备好，请稍后重试'); } return; }
    if (!this.loadedSessionId) {
      const created = createEmptySession(); this.loadedSessionId = created.id;
      this.unsavedSessions.set(created.id, created);
    }
    const targetId = this.loadedSessionId;
    const generation = this.sessionLoadRequestId;
    const snapshot = JSON.parse(JSON.stringify(this.messages)) as StoredMessage[];
    const mode = this.currentAgentMode;
    const fallback = this.unsavedSessions.get(targetId);
    const updatedAt = Date.now();
    let saved: ChatSession | null = null;
    // Capture before awaiting. A late write must never read another conversation's messages.
    const pending = this.persistQueue.then(async () => {
      const sessions = await this.sessionService.loadSessions();
      const original = sessions.find((session: ChatSession) => session.id === targetId) || fallback;
      if (!original) { throw new Error('这段对话已被删除，保存未覆盖其他记录'); }
      const next: ChatSession = { id: targetId, title: original.title, pinned: original.pinned,
        createdAt: original.createdAt, updatedAt, agentMode: mode, messages: snapshot };
      if ((!next.title || next.title === '新对话') && snapshot[0]?.role === 'user') { next.title = snapshot[0].text.slice(0, 30); }
      await this.sessionService.saveSession(next); this.unsavedSessions.delete(targetId); saved = next;
    });
    this.persistQueue = pending.catch(() => {});
    try {
      await pending;
      if (saved !== null) { this.onSessionSaved(saved, this.alive && generation === this.sessionLoadRequestId && targetId === this.loadedSessionId); }
    } catch (error) {
      console.error(`会话保存失败: ${JSON.stringify(error)}`);
      if (strict) { throw new Error('变更已完成，但执行记录未能保存，请勿重复创建'); }
      if (this.alive && generation === this.sessionLoadRequestId) { promptAction.showToast({ message: '对话未能保存，请检查存储后重试' }); }
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
    return AiReferenceSearch.find(this.allNotes, this.pickerKeyword, this.pinnedNotes.map((n: NoteItem) => n.id));
  }

  private openReferencePicker(): void {
    if (!this.menuActionsAvailable()) { return; }
    this.closeComposerMenus(); this.pickerKeyword = ''; this.pickerOpen = true;
  }

  private async prepareLocalTask(query: string): Promise<void> {
    if (!this.menuActionsAvailable()) { return; }
    const sessionId = this.loadedSessionId;
    const activeSessionId = this.activeSessionId;
    const draft = this.inputText;
    this.closeComposerMenus();
    if (this.assistantMode !== 'local') { await this.switchLocalAssistant(); }
    if (this.alive && sessionId === this.loadedSessionId && activeSessionId === this.activeSessionId &&
      draft === this.inputText && this.assistantMode === 'local' && this.menuActionsAvailable()) { this.inputText = query; }
  }

  private remoteTaskAvailable(): boolean {
    return REMOTE_AI_ENABLED && this.assistantMode === 'remote' && this.modelReady && this.menuActionsAvailable();
  }

  private prepareModelTask(query: string): void {
    if (!this.remoteTaskAvailable()) { return; }
    this.closeComposerMenus(); this.inputText = query;
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

  private startNewChat(): void {
    if (this.historyBusy || this.sessionLoadBusy || this.attachmentBusy || this.modelSwitchBusy || this.applyingProposal.length > 0) { return; }
    if (this.isLoading) {
      this.cancelStream();
    }
    this.sessionLoadRequestId++; this.sessionLoadBusy = false; this.sessionLoadError = '';
    this.loadedSessionId = '';
    this.onNewSession();
    this.pickerOpen = false; this.pickerKeyword = '';
    this.closeComposerMenus(); this.inputText = '';
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
          .fontColor(this.palette().onAccent)
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

        if (msg.streaming !== true) {
          Row({ space: 8 }) {
            if (msg.text && msg.text.length > 0) {
              IconButton({ icon: $r('app.media.ic_copy'), label: '复制回答', onAction: () => this.copyToClipboard(msg.text ?? '') })
            }
            IconButton({ icon: $r('app.media.ic_refresh'), label: msg.error ? '重试请求' : '重新生成回答',
              available: !this.isLoading && !this.applyingProposal, onAction: () => this.regenerateLastResponse() })
          }.margin({ top: 4 })
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
    AssistantText({ text, streaming: isStreamingText, hideActions: true })
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
    Menu() {
      MenuItem({ content: '本地助手 · 离线可用' })
        .selected(this.assistantMode === 'local' || !REMOTE_AI_ENABLED).selectIcon(true)
        .constraintSize({ minHeight: 48 }).onClick(() => this.switchLocalAssistant())
      if (REMOTE_AI_ENABLED && this.profiles.length > 0) {
        MenuItemGroup({ header: '已配置模型' }) {
          ForEach(this.profiles, (p: ModelProfile) => {
            MenuItem({ content: p.label, labelInfo: p.id === this.activeProfileId && this.assistantMode === 'remote' ? '当前' : '' })
              .selected(p.id === this.activeProfileId && this.assistantMode === 'remote').selectIcon(true)
              .constraintSize({ minHeight: 48 }).onClick(() => this.switchActiveProfile(p.id))
          }, (p: ModelProfile) => p.id)
        }
      }
      if (REMOTE_AI_ENABLED && this.isModelReasoningType) {
        MenuItemGroup({ header: '推理强度' }) {
          ForEach(THINKING_BUDGETS.slice(0, 3), (item: ThinkingBudgetPreset, index: number) => {
            MenuItem({ content: index === 0 ? '轻量' : index === 1 ? '均衡' : '深入' })
              .selected(this.getBudgetShortLabel(this.selectedThinkingBudget) === item.label).selectIcon(true)
              .constraintSize({ minHeight: 48 }).onClick(() => {
                this.modelMenuOpen = false;
                if (this.menuActionsAvailable()) { this.selectedThinkingBudget = item.val; }
              })
          }, (item: ThinkingBudgetPreset) => item.key)
        }
      }
      MenuItemGroup({ header: '设置' }) {
        this.menuAction('助手与模型设置', $r('app.media.ic_settings'), () => {
          this.modelMenuOpen = false; this.onOpenModelSettings();
        })
      }
    }.width(this.menuWidth()).fontSize(14).fontColor(this.palette().inkPrimary)
      .backgroundColor(this.palette().surface).enabled(this.menuActionsAvailable())
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
    if (!this.menuActionsAvailable()) { return; }
    this.plusMenuOpen = false;
    this.attachmentBusy = true;
    const request = ++this.attachmentRequestId;
    const sessionId = this.loadedSessionId;
    const activeSessionId = this.activeSessionId;
    try {
      const note = await this.onImportExternal();
      if (!this.alive || request !== this.attachmentRequestId || sessionId !== this.loadedSessionId || activeSessionId !== this.activeSessionId) { return; }
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
      if (!this.alive || request !== this.attachmentRequestId || sessionId !== this.loadedSessionId || activeSessionId !== this.activeSessionId) { return; }
      console.error(`导入外部文件异常: ${JSON.stringify(err)}`);
      promptAction.showToast({ message: '导入外部文件取消或失败' });
    } finally { if (this.alive && request === this.attachmentRequestId) { this.attachmentBusy = false; } }
  }

  private async rewindLastMessage(): Promise<void> {
    if (!this.menuActionsAvailable() || !this.servicesReady) { return; }
    if (!this.loadedSessionId) { promptAction.showToast({ message: '正在保存对话，请稍后重试' }); return; }
    if (this.messages.length === 0) {
      promptAction.showToast({ message: '暂无消息可撤销' });
      return;
    }
    const sessionId = this.loadedSessionId;
    if (!await this.confirmMessageRemoval() || this.loadedSessionId !== sessionId || !this.menuActionsAvailable()) { return; }
    const original = this.messages.slice();
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

  private handleBackRequest(): void {
    if (this.pickerOpen) { this.pickerOpen = false; }
    else if (this.plusMenuOpen) { this.plusMenuOpen = false; }
    else if (this.modelMenuOpen) { this.modelMenuOpen = false; }
    else if (this.conversationMenuOpen) { this.conversationMenuOpen = false; }
    else { this.onNavigateBack(); }
  }

  private async confirmMessageRemoval(): Promise<boolean> {
    try {
      const result = await promptAction.showDialog({ title: '撤回上一轮消息？', message: '删除最近一轮提问与回答，已创建的笔记和待办会保留。',
        buttons: [{ text: '取消', color: this.palette().inkSecondary }, { text: '撤回', color: this.palette().danger }] });
      return result.index === 1;
    } catch { return false; }
  }

  private async clearPinnedReferences(): Promise<void> {
    if (!this.menuActionsAvailable()) { return; }
    this.plusMenuOpen = false;
    const sessionId = this.loadedSessionId;
    const activeSessionId = this.activeSessionId;
    const pinned = this.pinnedNotes;
    try {
      const result = await promptAction.showDialog({ title: '移除全部引用？', message: '原文件和对话会保留。',
        buttons: [{ text: '取消', color: this.palette().inkSecondary }, { text: '移除', color: this.palette().danger }] });
      if (result.index === 1 && sessionId === this.loadedSessionId && activeSessionId === this.activeSessionId && pinned === this.pinnedNotes && this.menuActionsAvailable()) {
        this.pinnedNotes = []; this.onPinnedNotesChange([]); this.emitContext();
      }
    } catch { /* 取消确认 */ }
  }

  @Builder
  menuAction(title: string, icon: Resource, action: () => void, destructive: boolean = false, available: boolean = true) {
    MenuItem({ content: title, startIcon: icon })
      .contentFontColor(destructive ? this.palette().danger : this.palette().inkPrimary)
      .constraintSize({ minHeight: 48 }).enabled(this.menuActionsAvailable() && available)
      .accessibilityText(title).onClick(() => {
        if (this.menuActionsAvailable() && available) { this.closeComposerMenus(); action(); }
      })
  }

  @Builder
  plusActionMenu() {
    Menu() {
      MenuItemGroup({ header: '添加资料' }) {
        this.menuAction('引用库内资料', $r('app.media.ic_note'), () => {
          this.openReferencePicker();
        })
        this.menuAction('导入文件到资料库', $r('app.media.ic_import'), () => this.importExternalFile())
        this.menuAction('识别图片与整理文字', $r('app.media.ic_sparkle'), () => {
          this.plusMenuOpen = false; this.onSmartExtract();
        })
      }
      MenuItemGroup({ header: '离线任务' }) {
        this.menuAction('提取原文要点', $r('app.media.ic_read'), () => this.prepareLocalTask('提取要点'))
        this.menuAction('整理原文明示待办', $r('app.media.ic_check'), () => this.prepareLocalTask('整理待办'))
        this.menuAction('资料库概览', $r('app.media.ic_folder'), () => this.prepareLocalTask('资料概览'))
      }
      MenuItemGroup({ header: this.remoteTaskAvailable() ? '模型任务' : '模型任务 · 需选择已配置并授权的模型' }) {
        this.menuAction('讲解引用资料', $r('app.media.ic_sparkle'), () => this.prepareModelTask('请依据引用资料，解释核心概念并标注原文来源。'), false, this.remoteTaskAvailable())
        this.menuAction('生成自测题', $r('app.media.ic_note'), () => this.prepareModelTask('依据引用资料生成自测题，给出答案与来源。'), false, this.remoteTaskAvailable())
        this.menuAction('比较资料观点', $r('app.media.ic_link'), () => this.prepareModelTask('比较引用资料的观点与证据，区分一致点和差异并给出来源。'), false, this.remoteTaskAvailable())
      }
      if (this.pinnedNotes.length > 0) {
        MenuItemGroup({ header: `已引用 ${this.pinnedNotes.length} 篇资料` }) {
          this.menuAction('移除全部引用', $r('app.media.ic_close'), () => this.clearPinnedReferences())
        }
      }
    }.width(this.menuWidth()).fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surface)
      .enabled(this.menuActionsAvailable())
  }

  @Builder
  conversationActionMenu() {
    Menu() {
      this.menuAction('搜索并引用资料', $r('app.media.ic_search'), () => this.openReferencePicker())
      this.menuAction('助手与模型设置', $r('app.media.ic_settings'), () => { this.conversationMenuOpen = false; this.onOpenModelSettings(); })
      if (this.messages.length > 0) {
        this.menuAction('复制当前对话', $r('app.media.ic_copy'), () => this.copyToClipboard(this.messages.map((m: StoredMessage) => `${m.role === 'user' ? '我' : '墨客'}：${m.text}`).join('\n\n')))
        this.menuAction('重新回答上一问', $r('app.media.ic_redo'), () => { this.conversationMenuOpen = false; this.regenerateLastResponse(); })
        this.menuAction('撤回上一轮消息', $r('app.media.ic_undo'), () => {
          this.conversationMenuOpen = false; this.rewindLastMessage();
        })
        if (this.loadedSessionId) {
          this.menuAction('删除当前对话', $r('app.media.ic_trash'), () => {
            this.conversationMenuOpen = false; this.onDeleteSession(this.loadedSessionId);
          }, true)
        }
      }
    }.width(this.menuWidth()).fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surface)
      .enabled(this.menuActionsAvailable())
  }
  @Builder
  referencePicker() {
    Column({ space: 8 }) {
      Row() {
        Text('搜索并引用资料').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1)
        IconButton({ icon: $r('app.media.ic_close'), label: '关闭资料选择', onAction: () => { this.pickerOpen = false; } })
      }.width('100%')
      TextInput({ text: this.pickerKeyword, placeholder: '课程名、标签或正文关键词' }).height(44)
        .backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary)
        .onChange((v: string) => { this.pickerKeyword = v; })
      List({ space: 4 }) {
        ForEach(this.pickerCandidates(), (n: NoteItem) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 }) {
                AppIcon({ source: $r('app.media.ic_note'), tint: this.palette().inkSecondary })
                Column({ space: 2 }) {
                  Text(n.title).fontSize(14).fontColor(this.palette().inkPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${n.category || '未分类'} · ${n.type}`).fontSize(11).fontColor(this.palette().inkMuted)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text('引用').fontSize(12).fontColor(this.palette().accent)
              }.width('100%')
            }.width('100%').height(52).backgroundColor(this.palette().surfaceSubtle).borderRadius(8)
              .enabled(this.menuActionsAvailable()).accessibilityText(`引用${n.title}`).onClick(() => {
                if (this.menuActionsAvailable()) { this.togglePin(n); }
              })
          }
        }, (n: NoteItem) => n.id)
      }.width('100%').height(this.isPhone ? 140 : 180).scrollBar(BarState.Auto)
      Text(this.pickerCandidates().length ? '显示最多 40 项；扫描 PDF 的正文须先提取并校对。' : '没有匹配资料，可缩短关键词或先导入文件。')
        .fontSize(11).fontColor(this.palette().inkMuted).width('100%')
    }.width('100%').padding(12).borderRadius(12).backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().border })
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Column({ space: 6 }) {
          Row({ space: 12 }) {
            IconButton({ icon: $r('app.media.ic_history'), label: '对话记录', selected: this.historyOpen,
              onAction: () => this.onToggleHistory() })
            Blank().layoutWeight(1)
            IconButton({ icon: $r('app.media.ic_plus'), label: '新建对话',
              available: !this.historyBusy && !this.sessionLoadBusy && !this.attachmentBusy && !this.modelSwitchBusy && !this.applyingProposal,
              onAction: () => this.startNewChat() })
            Button({ type: ButtonType.Normal }) {
              AppIcon({ source: $r('app.media.ic_more'), tint: this.palette().inkSecondary })
            }.width(44).height(44).padding(0).borderRadius(12).backgroundColor(this.conversationMenuOpen ? this.palette().accentSoft : Color.Transparent)
              .enabled(this.menuActionsAvailable()).accessibilityText('对话操作')
              .onClick(() => this.toggleComposerMenu('conversation'))
              .bindMenu(this.conversationMenuOpen, this.conversationActionMenu, {
                placement: Placement.BottomRight, backgroundColor: this.palette().surface,
                onDisappear: () => { this.conversationMenuOpen = false; }
              })
          }.width('100%').height(44)
          if (REMOTE_AI_ENABLED && this.assistantMode === 'remote') {
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
          }
        }.width('100%').padding({ left: this.isPhone ? 12 : 20, right: this.isPhone ? 12 : 20, top: 6, bottom: 6 })
          .backgroundColor(this.palette().surface)
          .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })
      // 2. 消息流与欢迎看板
      if (this.sessionLoadBusy || this.sessionLoadError) {
        Column({ space: 12 }) {
          Text(this.sessionLoadBusy ? '正在读取对话…' : this.sessionLoadError)
            .fontSize(14).fontColor(this.palette().inkSecondary).textAlign(TextAlign.Center)
          if (this.sessionLoadError) {
            Button('重新读取').height(44).type(ButtonType.Normal).borderRadius(10)
              .backgroundColor(this.palette().accentSoft).fontColor(this.palette().accent)
              .onClick(() => this.loadSessionById(this.activeSessionId))
          }
        }.width('100%').layoutWeight(1).padding(24).justifyContent(FlexAlign.Center)
      } else if (this.messages.length === 0 && !this.isLoading) {
        Scroll() {
        Column({ space: 16 }) {
          Image($r('app.media.ic_sparkle')).width(32).height(32).fillColor(this.palette().accent)

          Column({ space: 4 }) {
            Text(this.assistantMode === 'local' || !REMOTE_AI_ENABLED ? '从资料原文开始' : '研读你的资料')
              .fontSize(TypographyTokens.TITLE_SUB)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)
            Text(this.assistantMode === 'local' || !REMOTE_AI_ENABLED ? '离线检索、摘录要点、整理待办。' : '提炼要点、比较观点或准备自测题。')
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
            ForEach(this.assistantMode === 'local' || !REMOTE_AI_ENABLED ? LOCAL_PROMPTS : this.showAllPrompts ? QUICK_PROMPTS : QUICK_PROMPTS.slice(0, 4), (qp: QuickPrompt) => {
              this.quickPromptCard(qp)
            }, (qp: QuickPrompt) => qp.title)
          }
          .constraintSize({ maxWidth: 560 })
          .width('100%')
          .padding({ left: 16, right: 16 })
          if (REMOTE_AI_ENABLED && this.assistantMode === 'remote') {
          Button(this.showAllPrompts ? '收起更多用法' : '更多用法').height(44).fontSize(12).type(ButtonType.Normal)
            .backgroundColor(Color.Transparent).fontColor(this.palette().inkSecondary).onClick(() => { this.showAllPrompts = !this.showAllPrompts; })
          }
          if (!this.modelReady) {
            Button('配置模型或使用本地助手').height(44).fontSize(13).type(ButtonType.Normal).borderRadius(8)
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
        if (this.pickerOpen) { this.referencePicker() }
        if (this.pinnedNotes.length > 0) {
          Row({ space: 8 }) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.pinnedNotes, (n: NoteItem) => {
                  Row({ space: 4 }) {
                    Text(n.title).fontSize(12).fontColor(this.palette().inkPrimary).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 130 })
                    IconButton({ icon: $r('app.media.ic_close'), label: `移除引用资料：${n.title}`,
                      available: this.menuActionsAvailable(), onAction: () => {
                        this.pinnedNotes = this.pinnedNotes.filter((p: NoteItem) => p.id !== n.id);
                        this.onPinnedNotesChange(this.pinnedNotes); this.emitContext();
                      } })
                  }.padding({ left: 10 }).borderRadius(8).backgroundColor(this.palette().accentSoft)
                }, (n: NoteItem) => `cockpit-pin-${n.id}`)
              }
            }.layoutWeight(1).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
          }.width('100%')
        }
        Column({ space: 4 }) {
          TextArea({ text: this.inputText, placeholder: '提问，或添加资料后让 AI 整理…' })
            .height(this.isPhone ? 80 : 88).width('100%').fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkPrimary).placeholderColor(this.palette().inkMuted)
            .backgroundColor(Color.Transparent).onChange((v: string) => { this.inputText = v; })
          Row({ space: 8 }) {
            Button({ type: ButtonType.Normal }) {
              AppIcon({ source: $r('app.media.ic_plus'), tint: this.palette().inkSecondary })
            }.width(44).height(44).padding(0).borderRadius(12).backgroundColor(this.plusMenuOpen ? this.palette().accentSoft : Color.Transparent)
              .enabled(this.menuActionsAvailable()).accessibilityText('添加资料与任务')
              .onClick(() => this.toggleComposerMenu('plus'))
              .bindMenu(this.plusMenuOpen, this.plusActionMenu, {
                placement: Placement.TopLeft, backgroundColor: this.palette().surface,
                onDisappear: () => { this.plusMenuOpen = false; }
              })
            Button({ type: ButtonType.Normal }) {
              Row({ space: 6 }) {
                Text(this.modelSwitchBusy ? '切换中…' : this.assistantMode === 'local' ? '选择模型' : this.modelLabel || '选择模型')
                  .fontSize(12).fontColor(this.palette().inkSecondary).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                AppIcon({ source: $r('app.media.ic_chevron_down'), tint: this.palette().inkSecondary, iconSize: 16 })
              }.width('100%')
            }.layoutWeight(1).height(44).padding({ left: 8, right: 8 }).borderRadius(8)
              .backgroundColor(this.modelMenuOpen ? this.palette().accentSoft : Color.Transparent)
              .enabled(this.menuActionsAvailable()).accessibilityText(`选择助手与模型，当前${this.modelLabel}`)
              .onClick(() => this.toggleComposerMenu('model'))
              .bindMenu(this.modelMenuOpen, this.modelSelectMenu, {
                placement: Placement.TopRight, backgroundColor: this.palette().surface,
                onDisappear: () => { this.modelMenuOpen = false; }
              })
            if (this.isLoading) {
              IconButton({ icon: $r('app.media.ic_stop'), label: '停止生成', destructive: true, onAction: () => this.cancelStream() })
            } else {
              IconButton({ icon: $r('app.media.ic_send'), label: '发送提问', selected: true,
                available: this.inputText.trim().length > 0 && this.menuActionsAvailable(), onAction: () => this.sendMessage() })
            }
          }.width('100%')
          if (this.attachmentBusy) {
            Text('正在导入资料…').fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
          }
        }.width('100%').padding(10).borderRadius(14).backgroundColor(this.palette().surface)
          .border({ width: 1, color: this.palette().border })
      }.width('100%').constraintSize({ maxWidth: 800 }).alignSelf(ItemAlign.Center)
        .padding({ left: this.isPhone ? 12 : 20, right: this.isPhone ? 12 : 20, bottom: this.isPhone ? 12 : 16, top: 6 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)

  }
  .width('100%')
  .height('100%')
  .onAreaChange((_old: Area, area: Area) => { this.workspaceWidth = Math.max(160, Number(area.width)); })
}
}

