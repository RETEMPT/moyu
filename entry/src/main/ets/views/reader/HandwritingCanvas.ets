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
import { promptAction } from '@kit.ArkUI';
import { ColorPalette, TypographyTokens, LayoutTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { ReaderSaveKind } from '../../common/types/ReaderSaveKind';
import { CanvasPoint, CanvasStroke } from '../../common/types/CanvasStroke';
import { InkInputService, InkSample } from '../../services/ink/InkInputService';
import { InkRenderer, InkStyle } from '../../services/ink/InkRenderer';
import { StylusShortcutService } from '../../services/ink/StylusShortcutService';
import { CanvasViewport, InkBounds } from '../../services/ink/CanvasViewport';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';

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
  @Prop persistOnDisappear: boolean = false;
  @Prop @Watch('onReadOnlyChanged') readOnly: boolean = false;
  @Prop @Watch('saveForExit') exitSaveToken: number = 0;
  onCommitForExit: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onExitSaveFinished: (ok: boolean) => void = () => {};
  onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onSaveStateChange: (state: string) => void = () => {};
  onDirtyChange: (dirty: boolean) => void = () => {};
  onReadingScroll: (offset: number) => void = () => {};
  onBlankTap: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
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
  private currentStroke: CanvasStroke | null = null;
  @State fingerDrawing: boolean = false;
  @State inkContact: boolean = false;
  @State toolsVisible: boolean = false;
  @State zoomScale: number = 1;
  @State viewportWidth: number = 360;
  private zoomStart: number = 1;
  private input: InkInputService = new InkInputService();
  private shortcuts: StylusShortcutService = new StylusShortcutService();
  private undoFrames: CanvasStroke[][] = [];
  private redoFrames: CanvasStroke[][] = [];
  private editingNote: NoteItem | null = null;
  private liveContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State title: string = '';
  private saveTimer: number = -1;
  private saveRevision: number = 0;
  private loadedNoteId: string = '';
  private canvasWidth: number = 1200;
  private canvasHeight: number = 2400;
  private panX: number = 0;
  private panY: number = 0;
  private panTouchX: number = 0;
  private panTouchY: number = 0;
  private panning: boolean = false;
  private zoomAnchor: CanvasPoint = { x: 0, y: 0 };
  private viewportReady: boolean = false;
  private drawTimer: number = -1;
  private savedRevision: number = 0;
  private boundsCache: Map<CanvasStroke, InkBounds> = new Map();

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  aboutToAppear(): void {
    this.editingNote = JSON.parse(JSON.stringify(this.editingNote || this.note)) as NoteItem;
    this.shortcuts.start(() => !this.readOnly && !this.inkContact, () => this.toggleEraser(), () => { this.toolsVisible = true; });
    this.loadedNoteId = this.note.id;
    this.title = this.note.title;
    this.selectedColor = this.isDarkMode ? '#F5F5F4' : '#1C1917';
    this.loadStrokes();
  }

  onNoteChanged(): void {
    if (this.loadedNoteId === this.note.id) { return; }
    this.finishStroke();
    if (this.saveTimer !== -1) { clearTimeout(this.saveTimer); this.flushSave(); }
    this.editingNote = JSON.parse(JSON.stringify(this.note)) as NoteItem;
    this.undoFrames = []; this.redoFrames = []; this.input.reset();
    this.loadedNoteId = this.note.id;
    this.title = this.note.title;
    this.loadStrokes();
    this.redrawAll();
  }

  aboutToDisappear(): void {
    if (this.isScratchpad || this.persistOnDisappear) { this.finishStroke(); }
    this.shortcuts.stop(); this.input.reset();
    if (this.drawTimer !== -1) { clearTimeout(this.drawTimer); this.drawTimer = -1; }
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
      if (this.isScratchpad || this.persistOnDisappear) { this.flushSave(); }
    }
  }

  private async saveForExit(): Promise<void> {
    this.finishStroke();
    if (this.saveTimer !== -1) { clearTimeout(this.saveTimer); this.saveTimer = -1; }
    const snapshot = this.strokeSnapshot();
    try {
      await this.onCommitForExit(snapshot, snapshot.contentDetail, this.isScratchpad ? 'scratchpad' : 'handwriting');
      this.onExitSaveFinished(true);
    } catch {
      this.onSaveStateChange('保存失败');
      this.onExitSaveFinished(false);
    }
  }

  private strokeSnapshot(): NoteItem {
    const snapshot = JSON.parse(JSON.stringify(this.editingNote || this.note)) as NoteItem;
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

    this.boundsCache.clear(); this.panX = 0; this.panY = 0;
    if (this.viewportReady) { this.zoomScale = this.canvasWidth / CanvasViewport.REFERENCE_WIDTH; }
    this.saveRevision = 0; this.savedRevision = 0; this.onDirtyChange(false);
  }

  /** 向下动态延展画布 */
  private extendCanvas(amount: number = 800): void {
    this.finishStroke(); this.panY -= Math.min(amount, this.canvasHeight * 0.75); this.requestRedraw();
  }

  private requestRedraw(): void {
    if (this.drawTimer !== -1) { return; }
    this.drawTimer = setTimeout(() => { this.drawTimer = -1; this.redrawAll(); }, 16);
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

  }

  private style(stroke: CanvasStroke): InkStyle {
    return { color: stroke.color, width: stroke.width, highlighter: stroke.isHighlighter, eraser: stroke.isEraser };
  }

  private drawSingleStroke(stroke: CanvasStroke): void {
    let bounds = this.boundsCache.get(stroke);
    if (!bounds) { bounds = CanvasViewport.bounds(stroke); this.boundsCache.set(stroke, bounds); }
    if (!CanvasViewport.visible(bounds, this.canvasWidth, this.canvasHeight, this.zoomScale, this.panX, this.panY)) { return; }
    const scale = CanvasViewport.scale(stroke) * this.zoomScale;
    this.context.save(); this.context.translate(this.panX, this.panY); this.context.scale(scale, scale);
    InkRenderer.stroke(this.context, stroke.points, this.style(stroke)); this.context.restore();
  }

  private remember(): void {
    this.undoFrames.push(this.strokes.slice());
    if (this.undoFrames.length > 50) { this.undoFrames.shift(); }
    this.redoFrames = [];
  }

  private toggleEraser(): void {
    this.finishStroke(); this.isEraser = !this.isEraser;
  }

  onReadOnlyChanged(): void {
    if (this.readOnly) { this.finishStroke(); this.toolsVisible = false; }
  }

  private finishStroke(): void {
    const stroke = this.currentStroke;
    if (stroke && stroke.points.length) {
      this.remember(); this.strokes = [...this.strokes, stroke];
      this.liveContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
      this.drawSingleStroke(stroke); this.scheduleSave();
    }
    this.currentStroke = null; this.inkContact = false; this.input.reset();
  }

  private handleTouch(event: TouchEvent): void {
    if (this.navigateTouch(event)) { return; }
    if (this.readOnly) { return; }
    const batch = this.input.read(event, this.fingerDrawing);
    if (batch.phase === 'ignore') { return; }
    event.stopPropagation();
    if (batch.phase === 'cancel') {
      this.currentStroke = null; this.inkContact = false;
      this.onDirtyChange(this.saveRevision !== this.savedRevision);
      this.liveContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight); this.redrawAll(); return;
    }
    if (batch.phase === 'begin') {
      this.liveContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
      if (this.currentStroke) { this.currentStroke = null; this.redrawAll(); }
      this.shortcuts.claim(); this.inkContact = true;
      this.onDirtyChange(true);
      this.currentStroke = { points: [], color: this.selectedColor, width: (this.isEraser ? 18 : this.selectedWidth) / this.zoomScale,
        referenceWidth: CanvasViewport.REFERENCE_WIDTH, isHighlighter: this.isHighlighter && !this.isEraser, isEraser: this.isEraser };
    }
    const stroke = this.currentStroke;
    if (!stroke) { return; }
    const target = stroke.isEraser ? this.context : this.liveContext;
    const style = this.style(stroke);
    target.save(); target.translate(this.panX, this.panY); target.scale(this.zoomScale, this.zoomScale);
    for (const point of batch.samples) {
      const world = CanvasViewport.world(point.x, point.y, this.zoomScale, this.panX, this.panY);
      const last = stroke.points[stroke.points.length - 1];
      if (last && Math.hypot(last.x - world.x, last.y - world.y) * this.zoomScale < 0.35 && Math.abs((last.pressure || 0) - point.pressure) < 0.04) { continue; }
      stroke.points.push({ x: world.x, y: world.y, pressure: point.pressure });
      InkRenderer.segment(target, stroke.points, stroke.points.length - 1, style);
    }
    target.restore();
    if (batch.phase === 'end') {
      this.finishStroke();
    }
  }

  private navigateTouch(event: TouchEvent): boolean {
    if (this.inkContact || (event.sourceTool !== SourceTool.Finger && !this.readOnly) || (this.fingerDrawing && !this.readOnly)) { return false; }
    if (event.touches.length > 1) { this.panning = false; return true; }
    const point = event.changedTouches[0] || event.touches[0];
    if (!point) { this.panning = false; return true; }
    if (event.type === TouchType.Down) { this.panning = true; this.panTouchX = point.x; this.panTouchY = point.y; }
    else if (event.type === TouchType.Move && this.panning) {
      if (this.readOnly) { this.onReadingScroll(this.panTouchY - point.y); }
      this.panX += point.x - this.panTouchX; this.panY += point.y - this.panTouchY;
      this.panTouchX = point.x; this.panTouchY = point.y; this.requestRedraw();
    } else { this.panning = false; }
    return true;
  }

  private scheduleSave(): void {
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

  private async flushSave(): Promise<void> {
    this.saveTimer = -1;
    const revision = this.saveRevision;
    const snapshot = this.strokeSnapshot();
    try { await this.onSaved(snapshot, snapshot.contentDetail, this.isScratchpad ? 'scratchpad' : 'handwriting'); if (revision === this.saveRevision && snapshot.id === this.loadedNoteId) { this.savedRevision = revision; this.onDirtyChange(false); this.onSaveStateChange('已保存'); } }
    catch { if (revision === this.saveRevision && snapshot.id === this.loadedNoteId) { this.onSaveStateChange('保存失败'); } }
  }

  // ------------------------------------------------------------------
  // 交互动作：撤销、清空
  // ------------------------------------------------------------------

  private handleUndo(): void {
    this.finishStroke();
    const before = this.undoFrames.pop();
    if (!before) { return; }
    this.redoFrames.push(this.strokes.slice()); this.strokes = before;
    this.redrawAll(); this.scheduleSave();
  }

  private handleRedo(): void {
    const after = this.redoFrames.pop();
    if (!after) { return; }
    this.undoFrames.push(this.strokes.slice()); this.strokes = after;
    this.redrawAll(); this.scheduleSave();
  }

  private async handleClear(): Promise<void> {
    if (!this.strokes.length) { return; }
    const result = await promptAction.showDialog({ title: '清空笔迹？', message: '清空后可撤销。',
      buttons: [{ text: '取消', color: '#666666' }, { text: '清空', color: '#DC2626' }] });
    if (result.index !== 1) { return; }
    this.finishStroke(); this.remember(); this.strokes = [];
    this.redrawAll(); this.scheduleSave();
  }

  // ------------------------------------------------------------------
  // 工具栏构建
  // ------------------------------------------------------------------

  private selectPen(): void {
    this.finishStroke();
    if (this.isHighlighter) {
      this.selectedColor = this.isDarkMode ? '#F5F5F4' : '#1C1917'; this.selectedWidth = 3;
    }
    this.isEraser = false; this.isHighlighter = false;
  }

  private selectHighlighter(): void {
    this.finishStroke(); this.isEraser = false; this.isHighlighter = true;
    this.selectedColor = '#EAB308'; this.selectedWidth = 14;
  }

  private inkColors(): string[] {
    return PEN_COLORS.map((color: string) => color === '#1C1917' && this.isDarkMode ? '#F5F5F4' : color);
  }

  private colorName(color: string): string {
    if (color === '#1C1917') { return '黑色'; }
    if (color === '#F5F5F4') { return '白色'; }
    if (color === '#2563EB') { return '蓝色'; }
    if (color === '#DC2626') { return '红色'; }
    if (color === '#059669') { return '绿色'; }
    return '黄色';
  }

  @Builder
  inkTool(icon: Resource, label: string, selected: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 3 }) {
      AppIcon({ source: icon, iconSize: 22, tint: selected ? this.palette().accent : this.palette().inkSecondary })
      Text(label).fontSize(10).fontColor(this.palette().inkSecondary)
      }
    }.width(56).height(56).padding(0).borderRadius(10)
      .backgroundColor(selected ? this.palette().accentSoft : Color.Transparent)
      .accessibilityText(label).bindTips(label).onClick(action)
  }

  @Builder
  penToolbar() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        if (this.isScratchpad) {
          Text('随堂草稿').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary).layoutWeight(1)
        } else if (this.readOnly) {
          Text(this.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1).maxLines(1)
        } else {
          TextInput({ text: this.title, placeholder: '笔记标题' })
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
            .backgroundColor(Color.Transparent).padding(0).height(44).layoutWeight(1)
            .onChange((value: string) => { this.title = value; this.scheduleSave(); })
        }
        if (!this.readOnly) {
        IconButton({ icon: $r('app.media.ic_hand'), selected: this.fingerDrawing,
          caption: '手指',
          label: this.fingerDrawing ? '关闭手指书写，仅使用手写笔' : '开启手指书写',
          onAction: () => { this.finishStroke(); this.fingerDrawing = !this.fingerDrawing; } })
        }
      }.width('100%')
      if (!this.readOnly) {
      Scroll() {
      Row() {
        this.inkTool($r('app.media.ic_pen'), '笔', !this.isEraser && !this.isHighlighter, () => this.selectPen())
        this.inkTool($r('app.media.ic_highlighter'), '荧光', this.isHighlighter && !this.isEraser, () => this.selectHighlighter())
        this.inkTool($r('app.media.ic_eraser'), '橡皮', this.isEraser, () => this.toggleEraser())
        this.inkTool($r('app.media.ic_undo'), '撤销', false, () => this.handleUndo())
        this.inkTool($r('app.media.ic_redo'), '重做', false, () => this.handleRedo())
        this.inkTool($r('app.media.ic_settings'), '更多', this.toolsVisible, () => { this.toolsVisible = !this.toolsVisible; })
      }.width(Math.max(336, this.viewportWidth - 24)).justifyContent(FlexAlign.SpaceBetween)
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      if (this.toolsVisible) {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.inkColors(), (color: string) => {
              Button({ type: ButtonType.Normal }) {
                Circle({ width: 20, height: 20 }).fill(color)
                  .stroke(this.selectedColor === color ? this.palette().inkPrimary : this.palette().border)
                  .strokeWidth(this.selectedColor === color ? 3 : 1)
              }.width(44).height(44).padding(0).borderRadius(10)
                .backgroundColor(this.selectedColor === color ? this.palette().accentSoft : Color.Transparent)
                .accessibilityText(`画笔颜色：${this.colorName(color)}`)
                .onClick(() => { this.selectPen(); this.selectedColor = color; })
            }, (color: string) => color)
            Divider().vertical(true).height(24).color(this.palette().border)
            ForEach(STROKE_WIDTHS, (width: number) => {
              Button({ type: ButtonType.Normal }) {
                Circle({ width: width * 2 + 4, height: width * 2 + 4 }).fill(this.palette().inkPrimary)
              }.width(44).height(44).padding(0).borderRadius(10)
                .backgroundColor(this.selectedWidth === width ? this.palette().accentSoft : Color.Transparent)
                .accessibilityText(`笔粗 ${width}`)
                .onClick(() => { this.selectPen(); this.selectedWidth = width; })
            }, (width: number) => `${width}`)
            IconButton({ icon: $r('app.media.ic_plus'), label: '延长稿纸', caption: '向下',
              onAction: () => this.extendCanvas(800) })
            IconButton({ icon: $r('app.media.ic_chevron_left'), label: '向左展开白板', caption: '向左',
              onAction: () => { this.finishStroke(); this.panX += this.canvasWidth * 0.75; this.requestRedraw(); } })
            IconButton({ icon: $r('app.media.ic_chevron_right'), label: '向右展开白板', caption: '向右',
              onAction: () => { this.finishStroke(); this.panX -= this.canvasWidth * 0.75; this.requestRedraw(); } })
            IconButton({ icon: $r('app.media.ic_trash'), label: '清空笔迹，可撤销', caption: '清空', destructive: true,
              onAction: () => this.handleClear() })
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      }
      }
    }.width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor(this.palette().surface)
      .border({ width: { bottom: 1 }, color: this.palette().borderSubtle })
  }

  build() {
    Column() {
      // 顶部悬浮工具栏
      this.penToolbar()

      // 白纸质感手绘无限画布区 (支持向下无限滚动与动态延展)
      Stack({ alignContent: Alignment.TopStart }) {
        Column().width('100%').height('100%').backgroundColor(this.isDarkMode ? '#1C1C1E' : '#FAF9F5')
        Canvas(this.context).width('100%').height('100%').hitTestBehavior(HitTestMode.None)
        Canvas(this.liveContext).width('100%').height('100%')
          .opacity(this.isHighlighter && !this.isEraser ? 0.35 : 1)
          .onReady(() => this.requestRedraw())
          .onAreaChange((_old: Area, area: Area) => {
            const width = Math.max(1, Number(area.width)); const height = Math.max(1, Number(area.height));
            this.finishStroke();
            if (!this.viewportReady) { this.zoomScale = width / CanvasViewport.REFERENCE_WIDTH; this.viewportReady = true; }
            else { this.panX += (width - this.canvasWidth) / 2; this.panY += (height - this.canvasHeight) / 2; }
            this.viewportWidth = width; this.canvasWidth = width; this.canvasHeight = height; this.requestRedraw();
          })
          .onTouch((event: TouchEvent) => this.handleTouch(event))
          .onClick(() => { if (this.readOnly && !this.inkContact) { this.onBlankTap(); } })
      }.width('100%')
      .onGestureJudgeBegin((_info: GestureInfo, event: BaseGestureEvent) => {
        return event.sourceTool === SourceTool.Pen || this.inkContact || (this.fingerDrawing && !this.readOnly && event.fingerList.length === 1)
          ? GestureJudgeResult.REJECT : GestureJudgeResult.CONTINUE;
      })
      .parallelGesture(PinchGesture({ fingers: 2 }).onActionStart(() => {
          this.panning = false; this.zoomStart = this.zoomScale;
          this.zoomAnchor = CanvasViewport.world(this.canvasWidth / 2, this.canvasHeight / 2, this.zoomScale, this.panX, this.panY);
        }).onActionUpdate((event: GestureEvent) => {
          if (!this.inkContact && event.sourceTool !== SourceTool.Pen) {
            this.zoomScale = Math.max(0.08, Math.min(8, this.zoomStart * event.scale));
            this.panX = this.canvasWidth / 2 - this.zoomAnchor.x * this.zoomScale;
            this.panY = this.canvasHeight / 2 - this.zoomAnchor.y * this.zoomScale; this.requestRedraw();
          }
        }))
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
