/**
 * 重命名资料表单。输入框以当前资料标题为初值。
 *
 * 沿用 SheetScaffold 外壳，与项目重命名保持一致的底部弹层体感。
 * 真正的落盘（改写正文首个 H1 + 元数据）由 Index.commitRename 处理。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { SheetOverlay } from './SheetScaffold';

@Component
export struct RenameNoteSheet {
  @Prop note: NoteItem;

  onClose: () => void = () => {};
  onRenameNote: (note: NoteItem, newTitle: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @State private draft: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.draft = this.note.title;
  }

  private submit(): void {
    const trimmed: string = this.draft.trim();
    if (trimmed.length > 0 && trimmed !== this.note.title) {
      this.onRenameNote(this.note, trimmed);
    }
    this.onClose();
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 8 }) {
        Text('重命名资料')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .width('100%')

        TextInput({ text: this.draft, placeholder: '新标题' })
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkPrimary)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(6)
          .height(32)
          .width('100%')
          .onChange((value: string) => {
            this.draft = value;
          })
          .onSubmit(() => {
            this.submit();
          })

        Row({ space: 8 }) {
          Button('取消')
            .layoutWeight(1)
            .height(28)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(6)
            .onClick(() => this.onClose())

          Button('保存')
            .layoutWeight(1)
            .height(28)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(Color.White)
            .backgroundColor(this.palette().accent)
            .borderRadius(6)
            .onClick(() => this.submit())
        }
        .width('100%')
      }
      .width('100%')
    }
  }
}
