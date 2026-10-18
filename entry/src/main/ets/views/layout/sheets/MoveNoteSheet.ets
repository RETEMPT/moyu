/**
 * 移动资料到其他项目（分类）。
 *
 * 上半部：现有分类列表，当前所属分类高亮；点选即移动。
 * 下半部：输入新分类名并「移动并新建」，用于归入尚不存在的项目。
 * 分类即项目：移动只改笔记的 category 元数据，侧边栏项目树由 buildSpaces 实时派生。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { SheetOverlay } from './SheetScaffold';

@Component
export struct MoveNoteSheet {
  @Prop note: NoteItem;
  @Prop @Watch('requestClose') closeToken: number = 0;
  @Prop categories: string[] = [];

  onClose: () => void = () => {};
  onMoveNote: (note: NoteItem, category: string) => Promise<boolean> = async () => false;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';

  @State private draft: string = '';
  @State private saving: boolean = false;
  @State private error: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private currentCategory(): string {
    return this.note.category.length === 0 ? '未分类' : this.note.category;
  }

  private requestClose(): void { if (!this.saving) { this.onClose(); } }

  private async move_to(category: string): Promise<void> {
    if (this.saving) { return; }
    const trimmed = category.trim();
    if (!trimmed) { this.error = '请输入项目名称'; return; }
    if (trimmed === this.currentCategory()) { this.onClose(); return; }
    this.saving = true; this.error = '';
    try {
      if (await this.onMoveNote(this.note, trimmed)) { this.onClose(); }
      else { this.error = '未能移动资料，请重试'; }
    } catch { this.error = '未能移动资料，请重试'; }
    finally { this.saving = false; }
  }

  @Builder
  categoryRow(category: string) {
    Row({ space: 8 }) {
      Text(category === this.currentCategory() ? '◉' : '○')
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(category === this.currentCategory() ? this.palette().accent : this.palette().inkMuted)
      Text(category)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkPrimary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (category === this.currentCategory()) {
        Text('当前')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 10, right: 10 })
    .borderRadius(6)
    .backgroundColor(category === this.currentCategory() ? this.palette().activeBg : this.palette().surfaceSubtle)
    .hoverEffect(HoverEffect.Highlight)
    .enabled(!this.saving).accessibilityText('归类到 ' + category).onClick(() => this.move_to(category))
  }

  build() {
    SheetOverlay({ onDismiss: () => this.requestClose() }) {
      Column({ space: 8 }) {
        Text(`移动「${this.note.title}」到项目`)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.categories.length === 0) {
          Text('还没有可选项目，可在下方输入新名称。')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .width('100%')
            .padding({ top: 4, bottom: 4 })
        } else {
          List({ space: 4 }) {
            ForEach(this.categories, (category: string) => {
              ListItem() {
                this.categoryRow(category)
              }
            }, (category: string) => category)
          }
          .width('100%')
          .constraintSize({ maxHeight: 200 })
          .scrollBar(BarState.Auto)
        }

        Row({ space: 6 }) {
          TextInput({ text: this.draft, placeholder: '新项目名称' })
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkPrimary)
            .placeholderColor(this.palette().inkMuted)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(6)
            .height(44)
            .layoutWeight(1).enabled(!this.saving).accessibilityText('资料新项目名称')
            .onChange((value: string) => {
              this.draft = value;
            })
          Button(this.saving ? '保存中…' : '移动并新建')
            .height(44)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().onAccent)
            .backgroundColor(this.palette().accent)
            .borderRadius(6)
            .enabled(!this.saving).onClick(() => this.move_to(this.draft))
        }
        .width('100%')

        if (this.error) { Text(this.error).fontSize(12).fontColor(this.palette().danger).width('100%') }

        Button('取消')
          .width('100%')
          .height(44)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkSecondary)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(6)
          .margin({ top: 2 })
          .enabled(!this.saving).onClick(() => this.requestClose())
      }
      .width('100%')
    }
  }
}
