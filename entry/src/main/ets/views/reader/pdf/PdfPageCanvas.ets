/**
 * 原生 PDF / 试卷单页排版与矢量墨水批注层 (PdfPageCanvas)
 *
 * 核心设计：
 *   1. 工业级 A4 纸张排版容器（比例 1 : 1.414），渲染试卷页眉、大题题干、选项槽、答题区与页脚
 *   2. 归一化矢量墨水批注层 (Normalized Vector Annotation Layer)：
 *      - 批注坐标以 (u, v) ∈ [0, 1] 存储，按当前物理像素实时缩放映射，保证缩放平移零漂移
 *      - 二次贝塞尔曲线（Quadratic Bézier）中点平滑插值，彻底消除锯齿与折线感
 *      - 荧光笔半透明叠加 (globalAlpha = 0.35)，保证清晰透出底层印刷字
 *   3. 触控事件分流与防误触：仅在非 pan 漫游模式下捕获落笔
 */
import { TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { CanvasPoint } from '../../../common/types/CanvasStroke';
import { InkInputService } from '../../../services/ink/InkInputService';
import { InkRenderer, InkStyle, InkContext } from '../../../services/ink/InkRenderer';
import { InkShapePolicy } from '../../../services/ink/InkShapePolicy';
import { PdfPageBackground } from './PdfPageBackground';
import { InkCanvasSurface } from '../InkCanvasSurface';
import {
  AnnotationTool,
  NormalizedPoint,
  PageAnnotationStroke,
  PdfPageModel,
  PdfPageSection
} from '../../../common/types/PdfAnnotationTypes';

@Component
export struct PdfPageCanvas {
  @Prop @Watch('onSourceChanged') pageModel: PdfPageModel;
  @Prop @Watch('onSourceChanged') sourceUri: string = '';
  @Prop @Watch('onSourceChanged') sourceType: string = 'pdf';
  @Prop useRealPdf: boolean = false;
  @State private pageAspectRatio: number = 0.707;
  // Strokes are read through a callback instead of an array @Prop: a parent rebuild must not
  // copy/reassign the array and replay every page's ink. Only the page's own revision changes.
  private strokes: PageAnnotationStroke[] = [];
  readStrokes: () => PageAnnotationStroke[] = () => this.strokes;
  @Prop @Watch('onStrokesChanged') revision: number = 0;
  @Prop @Watch('onStrokesChanged') strokesEpoch: number = 0;
  @Prop @Watch('finishInputForModeChange') isAnnotateMode: boolean = false;
  @Prop @Watch('finishInputForModeChange') tool: AnnotationTool = 'pen';
  @Prop @Watch('finishInputForModeChange') eraserMode: string = 'area';
  @Prop @Watch('finishInputForModeChange') eraserWidth: number = 20;
  @Prop @Watch('finishInputForModeChange') fingerDrawing: boolean = false;
  @Prop @Watch('finishInputForModeChange') selectedColor: string = '#DC2626';
  @Prop @Watch('finishInputForModeChange') selectedWidth: number = 3;
  @Prop isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';

  onStrokeAdded: (stroke: PageAnnotationStroke) => void = () => {};
  onEraseTrail: (trail: NormalizedPoint[], width: number, height: number) => boolean = () => false;
  onEraseStarted: () => void = () => {};
  onEraseFinished: (commit: boolean) => void = () => {};
  onInkContactChange: (active: boolean) => void = () => {};
  onPenActive: (pen: boolean) => void = () => {};
  onSourceReady: (ready: boolean) => void = () => {};
  onPageAspectRatio: (ratio: number) => void = () => {};
  onRestoreSource: () => void = () => {};
  onActiveFinisherChange: (finish: (() => void) | null) => void = () => {};
  @State private sourceReady: boolean = false;
  private loadedSourceUri: string = '';
  private loadedSourceType: string = '';
  private loadedPageIndex: number = -1;
  private input: InkInputService = new InkInputService();
  private erasing: boolean = false;
  private pendingModeCommit: boolean = false;

  // 画布与渲染上下文
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private liveContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  private pageWidth: number = 0;
  private pageHeight: number = 0;
  private currentStroke: PageAnnotationStroke | null = null;
  private shapeAnchor: CanvasPoint | null = null;
  private renderedStrokes: PageAnnotationStroke[] = [];
  private renderedEpoch: number = -1;
  private redrawTimer: number = -1;
  private eraseTrail: NormalizedPoint[] = [];
  private erasePreview: CanvasPoint | null = null;

  onStrokesChanged(): void {
    const read = this.readStrokes;
    const next = read !== undefined && read !== null ? read() : this.strokes;
    if (this.pageWidth <= 0 || this.pageHeight <= 0 || this.renderedEpoch !== this.strokesEpoch) {
      this.redrawAll();
      return;
    }
    if (this.isPrefix(this.renderedStrokes, next)) {
      const added = next.slice(this.renderedStrokes.length);
      if (added.length === 0) { return; }
      // A completed stroke is append-only: paint it instead of replaying the whole page and
      // transferring a fresh full-page ImageBitmap on every pen lift.
      for (const stroke of added) { this.renderStroke(stroke, this.context); }
      this.renderedStrokes = next;
      return;
    }
    this.redrawAll();
  }

  private isPrefix(previous: PageAnnotationStroke[], next: PageAnnotationStroke[]): boolean {
    if (previous.length > next.length) { return false; }
    for (let index = 0; index < previous.length; index++) {
      if (previous[index] !== next[index]) { return false; }
    }
    return true;
  }

  /** 重绘画布上的全部矢量笔画 */
  private redrawAll(): void {
    if (!this.context || this.pageWidth <= 0 || this.pageHeight <= 0) { return; }
    const read = this.readStrokes;
    const strokes = read !== undefined && read !== null ? read() : this.strokes;
    // Replay directly on the visible layer. The previous offscreen round-trip allocated a
    // full-page OffscreenCanvas and transferred a second full-page ImageBitmap for every
    // redraw; on a software-rendered emulator that alone blocked the UI for seconds.
    this.context.clearRect(0, 0, this.pageWidth, this.pageHeight);
    for (const stroke of strokes) { this.renderStroke(stroke, this.context); }
    if (this.currentStroke && this.currentStroke.isEraser) { this.renderStroke(this.currentStroke, this.context); }
    this.renderedStrokes = strokes;
    this.renderedEpoch = this.strokesEpoch;
  }

  /** Coalesce layout/state bursts (split-resize, note load) into one ink replay. */
  private scheduleRedraw(): void {
    if (this.redrawTimer !== -1) { return; }
    this.redrawTimer = setTimeout(() => {
      this.redrawTimer = -1;
      this.redrawAll();
    }, 0);
  }

  private mapped(stroke: PageAnnotationStroke): CanvasPoint[] {
    return stroke.points.map((p: NormalizedPoint) => {
      const point: CanvasPoint = { x: p.u * this.pageWidth, y: p.v * this.pageHeight, pressure: p.pressure };
      return point;
    });
  }

  private style(stroke: PageAnnotationStroke): InkStyle {
    return { color: stroke.color, width: stroke.width * this.pageWidth / 720,
      highlighter: stroke.isHighlighter, eraser: stroke.isEraser };
  }

  private renderStroke(stroke: PageAnnotationStroke, context: InkContext = this.context): void {
    InkRenderer.stroke(context, this.mapped(stroke), this.style(stroke));
  }

  private resetInput(): void {
    this.finishInput(false);
  }

  private finishInputForModeChange(): void {
    // A tool/width watcher may fire while the nib is still down. Commit only after Up,
    // otherwise the rest of the erase path is dropped and the user sees a dead eraser.
    if (this.input.isActive() || this.erasing) { this.pendingModeCommit = true; return; }
    this.finishInput(true);
  }

  private finishInput(commit: boolean): void {
    this.input.reset();
    this.pendingModeCommit = false;
    const stroke = this.currentStroke; this.currentStroke = null;
    this.shapeAnchor = null;
    const wasErasing = this.erasing;
    this.erasing = false;
    if (wasErasing) {
      const trail = this.eraseTrail !== undefined && this.eraseTrail !== null ? this.eraseTrail : [];
      this.eraseTrail = []; this.erasePreview = null;
      let changed = false;
      if (commit && trail.length > 0 && this.onEraseTrail !== undefined) {
        changed = this.onEraseTrail(trail, this.pageWidth, this.pageHeight);
      }
      // The local destination-out preview may not exactly match whole-stroke removal, so paint
      // the authoritative data once after the parent publishes it.
      if (!changed) {
        if (this.scheduleRedraw !== undefined) { this.scheduleRedraw(); }
        else if (this.redrawAll !== undefined) { this.redrawAll(); }
      }
      this.onEraseFinished(commit);
    }
    if (commit && stroke && stroke.points.length > 0) { this.onStrokeAdded(stroke); }
    this.liveContext.clearRect(0, 0, this.pageWidth, this.pageHeight);
    this.onActiveFinisherChange(null);
    this.onInkContactChange(false);
    // Keep the completed area preview until the parent publishes its new stroke array.
    // Replaying old @Prop data here briefly resurrects the erased ink.
    if (stroke && stroke.isEraser && !commit) {
      if (this.scheduleRedraw !== undefined) { this.scheduleRedraw(); }
      else if (this.redrawAll !== undefined) { this.redrawAll(); }
    }
  }

  private onSourceChanged(): void {
    // @Prop pageModel is copied again when tools change; only a different source/page invalidates its bitmap.
    if (this.loadedSourceUri === this.sourceUri && this.loadedSourceType === this.sourceType && this.loadedPageIndex === this.pageModel.pageIndex) { return; }
    this.loadedSourceType = this.sourceType;
    this.loadedSourceUri = this.sourceUri; this.loadedPageIndex = this.pageModel.pageIndex;
    this.resetInput(); this.sourceReady = false; this.onSourceReady(false);
    this.pageAspectRatio = 0.707;
  }

  private setSourceReady(ready: boolean): void {
    this.loadedSourceType = this.sourceType;
    this.loadedSourceUri = this.sourceUri; this.loadedPageIndex = this.pageModel.pageIndex;
    if (!ready) { this.resetInput(); }
    this.sourceReady = ready; this.onSourceReady(ready);
  }

  aboutToDisappear(): void {
    this.resetInput();
    if (this.redrawTimer !== -1) { clearTimeout(this.redrawTimer); this.redrawTimer = -1; }
  }

  private handleTouch(event: TouchEvent): void {
    if (!this.sourceReady || !this.isAnnotateMode || this.tool === 'pan' || this.pageWidth <= 0 || this.pageHeight <= 0) { return; }
    if (event.type === TouchType.Down && event.sourceTool === SourceTool.Pen && this.input.isActive() && !this.input.isPenActive()) {
      this.finishInput(false);
    }
    const batch = this.input.read(event, this.fingerDrawing);
    if (batch.phase === 'ignore') { return; }
    event.stopPropagation();
    if (batch.phase === 'cancel') { this.resetInput(); return; }
    if (batch.phase === 'begin') {
      this.liveContext.clearRect(0, 0, this.pageWidth, this.pageHeight);
      this.onActiveFinisherChange(() => this.finishInput(true));
      this.onPenActive(batch.pen);
      this.onInkContactChange(true);
      if (this.tool === 'eraser' && this.eraserMode !== 'area') {
        this.erasing = true;
        this.eraseTrail = []; this.erasePreview = null;
        this.onEraseStarted();
      } else {
        this.currentStroke = { id: 'stroke_' + Date.now() + '_' + Math.floor(Math.random() * 1000000),
          pageIndex: this.pageModel.pageIndex, color: this.selectedColor, width: this.tool === 'eraser' ? this.eraserWidth : this.selectedWidth,
          isHighlighter: this.tool === 'highlighter', isEraser: this.tool === 'eraser', points: [] };
      }
    }
    const stroke = this.currentStroke;
    if (stroke && InkShapePolicy.isShape(this.tool)) {
      for (const sample of batch.samples) {
        const point: CanvasPoint = { x: Math.max(0, Math.min(this.pageWidth, sample.x)), y: Math.max(0, Math.min(this.pageHeight, sample.y)) };
        if (!this.shapeAnchor) { this.shapeAnchor = point; }
        stroke.points = InkShapePolicy.points(this.tool, this.shapeAnchor, point).map((p: CanvasPoint): NormalizedPoint => {
          return { u: Math.max(0, Math.min(1, p.x / this.pageWidth)), v: Math.max(0, Math.min(1, p.y / this.pageHeight)), pressure: 0.5 };
        });
      }
      this.liveContext.clearRect(0, 0, this.pageWidth, this.pageHeight); this.renderStroke(stroke, this.liveContext);
      if (batch.phase === 'end') { this.finishInput(true); }
      return;
    }
    for (const sample of batch.samples) {
      const u = Math.max(0, Math.min(1, sample.x / this.pageWidth));
      const v = Math.max(0, Math.min(1, sample.y / this.pageHeight));
      if (this.erasing) {
        // Keep the whole trail on the UI thread and publish it once on Up. The previous
        // per-sample @State bump re-rendered every visible page dozens of times per swipe.
        this.eraseTrail.push({ u, v, pressure: sample.pressure });
        this.previewErase(u * this.pageWidth, v * this.pageHeight);
        continue;
      }
      if (!stroke) { continue; }
      const last = stroke.points[stroke.points.length - 1];
      if (last && Math.hypot((last.u - u) * this.pageWidth, (last.v - v) * this.pageHeight) < 0.35 && Math.abs((last.pressure || 0) - sample.pressure) < 0.04) { continue; }
      stroke.points.push({ u, v, pressure: sample.pressure });
      // Map only the last three points; a move does not replay the page or its full active stroke.
      const tail = stroke.points.slice(-3).map((p: NormalizedPoint) => {
        const point: CanvasPoint = { x: p.u * this.pageWidth, y: p.v * this.pageHeight, pressure: p.pressure };
        return point;
      });
      InkRenderer.segment(stroke.isEraser ? this.context : this.liveContext, tail, tail.length - 1, this.style(stroke));
    }
    if (batch.phase === 'end') {
      this.finishInput(true);
    }
  }

  /** Immediate visual feedback for the line/pixel eraser while the data change is batched. */
  private previewErase(x: number, y: number): void {
    const width = Math.max(2, this.eraserWidth * this.pageWidth / 720);
    const context = this.context;
    context.save();
    context.globalCompositeOperation = 'destination-out';
    context.lineWidth = width;
    context.lineCap = 'round';
    context.lineJoin = 'round';
    if (this.erasePreview === null) {
      context.beginPath(); context.arc(x, y, width / 2, 0, Math.PI * 2); context.fill();
    } else {
      context.beginPath(); context.moveTo(this.erasePreview.x, this.erasePreview.y); context.lineTo(x, y); context.stroke();
    }
    context.restore();
    this.erasePreview = { x: x, y: y };
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PdfPageBackground({ sourceUri: this.sourceUri, sourceType: this.sourceType, pageIndex: this.pageModel.pageIndex,
        onAspectRatio: (ratio: number) => { this.pageAspectRatio = ratio; this.onPageAspectRatio(ratio); },
        onSourceReady: (ready: boolean) => this.setSourceReady(ready),
        onRestoreSource: () => this.onRestoreSource() })
    InkCanvasSurface({ drawingContext: this.context, liveContext: this.liveContext,
      contentReady: this.sourceReady, interactive: this.sourceReady && this.isAnnotateMode && this.tool !== 'pan',
      liveOpacity: this.tool === 'highlighter' ? 0.35 : 1,
      onPaintReady: () => this.scheduleRedraw(), onInput: (event: TouchEvent) => this.handleTouch(event),
      onSizeChanged: (width: number, height: number) => {
        if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) { return; }
        if (Math.abs(width - this.pageWidth) < 0.5 && Math.abs(height - this.pageHeight) < 0.5) { return; }
        if (this.input.isActive()) { this.pendingModeCommit = true; }
        else { this.resetInput(); }
        this.pageWidth = width; this.pageHeight = height;
        this.renderedStrokes = []; this.renderedEpoch = -1;
        this.scheduleRedraw();
      }
    })
    }.width('100%')
    .aspectRatio(this.pageAspectRatio)
    .borderRadius(8)
    .shadow({
      radius: 16,
      color: this.isDarkMode ? 'rgba(0,0,0,0.45)' : 'rgba(0,0,0,0.08)',
      offsetY: 6
    })
    .border({ width: 1, color: this.isDarkMode ? '#2C2C2E' : '#E5E7EB' })
  }
}
