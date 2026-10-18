import { AnimationTokens, ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { AppIcon } from '../common/AppIcon';
import { readingRenderKey } from '../../common/utils/ForEachKeys';
import { NAV_LIBRARY } from '../../common/constants/WorkspaceConstants';
import { AI_FEATURES_VISIBLE } from '../../common/constants/RuntimeCapabilities';
import { ReadingProgressPolicy } from '../../services/document/ReadingProgressPolicy';
import { MemoFeedPolicy, MemoTagCount } from '../../services/library/MemoFeedPolicy';
import { QuickMemoComposer } from '../common/QuickMemoComposer';
import { MemoTimelineCard } from '../common/MemoTimelineCard';
import { MemoCalendar } from '../common/MemoCalendar';

/** A quiet document page with local composition and bounded record excerpts. */
@Component
export struct HomeWorkspace {
  @Prop @Watch('resetWindow') recentNotes: NoteItem[] = [];
  @Prop @Watch('resetWindow') selectedDate: string = '';
  @Prop @Watch('resetWindow') selectedTag: string = '';
  @Prop memoDraft: string = '';
  @Prop memoStatus: string = '';
  @Prop memoSaving: boolean = false;
  @Prop memoReady: boolean = false;
  onMemoChange: (value: string) => void = () => {};
  onSaveMemo: () => void = () => {};
  onRetryMemoDraft: () => void = () => {};
  onSelectDate: (date: string) => void = () => {};
  onOpenTag: (tag: string) => void = () => {};
  onClearFilters: () => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};
  onCreateNote: () => void = () => {};
  onCreateHandwriting: () => void = () => {};
  onImportDocument: () => void = () => {};
  onSmartExtract: () => void = () => {};
  onTogglePin: (note: NoteItem) => void = () => {};
  onToggleFavorite: (note: NoteItem) => void = () => {};
  onDeleteNote: (noteId: string) => void = () => {};
  onNavigate: (navKey: string) => void = () => {};
  onSearchNotes: () => void = () => {};
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindSingleColumn') singleColumn: boolean = true;
  @State private pinnedOnly: boolean = false;
  @State private filtersOpen: boolean = false;
  @State private shelfVisibleCount: number = 12;
  private cachedSource: NoteItem[] | null = null;
  private cachedQuery: string = '';
  private cachedNotes: NoteItem[] = [];
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle); }
  private resetWindow(): void { this.shelfVisibleCount = 12; }
  private displayNotes(): NoteItem[] {
    const query = JSON.stringify([this.selectedDate, this.selectedTag, this.pinnedOnly]);
    if (this.cachedSource === this.recentNotes && this.cachedQuery === query) { return this.cachedNotes; }
    this.cachedNotes = MemoFeedPolicy.query(this.recentNotes, this.selectedDate, this.selectedTag, this.pinnedOnly);
    this.cachedSource = this.recentNotes; this.cachedQuery = query;
    return this.cachedNotes;
  }
  private latestNote(): NoteItem | null { return ReadingProgressPolicy.latest(this.recentNotes); }
  private dayStart(note: NoteItem): number {
    const raw = note.createdAt || note.updatedAt || 0;
    if (!Number.isFinite(raw) || raw <= 0) { return 0; }
    const date = new Date(raw);
    return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
  }
  private dayLabel(note: NoteItem): string {
    const raw = note.createdAt || note.updatedAt || 0;
    if (!Number.isFinite(raw) || raw <= 0) { return '时间未记录'; }
    const date = new Date(raw); const now = new Date();
    const start = this.dayStart(note);
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    if (start === today) { return '今天'; }
    if (start === today - 86400000) { return '昨天'; }
    if (date.getFullYear() === now.getFullYear()) { return `${date.getMonth() + 1}月${date.getDate()}日`; }
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
  }
  private showDayHeader(index: number): boolean {
    const notes = this.displayNotes();
    return index === 0 || this.dayStart(notes[index]) !== this.dayStart(notes[index - 1]);
  }
  @Builder
  quickAction(icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        AppIcon({ source: icon, iconSize: 24, tint: this.palette().inkPrimary })
        Text(label).fontSize(14).fontColor(this.palette().inkPrimary).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%')
    }.width('100%').height(48).padding({ left: 8, right: 8 }).borderRadius(5).backgroundColor(Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText(label).onClick(action)
  }
  @Builder
  feedTab(label: string, pinned: boolean) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(14)
      .fontWeight(this.pinnedOnly === pinned ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.pinnedOnly === pinned ? this.palette().inkPrimary : this.palette().inkMuted)
      .backgroundColor(Color.Transparent).borderRadius(0).padding({ left: 12, right: 12 })
      .border({ width: { bottom: this.pinnedOnly === pinned ? 2 : 0 }, color: this.palette().inkPrimary })
      .accessibilityText(label).onClick(() => { this.pinnedOnly = pinned; this.shelfVisibleCount = 12; })
  }
  @Builder
  compactFilters() {
    Column({ space: 10 }) {
      MemoCalendar({ notes: this.recentNotes, selectedDate: this.selectedDate, onSelectDate: this.onSelectDate })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(MemoFeedPolicy.tags(this.recentNotes).slice(0, 40), (item: MemoTagCount) => {
          Button('#' + item.tag + ' ' + item.count, { type: ButtonType.Normal }).height(44).fontSize(12)
            .fontColor(this.palette().inkSecondary).backgroundColor(this.palette().surfaceSubtle).borderRadius(6)
            .margin({ right: 6, bottom: 6 }).onClick(() => this.onOpenTag(item.tag))
        }, (item: MemoTagCount) => item.tag + ':' + item.count)
      }.width('100%')
    }.width('100%').padding(8).borderRadius(8).backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })
  }
  @Builder
  continueReading(note: NoteItem) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        AppIcon({ source: $r('app.media.ic_note'), iconSize: 18, tint: this.palette().inkSecondary })
        Column({ space: 3 }) {
          Text('继续阅读').fontSize(12).fontColor(this.palette().inkMuted)
          Text(note.title).fontSize(13).fontColor(this.palette().inkPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        AppIcon({ source: $r('app.media.ic_chevron_right'), iconSize: 15, tint: this.palette().inkMuted })
      }.width('100%')
    }.width('100%').padding(12).constraintSize({ minHeight: 64 }).borderRadius(5)
      .border({ width: 1, color: this.palette().borderSubtle })
      .backgroundColor(Color.Transparent).accessibilityText('继续打开 ' + note.title)
      .onClick(() => this.onSelectNote(note))
  }
  build() {
    Scroll() {
      Column({ space: 20 }) {
        Column({ space: 14 }) {
          AppIcon({ source: $r('app.media.ic_page'), iconSize: 42, tint: this.palette().inkPrimary })
          Text('主页').fontSize(TypographyTokens.TITLE_HERO).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
          Text('记录想法，整理知识。').fontSize(14).fontColor(this.palette().inkMuted)
        }.width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: 4 })
        GridRow({ columns: this.singleColumn ? 2 : (AI_FEATURES_VISIBLE ? 4 : 3), gutter: 8 }) {
          GridCol() { this.quickAction($r('app.media.ic_new_note'), '新建笔记', () => this.onCreateNote()) }
          GridCol() { this.quickAction($r('app.media.ic_pen'), '手写笔记', () => this.onCreateHandwriting()) }
          GridCol() { this.quickAction($r('app.media.ic_import'), '导入资料', () => this.onImportDocument()) }
          if (AI_FEATURES_VISIBLE) {
            GridCol() { this.quickAction($r('app.media.ic_text_page'), '文字整理', () => this.onSmartExtract()) }
          }
        }.width('100%')
        QuickMemoComposer({ text: this.memoDraft, status: this.memoStatus, saving: this.memoSaving, ready: this.memoReady,
          onChange: this.onMemoChange, onSave: () => { this.pinnedOnly = false; this.onSaveMemo(); }, onRetryDraft: this.onRetryMemoDraft })
        Row() {
          this.feedTab('全部记录', false)
          this.feedTab('置顶', true)
          Blank()
            Button('筛选', { type: ButtonType.Normal }).height(44).fontSize(13).padding({ left: 12, right: 12 })
              .fontColor(this.palette().inkSecondary).backgroundColor(this.filtersOpen ? this.palette().activeBg : Color.Transparent)
              .borderRadius(5).accessibilityText('按日期与标签筛选').onClick(() => {
                animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => { this.filtersOpen = !this.filtersOpen; });
              })
          Button({ type: ButtonType.Normal }) {
            AppIcon({ source: $r('app.media.ic_search'), iconSize: 18, tint: this.palette().inkSecondary })
          }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
            .accessibilityText('搜索笔记、正文或标签').onClick(() => this.onSearchNotes())
        }.width('100%').border({ width: { bottom: 1 }, color: this.palette().borderSubtle })
        if (this.latestNote() !== null) { this.continueReading(this.latestNote()!) }
        if (this.filtersOpen) { this.compactFilters() }
        if (this.selectedDate || this.selectedTag || this.pinnedOnly) {
          Row({ space: 6 }) {
            Text((this.selectedDate || '所有日期') + (this.selectedTag ? ' · #' + this.selectedTag : '') + (this.pinnedOnly ? ' · 置顶' : ''))
              .fontSize(12).fontColor(this.palette().inkSecondary).layoutWeight(1).maxLines(2)
            Button('清除筛选', { type: ButtonType.Normal }).height(44).fontSize(12).fontColor(this.palette().inkPrimary)
              .backgroundColor(Color.Transparent).onClick(() => { this.pinnedOnly = false; this.onClearFilters(); })
          }.width('100%')
        }
        if (this.displayNotes().length === 0) {
          Column({ space: 8 }) {
            Text(this.selectedDate || this.selectedTag || this.pinnedOnly ? '没有匹配的记录' : '写下你的第一条记录')
              .fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
            Text('一句想法、一段摘录，都可以从上面的输入框开始。').fontSize(13).fontColor(this.palette().inkMuted)
              .textAlign(TextAlign.Center).lineHeight(22)
            Button('打开资料库', { type: ButtonType.Normal }).height(44).fontSize(13).fontColor(this.palette().inkSecondary)
              .backgroundColor(this.palette().surfaceSubtle).borderRadius(6).onClick(() => this.onNavigate(NAV_LIBRARY))
          }.width('100%').padding({ top: 40, bottom: 40 })
        } else {
          Column({ space: 0 }) {
            ForEach(this.displayNotes().slice(0, this.shelfVisibleCount), (note: NoteItem, index: number) => {
              if (this.showDayHeader(index)) {
                Row({ space: 10 }) {
                  Text(this.dayLabel(note)).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette().inkMuted)
                  Divider().layoutWeight(1).color(this.palette().borderSubtle)
                }.width('100%').padding({ top: index === 0 ? 2 : 10, bottom: 2 })
              }
              MemoTimelineCard({ note, onOpen: this.onSelectNote, onTag: this.onOpenTag,
                onTogglePin: this.onTogglePin, onToggleFavorite: this.onToggleFavorite, onDelete: this.onDeleteNote })
            }, (note: NoteItem) => readingRenderKey(note))
          }.width('100%')
          if (this.displayNotes().length > this.shelfVisibleCount) {
            Button('显示更多记录 · 已显示 ' + this.shelfVisibleCount + ' / ' + this.displayNotes().length, { type: ButtonType.Normal })
              .height(44).width('100%').fontSize(12).fontColor(this.palette().inkSecondary)
              .backgroundColor(this.palette().surfaceSubtle).borderRadius(6).onClick(() => { this.shelfVisibleCount += 12; })
          }
        }
      }.width('100%').constraintSize({ maxWidth: 840 }).padding({ left: this.singleColumn ? 16 : 40, right: this.singleColumn ? 16 : 40, top: this.singleColumn ? 28 : 64, bottom: 64 })
        .alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor(this.palette().canvas).id('home-workspace')
  }
}
