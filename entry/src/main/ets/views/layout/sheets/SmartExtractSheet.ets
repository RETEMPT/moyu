import { KeyboardAvoidMode } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { SmartContent } from '../../../common/types/SmartContent';
import { SmartTask } from '../../../common/types/SmartTask';
import { SmartExtractService, SmartLayoutStyle, SMART_INPUT_LIMIT } from '../../../services/smart/SmartExtractService';
import { SmartNoteBuilder } from '../../../services/smart/SmartNoteBuilder';
import { OcrService } from '../../../services/ocr/OcrService';
import { DocumentExtractService } from '../../../services/smart/DocumentExtractService';
import { ModelConfigService } from '../../../services/ai/ModelConfigService';
import { ModelProfilePolicy } from '../../../services/ai/ModelProfilePolicy';
import { RemoteAiPolicy } from '../../../services/ai/RemoteAiPolicy';
import { common } from '@kit.AbilityKit';
import { REMOTE_AI_ENABLED } from '../../../common/constants/RuntimeCapabilities';
import { IconButton } from '../../common/IconButton';
import { AppIcon } from '../../common/AppIcon';
import { AssistantText } from '../../common/AssistantText';

interface SmartExtractDraft {
  input: string;
  imageUri: string;
  result: SmartContent | null;
  title: string;
  category: string;
  body: string;
  tasks: SmartTask[];
  selectedTaskIds: string[];
  includeRelations: boolean;
  style?: SmartLayoutStyle;
  mergeWrappedLines?: boolean;
  useAi?: boolean;
}

@Component
export struct SmartExtractSheet {
  onClose: () => void = () => {};
  onCommit: (content: SmartContent, selectedTasks: SmartTask[]) => Promise<void> = async () => {};
  onImportSource: (uri: string) => Promise<string> = async () => { throw new Error('资料库尚未就绪，请稍后重试'); };
  onOpenModelSettings: () => void = () => {};
  @Prop @Watch('requestClose') closeToken: number = 0;
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;
  @State private step: string = 'input';
  @State private inputText: string = '';
  @State private imageUri: string = '';
  @State private sourceNotice: string = '';
  @State private layoutStyle: SmartLayoutStyle = 'faithful';
  @State private useAi: boolean = false;
  @State private aiReady: boolean = false;
  @State private pdfStart: string = '1';
  @State private pdfEnd: string = '1';
  @State private importProgress: string = '';
  @State private mergeWrappedLines: boolean = false;
  @State private result: SmartContent | null = null;
  @State private title: string = '';
  @State private category: string = '未分类';
  @State private body: string = '';
  @State private resultTab: string = 'preview';
  @State private tasks: SmartTask[] = [];
  @State private selectedTaskIds: string[] = [];
  @State private includeRelations: boolean = false;
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
      this.useAi = REMOTE_AI_ENABLED && draft.useAi === true;
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
      this.includeRelations = draft.includeRelations;
      this.step = 'result';
    }
    this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.loadAiAvailability();
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

  private async loadAiAvailability(): Promise<void> {
    try {
      const profile = await ModelConfigService.getInstance().getActiveProfile();
      if (!this.alive) { return; }
      this.aiReady = REMOTE_AI_ENABLED && !ModelProfilePolicy.validate(profile) && !profile.credentialUnavailable && RemoteAiPolicy.consented(profile);
    } catch { if (this.alive) { this.aiReady = false; } }
    if (this.alive && !this.aiReady) { this.useAi = false; }
  }

  private async pickDocument(): Promise<void> {
    if (this.busy()) { return; }
    const id = ++this.requestId; this.step = 'importing'; this.errorMsg = ''; this.sourceNotice = ''; this.importProgress = '选择文档…';
    try {
      const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['文档与 Marker 结果|.pdf,.md,.txt,.json'];
      const selected = await new picker.DocumentViewPicker().select(options);
      if (!this.alive || id !== this.requestId || !selected.length) { return; }
      DocumentExtractService.validateInput(selected[0]);
      this.importProgress = '正在保存到本机资料库…';
      const localPath = await this.onImportSource(selected[0]);
      if (!this.alive || id !== this.requestId) { return; }
      this.sourceNotice = '资料已保存到本机资料库「外部参考」，可离线重新打开。';
      this.importProgress = '正在读取本机副本…';
      const result = await DocumentExtractService.read(getContext(this) as common.UIAbilityContext, localPath,
        Number(this.pdfStart), Number(this.pdfEnd), () => !this.alive || id !== this.requestId,
        (page: number) => { if (this.alive && id === this.requestId) { this.importProgress = `正在提取第 ${page} 页…`; } });
      if (!this.alive || id !== this.requestId) { return; }
      const appended = this.inputText.trim() ? `${this.inputText}\n\n${result.text}` : result.text;
      if (appended.length > SMART_INPUT_LIMIT) { throw new Error('追加后文字超过上限，请先整理当前内容或缩小导入范围'); }
      this.inputText = appended; this.sourceNotice += '\n' + result.notice; AppStorage.setOrCreate('smartExtractDraft', appended);
    } catch (error) {
      if (this.alive && id === this.requestId) { this.errorMsg = error instanceof Error ? error.message : '文档提取未成功，原输入已保留'; }
    } finally { if (this.alive && id === this.requestId) { this.step = 'input'; this.importProgress = ''; } }
  }

  private requestClose(): void {
    if (this.step === 'saving') {
      return;
    }
    AppStorage.setOrCreate('smartExtractDraft', this.inputText);
    const draft: SmartExtractDraft = { input: this.inputText, imageUri: this.imageUri,
      result: this.step === 'result' ? this.result : null, title: this.title,
      category: this.category, body: this.body, tasks: this.tasks,
      selectedTaskIds: this.selectedTaskIds, includeRelations: this.includeRelations,
      style: this.layoutStyle, mergeWrappedLines: this.mergeWrappedLines, useAi: this.useAi };
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
      this.inputText = this.inputText.trim().length > 0 ? `${this.inputText}\n\n${text}` : text;
      this.imageUri = picked.photoUris[0];
      this.sourceNotice = '图片文字已追加，请先校对姓名、数字、日期，再开始排版。';
      AppStorage.setOrCreate('smartExtractDraft', this.inputText);
    } catch (error) {
      if (this.alive && id === this.requestId) {
        this.errorMsg = error instanceof Error && error.message.includes('未识别到文字') ? error.message :
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
      const extracted = await SmartExtractService.getInstance().extract(this.inputText, '整理笔记', this.layoutStyle, this.useAi && this.aiReady, this.mergeWrappedLines);
      if (!this.alive || id !== this.requestId) {
        return;
      }
      this.result = extracted;
      this.title = extracted.title;
      this.body = extracted.formattedMarkdown || this.inputText;
      this.tasks = extracted.tasks.slice();
      // 待办与关联由用户选择，避免把识别建议直接写入日历。
      this.selectedTaskIds = [];
      this.includeRelations = false;
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
      const edited: SmartTask = { id: task.id, title: task.title, deadline: value, priority: task.priority };
      return edited;
    });
  }

  private chosenTasks(): SmartTask[] {
    return this.tasks.filter((task: SmartTask) => this.selectedTaskIds.includes(task.id));
  }

  private previewContent(): SmartContent {
    const data = this.result!;
    const content: SmartContent = { id: data.id, type: data.type, title: this.title.replace(/[\r\n]/g, ' ').trim(),
      category: this.category.trim() || '未分类', summary: data.summary, tags: data.tags,
      entities: data.entities, tasks: this.tasks, relations: this.includeRelations ? data.relations : [],
      keyPoints: data.keyPoints, rawMarkdown: data.rawMarkdown, formattedMarkdown: this.body,
      processingMode: data.processingMode, processingNotice: data.processingNotice, createdAt: data.createdAt };
    return content;
  }

  private previewBody(): string {
    return this.result ? SmartNoteBuilder.buildMarkdown(this.previewContent(), this.chosenTasks(), this.includeRelations) : '';
  }

  private async commit(): Promise<void> {
    if (!this.result || this.busy()) {
      return;
    }
    if (this.title.trim().length === 0 || this.body.trim().length === 0) {
      this.errorMsg = '标题和正文不能为空。';
      return;
    }
    this.errorMsg = '';
    this.step = 'saving';
    try {
      await this.onCommit(this.previewContent(), this.chosenTasks());
      AppStorage.setOrCreate('smartExtractDraft', '');
      AppStorage.delete('smartExtractResultDraft');
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
      this.hint('1  导入或粘贴 → 2  校对文字 → 3  预览排版 → 4  保存笔记')
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          AppIcon({ source: $r('app.media.ic_sparkle'), tint: this.palette().accent })
          Text('从图片识别文字').fontSize(14)
        }.justifyContent(FlexAlign.Center).width('100%')
      }.width('100%').height(48)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
        .onClick(() => this.pickImageAndOcr())
      Button('导入 PDF / 文字 / Marker 结果').width('100%').height(48)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle).onClick(() => this.pickDocument())
      Row({ space: 8 }) {
        Text('PDF 页范围').fontSize(12).fontColor(this.palette().inkSecondary)
        TextInput({ text: this.pdfStart, placeholder: '起始页' }).layoutWeight(1).height(44)
          .onChange((value: string) => { this.pdfStart = value; })
        Text('–').fontColor(this.palette().inkMuted)
        TextInput({ text: this.pdfEnd, placeholder: '结束页' }).layoutWeight(1).height(44)
          .onChange((value: string) => { this.pdfEnd = value; })
      }.width('100%')
      this.hint('导入会保存到本机资料库「外部参考」。PDF 每次提取最多 5 页；支持 Marker Markdown 和响应 JSON。')
      if (this.imageUri.length > 0) {
        Image(this.imageUri).width('100%').height(100).objectFit(ImageFit.Contain).borderRadius(8)
      }
      if (this.sourceNotice.length > 0) {
        this.hint(this.sourceNotice)
      }
      TextArea({ text: this.inputText, placeholder: '粘贴通知、课程资料或随笔，也可以先识别图片。' })
        .height(this.isPhone ? 180 : 220).width('100%').fontSize(TypographyTokens.BODY_REGULAR)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
        .onChange((value: string) => {
          this.inputText = value;
          AppStorage.setOrCreate('smartExtractDraft', value);
          this.errorMsg = '';
        })
      Text(`${this.inputText.length} / ${SMART_INPUT_LIMIT} 字`)
        .fontSize(TypographyTokens.TINY).fontColor(this.inputText.length > SMART_INPUT_LIMIT ? this.palette().danger : this.palette().inkMuted)
        .width('100%')
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
      this.hint(this.layoutStyle === 'study' ? '按明确标题和项目符号整理层级，不改写或补充知识；无需大模型。' : '保留段落、原顺序、代码与公式，仅补笔记标题；无需大模型。')
      Row({ space: 10 }) {
        Text('合并图片断行').fontSize(14).layoutWeight(1).fontColor(this.palette().inkPrimary)
        Toggle({ type: ToggleType.Switch, isOn: this.mergeWrappedLines }).selectedColor(this.palette().accent)
          .onChange((value: boolean) => { this.mergeWrappedLines = value; })
      }.width('100%').constraintSize({ minHeight: 48 })
      if (this.mergeWrappedLines) { this.hint('尝试连接普通正文的断行，列表、空段、代码、表格与公式保留。请对照原文检查多栏内容和特殊换行。') }
      if (REMOTE_AI_ENABLED) {
      Row({ space: 8 }) {
        Text('AI 整理').layoutWeight(1).fontColor(this.palette().inkPrimary)
        Toggle({ type: ToggleType.Switch, isOn: this.useAi && this.aiReady }).enabled(this.aiReady).selectedColor(this.palette().accent)
          .onChange((value: boolean) => { this.useAi = value && this.aiReady; })
      }.width('100%').constraintSize({ minHeight: 44 })
      this.hint(this.useAi && this.aiReady ? '校对后的文字将发送到你配置并授权的模型服务，保存前可检查并编辑结果。' :
        this.aiReady ? '关闭时使用本地规则，不联网。' : '未配置或未授权模型，AI 整理不可用；本机识别与离线排版仍可使用。')
      Button('模型设置').height(44).fontColor(this.palette().inkSecondary)
        .backgroundColor(this.palette().surfaceSubtle).onClick(() => {
          this.requestClose();
          this.onOpenModelSettings();
        })
      } else { this.hint('本地整理保留原文，不联网。') }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  resultPanel() {
    Column({ space: 12 }) {
      this.hint(this.result?.processingNotice || '')
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
        AssistantText({ text: this.previewBody() }).width('100%').padding(12).borderRadius(10).backgroundColor(this.palette().surfaceSubtle)
      }
      Text(`添加到日历 · 已选 ${this.selectedTaskIds.length} 项`)
        .fontSize(TypographyTokens.BODY_REGULAR).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
      if (this.tasks.length === 0) {
        this.hint('没有识别到明确的待办，可直接保存笔记。')
      }
      ForEach(this.tasks, (task: SmartTask) => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Checkbox({ name: task.id }).select(this.selectedTaskIds.includes(task.id))
              .width(24).height(24).onChange(() => this.toggleTask(task.id))
            Text(task.title).layoutWeight(1).fontColor(this.palette().inkPrimary).fontSize(14)
          }.width('100%').constraintSize({ minHeight: 44 })
          TextInput({ text: task.deadline || '', placeholder: '日期：YYYY-MM-DD；留空放入今天' })
            .height(44).fontSize(14).fontColor(this.palette().inkPrimary)
            .backgroundColor(this.palette().surface)
            .onChange((value: string) => this.editDeadline(task.id, value))
          this.hint(SmartNoteBuilder.resolveDeadline(task.deadline || '') ||
            ((task.deadline || '').length > 0 ? '日期待确认；未修改时暂存今天并保留原截止说明。' : '无截止日期，将加入今天的待办。'))
        }.width('100%').padding(10).borderRadius(10).backgroundColor(this.palette().surfaceSubtle)
      }, (task: SmartTask) => task.id)
      if (this.result && this.result.relations.length > 0) {
        Row({ space: 8 }) {
          Checkbox({ name: 'relations' }).select(this.includeRelations)
            .onChange((value: boolean) => { this.includeRelations = value; })
          Text('附上建议关联').layoutWeight(1).fontColor(this.palette().inkPrimary)
        }.width('100%').constraintSize({ minHeight: 44 })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('文字识别与智能排版').layoutWeight(1).fontSize(TypographyTokens.TITLE_SUB)
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
          Button(this.useAi && this.aiReady ? '开始 AI 排版' : '开始本地整理').width('100%').height(48)
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
