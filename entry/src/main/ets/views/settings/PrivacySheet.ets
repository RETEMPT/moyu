import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { PRIVACY_SECTIONS, PrivacySection } from '../../common/constants/PrivacyNotice';

@Component
export struct PrivacySheet {
  onClose: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('隐私与数据说明').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary).layoutWeight(1)
          Button('关闭').height(44).onClick(() => this.onClose())
        }.width('100%')
        Scroll() {
          Column({ space: 16 }) {
            ForEach(PRIVACY_SECTIONS, (section: PrivacySection) => {
              Column({ space: 6 }) {
                Text(section.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary).width('100%')
                Text(section.body).fontSize(14).lineHeight(22).fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary).width('100%')
              }.width('100%')
            }, (section: PrivacySection) => section.title)
          }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      }.padding(20).width(this.phone ? '94%' : 640).height('86%').borderRadius(18).backgroundColor(ThemeHelper.paletteOfDark(this.dark).surface)
        .onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.4)').onClick(() => this.onClose())
  }
}
