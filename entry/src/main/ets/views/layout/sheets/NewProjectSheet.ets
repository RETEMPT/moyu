/**
 * 新建项目表单（居中对话框）。
 *
 * 表单状态（名称 / 图标 / 主题色）由本组件自己持有 —— 之前放在 Sidebar 上，
 * 导致「取消后重新打开还残留上次输了一半的名字」。组件随 sheet 一起卸载重建，
 * 状态自然清空。
 *
 * 居中呈现，初始值为「未命名项目」，点击名称框即可改名。
 */
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';

/** 项目预设图标与颜色。仅本表单使用，故就近定义。 */
const PRESET_ICONS: string[] = ['📁', '🚀', '📚', '💡', '🔬', '💼', '🎯', '🎨'];
const PRESET_COLORS: string[] = [
  '#4F46E5', // 经典靛蓝
  '#059669', // 翡翠绿
  '#D97706', // 琥珀橙
  '#DC2626', // 绯红
  '#2563EB', // 宝蓝
  '#7C3AED'  // 罗兰紫
];

@Component
export struct NewProjectSheet {
  onClose: () => void = () => {};
  onCreateProject: (name: string, color: string, icon: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @State private name: string = '未命名项目';
  @State private icon: string = PRESET_ICONS[0];
  @State private color: string = PRESET_COLORS[0];
  @State private isFocused: boolean = false;
  private cleared: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private submit(): void {
    const trimmed: string = this.name.trim();
    this.onCreateProject(trimmed.length > 0 ? trimmed : '未命名项目', this.color, this.icon);
    this.onClose();
  }

  build() {
    Column() {
      Column({ space: 14 }) {
        Row() {
          Text('新建项目')
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
            .responseRegion({ x: -8, y: -8, width: 44, height: 44 })
            .onClick(() => this.onClose())
        }
        .width('100%')

        TextInput({ text: this.name, placeholder: '未命名项目' })
          .fontSize(TypographyTokens.TITLE_SUB)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(10)
          .height(46)
          .width('100%')
          .onFocus(() => {
            animateTo({ duration: 260, curve: Curve.EaseInOut }, () => {
              this.isFocused = true;
            });
            if (!this.cleared && this.name === '未命名项目') {
              this.cleared = true;
              this.name = '';
            }
          })
          .onBlur(() => {
            animateTo({ duration: 260, curve: Curve.EaseInOut }, () => {
              this.isFocused = false;
            });
          })
          .onChange((value: string) => {
            this.name = value;
          })
          .onSubmit(() => {
            this.submit();
          })

        this.iconPicker()
        this.colorPicker()

        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(38)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(10)
            .onClick(() => this.onClose())

          Button('创建项目')
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
      .width('88%')
      .constraintSize({ maxWidth: 400 })
      .padding(20)
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 28, color: this.isDarkMode ? 'rgba(0,0,0,0.55)' : 'rgba(0,0,0,0.18)', offsetY: 8 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .offset({ y: this.isFocused ? -90 : 0 })
      .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
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

  @Builder
  iconPicker() {
    Column({ space: 6 }) {
      Text('选择图标')
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .width('100%')
      Row({ space: 10 }) {
        ForEach(PRESET_ICONS, (item: string) => {
          Text(item)
            .fontSize(22)
            .width(36)
            .height(36)
            .textAlign(TextAlign.Center)
            .borderRadius(8)
            .backgroundColor(this.icon === item ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .border({
              width: 1.5,
              color: this.icon === item ? this.palette().accent : Color.Transparent
            })
            .onClick(() => {
              this.icon = item;
            })
        }, (item: string) => item)
      }
      .width('100%')
    }
  }

  @Builder
  colorPicker() {
    Column({ space: 6 }) {
      Text('主题色')
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .width('100%')
      Row({ space: 12 }) {
        ForEach(PRESET_COLORS, (item: string) => {
          Circle({ width: 24, height: 24 })
            .fill(item)
            .stroke(this.color === item ? this.palette().inkPrimary : Color.Transparent)
            .strokeWidth(2.5)
            .onClick(() => {
              this.color = item;
            })
        }, (item: string) => item)
      }
      .width('100%')
    }
  }
}
