import { PdfTextPage } from '../../common/types/StudyTypes';
import { NoteItem } from '../../common/types/NoteItem';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { PdfDocumentService } from '../../services/document/PdfDocumentService';

@Component
export struct PdfTextSheet {
  @Require @Prop note: NoteItem;
  @Prop initialPage: number = 1;
  @Prop @Watch('closeRequested') closeToken: number = 0;
  onClose: () => void = () => {};
  onSave: (pages: PdfTextPage[]) => Promise<void> = async () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @State start: string = '1';
  @State end: string = '1';
  @State scanOcr: boolean = false;
  @State pages: PdfTextPage[] = [];
  @State selected: number = 0;
  @State busy: boolean = false;
  @State saving: boolean = false;
  @State status: string = '';
  private alive: boolean = true;
  private cancelled: boolean = false;

  aboutToAppear(): void { this.alive = true; this.start = `${this.initialPage}`; this.end = `${Math.min(this.note.pageCount || 1, this.initialPage + 9)}`; }
  aboutToDisappear(): void { this.alive = false; this.cancelled = true; }
  private closeRequested(): void { if (this.saving) { return; } if (this.busy) { this.cancelled = true; } else { this.onClose(); } }
  private palette() { return ThemeHelper.paletteOfDark(this.dark); }
  private async extract(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.cancelled = false; this.status = '';
    try {
      const pages = await PdfDocumentService.getInstance().extractPages(this.note.sourceUri || '', Number(this.start), Number(this.end),
        this.scanOcr, () => this.cancelled || !this.alive,
        (page: number) => { if (this.alive) { this.status = `正在提取第 ${page} 页…`; } });
      if (!this.alive) { return; }
      this.pages = pages; this.selected = 0;
      const empty = pages.filter((p: PdfTextPage) => !p.text.trim()).length;
      this.status = empty ? `${empty} 页未提取到文字，可开启扫描页 OCR 后重试，或手动校对。` : '请核对文字、公式和页码，再保存到检索。';
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '提取失败，请重试'; } }
    finally { if (this.alive) { this.busy = false; } }
  }
  private async save(): Promise<void> {
    if (this.busy || !this.pages.length) { return; }
    this.busy = true; this.saving = true;
    try { await this.onSave(this.pages); this.onClose(); }
    catch { if (this.alive) { this.status = '保存失败，校对内容仍在，请重试。'; } }
    finally { if (this.alive) { this.busy = false; this.saving = false; } }
  }
  private edit(text: string): void {
    this.pages = this.pages.map((page: PdfTextPage, index: number): PdfTextPage => ({ pageNumber: page.pageNumber,
      text: index === this.selected ? text : page.text, method: page.method, extractedAt: page.extractedAt }));
  }
  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('PDF 文字与来源').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
          Button(this.saving ? '保存中' : this.busy ? '取消提取' : '关闭').height(44).enabled(!this.saving).onClick(() => this.closeRequested())
        }.width('100%')
        Scroll() {
        Column({ space: 12 }) {
        Text(`${this.note.title} · 共 ${this.note.pageCount || 1} 页`).fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
        Text('端侧处理，每次最多 30 页。保存后的文字用于搜索、AI 引用与题卡；原 PDF 和笔迹保留。').fontSize(13)
          .fontColor(this.palette().inkSecondary).width('100%')
        Row({ space: 8 }) {
          TextInput({ text: this.start, placeholder: '起始页' }).type(InputType.Number).layoutWeight(1).onChange((value: string) => { this.start = value; }).enabled(!this.busy)
          Text('至').fontColor(this.palette().inkSecondary)
          TextInput({ text: this.end, placeholder: '结束页' }).type(InputType.Number).layoutWeight(1).onChange((value: string) => { this.end = value; }).enabled(!this.busy)
          Button('提取').height(44).enabled(!this.busy).onClick(() => this.extract())
        }
        Row({ space: 12 }) {
          Text('扫描页使用端侧 OCR').fontSize(14).fontColor(this.palette().inkPrimary).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.scanOcr }).enabled(!this.busy).onChange((value: boolean) => { this.scanOcr = value; })
        }.width('100%')
        if (this.status) { Text(this.status).fontSize(13).fontColor(this.palette().accent).width('100%') }
        if (this.pages.length > 0) {
          Row({ space: 8 }) {
            Button('上一页').height(44).enabled(!this.busy && this.selected > 0).onClick(() => { this.selected--; })
            Text(`校对第 ${this.pages[this.selected].pageNumber} 页`).fontSize(14).fontColor(this.palette().inkPrimary).layoutWeight(1).textAlign(TextAlign.Center)
            Button('下一页').height(44).enabled(!this.busy && this.selected < this.pages.length - 1).onClick(() => { this.selected++; })
          }.width('100%')
          TextArea({ text: this.pages[this.selected].text, placeholder: '此页没有文字，可粘贴校对后的原文' })
            .height(this.phone ? 180 : 250).fontSize(14).maxLength(80000).enabled(!this.busy).onChange((value: string) => this.edit(value))
          Button('已核对，保存到检索').width('100%').height(44).enabled(!this.busy).onClick(() => this.save())
        }
        }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }.padding(20).width(this.phone ? '94%' : 600).height('88%').borderRadius(18).backgroundColor(this.palette().surface)
        .onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.4)').onClick(() => { if (!this.busy) { this.onClose(); } })
  }
}
