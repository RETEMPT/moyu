import { ColorPalette } from '../../common/constants/DesignTokens';
import { NoteItem } from '../../common/types/NoteItem';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { MemoFeedPolicy, MemoDay } from '../../services/library/MemoFeedPolicy';
import { AppIcon } from './AppIcon';

@Component
export struct MemoCalendar {
  @Prop notes: NoteItem[] = [];
  @Prop selectedDate: string = '';
  onSelectDate: (date: string) => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @State year: number = new Date().getFullYear();
  @State month: number = new Date().getMonth();
  private weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.themeStyle); }
  private moveMonth(offset: number): void {
    const next = new Date(this.year, this.month + offset, 1);
    this.year = next.getFullYear(); this.month = next.getMonth();
  }
  build() {
    Column({ space: 4 }) {
      Row() {
        Text(`${this.year}年${this.month + 1}月`).fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary).layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_back'), iconSize: 13, tint: this.palette().inkMuted })
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText('记录日历上个月').onClick(() => this.moveMonth(-1))
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_chevron_right'), iconSize: 13, tint: this.palette().inkMuted })
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText('记录日历下个月').onClick(() => this.moveMonth(1))
      }.width('100%')
      Row() {
        ForEach(this.weekdays, (label: string) => {
          Text(label).fontSize(11).fontColor(this.palette().inkMuted).layoutWeight(1).textAlign(TextAlign.Center)
        }, (label: string) => label)
      }.width('100%').height(24)
      GridRow({ columns: 7, gutter: 0 }) {
        ForEach(MemoFeedPolicy.month(this.notes, this.year, this.month), (day: MemoDay) => {
          GridCol() {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 2 }) {
                Text(String(day.day)).fontSize(12)
                  .fontColor(this.selectedDate === day.key ? this.palette().onAccent : this.palette().inkPrimary)
                Circle({ width: 3, height: 3 }).fill(day.count > 0 ? this.palette().inkSecondary : Color.Transparent)
              }.justifyContent(FlexAlign.Center).width('100%').height('100%')
            }.width('100%').height(44).padding(0).borderRadius(6)
              .opacity(day.inMonth ? 1 : 0.35)
              .backgroundColor(this.selectedDate === day.key ? this.palette().accent : day.count > 0 ? this.palette().activeBg : Color.Transparent)
              .accessibilityText(`${day.key}，${day.count} 条记录`)
              .onClick(() => this.onSelectDate(this.selectedDate === day.key ? '' : day.key))
          }
        }, (day: MemoDay) => day.key + ':' + day.count)
      }.width('100%')
    }.width('100%')
  }
}
