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
import { AnnotationTool } from '../../../common/types/PdfAnnotationTypes';
import { PdfAnnotatorView } from '../pdf/PdfAnnotatorView';
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

  private handleBackRequest(): void {
    if (this.activeModal.length > 0) { this.activeModal = ''; return; }
    if (this.jumpDialogOpen) { this.jumpDialogOpen = false; return; }
    if (this.exitDialogOpen) { if (!this.exitSaving) { this.exitDialogOpen = false; } return; }
    if (this.isPhone && this.splitMode !== 'none') { this.splitMode = 'none'; return; }
    if (!this.exitSaving) { this.exitDialogOpen = true; }
  }

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  // 顶底栏沉浸与显隐状态
  @State barsVisible: boolean = true;

  // 模式与批注状态（鸿蒙笔控设计）
  @State isAnnotateMode: boolean = false;
  @State isPenPaletteExpanded: boolean = true;
  @State currentTool: AnnotationTool = 'pen';
  @State selectedColor: string = '#DC2626';
  @State selectedWidth: number = 3;
  @State undoTrigger: number = 0;
  @State redoTrigger: number = 0;
  @State fingerDrawing: boolean = false;
  private previousInkTool: AnnotationTool = 'pen';
  @State clearTrigger: number = 0;
  @State exitDialogOpen: boolean = false;
  @State exitSaving: boolean = false;
  @State exitSaveToken: number = 0;
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
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private onSourceJump(): void {
    this.currentPage = Math.max(1, Math.min(this.totalPages, this.sourcePage));
  }

  aboutToAppear(): void {
    this.loadedNoteId = this.note.id;
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
    if (this.loadedNoteId === this.note.id) { return; }
    this.loadedNoteId = this.note.id;
    this.activeModal = '';
    this.jumpDialogOpen = false;
    if (this.isDocumentOrExam()) {
      const count = this.note.pageCount && this.note.pageCount > 0 ? this.note.pageCount : 1;
      this.totalPages = count;
    }
  }

  private saveAndExit(): void {
    if (this.exitSaving) { return; }
    this.exitSaving = true;
    this.exitSaveToken++;
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
      AppIcon({ source: icon, iconSize: 22, tint: this.isAnnotateMode === annotate ? this.palette().accent : this.palette().inkSecondary })
    }.width(44).height(44).padding(0).borderRadius(12)
      .backgroundColor(this.isAnnotateMode === annotate ? this.palette().accentSoft : Color.Transparent)
      .accessibilityText(label).bindTips(label)
      .onClick(() => { this.isAnnotateMode = annotate; if (annotate) { this.isPenPaletteExpanded = true; } })
  }

  @Builder
  topNavigationBar() {
    Column({ space: 2 }) {
      Row({ space: 4 }) {
        IconButton({ icon: $r('app.media.ic_back'), label: '返回并选择保存方式', onAction: () => { this.exitDialogOpen = true; } })
        Text(this.note.title).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        IconButton({ icon: $r('app.media.ic_star'), label: this.note.favorite ? '取消收藏' : '收藏',
          selected: this.note.favorite === true, onAction: () => this.onToggleFavorite(this.note) })
        IconButton({ icon: $r('app.media.ic_fullscreen'), label: '沉浸阅读',
          onAction: () => { this.toggleBars(false); this.showToast('轻触屏幕边缘显示工具栏'); } })
        IconButton({ icon: $r('app.media.ic_more'), label: '更多文档操作' })
          .bindMenu(() => { this.documentMenu(); })
      }.width('100%').height(48)
      Scroll() {
        Row({ space: 4 }) {
          this.readerModeButton($r('app.media.ic_read'), '阅读', false)
          this.readerModeButton($r('app.media.ic_pen'), '批注', true)
          Divider().vertical(true).height(24).color(this.palette().border).margin({ left: 4, right: 4 })
          this.splitSegmentItem($r('app.media.ic_page'), '单页', 'none')
          this.splitSegmentItem($r('app.media.ic_sparkle'), '墨客', 'ai')
          this.splitSegmentItem($r('app.media.ic_canvas'), '稿纸', 'scratchpad')
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    }.width('100%').padding({ left: 8, right: 8, bottom: 4 }).backgroundColor(this.palette().surface)
      .border({ width: { bottom: 1 }, color: this.palette().borderSubtle })
  }

  @Builder
  splitSegmentItem(icon: Resource, label: string, mode: SplitModeType) {
    Button({ type: ButtonType.Normal }) {
      AppIcon({ source: icon, iconSize: 22, tint: this.splitMode === mode ? this.palette().accent : this.palette().inkSecondary })
    }.width(44).height(44).padding(0).borderRadius(12)
      .backgroundColor(this.splitMode === mode ? this.palette().accentSoft : Color.Transparent)
      .accessibilityText(mode === 'none' ? '仅显示文档' : `打开${label}分屏`)
      .bindTips(mode === 'none' ? '仅显示文档' : `打开${label}分屏`)
      .onClick(() => {
        animateTo({ duration: AnimationTokens.DURATION_SPLIT, curve: Curve.EaseInOut }, () => { this.splitMode = mode; });
      })
  }

  // ------------------------------------------------------------------
  // 灵动悬浮笔盘 (Floating Pen Palette) - 遵循鸿蒙笔控设计规范与 Obsidian 极简质感
  // ------------------------------------------------------------------

  @Builder
  pdfInkTool(icon: Resource, label: string, tool: AnnotationTool) {
    Button({ type: ButtonType.Normal }) {
      AppIcon({ source: icon, iconSize: 22, tint: this.currentTool === tool ? this.palette().accent : this.palette().inkSecondary })
    }.width(44).height(44).padding(0).borderRadius(10)
      .backgroundColor(this.currentTool === tool ? this.palette().accentSoft : Color.Transparent).accessibilityText(label).bindTips(label)
      .onClick(() => {
        this.currentTool = tool;
        if (tool === 'highlighter') { this.selectedColor = '#FACC15'; this.selectedWidth = 14; }
        if (tool === 'pen') {
          if (this.selectedColor === '#FACC15' || this.selectedColor === '#4ADE80') { this.selectedColor = '#DC2626'; }
          this.selectedWidth = 3;
        }
      })
  }

  @Builder
  floatingPenPalette() {
    Column({ space: 4 }) {
      Scroll() {
      Row() {
        this.pdfInkTool($r('app.media.ic_pen'), '笔', 'pen')
        this.pdfInkTool($r('app.media.ic_highlighter'), '荧光', 'highlighter')
        this.pdfInkTool($r('app.media.ic_eraser'), '橡皮', 'eraser')
        IconButton({ icon: $r('app.media.ic_undo'), label: '撤销批注', onAction: () => { this.undoTrigger++; } })
        IconButton({ icon: $r('app.media.ic_redo'), label: '重做批注', onAction: () => { this.redoTrigger++; } })
        IconButton({ icon: $r('app.media.ic_settings'), label: '颜色、笔粗与触控设置', selected: this.penOptionsOpen,
          onAction: () => { this.penOptionsOpen = !this.penOptionsOpen; } })
      }.width(Math.max(264, this.penPaletteWidth - 16)).justifyContent(FlexAlign.SpaceBetween)
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      if (this.penOptionsOpen) {
        Scroll() {
          Row({ space: 4 }) {
            ForEach(this.currentTool === 'highlighter' ? ['#FACC15', '#4ADE80'] : ['#1C1917', '#2563EB', '#DC2626', '#059669'], (color: string) => {
              Button({ type: ButtonType.Normal }) {
                Circle({ width: 20, height: 20 }).fill(color)
                  .stroke(this.selectedColor === color ? this.palette().inkPrimary : this.palette().border)
                  .strokeWidth(this.selectedColor === color ? 3 : 1)
              }.width(44).height(44).padding(0).borderRadius(10)
                .backgroundColor(this.selectedColor === color ? this.palette().accentSoft : Color.Transparent)
                .accessibilityText(`批注颜色 ${color}`).onClick(() => { this.selectedColor = color; })
            }, (color: string) => color)
            if (this.currentTool === 'pen') {
              Divider().vertical(true).height(24).color(this.palette().border)
              ForEach([2, 4, 8], (width: number) => {
                Button({ type: ButtonType.Normal }) {
                  Circle({ width: width * 2 + 4, height: width * 2 + 4 }).fill(this.palette().inkPrimary)
                }.width(44).height(44).padding(0).borderRadius(10)
                  .backgroundColor(this.selectedWidth === width ? this.palette().accentSoft : Color.Transparent)
                  .accessibilityText(`笔粗 ${width}`).onClick(() => { this.selectedWidth = width; })
              }, (width: number) => `${width}`)
            }
            IconButton({ icon: $r('app.media.ic_hand'), label: '切换为手指浏览', selected: this.currentTool === 'pan',
              onAction: () => { this.currentTool = 'pan'; } })
            IconButton({ icon: $r('app.media.ic_pen'), label: this.fingerDrawing ? '关闭手指书写，仅使用手写笔' : '开启手指书写',
              selected: this.fingerDrawing, onAction: () => { this.fingerDrawing = !this.fingerDrawing; } })
            IconButton({ icon: $r('app.media.ic_chevron_down'), label: '折叠笔工具', onAction: () => { this.isPenPaletteExpanded = false; } })
            IconButton({ icon: $r('app.media.ic_close'), label: '退出批注，继续阅读', onAction: () => { this.isAnnotateMode = false; } })
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
      }
    }.width('96%').constraintSize({ maxWidth: 600 })
      .onAreaChange((before: Area, after: Area) => { this.penPaletteWidth = Number(after.width); })
      .padding({ left: 8, right: 8, top: 6, bottom: 6 }).borderRadius(18)
      .backgroundColor(this.palette().surface).border({ width: 1, color: this.palette().border })
      .shadow({ radius: 12, color: this.isDarkMode ? 'rgba(0,0,0,0.4)' : 'rgba(36,32,51,0.12)', offsetY: 3 })
  }

  @Builder
  floatingBall() {
    Row({ space: 6 }) {
      AppIcon({ source: $r('app.media.ic_pen'), tint: this.palette().onAccent })
      if (!this.isAnnotateMode) {
      }
    }
    .padding(this.isAnnotateMode ? 12 : { left: 14, right: 16, top: 10, bottom: 10 })
    .constraintSize({ minWidth: 44, minHeight: 44 })
    .accessibilityText('打开批注工具')
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
          this.isAnnotateMode = true;
          this.isPenPaletteExpanded = true;
          this.showToast('已进入手写批注模式');
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
      if (this.note.sourceType === 'pdf' && this.note.sourceUri) {
        MenuItem({ content: '分享原 PDF' }).enabled(!this.shareBusy).onClick(() => this.shareOriginalPdf())
        MenuItem({ content: '提取页面文字' }).onClick(() => this.onExtractPdfText(this.currentPage))
        MenuItem({ content: '跳转页码' }).onClick(() => { this.jumpDialogOpen = true; })
        MenuItem({ content: this.isContinuousScroll ? '切换单页阅读' : '切换连续阅读' })
          .onClick(() => { this.isContinuousScroll = !this.isContinuousScroll; })
        MenuItem({ content: '清空本页笔迹，可撤销' }).onClick(() => this.clearCurrentPageAnnotations())
      }
      MenuItem({ content: '提取图片或文字' }).onClick(() => this.onSmartExtract())
      MenuItem({ content: '导出笔记文字' }).onClick(() => this.onExportText())
      MenuItem({ content: '搜索资料' }).onClick(() => this.onSearchNotes())
      MenuItem({ content: '保存并退出' }).onClick(() => { this.exitDialogOpen = true; })
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

          Button('✕')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .width(44)
            .height(44)
            .padding(0)
            .borderRadius(22)
            .backgroundColor(this.palette().surfaceSubtle)
            .onClick(() => {
              animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
                this.jumpDialogOpen = false;
              });
            })
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
      // 弹窗卡片
      Column({ space: 18 }) {
        // 头部：图标 + 标题
        Row({ space: 12 }) {
          // Obsidian 风格圆角图标徽章
          Row() {
            Text('✎')
              .fontSize(16)
              .fontColor(this.palette().accent)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.palette().accentSoft)
          .justifyContent(FlexAlign.Center)

          Column({ space: 4 }) {
            Text('保存文档修改？')
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)

            Text('退出前是否保存当前手写批注与阅读进度？')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

        // 提示信息条 (Obsidian 沉浸淡灰/深灰提示块)
        Row({ space: 8 }) {
          Text('ℹ')
            .fontSize(12)
            .fontColor(this.palette().inkMuted)
          Text('若选择放弃，本次会话中未保存的手写笔迹与文档状态将不会落盘。')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(this.palette().surfaceSubtle)
        .border({ width: 1, color: this.palette().borderSubtle })

        // 底部操作按钮组: [ 放弃修改 ] [ 取消 ] [ 保存并退出 ]
        Row({ space: 10 }) {
          // 放弃修改 (次要危险动作)
          Button('放弃修改')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDarkMode ? '#F87171' : '#DC2626')
            .backgroundColor(this.isDarkMode ? '#3B181E' : '#FEE2E2')
            .border({ width: 1, color: this.isDarkMode ? '#5C2229' : '#FCA5A5' })
            .borderRadius(10)
            .height(36)
            .layoutWeight(1)
            .enabled(!this.exitSaving)
            .onClick(() => {
              animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
                this.exitDialogOpen = false;
              });
              this.showToast('已放弃本次修改');
              this.onClose();
            })

          // 取消 (关闭弹窗，留在当前阅读器)
          Button('取消')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
            .backgroundColor(this.palette().surfaceSubtle)
            .border({ width: 1, color: this.palette().borderSubtle })
            .borderRadius(10)
            .height(36)
            .layoutWeight(1)
            .enabled(!this.exitSaving)
            .onClick(() => {
              animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
                this.exitDialogOpen = false;
              });
            })

          // 保存并退出 (主确认动作)
          Button('保存并退出')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .backgroundColor(this.palette().accent)
            .borderRadius(10)
            .height(36)
            .layoutWeight(1.2)
            .enabled(!this.exitSaving)
            .onClick(() => this.saveAndExit())
        }
        .width('100%')
      }
      .width(this.isPhone ? '92%' : 400)
      .padding(22)
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 24, color: this.isDarkMode ? 'rgba(0,0,0,0.65)' : 'rgba(0,0,0,0.18)', offsetY: 8 })
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
    .zIndex(300)
    .transition(
      TransitionEffect.OPACITY
        .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
    )
    .onClick(() => {
      animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
        if (!this.exitSaving) { this.exitDialogOpen = false; }
      });
    })
  }

  // ------------------------------------------------------------------
  // 稿纸分屏面板
  // ------------------------------------------------------------------

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

        Text('✕')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(12)
          .backgroundColor(this.palette().surfaceSubtle)
          .onClick(() => {
            animateTo({ duration: AnimationTokens.DURATION_SPLIT, curve: AnimationTokens.CURVE_STANDARD }, () => {
              this.splitMode = 'none';
            });
          })
      }
      .width('100%')
      .height(42)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.palette().surface)
      .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

      // 稿纸手写画布
      Column() {
        HandwritingCanvas({
          note: this.note,
          isScratchpad: true,
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
        Column() {
          this.topNavigationBar()
        }
        .width('100%')
        .translate({ y: this.barsVisible ? 0 : -56 })
        .opacity(this.barsVisible ? 1 : 0)
        .enabled(this.barsVisible)
        .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })

        // ---- 2. 主视口区（左文档 + 右分屏）----
        Row() {
          // 左侧主文档 / 试卷 / 稿纸编辑区
          Stack({ alignContent: Alignment.Bottom }) {
            if (this.isHandwritingNote()) {
              // 纯稿纸/白纸手写笔记
              HandwritingCanvas({
                note: this.note,
                isScratchpad: false,
                exitSaveToken: this.exitSaveToken,
                onCommitForExit: this.onCommitForExit,
                onExitSaveFinished: (ok: boolean) => {
                  this.exitSaving = false;
                  if (ok) { this.onClose(); } else { this.showToast('保存失败，请重试'); }
                },
                onSaved: this.onSaved,
                onSaveStateChange: this.onSaveStateChange
              })
            } else {
              // PDF / 试卷真题原盘批注
              PdfAnnotatorView({
                note: this.note,
                currentPage: this.currentPage,
                onPageChanged: (page: number) => { this.currentPage = page; },
                exitSaveToken: this.exitSaveToken,
                onCommitForExit: this.onCommitForExit,
                onExitSaveFinished: (ok: boolean) => {
                  this.exitSaving = false;
                  if (ok) { this.onClose(); } else { this.showToast('保存失败，批注仍保留在当前页，请重试'); }
                },
                barsVisible: this.barsVisible,
                isContinuousScroll: this.isContinuousScroll,
                isAnnotateMode: this.isAnnotateMode,
                currentTool: this.currentTool,
                selectedColor: this.selectedColor,
                selectedWidth: this.selectedWidth,
                undoTrigger: this.undoTrigger,
                redoTrigger: this.redoTrigger,
                fingerDrawing: this.fingerDrawing,
                onToggleEraser: () => {
                  if (this.currentTool === 'eraser') { this.currentTool = this.previousInkTool; }
                  else { this.previousInkTool = this.currentTool === 'pan' ? 'pen' : this.currentTool; this.currentTool = 'eraser'; }
                },
                onShowPenTools: () => { this.isPenPaletteExpanded = true; this.penOptionsOpen = true; this.barsVisible = true; },
                clearTrigger: this.clearTrigger,
                onSaved: this.onSaved,
                onSaveStateChange: this.onSaveStateChange
              })
            }

            // 批注模式下展示灵动悬浮笔盘；阅读模式下展示浮动翻页控制台
            if (this.isAnnotateMode) {
              if (this.isPenPaletteExpanded && this.barsVisible) {
                this.floatingPenPalette()
              }
            } else {
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
                  note: this.note,
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
      if (!this.isAnnotateMode || !this.isPenPaletteExpanded) {
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
