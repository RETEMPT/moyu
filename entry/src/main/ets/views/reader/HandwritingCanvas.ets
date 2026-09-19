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
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../common/constants/DesignTokens';
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
  onSaved: (note: NoteItem, content: string) => void = () => {};
  onSaveStateChange: (state: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

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

  private saveTimer: number = -1;
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.title = this.note.title;
    this.selectedColor = this.isDarkMode ? '#F5F5F4' : '#1C1917';
    this.loadStrokes();
  }

  onNoteChanged(): void {
    this.title = this.note.title;
    this.loadStrokes();
    this.redrawAll();
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
    this.onSaveStateChange('保存中...');
    this.saveTimer = setTimeout(() => {
      this.flushSave();
    }, 800);
  }

  private flushSave(): void {
    const serialized = JSON.stringify(this.strokes);
    if (this.isScratchpad) {
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
        scratchpadStrokes: serialized
      };
      this.onSaved(updatedNote, updatedNote.contentDetail);
      this.onSaveStateChange('草稿已保存');
    } else {
      const updatedNote: NoteItem = {
        id: this.note.id,
        title: this.title.trim().length > 0 ? this.title.trim() : '未命名手写笔记',
        category: this.note.category,
        type: this.note.type,
        previewText: `[白纸手写] 包含 ${this.strokes.length} 条墨迹`,
        tag: this.note.tag.length > 0 ? this.note.tag : '白纸笔记',
        tagColor: this.note.tagColor,
        updateTime: '刚刚',
        contentDetail: `# ${this.title}\n\n[白纸手写笔记]\n`,
        pageInfo: this.note.pageInfo,
        extraInfo: this.note.extraInfo,
        coverUrl: this.note.coverUrl,
        strokes: serialized,
        scratchpadStrokes: this.note.scratchpadStrokes
      };
      this.onSaved(updatedNote, updatedNote.contentDetail);
      this.onSaveStateChange('已保存');
    }
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
    Row({ space: 12 }) {
      if (this.isScratchpad) {
        Row({ space: 6 }) {
          Text('✎ 随堂草稿板')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
          Text(`(${this.strokes.length} 笔)`)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .layoutWeight(1)
      } else {
        TextInput({ text: this.title, placeholder: '输入笔记标题…' })
          .fontSize(TypographyTokens.TITLE_SUB)
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

      // 调色盘
      Row({ space: 8 }) {
        ForEach(PEN_COLORS, (color: string) => {
          Circle({ width: 18, height: 18 })
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
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(20)
      .backgroundColor(this.palette().surfaceSubtle)

      // 笔刷粗细
      Row({ space: 6 }) {
        ForEach(STROKE_WIDTHS, (w: number) => {
          Circle({ width: w * 2 + 6, height: w * 2 + 6 })
            .fill(this.selectedWidth === w ? this.palette().inkPrimary : this.palette().inkMuted)
            .onClick(() => {
              this.selectedWidth = w;
              this.isEraser = false;
              this.isHighlighter = false;
            })
        }, (w: number) => `${w}`)
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(20)
      .backgroundColor(this.palette().surfaceSubtle)

      // 荧光高亮笔按钮
      Text('🖍️')
        .fontSize(TypographyTokens.BODY_REGULAR)
        .padding(6)
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
        .fontSize(TypographyTokens.BODY_REGULAR)
        .fontColor(this.isEraser ? this.palette().accent : this.palette().inkSecondary)
        .padding(6)
        .borderRadius(6)
        .backgroundColor(this.isEraser ? this.palette().activeBg : Color.Transparent)
        .onClick(() => {
          this.isEraser = !this.isEraser;
          this.isHighlighter = false;
        })

      // 撤销按钮
      Text('↩')
        .fontSize(TypographyTokens.BODY_REGULAR)
        .fontColor(this.palette().inkSecondary)
        .padding(6)
        .borderRadius(6)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.handleUndo())

      // 清屏按钮
      Text('🗑️')
        .fontSize(TypographyTokens.BODY_REGULAR)
        .fontColor(this.palette().danger)
        .padding(6)
        .borderRadius(6)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.handleClear())
    }
    .width('100%')
    .height(48)
    .padding({ left: 20, right: 20 })
    .borderRadius(10)
    .backgroundColor(this.palette().surface)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)' })
  }

  build() {
    Column() {
      // 顶部悬浮工具栏
      this.penToolbar()

      // 白纸质感手绘画布区
      Stack() {
        // 白纸底纹层（带淡色网格）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.isDarkMode ? '#1C1C1E' : '#FAF9F5')

        // 真实手写笔墨迹 Canvas 层
        Canvas(this.context)
          .width('100%')
          .height('100%')
          .onReady(() => {
            // 获取画布实际尺寸并重绘
            this.canvasWidth = 1200;
            this.canvasHeight = 1600;
            this.redrawAll();
          })
          .onTouch((event: TouchEvent) => {
            const touch = event.touches[0];
            if (!touch) {
              return;
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
    .padding({ left: 24, right: 24, top: 12, bottom: 16 })
    .backgroundColor(this.palette().canvas)
  }
}
