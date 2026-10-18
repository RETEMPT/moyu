import { AnimationTokens, ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';

@Component
export struct QuickMemoComposer {
  @Prop text: string = '';
  @Prop status: string = '';
  @Prop saving: boolean = false;
  @Prop ready: boolean = false;
  onChange: (value: string) => void = () => {};
  onSave: () => void = () => {};
  onRetryDraft: () => void = () => {};
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @State private focused: boolean = false;
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle); }
  build() {
    Column({ space: 0 }) {
      Text('随手记').fontSize(12).fontColor(this.palette().inkSecondary).width('100%').padding({ left: 16, top: 14 })
      TextArea({ text: this.text, placeholder: '写下此刻的想法…' })
        .height(96).maxLength(12000).fontSize(15).fontColor(this.palette().inkPrimary)
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })
        .placeholderColor(this.palette().inkMuted).backgroundColor(Color.Transparent).borderRadius(0)
        .enabled(this.ready && !this.saving).accessibilityText('随手记正文')
        .onFocus(() => { this.focused = true; })
        .onBlur(() => { this.focused = false; })
        .onChange((value: string) => this.onChange(value))
      Row({ space: 8 }) {
        if (this.status.includes('失败') || this.status.includes('未能') || !this.ready) {
          Text(this.status).fontSize(12).fontColor(this.palette().inkSecondary).layoutWeight(1).maxLines(2)
        } else { Blank().layoutWeight(1) }
        if (this.status === '草稿未能保存') {
          Button('重试草稿', { type: ButtonType.Normal }).height(44).fontSize(12)
            .fontColor(this.palette().accent).backgroundColor(Color.Transparent).onClick(() => this.onRetryDraft())
        }
        Button(this.saving ? '保存中' : '保存记录', { type: ButtonType.Normal }).height(44).fontSize(14)
          .padding({ left: 16, right: 16 }).borderRadius(5).fontColor(this.palette().canvas)
          .backgroundColor(this.palette().inkPrimary).enabled(this.ready && !this.saving && this.text.trim().length > 0)
          .onClick(() => this.onSave())
      }.width('100%').padding({ left: 16, right: 12, bottom: 8 })
    }.width('100%').borderRadius(5).backgroundColor(this.palette().canvas)
      .border({ width: 1, color: this.focused ? this.palette().border : this.palette().borderSubtle })
      .animation({ duration: AnimationTokens.DURATION_FAST, curve: AnimationTokens.CURVE_STANDARD })
  }
}
