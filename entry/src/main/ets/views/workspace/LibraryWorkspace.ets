/**
 * 资料库视图
 *
 * Notion 风格的纯净列表：搜索 + 类型筛选 + 笔记卡片。
 * 数据由 Index 过滤后注入，本组件只负责呈现与交互回调。
 */
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { FILTER_ALL, NOTE_FILTERS } from '../../common/constants/WorkspaceConstants';
import { noteRenderKey } from '../../common/utils/ForEachKeys';

@Component
export struct LibraryWorkspace {
  @Prop notes: NoteItem[] = [];
  @Prop totalCount: number = 0;
  @Prop searchText: string = '';
  @Prop activeFilter: string = FILTER_ALL;
  @Prop activeNoteId: string = '';

  onSearchChange: (value: string) => void = () => {};
  onFilterChange: (filter: string) => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};
  onCreateNote: () => void = () => {};
  onImportDocument: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  /** 功能11：排序键与升降序，驱动 displayNotes() 的真实排序 */
  @State sortKey: string = 'update'; // 'update' | 'create' | 'title'
  @State sortAsc: boolean = false;
  /** 功能6：选中的标签，多选 OR 过滤，驱动 displayNotes() */
  @State selectedTags: string[] = [];

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private setSort(key: string): void {
    this.sortKey = key;
  }

  /** 从当前笔记里收集去重标签，作为筛选 chip 的数据源 */
  private availableTags(): string[] {
    const seen: Set<string> = new Set();
    const out: string[] = [];
    for (let i = 0; i < this.notes.length; i++) {
      const list: string[] = this.noteTags(this.notes[i]);
      for (let j = 0; j < list.length; j++) {
        if (!seen.has(list[j])) {
          seen.add(list[j]);
          out.push(list[j]);
        }
      }
    }
    return out;
  }

  /** 一篇笔记的标签列表：优先 tags[]，回退到单值 tag。 */
  private noteTags(note: NoteItem): string[] {
    if (note.tags !== undefined && note.tags.length > 0) {
      return note.tags;
    }
    return note.tag.length > 0 ? [note.tag] : [];
  }

  /** OR 匹配：只要命中任一选中标签即保留。 */
  private noteHasAnyTag(note: NoteItem, selected: string[]): boolean {
    const list: string[] = this.noteTags(note);
    for (let i = 0; i < list.length; i++) {
      for (let j = 0; j < selected.length; j++) {
        if (list[i] === selected[j]) {
          return true;
        }
      }
    }
    return false;
  }

  /** 标签过滤（OR）+ 排序后的实际展示列表。 */
  private displayNotes(): NoteItem[] {
    let list: NoteItem[] = this.notes.slice();
    if (this.selectedTags.length > 0) {
      const filtered: NoteItem[] = [];
      for (let i = 0; i < list.length; i++) {
        if (this.noteHasAnyTag(list[i], this.selectedTags)) {
          filtered.push(list[i]);
        }
      }
      list = filtered;
    }
    const asc: boolean = this.sortAsc;
    list.sort((a: NoteItem, b: NoteItem): number => {
      let cmp: number = 0;
      if (this.sortKey === 'title') {
        cmp = a.title.localeCompare(b.title);
      } else if (this.sortKey === 'create') {
        cmp = (a.createdAt ?? 0) - (b.createdAt ?? 0);
      } else {
        cmp = (a.updatedAt ?? 0) - (b.updatedAt ?? 0);
      }
      return asc ? cmp : -cmp;
    });
    return list;
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
  }

  @Builder
  filterChip(label: string) {
    Text(label)
      .fontSize(TypographyTokens.CAPTION)
      .fontColor(label === this.activeFilter ? this.palette().inkPrimary : this.palette().inkSecondary)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(6)
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
      .borderRadius(6)
      .backgroundColor(key === this.sortKey ? this.palette().activeBg : Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.setSort(key))
  }

  /** 功能6：标签筛选 chip（可多选高亮） */
  @Builder
  tagChip(tag: string) {
    Text(tag)
      .fontSize(TypographyTokens.TINY)
      .fontColor(this.isTagSelected(tag) ? Color.White : this.palette().inkSecondary)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(this.isTagSelected(tag) ? this.palette().accent : this.palette().surfaceSubtle)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.toggleTag(tag))
  }

  @Builder
  noteCard(note: NoteItem) {
    Row({ space: 12 }) {
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
              ForEach(this.noteTags(note), (t: string) => {
                Text(t)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(note.tagColor.length === 0 ? this.palette().inkSecondary : note.tagColor)
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
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 10 }) {
          Text(note.type)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
          Text(note.category)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
          Text(note.updateTime)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(8)
    .backgroundColor(note.id === this.activeNoteId ? this.palette().activeBg : Color.Transparent)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onSelectNote(note))
  }

  build() {
    Column() {
      Column() {
        // ---- 标题与操作 ----
        Row({ space: 8 }) {
          Text('资料库')
            .fontSize(TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Text(`${this.totalCount} 篇`)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
          Blank()
          Text('⇪ 导入')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(6)
            .backgroundColor(this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onImportDocument())
          Text('＋ 新建')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(6)
            .backgroundColor(this.palette().accent)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onCreateNote())
        }
        .width('100%')
        .margin({ bottom: 12 })

        // ---- 搜索 ----
        TextInput({ text: this.searchText, placeholder: '搜索标题、正文与 #标签' })
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .placeholderFont({ size: TypographyTokens.BODY_REGULAR })
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(6)
          .height(34)
          .width('100%')
          .onChange((value: string) => this.onSearchChange(value))

        // ---- 类型筛选 ----
        Row({ space: 2 }) {
          ForEach(NOTE_FILTERS, (filter: string) => {
            this.filterChip(filter)
          }, (filter: string) => filter)
        }
        .width('100%')
        .margin({ top: 10, bottom: 6 })

        // ---- 功能11：排序 ----
        Row({ space: 4 }) {
          Text('排序')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .margin({ right: 4 })
          this.sortChip('update', '更新时间')
          this.sortChip('create', '创建时间')
          this.sortChip('title', '标题')
          Blank()
          Text(this.sortAsc ? '↑ 升序' : '↓ 降序')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(6)
            .backgroundColor(this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.sortAsc = !this.sortAsc;
            })
        }
        .width('100%')
        .margin({ top: 2, bottom: 6 })

        // ---- 功能6：标签筛选（可多选高亮） ----
        if (this.availableTags().length > 0) {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.availableTags(), (tag: string) => {
                this.tagChip(tag)
              }, (tag: string) => tag)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .margin({ bottom: 6 })
        }

        Divider()
          .strokeWidth(1)
          .color(this.palette().borderSubtle)
      }
      .width('100%')
      .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 24 })

      // ---- 列表 ----
      if (this.displayNotes().length === 0) {
        Column({ space: 8 }) {
          Text('没有匹配的笔记')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
          Text('换个关键词，或新建一篇笔记开始记录。')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.displayNotes(), (note: NoteItem) => {
            ListItem() {
              this.noteCard(note)
            }
          }, (note: NoteItem) => noteRenderKey(note))
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 20 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH + 160 })
    .backgroundColor(this.palette().canvas)
  }
}
