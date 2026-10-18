/**
 * 资料库视图
 *
 * 统一封面书架、资料列表与文字时间流，复用纯查询策略。
 * 持久化显示设置由 Index 装配，临时筛选留在本组件。
 */
import { AnimationTokens, ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { DocumentPreview } from '../common/DocumentPreview';
import { documentLabel } from '../../common/utils/DocumentPresentation';
import { FILTER_ALL, NOTE_FILTERS } from '../../common/constants/WorkspaceConstants';
import { readingRenderKey } from '../../common/utils/ForEachKeys';
import { LibraryPolicy } from '../../services/library/LibraryPolicy';
import { ReadingProgressPolicy, ReadingStatus } from '../../services/document/ReadingProgressPolicy';
import { MemoTimelineCard } from '../common/MemoTimelineCard';
import { IconButton } from '../common/IconButton';

@Component
export struct LibraryWorkspace {
  @Prop @Watch('onQueryChanged') notes: NoteItem[] = [];
  @Prop allNotes: NoteItem[] = [];
  @Prop totalCount: number = 0;
  @Prop searchText: string = '';
  @Prop activeFilter: string = FILTER_ALL;
  @Prop activeNoteId: string = '';
  @Prop viewMode: string = 'shelf';
  @Prop sortKey: string = 'update';
  @Prop sortAsc: boolean = false;
  onViewModeChange: (view: string) => void = () => {};
  onSortChange: (key: string, ascending: boolean) => void = () => {};
  onResetFilters: () => void = () => {};
  onOpenTag: (tag: string) => void = () => {};

  onSearchChange: (value: string) => void = () => {};
  onFilterChange: (filter: string) => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};
  onOpenNoteMenu: (note: NoteItem) => void = () => {};
  onCreateNote: () => void = () => {};
  onImportDocument: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  @State selectedTags: string[] = [];
  @State optionsExpanded: boolean = false;
  @State readingStatus: ReadingStatus = 'all';
  @State visibleCount: number = 40;
  @State shelfColumns: number = 2;
  private cachedSource: NoteItem[] | null = null;
  private cachedQuery: string = '';
  private cachedNotes: NoteItem[] = [];

  private onQueryChanged(): void { this.visibleCount = 40; }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private setSort(key: string): void {
    this.onSortChange(key, key === 'title');
  }

  /** 从当前笔记里收集去重标签，作为筛选 chip 的数据源 */
  private availableTags(): string[] {
    return LibraryPolicy.availableTags(this.allNotes.length > 0 ? this.allNotes : this.notes);
  }

  /** 一篇笔记的标签列表：优先 tags[]，回退到单值 tag。 */
  private noteTags(note: NoteItem): string[] {
    return LibraryPolicy.tags(note);
  }

  /** 标签过滤（OR）+ 排序后的实际展示列表。 */
  private displayNotes(): NoteItem[] {
    const query = JSON.stringify(this.selectedTags) + this.sortKey + this.sortAsc + this.readingStatus + this.viewMode;
    if (this.cachedSource === this.notes && this.cachedQuery === query) { return this.cachedNotes; }
    this.cachedSource = this.notes; this.cachedQuery = query;
    this.cachedNotes = LibraryPolicy.query(this.notes, { tags: this.selectedTags,
      sort: this.viewMode === 'timeline' ? 'create' : this.sortKey, ascending: this.viewMode === 'timeline' ? false : this.sortAsc,
      type: this.viewMode === 'timeline' ? 'Markdown' : undefined, status: this.readingStatus, pinnedFirst: this.viewMode !== 'timeline' });
    return this.cachedNotes;
  }

  private isTagSelected(tag: string): boolean {
    for (let i = 0; i < this.selectedTags.length; i++) {
      if (this.selectedTags[i] === tag) {
        return true;
      }
    }
    return false;
  }

  private toggleTag(tag: string): void {
    const next: string[] = [];
    let removed: boolean = false;
    for (let i = 0; i < this.selectedTags.length; i++) {
      if (this.selectedTags[i] === tag) {
        removed = true;
        continue;
      }
      next.push(this.selectedTags[i]);
    }
    if (!removed) {
      next.push(tag);
    }
    this.selectedTags = next;
    this.visibleCount = 40;
  }

  private resetFilters(): void {
    this.selectedTags = []; this.readingStatus = 'all'; this.visibleCount = 40;
    this.onResetFilters();
  }

  @Builder
  viewChip(view: string, label: string) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(12).borderRadius(5)
      .padding({ left: 12, right: 12 }).fontColor(this.viewMode === view ? this.palette().inkPrimary : this.palette().inkSecondary)
      .backgroundColor(Color.Transparent)
      .border({ width: { bottom: this.viewMode === view ? 2 : 0 }, color: this.palette().inkPrimary })
      .accessibilityText('显示方式：' + label).onClick(() => {
        if (view === 'timeline') { this.readingStatus = 'all'; }
        this.visibleCount = 40; this.onViewModeChange(view);
      })
  }

  @Builder
  statusChip(key: ReadingStatus, label: string) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(12).borderRadius(5)
      .padding({ left: 10, right: 10 })
      .fontColor(this.readingStatus === key ? this.palette().inkPrimary : this.palette().inkSecondary)
      .backgroundColor(this.readingStatus === key ? this.palette().activeBg : Color.Transparent)
      .accessibilityText('阅读状态：' + label)
      .onClick(() => { this.readingStatus = key; this.visibleCount = 40; })
  }

  @Builder
  noteActions(note: NoteItem) {
    IconButton({ icon: $r('app.media.ic_more'), label: '资料操作 ' + note.title, compact: true,
      onAction: () => this.onOpenNoteMenu(note) })
  }

  @Builder
  shelfCard(note: NoteItem) {
    Column({ space: 8 }) {
      DocumentPreview({ note }).width('100%').height(210)
        .accessibilityText(`打开资料 ${note.title}，${ReadingProgressPolicy.label(note)}`).onClick(() => this.onSelectNote(note))
      Row({ space: 4 }) {
        Text(note.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).onClick(() => this.onSelectNote(note))
        this.noteActions(note)
      }.width('100%').alignItems(VerticalAlign.Bottom)
    }.width('100%').padding(10).borderRadius(5)
      .backgroundColor(note.id === this.activeNoteId ? this.palette().activeBg : this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })

  }

  @Builder
  filterChip(label: string) {
    Text(label)
      .fontSize(TypographyTokens.CAPTION)
      .fontColor(label === this.activeFilter ? this.palette().inkPrimary : this.palette().inkSecondary)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .height(44).constraintSize({ minWidth: 54 }).textAlign(TextAlign.Center)
      .borderRadius(5)
      .backgroundColor(label === this.activeFilter ? this.palette().activeBg : Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.onFilterChange(label))
  }

  /** 功能11：排序段选按钮 */
  @Builder
  sortChip(key: string, label: string) {
    Text(label)
      .fontSize(TypographyTokens.CAPTION)
      .fontColor(key === this.sortKey ? this.palette().inkPrimary : this.palette().inkSecondary)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .height(44).textAlign(TextAlign.Center).borderRadius(5)
      .backgroundColor(key === this.sortKey ? this.palette().activeBg : Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.setSort(key))
  }

  /** 功能6：标签筛选 chip（可多选高亮） */
  @Builder
  tagChip(tag: string) {
    Text(tag)
      .fontSize(TypographyTokens.TINY)
      .fontColor(this.isTagSelected(tag) ? this.palette().onAccent : this.palette().inkSecondary)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .height(44).textAlign(TextAlign.Center)
      .borderRadius(5)
      .backgroundColor(this.isTagSelected(tag) ? this.palette().accent : this.palette().surfaceSubtle)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.toggleTag(tag))
  }

  @Builder
  noteCard(note: NoteItem) {
    Row({ space: 12 }) {
      DocumentPreview({ note, compact: true }).width(56).height(72).onClick(() => this.onSelectNote(note))
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(note.title)
            .fontSize(TypographyTokens.BODY_LARGE)
            .fontColor(this.palette().inkPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.noteTags(note).length > 0) {
            Row({ space: 4 }) {
              ForEach(this.noteTags(note).slice(0, this.isPhone ? 1 : 3), (t: string) => {
                Text(t)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor((note.tagColor || '').length === 0 ? this.palette().inkSecondary : note.tagColor)
                  .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                  .borderRadius(4)
                  .backgroundColor(this.palette().surfaceSubtle)
              }, (t: string) => t)
            }
          }
        }
        .width('100%')

        Text(note.previewText)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 10 }) {
          Text(documentLabel(note.type))
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
          if (note.pageCount !== undefined && note.pageCount > 0) {
            Text(`${note.pageCount} 页`)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          Text(note.category).layoutWeight(1)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(note.updateTime)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
          Text(ReadingProgressPolicy.label(note))
            .fontSize(TypographyTokens.TINY).fontColor(this.palette().accent)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start).accessibilityText(`打开资料 ${note.title}`).onClick(() => this.onSelectNote(note))
      this.noteActions(note)
    }
    .alignItems(VerticalAlign.Bottom)
    .width('100%')
    .padding(12)
    .borderRadius(5)
    .backgroundColor(note.id === this.activeNoteId ? this.palette().activeBg : this.palette().surface)
    .border({ width: 1, color: this.palette().borderSubtle })
    .hoverEffect(HoverEffect.Highlight)
  }

  build() {
    Column() {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('资料库').fontSize(this.isPhone ? 28 : TypographyTokens.TITLE_HERO).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
          Button('导入资料', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(6)
            .padding({ left: 12, right: 12 }).fontColor(this.palette().inkSecondary).backgroundColor(this.palette().surface)
            .border({ width: 1, color: this.palette().borderSubtle }).accessibilityText('导入资料').onClick(() => this.onImportDocument())
          Button('新建', { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(6)
            .padding({ left: 14, right: 14 }).fontColor(this.palette().surface).backgroundColor(this.palette().inkPrimary)
            .onClick(() => this.onCreateNote())
        }.width('100%')
        TextInput({ text: this.searchText, placeholder: '搜索标题、正文与 #标签' })
          .fontSize(14).fontColor(this.palette().inkPrimary).placeholderColor(this.palette().inkMuted)
          .backgroundColor(this.palette().surface).border({ width: 1, color: this.palette().borderSubtle })
          .borderRadius(6).height(48).accessibilityText('搜索资料标题、正文与标签').width('100%')
          .onChange((value: string) => this.onSearchChange(value))
        Row({ space: 0 }) {
          this.viewChip('shelf', '书架')
          this.viewChip('list', '列表')
          this.viewChip('timeline', '时间流')
          Blank()
          Button(this.selectedTags.length > 0 || this.readingStatus !== 'all' ? '筛选 · 已启用' : '筛选', { type: ButtonType.Normal }).height(44).fontSize(12).padding({ left: 12, right: 12 })
            .fontColor(this.palette().inkSecondary).backgroundColor(this.optionsExpanded ? this.palette().activeBg : Color.Transparent)
            .borderRadius(5).accessibilityText('资料筛选与排序').onClick(() => {
              animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => { this.optionsExpanded = !this.optionsExpanded; });
            })
        }.width('100%').border({ width: { bottom: 1 }, color: this.palette().borderSubtle })
        Scroll() {
          Row({ space: 2 }) {
            ForEach(NOTE_FILTERS, (filter: string) => { this.filterChip(filter) }, (filter: string) => filter)
          }
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        if (this.optionsExpanded && this.viewMode !== 'timeline') {
          Scroll() {
            Row({ space: 2 }) {
              this.sortChip('update', '更新时间')
              this.sortChip('create', '创建时间')
              this.sortChip('title', '标题')
              this.sortChip('read', '最近打开')
              Button(this.sortAsc ? '↑ 升序' : '↓ 降序', { type: ButtonType.Normal }).height(44).fontSize(12)
                .padding({ left: 10, right: 10 }).fontColor(this.palette().inkSecondary).backgroundColor(Color.Transparent)
                .accessibilityText('切换排序方向').onClick(() => this.onSortChange(this.sortKey, !this.sortAsc))
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          Scroll() {
            Row({ space: 2 }) {
              this.statusChip('all', '全部状态')
              this.statusChip('unread', '未打开')
              this.statusChip('reading', '阅读中')
              this.statusChip('finished', '已到末页')
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        } else if (this.viewMode === 'timeline') {
          Text('文字记录按创建时间倒序排列').fontSize(12).fontColor(this.palette().inkMuted).width('100%').height(44)
        }
        if (this.optionsExpanded) {
          if (this.availableTags().length > 0) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.availableTags(), (tag: string) => { this.tagChip(tag) }, (tag: string) => tag)
              }
            }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          } else {
            Text('还没有标签，在正文中输入 #标签 即可创建。').fontSize(12).fontColor(this.palette().inkMuted).width('100%').padding(8)
          }
        }
        Row() {
          Text(`${this.displayNotes().length} / ${this.totalCount} 份资料`).fontSize(12).fontColor(this.palette().inkMuted).layoutWeight(1)
          Button('清除筛选', { type: ButtonType.Normal }).height(44).fontSize(12)
            .fontColor(this.palette().inkSecondary).backgroundColor(Color.Transparent).onClick(() => this.resetFilters())
        }.width('100%')
      }.width('100%').padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: this.isPhone ? 24 : 40 })

      // ---- 列表 ----
      if (this.displayNotes().length === 0) {
        Column({ space: 8 }) {
          Text(this.totalCount === 0 ? '资料库还是空的' : '没有匹配的资料')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
          Text(this.totalCount === 0 ? '导入 PDF、图片或文字，开始整理学习资料。' : '试试其他关键词，或清除筛选。')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
          if (this.totalCount > 0) {
            Button('清除筛选').height(44).onClick(() => this.resetFilters())
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.viewMode === 'timeline') {
        List({ space: 12 }) {
          ForEach(this.displayNotes().slice(0, this.visibleCount), (note: NoteItem) => {
            ListItem() {
              MemoTimelineCard({ note, showActions: false, showFooterActions: true, onOpenActions: this.onOpenNoteMenu,
                onOpen: this.onSelectNote, onTag: (tag: string) => {
                this.selectedTags = []; this.readingStatus = 'all'; this.onOpenTag(tag);
              } })
            }
          }, (note: NoteItem) => readingRenderKey(note))
          if (this.visibleCount < this.displayNotes().length) {
            ListItem() { Button('显示更多记录').width('100%').height(44).onClick(() => { this.visibleCount += 40; }) }
          }
        }.layoutWeight(1).width('100%')
          .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 12, bottom: 20 })
      } else if (this.viewMode === 'shelf') {
        Scroll() {
          Column({ space: 12 }) {
            GridRow({ columns: this.shelfColumns, gutter: 12 }) {
              ForEach(this.displayNotes().slice(0, this.visibleCount), (note: NoteItem) => {
                GridCol() { this.shelfCard(note) }
              }, (note: NoteItem) => readingRenderKey(note))
            }.width('100%')
            if (this.visibleCount < this.displayNotes().length) {
              Button('显示更多资料').height(44).onClick(() => { this.visibleCount += 40; })
            }
          }.width('100%').padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 12, bottom: 20 })
        }.layoutWeight(1).width('100%').align(Alignment.Top)
          .onAreaChange((_before: Area, after: Area) => { this.shelfColumns = Number(after.width) >= 900 ? 4 : Number(after.width) >= 600 ? 3 : 2; })
      } else {
        List({ space: 8 }) {
          ForEach(this.displayNotes().slice(0, this.visibleCount), (note: NoteItem) => {
            ListItem() {
              this.noteCard(note)
            }
          }, (note: NoteItem) => readingRenderKey(note))
          if (this.visibleCount < this.displayNotes().length) {
            ListItem() { Button('显示更多资料').width('100%').height(44).onClick(() => { this.visibleCount += 40; }) }
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 12, bottom: 20 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: 1080 })
    .backgroundColor(this.palette().canvas)
  }
}
