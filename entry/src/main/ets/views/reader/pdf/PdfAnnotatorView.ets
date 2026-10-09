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
import { ReaderSaveKind } from '../../../common/types/ReaderSaveKind';
import {
  AnnotationTool,
  DocumentAnnotationData,
  PageAnnotationStroke,
  PdfPageModel
} from '../../../common/types/PdfAnnotationTypes';
import { PdfPageCanvas } from './PdfPageCanvas';
import { PdfDocumentService } from '../../../services/document/PdfDocumentService';
import { PdfAnnotationPolicy } from '../../../services/document/PdfAnnotationPolicy';
import { InkRenderer } from '../../../services/ink/InkRenderer';
import { StylusShortcutService } from '../../../services/ink/StylusShortcutService';

interface InkHistoryFrame { pageIndex: number; before: PageAnnotationStroke[]; after: PageAnnotationStroke[]; }

const PEN_COLORS: string[] = ['#DC2626', '#2563EB', '#1C1917', '#059669'];
const HIGHLIGHTER_COLORS: string[] = ['#FACC15', '#4ADE80'];
const STROKE_WIDTHS: number[] = [2, 4, 8];

@Component
export struct PdfAnnotatorView {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop @Watch('onCurrentPageChanged') currentPage: number = 1;
  @Prop @Watch('saveForExit') exitSaveToken: number = 0;
  onCommitForExit: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onExitSaveFinished: (ok: boolean, noteId: string, saveToken: number) => void = () => {};
  @Prop barsVisible: boolean = true;
  @Prop @Watch('finishActiveInput') isContinuousScroll: boolean = true;
  onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onSaveStateChange: (state: string) => void = () => {};
  onDirtyChange: (dirty: boolean) => void = () => {};
  onReadingScroll: (offset: number) => void = () => {};
  onBlankTap: () => void = () => {};
  onPageChanged: (page: number) => void = () => {};
  onRestoreSource: () => void = () => {};
  onSourceReady: (ready: boolean) => void = () => {};
  onAnnotationError: (message: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';

  // 交互与工具栏状态
  @Prop isAnnotateMode: boolean = false;
  @Prop currentTool: AnnotationTool = 'pen';
  @Prop selectedColor: string = '#DC2626';
  @Prop selectedWidth: number = 3;
  @Prop @Watch('onUndoTriggered') undoTrigger: number = 0;
  @Prop @Watch('onRedoTriggered') redoTrigger: number = 0;
  @Prop fingerDrawing: boolean = false;
  onToggleEraser: () => void = () => {};
  onShowPenTools: () => void = () => {};
  @State inkContact: boolean = false;
  @Prop @Watch('onClearTriggered') clearTrigger: number = 0;
  @State zoomScale: number = 1.0;
  @State currentPageIdx: number = 0;
  @State viewportWidth: number = 360;

  // 滚动控制器
  private scroller: Scroller = new Scroller();
  private panScroller: Scroller = new Scroller();

  // 批注数据集（按页）
  @State pageStrokes: Record<number, PageAnnotationStroke[]> = {};
  // 撤销历史栈
  private undoStack: InkHistoryFrame[] = [];
  private redoStack: InkHistoryFrame[] = [];
  private eraseBefore: PageAnnotationStroke[] | null = null;
  private erasePage: number = -1;
  private shortcuts: StylusShortcutService = new StylusShortcutService();
  private zoomStart: number = 1;
  private saveTimer: number = -1;
  private saveRevision: number = 0;
  private savedRevision: number = 0;
  private loadedNoteId: string = '';
  private editingNote: NoteItem | null = null;
  private activeInputFinisher: (() => void) | null = null;
  private activeInputPage: number = -1;
  private readyPages: Record<number, boolean> = {};
  private loadedSource: string = '';
  private loadedPageCount: number = 0;
  @State private annotationError: string = '';
  private loadedAnnotationRaw: string | undefined = undefined;

  onCurrentPageChanged(): void {
    const idx = Math.max(0, Math.min(this.pages.length - 1, this.currentPage - 1));
    if (idx === this.currentPageIdx) { return; }
    this.finishActiveInput();
    this.currentPageIdx = idx;
    this.onSourceReady(this.readyPages[idx] === true && !this.annotationError);
    try {
      this.scroller.scrollToIndex(idx, true, ScrollAlign.START);
    } catch (e) {
      // ignore
    }
  }

  @State pages: PdfPageModel[] = [];

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  aboutToAppear(): void {
    this.shortcuts.start(() => this.isAnnotateMode && !this.annotationError && this.readyPages[this.currentPageIdx] === true && !this.inkContact, this.onToggleEraser, this.onShowPenTools);
    this.loadedNoteId = this.note.id;
    this.editingNote = JSON.parse(JSON.stringify(this.note)) as NoteItem;
    this.initPages();
    this.loadAnnotations();
    this.loadedSource = this.note.sourceUri || ''; this.loadedPageCount = this.pages.length;
  }

  aboutToDisappear(): void {
    this.shortcuts.stop();
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
  }

  onNoteChanged(): void {
    if (this.loadedNoteId === this.note.id) {
      if (this.loadedSource !== (this.note.sourceUri || '') || this.loadedPageCount !== this.note.pageCount) {
        this.finishActiveInput(); this.editingNote = JSON.parse(JSON.stringify(this.note)) as NoteItem;
        this.readyPages = {}; this.onSourceReady(false); this.initPages();
        this.loadedSource = this.note.sourceUri || ''; this.loadedPageCount = this.pages.length;
        this.currentPageIdx = Math.max(0, Math.min(this.currentPageIdx, this.pages.length - 1));
      }
      return;
    }
    this.finishActiveInput();
    this.finishErase(false);
    if (this.saveTimer !== -1) { clearTimeout(this.saveTimer); this.flushSave(); }
    this.loadedNoteId = this.note.id;
    this.editingNote = JSON.parse(JSON.stringify(this.note)) as NoteItem;
    this.undoStack = [];
    this.redoStack = []; this.eraseBefore = null; this.inkContact = false;
    this.zoomScale = 1; this.currentPageIdx = 0;
    this.initPages();
    this.loadAnnotations();
    this.readyPages = {}; this.onSourceReady(false);
    this.loadedSource = this.note.sourceUri || ''; this.loadedPageCount = this.pages.length;
  }

  /** 根据文档真实页数与标题动态生成排版页面 */
  private initPages(): void {
    const total = this.note.pageCount && this.note.pageCount > 0 ? this.note.pageCount : 1;
    this.pages = PdfDocumentService.getInstance().generatePageModels(total, this.note.title);
  }

  /** 从笔记中加载归一化矢量批注 */
  private loadAnnotations(): void {
    this.saveRevision = 0; this.savedRevision = 0; this.onDirtyChange(false);
    this.annotationError = ''; this.onAnnotationError('');
    this.loadedAnnotationRaw = this.note.pageAnnotations;
    try {
      this.pageStrokes = PdfAnnotationPolicy.read(this.note.pageAnnotations, this.pages.length).pages;
    } catch (error) {
      this.pageStrokes = {};
      this.annotationError = error instanceof Error ? error.message : '批注数据无法读取，原记录已保留。';
      this.onAnnotationError(this.annotationError); this.onSourceReady(false); this.onSaveStateChange('批注数据异常');
    }
  }

  private remember(pageIndex: number, before: PageAnnotationStroke[], after: PageAnnotationStroke[]): void {
    this.undoStack.push({ pageIndex, before: before.slice(), after: after.slice() });
    if (this.undoStack.length > 50) { this.undoStack.shift(); }
    this.redoStack = [];
  }

  private handleStrokeAdded(stroke: PageAnnotationStroke): void {
    if (this.annotationError) { return; }
    const before = this.pageStrokes[stroke.pageIndex] || [];
    const after = [...before, stroke];
    this.remember(stroke.pageIndex, before, after);
    this.pageStrokes[stroke.pageIndex] = after; this.scheduleSave();
  }

  private beginErase(pageIndex: number): void {
    if (this.annotationError) { return; }
    this.erasePage = pageIndex; this.eraseBefore = (this.pageStrokes[pageIndex] || []).slice();
  }

  private finishErase(commit: boolean): void {
    if (!this.eraseBefore) { return; }
    const before = this.eraseBefore; const page = this.erasePage;
    this.eraseBefore = null; this.erasePage = -1;
    const after = this.pageStrokes[page] || [];
    if (!commit) { this.pageStrokes[page] = before; return; }
    if (before.length !== after.length) { this.remember(page, before, after); this.scheduleSave(); }
  }

  private handleEraseAtPoint(pageIndex: number, u: number, v: number, width: number, height: number): void {
    const current = this.pageStrokes[pageIndex];
    if (!current || !this.eraseBefore) { return; }
    const x = u * width; const y = v * height;
    const remaining = current.filter((stroke: PageAnnotationStroke) => {
      const radius = 10 + stroke.width * width / 1440;
      for (let i = 0; i < stroke.points.length; i++) {
        const a = stroke.points[Math.max(0, i - 1)]; const b = stroke.points[i];
        if (InkRenderer.nearSegment(x, y, a.u * width, a.v * height, b.u * width, b.v * height, radius)) { return false; }
      }
      return true;
    });
    if (remaining.length !== current.length) { this.pageStrokes[pageIndex] = remaining; }
  }

  private handleUndo(): void {
    this.finishActiveInput();
    const frame = this.undoStack.pop();
    if (!frame) { return; }
    this.pageStrokes[frame.pageIndex] = frame.before.slice(); this.redoStack.push(frame); this.scheduleSave();
  }

  onRedoTriggered(): void {
    this.finishActiveInput();
    const frame = this.redoStack.pop();
    if (!frame) { return; }
    this.pageStrokes[frame.pageIndex] = frame.after.slice(); this.undoStack.push(frame); this.scheduleSave();
  }

  onUndoTriggered(): void { this.handleUndo(); }
  onClearTriggered(): void {
    this.finishActiveInput();
    const page = this.currentPageIdx; const before = this.pageStrokes[page] || [];
    if (!before.length) { return; }
    this.remember(page, before, []); this.pageStrokes[page] = []; this.scheduleSave();
  }

  /** 计划防抖自动落盘 */
  private scheduleSave(): void {
    if (this.annotationError) { return; }
    this.saveRevision++;
    this.onDirtyChange(true);
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
    }
    this.onSaveStateChange('保存中');
    this.saveTimer = setTimeout(() => {
      this.flushSave();
    }, 800);
  }

  /** 序列化并存入 NoteItem.pageAnnotations */
  private async flushSave(): Promise<void> {
    this.saveTimer = -1;
    if (this.annotationError) { this.onSaveStateChange('批注数据异常'); return; }
    const revision = this.saveRevision;
    const updatedNote = this.annotationSnapshot();
    try { await this.onSaved(updatedNote, updatedNote.contentDetail, 'pdf'); if (revision === this.saveRevision && updatedNote.id === this.loadedNoteId) { this.savedRevision = revision; this.onDirtyChange(false); this.onSaveStateChange('已保存'); } }
    catch { if (revision === this.saveRevision && updatedNote.id === this.loadedNoteId) { this.onSaveStateChange('保存失败'); } }
  }

  private async saveForExit(): Promise<void> {
    const requestToken = this.exitSaveToken;
    if (this.annotationError) {
      this.onSaveStateChange('批注数据异常');
      // A read-only invalid record can leave alongside a saved scratchpad without rewriting its original bytes.
      const untouched = this.saveRevision === 0 && this.loadedAnnotationRaw === this.note.pageAnnotations;
      this.onExitSaveFinished(untouched, this.loadedNoteId, requestToken); return;
    }
    this.finishActiveInput();
    if (this.saveTimer !== -1) { clearTimeout(this.saveTimer); this.saveTimer = -1; }
    const revision = this.saveRevision;
    const snapshot = this.annotationSnapshot();
    try {
      await this.onCommitForExit(snapshot, snapshot.contentDetail, 'pdf');
      if (snapshot.id !== this.loadedNoteId || revision !== this.saveRevision) { this.onExitSaveFinished(false, snapshot.id, requestToken); return; }
      this.savedRevision = revision; this.onDirtyChange(false); this.onSaveStateChange('已保存');
      this.onExitSaveFinished(true, snapshot.id, requestToken);
    } catch {
      if (snapshot.id === this.loadedNoteId && revision === this.saveRevision) { this.onSaveStateChange('保存失败'); }
      this.onExitSaveFinished(false, snapshot.id, requestToken);
    }
  }

  private annotationSnapshot(): NoteItem {
    if (this.annotationError) { throw new Error(this.annotationError); }
    const data: DocumentAnnotationData = {
      version: 1,
      pageCount: this.pages.length,
      pages: this.pageStrokes
    };
    const serialized = JSON.stringify(data);
    const updatedNote = JSON.parse(JSON.stringify(this.editingNote || this.note)) as NoteItem;
    updatedNote.pageAnnotations = serialized;
    return updatedNote;
  }

  private finishActiveInput(): void {
    const finish = this.activeInputFinisher;
    this.activeInputFinisher = null; this.activeInputPage = -1;
    if (finish !== null) { finish(); }
  }

  private setActiveInputFinisher(pageIndex: number, finish: (() => void) | null): void {
    if (finish === null) {
      if (this.activeInputPage === pageIndex) { this.activeInputFinisher = null; this.activeInputPage = -1; }
      return;
    }
    if (this.activeInputPage !== pageIndex) { this.finishActiveInput(); }
    this.activeInputPage = pageIndex; this.activeInputFinisher = finish;
  }

  private setPageSourceReady(pageIndex: number, ready: boolean): void {
    this.readyPages[pageIndex] = ready;
    if (pageIndex === this.currentPageIdx) { this.onSourceReady(ready && !this.annotationError); }
  }

  private setPageInkContact(pageIndex: number, active: boolean): void {
    if (!active && this.activeInputPage !== -1 && this.activeInputPage !== pageIndex) { return; }
    this.inkContact = active; this.onDirtyChange(active || this.saveRevision !== this.savedRevision);
  }

  private judgeNavigation(event: BaseGestureEvent): GestureJudgeResult {
    return event.sourceTool === SourceTool.Pen || this.inkContact ||
      (this.isAnnotateMode && this.fingerDrawing && this.currentTool !== 'pan' && event.fingerList.length === 1)
      ? GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isContinuousScroll) {
        // 连续列表按实际页面高度定位，位图由可见页管理。
        Scroll(this.panScroller) {
        List({ space: 24, scroller: this.scroller }) {
          ForEach(this.pages, (pm: PdfPageModel) => {
            ListItem() {
              PdfPageCanvas({
                pageModel: pm,
                sourceUri: this.note.sourceUri || '',
                useRealPdf: true,
                strokes: this.pageStrokes[pm.pageIndex] || [],
                isAnnotateMode: this.isAnnotateMode && !this.annotationError,
                tool: this.currentTool,
                selectedColor: this.selectedColor,
                selectedWidth: this.selectedWidth,
                isDarkMode: this.isDarkMode,
                onStrokeAdded: (stroke: PageAnnotationStroke) => this.handleStrokeAdded(stroke),
                fingerDrawing: this.fingerDrawing,
                onPenActive: () => this.shortcuts.claim(),
                onActiveFinisherChange: (finish: (() => void) | null) => this.setActiveInputFinisher(pm.pageIndex, finish),
                onSourceReady: (ready: boolean) => this.setPageSourceReady(pm.pageIndex, ready),
                onRestoreSource: () => this.onRestoreSource(),
                onInkContactChange: (active: boolean) => this.setPageInkContact(pm.pageIndex, active),
                onEraseStarted: () => this.beginErase(pm.pageIndex),
                onEraseFinished: (commit: boolean) => this.finishErase(commit),
                onEraseAtPoint: (u: number, v: number, width: number, height: number) => this.handleEraseAtPoint(pm.pageIndex, u, v, width, height)
              })
              .width('100%')
            }
          }, (pm: PdfPageModel) => `page_${pm.pageIndex}`)
        }
        .width(this.viewportWidth * this.zoomScale)
        .padding({ left: 32, right: 32, top: 24, bottom: 96 })
        .height('100%')
        .scrollBar(BarState.Auto)
        .onScroll((offset: number) => { if (!this.inkContact && !this.isAnnotateMode) { this.onReadingScroll(offset); } })
        .onScrollIndex((start: number) => {
          this.currentPageIdx = Math.max(0, start); this.onPageChanged(this.currentPageIdx + 1);
          this.onSourceReady(this.readyPages[this.currentPageIdx] === true && !this.annotationError);
        })
        .onGestureJudgeBegin((_info: GestureInfo, event: BaseGestureEvent) => this.judgeNavigation(event))
        .backgroundColor(this.palette().canvas)
        .onClick(() => { if (!this.inkContact && !this.isAnnotateMode) { this.onBlankTap(); } })
        .transition(
          TransitionEffect.OPACITY
            .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
        )
        }
        .width('100%').height('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
        .onGestureJudgeBegin((_info: GestureInfo, event: BaseGestureEvent) => this.judgeNavigation(event))
      } else {
        // ---- 单页排版视口 (单页居中、翻页聚焦) ----
        Scroll(this.panScroller) {
        Column() {
          if (this.pages[this.currentPageIdx]) {
            PdfPageCanvas({
              pageModel: this.pages[this.currentPageIdx],
              sourceUri: this.note.sourceUri || '',
              useRealPdf: true,
              strokes: this.pageStrokes[this.currentPageIdx] || [],
              isAnnotateMode: this.isAnnotateMode && !this.annotationError,
              tool: this.currentTool,
              selectedColor: this.selectedColor,
              selectedWidth: this.selectedWidth,
              isDarkMode: this.isDarkMode,
              onStrokeAdded: (stroke: PageAnnotationStroke) => this.handleStrokeAdded(stroke),
              fingerDrawing: this.fingerDrawing,
              onPenActive: () => this.shortcuts.claim(),
              onActiveFinisherChange: (finish: (() => void) | null) => this.setActiveInputFinisher(this.currentPageIdx, finish),
              onSourceReady: (ready: boolean) => this.setPageSourceReady(this.currentPageIdx, ready),
              onRestoreSource: () => this.onRestoreSource(),
              onInkContactChange: (active: boolean) => this.setPageInkContact(this.currentPageIdx, active),
              onEraseStarted: () => this.beginErase(this.currentPageIdx),
              onEraseFinished: (commit: boolean) => this.finishErase(commit),
              onEraseAtPoint: (u: number, v: number, width: number, height: number) => this.handleEraseAtPoint(this.currentPageIdx, u, v, width, height)
            })
            .width('100%')
            .transition(
              TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
                .animation({ duration: AnimationTokens.DURATION_PAGE_TRANSITION, curve: AnimationTokens.CURVE_STANDARD })
            )
          }
        }
        .width(this.viewportWidth * this.zoomScale)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 16, bottom: 80 })
        .backgroundColor(this.palette().canvas)
        .transition(
          TransitionEffect.OPACITY
            .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
        )
        }
        .width('100%').height('100%').scrollable(ScrollDirection.Free).scrollBar(BarState.Auto)
        .onScroll((_x: number, y: number) => { if (!this.inkContact && !this.isAnnotateMode) { this.onReadingScroll(y); } })
        .onClick(() => { if (!this.inkContact && !this.isAnnotateMode) { this.onBlankTap(); } })
        .onGestureJudgeBegin((_info: GestureInfo, event: BaseGestureEvent) => this.judgeNavigation(event))
      }
      if (this.annotationError.length > 0) {
        Text(this.annotationError).fontSize(13).fontColor(this.palette().inkPrimary)
          .padding(12).backgroundColor(this.palette().surface).borderRadius(10)
          .margin({ left: 20, right: 20, top: 12 }).align(Alignment.Top).hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea, area) => { this.viewportWidth = Math.max(1, Number(area.width)); })
    .parallelGesture(PinchGesture({ fingers: 2 }).onActionStart(() => { this.zoomStart = this.zoomScale; })
      .onActionUpdate((event: GestureEvent) => {
        if (!this.inkContact && event.sourceTool !== SourceTool.Pen) { this.zoomScale = Math.max(1, Math.min(2.5, this.zoomStart * event.scale)); }
      }))
  }
}
