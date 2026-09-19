/**
 * 全局顶栏 (Notion 风格极简工具条)
 *
 * 左区：侧边栏折叠按钮 + 空间面包屑
 * 右区：Markdown 落盘状态 + 快速搜索入口 + 右侧上下文面板开关
 */
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { SAVE_FAILED, SAVE_SAVING } from '../../common/constants/WorkspaceConstants';

const TOP_BAR_HEIGHT: number = 44;
const ICON_SIZE: number = 28;

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

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private saveStateColor(): string {
    const palette: ColorPalette = this.palette();
    if (this.saveState === SAVE_SAVING) {
      return palette.warning;
    }
    if (this.saveState === SAVE_FAILED) {
      return palette.danger;
    }
    return palette.success;
  }

  build() {
    Row() {
      // ---- 左区 ----
      Text('☰')
        .fontSize(TypographyTokens.TITLE_SUB)
        .fontColor(this.palette().inkSecondary)
        .width(ICON_SIZE)
        .height(ICON_SIZE)
        .textAlign(TextAlign.Center)
        .borderRadius(6)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onToggleSidebar())

      Row({ space: 6 }) {
        ForEach(this.breadcrumb, (segment: string, index: number) => {
          if (index > 0) {
            Text('/')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkMuted)
          }
          Text(segment)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(index === this.breadcrumb.length - 1 ? this.palette().inkPrimary : this.palette().inkSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }, (segment: string, index: number) => `${index}-${segment}`)
      }
      .layoutWeight(1)
      .margin({ left: 4 })

      // ---- 右区 ----
      Row({ space: 5 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.saveStateColor())
        Text(this.saveState)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
      }
      .margin({ right: 8 })

      Text('⌕')
        .fontSize(TypographyTokens.TITLE_SUB)
        .fontColor(this.palette().inkSecondary)
        .width(ICON_SIZE)
        .height(ICON_SIZE)
        .textAlign(TextAlign.Center)
        .borderRadius(6)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onOpenSearch())

      if (this.showContextToggle) {
        Text(this.contextPanelOpen ? '❯' : '❮')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.contextPanelOpen ? this.palette().accent : this.palette().inkSecondary)
          .width(ICON_SIZE)
          .height(ICON_SIZE)
          .textAlign(TextAlign.Center)
          .borderRadius(6)
          .backgroundColor(this.contextPanelOpen ? this.palette().accentSoft : Color.Transparent)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onToggleContext())
      }
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 8, right: 8 })
    .backgroundColor(this.palette().canvas)
    .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })
  }
}
