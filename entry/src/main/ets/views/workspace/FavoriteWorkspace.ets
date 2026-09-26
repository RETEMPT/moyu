/**
 * 收藏视图（功能7）
 *
 * 侧边栏「⭐ 收藏」的落点：集中展示 note.favorite === true 的笔记。
 * 收藏态由阅读器顶栏的 ☆/★ 切换并经 Index.toggleFavorite 落盘，此处只读展示。
 */
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { noteRenderKey } from '../../common/utils/ForEachKeys';

@Component
export struct FavoriteWorkspace {
  @Prop favorites: NoteItem[] = [];

  onSelectNote: (note: NoteItem) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  @Builder
  favCard(note: NoteItem) {
    Row({ space: 10 }) {
      Text('⭐')
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().warning)
      Column({ space: 3 }) {
        Text(note.title.length === 0 ? '未命名笔记' : note.title)
          .fontSize(TypographyTokens.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(note.category.length === 0 ? '未分类' : note.category)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(8)
    .backgroundColor(this.palette().surfaceSubtle)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onSelectNote(note))
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Text('收藏')
          .fontSize(TypographyTokens.TITLE_HERO)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
        Text(`${this.favorites.length} 篇`)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')
      .margin({ bottom: 14 })

      if (this.favorites.length === 0) {
        Column({ space: 8 }) {
          Text('⭐')
            .fontSize(40)
            .fontColor(this.palette().inkMuted)
          Text('还没有收藏的笔记')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
          Text('打开一篇笔记，点顶部工具条的「☆ 收藏」即可收藏到这里。')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 6 }) {
          ForEach(this.favorites, (note: NoteItem) => {
            ListItem() {
              this.favCard(note)
            }
          }, (note: NoteItem) => noteRenderKey(note))
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH + 160 })
    .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 24, bottom: 20 })
    .backgroundColor(this.palette().canvas)
  }
}
