/**
 * 墨语 (FlowMind) 顶层装配器
 *
 * 本文件只承担两件事：
 *   1. 持有全局状态与本地数据流（NoteStorageService / NoteSearchService）
 *   2. 把渲染委托给 AppShell 与 views/ 下的视图组件
 *
 * 布局、样式与响应式决策一律下沉到 views/，此处不再出现大段 UI 构建代码。
 */
import { common } from '@kit.AbilityKit';
import { curves, promptAction } from '@kit.ArkUI';
import { NoteItem } from '../common/types/NoteItem';
import { SpaceFolder } from '../common/types/SpaceFolder';
import { LinkGraph, Backlink, UnresolvedLink } from '../common/types/LinkGraph';
import { MarkdownOutlineItem } from '../common/types/MarkdownOutlineItem';
import { WorkspaceStats } from '../common/types/WorkspaceStats';
import { DocumentTransferResult, MarkdownDocument } from '../common/types/MarkdownDocument';
import { TodoItem, DayNote } from '../common/types/TodoItem';
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
  TRASH_RETENTION_DAYS
} from '../common/constants/WorkspaceConstants';
import { NoteStorageService } from '../services/NoteStorageService';
import { NoteSearchService } from '../services/NoteSearchService';
import { TodoStorageService } from '../services/TodoStorageService';
import { buildSpaces } from '../services/WorkspaceBuilder';
import { defaultProjects, seedNotes, templateBody } from '../common/seed/SeedContent';
import { AppShell } from '../views/layout/AppShell';
import { HomeWorkspace } from '../views/workspace/HomeWorkspace';
import { LibraryWorkspace } from '../views/workspace/LibraryWorkspace';
import { GraphWorkspace } from '../views/workspace/GraphWorkspace';
import { PendingWorkspace } from '../views/workspace/PendingWorkspace';
import { TodoWorkspace } from '../views/workspace/TodoWorkspace';
import { TrashWorkspace } from '../views/workspace/TrashWorkspace';
import { FavoriteWorkspace } from '../views/workspace/FavoriteWorkspace';
import { ReaderWorkspace } from '../views/reader/ReaderWorkspace';
import { HuaweiDocWorkspace } from '../views/reader/huawei/HuaweiDocWorkspace';
import { ContextDrawer, CONTEXT_TAB_OUTLINE } from '../views/context/ContextDrawer';
import { QuickSearchDialog } from '../views/explore/QuickSearchDialog';
import { AppearanceSheet } from '../views/settings/AppearanceSheet';
import { NameNoteSheet } from '../views/layout/sheets/NameNoteSheet';

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
  /** 新建笔记的命名弹层意图；非空即显示 NameNoteSheet。 */
  @State pendingCreate: PendingNoteCreate | null = null;
  @State toastVisible: boolean = false;
  @State toastMessage: string = '';
  /** 当前 Toast 是否附带「撤销」按钮 */
  @State undoVisible: boolean = false;

  private storage: NoteStorageService = new NoteStorageService();
  private searchService: NoteSearchService = new NoteSearchService();
  private todoStorage: TodoStorageService = new TodoStorageService();
  private toastTimer: number = -1;
  private bootstrapped: boolean = false;

  /**
   * 最近一次可撤销的删除操作。删除是本地即刻生效、且会连带清掉沙箱 .md 的破坏性动作，
   * 只有确认弹窗而没有后悔药的话，用户误触一次就永久丢数据。这里保留一个短时句柄，
   * 由 Toast 上的「撤销」按钮触发还原；Toast 消失时句柄一并失效。
   */
  private undoAction: (() => void) | null = null;

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
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      const loaded: NoteItem[] = await this.storage.load(context, seedNotes());
      this.notes = loaded.length > 0 ? loaded : seedNotes();
    } catch (error) {
      console.error(`本地笔记加载失败: ${JSON.stringify(error)}`);
      this.notes = seedNotes();
      this.notify('本地笔记读取失败，已加载示例内容');
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
      const expiredIds: string[] = [];
      for (let i = 0; i < stored.length; i++) {
        const rawDeletedAt: number | undefined = stored[i].deletedAt;
        const deletedAt: number = rawDeletedAt === undefined ? now : rawDeletedAt;
        const ageDays: number = (now - deletedAt) / (24 * 60 * 60 * 1000);
        if (ageDays > TRASH_RETENTION_DAYS) {
          expiredIds.push(stored[i].id);
        } else {
          keep.push(stored[i]);
        }
      }
      this.trash = keep;
      for (let i = 0; i < expiredIds.length; i++) {
        try {
          await this.storage.delete(context, expiredIds[i]);
        } catch (error) {
          console.error(`超期笔记文件清理失败 (${expiredIds[i]}): ${JSON.stringify(error)}`);
        }
      }
      if (expiredIds.length > 0) {
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
    if (this.readingOpen) {
      const category: string = this.readingNote.category.length === 0 ? '未分类' : this.readingNote.category;
      return [category, this.readingNote.title];
    }
    return [this.activeNav];
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

  private openNoteByTitle(title: string): void {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].title === title) {
        this.openNote(this.notes[i]);
        return;
      }
    }
    this.notify(`「${title}」尚未创建`);
  }

  /** 新建笔记前先弹命名层：记录意图并展示 NameNoteSheet，确认后再真正落地。 */
  private requestCreateNote(projectName: string, type: string, defaultName: string): void {
    const pending: PendingNoteCreate = {
      projectName: projectName,
      type: type,
      defaultName: defaultName
    };
    animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
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
    this.notes = [note].concat(this.notes);
    try {
      await this.storage.create(context, note);
    } catch (error) {
      console.error(`Markdown 正文创建失败: ${JSON.stringify(error)}`);
    }
    await this.persistSnapshot();
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

  /** 彻底删除单篇（不可恢复，需二次确认）：移除回收站条目并删掉沙箱 .md。 */
  private async purgeNote(note: NoteItem): Promise<void> {
    const confirmed: boolean = await this.confirmDestructive(`彻底删除「${note.title}」？此操作不可恢复。`);
    if (!confirmed) {
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.trash = this.removeById(this.trash, note.id);
    try {
      await this.storage.delete(context, note.id);
    } catch (error) {
      console.error(`彻底删除失败 (${note.id}): ${JSON.stringify(error)}`);
    }
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
    const ids: string[] = [];
    for (let i = 0; i < this.trash.length; i++) {
      ids.push(this.trash[i].id);
    }
    this.trash = [];
    for (let i = 0; i < ids.length; i++) {
      try {
        await this.storage.delete(context, ids[i]);
      } catch (error) {
        console.error(`清空回收站失败 (${ids[i]}): ${JSON.stringify(error)}`);
      }
    }
    await this.persistTrash();
    this.notify('回收站已清空');
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
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      await this.todoStorage.saveTodos(context, this.todos);
    } catch (error) {
      console.error(`待办保存失败: ${JSON.stringify(error)}`);
      this.notify('待办保存失败');
    }
  }

  private async persistDayNotes(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
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

  /**
   * 通过系统文件选择器导入文档。
   * @param targetCategory 导入后归入的项目名，默认「未分类」
   */
  private async importDocument(targetCategory: string = '未分类'): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      const result: DocumentTransferResult = await this.storage.importDocument(context);
      if (result.status === 'imported' && result.document !== undefined) {
        const document: MarkdownDocument = result.document;
        const now: Date = new Date();
        const note: NoteItem = {
          id: document.id,
          title: document.title,
          category: targetCategory,
          // 类型必须采用服务层回传的结果：写死 'Markdown' 会让导入的 PDF
          // 走不进原盘批注阅读器（ReaderWorkspace 按 type 分流）。
          type: result.noteType !== undefined ? result.noteType : 'Markdown',
          previewText: document.content.length > 48 ? `${document.content.substring(0, 48)}…` : document.content,
          tag: '导入',
          tagColor: '',
          updateTime: this.formatTime(now),
          contentDetail: document.content,
          tags: ['导入'],
          createdAt: now.getTime(),
          updatedAt: now.getTime()
        };
        this.notes = [note].concat(this.notes);
        await this.persistSnapshot();
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

  private handleSaved(note: NoteItem, content: string): void {
    const now: number = Date.now();
    note.updatedAt = now;
    note.updateTime = this.formatTime(new Date(now));
    if (note.createdAt === undefined) {
      note.createdAt = now;
    }
    let changed: boolean = false;
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === note.id) {
        this.notes[i] = note;
        changed = true;
        break;
      }
    }
    if (changed) {
      this.notes = this.notes.slice();
    }
    this.readingNote = note;
    this.persistSnapshot();
    this.refreshGraph();
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
          this.readingOpen = false;
          this.activeNoteId = '';
          this.outlineItems = [];
        },
        onToggleAnnotation: () => {
          this.annotationPaneOpen = !this.annotationPaneOpen;
        },
        onSaved: (note: NoteItem, content: string) => this.handleSaved(note, content),
        onSaveStateChange: (state: string) => {
          this.saveState = state;
        }
      })
    } else if (this.activeNav === NAV_HOME) {
      HomeWorkspace({
        stats: this.stats,
        recentNotes: this.notes.slice(0, 6),
        unresolvedLinks: this.linkGraph.unresolvedLinks,
        onSelectNote: (note: NoteItem) => this.openNote(note),
        onCreateNote: () => this.requestCreateNote('', 'Markdown', '未命名笔记'),
        onImportDocument: () => this.importDocument(),
        onOpenGraph: () => {
          this.activeNav = NAV_GRAPH;
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
        onSelectNoteById: (noteId: string) => this.openNoteById(noteId),
        onOpenNoteByTitle: (title: string) => this.openNoteByTitle(title)
      })
      .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
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
      .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
    } else if (this.activeNav === NAV_TRASH) {
      TrashWorkspace({
        trash: this.trash,
        retentionDays: TRASH_RETENTION_DAYS,
        onRestore: (note: NoteItem) => this.restoreFromTrash(note),
        onPurge: (note: NoteItem) => this.purgeNote(note),
        onEmpty: () => this.emptyTrash()
      })
      .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
    } else if (this.activeNav === NAV_FAVORITE) {
      FavoriteWorkspace({
        favorites: this.favoriteNotes(),
        onSelectNote: (note: NoteItem) => this.openNote(note)
      })
      .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
    } else if (this.activeNav === NAV_CANVAS) {
      PendingWorkspace({
        title: '白板',
        description: '自由画布与思维导图正在迁移到新的视图层，当前版本暂未开放。',
        pendingItems: [
          '星闪手写笔墨迹采样与压感',
          '卡片拖拽与自动连线',
          '白板内容导出为 Markdown'
        ]
      })
    } else {
      PendingWorkspace({
        title: 'AI 墨客',
        description: '端侧私有化 RAG 问答需要先完成本地索引，当前版本暂未开放。',
        pendingItems: [
          '本地 Markdown 分块与向量索引',
          '带来源片段的引用式回答',
          'L1 伴读 / L2 学情 / L3 跨库三层智能体'
        ]
      })
    }
  }

  @Builder
  contextContent() {
    ContextDrawer({
      outlineItems: this.outlineItems,
      backlinks: this.currentBacklinks(),
      unresolved: this.currentUnresolved(),
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
      onCreateFromTitle: (title: string) => this.createNote(title),
      onClose: () => {
        animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
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
        onToggleSidebar: () => {
          animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
            this.sidebarCollapsed = !this.sidebarCollapsed;
          });
        },
        onToggleContext: () => {
          animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
            this.contextPanelOpen = !this.contextPanelOpen;
          });
        },
        onOpenSearch: () => {
          animateTo({ curve: curves.springMotion(0.25, 0.76) }, () => {
            this.searchVisible = true;
          });
        },
        onSelectNav: (navKey: string) => {
          this.activeNav = navKey;
          this.readingOpen = false;
          this.fullScreenDocOpen = false;
          this.activeNoteId = '';
        },
        onToggleSpace: (spaceId: string) => {
          animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
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
          animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
            for (let i = 0; i < this.spaces.length; i++) {
              this.spaces[i].isOpen = false;
            }
            this.spaces = this.spaces.slice();
          });
        },
        onSelectSpace: (spaceId: string) => {
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
          animateTo({ curve: curves.springMotion(0.25, 0.76) }, () => {
            this.settingsVisible = true;
          });
        }
      })

      // ---- 华为风独立全屏文档与稿纸工作台 (PDF / 试卷 / 稿纸手写) ----
      if (this.fullScreenDocOpen) {
        HuaweiDocWorkspace({
          note: this.fullScreenDocNote,
          onClose: () => {
            this.fullScreenDocOpen = false;
            this.activeNoteId = '';
          },
          onSaved: (note: NoteItem, content: string) => this.handleSaved(note, content),
          onSaveStateChange: (state: string) => {
            this.saveState = state;
          }
        })
        .width('100%')
        .height('100%')
      }

      if (this.searchVisible) {
        QuickSearchDialog({
          notes: this.notes,
          onClose: () => {
            animateTo({ curve: curves.springMotion(0.25, 0.76) }, () => {
              this.searchVisible = false;
            });
          },
          onSelectNote: (note: NoteItem) => {
            animateTo({ curve: curves.springMotion(0.25, 0.76) }, () => {
              this.searchVisible = false;
              this.openNote(note);
            });
          }
        })
      }

      if (this.settingsVisible) {
        AppearanceSheet({
          onClose: () => {
            animateTo({ curve: curves.springMotion(0.25, 0.76) }, () => {
              this.settingsVisible = false;
            });
          },
          onLoadSeedData: () => {
            this.loadSeedData();
          }
        })
      }

      if (this.pendingCreate !== null) {
        NameNoteSheet({
          defaultName: this.pendingDefaultName(),
          onClose: () => {
            animateTo({ curve: curves.springMotion(0.25, 0.76) }, () => {
              this.pendingCreate = null;
            });
          },
          onConfirm: (name: string) => {
            animateTo({ curve: curves.springMotion(0.25, 0.76) }, () => {
              this.commitPendingCreate(name);
            });
          }
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
