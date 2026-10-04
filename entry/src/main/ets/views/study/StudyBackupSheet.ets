import { common } from '@kit.AbilityKit';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { ReviewCard } from '../../common/types/StudyTypes';
import { StudyBackup } from '../../common/types/StudyBackup';
import { StudyBackupPolicy } from '../../services/study/StudyBackupPolicy';
import { StudyBackupService } from '../../services/study/StudyBackupService';

@Component
export struct StudyBackupSheet {
  @Prop notes: NoteItem[] = [];
  @Prop cards: ReviewCard[] = [];
  @Prop @Watch('closeRequested') closeToken: number = 0;
  onClose: () => void = () => {};
  onRestore: (note: NoteItem, cards: ReviewCard[]) => Promise<void> = async () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @State course: string = '';
  @State backup: StudyBackup | null = null;
  @State busy: boolean = false;
  @State status: string = '';
  private alive: boolean = true;
  aboutToAppear(): void { this.alive = true; }
  aboutToDisappear(): void { this.alive = false; }
  private closeRequested(): void { if (!this.busy) { this.onClose(); } }
  private palette() { return ThemeHelper.paletteOfDark(this.dark); }
  private async exportFile(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const notes = this.notes.filter((note: NoteItem) => !this.course || (note.category || '未分类') === this.course);
      if (!notes.length) { throw new Error('此课程没有资料，请核对分类名'); }
      const ok = await StudyBackupService.exportFile(getContext(this) as common.UIAbilityContext, notes, this.cards);
      if (this.alive) { this.status = ok ? '学习资料备份已导出。建议先在另一设备验证恢复。' : '已取消导出'; }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '导出失败'; } }
    finally { if (this.alive) { this.busy = false; } }
  }
  private async selectFile(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try { this.backup = await StudyBackupService.selectFile(getContext(this) as common.UIAbilityContext); this.status = this.backup ? '请核对数量，确认后按副本导入。' : '已取消选择'; }
    catch (error) { this.status = (error as Error).message || '备份无法读取'; }
    finally { if (this.alive) { this.busy = false; } }
  }
  private async restore(): Promise<void> {
    const backup = this.backup;
    if (!backup || this.busy) { return; } this.busy = true;
    let restored = 0; let skipped = 0;
    try {
      for (let i = 0; i < backup.notes.length; i++) {
        const id = StudyBackupPolicy.restoreId(backup, i);
        const existing = this.notes.find((note: NoteItem) => note.id === id);
        this.status = `正在导入 ${i + 1}/${backup.notes.length}…`;
        const note = existing || await StudyBackupService.materialize(getContext(this) as common.UIAbilityContext, backup, i, StudyBackupPolicy.restoreTitle(backup, i));
        const cards = backup.cards.filter((card: ReviewCard) => card.noteId === backup.notes[i].id).map((card: ReviewCard, cardIndex: number): ReviewCard => ({
          id: `restorecard_${backup.id}_${i}_${cardIndex}`, noteId: id, course: note.category || '未分类', question: card.question,
          answer: card.answer, sourceText: card.sourceText, pageNumber: card.pageNumber, dueAt: card.dueAt,
          intervalDays: card.intervalDays, repetitions: card.repetitions, reviewCount: card.reviewCount, lapses: card.lapses, createdAt: card.createdAt,
          updatedAt: card.updatedAt, lastRating: card.lastRating }));
        await this.onRestore(note, cards); if (existing) { skipped++; } else { restored++; }
      }
      this.status = `已导入 ${restored} 份资料，跳过 ${skipped} 份已恢复资料。原资料保留。`;
    } catch (error) { this.status = `已导入 ${restored} 份。${(error as Error).message || '导入中断'}；可重试，已导入资料会跳过。`; }
    finally { if (this.alive) { this.busy = false; } }
  }
  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('学习资料备份').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
          Button('关闭').height(44).enabled(!this.busy).onClick(() => this.onClose())
        }.width('100%')
        Scroll() {
        Column({ space: 12 }) {
        Text('包含笔记、原 PDF、自定义封面、笔迹、已提取页面和复习题卡。日历、回收站、会话与模型密钥不在此备份内。')
          .fontSize(14).fontColor(this.palette().inkSecondary).width('100%')
        Text('文件未加密，请保存到可信位置；可自行存到系统文件选择器支持的网盘。恢复会创建副本，每份资料独立保存。')
          .fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
        Text('随包示例只备份现有正文与笔迹，恢复后仍标为示例，不包含原 PDF。').fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
        Text('单个附件最多 16 MB，备份文件最多 32 MB。资料较多时可按课程分批导出。').fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
        TextInput({ text: this.course, placeholder: '只备份某课程：填写分类名；留空备份全部' }).enabled(!this.busy).onChange((value: string) => { this.course = value.trim(); })
        Button('导出学习资料').height(44).width('100%').enabled(!this.busy).onClick(() => this.exportFile())
        Button('选择备份文件').height(44).width('100%').enabled(!this.busy).onClick(() => this.selectFile())
        if (this.backup) {
          Text(`${this.backup.notes.length} 份资料 · ${this.backup.cards.length} 道题卡 · ${this.backup.assets.length} 个附件`)
            .fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
          Button('确认导入为副本').height(44).width('100%').enabled(!this.busy).onClick(() => this.restore())
        }
        if (this.status) { Text(this.status).fontSize(13).fontColor(this.palette().accent).width('100%') }
        }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }.padding(20).width(this.phone ? '94%' : 580).height('86%').borderRadius(18).backgroundColor(this.palette().surface)
        .onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.4)').onClick(() => { if (!this.busy) { this.onClose(); } })
  }
}
