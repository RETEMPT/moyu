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
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { CanvasPoint } from '../../../common/types/CanvasStroke';
import { InkInputService } from '../../../services/ink/InkInputService';
import { InkRenderer, InkStyle, InkContext } from '../../../services/ink/InkRenderer';
import { InkFrameComposer } from '../../../services/ink/InkFrameComposer';
import { PdfPageBackground } from './PdfPageBackground';
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
  @Prop useRealPdf: boolean = false;
  @State private pageAspectRatio: number = 0.707;
  @Prop @Watch('onStrokesChanged') strokes: PageAnnotationStroke[] = [];
  @Prop @Watch('finishInputForModeChange') isAnnotateMode: boolean = false;
  @Prop @Watch('finishInputForModeChange') tool: AnnotationTool = 'pen';
  @Prop @Watch('finishInputForModeChange') eraserMode: string = 'stroke';
  @Prop @Watch('finishInputForModeChange') eraserWidth: number = 20;
  @Prop @Watch('finishInputForModeChange') fingerDrawing: boolean = false;
  @Prop @Watch('finishInputForModeChange') selectedColor: string = '#DC2626';
  @Prop @Watch('finishInputForModeChange') selectedWidth: number = 3;
  @Prop isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';

  onStrokeAdded: (stroke: PageAnnotationStroke) => void = () => {};
  onEraseAtPoint: (u: number, v: number, width: number, height: number) => void = () => {};
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
  private loadedPageIndex: number = -1;
  private input: InkInputService = new InkInputService();
  private erasing: boolean = false;

  // 画布与渲染上下文
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private liveContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @State pageWidth: number = 0;
  @State pageHeight: number = 0;
  private currentStroke: PageAnnotationStroke | null = null;
  private inkFrame: InkFrameComposer = new InkFrameComposer();

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  onStrokesChanged(): void {
    this.redrawAll();
  }

  /** 重绘画布上的全部矢量笔画 */
  private redrawAll(): void {
    if (!this.context || this.pageWidth <= 0 || this.pageHeight <= 0) {
      return;
    }
    this.inkFrame.render(this.context, this.pageWidth, this.pageHeight, (context: OffscreenCanvasRenderingContext2D) => {
      for (const stroke of this.strokes) { this.renderStroke(stroke, context); }
      if (this.currentStroke && this.currentStroke.isEraser) { this.renderStroke(this.currentStroke, context); }
    });
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
    this.finishInput(true);
  }

  private finishInput(commit: boolean): void {
    this.input.reset();
    const stroke = this.currentStroke; this.currentStroke = null;
    if (this.erasing) { this.erasing = false; this.onEraseFinished(commit); }
    if (commit && stroke && stroke.points.length > 0) { this.onStrokeAdded(stroke); }
    this.liveContext.clearRect(0, 0, this.pageWidth, this.pageHeight);
    this.onActiveFinisherChange(null);
    this.onInkContactChange(false);
    // Keep the completed area preview until the parent publishes its new stroke array.
    // Replaying old @Prop data here briefly resurrects the erased ink.
    if (stroke && stroke.isEraser && !commit) { this.redrawAll(); }
  }

  private onSourceChanged(): void {
    // @Prop pageModel is copied again when tools change; only a different source/page invalidates its bitmap.
    if (this.loadedSourceUri === this.sourceUri && this.loadedPageIndex === this.pageModel.pageIndex) { return; }
    this.loadedSourceUri = this.sourceUri; this.loadedPageIndex = this.pageModel.pageIndex;
    this.resetInput(); this.sourceReady = false; this.onSourceReady(false);
    this.pageAspectRatio = 0.707;
  }

  private setSourceReady(ready: boolean): void {
    this.loadedSourceUri = this.sourceUri; this.loadedPageIndex = this.pageModel.pageIndex;
    if (!ready) { this.resetInput(); }
    this.sourceReady = ready; this.onSourceReady(ready);
  }

  aboutToDisappear(): void { this.resetInput(); this.inkFrame.release(); }

  private handleTouch(event: TouchEvent): void {
    if (!this.sourceReady || !this.isAnnotateMode || this.tool === 'pan' || this.pageWidth <= 0 || this.pageHeight <= 0) { return; }
    if (event.type === TouchType.Down && event.sourceTool === SourceTool.Pen && this.input.isActive() && !this.input.isPenActive()) {
      this.finishInput(true);
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
      if (this.tool === 'eraser' && this.eraserMode !== 'area') { this.erasing = true; this.onEraseStarted(); }
      else {
        this.currentStroke = { id: 'stroke_' + Date.now() + '_' + Math.floor(Math.random() * 1000000),
          pageIndex: this.pageModel.pageIndex, color: this.selectedColor, width: this.tool === 'eraser' ? this.eraserWidth : this.selectedWidth,
          isHighlighter: this.tool === 'highlighter', isEraser: this.tool === 'eraser', points: [] };
      }
    }
    const stroke = this.currentStroke;
    for (const sample of batch.samples) {
      const u = Math.max(0, Math.min(1, sample.x / this.pageWidth));
      const v = Math.max(0, Math.min(1, sample.y / this.pageHeight));
      if (this.erasing) { this.onEraseAtPoint(u, v, this.pageWidth, this.pageHeight); continue; }
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

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PdfPageBackground({ sourceUri: this.sourceUri, pageIndex: this.pageModel.pageIndex,
        onAspectRatio: (ratio: number) => { this.pageAspectRatio = ratio; this.onPageAspectRatio(ratio); },
        onSourceReady: (ready: boolean) => this.setSourceReady(ready),
        onRestoreSource: () => this.onRestoreSource() })

      // ---- 第二层：归一化矢量批注 Canvas 图层 ----
      Canvas(this.context)
        .width('100%')
        .height('100%')
        .opacity(this.sourceReady ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)
      Canvas(this.liveContext).width('100%').height('100%')
        .opacity(this.sourceReady ? (this.tool === 'highlighter' ? 0.35 : 1) : 0)
        .hitTestBehavior(!this.sourceReady || !this.isAnnotateMode || this.tool === 'pan' ? HitTestMode.None : HitTestMode.Transparent)
        .onReady(() => this.redrawAll())
    }
    .width('100%')
    .onTouch((event: TouchEvent) => this.handleTouch(event))
    .aspectRatio(this.pageAspectRatio)
    .onVisibleAreaChange([0], (visible: boolean) => { if (!visible) { this.inkFrame.release(); } })
    .borderRadius(8)
    .shadow({
      radius: 16,
      color: this.isDarkMode ? 'rgba(0,0,0,0.45)' : 'rgba(0,0,0,0.08)',
      offsetY: 6
    })
    .border({ width: 1, color: this.isDarkMode ? '#2C2C2E' : '#E5E7EB' })
    .onAreaChange((oldArea, newArea) => {
      if (this.input.isActive()) { this.resetInput(); }
      this.pageWidth = Number(newArea.width);
      this.pageHeight = Number(newArea.height);
      this.redrawAll();
    })
  }
}
