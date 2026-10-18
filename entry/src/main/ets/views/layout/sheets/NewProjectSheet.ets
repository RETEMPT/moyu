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
import { PROJECT_ICONS, ProjectIconOption, projectIcon } from '../../../common/utils/ProjectIcons';
import { AppIcon } from '../../common/AppIcon';
import { IconButton } from '../../common/IconButton';

/** 项目预设颜色；图标与其他项目入口共用映射。 */
const PRESET_COLORS: string[] = [
  '#787774', // 中性灰
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
  onCreateProject: (name: string, color: string, icon: string) => Promise<boolean> = async () => false;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';

  @State private name: string = '未命名项目';
  @State private icon: string = PROJECT_ICONS[0].value;
  @State private color: string = PRESET_COLORS[0];
  @State private isFocused: boolean = false;
  private cleared: boolean = false;
  @State private saving: boolean = false;
  @State private error: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private async submit(): Promise<void> {
    if (this.saving) { return; }
    const trimmed: string = this.name.trim();
    this.saving = true; this.error = '';
    try {
      if (await this.onCreateProject(trimmed.length > 0 ? trimmed : '未命名项目', this.color, this.icon)) { this.onClose(); }
      else { this.error = '未能创建，请检查名称或重试'; }
    } catch { this.error = '保存失败，请重试'; }
    finally { this.saving = false; }
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
          IconButton({ icon: $r('app.media.ic_close'), label: '关闭新建项目', available: !this.saving, onAction: this.onClose })
        }
        .width('100%')

        TextInput({ text: this.name, placeholder: '未命名项目' })
          .maxLength(80)
          .enabled(!this.saving)
          .fontSize(TypographyTokens.TITLE_SUB)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(5)
          .height(46)
          .width('100%')
          .accessibilityText('项目名称')
          .onFocus(() => {
            animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
              this.isFocused = true;
            });
            if (!this.cleared && this.name === '未命名项目') {
              this.cleared = true;
              this.name = '';
            }
          })
          .onBlur(() => {
            animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
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

        if (this.error) { Text(this.error).fontSize(13).fontColor(this.palette().danger).width('100%') }
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(48)
            .enabled(!this.saving)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(5)
            .onClick(() => this.onClose())

          Button(this.saving ? '正在保存…' : '创建项目')
            .layoutWeight(1.2)
            .height(48)
            .enabled(!this.saving)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().onAccent)
            .backgroundColor(this.palette().accent)
            .borderRadius(5)
            .onClick(() => this.submit())
        }
        .width('100%')
      }
      .width('88%')
      .constraintSize({ maxWidth: 400 })
      .padding(20)
      .borderRadius(5)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 20, color: 'rgba(0,0,0,0.12)', offsetY: 6 })
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
    .onClick(() => { if (!this.saving) { this.onClose(); } })
  }

  @Builder
  iconPicker() {
    Column({ space: 6 }) {
      Text('图标')
        .fontSize(13)
        .fontColor(this.palette().inkMuted)
        .width('100%')
      GridRow({ columns: 4, gutter: 8 }) {
        ForEach(PROJECT_ICONS, (item: ProjectIconOption) => {
          GridCol() {
            Button({ type: ButtonType.Normal }) {
              AppIcon({ source: projectIcon(item.value), iconSize: 23, tint: this.palette().inkPrimary })
            }.width('100%').height(44).padding(0).borderRadius(5).enabled(!this.saving)
              .backgroundColor(this.icon === item.value ? this.palette().activeBg : Color.Transparent)
              .border({ width: 1, color: this.icon === item.value ? this.palette().inkPrimary : this.palette().borderSubtle })
              .accessibilityText('项目图标 ' + item.label).accessibilityDescription(this.icon === item.value ? '已选择' : '未选择')
              .onClick(() => { this.icon = item.value; })
          }
        }, (item: ProjectIconOption) => item.value)
      }
      .width('100%')
    }
  }

  @Builder
  colorPicker() {
    Column({ space: 6 }) {
      Text('主题色')
        .fontSize(13)
        .fontColor(this.palette().inkMuted)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(PRESET_COLORS, (item: string) => {
          Button({ type: ButtonType.Normal }) {
            Circle({ width: 20, height: 20 }).fill(item)
              .stroke(this.color === item ? this.palette().inkPrimary : Color.Transparent).strokeWidth(2)
          }.width(44).height(44).padding(0).borderRadius(5).enabled(!this.saving)
            .backgroundColor(this.color === item ? this.palette().activeBg : Color.Transparent)
            .accessibilityText('项目颜色 ' + item).accessibilityDescription(this.color === item ? '已选择' : '未选择')
            .onClick(() => { this.color = item; })
        }, (item: string) => item)
      }
      .width('100%')
    }
  }
}
