import { picker } from '@kit.CoreFileKit';
import { AnimationTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NOTE_COVER_PRESETS, NoteCoverPreset } from '../../../common/types/NoteCover';
import { NoteCoverVisual } from '../../reader/NoteCoverVisual';

@Component
export struct NoteCoverSheet {
  @Prop selected: string = '';
  @Prop @Watch('closeRequested') closeToken: number = 0;
  onClose: () => void = () => {};
  onSave: (source: string) => Promise<void> = async () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @State draft: string = '';
  @State busy: boolean = false;
  @State error: string = '';
  private alive: boolean = true;

  aboutToAppear(): void { this.draft = this.selected; this.alive = true; }
  aboutToDisappear(): void { this.alive = false; }
  private closeRequested(): void { if (!this.busy) { this.onClose(); } }

  private async selectPhoto(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    try {
      const options = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new picker.PhotoViewPicker().select(options);
      if (this.alive && result.photoUris.length > 0) { this.draft = result.photoUris[0]; }
    } catch { if (this.alive) { this.error = '图片未能打开，请重试；原封面已保留。'; } }
    finally { if (this.alive) { this.busy = false; } }
  }

  private async save(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    this.error = '';
    try { await this.onSave(this.draft); this.onClose(); }
    catch { this.error = '封面保存失败，原封面已保留，请重试。'; this.busy = false; }
  }

  @Builder
  presetCard(preset: NoteCoverPreset) {
    Column({ space: 6 }) {
      NoteCoverVisual({ source: preset.id }).height(72).borderRadius(8).clip(true)
      Text(preset.title).fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary)
      Text(preset.hint).fontSize(11).maxLines(2)
        .fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary)
    }.layoutWeight(1).padding(8).borderRadius(12)
      .backgroundColor(ThemeHelper.paletteOfDark(this.dark).surfaceSubtle)
      .border({ width: this.draft === preset.id ? 2 : 1,
        color: this.draft === preset.id ? ThemeHelper.paletteOfDark(this.dark).accent : ThemeHelper.paletteOfDark(this.dark).border })
      .enabled(!this.busy).accessibilityText(`${preset.title}封面${this.draft === preset.id ? '，已选择' : ''}`)
      .onClick(() => { this.draft = preset.id; })
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Column({ space: 4 }) {
            Text('笔记封面').fontSize(20).fontWeight(FontWeight.Bold)
              .fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary)
            Text('选择风格，或使用自己的图片').fontSize(12)
              .fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button('✕').width(44).height(44).accessibilityText('关闭封面选择')
            .backgroundColor(Color.Transparent).fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary)
            .enabled(!this.busy).onClick(() => this.closeRequested())
        }.width('100%')
        Scroll() {
          Column({ space: 12 }) {
            if (this.draft.length > 0) {
              NoteCoverVisual({ source: this.draft }).height(120).borderRadius(12).clip(true)
            }
            Row({ space: 10 }) { this.presetCard(NOTE_COVER_PRESETS[0]); this.presetCard(NOTE_COVER_PRESETS[1]); }
            Row({ space: 10 }) { this.presetCard(NOTE_COVER_PRESETS[2]); this.presetCard(NOTE_COVER_PRESETS[3]); }
            Row({ space: 10 }) {
              Button('从相册选择').height(44).layoutWeight(1).enabled(!this.busy)
                .backgroundColor(ThemeHelper.paletteOfDark(this.dark).surfaceSubtle).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary)
                .onClick(() => this.selectPhoto())
              Button('移除封面').height(44).layoutWeight(1).enabled(!this.busy)
                .backgroundColor(ThemeHelper.paletteOfDark(this.dark).surfaceSubtle).fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary)
                .onClick(() => { this.draft = ''; })
            }.width('100%')
            Text('封面不改写 Markdown 正文；自选图片保存到本机，请选择 12 MB 以内的图片。')
              .fontSize(12).lineHeight(20).fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary)
            if (this.error.length > 0) {
              Text(this.error).fontSize(13).fontColor(ThemeHelper.paletteOfDark(this.dark).danger)
            }
          }.width('100%').constraintSize({ minHeight: '100%' }).justifyContent(FlexAlign.Start)
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
        Button(this.busy ? '处理中…' : '保存封面').width('100%').height(48)
          .backgroundColor(ThemeHelper.paletteOfDark(this.dark).accent).fontColor(Color.White)
          .enabled(!this.busy).onClick(() => this.save())
      }.width(this.phone ? '100%' : '92%').constraintSize({ maxWidth: 520 })
        .height(this.phone ? '100%' : '86%').padding(20).borderRadius(this.phone ? 0 : 16)
        .backgroundColor(ThemeHelper.paletteOfDark(this.dark).surface).onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.36)')
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
      .onClick(() => this.closeRequested())
  }
}
