import { NoteItem } from '../../common/types/NoteItem';
import { ReaderPairPolicy } from '../../services/document/ReaderPairPolicy';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';

@Component
export struct ReaderPairPicker {
  @Require @Prop source: NoteItem;
  @Prop notes: NoteItem[] = [];
  @Prop @Watch('requestClose') closeToken: number = 0;
  onClose: () => void = () => {};
  onSelect: (id: string) => Promise<boolean> = async () => false;
  onOpenAssistant: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @StorageProp('flowmindStudyPreview') studyPreview: boolean = false;
  @State private keyword: string = '';
  @State private busy: boolean = false;
  @State private error: string = '';
  @State private limit: number = 40;

  private requestClose(): void { if (!this.busy) { this.onClose(); } }
  private matches(): NoteItem[] { return ReaderPairPolicy.candidates(this.notes, this.source, this.keyword); }
  private async select(id: string): Promise<void> {
    if (this.busy) { return; }
    this.busy = true; this.error = '';
    try {
      if (await this.onSelect(id)) { this.onClose(); }
      else { this.error = '资料未能打开，请检查保存状态后重试'; }
    } catch (error) { this.error = error instanceof Error ? error.message : '分屏未能打开，请重试'; }
    finally { this.busy = false; }
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('选择分屏资料')
            .fontSize(18).fontWeight(FontWeight.Medium).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary).layoutWeight(1)
          IconButton({ icon: $r('app.media.ic_close'), label: '关闭分屏选择', available: !this.busy, onAction: () => this.requestClose() })
        }.width('100%')
        if (this.studyPreview && (ReaderPairPolicy.isPdf(this.source) || ReaderPairPolicy.isMarkdown(this.source))) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 10 }) {
              AppIcon({ source: $r('app.media.ic_chat'), tint: ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accent })
              Text('AI 伴读').fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
                .fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accent)
              AppIcon({ source: $r('app.media.ic_chevron_right'), iconSize: 16,
                tint: ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accent })
            }.width('100%')
          }.width('100%').height(48).padding({ left: 12, right: 12 }).borderRadius(8).enabled(!this.busy)
            .backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accentSoft)
            .accessibilityText('打开 AI 伴读').onClick(this.onOpenAssistant)
        }
        TextInput({ text: this.keyword, placeholder: '搜索标题或项目' }).height(44).enabled(!this.busy)
          .backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).surfaceSubtle)
          .fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary)
          .onChange((value: string) => { this.keyword = value; this.limit = 40; })
        if (this.matches().length === 0) {
          Text(this.keyword.trim() ? '没有匹配的资料' : '先在资料库新建或导入另一份资料')
            .fontSize(14).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkMuted).layoutWeight(1).textAlign(TextAlign.Center)
        } else {
          List({ space: 6 }) {
            ForEach(this.matches().slice(0, this.limit), (note: NoteItem) => {
              ListItem() {
                Button({ type: ButtonType.Normal }) {
                  Column({ space: 5 }) {
                    Text(note.title || '未命名资料').fontSize(15).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary)
                      .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    Text(!note.category || note.category === '未分类' ? '资料库' : note.category).fontSize(12)
                      .fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkMuted).width('100%')
                  }.alignItems(HorizontalAlign.Start).width('100%')
                }.width('100%').constraintSize({ minHeight: 64 }).padding(12).borderRadius(5).enabled(!this.busy)
                  .backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).surfaceSubtle)
                  .accessibilityText('分屏打开 ' + note.title).onClick(() => this.select(note.id))
              }
            }, (note: NoteItem) => `${note.id}-${note.title}-${note.category}`)
            if (this.matches().length > this.limit) {
              ListItem() {
                Button('显示更多资料').height(44).width('100%').onClick(() => { this.limit += 40; })
                  .backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).surfaceSubtle)
                  .fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary)
              }
            }
          }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
        }
        if (this.error) { Text(this.error).fontSize(13).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).danger).width('100%') }
      }.padding(20).width(this.phone ? '96%' : 640).height(this.phone ? '90%' : '82%').borderRadius(8)
        .backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).surface).onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.32)').onClick(() => this.requestClose())
  }
}
