/**
 * 外观设置面板
 *
 * 应用内的主题热切换入口。三个选项对应 ThemeMode 的三个取值，
 * 点击即生效（不重启、不重建页面），并立即落盘。
 *
 * 切换会同时改变三样东西，面板底部把这三点如实告诉用户：
 *   1. 应用内配色（同步生效）
 *   2. 应用色彩模式（影响系统绘制元素）
 *   3. 桌面图标（浅色=白底墨笔，深色=曜石霓虹）
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { normalizeThemeMode, ThemeMode, THEME_MODE_OPTIONS, ThemeModeOption, themeModeLabel } from '../../common/theme/ThemeMode';
import { BrandMark } from '../brand/BrandMark';

@Component
export struct AppearanceSheet {
  onClose: () => void = () => {};
  /** 补入本机缺失的示例数据（含 PDF / 试卷，是进入原盘批注阅读器的入口） */
  onLoadSeedData: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  /** 当前选中的模式。初值取自 ThemeManager，切换后由本组件维护以驱动选中态重绘。 */
  @State selectedMode: ThemeMode = ThemeMode.SYSTEM;

  aboutToAppear(): void {
    this.selectedMode = normalizeThemeMode(ThemeManager.currentMode() as number);
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private async choose(mode: ThemeMode): Promise<void> {
    if (this.selectedMode === mode) {
      return;
    }
    this.selectedMode = mode;
    await ThemeManager.setMode(mode);
  }

  /** 单个模式选项行：标题 + 说明 + 选中态圆点 */
  @Builder
  modeRow(option: ThemeModeOption) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(option.label)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary)
          .fontWeight(this.selectedMode === option.mode ? FontWeight.Medium : FontWeight.Normal)
        Text(option.hint)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 选中态：实心圆点；未选中：空心圆环
      Circle({ width: 16, height: 16 })
        .fill(this.selectedMode === option.mode ? this.palette().accent : Color.Transparent)
        .stroke(this.selectedMode === option.mode ? this.palette().accent : this.palette().border)
        .strokeWidth(1.5)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(8)
    .backgroundColor(this.selectedMode === option.mode ? this.palette().accentSoft : Color.Transparent)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.choose(option.mode);
    })
  }

  build() {
    Column() {
      Column({ space: 0 }) {
        // ---- 标题 ----
        Row({ space: 10 }) {
          BrandMark({ markSize: 34 })
          Column({ space: 2 }) {
            Text('外观')
              .fontSize(TypographyTokens.TITLE_SUB)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkPrimary)
            Text(`当前：${themeModeLabel(this.selectedMode)}`)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('✕')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .borderRadius(6)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onClose())
        }
        .width('100%')
        .padding({ left: 14, right: 10, top: 14, bottom: 12 })

        Divider()
          .strokeWidth(1)
          .color(this.palette().borderSubtle)

        // ---- 模式选项 ----
        Column({ space: 2 }) {
          ForEach(THEME_MODE_OPTIONS, (option: ThemeModeOption) => {
            this.modeRow(option)
          }, (option: ThemeModeOption) => `theme-mode-${option.mode}`)
        }
        .width('100%')
        .padding({ left: 6, right: 6, top: 8, bottom: 8 })

        Divider()
          .strokeWidth(1)
          .color(this.palette().borderSubtle)

        // ---- 能力说明：把「图标跟随主题」的真实范围写清楚，不夸大 ----
        Column({ space: 4 }) {
          Text('切换后立即生效，无需重启。桌面图标会同步换成对应的浅色或深色版本。')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .width('100%')
          Text('「跟随系统」时，桌面图标由应用在系统深浅色变化时同步；系统未变则保持当前图标。')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 14 })
        .alignItems(HorizontalAlign.Start)

        Divider()
          .strokeWidth(1)
          .color(this.palette().borderSubtle)

        // ---- 数据：补入示例 ----
        Column({ space: 6 }) {
          Text('示例数据')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
            .fontWeight(FontWeight.Medium)
            .width('100%')
          Text('补入本机还没有的示例笔记。其中包含 PDF 与试卷类型，是进入「原盘批注」PDF 阅读器的入口。已存在的笔记一律不动。')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .width('100%')
          Text('载入示例数据')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().accent)
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .borderRadius(7)
            .backgroundColor(this.palette().accentSoft)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.onLoadSeedData();
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 14 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxWidth: 460 })
      .borderRadius(12)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 32, color: 'rgba(0,0,0,0.22)' })
      .border({ width: 1, color: this.palette().border })
      .transition(
        TransitionEffect.scale({ x: 0.95, y: 0.95 })
          .combine(TransitionEffect.OPACITY)
          .animation({ curve: curves.springMotion(0.25, 0.76) })
      )
      .onClick(() => {
        // 消费卡片内的点击，避免冒泡到遮罩导致面板被关闭
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 96 })
    .backgroundColor('rgba(0,0,0,0.25)')
    .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.25, 0.76) }))
    .onClick(() => this.onClose())
  }
}
