import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { PRIVACY_SECTIONS, PrivacySection } from '../../common/constants/PrivacyNotice';
import { bundleManager, common } from '@kit.AbilityKit';
import { PRIVACY_URL } from '../../common/constants/PublicationInfo';

@Component
export struct PrivacySheet {
  onClose: () => void = () => {};
  @Prop welcome: boolean = false;
  @Prop saving: boolean = false;
  onChoice: (agree: boolean) => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @State version: string = '';
  aboutToAppear(): void {
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).then((info: bundleManager.BundleInfo) => {
      this.version = `${info.versionName} (${info.versionCode})`;
    }).catch(() => { this.version = '版本信息暂不可用'; });
  }
  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('隐私与数据说明').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary).layoutWeight(1)
          if (!this.welcome) { Button('关闭').height(44).onClick(() => this.onClose()) }
        }.width('100%')
        Scroll() {
          Column({ space: 16 }) {
            Text(`墨语 ${this.version}`).fontSize(14).fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary).width('100%')
            Text('开源许可：MIT · 本地课程学习工作台').fontSize(13).fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary).width('100%')
            if (PRIVACY_URL) {
              Button('查看在线隐私政策').height(44).width('100%').onClick(() => {
                const context = getContext(this) as common.UIAbilityContext;
                context.startAbility({ action: 'ohos.want.action.viewData', uri: PRIVACY_URL }).catch(() => {});
              })
            }
            ForEach(PRIVACY_SECTIONS, (section: PrivacySection) => {
              Column({ space: 6 }) {
                Text(section.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary).width('100%')
                Text(section.body).fontSize(14).lineHeight(22).fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary).width('100%')
              }.width('100%')
            }, (section: PrivacySection) => section.title)
          }.width('100%')
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
        if (this.welcome) {
          Text('外部 AI 默认关闭，附近传递只在主动连接时请求权限。离线使用后，也可在模型设置中单独授权 AI 服务。')
            .fontSize(13).lineHeight(20).fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary).width('100%')
          Button('同意隐私说明并继续').height(48).width('100%').enabled(!this.saving).onClick(() => this.onChoice(true))
          Button('暂不同意，离线使用').height(48).width('100%').enabled(!this.saving).onClick(() => this.onChoice(false))
        }
      }.padding(20).width(this.phone ? '94%' : 640).height('86%').borderRadius(18).backgroundColor(ThemeHelper.paletteOfDark(this.dark).surface)
        .onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.4)').onClick(() => { if (!this.welcome) { this.onClose(); } })
  }
}
