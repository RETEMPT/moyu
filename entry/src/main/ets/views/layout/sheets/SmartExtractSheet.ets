import { KeyboardAvoidMode } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { SmartContent } from '../../../common/types/SmartContent';
import { SmartTask } from '../../../common/types/SmartTask';
import { SmartExtractService, SmartLayoutStyle, SMART_INPUT_LIMIT } from '../../../services/smart/SmartExtractService';
import { SmartNoteBuilder } from '../../../services/smart/SmartNoteBuilder';
import { OcrService } from '../../../services/ocr/OcrService';
import { DocumentExtractService, PdfExtractionCursor } from '../../../services/smart/DocumentExtractService';
import { TextImportPolicy } from '../../../services/smart/TextImportPolicy';
import { common } from '@kit.AbilityKit';
import { IconButton } from '../../common/IconButton';
import { AppIcon } from '../../common/AppIcon';
import { DocumentText } from '../../common/DocumentText';

interface SmartExtractDraft {
  input: string;
  imageUri: string;
  result: SmartContent | null;
  title: string;
  category: string;
  body: string;
  tasks: SmartTask[];
  selectedTaskIds: string[];
  style?: SmartLayoutStyle;
  mergeWrappedLines?: boolean;
  pdfSource?: SmartPdfSource | null;
}

interface SmartPdfSource { path: string; pages: number; next: PdfExtractionCursor; }

@Component
export struct SmartExtractSheet {
  onClose: () => void = () => {};
  onCommit: (content: SmartContent, selectedTasks: SmartTask[]) => Promise<void> = async () => {};
  onImportSource: (uri: string) => Promise<NoteItem> = async () => { throw new Error('资料库尚未就绪，请稍后重试'); };
  @Prop @Watch('requestClose') closeToken: number = 0;
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;
  @State private step: string = 'input';
  @State private inputText: string = '';
  @State private imageUri: string = '';
  @State private sourceNotice: string = '';
  @State private layoutStyle: SmartLayoutStyle = 'faithful';
  @State private pdfSource: SmartPdfSource | null = null;
  @State private importProgress: string = '';
  @State private mergeWrappedLines: boolean = false;
  @State private result: SmartContent | null = null;
  @State private title: string = '';
  @State private category: string = '未分类';
  @State private body: string = '';
  @State private resultTab: string = 'preview';
  @State private tasks: SmartTask[] = [];
  @State private selectedTaskIds: string[] = [];
  @State private errorMsg: string = '';
  private requestId: number = 0;
  private alive: boolean = true;
  private previousKeyboardMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;

  aboutToAppear(): void {
    this.alive = true;
    this.inputText = AppStorage.get<string>('smartExtractDraft') || '';
    const draft = AppStorage.get<SmartExtractDraft>('smartExtractResultDraft');
    if (draft) {
      this.imageUri = draft.imageUri || '';
      this.layoutStyle = draft.style === 'study' ? 'study' : 'faithful';
      this.mergeWrappedLines = draft.mergeWrappedLines === true;
      this.pdfSource = draft.pdfSource || null;
    }
    if (draft && draft.result !== null) {
      this.inputText = draft.input;
      this.imageUri = draft.imageUri;
      this.result = draft.result;
      this.title = draft.title;
      this.category = draft.category;
      this.body = draft.body;
      this.tasks = draft.tasks;
      this.selectedTaskIds = draft.selectedTaskIds;
      this.step = 'result';
    }
    this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.requestId++;
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode);
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private busy(): boolean {
    return this.step === 'ocr' || this.step === 'importing' || this.step === 'extracting' || this.step === 'saving';
  }

  private async pickDocument(): Promise<void> {
    if (this.busy()) { return; }
    const id = ++this.requestId; this.step = 'importing'; this.errorMsg = ''; this.sourceNotice = ''; this.importProgress = '选择文档…';
    try {
      const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['学习文档|.pdf,.md,.markdown,.txt'];
      const selected = await new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext).select(options);
      if (!this.alive || id !== this.requestId || !selected.length) { return; }
      this.importProgress = '正在保存到本机资料库…';
      const note = await this.onImportSource(selected[0]);
      if (!this.alive || id !== this.requestId) { return; }
      this.sourceNotice = `已保存「${note.title}」到资料库`;
      this.pdfSource = null;
      if (note.sourceType === 'pdf' && note.sourceUri) {
        this.pdfSource = { path: note.sourceUri, pages: note.pageCount || 0, next: { page: 1, offset: 0 } };
        await this.extractPdf(id);
      } else {
        this.appendText(TextImportPolicy.parse(note.contentDetail));
      }
    } catch (error) {
      if (this.alive && id === this.requestId) { this.errorMsg = error instanceof Error ? error.message : '文档提取未成功，原输入已保留'; }
    } finally { if (this.alive && id === this.requestId) { this.step = 'input'; this.importProgress = ''; } }
  }

  private appendText(text: string): void {
    const appended = this.inputText.trim() ? this.inputText + '\n\n' + text : text;
    if (appended.length > SMART_INPUT_LIMIT) { throw new Error('文字超过编辑区上限，请先整理当前文字'); }
    this.inputText = appended;
    AppStorage.setOrCreate('smartExtractDraft', appended);
  }

  private async extractPdf(id: number): Promise<void> {
    const pdf = this.pdfSource;
    if (!pdf) { return; }
    const budget = SMART_INPUT_LIMIT - (this.inputText.trim() ? this.inputText.length + 2 : 0);
    this.importProgress = `正在提取第 ${pdf.next.page} 页…`;
    const result = await DocumentExtractService.readPdf(pdf.path, pdf.pages, pdf.next, budget, OcrService.isHardwareSupported(),
      () => !this.alive || id !== this.requestId,
      (page: number) => { if (this.alive && id === this.requestId) { this.importProgress = `正在提取第 ${page} 页…`; } });
    if (!this.alive || id !== this.requestId) { return; }
    if (result.text) { this.appendText(result.text); }
    this.pdfSource = result.next ? { path: pdf.path, pages: pdf.pages, next: result.next } : null;
    if (!result.text) {
      this.errorMsg = OcrService.isHardwareSupported() ? '这部分未识别到文字' : '这部分未找到文字层，当前设备无法识别扫描页';
    }
  }

  private async continuePdf(): Promise<void> {
    if (this.busy() || !this.pdfSource) { return; }
    const id = ++this.requestId;
    this.errorMsg = '';
    this.step = 'importing';
    try { await this.extractPdf(id); }
    catch (error) {
      if (this.alive && id === this.requestId) { this.errorMsg = error instanceof Error ? error.message : '提取失败，可重试'; }
    } finally {
      if (this.alive && id === this.requestId) { this.step = 'input'; this.importProgress = ''; }
    }
  }

  private requestClose(): void {
    if (this.step === 'saving') {
      return;
    }
    AppStorage.setOrCreate('smartExtractDraft', this.inputText);
    const draft: SmartExtractDraft = { input: this.inputText, imageUri: this.imageUri,
      result: this.step === 'result' ? this.result : null, title: this.title,
      category: this.category, body: this.body, tasks: this.tasks,
      selectedTaskIds: this.selectedTaskIds,
      style: this.layoutStyle, mergeWrappedLines: this.mergeWrappedLines, pdfSource: this.pdfSource };
    AppStorage.setOrCreate('smartExtractResultDraft', draft);
    this.requestId++;
    this.onClose();
  }

  private async pickImageAndOcr(): Promise<void> {
    if (this.busy()) {
      return;
    }
    const id = ++this.requestId;
    this.errorMsg = '';
    this.step = 'ocr';
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const options = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picked = await photoPicker.select(options);
      if (!this.alive || id !== this.requestId || picked.photoUris.length === 0) {
        return;
      }
      const text = await OcrService.getInstance().recognizeTextFromUri(picked.photoUris[0]);
      if (!this.alive || id !== this.requestId) {
        return;
      }
      // 追加而不是覆盖用户此前粘贴或校对的文字。
      const appended = this.inputText.trim().length > 0 ? `${this.inputText}\n\n${text}` : text;
      if (appended.length > SMART_INPUT_LIMIT) { throw new Error('追加后文字超过上限，请先整理当前内容，原输入已保留'); }
      this.inputText = appended;
      this.imageUri = picked.photoUris[0];
      this.sourceNotice = '';
      AppStorage.setOrCreate('smartExtractDraft', this.inputText);
    } catch (error) {
      if (this.alive && id === this.requestId) {
      this.errorMsg = error instanceof Error && (error.message.includes('未识别到文字') || error.message.includes('超过上限')) ? error.message :
          '图片识别未成功：请检查图片是否清晰、设备是否支持 OCR，或直接粘贴文字。原输入已保留。';
      }
    } finally {
      if (this.alive && id === this.requestId) {
        this.step = 'input';
      }
    }
  }

  private async triggerExtraction(): Promise<void> {
    if (this.busy()) {
      return;
    }
    if (this.inputText.trim().length === 0 || this.inputText.trim().length > SMART_INPUT_LIMIT) {
      this.errorMsg = `请输入 1–${SMART_INPUT_LIMIT} 字的内容，较长资料可分段整理。`;
      return;
    }
    const id = ++this.requestId;
    this.errorMsg = '';
    this.step = 'extracting';
    try {
      const extracted = await SmartExtractService.getInstance().extract(this.inputText, '整理笔记', this.layoutStyle, this.mergeWrappedLines);
      if (!this.alive || id !== this.requestId) {
        return;
      }
      this.result = extracted;
      this.title = extracted.title;
      this.body = extracted.formattedMarkdown || this.inputText;
      this.tasks = extracted.tasks.slice();
      // 待办由用户选择，避免把识别建议直接写入日历。
      this.selectedTaskIds = [];
      this.resultTab = 'preview';
      this.step = 'result';
    } catch {
      if (this.alive && id === this.requestId) {
        this.errorMsg = '整理失败，输入已保留，请重试。';
        this.step = 'input';
      }
    }
  }

  private toggleTask(taskId: string): void {
    this.selectedTaskIds = this.selectedTaskIds.includes(taskId) ?
      this.selectedTaskIds.filter((id: string) => id !== taskId) : [...this.selectedTaskIds, taskId];
  }

  private editDeadline(taskId: string, value: string): void {
    this.tasks = this.tasks.map((task: SmartTask) => {
      if (task.id !== taskId) {
        return task;
      }
      const edited: SmartTask = { id: task.id, title: task.title, deadline: value, priority: task.priority,
        sourceTitle: task.sourceTitle, sourceUri: task.sourceUri, sourceLine: task.sourceLine,
        sourceText: task.sourceText, reminderTime: task.reminderTime, completed: task.completed };
      return edited;
    });
  }

  private chosenTasks(): SmartTask[] {
    return this.tasks.filter((task: SmartTask) => this.selectedTaskIds.includes(task.id));
  }

  private taskReferenceDate(): Date {
    return new Date(this.result ? this.result.createdAt : Date.now());
  }

  private pendingDates(): boolean {
    return this.chosenTasks().some((task: SmartTask) => (task.deadline || '').trim().length > 0 &&
      !SmartNoteBuilder.resolveDeadline(task.deadline || '', this.taskReferenceDate()));
  }

  private previewContent(): SmartContent {
    const data = this.result!;
    const content: SmartContent = { id: data.id, type: data.type, title: this.title.replace(/[\r\n]/g, ' ').trim(),
      category: this.category.trim() || '未分类', summary: data.summary, tags: data.tags,
      tasks: this.tasks, rawMarkdown: data.rawMarkdown, formattedMarkdown: this.body,
      processingMode: data.processingMode, processingNotice: data.processingNotice, createdAt: data.createdAt };
    return content;
  }

  private previewBody(): string {
    return this.result ? SmartNoteBuilder.buildMarkdown(this.previewContent(), this.chosenTasks()) : '';
  }

  private async commit(): Promise<void> {
    if (!this.result || this.busy()) {
      return;
    }
    if (this.title.trim().length === 0 || this.body.trim().length === 0) {
      this.errorMsg = '标题和正文不能为空。';
      return;
    }
    if (this.pendingDates()) {
      this.errorMsg = '请先确认已勾选待办的日期，或取消勾选后只保存笔记。清空日期可加入今天。';
      return;
    }
    this.errorMsg = '';
    this.step = 'saving';
    try {
      await this.onCommit(this.previewContent(), this.chosenTasks());
      AppStorage.setOrCreate('smartExtractDraft', '');
      AppStorage.delete('smartExtractResultDraft');
      if (this.pdfSource) {
        const draft: SmartExtractDraft = { input: '', imageUri: '', result: null, title: '', category: '',
          body: '', tasks: [], selectedTaskIds: [], style: this.layoutStyle,
          mergeWrappedLines: this.mergeWrappedLines, pdfSource: this.pdfSource };
        AppStorage.setOrCreate('smartExtractResultDraft', draft);
      }
      this.onClose();
    } catch (error) {
      this.step = 'result';
      this.errorMsg = error instanceof Error ? error.message : '保存未成功，内容已保留，请重试。';
    }
  }

  @Builder
  hint(text: string) {
    Text(text).fontSize(TypographyTokens.CAPTION).fontColor(this.palette().inkSecondary)
      .width('100%').lineHeight(20)
  }

  @Builder
  inputPanel() {
    Column({ space: 12 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          AppIcon({ source: $r('app.media.ic_note'), tint: this.palette().accent })
          Text('从图片识别文字').fontSize(14)
        }.justifyContent(FlexAlign.Center).width('100%')
      }.width('100%').height(48)
        .accessibilityText('从图片识别文字')
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
        .onClick(() => this.pickImageAndOcr())
      Button('导入 PDF / Markdown / TXT').width('100%').height(48)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle).onClick(() => this.pickDocument())
      if (this.pdfSource) {
        Button(`继续提取 PDF · 第 ${this.pdfSource.next.page} 页`, { type: ButtonType.Normal }).width('100%').height(44)
          .fontColor(this.palette().accent).backgroundColor(this.palette().accentSoft).onClick(() => this.continuePdf())
      }
      if (this.imageUri.length > 0) {
        Image(this.imageUri).width('100%').height(100).objectFit(ImageFit.Contain).borderRadius(8)
      }
      if (this.sourceNotice.length > 0) {
        Text(this.sourceNotice).fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
      }
      TextArea({ text: this.inputText, placeholder: '粘贴或校对文字' })
        .height(this.isPhone ? 180 : 220).width('100%').fontSize(TypographyTokens.BODY_REGULAR)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
        .onChange((value: string) => {
          this.inputText = value;
          AppStorage.setOrCreate('smartExtractDraft', value);
          this.errorMsg = '';
        })
      if (this.inputText.length > SMART_INPUT_LIMIT) {
        Text(`最多 ${SMART_INPUT_LIMIT} 字，请分段整理`).fontSize(14).fontColor(this.palette().danger).width('100%')
      }
      Row({ space: 8 }) {
        Button('保留原文').layoutWeight(1).height(44)
          .fontColor(this.palette().inkPrimary)
          .backgroundColor(this.layoutStyle === 'faithful' ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .onClick(() => { this.layoutStyle = 'faithful'; })
        Button('学习笔记').layoutWeight(1).height(44)
          .fontColor(this.palette().inkPrimary)
          .backgroundColor(this.layoutStyle === 'study' ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .onClick(() => { this.layoutStyle = 'study'; })
      }.width('100%')
      Row({ space: 10 }) {
        Text('合并图片断行').fontSize(14).layoutWeight(1).fontColor(this.palette().inkPrimary)
        Toggle({ type: ToggleType.Switch, isOn: this.mergeWrappedLines }).selectedColor(this.palette().accent)
          .onChange((value: boolean) => { this.mergeWrappedLines = value; })
      }.width('100%').constraintSize({ minHeight: 48 })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  taskRow(index: number) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Checkbox({ name: this.tasks[index].id }).select(this.selectedTaskIds.includes(this.tasks[index].id))
          .width(24).height(24).onChange(() => this.toggleTask(this.tasks[index].id))
        Text(this.tasks[index].title).layoutWeight(1).fontColor(this.palette().inkPrimary).fontSize(14)
      }.width('100%').constraintSize({ minHeight: 44 })
      TextInput({ text: this.tasks[index].deadline || '', placeholder: '日期：YYYY-MM-DD；留空放入今天' })
        .height(44).fontSize(14).fontColor(this.palette().inkPrimary)
        .backgroundColor(this.palette().surface)
        .onChange((value: string) => this.editDeadline(this.tasks[index].id, value))
      if (this.tasks[index].sourceLine && this.tasks[index].sourceText) {
        this.hint(`原文第 ${this.tasks[index].sourceLine} 行：${this.tasks[index].sourceText}`)
      }
      this.hint(SmartNoteBuilder.resolveDeadline(this.tasks[index].deadline || '', this.taskReferenceDate()) ||
        ((this.tasks[index].deadline || '').trim().length > 0 ? '日期待确认；请填写完整年月日，或清空日期加入今天。' : '无截止日期，将加入今天的待办。'))
    }.width('100%').padding(10).borderRadius(5).backgroundColor(this.palette().surfaceSubtle)
  }

  @Builder
  resultPanel() {
    Column({ space: 12 }) {
      TextInput({ text: this.title, placeholder: '笔记标题' }).height(44)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
        .onChange((value: string) => { this.title = value; })
      TextInput({ text: this.category, placeholder: '保存到分类，例如：课程笔记' }).height(44)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
        .onChange((value: string) => { this.category = value; })
      Row({ space: 6 }) {
        Button('预览').layoutWeight(1).height(44).fontColor(this.palette().inkPrimary)
          .backgroundColor(this.resultTab === 'preview' ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .onClick(() => { this.resultTab = 'preview'; })
        Button('编辑正文').layoutWeight(1).height(44).fontColor(this.palette().inkPrimary)
          .backgroundColor(this.resultTab === 'edit' ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .onClick(() => { this.resultTab = 'edit'; })
        Button('核对原文').layoutWeight(1).height(44).fontColor(this.palette().inkPrimary)
          .backgroundColor(this.resultTab === 'source' ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .onClick(() => { this.resultTab = 'source'; })
      }.width('100%')
      if (this.resultTab === 'edit') {
        TextArea({ text: this.body, placeholder: '编辑 Markdown 正文' }).height(260).width('100%')
          .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
          .onChange((value: string) => { this.body = value; })
      } else if (this.resultTab === 'source') {
        Text(this.result?.rawMarkdown || '').width('100%').fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary).lineHeight(24).copyOption(CopyOptions.InApp)
      } else {
        DocumentText({ text: this.previewBody() }).width('100%').padding(12).borderRadius(5).backgroundColor(this.palette().surfaceSubtle)
      }
      if (this.tasks.length > 0) {
        Text(`添加到日历 · 已选 ${this.selectedTaskIds.length} 项`)
          .fontSize(TypographyTokens.BODY_REGULAR).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
      }
      ForEach(this.tasks.map((task: SmartTask) => task.id), (taskId: string, index: number) => {
        this.taskRow(index)
      }, (taskId: string) => taskId)
      if (this.pendingDates()) { this.hint('已选待办还有待确认日期，请修改日期或取消勾选。') }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('文字识别与排版').layoutWeight(1).fontSize(TypographyTokens.TITLE_SUB)
            .fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
          IconButton({ icon: $r('app.media.ic_close'), label: '关闭，保留输入草稿', available: this.step !== 'saving', onAction: () => this.requestClose() })
        }.width('100%')
        Scroll() {
          Column({ space: 12 }) {
            if (this.step === 'input') {
              this.inputPanel()
            } else if (this.step === 'result') {
              this.resultPanel()
            } else {
              LoadingProgress().width(42).height(42).color(this.palette().accent)
              this.hint(this.step === 'importing' ? this.importProgress : this.step === 'ocr' ? '正在识别图片文字…' : (this.step === 'saving' ? '正在保存笔记和待办…' : '正在整理排版，请稍候…'))
            }
          }.width('100%')
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
        if (this.errorMsg.length > 0) {
          Text(this.errorMsg).width('100%').fontSize(14).fontColor(this.palette().danger)
        }
        if (this.step === 'input') {
          Button('开始整理').width('100%').height(48)
            .fontColor(this.palette().onAccent).backgroundColor(this.palette().accent)
            .enabled(this.inputText.trim().length > 0 && this.inputText.length <= SMART_INPUT_LIMIT)
            .onClick(() => this.triggerExtraction())
        } else if (this.step === 'result') {
          Row({ space: 8 }) {
            Button('返回校对').layoutWeight(1).height(48).fontColor(this.palette().inkPrimary)
              .backgroundColor(this.palette().surfaceSubtle).onClick(() => { this.step = 'input'; this.errorMsg = ''; })
            Button('保存笔记').layoutWeight(1).height(48).fontColor(this.palette().onAccent)
              .backgroundColor(this.palette().accent).onClick(() => this.commit())
          }.width('100%')
        } else if (this.step !== 'saving') {
          Button('取消并保留输入').width('100%').height(48).fontColor(this.palette().inkPrimary)
            .backgroundColor(this.palette().surfaceSubtle).onClick(() => this.requestClose())
        }
      }
      .width(this.isPhone ? '100%' : '92%').constraintSize({ maxWidth: 680 })
      .height(this.isPhone ? '100%' : '90%').padding(this.isPhone ? 16 : 24)
      .borderRadius(this.isPhone ? 0 : 16).backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })
      .onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.4)').onClick(() => this.requestClose())
  }
}
