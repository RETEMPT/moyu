/**
 * 回收站视图
 *
 * 展示软删除的笔记：每篇可「恢复」回资料库或「彻底删除」（不可恢复）。
 * 顶部提供「清空回收站」。列表标注删除时间与剩余保留天数，
 * 超过保留期的笔记由 Index 在启动时自动彻底删除，此处只做呈现。
 */
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { TimeFormat } from '../../common/utils/TimeFormat';

const DAY_MS: number = 24 * 60 * 60 * 1000;

@Component
export struct TrashWorkspace {
  @Prop trash: NoteItem[] = [];
  @Prop retentionDays: number = 30;

  onRestore: (note: NoteItem) => void = () => {};
  onPurge: (note: NoteItem) => void = () => {};
  onEmpty: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  /** 删除时间文案，deletedAt 缺失时回退为「未知」 */
  private deletedText(note: NoteItem): string {
    const deletedAt: number | undefined = note.deletedAt;
    if (deletedAt === undefined || deletedAt <= 0) {
      return '删除时间未知';
    }
    return `删除于 ${TimeFormat.format(new Date(deletedAt))}`;
  }

  /** 距离自动彻底删除的剩余天数（向下不小于 0） */
  private remainingDays(note: NoteItem): number {
    const deletedAt: number = note.deletedAt === undefined ? Date.now() : note.deletedAt;
    const remainMs: number = this.retentionDays * DAY_MS - (Date.now() - deletedAt);
    const days: number = Math.ceil(remainMs / DAY_MS);
    return days < 0 ? 0 : days;
  }

  @Builder
  actionButton(label: string, color: string, filled: boolean, action: () => void) {
    Text(label)
      .fontSize(TypographyTokens.CAPTION)
      .fontColor(filled ? Color.White : color)
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .borderRadius(6)
      .backgroundColor(filled ? color : Color.Transparent)
      .border({ width: filled ? 0 : 1, color: { top: color, bottom: color, left: color, right: color } })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(action)
  }

  @Builder
  trashCard(note: NoteItem) {
    Row({ space: 12 }) {
      Text('▤')
        .fontSize(TypographyTokens.TITLE_SUB)
        .fontColor(this.palette().inkMuted)

      Column({ space: 4 }) {
        Text(note.title.length === 0 ? '未命名笔记' : note.title)
          .fontSize(TypographyTokens.BODY_LARGE)
          .fontColor(this.palette().inkPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(note.previewText)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row({ space: 10 }) {
          Text(this.deletedText(note))
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
          Text(`剩余 ${this.remainingDays(note)} 天`)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.remainingDays(note) <= 3 ? this.palette().danger : this.palette().inkMuted)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 8 }) {
        this.actionButton('恢复', this.palette().accent, false, () => this.onRestore(note))
        this.actionButton('彻底删除', this.palette().danger, false, () => this.onPurge(note))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.palette().surfaceSubtle)
  }

  build() {
    Column() {
      Column() {
        // ---- 标题与操作 ----
        Row({ space: 8 }) {
          Text('回收站')
            .fontSize(TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Text(`${this.trash.length} 篇`)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
          Blank()
          if (this.trash.length > 0) {
            Text('清空回收站')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().danger)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(6)
              .border({ width: 1, color: { top: this.palette().danger, bottom: this.palette().danger, left: this.palette().danger, right: this.palette().danger } })
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onEmpty())
          }
        }
        .width('100%')
        .margin({ bottom: 8 })

        Text(`回收站中的笔记保留 ${this.retentionDays} 天，超期将自动彻底删除；可随时恢复到资料库。`)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
          .width('100%')
          .margin({ bottom: 12 })

        Divider()
          .strokeWidth(1)
          .color(this.palette().borderSubtle)
      }
      .width('100%')
      .padding({ left: 32, right: 32, top: 24 })

      // ---- 列表 ----
      if (this.trash.length === 0) {
        Column({ space: 8 }) {
          Text('回收站是空的')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
          Text('在侧边栏资料的「···」菜单里点删除，即可将其移入回收站。')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 32, right: 32 })
      } else {
        List({ space: 6 }) {
          ForEach(this.trash, (note: NoteItem) => {
            ListItem() {
              this.trashCard(note)
            }
          }, (note: NoteItem) => `${note.id}-${note.deletedAt === undefined ? 0 : note.deletedAt}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 20, right: 20, top: 10, bottom: 20 })
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH + 160 })
    .backgroundColor(this.palette().canvas)
  }
}
