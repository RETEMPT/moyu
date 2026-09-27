/**
 * 原生 PDF / 试卷原盘直接批注工作台 (PdfAnnotatorView)
 *
 * 核心设计：
 *   1. 华为笔记风格的悬浮灵动胶囊工具栏 (Floating Capsule HUD)：
 *      - 钢笔模式 (4 色：炭黑、经典蓝、朱红、翡翠绿)
 *      - 荧光笔模式 (半透明黄、薄荷绿，保证不遮挡试卷文字)
 *      - 像素/单笔橡皮擦与撤销 (Undo) 栈
 *      - 漫游手势模式 (Pan mode)：支持单指平移与双指捏合缩放，硬件级防手掌误触
 *   2. 多页 A4 物理排版连续视口 (Continuous Multi-Page Viewport)：
 *      - 支持无级缩放 (0.7x ~ 2.5x) 与居中自适应
 *   3. 归一化矢量数据自动持久化：
 *      - 防抖自动落盘至 NoteItem.pageAnnotations
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import {
  AnnotationTool,
  DocumentAnnotationData,
  PageAnnotationStroke,
  PdfPageModel
} from '../../../common/types/PdfAnnotationTypes';
import { PdfPageCanvas } from './PdfPageCanvas';
import { PdfDocumentService } from '../../../services/document/PdfDocumentService';

const PEN_COLORS: string[] = ['#DC2626', '#2563EB', '#1C1917', '#059669'];
const HIGHLIGHTER_COLORS: string[] = ['#FACC15', '#4ADE80'];
const STROKE_WIDTHS: number[] = [2, 4, 8];

@Component
export struct PdfAnnotatorView {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop @Watch('onCurrentPageChanged') currentPage: number = 1;
  @Prop barsVisible: boolean = true;
  @Prop isContinuousScroll: boolean = true;
  onSaved: (note: NoteItem, content: string) => void = () => {};
  onSaveStateChange: (state: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  // 交互与工具栏状态
  @Prop isAnnotateMode: boolean = false;
  @Prop currentTool: AnnotationTool = 'pen';
  @Prop selectedColor: string = '#DC2626';
  @Prop selectedWidth: number = 3;
  @Prop @Watch('onUndoTriggered') undoTrigger: number = 0;
  @Prop @Watch('onClearTriggered') clearTrigger: number = 0;
  @State zoomScale: number = 1.0;
  @State currentPageIdx: number = 0;

  // 滚动控制器
  private scroller: Scroller = new Scroller();

  // 批注数据集（按页）
  @State pageStrokes: Record<number, PageAnnotationStroke[]> = {};
  // 撤销历史栈
  private undoStack: PageAnnotationStroke[] = [];
  private saveTimer: number = -1;

  onCurrentPageChanged(): void {
    const idx = Math.max(0, Math.min(this.pages.length - 1, this.currentPage - 1));
    this.currentPageIdx = idx;
    try {
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: idx * 920,
        animation: { duration: 300, curve: Curve.EaseInOut }
      });
    } catch (e) {
      // ignore
    }
  }

  @State pages: PdfPageModel[] = [];

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.initPages();
    this.loadAnnotations();
  }

  onNoteChanged(): void {
    this.initPages();
    this.loadAnnotations();
  }

  /** 根据文档真实页数与标题动态生成排版页面 */
  private initPages(): void {
    const total = this.note.pageCount && this.note.pageCount > 0 ? this.note.pageCount : 9;
    this.pages = PdfDocumentService.getInstance().generatePageModels(total, this.note.title);
  }

  /** 从笔记中加载归一化矢量批注 */
  private loadAnnotations(): void {
    const raw = this.note.pageAnnotations;
    if (raw && raw.length > 0) {
      try {
        const parsed = JSON.parse(raw) as DocumentAnnotationData;
        if (parsed && parsed.pages) {
          this.pageStrokes = parsed.pages;
          return;
        }
      } catch (e) {
        console.error(`加载文档批注数据失败: ${JSON.stringify(e)}`);
      }
    }
    this.pageStrokes = { 0: [], 1: [] };
  }

  /** 收到单笔新增时追加并触发防抖持久化 */
  private handleStrokeAdded(stroke: PageAnnotationStroke): void {
    const pIdx = stroke.pageIndex;
    const current = this.pageStrokes[pIdx] ? [...this.pageStrokes[pIdx]] : [];
    current.push(stroke);
    this.pageStrokes[pIdx] = current;
    this.undoStack.push(stroke);
    this.scheduleSave();
  }

  /** 橡皮擦点位命中擦除 */
  private handleEraseAtPoint(pageIndex: number, u: number, v: number): void {
    const current = this.pageStrokes[pageIndex];
    if (!current || current.length === 0) {
      return;
    }
    // 阈值：归一化距离 0.04 内的笔画予以清除
    const remaining = current.filter((stroke) => {
      for (let i = 0; i < stroke.points.length; i++) {
        const pt = stroke.points[i];
        const distSq = (pt.u - u) * (pt.u - u) + (pt.v - v) * (pt.v - v);
        if (distSq < 0.0016) {
          return false;
        }
      }
      return true;
    });

    if (remaining.length !== current.length) {
      this.pageStrokes[pageIndex] = remaining;
      this.scheduleSave();
    }
  }

  /** 撤销上一笔 */
  private handleUndo(): void {
    if (this.undoStack.length === 0) {
      return;
    }
    const lastStroke = this.undoStack.pop();
    if (!lastStroke) {
      return;
    }
    const pIdx = lastStroke.pageIndex;
    const current = this.pageStrokes[pIdx];
    if (current && current.length > 0) {
      this.pageStrokes[pIdx] = current.filter((s) => s.id !== lastStroke.id);
      this.scheduleSave();
    }
  }

  onUndoTriggered(): void {
    this.handleUndo();
  }

  onClearTriggered(): void {
    this.handleClearCurrentPage();
  }

  /** 清空当前页全部批注 */
  private handleClearCurrentPage(): void {
    const pIdx = this.currentPageIdx;
    this.pageStrokes[pIdx] = [];
    this.undoStack = this.undoStack.filter((s) => s.pageIndex !== pIdx);
    this.scheduleSave();
  }

  /** 计划防抖自动落盘 */
  private scheduleSave(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
    }
    this.onSaveStateChange('批注保存中...');
    this.saveTimer = setTimeout(() => {
      this.flushSave();
    }, 800);
  }

  /** 序列化并存入 NoteItem.pageAnnotations */
  private flushSave(): void {
    const data: DocumentAnnotationData = {
      version: 1,
      pageCount: this.pages.length,
      pages: this.pageStrokes
    };
    const serialized = JSON.stringify(data);
    const updatedNote: NoteItem = {
      id: this.note.id,
      title: this.note.title,
      category: this.note.category,
      type: this.note.type,
      previewText: this.note.previewText,
      tag: this.note.tag,
      tagColor: this.note.tagColor,
      updateTime: this.note.updateTime,
      contentDetail: this.note.contentDetail,
      pageInfo: this.note.pageInfo,
      extraInfo: this.note.extraInfo,
      coverUrl: this.note.coverUrl,
      strokes: this.note.strokes,
      scratchpadStrokes: this.note.scratchpadStrokes,
      pageAnnotations: serialized
    };
    this.onSaved(updatedNote, updatedNote.contentDetail);
    this.onSaveStateChange('原盘批注已保存');
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isContinuousScroll) {
        // ---- 连续排版视口 (可缩放、连续滚屏) ----
        Scroll(this.scroller) {
          Column({ space: 24 }) {
            ForEach(this.pages, (pm: PdfPageModel) => {
              PdfPageCanvas({
                pageModel: pm,
                strokes: this.pageStrokes[pm.pageIndex] || [],
                isAnnotateMode: this.isAnnotateMode,
                tool: this.currentTool,
                selectedColor: this.selectedColor,
                selectedWidth: this.selectedWidth,
                isDarkMode: this.isDarkMode,
                onStrokeAdded: (stroke: PageAnnotationStroke) => this.handleStrokeAdded(stroke),
                onEraseAtPoint: (u: number, v: number) => this.handleEraseAtPoint(pm.pageIndex, u, v)
              })
            }, (pm: PdfPageModel) => `page_${pm.pageIndex}`)
          }
          .width(`${100 * this.zoomScale}%`)
          .padding({ left: 32, right: 32, top: 24, bottom: 96 })
          .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Auto)
        .backgroundColor(this.palette().canvas)
        .transition(
          TransitionEffect.OPACITY
            .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
        )
      } else {
        // ---- 单页排版视口 (单页居中、翻页聚焦) ----
        Column() {
          if (this.pages[this.currentPageIdx]) {
            PdfPageCanvas({
              pageModel: this.pages[this.currentPageIdx],
              strokes: this.pageStrokes[this.currentPageIdx] || [],
              isAnnotateMode: this.isAnnotateMode,
              tool: this.currentTool,
              selectedColor: this.selectedColor,
              selectedWidth: this.selectedWidth,
              isDarkMode: this.isDarkMode,
              onStrokeAdded: (stroke: PageAnnotationStroke) => this.handleStrokeAdded(stroke),
              onEraseAtPoint: (u: number, v: number) => this.handleEraseAtPoint(this.currentPageIdx, u, v)
            })
            .transition(
              TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
                .animation({ duration: AnimationTokens.DURATION_PAGE_TRANSITION, curve: AnimationTokens.CURVE_STANDARD })
            )
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 16, bottom: 80 })
        .backgroundColor(this.palette().canvas)
        .transition(
          TransitionEffect.OPACITY
            .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
        )
      }
    }
    .width('100%')
    .height('100%')
  }
}
