/**
 * 资料库视图
 *
 * 统一封面书架、资料列表与文字时间流，复用纯查询策略。
 * Index 保存可恢复的筛选，组件统一计算结果并管理当前列表的选择。
 */
import { AnimationTokens, ColorPalette, LayoutTokens, LibraryColors, TypographyTokens } from '../../common/constants/DesignTokens';
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
import { AppIcon } from '../common/AppIcon';
import { NoteTagBadge } from '../common/NoteTagBadge';

@Component
export struct LibraryWorkspace {
  @Prop @Watch('pruneSelection') notes: NoteItem[] = [];
  @Prop @Watch('onQueryChanged') projectName: string = '';
  @Prop @Watch('onQueryChanged') searchText: string = '';
  @Prop @Watch('onQueryChanged') activeFilter: string = FILTER_ALL;
  @Prop @Watch('onQueryChanged') selectedTags: string[] = [];
  @Prop @Watch('onQueryChanged') readingStatus: ReadingStatus = 'all';
  @Prop @Watch('resetScope') scopeToken: number = 0;
  @Prop activeNoteId: string = '';
  @Prop @Watch('onQueryChanged') viewMode: string = 'shelf';
  @Prop displayBusy: boolean = false;
  @Prop importing: boolean = false;
  @Prop sortKey: string = 'update';
  @Prop sortAsc: boolean = false;
  onViewModeChange: (view: string) => void = () => {};
  onSortChange: (key: string, ascending: boolean) => void = () => {};
  onResetFilters: () => void = () => {};
  onTagsChange: (tags: string[]) => void = () => {};
  onReadingStatusChange: (status: ReadingStatus) => void = () => {};
  onSearchChange: (value: string) => void = () => {};
  onFilterChange: (filter: string) => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};
  onOpenNoteMenu: (note: NoteItem) => void = () => {};
  onCreateNote: () => void = () => {};
  onImportDocument: () => void = () => {};
  onOpenBackup: () => void = () => {};
  onBatchMove: (ids: string[]) => void = () => {};
  onBatchShare: (ids: string[]) => void = () => {};
  onBatchTrash: (ids: string[]) => Promise<void> = async () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  @State optionsExpanded: boolean = false;
  @State visibleCount: number = 40;
  @State shelfColumns: number = 2;
  @State private batchMode: boolean = false;
  @State private batchBusy: boolean = false;
  @State private selectedIds: string[] = [];
  @State private libraryMenuOpen: boolean = false;
  private cachedSource: NoteItem[] | null = null;
  private cachedQuery: string = '';
  private cachedNotes: NoteItem[] = [];
  private tagSource: NoteItem[] | null = null;
  private tagScope: string = '';
  private tagLabels: string[] = [];

  private onQueryChanged(): void { this.visibleCount = 40; this.pruneSelection(); }

  private pruneSelection(): void {
    if (this.selectedIds.length === 0) { return; }
    const available = new Set(this.displayNotes().map((note: NoteItem) => note.id));
    const selected = this.selectedIds.filter((id: string) => available.has(id));
    if (selected.length !== this.selectedIds.length) { this.selectedIds = selected; }
  }

  private selectNote(id: string): void {
    this.selectedIds = this.selectedIds.includes(id) ? this.selectedIds.filter((item: string) => item !== id) : this.selectedIds.concat(id);
  }

  private selectResults(): void {
    const ids = this.displayNotes().map((note: NoteItem) => note.id);
    const selected = new Set(this.selectedIds);
    const all = ids.every((id: string) => selected.has(id));
    ids.forEach((id: string) => { if (all) { selected.delete(id); } else { selected.add(id); } });
    this.selectedIds = Array.from(selected);
  }

  private allResultsSelected(): boolean {
    const results = this.displayNotes();
    const selected = new Set(this.selectedIds);
    return results.length > 0 && results.every((note: NoteItem) => selected.has(note.id));
  }

  private async trashSelected(): Promise<void> {
    if (this.batchBusy || this.selectedIds.length === 0) { return; }
    this.batchBusy = true;
    try { await this.onBatchTrash(this.selectedIds.slice()); }
    finally { this.batchBusy = false; }
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private setSort(key: string): void {
    if (!this.displayBusy && key !== this.sortKey) { this.onSortChange(key, key === 'title'); }
  }

  /** 从当前笔记里收集去重标签，作为筛选 chip 的数据源 */
  private availableTags(): string[] {
    const scope = JSON.stringify([this.projectName, this.activeFilter, this.selectedTags]);
    if (this.tagSource !== this.notes || this.tagScope !== scope) {
      this.tagSource = this.notes;
      this.tagScope = scope;
      const labels = LibraryPolicy.availableTags(this.notes, this.projectName, this.activeFilter);
      const keys = new Set(labels.map((tag: string) => LibraryPolicy.tagKey(tag)));
      this.tagLabels = labels.concat(this.selectedTags.filter((tag: string) => !keys.has(LibraryPolicy.tagKey(tag))));
    }
    return this.tagLabels;
  }

  /** 一篇笔记的标签列表：优先 tags[]，回退到单值 tag。 */
  private noteTags(note: NoteItem): string[] {
    return LibraryPolicy.tags(note);
  }

  /** 标签过滤（OR）+ 排序后的实际展示列表。 */
  private displayNotes(): NoteItem[] {
    const timeline = !this.batchMode && this.viewMode === 'timeline';
    const query = JSON.stringify([this.projectName, this.searchText, this.activeFilter, this.selectedTags,
      this.sortKey, this.sortAsc, this.readingStatus, timeline]);
    if (this.cachedSource === this.notes && this.cachedQuery === query) { return this.cachedNotes; }
    this.cachedSource = this.notes; this.cachedQuery = query;
    this.cachedNotes = LibraryPolicy.query(this.notes, { category: this.projectName, keyword: this.searchText,
      type: this.activeFilter, tags: this.selectedTags,
      sort: timeline ? 'create' : this.sortKey, ascending: timeline ? false : this.sortAsc,
      status: this.readingStatus, pinnedFirst: !timeline });
    return this.cachedNotes;
  }

  private isTagSelected(tag: string): boolean {
    const key = LibraryPolicy.tagKey(tag);
    return this.selectedTags.some((item: string) => LibraryPolicy.tagKey(item) === key);
  }

  private toggleTag(tag: string): void {
    const key = LibraryPolicy.tagKey(tag);
    this.onTagsChange(this.isTagSelected(tag) ?
      this.selectedTags.filter((item: string) => LibraryPolicy.tagKey(item) !== key) : this.selectedTags.concat(tag));
  }

  private resetFilters(): void {
    this.onResetFilters();
  }

  private resetScope(): void {
    this.visibleCount = 40;
    this.optionsExpanded = false;
    this.batchMode = false;
    this.selectedIds = [];
    this.libraryMenuOpen = false;
  }

  private hasFilters(): boolean {
    return this.searchText.trim().length > 0 || this.activeFilter !== FILTER_ALL ||
      this.selectedTags.length > 0 || this.readingStatus !== 'all';
  }

  private focusSearch(): void {
    this.getUIContext().getFocusController().requestFocus('library-search-field');
  }

  private shelfTone(id: string): number {
    let tone = 0;
    for (let index = 0; index < id.length; index++) { tone = (tone + id.charCodeAt(index)) % 3; }
    return tone;
  }

  @Builder
  viewChip(view: string, label: string) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(7)
      .padding({ left: this.isPhone ? 9 : 14, right: this.isPhone ? 9 : 14 })
      .fontColor(this.viewMode === view ? this.palette().inkPrimary : this.palette().inkSecondary)
      .fontWeight(this.viewMode === view ? FontWeight.Medium : FontWeight.Normal)
      .backgroundColor(this.viewMode === view ?
        (this.isDarkMode ? this.palette().activeBg : LibraryColors.search) : Color.Transparent)
      .accessibilityDescription(this.viewMode === view ? '已选中' : '')
      .enabled(!this.displayBusy).accessibilityText('显示方式：' + label)
      .onClick(() => { if (view !== this.viewMode) { this.onViewModeChange(view); } })
  }

  @Builder
  statusChip(key: ReadingStatus, label: string) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(12).borderRadius(5)
      .padding({ left: 10, right: 10 })
      .fontColor(this.readingStatus === key ? this.palette().inkPrimary : this.palette().inkSecondary)
      .backgroundColor(this.readingStatus === key ? this.palette().activeBg : Color.Transparent)
      .accessibilityDescription(this.readingStatus === key ? '已选中' : '未选中')
      .accessibilityText('阅读状态：' + label)
      .onClick(() => this.onReadingStatusChange(key))
  }

  @Builder
  noteActions(note: NoteItem) {
    IconButton({ icon: $r('app.media.ic_more'), label: '资料操作 ' + note.title, compact: true,
      onAction: () => this.onOpenNoteMenu(note) })
  }

  @Builder
  shelfCard(note: NoteItem) {
    Column({ space: 4 }) {
      DocumentPreview({ note, shelfTone: this.shelfTone(note.id), compact: this.isPhone })
        .width('100%').aspectRatio(1.56).borderRadius(7).clip(true)
        .accessibilityText(`打开资料 ${note.title}，${ReadingProgressPolicy.label(note)}`).onClick(() => this.onSelectNote(note))
      Row({ space: 4 }) {
        Column({ space: 3 }) {
          Text(note.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(LibraryPolicy.type(note) + (note.pageCount && note.pageCount > 0 ? ` · ${note.pageCount} 页` : ''))
            .fontSize(12).fontColor(this.palette().inkMuted).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).padding({ left: 3 }).alignItems(HorizontalAlign.Start).onClick(() => this.onSelectNote(note))
        this.noteActions(note)
      }.width('100%').alignItems(VerticalAlign.Center)
    }.width('100%').padding(10).borderRadius(11)
      .backgroundColor(note.id === this.activeNoteId ? this.palette().activeBg : Color.Transparent)
      .border({ width: 1, color: this.palette().border })
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
      .accessibilityDescription(label === this.activeFilter ? '已选中' : '未选中')
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
      .accessibilityDescription(key === this.sortKey ? '已选中' : '未选中')
      .enabled(!this.displayBusy)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.setSort(key))
  }

  /** 功能6：标签筛选 chip（可多选高亮） */
  @Builder
  tagChip(tag: string) {
    Button({ type: ButtonType.Normal }) {
      NoteTagBadge({ tag, selected: this.isTagSelected(tag) })
    }.height(44).padding(0).backgroundColor(Color.Transparent).accessibilityText(`筛选标签 ${tag}`)
      .accessibilityDescription(this.isTagSelected(tag) ? '已选中' : '未选中').onClick(() => this.toggleTag(tag))
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
                NoteTagBadge({ tag: t, compact: true })
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

  @Builder
  manageButton(label: string, handler: () => void, enabled: boolean = true) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(8)
      .padding({ left: 10, right: 10 }).fontColor(this.palette().inkSecondary).backgroundColor(this.palette().surfaceSubtle)
      .enabled(enabled).onClick(handler)
  }

  @Builder
  libraryActions() {
    Menu() {
      MenuItem({ content: '新建笔记' }).onClick(() => { this.libraryMenuOpen = false; this.onCreateNote(); })
      MenuItem({ content: '批量管理' }).enabled(this.displayNotes().length > 0).onClick(() => {
        this.libraryMenuOpen = false; this.batchMode = true; this.visibleCount = 40;
      })
    }
  }

  @Builder
  batchRow(note: NoteItem) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        AppIcon({ source: this.selectedIds.includes(note.id) ? $r('app.media.ic_check') : $r('app.media.ic_checkbox_empty'),
          iconSize: 22, tint: this.selectedIds.includes(note.id) ? this.palette().accent : this.palette().inkMuted })
        Column({ space: 2 }) {
          Text(note.title).fontSize(15).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.palette().inkPrimary).width('100%')
          Text(`${documentLabel(note.type)} · ${note.category || '未分类'}`).fontSize(12).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(this.palette().inkMuted).width('100%')
        }.layoutWeight(1)
      }.width('100%')
    }.width('100%').height(56).padding({ left: 12, right: 12 }).borderRadius(8)
      .backgroundColor(this.selectedIds.includes(note.id) ? this.palette().activeBg : this.palette().surface)
      .accessibilityText('选择资料 ' + note.title).accessibilityDescription(this.selectedIds.includes(note.id) ? '已选择' : '未选择')
      .enabled(!this.batchBusy).onClick(() => this.selectNote(note.id))
  }

  build() {
    Column() {
      Column({ space: 14 }) {
        Row({ space: 6 }) {
          Column({ space: 4 }) {
            Text(this.projectName || '资料库').fontSize(this.isPhone ? 27 : 37)
              .fontFamily('serif').fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            Text(`${this.displayNotes().length} 份资料`).fontSize(12).fontColor(this.palette().inkMuted).width('100%')
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (!this.batchMode) {
            Button({ type: ButtonType.Normal }) {
              AppIcon({ source: $r('app.media.ic_more'), iconSize: 18, tint: this.palette().inkSecondary })
            }.width(44).height(44).padding(0).borderRadius(8).backgroundColor(Color.Transparent)
              .accessibilityText('更多资料库操作').onClick(() => { this.libraryMenuOpen = !this.libraryMenuOpen; })
              .bindMenu(this.libraryMenuOpen, this.libraryActions, { onDisappear: () => { this.libraryMenuOpen = false; } })
            Button(this.importing ? '导入中…' : '导入资料', { type: ButtonType.Normal }).height(44).fontSize(14).borderRadius(8)
              .padding({ left: this.isPhone ? 10 : 20, right: this.isPhone ? 10 : 20 })
              .fontColor(this.palette().onAccent).backgroundColor(this.palette().accent)
              .enabled(!this.importing).accessibilityText('导入资料').onClick(() => this.onImportDocument())
            Button({ type: ButtonType.Normal }) {
              AppIcon({ source: $r('app.media.ic_share'), iconSize: 20, tint: this.palette().inkSecondary })
            }.width(44).height(44).padding(0).borderRadius(8).backgroundColor(Color.Transparent)
              .border({ width: 1, color: this.palette().inkSecondary }).accessibilityText('备份与快传')
              .onClick(() => this.onOpenBackup())
          }
        }.width('100%')
        if (this.batchMode) {
          Row({ space: 6 }) {
            Text(`已选 ${this.selectedIds.length} 份`).fontSize(14).fontColor(this.palette().inkPrimary).layoutWeight(1)
            this.manageButton(this.allResultsSelected() ? '取消全选' : '全选结果',
              () => this.selectResults(), !this.batchBusy && this.displayNotes().length > 0)
            this.manageButton('完成', () => { this.batchMode = false; this.selectedIds = []; this.visibleCount = 40; }, !this.batchBusy)
          }.width('100%')
        }
        Row({ space: 8 }) {
          AppIcon({ source: $r('app.media.ic_search'), iconSize: 18, tint: this.palette().inkSecondary })
          TextInput({ text: this.searchText, placeholder: '搜索资料' })
            .fontSize(14).fontColor(this.palette().inkPrimary).placeholderColor(this.palette().inkMuted)
            .backgroundColor(Color.Transparent).padding({ left: 0, right: 8 }).height(46)
            .id('library-search-field').accessibilityText('搜索资料标题、正文与标签').layoutWeight(1)
            .onChange((value: string) => this.onSearchChange(value))
        }.width('100%').padding({ left: 12 }).borderRadius(9)
          .backgroundColor(this.isDarkMode ? this.palette().surfaceSubtle : LibraryColors.search)
          .keyboardShortcut('f', [ModifierKey.CTRL], () => this.focusSearch())
        Row({ space: 5 }) {
          if (!this.batchMode) {
            Row({ space: 2 }) {
              this.viewChip('shelf', '书架')
              this.viewChip('list', '列表')
              this.viewChip('timeline', '时间流')
            }
          }
          Blank()
          Button({ type: ButtonType.Normal }) {
            Row({ space: 7 }) {
              Path().commands('M2 3 H14 L10 8 V12 L6 14 V8 Z').width(16).height(16)
                .fill(Color.Transparent).stroke(this.palette().inkPrimary).strokeWidth(1.35)
              Text('筛选').fontSize(13).fontColor(this.palette().inkPrimary)
            }
          }.height(44).padding({ left: 12, right: 12 })
            .backgroundColor(this.optionsExpanded || this.hasFilters() ? this.palette().activeBg : Color.Transparent)
            .border({ width: 1, color: this.palette().inkSecondary }).borderRadius(8)
            .accessibilityText('资料筛选与排序').accessibilityDescription(this.hasFilters() ? '已启用筛选' : '')
            .onClick(() => {
              animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => { this.optionsExpanded = !this.optionsExpanded; });
            })
        }.width('100%').padding({ bottom: 11 }).border({ width: { bottom: 1 }, color: this.palette().border })
        if (this.optionsExpanded) {
          Scroll() {
            Row({ space: 2 }) {
              ForEach(NOTE_FILTERS, (filter: string) => { this.filterChip(filter) }, (filter: string) => filter)
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }
        if (this.optionsExpanded && (this.batchMode || this.viewMode !== 'timeline')) {
          Scroll() {
            Row({ space: 2 }) {
              this.sortChip('update', '更新时间')
              this.sortChip('create', '创建时间')
              this.sortChip('title', '标题')
              this.sortChip('read', '最近打开')
              Button(this.sortAsc ? '↑ 升序' : '↓ 降序', { type: ButtonType.Normal }).height(44).fontSize(12)
                .padding({ left: 10, right: 10 }).fontColor(this.palette().inkSecondary).backgroundColor(Color.Transparent)
                .enabled(!this.displayBusy).accessibilityText('切换排序方向').onClick(() => this.onSortChange(this.sortKey, !this.sortAsc))
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        } else if (this.optionsExpanded) {
          Text('资料按创建时间倒序排列').fontSize(12).fontColor(this.palette().inkMuted).width('100%').height(44)
        }
        if (this.optionsExpanded) {
          Scroll() {
            Row({ space: 2 }) {
              this.statusChip('all', '全部状态')
              this.statusChip('unread', '未打开')
              this.statusChip('reading', '阅读中')
              this.statusChip('finished', '已到末页')
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
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
        if (this.hasFilters()) {
          Row() {
            Button('清除筛选', { type: ButtonType.Normal }).height(44).fontSize(12)
              .fontColor(this.palette().inkSecondary).backgroundColor(Color.Transparent).onClick(() => this.resetFilters())
          }.width('100%').justifyContent(FlexAlign.End)
        }
      }.width('100%').padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: this.isPhone ? 14 : 24 })

      // ---- 列表 ----
      if (this.displayNotes().length === 0) {
        Column({ space: 8 }) {
          Text(this.hasFilters() ? '没有匹配的资料' : this.projectName ? '这个项目还没有资料' : '资料库还是空的')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
          Text(this.hasFilters() ? '试试其他关键词，或清除筛选。' : '导入 PDF、图片、文字或 Office 文字版。')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.batchMode) {
        List({ space: 8 }) {
          ForEach(this.displayNotes().slice(0, this.visibleCount), (note: NoteItem) => {
            ListItem() { this.batchRow(note) }
          }, (note: NoteItem) => readingRenderKey(note))
          if (this.visibleCount < this.displayNotes().length) {
            ListItem() { Button('显示更多资料').width('100%').height(44).onClick(() => { this.visibleCount += 40; }) }
          }
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
          .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 8, bottom: 8 })
      } else if (this.viewMode === 'timeline') {
        List({ space: 12 }) {
          ForEach(this.displayNotes().slice(0, this.visibleCount), (note: NoteItem) => {
            ListItem() {
              MemoTimelineCard({ note, showActions: false, showFooterActions: true, onOpenActions: this.onOpenNoteMenu,
                onOpen: this.onSelectNote, onTag: (tag: string) => this.onTagsChange([tag]) })
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
            GridRow({ columns: this.shelfColumns, gutter: 18 }) {
              ForEach(this.displayNotes().slice(0, this.visibleCount), (note: NoteItem) => {
                GridCol() { this.shelfCard(note) }
              }, (note: NoteItem) => readingRenderKey(note))
            }.width('100%')
            if (this.visibleCount < this.displayNotes().length) {
              Button('显示更多资料').height(44).onClick(() => { this.visibleCount += 40; })
            }
          }.width('100%').padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 20, bottom: 20 })
        }.layoutWeight(1).width('100%').align(Alignment.Top)
          .onAreaChange((_before: Area, after: Area) => {
            const contentWidth = Number(after.width) - 2 * LayoutTokens.gutter(this.isPhone);
            this.shelfColumns = contentWidth >= 970 ? 4 : contentWidth >= 600 ? 3 : contentWidth >= 280 ? 2 : 1;
          })
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
      if (this.batchMode && this.selectedIds.length > 0) {
        Row({ space: 6 }) {
          this.manageButton('移动分类', () => this.onBatchMove(this.selectedIds.slice()), !this.batchBusy)
          this.manageButton('备份与快传', () => this.onBatchShare(this.selectedIds.slice()), !this.batchBusy)
          this.manageButton('移入回收站', () => { this.trashSelected(); }, !this.batchBusy)
        }.width('100%').padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), bottom: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: 1080 })
    .backgroundColor(this.isDarkMode ? this.palette().canvas : LibraryColors.paper)
  }
}
