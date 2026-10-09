/**
 * 华为风独立全屏文档与稿纸工作台 (HuaweiDocWorkspace)
 *
 * 核心设计：
 *   1. 沉浸全屏阅读体验：
 *      - 顶栏与底栏支持平滑隐藏与呼出，释放 100% 屏幕空间。
 *      - 触控边缘感知（顶部/底部相近区域滑动或点击即刻呼出）。
 *      - 非笔触防误触（严格过滤手写笔 Pen 触控，避免书写涂画时意外弹出工具栏）。
 *   2. 华为自带 PDF 风格与高级极简质感：
 *      - 告别单调图标占位：全部控件采用胶囊药丸、图文联动与微排版。
 *      - 顶栏：退出全屏药丸、文档标题与格式勋章、居中分屏胶囊（全屏/AI伴读/稿纸）、撤销重做、检索分享、沉浸切换。
 *      - 二级 Tab：文件 (蓝) / 查看 (青) / 播放 (橙) / 签批 (红) / AI 助学 (紫)。
 *      - 功能区 Action Ribbon：丰富生动的操作卡片，带有清晰功能指示与说明。
 *   3. 浮动翻页与阅读控制台 (HUD Console)：
 *      - ◀ 上一页 / 下一页 ▶
 *      - 页面进度滑块 (Slider) 与百分比指示
 *      - 快捷页码跳转与连续/单页排版模式切换
 *   4. 双模分屏与统一模态弹窗。
 */
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SystemShareService } from '../../../services/SystemShareService';
import { ColorPalette, TypographyTokens, LayoutTokens, AnimationTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { ReaderSaveKind } from '../../../common/types/ReaderSaveKind';
import { CanvasToolState, CanvasToolCommand } from '../../../common/types/CanvasToolState';
import { AnnotationTool } from '../../../common/types/PdfAnnotationTypes';
import { PdfAnnotatorView } from '../pdf/PdfAnnotatorView';
import { InkWidthSlider } from '../../common/InkWidthSlider';
import { InkToolPolicy } from '../../../services/ink/InkToolPolicy';
import { HandwritingCanvas } from '../HandwritingCanvas';
import { HuaweiAiSplitPanel } from './HuaweiAiSplitPanel';
import { HuaweiDocActionDialog, HuaweiDocDialogType } from './HuaweiDocActionDialog';
import { AppIcon } from '../../common/AppIcon';
import { IconButton } from '../../common/IconButton';

export type HuaweiTabType = 'file' | 'view' | 'play' | 'annotate' | 'ai';
export type SplitModeType = 'none' | 'ai' | 'scratchpad';

@Component
export struct HuaweiDocWorkspace {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop @Watch('handleBackRequest') backRequestToken: number = 0;
  @Prop sourcePage: number = 1;
  @Prop @Watch('onSourceJump') sourceJumpToken: number = 0;
  onExtractPdfText: (page: number) => void = () => {};
  onClose: () => void = () => {};
  onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onCommitForExit: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onSmartExtract: () => void = () => {};
  onExportText: () => Promise<void> = async () => {};
  onSearchNotes: () => void = () => {};
  onSaveStateChange: (state: string) => void = () => {};
  onToggleFavorite: (note: NoteItem) => void = () => {};
  onOpenModelSettings: () => void = () => {};
  onRestorePdfSource: () => Promise<void> = async () => {};

  private handleBackRequest(): void {
    if (this.documentMenuOpen) { this.documentMenuOpen = false; return; }
    if (this.activeModal.length > 0) { this.activeModal = ''; return; }
    if (this.jumpDialogOpen) { this.jumpDialogOpen = false; return; }
    if (this.exitDialogOpen) { if (!this.exitSaving) { this.exitDialogOpen = false; } return; }
    if (this.exitSaving || this.restoreSourceBusy) { return; }
    if (this.isAnnotateMode) { this.returnToReading(); return; }
    if (this.isPhone && this.splitMode !== 'none' && !this.scratchpadDirty) { this.splitMode = 'none'; return; }
    if (!this.exitSaving) {
      if (this.documentDirty || this.scratchpadDirty) { this.saveDestination = 'close'; this.exitDialogOpen = true; }
      else { this.onClose(); }
    }
  }

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  // 顶底栏沉浸与显隐状态
  @State barsVisible: boolean = true;
  private scrollTravel: number = 0;

  // 模式与批注状态（鸿蒙笔控设计）
  @State isAnnotateMode: boolean = false;
  @State isPenPaletteExpanded: boolean = true;
  @State currentTool: AnnotationTool = 'pen';
  @State selectedColor: string = '#DC2626';
  @State selectedWidth: number = 3;
  private penWidth: number = 3;
  private highlighterWidth: number = 14;
  @State eraserWidth: number = 20;
  private penColor: string = '#DC2626';
  private highlighterColor: string = '#FACC15';
  @State whiteboardTool: string = 'pen';
  @State inkTarget: string = 'document';
  @State documentInk: CanvasToolState = { tool: 'pen', width: 3, color: '#1C1917', fingerDrawing: true, eraserMode: 'area' };
  @State scratchpadInk: CanvasToolState = { tool: 'pen', width: 3, color: '#1C1917', fingerDrawing: true, eraserMode: 'area' };
  @State canvasCommand: CanvasToolCommand = { sequence: 0, target: '', action: '', value: '' };
  @State pdfEraserMode: string = 'stroke';
  @State documentMenuOpen: boolean = false;
  @State undoTrigger: number = 0;
  @State redoTrigger: number = 0;
  @State fingerDrawing: boolean = false;
  private previousInkTool: AnnotationTool = 'pen';
  @State clearTrigger: number = 0;
  @State exitDialogOpen: boolean = false;
  @State exitSaving: boolean = false;
  @State exitSaveToken: number = 0;
  @State documentDirty: boolean = false;
  @State scratchpadDirty: boolean = false;
  private exitPending: number = 0;
  private exitFailed: boolean = false;
  @State private saveDestination: string = 'close';
  @State private restoreSourceBusy: boolean = false;
  @State private pdfSourceReady: boolean = false;
  @State private whiteboardReady: boolean = false;
  @State private annotationError: string = '';
  private nextSplitMode: SplitModeType = 'none';
  private loadedNoteId: string = '';

  // 导航与功能区状态
  @State activeTab: HuaweiTabType = 'file';
  @State splitMode: SplitModeType = 'none';
  @State activeModal: HuaweiDocDialogType = '';

  // 页码与阅读控制
  @State currentPage: number = 1;
  @State totalPages: number = 1;
  @State zoomPercent: number = 100;
  @State isContinuousScroll: boolean = true;
  @State penOptionsOpen: boolean = false;
  @State penPaletteWidth: number = 360;
  @State shareBusy: boolean = false;
  @State isPresentationMode: boolean = false;
  @State jumpDialogOpen: boolean = false;

  // 稿纸底纹状态
  @State paperBackground: string = 'grid'; // 'grid' | 'ruled' | 'blank'

  // 轻量提示
  @State toastText: string = '';
  @State toastOpen: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private onSourceJump(): void {
    this.currentPage = Math.max(1, Math.min(this.totalPages, this.sourcePage));
  }

  aboutToAppear(): void {
    this.loadedNoteId = this.note.id;
    // Phones support annotation without a paired stylus; the user may still turn finger drawing off.
    if (this.isPhone) { this.fingerDrawing = true; }
    if (this.isDocumentOrExam()) {
      const count = this.note.pageCount && this.note.pageCount > 0 ? this.note.pageCount : 1;
      this.totalPages = count;
      this.currentPage = Math.max(1, Math.min(this.sourcePage, count));
    } else {
      this.currentPage = 1;
      this.totalPages = 1;
    }
  }

  onNoteChanged(): void {
    if (this.loadedNoteId === this.note.id) {
      this.totalPages = this.note.pageCount && this.note.pageCount > 0 ? this.note.pageCount : 1;
      this.currentPage = Math.max(1, Math.min(this.currentPage, this.totalPages));
      return;
    }
    this.loadedNoteId = this.note.id;
    this.activeModal = ''; this.documentMenuOpen = false; this.inkTarget = 'document';
    this.jumpDialogOpen = false;
    this.documentDirty = false; this.scratchpadDirty = false; this.isAnnotateMode = false;
    this.pdfSourceReady = false; this.whiteboardReady = false; this.annotationError = '';
    this.exitDialogOpen = false; this.splitMode = 'none';
    this.exitSaving = false; this.exitPending = 0;
    this.currentPage = 1;
    if (this.isDocumentOrExam()) {
      const count = this.note.pageCount && this.note.pageCount > 0 ? this.note.pageCount : 1;
      this.totalPages = count;
    }
  }

  private saveAndExit(): void {
    this.beginReaderSave();
  }

  private returnToReading(): void {
    if (this.exitSaving || !this.isAnnotateMode) { return; }
    this.isAnnotateMode = false;
    this.penOptionsOpen = false;
    this.isPenPaletteExpanded = false;
    this.barsVisible = true;
    this.scrollTravel = 0;
    this.saveDestination = 'reading';
    this.beginReaderSave();
  }

  private setAnnotationMode(annotate: boolean): void {
    if (this.exitSaving || this.restoreSourceBusy) { return; }
    if (!annotate) { this.returnToReading(); return; }
    if (this.isHandwritingNote() && !this.whiteboardReady) {
      this.showToast('笔迹数据尚未读入或已损坏，请保留原资料并检查备份'); return;
    }
    if (!this.isHandwritingNote() && this.annotationError.length > 0) {
      this.showToast(this.annotationError); return;
    }
    if (!this.isHandwritingNote() && !this.pdfSourceReady) {
      this.showToast(this.note.sourceUri ? '请等待页面读取；读取失败时请重新关联原 PDF' : '请先重新关联这份资料的原 PDF'); return;
    }
    this.inkTarget = this.splitMode === 'scratchpad' ? 'scratchpad' : 'document';
    this.isAnnotateMode = true; this.barsVisible = true;
    this.isPenPaletteExpanded = true;
  }

  private beginReaderSave(): void {
    if (this.exitSaving) { return; }
    this.exitSaving = true;
    this.isAnnotateMode = false;
    this.exitPending = this.splitMode === 'scratchpad' ? 2 : 1;
    this.exitFailed = false;
    this.exitSaveToken++;
  }

  private exitSaveFinished(ok: boolean, noteId: string = '', requestToken: number = -1): void {
    if ((noteId.length > 0 && noteId !== this.loadedNoteId) ||
      (requestToken >= 0 && requestToken !== this.exitSaveToken)) { return; }
    if (!this.exitSaving || this.exitPending <= 0) { return; }
    this.exitFailed = this.exitFailed || !ok; this.exitPending--;
    if (this.exitPending > 0) { return; }
    this.exitSaving = false;
    if (this.exitFailed) {
      this.exitDialogOpen = true;
      this.showToast('保存失败，内容仍保留，请重试');
    } else {
      this.exitDialogOpen = false;
      if (this.saveDestination === 'close') { this.onClose(); }
      else if (this.saveDestination === 'split') { this.splitMode = this.nextSplitMode; }
      else { this.showToast('批注已保存，继续阅读'); }
    }
  }

  private async restorePdfSource(): Promise<void> {
    if (this.restoreSourceBusy || this.exitSaving) { return; }
    if (this.isAnnotateMode || this.documentDirty || this.scratchpadDirty) {
      this.showToast('请先返回阅读并保存批注，再重新关联原 PDF'); return;
    }
    this.restoreSourceBusy = true;
    const originalId = this.note.id;
    try {
      const answer = await promptAction.showDialog({ title: '重新关联原 PDF',
        message: `请选择《${this.note.title}》原来的 PDF。现有批注会保留；相同页数不代表相同内容，关联后请检查笔迹是否对应。旧页面文字索引将清除，可重新提取。`,
        buttons: [{ text: '取消', color: this.palette().inkSecondary }, { text: '选择原文件', color: this.palette().accent }] });
      if (answer.index === 1 && this.note.id === originalId) { await this.onRestorePdfSource(); }
    }
    catch (error) { this.showToast(error instanceof Error ? error.message : '原 PDF 未能关联，请重试'); }
    finally { this.restoreSourceBusy = false; }
  }

  private switchSplitMode(mode: SplitModeType): void {
    if (this.exitSaving || this.restoreSourceBusy || this.splitMode === mode) { return; }
    if (this.splitMode === 'scratchpad' && this.scratchpadDirty) {
      this.nextSplitMode = mode;
      this.saveDestination = 'split';
      this.beginReaderSave();
      return;
    }
    this.splitMode = mode;
  }

  private openSearch(): void {
    if (this.isAnnotateMode || this.documentDirty || this.scratchpadDirty || this.exitSaving) {
      this.showToast('请先返回阅读并保存批注，再打开其他资料'); return;
    }
    this.onSearchNotes();
  }

  private openSmartExtract(): void {
    if (this.isAnnotateMode || this.documentDirty || this.scratchpadDirty || this.exitSaving) {
      this.showToast('请先返回阅读并保存批注，再整理新资料'); return;
    }
    this.onSmartExtract();
  }

  private pageNumbersList(): number[] {
    const list: number[] = [];
    for (let i = 1; i <= this.totalPages; i++) {
      list.push(i);
    }
    return list;
  }

  /** 是否为 PDF / Word 试卷或参考资料 */
  private isDocumentOrExam(): boolean {
    const t = this.note.type.toLowerCase();
    const cat = this.note.category;
    return t === 'pdf' || t === 'doc' || t === 'docx' || cat === '试卷题库' || this.note.id === 'note-seed-exam' || this.note.id === 'note-seed-pdf';
  }

  /** 是否为纯稿纸/白纸手写型笔记 */
  private isHandwritingNote(): boolean {
    const t = this.note.type.toLowerCase();
    return t === 'canvas' || t === '白板' || t === '白纸笔记' || t === 'handwriting' || t === '稿纸';
  }

  /**
   * 判断是否为手指触控（严格过滤手写笔 Pen 触控，避免笔迹落笔时误触发呼出）
   */
  private isFingerTouch(event: TouchEvent): boolean {
    return event.sourceTool === SourceTool.Finger;
  }

  /** 切换顶底栏显隐 */
  private toggleBars(visible: boolean): void {
    animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
      this.barsVisible = visible;
    });
  }

  /** 上一页 */
  private prevPage(): void {
    if (this.currentPage > 1) {
      this.currentPage--;
      this.showToast(`已翻至第 ${this.currentPage} 页`);
    }
  }

  /** 下一页 */
  private nextPage(): void {
    if (this.currentPage < this.totalPages) {
      this.currentPage++;
      this.showToast(`已翻至第 ${this.currentPage} 页`);
    }
  }

  /** 跳转指定页码 */
  private jumpToPage(page: number): void {
    const p = Math.max(1, Math.min(this.totalPages, Math.round(page)));
    this.currentPage = p;
    animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
      this.jumpDialogOpen = false;
    });
    this.showToast(`已跳转至第 ${this.currentPage} 页`);
  }

  /** 清空当前页批注 */
  private clearCurrentPageAnnotations(): void {
    if (!this.isAnnotateMode || this.exitSaving) { return; }
    this.clearTrigger++;
  }

  private showToast(msg: string): void {
    this.toastText = msg;
    this.toastOpen = true;
    try {
      promptAction.showToast({ message: msg, duration: 1500 });
    } catch (e) {
      // ignore
    }
    setTimeout(() => {
      this.toastOpen = false;
    }, 2000);
  }

  // ------------------------------------------------------------------
  // 顶栏构建：退出、标题勋章、居中分屏胶囊、快捷工具
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // 顶栏构建：退出、标题勋章、模式分段（阅读/批注）、分屏胶囊、更多
  // ------------------------------------------------------------------

  @Builder
  readerModeButton(icon: Resource, label: string, annotate: boolean) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 3 }) {
      AppIcon({ source: icon, iconSize: 22, tint: this.isAnnotateMode === annotate ? this.palette().accent : this.palette().inkSecondary })
      Text(label).fontSize(10).fontColor(this.palette().inkPrimary)
      }
    }.width(56).height(56).padding(0).borderRadius(12)
      .backgroundColor(this.isAnnotateMode === annotate ? this.palette().accentSoft : Color.Transparent)
      .accessibilityText(label).bindTips(label)
      .enabled(!this.exitSaving && !this.restoreSourceBusy)
      .onClick(() => this.setAnnotationMode(annotate))
  }

  private handleReadingScroll(offset: number): void {
    if (this.isAnnotateMode || this.documentDirty || this.scratchpadDirty) { return; }
    this.scrollTravel = offset > 0 ? this.scrollTravel + offset : 0;
    if (this.scrollTravel >= 24) { this.scrollTravel = 0; this.toggleBars(false); }
  }

  @Builder
  topNavigationBar() {
    Column({ space: 2 }) {
      Row({ space: 4 }) {
        IconButton({ icon: $r('app.media.ic_back'), label: this.isAnnotateMode ? '返回阅读并保存批注' : '返回', caption: '返回', compact: true, destructive: this.isAnnotateMode, onAction: () => this.handleBackRequest() })
        Text(this.note.title).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        IconButton({ icon: $r('app.media.ic_star'), label: this.note.favorite ? '取消收藏' : '收藏',
          caption: '收藏', selected: this.note.favorite === true, onAction: () => this.onToggleFavorite(this.note) })
        IconButton({ icon: $r('app.media.ic_fullscreen'), label: '沉浸阅读', caption: '沉浸',
          onAction: () => { this.toggleBars(false); this.showToast('轻触屏幕边缘显示工具栏'); } })
        Button({ type: ButtonType.Normal }) {
          Column({ space: 3 }) {
            AppIcon({ source: $r('app.media.ic_more'), tint: this.palette().inkSecondary })
            Text('更多').fontSize(10).fontColor(this.palette().inkSecondary)
          }
        }.width(44).height(56).padding(0).borderRadius(12).backgroundColor(Color.Transparent).accessibilityText('更多文档操作')
          .enabled(!this.exitSaving && !this.restoreSourceBusy).onClick(() => { this.documentMenuOpen = !this.documentMenuOpen; })
          .bindMenu(this.documentMenuOpen, this.documentMenu, { onDisappear: () => { this.documentMenuOpen = false; } })
      }.width('100%').height(60)
      if (this.isAnnotateMode) { this.annotationToolbar() }
      else {
      Scroll() {
        Row({ space: 4 }) {
          this.readerModeButton($r('app.media.ic_read'), '阅读', false)
          this.readerModeButton(this.isAnnotateMode ? this.activeToolIcon() : $r('app.media.ic_pen'), this.isAnnotateMode ? InkToolPolicy.label(this.activeTool()) : '批注', true)
          Divider().vertical(true).height(24).color(this.palette().border).margin({ left: 4, right: 4 })
          this.splitSegmentItem($r('app.media.ic_page'), '单页', 'none')
          this.splitSegmentItem($r('app.media.ic_sparkle'), '墨客', 'ai')
          this.splitSegmentItem($r('app.media.ic_canvas'), '稿纸', 'scratchpad')
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      }
    }.width('100%').padding({ left: 8, right: 8, bottom: 4 }).backgroundColor(this.palette().surface)
      .border({ width: { bottom: 1 }, color: this.palette().borderSubtle })
  }

  @Builder
  splitSegmentItem(icon: Resource, label: string, mode: SplitModeType) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 3 }) {
      AppIcon({ source: icon, iconSize: 22, tint: this.splitMode === mode ? this.palette().accent : this.palette().inkSecondary })
      Text(label).fontSize(10).fontColor(this.palette().inkPrimary)
      }
    }.width(56).height(56).padding(0).borderRadius(12)
      .backgroundColor(this.splitMode === mode ? this.palette().accentSoft : Color.Transparent)
      .accessibilityText(mode === 'none' ? '仅显示文档' : `打开${label}分屏`)
      .bindTips(mode === 'none' ? '仅显示文档' : `打开${label}分屏`)
      .onClick(() => {
        this.switchSplitMode(mode);
      })
  }

  // ------------------------------------------------------------------
  // 灵动悬浮笔盘 (Floating Pen Palette) - 遵循鸿蒙笔控设计规范与 Obsidian 极简质感
  // ------------------------------------------------------------------

  private usesCanvasTools(): boolean { return this.inkTarget === 'scratchpad' || this.isHandwritingNote(); }
  private canvasState(): CanvasToolState { return this.inkTarget === 'scratchpad' ? this.scratchpadInk : this.documentInk; }
  private activeTool(): string { return this.usesCanvasTools() ? this.canvasState().tool : this.currentTool; }
  private activeWidth(): number { return this.usesCanvasTools() ? this.canvasState().width : this.currentTool === 'eraser' ? this.eraserWidth : this.selectedWidth; }
  private activeColor(): string { return this.usesCanvasTools() ? this.canvasState().color : this.selectedColor; }
  private activeFingerDrawing(): boolean { return this.usesCanvasTools() ? this.canvasState().fingerDrawing : this.fingerDrawing; }
  private activeEraserMode(): string { return this.usesCanvasTools() ? this.canvasState().eraserMode : this.pdfEraserMode; }
  private inkColors(): string[] {
    return [this.usesCanvasTools() && this.isDarkMode ? '#F5F5F4' : '#1C1917', '#2563EB', '#DC2626', '#059669', '#EAB308'];
  }

  private sendCanvasCommand(action: string, value: string = ''): void {
    if (!this.isAnnotateMode || this.exitSaving) { return; }
    this.canvasCommand = { sequence: this.canvasCommand.sequence + 1, target: this.inkTarget, action, value };
  }
  private selectInkTool(tool: AnnotationTool): void {
    if (this.usesCanvasTools()) { this.sendCanvasCommand(tool); }
    else { this.selectPdfTool(tool); }
  }
  private changeInkWidth(value: number): void {
    if (this.usesCanvasTools()) { this.sendCanvasCommand('width', String(value)); }
    else { this.changePdfWidth(value); }
  }
  private changeInkColor(value: string): void {
    if (this.usesCanvasTools()) { this.sendCanvasCommand('color', value); }
    else { this.selectedColor = value; }
  }
  private changeInkEraserMode(value: string): void {
    if (this.usesCanvasTools()) { this.sendCanvasCommand('eraserMode', value); }
    else { this.pdfEraserMode = value; }
  }
  private undoInk(): void { if (this.usesCanvasTools()) { this.sendCanvasCommand('undo'); } else { this.undoTrigger++; } }
  private redoInk(): void { if (this.usesCanvasTools()) { this.sendCanvasCommand('redo'); } else { this.redoTrigger++; } }
  private toggleInkFinger(): void { if (this.usesCanvasTools()) { this.sendCanvasCommand('finger'); } else { this.fingerDrawing = !this.fingerDrawing; } }
  private activeToolIcon(): Resource {
    const tool = this.activeTool();
    return tool === 'eraser' ? $r('app.media.ic_eraser') : tool === 'highlighter' ? $r('app.media.ic_highlighter') : tool === 'pan' ? $r('app.media.ic_hand') : $r('app.media.ic_pen');
  }
  private selectPdfTool(tool: AnnotationTool): void {
    if (this.exitSaving || this.restoreSourceBusy) { return; }
    if (this.currentTool === 'pen') { this.penColor = this.selectedColor; this.penWidth = this.selectedWidth; }
    if (this.currentTool === 'highlighter') { this.highlighterColor = this.selectedColor; this.highlighterWidth = this.selectedWidth; }
    if (tool === 'eraser' && this.currentTool !== 'eraser') { this.previousInkTool = this.currentTool === 'highlighter' ? 'highlighter' : 'pen'; }
    this.currentTool = tool;
    if (tool === 'pen') { this.selectedColor = this.penColor; this.selectedWidth = this.penWidth; }
    if (tool === 'highlighter') { this.selectedColor = this.highlighterColor; this.selectedWidth = this.highlighterWidth; }
  }
  private changePdfWidth(value: number): void {
    if (this.currentTool === 'eraser') { this.eraserWidth = InkToolPolicy.width('eraser', value); }
    else if (this.currentTool !== 'pan') { this.selectedWidth = InkToolPolicy.width(this.currentTool, value); }
  }

  @Builder
  annotationToolbar() {
    Column({ space: 4 }) {
      Scroll() {
        Row({ space: 2 }) {
          if (this.splitMode === 'scratchpad') {
            Button('正文', { type: ButtonType.Normal }).height(44).fontSize(12).borderRadius(8)
              .backgroundColor(this.inkTarget === 'document' ? this.palette().accentSoft : Color.Transparent).fontColor(this.palette().inkPrimary)
              .accessibilityText('操作正文批注').onClick(() => { this.inkTarget = 'document'; })
            Button('稿纸', { type: ButtonType.Normal }).height(44).fontSize(12).borderRadius(8)
              .backgroundColor(this.inkTarget === 'scratchpad' ? this.palette().accentSoft : Color.Transparent).fontColor(this.palette().inkPrimary)
              .accessibilityText('操作随堂稿纸').onClick(() => { this.inkTarget = 'scratchpad'; })
            Divider().vertical(true).height(24).color(this.palette().border)
          }
          IconButton({ icon: $r('app.media.ic_pen'), caption: '笔', compact: true, label: '普通笔', selected: this.activeTool() === 'pen', onAction: () => this.selectInkTool('pen') })
          IconButton({ icon: $r('app.media.ic_highlighter'), caption: '荧光', compact: true, label: '荧光笔', selected: this.activeTool() === 'highlighter', onAction: () => this.selectInkTool('highlighter') })
          IconButton({ icon: $r('app.media.ic_eraser'), caption: '橡皮', compact: true, label: '橡皮', selected: this.activeTool() === 'eraser', onAction: () => this.selectInkTool('eraser') })
          IconButton({ icon: $r('app.media.ic_undo'), label: '撤销当前批注', compact: true, onAction: () => this.undoInk() })
          IconButton({ icon: $r('app.media.ic_redo'), label: '重做当前批注', compact: true, onAction: () => this.redoInk() })
          IconButton({ icon: $r('app.media.ic_settings'), label: '更多笔设置', compact: true, selected: this.penOptionsOpen, onAction: () => { this.penOptionsOpen = !this.penOptionsOpen; } })
        }.constraintSize({ minWidth: this.splitMode === 'scratchpad' ? 460 : 312 })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      if (this.penOptionsOpen) {
        Column({ space: 2 }) {
          InkWidthSlider({ tool: this.activeTool(), value: this.activeWidth(), onChange: (value: number) => this.changeInkWidth(value) })
          Scroll() {
            Row({ space: 4 }) {
              if (this.activeTool() !== 'eraser') {
                ForEach(this.inkColors(), (color: string) => {
                  Button({ type: ButtonType.Normal }) {
                    Circle({ width: 20, height: 20 }).fill(color)
                      .stroke(this.activeColor() === color ? this.palette().inkPrimary : this.palette().border)
                      .strokeWidth(this.activeColor() === color ? 3 : 1)
                  }.width(44).height(44).padding(0).borderRadius(8).backgroundColor(this.activeColor() === color ? this.palette().accentSoft : Color.Transparent)
                    .accessibilityText(`批注颜色 ${color}`).onClick(() => this.changeInkColor(color))
                }, (color: string) => color)
              } else {
                Button('区域消除', { type: ButtonType.Normal }).height(44).fontSize(12).fontColor(this.palette().inkPrimary)
                  .backgroundColor(this.activeEraserMode() === 'area' ? this.palette().accentSoft : Color.Transparent).onClick(() => this.changeInkEraserMode('area'))
                Button('笔画消除', { type: ButtonType.Normal }).height(44).fontSize(12).fontColor(this.palette().inkPrimary)
                  .backgroundColor(this.activeEraserMode() === 'stroke' ? this.palette().accentSoft : Color.Transparent).onClick(() => this.changeInkEraserMode('stroke'))
              }
              IconButton({ icon: $r('app.media.ic_hand'), caption: '手指', compact: true, selected: this.activeFingerDrawing(),
                label: this.activeFingerDrawing() ? '关闭手指书写，仅使用手写笔' : '开启手指书写', onAction: () => this.toggleInkFinger() })
              if (this.usesCanvasTools()) {
                IconButton({ icon: $r('app.media.ic_plus'), caption: '向下', compact: true, label: '展开更多书写区域',
                  onAction: () => this.sendCanvasCommand('extend') })
                IconButton({ icon: $r('app.media.ic_trash'), caption: '清空', compact: true, label: '清空当前画布笔迹，可撤销', destructive: true,
                  onAction: () => this.sendCanvasCommand('clear') })
              }
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }.width('100%').constraintSize({ maxWidth: 640 }).alignSelf(ItemAlign.Center)
      }
    }.width('100%').enabled(!this.exitSaving)
  }

  @Builder
  floatingBall() {
    Row({ space: 6 }) {
      AppIcon({ source: this.isAnnotateMode ? this.activeToolIcon() : $r('app.media.ic_pen'), tint: this.palette().onAccent })
    }
    .padding(this.isAnnotateMode ? 12 : { left: 14, right: 16, top: 10, bottom: 10 })
    .constraintSize({ minWidth: 44, minHeight: 44 })
    .accessibilityText(this.isAnnotateMode ? `当前${InkToolPolicy.label(this.activeTool())}，打开批注工具` : '打开批注工具')
    .borderRadius(24)
    .backgroundColor(this.palette().accent)
    .shadow({
      radius: 16,
      color: this.isDarkMode ? 'rgba(0,0,0,0.5)' : 'rgba(37,99,235,0.35)',
      offsetY: 6
    })
    .hoverEffect(HoverEffect.Highlight)
    .margin({ right: 24, bottom: 24 })
    .zIndex(60)
    .onClick(() => {
      animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
        if (!this.isAnnotateMode) {
          this.setAnnotationMode(true);
        } else {
          this.isPenPaletteExpanded = true;
        }
      });
    })
  }

  // ------------------------------------------------------------------
  // 「··· 更多」功能操作面板与统一入口 (Obsidian 简约命令卡片风格)
  // ------------------------------------------------------------------

  private async shareOriginalPdf(): Promise<void> {
    if (this.shareBusy) { return; }
    this.shareBusy = true;
    const title = this.note.title;
    const source = this.note.sourceUri || '';
    try {
      await SystemShareService.sharePdf(this.getUIContext().getHostContext() as common.UIAbilityContext, title, source);
    } catch (error) {
      this.showToast(error instanceof Error ? error.message : '系统分享未打开，请使用资料备份');
    } finally { this.shareBusy = false; }
  }

  @Builder
  documentMenu() {
    Menu() {
      MenuItem({ content: '打开随堂稿纸', startIcon: $r('app.media.ic_canvas') })
        .onClick(() => { this.documentMenuOpen = false; this.switchSplitMode('scratchpad'); })
      MenuItem({ content: '打开 AI 伴读', startIcon: $r('app.media.ic_sparkle') })
        .onClick(() => { this.documentMenuOpen = false; this.switchSplitMode('ai'); })
      MenuItem({ content: '仅显示正文', startIcon: $r('app.media.ic_page') })
        .onClick(() => { this.documentMenuOpen = false; this.switchSplitMode('none'); })
      if (!this.isHandwritingNote()) {
        MenuItem({ content: this.restoreSourceBusy ? '正在关联原 PDF…' : '重新关联原 PDF' })
          .enabled(!this.restoreSourceBusy && !this.exitSaving).onClick(() => { this.documentMenuOpen = false; this.restorePdfSource(); })
      }
      if (this.note.sourceType === 'pdf' && this.note.sourceUri) {
        MenuItem({ content: '分享原 PDF' }).enabled(!this.shareBusy).onClick(() => { this.documentMenuOpen = false; this.shareOriginalPdf(); })
        MenuItem({ content: '提取页面文字' }).onClick(() => { this.documentMenuOpen = false; this.onExtractPdfText(this.currentPage); })
        MenuItem({ content: '跳转页码' }).onClick(() => { this.documentMenuOpen = false; this.jumpDialogOpen = true; })
        MenuItem({ content: this.isContinuousScroll ? '切换单页阅读' : '切换连续阅读' })
          .onClick(() => { this.documentMenuOpen = false; this.isContinuousScroll = !this.isContinuousScroll; })
        MenuItem({ content: '清空本页笔迹，可撤销' }).enabled(this.isAnnotateMode && !this.exitSaving)
          .onClick(() => { this.documentMenuOpen = false; this.clearCurrentPageAnnotations(); })
      }
      MenuItem({ content: '提取图片或文字' }).onClick(() => { this.documentMenuOpen = false; this.openSmartExtract(); })
      MenuItem({ content: '导出笔记文字' }).onClick(() => { this.documentMenuOpen = false; this.onExportText(); })
      MenuItem({ content: '搜索资料' }).onClick(() => { this.documentMenuOpen = false; this.openSearch(); })
      MenuItem({ content: '退出阅读' }).onClick(() => { this.documentMenuOpen = false; this.handleBackRequest(); })
    }
  }

  // ------------------------------------------------------------------
  // 底部高级浮动翻页与阅读控制台 (HUD Console) - Obsidian 极简几何字形
  // ------------------------------------------------------------------

  @Builder
  bottomReadingConsole() {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        IconButton({ icon: $r('app.media.ic_chevron_left'), label: '上一页', available: this.currentPage > 1,
          onAction: () => this.prevPage() })
        Button(`${this.currentPage} / ${this.totalPages}`, { type: ButtonType.Normal })
          .height(44).layoutWeight(1).constraintSize({ minWidth: 44 })
          .fontSize(14).fontColor(this.palette().inkPrimary).backgroundColor(Color.Transparent)
          .accessibilityText(`当前第 ${this.currentPage} 页，共 ${this.totalPages} 页，点击跳转`)
          .onClick(() => { this.jumpDialogOpen = true; })
        IconButton({ icon: $r('app.media.ic_chevron_right'), label: '下一页', available: this.currentPage < this.totalPages,
          onAction: () => this.nextPage() })
        IconButton({ icon: this.isContinuousScroll ? $r('app.media.ic_menu') : $r('app.media.ic_page'),
          label: this.isContinuousScroll ? '切换单页阅读' : '切换连续阅读',
          onAction: () => { this.isContinuousScroll = !this.isContinuousScroll; } })
        IconButton({ icon: $r('app.media.ic_chevron_down'), label: '隐藏阅读工具栏',
          onAction: () => this.toggleBars(false) })
      }.width('100%')
      if (!this.isPhone && this.totalPages > 1) {
        Slider({ value: this.currentPage, min: 1, max: this.totalPages, step: 1, style: SliderStyle.OutSet })
          .width('100%').height(28).trackColor(this.palette().surfaceSubtle).selectedColor(this.palette().accent)
          .accessibilityText('翻页进度').onChange((value: number) => { this.currentPage = Math.round(value); })
      }
    }.width('96%').constraintSize({ maxWidth: 600 })
      .padding({ left: 8, right: 8, top: 4, bottom: 4 }).borderRadius(18)
      .backgroundColor(this.palette().surface).border({ width: 1, color: this.palette().border })
      .shadow({ radius: 12, color: this.isDarkMode ? 'rgba(0,0,0,0.4)' : 'rgba(36,32,51,0.12)', offsetY: 3 })
      .margin({ bottom: 12 }).translate({ y: this.barsVisible ? 0 : 96 })
      .opacity(this.barsVisible ? 1 : 0).enabled(this.barsVisible)
      .animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut })
  }

  // ------------------------------------------------------------------
  // 隐藏态下的触控呼出热区与极简浮动手柄（非笔触触发）
  // ------------------------------------------------------------------

  @Builder
  topProximityZone() {
    Stack({ alignContent: Alignment.Top }) {
      // 触控感知热区 (无色透明，覆盖顶部 52vp)
      Row()
        .width('100%')
        .height(52)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .onTouch((event: TouchEvent) => {
          if (this.isFingerTouch(event)) {
            if (event.type === TouchType.Down || event.type === TouchType.Move) {
              this.toggleBars(true);
            }
          }
        })

      // 居中半透明极简呼出手柄
      Row({ space: 4 }) {
        Text('▾')
          .fontSize(10)
          .fontColor(this.palette().inkSecondary)
        Text('呼出导航栏')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkSecondary)
      }
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor(this.isDarkMode ? 'rgba(30,30,35,0.85)' : 'rgba(255,255,255,0.88)')
      .backdropBlur(12)
      .shadow({ radius: 8, color: 'rgba(0,0,0,0.1)', offsetY: 2 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .margin({ top: 6 })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.toggleBars(true))
    }
    .width('100%')
    .height(52)
    .position({ x: 0, y: 0 })
    .zIndex(50)
  }

  @Builder
  bottomProximityZone() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 触控感知热区 (无色透明，覆盖底部 56vp)
      Row()
        .width('100%')
        .height(56)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .onTouch((event: TouchEvent) => {
          if (this.isFingerTouch(event)) {
            if (event.type === TouchType.Down || event.type === TouchType.Move) {
              this.toggleBars(true);
            }
          }
        })

      // 居中半透明极简控制台唤回手柄
      Row({ space: 6 }) {
        Text('▲')
          .fontSize(10)
          .fontColor(this.palette().inkSecondary)
        Text(`第 ${this.currentPage} / ${this.totalPages} 页 · 呼出控制台`)
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
      }
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.isDarkMode ? 'rgba(30,30,35,0.88)' : 'rgba(255,255,255,0.92)')
      .backdropBlur(12)
      .shadow({ radius: 10, color: 'rgba(0,0,0,0.12)', offsetY: 3 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .margin({ bottom: 12 })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.toggleBars(true))
    }
    .width('100%')
    .height(56)
    .position({ x: 0, y: '100%' })
    .translate({ y: -56 })
    .zIndex(50)
  }

  // ------------------------------------------------------------------
  // 快速页码跳转弹窗
  // ------------------------------------------------------------------

  @Builder
  quickJumpDialog() {
    Column() {
      // 弹窗卡片
      Column({ space: 16 }) {
        Row() {
          Text('快速跳转至指定页')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)

          Blank()

          IconButton({ icon: $r('app.media.ic_close'), label: '关闭页码跳转', onAction: () => { this.jumpDialogOpen = false; } })
        }
        .width('100%')

        // 快速单选页码药丸
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.pageNumbersList(), (pNum: number) => {
            Text(`第 ${pNum} 页`)
              .fontSize(TypographyTokens.CAPTION)
              .fontWeight(this.currentPage === pNum ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentPage === pNum ? '#FFFFFF' : this.palette().inkPrimary)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .margin(4)
              .borderRadius(14)
              .backgroundColor(this.currentPage === pNum ? this.palette().accent : this.palette().surfaceSubtle)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.jumpToPage(pNum))
          }, (pNum: number) => `jump_page_${pNum}`)
        }
        .width('100%')
      }
      .width(320)
      .padding(20)
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 16, color: this.isDarkMode ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.12)', offsetY: 4 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .onClick(() => {
        // 消费卡片点击，防止冒泡到遮罩关闭
      })
      .transition(
        TransitionEffect.scale({ x: AnimationTokens.SCALE_MODAL_ENTER, y: AnimationTokens.SCALE_MODAL_ENTER })
          .combine(TransitionEffect.OPACITY)
          .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
      )
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(0,0,0,0.65)' : 'rgba(0,0,0,0.45)')
    .zIndex(200)
    .transition(
      TransitionEffect.OPACITY
        .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
    )
    .onClick(() => {
      animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
        this.jumpDialogOpen = false;
      });
    })
  }

  // ------------------------------------------------------------------
  // 退出阅读器确认弹窗 (Obsidian 简约高级模态弹窗)
  // ------------------------------------------------------------------

  @Builder
  exitConfirmationDialog() {
    Column() {
      Column({ space: 16 }) {
        Text(this.saveDestination !== 'close' ? '批注尚未保存' : '保存修改后退出？').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).width('100%')
        Text('还有未保存的内容。').fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
        Row({ space: 12 }) {
          Button('继续阅读').height(48).layoutWeight(1).enabled(!this.exitSaving).backgroundColor(this.palette().surfaceSubtle)
            .fontColor(this.palette().inkPrimary).onClick(() => { this.exitDialogOpen = false; })
          Button(this.exitSaving ? '保存中…' : this.saveDestination !== 'close' ? '重试保存' : '保存并退出').height(48).layoutWeight(1).enabled(!this.exitSaving)
            .backgroundColor(this.palette().accent).fontColor(this.palette().onAccent).onClick(() => this.saveAndExit())
        }.width('100%')
      }.width('90%').constraintSize({ maxWidth: 380 }).padding(20).borderRadius(20).backgroundColor(this.palette().surface)
          .onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.4)').zIndex(300)
      .onClick(() => { if (!this.exitSaving) { this.exitDialogOpen = false; } })
  }

  @Builder
  scratchpadSplitPane() {
    Column() {
      // 顶栏：底纹选择与清空
      Row({ space: 8 }) {
        Row() {
          Text('···')
            .fontSize(TypographyTokens.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkMuted)
        }
        .width(36)
        .height(18)
        .justifyContent(FlexAlign.Center)

        Text('随堂演算稿纸')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)

        Blank()

        Row({ space: 4 }) {
          Text('方格')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.paperBackground === 'grid' ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(this.paperBackground === 'grid' ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .onClick(() => { this.paperBackground = 'grid'; })

          Text('横线')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.paperBackground === 'ruled' ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(this.paperBackground === 'ruled' ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .onClick(() => { this.paperBackground = 'ruled'; })

          Text('白纸')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.paperBackground === 'blank' ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(this.paperBackground === 'blank' ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .onClick(() => { this.paperBackground = 'blank'; })
        }

        IconButton({ icon: $r('app.media.ic_close'), label: '关闭稿纸分屏', onAction: () => this.switchSplitMode('none') })
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.palette().surface)
      .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

      // 稿纸手写画布
      Column() {
        HandwritingCanvas({
          note: this.note,
          isScratchpad: true,
          showToolbar: false,
          toolCommand: this.canvasCommand,
          onFocused: () => { this.inkTarget = 'scratchpad'; },
          onShowTools: () => { this.inkTarget = 'scratchpad'; this.penOptionsOpen = true; this.barsVisible = true; },
          onToolStateChange: (state: CanvasToolState) => { this.scratchpadInk = state; },
          paperBackground: this.paperBackground,
          readOnly: !this.isAnnotateMode || this.exitSaving,
          exitSaveToken: this.exitSaveToken,
          onCommitForExit: this.onCommitForExit,
          onExitSaveFinished: (ok: boolean, noteId: string, token: number) => this.exitSaveFinished(ok, noteId, token),
          onDirtyChange: (dirty: boolean) => { this.scratchpadDirty = dirty; },
          onSaved: this.onSaved,
          onSaveStateChange: this.onSaveStateChange
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)
  }

  // ------------------------------------------------------------------
  // 主布局构建
  // ------------------------------------------------------------------

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // ---- 1. 顶部极简导航栏 (单行 48vp)，支持平滑上滑隐藏 ----
        if (this.barsVisible) { this.topNavigationBar() }
        else {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              AppIcon({ source: $r('app.media.ic_chevron_down'), iconSize: 14, tint: this.palette().inkSecondary })
              Text(this.note.title).fontSize(12).fontColor(this.palette().inkSecondary).maxLines(1)
            }
          }.width('100%').height(28).backgroundColor(this.palette().surface).onClick(() => this.toggleBars(true))
        }

        // ---- 2. 主视口区（左文档 + 右分屏）----
        Row() {
          // 左侧主文档 / 试卷 / 稿纸编辑区
          Stack({ alignContent: Alignment.Bottom }) {
            if (this.isHandwritingNote()) {
              // 纯稿纸/白纸手写笔记
              HandwritingCanvas({
                note: this.note,
                isScratchpad: false,
                showToolbar: false,
                toolCommand: this.canvasCommand,
                onFocused: () => { this.inkTarget = 'document'; },
                onShowTools: () => { this.inkTarget = 'document'; this.penOptionsOpen = true; this.barsVisible = true; },
                onToolStateChange: (state: CanvasToolState) => { this.documentInk = state; },
                onToolChange: (tool: string) => { this.whiteboardTool = tool; },
                onContentReady: (ready: boolean) => { this.whiteboardReady = ready; },
                readOnly: !this.isAnnotateMode || this.exitSaving,
                onReadingScroll: (offset: number) => this.handleReadingScroll(offset),
                onBlankTap: () => { if (!this.isAnnotateMode) { this.toggleBars(true); } },
                onDirtyChange: (dirty: boolean) => { this.documentDirty = dirty; },
                exitSaveToken: this.exitSaveToken,
                onCommitForExit: this.onCommitForExit,
                onExitSaveFinished: (ok: boolean, noteId: string, token: number) => this.exitSaveFinished(ok, noteId, token),
                onSaved: this.onSaved,
                onSaveStateChange: this.onSaveStateChange
              })
            } else {
              // PDF / 试卷真题原盘批注
              PdfAnnotatorView({
                note: this.note,
                onRestoreSource: () => this.restorePdfSource(),
                onSourceReady: (ready: boolean) => { this.pdfSourceReady = ready; },
                onAnnotationError: (message: string) => { this.annotationError = message; },
                onReadingScroll: (offset: number) => this.handleReadingScroll(offset),
                onBlankTap: () => { if (!this.isAnnotateMode) { this.toggleBars(true); } },
                onDirtyChange: (dirty: boolean) => { this.documentDirty = dirty; },
                currentPage: this.currentPage,
                onPageChanged: (page: number) => { this.currentPage = page; },
                exitSaveToken: this.exitSaveToken,
                onCommitForExit: this.onCommitForExit,
                onExitSaveFinished: (ok: boolean, noteId: string, token: number) => this.exitSaveFinished(ok, noteId, token),
                barsVisible: this.barsVisible,
                isContinuousScroll: this.isContinuousScroll,
                isAnnotateMode: this.isAnnotateMode && !this.exitSaving,
                currentTool: this.currentTool,
                selectedColor: this.selectedColor,
                selectedWidth: this.selectedWidth,
                eraserWidth: this.eraserWidth,
                eraserMode: this.pdfEraserMode,
                onFocused: () => { this.inkTarget = 'document'; },
                undoTrigger: this.undoTrigger,
                redoTrigger: this.redoTrigger,
                fingerDrawing: this.fingerDrawing,
                onToggleEraser: () => {
                  this.selectPdfTool(this.currentTool === 'eraser' ? this.previousInkTool : 'eraser');
                },
                onShowPenTools: () => { this.inkTarget = 'document'; this.penOptionsOpen = true; this.barsVisible = true; },
                clearTrigger: this.clearTrigger,
                onSaved: this.onSaved,
                onSaveStateChange: this.onSaveStateChange
              })
            }

            // 批注模式下展示灵动悬浮笔盘；阅读模式下展示浮动翻页控制台
            if (!this.isAnnotateMode) {
              this.bottomReadingConsole()
            }
          }
          .layoutWeight(this.splitMode === 'none' || this.isPhone ? 100 : 55)
          .height('100%')
          .animation({ duration: AnimationTokens.DURATION_SPLIT, curve: AnimationTokens.CURVE_STANDARD })

          // 右侧分屏区（平板为左右分屏，手机为全宽滑入式抽屉）
          if (this.splitMode !== 'none') {
            if (!this.isPhone) {
              Divider()
                .vertical(true)
                .strokeWidth(1)
                .color(this.palette().borderSubtle)
                .height('100%')
                .transition(
                  TransitionEffect.OPACITY
                    .animation({ duration: AnimationTokens.DURATION_SPLIT, curve: AnimationTokens.CURVE_STANDARD })
                )
            }

            Column() {
              if (this.splitMode === 'ai') {
                HuaweiAiSplitPanel({
                  onOpenModelSettings: () => {
                    if (this.isAnnotateMode || this.exitSaving || this.documentDirty || this.scratchpadDirty) { this.showToast('请先返回阅读并完成文档保存'); }
                    else { this.onOpenModelSettings(); }
                  },
                  note: this.note,
                  currentPage: this.currentPage,
                  onExtractText: () => {
                    if (this.isAnnotateMode || this.exitSaving || this.documentDirty || this.scratchpadDirty) { this.showToast('请先返回阅读并完成文档保存'); }
                    else { this.onExtractPdfText(this.currentPage); }
                  },
                  onClose: () => {
                    animateTo({ duration: AnimationTokens.DURATION_SPLIT, curve: AnimationTokens.CURVE_STANDARD }, () => {
                      this.splitMode = 'none';
                    });
                  }
                })
              } else if (this.splitMode === 'scratchpad') {
                this.scratchpadSplitPane()
              }
            }
            .layoutWeight(this.isPhone ? undefined : 45)
            .width(this.isPhone ? '100%' : undefined)
            .height('100%')
            .position(this.isPhone ? { x: 0, y: 0 } : undefined)
            .zIndex(this.isPhone ? 40 : 1)
            .backgroundColor(this.palette().surface)
            .transition(
              TransitionEffect.move(TransitionEdge.END)
                .combine(TransitionEffect.OPACITY)
                .animation({ duration: AnimationTokens.DURATION_SPLIT, curve: AnimationTokens.CURVE_STANDARD })
            )
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette().canvas)

      // ---- 3. 灵动悬浮球（在批注模式折叠态或阅读模式下提供一键唤起）----
      if (!this.isAnnotateMode) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.floatingBall()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // ---- 4. 隐藏状态下的顶部/底部感应呼出区域（过滤笔触）----
      if (!this.barsVisible) {
        this.topProximityZone()
        this.bottomProximityZone()
      }

      // ---- 5. 快速页码跳转弹窗 ----
      if (this.jumpDialogOpen) {
        this.quickJumpDialog()
      }

      // ---- 6. 统一顶层操作模态弹窗（另存为、格式转换、长图输出、打印）----
      if (this.activeModal.length > 0) {
        HuaweiDocActionDialog({
          note: this.note,
          dialogType: this.activeModal,
          onClose: () => {
            animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
              this.activeModal = '';
            });
          },
          onConfirm: (actionType: string, payload: string) => {
            this.showToast('当前不支持此导出或转换方式，请保留原文件。');
          }
        })
      }

      // ---- 7. 「··· 更多」功能操作面板 ----

      // ---- 8. 退出阅读器保存确认弹窗 (Obsidian 风格) ----
      if (this.exitDialogOpen) {
        this.exitConfirmationDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)
  }
}
