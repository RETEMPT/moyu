import { copyNote } from '../../../common/utils/NoteSnapshot';
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
import { ReaderTheme } from '../../../common/theme/ReaderTheme';
import { NoteItem } from '../../../common/types/NoteItem';
import { ReaderSaveKind } from '../../../common/types/ReaderSaveKind';
import {
  AnnotationTool,
  NormalizedPoint,
  DocumentAnnotationData,
  PageAnnotationStroke,
  PdfPageModel
} from '../../../common/types/PdfAnnotationTypes';
import { PdfPageCanvas } from './PdfPageCanvas';
import { PdfDocumentService } from '../../../services/document/PdfDocumentService';
import { PdfPageDataSource } from '../../../services/document/PdfPageDataSource';
import { PdfAnnotationPolicy } from '../../../services/document/PdfAnnotationPolicy';
import { InkRenderer } from '../../../services/ink/InkRenderer';
import { CanvasStroke, CanvasPoint } from '../../../common/types/CanvasStroke';
import { CanvasStrokeEraser } from '../../../services/ink/CanvasStrokeEraser';
import { StylusShortcutService } from '../../../services/ink/StylusShortcutService';

interface InkHistoryFrame { pageIndex: number; before: PageAnnotationStroke[]; after: PageAnnotationStroke[]; }
interface CachedAnnotations { raw: string | undefined; pages: Record<number, PageAnnotationStroke[]>; }

const PEN_COLORS: string[] = ['#DC2626', '#2563EB', '#1C1917', '#059669'];
const HIGHLIGHTER_COLORS: string[] = ['#FACC15', '#4ADE80'];
const STROKE_WIDTHS: number[] = [2, 4, 8];
const EMPTY_STROKES: PageAnnotationStroke[] = [];
const ANNOTATION_CACHE_LIMIT: number = 2;

@Component
export struct PdfAnnotatorView {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop @Watch('onCurrentPageChanged') currentPage: number = 1;
  @Prop @Watch('saveForExit') exitSaveToken: number = 0;
  onCommitForExit: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onExitSaveFinished: (ok: boolean, noteId: string, saveToken: number) => void = () => {};
  @Prop @Watch('onReadingModeChanged') isContinuousScroll: boolean = true;
  onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onSaveStateChange: (state: string) => void = () => {};
  onDirtyChange: (dirty: boolean) => void = () => {};
  onBlankTap: () => void = () => {};
  onPageChanged: (page: number) => void = () => {};
  onRestoreSource: () => void = () => {};
  onSourceReady: (ready: boolean) => void = () => {};
  onAnnotationError: (message: string) => void = () => {};
  onFocused: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';

  // 交互与工具栏状态
  @Prop @Watch('finishActiveInput') isAnnotateMode: boolean = false;
  @Prop currentTool: AnnotationTool = 'pen';
  @Prop @Watch('finishActiveInput') selectedColor: string = '#DC2626';
  @Prop @Watch('finishActiveInput') selectedWidth: number = 3;
  @Prop @Watch('finishActiveInput') eraserWidth: number = 20;
  @Prop @Watch('finishActiveInput') eraserMode: string = 'area';
  @Prop @Watch('onUndoTriggered') undoTrigger: number = 0;
  @Prop @Watch('onRedoTriggered') redoTrigger: number = 0;
  @Prop fingerDrawing: boolean = false;
  onToggleEraser: () => void = () => {};
  onShowPenTools: () => void = () => {};
  // Contact flags are read by gesture/tap handlers only. Keeping them out of @State avoids
  // rebuilding the page list on every pen-down and pen-up.
  private inkContact: boolean = false;
  private penContact: boolean = false;
  @Prop @Watch('onClearTriggered') clearTrigger: number = 0;
  @State zoomScale: number = 1.0;
  @State currentPageIdx: number = 0;
  @State viewportWidth: number = 360;
  @State viewportHeight: number = 640;
  @State private pageRatios: Record<number, number> = {};

  // 滚动控制器
  private scroller: Scroller = new Scroller();
  private panScroller: Scroller = new Scroller();

  // 批注数据集（按页）
  @State pageStrokes: Record<number, PageAnnotationStroke[]> = {};
  // Per-page revision: writing on page 1 must not force visible pages 2/3 to replay their ink.
  @State private pageRevisions: Record<number, number> = {};
  // Bumped only when the whole annotation set is replaced (note switch / load).
  @State private strokesEpoch: number = 0;
  // Kept for code paths/tests that only need a monotonic document revision; rendering uses
  // pageRevisions so unrelated pages stay untouched.
  private annotationRevision: number = 0;
  // Parsing a large pageAnnotations JSON is synchronous; reuse the last two notes when tabs switch.
  private annotationCache: Map<string, CachedAnnotations> = new Map();
  private pageDataSource: PdfPageDataSource = new PdfPageDataSource();
  // 撤销历史栈
  private undoStack: InkHistoryFrame[] = [];
  private redoStack: InkHistoryFrame[] = [];
  private eraseBefore: PageAnnotationStroke[] | null = null;
  private erasePage: number = -1;
  private erasePrevious: CanvasPoint | null = null;
  private shortcuts: StylusShortcutService = new StylusShortcutService();
  private zoomStart: number = 1;
  private saveTimer: number = -1;
  private saveRevision: number = 0;
  private savedRevision: number = 0;
  private saveInFlight: Promise<void> | null = null;
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
      if (this.isContinuousScroll) { this.scroller.scrollToIndex(idx, true, ScrollAlign.START); }
    } catch (e) {
      // ignore
    }
  }

  @State pages: PdfPageModel[] = [];

  private onReadingModeChanged(): void {
    this.finishActiveInput(); this.zoomScale = 1;
    this.panScroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private selectVisiblePage(index: number): void {
    if (this.inkContact) { return; }
    const next = Math.max(0, Math.min(this.pages.length - 1, index));
    if (next !== this.currentPageIdx) { this.finishActiveInput(); }
    this.currentPageIdx = next;
    this.onPageChanged(next + 1);
    this.onSourceReady(this.readyPages[next] === true && !this.annotationError);
  }

  private fittedPageWidth(page: PdfPageModel): number {
    const ratio = this.pageRatios[page.pageIndex] || 0.707;
    const height = Math.max(1, this.viewportHeight - 16);
    return Math.max(1, Math.min(this.viewportWidth - 16, height * ratio)) * this.zoomScale;
  }

  private palette(): ColorPalette {
    return ReaderTheme.palette(this.isDarkMode, this.themeStyle);
  }

  aboutToAppear(): void {
    this.shortcuts.start(() => this.isAnnotateMode && !this.annotationError && this.readyPages[this.currentPageIdx] === true && !this.inkContact, this.onToggleEraser, this.onShowPenTools);
    this.loadedNoteId = this.note.id;
    this.editingNote = copyNote(this.note);
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
        this.finishActiveInput(); this.editingNote = copyNote(this.note);
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
    this.editingNote = copyNote(this.note);
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
    const total = this.note.sourceType === 'image' || this.note.type.toLowerCase() === 'image' ? 1 :
      this.note.pageCount && this.note.pageCount > 0 ? this.note.pageCount : 1;
    this.pages = PdfDocumentService.getInstance().generatePageModels(total, this.note.title);
    this.currentPageIdx = Math.max(0, Math.min(total - 1, (this.currentPage || 1) - 1));
    this.pageDataSource.setPages(this.pages);
    this.pageRatios = {};
  }

  /** 从笔记中加载归一化矢量批注 */
  private loadAnnotations(): void {
    this.saveRevision = 0; this.savedRevision = 0; this.onDirtyChange(false);
    this.annotationError = ''; this.onAnnotationError('');
    const raw = this.note.pageAnnotations;
    this.loadedAnnotationRaw = raw;
    try {
      const cache = this.annotationCache;
      const cached = cache !== undefined && cache !== null ? cache.get(this.note.id) : undefined;
      if (cached !== undefined && cached.raw === raw) {
        this.pageStrokes = cached.pages;
      } else {
        const data = PdfAnnotationPolicy.read(raw, this.pages.length);
        this.pageStrokes = data.pages;
        if (cache !== undefined && cache !== null) { this.cacheAnnotations(raw, data.pages); }
      }
      this.pageRevisions = {};
      this.strokesEpoch++;
    } catch (error) {
      if (this.annotationCache !== undefined && this.annotationCache !== null) { this.annotationCache.delete(this.note.id); }
      this.pageStrokes = {};
      this.pageRevisions = {};
      this.strokesEpoch++;
      this.annotationError = error instanceof Error ? error.message : '批注数据无法读取，原记录已保留。';
      this.onAnnotationError(this.annotationError); this.onSourceReady(false); this.onSaveStateChange('批注数据异常');
    }
  }

  private cacheAnnotations(raw: string | undefined, pages: Record<number, PageAnnotationStroke[]>): void {
    const cache = this.annotationCache;
    if (cache === undefined || cache === null) { return; }
    cache.delete(this.note.id);
    cache.set(this.note.id, { raw: raw, pages: pages });
    while (cache.size > ANNOTATION_CACHE_LIMIT) {
      const keys: string[] = [];
      for (const key of cache.keys()) { keys.push(key); }
      if (keys.length === 0) { break; }
      cache.delete(keys[0]);
    }
  }

  private invalidateAnnotationCache(): void {
    if (this.annotationCache !== undefined && this.annotationCache !== null) { this.annotationCache.delete(this.note.id); }
  }

  private bumpPage(pageIndex: number): void {
    const next: Record<number, number> = {};
    if (this.pageRevisions !== undefined && this.pageRevisions !== null) {
      for (const key of Object.keys(this.pageRevisions)) {
        next[Number(key)] = this.pageRevisions[Number(key)];
      }
      next[pageIndex] = (next[pageIndex] || 0) + 1;
      this.pageRevisions = next;
    }
    this.annotationRevision = (this.annotationRevision || 0) + 1;
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
    this.pageStrokes[stroke.pageIndex] = after;
    if (this.invalidateAnnotationCache !== undefined) { this.invalidateAnnotationCache(); }
    if (this.bumpPage !== undefined) { this.bumpPage(stroke.pageIndex); }
    else { this.annotationRevision = (this.annotationRevision || 0) + 1; }
    this.scheduleSave();
  }

  private beginErase(pageIndex: number): void {
    if (this.annotationError) { return; }
    this.erasePrevious = null;
    this.erasePage = pageIndex; this.eraseBefore = (this.pageStrokes[pageIndex] || []).slice();
  }

  private finishErase(commit: boolean): void {
    if (!this.eraseBefore) { return; }
    const before = this.eraseBefore; const page = this.erasePage;
    this.eraseBefore = null; this.erasePage = -1; this.erasePrevious = null;
    const after = this.pageStrokes[page] || [];
    if (!commit) {
      this.pageStrokes[page] = before;
      if (this.invalidateAnnotationCache !== undefined) { this.invalidateAnnotationCache(); }
      if (this.bumpPage !== undefined) { this.bumpPage(page); }
      else { this.annotationRevision = (this.annotationRevision || 0) + 1; }
      return;
    }
    if (before.length !== after.length) { this.remember(page, before, after); this.scheduleSave(); }
  }

  /** Apply the whole eraser swipe once instead of re-filtering and re-rendering per sample. */
  private handleEraseTrail(pageIndex: number, trail: NormalizedPoint[], width: number, height: number): boolean {
    const current = this.pageStrokes[pageIndex];
    if (!current || !this.eraseBefore || trail.length === 0 || width <= 0 || height <= 0) { return false; }
    let remaining = current;
    let previous: CanvasPoint | null = null;
    const threshold = this.eraserWidth * width / 1440;
    for (const point of trail) {
      const mappedPoint: CanvasPoint = { x: point.u * width, y: point.v * height };
      const from: CanvasPoint = previous === null ? mappedPoint : previous;
      remaining = remaining.filter((stroke: PageAnnotationStroke) => {
        const mapped: CanvasStroke = { points: stroke.points.map((p: NormalizedPoint) => { const item: CanvasPoint = { x: p.u * width, y: p.v * height }; return item; }),
          width: stroke.width * width / 1440, color: stroke.color, referenceWidth: 1200, isHighlighter: stroke.isHighlighter, isEraser: stroke.isEraser };
        return !CanvasStrokeEraser.hit(mapped, from, mappedPoint, threshold);
      });
      previous = mappedPoint;
      if (remaining.length === 0) { break; }
    }
    if (remaining.length === current.length) { return false; }
    this.pageStrokes[pageIndex] = remaining;
    if (this.invalidateAnnotationCache !== undefined) { this.invalidateAnnotationCache(); }
    if (this.bumpPage !== undefined) { this.bumpPage(pageIndex); }
    else { this.annotationRevision = (this.annotationRevision || 0) + 1; }
    return true;
  }

  /** Single-sample entry kept for callers that apply erasing point by point. */
  private handleEraseAtPoint(pageIndex: number, u: number, v: number, width: number, height: number): void {
    const current = this.pageStrokes[pageIndex];
    if (!current || !this.eraseBefore) { return; }
    const point: CanvasPoint = { x: u * width, y: v * height };
    const previous = this.erasePrevious === undefined || this.erasePrevious === null ? point : this.erasePrevious;
    this.erasePrevious = point;
    const remaining = current.filter((stroke: PageAnnotationStroke) => {
      const mapped: CanvasStroke = { points: stroke.points.map((p: NormalizedPoint) => { const item: CanvasPoint = { x: p.u * width, y: p.v * height }; return item; }),
        width: stroke.width * width / 1440, color: stroke.color, referenceWidth: 1200, isHighlighter: stroke.isHighlighter, isEraser: stroke.isEraser };
      return !CanvasStrokeEraser.hit(mapped, previous, point, this.eraserWidth * width / 1440);
    });
    if (remaining.length === current.length) { return; }
    this.pageStrokes[pageIndex] = remaining;
    if (this.invalidateAnnotationCache !== undefined) { this.invalidateAnnotationCache(); }
    if (this.bumpPage !== undefined) { this.bumpPage(pageIndex); }
    else { this.annotationRevision = (this.annotationRevision || 0) + 1; }
  }

  private handleUndo(): void {
    this.finishActiveInput();
    const frame = this.undoStack.pop();
    if (!frame) { return; }
    this.pageStrokes[frame.pageIndex] = frame.before.slice();
    if (this.invalidateAnnotationCache !== undefined) { this.invalidateAnnotationCache(); }
    if (this.bumpPage !== undefined) { this.bumpPage(frame.pageIndex); }
    else { this.annotationRevision = (this.annotationRevision || 0) + 1; }
    this.redoStack.push(frame); this.scheduleSave();
  }

  onRedoTriggered(): void {
    this.finishActiveInput();
    const frame = this.redoStack.pop();
    if (!frame) { return; }
    this.pageStrokes[frame.pageIndex] = frame.after.slice();
    if (this.invalidateAnnotationCache !== undefined) { this.invalidateAnnotationCache(); }
    if (this.bumpPage !== undefined) { this.bumpPage(frame.pageIndex); }
    else { this.annotationRevision = (this.annotationRevision || 0) + 1; }
    this.undoStack.push(frame); this.scheduleSave();
  }

  onUndoTriggered(): void { this.handleUndo(); }
  onClearTriggered(): void {
    this.finishActiveInput();
    const page = this.currentPageIdx; const before = this.pageStrokes[page] || [];
    if (!before.length) { return; }
    this.remember(page, before, []); this.pageStrokes[page] = [];
    if (this.invalidateAnnotationCache !== undefined) { this.invalidateAnnotationCache(); }
    if (this.bumpPage !== undefined) { this.bumpPage(page); }
    else { this.annotationRevision = (this.annotationRevision || 0) + 1; }
    this.scheduleSave();
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
    let pending: Promise<void> | null = null;
    try {
      pending = this.onSaved(updatedNote, updatedNote.contentDetail, 'pdf');
      this.saveInFlight = pending;
      await pending;
      if (revision === this.saveRevision && updatedNote.id === this.loadedNoteId) {
        this.savedRevision = revision;
        if (this.cacheAnnotations !== undefined) { this.cacheAnnotations(updatedNote.pageAnnotations, this.pageStrokes); }
        this.onDirtyChange(false); this.onSaveStateChange('已保存');
      }
    }
    catch { if (revision === this.saveRevision && updatedNote.id === this.loadedNoteId) { this.onSaveStateChange('保存失败'); } }
    finally { if (this.saveInFlight === pending) { this.saveInFlight = null; } }
  }

  private async saveForExit(): Promise<void> {
    const requestToken = this.exitSaveToken;
    const noteId = this.loadedNoteId;
    if (this.annotationError) {
      this.onSaveStateChange('批注数据异常');
      // A read-only invalid record can leave alongside a saved scratchpad without rewriting its original bytes.
      const untouched = this.saveRevision === 0 && this.loadedAnnotationRaw === this.note.pageAnnotations;
      this.onExitSaveFinished(untouched, this.loadedNoteId, requestToken); return;
    }
    this.finishActiveInput();
    if (this.saveTimer !== -1) { clearTimeout(this.saveTimer); this.saveTimer = -1; }
    const pending = this.saveInFlight;
    if (pending) { try { await pending; } catch { /* Retry the current revision below. */ } }
    if (noteId !== this.loadedNoteId || requestToken !== this.exitSaveToken) {
      this.onExitSaveFinished(false, noteId, requestToken); return;
    }
    if (this.saveRevision === this.savedRevision) {
      this.onDirtyChange(false);
      this.onExitSaveFinished(true, noteId, requestToken); return;
    }
    const revision = this.saveRevision;
    const snapshot = this.annotationSnapshot();
    try {
      await this.onCommitForExit(snapshot, snapshot.contentDetail, 'pdf');
      if (snapshot.id !== this.loadedNoteId || revision !== this.saveRevision) { this.onExitSaveFinished(false, snapshot.id, requestToken); return; }
      this.savedRevision = revision;
      if (this.cacheAnnotations !== undefined) { this.cacheAnnotations(snapshot.pageAnnotations, this.pageStrokes); }
      this.onDirtyChange(false); this.onSaveStateChange('已保存');
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
    const updatedNote = copyNote(this.editingNote || this.note);
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
    if (!active) { this.penContact = false; }
    // Contact alone does not dirty a document; scheduleSave() (triggered by an actual stroke)
    // owns that transition and avoids rebuilding this 1300-line workspace on every pen-down.
    this.inkContact = active;
  }

  private judgeNavigation(event: BaseGestureEvent): GestureJudgeResult {
    return event.sourceTool === SourceTool.Pen || this.penContact || (this.inkContact && event.fingerList.length < 2) ||
      (this.isAnnotateMode && this.fingerDrawing && this.currentTool !== 'pan' && event.fingerList.length === 1)
      ? GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE;
  }

  @Builder
  annotationPage(pm: PdfPageModel) {
    PdfPageCanvas({
      pageModel: pm,
      sourceUri: this.note.sourceUri || '',
      sourceType: this.note.sourceType === 'image' || this.note.type.toLowerCase() === 'image' ? 'image' : 'pdf',
      useRealPdf: true,
      readStrokes: () => this.pageStrokes[pm.pageIndex] || EMPTY_STROKES,
      revision: this.pageRevisions[pm.pageIndex] || 0,
      strokesEpoch: this.strokesEpoch,
      isAnnotateMode: this.isAnnotateMode && !this.annotationError,
      tool: this.currentTool,
      eraserMode: this.eraserMode,
      eraserWidth: this.eraserWidth,
      selectedColor: this.selectedColor,
      selectedWidth: this.selectedWidth,
      isDarkMode: this.isDarkMode,
      onStrokeAdded: (stroke: PageAnnotationStroke) => this.handleStrokeAdded(stroke),
      fingerDrawing: this.fingerDrawing,
      onPenActive: (pen: boolean) => { this.penContact = pen; this.shortcuts.claim(); this.onFocused(); },
      onActiveFinisherChange: (finish: (() => void) | null) => this.setActiveInputFinisher(pm.pageIndex, finish),
      onSourceReady: (ready: boolean) => this.setPageSourceReady(pm.pageIndex, ready),
      onPageAspectRatio: (ratio: number) => { if (Number.isFinite(ratio) && ratio > 0) { this.pageRatios[pm.pageIndex] = ratio; } },
      onRestoreSource: () => this.onRestoreSource(),
      onInkContactChange: (active: boolean) => this.setPageInkContact(pm.pageIndex, active),
      onEraseStarted: () => this.beginErase(pm.pageIndex),
      onEraseFinished: (commit: boolean) => this.finishErase(commit),
      onEraseTrail: (trail: NormalizedPoint[], width: number, height: number) => this.handleEraseTrail(pm.pageIndex, trail, width, height)
    })
    .width(this.isContinuousScroll ? '100%' : this.fittedPageWidth(pm))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isContinuousScroll) {
        // 连续列表按实际页面高度定位，位图由可见页管理。
        Scroll(this.panScroller) {
        List({ space: 12, scroller: this.scroller, initialIndex: this.currentPageIdx }) {
          LazyForEach(this.pageDataSource, (pm: PdfPageModel) => {
            ListItem() {
              this.annotationPage(pm)
            }
          }, (pm: PdfPageModel) => `page_${pm.pageIndex}`)
        }
        .width(this.viewportWidth * this.zoomScale)
        .padding({ left: 8, right: 8, top: 8, bottom: 56 })
        .height('100%')
        .cachedCount(1)
        .scrollBar(BarState.Auto)
        .onScrollIndex((start: number) => {
          this.selectVisiblePage(start);
        })
        .onGestureJudgeBegin((_info: GestureInfo, event: BaseGestureEvent) => this.judgeNavigation(event))
        .backgroundColor(this.palette().canvas)
        .onClick(() => { if (!this.inkContact && !this.isAnnotateMode) { this.onBlankTap(); } })
        .transition(
          TransitionEffect.OPACITY
            .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
        )
        }
        .width('100%').height('100%').scrollable(this.zoomScale > 1 ? ScrollDirection.Horizontal : ScrollDirection.None).scrollBar(BarState.Auto)
        .onGestureJudgeBegin((_info: GestureInfo, event: BaseGestureEvent) => this.judgeNavigation(event))
      } else {
        // 整页按可用宽高缩放；未放大时上下滑动切页，放大后在页内平移。
        Swiper() {
          LazyForEach(this.pageDataSource, (pm: PdfPageModel) => {
            Scroll() {
              Column() { this.annotationPage(pm) }
                .width(Math.max(this.viewportWidth, this.fittedPageWidth(pm) + 16))
                .constraintSize({ minHeight: this.viewportHeight })
                .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).padding(8)
            }.width('100%').height('100%')
              .scrollable(this.zoomScale > 1 ? ScrollDirection.Free : ScrollDirection.None).scrollBar(BarState.Off)
              .onGestureJudgeBegin((_info: GestureInfo, event: BaseGestureEvent) => this.judgeNavigation(event))
          }, (pm: PdfPageModel) => `page_${pm.pageIndex}`)
        }.width('100%').height('100%').vertical(true).loop(false).indicator(false).cachedCount(1)
          .index(this.currentPageIdx)
          .disableSwipe(this.zoomScale > 1 || (this.isAnnotateMode && this.fingerDrawing && this.currentTool !== 'pan'))
          .onChange((index: number) => this.selectVisiblePage(index))
          .onGestureJudgeBegin((_info: GestureInfo, event: BaseGestureEvent) => this.judgeNavigation(event))
          .onClick(() => { if (!this.inkContact && !this.isAnnotateMode) { this.onBlankTap(); } })
          .backgroundColor(this.palette().canvas)
      }
      if (this.annotationError.length > 0) {
        Text(this.annotationError).fontSize(13).fontColor(this.palette().inkPrimary)
          .padding(12).backgroundColor(this.palette().surface).borderRadius(5)
          .margin({ left: 20, right: 20, top: 12 }).align(Alignment.Top).hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea, area) => {
      const width = Number(area.width); const height = Number(area.height);
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return; }
      if (Math.abs(width - this.viewportWidth) < 0.5 && Math.abs(height - this.viewportHeight) < 0.5) { return; }
      this.viewportWidth = width; this.viewportHeight = height;
    })
    .parallelGesture(PinchGesture({ fingers: 2 }).onActionStart(() => { this.zoomStart = this.zoomScale; })
      .onActionUpdate((event: GestureEvent) => {
        if (!this.inkContact && event.sourceTool !== SourceTool.Pen) { this.zoomScale = Math.max(1, Math.min(2.5, this.zoomStart * event.scale)); }
      }))
  }
}
