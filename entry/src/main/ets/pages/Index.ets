import { AnimationTokens } from '../common/constants/DesignTokens';
/**
 * 墨语 (FlowMind) 顶层装配器
 *
 * 持有全局状态、导航和现有工作区操作，装配 AppShell 与 views/ 下的组件。
 * 阅读器保存、学习资料恢复逐步下沉到独立用例服务；其余业务操作仍在迁移中。
 *
 * 布局、样式与响应式决策一律下沉到 views/，此处不再出现大段 UI 构建代码。
 */
import { common } from '@kit.AbilityKit';
import { curves, promptAction } from '@kit.ArkUI';
import { NoteItem } from '../common/types/NoteItem';
import { ReaderSaveKind } from '../common/types/ReaderSaveKind';
import { SpaceFolder } from '../common/types/SpaceFolder';
import { LinkGraph, Backlink, UnresolvedLink } from '../common/types/LinkGraph';
import { MarkdownOutlineItem } from '../common/types/MarkdownOutlineItem';
import { WorkspaceStats } from '../common/types/WorkspaceStats';
import { DocumentTransferResult, MarkdownDocument } from '../common/types/MarkdownDocument';
import { TodoItem, DayNote } from '../common/types/TodoItem';
import { ChatSession } from '../common/types/ChatSession';
import { ChatCitation } from '../common/types/ChatSession';
import {
  CATEGORY_UNFILED,
  FILTER_ALL,
  NAV_AI,
  NAV_CANVAS,
  NAV_FAVORITE,
  NAV_GRAPH,
  NAV_HOME,
  NAV_LIBRARY,
  NAV_TODO,
  NAV_TRASH,
  SAVE_IDLE,
  SAVE_SAVING,
  SAVE_FAILED,
  TRASH_RETENTION_DAYS
} from '../common/constants/WorkspaceConstants';
import { NoteStorageService } from '../services/NoteStorageService';
import { NoteCoverService } from '../services/NoteCoverService';
import { NoteSearchService } from '../services/NoteSearchService';
import { TodoStorageService } from '../services/TodoStorageService';
import { ChatSessionService } from '../services/ai/ChatSessionService';
import { ModelConfigService } from '../services/ai/ModelConfigService';
import { buildSpaces } from '../services/WorkspaceBuilder';
import { defaultProjects, seedNotes, templateBody } from '../common/seed/SeedContent';
import { AppShell } from '../views/layout/AppShell';
import { SIDEBAR_MODE_SESSIONS, SIDEBAR_MODE_TREE } from '../views/layout/Sidebar';
import { HomeWorkspace } from '../views/workspace/HomeWorkspace';
import { LibraryWorkspace } from '../views/workspace/LibraryWorkspace';
import { GraphWorkspace } from '../views/workspace/GraphWorkspace';
import { HandwritingCanvas } from '../views/reader/HandwritingCanvas';
import { AiWorkspace } from '../views/ai/AiWorkspace';
import { AiSourcesPanel } from '../views/ai/AiSourcesPanel';
import { TodoWorkspace } from '../views/workspace/TodoWorkspace';
import { TrashWorkspace } from '../views/workspace/TrashWorkspace';
import { FavoriteWorkspace } from '../views/workspace/FavoriteWorkspace';
import { ReaderWorkspace } from '../views/reader/ReaderWorkspace';
import { HuaweiDocWorkspace } from '../views/reader/huawei/HuaweiDocWorkspace';
import { ContextDrawer, CONTEXT_TAB_OUTLINE } from '../views/context/ContextDrawer';
import { QuickSearchDialog } from '../views/explore/QuickSearchDialog';
import { AppearanceSheet } from '../views/settings/AppearanceSheet';
import { ModelSettingsSheet } from '../views/settings/ModelSettingsSheet';
import { NewProjectSheet } from '../views/layout/sheets/NewProjectSheet';
import { CreateNoteSheet } from '../views/layout/sheets/CreateNoteSheet';
import { ProjectMenuSheet } from '../views/layout/sheets/ProjectMenuSheet';
import { NewContentSheet } from '../views/layout/sheets/NewContentSheet';
import { RenameProjectSheet } from '../views/layout/sheets/RenameProjectSheet';
import { NoteMenuSheet } from '../views/layout/sheets/NoteMenuSheet';
import { RenameNoteSheet } from '../views/layout/sheets/RenameNoteSheet';
import { MoveNoteSheet } from '../views/layout/sheets/MoveNoteSheet';
import { NameNoteSheet } from '../views/layout/sheets/NameNoteSheet';
import { SmartExtractSheet } from '../views/layout/sheets/SmartExtractSheet';
import { NoteCoverSheet } from '../views/layout/sheets/NoteCoverSheet';
import { SmartContent } from '../common/types/SmartContent';
import { SmartTask } from '../common/types/SmartTask';
import { SmartCaptureService, SmartCaptureStorage } from '../services/smart/SmartCaptureService';
import { ReviewCard, PdfTextPage } from '../common/types/StudyTypes';
import { ReviewStorageService } from '../services/study/ReviewStorageService';
import { ReviewPolicy } from '../services/study/ReviewPolicy';
import { StudySourceService } from '../services/study/StudySourceService';
import { StudySheet } from '../views/study/StudySheet';
import { PdfTextSheet } from '../views/study/PdfTextSheet';
import { StudyBackupSheet } from '../views/study/StudyBackupSheet';
import { StudyRestoreService } from '../services/study/StudyRestoreService';
import { ReaderCommitService } from '../services/document/ReaderCommitService';
import { PrivacySheet } from '../views/settings/PrivacySheet';
import { PrivacyNoticeService } from '../services/PrivacyNoticeService';

/** 命名弹层待提交的「新建笔记」意图。projectName 为空表示落在当前空间（全局新建）。 */
interface PendingNoteCreate {
  projectName: string;
  type: string;
  defaultName: string;
}

const EMPTY_NOTE: NoteItem = {
  id: '',
  title: '',
  category: '',
  type: '',
  previewText: '',
  tag: '',
  tagColor: '',
  updateTime: '',
  contentDetail: ''
};

const EMPTY_GRAPH: LinkGraph = { backlinks: [], unresolvedLinks: [] };

const EMPTY_STATS: WorkspaceStats = { noteCount: 0, linkCount: 0, unresolvedCount: 0, tagCount: 0 };

@Entry
@Component
struct Index {
  // ---- 导航与布局 ----
  @State activeNav: string = NAV_HOME;
  @State activeSpaceId: string = '';
  @State activeNoteId: string = '';
  @State sidebarCollapsed: boolean = false;
  @State contextPanelOpen: boolean = true;
  @State contextTab: string = CONTEXT_TAB_OUTLINE;

  // ---- 资料库筛选 ----
  @State searchText: string = '';
  @State activeFilter: string = FILTER_ALL;

  // ---- 本地数据 ----
  @State customProjects: SpaceFolder[] = defaultProjects();
  @State spaces: SpaceFolder[] = [];
  @State notes: NoteItem[] = [];
  @State trash: NoteItem[] = [];
  @State linkGraph: LinkGraph = EMPTY_GRAPH;
  @State stats: WorkspaceStats = EMPTY_STATS;

  // ---- 待办日历 ----
  @State todos: TodoItem[] = [];
  @State dayNotes: DayNote[] = [];

  // ---- AI 会话（列表由 Index 持有，侧栏与工作台共用） ----
  @State sessions: ChatSession[] = [];
  @State activeSessionId: string = '';
  @State sidebarMode: string = SIDEBAR_MODE_TREE;
  /** AI 墨客右栏「来源与上下文」由工作台上报 */
  @State aiCitations: ChatCitation[] = [];
  @State aiPinnedNotes: NoteItem[] = [];
  @State aiLayerLabel: string = '';
  @State aiModelLabel: string = '';
  @State aiToolsEnabled: boolean = true;
  @State aiPrefilledPrompt: string = '';

  // ---- 研读态 (速记与 Markdown 随笔) ----
  @State readingOpen: boolean = false;
  @State readingNote: NoteItem = EMPTY_NOTE;
  @State annotationPaneOpen: boolean = false;
  @State saveState: string = SAVE_IDLE;
  @State outlineItems: MarkdownOutlineItem[] = [];
  @State jumpToken: number = 0;
  @State jumpLine: number = -1;

  // ---- 独立全屏文档态 (PDF / 试卷 / 稿纸手写) ----
  @State fullScreenDocOpen: boolean = false;
  @State fullScreenDocNote: NoteItem = EMPTY_NOTE;

  // ---- 全局浮层 ----
  @State searchVisible: boolean = false;
  @State settingsVisible: boolean = false;
  @State smartExtractVisible: boolean = false;
  @State smartExtractCloseToken: number = 0;
  @State coverNoteId: string = '';
  @State coverCloseToken: number = 0;
  @State modelCloseToken: number = 0;
  @State documentBackToken: number = 0;
  @State reviewCards: ReviewCard[] = [];
  @State studyVisible: boolean = false;
  @State studyCourse: string = '';
  @State studyCloseToken: number = 0;
  @State backupVisible: boolean = false;
  @State backupCloseToken: number = 0;
  @State privacyVisible: boolean = false;
  @State privacyWelcome: boolean = true;
  @State privacySaving: boolean = false;
  private privacyNotice: PrivacyNoticeService = new PrivacyNoticeService();
  @State pdfExtractNoteId: string = '';
  @State pdfExtractPage: number = 1;
  @State pdfExtractCloseToken: number = 0;
  @State sourcePage: number = 1;
  @State sourceJumpToken: number = 0;
  private reviewStorage: ReviewStorageService = new ReviewStorageService();
  @StorageProp('flowmindSingleColumn') singleColumn: boolean = false;
  /** 新建笔记的命名弹层意图；非空即显示 NameNoteSheet。 */
  @State pendingCreate: PendingNoteCreate | null = null;
  @State toastVisible: boolean = false;
  @State toastMessage: string = '';
  /** 当前 Toast 是否附带「撤销」按钮 */
  @State undoVisible: boolean = false;
  /** 新建笔记对话框（记随笔） */
  @State createNoteOpen: boolean = false;
  /** 新建项目对话框 */
  @State createProjectOpen: boolean = false;
  /** 底部弹层类型：'project_menu' | 'new_content' | 'rename_project' | 'note_menu' | 'rename_note' | 'move_note' */
  @State activeSheet: string = '';
  @State sheetProject: SpaceFolder | null = null;
  @State sheetNote: NoteItem | null = null;

  private storage: NoteStorageService = new NoteStorageService();
  private readerCommits: ReaderCommitService = new ReaderCommitService();
  private searchService: NoteSearchService = new NoteSearchService();
  private todoStorage: TodoStorageService = new TodoStorageService();
  private chatStorage: ChatSessionService = ChatSessionService.getInstance();
  private toastTimer: number = -1;
  private bootstrapped: boolean = false;

  /**
   * 最近一次可撤销的删除操作。删除是本地即刻生效、且会连带清掉沙箱 .md 的破坏性动作，
   * 只有确认弹窗而没有后悔药的话，用户误触一次就永久丢数据。这里保留一个短时句柄，
   * 由 Toast 上的「撤销」按钮触发还原；Toast 消失时句柄一并失效。
   */
  private undoAction: (() => void) | null = null;
  private appContext: common.UIAbilityContext | null = null;

  private getAbilityContext(): common.UIAbilityContext {
    if (this.appContext !== null) {
      return this.appContext;
    }
    this.appContext = getContext(this) as common.UIAbilityContext;
    return this.appContext;
  }

  private dismissNavigationOverlay(): void {
    if (this.singleColumn) { this.sidebarCollapsed = true; this.contextPanelOpen = false; }
  }

  onBackPress(): boolean {
    if (this.privacyWelcome) { this.getAbilityContext().terminateSelf(); return true; }
    if (this.privacyVisible) { this.privacyVisible = false; return true; }
    if (this.backupVisible) { this.backupCloseToken++; return true; }
    if (this.studyVisible) { this.studyCloseToken++; return true; }
    if (this.pdfExtractNoteId) { this.pdfExtractCloseToken++; return true; }
    if (this.coverNoteId.length > 0) { this.coverCloseToken++; return true; }
    if (this.activeSheet === 'model_settings') { this.modelCloseToken++; return true; }
    if (this.activeSheet.length > 0) { this.activeSheet = ''; return true; }
    if (this.createProjectOpen) { this.createProjectOpen = false; return true; }
    if (this.pendingCreate !== null) { this.pendingCreate = null; return true; }
    if (this.smartExtractVisible) { this.smartExtractCloseToken++; return true; }
    if (this.settingsVisible) { this.settingsVisible = false; return true; }
    if (this.searchVisible) { this.searchVisible = false; return true; }
    if (this.fullScreenDocOpen) { this.documentBackToken++; return true; }
    if (this.singleColumn && this.contextPanelOpen) { this.contextPanelOpen = false; return true; }
    if (this.singleColumn && !this.sidebarCollapsed) { this.sidebarCollapsed = true; return true; }
    if (this.readingOpen) { this.closeReading(); return true; }
    if (this.activeNav !== NAV_HOME) { this.activeNav = NAV_HOME; this.activeSpaceId = ''; return true; }
    return false;
  }

  private closeReading(): void {
    if (this.saveState === SAVE_SAVING || this.saveState === SAVE_FAILED) {
      this.notify(this.saveState === SAVE_SAVING ? '正在保存，请稍候再返回' : '保存失败，请先重试保存');
      return;
    }
    this.readingOpen = false;
    this.activeNoteId = '';
    this.outlineItems = [];
  }

  aboutToAppear(): void {
    if (!this.bootstrapped) {
      this.bootstrapped = true;
      this.bootstrap();
    }
  }

  // ==================================================================
  // 启动与本地数据
  // ==================================================================

  private async bootstrap(): Promise<void> {
    const context: common.UIAbilityContext = this.getAbilityContext();
    try { this.privacyWelcome = !await this.privacyNotice.shown(context); }
    catch { this.privacyWelcome = true; }
    try {
      const loaded: NoteItem[] = await this.storage.load(context, seedNotes());
      this.notes = loaded;
    } catch (error) {
      console.error(`本地笔记加载失败: ${JSON.stringify(error)}`);
      this.notes = [];
      this.notify('本地笔记读取失败，原数据已保留，请检查存储后重试');
    }
    // 恢复用户自建项目。此前 customProjects 只存在于内存，重启即丢，
    // 表现为「建完项目再打开就没了」。首次运行没有快照时回退到默认项目。
    try {
      const savedProjects: SpaceFolder[] | null = await this.storage.loadProjects(context);
      this.customProjects = savedProjects !== null ? savedProjects : defaultProjects();
    } catch (error) {
      console.error(`项目列表加载失败: ${JSON.stringify(error)}`);
      this.customProjects = defaultProjects();
    }
    this.backfillNoteMeta();
    this.rebuildSpaces();
    this.activeSpaceId = '';
    this.persistSnapshot();
    this.refreshGraph();
    await this.loadTrash(context);
    await this.loadTodos(context);
    await this.loadSessions(context);
    try { this.reviewCards = await this.reviewStorage.load(context); }
    catch { this.notify('复习记录读取失败，原数据已保留'); }
    // 模型配置也在这里初始化：AI 视图自行取 Context 有竞态，
    // 由持有 Context 的 Index 统一初始化，视图侧只读单例。
    try {
      await ModelConfigService.getInstance().init(context);
    } catch (error) {
      console.error(`模型配置初始化失败: ${JSON.stringify(error)}`);
    }
  }

  // ==================================================================
  // AI 会话（侧栏「对话」模式 + AI 墨客工作台共用同一份列表）
  // ==================================================================

  /** 置顶优先、其次按更新时间倒序 */
  private sortSessions(list: ChatSession[]): ChatSession[] {
    const next: ChatSession[] = list.slice();
    next.sort((a: ChatSession, b: ChatSession) => {
      if (a.pinned !== b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.updatedAt - a.updatedAt;
    });
    return next;
  }

  /** AiWorkspace 新建或更新会话后回写列表，并同步 activeSessionId */
  private handleSessionSaved(session: ChatSession): void {
    let replaced: boolean = false;
    const next: ChatSession[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === session.id) {
        next.push(session);
        replaced = true;
      } else {
        next.push(this.sessions[i]);
      }
    }
    if (!replaced) {
      next.unshift(session);
    }
    this.sessions = this.sortSessions(next);
    this.activeSessionId = session.id;
  }

  private handleSelectSession(session: ChatSession): void {
    this.dismissNavigationOverlay();
    if (!session || !session.id) {
      return;
    }
    this.activeNav = NAV_AI;
    this.readingOpen = false;
    this.fullScreenDocOpen = false;
    this.activeNoteId = '';
    this.activeSessionId = session.id;
  }

  private handleNewSession(): void {
    this.dismissNavigationOverlay();
    this.activeNav = NAV_AI;
    this.readingOpen = false;
    this.fullScreenDocOpen = false;
    this.activeSessionId = '';
  }

  private async handleDeleteSession(sessionId: string): Promise<void> {
    try {
      await this.chatStorage.deleteSession(sessionId);
    } catch (error) {
      console.error(`会话删除失败: ${JSON.stringify(error)}`);
      this.notify('会话删除失败');
      return;
    }
    this.sessions = this.sessions.filter((s: ChatSession) => s.id !== sessionId);
    if (this.activeSessionId === sessionId) {
      this.activeSessionId = '';
    }
    this.notify('已删除对话');
  }

  private async handleTogglePinSession(session: ChatSession): Promise<void> {
    const next: ChatSession[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const s: ChatSession = this.sessions[i];
      if (s.id === session.id) {
        const toggled: ChatSession = {
          id: s.id,
          title: s.title,
          pinned: !s.pinned,
          agentMode: s.agentMode,
          messages: s.messages,
          createdAt: s.createdAt,
          updatedAt: s.updatedAt
        };
        next.push(toggled);
      } else {
        next.push(s);
      }
    }
    this.sessions = this.sortSessions(next);
    try {
      await this.chatStorage.saveSessions(this.sessions);
    } catch (error) {
      console.error(`会话置顶保存失败: ${JSON.stringify(error)}`);
    }
  }

  /** 载入 AI 会话列表（侧栏「对话」模式的唯一数据源） */
  private async loadSessions(context: common.UIAbilityContext): Promise<void> {
    try {
      await this.chatStorage.init(context);
      this.sessions = await this.chatStorage.loadSessions();
    } catch (error) {
      console.error(`会话列表加载失败: ${JSON.stringify(error)}`);
      this.sessions = [];
    }
  }

  /**
   * 为旧数据回填功能6/11 所需的元信息：
   * tags 从单值 tag 派生；createdAt/updatedAt 用「按现有顺序倒推的分钟数」填充，
   * 这样排序后的顺序与既有 seed 顺序一致，不会打乱用户熟悉的列表。
   */
  private backfillNoteMeta(): void {
    const base: number = Date.now();
    let changed: boolean = false;
    for (let i = 0; i < this.notes.length; i++) {
      const n: NoteItem = this.notes[i];
      if (n.updatedAt === undefined) {
        n.updatedAt = base - i * 60000;
        changed = true;
      }
      if (n.createdAt === undefined) {
        n.createdAt = n.updatedAt;
        changed = true;
      }
      if (n.tags === undefined) {
        n.tags = n.tag.length > 0 ? [n.tag] : [];
        changed = true;
      }
    }
    if (changed) {
      this.notes = this.notes.slice();
    }
  }

  /**
   * 载入回收站，并自动彻底删除已超过保留期的笔记。
   * 超期判定以 deletedAt 为准；缺失 deletedAt 的异常条目按「刚删除」处理，不误删。
   */
  private async loadTrash(context: common.UIAbilityContext): Promise<void> {
    try {
      const stored: NoteItem[] = await this.storage.loadTrash(context);
      const now: number = Date.now();
      const keep: NoteItem[] = [];
      const expired: NoteItem[] = [];
      for (let i = 0; i < stored.length; i++) {
        const rawDeletedAt: number | undefined = stored[i].deletedAt;
        const deletedAt: number = rawDeletedAt === undefined ? now : rawDeletedAt;
        const ageDays: number = (now - deletedAt) / (24 * 60 * 60 * 1000);
        if (ageDays > TRASH_RETENTION_DAYS) {
          expired.push(stored[i]);
        } else {
          keep.push(stored[i]);
        }
      }
      for (let i = 0; i < expired.length; i++) {
        try {
          await this.storage.delete(context, expired[i].id, expired[i].sourceUri || '', expired[i].coverUrl || '');
        } catch (error) {
          keep.push(expired[i]);
          console.error(`超期笔记文件清理失败 (${expired[i].id}): ${JSON.stringify(error)}`);
        }
      }
      this.trash = keep;
      if (expired.length > 0) {
        await this.persistTrash();
      }
    } catch (error) {
      console.error(`回收站加载失败: ${JSON.stringify(error)}`);
      this.trash = [];
    }
  }

  /** 载入待办与日期备忘（各自独立于笔记快照存储） */
  private async loadTodos(context: common.UIAbilityContext): Promise<void> {
    try {
      this.todos = await this.todoStorage.loadTodos(context);
      this.dayNotes = await this.todoStorage.loadDayNotes(context);
    } catch (error) {
      console.error(`待办数据加载失败: ${JSON.stringify(error)}`);
      this.todos = [];
      this.dayNotes = [];
    }
  }

  /** 把项目列表落盘。所有增删改项目的操作都必须调它，否则重启即丢。 */
  private async persistProjects(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      await this.storage.saveProjects(context, this.customProjects);
    } catch (error) {
      console.error(`项目列表保存失败: ${JSON.stringify(error)}`);
      this.notify('项目列表保存失败');
    }
  }

  /**
   * 补入本机还没有的示例数据，已存在的笔记一律不动。
   *
   * 存在的意义：示例里包含 PDF 与 Doc 类型的笔记，是进入「原盘批注」PDF 阅读器的
   * 唯一入口（导入 PDF 要走系统文件选择器）。老设备的笔记快照往往早于这些示例，
   * 而 load() 只在快照缺失时才灌种子，所以它们永远补不进来。这里给一个显式入口。
   */
  private async loadSeedData(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const seeds: NoteItem[] = seedNotes();
    const existing: Set<string> = new Set();
    for (let i = 0; i < this.notes.length; i++) {
      existing.add(this.notes[i].id);
    }
    const missing: NoteItem[] = [];
    for (let i = 0; i < seeds.length; i++) {
      if (!existing.has(seeds[i].id)) {
        missing.push(seeds[i]);
      }
    }
    if (missing.length === 0) {
      this.notify('示例数据已全部存在');
      return;
    }
    this.notes = this.notes.concat(missing);
    await this.persistSnapshot();
    // 新补入的笔记需要把正文真正落到沙箱，否则只有元数据没有 .md
    try {
      await this.storage.reconcileFiles(this.notes);
    } catch (error) {
      console.error(`示例数据落盘失败: ${JSON.stringify(error)}`);
    }
    this.rebuildSpaces();
    this.refreshGraph();
    this.notify(`已补入 ${missing.length} 篇示例数据`);
  }


  /**
   * 重建侧边栏项目树。
   * 任何改动「笔记归类」或「项目列表」的操作都必须走这里，
   * 否则侧边栏会停留在上一帧的树，表现为新建的资料不出现。
   */
  private rebuildSpaces(): void {
    this.spaces = buildSpaces(this.notes, this.customProjects, this.spaces);
  }

  private async persistSnapshot(): Promise<void> {
    try {
      await this.storage.save(this.notes);
    } catch (error) {
      console.error(`笔记元数据保存失败: ${JSON.stringify(error)}`);
      this.notify('笔记元数据保存失败');
    }
  }

  private async refreshGraph(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      this.linkGraph = await this.searchService.buildLinkGraph(context, this.notes);
    } catch (error) {
      console.error(`双链图谱构建失败: ${JSON.stringify(error)}`);
      this.linkGraph = EMPTY_GRAPH;
    }
    this.refreshStats();
  }

  private refreshStats(): void {
    const tags: Set<string> = new Set();
    for (let i = 0; i < this.notes.length; i++) {
      const note: NoteItem = this.notes[i];
      const list: string[] = note.tags !== undefined ? note.tags : (note.tag.length > 0 ? [note.tag] : []);
      for (let j = 0; j < list.length; j++) {
        if (list[j].length > 0) {
          tags.add(list[j]);
        }
      }
    }
    this.stats = {
      noteCount: this.notes.length,
      linkCount: this.linkGraph.backlinks.length,
      unresolvedCount: this.linkGraph.unresolvedLinks.length,
      tagCount: tags.size
    };
  }

  // ==================================================================
  // 派生数据
  // ==================================================================

  private filteredNotes(): NoteItem[] {
    const keyword: string = this.searchText.trim().toLowerCase();
    const spaceName: string = this.activeSpaceName();
    const result: NoteItem[] = [];
    for (let i = 0; i < this.notes.length; i++) {
      const note: NoteItem = this.notes[i];
      if (this.activeFilter !== FILTER_ALL && note.type !== this.activeFilter) {
        continue;
      }
      if (spaceName.length > 0 && note.category !== spaceName) {
        continue;
      }
      if (keyword.length > 0) {
        const hit: boolean = note.title.toLowerCase().includes(keyword)
          || note.previewText.toLowerCase().includes(keyword)
          || note.tag.toLowerCase().includes(keyword);
        if (!hit) {
          continue;
        }
      }
      result.push(note);
    }
    return result;
  }

  private activeSpaceName(): string {
    for (let i = 0; i < this.spaces.length; i++) {
      if (this.spaces[i].id === this.activeSpaceId) {
        return this.spaces[i].name;
      }
    }
    return '';
  }

  private currentBacklinks(): Backlink[] {
    if (!this.readingOpen) {
      return [];
    }
    const result: Backlink[] = [];
    for (let i = 0; i < this.linkGraph.backlinks.length; i++) {
      if (this.linkGraph.backlinks[i].targetNoteId === this.readingNote.id) {
        result.push(this.linkGraph.backlinks[i]);
      }
    }
    return result;
  }

  private currentUnresolved(): UnresolvedLink[] {
    if (!this.readingOpen) {
      return [];
    }
    const result: UnresolvedLink[] = [];
    for (let i = 0; i < this.linkGraph.unresolvedLinks.length; i++) {
      if (this.linkGraph.unresolvedLinks[i].sourceNoteId === this.readingNote.id) {
        result.push(this.linkGraph.unresolvedLinks[i]);
      }
    }
    return result;
  }

  private breadcrumb(): string[] {
    if (this.readingOpen || this.fullScreenDocOpen) {
      const note = this.fullScreenDocOpen ? this.fullScreenDocNote : this.readingNote;
      const category: string = note.category.length === 0 ? '未分类' : note.category;
      return [category, note.title];
    }
    return [this.activeNav];
  }

  /** Persist the image and metadata before publishing a changed cover. */
  private async updateNoteCover(noteId: string, uri: string): Promise<void> {
    const note = this.notes.find((item: NoteItem) => item.id === noteId);
    if (!note) { throw new Error('笔记已被移走，请重新打开'); }
    const context = this.getAbilityContext();
    const source = await NoteCoverService.prepare(context, noteId, uri);
    const previous = note.coverUrl || '';
    const updated = JSON.parse(JSON.stringify(note)) as NoteItem;
    updated.coverUrl = source;
    updated.updatedAt = Date.now(); updated.updateTime = '刚刚';
    const next = this.notes.map((item: NoteItem) => item.id === noteId ? updated : item);
    try { await this.storage.save(next); } catch {
      if (source !== previous) { await NoteCoverService.removeManaged(context, source); }
      throw new Error('封面未能保存，请重试');
    }
    this.notes = next;
    this.rebuildSpaces();
    if (this.readingNote.id === noteId) { this.readingNote = updated; }
    if (this.fullScreenDocNote.id === noteId) { this.fullScreenDocNote = updated; }
    if (source !== previous && !this.notes.concat(this.trash).some((item: NoteItem) => item.coverUrl === previous)) {
      try { await NoteCoverService.removeManaged(context, previous); } catch { console.warn('旧封面清理失败'); }
    }
    this.notify(source.length > 0 ? '封面已保存' : '封面已移除');
  }

  closeSheet(): void {
    animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
      this.activeSheet = '';
      this.sheetProject = null;
      this.sheetNote = null;
    });
  }

  @Builder
  activeSheetContent() {
    if (this.activeSheet === 'project_menu' && this.sheetProject !== null) {
      ProjectMenuSheet({
        project: this.sheetProject,
        onClose: () => this.closeSheet(),
        onCreateNoteInProject: (title: string, projectName: string, type: string) => {
          this.closeSheet();
          this.createNoteInProject(title, projectName, type);
        },
        onRequestRename: (project: SpaceFolder) => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.sheetProject = project;
            this.activeSheet = 'rename_project';
          });
        },
        onDeleteProject: (name: string) => {
          this.closeSheet();
          this.deleteProject(name);
        }
      })
    } else if (this.activeSheet === 'new_content' && this.sheetProject !== null) {
      NewContentSheet({
        project: this.sheetProject,
        onClose: () => this.closeSheet(),
        onCreateNoteInProject: (title: string, projectName: string, type: string) => {
          this.closeSheet();
          this.createNoteInProject(title, projectName, type);
        },
        onImportIntoProject: (projectName: string) => {
          this.closeSheet();
          this.importDocument(projectName);
        }
      })
    } else if (this.activeSheet === 'rename_project' && this.sheetProject !== null) {
      RenameProjectSheet({
        project: this.sheetProject,
        onClose: () => this.closeSheet(),
        onRenameProject: (oldName: string, newName: string) => {
          this.renameProject(oldName, newName);
        }
      })
    } else if (this.activeSheet === 'note_menu' && this.sheetNote !== null) {
      NoteMenuSheet({
        note: this.sheetNote,
        onClose: () => this.closeSheet(),
        onOpenNote: (note: NoteItem) => {
          this.openNote(note);
          this.closeSheet();
        },
        onDeleteNote: (noteId: string) => {
          this.closeSheet();
          this.deleteNote(noteId);
        },
        onRequestRename: (note: NoteItem) => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.sheetNote = note;
            this.activeSheet = 'rename_note';
          });
        },
        onRequestMove: (note: NoteItem) => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.sheetNote = note;
            this.activeSheet = 'move_note';
          });
        }
      })
    } else if (this.activeSheet === 'rename_note' && this.sheetNote !== null) {
      RenameNoteSheet({
        note: this.sheetNote,
        onClose: () => this.closeSheet(),
        onRenameNote: (note: NoteItem, newTitle: string) => {
          this.commitRename(note, newTitle);
        }
      })
    } else if (this.activeSheet === 'move_note' && this.sheetNote !== null) {
      MoveNoteSheet({
        note: this.sheetNote,
        categories: this.spaces.map((s: SpaceFolder) => s.name),
        onClose: () => this.closeSheet(),
        onMoveNote: (note: NoteItem, category: string) => {
          this.commitMove(note, category);
        }
      })
    } else if (this.activeSheet === 'model_settings') {
      ModelSettingsSheet({
        closeToken: this.modelCloseToken,
        onClose: () => this.closeSheet()
      })
    }
  }

  /** 点击面包屑：分类段 → 回到资料库并按分类筛选；标题段 → 打开文档切换搜索 */
  private onBreadcrumbClick(index: number, segment: string): void {
    if (this.readingOpen || this.fullScreenDocOpen) {
      if (index === 0) {
        // 点击分类名：关闭当前文档，回到资料库并选中该项目
        this.readingOpen = false;
        this.fullScreenDocOpen = false;
        this.activeNoteId = '';
        this.activeNav = NAV_LIBRARY;
        // 尝试选中对应项目
        for (let i = 0; i < this.spaces.length; i++) {
          if (this.spaces[i].name === segment) {
            this.activeSpaceId = this.spaces[i].id;
            break;
          }
        }
      } else {
        // 点击文档标题：打开快速搜索以便切换文档
        this.searchVisible = true;
      }
    }
  }

  // ==================================================================
  // 交互
  // ==================================================================

  private notify(message: string): void {
    this.clearUndo();
    this.showToast(message, 2000);
    try {
      promptAction.showToast({ message: message, duration: 1500 });
    } catch (error) {
      // 预览器不支持系统 Toast 时忽略
    }
  }

  /**
   * 删除类操作专用的提示：在 Toast 上挂一个「撤销」按钮，并延长停留时间。
   * @param message 提示文案
   * @param undo 点「撤销」时执行的回滚动作
   */
  private notifyUndoable(message: string, undo: () => void): void {
    this.clearUndo();
    this.undoAction = undo;
    this.undoVisible = true;
    this.showToast(message, 6000);
    try {
      promptAction.showToast({ message: `${message}，可撤销`, duration: 2000 });
    } catch (error) {
      // 预览器不支持系统 Toast 时忽略
    }
  }

  private showToast(message: string, duration: number): void {
    this.toastMessage = message;
    this.toastVisible = true;
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => {
      this.toastVisible = false;
      // Toast 消失即代表「后悔药」过期。句柄必须跟着一起丢弃，
      // 否则按钮虽已不可见，撤销动作仍会被后续逻辑误触发。
      this.clearUndo();
    }, duration);
  }

  private clearUndo(): void {
    this.undoAction = null;
    this.undoVisible = false;
  }

  /** 执行挂起的撤销。先把句柄清空再执行，避免回滚过程中再次触发。 */
  private runUndo(): void {
    const action: (() => void) | null = this.undoAction;
    this.hideToast();
    if (action !== null) {
      action();
    }
  }

  private hideToast(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
      this.toastTimer = -1;
    }
    this.toastVisible = false;
    this.clearUndo();
  }

  /** 判断是否为重度文档（PDF / 试卷 / Doc / 稿纸 / 手写笔记），需要唤起全屏华为风工作台 */
  private isHeavyDocument(note: NoteItem): boolean {
    const t = note.type.toLowerCase();
    const cat = note.category;
    return t === 'pdf' || t === 'doc' || t === 'docx' || t === 'canvas' || t === '白板' ||
      t === '白纸笔记' || t === 'handwriting' || t === '稿纸' || cat === '试卷题库' ||
      note.id === 'note-seed-exam' || note.id === 'note-seed-pdf' || note.id === 'note-seed-handwriting';
  }

  private openNote(note: NoteItem): void {
    const current = this.notes.find((item: NoteItem) => item.id === note.id);
    if (!current) { this.notify('笔记已被移走'); return; }
    note = current;
    this.sourcePage = 1;
    this.dismissNavigationOverlay();
    if (this.isHeavyDocument(note)) {
      // PDF / 试卷 / 稿纸手写：进入独立全屏华为风阅读器工作台
      this.fullScreenDocNote = note;
      this.fullScreenDocOpen = true;
      this.activeNoteId = note.id;
      this.readingOpen = false;
      return;
    }
    // 速记与常规 Markdown 随笔：保持在三栏式 AppShell 内打开
    this.readingNote = note;
    this.readingOpen = true;
    this.activeNoteId = note.id;
    this.outlineItems = [];
    this.saveState = SAVE_IDLE;
    this.annotationPaneOpen = false;
    this.fullScreenDocOpen = false;
  }

  private openNoteById(noteId: string): void {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === noteId) {
        this.openNote(this.notes[i]);
        return;
      }
    }
    this.notify('目标笔记不存在');
  }

  private openStudySource(noteId: string, pageNumber?: number, line?: number): void {
    const note = this.notes.find((item: NoteItem) => item.id === noteId);
    if (!note) { this.notify('来源资料已被移除'); return; }
    if (pageNumber && (!Number.isInteger(pageNumber) || pageNumber < 1 || pageNumber > (note.pageCount || 0))) {
      this.notify('来源页码已无效，请重新核对资料'); return;
    }
    this.openNote(note);
    if (pageNumber && this.fullScreenDocOpen) {
      this.sourcePage = Math.max(1, Math.min(note.pageCount || 1, pageNumber)); this.sourceJumpToken++;
    } else if (line && this.readingOpen) { this.jumpLine = line - 1; this.jumpToken++; }
  }

  private async savePdfText(pages: PdfTextPage[]): Promise<void> {
    const note = this.notes.find((item: NoteItem) => item.id === this.pdfExtractNoteId);
    if (!note) { throw new Error('资料已移除'); }
    const previous = note.pdfTextJson;
    note.pdfTextJson = StudySourceService.merge(note, pages);
    try { await this.storage.save(this.notes); }
    catch { note.pdfTextJson = previous; throw new Error('文字索引保存失败'); }
    this.notes = this.notes.slice();
    if (this.fullScreenDocNote.id === note.id) { this.fullScreenDocNote = note; }
    this.notify('已保存校对文字，可用于搜索与课程自测');
  }

  private openNoteByTitle(title: string): void {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].title === title) {
        this.openNote(this.notes[i]);
        return;
      }
    }
    this.requestCreateNote('', 'Markdown', title);
  }

  /** 新建笔记前先弹命名层：记录意图并展示 NameNoteSheet，确认后再真正落地。 */
  private requestCreateNote(projectName: string, type: string, defaultName: string): void {
    const pending: PendingNoteCreate = {
      projectName: projectName,
      type: type,
      defaultName: defaultName
    };
    animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
      this.pendingCreate = pending;
    });
  }

  /** 命名层确认：按意图分发到全局新建或项目内新建。 */
  private commitPendingCreate(name: string): void {
    const pending: PendingNoteCreate | null = this.pendingCreate;
    this.pendingCreate = null;
    if (pending === null) {
      return;
    }
    if (pending.projectName.length === 0) {
      this.createNote(name);
    } else {
      this.createNoteInProject(name, pending.projectName, pending.type);
    }
  }

  /** 命名层默认标题（取自待创建意图）。 */
  private pendingDefaultName(): string {
    const pending: PendingNoteCreate | null = this.pendingCreate;
    return pending !== null ? pending.defaultName : '未命名笔记';
  }

  private async createNote(title: string): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const now: Date = new Date();
    const category: string = this.activeSpaceName();
    const note: NoteItem = {
      id: `note-${now.getTime()}`,
      title: title,
      category: category.length === 0 ? '未分类' : category,
      type: 'Markdown',
      previewText: '空白笔记',
      tag: '新笔记',
      tagColor: '',
      updateTime: this.formatTime(now),
      contentDetail: `# ${title}\n\n`,
      tags: ['新笔记'],
      createdAt: now.getTime(),
      updatedAt: now.getTime()
    };
    const next = [note].concat(this.notes);
    try {
      await this.storage.create(context, note);
      await this.storage.save(next);
    } catch (error) {
      console.error(`Markdown 正文创建失败: ${JSON.stringify(error)}`);
      this.notify('新笔记保存未完成，请检查存储后重试');
      return;
    }
    this.notes = next;
    this.rebuildSpaces();
    this.openNote(note);
    this.notify('已创建新笔记');
  }

  private createProject(name: string, color: string, icon: string): void {
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      return;
    }
    for (let i = 0; i < this.customProjects.length; i++) {
      if (this.customProjects[i].name === trimmed) {
        this.notify(`项目「${trimmed}」已存在`);
        return;
      }
    }
    const newProj: SpaceFolder = {
      id: `space-${Date.now()}`,
      name: trimmed,
      count: 0,
      isOpen: true,
      children: [],
      color: color,
      icon: icon,
      notes: []
    };
    this.customProjects = [...this.customProjects, newProj];
    this.rebuildSpaces();
    this.persistProjects();
    this.notify(`已创建项目「${trimmed}」`);
  }

  private renameProject(oldName: string, newName: string): void {
    const trimmed = newName.trim();
    if (trimmed.length === 0 || trimmed === oldName) {
      return;
    }
    for (let i = 0; i < this.customProjects.length; i++) {
      if (this.customProjects[i].name === oldName) {
        this.customProjects[i].name = trimmed;
        this.customProjects[i].id = `space-${trimmed}`;
        break;
      }
    }
    this.customProjects = this.customProjects.slice();
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].category === oldName) {
        this.notes[i].category = trimmed;
      }
    }
    this.notes = this.notes.slice();
    this.persistSnapshot();
    this.rebuildSpaces();
    this.persistProjects();
    this.notify(`已将项目重命名为「${trimmed}」`);
  }

  private deleteProject(projectName: string): void {
    // 删除项目会连带把下辖资料改判到「未分类」。撤销必须把这两件事一起还原，
    // 只还原项目壳子的话，原先归属它的笔记会散落在「未分类」里回不来。
    const removedProjects: SpaceFolder[] = this.customProjects.filter(
      (p: SpaceFolder) => p.name === projectName);
    const movedNoteIds: string[] = [];
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].category === projectName) {
        movedNoteIds.push(this.notes[i].id);
      }
    }

    this.customProjects = this.customProjects.filter((p: SpaceFolder) => p.name !== projectName);
    // 下辖笔记移至未分类
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].category === projectName) {
        this.notes[i].category = '未分类';
      }
    }
    this.notes = this.notes.slice();
    this.persistSnapshot();
    this.rebuildSpaces();
    this.persistProjects();

    const message: string = movedNoteIds.length > 0
      ? `已删除项目「${projectName}」，${movedNoteIds.length} 篇资料归入未分类`
      : `已删除项目「${projectName}」`;
    this.notifyUndoable(message, () => {
      this.restoreProject(removedProjects, movedNoteIds, projectName);
    });
  }

  /** 撤销删除项目：还原项目壳子，并把原先归属它的笔记改回该分类。 */
  private restoreProject(projects: SpaceFolder[], noteIds: string[], projectName: string): void {
    if (projects.length === 0) {
      this.notify('项目已不存在');
      return;
    }
    const idSet: Set<string> = new Set(noteIds);
    for (let i = 0; i < this.notes.length; i++) {
      if (idSet.has(this.notes[i].id)) {
        this.notes[i].category = projectName;
      }
    }
    this.notes = this.notes.slice();
    this.customProjects = this.customProjects.concat(projects);
    this.persistSnapshot();
    this.rebuildSpaces();
    this.persistProjects();
    this.notify(`已恢复项目「${projectName}」`);
  }

  private async createNoteInProject(title: string, projectName: string, type: string): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const now: Date = new Date();
    const tag = type === 'Canvas' ? '白板' : (type === 'Doc' ? '资料' : (type === 'Task' ? '待办' : '重点'));
    const note: NoteItem = {
      id: `note-${now.getTime()}`,
      title: title,
      category: projectName,
      type: type,
      previewText: `新创建的${type}资料`,
      tag: tag,
      tagColor: '',
      updateTime: this.formatTime(now),
      contentDetail: `# ${title}\n\n`,
      tags: [tag],
      createdAt: now.getTime(),
      updatedAt: now.getTime()
    };
    this.notes = [note].concat(this.notes);
    try {
      await this.storage.create(context, note);
    } catch (error) {
      console.error(`资料正文创建失败: ${JSON.stringify(error)}`);
    }
    await this.persistSnapshot();
    this.rebuildSpaces();
    this.refreshGraph();
    this.openNote(note);
    this.notify(`已在「${projectName}」创建${type}`);
  }

  /**
   * 按模板新建（功能10）。
   * 模板正文预填结构，标题取模板名；空白模板等价于普通新建。
   */
  private async createNoteFromTemplate(templateName: string, projectName: string): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const now: Date = new Date();
    const category: string = projectName.length === 0 ? '未分类' : projectName;
    const body: string = templateBody(templateName, now);
    const note: NoteItem = {
      id: `note-${now.getTime()}`,
      title: templateName,
      category: category,
      type: 'Markdown',
      previewText: templateName,
      tag: templateName,
      tagColor: '',
      updateTime: this.formatTime(now),
      contentDetail: body,
      tags: [templateName],
      createdAt: now.getTime(),
      updatedAt: now.getTime()
    };
    this.notes = [note].concat(this.notes);
    try {
      await this.storage.create(context, note);
    } catch (error) {
      console.error(`模板正文创建失败: ${JSON.stringify(error)}`);
    }
    await this.persistSnapshot();
    this.rebuildSpaces();
    this.refreshGraph();
    this.openNote(note);
    this.notify(`已用「${templateName}」模板新建`);
  }

  private async deleteNote(noteId: string): Promise<void> {
    // 软删除：移入回收站（可恢复），保留沙箱 .md 文件——只有「彻底删除」才真正移除文件。
    let removed: NoteItem | null = null;
    let removedIndex: number = -1;
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === noteId) {
        removed = this.notes[i];
        removedIndex = i;
        break;
      }
    }
    if (removed === null) {
      this.notify('目标资料不存在');
      return;
    }
    const trashed: NoteItem = removed;
    trashed.deletedAt = Date.now();
    this.notes = this.notes.filter((n: NoteItem) => n.id !== noteId);
    this.trash = [trashed].concat(this.trash);
    if (this.readingOpen && this.readingNote.id === noteId) {
      this.readingOpen = false;
      this.activeNoteId = '';
      this.outlineItems = [];
    }
    if (this.fullScreenDocOpen && this.fullScreenDocNote.id === noteId) {
      this.fullScreenDocOpen = false;
      this.activeNoteId = '';
    }
    this.persistSnapshot();
    this.persistTrash();
    this.rebuildSpaces();
    this.refreshGraph();

    const restoreIndex: number = removedIndex;
    this.notifyUndoable(`已将「${trashed.title}」移入回收站`, () => {
      this.undoSoftDelete(trashed, restoreIndex);
    });
  }

  /** 撤销软删除：从回收站移除并按原下标插回资料库，deletedAt 清空即恢复为正常笔记。 */
  private undoSoftDelete(note: NoteItem, index: number): void {
    this.trash = this.removeById(this.trash, note.id);
    note.deletedAt = undefined;
    const next: NoteItem[] = this.notes.slice();
    const at: number = (index >= 0 && index <= next.length) ? index : next.length;
    next.splice(at, 0, note);
    this.notes = next;
    this.persistSnapshot();
    this.persistTrash();
    this.rebuildSpaces();
    this.refreshGraph();
    this.notify(`已恢复「${note.title}」`);
  }

  /** 从回收站恢复到资料库（回收站视图的「恢复」按钮）。 */
  private async restoreFromTrash(note: NoteItem): Promise<void> {
    this.trash = this.removeById(this.trash, note.id);
    note.deletedAt = undefined;
    this.notes = [note].concat(this.notes);
    this.persistSnapshot();
    this.persistTrash();
    this.rebuildSpaces();
    this.refreshGraph();
    this.notify(`已恢复「${note.title}」`);
  }

  /** 彻底删除单篇：先清理应用内文件，失败时保留回收站条目供重试。 */
  private async purgeNote(note: NoteItem): Promise<void> {
    const confirmed: boolean = await this.confirmDestructive(`彻底删除「${note.title}」？此操作不可恢复。`);
    if (!confirmed) {
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      await this.storage.delete(context, note.id, note.sourceUri || '', note.coverUrl || '');
    } catch (error) {
      console.error(`彻底删除失败 (${note.id}): ${JSON.stringify(error)}`);
      this.notify('文件删除失败，已保留回收站条目，请重试');
      return;
    }
    this.trash = this.removeById(this.trash, note.id);
    await this.persistTrash();
    this.notify('已彻底删除');
  }

  /** 清空回收站（不可恢复，需二次确认）。 */
  private async emptyTrash(): Promise<void> {
    if (this.trash.length === 0) {
      return;
    }
    const confirmed: boolean =
      await this.confirmDestructive(`清空回收站？${this.trash.length} 篇笔记将被彻底删除，不可恢复。`);
    if (!confirmed) {
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const pending: NoteItem[] = this.trash.slice();
    const failed: NoteItem[] = [];
    for (let i = 0; i < pending.length; i++) {
      try {
        await this.storage.delete(context, pending[i].id, pending[i].sourceUri || '', pending[i].coverUrl || '');
      } catch (error) {
        failed.push(pending[i]);
        console.error(`清空回收站失败 (${pending[i].id}): ${JSON.stringify(error)}`);
      }
    }
    this.trash = failed;
    await this.persistTrash();
    this.notify(failed.length === 0 ? '回收站已清空' : `有 ${failed.length} 篇文件清理失败，已保留供重试`);
  }

  /** 不可恢复操作的二次确认；对话框不可用时按「取消」处理，绝不误删。 */
  private async confirmDestructive(message: string): Promise<boolean> {
    try {
      const response = await promptAction.showDialog({
        title: '不可恢复的操作',
        message: message,
        buttons: [
          { text: '取消', color: '#787774' },
          { text: '彻底删除', color: '#E03E3E' }
        ]
      });
      return response.index === 1;
    } catch (error) {
      console.error(`确认对话框显示失败: ${JSON.stringify(error)}`);
      this.notify('无法显示确认对话框，操作已取消');
      return false;
    }
  }

  private async persistTrash(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      await this.storage.saveTrash(context, this.trash);
    } catch (error) {
      console.error(`回收站保存失败: ${JSON.stringify(error)}`);
      this.notify('回收站保存失败');
    }
  }

  private removeById(list: NoteItem[], id: string): NoteItem[] {
    const result: NoteItem[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].id !== id) {
        result.push(list[i]);
      }
    }
    return result;
  }

  private findNoteById(id: string): NoteItem | null {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === id) {
        return this.notes[i];
      }
    }
    return null;
  }

  private requireAiNote(identifier: string): NoteItem {
    const key = identifier.trim().toLowerCase();
    const byId = this.notes.find((note: NoteItem) => note.id.toLowerCase() === key);
    if (byId) { return byId; }
    const matches = this.notes.filter((note: NoteItem) => note.title.toLowerCase() === key);
    if (matches.length !== 1) { throw new Error(matches.length > 1 ? '标题对应多篇笔记，请指定笔记 ID' : `未找到笔记「${identifier}」，请提供完整标题或 ID`); }
    return matches[0];
  }

  private async commitAiNote(note: NoteItem, writeBody: boolean = false): Promise<void> {
    const previous = this.notes.find((item: NoteItem) => item.id === note.id);
    const context = this.getAbilityContext();
    if (writeBody && previous && this.readingOpen && this.readingNote.id === previous.id) {
      throw new Error('请先结束当前笔记编辑并返回，再修改正文');
    }
    if (writeBody) { await this.storage.saveDocument(context, note, note.contentDetail); }
    const next = previous ? this.notes.map((item: NoteItem) => item.id === note.id ? note : item) : [note].concat(this.notes);
    try { await this.storage.save(next); }
    catch (error) {
      if (writeBody) {
        if (previous) { await this.storage.saveDocument(context, previous, previous.contentDetail); }
        else { await this.storage.delete(context, note.id); }
      }
      throw new Error(error instanceof Error ? error.message : '笔记未能保存');
    }
    this.notes = next;
    if (this.readingNote.id === note.id) { this.readingNote = note; }
    this.rebuildSpaces(); this.refreshStats();
    await this.refreshGraph();
  }

  private async handleAiAddTag(identifier: string, tags: string): Promise<void> {
    const note = this.requireAiNote(identifier);
    const values = tags.split(/[,，]/).map((value: string) => value.trim()).filter((value: string) => value.length > 0);
    if (!values.length) { throw new Error('标签不能为空'); }
    const merged = note.tags ? note.tags.slice() : note.tag.split(',').filter((value: string) => value.trim().length > 0);
    for (const value of values) { if (!merged.includes(value)) { merged.push(value); } }
    const updated = JSON.parse(JSON.stringify(note)) as NoteItem;
    updated.tags = merged; updated.tag = merged.join(', '); updated.updatedAt = Date.now();
    await this.commitAiNote(updated);
  }

  private async handleAiCreateLink(identifier: string, title: string): Promise<void> {
    const note = this.requireAiNote(identifier);
    const link = `[[${title}]]`;
    if (note.contentDetail.includes(link)) { return; }
    const updated = JSON.parse(JSON.stringify(note)) as NoteItem;
    updated.contentDetail = `${note.contentDetail}\n\n${link}\n`; updated.updatedAt = Date.now(); updated.updateTime = '刚刚';
    await this.commitAiNote(updated, true);
  }

  private async handleAiCategorize(identifier: string, category: string): Promise<void> {
    const note = this.requireAiNote(identifier);
    const updated = JSON.parse(JSON.stringify(note)) as NoteItem;
    updated.category = category; updated.updatedAt = Date.now();
    await this.commitAiNote(updated);
  }

  private async handleAiCreateNote(title: string, category: string, tag: string, content: string): Promise<void> {
    const now = Date.now();
    const tags = tag.trim() ? tag.split(/[,，]/).map((value: string) => value.trim()).filter((value: string) => !!value) : ['AI生成'];
    const note: NoteItem = { id: `note-${now}-${this.notes.length}`, title, category: category || CATEGORY_UNFILED,
      type: 'Markdown', previewText: content.slice(0, 100).replace(/[#*`\n]/g, ' ').trim(), tag: tags.join(', '), tags,
      tagColor: '', updateTime: '刚刚', contentDetail: content, createdAt: now, updatedAt: now };
    await this.commitAiNote(note, true);
    this.notify(`已保存笔记《${title}》`);
  }

  private async handleAiCreateTodo(date: string, title: string): Promise<void> {
    const now = Date.now();
    const todo: TodoItem = { id: `todo-${now}-${this.todos.length}`, date, title, done: false,
      noteRefs: [], createdAt: now, updatedAt: now };
    const next = [todo].concat(this.todos);
    await this.todoStorage.saveTodos(this.getAbilityContext(), next);
    this.todos = next;
  }
  // ==================================================================
  // 重命名 / 移动分类
  // ==================================================================

  /** 现有分类去重列表（含「未分类」兜底），供移动弹层选择目标。 */
  private allCategories(): string[] {
    const seen: Set<string> = new Set();
    const result: string[] = [];
    for (let i = 0; i < this.notes.length; i++) {
      const category: string = this.notes[i].category.length === 0 ? CATEGORY_UNFILED : this.notes[i].category;
      if (!seen.has(category)) {
        seen.add(category);
        result.push(category);
      }
    }
    return result;
  }

  /** 把正文首个一级标题替换为新标题；无一级标题时在开头补一个。 */
  private replaceLeadingHeading(content: string, title: string): string {
    const lines: string[] = content.split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('# ')) {
        lines[i] = `# ${title}`;
        return lines.join('\n');
      }
    }
    return `# ${title}\n\n${content}`;
  }

  /** 确认重命名：更新标题元数据并同步正文首个 H1，落盘 .md 与快照。 */
  private async commitRename(note: NoteItem, newTitle: string): Promise<void> {
    const trimmed: string = newTitle.trim();
    const target: NoteItem | null = this.findNoteById(note.id);
    if (target === null) {
      this.notify('目标笔记不存在');
      return;
    }
    if (trimmed.length === 0 || trimmed === target.title) {
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const nextContent: string = this.replaceLeadingHeading(target.contentDetail, trimmed);
    target.title = trimmed;
    target.contentDetail = nextContent;
    target.updateTime = this.formatTime(new Date());
    this.notes = this.notes.slice();
    if (this.readingOpen && this.readingNote.id === target.id) {
      this.readingNote = target;
    }
    if (this.fullScreenDocOpen && this.fullScreenDocNote.id === target.id) {
      this.fullScreenDocNote = target;
    }
    try {
      await this.storage.saveDocument(context, target, nextContent);
    } catch (error) {
      console.error(`重命名后正文落盘失败 (${target.id}): ${JSON.stringify(error)}`);
    }
    await this.persistSnapshot();
    this.rebuildSpaces();
    this.notify(`已重命名为「${trimmed}」`);
  }

  /** 确认移动：只更新分类元数据并重建项目树（正文不变，无需重写 .md）。 */
  private async commitMove(note: NoteItem, category: string): Promise<void> {
    const trimmed: string = category.trim();
    const target: NoteItem | null = this.findNoteById(note.id);
    if (target === null) {
      this.notify('目标笔记不存在');
      return;
    }
    if (trimmed.length === 0) {
      return;
    }
    if (target.category === trimmed) {
      this.notify(`「${target.title}」已在「${trimmed}」`);
      return;
    }
    target.category = trimmed;
    this.notes = this.notes.slice();
    if (this.readingOpen && this.readingNote.id === target.id) {
      this.readingNote = target;
    }
    if (this.fullScreenDocOpen && this.fullScreenDocNote.id === target.id) {
      this.fullScreenDocNote = target;
    }
    await this.persistSnapshot();
    this.rebuildSpaces();
    this.notify(`已移动到「${trimmed}」`);
  }

  // ==================================================================
  // 收藏（星标）
  // ==================================================================

  /** 已收藏的笔记列表（回收站中的笔记不在 this.notes 内，无需再排除）。 */
  private favoriteNotes(): NoteItem[] {
    const result: NoteItem[] = [];
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].favorite === true) {
        result.push(this.notes[i]);
      }
    }
    return result;
  }

  /** 切换收藏态并落盘；同步刷新阅读器与侧栏角标。 */
  private async toggleFavorite(note: NoteItem): Promise<void> {
    const target: NoteItem | null = this.findNoteById(note.id);
    if (target === null) {
      this.notify('目标笔记不存在');
      return;
    }
    target.favorite = target.favorite !== true;
    this.notes = this.notes.slice();
    if (this.readingOpen && this.readingNote.id === target.id) {
      this.readingNote = target;
    }
    await this.persistSnapshot();
    this.notify(target.favorite ? `已收藏「${target.title}」` : `已取消收藏「${target.title}」`);
  }

  /** 切换置顶状态并落盘 */
  private async togglePinNote(note: NoteItem): Promise<void> {
    const target: NoteItem | null = this.findNoteById(note.id);
    if (target === null) {
      return;
    }
    target.isPinned = target.isPinned !== true;
    this.notes = this.notes.slice();
    await this.persistSnapshot();
    this.notify(target.isPinned ? `已置顶「${target.title}」` : `已取消置顶「${target.title}」`);
  }

  // ==================================================================
  // 多标签（功能6）
  // ==================================================================

  /**
   * 写回一篇笔记的标签列表。
   * 同时把单值 tag 同步为首个标签，卡片/侧栏的旧展示位无需改造即可跟着更新。
   */
  private async applyTags(note: NoteItem, tags: string[]): Promise<void> {
    const target: NoteItem | null = this.findNoteById(note.id);
    if (target === null) {
      this.notify('目标笔记不存在');
      return;
    }
    const clean: string[] = [];
    for (let i = 0; i < tags.length; i++) {
      const t: string = tags[i].trim().replace(/^#/, '');
      if (t.length === 0) {
        continue;
      }
      let dup: boolean = false;
      for (let j = 0; j < clean.length; j++) {
        if (clean[j] === t) {
          dup = true;
          break;
        }
      }
      if (!dup) {
        clean.push(t);
      }
    }
    target.tags = clean;
    target.tag = clean.length > 0 ? clean[0] : '';
    target.updatedAt = Date.now();
    this.notes = this.notes.slice();
    if (this.readingOpen && this.readingNote.id === target.id) {
      this.readingNote = target;
    }
    await this.persistSnapshot();
    this.rebuildSpaces();
    this.refreshStats();
    this.notify(`已更新「${target.title}」的标签`);
  }

  // ==================================================================
  // 待办日历
  // ==================================================================

  /** 全部未完成待办数量，用于侧边栏角标。 */
  private todoPendingCount(): number {
    let count: number = 0;
    for (let i = 0; i < this.todos.length; i++) {
      if (!this.todos[i].done) {
        count++;
      }
    }
    return count;
  }

  private async persistTodos(): Promise<void> {
    const context: common.UIAbilityContext = this.getAbilityContext();
    try {
      await this.todoStorage.saveTodos(context, this.todos);
    } catch (error) {
      console.error(`待办保存失败: ${JSON.stringify(error)}`);
      this.notify('待办保存失败');
    }
  }

  private async persistDayNotes(): Promise<void> {
    const context: common.UIAbilityContext = this.getAbilityContext();
    try {
      await this.todoStorage.saveDayNotes(context, this.dayNotes);
    } catch (error) {
      console.error(`日期备忘保存失败: ${JSON.stringify(error)}`);
    }
  }

  /** 新增一条待办到指定日期。 */
  private async addTodo(dateKey: string, title: string, noteRefs: string[]): Promise<void> {
    const now: number = Date.now();
    const todo: TodoItem = {
      id: `todo-${now}-${this.todos.length}`,
      date: dateKey,
      title: title,
      done: false,
      noteRefs: noteRefs.slice(),
      createdAt: now,
      updatedAt: now
    };
    this.todos = [todo].concat(this.todos);
    await this.persistTodos();
    this.notify('已添加待办');
  }

  /**
   * 黄金闭环：智能提取落地为双链知识卡并注入待办日程
   */
  private async handleCommitSmartExtract(content: SmartContent, selectedTasks: SmartTask[]): Promise<void> {
    const context = this.getAbilityContext();
    const persistence: SmartCaptureStorage = {
      currentNotes: () => this.notes,
      currentTodos: () => this.todos,
      writeDocument: async (note: NoteItem) => { await this.storage.create(context, note); },
      writeNotes: async (notes: NoteItem[]) => {
        await this.storage.save(notes);
        this.notes = notes;
        this.rebuildSpaces();
      },
      writeTodos: async (todos: TodoItem[]) => {
        await this.todoStorage.saveTodos(context, todos);
        this.todos = todos;
      }
    };
    const note = await SmartCaptureService.commit(content, selectedTasks, persistence);
    this.refreshStats();
    await this.refreshGraph();
    this.openNote(note);
    this.notify('已保存「' + content.title + '」与 ' + selectedTasks.length + ' 条待办');
  }

  /** 切换待办完成态：未完成（红）↔ 已完成（绿）。 */
  private async toggleTodo(todo: TodoItem): Promise<void> {
    for (let i = 0; i < this.todos.length; i++) {
      if (this.todos[i].id === todo.id) {
        const current: TodoItem = this.todos[i];
        const next: TodoItem = {
          id: current.id,
          date: current.date,
          title: current.title,
          done: !current.done,
          noteRefs: current.noteRefs,
          createdAt: current.createdAt,
          updatedAt: Date.now()
        };
        this.todos[i] = next;
        break;
      }
    }
    this.todos = this.todos.slice();
    await this.persistTodos();
  }

  /** 删除一条待办。 */
  private async deleteTodo(todo: TodoItem): Promise<void> {
    const result: TodoItem[] = [];
    for (let i = 0; i < this.todos.length; i++) {
      if (this.todos[i].id !== todo.id) {
        result.push(this.todos[i]);
      }
    }
    this.todos = result;
    await this.persistTodos();
    this.notify('已删除待办');
  }

  /** 写入某日期的备忘文本（不存在则新建条目）。 */
  private async updateDayNote(dateKey: string, text: string): Promise<void> {
    const now: number = Date.now();
    const entry: DayNote = { date: dateKey, text: text, updatedAt: now };
    let found: boolean = false;
    for (let i = 0; i < this.dayNotes.length; i++) {
      if (this.dayNotes[i].date === dateKey) {
        this.dayNotes[i] = entry;
        found = true;
        break;
      }
    }
    if (!found) {
      const next: DayNote[] = [entry];
      this.dayNotes = next.concat(this.dayNotes);
    } else {
      this.dayNotes = this.dayNotes.slice();
    }
    await this.persistDayNotes();
  }

  /** 获取或自动生成自由白板笔记，用于自由白板画卷常驻工作区 */
  private getOrCreateCanvasNote(): NoteItem {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].type.toLowerCase() === 'canvas' || this.notes[i].id === 'note-seed-handwriting' || this.notes[i].title === '自由白板演算') {
        return this.notes[i];
      }
    }
    const canvasNote: NoteItem = {
      id: `canvas-global`,
      title: '自由白板演算',
      category: '速记灵感',
      type: 'canvas',
      previewText: '全功能多色自由手写草稿板',
      tag: '手写',
      tagColor: '#D97706',
      updateTime: '刚刚',
      contentDetail: '',
      strokes: '[]'
    };
    this.notes = [canvasNote].concat(this.notes);
    return canvasNote;
  }

  /**
   * 通过系统文件选择器导入文档。
   * @param targetCategory 导入后归入的项目名，默认「未分类」
   */
  private async importDocument(targetCategory: string = '未分类'): Promise<void> {
    const context: common.UIAbilityContext = this.getAbilityContext();
    try {
      const result: DocumentTransferResult = await this.storage.importDocument(context);
      if (result.status === 'imported' && result.document !== undefined) {
        const document: MarkdownDocument = result.document;
        const now: Date = new Date();
        const isPdf: boolean = result.noteType === 'PDF' || document.title.toLowerCase().endsWith('.pdf');
        const note: NoteItem = {
          id: document.id,
          title: document.title,
          category: targetCategory,
          type: result.noteType !== undefined ? result.noteType : (isPdf ? 'PDF' : 'Markdown'),
          sourceType: isPdf ? 'pdf' : 'document',
          sourceUri: result.sourceUri,
          pageCount: result.pageCount || 1,
          pageInfo: isPdf ? (result.pageCount || 1) + ' 页' : '',
          previewText: document.content.length > 48 ? `${document.content.substring(0, 48)}…` : document.content,
          tag: isPdf ? 'PDF文献' : '导入',
          tagColor: isPdf ? '#E11D48' : '#2563EB',
          updateTime: this.formatTime(now),
          contentDetail: document.content,
          tags: isPdf ? ['PDF文献', targetCategory] : ['导入'],
          createdAt: now.getTime(),
          updatedAt: now.getTime()
        };
        const nextNotes = [note].concat(this.notes);
        await this.storage.save(nextNotes);
        this.notes = nextNotes;
        this.rebuildSpaces();
        this.refreshGraph();
        this.notify(`已导入 ${document.fileName}`);
      } else if (result.status !== 'cancelled') {
        this.notify(result.message);
      }
    } catch (error) {
      console.error(`文档导入失败: ${JSON.stringify(error)}`);
      this.notify('文档导入失败');
    }
  }

  private handleSaved(note: NoteItem, content: string, kind: ReaderSaveKind = 'markdown'): Promise<void> {
    note.updateTime = this.formatTime(new Date());
    return this.readerCommits.commit(note, content, {
      notes: () => this.notes,
      saveDocument: async (item: NoteItem, text: string) => { await this.storage.saveDocument(this.getAbilityContext(), item, text); },
      saveNotes: (items: NoteItem[]) => this.storage.save(items),
      publish: (items: NoteItem[], saved: NoteItem) => {
        this.notes = items; this.readingNote = saved;
        if (this.fullScreenDocNote.id === saved.id) { this.fullScreenDocNote = saved; }
        this.refreshGraph();
      }
    }, true, kind);
  }

  private formatTime(date: Date): string {
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const hour: string = date.getHours() < 10 ? `0${date.getHours()}` : `${date.getHours()}`;
    const minute: string = date.getMinutes() < 10 ? `0${date.getMinutes()}` : `${date.getMinutes()}`;
    return `${month}月${day}日 ${hour}:${minute}`;
  }

  // ==================================================================
  // 视图装配
  // ==================================================================

  @Builder
  workspaceContent() {
    if (this.readingOpen) {
      ReaderWorkspace({
        note: this.readingNote,
        annotationPaneOpen: this.annotationPaneOpen,
        jumpToken: this.jumpToken,
        jumpLine: this.jumpLine,
        favorite: this.readingNote.favorite === true,
        onChooseCover: () => { this.coverNoteId = this.readingNote.id; },
        onToggleFavorite: (note: NoteItem) => {
          this.toggleFavorite(note);
        },
        onDeleteNote: (note: NoteItem) => {
          this.deleteNote(note.id);
        },
        onOutlineUpdated: (items: MarkdownOutlineItem[]) => {
          this.outlineItems = items;
        },
        onOpenNoteByTitle: (title: string) => {
          this.openNoteByTitle(title);
        },
        onBack: () => {
          this.closeReading();
        },
        onToggleAnnotation: () => {
          this.annotationPaneOpen = !this.annotationPaneOpen;
        },
        onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => this.handleSaved(note, content, kind),
        onSaveStateChange: (state: string) => {
          this.saveState = state;
        }
      })
    } else if (this.activeNav === NAV_HOME) {
      HomeWorkspace({
        stats: this.stats,
        recentNotes: this.notes,
        unresolvedLinks: this.linkGraph.unresolvedLinks,
        courses: ReviewPolicy.courses(this.notes, this.reviewCards, this.todos),
        onOpenStudy: (course: string) => { this.studyCourse = course; this.studyVisible = true; },
        onSelectNote: (note: NoteItem) => this.openNote(note),
        onCreateNote: () => this.requestCreateNote('', 'Markdown', '未命名笔记'),
        onImportDocument: () => this.importDocument(),
        onOpenGraph: () => {
          this.activeNav = NAV_GRAPH;
        },
        onChooseCover: (noteId: string) => { this.coverNoteId = noteId; },
        onTogglePin: (note: NoteItem) => this.togglePinNote(note),
        onToggleFavorite: (note: NoteItem) => this.toggleFavorite(note),
        onDeleteNote: (noteId: string) => this.deleteNote(noteId),
        onSmartExtract: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.smartExtractVisible = true;
          });
        },
        onOpenNoteByTitle: (title: string) => this.openNoteByTitle(title),
        onNavigate: (navKey: string) => {
          this.activeNav = navKey;
        }
      })
    } else if (this.activeNav === NAV_LIBRARY) {
      LibraryWorkspace({
        notes: this.filteredNotes(),
        totalCount: this.notes.length,
        searchText: this.searchText,
        activeFilter: this.activeFilter,
        activeNoteId: this.activeNoteId,
        onSearchChange: (value: string) => {
          this.searchText = value;
        },
        onFilterChange: (filter: string) => {
          this.activeFilter = filter;
        },
        onSelectNote: (note: NoteItem) => this.openNote(note),
        onCreateNote: () => this.requestCreateNote('', 'Markdown', '未命名笔记'),
        onImportDocument: () => this.importDocument()
      })
    } else if (this.activeNav === NAV_GRAPH) {
      GraphWorkspace({
        graph: this.linkGraph,
        stats: this.stats,
        allNotes: this.notes,
        onSelectNoteById: (noteId: string) => this.openNoteById(noteId),
        onOpenNoteByTitle: (title: string) => this.openNoteByTitle(title),
        onLinkNodes: (sourceIdentifier: string, targetTitle: string) => {
          this.handleAiCreateLink(sourceIdentifier, targetTitle);
        },
        onCreateGalaxy: (galaxyName: string) => {
          this.createProject(galaxyName, '#6366F1', '🪐');
        }
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
    } else if (this.activeNav === NAV_TODO) {
      TodoWorkspace({
        dayNotes: this.dayNotes,
        todos: this.todos,
        notes: this.notes,
        onAddTodo: (dateKey: string, title: string, noteRefs: string[]) => {
          this.addTodo(dateKey, title, noteRefs);
        },
        onToggleTodo: (todo: TodoItem) => this.toggleTodo(todo),
        onDeleteTodo: (todo: TodoItem) => this.deleteTodo(todo),
        onUpdateDayNote: (dateKey: string, text: string) => {
          this.updateDayNote(dateKey, text);
        },
        onOpenNote: (noteId: string) => this.openNoteById(noteId)
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
    } else if (this.activeNav === NAV_TRASH) {
      TrashWorkspace({
        trash: this.trash,
        retentionDays: TRASH_RETENTION_DAYS,
        onRestore: (note: NoteItem) => this.restoreFromTrash(note),
        onPurge: (note: NoteItem) => this.purgeNote(note),
        onEmpty: () => this.emptyTrash()
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
    } else if (this.activeNav === NAV_FAVORITE) {
      FavoriteWorkspace({
        favorites: this.favoriteNotes(),
        onSelectNote: (note: NoteItem) => this.openNote(note)
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
    } else if (this.activeNav === NAV_CANVAS) {
      HandwritingCanvas({
        note: this.getOrCreateCanvasNote(),
        isScratchpad: false,
        onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => this.handleSaved(note, content, kind),
        onSaveStateChange: (state: string) => {
          this.saveState = state;
        }
      })
      .width('100%')
      .height('100%')
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
    } else {
      AiWorkspace({
        onOpenCitation: (c: ChatCitation) => this.openStudySource(c.noteId, c.pageNumber, c.startLine),
        reviewCards: this.reviewCards,
        allNotes: this.notes,
        todos: this.todos,
        stats: this.stats,
        activeSessionId: this.activeSessionId,
        currentNote: this.activeNoteId.length > 0
          ? this.notes.find((note: NoteItem) => note.id === this.activeNoteId) ?? null
          : null,
        externalPinnedNotes: this.aiPinnedNotes,
        prefilledPrompt: this.aiPrefilledPrompt,
        toolsEnabled: this.aiToolsEnabled,
        contextPanelOpen: this.contextPanelOpen,
        onToggleContextPanel: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.contextPanelOpen = !this.contextPanelOpen;
            if (this.singleColumn && this.contextPanelOpen) { this.sidebarCollapsed = true; }
          });
        },
        onPinnedNotesChange: (pinned: NoteItem[]) => {
          this.aiPinnedNotes = pinned;
        },
        onSessionSaved: (session: ChatSession) => {
          this.handleSessionSaved(session);
        },
        onContextChange: (citations: ChatCitation[], pinned: NoteItem[], layerLabel: string, modelLabel: string) => {
          this.aiCitations = citations;
          this.aiPinnedNotes = pinned;
          this.aiLayerLabel = layerLabel;
          this.aiModelLabel = modelLabel;
        },
        onOpenModelSettings: () => {
          this.activeSheet = 'model_settings';
        },
        onCreateTodo: (dateKey: string, title: string) => this.handleAiCreateTodo(dateKey, title),
        onAddTagToNote: (identifier: string, tags: string) => this.handleAiAddTag(identifier, tags),
        onCreateLinkBetweenNotes: (sourceIdentifier: string, targetTitle: string) => this.handleAiCreateLink(sourceIdentifier, targetTitle),
        onCategorizeNote: (identifier: string, category: string) => this.handleAiCategorize(identifier, category),
        onCreateNewNote: (title: string, category: string, tag: string, content: string) => this.handleAiCreateNote(title, category, tag, content),
        onOpenSearch: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.searchVisible = true;
          });
        },
        onSmartExtract: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.smartExtractVisible = true;
          });
        }
      })
    }
  }

  @Builder
  contextContent() {
    // AI 墨客下右栏改为「来源与上下文」；其余场景仍是笔记大纲 / 反向链接
    if (this.activeNav === NAV_AI) {
      AiSourcesPanel({
        spaces: this.spaces,
        citations: this.aiCitations,
        pinnedNotes: this.aiPinnedNotes,
        layerLabel: this.aiLayerLabel,
        modelLabel: this.aiModelLabel,
        currentDocTitle: this.activeNoteId.length > 0
          ? (this.notes.find((note: NoteItem) => note.id === this.activeNoteId)?.title ?? '')
          : '',
        currentDocNote: this.activeNoteId.length > 0
          ? (this.notes.find((note: NoteItem) => note.id === this.activeNoteId) ?? null)
          : null,
        allNotes: this.notes,
        toolsEnabled: this.aiToolsEnabled,
        onToggleTools: (enabled: boolean) => {
          this.aiToolsEnabled = enabled;
        },
        onAddPinnedNote: (note: NoteItem) => {
          if (!this.aiPinnedNotes.some((n: NoteItem) => n.id === note.id)) {
            this.aiPinnedNotes = [...this.aiPinnedNotes, note];
          }
        },
        onAddBatchPinnedNotes: (notes: NoteItem[]) => {
          const currentIds: Set<string> = new Set(this.aiPinnedNotes.map((n: NoteItem) => n.id));
          const newNotes: NoteItem[] = notes.filter((n: NoteItem) => !currentIds.has(n.id));
          if (newNotes.length > 0) {
            this.aiPinnedNotes = [...this.aiPinnedNotes, ...newNotes];
          }
        },
        onRemovePinnedNote: (noteId: string) => {
          this.aiPinnedNotes = this.aiPinnedNotes.filter((n: NoteItem) => n.id !== noteId);
        },
        onRemoveBatchPinnedNotes: (noteIds: string[]) => {
          const removeIds: Set<string> = new Set(noteIds);
          this.aiPinnedNotes = this.aiPinnedNotes.filter((n: NoteItem) => !removeIds.has(n.id));
        },
        onClearPinnedNotes: () => {
          this.aiPinnedNotes = [];
        },
        onCreateProject: (name: string, color: string, icon: string) => {
          this.createProject(name, color, icon);
        },
        onStartChatWithContext: (prefilled: string) => {
          this.aiPrefilledPrompt = prefilled;
        },
        onPreviewSource: (c: ChatCitation) => this.openStudySource(c.noteId, c.pageNumber, c.startLine),
        onOpenModelSettings: () => {
          this.activeSheet = 'model_settings';
        },
        onClose: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.contextPanelOpen = false;
          });
        }
      })
    } else {
      ContextDrawer({
        outlineItems: this.outlineItems,
        backlinks: this.currentBacklinks(),
        unresolved: this.currentUnresolved(),
        recentNotes: this.notes.slice(0, 10),
        activeTab: this.contextTab,
        closable: true,
        onTabChange: (tab: string) => {
          this.contextTab = tab;
        },
        onJumpToLine: (line: number) => {
          this.jumpLine = line;
          this.jumpToken = this.jumpToken + 1;
        },
        onOpenNote: (noteId: string) => this.openNoteById(noteId),
        onSelectNote: (note: NoteItem) => this.openNote(note),
        onCreateFromTitle: (title: string) => this.createNote(title),
        onClose: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.contextPanelOpen = false;
          });
        }
      })
    }
  }

  build() {
    Stack() {
      AppShell({
        breadcrumb: this.breadcrumb(),
        saveState: this.saveState,
        spaces: this.spaces,
        recentNotes: this.notes.slice(0, 8),
        activeNav: this.activeNav,
        activeSpaceId: this.activeSpaceId,
        activeNoteId: this.activeNoteId,
        sidebarCollapsed: this.sidebarCollapsed,
        contextPanelOpen: this.contextPanelOpen,
        // 注意：@BuilderParam 直接传 this.xxx 时，builder 内的 this 会指向子组件 AppShell，
        // 读不到 Index 的状态（曾导致 this.notes.slice 崩溃）。用内联 Builder 箭头函数包裹可保留宿主 this。
        content: () => {
          this.workspaceContent();
        },
        contextPanel: () => {
          this.contextContent();
        },
        onBreadcrumbClick: (index: number, segment: string) => {
          this.onBreadcrumbClick(index, segment);
        },
        onLayoutModeChange: (singleColumn: boolean, threeColumn: boolean) => {
          this.sidebarCollapsed = singleColumn;
          this.contextPanelOpen = threeColumn;
        },
        onToggleSidebar: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.sidebarCollapsed = !this.sidebarCollapsed;
            if (this.singleColumn && !this.sidebarCollapsed) { this.contextPanelOpen = false; }
          });
        },
        onToggleContext: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.contextPanelOpen = !this.contextPanelOpen;
            if (this.singleColumn && this.contextPanelOpen) { this.sidebarCollapsed = true; }
          });
        },
        onOpenSearch: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.searchVisible = true;
          });
        },
        onSelectNav: (navKey: string) => {
          this.dismissNavigationOverlay();
          this.activeNav = navKey;
          this.readingOpen = false;
          this.fullScreenDocOpen = false;
          this.activeNoteId = '';
          // 进入 AI 墨客自动切到对话列表；离开时切回资料树。
          // 用户在 AI 里手动切回资料树后不会被强行拉回（只在导航变化时决策）。
          this.sidebarMode = navKey === NAV_AI ? SIDEBAR_MODE_SESSIONS : SIDEBAR_MODE_TREE;
        },
        onToggleSpace: (spaceId: string) => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            for (let i = 0; i < this.spaces.length; i++) {
              if (this.spaces[i].id === spaceId) {
                this.spaces[i].isOpen = !this.spaces[i].isOpen;
                break;
              }
            }
            this.spaces = this.spaces.slice();
          });
        },
        onCollapseAllSpaces: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            for (let i = 0; i < this.spaces.length; i++) {
              this.spaces[i].isOpen = false;
            }
            this.spaces = this.spaces.slice();
          });
        },
        onSelectSpace: (spaceId: string) => {
          this.dismissNavigationOverlay();
          this.activeSpaceId = this.activeSpaceId === spaceId ? '' : spaceId;
          this.activeNav = NAV_LIBRARY;
          this.readingOpen = false;
          this.fullScreenDocOpen = false;
        },
        onSelectNote: (note: NoteItem) => this.openNote(note),
        onCreateNote: () => this.requestCreateNote('', 'Markdown', '未命名笔记'),
        onCreateNoteInProject: (title: string, projectName: string, type: string) => {
          // title 在这里作为命名层的默认标题（未命名笔记 / 未命名导图 / 未命名参考资料）
          this.requestCreateNote(projectName, type, title);
        },
        onCreateFromTemplate: (templateName: string, projectName: string) => {
          this.createNoteFromTemplate(templateName, projectName);
        },
        onImportIntoProject: (projectName: string) => {
          this.importDocument(projectName);
        },
        onCreateProject: (name: string, color: string, icon: string) => {
          this.createProject(name, color, icon);
        },
        onOpenCreateProject: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.createProjectOpen = true;
          });
        },
        onOpenSheet: (type: string, project: SpaceFolder | null, note: NoteItem | null) => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.activeSheet = type;
            this.sheetProject = project;
            this.sheetNote = note;
          });
        },
        onRenameProject: (oldName: string, newName: string) => {
          this.renameProject(oldName, newName);
        },
        onDeleteProject: (name: string) => {
          this.deleteProject(name);
        },
        onDeleteNote: (noteId: string) => {
          this.deleteNote(noteId);
        },
        trashCount: this.trash.length,
        todoPendingCount: this.todoPendingCount(),
        sidebarMode: this.sidebarMode,
        sessions: this.sessions,
        activeSessionId: this.activeSessionId,
        onSidebarModeChange: (mode: string) => {
          this.sidebarMode = mode;
        },
        onSelectSession: (session: ChatSession) => {
          this.handleSelectSession(session);
        },
        onNewSession: () => {
          this.handleNewSession();
        },
        onDeleteSession: (sessionId: string) => {
          this.handleDeleteSession(sessionId);
        },
        onTogglePinSession: (session: ChatSession) => {
          this.handleTogglePinSession(session);
        },
        favoriteCount: this.favoriteNotes().length,
        onRenameNote: (note: NoteItem, newTitle: string) => {
          this.commitRename(note, newTitle);
        },
        onMoveNote: (note: NoteItem, category: string) => {
          this.commitMove(note, category);
        },
        onApplyTags: (note: NoteItem, tags: string[]) => {
          this.applyTags(note, tags);
        },
        onOpenSettings: () => {
          animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
            this.settingsVisible = true;
          });
        }
      })

      // ---- 华为风独立全屏文档与稿纸工作台 (PDF / 试卷 / 稿纸手写) ----
      if (this.fullScreenDocOpen) {
        HuaweiDocWorkspace({
          note: this.fullScreenDocNote,
          sourcePage: this.sourcePage,
          sourceJumpToken: this.sourceJumpToken,
          onExtractPdfText: (page: number) => { this.pdfExtractNoteId = this.fullScreenDocNote.id; this.pdfExtractPage = page; },
          backRequestToken: this.documentBackToken,
          onCommitForExit: async (note: NoteItem, content: string, kind?: ReaderSaveKind) => {
            await this.handleSaved(note, content, kind);
            this.saveState = SAVE_IDLE;
          },
          onSmartExtract: () => { this.smartExtractVisible = true; },
          onExportText: async () => {
            const result = await this.storage.exportDocument(this.getAbilityContext(), this.fullScreenDocNote);
            if (result.status !== 'cancelled') { this.notify(result.message); }
          },
          onSearchNotes: () => { this.searchVisible = true; },
          onClose: () => {
            this.fullScreenDocOpen = false;
            this.activeNoteId = '';
          },
          onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => this.handleSaved(note, content, kind),
          onSaveStateChange: (state: string) => {
            this.saveState = state;
          },
          onToggleFavorite: (note: NoteItem) => {
            this.toggleFavorite(note);
          }
        })
        .width('100%')
        .height('100%')
      }

      if (this.privacyVisible || this.privacyWelcome) {
        PrivacySheet({ welcome: this.privacyWelcome, saving: this.privacySaving,
          onClose: () => { this.privacyVisible = false; },
          onChoice: async (agree: boolean) => {
            if (this.privacySaving) { return; }
            this.privacySaving = true;
            try { await this.privacyNotice.choose(this.getAbilityContext(), agree); this.privacyWelcome = false; }
            catch { this.privacyWelcome = false; this.notify('选择未能保存，下次启动会再次提示'); }
            finally { this.privacySaving = false; }
          }
        })
      }
      if (this.backupVisible) {
        StudyBackupSheet({ notes: this.notes, cards: this.reviewCards, closeToken: this.backupCloseToken,
          onClose: () => { this.backupVisible = false; },
          onRestore: (note: NoteItem, cards: ReviewCard[]) => StudyRestoreService.commit(note, cards, {
            notes: () => this.notes, cards: () => this.reviewCards,
            create: async (item: NoteItem) => { await this.storage.create(this.getAbilityContext(), item); },
            saveNotes: (notes: NoteItem[]) => this.storage.save(notes),
            saveCards: (items: ReviewCard[]) => this.reviewStorage.save(this.getAbilityContext(), items),
            remove: (item: NoteItem) => this.storage.delete(this.getAbilityContext(), item.id, item.sourceUri || '', item.coverUrl || ''),
            publishNotes: (notes: NoteItem[]) => { this.notes = notes; this.rebuildSpaces(); this.refreshStats(); this.refreshGraph(); },
            publishCards: (items: ReviewCard[]) => { this.reviewCards = items; }
          }) })
      }
      if (this.studyVisible) {
        StudySheet({ notes: this.notes, cards: this.reviewCards, course: this.studyCourse,
          closeToken: this.studyCloseToken,
          onClose: () => { this.studyVisible = false; },
          onSave: async (cards: ReviewCard[]) => {
            await this.reviewStorage.save(this.getAbilityContext(), cards);
            this.reviewCards = cards;
          },
          onSource: (noteId: string, page?: number) => this.openStudySource(noteId, page) })
      }
      if (this.pdfExtractNoteId && this.notes.some((note: NoteItem) => note.id === this.pdfExtractNoteId)) {
        PdfTextSheet({ note: this.notes.find((note: NoteItem) => note.id === this.pdfExtractNoteId)!,
          initialPage: this.pdfExtractPage, closeToken: this.pdfExtractCloseToken,
          onClose: () => { this.pdfExtractNoteId = ''; },
          onSave: (pages: PdfTextPage[]) => this.savePdfText(pages) })
      }

      if (this.searchVisible) {
        QuickSearchDialog({
          notes: this.notes,
          onSelectSource: (note: NoteItem, page: number) => { this.searchVisible = false; this.openStudySource(note.id, page); },
          onClose: () => {
            animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
              this.searchVisible = false;
            });
          },
          onSelectNote: (note: NoteItem) => {
            animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
              this.searchVisible = false;
              this.openNote(note);
            });
          }
        })
      }

      if (this.settingsVisible) {
        AppearanceSheet({
          onOpenPrivacy: () => { this.settingsVisible = false; this.privacyVisible = true; },
          onOpenBackup: () => {
            if (this.readingOpen || this.fullScreenDocOpen) { this.notify('请先保存并退出当前阅读，再备份学习资料'); return; }
            this.settingsVisible = false; this.backupVisible = true;
          },
          onClose: () => {
            animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
              this.settingsVisible = false;
            });
          },
          onLoadSeedData: () => {
            this.loadSeedData();
          }
        })
      }

      if (this.smartExtractVisible) {
        SmartExtractSheet({
          onClose: () => {
            animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
              this.smartExtractVisible = false;
            });
          },
          closeToken: this.smartExtractCloseToken,
          onOpenModelSettings: () => { this.activeSheet = 'model_settings'; },
          onCommit: (content: SmartContent, selectedTasks: SmartTask[]) => {
            return this.handleCommitSmartExtract(content, selectedTasks);
          }
        })
      }

      if (this.pendingCreate !== null) {
        NameNoteSheet({
          defaultName: this.pendingDefaultName(),
          onClose: () => {
            animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
              this.pendingCreate = null;
            });
          },
          onConfirm: (name: string) => {
            animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
              this.commitPendingCreate(name);
            });
          }
        })
      }

      // ---- 新建项目对话框（居中，初始「未命名项目」） ----
      if (this.createProjectOpen) {
        NewProjectSheet({
          onClose: () => {
            animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
              this.createProjectOpen = false;
            });
          },
          onCreateProject: (name: string, color: string, icon: string) => {
            this.createProject(name, color, icon);
          }
        })
      }

      // ---- 底部弹层（全屏遮罩，由 Sidebar 触发） ----
      this.activeSheetContent()
      if (this.coverNoteId.length > 0) {
        NoteCoverSheet({
          selected: this.notes.find((item: NoteItem) => item.id === this.coverNoteId)?.coverUrl || '',
          closeToken: this.coverCloseToken,
          onClose: () => { this.coverNoteId = ''; },
          onSave: (source: string) => this.updateNoteCover(this.coverNoteId, source)
        })
      }
      if (this.toastVisible) {
        Column() {
          Row({ space: 4 }) {
            Text(this.toastMessage)
              .fontSize(13)
              .fontColor(Color.White)
              .padding({ left: 14, right: this.undoVisible ? 2 : 14, top: 9, bottom: 9 })

            if (this.undoVisible) {
              Text('撤销')
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor('#8AB4F8')
                .padding({ left: 8, right: 14, top: 9, bottom: 9 })
                .onClick(() => this.runUndo())
            }
          }
          .borderRadius(8)
          .backgroundColor('rgba(32,32,32,0.92)')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: 48 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
  }
}
