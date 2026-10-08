/**
 * 新建笔记的命名弹层。
 *
 * 之前「新建笔记 / 白板 / 参考资料」都是一键直接落地一个硬编码标题（未命名笔记），
 * 没有命名这一步。这里补上：默认填入传入的标题，点进输入框即自动清空从头命名，
 * 右上角的对号（✓）确认创建。真正的落盘仍由 Index 的 createNote / createNoteInProject 处理。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { SheetOverlay } from './SheetScaffold';
import { AppIcon } from '../../common/AppIcon';

@Component
export struct NameNoteSheet {
  @Prop defaultName: string = '未命名笔记';
  @Prop noteType: string = 'Markdown';
  @Prop busy: boolean = false;
  @Prop errorMessage: string = '';

  onClose: () => void = () => {};
  onConfirm: (name: string) => void = () => {};
  onTypeChange: (type: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @State private draft: string = '';
  /** 是否已执行过「聚焦即清空」，避免清空后再次聚焦又把用户输入抹掉 */
  private cleared: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.draft = this.defaultName;
  }

  private focusClear(): void {
    if (!this.cleared) {
      this.cleared = true;
      this.draft = '';
    }
  }

  private submit(): void {
    if (this.busy) { return; }
    const trimmed: string = this.draft.trim();
    this.onConfirm(trimmed.length > 0 ? trimmed : this.defaultName);
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 10 }) {
        Row() {
          Text('新建笔记')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 右上角对号：确认创建
          Button({ type: ButtonType.Normal }) {
            if (this.busy) {
              LoadingProgress().width(20).height(20).color(this.palette().onAccent)
            } else {
              AppIcon({ source: $r('app.media.ic_check'), tint: this.palette().onAccent })
            }
          }
            .width(44)
            .height(44)
            .enabled(!this.busy)
            .accessibilityText(this.busy ? '正在创建笔记' : '创建笔记')
            .padding(0)
            .borderRadius(15)
            .backgroundColor(this.palette().accent)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.submit())
        }
        .width('100%')

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            AppIcon({ source: $r('app.media.ic_note'), tint: this.noteType === 'Markdown' ? this.palette().accent : this.palette().inkSecondary })
          }.height(44).layoutWeight(1).enabled(!this.busy).accessibilityText('文字笔记').bindTips('文字笔记')
            .backgroundColor(this.noteType === 'Markdown' ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .fontColor(this.palette().inkPrimary).onClick(() => this.onTypeChange('Markdown'))
          Button({ type: ButtonType.Normal }) {
            AppIcon({ source: $r('app.media.ic_pen'), tint: this.noteType !== 'Markdown' ? this.palette().accent : this.palette().inkSecondary })
          }.height(44).layoutWeight(1).enabled(!this.busy).accessibilityText('手写笔记').bindTips('手写笔记')
            .backgroundColor(this.noteType !== 'Markdown' ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .fontColor(this.palette().inkPrimary).onClick(() => this.onTypeChange('Handwriting'))
        }.width('100%')

        TextInput({ text: this.draft, placeholder: this.defaultName })
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(8)
          .height(48)
          .enabled(!this.busy)
          .width('100%')
          .onFocus(() => this.focusClear())
          .onChange((value: string) => {
            this.draft = value;
          })
          .onSubmit(() => this.submit())
        if (this.errorMessage) {
          Text(this.errorMessage).fontSize(12).fontColor(this.palette().danger).width('100%')
        }
      }
      .width('100%')
    }
  }
}
