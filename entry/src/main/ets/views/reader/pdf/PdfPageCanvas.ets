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
  @Prop @Watch('onStrokesChanged') strokes: PageAnnotationStroke[] = [];
  @Prop isAnnotateMode: boolean = false;
  @Prop tool: AnnotationTool = 'pen';
  @Prop selectedColor: string = '#DC2626';
  @Prop selectedWidth: number = 3;
  @Prop isDarkMode: boolean = false;

  onStrokeAdded: (stroke: PageAnnotationStroke) => void = () => {};
  onEraseAtPoint: (u: number, v: number) => void = () => {};

  // 画布与渲染上下文
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @State pageWidth: number = 0;
  @State pageHeight: number = 0;
  private currentStroke: PageAnnotationStroke | null = null;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
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
    // 绘制当前正在书写的一笔
    if (this.currentStroke !== null) {
      this.renderStroke(this.currentStroke);
    }
  }

  /** 将单条归一化笔画映射到实际物理像素并执行贝塞尔平滑绘制 */
  private renderStroke(stroke: PageAnnotationStroke): void {
    const pts = stroke.points;
    if (pts.length === 0) {
      return;
    }

    // 缩放基准比例：以 720px 宽度为基准计算相对线宽
    const scaleFactor = Math.max(0.5, this.pageWidth / 720);
    const renderWidth = Math.max(1.5, stroke.width * scaleFactor);

    // 单点落笔绘制圆点
    if (pts.length === 1) {
      const cx = pts[0].u * this.pageWidth;
      const cy = pts[0].v * this.pageHeight;
      this.context.beginPath();
      if (stroke.isEraser) {
        this.context.fillStyle = this.isDarkMode ? '#1E1E1E' : '#FFFFFF';
      } else {
        this.context.fillStyle = stroke.color;
      }
      this.context.arc(cx, cy, renderWidth, 0, Math.PI * 2);
      this.context.fill();
      return;
    }

    this.context.beginPath();
    this.context.lineWidth = renderWidth;
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';

    if (stroke.isEraser) {
      this.context.strokeStyle = this.isDarkMode ? '#1E1E1E' : '#FFFFFF';
      this.context.globalAlpha = 1.0;
    } else if (stroke.isHighlighter) {
      this.context.strokeStyle = stroke.color;
      this.context.globalAlpha = 0.35;
    } else {
      this.context.strokeStyle = stroke.color;
      this.context.globalAlpha = 1.0;
    }

    // 贝塞尔中点平滑插值算法
    const startX = pts[0].u * this.pageWidth;
    const startY = pts[0].v * this.pageHeight;
    this.context.moveTo(startX, startY);

    if (pts.length === 2) {
      const p1X = pts[1].u * this.pageWidth;
      const p1Y = pts[1].v * this.pageHeight;
      this.context.lineTo(p1X, p1Y);
    } else {
      for (let i = 1; i < pts.length - 1; i++) {
        const curX = pts[i].u * this.pageWidth;
        const curY = pts[i].v * this.pageHeight;
        const nextX = pts[i + 1].u * this.pageWidth;
        const nextY = pts[i + 1].v * this.pageHeight;
        const midX = (curX + nextX) / 2;
        const midY = (curY + nextY) / 2;
        this.context.quadraticCurveTo(curX, curY, midX, midY);
      }
      const lastX = pts[pts.length - 1].u * this.pageWidth;
      const lastY = pts[pts.length - 1].v * this.pageHeight;
      this.context.lineTo(lastX, lastY);
    }

    this.context.stroke();
    this.context.globalAlpha = 1.0;
  }

  /** 处理用户在试卷页面上的落笔事件 */
  private handleTouch(event: TouchEvent): void {
    if (!this.isAnnotateMode || this.tool === 'pan') {
      // 阅读模式或漫游平移模式下不落墨，让外层 Scroll / 手势接管
      return;
    }

    const touch = event.touches[0];
    if (!touch || this.pageWidth <= 0 || this.pageHeight <= 0) {
      return;
    }

    // 转换为归一化比例坐标 [0, 1]
    const clampedX = Math.max(0, Math.min(touch.x, this.pageWidth));
    const clampedY = Math.max(0, Math.min(touch.y, this.pageHeight));
    const u = clampedX / this.pageWidth;
    const v = clampedY / this.pageHeight;

    if (event.type === TouchType.Down) {
      if (this.tool === 'eraser') {
        this.onEraseAtPoint(u, v);
        return;
      }
      const newStroke: PageAnnotationStroke = {
        id: `stroke_${Date.now()}_${Math.floor(Math.random() * 10000)}`,
        pageIndex: this.pageModel.pageIndex,
        color: this.selectedColor,
        width: this.selectedWidth,
        isHighlighter: this.tool === 'highlighter',
        isEraser: false,
        points: [{ u, v }]
      };
      this.currentStroke = newStroke;
      this.redrawAll();
    } else if (event.type === TouchType.Move) {
      if (this.tool === 'eraser') {
        this.onEraseAtPoint(u, v);
        return;
      }
      if (this.currentStroke !== null) {
        const pts = this.currentStroke.points;
        const lastPt = pts[pts.length - 1];
        // 简单抽样过滤：若移动距离极小则跳过，减轻点数压力
        const du = Math.abs(lastPt.u - u);
        const dv = Math.abs(lastPt.v - v);
        if (du > 0.001 || dv > 0.001) {
          pts.push({ u, v });
          this.redrawAll();
        }
      }
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.currentStroke !== null) {
        if (this.currentStroke.points.length > 0) {
          this.onStrokeAdded(this.currentStroke);
        }
        this.currentStroke = null;
        this.redrawAll();
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // ---- 第一层：PDF 页面原生排版层 (Paper View) ----
      Column() {
        // 页眉信息：试卷科目与防伪标记
        Row() {
          Text('绝密 ★ 启用前')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDarkMode ? '#71717A' : '#A1A1AA')
          Blank()
          Text('计算机专业基础综合考卷')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Normal)
            .fontColor(this.isDarkMode ? '#71717A' : '#A1A1AA')
        }
        .width('100%')
        .padding({ bottom: 12 })
        .border({ width: { bottom: 1 }, color: { bottom: this.isDarkMode ? '#27272A' : '#F4F4F5' } })

        // 试卷正文段落列表
        Column({ space: 14 }) {
          ForEach(this.pageModel.sections, (sec: PdfPageSection, idx: number) => {
            if (sec.type === 'header') {
              Column({ space: 4 }) {
                Text(sec.title)
                  .fontSize(TypographyTokens.TITLE_SUB)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette().inkPrimary)
                Text(sec.text)
                  .fontSize(TypographyTokens.BODY_REGULAR)
                  .fontColor(this.palette().inkSecondary)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .margin({ top: 8, bottom: 8 })
            } else if (sec.type === 'question') {
              Column({ space: 8 }) {
                Row({ space: 6 }) {
                  if (sec.tag) {
                    Text(sec.tag)
                      .fontSize(TypographyTokens.CAPTION)
                      .fontColor('#2563EB')
                      .backgroundColor(this.isDarkMode ? '#1E293B' : '#EFF6FF')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(4)
                  }
                  if (sec.score) {
                    Text(`[${sec.score}]`)
                      .fontSize(TypographyTokens.CAPTION)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.isDarkMode ? '#E11D48' : '#DC2626')
                  }
                }

                Text(sec.text)
                  .fontSize(TypographyTokens.BODY_REGULAR)
                  .lineHeight(24)
                  .fontColor(this.palette().inkPrimary)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor(this.isDarkMode ? '#18181B' : '#FAFAFA')
              .borderRadius(8)
              .border({ width: 1, color: this.isDarkMode ? '#27272A' : '#F0F0F0' })
            } else if (sec.type === 'blank') {
              // 试卷留白答题/草稿虚线框
              Column() {
                Text(sec.text)
                  .fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkMuted)
                  .alignSelf(ItemAlign.Start)
              }
              .width('100%')
              .height(130)
              .padding(10)
              .border({
                width: 1,
                style: BorderStyle.Dashed,
                color: this.isDarkMode ? '#3F3F46' : '#D4D4D8'
              })
              .borderRadius(6)
              .backgroundColor(this.isDarkMode ? '#141416' : '#FCFCFC')
            }
          }, (sec: PdfPageSection, idx: number) => `sec_${idx}`)
        }
        .width('100%')
        .margin({ top: 12 })

        Blank()

        // 页脚：页码指示
        Row() {
          Blank()
          Text(this.pageModel.pageNumberText)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
          Blank()
        }
        .width('100%')
        .padding({ top: 14 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 32, right: 32, top: 28, bottom: 24 })
      .backgroundColor(this.isDarkMode ? '#1C1C1E' : '#FFFFFF')

      // ---- 第二层：归一化矢量批注 Canvas 图层 ----
      Canvas(this.context)
        .width('100%')
        .height('100%')
        .hitTestBehavior(!this.isAnnotateMode || this.tool === 'pan' ? HitTestMode.None : HitTestMode.Block)
        .onTouch((event: TouchEvent) => this.handleTouch(event))
    }
    .width('100%')
    .aspectRatio(0.707) // A4 纸比例 1 : 1.414 (宽/高 ≈ 0.707)
    .borderRadius(8)
    .shadow({
      radius: 16,
      color: this.isDarkMode ? 'rgba(0,0,0,0.45)' : 'rgba(0,0,0,0.08)',
      offsetY: 6
    })
    .border({ width: 1, color: this.isDarkMode ? '#2C2C2E' : '#E5E7EB' })
    .onAreaChange((oldArea, newArea) => {
      this.pageWidth = Number(newArea.width);
      this.pageHeight = Number(newArea.height);
      this.redrawAll();
    })
  }
}
