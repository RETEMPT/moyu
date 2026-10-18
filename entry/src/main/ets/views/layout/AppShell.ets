/**
 * 响应式工作台外壳
 *
 * 三级响应式：
 *   >= 1200vp  三栏（侧边栏 + 正文 + 上下文面板）
 *   840 ~ 1199vp 双栏（侧边栏 + 正文，上下文面板改为浮层）
 *   < 840vp    单栏（侧边栏与上下文面板均为浮层）
 *
 * 内容区与上下文面板通过 @BuilderParam 插槽注入，外壳只负责布局与响应式决策。
 */

import { ColorPalette, LayoutTokens, AnimationTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { SpaceFolder } from '../../common/types/SpaceFolder';
import { SAVE_IDLE, NAV_SETTINGS } from '../../common/constants/WorkspaceConstants';
import { GlobalTopBar } from './GlobalTopBar';
import { Sidebar } from './Sidebar';
import { BottomNavBar } from './BottomNavBar';

@Component
export struct AppShell {
  @Prop breadcrumb: string[] = [];
  @Prop saveState: string = SAVE_IDLE;
  @Prop spaces: SpaceFolder[] = [];

  @Prop activeNav: string = '';
  @Prop activeSpaceId: string = '';
  @Prop activeNoteId: string = '';
  @Prop sidebarCollapsed: boolean = false;
  @Prop contextPanelOpen: boolean = false;

  onToggleSidebar: () => void = () => {};
  onToggleContext: () => void = () => {};
  onLayoutModeChange: (singleColumn: boolean, threeColumn: boolean) => void = () => {};
  onOpenSearch: () => void = () => {};
  onSelectNav: (navKey: string) => void = () => {};
  onToggleSpace: (spaceId: string) => void = () => {};
  onCollapseAllSpaces: () => void = () => {};
  onSelectSpace: (spaceId: string) => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};
  onOpenSettings: () => void = () => {};
  onBreadcrumbClick: (index: number, segment: string) => void = () => {};
  onOpenSheet: (type: string, project: SpaceFolder | null, note: NoteItem | null) => void = () => {};
  onOpenCreateProject: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';

  @State isThreeColumn: boolean = false;
  @State isTwoColumn: boolean = false;
  @State isPhone: boolean = true;

  @Builder
  emptyPanel() {
  }

  @BuilderParam content: () => void = this.emptyPanel;
  @BuilderParam contextPanel: () => void = this.emptyPanel;

  aboutToAppear(): void {
    AppStorage.setOrCreate('flowmindIsPhone', true);
    AppStorage.setOrCreate('flowmindSingleColumn', true);
    this.onLayoutModeChange(true, false);
  }

  /** Use the actual shell width, including split windows and constrained panes. */
  private updateLayout(width: number): void {
    if (!Number.isFinite(width) || width <= 0) { return; }
    const three = width >= LayoutTokens.BREAKPOINT_TABLET_LARGE;
    const two = width >= LayoutTokens.BREAKPOINT_TABLET_MEDIUM;
    const phone = width < LayoutTokens.BREAKPOINT_PHONE;
    const changed = three !== this.isThreeColumn || two !== this.isTwoColumn || phone !== this.isPhone;
    this.isThreeColumn = three; this.isTwoColumn = two; this.isPhone = phone;
    AppStorage.setOrCreate('flowmindIsPhone', phone);
    AppStorage.setOrCreate('flowmindSingleColumn', !two);
    if (changed) { this.onLayoutModeChange(!two, three); }
  }
  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
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
    return this.activeNav !== NAV_SETTINGS && this.activeNoteId.length > 0 && this.isThreeColumn && this.contextPanelOpen;
  }

  /** 上下文面板是否以浮层形式呈现（单栏 / 双栏） */
  private isContextOverlay(): boolean {
    return this.activeNav !== NAV_SETTINGS && this.activeNoteId.length > 0 && !this.isThreeColumn && this.contextPanelOpen;
  }

  @Builder
  sidebarPanel() {
    Sidebar({
      spaces: this.spaces,
      onToggleSidebar: this.onToggleSidebar,
      activeNav: this.activeNav,
      activeSpaceId: this.activeSpaceId,
      activeNoteId: this.activeNoteId,
      onToggleSpace: this.onToggleSpace,
      onCollapseAllSpaces: this.onCollapseAllSpaces,
      onSelectSpace: this.onSelectSpace,
      onOpenSearch: this.onOpenSearch,
      onSelectNote: this.onSelectNote,
      onSelectNav: this.onSelectNav,
      onOpenSettings: this.onOpenSettings,
      onOpenSheet: this.onOpenSheet,
      onOpenCreateProject: this.onOpenCreateProject
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
              .animation({ duration: AnimationTokens.duration(120), curve: Curve.EaseInOut })
          )
        }

        Column() {
          GlobalTopBar({
            breadcrumb: this.breadcrumb,
            saveState: this.saveState,
            contextPanelOpen: this.contextPanelOpen,
            showContextToggle: this.activeNav !== NAV_SETTINGS && this.activeNoteId.length > 0 && (this.isTwoColumn || this.isThreeColumn || this.isPhone),
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

          if (this.isPhone) {
            BottomNavBar({
              activeNav: this.activeNav,
              onSelectNav: this.onSelectNav
            })
          }
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
              .animation({ duration: AnimationTokens.duration(120), curve: Curve.EaseInOut })
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
              .animation({ duration: AnimationTokens.duration(120), curve: Curve.EaseInOut })
          )

          Column()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.25)')
            .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.duration(120), curve: Curve.EaseInOut }))
            .onClick(() => this.onToggleSidebar())
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.duration(120), curve: Curve.EaseInOut }))
      }

      // ---- 单栏 / 双栏：上下文面板浮层 ----
      if (this.isContextOverlay()) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.25)')
            .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.duration(120), curve: Curve.EaseInOut }))
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
              .animation({ duration: AnimationTokens.duration(120), curve: Curve.EaseInOut })
          )
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.duration(120), curve: Curve.EaseInOut }))
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((before: Area, after: Area) => this.updateLayout(Number(after.width)))
    .keyboardShortcut('k', [ModifierKey.CTRL], () => this.onOpenSearch())
    .backgroundColor(this.palette().canvas)
  }
}
