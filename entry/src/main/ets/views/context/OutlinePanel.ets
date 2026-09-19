/**
 * 大纲面板 (T4.1)
 *
 * 基于正文标题动态生成目录树，点击条目由父组件驱动正文平滑锚点定位。
 */
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { MarkdownOutlineItem } from '../../common/types/MarkdownOutlineItem';

@Component
export struct OutlinePanel {
  @Prop outlineItems: MarkdownOutlineItem[] = [];
  @Prop activeLine: number = -1;

  onJumpToLine: (line: number) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  build() {
    Column() {
      if (this.outlineItems.length === 0) {
        Column({ space: 6 }) {
          Text('这篇笔记还没有标题')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
          Text('用 # / ## / ### 书写标题，目录会自动生成。')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .padding({ top: 16 })
        .alignItems(HorizontalAlign.Start)
      } else {
        List({ space: 1 }) {
          ForEach(this.outlineItems, (item: MarkdownOutlineItem) => {
            ListItem() {
              Row() {
                Text(item.text)
                  .fontSize(item.level === 1 ? TypographyTokens.BODY_REGULAR : TypographyTokens.CAPTION)
                  .fontWeight(item.level === 1 ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.activeLine === item.line ? this.palette().accent : this.palette().inkSecondary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({
                left: 8 + (item.level - 1) * 12,
                right: 8,
                top: 5,
                bottom: 5
              })
              .borderRadius(6)
              .backgroundColor(this.activeLine === item.line ? this.palette().accentSoft : Color.Transparent)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onJumpToLine(item.line))
            }
          }, (item: MarkdownOutlineItem) => `${item.line}-${item.text}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
