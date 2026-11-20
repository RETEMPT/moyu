import { common } from '@kit.AbilityKit';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { ReviewCard } from '../../common/types/StudyTypes';
import { StudyBackup } from '../../common/types/StudyBackup';
import { AnimationTokens } from '../../common/constants/DesignTokens';
import { SpaceFolder } from '../../common/types/SpaceFolder';
import { buildSpaces } from '../../services/WorkspaceBuilder';
import { projectIcon } from '../../common/utils/ProjectIcons';
import { StudyBackupService } from '../../services/study/StudyBackupService';
import { StudyImportService } from '../../services/study/StudyImportService';
import { StudyShareInbox } from '../../services/study/StudyShareInbox';
import { SystemShareService } from '../../services/SystemShareService';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';

interface ShareFolder { id: string; name: string; icon?: string; notes: NoteItem[]; }

@Component
export struct StudyBackupSheet {
  @Prop @Watch('onNotesChanged') notes: NoteItem[] = [];
  @Prop cards: ReviewCard[] = [];
  @Prop spaces: SpaceFolder[] = [];
  @Prop initialSelection: string[] = [];
  @Prop @Watch('closeRequested') closeToken: number = 0;
  onClose: () => void = () => {};
  onRestore: (note: NoteItem, cards: ReviewCard[]) => Promise<void> = async () => {};
  isInTrash: (id: string) => boolean = () => false;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @StorageProp('moyuStudyShareRevision') @Watch('observeReceived') shareRevision: number = 0;
  @State selectedIds: string[] = [];
  @State visibleCount: number = 40;
  @State visibleFolderCount: number = 40;
  @State openFolderId: string = '';
  @State receiving: boolean = false;
  @State sharedPending: boolean = false;
  @State previewCount: number = 0;
  @State previewNames: string[] = [];
  @State private previewFromShare: boolean = false;
  @State busy: boolean = false;
  @State status: string = '';
  private backup: StudyBackup | null = null;
  private alive: boolean = true;
  private cachedNotes: NoteItem[] | null = null;
  private cachedSpaces: SpaceFolder[] | null = null;
  private cachedFolders: ShareFolder[] = [];
  aboutToAppear(): void {
    this.alive = true;
    this.selectedIds = this.initialSelection.slice();
    this.onNotesChanged();
    this.observeReceived();
  }
  aboutToDisappear(): void { this.alive = false; }
  private closeRequested(): void { if (!this.busy) { this.onClose(); } }
  private palette() { return ThemeHelper.paletteOfDark(this.dark, this.themeStyle); }
  private observeReceived(): void {
    const received = StudyShareInbox.pending();
    this.sharedPending = received !== null;
    if (received && !this.busy && !this.backup) {
      this.receiving = true;
      this.setPreview(received, true);
    }
  }
  private setPreview(backup: StudyBackup | null, fromShare: boolean = false): void {
    this.backup = backup;
    this.previewFromShare = fromShare;
    this.previewCount = backup?.notes.length || 0;
    this.previewNames = backup ? backup.notes.slice(0, 5).map((note: NoteItem) => note.title || '未命名资料') : [];
  }
  private discardPreview(): void {
    const sharedId = this.previewFromShare ? this.backup?.id : undefined;
    this.setPreview(null);
    if (sharedId) { StudyShareInbox.dismiss(sharedId); }
  }
  private showReceived(): void {
    const received = StudyShareInbox.pending();
    if (received) { this.status = ''; this.setPreview(received, true); }
  }
  private onNotesChanged(): void {
    const available = new Set(this.notes.map((note: NoteItem) => note.id));
    this.selectedIds = this.selectedIds.filter((id: string) => available.has(id));
  }
  private selectedNotes(): NoteItem[] {
    const selected = new Set(this.selectedIds);
    return this.notes.filter((note: NoteItem) => selected.has(note.id));
  }
  private folders(): ShareFolder[] {
    if (this.cachedNotes !== this.notes || this.cachedSpaces !== this.spaces) {
      this.cachedFolders = buildSpaces(this.notes, this.spaces, [], true).filter((folder: SpaceFolder) => (folder.notes || []).length > 0)
        .map((folder: SpaceFolder): ShareFolder => ({ id: folder.id, name: folder.name, icon: folder.icon, notes: folder.notes || [] }));
      this.cachedNotes = this.notes; this.cachedSpaces = this.spaces;
    }
    return this.cachedFolders;
  }
  private folderSelectedCount(folder: ShareFolder): number {
    const selected = new Set(this.selectedIds);
    return folder.notes.filter((note: NoteItem) => selected.has(note.id)).length;
  }
  private toggleFolder(folder: ShareFolder): void {
    if (this.busy) { return; }
    const selected = new Set(this.selectedIds);
    const all = folder.notes.every((note: NoteItem) => selected.has(note.id));
    folder.notes.forEach((note: NoteItem) => { if (all) { selected.delete(note.id); } else { selected.add(note.id); } });
    this.selectedIds = Array.from(selected);
  }
  private toggleNote(id: string): void {
    if (this.busy) { return; }
    this.selectedIds = this.selectedIds.includes(id) ? this.selectedIds.filter((value: string) => value !== id) : this.selectedIds.concat(id);
  }
  private async exportFile(): Promise<void> {
    if (this.busy || this.selectedNotes().length === 0) { return; }
    this.busy = true; this.status = '正在准备所选资料…';
    try {
      const ok = await StudyBackupService.exportFile(getContext(this) as common.UIAbilityContext, this.selectedNotes(), this.cards);
      if (this.alive) { this.status = ok ? '资料包已保存' : ''; }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '导出失败，请重试'; } }
    finally { if (this.alive) { this.busy = false; } }
  }
  private async shareSelected(): Promise<void> {
    if (this.busy || this.selectedNotes().length === 0) { return; }
    if (!SystemShareService.available()) { this.status = '此设备可导出资料包，再从文件应用发送。'; return; }
    this.busy = true; this.status = '正在准备所选资料…';
    const notes = this.selectedNotes();
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const source = await StudyBackupService.createShareFile(context, notes, this.cards);
      if (!this.alive) { return; }
      await SystemShareService.shareBackup(context, source, notes.length);
      if (this.alive) { this.status = '已打开系统分享，请选择接收设备并确认。'; }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '无法打开系统分享，请重试'; } }
    finally { if (this.alive) { this.busy = false; } }
  }
  private async selectFile(): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.status = '';
    try {
      const backup = await StudyBackupService.selectFile(getContext(this) as common.UIAbilityContext);
      if (this.alive && backup) { this.setPreview(backup); }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '资料包无法读取'; } }
    finally { if (this.alive) { this.busy = false; } }
  }
  private async restore(): Promise<void> {
    const backup = this.backup;
    if (!backup || this.busy) { return; } this.busy = true;
    try {
      const result = await StudyImportService.restore(getContext(this) as common.UIAbilityContext, backup, {
        notes: () => this.notes, isInTrash: this.isInTrash, commit: this.onRestore,
        progress: (message: string) => { if (this.alive) { this.status = message; } }
      });
      if (this.alive) {
        this.status = `已导入 ${result.imported} 份资料，跳过 ${result.skipped} 份已有副本`;
        this.discardPreview();
      }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '导入中断，可重试'; } }
    finally { if (this.alive) { this.busy = false; } }
  }
  @Builder
  folderRow(folder: ShareFolder) {
    Row({ space: 2 }) {
      Button({ type: ButtonType.Normal }) {
        AppIcon({ source: this.folderSelectedCount(folder) === folder.notes.length ? $r('app.media.ic_check') :
          this.folderSelectedCount(folder) > 0 ? $r('app.media.ic_checkbox_partial') : $r('app.media.ic_checkbox_empty'),
          iconSize: 22, tint: this.palette().inkSecondary })
      }.width(44).height(48).padding(0).backgroundColor(Color.Transparent).enabled(!this.busy)
        .accessibilityText('选择整个文件夹 ' + folder.name)
        .accessibilityDescription(this.folderSelectedCount(folder) === folder.notes.length ? '全部已选' : this.folderSelectedCount(folder) > 0 ? '部分已选' : '未选择')
        .onClick(() => this.toggleFolder(folder))
      Button({ type: ButtonType.Normal }) {
        Row({ space: 9 }) {
          AppIcon({ source: projectIcon(folder.icon || ''), iconSize: 20, tint: this.palette().inkSecondary })
          Text(folder.name).fontSize(15).fontColor(this.palette().inkPrimary).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Start)
          Text(`${folder.notes.length}`).fontSize(13).fontColor(this.palette().inkMuted)
          AppIcon({ source: this.openFolderId === folder.id ? $r('app.media.ic_chevron_up') : $r('app.media.ic_chevron_right'), iconSize: 15, tint: this.palette().inkMuted })
        }.width('100%')
      }.layoutWeight(1).height(48).padding({ left: 0, right: 8 }).backgroundColor(Color.Transparent).enabled(!this.busy)
        .accessibilityText('展开分享文件夹 ' + folder.name).accessibilityDescription(this.openFolderId === folder.id ? '已展开' : '已收起')
        .onClick(() => { this.openFolderId = this.openFolderId === folder.id ? '' : folder.id; this.visibleCount = 40; })
    }.width('100%').borderRadius(5).backgroundColor(this.folderSelectedCount(folder) > 0 ? this.palette().activeBg : Color.Transparent)
  }
  @Builder
  noteRow(note: NoteItem) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        AppIcon({ source: this.selectedIds.includes(note.id) ? $r('app.media.ic_check') : $r('app.media.ic_checkbox_empty'), iconSize: 22, tint: this.palette().inkSecondary })
        Text(note.title || '未命名资料').fontSize(15).fontColor(this.palette().inkPrimary).layoutWeight(1).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Start)
      }.width('100%')
    }.width('100%').height(48).padding({ left: 38, right: 8 }).borderRadius(5)
      .backgroundColor(this.selectedIds.includes(note.id) ? this.palette().activeBg : Color.Transparent).enabled(!this.busy)
      .accessibilityText('选择快传资料 ' + note.title).accessibilityDescription(this.selectedIds.includes(note.id) ? '已选择' : '未选择')
      .onClick(() => this.toggleNote(note.id))
  }
  @Builder
  sendPanel() {
    Row() {
      Text(`已选 ${this.selectedIds.length} 份`).fontSize(14).fontColor(this.palette().inkPrimary).layoutWeight(1)
      Button(this.selectedIds.length === this.notes.length && this.notes.length > 0 ? '取消全选' : '全选', { type: ButtonType.Normal })
        .height(44).backgroundColor(Color.Transparent).fontColor(this.palette().inkSecondary).enabled(!this.busy && this.notes.length > 0)
        .onClick(() => { this.selectedIds = this.selectedIds.length === this.notes.length ? [] : this.notes.map((note: NoteItem) => note.id); })
    }.width('100%')
    List() {
      ForEach(this.folders().slice(0, this.visibleFolderCount), (folder: ShareFolder) => {
        ListItem() { this.folderRow(folder) }
        if (this.openFolderId === folder.id) {
          ForEach(folder.notes.slice(0, this.visibleCount), (note: NoteItem) => {
            ListItem() { this.noteRow(note) }
          }, (note: NoteItem) => note.id)
          if (this.visibleCount < folder.notes.length) {
            ListItem() { Button('显示更多资料').height(44).width('100%').enabled(!this.busy).onClick(() => { this.visibleCount += 40; }) }
          }
        }
      }, (folder: ShareFolder) => folder.id)
      if (this.visibleFolderCount < this.folders().length) {
        ListItem() { Button('显示更多文件夹').height(44).width('100%').enabled(!this.busy).onClick(() => { this.visibleFolderCount += 40; }) }
      }
      if (this.notes.length === 0) {
        ListItem() { Text('还没有可分享的资料').fontSize(14).fontColor(this.palette().inkMuted).padding(16) }
      }
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    Row({ space: 10 }) {
      Button('导出文件', { type: ButtonType.Normal }).height(44).layoutWeight(1).borderRadius(6).fontColor(this.palette().inkPrimary)
        .backgroundColor(this.palette().surfaceSubtle).enabled(!this.busy && this.selectedIds.length > 0).onClick(() => this.exportFile())
      Button('附近快传', { type: ButtonType.Normal }).height(44).layoutWeight(1).borderRadius(6).fontColor(this.palette().onAccent)
        .backgroundColor(this.palette().accent).enabled(!this.busy && this.selectedIds.length > 0).onClick(() => this.shareSelected())
    }.width('100%')
  }

  @Builder
  receivePanel() {
    Scroll() {
      Column({ space: 12 }) {
        Text('在系统分享面板选墨语，或从文件中选择收到的资料包。')
          .fontSize(14).fontColor(this.palette().inkSecondary).width('100%')
        if (this.sharedPending && !this.previewFromShare) {
          Button('查看收到的资料包', { type: ButtonType.Normal }).height(44).width('100%').enabled(!this.busy)
            .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle).onClick(() => this.showReceived())
        }
        if (this.previewCount > 0) {
          Column({ space: 8 }) {
            Text(`${this.previewCount} 份资料待导入`).fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkPrimary).width('100%')
            ForEach(this.previewNames, (name: string) => {
              Text(name).fontSize(14).fontColor(this.palette().inkSecondary).width('100%').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }, (name: string, index: number) => `${index}:${name}`)
            if (this.previewCount > this.previewNames.length) {
              Text(`另有 ${this.previewCount - this.previewNames.length} 份`).fontSize(13).fontColor(this.palette().inkMuted).width('100%')
            }
          }.width('100%').padding(14).borderRadius(10).backgroundColor(this.palette().surfaceSubtle)
          Button(this.previewFromShare ? '忽略收到的资料包' : '取消预览', { type: ButtonType.Normal })
            .height(44).width('100%').enabled(!this.busy).fontColor(this.palette().inkSecondary)
            .backgroundColor(Color.Transparent).onClick(() => this.discardPreview())
        }
      }.width('100%')
    }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto)
    Row({ space: 10 }) {
      Button('选择资料包', { type: ButtonType.Normal }).height(44).layoutWeight(1).borderRadius(6)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle).enabled(!this.busy).onClick(() => this.selectFile())
      if (this.previewCount > 0) {
        Button('确认导入为副本', { type: ButtonType.Normal }).height(44).layoutWeight(1).borderRadius(6)
          .fontColor(this.palette().onAccent).backgroundColor(this.palette().accent).enabled(!this.busy).onClick(() => this.restore())
      }
    }.width('100%')
  }

  @Builder
  transferTab(title: string, receive: boolean) {
    Button(title, { type: ButtonType.Normal }).height(44).layoutWeight(1).borderRadius(8)
      .fontColor(this.receiving === receive ? this.palette().inkPrimary : this.palette().inkMuted)
      .backgroundColor(this.receiving === receive ? this.palette().activeBg : Color.Transparent)
      .accessibilityDescription(this.receiving === receive ? '已选中' : '未选中')
      .enabled(!this.busy).onClick(() => {
        if (this.receiving === receive) { return; }
        this.receiving = receive;
        this.status = '';
        if (receive && !this.backup) { this.showReceived(); }
      })
  }

  build() {
    Stack({ alignContent: this.phone ? Alignment.Bottom : Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor(this.dark ? 'rgba(0,0,0,0.42)' : 'rgba(0,0,0,0.20)')
        .onClick(() => this.closeRequested())
      Column({ space: 10 }) {
        Row() {
          Text('备份与快传').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
          IconButton({ icon: $r('app.media.ic_close'), label: '关闭资料快传', available: !this.busy, onAction: this.onClose })
        }.width('100%')
        Row({ space: 4 }) {
          this.transferTab('发送与导出', false)
          this.transferTab(this.sharedPending ? '接收 · 1' : '接收', true)
        }.width('100%').padding(3).borderRadius(10).backgroundColor(this.palette().surfaceSubtle)
        if (this.receiving) { this.receivePanel() } else { this.sendPanel() }
        if (this.status) {
          Text(this.status).fontSize(13).fontColor(this.palette().inkSecondary).width('100%').maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.padding(this.phone ? 16 : 24).width('94%').height('86%').constraintSize({ maxWidth: 560 })
        .margin({ bottom: this.phone ? 12 : 0 }).borderRadius(18).backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().borderSubtle }).onClick(() => {})
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: this.phone ? 24 : 8 }))
          .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_SMOOTH }))
    }.width('100%').height('100%')
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_SMOOTH }))
  }
}
