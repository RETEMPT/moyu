import { ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { LibraryPolicy } from '../../services/library/LibraryPolicy';
import { AppIcon } from './AppIcon';
import { IconButton } from './IconButton';

/** Text stays as a bounded excerpt; opening the card enters the full Markdown reader. */
@Component
export struct MemoTimelineCard {
  @Require @Prop note: NoteItem;
  onOpen: (note: NoteItem) => void = () => {};
  onTag: (tag: string) => void = () => {};
  onTogglePin: (note: NoteItem) => void = () => {};
  onToggleFavorite: (note: NoteItem) => void = () => {};
  onDelete: (noteId: string) => void = () => {};
  @Prop showActions: boolean = true;
  @Prop showFooterActions: boolean = false;
  onOpenActions: (note: NoteItem) => void = () => {};
  @State menuOpen: boolean = false;
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle); }
  private timestamp(): string {
    const time = this.note.createdAt || 0;
    if (!Number.isFinite(time) || time <= 0) { return '时间未记录'; }
    const date = new Date(time);
    if (!Number.isFinite(date.getTime())) { return '时间未记录'; }
    return String(date.getHours()).padStart(2, '0') + ':' + String(date.getMinutes()).padStart(2, '0');
  }
  private excerpt(): string {
    const source = (this.note.contentDetail || this.note.previewText || '').slice(0, 1600).trim();
    const firstLine = source.split('\n')[0];
    return (firstLine.replace(/^#{1,6}\s+/, '') === this.note.title
      ? source.slice(firstLine.length).trimStart() : source)
      .replace(/^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+|\d+\.\s+)/gm, '')
      .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').replace(/[*_`]/g, '').replace(/\s+/g, ' ').slice(0, 260);
  }
  @Builder
  actions() {
    Menu() {
      MenuItem({ content: '打开记录' }).onClick(() => { this.menuOpen = false; this.onOpen(this.note); })
      MenuItem({ content: this.note.isPinned ? '取消置顶' : '置顶记录' })
        .onClick(() => { this.menuOpen = false; this.onTogglePin(this.note); })
      MenuItem({ content: this.note.favorite ? '★ 取消收藏' : '☆ 加入收藏' })
        .onClick(() => { this.menuOpen = false; this.onToggleFavorite(this.note); })
      MenuItem({ content: '移至回收站' }).onClick(() => { this.menuOpen = false; this.onDelete(this.note.id); })
    }
  }
  build() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(this.note.title || '未命名笔记').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityText('打开记录 ' + this.note.title).onClick(() => this.onOpen(this.note))
        Text(this.timestamp()).fontSize(12).fontColor(this.palette().inkMuted)
        if (this.note.isPinned) {
          Text('置顶').fontSize(11).fontColor(this.palette().inkMuted)
        }
        if (this.showActions) {
          Button({ type: ButtonType.Normal }) {
            AppIcon({ source: $r('app.media.ic_more'), iconSize: 16, tint: this.palette().inkMuted })
          }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).borderRadius(6)
            .accessibilityText('笔记操作 ' + this.note.title).onClick(() => { this.menuOpen = !this.menuOpen; })
            .bindMenu(this.menuOpen, this.actions, { onDisappear: () => { this.menuOpen = false; } })
        }
      }.width('100%').height(44)
      if (this.excerpt().length > 0) {
        Column() {
          Text(this.excerpt()).fontSize(15).lineHeight(24).fontColor(this.palette().inkSecondary)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.width('100%')
          .accessibilityText('阅读摘要 ' + this.note.title).onClick(() => this.onOpen(this.note))
      }
      if (LibraryPolicy.tags(this.note).length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(LibraryPolicy.tags(this.note).slice(0, 8), (tag: string) => {
              Button({ type: ButtonType.Normal }) {
                Text('#' + tag).fontSize(12).fontColor(this.palette().inkSecondary).padding({ left: 6, right: 6, top: 3, bottom: 3 })
                  .borderRadius(3).backgroundColor(this.palette().tagBg)
              }.height(44).padding(0).backgroundColor(Color.Transparent).accessibilityText('查看标签 ' + tag)
                .onClick(() => this.onTag(tag))
            }, (tag: string) => tag)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }
      if (this.showFooterActions) {
        Row() {
          Blank()
          IconButton({ icon: $r('app.media.ic_more'), label: '资料操作 ' + this.note.title, compact: true,
            onAction: () => this.onOpenActions(this.note) })
        }.width('100%')
      }
    }.width('100%').padding({ left: 0, right: 0, top: 8, bottom: 14 }).alignItems(HorizontalAlign.Start)
      .backgroundColor(Color.Transparent).border({ width: { bottom: 1 }, color: this.palette().borderSubtle })
  }
}
