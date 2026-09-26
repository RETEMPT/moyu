/**
 * 首页工作台 (HomeWorkspace)
 *
 * 布局结构（按 Moyu 反馈调整）：
 *   1. 品牌欢迎与快捷操作岛（顶部）
 *   2. Bento 统计卡片栅格
 *   3. 分组与文件封面网格 —— 主页主体，支持上传封面
 *   4. 过往浏览 —— 右下角，展示最近打开的文件
 */
import { curves } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
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
  onUploadCover: (noteId: string, uri: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;
  @State pressedCardId: string = '';
  @State hoveredCardId: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  /** 打开系统相册选择封面图，选中后回调 onUploadCover */
  private async pickCover(noteId: string): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({ MIMEType: picker.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1 });
      if (result.photoUris && result.photoUris.length > 0) {
        this.onUploadCover(noteId, result.photoUris[0]);
      }
    } catch (err) {
      // 用户取消或系统异常，静默忽略
    }
  }

  // ------------------------------------------------------------------
  // 辅助判定
  // ------------------------------------------------------------------

  private isPdfNote(note: NoteItem): boolean {
    const t = note.type.toLowerCase();
    return t === 'pdf' || note.title.toLowerCase().endsWith('.pdf');
  }

  private isHandwritingNote(note: NoteItem): boolean {
    const t = note.type.toLowerCase();
    return t === 'canvas' || t === '白板' || t === '白纸笔记' || t === 'handwriting' || t === '稿纸';
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
        // 顶部红色 PDF 标头与页数
        Row() {
          Text('PDF')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('#E11D48')
          Blank()
          Text(note.pageInfo && note.pageInfo.length > 0 ? note.pageInfo : '考研试卷')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkMuted)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.isDarkMode ? '#332226' : '#FFE4E6')
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10 })

        // 中部大图标与文档名
        Column({ space: 6 }) {
          Text('🗎')
            .fontSize(30)
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
        .padding({ left: 10, right: 10 })
      }
      .width('100%')
      .height(108)
      .borderRadius({ topLeft: 12, topRight: 12 })
      .backgroundColor(this.isDarkMode ? '#282424' : '#FFF1F2')
      .border({ width: { bottom: 1 }, color: { bottom: this.isDarkMode ? '#3A2E30' : '#FFE4E6' } })

      // 底部信息条
      Row({ space: 6 }) {
        Text(note.category)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkSecondary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(note.updateTime)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(this.palette().surface)
    .shadow({ radius: 10, color: this.isDarkMode ? 'rgba(0,0,0,0.35)' : 'rgba(0,0,0,0.04)', offsetY: 2 })
    .border({ width: 1, color: this.palette().borderSubtle })
  }

  /** 2. 白纸底手写笔记专属卡片 */
  @Builder
  handwritingCoverCard(note: NoteItem) {
    Column() {
      // 封面区域
      Column() {
        Row() {
          Text('稿纸演算')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Medium)
            .fontColor('#D97706')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.isDarkMode ? '#362818' : '#FEF3C7')
          Blank()
          Text('✎ 手写笔迹')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10 })

        Column({ space: 6 }) {
          Text('⬡')
            .fontSize(28)
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
        .padding({ left: 10, right: 10 })
      }
      .width('100%')
      .height(108)
      .borderRadius({ topLeft: 12, topRight: 12 })
      .backgroundColor(this.isDarkMode ? '#28241E' : '#FFFBEB')
      .border({ width: { bottom: 1 }, color: { bottom: this.isDarkMode ? '#3D3424' : '#FEF3C7' } })

      Row({ space: 6 }) {
        Text(note.category)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkSecondary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(note.updateTime)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(this.palette().surface)
    .shadow({ radius: 10, color: this.isDarkMode ? 'rgba(0,0,0,0.35)' : 'rgba(0,0,0,0.04)', offsetY: 2 })
    .border({ width: 1, color: this.palette().borderSubtle })
  }

  /** 3. 纯文字随笔卡片 (Notion 极简排版封面) */
  @Builder
  textCoverCard(note: NoteItem) {
    Column() {
      Column() {
        Row() {
          Text('Markdown')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().accent)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.palette().accentSoft)
          Blank()
          Text('▤')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10 })

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
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .height(108)
      .borderRadius({ topLeft: 12, topRight: 12 })
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

      Row({ space: 6 }) {
        Text(note.category)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkSecondary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(note.updateTime)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    }
    .width('100%')
    .borderRadius(14)
    .backgroundColor(this.palette().surface)
    .shadow({ radius: 10, color: this.isDarkMode ? 'rgba(0,0,0,0.35)' : 'rgba(0,0,0,0.04)', offsetY: 2 })
    .border({ width: 1, color: this.palette().borderSubtle })
  }

  /** 统一卡片入口与体感响应 */
  @Builder
  shelfCard(note: NoteItem) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (note.coverUrl && note.coverUrl.length > 0) {
          // 自定义封面
          Image(note.coverUrl)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius({ topLeft: 12, topRight: 12 })
        } else if (this.isPdfNote(note)) {
          this.pdfCoverCard(note)
        } else if (this.isHandwritingNote(note)) {
          this.handwritingCoverCard(note)
        } else {
          this.textCoverCard(note)
        }
      }
      .width('100%')
      .height('100%')

      // 封面上传按钮（hover/长按出现）
      if (this.hoveredCardId === note.id || this.pressedCardId === note.id) {
        Text('📷')
          .fontSize(14)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .borderRadius(14)
          .backgroundColor('rgba(0,0,0,0.55)')
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.pickCover(note.id);
          })
      }
    }
    .width('100%')
    .height(160)
    .clip(true)
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
    .onHover((isHover: boolean) => {
      this.hoveredCardId = isHover ? note.id : '';
    })
    .onClick(() => {
      this.onSelectNote(note);
    })
  }

  // ------------------------------------------------------------------
  // Bento 统计卡片 (Bento Grid)
  // ------------------------------------------------------------------

  @Builder
  statBentoCard(icon: string, label: string, value: string, hint: string, iconBg: string) {
    Column({ space: 6 }) {
      Row() {
        Row() {
          Text(icon)
            .fontSize(14)
        }
        .width(26)
        .height(26)
        .borderRadius(6)
        .backgroundColor(iconBg)
        .justifyContent(FlexAlign.Center)

        Blank()

        Text(value)
          .fontSize(TypographyTokens.TITLE_HERO)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
      }
      .width('100%')

      Column({ space: 1 }) {
        Text(label)
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
        Text(hint)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .padding(14)
    .borderRadius(14)
    .backgroundColor(this.palette().surface)
    .border({ width: 1, color: this.palette().borderSubtle })
    .shadow({ radius: 8, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.03)', offsetY: 2 })
  }

  @Builder
  sectionLabel(text: string) {
    Text(text)
      .fontSize(TypographyTokens.CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.palette().inkSecondary)
      .width('100%')
      .margin({ bottom: 8 })
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          // ---- 1. 品牌欢迎与快捷操作岛 ----
          Column({ space: 14 }) {
            // 品牌标题行（独占整行，避免被快捷按钮挤压导致末字裁切）
            Row({ space: 14 }) {
              BrandMark({ markSize: 46 })
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Text('墨语')
                    .fontSize(TypographyTokens.TITLE_HERO)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette().inkPrimary)
                  Text('第二大脑')
                    .fontSize(TypographyTokens.CAPTION)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.palette().accent)
                    .maxLines(1)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(999)
                    .backgroundColor(this.palette().accentSoft)
                }
                .alignItems(VerticalAlign.Bottom)

                Text('离线优先、隐私可控，让每篇随想与文档都连成思考的星系。')
                  .fontSize(TypographyTokens.BODY_REGULAR)
                  .fontColor(this.palette().inkSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 快捷操作岛（独立一行，窄屏自动换行）
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              Row({ space: 4 }) {
                Text('＋')
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                Text('记随笔')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
              }
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .margin({ right: 8, bottom: 8 })
              .borderRadius(16)
              .backgroundColor(this.palette().accent)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onCreateNote())

              Row({ space: 4 }) {
                Text('🗎')
                  .fontSize(12)
                  .fontColor(this.palette().inkPrimary)
                Text('导入文档')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().inkPrimary)
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .margin({ right: 8, bottom: 8 })
              .borderRadius(16)
              .backgroundColor(this.palette().surface)
              .border({ width: 1, color: this.palette().borderSubtle })
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onImportDocument())

              Row({ space: 4 }) {
                Text('◍')
                  .fontSize(12)
                  .fontColor(this.palette().accent)
                Text('星系图谱')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().accent)
              }
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .margin({ bottom: 8 })
              .borderRadius(16)
              .backgroundColor(this.palette().accentSoft)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onOpenGraph())
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 20 })

          // ---- 2. Bento 统计卡片栅格 ----
          Row({ space: 12 }) {
            this.statBentoCard('📄', '本地笔记', `${this.stats.noteCount}`, 'Markdown 事实源', 'rgba(37,99,235,0.12)')
            this.statBentoCard('🔗', '双向链接', `${this.stats.linkCount}`, '[[概念]] 已解析', 'rgba(99,102,241,0.12)')
            this.statBentoCard('✦', '待创建概念', `${this.stats.unresolvedCount}`, '思维脉络待扩充', 'rgba(217,119,6,0.12)')
            this.statBentoCard('🏷', '聚合标签', `${this.stats.tagCount}`, '#标签 自动归档', 'rgba(5,150,105,0.12)')
          }
          .width('100%')
          .margin({ bottom: 20 })

          // ---- 3. 分组与文件（主页主体） ----
          this.sectionLabel('分组与文件')
          if (this.recentNotes.length === 0) {
            Column({ space: 8 }) {
              Text('还没有本地笔记')
                .fontSize(TypographyTokens.BODY_REGULAR)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().inkPrimary)
              Text('新建或导入一篇文档，立刻开启知识沉淀。')
                .fontSize(TypographyTokens.CAPTION)
                .fontColor(this.palette().inkMuted)
            }
            .width('100%')
            .padding(24)
            .borderRadius(14)
            .backgroundColor(this.palette().surface)
            .border({ width: 1, color: this.palette().borderSubtle })
            .alignItems(HorizontalAlign.Center)
            .margin({ bottom: 20 })
          } else {
            GridRow({ columns: 3, gutter: 14 }) {
              ForEach(this.recentNotes, (note: NoteItem) => {
                GridCol() {
                  this.shelfCard(note)
                }
              }, (note: NoteItem) => noteRenderKey(note))
            }
            .width('100%')
            .margin({ bottom: 20 })
          }

          // ---- 4. 过往浏览（右下角） ----
          Row() {
            Blank()
            Column() {
              this.sectionLabel('过往浏览')
              if (this.recentNotes.length === 0) {
                Text('暂无浏览记录')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
              } else {
                Column({ space: 4 }) {
                  ForEach(this.recentNotes.slice(0, 5), (note: NoteItem) => {
                    Row({ space: 8 }) {
                      Text(this.isPdfNote(note) ? '🗎' : (this.isHandwritingNote(note) ? '⬡' : '▤'))
                        .fontSize(TypographyTokens.CAPTION)
                        .fontColor(this.isPdfNote(note) ? '#E11D48' : (this.isHandwritingNote(note) ? '#D97706' : this.palette().link))
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
                    .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                    .borderRadius(6)
                    .hoverEffect(HoverEffect.Highlight)
                    .onClick(() => this.onSelectNote(note))
                  }, (note: NoteItem) => noteRenderKey(note))
                }
                .width('100%')
              }
            }
            .width(320)
            .padding(14)
            .borderRadius(12)
            .backgroundColor(this.palette().surface)
            .border({ width: 1, color: this.palette().borderSubtle })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Bottom)
          .margin({ top: 8 })

          // ---- 5. 待创建概念 ----
          if (this.unresolvedLinks.length > 0) {
            Column({ space: 6 }) {
              this.sectionLabel('待创建的概念网络')
              Column({ space: 4 }) {
                ForEach(this.unresolvedLinks.slice(0, 3), (link: UnresolvedLink) => {
                  Row({ space: 8 }) {
                    Text('○')
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().link)
                    Text(link.target)
                      .fontSize(TypographyTokens.CAPTION)
                      .fontWeight(FontWeight.Medium)
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
                  .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                  .borderRadius(6)
                  .hoverEffect(HoverEffect.Highlight)
                }, (link: UnresolvedLink) => `${link.sourceNoteId}-${link.target}`)
              }
              .width('100%')
              .padding(8)
              .borderRadius(10)
              .backgroundColor(this.palette().surface)
              .border({ width: 1, color: this.palette().borderSubtle })
            }
            .width('100%')
            .margin({ top: 16 })
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH + 200 })
        .alignItems(HorizontalAlign.Start)
        .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 28, bottom: 48 })
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
