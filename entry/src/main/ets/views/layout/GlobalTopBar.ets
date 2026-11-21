/**
 * 全局顶栏 (Notion 风格极简工具条)
 *
 * 左区：侧边栏折叠按钮 + 空间面包屑（每段可点击跳转）
 * 右区：Markdown 落盘状态 + 快速搜索入口 + 右侧上下文面板开关
 */
import { ColorPalette, LayoutTokens, LibraryColors, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { SAVE_FAILED, SAVE_SAVING } from '../../common/constants/WorkspaceConstants';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';

const TOP_BAR_HEIGHT: number = 48;

@Component
export struct GlobalTopBar {
  /** 面包屑层级，最后一段为当前文档 */
  @Prop breadcrumb: string[] = [];
  @Prop canGoBack: boolean = false;
  @Prop libraryStyle: boolean = false;
  @Prop showSidebarToggle: boolean = true;
  @Prop showSearch: boolean = true;
  /** 落盘状态文案：已保存 / 保存中 / 保存失败 */
  @Prop saveState: string = '已保存';
  /** 右侧上下文面板当前是否展开 */
  @Prop contextPanelOpen: boolean = false;
  /** 是否展示上下文面板开关（单栏下无意义） */
  @Prop showContextToggle: boolean = true;

  onToggleSidebar: () => void = () => {};
  onBack: () => void = () => {};
  onToggleContext: () => void = () => {};
  onOpenSearch: () => void = () => {};
  /** 点击面包屑某一段（分类名或文档标题）时回调，index 为该段下标 */
  onBreadcrumbClick: (index: number, segment: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private saveStateColor(): string {
    const palette: ColorPalette = this.palette();
    if (this.saveState === SAVE_SAVING) {
      return palette.warning;
    }
    if (this.saveState === SAVE_FAILED) {
      return palette.danger;
    }
    return palette.inkMuted;
  }

  build() {
    Row() {
      // ---- 左区 ----
      if (this.showSidebarToggle) {
        IconButton({ icon: $r('app.media.ic_menu'), label: '打开导航', onAction: this.onToggleSidebar })
      }

      if (this.canGoBack) {
        IconButton({ icon: $r('app.media.ic_back'), label: '返回上一页', onAction: this.onBack })
      }

      Row({ space: 6 }) {
        ForEach(this.breadcrumb, (segment: string, index: number) => {
          if (index > 0) {
            Text('/')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkMuted)
          }
          Text(segment === '首页' ? '主页' : segment)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(index === this.breadcrumb.length - 1 ? this.palette().inkPrimary : this.palette().inkMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onBreadcrumbClick(index, segment))
        }, (segment: string, index: number) => `${index}-${segment}`)
      }
      .layoutWeight(1)
      .margin({ left: this.showSidebarToggle || this.canGoBack ? 4 : 0 })

      // ---- 右区 ----
      if (this.saveState === SAVE_SAVING || this.saveState === SAVE_FAILED) {
      Row({ space: 5 }) {
        AppIcon({ source: $r('app.media.ic_lock'), iconSize: 14, tint: this.saveStateColor() })
        if (!this.isPhone || this.saveState === SAVE_FAILED) {
          Text(this.saveState)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.saveStateColor())
        }
      }
      .accessibilityText(this.saveState)
      .margin({ right: 8 })
      }

      if (this.showSearch) {
        IconButton({ icon: $r('app.media.ic_search'), label: '搜索笔记', onAction: this.onOpenSearch })
          .keyboardShortcut('f', [ModifierKey.CTRL], () => this.onOpenSearch())
      }

      if (this.showContextToggle) {
        IconButton({ icon: $r('app.media.ic_panel'), label: this.contextPanelOpen ? '收起文档信息' : '打开文档信息',
          selected: this.contextPanelOpen, onAction: () => this.onToggleContext() })
      }
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: this.libraryStyle && !this.showSidebarToggle ? LayoutTokens.gutter(this.isPhone) : 8, right: 8 })
    .backgroundColor(this.libraryStyle && !this.isDarkMode ? LibraryColors.paper : this.palette().canvas)
  }
}
