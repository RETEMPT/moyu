import { ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { AiModelCatalog, AiCatalogModel } from '../../services/ai/AiModelCatalog';

@Component
export struct CloudModelCatalog {
  @Prop selectedId: string = 'seed-pro';
  @State family: string = '';
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  onSelect: (id: string) => void = () => {};
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark); }

  build() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Image($r('app.media.ic_sparkle')).width(22).height(22).fillColor(this.palette().accent)
          Text('云端 AI').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
          Text('尚未开放').fontSize(12).fontColor(this.palette().inkSecondary).padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(6).backgroundColor(this.palette().surfaceSubtle)
        }.width('100%')
        Text('先浏览模型，按需接入。当前可使用自己的 API Key；云端服务暂未开放。')
          .fontSize(13).lineHeight(21).fontColor(this.palette().inkSecondary).width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
      Scroll() {
        Row({ space: 6 }) {
          ForEach(['全部', ...AiModelCatalog.FAMILIES], (name: string) => {
            Button(name).height(44).fontSize(13).type(ButtonType.Normal).borderRadius(8)
              .backgroundColor(this.family === (name === '全部' ? '' : name) ? this.palette().accentSoft : Color.Transparent)
              .fontColor(this.family === (name === '全部' ? '' : name) ? this.palette().accent : this.palette().inkSecondary)
              .onClick(() => { this.family = name === '全部' ? '' : name; })
          }, (name: string) => name)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      Column({ space: 8 }) {
        ForEach(AiModelCatalog.list(this.family), (item: AiCatalogModel) => {
          Row({ space: 12 }) {
            Text(item.family.slice(0, 1)).fontSize(16).fontWeight(FontWeight.Medium).width(36).height(36)
              .textAlign(TextAlign.Center).borderRadius(8).fontColor(this.palette().inkSecondary).backgroundColor(this.palette().surfaceSubtle)
            Column({ space: 4 }) {
              Text(item.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).maxLines(2)
              Text(item.provider).fontSize(12).fontColor(this.palette().inkSecondary)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text(this.selectedId === item.id ? '已选预览' : '预览').fontSize(12)
              .fontColor(this.selectedId === item.id ? this.palette().accent : this.palette().inkMuted)
          }.width('100%').constraintSize({ minHeight: 72 }).padding(12).borderRadius(10)
            .border({ width: 1, color: this.selectedId === item.id ? this.palette().accent : this.palette().borderSubtle })
            .backgroundColor(this.selectedId === item.id ? this.palette().accentSoft : this.palette().surface)
            .accessibilityText(`${item.name}，云端服务未开放，选择仅用于预览`)
            .onClick(() => this.onSelect(item.id))
        }, (item: AiCatalogModel) => item.id)
      }.width('100%')
      Text('此目录保存在本机，浏览和预览不发送资料，也不会更改当前模型。自配 API 的模型可用性及费用由服务商决定。')
        .fontSize(12).lineHeight(20).fontColor(this.palette().inkSecondary).width('100%')
      Text(`目录核对：${AiModelCatalog.CHECKED_AT}`).fontSize(11).fontColor(this.palette().inkMuted).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
