/**
 * 白纸底手写笔记画布组件 (HandwritingCanvas)
 *
 * 核心特性：
 *   1. 白纸质感底色（米白 #FAF9F6 / 暗夜石板灰 #1E1E1E）+ 可选极简方格/点阵底纹
 *   2. 多颜色笔工具栏：炭黑、经典蓝、墨红、翡翠绿、荧光高亮笔
 *   3. 笔触粗细切换（细 2px / 中 4px / 粗 8px / 荧光 16px）与精准橡皮擦
 *   4. 基于 ArkUI Canvas 的平滑实时笔迹采样与重绘
 *   5. 支持撤销、清屏与防抖自动落盘
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, TypographyTokens, AnimationTokens, LayoutTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { CanvasPoint, CanvasStroke } from '../../common/types/CanvasStroke';

const PEN_COLORS: string[] = [
  '#1C1917', // 炭黑
  '#2563EB', // 经典蓝
  '#DC2626', // 墨红
  '#059669', // 翡翠绿
  '#EAB308'  // 荧光黄高亮
];

const STROKE_WIDTHS: number[] = [2, 4, 8];

@Component
export struct HandwritingCanvas {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop isScratchpad: boolean = false;
  @Prop @Watch('saveForExit') exitSaveToken: number = 0;
  onCommitForExit: (note: NoteItem, content: string) => Promise<void> = async () => {};
  onExitSaveFinished: (ok: boolean) => void = () => {};
  onSaved: (note: NoteItem, content: string) => void = () => {};
  onSaveStateChange: (state: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  // 画布上下文
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // 笔迹数据
  @State strokes: CanvasStroke[] = [];
  @State selectedColor: string = '#1C1917';
  @State selectedWidth: number = 3;
  @State isHighlighter: boolean = false;
  @State isEraser: boolean = false;
  @State currentStroke: CanvasStroke | null = null;
  @State title: string = '';
  @State dynamicCanvasHeight: number = 2400;

  private canvasScroller: Scroller = new Scroller();
  private saveTimer: number = -1;
  private loadedNoteId: string = '';
  private canvasWidth: number = 1200;
  private canvasHeight: number = 2400;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.loadedNoteId = this.note.id;
    this.title = this.note.title;
    this.selectedColor = this.isDarkMode ? '#F5F5F4' : '#1C1917';
    this.loadStrokes();
  }

  onNoteChanged(): void {
    if (this.loadedNoteId === this.note.id) { return; }
    this.loadedNoteId = this.note.id;
    this.title = this.note.title;
    this.loadStrokes();
    this.redrawAll();
  }

  aboutToDisappear(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
      if (this.isScratchpad) { this.flushSave(); }
    }
  }

  private async saveForExit(): Promise<void> {
    if (this.saveTimer !== -1) { clearTimeout(this.saveTimer); this.saveTimer = -1; }
    const snapshot = this.strokeSnapshot();
    try {
      await this.onCommitForExit(snapshot, snapshot.contentDetail);
      this.onExitSaveFinished(true);
    } catch {
      this.onSaveStateChange('保存失败');
      this.onExitSaveFinished(false);
    }
  }

  private strokeSnapshot(): NoteItem {
    const snapshot = JSON.parse(JSON.stringify(this.note)) as NoteItem;
    if (this.isScratchpad) {
      snapshot.scratchpadStrokes = JSON.stringify(this.strokes);
    } else {
      snapshot.strokes = JSON.stringify(this.strokes);
      snapshot.title = this.title.trim() || '未命名手写笔记';
      snapshot.contentDetail = `# ${snapshot.title}\n\n[白纸手写笔记]\n`;
      snapshot.previewText = `[白纸手写] 包含 ${this.strokes.length} 条墨迹`;
    }
    return snapshot;
  }

  private loadStrokes(): void {
    const rawStrokes = this.isScratchpad ? this.note.scratchpadStrokes : this.note.strokes;
    if (rawStrokes && rawStrokes.length > 0) {
      try {
        this.strokes = JSON.parse(rawStrokes) as CanvasStroke[];
      } catch (e) {
        console.error(`解析笔迹数据失败: ${JSON.stringify(e)}`);
        this.strokes = [];
      }
    } else {
      this.strokes = [];
    }

    // 根据历史笔迹中最大 Y 轴坐标，智能计算并延展画布高度
    let maxY = 1800;
    for (let i = 0; i < this.strokes.length; i++) {
      const s = this.strokes[i];
      for (let j = 0; j < s.points.length; j++) {
        if (s.points[j].y > maxY) {
          maxY = s.points[j].y;
        }
      }
    }
    this.dynamicCanvasHeight = Math.max(2400, Math.ceil((maxY + 800) / 400) * 400);
    this.canvasHeight = this.dynamicCanvasHeight;
  }

  /** 向下动态延展画布 */
  private extendCanvas(amount: number = 800): void {
    this.dynamicCanvasHeight += amount;
    this.canvasHeight = this.dynamicCanvasHeight;
    setTimeout(() => {
      this.redrawAll();
    }, 40);
  }

  private redrawAll(): void {
    if (!this.context || this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return;
    }
    this.context.clearRect(0, 0, this.canvasWidth, this.canvasHeight);

    // 绘制全部历史笔迹
    for (let i = 0; i < this.strokes.length; i++) {
      this.drawSingleStroke(this.strokes[i]);
    }
    // 绘制当前正在画的一笔
    if (this.currentStroke !== null) {
      this.drawSingleStroke(this.currentStroke);
    }
  }

  private drawSingleStroke(stroke: CanvasStroke): void {
    if (stroke.points.length < 2) {
      if (stroke.points.length === 1) {
        this.context.beginPath();
        this.context.fillStyle = stroke.isEraser
          ? (this.isDarkMode ? '#1E1E1E' : '#FAF9F6')
          : stroke.color;
        this.context.arc(stroke.points[0].x, stroke.points[0].y, stroke.width / 2, 0, Math.PI * 2);
        this.context.fill();
      }
      return;
    }

    this.context.beginPath();
    this.context.lineWidth = stroke.width;
    this.context.lineCap = 'round';
    this.context.lineJoin = 'round';

    if (stroke.isEraser) {
      this.context.strokeStyle = this.isDarkMode ? '#1E1E1E' : '#FAF9F6';
      this.context.globalAlpha = 1.0;
    } else if (stroke.isHighlighter) {
      this.context.strokeStyle = stroke.color;
      this.context.globalAlpha = 0.35;
    } else {
      this.context.strokeStyle = stroke.color;
      this.context.globalAlpha = 1.0;
    }

    this.context.moveTo(stroke.points[0].x, stroke.points[0].y);
    for (let i = 1; i < stroke.points.length; i++) {
      this.context.lineTo(stroke.points[i].x, stroke.points[i].y);
    }
    this.context.stroke();
    this.context.globalAlpha = 1.0;
  }

  private scheduleSave(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
    }
    this.onSaveStateChange('保存中');
    this.saveTimer = setTimeout(() => {
      this.flushSave();
    }, 800);
  }

  private flushSave(): void {
    this.saveTimer = -1;
    const snapshot = this.strokeSnapshot();
    this.onSaved(snapshot, snapshot.contentDetail);
    this.onSaveStateChange('已保存');
  }

  // ------------------------------------------------------------------
  // 交互动作：撤销、清空
  // ------------------------------------------------------------------

  private handleUndo(): void {
    if (this.strokes.length > 0) {
      this.strokes.pop();
      this.redrawAll();
      this.scheduleSave();
    }
  }

  private handleClear(): void {
    this.strokes = [];
    this.redrawAll();
    this.scheduleSave();
  }

  // ------------------------------------------------------------------
  // 工具栏构建
  // ------------------------------------------------------------------

  @Builder
  penToolbar() {
    Row({ space: this.isPhone ? 8 : 12 }) {
      if (this.isScratchpad) {
        Row({ space: 4 }) {
          Text('✎ 随堂草稿')
            .fontSize(this.isPhone ? TypographyTokens.CAPTION : TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
          if (!this.isPhone) {
            Text(`(${this.strokes.length} 笔)`)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
        }
        .layoutWeight(this.isPhone ? 0 : 1)
      } else {
        TextInput({ text: this.title, placeholder: '输入笔记标题…' })
          .fontSize(this.isPhone ? TypographyTokens.BODY_REGULAR : TypographyTokens.TITLE_SUB)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .height(34)
          .layoutWeight(1)
          .onChange((val: string) => {
            this.title = val;
            this.scheduleSave();
          })
      }

      // 可横滑工具项容器
      Scroll() {
        Row({ space: this.isPhone ? 6 : 8 }) {
          // 调色盘
          Row({ space: this.isPhone ? 5 : 8 }) {
            ForEach(PEN_COLORS, (color: string) => {
              Circle({ width: this.isPhone ? 16 : 18, height: this.isPhone ? 16 : 18 })
                .fill(color)
                .stroke(this.selectedColor === color && !this.isEraser && !this.isHighlighter
                  ? this.palette().inkPrimary : Color.Transparent)
                .strokeWidth(2)
                .onClick(() => {
                  this.selectedColor = color;
                  this.isEraser = false;
                  this.isHighlighter = false;
                })
            }, (color: string) => color)
          }
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
          .borderRadius(20)
          .backgroundColor(this.palette().surfaceSubtle)

          // 笔刷粗细
          Row({ space: 5 }) {
            ForEach(STROKE_WIDTHS, (w: number) => {
              Circle({ width: w * 2 + 5, height: w * 2 + 5 })
                .fill(this.selectedWidth === w ? this.palette().inkPrimary : this.palette().inkMuted)
                .onClick(() => {
                  this.selectedWidth = w;
                  this.isEraser = false;
                  this.isHighlighter = false;
                })
            }, (w: number) => `${w}`)
          }
          .padding({ left: 6, right: 6, top: 4, bottom: 4 })
          .borderRadius(20)
          .backgroundColor(this.palette().surfaceSubtle)

          // 荧光高亮笔按钮
          Text('🖍️')
            .fontSize(this.isPhone ? 14 : TypographyTokens.BODY_REGULAR)
            .padding(this.isPhone ? 4 : 6)
            .borderRadius(6)
            .backgroundColor(this.isHighlighter ? this.palette().activeBg : Color.Transparent)
            .onClick(() => {
              this.isHighlighter = !this.isHighlighter;
              this.isEraser = false;
              if (this.isHighlighter) {
                this.selectedColor = '#EAB308';
                this.selectedWidth = 14;
              } else {
                this.selectedColor = this.isDarkMode ? '#F5F5F4' : '#1C1917';
                this.selectedWidth = 3;
              }
            })

          // 橡皮擦按钮
          Text('⌫')
            .fontSize(this.isPhone ? 14 : TypographyTokens.BODY_REGULAR)
            .fontColor(this.isEraser ? this.palette().accent : this.palette().inkSecondary)
            .padding(this.isPhone ? 4 : 6)
            .borderRadius(6)
            .backgroundColor(this.isEraser ? this.palette().activeBg : Color.Transparent)
            .onClick(() => {
              this.isEraser = !this.isEraser;
              this.isHighlighter = false;
            })

          // 撤销按钮
          Text('↩')
            .fontSize(this.isPhone ? 14 : TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .padding(this.isPhone ? 4 : 6)
            .borderRadius(6)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.handleUndo())

          // 清屏按钮
          Text('🗑️')
            .fontSize(this.isPhone ? 14 : TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().danger)
            .padding(this.isPhone ? 4 : 6)
            .borderRadius(6)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.handleClear())

          // 延长画布快捷按钮
          Row({ space: 3 }) {
            Text('＋')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().accent)
            Text('延长')
              .fontSize(this.isPhone ? TypographyTokens.TINY : TypographyTokens.CAPTION)
              .fontColor(this.palette().accent)
          }
          .padding(this.isPhone ? { left: 6, right: 6, top: 4, bottom: 4 } : { left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor(this.palette().accentSoft)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.extendCanvas(800);
            setTimeout(() => {
              this.canvasScroller.scrollEdge(Edge.Bottom);
            }, 60);
          })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .layoutWeight(this.isPhone ? 1 : 0)
    }
    .width('100%')
    .height(48)
    .padding({ left: this.isPhone ? 10 : 20, right: this.isPhone ? 10 : 20 })
    .borderRadius(10)
    .backgroundColor(this.palette().surface)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)' })
  }

  build() {
    Column() {
      // 顶部悬浮工具栏
      this.penToolbar()

      // 白纸质感手绘无限画布区 (支持向下无限滚动与动态延展)
      Scroll(this.canvasScroller) {
        Column() {
          Stack({ alignContent: Alignment.TopStart }) {
            // 白纸底纹层（带极简素雅质感）
            Column()
              .width('100%')
              .height(this.dynamicCanvasHeight)
              .backgroundColor(this.isDarkMode ? '#1C1C1E' : '#FAF9F5')

            // 真实手写笔墨迹 Canvas 层
            Canvas(this.context)
              .width('100%')
              .height(this.dynamicCanvasHeight)
              .onReady(() => {
                this.canvasWidth = 1200;
                this.canvasHeight = this.dynamicCanvasHeight;
                this.redrawAll();
              })
              .onTouch((event: TouchEvent) => {
                const touch = event.touches[0];
                if (!touch) {
                  return;
                }

                // 笔尖接近画布底部时自动无感向下延长
                if (touch.y > this.dynamicCanvasHeight - 320) {
                  this.extendCanvas(800);
                }

                if (event.type === TouchType.Down) {
                  this.currentStroke = {
                    points: [{ x: touch.x, y: touch.y }],
                    color: this.selectedColor,
                    width: this.isEraser ? 16 : this.selectedWidth,
                    isHighlighter: this.isHighlighter,
                    isEraser: this.isEraser
                  };
                  this.drawSingleStroke(this.currentStroke);
                } else if (event.type === TouchType.Move) {
                  if (this.currentStroke !== null) {
                    this.currentStroke.points.push({ x: touch.x, y: touch.y });
                    this.drawSingleStroke(this.currentStroke);
                  }
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  if (this.currentStroke !== null && this.currentStroke.points.length > 0) {
                    this.strokes.push(this.currentStroke);
                    this.currentStroke = null;
                    this.scheduleSave();
                  }
                }
              })
          }
          .width('100%')
          .height(this.dynamicCanvasHeight)
        }
        .width('100%')
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .layoutWeight(1)
      .margin({ top: 8 })
      .borderRadius(12)
      .shadow({ radius: 12, color: 'rgba(0,0,0,0.05)', offsetY: 2 })
      .border({
        width: 1,
        color: this.isDarkMode ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 12, bottom: 16 })
    .backgroundColor(this.palette().canvas)
  }
}
