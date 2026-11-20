import { ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';

@Component
export struct DocumentImportStatus {
  @Prop message: string = '';
  @Prop busy: boolean = false;
  @Prop failed: boolean = false;
  @Prop canOpen: boolean = false;
  onOpen: () => void = () => {};
  onClose: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') theme: string = 'mono';

  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.theme); }

  build() {
    Column() {
      Row({ space: 8 }) {
        if (this.busy) { LoadingProgress().width(20).height(20).color(this.palette().accent) }
        Text(this.message).layoutWeight(1).fontSize(13)
          .fontColor(this.failed ? this.palette().danger : this.palette().inkPrimary)
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!this.busy) {
          if (this.canOpen) {
            Button('打开', { type: ButtonType.Normal }).height(44).fontSize(13)
              .backgroundColor(Color.Transparent).fontColor(this.palette().accent).onClick(this.onOpen)
          }
          Button('关闭', { type: ButtonType.Normal }).height(44).fontSize(13)
            .backgroundColor(Color.Transparent).fontColor(this.palette().inkSecondary).onClick(this.onClose)
        }
      }.width('94%').constraintSize({ maxWidth: 600, minHeight: 48 })
        .padding({ left: 14, right: 6 }).borderRadius(12)
        .backgroundColor(this.palette().surface).border({ width: 1, color: this.palette().borderSubtle })
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.12)', offsetY: 4 })
    }.width('100%').height('100%').justifyContent(FlexAlign.End).padding({ bottom: 62 })
      .hitTestBehavior(HitTestMode.Transparent)
  }
}
