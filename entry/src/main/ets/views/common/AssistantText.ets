import { AssistantTextParser, AssistantBlock, AssistantSpan } from '../../services/ai/AssistantTextParser';
import { ThemeHelper } from '../../common/theme/ThemeHelper';

/** Shared by offline and model answers; streaming updates are coalesced. */
@Component
export struct AssistantText {
  @Prop @Watch('refresh') text: string = '';
  @Prop @Watch('refresh') streaming: boolean = false;
  @Prop hideActions: boolean = false;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  @State blocks: AssistantBlock[] = [];
  private timer: number = -1;
  aboutToAppear(): void { this.blocks = AssistantTextParser.parse(this.text); }
  aboutToDisappear(): void { if (this.timer !== -1) { clearTimeout(this.timer); } }
  private refresh(): void {
    if (!this.streaming) {
      if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
      this.blocks = AssistantTextParser.parse(this.text); return;
    }
    if (this.timer === -1) { this.timer = setTimeout(() => { this.timer = -1; this.blocks = AssistantTextParser.parse(this.text); }, 80); }
  }
  @Builder
  inline(text: string) {
    Text() {
      ForEach(AssistantTextParser.spans(text), (span: AssistantSpan) => {
        Span(span.text).fontWeight(span.style === 'bold' ? FontWeight.Bold : FontWeight.Normal)
          .fontStyle(span.style === 'italic' ? FontStyle.Italic : FontStyle.Normal)
          .fontFamily(span.style === 'code' ? 'monospace' : 'sans-serif')
          .decoration({ type: span.style === 'strike' ? TextDecorationType.LineThrough : TextDecorationType.None })
          .fontColor(span.style === 'code' ? ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accent : ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary)
      })
    }.fontSize(15).lineHeight(24).width('100%').copyOption(CopyOptions.LocalDevice)
  }
  @Builder
  block(block: AssistantBlock) {
    if (block.kind === 'heading') {
      Text(block.text).fontSize(block.level === 1 ? 20 : block.level === 2 ? 17 : 15)
        .fontWeight(FontWeight.Bold).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary)
        .width('100%').margin({ top: 6, bottom: 2 }).copyOption(CopyOptions.LocalDevice)
    } else if (block.kind === 'list') {
      Row({ space: 8 }) {
        Text(block.marker).fontSize(14).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accent).width(24).margin({ top: 2 })
        Column() { this.inline(block.text) }.layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Top)
    } else if (block.kind === 'table') {
      Scroll() {
        Column({ space: 0 }) {
          ForEach(block.rows, (row: string[], rowIndex: number) => {
            Row({ space: 0 }) {
              ForEach(row, (cell: string) => {
                Text(cell).width(148).padding(10).fontSize(13).lineHeight(20)
                  .fontWeight(rowIndex === 0 ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary).copyOption(CopyOptions.LocalDevice)
              })
            }.backgroundColor(rowIndex === 0 ? ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accentSoft : ThemeHelper.paletteOfDark(this.dark, this.themeStyle).surfaceSubtle)
              .border({ width: { bottom: 1 }, color: ThemeHelper.paletteOfDark(this.dark, this.themeStyle).borderSubtle })
          })
        }
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).width('100%').borderRadius(10)
    } else if (block.kind === 'code' || block.kind === 'math') {
      if (this.hideActions && block.language === 'action_proposal') {
        Text('建议操作见下方，请核对后确认。').fontSize(12).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accent)
      } else {
        Column({ space: 6 }) {
          if (block.language) { Text(block.language).fontSize(11).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkMuted).width('100%') }
          Text(block.text).fontFamily('monospace').fontSize(13).lineHeight(21).width('100%')
            .fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary).copyOption(CopyOptions.LocalDevice)
        }.width('100%').padding(12).borderRadius(10).backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).surfaceSubtle)
      }
    } else if (block.kind === 'quote') {
      Column() { this.inline(block.text) }.width('100%').padding(10)
        .border({ width: { left: 3 }, color: ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accent })
        .backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accentSoft)
    } else if (block.kind === 'divider') { Divider().color(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).borderSubtle) }
    else { this.inline(block.text) }
  }
  build() {
    Column({ space: 8 }) {
      ForEach(this.blocks, (block: AssistantBlock) => { this.block(block) },
        (block: AssistantBlock, index: number) => `${index}-${block.kind}-${block.text}`)
      if (this.streaming) { Text('生成中…').fontSize(11).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkMuted) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
