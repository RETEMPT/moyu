/**
 * 新建项目表单。
 *
 * 表单状态（名称 / 图标 / 主题色）由本组件自己持有 —— 之前放在 Sidebar 上，
 * 导致「取消后重新打开还残留上次输了一半的名字」。组件随 sheet 一起卸载重建，
 * 状态自然清空。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { SheetOverlay } from './SheetScaffold';

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

  @State private name: string = '';
  @State private icon: string = PRESET_ICONS[0];
  @State private color: string = PRESET_COLORS[0];

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private submit(): void {
    const trimmed: string = this.name.trim();
    if (trimmed.length > 0) {
      this.onCreateProject(trimmed, this.color, this.icon);
    }
    this.onClose();
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 12 }) {
        Text('新建项目')
          .fontSize(TypographyTokens.TITLE_SUB)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .width('100%')

        TextInput({ text: this.name, placeholder: '输入项目名称（如：操作系统课设）' })
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(8)
          .height(38)
          .width('100%')
          .onChange((value: string) => {
            this.name = value;
          })

        this.iconPicker()
        this.colorPicker()

        Row({ space: 8 }) {
          Button('取消')
            .layoutWeight(1)
            .height(34)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(8)
            .onClick(() => this.onClose())

          Button('创建项目')
            .layoutWeight(1)
            .height(34)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(Color.White)
            .backgroundColor(this.palette().accent)
            .borderRadius(8)
            .onClick(() => this.submit())
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .width('100%')
    }
  }

  @Builder
  iconPicker() {
    Column({ space: 4 }) {
      Text('选择图标')
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .width('100%')
      Row({ space: 8 }) {
        ForEach(PRESET_ICONS, (item: string) => {
          Text(item)
            .fontSize(TypographyTokens.BODY_LARGE)
            .width(26)
            .height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(6)
            .backgroundColor(this.icon === item ? this.palette().activeBg : Color.Transparent)
            .border({
              width: 1,
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
    Column({ space: 4 }) {
      Text('主题色')
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .width('100%')
      Row({ space: 10 }) {
        ForEach(PRESET_COLORS, (item: string) => {
          Circle({ width: 20, height: 20 })
            .fill(item)
            .stroke(this.color === item ? this.palette().inkPrimary : Color.Transparent)
            .strokeWidth(2)
            .onClick(() => {
              this.color = item;
            })
        }, (item: string) => item)
      }
      .width('100%')
    }
  }
}
