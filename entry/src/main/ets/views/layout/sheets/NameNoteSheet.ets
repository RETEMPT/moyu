import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { SheetOverlay } from './SheetScaffold';
import { AppIcon } from '../../common/AppIcon';

/** Project uses the existing category field; topic tags remain independent. */
@Component
export struct NameNoteSheet {
  @Prop defaultName: string = '未命名笔记';
  @Prop noteType: string = 'Markdown';
  @Prop defaultProject: string = '未分类';
  @Prop projects: string[] = [];
  @Prop busy: boolean = false;
  @Prop errorMessage: string = '';
  onClose: () => void = () => {};
  onConfirm: (name: string, project: string, tags: string[]) => void = () => {};
  onTypeChange: (type: string) => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'ink';
  @State draft: string = '';
  @State destination: string = '未分类';
  @State tagDraft: string = '';
  aboutToAppear(): void { this.destination = this.defaultProject || '未分类'; }
  private palette() { return ThemeHelper.paletteOfDark(this.dark, this.style); }
  private destinations(): string[] { return Array.from(new Set(['未分类', this.defaultProject].concat(this.projects).filter((s: string) => s.length > 0))); }
  private submit(): void {
    if (this.busy) { return; }
    const tags = Array.from(new Set(this.tagDraft.split(/[,，、\n]/).map((s: string) => s.trim()).filter((s: string) => s.length > 0))).slice(0, 12);
    this.onConfirm(this.draft.trim() || (this.noteType === 'Markdown' ? '未命名笔记' : '未命名手写白板'), this.destination, tags);
  }
  @Builder
  typeChoice(type: string, title: string, detail: string, icon: Resource) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 6 }) {
        AppIcon({ source: icon, tint: this.noteType === type ? this.palette().accent : this.palette().inkSecondary })
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
        Text(detail).fontSize(11).fontColor(this.palette().inkSecondary)
      }.padding(12).width('100%')
    }.layoutWeight(1).height(100).padding(0).borderRadius(12).enabled(!this.busy)
      .backgroundColor(this.noteType === type ? this.palette().accentSoft : this.palette().surfaceSubtle)
      .accessibilityText(`${title}${this.noteType === type ? '，已选中' : ''}，${detail}`).onClick(() => this.onTypeChange(type))
  }
  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 12 }) {
        Text('新建内容').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).width('100%')
        Scroll() {
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              this.typeChoice('Markdown', '文字笔记', '记录、整理与双向链接', $r('app.media.ic_note'))
              this.typeChoice('Handwriting', '手写白板', '书写、绘图与批注', $r('app.media.ic_pen'))
            }.width('100%')
            Text('标题').fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
            TextInput({ text: this.draft, placeholder: this.noteType === 'Markdown' ? '例如：高等数学 · 第一章' : '例如：电路分析草稿' })
              .height(48).enabled(!this.busy).fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
              .onChange((v: string) => { this.draft = v; }).onSubmit(() => this.submit())
            Text('所属项目').fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
            Select(this.destinations().map((value: string) => { const option: SelectOption = { value }; return option; }))
              .selected(this.destinations().indexOf(this.destination)).value(this.destination).width('100%').height(48)
              .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle).enabled(!this.busy)
              .onSelect((_index: number, value: string) => { this.destination = value; })
            Text('主题标签（选填）').fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
            TextInput({ text: this.tagDraft, placeholder: '例如：课堂、复习，用逗号分隔' }).height(48).enabled(!this.busy)
              .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle).maxLength(240)
              .onChange((v: string) => { this.tagDraft = v; })
            Text('项目决定资料存放分区；标签用于跨项目筛选。').fontSize(12).fontColor(this.palette().inkMuted).width('100%')
            if (this.errorMessage) { Text(this.errorMessage).fontSize(13).fontColor(this.palette().danger).width('100%') }
          }.width('100%')
        }.width('100%').constraintSize({ maxHeight: 360 }).scrollBar(BarState.Auto)
        Row({ space: 10 }) {
          Button('取消').height(44).layoutWeight(1).enabled(!this.busy).backgroundColor(this.palette().surfaceSubtle)
            .fontColor(this.palette().inkSecondary).onClick(this.onClose)
          Button(this.busy ? '正在创建…' : '创建').height(44).layoutWeight(1).enabled(!this.busy)
            .backgroundColor(this.palette().accent).fontColor(this.palette().onAccent).onClick(() => this.submit())
        }.width('100%')
      }.width('100%')
    }
  }
}
