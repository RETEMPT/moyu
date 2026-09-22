/**
 * 右侧上下文抽屉 (T4.3)
 *
 * 常驻三栏时不显示关闭按钮；单栏 / 双栏以浮层呈现时提供一键收起，
 * 收起后中间工作台会自动填满（由 AppShell 的布局决策保证）。
 */
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { Backlink, UnresolvedLink } from '../../common/types/LinkGraph';
import { MarkdownOutlineItem } from '../../common/types/MarkdownOutlineItem';
import { OutlinePanel } from './OutlinePanel';
import { BacklinksPanel } from './BacklinksPanel';

export const CONTEXT_TAB_OUTLINE: string = 'outline';
export const CONTEXT_TAB_BACKLINK: string = 'backlink';

@Component
export struct ContextDrawer {
  @Prop outlineItems: MarkdownOutlineItem[] = [];
  @Prop backlinks: Backlink[] = [];
  @Prop unresolved: UnresolvedLink[] = [];
  @Prop activeTab: string = CONTEXT_TAB_OUTLINE;
  @Prop closable: boolean = false;

  onTabChange: (tab: string) => void = () => {};
  onJumpToLine: (line: number) => void = () => {};
  onOpenNote: (noteId: string) => void = () => {};
  onCreateFromTitle: (title: string) => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  /** 面板宽度：手机窄屏铺满，宽屏用固定宽度。 */
  private panelWidth(): Length {
    return this.isPhone ? '100%' : LayoutTokens.CONTEXT_PANEL_WIDTH;
  }

  @Builder
  tabItem(label: string, tabKey: string) {
    Column() {
      Text(label)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.activeTab === tabKey ? this.palette().inkPrimary : this.palette().inkMuted)
        .fontWeight(this.activeTab === tabKey ? FontWeight.Medium : FontWeight.Normal)
      Divider()
        .strokeWidth(2)
        .color(this.activeTab === tabKey ? this.palette().accent : Color.Transparent)
        .width(20)
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .height(32)
    .justifyContent(FlexAlign.Center)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onTabChange(tabKey))
  }

  build() {
    Column() {
      Row() {
        this.tabItem('大纲', CONTEXT_TAB_OUTLINE)
        this.tabItem('反向链接', CONTEXT_TAB_BACKLINK)
        if (this.closable) {
          Text('✕')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .borderRadius(6)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onClose())
        }
      }
      .width('100%')
      .height(36)
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(1)
        .color(this.palette().borderSubtle)

      Column() {
        if (this.activeTab === CONTEXT_TAB_OUTLINE) {
          OutlinePanel({
            outlineItems: this.outlineItems,
            onJumpToLine: this.onJumpToLine
          })
        } else {
          BacklinksPanel({
            backlinks: this.backlinks,
            unresolved: this.unresolved,
            onOpenNote: this.onOpenNote,
            onCreateFromTitle: this.onCreateFromTitle
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: 8 })
    }
    .width(this.panelWidth())
    .height('100%')
    .padding({ left: 10, right: 10 })
    .backgroundColor(this.palette().sidebar)
    .border({ width: { left: 1 }, color: { left: this.palette().borderSubtle } })
  }
}
