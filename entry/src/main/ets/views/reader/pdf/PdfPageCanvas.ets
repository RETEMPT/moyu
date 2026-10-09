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
import { InkRenderer, InkStyle } from '../../../services/ink/InkRenderer';
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
  @Prop pageModel: PdfPageModel;
  @Prop sourceUri: string = '';
  @Prop useRealPdf: boolean = false;
  @State private pageAspectRatio: number = 0.707;
  @Prop @Watch('onStrokesChanged') strokes: PageAnnotationStroke[] = [];
  @Prop @Watch('resetInput') isAnnotateMode: boolean = false;
  @Prop @Watch('resetInput') tool: AnnotationTool = 'pen';
  @Prop fingerDrawing: boolean = false;
  @Prop selectedColor: string = '#DC2626';
  @Prop selectedWidth: number = 3;
  @Prop isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';

  onStrokeAdded: (stroke: PageAnnotationStroke) => void = () => {};
  onEraseAtPoint: (u: number, v: number, width: number, height: number) => void = () => {};
  onEraseStarted: () => void = () => {};
  onEraseFinished: (commit: boolean) => void = () => {};
  onInkContactChange: (active: boolean) => void = () => {};
  onPenActive: () => void = () => {};
  private input: InkInputService = new InkInputService();
  private erasing: boolean = false;

  // 画布与渲染上下文
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private liveContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @State pageWidth: number = 0;
  @State pageHeight: number = 0;
  private currentStroke: PageAnnotationStroke | null = null;

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
    this.context.clearRect(0, 0, this.pageWidth, this.pageHeight);

    // 绘制该页全部历史笔画
    for (let i = 0; i < this.strokes.length; i++) {
      this.renderStroke(this.strokes[i]);
    }

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

  private renderStroke(stroke: PageAnnotationStroke): void {
    InkRenderer.stroke(this.context, this.mapped(stroke), this.style(stroke));
  }

  private resetInput(): void {
    this.input.reset(); this.currentStroke = null;
    this.liveContext.clearRect(0, 0, this.pageWidth, this.pageHeight);
    if (this.erasing) { this.onEraseFinished(false); this.erasing = false; }
    this.onInkContactChange(false);
  }

  aboutToDisappear(): void { this.resetInput(); }

  private handleTouch(event: TouchEvent): void {
    if (!this.isAnnotateMode || this.tool === 'pan' || this.pageWidth <= 0 || this.pageHeight <= 0) { return; }
    const batch = this.input.read(event, this.fingerDrawing);
    if (batch.phase === 'ignore') { return; }
    event.stopPropagation();
    if (batch.phase === 'cancel') { this.resetInput(); return; }
    if (batch.phase === 'begin') {
      this.liveContext.clearRect(0, 0, this.pageWidth, this.pageHeight);
      this.onPenActive(); this.onInkContactChange(true);
      if (this.tool === 'eraser') { this.erasing = true; this.onEraseStarted(); }
      else {
        this.currentStroke = { id: 'stroke_' + Date.now() + '_' + Math.floor(Math.random() * 1000000),
          pageIndex: this.pageModel.pageIndex, color: this.selectedColor, width: this.selectedWidth,
          isHighlighter: this.tool === 'highlighter', isEraser: false, points: [] };
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
      InkRenderer.segment(this.liveContext, tail, tail.length - 1, this.style(stroke));
    }
    if (batch.phase === 'end') {
      if (this.erasing) { this.erasing = false; this.onEraseFinished(true); }
      if (stroke && stroke.points.length) {
        this.currentStroke = null; this.onStrokeAdded(stroke);
      }
      this.liveContext.clearRect(0, 0, this.pageWidth, this.pageHeight);
      this.onInkContactChange(false);
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PdfPageBackground({ sourceUri: this.sourceUri, pageIndex: this.pageModel.pageIndex,
        onAspectRatio: (ratio: number) => { this.pageAspectRatio = ratio; } })

      // ---- 第二层：归一化矢量批注 Canvas 图层 ----
      Canvas(this.context)
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      Canvas(this.liveContext).width('100%').height('100%')
        .opacity(this.tool === 'highlighter' ? 0.35 : 1)
        .hitTestBehavior(!this.isAnnotateMode || this.tool === 'pan' ? HitTestMode.None : HitTestMode.Transparent)
        .onReady(() => this.redrawAll())
        .onTouch((event: TouchEvent) => this.handleTouch(event))
    }
    .width('100%')
    .aspectRatio(this.pageAspectRatio)
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
