import { copyNote } from '../../common/utils/NoteSnapshot';
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
import { InkRenderer, InkStyle, InkContext } from '../../services/ink/InkRenderer';
import { InkFrameComposer } from '../../services/ink/InkFrameComposer';
import { StylusShortcutService } from '../../services/ink/StylusShortcutService';
import { CanvasViewport, InkBounds } from '../../services/ink/CanvasViewport';
import { CanvasPaperGuides } from '../../services/ink/CanvasPaperGuides';
import { CanvasStrokeLoader } from '../../services/ink/CanvasStrokeLoader';
import { CanvasStrokeEraser } from '../../services/ink/CanvasStrokeEraser';
import { CanvasToolState, CanvasToolCommand } from '../../common/types/CanvasToolState';
import { AppIcon } from '../common/AppIcon';
import { InkWidthSlider } from '../common/InkWidthSlider';
import { InkToolPolicy } from '../../services/ink/InkToolPolicy';
import { InkShapePolicy } from '../../services/ink/InkShapePolicy';
import { IconButton } from '../common/IconButton';
import { InkCanvasSurface } from './InkCanvasSurface';

const PEN_COLORS: string[] = [
  '#1C1917', // 炭黑
  '#2563EB', // 经典蓝
  '#DC2626', // 墨红
  '#059669', // 翡翠绿
  '#EAB308'  // 荧光黄高亮
];


@Component
export struct HandwritingCanvas {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop isScratchpad: boolean = false;
  @Prop persistOnDisappear: boolean = false;
  @Prop @Watch('onReadOnlyChanged') readOnly: boolean = false;
  @State paperBackground: string = 'blank';
  @Prop @Watch('saveForExit') exitSaveToken: number = 0;
  onCommitForExit: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onExitSaveFinished: (ok: boolean, noteId: string, saveToken: number) => void = () => {};
  onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onSaveStateChange: (state: string) => void = () => {};
  onDirtyChange: (dirty: boolean) => void = () => {};
  onReadingScroll: (offset: number) => void = () => {};
  onBlankTap: () => void = () => {};
  onToolChange: (tool: string) => void = () => {};
  @Prop showToolbar: boolean = true;
  @Prop @Watch('handleToolCommand') toolCommand: CanvasToolCommand = { sequence: 0, target: '', action: '', value: '' };
  onFocused: () => void = () => {};
  onShowTools: () => void = () => {};
  onToolStateChange: (state: CanvasToolState) => void = () => {};
  onContentReady: (ready: boolean) => void = () => {};

  @StorageProp('flowmindDarkMode') @Watch('requestRedraw') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') @Watch('requestRedraw') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  // 画布上下文
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private paperContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // 笔迹数据
  private strokes: CanvasStroke[] = [];
  @State private loadingInk: boolean = false;
  private loadGeneration: number = 0;
  private loadInFlight: Promise<void> | null = null;
  @State loadError: string = '';
  private loadedRaw: string | undefined = undefined;
  @State selectedColor: string = '#1C1917';
  @State selectedWidth: number = 3;
  private penWidth: number = 3;
  private highlighterWidth: number = 14;
  @State eraserWidth: number = 18;
  private penColor: string = '#1C1917';
  private highlighterColor: string = '#EAB308';
  @State isHighlighter: boolean = false;
  @State isPan: boolean = false;
  @State isEraser: boolean = false;
  @State eraserMode: string = 'area';
  private eraseBefore: CanvasStroke[] | null = null;
  private currentStroke: CanvasStroke | null = null;
  private shapeAnchor: CanvasPoint | null = null;
  @State shapeTool: string = '';
  // Whiteboards remain usable without a paired stylus. The hand toggle enables browsing instead.
  @State fingerDrawing: boolean = true;
  @State inkContact: boolean = false;
  @State toolsVisible: boolean = false;
  @State zoomScale: number = 1;
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
  private navigating: boolean = false;
  private pairIds: string = '';
  private pairDistance: number = 0;
  private pairAnchor: CanvasPoint = { x: 0, y: 0 };
  private drawTimer: number = -1;
  private savedRevision: number = 0;
  private saveInFlight: Promise<void> | null = null;
  private boundsCache: Map<CanvasStroke, InkBounds> = new Map();
  private inkFrame: InkFrameComposer = new InkFrameComposer();

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  aboutToAppear(): void {
    this.editingNote = copyNote(this.editingNote || this.note);
    this.shortcuts.start(() => !this.readOnly && !this.loadError && !this.loadingInk && !this.inkContact, () => this.toggleEraser(), () => { this.onFocused(); if (this.showToolbar) { this.toolsVisible = true; } else { this.onShowTools(); } });
    this.loadedNoteId = this.note.id;
    this.title = this.note.title;
    this.selectedColor = this.isDarkMode ? '#F5F5F4' : '#1C1917';
    this.penColor = this.selectedColor; this.onToolChange(this.activeTool()); this.emitToolState();
    this.loadStrokes();
  }

  onNoteChanged(): void {
    if (this.loadedNoteId === this.note.id) {
      const raw = this.isScratchpad ? this.note.scratchpadStrokes : this.note.strokes;
      if ((this.loadError || this.loadingInk) && this.saveRevision === 0 && raw !== this.loadedRaw) {
        this.editingNote = copyNote(this.note);
        this.title = this.note.title; this.loadStrokes(); this.redrawAll();
      }
      return;
    }
    this.finishStroke();
    if (this.saveTimer !== -1) { clearTimeout(this.saveTimer); this.flushSave(); }
    this.editingNote = copyNote(this.note);
    this.undoFrames = []; this.redoFrames = []; this.input.reset();
    this.loadedNoteId = this.note.id;
    this.title = this.note.title;
    this.loadStrokes();
    this.redrawAll();
  }

  aboutToDisappear(): void {
    if (this.isScratchpad || this.persistOnDisappear) { this.finishStroke(); }
    this.loadGeneration++; this.loadInFlight = null; this.loadingInk = false;
    this.shortcuts.stop(); this.input.reset();
    if (this.drawTimer !== -1) { clearTimeout(this.drawTimer); this.drawTimer = -1; }
    this.inkFrame.release();
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
      if (this.isScratchpad || this.persistOnDisappear) { this.flushSave(); }
    }
  }

  private async saveForExit(): Promise<void> {
    const requestToken = this.exitSaveToken;
    const noteId = this.loadedNoteId; const generation = this.loadGeneration;
    if (this.loadingInk && this.saveRevision === 0) {
      const original = this.isScratchpad ? this.note.scratchpadStrokes : this.note.strokes;
      if (original === this.loadedRaw) {
        // No input is accepted while loading. Retain the original bytes without decoding or rewriting them.
        this.onExitSaveFinished(true, noteId, requestToken); return;
      }
    }
    if (this.loadInFlight) { await this.loadInFlight; }
    if (noteId !== this.loadedNoteId || generation !== this.loadGeneration || requestToken !== this.exitSaveToken) {
      this.onExitSaveFinished(false, noteId, requestToken); return;
    }
    this.finishStroke();
    if (this.saveTimer !== -1) { clearTimeout(this.saveTimer); this.saveTimer = -1; }
    if (this.loadError) {
      const raw = this.isScratchpad ? this.note.scratchpadStrokes : this.note.strokes;
      const unchanged = this.saveRevision === 0 && raw === this.loadedRaw;
      if (!unchanged) { this.onSaveStateChange('笔迹无法保存，请先从备份恢复'); }
      // An unchanged damaged scratchpad must not block saving the main document, or be rewritten as empty ink.
      this.onExitSaveFinished(unchanged, this.loadedNoteId, requestToken);
      return;
    }
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
    const snapshot = this.strokeSnapshot();
    try {
      await this.onCommitForExit(snapshot, snapshot.contentDetail, this.isScratchpad ? 'scratchpad' : 'handwriting');
      if (revision !== this.saveRevision || snapshot.id !== this.loadedNoteId) {
        this.onExitSaveFinished(false, snapshot.id, requestToken); return;
      }
      this.savedRevision = revision;
      this.onDirtyChange(false);
      this.onSaveStateChange('已保存');
      this.onExitSaveFinished(true, snapshot.id, requestToken);
    } catch {
      if (revision === this.saveRevision && snapshot.id === this.loadedNoteId) { this.onSaveStateChange('保存失败'); }
      this.onExitSaveFinished(false, snapshot.id, requestToken);
    }
  }

  private strokeSnapshot(): NoteItem {
    const snapshot = copyNote(this.editingNote || this.note);
    if (this.loadError) { return snapshot; }
    if (this.isScratchpad) {
      snapshot.scratchpadStrokes = JSON.stringify(this.strokes);
      snapshot.scratchpadPaperStyle = this.paperBackground;
    } else {
      snapshot.strokes = JSON.stringify(this.strokes);
      snapshot.paperStyle = this.paperBackground;
      snapshot.title = this.title.trim() || '未命名手写笔记';
      snapshot.contentDetail = `# ${snapshot.title}\n\n[白纸手写笔记]\n`;
      snapshot.previewText = `[白纸手写] 包含 ${this.strokes.length} 条墨迹`;
    }
    return snapshot;
  }

  private loadStrokes(): void {
    const rawStrokes = this.isScratchpad ? this.note.scratchpadStrokes : this.note.strokes;
    const paper = this.isScratchpad ? this.note.scratchpadPaperStyle : this.note.paperStyle;
    this.paperBackground = ['blank', 'grid', 'ruled'].includes(paper || '') ? paper! : this.isScratchpad ? 'grid' : 'blank';
    this.emitToolState();
    this.loadedRaw = rawStrokes; this.loadError = '';
    this.strokes = []; this.loadingInk = true; this.onContentReady(false);
    this.boundsCache.clear(); this.panX = 0; this.panY = 0; this.navigating = false; this.pairIds = ''; this.eraseBefore = null;
    if (this.viewportReady) { this.zoomScale = this.canvasWidth / CanvasViewport.REFERENCE_WIDTH; }
    this.saveRevision = 0; this.savedRevision = 0; this.onDirtyChange(false);
    const generation = ++this.loadGeneration;
    this.loadInFlight = this.readStrokes(rawStrokes, this.note.id, generation);
  }

  private async readStrokes(raw: string | undefined, noteId: string, generation: number): Promise<void> {
    try {
      const strokes = await CanvasStrokeLoader.load(raw);
      if (generation !== this.loadGeneration || this.note.id !== noteId) { return; }
      this.strokes = strokes;
    } catch {
      if (generation !== this.loadGeneration || this.note.id !== noteId) { return; }
      console.error('白板笔迹读取失败，原始数据已保留');
      this.loadError = '笔迹数据无法读取，原始内容已保留。请从备份恢复后继续编辑。'; this.toolsVisible = false;
    } finally {
      if (generation === this.loadGeneration && this.note.id === noteId) {
        this.loadingInk = false; this.loadInFlight = null; this.onContentReady(!this.loadError); this.requestRedraw();
      }
    }
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
    if (!this.context || !this.viewportReady || this.loadingInk || this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return;
    }
    if (this.drawTimer !== -1) { clearTimeout(this.drawTimer); this.drawTimer = -1; }
    this.drawPaperBackground();
    if (!this.strokes.length && !this.currentStroke) { this.context.clearRect(0, 0, this.canvasWidth, this.canvasHeight); this.inkFrame.release(); return; }
    this.inkFrame.render(this.context, this.canvasWidth, this.canvasHeight, (context: OffscreenCanvasRenderingContext2D) => {
      for (const stroke of this.strokes) { this.drawSingleStroke(stroke, context); }
      const active = this.currentStroke;
      if (active && active.isEraser && !this.eraseBefore && active.points.length) {
        context.save(); context.translate(this.panX, this.panY); context.scale(this.zoomScale, this.zoomScale);
        InkRenderer.stroke(context, active.points, this.style(active)); context.restore();
      }
    });
  }

  private style(stroke: CanvasStroke): InkStyle {
    return { color: stroke.color, width: stroke.width, highlighter: stroke.isHighlighter, eraser: stroke.isEraser };
  }

  private drawPaperBackground(): void {
    this.paperContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    const lines = CanvasPaperGuides.lines(this.canvasWidth, this.canvasHeight, this.zoomScale, this.panX, this.panY, this.paperBackground);
    if (!lines.length) { return; }
    this.paperContext.save(); this.paperContext.globalAlpha = 0.65;
    this.paperContext.strokeStyle = this.palette().border; this.paperContext.lineWidth = 0.7;
    this.paperContext.beginPath();
    for (const line of lines) {
      this.paperContext.moveTo(line.x1, line.y1); this.paperContext.lineTo(line.x2, line.y2);
    }
    this.paperContext.stroke(); this.paperContext.restore();
  }

  private drawSingleStroke(stroke: CanvasStroke, context: InkContext = this.context): void {
    let bounds = this.boundsCache.get(stroke);
    if (!bounds) { bounds = CanvasViewport.bounds(stroke); this.boundsCache.set(stroke, bounds); }
    if (!CanvasViewport.visible(bounds, this.canvasWidth, this.canvasHeight, this.zoomScale, this.panX, this.panY)) { return; }
    const scale = CanvasViewport.scale(stroke) * this.zoomScale;
    context.save(); context.translate(this.panX, this.panY); context.scale(scale, scale);
    InkRenderer.stroke(context, stroke.points, this.style(stroke)); context.restore();
  }

  private remember(): void {
    this.undoFrames.push(this.strokes.slice());
    if (this.undoFrames.length > 50) { this.undoFrames.shift(); }
    this.redoFrames = [];
  }

  private toggleEraser(): void {
    if (this.readOnly || this.loadError || this.loadingInk) { return; }
    this.shortcuts.claim();
    this.finishStroke(); this.shapeTool = ''; this.isPan = false; this.isEraser = !this.isEraser; this.onToolChange(this.activeTool()); this.emitToolState();
  }

  onReadOnlyChanged(): void {
    if (this.readOnly) { this.finishStroke(); this.toolsVisible = false; }
  }

  private finishStroke(): void {
    const stroke = this.currentStroke;
    if (!this.loadError && this.eraseBefore) {
      if (this.strokes.length !== this.eraseBefore.length) {
        this.undoFrames.push(this.eraseBefore); if (this.undoFrames.length > 50) { this.undoFrames.shift(); }
        this.redoFrames = []; this.scheduleSave();
      } else { this.onDirtyChange(this.saveRevision !== this.savedRevision); }
      this.eraseBefore = null;
    } else if (!this.loadError && stroke && stroke.points.length) {
      this.remember(); this.strokes = [...this.strokes, stroke];
      this.liveContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
      this.drawSingleStroke(stroke); this.scheduleSave();
    }
    if (stroke && !stroke.points.length) { this.onDirtyChange(this.saveRevision !== this.savedRevision); }
    this.currentStroke = null; this.shapeAnchor = null; this.inkContact = false; this.input.reset();
  }

  private cancelContact(): void {
    if (this.eraseBefore) { this.strokes = this.eraseBefore; this.eraseBefore = null; }
    this.currentStroke = null; this.shapeAnchor = null; this.inkContact = false; this.input.reset();
    this.onDirtyChange(this.saveRevision !== this.savedRevision);
    this.liveContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight); this.redrawAll();
  }

  private handleTouch(event: TouchEvent): void {
    if (this.navigateTouch(event)) { return; }
    if (this.readOnly || this.loadError || this.loadingInk || this.isPan) { return; }
    if (event.sourceTool === SourceTool.Pen && event.type === TouchType.Down && this.input.isActive() && !this.input.isPenActive()) {
      this.cancelContact();
    }
    const batch = this.input.read(event, this.fingerDrawing);
    if (batch.phase === 'ignore') { return; }
    event.stopPropagation();
    if (batch.phase === 'cancel') { this.cancelContact(); return; }
    if (batch.phase === 'begin') {
      this.liveContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
      if (this.currentStroke) { this.currentStroke = null; this.redrawAll(); }
      this.shortcuts.claim(); this.onFocused(); this.inkContact = true;
      if (this.isEraser && this.eraserMode === 'stroke') { this.eraseBefore = this.strokes.slice(); }
      this.onDirtyChange(true);
      this.currentStroke = { points: [], color: this.selectedColor, width: (this.isEraser ? this.eraserWidth : this.selectedWidth) / this.zoomScale,
        referenceWidth: CanvasViewport.REFERENCE_WIDTH, isHighlighter: this.isHighlighter && !this.isEraser, isEraser: this.isEraser };
    }
    const stroke = this.currentStroke;
    if (!stroke) { return; }
    if (InkShapePolicy.isShape(this.shapeTool) && !this.isEraser && !this.isHighlighter && !this.isPan) {
      for (const sample of batch.samples) {
        const world = CanvasViewport.world(sample.x, sample.y, this.zoomScale, this.panX, this.panY);
        if (!this.shapeAnchor) { this.shapeAnchor = world; }
        stroke.points = InkShapePolicy.points(this.activeTool(), this.shapeAnchor, world);
      }
      this.liveContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
      this.liveContext.save(); this.liveContext.translate(this.panX, this.panY); this.liveContext.scale(this.zoomScale, this.zoomScale);
      InkRenderer.stroke(this.liveContext, stroke.points, this.style(stroke)); this.liveContext.restore();
      if (batch.phase === 'end') { this.finishStroke(); }
      return;
    }
    const target = stroke.isEraser ? this.context : this.liveContext;
    const style = this.style(stroke);
    let erased = false;
    target.save(); target.translate(this.panX, this.panY); target.scale(this.zoomScale, this.zoomScale);
    for (const point of batch.samples) {
      const world = CanvasViewport.world(point.x, point.y, this.zoomScale, this.panX, this.panY);
      const last = stroke.points[stroke.points.length - 1];
      if (last && Math.hypot(last.x - world.x, last.y - world.y) * this.zoomScale < 0.35 && Math.abs((last.pressure || 0) - point.pressure) < 0.04) { continue; }
      stroke.points.push({ x: world.x, y: world.y, pressure: point.pressure });
      if (this.eraseBefore) {
        const remaining = this.strokes.filter((saved: CanvasStroke) => !CanvasStrokeEraser.hit(saved, last || world, world, stroke.width / 2));
        if (remaining.length !== this.strokes.length) { this.strokes = remaining; erased = true; }
      } else { InkRenderer.segment(target, stroke.points, stroke.points.length - 1, style); }
    }
    target.restore();
    if (erased) { this.requestRedraw(); }
    if (batch.phase === 'end') {
      this.finishStroke();
      if (!stroke.isEraser && !this.isScratchpad) { this.revealWritingSpace(); }
    }
  }

  private revealWritingSpace(): void {
    const last = this.strokes[this.strokes.length - 1];
    if (!last || last.isEraser || !last.points.length) { return; }
    const point = last.points[last.points.length - 1];
    const x = point.x * this.zoomScale + this.panX; const y = point.y * this.zoomScale + this.panY;
    // Move only after lift: expanding must never move the paper underneath an active nib.
    if (y > this.canvasHeight - 56) { this.panY -= this.canvasHeight * 0.3; }
    if (x > this.canvasWidth - 40) { this.panX -= this.canvasWidth * 0.25; }
    if (x < 40) { this.panX += this.canvasWidth * 0.25; }
    this.requestRedraw();
  }

  private navigateTouch(event: TouchEvent): boolean {
    // A pen owns its contact; additional palm/finger contacts must not move the page.
    if (event.sourceTool === SourceTool.Pen || this.input.isPenActive()) { return false; }
    const touches = event.touches;
    if (event.type === TouchType.Cancel && this.navigating) {
      this.navigating = false; this.pairIds = ''; this.panning = false; return true;
    }
    if (touches.length >= 2) {
      if (this.inkContact) { this.cancelContact(); }
      this.onFocused(); this.panning = false; this.navigating = true;
      const a = touches[0]; const b = touches[1];
      const ids = `${a.id}:${b.id}`;
      const centerX = (a.x + b.x) / 2; const centerY = (a.y + b.y) / 2;
      const distance = Math.max(1, Math.hypot(a.x - b.x, a.y - b.y));
      if (this.pairIds !== ids || event.type === TouchType.Down) {
        this.pairIds = ids; this.pairDistance = distance; this.zoomStart = this.zoomScale;
        this.pairAnchor = CanvasViewport.world(centerX, centerY, this.zoomScale, this.panX, this.panY);
      } else if (event.type === TouchType.Move) {
        this.zoomScale = Math.max(0.08, Math.min(8, this.zoomStart * distance / this.pairDistance));
        this.panX = centerX - this.pairAnchor.x * this.zoomScale;
        this.panY = centerY - this.pairAnchor.y * this.zoomScale; this.requestRedraw();
      }
      return true;
    }
    if (this.navigating) {
      this.pairIds = '';
      // A remaining finger cannot turn the end of a pinch into a new ink stroke.
      const allReleased = event.type === TouchType.Up && touches.every((point: TouchObject) =>
        event.changedTouches.some((changed: TouchObject) => changed.id === point.id));
      if (!touches.length || allReleased) { this.navigating = false; }
      return true;
    }
    if (this.inkContact || (event.sourceTool !== SourceTool.Finger && !this.readOnly && !this.isPan) || (this.fingerDrawing && !this.readOnly && !this.isPan)) { return false; }
    const point = event.changedTouches[0] || touches[0];
    if (!point) { this.panning = false; return true; }
    if (event.type === TouchType.Down) { this.onFocused(); this.panning = true; this.panTouchX = point.x; this.panTouchY = point.y; }
    else if (event.type === TouchType.Move && this.panning) {
      if (this.readOnly) { this.onReadingScroll(this.panTouchY - point.y); }
      this.panX += point.x - this.panTouchX; this.panY += point.y - this.panTouchY;
      this.panTouchX = point.x; this.panTouchY = point.y; this.requestRedraw();
    } else { this.panning = false; }
    return true;
  }

  private scheduleSave(): void {
    if (this.loadError) { return; }
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
    if (this.loadError) { this.onSaveStateChange('笔迹无法保存，请先从备份恢复'); return; }
    const revision = this.saveRevision;
    const snapshot = this.strokeSnapshot();
    let pending: Promise<void> | null = null;
    try {
      pending = this.onSaved(snapshot, snapshot.contentDetail, this.isScratchpad ? 'scratchpad' : 'handwriting');
      this.saveInFlight = pending;
      await pending;
      if (revision === this.saveRevision && snapshot.id === this.loadedNoteId) { this.savedRevision = revision; this.onDirtyChange(false); this.onSaveStateChange('已保存'); }
    }
    catch { if (revision === this.saveRevision && snapshot.id === this.loadedNoteId) { this.onSaveStateChange('保存失败'); } }
    finally { if (this.saveInFlight === pending) { this.saveInFlight = null; } }
  }

  // ------------------------------------------------------------------
  // 交互动作：撤销、清空
  // ------------------------------------------------------------------

  private handleUndo(): void {
    if (this.readOnly || this.loadError || this.loadingInk) { return; }
    this.finishStroke();
    const before = this.undoFrames.pop();
    if (!before) { return; }
    this.redoFrames.push(this.strokes.slice()); this.strokes = before;
    this.redrawAll(); this.scheduleSave();
  }

  private handleRedo(): void {
    if (this.readOnly || this.loadError || this.loadingInk) { return; }
    this.finishStroke();
    const after = this.redoFrames.pop();
    if (!after) { return; }
    this.undoFrames.push(this.strokes.slice()); this.strokes = after;
    this.redrawAll(); this.scheduleSave();
  }

  private async handleClear(): Promise<void> {
    if (this.readOnly || this.loadError || this.loadingInk) { return; }
    this.finishStroke();
    if (!this.strokes.length) { return; }
    const noteId = this.loadedNoteId;
    const result = await promptAction.showDialog({ title: '清空笔迹？', message: '清空后可撤销。',
      buttons: [{ text: '取消', color: '#666666' }, { text: '清空', color: '#DC2626' }] });
    if (result.index !== 1 || this.readOnly || this.loadError || this.loadingInk || noteId !== this.loadedNoteId) { return; }
    this.clearConfirmed();
  }

  private clearConfirmed(): void {
    if (this.readOnly || this.loadError || this.loadingInk) { return; }
    this.finishStroke();
    if (!this.strokes.length) { return; }
    this.remember(); this.strokes = [];
    this.redrawAll(); this.scheduleSave();
  }

  // ------------------------------------------------------------------
  // 工具栏构建
  // ------------------------------------------------------------------

  private activeTool(): string { return this.isPan ? 'pan' : this.isEraser ? 'eraser' : this.isHighlighter ? 'highlighter' : this.shapeTool || 'pen'; }

  private rememberInkSettings(): void {
    if (this.isHighlighter) { this.highlighterColor = this.selectedColor; this.highlighterWidth = this.selectedWidth; }
    else { this.penColor = this.selectedColor; this.penWidth = this.selectedWidth; }
  }

  private selectPen(): void {
    if (this.readOnly || this.loadError || this.loadingInk) { return; }
    this.shortcuts.claim();
    this.finishStroke(); this.rememberInkSettings();
    this.shapeTool = ''; this.isPan = false; this.isEraser = false; this.isHighlighter = false;
    this.selectedColor = this.penColor; this.selectedWidth = this.penWidth;
    this.onToolChange(this.activeTool()); this.emitToolState();
  }

  private selectHighlighter(): void {
    if (this.readOnly || this.loadError || this.loadingInk) { return; }
    this.shortcuts.claim();
    this.finishStroke(); this.rememberInkSettings(); this.shapeTool = ''; this.isPan = false; this.isEraser = false; this.isHighlighter = true;
    this.selectedColor = this.highlighterColor; this.selectedWidth = this.highlighterWidth;
    this.onToolChange(this.activeTool()); this.emitToolState();
  }

  private changeWidth(value: number): void {
    if (this.readOnly || this.loadError || this.loadingInk) { return; }
    this.finishStroke();
    if (this.isEraser) { this.eraserWidth = InkToolPolicy.width('eraser', value); }
    else { this.selectedWidth = InkToolPolicy.width(this.activeTool(), value); this.rememberInkSettings(); }
    this.emitToolState();
  }

  private changeColor(color: string): void {
    if (this.readOnly || this.loadError || this.loadingInk || this.isEraser) { return; }
    this.finishStroke(); this.selectedColor = color; this.rememberInkSettings(); this.emitToolState();
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

  private emitToolState(): void {
    this.onToolStateChange({ tool: this.activeTool(), width: this.isEraser ? this.eraserWidth : this.selectedWidth,
      color: this.selectedColor, fingerDrawing: this.fingerDrawing, eraserMode: this.eraserMode, paperStyle: this.paperBackground });
  }

  private selectEraser(): void {
    if (this.readOnly || this.loadError || this.loadingInk) { return; }
    this.isPan = false;
    if (!this.isEraser) { this.toggleEraser(); }
    else { this.onToolChange(this.activeTool()); this.emitToolState(); }
  }

  private changeEraserMode(mode: string): void {
    if (this.readOnly || this.loadError || this.loadingInk || (mode !== 'area' && mode !== 'stroke')) { return; }
    this.finishStroke(); this.eraserMode = mode; this.emitToolState();
  }

  private handleToolCommand(): void {
    const command = this.toolCommand;
    if (command.sequence && command.target === (this.isScratchpad ? 'scratchpad' : 'document') && command.action === 'resetView') {
      this.finishStroke(); this.panX = 0; this.panY = 0; this.zoomScale = this.canvasWidth / CanvasViewport.REFERENCE_WIDTH; this.requestRedraw(); return;
    }
    if (!command.sequence || command.target !== (this.isScratchpad ? 'scratchpad' : 'document') || this.readOnly || this.loadError || this.loadingInk) { return; }
    this.shortcuts.claim();
    if (command.action === 'pen') { this.selectPen(); }
    else if (InkShapePolicy.isShape(command.action)) { this.selectPen(); this.shapeTool = command.action; this.onToolChange(this.activeTool()); this.emitToolState(); }
    else if (command.action === 'paper' && ['blank', 'grid', 'ruled'].includes(command.value)) {
      this.finishStroke(); this.paperBackground = command.value; this.scheduleSave(); this.requestRedraw(); this.emitToolState();
    }
    else if (command.action === 'highlighter') { this.selectHighlighter(); }
    else if (command.action === 'eraser') { this.selectEraser(); }
    else if (command.action === 'pan') { this.finishStroke(); this.isPan = true; this.onToolChange('pan'); this.emitToolState(); }
    else if (command.action === 'width') { this.changeWidth(Number(command.value)); }
    else if (command.action === 'color') { this.changeColor(command.value); }
    else if (command.action === 'eraserMode') { this.changeEraserMode(command.value); }
    else if (command.action === 'finger') { this.finishStroke(); this.fingerDrawing = !this.fingerDrawing; this.emitToolState(); }
    else if (command.action === 'undo') { this.handleUndo(); }
    else if (command.action === 'redo') { this.handleRedo(); }
    else if (command.action === 'clear') { this.handleClear(); }
    else if (command.action === 'clearConfirmed') { this.clearConfirmed(); }
    else if (command.action === 'extend') { this.extendCanvas(800); }
    else if (command.action === 'settings') { this.toolsVisible = true; }
  }

  @Builder
  penToolbar() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        if (this.isScratchpad) {
          Text('随堂草稿').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary).layoutWeight(1)
        } else if (this.readOnly || this.loadError || this.loadingInk) {
          Text(this.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1).maxLines(1)
        } else {
          TextInput({ text: this.title, placeholder: '笔记标题' })
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
            .backgroundColor(Color.Transparent).padding(0).height(44).layoutWeight(1)
            .onChange((value: string) => { this.title = value; this.scheduleSave(); })
        }
        if (!this.readOnly && !this.loadError && !this.loadingInk) {
        IconButton({ icon: $r('app.media.ic_hand'), selected: this.fingerDrawing,
          caption: '手指', compact: true,
          label: this.fingerDrawing ? '关闭手指书写，仅使用手写笔' : '开启手指书写',
          onAction: () => { this.finishStroke(); this.fingerDrawing = !this.fingerDrawing; this.emitToolState(); } })
        }
      }.width('100%')
      if (!this.readOnly && !this.loadError && !this.loadingInk) {
      Scroll() {
      Row() {
        IconButton({ icon: $r('app.media.ic_pen'), label: '普通笔', caption: '笔', compact: true, selected: !this.isEraser && !this.isHighlighter, onAction: () => this.selectPen() })
        IconButton({ icon: $r('app.media.ic_highlighter'), label: '荧光笔', caption: '荧光', compact: true, selected: this.isHighlighter && !this.isEraser, onAction: () => this.selectHighlighter() })
        IconButton({ icon: $r('app.media.ic_eraser'), label: '橡皮', caption: '橡皮', compact: true, selected: this.isEraser, onAction: () => this.selectEraser() })
        IconButton({ icon: $r('app.media.ic_undo'), label: '撤销笔迹', compact: true, onAction: () => this.handleUndo() })
        IconButton({ icon: $r('app.media.ic_redo'), label: '重做笔迹', compact: true, onAction: () => this.handleRedo() })
        IconButton({ icon: $r('app.media.ic_settings'), label: '更多笔设置', compact: true, selected: this.toolsVisible, onAction: () => { this.toolsVisible = !this.toolsVisible; } })
      }.constraintSize({ minWidth: 312 }).justifyContent(FlexAlign.Start)
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      if (this.isEraser) {
        Row({ space: 4 }) {
          Text('橡皮').fontSize(12).fontColor(this.palette().inkSecondary)
          Button('区域擦除', { type: ButtonType.Normal }).height(44).fontSize(12).fontColor(this.eraserMode === 'area' ? this.palette().accent : this.palette().inkSecondary)
            .backgroundColor(this.eraserMode === 'area' ? this.palette().accentSoft : Color.Transparent).onClick(() => this.changeEraserMode('area'))
          Button('笔画擦除', { type: ButtonType.Normal }).height(44).fontSize(12).fontColor(this.eraserMode === 'stroke' ? this.palette().accent : this.palette().inkSecondary)
            .backgroundColor(this.eraserMode === 'stroke' ? this.palette().accentSoft : Color.Transparent).onClick(() => this.changeEraserMode('stroke'))
        }.width('100%')
        Text(this.eraserMode === 'area' ? '只擦掉经过的区域，保留笔画其余部分。' : '碰到笔画就删除整笔，可撤销。')
          .fontSize(12).fontColor(this.palette().inkMuted).width('100%')
      }
      if (this.toolsVisible) {
        InkWidthSlider({ tool: this.activeTool(), value: this.isEraser ? this.eraserWidth : this.selectedWidth, onChange: (value: number) => this.changeWidth(value) })
        Scroll() {
          Row({ space: 4 }) {
            if (!this.isEraser) {
            ForEach(this.inkColors(), (color: string) => {
              Button({ type: ButtonType.Normal }) {
                Circle({ width: 20, height: 20 }).fill(color)
                  .stroke(this.selectedColor === color ? this.palette().inkPrimary : this.palette().border)
                  .strokeWidth(this.selectedColor === color ? 3 : 1)
              }.width(44).height(44).padding(0).borderRadius(5)
                .backgroundColor(this.selectedColor === color ? this.palette().accentSoft : Color.Transparent)
                .accessibilityText(`画笔颜色：${this.colorName(color)}`)
                .onClick(() => this.changeColor(color))
            }, (color: string) => color)
            }
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
      if (this.showToolbar) { this.penToolbar() }

      // 白纸质感手绘无限画布区 (支持向下无限滚动与动态延展)
      Stack({ alignContent: Alignment.TopStart }) {
        InkCanvasSurface({ drawingContext: this.context, liveContext: this.liveContext, paperContext: this.paperContext,
          drawPaper: true, contentReady: !this.loadingInk, interactive: !this.loadingInk && !this.loadError, liveOpacity: this.isHighlighter && !this.isEraser ? 0.35 : 1,
          onPaintReady: () => this.requestRedraw(), onInput: (event: TouchEvent) => this.handleTouch(event),
          onBlankTap: () => { if (this.readOnly && !this.inkContact) { this.onBlankTap(); } },
          onSizeChanged: (surfaceWidth: number, surfaceHeight: number) => {
            if (!Number.isFinite(surfaceWidth) || !Number.isFinite(surfaceHeight) || surfaceWidth <= 0 || surfaceHeight <= 0) { return; }
            const width = surfaceWidth; const height = surfaceHeight;
            if (this.viewportReady && Math.abs(width - this.canvasWidth) < 0.5 && Math.abs(height - this.canvasHeight) < 0.5) { return; }
            this.finishStroke();
            if (!this.viewportReady) { this.zoomScale = width / CanvasViewport.REFERENCE_WIDTH; this.viewportReady = true; }
            else { this.panX += (width - this.canvasWidth) / 2; this.panY += (height - this.canvasHeight) / 2; }
            this.canvasWidth = width; this.canvasHeight = height; this.requestRedraw();
          }
        })
        if (this.loadingInk) {
          Column({ space: 8 }) {
            LoadingProgress().width(32).height(32)
            Text('正在读取稿纸…').fontSize(13).fontColor(this.palette().inkSecondary)
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).hitTestBehavior(HitTestMode.None)
        } else if (this.loadError) {
          Column({ space: 12 }) {
            AppIcon({ source: $r('app.media.ic_canvas'), iconSize: 32, tint: this.palette().inkSecondary })
            Text('笔迹暂时无法读取').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
            Text(this.loadError).fontSize(14).fontColor(this.palette().inkSecondary).textAlign(TextAlign.Center)
          }.width('100%').height('100%').padding(24).justifyContent(FlexAlign.Center)
        }
      }.width('100%')
      .layoutWeight(1)
      .backgroundColor(this.isDarkMode ? '#1C1C1E' : '#FFFFFF')
      .borderRadius(this.showToolbar ? 12 : 0)
      .border({
        width: 1,
        color: this.isDarkMode ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: this.showToolbar ? LayoutTokens.gutter(this.isPhone) : 0, right: this.showToolbar ? LayoutTokens.gutter(this.isPhone) : 0, top: this.showToolbar ? 4 : 0, bottom: this.showToolbar ? 8 : 0 })
    .backgroundColor(this.palette().canvas)
  }
}
