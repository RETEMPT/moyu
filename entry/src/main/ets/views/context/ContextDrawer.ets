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
import { NoteItem } from '../../common/types/NoteItem';
import { OutlinePanel } from './OutlinePanel';
import { BacklinksPanel } from './BacklinksPanel';

export const CONTEXT_TAB_OUTLINE: string = 'outline';
export const CONTEXT_TAB_BACKLINK: string = 'backlink';

@Component
export struct ContextDrawer {
  @Prop outlineItems: MarkdownOutlineItem[] = [];
  @Prop backlinks: Backlink[] = [];
  @Prop unresolved: UnresolvedLink[] = [];
  @Prop recentNotes: NoteItem[] = [];
  @Prop activeTab: string = CONTEXT_TAB_OUTLINE;
  @Prop closable: boolean = false;

  onTabChange: (tab: string) => void = () => {};
  onJumpToLine: (line: number) => void = () => {};
  onOpenNote: (noteId: string) => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};
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
            .responseRegion({ x: -8, y: -8, width: 44, height: 44 })
            .onClick(() => this.onClose())
        }
      }
      .width('100%')
      .height(36)
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(1)
        .color(this.palette().borderSubtle)

      // ---- 上方 2/3: 大纲 / 反向链接 ----
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
      .layoutWeight(2)
      .padding({ top: 8 })

      // ---- 下方 1/3: 固定过往浏览 ----
      Divider()
        .strokeWidth(1)
        .color(this.palette().borderSubtle)

      Column() {
        Row({ space: 6 }) {
          Text('⏱')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
          Text('过往浏览')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Blank()
          Text(`${this.recentNotes.length}`)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 10, bottom: 6 })

        if (this.recentNotes.length === 0) {
          Column() {
            Text('暂无最近浏览')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          .width('100%')
          .padding({ top: 14 })
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 2 }) {
            ForEach(this.recentNotes.slice(0, 8), (note: NoteItem) => {
              ListItem() {
                Row({ space: 8 }) {
                  Text(note.type.toLowerCase() === 'pdf' || note.title.toLowerCase().endsWith('.pdf') ? '🗎' :
                    (note.type.toLowerCase() === 'canvas' || note.type === '白板' || note.type === '手写' ? '✎' : '▤'))
                    .fontSize(TypographyTokens.CAPTION)
                    .fontColor(note.type.toLowerCase() === 'pdf' || note.title.toLowerCase().endsWith('.pdf') ? '#E11D48' :
                      (note.type.toLowerCase() === 'canvas' || note.type === '白板' ? '#D97706' : this.palette().link))

                  Text(note.title)
                    .fontSize(TypographyTokens.CAPTION)
                    .fontColor(this.palette().inkSecondary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)

                  Text(note.updateTime)
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().inkMuted)
                }
                .width('100%')
                .padding({ left: 6, right: 6, top: 5, bottom: 5 })
                .borderRadius(6)
                .hoverEffect(HoverEffect.Highlight)
                .onClick(() => this.onSelectNote(note))
              }
            }, (note: NoteItem) => `context_recent_${note.id}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ bottom: 8 })
    }
    .width(this.panelWidth())
    .height('100%')
    .padding({ left: 10, right: 10 })
    .backgroundColor(this.palette().sidebar)
    .border({ width: { left: 1 }, color: { left: this.palette().borderSubtle } })
  }
}
