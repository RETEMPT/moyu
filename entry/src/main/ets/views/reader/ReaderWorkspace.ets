/**
 * 研读工作台容器 (支持原生三层架构 PDF/试卷原盘批注、边读边写分屏与白纸底手写笔记)
 *
 * 智能路由：
 *   1. PDF / 试卷真题 (PDF / Doc / 试卷)：
 *      - ✎ 原盘批注 (默认)：原生三层架构，A4 物理排版 + 归一化矢量墨水 (u,v)，缩放平移零漂移
 *      - ◫ 边读边写：左侧试卷题干 (55%) + 右侧白纸草稿板 (45%)
 *      - ◎ 结构研读：纯文本 Markdown 大纲锚点与 [[双向链接]] 沉浸研读
 *   2. 纯文字随笔 (Markdown / Text)：
 *      - 沉浸式打字与阅读，支持一键呼出随堂草稿板
 *   3. 白纸底手写笔记 (Canvas / 白纸笔记 / 手写)：
 *      - 沉浸式白纸底色多色笔画板
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { MarkdownOutlineItem } from '../../common/types/MarkdownOutlineItem';
import { MarkdownReader } from './MarkdownReader';
import { HandwritingCanvas } from './HandwritingCanvas';
import { PdfAnnotatorView } from './pdf/PdfAnnotatorView';

@Component
export struct ReaderWorkspace {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop annotationPaneOpen: boolean = false;
  @Prop jumpToken: number = 0;
  @Prop jumpLine: number = -1;
  /** 当前笔记的收藏态，由 Index 依据 note.favorite 下发 */
  @Prop favorite: boolean = false;

  onBack: () => void = () => {};
  onToggleAnnotation: () => void = () => {};
  onToggleFavorite: (note: NoteItem) => void = () => {};
  onDeleteNote: (note: NoteItem) => void = () => {};
  onSaved: (note: NoteItem, content: string) => void = () => {};
  onSaveStateChange: (state: string) => void = () => {};
  onOutlineUpdated: (items: MarkdownOutlineItem[]) => void = () => {};
  onOpenNoteByTitle: (title: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;
  @State isSplitMode: boolean = false;
  @State activeDocMode: string = 'annotator'; // 'annotator' | 'split' | 'reader'
  /** 删除二次确认态：点「删除」后原地展开为「确认删除 / 取消」，避免误删当前文件 */
  @State deleteArmed: boolean = false;
  /** 上次装载的笔记 id：仅当切换到不同笔记时才重置阅读模式 */
  private lastNoteId: string = '';

  aboutToAppear(): void {
    this.lastNoteId = this.note.id;
    if (this.isDocumentOrExam()) {
      this.activeDocMode = 'annotator';
    } else {
      this.activeDocMode = 'reader';
    }
  }

  onNoteChanged(): void {
    // 同一篇笔记的元数据刷新（如收藏/移动回写）不重置模式，避免把用户踢回默认档
    if (this.note.id === this.lastNoteId) {
      return;
    }
    this.lastNoteId = this.note.id;
    this.deleteArmed = false;
    if (this.isDocumentOrExam()) {
      this.activeDocMode = 'annotator';
    } else {
      this.activeDocMode = 'reader';
    }
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  /** 是否为纯白纸手写型笔记 */
  private isHandwritingNote(): boolean {
    const t = this.note.type.toLowerCase();
    return t === 'canvas' || t === '白板' || t === '白纸笔记' || t === 'handwriting';
  }

  /** 是否为 PDF / Word 试卷或参考资料 */
  private isDocumentOrExam(): boolean {
    const t = this.note.type.toLowerCase();
    const cat = this.note.category;
    return t === 'pdf' || t === 'doc' || t === 'docx' || cat === '试卷题库' || this.note.id === 'note-seed-exam';
  }

  /** 当前是否处于双开分屏状态 */
  private isSplitActive(): boolean {
    if (this.isDocumentOrExam()) {
      return this.activeDocMode === 'split';
    }
    return this.isSplitMode;
  }

  build() {
    Column() {
      // ---- 顶层工作区微工具条：返回 + 模式分段选择器 ----
      Row() {
        // 返回按钮
        Row({ space: 4 }) {
          Text('❮')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
          if (!this.isPhone) {
            Text('返回')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkSecondary)
          }
        }
        .padding({ left: 8, right: this.isPhone ? 8 : 10, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor(this.palette().surfaceSubtle)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onBack())

        // 功能7：收藏切换，写回 note.favorite 并落盘（由 Index.toggleFavorite 处理）
        Row({ space: 4 }) {
          Text(this.favorite ? '★' : '☆')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.favorite ? this.palette().warning : this.palette().inkSecondary)
          if (!this.isPhone) {
            Text(this.favorite ? '已收藏' : '收藏')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.favorite ? this.palette().warning : this.palette().inkSecondary)
          }
        }
        .margin({ left: 8 })
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor(this.favorite ? this.palette().accentSoft : this.palette().surfaceSubtle)
        .hoverEffect(HoverEffect.Highlight)
        .animation({ curve: curves.springMotion(0.25, 0.76) })
        .onClick(() => {
          this.onToggleFavorite(this.note);
        })

        // 删除当前文件：与侧边栏「···」菜单一致，软删除进回收站、可在提示条撤销。
        // 为避免误删，首次点击只「武装」，原地展开确认/取消。
        if (this.deleteArmed) {
          Row({ space: 6 }) {
            Text('取消')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkSecondary)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.palette().surfaceSubtle)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.deleteArmed = false;
              })
            Text(this.isPhone ? '🗑 确认' : '确认删除')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(Color.White)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.palette().danger)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.deleteArmed = false;
                this.onDeleteNote(this.note);
              })
          }
          .margin({ left: 8 })
        } else {
          Row({ space: 4 }) {
            Text('🗑')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkSecondary)
            if (!this.isPhone) {
              Text('删除')
                .fontSize(TypographyTokens.CAPTION)
                .fontColor(this.palette().inkSecondary)
            }
          }
          .margin({ left: 8 })
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor(this.palette().surfaceSubtle)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.deleteArmed = true;
          })
        }

        Blank()

        // 模式切换控制器
        if (!this.isHandwritingNote()) {
          if (this.isDocumentOrExam()) {
            // PDF/试卷三模切换器：原盘批注 / 边读边写 / 结构研读
            Row({ space: 4 }) {
              // 1. 原盘批注
              Text(this.isPhone ? '✎' : '✎ 原盘批注')
                .fontSize(TypographyTokens.CAPTION)
                .fontWeight(this.activeDocMode === 'annotator' ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.activeDocMode === 'annotator' ? this.palette().accent : this.palette().inkSecondary)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(6)
                .backgroundColor(this.activeDocMode === 'annotator' ? this.palette().accentSoft : 'transparent')
                .onClick(() => {
                  animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
                    this.activeDocMode = 'annotator';
                  });
                })

              // 2. 边读边写
              Text(this.isPhone ? '◫' : '◫ 边读边写')
                .fontSize(TypographyTokens.CAPTION)
                .fontWeight(this.activeDocMode === 'split' ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.activeDocMode === 'split' ? this.palette().accent : this.palette().inkSecondary)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(6)
                .backgroundColor(this.activeDocMode === 'split' ? this.palette().accentSoft : 'transparent')
                .onClick(() => {
                  animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
                    this.activeDocMode = 'split';
                  });
                })

              // 3. 结构研读
              Text(this.isPhone ? '◎' : '◎ 结构研读')
                .fontSize(TypographyTokens.CAPTION)
                .fontWeight(this.activeDocMode === 'reader' ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.activeDocMode === 'reader' ? this.palette().accent : this.palette().inkSecondary)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .borderRadius(6)
                .backgroundColor(this.activeDocMode === 'reader' ? this.palette().accentSoft : 'transparent')
                .onClick(() => {
                  animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
                    this.activeDocMode = 'reader';
                  });
                })
            }
            .padding(2)
            .borderRadius(8)
            .backgroundColor(this.palette().surfaceSubtle)
          } else {
            // 普通 Markdown 笔记：边读边写开关
            Row({ space: 6 }) {
              Text('◫')
                .fontSize(TypographyTokens.CAPTION)
                .fontColor(this.isSplitMode ? this.palette().accent : this.palette().inkSecondary)
              if (!this.isPhone) {
                Text(this.isSplitMode ? '收起草稿板' : '边读边写')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(this.isSplitMode ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.isSplitMode ? this.palette().accent : this.palette().inkSecondary)
              }
            }
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor(this.isSplitMode ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .animation({ curve: curves.springMotion(0.25, 0.76) })
            .onClick(() => {
              animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
                this.isSplitMode = !this.isSplitMode;
              });
            })
          }
        }
      }
      .width('100%')
      .height(38)
      .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone) })
      .backgroundColor(this.palette().surface)
      .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

      // ---- 主工作区 ----
      if (this.isHandwritingNote()) {
        // 模式 1：纯白纸多色手写笔记
        Column() {
          HandwritingCanvas({
            note: this.note,
            isScratchpad: false,
            onSaved: this.onSaved,
            onSaveStateChange: this.onSaveStateChange
          })
        }
        .layoutWeight(1)
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
      } else if (this.isDocumentOrExam() && this.activeDocMode === 'annotator') {
        // 模式 2：原生三层架构 PDF/试卷原盘手写批注
        Column() {
          PdfAnnotatorView({
            note: this.note,
            onSaved: this.onSaved,
            onSaveStateChange: this.onSaveStateChange
          })
        }
        .layoutWeight(1)
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
      } else {
        // 模式 3：双开分屏 或 纯文本研读
        Row() {
          // 左侧研读区 (试卷 / 文献 / 随笔)
          Column() {
            MarkdownReader({
              note: this.note,
              jumpToken: this.jumpToken,
              jumpLine: this.jumpLine,
              onSaved: this.onSaved,
              onSaveStateChange: this.onSaveStateChange,
              onOutlineUpdated: this.onOutlineUpdated,
              onOpenNoteByTitle: this.onOpenNoteByTitle
            })
          }
          .layoutWeight(this.isSplitActive() ? 55 : 100)
          .height('100%')
          .animation({ curve: curves.springMotion(0.28, 0.76) })

          // 中间分割条 + 右侧随堂草稿板
          if (this.isSplitActive()) {
            Divider()
              .vertical(true)
              .strokeWidth(1)
              .color(this.palette().borderSubtle)
              .height('100%')

            Column() {
              HandwritingCanvas({
                note: this.note,
                isScratchpad: true,
                onSaved: this.onSaved,
                onSaveStateChange: this.onSaveStateChange
              })
            }
            .layoutWeight(45)
            .height('100%')
            .transition(
              TransitionEffect.move(TransitionEdge.END)
                .combine(TransitionEffect.OPACITY)
                .animation({ curve: curves.springMotion(0.28, 0.76) })
            )
          }
        }
        .layoutWeight(1)
        .width('100%')
        .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.28, 0.76) }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)
  }
}
