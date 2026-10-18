import { ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteCoverVisual } from '../reader/NoteCoverVisual';
import { AppIcon } from './AppIcon';

/** Lightweight, format-specific covers; no document parsing or ink decoding in shelf rows. */
@Component
export struct DocumentCover {
  @Prop type: string = 'Markdown';
  @Prop title: string = '';
  @Prop pageCount: number = 0;
  @Prop coverUrl: string = '';
  @Prop compact: boolean = false;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';

  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.themeStyle); }
  private titleLabel(): string {
    return this.title.trim().replace(/\.(pdf|docx?|markdown|md|txt|png|jpe?g|webp|bmp|gif)$/i, '') || '未命名笔记';
  }
  private typeLabel(): string {
    const kind = this.type.toLowerCase();
    if (kind === 'image' || kind === '图片') { return '图片'; }
    if (kind === 'pdf') { return 'PDF'; }
    if (['doc', 'docx', 'word', '资料'].includes(kind)) { return 'Word'; }
    if (['canvas', 'handwriting', '白板', '白纸笔记', '稿纸'].includes(kind)) { return '手写'; }
    if (kind === 'task' || kind === '待办') { return '待办'; }
    return '笔记';
  }
  private coverColor(): string {
    if (this.dark) { return '#292A28'; }
    if (this.typeLabel() === 'PDF') { return '#F0EBE4'; }
    if (this.typeLabel() === '图片') { return '#E9EFE9'; }
    if (this.typeLabel() === 'Word') { return '#E9EDF4'; }
    if (this.typeLabel() === '手写') { return '#ECEAF2'; }
    return '#F3F1EA';
  }
  private coverIcon(): Resource {
    if (this.typeLabel() === 'PDF') { return $r('app.media.ic_pdf'); }
    if (this.typeLabel() === '图片') { return $r('app.media.ic_cover'); }
    if (this.typeLabel() === '手写') { return $r('app.media.ic_pen'); }
    if (this.typeLabel() === '待办') { return $r('app.media.ic_check'); }
    return $r('app.media.ic_read');
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.coverUrl.length > 0) {
        NoteCoverVisual({ source: this.coverUrl }).width('100%').height('100%')
      }
      Column() {
        Column({ space: this.compact ? 6 : 16 }) {
          AppIcon({ source: this.coverIcon(), iconSize: this.compact ? 22 : 38, tint: this.palette().inkSecondary })
          if (!this.compact) {
            Text(this.titleLabel()).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
              .textAlign(TextAlign.Center).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(this.compact ? 4 : 22)
          .backgroundColor(this.coverUrl.length > 0 ? this.palette().surface : Color.Transparent)
          .opacity(this.coverUrl.length > 0 ? 0 : 1)
        Row() {
          Text(this.typeLabel()).fontSize(this.compact ? 9 : 11).fontWeight(FontWeight.Medium).fontColor(this.palette().inkSecondary)
          Blank()
          if (this.pageCount > 0 && !this.compact) {
            Text(`${this.pageCount} 页`).fontSize(11).fontColor(this.palette().inkMuted)
          }
        }.width('100%').height(this.compact ? 22 : 32).padding({ left: this.compact ? 6 : 14, right: 14 })
          .backgroundColor(this.coverUrl.length > 0 ? this.palette().surface : Color.Transparent)
      }.width('100%').height('100%')
      Column().width(3).height('100%').backgroundColor(this.palette().border).opacity(0.65)
    }.width('100%').height('100%').backgroundColor(this.coverColor())
      .border({ width: 1, color: this.palette().borderSubtle, radius: 8 }).borderRadius(8).clip(true)
      .accessibilityText(this.titleLabel() + '，' + this.typeLabel()).hitTestBehavior(HitTestMode.None)
  }
}
