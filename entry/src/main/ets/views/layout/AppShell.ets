/**
 * 三栏工作台外壳 (Obsidian 工作台布局)
 *
 * 三级响应式：
 *   >= 1200vp  三栏（侧边栏 + 正文 + 上下文面板）
 *   840 ~ 1199vp 双栏（侧边栏 + 正文，上下文面板改为浮层）
 *   < 840vp    单栏（侧边栏与上下文面板均为浮层）
 *
 * 内容区与上下文面板通过 @BuilderParam 插槽注入，外壳只负责布局与响应式决策。
 */
import { curves, mediaquery } from '@kit.ArkUI';
import { ColorPalette, LayoutTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { SpaceFolder } from '../../common/types/SpaceFolder';
import { ChatSession } from '../../common/types/ChatSession';
import { SAVE_IDLE } from '../../common/constants/WorkspaceConstants';
import { GlobalTopBar } from './GlobalTopBar';
import { Sidebar } from './Sidebar';

@Component
export struct AppShell {
  @Prop breadcrumb: string[] = [];
  @Prop saveState: string = SAVE_IDLE;
  @Prop spaces: SpaceFolder[] = [];
  @Prop recentNotes: NoteItem[] = [];
  @Prop activeNav: string = '';
  @Prop activeSpaceId: string = '';
  @Prop activeNoteId: string = '';
  @Prop sidebarCollapsed: boolean = false;
  @Prop contextPanelOpen: boolean = false;
  @Prop trashCount: number = 0;
  @Prop todoPendingCount: number = 0;
  @Prop favoriteCount: number = 0;
  /** 侧栏中段模式：'tree' 项目资料树 | 'sessions' 对话记录 */
  @Prop sidebarMode: string = 'tree';
  @Prop sessions: ChatSession[] = [];
  @Prop activeSessionId: string = '';

  onToggleSidebar: () => void = () => {};
  onToggleContext: () => void = () => {};
  onOpenSearch: () => void = () => {};
  onSelectNav: (navKey: string) => void = () => {};
  onToggleSpace: (spaceId: string) => void = () => {};
  onCollapseAllSpaces: () => void = () => {};
  onSelectSpace: (spaceId: string) => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};
  onCreateNote: () => void = () => {};
  onCreateNoteInProject: (title: string, projectName: string, type: string) => void = () => {};
  onCreateFromTemplate: (templateName: string, projectName: string) => void = () => {};
  onImportIntoProject: (projectName: string) => void = () => {};
  onCreateProject: (name: string, color: string, icon: string) => void = () => {};
  onRenameProject: (oldName: string, newName: string) => void = () => {};
  onDeleteProject: (name: string) => void = () => {};
  onDeleteNote: (noteId: string) => void = () => {};
  onRenameNote: (note: NoteItem, newTitle: string) => void = () => {};
  onMoveNote: (note: NoteItem, category: string) => void = () => {};
  onApplyTags: (note: NoteItem, tags: string[]) => void = () => {};
  onOpenSettings: () => void = () => {};
  onBreadcrumbClick: (index: number, segment: string) => void = () => {};
  onOpenSheet: (type: string, project: SpaceFolder | null, note: NoteItem | null) => void = () => {};
  onOpenCreateProject: () => void = () => {};
  onSidebarModeChange: (mode: string) => void = () => {};
  onSelectSession: (session: ChatSession) => void = () => {};
  onNewSession: () => void = () => {};
  onDeleteSession: (sessionId: string) => void = () => {};
  onTogglePinSession: (session: ChatSession) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @State isThreeColumn: boolean = false;
  @State isTwoColumn: boolean = false;
  @State isPhone: boolean = false;

  private threeColumnListener: mediaquery.MediaQueryListener | undefined = undefined;
  private twoColumnListener: mediaquery.MediaQueryListener | undefined = undefined;
  private phoneListener: mediaquery.MediaQueryListener | undefined = undefined;

  @Builder
  emptyPanel() {
  }

  @BuilderParam content: () => void = this.emptyPanel;
  @BuilderParam contextPanel: () => void = this.emptyPanel;

  private onThreeColumnChange = (result: mediaquery.MediaQueryResult): void => {
    this.isThreeColumn = result.matches;
  };

  private onTwoColumnChange = (result: mediaquery.MediaQueryResult): void => {
    this.isTwoColumn = result.matches;
  };

  private onPhoneChange = (result: mediaquery.MediaQueryResult): void => {
    this.isPhone = result.matches;
    AppStorage.setOrCreate('flowmindIsPhone', result.matches);
  };

  aboutToAppear(): void {
    const threeColumn: mediaquery.MediaQueryListener =
      mediaquery.matchMediaSync(`(width >= ${LayoutTokens.BREAKPOINT_TABLET_LARGE}vp)`);
    const twoColumn: mediaquery.MediaQueryListener =
      mediaquery.matchMediaSync(`(width >= ${LayoutTokens.BREAKPOINT_TABLET_MEDIUM}vp)`);
    const phone: mediaquery.MediaQueryListener =
      mediaquery.matchMediaSync(`(width < ${LayoutTokens.BREAKPOINT_PHONE}vp)`);

    this.threeColumnListener = threeColumn;
    this.twoColumnListener = twoColumn;
    this.phoneListener = phone;
    this.isThreeColumn = threeColumn.matches;
    this.isTwoColumn = twoColumn.matches;
    this.isPhone = phone.matches;
    AppStorage.setOrCreate('flowmindIsPhone', phone.matches);

    threeColumn.on('change', this.onThreeColumnChange);
    twoColumn.on('change', this.onTwoColumnChange);
    phone.on('change', this.onPhoneChange);
  }

  aboutToDisappear(): void {
    if (this.threeColumnListener !== undefined) {
      this.threeColumnListener.off('change', this.onThreeColumnChange);
    }
    if (this.twoColumnListener !== undefined) {
      this.twoColumnListener.off('change', this.onTwoColumnChange);
    }
    if (this.phoneListener !== undefined) {
      this.phoneListener.off('change', this.onPhoneChange);
    }
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  /** 侧边栏是否常驻（双栏 / 三栏且未折叠） */
  private isSidebarDocked(): boolean {
    return (this.isTwoColumn || this.isThreeColumn) && !this.sidebarCollapsed;
  }

  /** 侧边栏是否以浮层形式呈现（单栏且未折叠） */
  private isSidebarOverlay(): boolean {
    return !this.isTwoColumn && !this.isThreeColumn && !this.sidebarCollapsed;
  }

  /** 上下文面板是否常驻（仅三栏） */
  private isContextDocked(): boolean {
    return this.isThreeColumn && this.contextPanelOpen;
  }

  /** 上下文面板是否以浮层形式呈现（单栏 / 双栏） */
  private isContextOverlay(): boolean {
    return !this.isThreeColumn && this.contextPanelOpen;
  }

  @Builder
  sidebarPanel() {
    Sidebar({
      spaces: this.spaces,
      recentNotes: this.recentNotes,
      activeNav: this.activeNav,
      activeSpaceId: this.activeSpaceId,
      activeNoteId: this.activeNoteId,
      trashCount: this.trashCount,
      todoPendingCount: this.todoPendingCount,
      favoriteCount: this.favoriteCount,
      onToggleSpace: this.onToggleSpace,
      onCollapseAllSpaces: this.onCollapseAllSpaces,
      onSelectSpace: this.onSelectSpace,
      onOpenSearch: this.onOpenSearch,
      onSelectNote: this.onSelectNote,
      onCreateNote: this.onCreateNote,
      onCreateNoteInProject: this.onCreateNoteInProject,
      onCreateFromTemplate: this.onCreateFromTemplate,
      onImportIntoProject: this.onImportIntoProject,
      onCreateProject: this.onCreateProject,
      onRenameProject: this.onRenameProject,
      onDeleteProject: this.onDeleteProject,
      onDeleteNote: this.onDeleteNote,
      onRenameNote: this.onRenameNote,
      onMoveNote: this.onMoveNote,
      onApplyTags: this.onApplyTags,
      onSelectNav: this.onSelectNav,
      onOpenSettings: this.onOpenSettings,
      onOpenSheet: this.onOpenSheet,
      onOpenCreateProject: this.onOpenCreateProject,
      sidebarMode: this.sidebarMode,
      sessions: this.sessions,
      activeSessionId: this.activeSessionId,
      onSidebarModeChange: this.onSidebarModeChange,
      onSelectSession: this.onSelectSession,
      onNewSession: this.onNewSession,
      onDeleteSession: this.onDeleteSession,
      onTogglePinSession: this.onTogglePinSession
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ---- 主框架 ----
      Row() {
        if (this.isSidebarDocked()) {
          Column() {
            this.sidebarPanel()
          }
          .height('100%')
          .transition(
            TransitionEffect.move(TransitionEdge.START)
              .combine(TransitionEffect.OPACITY)
              .animation({ curve: curves.springMotion(0.28, 0.76) })
          )
        }

        Column() {
          GlobalTopBar({
            breadcrumb: this.breadcrumb,
            saveState: this.saveState,
            contextPanelOpen: this.contextPanelOpen,
            showContextToggle: this.isTwoColumn || this.isThreeColumn || this.isPhone,
            onToggleSidebar: this.onToggleSidebar,
            onToggleContext: this.onToggleContext,
            onOpenSearch: this.onOpenSearch,
            onBreadcrumbClick: this.onBreadcrumbClick
          })

          Column() {
            this.content()
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.palette().canvas)
        }
        .layoutWeight(1)
        .height('100%')

        if (this.isContextDocked()) {
          Column() {
            this.contextPanel()
          }
          .height('100%')
          .transition(
            TransitionEffect.move(TransitionEdge.END)
              .combine(TransitionEffect.OPACITY)
              .animation({ curve: curves.springMotion(0.28, 0.76) })
          )
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette().canvas)

      // ---- 单栏：侧边栏浮层 ----
      if (this.isSidebarOverlay()) {
        Row() {
          Column() {
            this.sidebarPanel()
          }
          .height('100%')
          .shadow({ radius: 24, color: 'rgba(0,0,0,0.18)' })
          .transition(
            TransitionEffect.move(TransitionEdge.START)
              .combine(TransitionEffect.OPACITY)
              .animation({ curve: curves.springMotion(0.28, 0.76) })
          )

          Column()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.25)')
            .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
            .onClick(() => this.onToggleSidebar())
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
      }

      // ---- 单栏 / 双栏：上下文面板浮层 ----
      if (this.isContextOverlay()) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.25)')
            .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
            .onClick(() => this.onToggleContext())

          Column() {
            this.contextPanel()
          }
          .width(this.isPhone ? '100%' : LayoutTokens.CONTEXT_PANEL_WIDTH)
          .height('100%')
          .shadow({ radius: 24, color: 'rgba(0,0,0,0.18)' })
          .transition(
            TransitionEffect.move(TransitionEdge.END)
              .combine(TransitionEffect.OPACITY)
              .animation({ curve: curves.springMotion(0.28, 0.76) })
          )
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)
  }
}
