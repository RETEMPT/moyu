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

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
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
          if (note.tag.length > 0) {
            Text(note.tag)
              .fontSize(TypographyTokens.TINY)
              .fontColor(note.tagColor.length === 0 ? this.palette().inkSecondary : note.tagColor)
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(4)
              .backgroundColor(this.palette().surfaceSubtle)
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

        Divider()
          .strokeWidth(1)
          .color(this.palette().borderSubtle)
      }
      .width('100%')
      .padding({ left: 32, right: 32, top: 24 })

      // ---- 列表 ----
      if (this.notes.length === 0) {
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
          ForEach(this.notes, (note: NoteItem) => {
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
