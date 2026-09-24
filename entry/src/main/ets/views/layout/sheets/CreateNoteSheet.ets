/**
 * 新建笔记对话框（居中）。
 *
 * 初始值为「未命名笔记」，点击名称框即可改名。
 * 居中呈现，与新建项目对话框视觉一致。
 */
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';

@Component
export struct CreateNoteSheet {
  onClose: () => void = () => {};
  onCreateNote: (title: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @State private name: string = '未命名笔记';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private submit(): void {
    const trimmed: string = this.name.trim();
    this.onCreateNote(trimmed.length > 0 ? trimmed : '未命名笔记');
    this.onClose();
  }

  build() {
    Column() {
      Column({ space: 14 }) {
        Row() {
          Text('记随笔')
            .fontSize(TypographyTokens.TITLE_SUB)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Blank()
          Text('✕')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkMuted)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .borderRadius(6)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onClose())
        }
        .width('100%')

        TextInput({ text: this.name, placeholder: '点击输入笔记标题' })
          .fontSize(TypographyTokens.TITLE_SUB)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(10)
          .height(48)
          .width('100%')
          .onChange((value: string) => {
            this.name = value;
          })
          .onSubmit(() => {
            this.submit();
          })

        Text('支持 Markdown 语法、[[双向链接]] 与 #标签，离线存储在本地沙箱。')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')

        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(38)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(10)
            .onClick(() => this.onClose())

          Button('开始书写')
            .layoutWeight(1.2)
            .height(38)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(this.palette().accent)
            .borderRadius(10)
            .onClick(() => this.submit())
        }
        .width('100%')
      }
      .width(400)
      .padding(22)
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 28, color: this.isDarkMode ? 'rgba(0,0,0,0.55)' : 'rgba(0,0,0,0.18)', offsetY: 8 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .transition(
        TransitionEffect.scale({ x: AnimationTokens.SCALE_MODAL_ENTER, y: AnimationTokens.SCALE_MODAL_ENTER })
          .combine(TransitionEffect.OPACITY)
          .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
      )
      .onClick(() => {
        // 消费卡片内点击，避免冒泡关闭
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(0,0,0,0.55)' : 'rgba(0,0,0,0.35)')
    .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }))
    .onClick(() => this.onClose())
  }
}
