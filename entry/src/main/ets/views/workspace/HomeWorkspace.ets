/**
 * 首页工作台 (视觉文件书架与双模式笔记入口)
 *
 * 核心架构：
 *   1. 顶部：工作区品牌 + 统计指标胶囊
 *   2. 左侧：最近记录动态流 + 知识网络待创建概念
 *   3. 右侧/右下侧：【最近使用的文件视觉书架】(Recent Files Shelf)：
 *      - PDF 文档：专有红色 PDF 质感标头、折角阴影、页码与格式标识
 *      - 白纸底笔记：网格纸质感底纹封面、手绘多色笔标识、笔迹统计
 *      - 纯文字随笔：Notion 风格极简排版封面、分类主题色条与文本预览
 *      - 触感交互：短按 0.96 弹簧微凹陷，点击直达对应编辑器
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, LayoutTokens, TypographyTokens, AnimationTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { UnresolvedLink } from '../../common/types/LinkGraph';
import { WorkspaceStats } from '../../common/types/WorkspaceStats';
import { BrandMark } from '../brand/BrandMark';
import { noteRenderKey } from '../../common/utils/ForEachKeys';

@Component
export struct HomeWorkspace {
  @Prop stats: WorkspaceStats = { noteCount: 0, linkCount: 0, unresolvedCount: 0, tagCount: 0 };
  @Prop recentNotes: NoteItem[] = [];
  @Prop unresolvedLinks: UnresolvedLink[] = [];

  onSelectNote: (note: NoteItem) => void = () => {};
  onCreateNote: () => void = () => {};
  onImportDocument: () => void = () => {};
  onOpenGraph: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @State pressedCardId: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  // ------------------------------------------------------------------
  // 辅助函数：封面生成与样式判定
  // ------------------------------------------------------------------

  private isPdfNote(note: NoteItem): boolean {
    const t = note.type.toLowerCase();
    return t === 'pdf' || note.title.toLowerCase().endsWith('.pdf');
  }

  private isHandwritingNote(note: NoteItem): boolean {
    const t = note.type.toLowerCase();
    return t === 'canvas' || t === '白板' || t === '白纸笔记' || t === 'handwriting';
  }

  // ------------------------------------------------------------------
  // 视图构建：封面与卡片生成器
  // ------------------------------------------------------------------

  /** 1. PDF 专属封面卡片 */
  @Builder
  pdfCoverCard(note: NoteItem) {
    Column() {
      // 封面区域
      Column() {
        // 顶部红色 PDF 标头
        Row() {
          Text('PDF')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#E11D48')
          Blank()
          Text(note.pageInfo && note.pageInfo.length > 0 ? note.pageInfo : '文档')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 10 })

        // 中部大图标与文档名
        Column({ space: 4 }) {
          Text('🗎')
            .fontSize(28)
            .fontColor('#E11D48')
          Text(note.title)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 8, right: 8 })
      }
      .width('100%')
      .height(100)
      .borderRadius({ topLeft: 8, topRight: 8 })
      .backgroundColor(this.isDarkMode ? '#282424' : '#FFF1F2')
      .border({ width: { bottom: 1 }, color: { bottom: this.isDarkMode ? '#3A2E30' : '#FFE4E6' } })

      // 底部信息条
      Row({ space: 4 }) {
        Text(note.category)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(note.updateTime)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    }
    .width('100%')
    .borderRadius(10)
    .backgroundColor(this.palette().surface)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
    .border({ width: 1, color: this.palette().borderSubtle })
  }

  /** 2. 白纸底手写笔记专属卡片 */
  @Builder
  handwritingCoverCard(note: NoteItem) {
    Column() {
      // 白纸网格质感封面
      Column() {
        Row() {
          Text('白纸笔记')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkSecondary)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.palette().surfaceSubtle)
          Blank()
          Text('✎ 多色笔')
            .fontSize(TypographyTokens.TINY)
            .fontColor('#D97706')
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 10 })

        Column({ space: 4 }) {
          Text('⬡')
            .fontSize(26)
            .fontColor('#D97706')
          Text(note.title)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 8, right: 8 })
      }
      .width('100%')
      .height(100)
      .borderRadius({ topLeft: 8, topRight: 8 })
      .backgroundColor(this.isDarkMode ? '#24221E' : '#FFFBEB')
      .border({ width: { bottom: 1 }, color: { bottom: this.isDarkMode ? '#383324' : '#FEF3C7' } })

      Row({ space: 4 }) {
        Text(note.category)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(note.updateTime)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    }
    .width('100%')
    .borderRadius(10)
    .backgroundColor(this.palette().surface)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
    .border({ width: 1, color: this.palette().borderSubtle })
  }

  /** 3. 纯文字随笔卡片 (Notion 极简排版封面) */
  @Builder
  textCoverCard(note: NoteItem) {
    Column() {
      // 封面区域
      Column() {
        Row() {
          Text('纯文字')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkSecondary)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.palette().surfaceSubtle)
          Blank()
          Text('▤')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 10 })

        Column({ space: 4 }) {
          Text(note.title)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(note.previewText)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkSecondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 10, right: 10 })
      }
      .width('100%')
      .height(100)
      .borderRadius({ topLeft: 8, topRight: 8 })
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

      Row({ space: 4 }) {
        Text(note.category)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(note.updateTime)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    }
    .width('100%')
    .borderRadius(10)
    .backgroundColor(this.palette().surface)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
    .border({ width: 1, color: this.palette().borderSubtle })
  }

  /** 统一卡片入口与体感响应 */
  @Builder
  shelfCard(note: NoteItem) {
    Column() {
      if (this.isPdfNote(note)) {
        this.pdfCoverCard(note)
      } else if (this.handwritingCheck(note)) {
        this.handwritingCoverCard(note)
      } else {
        this.textCoverCard(note)
      }
    }
    .scale({
      x: this.pressedCardId === note.id ? AnimationTokens.SCALE_PRESSED : 1.0,
      y: this.pressedCardId === note.id ? AnimationTokens.SCALE_PRESSED : 1.0
    })
    .animation({ curve: curves.springMotion(0.25, 0.76) })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedCardId = note.id;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedCardId = '';
      }
    })
    .onClick(() => {
      this.onSelectNote(note);
    })
  }

  private handwritingCheck(note: NoteItem): boolean {
    return this.isHandwritingNote(note);
  }

  // ------------------------------------------------------------------
  // 统计与标题
  // ------------------------------------------------------------------

  @Builder
  statCard(label: string, value: string, hint: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(TypographyTokens.TITLE_SECTION)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().inkPrimary)
      Text(label)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkSecondary)
      Text(hint)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(8)
    .backgroundColor(this.palette().surfaceSubtle)
  }

  @Builder
  sectionLabel(text: string) {
    Text(text)
      .fontSize(TypographyTokens.TINY)
      .fontColor(this.palette().inkMuted)
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .margin({ bottom: 6 })
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          // ---- 品牌欢迎 ----
          Row({ space: 12 }) {
            BrandMark({ markSize: 44 })
            Column({ space: 4 }) {
              Text('墨语 · 第二大脑')
                .fontSize(TypographyTokens.TITLE_HERO)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette().inkPrimary)
              Text('离线可用、数据私密，让每篇笔记与文档都连成思考的星系。')
                .fontSize(TypographyTokens.BODY_REGULAR)
                .fontColor(this.palette().inkSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: 18 })

          // ---- 统计胶囊 ----
          Row({ space: 10 }) {
            this.statCard('本地笔记', `${this.stats.noteCount}`, 'Markdown 事实源')
            this.statCard('双向链接', `${this.stats.linkCount}`, '[[笔记]] 已解析')
            this.statCard('待解析链接', `${this.stats.unresolvedCount}`, '目标概念待创建')
            this.statCard('标签', `${this.stats.tagCount}`, '#标签 自动索引')
          }
          .width('100%')
          .margin({ bottom: 24 })

          // ---- 主体双栏：左侧列表流 + 右侧视觉书架 ----
          Row({ space: 24 }) {
            // 左侧：最近文字流与待解析概念
            Column() {
              this.sectionLabel('最近动态')
              if (this.recentNotes.length === 0) {
                Column({ space: 6 }) {
                  Text('还没有本地笔记')
                    .fontSize(TypographyTokens.BODY_REGULAR)
                    .fontColor(this.palette().inkSecondary)
                  Text('新建或导入一篇文档，立刻开启知识沉淀。')
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().inkMuted)
                }
                .width('100%')
                .padding({ top: 16, bottom: 16 })
                .alignItems(HorizontalAlign.Start)
              } else {
                ForEach(this.recentNotes.slice(0, 5), (note: NoteItem) => {
                  Row({ space: 10 }) {
                    Text(this.isPdfNote(note) ? '🗎' : (this.handwritingCheck(note) ? '⬡' : '▤'))
                      .fontSize(TypographyTokens.BODY_REGULAR)
                      .fontColor(this.isPdfNote(note) ? '#E11D48' : (this.handwritingCheck(note) ? '#D97706' : this.palette().link))

                    Column({ space: 2 }) {
                      Text(note.title)
                        .fontSize(TypographyTokens.BODY_REGULAR)
                        .fontColor(this.palette().inkPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(note.previewText)
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().inkMuted)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text(note.updateTime)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().inkMuted)
                  }
                  .width('100%')
                  .padding({ left: 8, right: 8, top: 8, bottom: 8 })
                  .borderRadius(6)
                  .hoverEffect(HoverEffect.Highlight)
                  .onClick(() => this.onSelectNote(note))
                }, (note: NoteItem) => noteRenderKey(note))
              }

              // 待创建概念
              if (this.unresolvedLinks.length > 0) {
                Column() {
                  this.sectionLabel('待创建的概念网络')
                  ForEach(this.unresolvedLinks.slice(0, 3), (link: UnresolvedLink) => {
                    Row({ space: 8 }) {
                      Text('○')
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().link)
                      Text(link.target)
                        .fontSize(TypographyTokens.CAPTION)
                        .fontColor(this.palette().link)
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`来自 ${link.sourceTitle}`)
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().inkMuted)
                        .maxLines(1)
                    }
                    .width('100%')
                    .padding({ top: 4, bottom: 4 })
                  }, (link: UnresolvedLink) => `${link.sourceNoteId}-${link.target}`)
                }
                .width('100%')
                .margin({ top: 16 })
                .alignItems(HorizontalAlign.Start)
              }
            }
            .layoutWeight(2)
            .alignItems(HorizontalAlign.Start)

            // 右侧/右下侧：【最近使用的文件视觉书架】
            Column() {
              Row() {
                this.sectionLabel('最近使用的文件')
                Blank()
                Row({ space: 4 }) {
                  Text('＋ 记随笔')
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().accent)
                    .onClick(() => this.onCreateNote())
                }
              }
              .width('100%')

              // 2 列卡片流
              GridRow({ columns: 2, gutter: 12 }) {
                ForEach(this.recentNotes.slice(0, 6), (note: NoteItem) => {
                  GridCol() {
                    this.shelfCard(note)
                  }
                }, (note: NoteItem) => noteRenderKey(note))
              }
              .width('100%')
            }
            .layoutWeight(3)
            .alignItems(HorizontalAlign.Start)
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
