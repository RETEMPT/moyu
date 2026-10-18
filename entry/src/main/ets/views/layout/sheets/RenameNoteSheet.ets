/**
 * 重命名资料表单。输入框以当前资料标题为初值。
 *
 * 沿用 SheetScaffold 外壳，与项目重命名保持一致的底部弹层体感。
 * 标题元数据由 Index.commitRename 持久化；正文保留原文。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { SheetOverlay } from './SheetScaffold';

@Component
export struct RenameNoteSheet {
  @Prop note: NoteItem;
  @Prop @Watch('requestClose') closeToken: number = 0;

  onClose: () => void = () => {};
  onRenameNote: (note: NoteItem, newTitle: string) => Promise<boolean> = async () => false;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';

  @State private draft: string = '';
  @State private saving: boolean = false;
  @State private error: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  aboutToAppear(): void {
    this.draft = this.note.title;
  }

  private requestClose(): void { if (!this.saving) { this.onClose(); } }

  private async submit(): Promise<void> {
    if (this.saving) { return; }
    const trimmed = this.draft.trim();
    if (!trimmed || trimmed.length > 200 || /[\r\n]/.test(trimmed)) { this.error = '标题需为 1–200 字，不能包含换行'; return; }
    if (trimmed === this.note.title) { this.onClose(); return; }
    this.saving = true; this.error = '';
    try {
      if (await this.onRenameNote(this.note, trimmed)) { this.onClose(); }
      else { this.error = '未能保存标题，请重试'; }
    } catch { this.error = '未能保存标题，请重试'; }
    finally { this.saving = false; }
  }

  build() {
    SheetOverlay({ onDismiss: () => this.requestClose() }) {
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
          .height(44)
          .width('100%').enabled(!this.saving).accessibilityText('资料新标题')
          .onChange((value: string) => {
            this.draft = value;
          })
          .onSubmit(() => {
            this.submit();
          })

        if (this.error) { Text(this.error).fontSize(12).fontColor(this.palette().danger).width('100%') }

        Row({ space: 8 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(6)
            .enabled(!this.saving).onClick(() => this.requestClose())

          Button(this.saving ? '保存中…' : '保存')
            .layoutWeight(1)
            .height(44)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().onAccent)
            .backgroundColor(this.palette().accent)
            .borderRadius(6)
            .enabled(!this.saving).onClick(() => this.submit())
        }
        .width('100%')
      }
      .width('100%')
    }
  }
}
