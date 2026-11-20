import { ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { LearningCitation, LearningResult, LearningSection } from '../../common/types/LearningResult';
import { NoteItem } from '../../common/types/NoteItem';
import { ReaderPairPolicy } from '../../services/document/ReaderPairPolicy';
import { LearningResultPolicy, LearningSourceLocation } from '../../services/study/LearningResultPolicy';
import { StudyAssistantFragment, StudyAssistantGateway, StudyAssistantRequest, StudyGatewayModel, StudyGatewaySelection } from '../../services/study/StudyAssistantGateway';
import { StudyAssistantSource } from '../../services/study/StudyAssistantSource';
import { StudySourceService } from '../../services/study/StudySourceService';
import { AppIcon } from '../common/AppIcon';
import { DocumentText } from '../common/DocumentText';

@Component
export struct StudyAssistantPanel {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop @Watch('onActiveChanged') active: boolean = true;
  @Prop sourcePage: number = 1;
  @Prop gatewayAvailable: boolean = false;
  @Prop sharedGateway: StudyGatewaySelection = { pairingCode: '', models: [], model: '' };
  onGatewayChange: (selection: StudyGatewaySelection) => void = () => {};
  onExtract: (page: number) => void = () => {};
  onJump: (page?: number, line?: number) => void = () => {};
  onSaveDraft: (title: string, body: string) => Promise<boolean> = async () => false;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';
  @State private operation: string = 'qa';
  @State private goal: string = '';
  @State private start: string = '1';
  @State private end: string = '';
  @State private pairingCode: string = '';
  @State private models: StudyGatewayModel[] = [];
  @State private selectedModel: string = '';
  @State private connecting: boolean = false;
  @State private pending: StudyAssistantRequest | null = null;
  @State private result: LearningResult | null = null;
  @State private locations: LearningSourceLocation[] = [];
  @State private status: string = '';
  @State private busy: boolean = false;
  @State private saving: boolean = false;
  @State private savedJob: string = '';
  @State private pairingOpen: boolean = false;
  @State private pendingLocations: LearningSourceLocation[] = [];
  private gateway: StudyAssistantGateway = new StudyAssistantGateway();
  private scroller: Scroller = new Scroller();
  private generation: number = 0;
  private noteId: string = '';
  private sourceText: string = '';
  private sourceUri: string = '';
  private pageCount: number = 0;

  aboutToAppear(): void {
    this.pairingCode = this.sharedGateway.pairingCode;
    this.models = this.sharedGateway.models;
    this.selectedModel = this.sharedGateway.model;
    this.onNoteChanged();
  }

  aboutToDisappear(): void { this.stopRequest(); }

  private onActiveChanged(): void {
    if (!this.active && (this.busy || this.connecting)) {
      this.stopRequest();
      this.status = '已停止等待，重新打开助手可再次确认发送。';
    }
  }

  private onNoteChanged(): void {
    const pdf = ReaderPairPolicy.isPdf(this.note);
    const text = pdf ? this.note.pdfTextJson || '' : this.note.contentDetail;
    const uri = this.note.sourceUri || '';
    const pages = this.note.pageCount || 0;
    if (this.noteId === this.note.id && this.sourceText === text && this.sourceUri === uri &&
      this.pageCount === pages && !this.note.deletedAt) { return; }
    this.stopRequest();
    this.resetPreview();
    this.result = null;
    this.locations = [];
    if (this.noteId !== this.note.id) {
      this.start = String(pdf ? this.sourcePage || this.note.readPage || 1 : 1);
      this.end = '';
      this.goal = '';
    }
    this.noteId = this.note.id;
    this.sourceText = text;
    this.sourceUri = uri;
    this.pageCount = pages;
  }

  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.style); }

  private rangeLabel(): string {
    const end = this.end.trim();
    if (ReaderPairPolicy.isPdf(this.note)) {
      return end && end !== this.start ? `第 ${this.start}–${end} 页` : `第 ${this.start} 页`;
    }
    return end ? `第 ${this.start}–${end} 行` : `第 ${this.start} 行至文末`;
  }

  private citationLabel(citation: LearningCitation): string {
    const location = this.locations.find(item => item.sourceId === citation.source_id);
    if (!location || !this.result) { return ''; }
    if (location.pageNumber !== undefined) { return `PDF 第 ${location.pageNumber} 页`; }
    return `原文第 ${LearningResultPolicy.citationLine(this.result, citation, location)} 行`;
  }

  private previewLocation(id: string): string {
    const location = this.pendingLocations.find(item => item.sourceId === id);
    return location ? StudyAssistantSource.locationLabel(location) : '';
  }

  private stopRequest(): void {
    this.generation++;
    this.gateway.cancel();
    this.busy = false;
    this.connecting = false;
  }

  private resetPreview(): void {
    this.pending = null;
    this.pendingLocations = [];
    this.status = '';
  }

  private useCurrentPage(): void {
    this.start = String(this.sourcePage || this.note.readPage || 1);
    this.end = '';
    this.resetPreview();
  }

  private prepare(): void {
    this.resetPreview();
    const goal = this.goal.trim();
    try {
      if (!this.model()) { throw new Error('请先连接电脑网关并选择模型。'); }
      if (this.note.deletedAt) { throw new Error('当前资料已移入回收站。'); }
      const selection = StudyAssistantSource.prepare(this.note, this.operation,
        this.operation === 'report' ? '按学习主题、待核对的问题和下周计划整理周报草稿。仅依据所选资料，不虚构时间或已完成的学习记录。' +
          (goal ? '\n补充要求：' + goal : '') : this.operation === 'summary' && !goal ? '概括所选资料，提炼关键概念。' : goal,
        this.start, this.end);
      this.pendingLocations = selection.locations;
      this.pending = selection.request;
      this.scroller.scrollEdge(Edge.Top);
    } catch (error) {
      this.status = error instanceof Error ? error.message : '无法准备资料。';
    }
  }

  private validPairing(): boolean { return /^[a-f0-9]{32}$/.test(this.pairingCode.trim()); }

  private model(): StudyGatewayModel | undefined {
    return this.models.find((item: StudyGatewayModel) => item.id === this.selectedModel);
  }

  private async connect(): Promise<void> {
    if (!this.active || this.connecting || !this.validPairing()) { return; }
    const generation = ++this.generation;
    this.connecting = true;
    this.status = '';
    try {
      const models = await this.gateway.models(this.pairingCode.trim());
      if (generation !== this.generation) { return; }
      this.models = models;
      if (!this.model()) { this.selectedModel = models[0].id; }
      this.pairingOpen = false;
      this.publishGateway();
    } catch (error) {
      if (generation !== this.generation) { return; }
      this.models = [];
      this.selectedModel = '';
      this.status = error instanceof Error ? error.message : '无法读取电脑网关的模型列表。';
    } finally {
      if (generation === this.generation) { this.connecting = false; }
    }
  }

  private publishGateway(): void {
    this.onGatewayChange({ pairingCode: this.pairingCode.trim(), models: this.models, model: this.selectedModel });
  }

  private extract(): void {
    const page = Number(this.start);
    if (!Number.isInteger(page) || page < 1 || page > (this.note.pageCount || 0)) {
      this.status = '请输入有效的起始页。';
      return;
    }
    const end = Number(this.end.trim() || this.start);
    const pages = StudySourceService.pages(this.note);
    if (Number.isInteger(end) && end >= page && end <= (this.note.pageCount || 0) && end - page < 12) {
      for (let candidate = page; candidate <= end; candidate++) {
        if (pages.some(item => item.pageNumber === candidate && item.text.trim().length > 0)) { continue; }
        this.onExtract(candidate);
        return;
      }
    }
    this.onExtract(page);
  }

  private async send(): Promise<void> {
    const payload = this.pending;
    const model = this.selectedModel;
    if (!payload || this.active === false || this.busy || !model || !this.validPairing()) { return; }
    const generation = ++this.generation;
    this.busy = true;
    this.status = '正在生成，仍可在阅读区查看原文。';
    this.scroller.scrollEdge(Edge.Top);
    try {
      const result = await this.gateway.generate(payload, this.pairingCode.trim(), model);
      if (generation !== this.generation) { return; }
      this.locations = this.pendingLocations;
      this.result = result;
      this.resetPreview();
    } catch (error) {
      if (generation === this.generation) { this.status = error instanceof Error ? error.message : '生成失败，请重试。'; }
    } finally {
      if (generation === this.generation) { this.busy = false; }
    }
  }

  private jump(citation: LearningCitation): void {
    const result = this.result;
    if (!result) { return; }
    const location = this.locations.find((item: LearningSourceLocation) => item.sourceId === citation.source_id);
    if (!location) { this.status = '当前资料内无法唯一定位这条引文。'; return; }
    this.onJump(location.pageNumber, location.pageNumber === undefined ?
      LearningResultPolicy.citationLine(result, citation, location) : undefined);
  }

  private async save(): Promise<void> {
    const result = this.result;
    if (!result || this.saving || this.savedJob === result.job_id) { return; }
    const noteId = this.noteId;
    this.saving = true;
    try {
      if (await this.onSaveDraft(result.title, StudyAssistantSource.markdown(result, this.note.title, this.locations))) {
        if (noteId === this.noteId) { this.savedJob = result.job_id; this.status = '已保存为本地笔记。'; }
      } else if (noteId === this.noteId) { this.status = '保存失败，草稿已保留。'; }
    } catch {
      if (noteId === this.noteId) { this.status = '保存失败，草稿已保留。'; }
    } finally {
      this.saving = false;
    }
  }

  @Builder
  mode(label: string, value: string) {
    Button(label, { type: ButtonType.Normal }).layoutWeight(1).height(44).padding({ left: 8, right: 8 })
      .fontSize(13).borderRadius(22).fontColor(this.palette().inkPrimary)
      .backgroundColor(this.operation === value ? this.palette().accentSoft : this.palette().surface)
      .border({ width: 1, color: this.operation === value ? this.palette().accent : this.palette().border })
      .accessibilityDescription(this.operation === value ? '已选中' : '')
      .onClick(() => { this.operation = value; this.resetPreview(); })
  }

  @Builder
  action(label: string, primary: boolean, available: boolean, onAction: () => void) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(22)
      .padding({ left: 14, right: 14 }).fontWeight(FontWeight.Medium)
      .fontColor(primary ? this.palette().onAccent : this.palette().inkPrimary)
      .backgroundColor(primary ? this.palette().accent : this.palette().accentSoft)
      .enabled(available).onClick(onAction)
  }

  @Builder
  modelOption(model: StudyGatewayModel) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Row() {
          AppIcon({ source: model.id === 'deepseek-flash' ? $r('app.media.ic_project_rocket') :
            model.id === 'deepseek-v4-pro' ? $r('app.media.ic_graph') : $r('app.media.ic_cloud'),
            iconSize: 20, tint: this.selectedModel === model.id ? this.palette().accent : this.palette().inkSecondary })
        }.width(38).height(38).justifyContent(FlexAlign.Center).borderRadius(12).backgroundColor(this.palette().surface)
        Column({ space: 3 }) {
          Text(model.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (model.id === 'deepseek-flash' || model.id === 'deepseek-v4-pro') {
            Text(model.id === 'deepseek-flash' ? '日常问答和选页摘要' : '复杂问题和长资料综合整理')
              .fontSize(12).fontColor(this.palette().inkSecondary)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.selectedModel === model.id) {
          AppIcon({ source: $r('app.media.ic_check'), iconSize: 18, tint: this.palette().accent })
        }
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 56 })
      .padding({ left: 10, right: 12, top: 8, bottom: 8 }).borderRadius(14)
      .backgroundColor(this.selectedModel === model.id ? this.palette().accentSoft : this.palette().surfaceSubtle)
      .border({ width: 1, color: this.selectedModel === model.id ? this.palette().accent : this.palette().borderSubtle })
      .accessibilityDescription(this.selectedModel === model.id ? '已选中' : '可选模型')
      .onClick(() => {
        if (this.selectedModel !== model.id) { this.selectedModel = model.id; this.resetPreview(); this.publishGateway(); }
      })
  }

  @Builder
  modelPicker() {
    Column({ space: 8 }) {
      Text('选择模型').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
      if (this.models.length > 0) {
        ForEach(this.models, (model: StudyGatewayModel) => { this.modelOption(model) }, (model: StudyGatewayModel) => model.id)
        if (this.model()?.agent) {
          Text('Agent 可在已确认发送的片段中检索资料。').fontSize(12).fontColor(this.palette().inkSecondary)
        }
        this.action(this.pairingOpen ? '收起配对设置' : '更改网关配对码', false, !this.connecting,
          () => { this.pairingOpen = !this.pairingOpen; })
      }
      if (this.pairingOpen || this.models.length === 0) {
        TextInput({ placeholder: '电脑网关显示的 32 位配对码', text: this.pairingCode })
          .height(48).width('100%').fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surface)
          .type(InputType.Password).maxLength(32).accessibilityText('模拟器网关配对码')
          .enabled(!this.connecting).onChange((value: string) => {
            if (this.connecting) { return; }
            this.pairingCode = value;
            this.models = [];
            this.selectedModel = '';
            this.resetPreview();
          })
        this.action(this.connecting ? '正在连接…' : '连接电脑网关', false, !this.connecting && this.validPairing(),
          () => { this.connect(); })
      }
    }.padding(12).borderRadius(20).backgroundColor(this.palette().surfaceSubtle)
      .width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  composer() {
    Column({ space: 12 }) {
      this.modelPicker()
      Row({ space: 6 }) {
        this.mode('问答', 'qa')
        this.mode('摘要', 'summary')
        this.mode('周报', 'report')
      }.width('100%')
      Column({ space: 8 }) {
        Text('资料范围').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
        Text(ReaderPairPolicy.isPdf(this.note) ? '结束页留空时仅选起始页。' : '结束行留空时选至文末。')
          .fontSize(12).fontColor(this.palette().inkSecondary)
        Row({ space: 8 }) {
          TextInput({ placeholder: ReaderPairPolicy.isPdf(this.note) ? '起始页' : '起始行', text: this.start })
            .height(44).type(InputType.Number).maxLength(8).layoutWeight(1)
            .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surface)
            .accessibilityText('资料范围起始').onChange((value: string) => { this.start = value; this.resetPreview(); })
          TextInput({ placeholder: ReaderPairPolicy.isPdf(this.note) ? '结束页' : '结束行', text: this.end })
            .height(44).type(InputType.Number).maxLength(8).layoutWeight(1)
            .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surface)
            .accessibilityText('资料范围结束').onChange((value: string) => { this.end = value; this.resetPreview(); })
        }.width('100%')
        if (ReaderPairPolicy.isPdf(this.note)) {
          Flex({ wrap: FlexWrap.Wrap }) {
            this.action('使用当前页', false, true, () => this.useCurrentPage())
            this.action('提取待校对页', false, true, () => this.extract())
          }.width('100%')
        }
      }.padding(12).borderRadius(20).backgroundColor(this.palette().surfaceSubtle)
        .width('100%').alignItems(HorizontalAlign.Start)
      TextArea({ placeholder: this.operation === 'qa' ? '输入与资料相关的问题' : '补充要求，可留空', text: this.goal })
        .height(92).maxLength(this.operation === 'report' ? 700 : 800)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
        .accessibilityText(this.operation === 'qa' ? '学习问题' : '补充要求')
        .onChange((value: string) => { this.goal = value; this.resetPreview(); })
      this.action('预览发送内容', true, !!this.selectedModel && !this.connecting, () => this.prepare())
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  preview(payload: StudyAssistantRequest) {
    Column({ space: 10 }) {
      Text('发送预览').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
      Text(this.rangeLabel() + ' · ' + payload.sources.length + ' 个原文片段').fontSize(13).fontColor(this.palette().inkSecondary)
      Text('确认后，以下内容会经电脑网关发送给 ' + (this.model()?.label || '所选模型') + '。')
        .fontSize(13).fontColor(this.palette().inkSecondary)
      Text(payload.goal).fontSize(14).fontColor(this.palette().inkPrimary)
        .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
      ForEach(payload.sources, (source: StudyAssistantFragment) => {
        Column({ space: 5 }) {
          Text(this.previewLocation(source.id)).fontSize(12).fontColor(this.palette().link).fontWeight(FontWeight.Medium)
          Text(source.text).fontSize(13).textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
            .fontColor(this.palette().inkSecondary).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start).padding(10).borderRadius(12).backgroundColor(this.palette().surface)
      }, (source: StudyAssistantFragment) => source.id)
      Row({ space: 8 }) {
        this.action('返回修改', false, true, () => {
          this.scroller.scrollEdge(Edge.Top);
          this.resetPreview();
        })
        this.action('确认发送', true, this.validPairing(), () => { this.send(); })
      }.width('100%')
    }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
      .backgroundColor(this.palette().surfaceSubtle).borderRadius(20)
  }

  @Builder
  output(result: LearningResult) {
    Column({ space: 12 }) {
      Text(result.title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
      ForEach(result.warnings, (warning: string) => {
        Text(warning).fontSize(12).fontColor(this.palette().inkSecondary)
      })
      ForEach(result.sections, (section: LearningSection) => {
        Column({ space: 8 }) {
          Text(section.heading).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
          DocumentText({ text: section.body, allowLinks: false })
          ForEach(section.citations, (citation: LearningCitation) => {
            Column({ space: 4 }) {
              Text(citation.quote).fontSize(13).textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
                .fontColor(this.palette().inkSecondary)
              if (this.citationLabel(citation)) {
                this.action(this.citationLabel(citation), false, true, () => this.jump(citation))
              } else {
                Text('此引文在当前资料中无法唯一定位').fontSize(12).fontColor(this.palette().inkMuted)
              }
            }.padding(10).borderRadius(12).backgroundColor(this.palette().surfaceSubtle)
              .width('100%').alignItems(HorizontalAlign.Start)
          })
        }.padding(12).width('100%').alignItems(HorizontalAlign.Start).borderRadius(16)
          .border({ width: 1, color: this.palette().borderSubtle })
      })
      Flex({ wrap: FlexWrap.Wrap }) {
        this.action(this.savedJob === result.job_id ? '已保存' : this.saving ? '正在保存…' : '保存为本地笔记',
          true, !this.saving && this.savedJob !== result.job_id, () => { this.save(); })
        this.action('新建请求', false, !this.saving, () => {
          this.scroller.scrollEdge(Edge.Top);
          this.result = null;
          this.locations = [];
          this.goal = '';
          this.resetPreview();
        })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Column({ space: 4 }) {
        Text('AI 伴读').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
        Text(this.note.title).fontSize(13).fontColor(this.palette().inkSecondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, top: 12, bottom: 10 })
        .backgroundColor(this.palette().surfaceSubtle)
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          if (this.status) {
            Text(this.status).fontSize(13).fontColor(this.palette().inkPrimary)
              .width('100%').padding(12).borderRadius(12).backgroundColor(this.palette().accentSoft)
          }
          if (this.busy) {
            this.action('停止等待', false, true, () => {
              this.stopRequest();
              this.status = '已停止等待，电脑上的请求可能仍在处理。';
            })
          } else if (this.pending) {
            this.preview(this.pending)
          } else if (this.result) {
            this.output(this.result)
          } else if (this.gatewayAvailable) {
            this.composer()
          } else {
            Text('当前版本未启用电脑网关').fontSize(14).fontColor(this.palette().inkSecondary).width('100%')
            if (ReaderPairPolicy.isPdf(this.note) && this.note.sourceUri) {
              this.action('提取当前页文字', false, true, () => this.onExtract(this.sourcePage))
            }
          }
        }.padding(16).width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start).backgroundColor(this.palette().surface)
  }
}
