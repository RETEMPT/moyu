/**
 * 迁移中占位视图
 *
 * 用于尚未完成视图层迁移的功能页（白板 / AI 墨客），
 * 明确告知当前状态，避免出现空白页让用户误以为功能丢失。
 */
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';

@Component
export struct PendingWorkspace {
  @Require @Prop title: string;
  @Require @Prop description: string;
  @Prop pendingItems: string[] = [];

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  build() {
    Column() {
      Column({ space: 10 }) {
        Text(this.title)
          .fontSize(TypographyTokens.TITLE_SECTION)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
        Text(this.description)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkSecondary)
          .textAlign(TextAlign.Center)

        Column({ space: 6 }) {
          ForEach(this.pendingItems, (item: string) => {
            Row({ space: 8 }) {
              Text('○')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
              Text(item)
                .fontSize(TypographyTokens.CAPTION)
                .fontColor(this.palette().inkSecondary)
                .layoutWeight(1)
            }
            .width('100%')
          }, (item: string) => item)
        }
        .width('100%')
        .padding(12)
        .borderRadius(8)
        .backgroundColor(this.palette().surfaceSubtle)
        .margin({ top: 6 })
      }
      .width(360)
      .alignItems(HorizontalAlign.Center)
      .padding(24)
      .borderRadius(10)
      .border({ width: 1, color: this.palette().border, style: BorderStyle.Dashed })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.palette().canvas)
  }
}
