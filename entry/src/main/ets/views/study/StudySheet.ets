import { common } from '@kit.AbilityKit';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { ReviewCard, ReviewRating } from '../../common/types/StudyTypes';
import { ReviewPolicy } from '../../services/study/ReviewPolicy';
import { StudySourceService } from '../../services/study/StudySourceService';

@Component
export struct StudySheet {
  @Prop notes: NoteItem[] = [];
  @Prop cards: ReviewCard[] = [];
  @Prop course: string = '';
  @Prop initialNoteId: string = '';
  @Prop @Watch('closeRequested') closeToken: number = 0;
  onClose: () => void = () => {};
  onSave: (cards: ReviewCard[]) => Promise<void> = async () => {};
  onSource: (noteId: string, pageNumber?: number) => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @State noteId: string = '';
  @State tab: number = 0;
  @State question: string = '';
  @State answer: string = '';
  @State sourceText: string = '';
  @State reveal: boolean = false;
  @State busy: boolean = false;
  @State status: string = '';
  @State deleteWarning: string = '';
  @State noteFilter: string = '';
  @State notePage: number = 0;
  @State cardPage: number = 0;
  private alive: boolean = true;
  aboutToAppear(): void { this.alive = true; this.noteId = this.initialNoteId || this.availableNotes()[0]?.id || ''; }
  aboutToDisappear(): void { this.alive = false; }
  private closeRequested(): void { if (!this.busy) { this.onClose(); } }
  private palette() { return ThemeHelper.paletteOfDark(this.dark, this.themeStyle); }
  private availableNotes(): NoteItem[] { return this.notes.filter((note: NoteItem) => !this.course || (note.category || '未分类') === this.course); }
  private filteredNotes(): NoteItem[] { return this.availableNotes().filter((note: NoteItem) => note.title.toLowerCase().includes(this.noteFilter.toLowerCase())); }
  private activeCards(): ReviewCard[] {
    const ids = new Set(this.availableNotes().map((note: NoteItem) => note.id));
    return this.cards.filter((card: ReviewCard) => ids.has(card.noteId));
  }
  private dueCards(): ReviewCard[] { return this.activeCards().filter((card: ReviewCard) => card.dueAt <= Date.now()).sort((a: ReviewCard, b: ReviewCard) => a.dueAt - b.dueAt); }
  private selectedNote(): NoteItem | undefined { return this.notes.find((note: NoteItem) => note.id === this.noteId); }
  private async commit(next: ReviewCard[], message: string): Promise<boolean> {
    if (this.busy) { return false; }
    this.busy = true;
    try { await this.onSave(next); if (this.alive) { this.status = message; this.reveal = false; } return true; }
    catch { if (this.alive) { this.status = '保存失败，原复习记录已保留，请重试。'; } return false; }
    finally { if (this.alive) { this.busy = false; } }
  }
  private async manual(): Promise<void> {
    const note = this.selectedNote();
    if (!note) { this.status = '请先选择一份课程资料'; return; }
    try {
      const card = ReviewPolicy.create(note, { question: this.question, answer: this.answer, sourceText: this.sourceText });
      if (await this.commit(this.cards.concat([card]), '题卡已保存，可以开始自测。')) { this.question = ''; this.answer = ''; this.sourceText = ''; }
    } catch (error) { this.status = (error as Error).message; }
  }
  private async rate(card: ReviewCard, rating: ReviewRating): Promise<void> {
    const next = this.cards.map((item: ReviewCard) => item.id === card.id ? ReviewPolicy.rate(item, rating) : item);
    await this.commit(next, '已记录反馈并安排下次复习。');
  }
  @Builder
  reviewPanel() {
    if (this.dueCards().length > 0) {
      Column({ space: 12 }) {
        Text(this.dueCards()[0].question).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
        Text(`${this.notes.find((note: NoteItem) => note.id === this.dueCards()[0].noteId)?.category || '未分类'} · 已复习 ${this.dueCards()[0].reviewCount || 0} 次`).fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
        if (this.reveal) {
          Text(this.dueCards()[0].answer).fontSize(15).fontColor(this.palette().inkPrimary).width('100%')
          if (this.dueCards()[0].sourceText) { Text(`原文：${this.dueCards()[0].sourceText}`).fontSize(13).fontColor(this.palette().inkSecondary).width('100%') }
          Row({ space: 8 }) {
            Button('不会').height(44).layoutWeight(1).onClick(() => this.rate(this.dueCards()[0], 'again'))
            Button('模糊').height(44).layoutWeight(1).onClick(() => this.rate(this.dueCards()[0], 'hard'))
            Button('掌握').height(44).layoutWeight(1).onClick(() => this.rate(this.dueCards()[0], 'good'))
          }.width('100%').enabled(!this.busy)
        } else { Button('先回忆，再查看答案').height(44).width('100%').onClick(() => { this.reveal = true; }) }
        Button(this.dueCards()[0].pageNumber ? `查看原文第 ${this.dueCards()[0].pageNumber} 页` : '查看来源资料')
          .height(44).enabled(!this.busy).onClick(() => { const card = this.dueCards()[0]; this.onClose(); this.onSource(card.noteId, card.pageNumber); })
      }.padding(16).borderRadius(5).backgroundColor(this.palette().surfaceSubtle).width('100%')
    } else {
      Text(this.activeCards().length ? '本轮待复习已完成。下次到期后会出现在这里。' : '还没有题卡，先从一份课程资料创建。')
        .fontSize(15).fontColor(this.palette().inkSecondary).width('100%')
    }
    ForEach(this.activeCards().slice().sort((a: ReviewCard, b: ReviewCard) => a.dueAt - b.dueAt).slice(this.cardPage * 50, (this.cardPage + 1) * 50), (card: ReviewCard) => {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(card.question).fontSize(14).maxLines(2).fontColor(this.palette().inkPrimary)
          Text(`下次：${new Date(card.dueAt).toLocaleDateString()} · 遗忘 ${card.lapses} 次`).fontSize(12).fontColor(this.palette().inkSecondary)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button(this.deleteWarning === card.id ? '确认移除' : '移除').height(44).enabled(!this.busy).onClick(() => {
          if (this.deleteWarning !== card.id) { this.deleteWarning = card.id; }
          else { this.commit(this.cards.filter((item: ReviewCard) => item.id !== card.id), '题卡已移除'); this.deleteWarning = ''; this.cardPage = 0; }
        })
      }.width('100%').padding(8)
    }, (card: ReviewCard) => `${card.id}:${card.updatedAt}`)
    if (this.activeCards().length > 50) {
      Row({ space: 8 }) {
        Button('上一组').height(44).enabled(!this.busy && this.cardPage > 0).onClick(() => { this.cardPage--; })
        Text(`第 ${this.cardPage + 1}/${Math.ceil(this.activeCards().length / 50)} 组`).fontColor(this.palette().inkSecondary).layoutWeight(1).textAlign(TextAlign.Center)
        Button('下一组').height(44).enabled(!this.busy && (this.cardPage + 1) * 50 < this.activeCards().length).onClick(() => { this.cardPage++; })
      }.width('100%')
    }
  }
  @Builder
  createPanel() {
    Text('选择课程资料').fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
    TextInput({ text: this.noteFilter, placeholder: '按标题查找资料' }).enabled(!this.busy).onChange((value: string) => { this.noteFilter = value; this.notePage = 0; })
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.filteredNotes().slice(this.notePage * 20, (this.notePage + 1) * 20), (note: NoteItem) => {
          Button(note.title).height(44).backgroundColor(this.noteId === note.id ? this.palette().accent : this.palette().surfaceSubtle)
            .fontColor(this.noteId === note.id ? this.palette().onAccent : this.palette().inkPrimary).enabled(!this.busy)
            .onClick(() => { this.noteId = note.id; })
        }, (note: NoteItem) => note.id)
      }
    }.scrollable(ScrollDirection.Horizontal).width('100%')
    if (this.filteredNotes().length > 20) {
      Row({ space: 8 }) {
        Button('上一组资料').height(44).enabled(!this.busy && this.notePage > 0).onClick(() => { this.notePage--; })
        Text(`${this.notePage + 1}/${Math.ceil(this.filteredNotes().length / 20)}`).fontColor(this.palette().inkSecondary).layoutWeight(1).textAlign(TextAlign.Center)
        Button('下一组资料').height(44).enabled(!this.busy && (this.notePage + 1) * 20 < this.filteredNotes().length).onClick(() => { this.notePage++; })
      }.width('100%')
    }
    if (this.selectedNote()) { Text(`当前：${this.selectedNote()?.title}`).fontSize(13).fontColor(this.palette().inkSecondary).width('100%') }
    TextInput({ text: this.question, placeholder: '自测问题' }).maxLength(4000).enabled(!this.busy).onChange((value: string) => { this.question = value; })
    TextArea({ text: this.answer, placeholder: '参考答案' }).height(100).maxLength(12000).enabled(!this.busy).onChange((value: string) => { this.answer = value; })
    TextArea({ text: this.sourceText, placeholder: '引用原文（手动卡片可选）' }).height(70).maxLength(20000).enabled(!this.busy).onChange((value: string) => { this.sourceText = value; })
    Button('保存手动题卡').height(44).width('100%').enabled(!this.busy).onClick(() => this.manual())
  }
  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text(this.course ? `${this.course} · 复习` : '课程自测与复习').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1).maxLines(1)
          Button('关闭').height(44).enabled(!this.busy).onClick(() => this.closeRequested())
        }.width('100%')
        Text(`${this.activeCards().length} 道题卡 · ${this.dueCards().length} 道待复习`).fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
        Row({ space: 8 }) {
          Button('开始复习').height(44).layoutWeight(1).enabled(!this.busy).onClick(() => { this.tab = 0; })
          Button('创建题卡').height(44).layoutWeight(1).enabled(!this.busy).onClick(() => { this.tab = 1; })
        }.width('100%')
        if (this.status) { Text(this.status).fontSize(13).fontColor(this.palette().accent).width('100%') }
        Scroll() {
          Column({ space: 12 }) { if (this.tab === 0) { this.reviewPanel() } else { this.createPanel() } }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }.padding(18).width(this.phone ? '94%' : 620).height('88%').borderRadius(8).backgroundColor(this.palette().surface)
        .onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.4)').onClick(() => this.closeRequested())
  }
}
