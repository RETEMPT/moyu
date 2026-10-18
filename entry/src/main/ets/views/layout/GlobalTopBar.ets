/**
 * 全局顶栏 (Notion 风格极简工具条)
 *
 * 左区：侧边栏折叠按钮 + 空间面包屑（每段可点击跳转）
 * 右区：Markdown 落盘状态 + 快速搜索入口 + 右侧上下文面板开关
 */
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { SAVE_FAILED, SAVE_SAVING } from '../../common/constants/WorkspaceConstants';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';

const TOP_BAR_HEIGHT: number = 48;
const ICON_SIZE: number = 44;

@Component
export struct GlobalTopBar {
  /** 面包屑层级，最后一段为当前文档 */
  @Prop breadcrumb: string[] = [];
  /** 落盘状态文案：已保存 / 保存中 / 保存失败 */
  @Prop saveState: string = '已保存';
  /** 右侧上下文面板当前是否展开 */
  @Prop contextPanelOpen: boolean = false;
  /** 是否展示上下文面板开关（单栏下无意义） */
  @Prop showContextToggle: boolean = true;

  onToggleSidebar: () => void = () => {};
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

  /** 图标点击区：手机放大到接近最小触控目标，宽屏保持紧凑 */
  private iconSize(): number {
    return ICON_SIZE;
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
      Row() {
        AppIcon({ source: $r('app.media.ic_menu'), iconSize: 20, tint: this.palette().inkSecondary })
      }
      .width(this.iconSize())
      .height(this.iconSize())
      .justifyContent(FlexAlign.Center)
      .borderRadius(6)
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText('打开导航')
      .onClick(() => this.onToggleSidebar())

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
      .margin({ left: 4 })

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

      Row() {
        AppIcon({ source: $r('app.media.ic_search'), iconSize: 20, tint: this.palette().inkSecondary })
      }
      .width(this.iconSize())
      .height(this.iconSize())
      .justifyContent(FlexAlign.Center)
      .borderRadius(6)
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText('搜索笔记')
      .keyboardShortcut('f', [ModifierKey.CTRL], () => this.onOpenSearch())
      .onClick(() => this.onOpenSearch())

      if (this.showContextToggle) {
        IconButton({ icon: $r('app.media.ic_panel'), label: this.contextPanelOpen ? '收起文档信息' : '打开文档信息',
          selected: this.contextPanelOpen, onAction: () => this.onToggleContext() })
      }
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.palette().canvas)
  }
}
