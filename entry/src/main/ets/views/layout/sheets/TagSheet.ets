/**
 * 标签编辑面板（功能6）
 *
 * 沿用 SheetScaffold 外壳，与重命名/移动保持一致的底部弹层体感。
 * 可增删标签 chip、点选建议标签；「完成」通过 onApplyTags 把最终标签写回笔记。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { SheetOverlay } from './SheetScaffold';

@Component
export struct TagSheet {
  @Prop note: NoteItem;

  onClose: () => void = () => {};
  /** 把最终标签写回笔记；父组件负责持久化与刷新。 */
  onApplyTags: (note: NoteItem, tags: string[]) => void = () => {};

  @State private draft: string = '';
  @State private tags: string[] = [];

  /** 建议标签占位数据 */
  private suggestions: string[] = ['重要', '待整理', '灵感', '读书', '工作', '归档'];

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    const seed: string[] = [];
    const existing: string[] | undefined = this.note.tags;
    if (existing !== undefined && existing.length > 0) {
      for (let i = 0; i < existing.length; i++) {
        seed.push(existing[i]);
      }
    } else if (this.note.tag.length > 0) {
      seed.push(this.note.tag);
    }
    this.tags = seed;
  }

  private has(tag: string): boolean {
    for (let i = 0; i < this.tags.length; i++) {
      if (this.tags[i] === tag) {
        return true;
      }
    }
    return false;
  }

  private addTag(raw: string): void {
    const tag: string = raw.trim().replace(/^#/, '');
    if (tag.length === 0 || this.has(tag)) {
      return;
    }
    const next: string[] = this.tags.slice();
    next.push(tag);
    this.tags = next;
    this.draft = '';
  }

  private removeTag(tag: string): void {
    const next: string[] = [];
    for (let i = 0; i < this.tags.length; i++) {
      if (this.tags[i] !== tag) {
        next.push(this.tags[i]);
      }
    }
    this.tags = next;
  }

  private toggleSuggestion(tag: string): void {
    if (this.has(tag)) {
      this.removeTag(tag);
    } else {
      this.addTag(tag);
    }
  }

  @Builder
  selectedChip(tag: string) {
    Row({ space: 4 }) {
      Text(`#${tag}`)
        .fontSize(TypographyTokens.TINY)
        .fontColor(Color.White)
      Text('×')
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(Color.White)
    }
    .padding({ left: 10, right: 8, top: 4, bottom: 4 })
    .borderRadius(10)
    .backgroundColor(this.palette().accent)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.removeTag(tag))
  }

  @Builder
  suggestChip(tag: string) {
    Text(`#${tag}`)
      .fontSize(TypographyTokens.TINY)
      .fontColor(this.has(tag) ? this.palette().accent : this.palette().inkSecondary)
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.has(tag) ? this.palette().accent : Color.Transparent })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.toggleSuggestion(tag))
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 10 }) {
        Text('编辑标签')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .width('100%')

        Row({ space: 8 }) {
          TextInput({ text: this.draft, placeholder: '输入标签后回车添加' })
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkPrimary)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(6)
            .height(32)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.draft = value;
            })
            .onSubmit(() => {
              this.addTag(this.draft);
            })
          Text('添加')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(Color.White)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(6)
            .backgroundColor(this.palette().accent)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.addTag(this.draft))
        }
        .width('100%')

        // ---- 已选标签 ----
        Column({ space: 6 }) {
          Text('已选标签')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .width('100%')
          if (this.tags.length === 0) {
            Text('还没有标签')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
              .width('100%')
          } else {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.tags, (tag: string) => {
                Row() {
                  this.selectedChip(tag)
                }
                .margin({ right: 6, bottom: 6 })
              }, (tag: string) => tag)
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        // ---- 建议标签 ----
        Column({ space: 6 }) {
          Text('建议标签')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.suggestions, (tag: string) => {
              Row() {
                this.suggestChip(tag)
              }
              .margin({ right: 6, bottom: 6 })
            }, (tag: string) => tag)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 8 }) {
          Button('取消')
            .layoutWeight(1)
            .height(28)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(6)
            .onClick(() => this.onClose())
          Button('完成')
            .layoutWeight(1)
            .height(28)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(Color.White)
            .backgroundColor(this.palette().accent)
            .borderRadius(6)
            .onClick(() => {
              this.onApplyTags(this.note, this.tags);
              this.onClose();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }
}
