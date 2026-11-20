import { ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { MemoExcerptPart, MemoFeedPolicy } from '../../services/library/MemoFeedPolicy';
import { NoteTagPresentation } from '../../services/library/NoteTagPresentation';
import { AppIcon } from './AppIcon';
import { IconButton } from './IconButton';
import { NoteTagBadge } from './NoteTagBadge';

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
  private title(): string {
    return NoteTagPresentation.displayTitle(this.note.title || '', MemoFeedPolicy.cardTags(this.note)) || '随手记';
  }
  private timestamp(): string {
    const time = this.note.createdAt || this.note.updatedAt || 0;
    if (!Number.isFinite(time) || time <= 0) { return '时间未记录'; }
    const date = new Date(time);
    if (!Number.isFinite(date.getTime())) { return '时间未记录'; }
    return String(date.getHours()).padStart(2, '0') + ':' + String(date.getMinutes()).padStart(2, '0');
  }
  private excerptInk(part: MemoExcerptPart): string {
    return part.kind === 'reference' ? this.palette().link : this.palette().inkSecondary;
  }
  @Builder
  summary(parts: MemoExcerptPart[]) {
    if (parts.length > 0) {
      Text() {
        ForEach(parts, (part: MemoExcerptPart) => {
          Span(part.text).fontColor(this.excerptInk(part))
            .fontWeight(part.kind === 'text' ? FontWeight.Normal : FontWeight.Medium)
        }, (part: MemoExcerptPart, index: number) => `${index}:${part.kind}:${part.text}`)
      }.fontSize(15).lineHeight(24).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        .accessibilityText('阅读摘要 ' + this.note.title).onClick(() => this.onOpen(this.note))
    }
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
        Text(this.title()).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
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
      this.summary(MemoFeedPolicy.excerpt(this.note))
      if (MemoFeedPolicy.cardTags(this.note).length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(MemoFeedPolicy.cardTags(this.note), (tag: string) => {
            Button({ type: ButtonType.Normal }) {
              NoteTagBadge({ tag })
            }.height(44).padding(0).margin({ right: 6 }).backgroundColor(Color.Transparent)
              .accessibilityText('查看标签 ' + tag).onClick(() => this.onTag(tag))
          }, (tag: string) => tag)
        }.width('100%')
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
