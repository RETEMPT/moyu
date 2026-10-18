import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { InkToolPolicy } from '../../services/ink/InkToolPolicy';

@Component
export struct InkWidthSlider {
  @Prop tool: string = 'pen';
  @Prop value: number = 3;
  @Prop accentColor: string = '';
  onChange: (value: number) => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';
  build() {
    Row({ space: 10 }) {
      Text(`${this.tool === 'eraser' ? '直径' : '粗细'} ${this.value} px`).fontSize(12)
        .fontColor(ThemeHelper.paletteOfDark(this.dark, this.style).inkPrimary).width(94)
      Slider({ value: this.value, min: InkToolPolicy.min(this.tool), max: InkToolPolicy.max(this.tool), step: 1 })
        .layoutWeight(1).height(44).selectedColor(this.accentColor || ThemeHelper.paletteOfDark(this.dark, this.style).accent)
        .accessibilityText(`${InkToolPolicy.label(this.tool)}大小，${this.value}`)
        .onChange((value: number) => this.onChange(InkToolPolicy.width(this.tool, value)))
    }.width('100%')
  }
}
