/**
 * Action Sheet 的公共外壳与零件。
 *
 * 侧边栏里有 5 个底部弹层（项目菜单 / 新建项目 / 新建内容 / 重命名 / 文件菜单），
 * 它们的外壳完全一致：半透明遮罩 + 底部圆角卡片 + 同一套出入场动画。
 * 抽成组件后，各个 sheet 只需专注自己的内容，样式改动也只有一处。
 */
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';

/** 遮罩 + 底部卡片。body 由调用方通过尾随闭包注入。 */
@Component
export struct SheetOverlay {
  /** 点击遮罩或调用方主动关闭时触发 */
  onDismiss: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @Builder
  emptyBody() {
  }

  @BuilderParam body: () => void = this.emptyBody;

  build() {
    Column() {
      Column({ space: 8 }) {
        this.body()
      }
      .width('94%')
      .padding(10)
      .margin({ bottom: 10 })
      .borderRadius(12)
      .backgroundColor(ThemeHelper.paletteOfDark(this.isDarkMode).surface)
      .shadow({ radius: 16, color: this.isDarkMode ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.14)', offsetY: 4 })
      .border({
        width: 1,
        color: this.isDarkMode ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)'
      })
      .onClick(() => {
        // 消费卡片内的点击，避免冒泡到遮罩导致弹层关闭
      })
      .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .backgroundColor(this.isDarkMode ? 'rgba(0,0,0,0.32)' : 'rgba(0,0,0,0.12)')
    .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }))
    .onClick(() => this.onDismiss())
  }
}

/** 弹层里的一行操作项（图标 + 文案整行可点）。 */
@Component
export struct SheetActionRow {
  @Prop label: string = '';
  @Prop isDestructive: boolean = false;
  onAction: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  build() {
    Row() {
      Text(this.label)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.isDestructive ? this.palette().danger : this.palette().inkPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(32)
    .padding({ left: 8, right: 8 })
    .borderRadius(6)
    .backgroundColor(this.palette().surfaceSubtle)
    .onClick(() => this.onAction())
  }
}

/** 弹层底部的「取消」按钮。 */
@Component
export struct SheetCancelButton {
  onCancel: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  build() {
    Button('取消')
      .width('100%')
      .height(28)
      .fontSize(TypographyTokens.CAPTION)
      .fontColor(ThemeHelper.paletteOfDark(this.isDarkMode).inkSecondary)
      .backgroundColor(ThemeHelper.paletteOfDark(this.isDarkMode).surfaceSubtle)
      .borderRadius(6)
      .margin({ top: 2 })
      .onClick(() => this.onCancel())
  }
}

/**
 * 危险操作的二次确认块。
 * 默认只显示 isArmed=false 的触发项；点开后替换为红色确认行，避免误触即删。
 */
@Component
export struct DestructiveConfirm {
  @Prop triggerLabel: string = '';
  @Prop question: string = '';
  @Prop consequence: string = '';
  onConfirm: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @State private isArmed: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  build() {
    Column({ space: 4 }) {
      if (this.isArmed) {
        Column({ space: 6 }) {
          Text(this.question)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().danger)
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.consequence.length > 0) {
            Text(this.consequence)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Row({ space: 6 }) {
            Button('取消')
              .layoutWeight(1)
              .height(26)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkSecondary)
              .backgroundColor(this.palette().surface)
              .borderRadius(6)
              .onClick(() => {
                this.isArmed = false;
              })
            Button('确认删除')
              .layoutWeight(1)
              .height(26)
              .fontSize(TypographyTokens.TINY)
              .fontColor(Color.White)
              .backgroundColor(this.palette().danger)
              .borderRadius(6)
              .onClick(() => {
                this.isArmed = false;
                this.onConfirm();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(6)
        .borderRadius(6)
        .backgroundColor(this.palette().surfaceSubtle)
      } else {
        SheetActionRow({
          label: this.triggerLabel,
          isDestructive: true,
          onAction: () => {
            this.isArmed = true;
          }
        })
      }
    }
    .width('100%')
  }
}
