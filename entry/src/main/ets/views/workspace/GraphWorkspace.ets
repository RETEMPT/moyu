/**
 * 知识图谱视图 (Obsidian 双链回溯的列表形态)
 *
 * 图谱是探索入口而非知识唯一呈现：先保证「引用可追溯」，
 * 再在后续 Sprint 叠加 Canvas 动态渲染。
 */
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { Backlink, LinkGraph, UnresolvedLink } from '../../common/types/LinkGraph';
import { WorkspaceStats } from '../../common/types/WorkspaceStats';

@Component
export struct GraphWorkspace {
  @Prop graph: LinkGraph = { backlinks: [], unresolvedLinks: [] };
  @Prop stats: WorkspaceStats = { noteCount: 0, linkCount: 0, unresolvedCount: 0, tagCount: 0 };

  onSelectNoteById: (noteId: string) => void = () => {};
  onOpenNoteByTitle: (title: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  @Builder
  panelTitle(text: string, count: number) {
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
    .margin({ bottom: 8 })
  }

  @Builder
  emptyHint(text: string) {
    Column() {
      Text(text)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkMuted)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Text('知识图谱')
            .fontSize(TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Text(`共 ${this.stats.noteCount} 篇笔记 · ${this.stats.linkCount} 条已解析引用 · ${this.stats.unresolvedCount} 个待创建概念`)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .margin({ top: 4, bottom: 18 })

          Row({ space: 24 }) {
            // ---- 已解析引用 ----
            Column() {
              this.panelTitle('已解析引用', this.graph.backlinks.length)
              if (this.graph.backlinks.length === 0) {
                this.emptyHint('还没有任何 [[双链]]。在正文中书写 [[笔记标题]] 即可建立连接。')
              } else {
                ForEach(this.graph.backlinks, (link: Backlink) => {
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(link.sourceTitle)
                        .fontSize(TypographyTokens.BODY_REGULAR)
                        .fontColor(this.palette().inkPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                        .onClick(() => this.onSelectNoteById(link.sourceNoteId))
                      Text('→')
                        .fontSize(TypographyTokens.CAPTION)
                        .fontColor(this.palette().inkMuted)
                      Text(link.targetTitle)
                        .fontSize(TypographyTokens.BODY_REGULAR)
                        .fontColor(this.palette().link)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                        .onClick(() => this.onSelectNoteById(link.targetNoteId))
                    }
                    .width('100%')

                    if (link.label.length > 0) {
                      Text(link.label)
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().inkMuted)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(6)
                  .hoverEffect(HoverEffect.Highlight)
                }, (link: Backlink, index: number) => `${index}-${link.sourceNoteId}-${link.targetNoteId}-${link.label}`)
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(8)
            .backgroundColor(this.palette().surfaceSubtle)

            // ---- 未解析 ----
            Column() {
              this.panelTitle('待创建的概念', this.graph.unresolvedLinks.length)
              if (this.graph.unresolvedLinks.length === 0) {
                this.emptyHint('所有双链都已指向真实笔记，知识网络是闭合的。')
              } else {
                ForEach(this.graph.unresolvedLinks, (link: UnresolvedLink) => {
                  Row({ space: 8 }) {
                    Text('○')
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().link)
                    Text(link.target)
                      .fontSize(TypographyTokens.BODY_REGULAR)
                      .fontColor(this.palette().link)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                      .onClick(() => this.onOpenNoteByTitle(link.target))
                    Text(link.sourceTitle)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().inkMuted)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(6)
                  .hoverEffect(HoverEffect.Highlight)
                }, (link: UnresolvedLink, index: number) => `${index}-${link.sourceNoteId}-${link.target}`)
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(8)
            .backgroundColor(this.palette().surfaceSubtle)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH + 200 })
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 32, right: 32, top: 28, bottom: 48 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor(this.palette().canvas)
  }
}
