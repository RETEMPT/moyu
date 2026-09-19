/**
 * 反向链接面板 (T4.2)
 *
 * 展示引用了当前文档的其他笔记（已解析引用），
 * 以及当前文档中指向尚不存在笔记的待创建概念。
 */
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { Backlink, UnresolvedLink } from '../../common/types/LinkGraph';

@Component
export struct BacklinksPanel {
  @Prop backlinks: Backlink[] = [];
  @Prop unresolved: UnresolvedLink[] = [];

  onOpenNote: (noteId: string) => void = () => {};
  onCreateFromTitle: (title: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  @Builder
  groupLabel(text: string, count: number) {
    Row({ space: 6 }) {
      Text(text)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .fontWeight(FontWeight.Medium)
      Text(`${count}`)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkSecondary)
    }
    .width('100%')
    .margin({ top: 6, bottom: 6 })
  }

  build() {
    Scroll() {
      Column() {
        if (this.backlinks.length === 0 && this.unresolved.length === 0) {
          Column({ space: 6 }) {
            Text('还没有链接关系')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkSecondary)
            Text('在其他笔记里书写 [[这篇笔记的标题]]，就会出现在这里。')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          .width('100%')
          .padding({ top: 16 })
          .alignItems(HorizontalAlign.Start)
        }

        if (this.backlinks.length > 0) {
          this.groupLabel('被引用', this.backlinks.length)
          ForEach(this.backlinks, (link: Backlink) => {
            Column({ space: 3 }) {
              Text(link.sourceTitle)
                .fontSize(TypographyTokens.BODY_REGULAR)
                .fontColor(this.palette().link)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              if (link.label.length > 0) {
                Text(link.label)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 7, bottom: 7 })
            .borderRadius(6)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onOpenNote(link.sourceNoteId))
          }, (link: Backlink, index: number) => `${index}-${link.sourceNoteId}-${link.label}`)
        }

        if (this.unresolved.length > 0) {
          this.groupLabel('待创建', this.unresolved.length)
          ForEach(this.unresolved, (link: UnresolvedLink) => {
            Row({ space: 8 }) {
              Text('○')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().link)
              Text(link.target)
                .fontSize(TypographyTokens.CAPTION)
                .fontColor(this.palette().link)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .borderRadius(6)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onCreateFromTitle(link.target))
          }, (link: UnresolvedLink, index: number) => `${index}-${link.sourceNoteId}-${link.target}`)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}
