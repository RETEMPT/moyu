import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { documentLabel, documentIcon } from '../../common/utils/DocumentPresentation';
import { AppIcon } from './AppIcon';

/** Consistent paper cover; only the inner symbol and type name vary. */
@Component
export struct DocumentCover {
  @Prop type: string = 'Markdown';
  @Prop pageCount: number = 0;
  @Prop compact: boolean = false;
  @StorageProp('flowmindDarkMode') dark: boolean = false;

  build() {
    Column({ space: 6 }) {
      if (!this.compact) {
      Row() {
        Text(documentLabel(this.type)).fontSize(11).fontWeight(FontWeight.Medium)
          .fontColor(ThemeHelper.paletteOfDark(this.dark).accent)
        Blank()
        if (this.pageCount > 0) {
          Text(`${this.pageCount} 页`).fontSize(11).fontColor(ThemeHelper.paletteOfDark(this.dark).inkMuted)
        }
      }.width('100%')
      }
      Stack({ alignContent: Alignment.Center }) {
        AppIcon({ source: $r('app.media.ic_page'), iconSize: this.compact ? 36 : 60, tint: ThemeHelper.paletteOfDark(this.dark).border })
        AppIcon({ source: documentIcon(this.type), iconSize: this.compact ? 14 : 22, tint: ThemeHelper.paletteOfDark(this.dark).accent })
      }.width(this.compact ? 42 : 68).height(this.compact ? 42 : 68)
    }.width('100%').height('100%').padding({ left: this.compact ? 6 : 12, right: this.compact ? 6 : 12, top: 8, bottom: 8 })
      .justifyContent(FlexAlign.Center).backgroundColor(ThemeHelper.paletteOfDark(this.dark).accentSoft)
  }
}
