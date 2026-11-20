import { NoteItem } from '../../common/types/NoteItem';
import { LearningCardCandidate, LearningCitation, LearningResult, LearningSection, LearningSource } from '../../common/types/LearningResult';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { DocumentSourcePolicy } from '../../services/document/DocumentSourcePolicy';
import { LearningResultFile } from '../../services/study/LearningResultFile';
import { LearningResultPolicy, LearningSourceLocation } from '../../services/study/LearningResultPolicy';

@Component
export struct LearningResultPanel {
  @Prop @Watch('refreshLocations') note: NoteItem | undefined = undefined;
  @Prop @Watch('refreshLocations') result: LearningResult | undefined = undefined;
  onResult: (result: LearningResult | undefined) => void = () => {};
  onAdopt: (result: LearningResult, noteId: string, index: number) => Promise<boolean> = async () => false;
  onSource: (noteId: string, page?: number, line?: number) => void = () => {};
  onBusy: (busy: boolean) => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @State private page: string = '';
  @State private status: string = '';
  @State private busy: boolean = false;
  @State private locations: LearningSourceLocation[] = [];
  private noteId: string = '';
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; this.refreshLocations(); }
  aboutToDisappear(): void { this.alive = false; }
  private palette() { return ThemeHelper.paletteOfDark(this.dark, this.themeStyle); }
  private pdf(): boolean {
    return this.note !== undefined &&
      DocumentSourcePolicy.kind({ type: this.note.type, sourceType: this.note.sourceType }) === 'pdf';
  }

  private refreshLocations(): void {
    if ((this.note?.id || '') !== this.noteId) {
      this.noteId = this.note?.id || '';
      this.page = this.pdf() ? String(this.note?.readPage || 1) : '';
    }
    this.locations = this.result && this.note ? LearningResultPolicy.locate(this.result, this.note) : [];
  }

  private location(citation: LearningCitation): LearningSourceLocation | undefined {
    return this.locations.find((location: LearningSourceLocation) => location.sourceId === citation.source_id);
  }

  private openCitation(citation: LearningCitation): void {
    if (!this.note || !this.result) { return; }
    const location = LearningResultPolicy.locate(this.result, this.note)
      .find((item: LearningSourceLocation) => item.sourceId === citation.source_id);
    if (!location) { this.status = '当前资料已无法唯一定位这条引文。'; return; }
    this.onSource(this.note.id, location.pageNumber, LearningResultPolicy.citationLine(this.result, citation, location));
  }

  private async openFile(): Promise<void> {
    if (this.busy) { return; }
    this.setBusy(true);
    try {
      const result = await LearningResultFile.select(this.getUIContext().getHostContext() as Context);
      if (this.alive && result !== null) { this.onResult(result); this.status = ''; }
    } catch (error) {
      if (this.alive) { this.status = error instanceof Error ? error.message : '学习结果读取失败。'; }
    } finally { if (this.alive) { this.setBusy(false); } }
  }

  private setBusy(busy: boolean): void { this.busy = busy; this.onBusy(busy); }

  private async exportSource(): Promise<void> {
    if (!this.note || this.busy) { return; }
    const note = this.note;
    this.setBusy(true);
    try {
      const page = this.pdf() ? Number(this.page) : undefined;
      if (page !== undefined && (!Number.isInteger(page) || page < 1 || page > (note.pageCount || 0))) {
        throw new Error('请输入有效的 PDF 页码。');
      }
      const text = LearningResultPolicy.exportText(note, page);
      const title = page === undefined ? note.title : `${note.title}-第${page}页`;
      if (await LearningResultFile.exportText(this.getUIContext().getHostContext() as Context, title, text) && this.alive) {
        this.status = '原文已导出，可以交给本机模型工具。';
      }
    } catch (error) {
      if (this.alive) { this.status = error instanceof Error ? error.message : '原文导出失败。'; }
    } finally { if (this.alive) { this.setBusy(false); } }
  }

  private async adopt(index: number): Promise<void> {
    if (!this.note || !this.result || this.busy) { return; }
    this.setBusy(true);
    try {
      const saved = await this.onAdopt(this.result, this.note.id, index);
      if (this.alive) { this.status = saved ? '已采纳为生成题卡，可开始复习。' : '这道生成题卡已采纳。'; }
    } catch (error) {
      if (this.alive) { this.status = error instanceof Error ? error.message : '题卡保存失败，可重试。'; }
    } finally { if (this.alive) { this.setBusy(false); } }
  }

  @Builder
  citations(items: LearningCitation[]) {
    ForEach(items, (citation: LearningCitation) => {
      Column({ space: 4 }) {
        Text(this.result?.sources.find((item: LearningSource) => item.id === citation.source_id)?.name || '出处')
          .fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
        Text(citation.quote).fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
        if (this.location(citation)) {
          Button(this.location(citation)?.pageNumber ? `查看原 PDF 第 ${this.location(citation)?.pageNumber} 页` : '查看原文位置')
            .height(44).enabled(!this.busy).onClick(() => this.openCitation(citation))
        } else {
          Text('请在上方选择可唯一匹配的本地资料。').fontSize(12).fontColor(this.palette().inkSecondary)
        }
      }.padding(8).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(this.palette().surfaceSubtle)
    }, (citation: LearningCitation, index: number) => `${citation.source_id}:${index}`)
  }

  build() {
    Column({ space: 10 }) {
      if (this.pdf()) {
        TextInput({ text: this.page, placeholder: '提取并校对过的 PDF 页码' }).type(InputType.Number).enabled(!this.busy)
          .onChange((value: string) => { this.page = value; })
      }
      Button('导出所选原文').height(44).width('100%').enabled(!this.busy && this.note !== undefined).onClick(() => this.exportSource())
      Button('打开学习结果 JSON').height(44).width('100%').enabled(!this.busy).onClick(() => this.openFile())
      if (this.status) { Text(this.status).fontSize(13).fontColor(this.palette().accent).width('100%') }
      if (this.result) {
        Text(this.result.title).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).width('100%')
        Button('清除预览').height(44).enabled(!this.busy).onClick(() => { this.onResult(undefined); this.status = ''; })
        ForEach(this.result.sections, (section: LearningSection) => {
          Column({ space: 6 }) {
            Text(section.heading).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
            Text(section.body).fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
            this.citations(section.citations)
          }.width('100%')
        }, (section: LearningSection, index: number) => `${this.result?.job_id}:section:${index}`)
        ForEach(this.result.cards, (card: LearningCardCandidate, index: number) => {
          Column({ space: 6 }) {
            Text(card.question).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
            Text(card.answer).fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
            this.citations(card.citations)
            Button('采纳题卡').height(44).enabled(!this.busy && this.note !== undefined).onClick(() => this.adopt(index))
          }.width('100%')
        }, (card: LearningCardCandidate, index: number) => `${this.result?.job_id}:card:${index}`)
        ForEach(this.result.warnings, (warning: string) => {
          Text(warning).fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
        }, (warning: string, index: number) => `${index}:${warning}`)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
