/**
 * 重命名项目表单。输入框以当前项目名为初值。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { SpaceFolder } from '../../../common/types/SpaceFolder';
import { SheetOverlay } from './SheetScaffold';

@Component
export struct RenameProjectSheet {
  @Prop project: SpaceFolder;

  onClose: () => void = () => {};
  onRenameProject: (oldName: string, newName: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @State private draft: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.draft = this.project.name;
  }

  private submit(): void {
    const trimmed: string = this.draft.trim();
    if (trimmed.length > 0 && trimmed !== this.project.name) {
      this.onRenameProject(this.project.name, trimmed);
    }
    this.onClose();
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 8 }) {
        Text('重命名项目')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .width('100%')

        TextInput({ text: this.draft, placeholder: '新项目名称' })
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkPrimary)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(6)
          .height(32)
          .width('100%')
          .onChange((value: string) => {
            this.draft = value;
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
