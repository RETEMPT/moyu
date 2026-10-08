import { ColorPalette, LayoutTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { AppIcon } from './AppIcon';

/** Shared 44vp target with an explicit action name for accessibility. */
@Component
export struct IconButton {
  @Prop icon: Resource = $r('app.media.ic_more');
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop destructive: boolean = false;
  @Prop available: boolean = true;
  onAction: () => void = () => {};
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.isDarkMode); }

  build() {
    Button({ type: ButtonType.Normal }) {
      AppIcon({ source: this.icon, tint: this.destructive ? this.palette().danger :
        (this.selected ? this.palette().accent : this.palette().inkSecondary) })
    }
    .width(LayoutTokens.MIN_TOUCH_TARGET)
    .height(LayoutTokens.MIN_TOUCH_TARGET)
    .padding(0)
    .borderRadius(12)
    .backgroundColor(this.selected ? this.palette().accentSoft : Color.Transparent)
    .enabled(this.available)
    .opacity(this.available ? 1 : 0.4)
    .accessibilityText(this.label)
    .accessibilityDescription(this.selected ? '已选中' : '')
    .bindTips(this.label)
    .onClick(() => this.onAction())
  }
}
