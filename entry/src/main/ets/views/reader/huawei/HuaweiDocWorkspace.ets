/** 单份 PDF／图片／手写资料的阅读、批注和随堂稿纸。文件分屏由 ReaderSplitWorkspace 协调。 */
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SystemShareService } from '../../../services/SystemShareService';
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../../common/constants/DesignTokens';
import { ReaderTheme } from '../../../common/theme/ReaderTheme';
import { ImageDocumentService } from '../../../services/document/ImageDocumentService';
import { NoteItem } from '../../../common/types/NoteItem';
import { ReaderSaveKind } from '../../../common/types/ReaderSaveKind';
import { CanvasToolState, CanvasToolCommand } from '../../../common/types/CanvasToolState';
import { AnnotationTool } from '../../../common/types/PdfAnnotationTypes';
import { PdfAnnotatorView } from '../pdf/PdfAnnotatorView';
import { InkWidthSlider } from '../../common/InkWidthSlider';
import { InkToolPolicy } from '../../../services/ink/InkToolPolicy';
import { InkShapePolicy } from '../../../services/ink/InkShapePolicy';
import { HandwritingCanvas } from '../HandwritingCanvas';
import { HuaweiDocActionDialog, HuaweiDocDialogType } from './HuaweiDocActionDialog';
import { AppIcon } from '../../common/AppIcon';
import { IconButton } from '../../common/IconButton';
import { DocumentTransferResult } from '../../../common/types/MarkdownDocument';
import { ReaderOutputService } from '../../../services/document/ReaderOutputService';
import { ReadingProgressPolicy } from '../../../services/document/ReadingProgressPolicy';
import { SAVE_IDLE, SAVE_SAVING, SAVE_FAILED } from '../../../common/constants/WorkspaceConstants';

export type SplitModeType = 'none' | 'scratchpad';

@Component
export struct HuaweiDocWorkspace {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop @Watch('handleBackRequest') backRequestToken: number = 0;
  @Prop paneMode: boolean = false;
  @Prop @Watch('saveForHost') hostSaveToken: number = 0;
  onHostSaveFinished: (ok: boolean, noteId: string, token: number) => void = () => {};
  @Prop sourcePage: number = 1;
  @Prop @Watch('onSourceJump') sourceJumpToken: number = 0;
  @Prop documentTabs: NoteItem[] = [];
  @Prop isFreeCanvas: boolean = false;
  onSelectDocument: (id: string) => void = () => {};
  onCloseDocumentTab: (id: string) => void = () => {};
  onCreateHandwriting: () => void = () => {};
  onExtractPdfText: (page: number) => void = () => {};
  onClose: () => void = () => {};
  onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onCommitForExit: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onSmartExtract: () => void = () => {};
  onExportText: (extension: string) => Promise<DocumentTransferResult> = async () => ({ status: 'failed', message: '导出暂不可用' });
  onSearchNotes: () => void = () => {};
  onSaveStateChange: (state: string) => void = () => {};
  onToggleFavorite: (note: NoteItem) => void = () => {};
  onRestorePdfSource: () => Promise<void> = async () => {};
  onReadingPageChange: (noteId: string, page: number, visitedAt: number) => Promise<void> = async () => {};
  private readingTimer: number = -1;
  private pendingReadingPage: number = 0;
  private pendingReadingAt: number = 0;
  private lastRecordedPage: number = 0;
  private readingWrite: Promise<void> = Promise.resolve();
  private readingWritePending: boolean = false;

  private handleBackRequest(): void {
    if (this.shapeOptionsOpen || this.paperOptionsOpen) { this.shapeOptionsOpen = false; this.paperOptionsOpen = false; return; }
    if (this.scratchpadMenuOpen) { this.scratchpadMenuOpen = false; return; }
    if (this.documentMenuOpen) { this.documentMenuOpen = false; return; }
    if (this.activeModal.length > 0) { this.closeOutput(); return; }
    if (this.penOptionsOpen) { this.penOptionsOpen = false; return; }
    if (this.clearDialogOpen) { this.clearDialogOpen = false; return; }
    if (this.jumpDialogOpen) { this.jumpDialogOpen = false; return; }
    if (this.exitDialogOpen) { if (!this.exitSaving) { this.exitDialogOpen = false; } return; }
    if (this.exitSaving || this.restoreSourceBusy) { return; }
    if (this.isAnnotateMode || this.documentDirty || this.scratchpadDirty || this.splitMode !== 'none' ||
      this.pendingReadingPage > 0 || this.readingWritePending) { this.saveDestination = 'close'; this.beginReaderSave(); }
    else { this.onClose(); }
  }

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;


  // 模式与批注状态（鸿蒙笔控设计）
  @State isAnnotateMode: boolean = false;
  @State currentTool: AnnotationTool = 'pen';
  @State selectedColor: string = '#DC2626';
  @State selectedWidth: number = 3;
  private penWidth: number = 3;
  private highlighterWidth: number = 14;
  @State eraserWidth: number = 20;
  private penColor: string = '#DC2626';
  private highlighterColor: string = '#FACC15';
  @State inkTarget: string = 'document';
  @State documentInk: CanvasToolState = { tool: 'pen', width: 3, color: '#1C1917', fingerDrawing: true, eraserMode: 'area' };
  @State scratchpadInk: CanvasToolState = { tool: 'pen', width: 3, color: '#1C1917', fingerDrawing: true, eraserMode: 'area' };
  @State canvasCommand: CanvasToolCommand = { sequence: 0, target: '', action: '', value: '' };
  @State pdfEraserMode: string = 'area';
  private requestedInkTool: AnnotationTool = 'pen';
  private documentInkTool: string = 'pen';
  private scratchpadInkTool: string = 'pen';
  @State documentMenuOpen: boolean = false;
  @State scratchpadMenuOpen: boolean = false;
  private clearInkTarget: string = 'document';
  @State undoTrigger: number = 0;
  @State redoTrigger: number = 0;
  @State fingerDrawing: boolean = true;
  private previousInkTool: AnnotationTool = 'pen';
  @State clearTrigger: number = 0;
  @State exitDialogOpen: boolean = false;
  @State exitSaving: boolean = false;
  @State exitSaveToken: number = 0;
  // Dirty flags are read by exit/save decisions, never rendered. Keeping them out of @State
  // prevents the whole reader tree from rebuilding on every autosave transition.
  private documentDirty: boolean = false;
  private scratchpadDirty: boolean = false;
  private exitPending: number = 0;
  private exitFailed: boolean = false;
  private completedSaveAreas: Set<string> = new Set();
  private expectedSaveAreas: Set<string> = new Set();
  private scratchpadState: string = SAVE_IDLE;
  @State private saveDestination: string = 'close';
  @State private restoreSourceBusy: boolean = false;
  @State private pdfSourceReady: boolean = false;
  private whiteboardReady: boolean = false;
  private annotationError: string = '';
  private nextSplitMode: SplitModeType = 'none';
  private loadedNoteId: string = '';

  // 导航与功能区状态
  @State splitMode: SplitModeType = 'none';
  @State activeModal: HuaweiDocDialogType = '';
  @State outputBusy: boolean = false;
  @State outputMessage: string = '';
  @State outputFailed: boolean = false;
  private documentSaveState: string = '已保存';
  private pendingOutput: HuaweiDocDialogType = '';
  private pendingDocumentId: string = '';
  @State private clearDialogOpen: boolean = false;
  @State private colorInput: string = '';

  // 页码与阅读控制
  @State currentPage: number = 1;
  @State totalPages: number = 1;
  @State isContinuousScroll: boolean = true;
  @State penOptionsOpen: boolean = false;
  @State shapeOptionsOpen: boolean = false;
  @State paperOptionsOpen: boolean = false;
  @State jumpDialogOpen: boolean = false;
  @State jumpPageInput: string = '';
  @State pageOverviewOpen: boolean = false;
  @State annotationMoreOpen: boolean = false;

  // 轻量提示
  private toastText: string = '';
  private toastOpen: boolean = false;

  private palette(): ColorPalette {
    return ReaderTheme.palette(this.isDarkMode, this.themeStyle);
  }

  private onSourceJump(): void {
    this.rememberReadingPage(Math.max(1, Math.min(this.totalPages, this.sourcePage)));
  }

  private rememberReadingPage(page: number): void {
    this.currentPage = page;
    if (this.isFreeCanvas || this.isHandwritingNote() || page === this.lastRecordedPage) { return; }
    this.lastRecordedPage = page; this.pendingReadingPage = page; this.pendingReadingAt = Date.now();
    if (this.readingTimer !== -1) { clearTimeout(this.readingTimer); }
    this.readingTimer = setTimeout(() => {
      this.readingTimer = -1;
      this.flushReadingProgress().catch(() => this.showToast('阅读位置未能保存，请重试'));
    }, 600);
  }

  private flushReadingProgress(): Promise<void> {
    if (this.readingTimer !== -1) { clearTimeout(this.readingTimer); this.readingTimer = -1; }
    const page = this.pendingReadingPage;
    if (page <= 0) { return this.readingWrite; }
    const id = this.loadedNoteId;
    const visitedAt = this.pendingReadingAt;
    this.pendingReadingPage = 0;
    this.readingWritePending = true;
    const request = this.readingWrite.catch(() => {}).then(() => this.onReadingPageChange(id, page, visitedAt));
    this.readingWrite = request;
    return request.then(() => { if (this.readingWrite === request) { this.readingWritePending = false; } }).catch(() => {
      if (this.readingWrite === request) { this.readingWritePending = false; }
      if (this.loadedNoteId === id && this.pendingReadingPage === 0 && this.lastRecordedPage === page) {
        this.pendingReadingPage = page; this.pendingReadingAt = visitedAt; this.lastRecordedPage = 0;
      }
      throw new Error('阅读位置保存失败');
    });
  }

  aboutToDisappear(): void {
    this.flushReadingProgress().catch(() => this.onSaveStateChange('阅读位置保存失败'));
  }

  aboutToAppear(): void {
    this.loadedNoteId = this.note.id;
    this.lastRecordedPage = this.note.readPage || 0;
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
    this.flushReadingProgress().catch(() => this.onSaveStateChange('阅读位置保存失败'));
    this.loadedNoteId = this.note.id;
    this.lastRecordedPage = this.note.readPage || 0;
    this.activeModal = ''; this.documentMenuOpen = false; this.scratchpadMenuOpen = false; this.inkTarget = 'document';
    this.outputBusy = false; this.outputMessage = ''; this.pendingOutput = '';
    this.jumpDialogOpen = false;
    this.penOptionsOpen = false; this.shapeOptionsOpen = false; this.paperOptionsOpen = false; this.clearDialogOpen = false;
    this.documentDirty = false; this.scratchpadDirty = false; this.isAnnotateMode = false;
    this.pdfSourceReady = false; this.whiteboardReady = false; this.annotationError = '';
    this.exitDialogOpen = false; this.splitMode = 'none';
    this.documentSaveState = SAVE_IDLE; this.scratchpadState = SAVE_IDLE;
    this.exitSaving = false; this.exitPending = 0;
    this.totalPages = this.isImageDocument() || this.isHandwritingNote() ? 1 :
      this.note.pageCount && this.note.pageCount > 0 ? this.note.pageCount : 1;
    this.currentPage = ReadingProgressPolicy.page(this.note);
  }


  private updateAreaState(area: string, state: string): void {
    if (area === 'document') { this.documentSaveState = state; }
    else if (area === 'scratchpad') { this.scratchpadState = state; }
    const states: string[] = [this.documentSaveState];
    if (this.splitMode === 'scratchpad') { states.push(this.scratchpadState); }
    const failure = states.find((value: string) => value !== SAVE_IDLE && value !== SAVE_SAVING);
    this.onSaveStateChange(this.exitSaving ? SAVE_SAVING : failure || (states.includes(SAVE_SAVING) ? SAVE_SAVING : SAVE_IDLE));
  }




  private returnToReading(): void {
    if (this.exitSaving || !this.isAnnotateMode) { return; }
    this.isAnnotateMode = false;
    this.penOptionsOpen = false;
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
      this.showToast(this.isImageDocument() ? '请等待图片读入；读取失败时请重试或重新导入' :
        this.note.sourceUri ? '请等待页面读取；读取失败时请重新关联原 PDF' : '请先重新关联这份资料的原 PDF'); return;
    }
    this.inkTarget = 'document';
    if (!this.isHandwritingNote() && this.currentTool === 'pan') { this.selectPdfTool('pen'); }
    this.isAnnotateMode = true;
  }

  private beginReaderSave(): void {
    if (this.exitSaving) { return; }
    this.exitSaving = true;
    this.isAnnotateMode = false;
    this.expectedSaveAreas = new Set(['document']);
    if (this.splitMode === 'scratchpad') { this.expectedSaveAreas.add('scratchpad'); }
    this.exitPending = this.expectedSaveAreas.size;
    this.completedSaveAreas = new Set(); this.exitFailed = false;
    this.onSaveStateChange(SAVE_SAVING);
    if (this.pendingReadingPage > 0 || this.readingWritePending) {
      this.exitPending++; this.expectedSaveAreas.add('progress');
      const id = this.loadedNoteId; const token = this.exitSaveToken + 1;
      this.flushReadingProgress().then(() => this.exitSaveFinished(true, id, token, 'progress'))
        .catch(() => this.exitSaveFinished(false, id, token, 'progress'));
    }
    this.exitSaveToken++;
  }

  private saveForHost(): void {
    if (this.exitSaving || this.restoreSourceBusy || this.outputBusy) { this.onHostSaveFinished(false, this.note.id, this.hostSaveToken); return; }
    this.saveDestination = 'host'; this.beginReaderSave();
  }

  private exitSaveFinished(ok: boolean, noteId: string, requestToken: number, area: string): void {
    if (noteId !== this.loadedNoteId || requestToken !== this.exitSaveToken) { return; }
    if (!this.exitSaving || this.exitPending <= 0) { return; }
    if (!this.expectedSaveAreas.has(area) || this.completedSaveAreas.has(area)) { return; }
    this.completedSaveAreas.add(area);
    this.exitFailed = this.exitFailed || !ok; this.exitPending--;
    if (this.exitPending > 0) { return; }
    this.exitSaving = false;
    if (this.exitFailed) {
      this.exitDialogOpen = this.saveDestination !== 'host';
      this.onSaveStateChange(SAVE_FAILED);
      if (this.saveDestination === 'host') { this.onHostSaveFinished(false, this.note.id, this.hostSaveToken); return; }
      this.showToast('保存失败，内容仍保留，请重试');
    } else {
      this.exitDialogOpen = false;
      this.documentDirty = false; this.scratchpadDirty = false;
      this.documentSaveState = SAVE_IDLE; this.scratchpadState = SAVE_IDLE;
      this.onSaveStateChange(SAVE_IDLE);
      if (this.saveDestination === 'host') { this.onHostSaveFinished(true, this.note.id, this.hostSaveToken); }
      else if (this.saveDestination === 'close') { this.onClose(); }
      else if (this.saveDestination === 'split') {
        this.splitMode = this.nextSplitMode; this.inkTarget = 'document';
      }
      else if (this.saveDestination === 'output') { this.activeModal = this.pendingOutput; this.pendingOutput = ''; }
      else if (this.saveDestination === 'tab') { this.onSelectDocument(this.pendingDocumentId); }
      else if (this.saveDestination === 'closeTab') { this.onCloseDocumentTab(this.pendingDocumentId); }
      else if (this.saveDestination === 'new') { this.onCreateHandwriting(); }
      else if (this.saveDestination === 'search') { this.onSearchNotes(); }
      else if (this.saveDestination === 'extract') { this.onSmartExtract(); }
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
    this.scratchpadMenuOpen = false;
    if (this.exitSaving || this.restoreSourceBusy || this.splitMode === mode) { return; }
    if (this.splitMode !== 'none') {
      this.nextSplitMode = mode;
      this.saveDestination = 'split';
      this.beginReaderSave();
      return;
    }
    this.splitMode = mode;
  }

  private openSearch(): void {
    if (this.exitSaving || this.restoreSourceBusy || this.outputBusy) { return; }
    this.penOptionsOpen = false;
    this.saveDestination = 'search';
    if (this.isAnnotateMode || this.documentDirty || this.scratchpadDirty || this.pendingReadingPage > 0 || this.readingWritePending) { this.beginReaderSave(); }
    else { this.onSearchNotes(); }
  }

  private openSmartExtract(): void {
    if (this.exitSaving || this.restoreSourceBusy || this.outputBusy) { return; }
    this.penOptionsOpen = false;
    this.saveDestination = 'extract';
    if (this.isAnnotateMode || this.documentDirty || this.scratchpadDirty || this.pendingReadingPage > 0 || this.readingWritePending) { this.beginReaderSave(); }
    else { this.onSmartExtract(); }
  }

  /** 是否为 PDF / Word 试卷或参考资料 */
  private isDocumentOrExam(): boolean {
    const t = this.note.type.toLowerCase();
    const cat = this.note.category;
    return this.note.sourceType === 'pdf' || t === 'pdf' || t === 'doc' || t === 'docx' || cat === '试卷题库' || this.note.id === 'note-seed-exam' || this.note.id === 'note-seed-pdf';
  }

  private isImageDocument(): boolean {
    return this.note.sourceType === 'image' || this.note.type.toLowerCase() === 'image';
  }

  private requestDocument(id: string, close: boolean = false): void {
    if (this.exitSaving || this.outputBusy || this.restoreSourceBusy) { return; }
    if (id !== this.note.id && close) { this.onCloseDocumentTab(id); return; }
    if (id === this.note.id && !close) { return; }
    this.penOptionsOpen = false;
    this.pendingDocumentId = id;
    this.saveDestination = close ? 'closeTab' : 'tab';
    if (this.documentDirty || this.scratchpadDirty || this.isAnnotateMode || this.pendingReadingPage > 0 || this.readingWritePending) { this.beginReaderSave(); }
    else if (close) { this.onCloseDocumentTab(id); }
    else { this.onSelectDocument(id); }
  }

  private createDocument(): void {
    if (this.exitSaving || this.outputBusy || this.restoreSourceBusy) { return; }
    this.saveDestination = 'new';
    if (this.documentDirty || this.scratchpadDirty || this.isAnnotateMode || this.pendingReadingPage > 0 || this.readingWritePending) { this.beginReaderSave(); }
    else { this.onCreateHandwriting(); }
  }

  /** 是否为纯稿纸/白纸手写型笔记 */
  private isHandwritingNote(): boolean {
    const t = this.note.type.toLowerCase();
    return t === 'canvas' || t === '白板' || t === '白纸笔记' || t === 'handwriting' || t === '稿纸';
  }


  /** 跳转指定页码 */
  private jumpToPage(page: number): void {
    const p = Math.max(1, Math.min(this.totalPages, Math.round(page)));
    this.rememberReadingPage(p);
    animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
      this.jumpDialogOpen = false;
    });
    this.showToast(`已跳转至第 ${this.currentPage} 页`);
  }

  private pageNumbers(): number[] {
    const pages: number[] = [];
    for (let page = 1; page <= this.totalPages; page++) { pages.push(page); }
    return pages;
  }

  @Builder
  pageOverviewPanel() {
    Column({ space: 14 }) {
      Row() {
        Text('页面总览').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1)
        Text(`${this.currentPage} / ${this.totalPages}`).fontSize(12).fontColor(this.palette().inkMuted)
      }.width('100%')
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.pageNumbers(), (page: number) => {
            Button(`${page}`, { type: ButtonType.Normal }).width(48).height(44).fontSize(12)
              .fontColor(page === this.currentPage ? this.palette().accent : this.palette().inkSecondary)
              .backgroundColor(page === this.currentPage ? this.palette().accentSoft : this.palette().surfaceSubtle)
              .border({ width: 1, color: page === this.currentPage ? this.palette().accent : this.palette().borderSubtle, radius: 8 })
              .margin({ right: 6, bottom: 6 })
              .accessibilityText(`跳转到第 ${page} 页`)
              .onClick(() => { this.jumpToPage(page); this.pageOverviewOpen = false; })
          }, (page: number) => String(page))
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 320 }).scrollBar(BarState.Auto)
    }.padding(18).width(320).alignItems(HorizontalAlign.Start)
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
  // 顶栏构建：退出、标题勋章、模式分段（阅读/批注）、分屏胶囊、更多
  // ------------------------------------------------------------------


  @Builder
  topNavigationBar() {
    Column() {
      if (!this.paneMode) {
      Row({ space: 4 }) {
        if (!this.paneMode) { IconButton({ icon: $r('app.media.ic_back'), label: '返回资料库', compact: true, onAction: () => this.handleBackRequest() }) }
        if (this.isFreeCanvas) {
          Blank()
        } else {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.documentTabs.length > 0 ? this.documentTabs : [this.note], (document: NoteItem) => {
              Row({ space: 2 }) {
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 7 }) {
                    AppIcon({ source: document.sourceType === 'image' ? $r('app.media.ic_cover') : document.type === 'Handwriting' ? $r('app.media.ic_pen') : $r('app.media.ic_pdf'), iconSize: 16,
                      tint: document.id === this.note.id ? this.palette().accent : this.palette().inkMuted })
                    Text(document.title).fontSize(13).fontWeight(document.id === this.note.id ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor(this.palette().inkPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: this.isPhone ? 120 : 172 })
                  }
                }.height(44).padding({ left: 12, right: 4 }).backgroundColor(Color.Transparent)
                  .accessibilityText(`打开资料 ${document.title}`).onClick(() => this.requestDocument(document.id))
                Button({ type: ButtonType.Normal }) {
                  AppIcon({ source: $r('app.media.ic_close'), iconSize: 13, tint: this.palette().inkMuted })
                }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).accessibilityText(`关闭标签 ${document.title}`)
                  .onClick(() => this.requestDocument(document.id, true))
              }.borderRadius({ topLeft: 5, topRight: 5 }).backgroundColor(document.id === this.note.id ? this.palette().hoverBg : Color.Transparent)
                .border({ width: { bottom: document.id === this.note.id ? 2 : 0 }, color: this.palette().inkPrimary })
            }, (document: NoteItem) => document.id)
          }
        }.layoutWeight(1).height(48).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start).id('reader-tabs')
        }
        if (!this.isPhone && !this.isFreeCanvas && !this.paneMode) {
          IconButton({ icon: $r('app.media.ic_plus'), label: '新建手写笔记', onAction: () => this.createDocument() })
          IconButton({ icon: $r('app.media.ic_search'), label: '搜索资料', onAction: () => this.openSearch() })
        }
        this.documentActions()
      }.width('100%').height(52).backgroundColor(this.palette().canvas)
      }
      this.annotationToolbar()
    }.width('100%').padding({ left: this.isPhone ? 4 : 12, right: this.isPhone ? 4 : 12 }).backgroundColor(this.palette().surface)
      .border({ width: { bottom: 1 }, color: this.palette().borderSubtle })
  }

  @Builder
  documentActions() {
        if (!this.paneMode && !this.isPhone) {
          IconButton({ icon: $r('app.media.ic_screenshot'), label: '保存正文截图', onAction: () => this.openOutput('export_image') })
        }
        if (!this.paneMode) {
        IconButton({ icon: $r('app.media.ic_export'), label: this.isImageDocument() ? '导出原始图片' : this.isHandwritingNote() ? '导出手写截图' : '导出笔记文字',
          onAction: () => this.openOutput(this.isImageDocument() ? 'export_original' : this.isHandwritingNote() ? 'export_image' : 'export_text') })
        }
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_more'), tint: this.palette().inkSecondary })
        }.width(44).height(44).padding(0).borderRadius(5).backgroundColor(Color.Transparent).accessibilityText('更多文档操作')
          .enabled(!this.exitSaving && !this.restoreSourceBusy).onClick(() => { this.documentMenuOpen = !this.documentMenuOpen; })
          .bindMenu(this.documentMenuOpen, this.documentMenu, { onDisappear: () => { this.documentMenuOpen = false; } })
  }

  // ------------------------------------------------------------------
  // 笔工具的二级参数面板
  // ------------------------------------------------------------------

  private usesCanvasTools(): boolean { return this.inkTarget === 'scratchpad' || this.isHandwritingNote(); }
  private canvasState(): CanvasToolState { return this.inkTarget === 'scratchpad' ? this.scratchpadInk : this.documentInk; }
  private activeTool(): string { return this.usesCanvasTools() ? this.canvasState().tool : this.currentTool; }
  private activeWidth(): number { return this.usesCanvasTools() ? this.canvasState().width : this.currentTool === 'eraser' ? this.eraserWidth : this.selectedWidth; }
  private activeColor(): string { return this.usesCanvasTools() ? this.canvasState().color : this.selectedColor; }
  private activeFingerDrawing(): boolean { return this.usesCanvasTools() ? this.canvasState().fingerDrawing : this.fingerDrawing; }
  private activeEraserMode(): string { return this.usesCanvasTools() ? this.canvasState().eraserMode : this.pdfEraserMode; }
  private inkColors(): string[] {
    return [this.usesCanvasTools() && this.isDarkMode ? '#F5F5F4' : '#1C1917', '#2563EB', '#DC2626', '#E89B2C', '#059669', '#8B5EC9', '#EAB308', '#78849A'];
  }

  private sendCanvasCommand(action: string, value: string = ''): void {
    if ((!this.isAnnotateMode && action !== 'resetView') || this.exitSaving || this.restoreSourceBusy) { return; }
    this.canvasCommand = { sequence: this.canvasCommand.sequence + 1, target: this.inkTarget, action, value };
  }
  private prepareInkAction(): boolean {
    const target = this.inkTarget;
    if (!this.isAnnotateMode) { this.setAnnotationMode(true); }
    if (!this.isAnnotateMode || this.exitSaving || this.restoreSourceBusy) { return false; }
    this.inkTarget = target; return true;
  }
  private selectInkTool(tool: AnnotationTool): void {
    if (!this.isAnnotateMode || this.exitSaving) { return; }
    this.requestedInkTool = tool;
    if (this.activeTool() !== tool) { this.penOptionsOpen = false; }
    if (this.usesCanvasTools()) {
      const target = this.inkTarget;
      this.sendCanvasCommand(tool);
      if (target === 'scratchpad') { this.scratchpadInkTool = tool; } else { this.documentInkTool = tool; }
    }
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
    if ((value !== 'area' && value !== 'stroke') || !this.isAnnotateMode || this.exitSaving || this.restoreSourceBusy) { return; }
    if (this.usesCanvasTools()) { this.sendCanvasCommand('eraserMode', value); }
    else { this.pdfEraserMode = value; }
  }
  private undoInk(): void { if (this.usesCanvasTools()) { this.sendCanvasCommand('undo'); } else { this.undoTrigger++; } }
  private redoInk(): void { if (this.usesCanvasTools()) { this.sendCanvasCommand('redo'); } else { this.redoTrigger++; } }
  private toggleInkFinger(): void { if (this.usesCanvasTools()) { this.sendCanvasCommand('finger'); } else { this.fingerDrawing = !this.fingerDrawing; } }
  private selectPdfTool(tool: AnnotationTool): void {
    if (this.exitSaving || this.restoreSourceBusy) { return; }
    this.requestedInkTool = tool;
    if (this.currentTool === 'pen' || InkShapePolicy.isShape(this.currentTool)) { this.penColor = this.selectedColor; this.penWidth = this.selectedWidth; }
    if (this.currentTool === 'highlighter') { this.highlighterColor = this.selectedColor; this.highlighterWidth = this.selectedWidth; }
    if (tool === 'eraser' && this.currentTool !== 'eraser') { this.previousInkTool = this.currentTool === 'highlighter' ? 'highlighter' : 'pen'; }
    this.currentTool = tool;
    if (tool === 'pen' || InkShapePolicy.isShape(tool)) { this.selectedColor = this.penColor; this.selectedWidth = this.penWidth; }
    if (tool === 'highlighter') { this.selectedColor = this.highlighterColor; this.selectedWidth = this.highlighterWidth; }
  }

  /** Apply the last user-selected tool to the canvas that actually receives the next stroke. */
  private ensureCanvasTool(target: string): void {
    if (!this.isAnnotateMode || this.exitSaving || this.restoreSourceBusy) { return; }
    if (target === 'scratchpad') {
      if (this.scratchpadInkTool === this.requestedInkTool) { return; }
      this.inkTarget = 'scratchpad'; this.sendCanvasCommand(this.requestedInkTool); this.scratchpadInkTool = this.requestedInkTool;
      return;
    }
    if (this.isHandwritingNote()) {
      if (this.documentInkTool === this.requestedInkTool) { return; }
      this.inkTarget = 'document'; this.sendCanvasCommand(this.requestedInkTool); this.documentInkTool = this.requestedInkTool;
      return;
    }
    if (this.currentTool !== this.requestedInkTool) { this.inkTarget = 'document'; this.selectPdfTool(this.requestedInkTool); }
  }
  private changePdfWidth(value: number): void {
    if (this.currentTool === 'eraser') { this.eraserWidth = InkToolPolicy.width('eraser', value); }
    else if (this.currentTool !== 'pan') { this.selectedWidth = InkToolPolicy.width(this.currentTool, value); }
  }

  private openToolSettings(tool: AnnotationTool): void {
    if (tool === 'pan' || !this.prepareInkAction()) { return; }
    this.selectInkTool(tool);
    this.colorInput = this.activeColor().toUpperCase();
    this.penOptionsOpen = true;
  }

  private applyHexColor(): void {
    const value = this.colorInput.trim();
    if (!/^#?[0-9a-fA-F]{6}$/.test(value)) { this.showToast('请输入 6 位颜色值'); return; }
    const color = (value.startsWith('#') ? value : '#' + value).toUpperCase();
    this.colorInput = color;
    this.changeInkColor(color);
  }

  private widthPresets(): number[] {
    return this.activeTool() === 'highlighter' ? [6, 10, 14, 22, 32] : [1, 2, 3, 6, 12];
  }

  private requestClearInk(): void {
    if (!this.isAnnotateMode || this.exitSaving) { return; }
    this.penOptionsOpen = false;
    this.clearInkTarget = this.inkTarget;
    this.clearDialogOpen = true;
  }

  private confirmClearInk(): void {
    if (!this.isAnnotateMode || this.exitSaving) { return; }
    this.clearDialogOpen = false;
    this.inkTarget = this.clearInkTarget;
    if (this.usesCanvasTools()) { this.sendCanvasCommand('clearConfirmed'); }
    else { this.clearCurrentPageAnnotations(); }
  }

  @Builder
  toolButton(tool: AnnotationTool, icon: Resource, label: string) {
    Button({ type: ButtonType.Normal }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        AppIcon({ source: icon, iconSize: 23, tint: this.isAnnotateMode && this.activeTool() === tool ? this.palette().accent : this.palette().inkPrimary })
        if (tool === 'eraser') {
          Text(this.activeEraserMode() === 'area' ? '区' : '笔')
            .fontSize(8).fontColor(this.palette().inkMuted).padding({ left: 2, right: 1 })
        }
      }.width(28).height(28)
    }.width(44).height(44).padding(0).borderRadius(5)
      .id(`ink-tool-${tool}`)
      .backgroundColor(this.isAnnotateMode && this.activeTool() === tool ? this.palette().accentSoft : Color.Transparent)
      .enabled(!this.exitSaving && !this.restoreSourceBusy)
      .accessibilityText(label).accessibilityDescription('轻触进入批注并选择，双击打开设置')
      .bindTips(label)
      .onClick(() => { if (this.prepareInkAction()) { this.selectInkTool(tool); } })
      .parallelGesture(TapGesture({ count: 2, fingers: 1 }).onAction(() => this.openToolSettings(tool)))
      .bindPopup(this.penOptionsOpen && this.isAnnotateMode && this.activeTool() === tool, {
        builder: this.penSettingsPanel, placement: Placement.Bottom, popupColor: this.palette().surface,
        radius: 8, shadow: { radius: 16, color: 'rgba(0,0,0,0.10)', offsetY: 4 },
        onStateChange: (event) => { if (!event.isVisible) { this.penOptionsOpen = false; } }
      })
  }

  @Builder
  annotationOverflowMenu() {
    Menu() {
      MenuItem({ content: '图形工具' }).onClick(() => { this.penOptionsOpen = false; this.shapeOptionsOpen = true; })
      if (this.usesCanvasTools()) {
        MenuItem({ content: '纸张与视图' }).onClick(() => { this.penOptionsOpen = false; this.paperOptionsOpen = true; })
      }
      MenuItem({ content: '页面总览' }).enabled(this.totalPages > 1).onClick(() => { this.pageOverviewOpen = true; })
      MenuItem({ content: this.usesCanvasTools() ? '清空当前稿纸笔迹' : '清空本页笔迹' })
        .enabled(this.isAnnotateMode && !this.exitSaving).onClick(() => this.requestClearInk())
    }
  }

  @Builder
  annotationToolbar() {
    Row({ space: 2 }) {
      Scroll() {
        Row({ space: this.isPhone ? 0 : 4 }) {
          Button({ type: ButtonType.Normal }) { AppIcon({ source: $r('app.media.ic_undo'), tint: this.palette().inkSecondary }) }
            .width(44).height(44).padding(0).backgroundColor(Color.Transparent).enabled(this.isAnnotateMode && !this.exitSaving)
            .opacity(this.isAnnotateMode ? 1 : 0.65).accessibilityText('撤销当前批注').id('reader-undo').onClick(() => this.undoInk())
          Button({ type: ButtonType.Normal }) { AppIcon({ source: $r('app.media.ic_redo'), tint: this.palette().inkSecondary }) }
            .width(44).height(44).padding(0).backgroundColor(Color.Transparent).enabled(this.isAnnotateMode && !this.exitSaving)
            .opacity(this.isAnnotateMode ? 1 : 0.65).accessibilityText('重做当前批注').id('reader-redo').onClick(() => this.redoInk())
          Divider().vertical(true).height(22).color(this.palette().borderSubtle).margin({ left: 5, right: 5 })
          this.toolButton('pen', $r('app.media.ic_pen'), '普通笔')
          this.toolButton('highlighter', $r('app.media.ic_highlighter'), '荧光笔')
          this.toolButton('eraser', $r('app.media.ic_eraser'), '橡皮')
          if (this.activeTool() === 'eraser') {
            Button((this.activeEraserMode() === 'area' ? '区域擦除' : '笔画擦除') + ' ▾', { type: ButtonType.Normal })
              .height(44).padding({ left: 10, right: 10 }).borderRadius(5).fontSize(12)
              .fontColor(this.palette().inkSecondary).backgroundColor(this.palette().surfaceSubtle)
              .enabled(!this.exitSaving && !this.restoreSourceBusy).accessibilityText('选择橡皮擦除方式')
              .onClick(() => this.openToolSettings('eraser'))
          }
          Button({ type: ButtonType.Normal }) {
            AppIcon({ source: $r('app.media.ic_hand'), tint: !this.isAnnotateMode || this.activeTool() === 'pan' ? this.palette().accent : this.palette().inkSecondary })
          }.width(44).height(44).padding(0).borderRadius(5).enabled(!this.exitSaving)
            .backgroundColor(!this.isAnnotateMode || this.activeTool() === 'pan' ? this.palette().accentSoft : Color.Transparent)
            .accessibilityText('拖动页面').onClick(() => { if (this.isAnnotateMode) { this.selectInkTool('pan'); } })
          Button({ type: ButtonType.Normal }) {
            AppIcon({ source: $r('app.media.ic_shape'), iconSize: 23, tint: this.isAnnotateMode && InkShapePolicy.isShape(this.activeTool()) ? this.palette().accent : this.palette().inkPrimary })
          }.width(44).height(44).padding(0).borderRadius(5).id('ink-shapes')
            .enabled(!this.exitSaving && !this.restoreSourceBusy).accessibilityText('图形工具')
            .backgroundColor(this.isAnnotateMode && InkShapePolicy.isShape(this.activeTool()) ? this.palette().accentSoft : Color.Transparent)
            .onClick(() => { this.penOptionsOpen = false; this.paperOptionsOpen = false; this.shapeOptionsOpen = !this.shapeOptionsOpen; })
            .bindPopup(this.shapeOptionsOpen, { builder: this.shapeSettingsPanel, placement: Placement.Bottom,
              popupColor: this.palette().surface, radius: 8, shadow: { radius: 16, color: 'rgba(0,0,0,0.10)', offsetY: 4 },
              onStateChange: (event) => { if (!event.isVisible) { this.shapeOptionsOpen = false; } } })
          if (this.splitMode === 'scratchpad') {
            Divider().vertical(true).height(22).color(this.palette().borderSubtle).margin({ left: 6, right: 6 })
            Button('正文', { type: ButtonType.Normal }).height(44).fontSize(12)
              .backgroundColor(this.inkTarget === 'document' ? this.palette().accentSoft : Color.Transparent).fontColor(this.palette().inkPrimary)
              .accessibilityText('操作正文批注').onClick(() => { this.penOptionsOpen = false; this.inkTarget = 'document'; })
            Button('稿纸', { type: ButtonType.Normal }).height(44).fontSize(12)
              .backgroundColor(this.inkTarget === 'scratchpad' ? this.palette().accentSoft : Color.Transparent).fontColor(this.palette().inkPrimary)
              .accessibilityText('操作随堂稿纸').onClick(() => { this.penOptionsOpen = false; this.inkTarget = 'scratchpad'; })
          }
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1).height(52).align(Alignment.Start).id('reader-ink-tools')
      if (this.usesCanvasTools()) {
        Button({ type: ButtonType.Normal }) { AppIcon({ source: $r('app.media.ic_page'), tint: this.palette().inkPrimary }) }
          .width(44).height(44).padding(0).borderRadius(5).id('ink-paper').backgroundColor(Color.Transparent)
          .enabled(!this.exitSaving && !this.restoreSourceBusy).accessibilityText('纸张与视图')
          .onClick(() => { this.penOptionsOpen = false; this.shapeOptionsOpen = false; this.paperOptionsOpen = !this.paperOptionsOpen; })
          .bindPopup(this.paperOptionsOpen, { builder: this.paperSettingsPanel, placement: Placement.Bottom,
            popupColor: this.palette().surface, radius: 8, shadow: { radius: 16, color: 'rgba(0,0,0,0.10)', offsetY: 4 },
            onStateChange: (event) => { if (!event.isVisible) { this.paperOptionsOpen = false; } } })
      }
      if (!this.isPhone) {
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_split'), tint: this.splitMode === 'scratchpad' ? this.palette().accent : this.palette().inkSecondary })
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).accessibilityText('切换随堂稿纸')
          .enabled(!this.exitSaving).onClick(() => this.switchSplitMode(this.splitMode === 'scratchpad' ? 'none' : 'scratchpad'))
      }
      Divider().vertical(true).height(22).color(this.palette().borderSubtle).margin({ left: 4, right: 4 })
      if (this.isPhone) {
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_more'), iconSize: 20, tint: this.palette().inkSecondary })
        }.width(44).height(44).padding(0).borderRadius(5).backgroundColor(Color.Transparent)
          .accessibilityText('更多批注工具')
          .onClick(() => { this.annotationMoreOpen = !this.annotationMoreOpen; })
          .bindMenu(this.annotationMoreOpen, this.annotationOverflowMenu, {
            onDisappear: () => { this.annotationMoreOpen = false; }
          })
      }
      if (this.totalPages > 1) {
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_list'), iconSize: 20, tint: this.palette().inkSecondary })
        }.width(44).height(44).padding(0).borderRadius(5).backgroundColor(Color.Transparent)
          .accessibilityText('页面总览')
          .onClick(() => { this.pageOverviewOpen = !this.pageOverviewOpen; })
          .bindPopup(this.pageOverviewOpen, {
            builder: this.pageOverviewPanel, placement: Placement.Bottom, popupColor: this.palette().surface,
            radius: 18, shadow: { radius: 16, color: 'rgba(0,0,0,0.10)', offsetY: 4 },
            onStateChange: (event) => { if (!event.isVisible) { this.pageOverviewOpen = false; } }
          })
      }
      if (this.paneMode) { this.documentActions() }
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          AppIcon({ source: this.isAnnotateMode ? $r('app.media.ic_unlock') : $r('app.media.ic_lock'), iconSize: 20, tint: this.palette().accent })
          if (!this.isPhone) {
            Text(this.exitSaving ? '保存中' : this.isAnnotateMode ? '可批注' : '只读').fontSize(12).fontColor(this.palette().inkPrimary)
          }
        }
      }.height(44).width(this.isPhone ? 44 : undefined).constraintSize({ minWidth: 44 }).padding({ left: 10, right: 10 }).borderRadius(5).backgroundColor(Color.Transparent)
        .accessibilityText(this.isAnnotateMode ? '锁定只读并保存批注' : '解锁批注').enabled(!this.exitSaving && !this.restoreSourceBusy)
        .id('ink-mode-toggle')
        .onClick(() => this.setAnnotationMode(!this.isAnnotateMode))
    }.width('100%').height(54).backgroundColor(this.palette().surface)
  }

  @Builder
  shapeOption(tool: AnnotationTool, icon: Resource, label: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 10 }) {
        AppIcon({ source: icon, iconSize: 26, tint: this.activeTool() === tool ? this.palette().accent : this.palette().inkPrimary })
        Text(label).fontSize(12).fontColor(this.palette().inkSecondary)
      }.width('100%').height('100%').justifyContent(FlexAlign.Center)
    }.width(60).height(84).padding(0).border({ width: 1, radius: 5, color: this.activeTool() === tool ? this.palette().accent : this.palette().borderSubtle })
      .backgroundColor(this.activeTool() === tool ? this.palette().accentSoft : this.palette().surface).id('ink-shape-' + tool)
      .accessibilityText('绘制' + label).onClick(() => {
        if (this.prepareInkAction()) { this.selectInkTool(tool); this.shapeOptionsOpen = false; }
      })
  }

  @Builder
  shapeSettingsPanel() {
    Column({ space: 18 }) {
      Text('图形').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
      Row({ space: 8 }) {
        this.shapeOption('line', $r('app.media.ic_line'), '直线')
        this.shapeOption('rectangle', $r('app.media.ic_rectangle'), '矩形')
        this.shapeOption('ellipse', $r('app.media.ic_ellipse'), '椭圆')
        this.shapeOption('arrow', $r('app.media.ic_arrow'), '箭头')
      }
    }.padding(20).width(304).alignItems(HorizontalAlign.Start)
  }

  @Builder
  paperOption(style: string, label: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 10 }) {
        Stack() {
          if (style !== 'blank') {
            Column({ space: 9 }) {
              ForEach([0, 1, 2, 3, 4, 5], () => { Divider().color(this.palette().border) })
            }.width(48).height(64).justifyContent(FlexAlign.Center)
          }
          if (style === 'grid') {
            Row({ space: 9 }) {
              ForEach([0, 1, 2, 3, 4], () => { Divider().vertical(true).height(64).color(this.palette().border) })
            }.width(48).height(64).justifyContent(FlexAlign.Center)
          }
        }.width(68).height(82).backgroundColor(this.palette().surface)
          .border({ width: 1, radius: 5, color: this.canvasState().paperStyle === style ? this.palette().accent : this.palette().borderSubtle })
        Text(label).fontSize(12).fontColor(this.palette().inkSecondary)
      }
    }.width(76).padding(0).backgroundColor(Color.Transparent).id('ink-paper-' + style).accessibilityText('使用' + label)
      .onClick(() => {
        if (this.prepareInkAction()) { this.sendCanvasCommand('paper', style); this.paperOptionsOpen = false; }
      })
  }

  @Builder
  paperSettingsPanel() {
    Column({ space: 18 }) {
      Text('纸张').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
      Row({ space: 10 }) { this.paperOption('blank', '白纸'); this.paperOption('ruled', '横线'); this.paperOption('grid', '方格'); }
      Divider().color(this.palette().borderSubtle)
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          AppIcon({ source: $r('app.media.ic_refresh'), iconSize: 18, tint: this.palette().inkSecondary })
          Text('回到起点').fontSize(13).fontColor(this.palette().inkPrimary)
        }
      }.width('100%').height(44).borderRadius(5).backgroundColor(this.palette().surfaceSubtle).id('ink-reset-view').accessibilityText('回到起点')
        .onClick(() => { this.sendCanvasCommand('resetView'); this.paperOptionsOpen = false; })
    }.padding(20).width(288).alignItems(HorizontalAlign.Start)
  }

  @Builder
  colorOption(color: string) {
    Button({ type: ButtonType.Normal }) {
      Circle({ width: 25, height: 25 }).fill(color).stroke(this.activeColor().toUpperCase() === color ? this.palette().accent : this.palette().border)
        .strokeWidth(this.activeColor().toUpperCase() === color ? 3 : 1)
    }.width(52).height(44).padding(0).borderRadius(5)
      .backgroundColor(this.activeColor().toUpperCase() === color ? this.palette().accentSoft : Color.Transparent)
      .accessibilityText(`批注颜色 ${color}`).onClick(() => { this.colorInput = color; this.changeInkColor(color); })
  }

  @Builder
  penSettingsPanel() {
    Column({ space: 14 }) {
      Row() {
        Text(this.activeTool() === 'eraser' ? '橡皮擦' : this.activeTool() === 'highlighter' ? '荧光笔' : '画笔')
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_close'), iconSize: 16, tint: this.palette().inkMuted })
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).accessibilityText('收起笔设置').onClick(() => { this.penOptionsOpen = false; })
      }.width('100%').height(32)
      if (this.activeTool() === 'eraser') {
        Row({ space: 10 }) {
          ForEach(['area', 'stroke'], (mode: string) => {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 10 }) {
                AppIcon({ source: mode === 'area' ? $r('app.media.ic_eraser') : $r('app.media.ic_pen'), iconSize: 26,
                  tint: this.activeEraserMode() === mode ? this.palette().accent : this.palette().inkSecondary })
                Text(mode === 'area' ? '区域擦除' : '笔画擦除').fontSize(13).fontColor(this.palette().inkPrimary)
              }
            }.layoutWeight(1).height(84).padding(8).borderRadius(5)
              .backgroundColor(this.activeEraserMode() === mode ? this.palette().accentSoft : this.palette().surfaceSubtle)
              .border({ width: 1, color: this.activeEraserMode() === mode ? this.palette().accent : this.palette().borderSubtle, radius: 5 })
              .accessibilityText(mode === 'area' ? '区域擦除' : '笔画擦除')
              .accessibilityDescription(this.activeEraserMode() === mode ? '已选中' : '未选中')
              .onClick(() => this.changeInkEraserMode(mode))
          }, (mode: string) => mode)
        }.width('100%')
        Text(this.activeEraserMode() === 'area' ? '只擦掉橡皮经过的区域，保留笔画其余部分。' : '碰到笔画就删除整笔，抬笔后可撤销。')
          .fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
      } else {
        Row({ space: 5 }) {
          ForEach(this.widthPresets(), (width: number) => {
            Button({ type: ButtonType.Normal }) {
              Path().commands('M 6 26 C 13 9 19 11 23 21 S 32 26 38 13').width(44).height(36)
                .fill(Color.Transparent).stroke(this.activeColor()).strokeWidth(Math.min(12, width)).strokeLineCap(LineCapStyle.Round)
            }.layoutWeight(1).height(44).padding(0).borderRadius(5)
              .backgroundColor(this.activeWidth() === width ? this.palette().accentSoft : this.palette().surfaceSubtle)
              .border({ width: 1, color: this.activeWidth() === width ? this.palette().accent : this.palette().borderSubtle, radius: 5 })
              .accessibilityText(`笔宽 ${width} px`).onClick(() => this.changeInkWidth(width))
          }, (width: number) => String(width))
        }.width('100%')
      }
      InkWidthSlider({ tool: this.activeTool(), value: this.activeWidth(), accentColor: this.palette().accent, onChange: (value: number) => this.changeInkWidth(value) })
      Divider().color(this.palette().borderSubtle)
      if (this.activeTool() !== 'eraser') {
        Column() {
          Row({ space: 8 }) { ForEach(this.inkColors().slice(0, 4), (color: string) => { this.colorOption(color) }, (color: string) => color) }
          Row({ space: 8 }) { ForEach(this.inkColors().slice(4, 8), (color: string) => { this.colorOption(color) }, (color: string) => color) }
        }.width('100%').alignItems(HorizontalAlign.Start)
        Row({ space: 10 }) {
          Circle({ width: 18, height: 18 }).fill(this.activeColor()).stroke(this.palette().border).strokeWidth(1)
          TextInput({ text: this.colorInput, placeholder: '#2563EB' }).height(44).layoutWeight(1).fontSize(13).maxLength(7)
            .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle).borderRadius(5)
            .accessibilityText('自定义颜色，6 位十六进制').onChange((value: string) => { this.colorInput = value; })
            .onSubmit(() => this.applyHexColor())
          Button('应用', { type: ButtonType.Normal }).height(44).borderRadius(5).fontSize(12).fontColor(this.palette().accent).backgroundColor(this.palette().accentSoft)
            .onClick(() => this.applyHexColor())
        }.width('100%')
      } else {
        Row() {
          Blank()
          Circle({ width: Math.min(48, this.activeWidth()), height: Math.min(48, this.activeWidth()) })
            .fill(this.palette().surfaceSubtle).stroke(this.palette().inkMuted).strokeWidth(1)
          Blank()
        }.width('100%').height(56).accessibilityText('橡皮直径预览')
        Button(this.usesCanvasTools() ? '清空当前稿纸笔迹' : '清空本页笔迹', { type: ButtonType.Normal })
          .height(44).width('100%').fontSize(13).fontColor(this.palette().danger).backgroundColor(Color.Transparent)
          .onClick(() => this.requestClearInk())
      }
      Row() {
        Text('手指书写').fontSize(12).fontColor(this.palette().inkSecondary).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.activeFingerDrawing() }).selectedColor(this.palette().accent)
          .accessibilityText('手指书写').onChange((value: boolean) => { if (value !== this.activeFingerDrawing()) { this.toggleInkFinger(); } })
      }.width('100%').height(36)
    }.width(this.isPhone ? 286 : 308).padding(20).borderRadius(8)
      .border({ width: 1, color: this.palette().borderSubtle }).backgroundColor(this.palette().surface)
  }

  // ------------------------------------------------------------------
  // 「··· 更多」功能操作面板与统一入口
  // ------------------------------------------------------------------

  private closeOutput(): void {
    if (this.outputBusy) { return; }
    this.activeModal = ''; this.outputMessage = ''; this.outputFailed = false;
  }

  private openOutput(action: HuaweiDocDialogType): void {
    if (this.exitSaving || this.restoreSourceBusy || this.outputBusy) { return; }
    this.documentMenuOpen = false; this.penOptionsOpen = false;
    this.outputMessage = ''; this.outputFailed = false;
    if (this.isAnnotateMode || this.documentDirty || this.scratchpadDirty) {
      this.pendingOutput = action; this.saveDestination = 'output'; this.beginReaderSave();
    } else { this.activeModal = action; }
  }

  private async performOutput(extension: string): Promise<void> {
    if (this.outputBusy || !this.activeModal) { return; }
    const noteId = this.note.id;
    const action = this.activeModal;
    this.outputBusy = true; this.outputMessage = ''; this.outputFailed = false;
    try {
      if (action === 'share_pdf' || action === 'share_image') {
        if (action === 'share_image') {
          await SystemShareService.shareImage(this.getUIContext().getHostContext() as common.UIAbilityContext, this.note.title, this.note.sourceUri || '');
        } else {
          await SystemShareService.sharePdf(this.getUIContext().getHostContext() as common.UIAbilityContext, this.note.title, this.note.sourceUri || '');
        }
        if (this.note.id === noteId) { this.outputMessage = '已打开系统分享面板'; }
      } else {
        if (action === 'export_image' && !(this.isHandwritingNote() ? this.whiteboardReady : this.pdfSourceReady && !this.annotationError)) {
          throw new Error('正文或笔迹尚未加载完成，请关闭弹窗，检查页面后重试');
        }
        const result = action === 'export_image' ? await ReaderOutputService.saveScreenshot(
          this.getUIContext().getHostContext() as common.UIAbilityContext, this.getUIContext(), `reader-document-${noteId}`, this.note.title) :
          action === 'export_original' ? await ImageDocumentService.exportOriginal(this.getUIContext().getHostContext() as common.UIAbilityContext, this.note) : await this.onExportText(extension);
        if (this.note.id !== noteId) { return; }
        if (result.status === 'cancelled') { this.activeModal = ''; }
        else { this.outputMessage = result.message; this.outputFailed = result.status !== 'exported'; }
      }
    } catch (error) {
      if (this.note.id === noteId) { this.outputMessage = error instanceof Error ? error.message : '操作未完成，请重试'; this.outputFailed = true; }
    } finally { if (this.note.id === noteId) { this.outputBusy = false; } }
  }

  @Builder
  documentMenu() {
    Menu() {
      MenuItem({ content: this.note.favorite ? '取消收藏' : '收藏资料', startIcon: $r('app.media.ic_star') })
        .onClick(() => { this.documentMenuOpen = false; this.onToggleFavorite(this.note); })

      MenuItem({ content: '打开随堂稿纸', startIcon: $r('app.media.ic_canvas') })
        .onClick(() => { this.documentMenuOpen = false; this.switchSplitMode('scratchpad'); })
      MenuItem({ content: '仅显示正文', startIcon: $r('app.media.ic_page') })
        .onClick(() => { this.documentMenuOpen = false; this.switchSplitMode('none'); })
      if (!this.isHandwritingNote() && !this.isImageDocument()) {
        MenuItem({ content: this.restoreSourceBusy ? '正在关联原 PDF…' : '重新关联原 PDF' })
          .enabled(!this.restoreSourceBusy && !this.exitSaving).onClick(() => { this.documentMenuOpen = false; this.restorePdfSource(); })
      }
      if (this.isImageDocument() && this.note.sourceUri) {
        MenuItem({ content: '分享原始图片', startIcon: $r('app.media.ic_share') }).onClick(() => this.openOutput('share_image'))
        MenuItem({ content: '导出原始图片', startIcon: $r('app.media.ic_export') }).onClick(() => this.openOutput('export_original'))
      }
      MenuItem({ content: '画笔设置' }).enabled(this.isAnnotateMode && !this.exitSaving).onClick(() => {
        this.documentMenuOpen = false; this.openToolSettings(this.activeTool() === 'eraser' ? 'eraser' : this.activeTool() === 'highlighter' ? 'highlighter' : 'pen');
      })
      MenuItem({ content: '新建手写笔记', startIcon: $r('app.media.ic_plus') }).onClick(() => { this.documentMenuOpen = false; this.createDocument(); })
      if (this.note.sourceType === 'pdf' && this.note.sourceUri) {
        MenuItem({ content: '分享原 PDF' }).onClick(() => this.openOutput('share_pdf'))
        MenuItem({ content: '提取页面文字' }).onClick(() => { this.documentMenuOpen = false; this.onExtractPdfText(this.currentPage); })
        MenuItem({ content: '跳转页码' }).onClick(() => { this.documentMenuOpen = false; this.openPageJump(); })
        MenuItem({ content: this.isContinuousScroll ? '切换单页阅读' : '切换连续阅读' })
          .onClick(() => { this.documentMenuOpen = false; this.isContinuousScroll = !this.isContinuousScroll; })
      }
      MenuItem({ content: this.usesCanvasTools() ? '清空当前稿纸笔迹' : '清空本页笔迹' }).enabled(this.isAnnotateMode && !this.exitSaving)
        .onClick(() => { this.documentMenuOpen = false; this.requestClearInk(); })
      MenuItem({ content: '提取图片或文字' }).onClick(() => { this.documentMenuOpen = false; this.openSmartExtract(); })
      if (!this.isHandwritingNote() && !this.isImageDocument()) {
        MenuItem({ content: '导出笔记文字', startIcon: $r('app.media.ic_export') }).onClick(() => this.openOutput('export_text'))
      }
      MenuItem({ content: '保存正文截图', startIcon: $r('app.media.ic_screenshot') }).onClick(() => this.openOutput('export_image'))

      MenuItem({ content: '搜索资料' }).onClick(() => { this.documentMenuOpen = false; this.openSearch(); })
      MenuItem({ content: '退出阅读' }).onClick(() => { this.documentMenuOpen = false; this.handleBackRequest(); })
    }
  }

  // ------------------------------------------------------------------
  // 固定页码入口
  // ------------------------------------------------------------------

  @Builder
  bottomReadingConsole() {
    Row({ space: 2 }) {
      Button({ type: ButtonType.Normal }) {
        AppIcon({ source: $r('app.media.ic_back'), iconSize: 16, tint: this.palette().inkSecondary })
      }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).borderRadius(6)
        .enabled(this.pdfSourceReady && !this.exitSaving && this.currentPage > 1)
        .accessibilityText('上一页').onClick(() => this.jumpToPage(this.currentPage - 1))
      Button(`${this.currentPage} / ${this.totalPages}`, { type: ButtonType.Normal })
        .height(44).constraintSize({ minWidth: 72 }).padding({ left: 10, right: 10 })
        .fontSize(13).fontColor(this.palette().inkPrimary).backgroundColor(Color.Transparent).borderRadius(6)
        .accessibilityText(`当前第 ${this.currentPage} 页，共 ${this.totalPages} 页，点击跳转`)
        .onClick(() => this.openPageJump()).enabled(!this.exitSaving)
        .bindPopup(this.jumpDialogOpen, {
          builder: this.quickJumpDialog, placement: Placement.TopLeft,
          popupColor: this.palette().surface,
          onStateChange: (event) => { if (!event.isVisible) { this.jumpDialogOpen = false; } }
        })
      Button({ type: ButtonType.Normal }) {
        AppIcon({ source: $r('app.media.ic_chevron_right'), iconSize: 16, tint: this.palette().inkSecondary })
      }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).borderRadius(6)
        .enabled(this.pdfSourceReady && !this.exitSaving && this.currentPage < this.totalPages)
        .accessibilityText('下一页').onClick(() => this.jumpToPage(this.currentPage + 1))
      if (!this.isImageDocument()) {
        Divider().vertical(true).height(18).color(this.palette().borderSubtle)
        Button(this.isContinuousScroll ? '连续' : '逐页', { type: ButtonType.Normal }).height(44).fontSize(12)
          .padding({ left: 12, right: 12 }).backgroundColor(Color.Transparent).fontColor(this.palette().inkSecondary)
          .accessibilityText(this.isContinuousScroll ? '切换为逐页阅读' : '切换为连续滚动')
          .enabled(this.pdfSourceReady && !this.exitSaving).onClick(() => { this.isContinuousScroll = !this.isContinuousScroll; })
      }
    }.height(48).padding({ left: 2, right: 2 }).borderRadius(8).backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle }).id('reader-page-controls')
      .position({ x: 12, y: '100%' }).translate({ y: -60 })
  }
  // 快速页码跳转弹窗
  // ------------------------------------------------------------------

  private openPageJump(): void {
    this.jumpPageInput = String(this.currentPage);
    this.jumpDialogOpen = true;
  }

  private submitPageJump(): void {
    const page = Number(this.jumpPageInput);
    if (!Number.isInteger(page) || page < 1 || page > this.totalPages) {
      this.showToast(`请输入 1 到 ${this.totalPages} 之间的页码`); return;
    }
    this.jumpToPage(page);
  }

  @Builder
  quickJumpDialog() {
    Column({ space: 8 }) {
      Text(`跳转页码 · 共 ${this.totalPages} 页`).fontSize(13).fontColor(this.palette().inkSecondary)
      Row({ space: 8 }) {
        TextInput({ text: this.jumpPageInput, placeholder: '页码' }).type(InputType.Number)
          .height(44).layoutWeight(1).fontSize(16).fontColor(this.palette().inkPrimary)
          .backgroundColor(this.palette().surfaceSubtle).accessibilityText('输入跳转页码')
          .onChange((value: string) => { this.jumpPageInput = value; })
          .onSubmit(() => this.submitPageJump())
        Button('跳转').height(44).fontSize(14).backgroundColor(this.palette().accent)
          .fontColor(this.palette().onAccent).onClick(() => this.submitPageJump())
      }
    }.width(this.isPhone ? 220 : 260).padding(12)
  }
  // ------------------------------------------------------------------
  // 清空笔迹确认与保存失败重试
  // ------------------------------------------------------------------

  @Builder
  clearInkDialog() {
    Column() {
      Column({ space: 18 }) {
        Row({ space: 12 }) {
          AppIcon({ source: $r('app.media.ic_trash'), tint: this.palette().danger })
          Text(this.usesCanvasTools() ? '清空当前稿纸笔迹？' : '清空本页笔迹？').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1)
        }.width('100%')
        Text('原文件保留，清空后可撤销').fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
        Row({ space: 12 }) {
          Button('取消', { type: ButtonType.Normal }).height(48).layoutWeight(1).borderRadius(5).backgroundColor(this.palette().surfaceSubtle)
            .fontColor(this.palette().inkPrimary).onClick(() => { this.clearDialogOpen = false; })
          Button('清空笔迹', { type: ButtonType.Normal }).height(48).layoutWeight(1).borderRadius(5).backgroundColor(this.palette().danger)
            .fontColor('#FFFFFF').onClick(() => this.confirmClearInk())
        }.width('100%')
      }.width('88%').constraintSize({ maxWidth: 390 }).padding(24).borderRadius(8).backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().borderSubtle }).shadow({ radius: 20, color: 'rgba(0,0,0,0.12)', offsetY: 6 }).onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.18)').zIndex(300).onClick(() => { this.clearDialogOpen = false; })
  }

  @Builder
  saveFailureDialog() {
    Column() {
      Column({ space: 16 }) {
        Text('保存未完成').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).width('100%')
        Text('内容已保留。重试成功后会继续刚才的操作，不会清空稿纸。').fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
        Row({ space: 12 }) {
          Button('继续阅读').height(48).layoutWeight(1).enabled(!this.exitSaving).backgroundColor(this.palette().surfaceSubtle)
            .fontColor(this.palette().inkPrimary).onClick(() => { this.exitDialogOpen = false; })
          Button(this.exitSaving ? '保存中…' : '重试保存').height(48).layoutWeight(1).enabled(!this.exitSaving)
            .backgroundColor(this.palette().accent).fontColor(this.palette().onAccent).onClick(() => this.beginReaderSave())
        }.width('100%')
      }.width('90%').constraintSize({ maxWidth: 380 }).padding(20).borderRadius(8).backgroundColor(this.palette().surface)
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
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_more'), tint: this.palette().inkSecondary })
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText('随堂稿纸操作').enabled(!this.exitSaving)
          .onClick(() => { this.inkTarget = 'scratchpad'; this.scratchpadMenuOpen = !this.scratchpadMenuOpen; })
          .bindMenu(this.scratchpadMenuOpen, this.scratchpadMenu, { onDisappear: () => { this.scratchpadMenuOpen = false; } })

        Text('随堂演算稿纸')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)

        Blank()

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
          onFocused: () => { this.inkTarget = 'scratchpad'; this.ensureCanvasTool('scratchpad'); },
          onShowTools: () => { this.inkTarget = 'scratchpad'; this.openToolSettings(this.activeTool() === 'eraser' ? 'eraser' : this.activeTool() === 'highlighter' ? 'highlighter' : 'pen'); },
          onToolStateChange: (state: CanvasToolState) => { this.scratchpadInk = state; this.scratchpadInkTool = state.tool; },
          readOnly: !this.isAnnotateMode || this.exitSaving,
          exitSaveToken: this.exitSaveToken,
          onCommitForExit: this.onCommitForExit,
          onExitSaveFinished: (ok: boolean, noteId: string, token: number) => this.exitSaveFinished(ok, noteId, token, 'scratchpad'),
          onDirtyChange: (dirty: boolean) => { this.scratchpadDirty = dirty; },
          onSaved: this.onSaved,
          onSaveStateChange: (state: string) => { this.updateAreaState('scratchpad', state); }
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)
  }

  @Builder
  scratchpadMenu() {
    Menu() {
      MenuItem({ content: '稿纸画笔设置' }).onClick(() => {
        this.scratchpadMenuOpen = false; this.inkTarget = 'scratchpad';
        if (this.prepareInkAction()) { this.openToolSettings('pen'); }
      })
      MenuItem({ content: '空白稿纸' }).onClick(() => this.changeScratchpadPaper('blank'))
      MenuItem({ content: '横线稿纸' }).onClick(() => this.changeScratchpadPaper('ruled'))
      MenuItem({ content: '方格稿纸' }).onClick(() => this.changeScratchpadPaper('grid'))
      MenuItem({ content: '重置稿纸视图' }).onClick(() => {
        this.scratchpadMenuOpen = false; this.inkTarget = 'scratchpad'; this.sendCanvasCommand('resetView');
      })
      MenuItem({ content: '清空随堂稿纸笔迹' }).onClick(() => {
        this.scratchpadMenuOpen = false; this.inkTarget = 'scratchpad';
        if (this.prepareInkAction()) { this.requestClearInk(); }
      })
    }
  }

  private changeScratchpadPaper(style: string): void {
    this.scratchpadMenuOpen = false; this.inkTarget = 'scratchpad';
    if (this.prepareInkAction()) { this.sendCanvasCommand('paper', style); }
  }

  // ------------------------------------------------------------------
  // 主布局构建
  // ------------------------------------------------------------------

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // ---- 1. 固定文档导航与共享书写工具 ----
        this.topNavigationBar()

        // ---- 2. 主视口区（左文档 + 右分屏）----
        Row() {
          // 左侧主文档 / 试卷 / 稿纸编辑区
          Stack({ alignContent: Alignment.Bottom }) {
            Stack() {
            if (this.isHandwritingNote()) {
              // 纯稿纸/白纸手写笔记
              HandwritingCanvas({
                note: this.note,
                isScratchpad: false,
                showToolbar: false,
                toolCommand: this.canvasCommand,
                onFocused: () => { this.inkTarget = 'document'; this.ensureCanvasTool('document'); },
                onShowTools: () => { this.inkTarget = 'document'; this.openToolSettings(this.activeTool() === 'eraser' ? 'eraser' : this.activeTool() === 'highlighter' ? 'highlighter' : 'pen'); },
                onToolStateChange: (state: CanvasToolState) => { this.documentInk = state; this.documentInkTool = state.tool; },
                onContentReady: (ready: boolean) => { this.whiteboardReady = ready; },
                readOnly: !this.isAnnotateMode || this.exitSaving,
                onDirtyChange: (dirty: boolean) => { this.documentDirty = dirty; },
                exitSaveToken: this.exitSaveToken,
                onCommitForExit: this.onCommitForExit,
                onExitSaveFinished: (ok: boolean, noteId: string, token: number) => this.exitSaveFinished(ok, noteId, token, 'document'),
                onSaved: this.onSaved,
                onSaveStateChange: (state: string) => { this.updateAreaState('document', state); }
              })
            } else {
              // PDF / 试卷真题原盘批注
              PdfAnnotatorView({
                note: this.note,
                onRestoreSource: () => this.restorePdfSource(),
                onSourceReady: (ready: boolean) => { this.pdfSourceReady = ready; if (ready) { this.rememberReadingPage(this.currentPage); } },
                onAnnotationError: (message: string) => { this.annotationError = message; },
                onDirtyChange: (dirty: boolean) => { this.documentDirty = dirty; },
                currentPage: this.currentPage,
                onPageChanged: (page: number) => this.rememberReadingPage(page),
                exitSaveToken: this.exitSaveToken,
                onCommitForExit: this.onCommitForExit,
                onExitSaveFinished: (ok: boolean, noteId: string, token: number) => this.exitSaveFinished(ok, noteId, token, 'document'),
                isContinuousScroll: this.isContinuousScroll,
                isAnnotateMode: this.isAnnotateMode && !this.exitSaving,
                currentTool: this.currentTool,
                selectedColor: this.selectedColor,
                selectedWidth: this.selectedWidth,
                eraserWidth: this.eraserWidth,
                eraserMode: this.pdfEraserMode,
                onFocused: () => { this.inkTarget = 'document'; this.ensureCanvasTool('document'); },
                undoTrigger: this.undoTrigger,
                redoTrigger: this.redoTrigger,
                fingerDrawing: this.fingerDrawing,
                onToggleEraser: () => {
                  this.selectPdfTool(this.currentTool === 'eraser' ? this.previousInkTool : 'eraser');
                },
                onShowPenTools: () => { this.inkTarget = 'document'; this.openToolSettings(this.activeTool() === 'eraser' ? 'eraser' : this.activeTool() === 'highlighter' ? 'highlighter' : 'pen'); },
                clearTrigger: this.clearTrigger,
                onSaved: this.onSaved,
                onSaveStateChange: (state: string) => { this.updateAreaState('document', state); }
              })
            }

            }.width('100%').height('100%').clip(true).id(`reader-document-${this.note.id}`)
            // 页码固定在正文左下角，书写时也可快速跳页。
            if (!this.isHandwritingNote()) {
              this.bottomReadingConsole()
            }
          }
          .layoutWeight(this.splitMode === 'none' || this.isPhone ? 100 : 55)
          .height('100%')

          // 随堂稿纸在手机上使用全宽抽屉，文件分屏由外层工作台负责。
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
              this.scratchpadSplitPane()
            }
            .layoutWeight(this.isPhone ? undefined : 45)
            .width(this.isPhone ? '100%' : undefined)
            .height('100%')
            .position(this.isPhone ? { x: 0, y: 0 } : undefined)
            .zIndex(this.isPhone ? 40 : 1)
            .backgroundColor(this.palette().surface)

          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette().canvas)


      // ---- 6. 统一顶层操作模态弹窗（另存为、格式转换、长图输出、打印）----
      if (this.activeModal.length > 0) {
        HuaweiDocActionDialog({
          note: this.note,
          dialogType: this.activeModal,
          busy: this.outputBusy, resultMessage: this.outputMessage, failed: this.outputFailed,
          onClose: () => this.closeOutput(),
          onConfirm: (extension: string) => this.performOutput(extension)
        })
      }

      // 保存失败时保留原页面并允许重试；正常返回不弹确认框。
      if (this.exitDialogOpen) {
        this.saveFailureDialog()
      }
      if (this.clearDialogOpen) { this.clearInkDialog() }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)
  }
}
