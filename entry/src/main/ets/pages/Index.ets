import { copyNote } from '../common/utils/NoteSnapshot';
import { AnimationTokens } from '../common/constants/DesignTokens';
import { AI_FEATURES_VISIBLE } from '../common/constants/RuntimeCapabilities';
/**
 * 墨语 (FlowMind) 顶层装配器
 *
 * 持有全局状态、导航和现有工作区操作，装配 AppShell 与 views/ 下的组件。
 * 阅读器保存、学习资料恢复逐步下沉到独立用例服务；其余业务操作仍在迁移中。
 *
 * 布局、样式与响应式决策一律下沉到 views/，此处不再出现大段 UI 构建代码。
 */
import { common } from '@kit.AbilityKit';
import { curves, KeyboardAvoidMode, promptAction } from '@kit.ArkUI';
import { NoteItem } from '../common/types/NoteItem';
import { ReaderSaveKind } from '../common/types/ReaderSaveKind';
import { SerialTaskQueue } from '../services/storage/SerialTaskQueue';
import { WorkspaceNotePolicy } from '../services/WorkspaceNotePolicy';
import { SpaceFolder } from '../common/types/SpaceFolder';
import { LinkGraph, Backlink, UnresolvedLink } from '../common/types/LinkGraph';
import { MarkdownOutlineItem } from '../common/types/MarkdownOutlineItem';
import { WorkspaceStats } from '../common/types/WorkspaceStats';
import { DocumentTransferResult, MarkdownDocument } from '../common/types/MarkdownDocument';
import { TodoItem, DayNote } from '../common/types/TodoItem';
import {
  CATEGORY_UNFILED,
  FILTER_ALL,
  NAV_CANVAS,
  NAV_FAVORITE,
  NAV_GRAPH,
  NAV_HOME,
  NAV_SETTINGS,
  NAV_LIBRARY,
  NAV_TODO,
  NAV_TRASH,
  SAVE_IDLE,
  SAVE_SAVING,
  SAVE_FAILED,
  TRASH_RETENTION_DAYS
} from '../common/constants/WorkspaceConstants';
import { NoteStorageService } from '../services/NoteStorageService';
import { PdfDocumentService } from '../services/document/PdfDocumentService';
import { LocalPdfEngineHost } from '../views/reader/pdf/LocalPdfEngineHost';
import { NoteCoverService } from '../services/NoteCoverService';
import { NoteSearchService } from '../services/NoteSearchService';
import { LibraryPolicy } from '../services/library/LibraryPolicy';
import { LibraryPreferencesService, LibraryPreferences } from '../services/library/LibraryPreferencesService';
import { ReadingProgressPolicy } from '../services/document/ReadingProgressPolicy';
import { MemoDraftService } from '../services/library/MemoDraftService';
import { QuickMemoService, MemoDraft } from '../services/library/QuickMemoService';
import { TodoStorageService } from '../services/TodoStorageService';
import { buildSpaces } from '../services/WorkspaceBuilder';
import { templateBody } from '../common/templates/NoteTemplates';
import { UsageGuideSheet } from '../views/settings/UsageGuideSheet';
import { AppShell } from '../views/layout/AppShell';
import { HomeWorkspace } from '../views/workspace/HomeWorkspace';
import { LibraryWorkspace } from '../views/workspace/LibraryWorkspace';
import { GraphWorkspace } from '../views/workspace/GraphWorkspace';
import { TodoWorkspace } from '../views/workspace/TodoWorkspace';
import { TrashedProject } from '../common/types/TrashedProject';
import { WorkspaceLifecycle, WorkspaceState } from '../services/library/WorkspaceLifecycle';
import { TrashWorkspace } from '../views/workspace/TrashWorkspace';
import { FavoriteWorkspace } from '../views/workspace/FavoriteWorkspace';
import { ReaderPairPolicy } from '../services/document/ReaderPairPolicy';
import { ReaderPairPicker } from '../views/reader/ReaderPairPicker';
import { ReaderSplitWorkspace } from '../views/reader/ReaderSplitWorkspace';
import { ContextDrawer, CONTEXT_TAB_OUTLINE } from '../views/context/ContextDrawer';
import { QuickSearchDialog } from '../views/explore/QuickSearchDialog';
import { SettingsWorkspace } from '../views/settings/SettingsWorkspace';
import { NewProjectSheet } from '../views/layout/sheets/NewProjectSheet';
import { CreateNoteSheet } from '../views/layout/sheets/CreateNoteSheet';
import { ProjectMenuSheet } from '../views/layout/sheets/ProjectMenuSheet';
import { NewContentSheet } from '../views/layout/sheets/NewContentSheet';
import { TemplateSheet } from '../views/layout/sheets/TemplateSheet';
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
  @State settingsSection: string = 'overview';
  @State settingsBackToken: number = 0;
  @State settingsExitToken: number = 0;
  @State settingsOpenToken: number = 0;
  private settingsExitAction: (() => void) | null = null;
  @State activeSpaceId: string = '';
  @State activeNoteId: string = '';
  @State sidebarCollapsed: boolean = false;
  @State contextPanelOpen: boolean = true;
  @State contextTab: string = CONTEXT_TAB_OUTLINE;

  // ---- 资料库筛选 ----
  @State searchText: string = '';
  @State activeFilter: string = FILTER_ALL;

  // ---- 本地数据 ----
  @State customProjects: SpaceFolder[] = [];
  @State projectCreateBusy: boolean = false;
  @State spaces: SpaceFolder[] = [];
  @State notes: NoteItem[] = [];
  @State trash: NoteItem[] = [];
  @State trashedProjects: TrashedProject[] = [];
  @State linkGraph: LinkGraph = EMPTY_GRAPH;
  @State stats: WorkspaceStats = EMPTY_STATS;

  // ---- 待办日历 ----
  @State todos: TodoItem[] = [];
  @State dayNotes: DayNote[] = [];

  private noteMutationQueue: SerialTaskQueue = new SerialTaskQueue();

  // ---- 研读态 (速记与 Markdown 随笔) ----
  @State readingOpen: boolean = false;
  @State readingNote: NoteItem = EMPTY_NOTE;
  @State saveState: string = SAVE_IDLE;
  @State outlineItems: MarkdownOutlineItem[] = [];
  @State jumpToken: number = 0;
  @State jumpLine: number = -1;

  // ---- 独立全屏文档态 (PDF / 试卷 / 稿纸手写) ----
  @State fullScreenDocOpen: boolean = false;
  @State readerTabIds: string[] = [];
  @State private companionNoteId: string = '';
  @State private pairPickerSourceId: string = '';
  @State private pairPickerCloseToken: number = 0;
  @State fullScreenDocNote: NoteItem = EMPTY_NOTE;
  // Full-screen reader autosave must not rebuild AppShell/Library behind it. The reader owns
  // its own busy/failed UI; this mirror is only consulted by navigation guards and on exit.
  private readerSaveState: string = SAVE_IDLE;
  private readingOpenTimer: number = -1;
  private pendingReadOpenedAt: Map<string, number> = new Map();

  // ---- 全局浮层 ----
  @State searchVisible: boolean = false;
  @State smartExtractVisible: boolean = false;
  @State smartExtractCloseToken: number = 0;
  @State coverNoteId: string = '';
  @State coverCloseToken: number = 0;
  @State documentBackToken: number = 0;
  @State readerBackToken: number = 0;
  @State reviewCards: ReviewCard[] = [];
  @State studyVisible: boolean = false;
  @State studyCourse: string = '';
  @State studyCloseToken: number = 0;
  @State backupVisible: boolean = false;
  @State backupCloseToken: number = 0;
  @State privacyVisible: boolean = false;
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
  @State noteCreateBusy: boolean = false;
  private documentImportBusy: boolean = false;
  @State noteCreateError: string = '';
  /** 新建项目对话框 */
  @State createProjectOpen: boolean = false;
  /** 底部弹层类型：'project_menu' | 'new_content' | 'rename_project' | 'note_menu' | 'rename_note' | 'move_note' */
  @State activeSheet: string = '';
  @State sheetProject: SpaceFolder | null = null;
  @State sheetNote: NoteItem | null = null;
  @State private sheetCloseToken: number = 0;

  private storage: NoteStorageService = new NoteStorageService();
  private readerCommits: ReaderCommitService = new ReaderCommitService();
  private libraryPreferences: LibraryPreferencesService = new LibraryPreferencesService();
  @State private libraryDisplay: LibraryPreferences = { view: 'shelf', sort: 'update', ascending: false };
  @State private libraryDisplayBusy: boolean = false;
  private memoDraftStore: MemoDraftService = new MemoDraftService();
  private memoDraftId: string = `memo_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
  private memoDraftRevision: number = 0;
  private memoDraftTimer: number = -1;
  @State private memoDraft: string = '';
  @State private memoDraftStatus: string = '';
  @State private memoSaving: boolean = false;
  @State private memoReady: boolean = false;
  @State private memoDateFilter: string = '';
  @State private memoTagFilter: string = '';
  private searchService: NoteSearchService = new NoteSearchService();
  private graphRequestId: number = 0;
  private todoStorage: TodoStorageService = new TodoStorageService();
  private toastTimer: number = -1;
  private bootstrapped: boolean = false;
  @State private workspaceLoading: boolean = true;

  /**
   * 最近一次可撤销的回收操作。原件在软删除阶段保留，状态事务成功后提供短时撤销句柄，
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
    if (this.pairPickerSourceId) { this.pairPickerCloseToken++; return true; }
    if (this.privacyVisible) { this.privacyVisible = false; return true; }
    if (this.backupVisible) { this.backupCloseToken++; return true; }
    if (this.studyVisible) { this.studyCloseToken++; return true; }
    if (this.pdfExtractNoteId) { this.pdfExtractCloseToken++; return true; }
    if (this.coverNoteId.length > 0) { this.coverCloseToken++; return true; }
    if (this.activeSheet === 'rename_note' || this.activeSheet === 'move_note') { this.sheetCloseToken++; return true; }
    if (this.activeSheet.length > 0) { this.closeSheet(); return true; }
    if (this.createProjectOpen) { this.createProjectOpen = false; return true; }
    if (this.pendingCreate !== null) { if (!this.noteCreateBusy) { this.pendingCreate = null; } return true; }
    if (this.smartExtractVisible) { this.smartExtractCloseToken++; return true; }
    if (this.searchVisible) { this.searchVisible = false; return true; }
    if (this.fullScreenDocOpen) { this.documentBackToken++; return true; }
    if (this.singleColumn && this.contextPanelOpen) { this.contextPanelOpen = false; return true; }
    if (this.singleColumn && !this.sidebarCollapsed) { this.sidebarCollapsed = true; return true; }
    if (this.readingOpen) { this.readerBackToken++; return true; }
    if (this.activeNav === NAV_SETTINGS) { this.settingsBackToken++; return true; }
    if (this.activeNav !== NAV_HOME) { this.activeNav = NAV_HOME; this.activeSpaceId = ''; return true; }
    return false;
  }

  private closeReading(): void {
    if (this.saveState !== SAVE_IDLE) {
      this.notify(this.saveState === SAVE_SAVING ? '正在保存，请稍候再返回' : '保存失败，请先重试保存');
      return;
    }
    this.readingOpen = false;
    this.activeNoteId = '';
    this.outlineItems = [];
    this.flushReadingOpens();
    // Reader autosave mutates the shared note in place; refresh the collection identity once
    // so the library/graph see the latest body and metadata.
    this.notes = this.notes.slice();
  }

  private previousKeyboardMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode);
    if (this.readingOpenTimer !== -1) { clearTimeout(this.readingOpenTimer); this.readingOpenTimer = -1; }
    this.flushReadingOpens();
  }

  aboutToAppear(): void {
    this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    if (!this.bootstrapped) {
      this.bootstrapped = true;
      this.bootstrap();
    }
  }

  // ==================================================================
  // 启动与本地数据
  // ==================================================================

  private async bootstrap(): Promise<void> {
    try { await this.loadWorkspace(); }
    catch { this.notify('本机资料初始化未完成，请保留原数据并重启重试'); }
    finally { this.workspaceLoading = false; }
  }

  private async loadWorkspace(): Promise<void> {
    const context: common.UIAbilityContext = this.getAbilityContext();
    PdfDocumentService.getInstance().bindContext(context);
    try { this.libraryDisplay = await this.libraryPreferences.load(context); }
    catch { this.notify('资料库显示设置读取失败，已使用默认显示；原设置已保留'); }
    let draftReady: boolean = true;
    let notesReady: boolean = false;
    try {
      const draft = await this.memoDraftStore.load(context);
      if (draft) { this.memoDraft = draft.content; this.memoDraftId = draft.id; this.memoDraftStatus = draft.content ? '已恢复本机草稿' : ''; }
    } catch { draftReady = false; this.memoDraftStatus = '草稿读取失败，原数据已保留'; }
    try {
      await this.storage.enableRelational(context);
      const loaded: NoteItem[] = await this.storage.load(context, []);
      this.notes = loaded;
      notesReady = true;
      try { this.notes = await this.storage.ensureDebugPdf(context, loaded); }
      catch (error) {
        console.warn(`内置阅读示例加载失败: ${JSON.stringify(error)}`);
        this.notify('内置阅读示例未能加入，可在使用指引中重试导入');
      }
    } catch (error) {
      console.error(`本地笔记加载失败: ${JSON.stringify(error)}`);
      this.notes = [];
      this.notify('本地笔记读取失败，原数据已保留，请检查存储后重试');
    }
    // 恢复用户自建项目。此前 customProjects 只存在于内存，重启即丢，
    // 表现为「建完项目再打开就没了」。首次运行没有快照时回退到默认项目。
    try {
      const savedProjects: SpaceFolder[] | null = await this.storage.loadProjects(context);
      this.customProjects = savedProjects !== null ? savedProjects : [];
    } catch (error) {
      console.error(`项目列表加载失败: ${JSON.stringify(error)}`);
      this.customProjects = [];
    }
    this.backfillNoteMeta();
    this.rebuildSpaces();
    this.activeSpaceId = '';
    await this.persistSnapshot();
    this.refreshGraph();
    await this.loadTrash(context);
    await this.loadTodos(context);
    try { this.reviewCards = await this.reviewStorage.load(context); }
    catch { this.notify('复习记录读取失败，原数据已保留'); }
    this.memoReady = draftReady && notesReady;
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
      this.trashedProjects = await this.storage.loadTrashedProjects(context);
      const now: number = Date.now();
      const keep: NoteItem[] = [];
      const expired: NoteItem[] = [];
      for (let i = 0; i < stored.length; i++) {
        const rawDeletedAt: number | undefined = stored[i].deletedAt;
        const deletedAt: number = Number.isFinite(rawDeletedAt) && (rawDeletedAt || 0) > 0 ? rawDeletedAt! : now;
        const ageDays: number = (now - deletedAt) / (24 * 60 * 60 * 1000);
        if (ageDays > TRASH_RETENTION_DAYS) {
          expired.push(stored[i]);
        } else {
          keep.push(stored[i]);
        }
      }
      const retainedIds = new Set(keep.map((note: NoteItem) => note.id));
      const groups = this.trashedProjects.filter((group: TrashedProject) =>
        now - group.deletedAt <= TRASH_RETENTION_DAYS * 86400000 || group.noteIds.some((id: string) => retainedIds.has(id)));
      if (expired.length > 0 || groups.length !== this.trashedProjects.length) {
        await this.storage.saveWorkspace(context, this.notes, this.customProjects, keep, groups, expired);
      }
      this.trash = keep; this.trashedProjects = groups;
      try {
        const remaining = await this.storage.cleanupPendingDeletions(context, this.notes.concat(keep));
        if (remaining > 0) { this.notify('部分过期文件尚未清理，将在下次启动时重试'); }
      } catch { this.notify('待清理文件尚未处理，已保留清理记录供下次启动重试'); }
    } catch (error) {
      console.error(`回收站加载失败: ${JSON.stringify(error)}`);
      this.trash = [];
      this.notify('回收站读取或清理失败，原记录已保留，请检查存储后重试');
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
    const id = ++this.graphRequestId; const notes = this.notes;
    const cancelled = (): boolean => id !== this.graphRequestId || notes !== this.notes;
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      const graph = await this.searchService.buildLinkGraph(context, notes, cancelled);
      if (cancelled()) { return; }
      this.linkGraph = graph;
    } catch (error) {
      if (cancelled()) { return; }
      console.error(`双链图谱构建失败: ${JSON.stringify(error)}`);
      this.notify('图谱暂时无法更新，已保留上次结果。请检查资料后重试。');
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
    return LibraryPolicy.query(this.notes, { keyword: this.searchText, category: this.activeSpaceName(), type: this.activeFilter });
  }

  private async updateLibraryDisplay(view: string, sort: string, ascending: boolean): Promise<void> {
    if (this.libraryDisplayBusy) { return; }
    this.libraryDisplayBusy = true;
    const next: LibraryPreferences = { view, sort, ascending };
    try {
      await this.libraryPreferences.save(this.getAbilityContext(), next); this.libraryDisplay = next;
      if (view === 'timeline') { this.activeFilter = 'Markdown'; }
    }
    catch { this.notify('资料库显示设置未能保存，请重试'); }
    finally { this.libraryDisplayBusy = false; }
  }

  private activeSpaceName(): string {
    for (let i = 0; i < this.spaces.length; i++) {
      if (this.spaces[i].id === this.activeSpaceId) {
        return this.spaces[i].name;
      }
    }
    return '';
  }

  private changeMemoDraft(value: string): void {
    if (!this.memoReady || this.memoSaving) { return; }
    this.memoDraft = value.slice(0, 12000); this.memoDraftRevision++;
    this.memoDraftStatus = '草稿保存中';
    if (this.memoDraftTimer !== -1) { clearTimeout(this.memoDraftTimer); }
    this.memoDraftTimer = setTimeout(() => { this.persistMemoDraft().catch(() => {}); }, 500);
  }

  private async persistMemoDraft(): Promise<void> {
    if (this.memoDraftTimer !== -1) { clearTimeout(this.memoDraftTimer); this.memoDraftTimer = -1; }
    const revision = this.memoDraftRevision;
    const draft: MemoDraft = { id: this.memoDraftId, content: this.memoDraft };
    try {
      await this.memoDraftStore.save(this.getAbilityContext(), draft);
      if (revision === this.memoDraftRevision) { this.memoDraftStatus = draft.content ? '草稿已保存到本机' : ''; }
    } catch {
      if (revision === this.memoDraftRevision) { this.memoDraftStatus = '草稿未能保存'; }
      throw new Error('草稿保存失败');
    }
  }

  onPageHide(): void {
    if (this.memoDraftTimer !== -1) { this.persistMemoDraft().catch(() => {}); }
  }

  private async saveQuickMemo(): Promise<void> {
    if (!this.memoReady || this.memoSaving || !this.memoDraft.trim()) { return; }
    this.memoSaving = true;
    const draft: MemoDraft = { id: this.memoDraftId, content: this.memoDraft };
    try {
      await this.persistMemoDraft();
      await this.noteMutationQueue.run<void>(() => QuickMemoService.commit(draft, {
        notes: () => this.notes,
        create: async (note: NoteItem) => { await this.storage.create(this.getAbilityContext(), note); },
        saveNotes: (notes: NoteItem[]) => this.storage.save(notes),
        publish: (notes: NoteItem[]) => { this.notes = notes; this.rebuildSpaces(); this.refreshGraph(); }
      }));
      this.memoDateFilter = ''; this.memoTagFilter = '';
      this.memoDraft = ''; this.memoDraftRevision++;
      this.memoDraftId = `memo_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
      try { await this.persistMemoDraft(); this.memoDraftStatus = '已保存为本机笔记'; }
      catch { this.notify('笔记已保存，草稿清理未完成；重试不会重复创建原记录'); }
    } catch (error) { this.notify(error instanceof Error ? error.message : '记录保存失败，草稿已保留'); }
    finally { this.memoSaving = false; }
  }

  private openMemoTag(tag: string): void {
    this.searchText = '#' + tag; this.activeFilter = FILTER_ALL; this.activeSpaceId = '';
    this.activeNav = NAV_LIBRARY;
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

  /** Prepare outside the queue, then merge the cover into the latest committed note. */
  private async updateNoteCover(noteId: string, uri: string): Promise<void> {
    const context = this.getAbilityContext();
    const source = await NoteCoverService.prepare(context, noteId, uri);
    let previous = '';
    try {
      await this.noteMutationQueue.run<void>(async () => {
        const note = this.findNoteById(noteId);
        if (!note) { throw new Error('资料已移走，请重新打开'); }
        previous = note.coverUrl || '';
        const updated = copyNote(note); updated.coverUrl = source;
        updated.updatedAt = Date.now(); updated.updateTime = '刚刚';
        await this.saveLinkedNote(updated);
      });
    } catch {
      if (source && !this.notes.concat(this.trash).some((item: NoteItem) => item.coverUrl === source)) {
        try { await NoteCoverService.removeManaged(context, source); } catch { /* Preserve the save error. */ }
      }
      throw new Error('封面未能保存，请重试');
    }
    if (source !== previous && !this.notes.concat(this.trash).some((item: NoteItem) => item.coverUrl === previous)) {
      try { await NoteCoverService.removeManaged(context, previous); } catch { console.warn('旧封面清理失败'); }
    }
    this.notify(source ? '封面已保存' : '封面已移除');
  }

  private openNoteMenu(note: NoteItem): void {
    const current = this.notes.find((item: NoteItem) => item.id === note.id && !item.deletedAt);
    if (!current) { this.notify('资料已移走，请刷新后重试'); return; }
    this.sheetNote = current; this.sheetProject = null; this.activeSheet = 'note_menu';
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
    if (this.activeSheet === 'usage_guide') {
      UsageGuideSheet({ onClose: () => this.closeSheet() })
    } else if (this.activeSheet === 'project_menu' && this.sheetProject !== null) {
      ProjectMenuSheet({
        project: this.sheetProject,
        onClose: () => this.closeSheet(),
          onCreateNoteInProject: (title: string, projectName: string, type: string) => {
          this.closeSheet();
          if (type === 'Doc') { this.importDocument(projectName); }
          else { this.requestCreateNote(projectName, type, title); }
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
          if (type === 'Doc') { this.importDocument(projectName); }
          else { this.requestCreateNote(projectName, type, title); }
        },
        onImportIntoProject: (projectName: string) => {
          this.closeSheet();
          this.importDocument(projectName);
        },
        onRequestTemplate: () => { this.activeSheet = 'template'; }
      })
    } else if (this.activeSheet === 'template' && this.sheetProject !== null) {
      TemplateSheet({ projectName: this.sheetProject.name, onClose: () => this.closeSheet(),
        onPickTemplate: (name: string, project: string) => { this.createNoteFromTemplate(name, project); } })
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
        note: this.sheetNote, closeToken: this.sheetCloseToken,
        onClose: () => this.closeSheet(),
        onRenameNote: (note: NoteItem, newTitle: string) => this.commitRename(note, newTitle)
      })
    } else if (this.activeSheet === 'move_note' && this.sheetNote !== null) {
      MoveNoteSheet({
        note: this.sheetNote, closeToken: this.sheetCloseToken,
        categories: this.allCategories(),
        onClose: () => this.closeSheet(),
        onMoveNote: (note: NoteItem, category: string) => this.commitMove(note, category)
      })
    }
  }

  /** 点击面包屑：分类段 → 回到资料库并按分类筛选；标题段 → 打开文档切换搜索 */
  private onBreadcrumbClick(index: number, segment: string): void {
    if (this.activeNav === NAV_SETTINGS) { this.afterSettingsExit(() => this.onBreadcrumbClick(index, segment)); return; }
    if (this.readingOpen || this.fullScreenDocOpen) {
      if (index === 0) {
        if ((this.fullScreenDocOpen && this.readerSaveState !== undefined ? this.readerSaveState : this.saveState) !== SAVE_IDLE) { this.notify('请先完成或重试资料保存'); return; }
        // 点击分类名：关闭当前文档，回到资料库并选中该项目
        if (this.readingOpen) { this.readingOpen = false; this.activeNoteId = ''; this.notes = this.notes.slice(); }
        else { this.closeFullScreenReader(); }
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
    return note.sourceType === 'pdf' || note.sourceType === 'image' || t === 'image' || t === 'pdf' || t === 'doc' || t === 'docx' || t === 'canvas' || t === '白板' ||
      t === '白纸笔记' || t === 'handwriting' || t === '稿纸' || cat === '试卷题库' ||
      note.id === 'note-seed-exam' || note.id === 'note-seed-pdf' || note.id === 'note-seed-handwriting';
  }

  /**
   * Opening a document is a navigation action, not an edit. Persist the "recently opened"
   * timestamp after a short idle window and coalesce rapid tab clicks into one snapshot write
   * instead of blocking the first PDF parse behind a full-library save.
   */
  private markReadingOpened(noteId: string): void {
    this.pendingReadOpenedAt.set(noteId, Date.now());
    if (this.readingOpenTimer !== -1) { clearTimeout(this.readingOpenTimer); }
    this.readingOpenTimer = setTimeout(() => {
      this.readingOpenTimer = -1;
      this.flushReadingOpens();
    }, 1200);
  }

  private flushReadingOpens(): void {
    if (this.pendingReadOpenedAt.size === 0) { return; }
    const pending: Map<string, number> = new Map();
    for (const noteId of this.pendingReadOpenedAt.keys()) {
      pending.set(noteId, this.pendingReadOpenedAt.get(noteId) || 0);
    }
    this.pendingReadOpenedAt.clear();
    this.noteMutationQueue.run<void>(async () => {
      let changed = false;
      for (const noteId of Array.from(pending.keys())) {
        const note = this.notes.find((item: NoteItem) => item.id === noteId);
        const openedAt = pending.get(noteId) || 0;
        if (note !== undefined && openedAt > (note.lastReadAt || 0)) {
          note.lastReadAt = openedAt;
          changed = true;
        }
      }
      if (changed) { await this.storage.save(this.notes); }
    }).catch(() => this.notify('阅读记录未能保存，请检查存储后重试'));
  }

  private closeFullScreenReader(): void {
    this.flushReadingOpens();
    this.readerSaveState = SAVE_IDLE;
    this.saveState = SAVE_IDLE;
    this.companionNoteId = '';
    this.fullScreenDocOpen = false;
    this.activeNoteId = '';
    // Refresh collection identity once on exit so the library sees the annotations/readPage
    // written through the in-place reader publish path.
    this.notes = this.notes.slice();
  }

  private openNote(note: NoteItem, preserveCompanion: boolean = false): void {
    if ((this.readingOpen || this.fullScreenDocOpen) && (this.fullScreenDocOpen && this.readerSaveState !== undefined ? this.readerSaveState : this.saveState) !== SAVE_IDLE) {
      this.notify('请先完成或重试当前资料保存'); return;
    }
    if (this.activeNav === NAV_SETTINGS) { this.afterSettingsExit(() => this.openNote(note, preserveCompanion)); return; }
    const current = this.notes.find((item: NoteItem) => item.id === note.id);
    if (!current) { this.notify('笔记已被移走'); return; }
    note = current;
    if (!preserveCompanion || !ReaderPairPolicy.isReadable(note) || note.id === this.companionNoteId) { this.companionNoteId = ''; }
    this.sourcePage = ReadingProgressPolicy.page(note);
    if (!WorkspaceNotePolicy.isFreeCanvas(note)) {
      if (this.markReadingOpened !== undefined) { this.markReadingOpened(note.id); }
      else if (this.recordReading !== undefined) { this.recordReading(note.id).catch(() => {}); }
    }
    this.dismissNavigationOverlay();
    if (!WorkspaceNotePolicy.isFreeCanvas(note) && !this.readerTabIds.includes(note.id)) { this.readerTabIds = [...this.readerTabIds, note.id].slice(-8); }
    if (this.isHeavyDocument(note)) {
      // PDF / 试卷 / 稿纸手写：进入独立全屏华为风阅读器工作台
      this.readerSaveState = SAVE_IDLE;
      this.fullScreenDocNote = note;
      animateTo({ duration: WorkspaceNotePolicy.isFreeCanvas(note) ? AnimationTokens.DURATION_FAST : AnimationTokens.DURATION_PAGE_TRANSITION, curve: AnimationTokens.CURVE_STANDARD }, () => {
        this.fullScreenDocOpen = true;
      });
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
    this.readerSaveState = SAVE_IDLE;
    this.fullScreenDocOpen = false;
    PdfDocumentService.getInstance().clearPageCache();
    this.notes = this.notes.slice();
  }

  private openNoteById(noteId: string, preserveCompanion: boolean = false): void {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === noteId) {
        this.openNote(this.notes[i], preserveCompanion);
        return;
      }
    }
    this.notify('目标笔记不存在');
  }

  private openPairPicker(sourceId: string): void {
    if ((this.fullScreenDocOpen && this.readerSaveState !== undefined ? this.readerSaveState : this.saveState) !== SAVE_IDLE) { this.notify('请先完成或重试当前资料保存'); return; }
    const source = this.notes.find((note: NoteItem) => note.id === sourceId);
    if (!source || !ReaderPairPolicy.isReadable(source)) { this.notify('当前资料格式暂不支持分屏'); return; }
    this.pairPickerSourceId = sourceId;
  }

  private async selectReaderPair(otherId: string, requestedSourceId: string = ''): Promise<boolean> {
    if ((this.fullScreenDocOpen && this.readerSaveState !== undefined ? this.readerSaveState : this.saveState) !== SAVE_IDLE) { throw new Error('当前资料尚未保存，请先完成保存'); }
    const sourceId = requestedSourceId || this.pairPickerSourceId;
    const source = this.notes.find((note: NoteItem) => note.id === sourceId);
    const other = this.notes.find((note: NoteItem) => note.id === otherId);
    if (!source || !other) { throw new Error('资料已移走，请重新选择'); }
    const pair = ReaderPairPolicy.pair(source, other);
    await this.recordReading(pair.secondaryId);
    const current = this.notes.find((note: NoteItem) => note.id === pair.primaryId);
    const secondary = this.notes.find((note: NoteItem) => note.id === pair.secondaryId);
    if (!current || !secondary) { throw new Error('资料已移走，请重新选择'); }
    ReaderPairPolicy.pair(current, secondary);
    if ((this.fullScreenDocOpen && this.readerSaveState !== undefined ? this.readerSaveState : this.saveState) !== SAVE_IDLE || (requestedSourceId ? (this.readingOpen ? this.readingNote.id : this.fullScreenDocNote.id) !== sourceId : this.pairPickerSourceId !== sourceId)) {
      throw new Error('阅读状态已改变，请重新选择');
    }
    if ((!this.fullScreenDocOpen || this.fullScreenDocNote.id !== current.id) && (!this.readingOpen || this.readingNote.id !== current.id)) { this.openNote(current); }
    if ((!this.fullScreenDocOpen || this.fullScreenDocNote.id !== current.id) && (!this.readingOpen || this.readingNote.id !== current.id)) { return false; }
    this.readerTabIds = ReaderPairPolicy.rememberTabs(this.readerTabIds, current.id, secondary.id);
    this.companionNoteId = secondary.id;
    return true;
  }

  private async splitReaderDocument(id: string): Promise<void> {
    try { await this.selectReaderPair(id, this.readingOpen ? this.readingNote.id : this.fullScreenDocNote.id); }
    catch (error) { this.notify(error instanceof Error ? error.message : '分屏未能打开，请重试'); }
  }

  private pairedDocument(): NoteItem | null {
    return this.notes.find((note: NoteItem) => note.id === this.companionNoteId && note.id !== this.activeNoteId && ReaderPairPolicy.isReadable(note)) || null;
  }

  private readerDocuments(): NoteItem[] {
    const tabs: NoteItem[] = [];
    for (const id of this.readerTabIds) {
      const note = this.notes.find((item: NoteItem) => item.id === id && !item.deletedAt);
      if (note && ReaderPairPolicy.isReadable(note)) { tabs.push(note); }
    }
    return tabs;
  }

  private closeReaderTab(id: string): void {
    if ((this.readingOpen || this.fullScreenDocOpen) && ((this.readingOpen ? this.readingNote.id : this.fullScreenDocNote.id) === id || this.companionNoteId === id) && (this.fullScreenDocOpen && this.readerSaveState !== undefined ? this.readerSaveState : this.saveState) !== SAVE_IDLE) {
      this.notify('请先完成或重试当前资料保存'); return;
    }
    const index = this.readerTabIds.indexOf(id);
    this.readerTabIds = this.readerTabIds.filter((value: string) => value !== id);
    if (this.companionNoteId === id) { this.companionNoteId = ''; }
    if ((this.readingOpen ? this.readingNote.id : this.fullScreenDocNote.id) !== id) { return; }
    const tabs = this.readerDocuments();
    const next = tabs[Math.max(0, Math.min(index, tabs.length - 1))];
    if (next) { this.openNote(next, true); }
    else if (this.readingOpen) { this.closeReading(); }
    else if (this.closeFullScreenReader !== undefined) { this.closeFullScreenReader(); }
    else { this.fullScreenDocOpen = false; this.readingOpen = false; this.activeNoteId = ''; this.companionNoteId = ''; }
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
    const id = this.pdfExtractNoteId;
    const captured: PdfTextPage[] = pages.map((page: PdfTextPage): PdfTextPage => ({ pageNumber: page.pageNumber,
      text: page.text, method: page.method, extractedAt: page.extractedAt }));
    const saved = await this.updateNoteMetadata(id, (note: NoteItem) => { note.pdfTextJson = StudySourceService.merge(note, captured); });
    if (!saved) { throw new Error('校对文字保存失败，输入已保留，请重试'); }
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
    if (this.noteCreateBusy) { return; }
    this.noteCreateError = '';
    const pending: PendingNoteCreate = {
      projectName: projectName,
      type: /^(canvas|handwriting)$/i.test(type) ? 'Handwriting' : 'Markdown',
      defaultName: defaultName
    };
    animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
      this.pendingCreate = pending;
    });
  }

  /** 命名层确认：按意图分发到全局新建或项目内新建。 */
  private async commitPendingCreate(name: string, projectName?: string, tags: string[] = []): Promise<void> {
    if (this.noteCreateBusy) { return; }
    const pending: PendingNoteCreate | null = this.pendingCreate;
    if (pending === null) {
      return;
    }
    const ok = await this.createNote(name, pending.type, projectName === undefined ? pending.projectName || this.activeSpaceName() : projectName, '', tags);
    if (ok) { this.pendingCreate = null; }
  }

  /** 命名层默认标题（取自待创建意图）。 */
  private pendingDefaultName(): string {
    const pending: PendingNoteCreate | null = this.pendingCreate;
    return pending !== null ? pending.defaultName : '未命名笔记';
  }

  private async createNote(title: string, type: string = 'Markdown', projectName: string = this.activeSpaceName(), body: string = '', tags: string[] = []): Promise<boolean> {
    if (this.noteCreateBusy) { return false; }
    this.noteCreateBusy = true;
    this.noteCreateError = '';
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const now: Date = new Date();
    const category: string = projectName.trim();
    const projectId = this.spaces?.find((space: SpaceFolder) => space.name === category)?.id || '';
    const cleanTitle = title.trim() || '未命名笔记';
    const handwriting = type.toLowerCase() === 'canvas' || type.toLowerCase() === 'handwriting';
    const note: NoteItem = {
      id: `note-${now.getTime()}-${Math.floor(Math.random() * 1000000)}`,
      title: cleanTitle,
      category: category.length === 0 ? '未分类' : category,
      type: handwriting ? 'Handwriting' : 'Markdown',
      previewText: '空白笔记',
      tag: tags[0] || '',
      tagColor: '',
      updateTime: this.formatTime(now),
      contentDetail: body || `# ${cleanTitle}\n\n`,
      strokes: handwriting ? '[]' : undefined,
      tags: tags.slice(0, 12),
      createdAt: now.getTime(),
      updatedAt: now.getTime()
    };
    try {
      await this.noteMutationQueue.run<void>(async () => {
        if (projectId) { note.category = this.spaces.find((space: SpaceFolder) => space.id === projectId)?.name || CATEGORY_UNFILED; }
        await this.storage.create(context, note);
        const next = [note].concat(this.notes);
        await this.storage.save(next);
        this.notes = next;
      });
    } catch (error) {
      console.error(`Markdown 正文创建失败: ${JSON.stringify(error)}`);
      this.noteCreateError = '创建失败，请检查存储后重试';
      this.notify(this.noteCreateError);
      return false;
    } finally {
      this.noteCreateBusy = false;
    }
    this.rebuildSpaces();
    this.refreshGraph();
    this.openNote(note);
    this.notify('已创建新笔记');
    return true;
  }

  private async createProject(name: string, color: string, icon: string): Promise<boolean> {
    if (this.projectCreateBusy) { return false; }
    const trimmed = name.trim();
    if (trimmed.length === 0 || trimmed.length > 80) { this.notify('主题名称需为 1–80 字'); return false; }
    for (let i = 0; i < this.customProjects.length; i++) {
      if (this.customProjects[i].name === trimmed) {
        this.notify(`项目「${trimmed}」已存在`);
        return false;
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
    this.projectCreateBusy = true;
    try {
      await this.noteMutationQueue.run<void>(async () => {
        if (this.customProjects.some((project: SpaceFolder) => project.name === trimmed)) { throw new Error('项目名称已存在'); }
        const next = [...this.customProjects, newProj];
        await this.storage.saveProjects(this.getAbilityContext(), next);
        this.customProjects = next;
      });
      this.rebuildSpaces();
      this.notify(`已创建项目「${trimmed}」`);
      return true;
    } catch { this.notify('主题保存失败，请重试'); return false; }
    finally { this.projectCreateBusy = false; }
  }

  private workspaceState(): WorkspaceState {
    return { notes: this.notes, projects: this.customProjects, trash: this.trash, trashedProjects: this.trashedProjects };
  }

  private async commitWorkspace(next: WorkspaceState, purgeCandidates: NoteItem[] = []): Promise<void> {
    await this.storage.saveWorkspace(this.getAbilityContext(), next.notes, next.projects, next.trash, next.trashedProjects, purgeCandidates);
    this.notes = next.notes; this.customProjects = next.projects;
    this.trash = next.trash; this.trashedProjects = next.trashedProjects;
    this.readerTabIds = this.readerTabIds.filter((id: string) => next.notes.some((note: NoteItem) => note.id === id));
    if (!next.notes.some((note: NoteItem) => note.id === this.companionNoteId)) { this.companionNoteId = ''; }
    const reading = next.notes.find((note: NoteItem) => note.id === this.readingNote.id);
    const document = next.notes.find((note: NoteItem) => note.id === this.fullScreenDocNote.id);
    if (reading) { this.readingNote = reading; }
    if (document) { this.fullScreenDocNote = document; }
    if (!this.notes.some((note: NoteItem) => note.id === this.activeNoteId)) {
      this.readingOpen = false; this.fullScreenDocOpen = false; this.activeNoteId = ''; this.outlineItems = [];
      this.readerSaveState = SAVE_IDLE;
    }
    this.rebuildSpaces();
    if (!this.spaces.some((space: SpaceFolder) => space.id === this.activeSpaceId)) { this.activeSpaceId = ''; }
    this.refreshGraph();
  }

  private async renameProject(oldName: string, newName: string): Promise<void> {
    try {
      await this.noteMutationQueue.run<void>(async () => {
        const next = WorkspaceLifecycle.renameProject(this.workspaceState(), oldName, newName.trim());
        await this.commitWorkspace(next);
      });
      this.notify(`已将项目重命名为「${newName.trim()}」`);
    } catch (error) { this.notify(error instanceof Error ? error.message : '项目重命名失败，请重试'); }
  }

  private async deleteProject(projectName: string): Promise<void> {
    if (this.notes.some((note: NoteItem) => note.category === projectName && (note.id === this.activeNoteId || note.id === this.companionNoteId)) && this.saveState !== SAVE_IDLE) {
      this.notify('请等待当前资料保存完成后再删除项目'); return;
    }
    try {
      let groupId = '';
      await this.noteMutationQueue.run<void>(async () => {
        const next = WorkspaceLifecycle.deleteProject(this.workspaceState(), projectName, Date.now());
        groupId = next.trashedProjects[0].id;
        await this.commitWorkspace(next);
      });
      this.notifyUndoable(`已将项目「${projectName}」及其资料移入回收站`, () => { this.restoreTrashedProject(groupId); });
    } catch (error) { this.notify(error instanceof Error ? error.message : '项目删除失败，请重试'); }
  }

  private async restoreTrashedProject(id: string): Promise<void> {
    try {
      await this.noteMutationQueue.run<void>(async () => { await this.commitWorkspace(WorkspaceLifecycle.restoreProject(this.workspaceState(), id)); });
      this.notify('项目及其资料已恢复');
    } catch (error) { this.notify(error instanceof Error ? error.message : '项目恢复失败，请重试'); }
  }

  private async createNoteFromTemplate(templateName: string, projectName: string): Promise<boolean> {
    return this.createNote(templateName, 'Markdown', projectName, templateBody(templateName, new Date()));
  }

  private async deleteNote(noteId: string): Promise<void> {
    if ((this.activeNoteId === noteId || this.companionNoteId === noteId) && this.saveState !== SAVE_IDLE) { this.notify('请等待资料保存完成后再删除'); return; }
    try {
      await this.noteMutationQueue.run<void>(async () => { await this.commitWorkspace(WorkspaceLifecycle.deleteNote(this.workspaceState(), noteId, Date.now())); });
      this.notifyUndoable('已将资料移入回收站', () => { this.restoreFromTrashById(noteId); });
    } catch (error) { this.notify(error instanceof Error ? error.message : '删除失败，请重试'); }
  }

  private async restoreFromTrashById(id: string): Promise<void> {
    try {
      await this.noteMutationQueue.run<void>(async () => { await this.commitWorkspace(WorkspaceLifecycle.restoreNote(this.workspaceState(), id)); });
      this.notify('资料已恢复到资料库');
    } catch (error) { this.notify(error instanceof Error ? error.message : '恢复失败，请重试'); }
  }

  private async restoreFromTrash(note: NoteItem): Promise<void> { await this.restoreFromTrashById(note.id); }

  private async purgeNote(note: NoteItem): Promise<void> {
    if (!await this.confirmDestructive(`彻底删除「${note.title}」？此操作不可恢复。`)) { return; }
    try {
      await this.noteMutationQueue.run<void>(async () => {
        const current = this.trash.find((item: NoteItem) => item.id === note.id);
        if (!current) { throw new Error('回收站记录已变更，请刷新后重试'); }
        await this.commitWorkspace({ notes: this.notes, projects: this.customProjects,
          trash: this.trash.filter((item: NoteItem) => item.id !== note.id), trashedProjects: this.trashedProjects }, [current]);
        const remaining = await this.storage.cleanupPendingDeletions(this.getAbilityContext(), this.notes.concat(this.trash));
        if (remaining > 0) { throw new Error('删除记录已提交，部分文件清理待下次启动重试'); }
      });
      this.notify('已彻底删除');
    } catch (error) { this.notify(error instanceof Error ? error.message : '清理失败，已保留回收站记录供重试'); }
  }

  private async emptyTrash(): Promise<void> {
    if (this.trash.length === 0 && this.trashedProjects.length === 0) { return; }
    if (!await this.confirmDestructive(`清空回收站？${this.trash.length} 篇资料和 ${this.trashedProjects.length} 个项目将被彻底删除，不可恢复。`)) { return; }
    try {
      let remaining = 0;
      await this.noteMutationQueue.run<void>(async () => {
        const removing = this.trash.slice();
        await this.commitWorkspace({ notes: this.notes, projects: this.customProjects, trash: [], trashedProjects: [] }, removing);
        remaining = await this.storage.cleanupPendingDeletions(this.getAbilityContext(), this.notes);
      });
      this.notify(remaining > 0 ? `有 ${remaining} 份文件清理尚未完成，下次启动时重试` : '回收站已清空');
    } catch (error) { this.notify(error instanceof Error ? error.message : '回收站保存失败，请重试'); }
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

  private findNoteById(id: string): NoteItem | null {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === id) {
        return this.notes[i];
      }
    }
    return null;
  }

  private requireNote(identifier: string): NoteItem {
    const key = identifier.trim().toLowerCase();
    const byId = this.notes.find((note: NoteItem) => note.id.toLowerCase() === key);
    if (byId) { return byId; }
    const matches = this.notes.filter((note: NoteItem) => note.title.toLowerCase() === key);
    if (matches.length !== 1) { throw new Error(matches.length > 1 ? '标题对应多篇笔记，请指定笔记 ID' : `未找到笔记「${identifier}」，请提供完整标题或 ID`); }
    return matches[0];
  }

  private async saveLinkedNote(note: NoteItem, writeBody: boolean = false): Promise<void> {
    const previous = this.notes.find((item: NoteItem) => item.id === note.id);
    const context = this.getAbilityContext();
    if (writeBody && previous && ((this.readingOpen && this.readingNote.id === previous.id) ||
      (this.fullScreenDocOpen && (this.fullScreenDocNote.id === previous.id || this.companionNoteId === previous.id)))) {
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

  private async createGraphLink(identifier: string, title: string): Promise<void> {
    return this.noteMutationQueue.run<void>(async () => {
      const note = this.requireNote(identifier);
      const link = `[[${title}]]`;
      const updated = WorkspaceNotePolicy.mutate(note, 'update_note',
        note.contentDetail.includes(link) ? note.contentDetail : `${note.contentDetail}\n\n${link}\n`, note.updatedAt || 0);
      if (note.contentDetail.includes(link)) { return; }
      await this.saveLinkedNote(updated, true);
    });
  }

  // ==================================================================
  // 重命名 / 移动分类
  // ==================================================================

  /** 现有分类去重列表（含「未分类」兜底），供移动弹层选择目标。 */
  private allCategories(): string[] {
    const seen: Set<string> = new Set([CATEGORY_UNFILED]);
    const result: string[] = [CATEGORY_UNFILED];
    for (const space of this.spaces) {
      if (!seen.has(space.name)) { seen.add(space.name); result.push(space.name); }
    }
    for (let i = 0; i < this.notes.length; i++) {
      const category: string = this.notes[i].category.length === 0 ? CATEGORY_UNFILED : this.notes[i].category;
      if (!seen.has(category)) {
        seen.add(category);
        result.push(category);
      }
    }
    return result;
  }

  /** One metadata mutation reads the latest committed note inside the workspace queue. */
  private async updateNoteMetadata(id: string, change: (note: NoteItem) => void): Promise<NoteItem | null> {
    let saved: NoteItem | null = null;
    try {
      await this.noteMutationQueue.run<void>(async () => {
        const current = this.findNoteById(id);
        if (!current) { throw new Error('目标资料已不存在'); }
        const next = copyNote(current); change(next);
        await this.saveLinkedNote(next);
        saved = next;
      });
      return saved;
    } catch (error) { this.notify(error instanceof Error ? error.message : '资料保存失败，请重试'); return null; }
  }

  private async commitRename(note: NoteItem, newTitle: string): Promise<boolean> {
    const title = newTitle.trim(); if (!title || title.length > 200 || /[\r\n]/.test(title)) { return false; }
    const saved = await this.updateNoteMetadata(note.id, (next: NoteItem) => {
      next.title = title; next.updateTime = this.formatTime(new Date()); next.updatedAt = Date.now();
    });
    if (saved) { this.notify(`已重命名为「${title}」`); }
    return saved !== null;
  }

  private async commitMove(note: NoteItem, category: string): Promise<boolean> {
    const name = category.trim() || CATEGORY_UNFILED;
    const saved = await this.updateNoteMetadata(note.id, (next: NoteItem) => { next.category = name; });
    if (saved) { this.notify(name === CATEGORY_UNFILED ? '已移回资料库' : `已移动到「${name}」`); }
    return saved !== null;
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

  private async toggleFavorite(note: NoteItem): Promise<void> {
    const saved = await this.updateNoteMetadata(note.id, (next: NoteItem) => { next.favorite = next.favorite !== true; });
    if (saved) { this.notify(saved.favorite ? '已收藏' : '已取消收藏'); }
  }

  private async togglePinNote(note: NoteItem): Promise<void> {
    const saved = await this.updateNoteMetadata(note.id, (next: NoteItem) => { next.isPinned = next.isPinned !== true; });
    if (saved) { this.notify(saved.isPinned ? '已置顶' : '已取消置顶'); }
  }

  private async applyTags(note: NoteItem, tags: string[]): Promise<void> {
    const clean = Array.from(new Set(tags.map((tag: string) => tag.trim().replace(/^#/, '')).filter((tag: string) => tag.length > 0))).slice(0, 12);
    const saved = await this.updateNoteMetadata(note.id, (next: NoteItem) => {
      next.tags = clean; next.tag = clean[0] || ''; next.updatedAt = Date.now();
    });
    if (saved) { this.notify('标签已保存'); }
  }

  // ==================================================================
  // 待办日历
  // ==================================================================

  private async addTodo(dateKey: string, title: string, noteRefs: string[]): Promise<boolean> {
    try {
      await this.noteMutationQueue.run<void>(async () => {
        if (!title.trim()) { throw new Error('请填写待办内容'); }
        const now = Date.now();
        const todo: TodoItem = { id: `todo-${now}-${Math.floor(Math.random() * 1000000)}`, date: dateKey,
          title: title.trim(), done: false, noteRefs: noteRefs.slice(), createdAt: now, updatedAt: now };
        const next = [todo].concat(this.todos);
        await this.todoStorage.saveTodos(this.getAbilityContext(), next); this.todos = next;
      });
      this.notify('已添加待办'); return true;
    } catch (error) { this.notify(error instanceof Error ? error.message : '待办保存失败，请重试'); return false; }
  }

  /**
   * 将本地整理结果保存为笔记及用户选中的待办。
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
    const note = await this.noteMutationQueue.run<NoteItem>(() => SmartCaptureService.commit(content, selectedTasks, persistence));
    this.refreshStats();
    await this.refreshGraph();
    this.openNote(note);
    this.notify('已保存「' + content.title + '」与 ' + selectedTasks.length + ' 条待办');
  }

  private async toggleTodo(todo: TodoItem): Promise<void> {
    try {
      await this.noteMutationQueue.run<void>(async () => {
        const next = this.todos.map((item: TodoItem): TodoItem => item.id !== todo.id ? item :
          { id: item.id, date: item.date, title: item.title, done: !item.done, noteRefs: item.noteRefs.slice(), createdAt: item.createdAt, updatedAt: Date.now() });
        await this.todoStorage.saveTodos(this.getAbilityContext(), next); this.todos = next;
      });
    } catch (error) { this.notify(error instanceof Error ? error.message : '待办保存失败，请重试'); }
  }

  private async deleteTodo(todo: TodoItem): Promise<void> {
    try {
      await this.noteMutationQueue.run<void>(async () => {
        const next = this.todos.filter((item: TodoItem) => item.id !== todo.id);
        await this.todoStorage.saveTodos(this.getAbilityContext(), next); this.todos = next;
      });
      this.notify('已删除待办');
    } catch (error) { this.notify(error instanceof Error ? error.message : '删除待办失败，请重试'); }
  }

  private async updateDayNote(dateKey: string, text: string): Promise<void> {
    try {
      await this.noteMutationQueue.run<void>(async () => {
        const entry: DayNote = { date: dateKey, text, updatedAt: Date.now() };
        const next = [entry].concat(this.dayNotes.filter((item: DayNote) => item.date !== dateKey));
        await this.todoStorage.saveDayNotes(this.getAbilityContext(), next); this.dayNotes = next;
      });
    } catch (error) { this.notify(error instanceof Error ? error.message : '日期备忘保存失败，请保留输入后重试'); }
  }

  private freeCanvasOpening: boolean = false;

  /** Dedicated canvas identity; an ordinary handwritten note is never used as the global board. */
  private async openFreeCanvas(): Promise<void> {
    if (this.freeCanvasOpening) { return; }
    this.freeCanvasOpening = true;
    const fromNav = this.activeNav; const fromNote = this.activeNoteId;
    try {
      const existing = this.notes.find((note: NoteItem) => WorkspaceNotePolicy.isFreeCanvas(note));
      if (existing) { this.openNote(existing); return; }
      const canvasNote = await this.noteMutationQueue.run<NoteItem>(async () => {
        const current = this.notes.find((note: NoteItem) => WorkspaceNotePolicy.isFreeCanvas(note));
        if (current) { return current; }
        const occupied = this.notes.concat(this.trash).map((note: NoteItem) => note.id);
        const created = WorkspaceNotePolicy.createFreeCanvas(occupied, Date.now());
        await this.storage.create(this.getAbilityContext(), created);
        const next = [created].concat(this.notes); await this.storage.save(next); this.notes = next;
        return created;
      });
      this.rebuildSpaces(); this.refreshGraph();
      if (this.activeNav === fromNav && this.activeNoteId === fromNote) { this.openNote(canvasNote); }
    } catch (error) {
      console.error('自由白板创建失败: ' + (error instanceof Error ? error.message : '本地存储不可用'));
      this.notify('自由白板暂时无法打开，请检查存储后重试');
    }
    finally { this.freeCanvasOpening = false; }
  }

  /**
   * 通过系统文件选择器导入文档。
   * @param targetCategory 导入后归入的项目名，默认「未分类」
   */
  private async importDocument(targetCategory: string = '未分类', example: boolean = false, snapshot: boolean = false,
    selectedUri: string = ''): Promise<NoteItem | null> {
    if (this.documentImportBusy) { return null; }
    this.documentImportBusy = true;
    const targetProjectId = this.spaces?.find((space: SpaceFolder) => space.name === targetCategory)?.id || '';
    try {
      const uris = example ? [''] : selectedUri ? [selectedUri] : await this.storage.selectDocumentUris(this.getAbilityContext());
      let first: NoteItem | null = null; let imported: number = 0;
      for (let index = 0; index < uris.length; index++) {
        if (uris.length > 1) { this.notify(`正在导入 ${index + 1}/${uris.length} 份资料…`); }
        const note = await this.importOneDocument(targetCategory, example, snapshot, uris[index], targetProjectId);
        if (note) { imported++; if (first === null) { first = note; } }
      }
      if (uris.length > 1) { this.notify(`已导入 ${imported}/${uris.length} 份资料${imported < uris.length ? '，未完成的资料可重新选择导入' : ''}`); }
      if (first && (first.category === CATEGORY_UNFILED || !targetCategory.trim() || targetCategory === CATEGORY_UNFILED)) {
        this.activeNav = NAV_LIBRARY; this.activeSpaceId = ''; this.searchText = ''; this.activeFilter = FILTER_ALL;
      }
      return first;
    } catch (error) { this.notify(error instanceof Error ? error.message : '文件选择失败，请重试'); return null; }
    finally { this.documentImportBusy = false; }
  }

  private async importOneDocument(targetCategory: string, example: boolean, snapshot: boolean, selectedUri: string, targetProjectId: string = ''): Promise<NoteItem | null> {
    const context: common.UIAbilityContext = this.getAbilityContext();
    try {
      const result: DocumentTransferResult = example ? await this.storage.importExamplePdf(context, snapshot) :
        await this.storage.importDocumentUri(context, selectedUri);
      if (result.status === 'imported' && result.document !== undefined) {
        const document: MarkdownDocument = result.document;
        const now: Date = new Date();
        const isPdf: boolean = result.noteType === 'PDF' || document.title.toLowerCase().endsWith('.pdf');
        const isImage: boolean = result.noteType === 'Image';
        const note: NoteItem = {
          id: document.id,
          title: document.title,
          category: targetCategory.trim() || CATEGORY_UNFILED,
          type: result.noteType !== undefined ? result.noteType : (isPdf ? 'PDF' : 'Markdown'),
          sourceType: isImage ? 'image' : isPdf ? 'pdf' : 'document',
          sourceUri: result.sourceUri,
          sourceFileName: result.sourceFileName,
          documentMeta: result.documentMeta,
          pageCount: result.pageCount || 1,
          pageInfo: isImage ? '图片 · 独立批注' : isPdf ? (result.pageCount || 1) + ' 页' : '',
          previewText: document.content.length > 48 ? `${document.content.substring(0, 48)}…` : document.content,
          tag: isImage ? '图片资料' : isPdf ? 'PDF文献' : '导入',
          tagColor: isPdf ? '#E11D48' : '#2563EB',
          updateTime: this.formatTime(now),
          contentDetail: document.content,
          tags: isPdf ? ['PDF文献'] : ['导入'],
          createdAt: now.getTime(),
          updatedAt: now.getTime()
        };
        try {
          await this.noteMutationQueue.run<void>(async () => {
            if (targetProjectId) { note.category = this.spaces.find((space: SpaceFolder) => space.id === targetProjectId)?.name || CATEGORY_UNFILED; }
            const nextNotes = [note].concat(this.notes);
            await this.storage.save(nextNotes);
            this.notes = nextNotes;
          });
        }
        catch (error) {
          try { await this.storage.delete(context, note.id, note.sourceUri || ''); } catch { /* Keep the original failure available for retry. */ }
          throw new Error(error instanceof Error ? error.message : '本机资料保存失败，请重试');
        }
        this.rebuildSpaces();
        this.refreshGraph();
        this.notify(`已保存到本机资料库：${result.fileName || document.title}`);
        return note;
      } else if (result.status !== 'cancelled') {
        this.notify(result.message);
      }
    } catch (error) {
      console.error(`文档导入失败: ${JSON.stringify(error)}`);
      this.notify('文档导入失败');
    }
    return null;
  }

  /** Copy only the fields that the active reader edited, without replacing the notes array. */
  private applyReaderSave(target: NoteItem, saved: NoteItem, kind: ReaderSaveKind): void {
    if (kind === 'reading') {
      if ((saved.lastReadAt || 0) >= (target.lastReadAt || 0)) {
        target.lastReadAt = saved.lastReadAt;
        if (Number.isInteger(saved.readPage) && (saved.readPage || 0) > 0) { target.readPage = saved.readPage; }
      }
    } else if (kind === 'pdf') {
      target.pageAnnotations = saved.pageAnnotations;
    } else if (kind === 'scratchpad') {
      target.scratchpadStrokes = saved.scratchpadStrokes;
      target.scratchpadPaperStyle = saved.scratchpadPaperStyle;
    } else if (kind === 'handwriting') {
      target.strokes = saved.strokes;
      target.paperStyle = saved.paperStyle;
      target.title = saved.title;
      target.contentDetail = saved.contentDetail;
      target.previewText = saved.previewText;
    }
    target.updatedAt = saved.updatedAt;
    target.updateTime = saved.updateTime;
  }

  private handleSaved(note: NoteItem, content: string, kind: ReaderSaveKind = 'markdown'): Promise<void> {
    const snapshot = copyNote(note);
    if (kind !== 'reading') { snapshot.updateTime = this.formatTime(new Date()); }
    return this.noteMutationQueue.run<void>(() => this.readerCommits.commit(snapshot, content, {
      notes: () => this.notes,
      saveDocument: async (item: NoteItem, text: string) => { await this.storage.saveDocument(this.getAbilityContext(), item, text); },
      saveNotes: (items: NoteItem[]) => this.storage.save(items),
      publish: (items: NoteItem[], saved: NoteItem) => {
        const previous = this.notes.find((item: NoteItem) => item.id === saved.id);
        const previousTitle = previous?.title;
        const previousContent = previous?.contentDetail;
        // Reader autosave is a hot path (annotation debounce / page turns). Replacing @State
        // notes here rebuilt AppShell, the library and the reader on every save. The reader
        // already owns the live copy, so mutate the shared note object and publish the array
        // once when the reader closes.
        const light = (kind === 'reading' || kind === 'pdf' || kind === 'scratchpad' || kind === 'handwriting') &&
          (this.fullScreenDocOpen || this.readingOpen);
        if (light) {
          if (previous !== undefined) { this.applyReaderSave(previous, saved, kind); }
          if (this.fullScreenDocNote.id === saved.id && this.fullScreenDocNote !== previous) {
            this.applyReaderSave(this.fullScreenDocNote, saved, kind);
          }
          if (this.readingNote.id === saved.id && this.readingNote !== previous) {
            this.applyReaderSave(this.readingNote, saved, kind);
          }
        } else {
          this.notes = items;
          if (this.readingNote.id === saved.id) { this.readingNote = saved; }
          if (this.fullScreenDocNote.id === saved.id) { this.fullScreenDocNote = saved; }
        }
        if (kind === 'markdown' || (kind === 'handwriting' && (previousTitle !== saved.title || previousContent !== saved.contentDetail))) { this.refreshGraph(); }
      }
    }, kind === 'markdown' || kind === 'handwriting', kind));
  }

  private recordReading(noteId: string, page?: number, visitedAt: number = Date.now()): Promise<void> {
    const current = this.notes.find((note: NoteItem) => note.id === noteId);
    if (!current) { return Promise.reject(new Error('资料已移除')); }
    const snapshot = copyNote(current);
    snapshot.lastReadAt = visitedAt;
    if (page !== undefined) { snapshot.readPage = page; }
    return this.handleSaved(snapshot, snapshot.contentDetail, 'reading');
  }

  private async restoreReaderPdfSource(note: NoteItem = this.fullScreenDocNote): Promise<void> {
    const context = this.getAbilityContext();
    const originalId = note.id;
    const previousSource = note.sourceUri || '';
    const replacement = await this.storage.selectReplacementPdf(context, note);
    if (!replacement) { return; }
    try {
      await this.handleSaved(replacement, replacement.contentDetail, 'pdf-source');
    } catch (error) {
      try { await PdfDocumentService.getInstance().removeManagedPdf(context, replacement.sourceUri || ''); }
      catch { console.warn('关联失败后的 PDF 副本清理失败'); }
      throw new Error(error instanceof Error ? error.message : '原 PDF 关联保存失败');
    }
    if (this.fullScreenDocOpen && this.fullScreenDocNote.id === originalId) {
      this.notify('原 PDF 已关联，现有批注已保留');
    }
    if (previousSource !== replacement.sourceUri && !this.notes.concat(this.trash).some((item: NoteItem) => item.sourceUri === previousSource)) {
      try { await PdfDocumentService.getInstance().removeManagedPdf(context, previousSource); }
      catch { console.warn('旧 PDF 副本清理失败'); }
    }
  }

  /** Extraction uses the exact persisted source and never relies on a picker grant after import. */
  private async importExtractSource(uri: string): Promise<string> {
    const note = await this.importDocument(CATEGORY_UNFILED, false, false, uri);
    if (!note) { throw new Error('资料未能保存到本机资料库，请重试'); }
    if (note.sourceType === 'pdf' && note.sourceUri) { return note.sourceUri; }
    return (await this.storage.read(this.getAbilityContext(), note)).filePath;
  }

  private formatTime(date: Date): string {
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const hour: string = date.getHours() < 10 ? `0${date.getHours()}` : `${date.getHours()}`;
    const minute: string = date.getMinutes() < 10 ? `0${date.getMinutes()}` : `${date.getMinutes()}`;
    return `${month}月${day}日 ${hour}:${minute}`;
  }

  private openSettings(section: string = 'overview'): void {
    if ((this.fullScreenDocOpen && this.readerSaveState !== undefined ? this.readerSaveState : this.saveState) !== SAVE_IDLE) {
      this.notify('请先完成或重试文档保存'); return;
    }
    this.readingOpen = false; this.fullScreenDocOpen = false; this.contextPanelOpen = false;
    this.readerSaveState = SAVE_IDLE;
    this.notes = this.notes.slice();
    this.activeSheet = ''; this.settingsSection = section;
    this.settingsOpenToken++;
    this.activeNav = NAV_SETTINGS; if (this.singleColumn) { this.sidebarCollapsed = true; }
  }

  private afterSettingsExit(action: () => void): void {
    if ((this.readingOpen || this.fullScreenDocOpen) && (this.fullScreenDocOpen && this.readerSaveState !== undefined ? this.readerSaveState : this.saveState) !== SAVE_IDLE) { this.notify('请先完成或重试资料保存'); return; }
    if (this.activeNav !== NAV_SETTINGS) { action(); return; }
    this.settingsExitAction = action;
    this.settingsExitToken++;
  }

  private completeSettingsExit(): void {
    const action = this.settingsExitAction;
    this.settingsExitAction = null;
    this.activeNav = NAV_HOME;
    if (action !== null) { action(); }
  }

  // ==================================================================
  // 视图装配
  // ==================================================================

  @Builder
  readerWorkspaceContent(readerNote: NoteItem) {
    ReaderSplitWorkspace({
      note: readerNote, manageKeyboardMode: false,
      documentTabs: this.readerDocuments(),
      secondaryNote: this.pairedDocument(),
      onOpenSplitPicker: () => this.openPairPicker(readerNote.id),
      onSecondaryClosed: () => { this.companionNoteId = ''; },
      onOpenNoteByTitle: (title: string) => this.openNoteByTitle(title),
      onSplitDocument: (id: string) => { this.splitReaderDocument(id); },
      onDeleteNote: (note: NoteItem) => { this.deleteNote(note.id); },
      onChooseCover: (note: NoteItem) => { this.coverNoteId = note.id; },
      onSelectDocument: (id: string) => this.openNoteById(id, true),
      onCloseDocumentTab: (id: string) => this.closeReaderTab(id),
      onCreateHandwriting: () => this.requestCreateNote('', 'Handwriting', '未命名手写笔记'),
      onRestorePdfSource: (note: NoteItem) => this.restoreReaderPdfSource(note),
      sourcePage: this.sourcePage,
      onReadingPageChange: (noteId: string, page: number, visitedAt: number) => this.recordReading(noteId, page, visitedAt),
      sourceJumpToken: this.sourceJumpToken,
      onExtractPdfText: (noteId: string, page: number) => { this.pdfExtractNoteId = noteId; this.pdfExtractPage = page; },
      backRequestToken: this.readingOpen ? this.readerBackToken : this.documentBackToken,
      jumpToken: this.jumpToken, jumpLine: this.jumpLine, onOutlineUpdated: (items: MarkdownOutlineItem[]) => { this.outlineItems = items; },
      onSmartExtract: () => { this.smartExtractVisible = true; },
      onExportText: (note: NoteItem, extension: string) => this.storage.exportDocument(this.getAbilityContext(), note, extension),
      onSearchNotes: () => { this.searchVisible = true; },
      onClose: () => {
        this.companionNoteId = '';
        if (this.readingOpen) { this.closeReading(); }
        else { this.closeFullScreenReader(); }
      },
      onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => this.handleSaved(note, content, kind),
      onSaveStateChange: (state: string) => {
        // The full-screen reader covers the shell. Updating a @State consumed by AppShell here
        // rebuilt the entire workspace (library, sidebar, reader) on every 800 ms autosave.
        if (this.fullScreenDocOpen) { this.readerSaveState = state; }
        else { this.saveState = state; }
      },
      onToggleFavorite: (note: NoteItem) => {
        this.toggleFavorite(note);
      }
    })
  }

  @Builder
  workspaceContent() {
    if (this.activeNav === NAV_SETTINGS) {
      SettingsWorkspace({ initialSection: this.settingsSection, noteCount: this.notes.length, projectCount: this.spaces.length,
        openRequestToken: this.settingsOpenToken,
        backRequestToken: this.settingsBackToken, onExit: () => { this.activeNav = NAV_HOME; },
        exitRequestToken: this.settingsExitToken, onExitConfirmed: () => this.completeSettingsExit(),
        onOpenLibrary: () => { this.activeNav = NAV_LIBRARY; },
        onImportExample: () => this.importDocument('示例资料', true),
        onImportSnapshot: () => this.importDocument('示例资料', true, true),
        onOpenCapture: () => { this.smartExtractVisible = true; },
        onOpenBackup: () => { this.backupVisible = true; }, onOpenPrivacy: () => { this.privacyVisible = true; } })
    } else if (this.readingOpen) {
      this.readerWorkspaceContent(this.readingNote)
    } else if (this.activeNav === NAV_HOME) {
      HomeWorkspace({
        memoDraft: this.memoDraft, memoStatus: this.memoDraftStatus, memoSaving: this.memoSaving, memoReady: this.memoReady,
        onMemoChange: (value: string) => this.changeMemoDraft(value),
        onSaveMemo: () => { this.saveQuickMemo(); },
        onRetryMemoDraft: () => { this.persistMemoDraft().catch(() => {}); },
        selectedDate: this.memoDateFilter, selectedTag: this.memoTagFilter,
        onSelectDate: (date: string) => { this.memoDateFilter = date; },
        onOpenTag: (tag: string) => { this.memoTagFilter = tag; },
        onClearFilters: () => { this.memoDateFilter = ''; this.memoTagFilter = ''; },
        recentNotes: this.notes,
        onSearchNotes: () => { this.searchVisible = true; },
        onSelectNote: (note: NoteItem) => this.openNote(note),
        onCreateNote: () => this.requestCreateNote('', 'Markdown', '未命名笔记'),
        onCreateHandwriting: () => this.requestCreateNote('', 'Handwriting', '未命名手写笔记'),
        onImportDocument: () => this.importDocument(),
        onSmartExtract: () => { this.smartExtractVisible = true; },
        onTogglePin: (note: NoteItem) => this.togglePinNote(note),
        onToggleFavorite: (note: NoteItem) => this.toggleFavorite(note),
        onDeleteNote: (noteId: string) => this.deleteNote(noteId),
        onNavigate: (navKey: string) => { this.activeNav = navKey; }
      })
    } else if (this.activeNav === NAV_LIBRARY) {
      LibraryWorkspace({
        onOpenTag: (tag: string) => this.openMemoTag(tag),
        notes: this.filteredNotes(),
        allNotes: this.notes,
        viewMode: this.libraryDisplay.view, sortKey: this.libraryDisplay.sort, sortAsc: this.libraryDisplay.ascending,
        onViewModeChange: (view: string) => { this.updateLibraryDisplay(view, this.libraryDisplay.sort, this.libraryDisplay.ascending); },
        onSortChange: (sort: string, ascending: boolean) => { this.updateLibraryDisplay(this.libraryDisplay.view, sort, ascending); },
        onResetFilters: () => { this.searchText = ''; this.activeFilter = FILTER_ALL; this.activeSpaceId = ''; },
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
        onOpenNoteMenu: (note: NoteItem) => this.openNoteMenu(note),
        onCreateNote: () => this.requestCreateNote('', 'Markdown', '未命名笔记'),
        onImportDocument: () => this.importDocument(this.activeSpaceName() || '未分类')
      })
    } else if (this.activeNav === NAV_GRAPH) {
      GraphWorkspace({
        graph: this.linkGraph,
        stats: this.stats,
        allNotes: this.notes,
        projects: this.customProjects,
        onSelectNoteById: (noteId: string) => this.openNoteById(noteId),
        onOpenNoteByTitle: (title: string) => this.openNoteByTitle(title),
        onLinkNodes: (sourceIdentifier: string, targetTitle: string) => {
          this.createGraphLink(sourceIdentifier, targetTitle);
        },
        onCreateGalaxy: (galaxyName: string) => this.createProject(galaxyName, '#6366F1', '🪐')
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
    } else if (this.activeNav === NAV_TODO) {
      TodoWorkspace({
        dayNotes: this.dayNotes,
        todos: this.todos,
        notes: this.notes,
        onAddTodo: (dateKey: string, title: string, noteRefs: string[]) => this.addTodo(dateKey, title, noteRefs),
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
        projects: this.trashedProjects,
        onRestoreProject: (id: string) => this.restoreTrashedProject(id),
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

    }
  }

  @Builder
  contextContent() {
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

  build() {
    Stack() {
      AppShell({
        breadcrumb: this.breadcrumb(),
        saveState: this.saveState,
        spaces: this.spaces,
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
          animateTo({ duration: AnimationTokens.duration(120), curve: Curve.EaseInOut }, () => {
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
          this.afterSettingsExit(() => {
            this.dismissNavigationOverlay();
            if (navKey === NAV_CANVAS) { this.openFreeCanvas(); return; }
            this.activeNav = navKey;
            this.readingOpen = false;
            this.closeFullScreenReader();
            this.activeNoteId = '';
          });
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
          this.afterSettingsExit(() => {
            this.dismissNavigationOverlay();
            this.activeSpaceId = this.activeSpaceId === spaceId ? '' : spaceId;
            this.activeNav = NAV_LIBRARY;
            this.readingOpen = false;
            this.closeFullScreenReader();
          });
        },
        onSelectNote: (note: NoteItem) => this.openNote(note),
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
        onOpenSettings: () => {
          this.openSettings('overview');
        }
      }).enabled(!this.workspaceLoading)
      if (this.workspaceLoading) { LoadingProgress().width(32).height(32).zIndex(1000).accessibilityText('正在读取本机资料') }

      // ---- 华为风独立全屏文档与稿纸工作台 (PDF / 试卷 / 稿纸手写) ----
      if (this.fullScreenDocOpen) {
        Column() { this.readerWorkspaceContent(this.fullScreenDocNote) }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: WorkspaceNotePolicy.isFreeCanvas(this.fullScreenDocNote) ? 0 : 8 }))
          .animation({ duration: WorkspaceNotePolicy.isFreeCanvas(this.fullScreenDocNote) ? AnimationTokens.DURATION_FAST : AnimationTokens.DURATION_PAGE_TRANSITION, curve: AnimationTokens.CURVE_STANDARD }))
      }

      if (this.pairPickerSourceId && this.notes.some((note: NoteItem) => note.id === this.pairPickerSourceId)) {
        ReaderPairPicker({ source: this.notes.find((note: NoteItem) => note.id === this.pairPickerSourceId)!, notes: this.notes,
          closeToken: this.pairPickerCloseToken,
          onClose: () => { this.pairPickerSourceId = ''; }, onSelect: (id: string) => this.selectReaderPair(id) })
      }
      if (this.privacyVisible) {
        PrivacySheet({ onClose: () => { this.privacyVisible = false; } })
      }
      if (this.backupVisible) {
        StudyBackupSheet({ notes: this.notes, spaces: this.spaces, cards: this.reviewCards, closeToken: this.backupCloseToken,
          onClose: () => { this.backupVisible = false; },
          onRestore: (note: NoteItem, cards: ReviewCard[]) => this.noteMutationQueue.run<void>(() => StudyRestoreService.commit(note, cards, {
            notes: () => this.notes, cards: () => this.reviewCards,
            create: async (item: NoteItem) => { await this.storage.create(this.getAbilityContext(), item); },
            saveNotes: (notes: NoteItem[]) => this.storage.save(notes),
            saveCards: (items: ReviewCard[]) => this.reviewStorage.save(this.getAbilityContext(), items),
            remove: (item: NoteItem) => this.storage.delete(this.getAbilityContext(), item.id, item.sourceUri || '', item.coverUrl || ''),
            publishNotes: (notes: NoteItem[]) => { this.notes = notes; this.rebuildSpaces(); this.refreshStats(); this.refreshGraph(); },
            publishCards: (items: ReviewCard[]) => { this.reviewCards = items; }
          })) })
      }
      if (this.studyVisible) {
        StudySheet({ notes: this.notes, cards: this.reviewCards, course: this.studyCourse,
          closeToken: this.studyCloseToken,
          onClose: () => { this.studyVisible = false; },
          onSave: async (cards: ReviewCard[]) => {
            const captured = ReviewPolicy.normalize(cards);
            await this.noteMutationQueue.run<void>(async () => {
              await this.reviewStorage.save(this.getAbilityContext(), captured); this.reviewCards = captured;
            });
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


      if (AI_FEATURES_VISIBLE && this.smartExtractVisible) {
        SmartExtractSheet({
          onImportSource: (uri: string) => this.importExtractSource(uri),
          onClose: () => {
            animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
              this.smartExtractVisible = false;
            });
          },
          closeToken: this.smartExtractCloseToken,
          onCommit: (content: SmartContent, selectedTasks: SmartTask[]) => {
            return this.handleCommitSmartExtract(content, selectedTasks);
          }
        })
      }

      if (this.pendingCreate !== null) {
        NameNoteSheet({
          defaultName: this.pendingDefaultName(),
          noteType: this.pendingCreate?.type || 'Markdown',
          defaultProject: this.pendingCreate?.projectName || this.activeSpaceName() || '未分类',
          projects: this.customProjects.map((p: SpaceFolder) => p.name).concat(this.allCategories()),
          busy: this.noteCreateBusy,
          errorMessage: this.noteCreateError,
          onTypeChange: (type: string) => {
            const pending = this.pendingCreate;
            if (pending && !this.noteCreateBusy) {
              this.pendingCreate = { projectName: pending.projectName, type, defaultName: pending.defaultName };
            }
          },
          onClose: () => {
            if (this.noteCreateBusy) { return; }
            animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
              this.pendingCreate = null;
            });
          },
          onConfirm: (name: string, project: string, tags: string[]) => {
            this.commitPendingCreate(name, project, tags);
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
          onCreateProject: (name: string, color: string, icon: string) => this.createProject(name, color, icon)
        })
      }

      LocalPdfEngineHost()

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
