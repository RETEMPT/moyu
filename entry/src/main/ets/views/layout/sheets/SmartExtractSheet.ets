import { KeyboardAvoidMode } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { FileMarkdown, FileMarkdownService } from '../../../services/smart/FileMarkdownService';
import { IconButton } from '../../common/IconButton';
import { DocumentText } from '../../common/DocumentText';

interface LegacyExtractDraft { title: string; body: string; input: string; }

@Component
export struct SmartExtractSheet {
  onClose: () => void = () => {};
  onCommit: (title: string, markdown: string) => Promise<boolean> = async () => false;
  @Prop @Watch('requestClose') closeToken: number = 0;
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;
  @State private title: string = '';
  @State private markdown: string = '';
  @State private editing: boolean = false;
  @State private working: string = '';
  @State private status: string = '';
  private previewLimit: number = 24000;
  private requestId: number = 0;
  private alive: boolean = true;
  private previousKeyboardMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;

  aboutToAppear(): void {
    this.alive = true;
    const draft = AppStorage.get<FileMarkdown>('fileMarkdownDraft');
    const legacy = AppStorage.get<LegacyExtractDraft>('smartExtractResultDraft');
    this.title = draft ? draft.title : (legacy?.title || '');
    this.markdown = draft ? draft.markdown : (legacy?.body || legacy?.input || AppStorage.get<string>('smartExtractDraft') || '');
    this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.requestId++;
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode);
  }

  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle); }

  private previewText(): string {
    if (this.markdown.length <= this.previewLimit) { return this.markdown; }
    const end = this.markdown.lastIndexOf('\n', this.previewLimit);
    return this.markdown.slice(0, end >= this.previewLimit / 2 ? end : this.previewLimit - 1);
  }

  private remember(): void {
    const draft: FileMarkdown = { title: this.title, markdown: this.markdown };
    AppStorage.setOrCreate('fileMarkdownDraft', draft);
  }

  private requestClose(): void {
    if (this.working === '正在保存…') { return; }
    this.remember();
    this.requestId++;
    this.onClose();
  }

  private async pickDocument(): Promise<void> {
    if (this.working) { return; }
    const id = ++this.requestId;
    const cancelled = (): boolean => !this.alive || id !== this.requestId;
    this.status = '';
    this.working = '正在选择文件…';
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const selected = await new picker.DocumentViewPicker(context).select(options);
      if (cancelled() || !selected.length) { return; }
      const result = await FileMarkdownService.read(context, selected[0], cancelled,
        (message: string) => { if (!cancelled()) { this.working = message; } });
      if (cancelled()) { return; }
      this.title = result.title;
      this.markdown = result.markdown;
      this.editing = false;
      this.remember();
    } catch (error) {
      if (!cancelled()) { this.status = error instanceof Error ? error.message : '读取失败，请重新选择文件'; }
    } finally { if (!cancelled()) { this.working = ''; } }
  }

  private async commit(): Promise<void> {
    if (this.working || !this.markdown.trim()) { return; }
    this.working = '正在保存…';
    this.status = '';
    try {
      const saved = await this.onCommit(this.title.trim() || '识别文稿', this.markdown);
      if (!saved) { throw new Error('保存失败，Markdown 已保留'); }
      AppStorage.delete('fileMarkdownDraft');
      AppStorage.delete('smartExtractDraft');
      AppStorage.delete('smartExtractResultDraft');
      this.onClose();
    } catch (error) { this.status = (error as Error).message || '保存失败，Markdown 已保留'; }
    finally { this.working = ''; }
  }

  @Builder
  resultPanel() {
    if (this.editing) {
      TextInput({ text: this.title, placeholder: '文稿标题' }).height(44).width('100%').maxLength(200)
        .onChange((value: string) => { this.title = value; this.remember(); })
      TextArea({ text: this.markdown, placeholder: 'Markdown 正文' }).width('100%').height(350)
        .focusable(true).onChange((value: string) => { this.markdown = value; this.remember(); })
    } else {
      if (this.title) { Text(this.title).fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor(this.palette().inkPrimary).width('100%') }
      if (this.markdown.length > this.previewLimit) {
        Text('预览显示文稿开头，保存时写入全文。').fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
      }
      DocumentText({ text: this.previewText(), allowLinks: false }).width('100%')
    }
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('文字识别与排版').layoutWeight(1).fontSize(TypographyTokens.TITLE_SUB)
            .fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
          IconButton({ icon: $r('app.media.ic_close'), label: '关闭文字识别',
            available: this.working !== '正在保存…', onAction: () => this.requestClose() })
        }.width('100%')
        Button(this.markdown ? '更换文件' : '选择文件', { type: ButtonType.Normal }).width('100%').height(46)
          .fontColor(this.markdown ? this.palette().inkPrimary : this.palette().onAccent)
          .backgroundColor(this.markdown ? this.palette().surfaceSubtle : this.palette().accent)
          .enabled(!this.working).onClick(() => this.pickDocument())
        if (this.working) {
          Row({ space: 8 }) {
            LoadingProgress().width(22).height(22).color(this.palette().accent)
            Text(this.working).fontSize(14).fontColor(this.palette().inkSecondary)
          }.width('100%')
        } else if (!this.markdown) {
          Text('支持图片、PDF、Markdown、TXT、DOCX 和 PPTX').width('100%').fontSize(13)
            .fontColor(this.palette().inkSecondary)
        }
        if (this.status) { Text(this.status).width('100%').fontSize(14).fontColor(this.palette().danger) }
        if (this.markdown || this.editing) {
          Scroll() {
            Column({ space: 10 }) { this.resultPanel() }.width('100%')
          }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto)
          Row({ space: 8 }) {
            Button(this.editing ? '预览 Markdown' : '编辑 Markdown', { type: ButtonType.Normal }).layoutWeight(1).height(46)
              .enabled(!this.working).fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
              .onClick(() => { this.editing = !this.editing; })
            Button('保存为 Markdown', { type: ButtonType.Normal }).layoutWeight(1).height(46)
              .enabled(!this.working && this.markdown.trim().length > 0).fontColor(this.palette().onAccent)
              .backgroundColor(this.palette().accent).onClick(() => this.commit())
          }.width('100%')
        }
      }.width(this.isPhone ? '100%' : '92%').constraintSize({ maxWidth: 680 })
        .height(this.markdown || this.editing ? (this.isPhone ? '100%' : '86%') : undefined)
        .padding(this.isPhone ? 16 : 22).borderRadius(16).backgroundColor(this.palette().surface)
        .onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.4)').onClick(() => this.requestClose())
  }
}
