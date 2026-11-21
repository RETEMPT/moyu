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
  @Prop shelfTone: number = -1;
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

  private shelfPaper(): string {
    return (this.dark ? ['#2B3029', '#332E26', '#302C36'] : ['#E7E9DF', '#F0EBE2', '#EAE5F0'])[this.shelfTone] || this.coverColor();
  }

  private shelfDetail(): string {
    return (this.dark ? ['#4D5945', '#63553B', '#564966'] : ['#A4AE90', '#C3B58F', '#AEA2C4'])[this.shelfTone] || this.palette().border;
  }

  @Builder
  shelfMotif() {
    if (this.shelfTone === 0) {
      Column().width('31%').height('28%').position({ x: '57%', y: '74%' })
        .backgroundColor(this.shelfDetail()).opacity(0.46)
      Column().width('28%').height('55%').position({ x: '74%', y: '48%' })
        .backgroundColor(this.shelfDetail()).opacity(0.57)
    } else if (this.shelfTone === 1 && this.typeLabel() !== 'PDF') {
      Column().width('35%').height('54%').position({ x: '54%', y: '74%' })
        .rotate({ angle: 45 }).backgroundColor(this.shelfDetail()).opacity(0.46)
      Column().width('40%').height('65%').position({ x: '74%', y: '65%' })
        .rotate({ angle: 45 }).backgroundColor(this.shelfDetail()).opacity(0.56)
    } else if (this.shelfTone === 2 && this.typeLabel() === '笔记') {
      Column({ space: 6 }) {
        Divider().strokeWidth(3).color(this.shelfDetail())
        Divider().strokeWidth(3).color(this.shelfDetail())
        Divider().strokeWidth(3).color(this.shelfDetail())
        Divider().width('68%').strokeWidth(3).color(this.shelfDetail())
      }.width('38%').alignItems(HorizontalAlign.Start).position({ x: '60%', y: '58%' }).opacity(0.66)
    } else {
      Circle().width('44%').height('78%').position({ x: '52%', y: '57%' }).fill(this.shelfDetail()).opacity(0.44)
      if (this.shelfTone === 2) {
        Column().width('10%').height('55%').position({ x: '84%', y: '48%' })
          .backgroundColor(this.shelfDetail()).opacity(0.50)
      } else {
        Circle().width('50%').height('83%').position({ x: '66%', y: '43%' }).fill(this.shelfDetail()).opacity(0.48)
      }
    }
  }

  @Builder
  paperShelf() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.coverUrl.length > 0) {
        NoteCoverVisual({ source: this.coverUrl }).width('100%').height('100%')
      } else {
        this.shelfMotif()
        Column().width('6%').height('100%').backgroundColor(this.shelfDetail()).opacity(0.72)
        Text(this.titleLabel()).fontSize(this.compact ? 17 : 23).fontFamily('serif')
          .fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('78%').position({ x: '15%', y: '16%' })
      }
    }.width('100%').height('100%').backgroundColor(this.shelfPaper()).borderRadius(7).clip(true)
      .accessibilityText(this.titleLabel() + '，' + this.typeLabel()).hitTestBehavior(HitTestMode.None)
  }

  @Builder
  standardCover() {
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

  build() {
    if (this.shelfTone >= 0) { this.paperShelf() } else { this.standardCover() }
  }
}
