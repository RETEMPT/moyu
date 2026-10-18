import { KeyboardAvoidMode, promptAction } from '@kit.ArkUI';
import { NoteItem } from '../../common/types/NoteItem';
import { MarkdownOutlineItem } from '../../common/types/MarkdownOutlineItem';
import { ReaderSaveKind } from '../../common/types/ReaderSaveKind';
import { DocumentTransferResult } from '../../common/types/MarkdownDocument';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { SAVE_IDLE, SAVE_SAVING, SAVE_FAILED } from '../../common/constants/WorkspaceConstants';
import { ReaderPairPolicy } from '../../services/document/ReaderPairPolicy';
import { PdfDocumentService } from '../../services/document/PdfDocumentService';
import { WorkspaceNotePolicy } from '../../services/WorkspaceNotePolicy';
import { IconButton } from '../common/IconButton';
import { ReaderWorkspace } from './ReaderWorkspace';
import { HuaweiDocWorkspace } from './huawei/HuaweiDocWorkspace';

/** A split owns navigation and save barriers. Each pane keeps its format-specific reader and data. */
@Component
export struct ReaderSplitWorkspace {
  @Require @Prop note: NoteItem;
  @Prop secondaryNote: NoteItem | null = null;
  @Prop documentTabs: NoteItem[] = [];
  @Prop manageKeyboardMode: boolean = true;
  @Prop @Watch('requestBack') backRequestToken: number = 0;
  @Prop sourcePage: number = 1;
  @Prop jumpToken: number = 0;
  @Prop jumpLine: number = -1;
  onOutlineUpdated: (items: MarkdownOutlineItem[]) => void = () => {};
  @Prop sourceJumpToken: number = 0;
  onClose: () => void = () => {};
  onSecondaryClosed: () => void = () => {};
  onSelectDocument: (id: string) => void = () => {};
  onCloseDocumentTab: (id: string) => void = () => {};
  onOpenSplitPicker: () => void = () => {};
  onSplitDocument: (id: string) => void = () => {};
  onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onSaveStateChange: (state: string) => void = () => {};
  onToggleFavorite: (note: NoteItem) => void = () => {};
  onDeleteNote: (note: NoteItem) => void = () => {};
  onChooseCover: (note: NoteItem) => void = () => {};
  onOpenNoteByTitle: (title: string) => void = () => {};
  onCreateHandwriting: () => void = () => {};
  onSearchNotes: () => void = () => {};
  onSmartExtract: () => void = () => {};
  onExtractPdfText: (noteId: string, page: number) => void = () => {};
  onRestorePdfSource: (note: NoteItem) => Promise<void> = async () => {};
  onExportText: (note: NoteItem, extension: string) => Promise<DocumentTransferResult> = async () => ({ status: 'failed', message: '导出未完成' });
  onReadingPageChange: (noteId: string, page: number, at: number) => Promise<void> = async () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @State private saveToken: number = 0;
  @State private primaryBackToken: number = 0;
  @State private primaryScratchpad: boolean = false;
  @State private secondaryScratchpad: boolean = false;
  @State private busy: boolean = false;
  @State private failed: boolean = false;
  @State private draggedId: string = '';
  @State private overDrop: boolean = false;
  private expected: Set<string> = new Set();
  private states: Map<string, string> = new Map();
  private pendingAction: () => void = () => {};
  private anyFailed: boolean = false;
  private ignoreTabClickUntil: number = 0;
  private previousKeyboardMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;

  aboutToAppear(): void {
    if (!this.manageKeyboardMode) { return; }
    this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }
  aboutToDisappear(): void {
    // Page bitmaps are only borrowed for the lifetime of the reader; do not retain 1200x1800
    // textures after the user returns to the library.
    PdfDocumentService.getInstance().clearPageCache();
    if (this.manageKeyboardMode) { this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode); }
  }

  private requestBack(): void { if (!this.busy) { this.primaryBackToken++; } }

  private updateState(id: string, state: string): void {
    this.states.set(id, state);
    const visible = [this.states.get(this.note.id) || SAVE_IDLE];
    if (this.secondaryNote) { visible.push(this.states.get(this.secondaryNote.id) || SAVE_IDLE); }
    const error = visible.find((value: string) => value !== SAVE_IDLE && value !== SAVE_SAVING);
    this.onSaveStateChange(this.busy ? SAVE_SAVING : error || (visible.includes(SAVE_SAVING) ? SAVE_SAVING : SAVE_IDLE));
  }

  private saveBefore(action: () => void): void {
    if (this.busy) { return; }
    this.pendingAction = action; this.anyFailed = false; this.failed = false;
    this.expected = new Set([this.note.id]);
    if (this.secondaryNote) { this.expected.add(this.secondaryNote.id); }
    this.busy = true; this.onSaveStateChange(SAVE_SAVING); this.saveToken++;
  }

  private saved(ok: boolean, id: string, token: number): void {
    if (!this.busy || token !== this.saveToken || !this.expected.has(id)) { return; }
    this.expected.delete(id); this.anyFailed = this.anyFailed || !ok;
    this.states.set(id, ok ? SAVE_IDLE : SAVE_FAILED);
    if (this.expected.size) { return; }
    this.busy = false; this.failed = this.anyFailed;
    this.onSaveStateChange(this.failed ? SAVE_FAILED : SAVE_IDLE);
    if (this.failed) { promptAction.showToast({ message: '保存未完成，内容和当前分屏已保留，请重试', duration: 2200 }); }
    else { this.pendingAction(); }
  }

  private selectTab(id: string): void {
    if (this.draggedId || Date.now() < this.ignoreTabClickUntil || id === this.note.id || id === this.secondaryNote?.id) { return; }
    this.saveBefore(() => this.onSelectDocument(id));
  }

  private dropDocument(): void {
    const id = this.draggedId;
    this.draggedId = ''; this.overDrop = false;
    if (!id || id === this.note.id || !this.documentTabs.some((item: NoteItem) => item.id === id)) { return; }
    this.saveBefore(() => this.onSplitDocument(id));
  }

  @Builder
  tabs() {
    Row({ space: 4 }) {
      IconButton({ icon: $r('app.media.ic_back'), label: '返回资料库', compact: true, available: !this.busy, onAction: () => this.requestBack() })
      if (WorkspaceNotePolicy.isFreeCanvas(this.note) && !this.secondaryNote) {
        Blank()
      } else {
      Scroll() {
        Row({ space: 4 }) {
          ForEach(this.documentTabs, (item: NoteItem) => {
            Row({ space: 0 }) {
              Button({ type: ButtonType.Normal }) {
                Text(item.title).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor(ThemeHelper.paletteOfDark(this.dark, this.style).inkPrimary)
              }.height(44).padding({ left: 12, right: 6 }).constraintSize({ maxWidth: this.phone ? 132 : 200 }).backgroundColor(Color.Transparent)
                .accessibilityText('打开资料 ' + item.title).onClick(() => this.selectTab(item.id))
                .draggable(!this.busy).onDragStart((): DragItemInfo => { this.draggedId = item.id; return { extraInfo: item.id }; })
                .onDragEnd(() => { this.draggedId = ''; this.overDrop = false; this.ignoreTabClickUntil = Date.now() + 200; })
                .accessibilityDescription('拖到阅读区右半边可分屏')
              IconButton({ icon: $r('app.media.ic_close'), label: '关闭标签 ' + item.title, compact: true,
                onAction: () => this.saveBefore(() => this.onCloseDocumentTab(item.id)) })
            }.backgroundColor(item.id === this.note.id || item.id === this.secondaryNote?.id ? ThemeHelper.paletteOfDark(this.dark, this.style).activeBg : Color.Transparent)
              .borderRadius(5)
          }, (item: NoteItem) => `${item.id}-${item.title}`)
        }
      }.layoutWeight(1).height(48).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      if (this.failed) {
        Button('重试保存').height(44).onClick(() => this.saveBefore(this.pendingAction))
      }
      IconButton({ icon: $r('app.media.ic_search'), label: '搜索并打开资料', compact: true, available: !this.busy,
        onAction: () => this.saveBefore(this.onSearchNotes) })
      IconButton({ icon: $r('app.media.ic_split'), label: this.secondaryNote ? '更换分屏资料' : '分屏阅读', compact: true,
        available: !this.busy, onAction: () => this.saveBefore(this.onOpenSplitPicker) })
      if (this.secondaryNote) {
        IconButton({ icon: $r('app.media.ic_close'), label: '收起分屏资料', compact: true, available: !this.busy,
          onAction: () => this.saveBefore(this.onSecondaryClosed) })
      }
    }.width('100%').height(52).padding({ left: 4, right: 4 }).backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.style).surface)
  }

  @Builder
  pane(item: NoteItem, secondary: boolean) {
    if (ReaderPairPolicy.isMarkdown(item)) {
      ReaderWorkspace({ note: item, paneMode: true, compactPane: this.secondaryNote !== null, companionPane: secondary, manageKeyboardMode: false, favorite: item.favorite === true,
        backRequestToken: secondary ? 0 : this.primaryBackToken, hostSaveToken: this.saveToken,
        jumpToken: secondary ? 0 : this.jumpToken, jumpLine: secondary ? -1 : this.jumpLine,
        onOutlineUpdated: (items: MarkdownOutlineItem[]) => { if (!secondary) { this.onOutlineUpdated(items); } },
        annotationPaneOpen: secondary ? this.secondaryScratchpad : this.primaryScratchpad,
        onHostSaveFinished: (ok: boolean, id: string, token: number) => this.saved(ok, id, token),
        onToggleAnnotation: () => { if (secondary) { this.secondaryScratchpad = !this.secondaryScratchpad; } else { this.primaryScratchpad = !this.primaryScratchpad; } },
        onBack: () => this.saveBefore(secondary ? this.onSecondaryClosed : this.onClose),
        onToggleFavorite: this.onToggleFavorite, onSaved: this.onSaved,
        onDeleteNote: (note: NoteItem) => this.saveBefore(() => this.onDeleteNote(note)),
        onChooseCover: () => this.saveBefore(() => this.onChooseCover(item)),
        onOpenNoteByTitle: (title: string) => this.saveBefore(() => this.onOpenNoteByTitle(title)),
        onSaveStateChange: (state: string) => this.updateState(item.id, state) })
    } else {
      HuaweiDocWorkspace({ note: item, paneMode: true, isFreeCanvas: WorkspaceNotePolicy.isFreeCanvas(item),
        backRequestToken: secondary ? 0 : this.primaryBackToken, hostSaveToken: this.saveToken,
        sourcePage: secondary ? item.readPage || 1 : this.sourcePage, sourceJumpToken: secondary ? 0 : this.sourceJumpToken,
        onHostSaveFinished: (ok: boolean, id: string, token: number) => this.saved(ok, id, token),
        onSaved: this.onSaved, onCommitForExit: this.onSaved, onReadingPageChange: this.onReadingPageChange,
        onClose: () => {
          // A single pane already saved itself in HuaweiDocWorkspace before invoking this
          // callback. Wrapping it in saveBefore starts a second host-save round through a
          // @Builder function prop, which can leave `busy` stuck and make Back a no-op.
          if (secondary || this.secondaryNote) { this.saveBefore(secondary ? this.onSecondaryClosed : this.onClose); }
          else { this.onClose(); }
        },
        onToggleFavorite: this.onToggleFavorite,
        onCreateHandwriting: () => this.saveBefore(this.onCreateHandwriting),
        onSearchNotes: () => this.saveBefore(this.onSearchNotes), onSmartExtract: () => this.saveBefore(this.onSmartExtract),
        onExtractPdfText: (page: number) => this.saveBefore(() => this.onExtractPdfText(item.id, page)),
        onRestorePdfSource: () => this.onRestorePdfSource(item), onExportText: (extension: string) => this.onExportText(item, extension),
        onSaveStateChange: (state: string) => this.updateState(item.id, state) })
    }
  }

  build() {
    Column() {
      this.tabs()
      Stack({ alignContent: Alignment.TopStart }) {
        Flex({ direction: this.phone ? FlexDirection.Column : FlexDirection.Row }) {
          Column() { this.pane(this.note, false) }.layoutWeight(1).height(this.phone && this.secondaryNote ? undefined : '100%').clip(true)
          if (this.secondaryNote) {
            Divider().vertical(!this.phone).strokeWidth(1).color(ThemeHelper.paletteOfDark(this.dark, this.style).borderSubtle)
            Column() { this.pane(this.secondaryNote, true) }.layoutWeight(1).height(this.phone ? undefined : '100%').clip(true)
          }
        }.width('100%').height('100%').enabled(!this.busy)
        if (this.draggedId && this.draggedId !== this.note.id) {
          Column({ space: 12 }) {
            Text('放到这里分屏阅读').fontSize(18).fontColor(ThemeHelper.paletteOfDark(this.dark, this.style).inkPrimary)
            Text('支持不同格式，也可打开两份同格式资料').fontSize(13).fontColor(ThemeHelper.paletteOfDark(this.dark, this.style).inkSecondary)
          }.width('50%').height('100%').position({ x: '50%', y: 0 }).justifyContent(FlexAlign.Center)
            .backgroundColor(this.overDrop ? ThemeHelper.paletteOfDark(this.dark, this.style).activeBg : ThemeHelper.paletteOfDark(this.dark, this.style).surface).border({ width: 2, color: ThemeHelper.paletteOfDark(this.dark, this.style).accent })
            .zIndex(100).accessibilityText('右侧分屏放置区')
            .onDragEnter(() => { this.overDrop = true; }).onDragLeave(() => { this.overDrop = false; }).onDrop(() => this.dropDocument())
        }
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.style).canvas)
  }
}
