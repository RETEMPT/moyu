import { promptAction } from '@kit.ArkUI';
import { NoteItem } from '../../common/types/NoteItem';
import { ReaderSaveKind } from '../../common/types/ReaderSaveKind';
import { MarkdownOutlineItem } from '../../common/types/MarkdownOutlineItem';
import { SAVE_IDLE, SAVE_SAVING, SAVE_FAILED } from '../../common/constants/WorkspaceConstants';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { MarkdownReader } from './MarkdownReader';
import { HandwritingCanvas } from './HandwritingCanvas';

/** Text-only reader. PDF, image and handwriting documents are routed by Index to HuaweiDocWorkspace. */
@Component
export struct ReaderWorkspace {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop backRequestToken: number = 0;
  @Prop manageKeyboardMode: boolean = true;
  @Prop compactPane: boolean = false;
  @Prop companionPane: boolean = false;
  @Prop paneMode: boolean = false;
  @Prop @Watch('saveForHost') hostSaveToken: number = 0;
  onHostSaveFinished: (ok: boolean, noteId: string, token: number) => void = () => {};
  @Prop annotationPaneOpen: boolean = false;
  @Prop jumpToken: number = 0;
  @Prop jumpLine: number = -1;
  @Prop favorite: boolean = false;
  onBack: () => void = () => {};
  onOpenCompanion: () => void = () => {};
  @Prop showCompanionAction: boolean = false;
  onToggleAnnotation: () => void = () => {};
  onToggleFavorite: (note: NoteItem) => void = () => {};
  onDeleteNote: (note: NoteItem) => void = () => {};
  onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onChooseCover: () => void = () => {};
  onSaveStateChange: (state: string) => void = () => {};
  onOutlineUpdated: (items: MarkdownOutlineItem[]) => void = () => {};
  onOpenNoteByTitle: (title: string) => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @State private inkExitToken: number = 0;
  @State private closingInk: boolean = false;
  @State private textSaveToken: number = 0;
  @State private closingText: boolean = false;
  private lastNoteId: string = '';
  private textState: string = SAVE_IDLE;
  private inkState: string = SAVE_IDLE;
  private inkDestination: string = '';

  aboutToAppear(): void { this.lastNoteId = this.note.id; }
  private onNoteChanged(): void {
    if (this.lastNoteId === this.note.id) { return; }
    this.lastNoteId = this.note.id; this.textState = SAVE_IDLE; this.inkState = SAVE_IDLE;
    this.inkDestination = ''; this.closingInk = false;
  }

  private updateSaveState(area: string, state: string): void {
    if (area === 'text') { this.textState = state; } else { this.inkState = state; }
    const failure = [this.textState, this.inkState].find((value: string) => value !== SAVE_IDLE && value !== SAVE_SAVING);
    this.onSaveStateChange(failure || (this.textState === SAVE_SAVING || this.inkState === SAVE_SAVING ? SAVE_SAVING : SAVE_IDLE));
  }

  private requestClose(): void {
    if (this.textState !== SAVE_IDLE) {
      promptAction.showToast({ message: '请等待正文保存完成；失败时请先重试', duration: 2000 }); return;
    }
    if (this.annotationPaneOpen) { this.saveInkBeforeLeaving('reader'); }
    else { this.onBack(); }
  }

  private saveForHost(): void {
    if (this.closingText || this.closingInk) { this.onHostSaveFinished(false, this.note.id, this.hostSaveToken); return; }
    this.closingText = true; this.textSaveToken++;
  }

  private textSaveFinished(ok: boolean, noteId: string, token: number): void {
    if (!this.closingText || noteId !== this.note.id || token !== this.textSaveToken) { return; }
    this.closingText = false;
    if (!ok) { this.onHostSaveFinished(false, noteId, this.hostSaveToken); return; }
    if (this.annotationPaneOpen) { this.saveInkBeforeLeaving('host'); }
    else { this.onHostSaveFinished(true, noteId, this.hostSaveToken); }
  }

  private toggleAnnotation(): void {
    if (this.annotationPaneOpen) { this.saveInkBeforeLeaving('pane'); }
    else { this.onToggleAnnotation(); }
  }

  private requestCompanion(): void {
    if (this.annotationPaneOpen) { this.saveInkBeforeLeaving('companion'); }
    else { this.onOpenCompanion(); }
  }

  private saveInkBeforeLeaving(destination: string): void {
    if (this.closingInk) { return; }
    this.inkDestination = destination; this.closingInk = true; this.inkExitToken++;
  }

  private inkExitFinished(ok: boolean, noteId: string, token: number): void {
    if (!this.closingInk || noteId !== this.note.id || token !== this.inkExitToken) { return; }
    this.closingInk = false;
    if (!ok) {
      this.updateSaveState('ink', SAVE_FAILED);
      if (this.inkDestination === 'host') { this.onHostSaveFinished(false, noteId, this.hostSaveToken); }
      return;
    }
    this.updateSaveState('ink', SAVE_IDLE);
    const destination = this.inkDestination; this.inkDestination = '';
    if (destination === 'host') { this.onHostSaveFinished(true, noteId, this.hostSaveToken); }
    else if (destination === 'reader') { this.onBack(); }
    else if (destination === 'companion') { this.onOpenCompanion(); }
    else { this.onToggleAnnotation(); }
  }

  build() {
    Row() {
      Column() {
        MarkdownReader({ note: this.note, compactPane: this.compactPane, companionPane: this.companionPane, showBackButton: !this.paneMode, manageKeyboardMode: this.manageKeyboardMode, backRequestToken: this.backRequestToken, inputLocked: this.closingInk || this.closingText,
          saveRequestToken: this.textSaveToken, onSaveRequestFinished: (ok: boolean, noteId: string, token: number) => this.textSaveFinished(ok, noteId, token),
          showCompanionAction: this.showCompanionAction, onOpenCompanion: () => this.requestCompanion(),
          onRequestClose: () => this.requestClose(), onChooseCover: this.onChooseCover,
          favorite: this.favorite, annotationPaneOpen: this.annotationPaneOpen,
          onToggleFavorite: () => this.onToggleFavorite(this.note), onDeleteNote: () => this.onDeleteNote(this.note),
          onToggleAnnotation: () => this.toggleAnnotation(), jumpToken: this.jumpToken, jumpLine: this.jumpLine,
          onSaved: this.onSaved, onSaveStateChange: (state: string) => this.updateSaveState('text', state),
          onOutlineUpdated: this.onOutlineUpdated, onOpenNoteByTitle: this.onOpenNoteByTitle })
      }.height('100%').layoutWeight(this.annotationPaneOpen ? 55 : 100)
      if (this.annotationPaneOpen) {
        Divider().vertical(true).strokeWidth(1).height('100%').color(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).borderSubtle)
        Column() {
          HandwritingCanvas({ note: this.note, isScratchpad: true, readOnly: this.closingInk,
            onSaved: this.onSaved, onCommitForExit: this.onSaved, exitSaveToken: this.inkExitToken,
            onDirtyChange: (dirty: boolean) => this.updateSaveState('ink', dirty ? SAVE_SAVING : SAVE_IDLE),
            onExitSaveFinished: (ok: boolean, noteId: string, token: number) => this.inkExitFinished(ok, noteId, token),
            onSaveStateChange: (state: string) => this.updateSaveState('ink', state) })
        }.height('100%').layoutWeight(45)
      }
    }.width('100%').height('100%').backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).canvas)
  }
}
