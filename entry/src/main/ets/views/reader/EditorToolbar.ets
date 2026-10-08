/**
 * 编辑格式与双向链接工具栏。
 *
 * 主栏保留格式与链接入口。
 *   `Aa 格式`  展开格式面板（标题级别 / 加粗 / 斜体 / 列表 / 待办 / 引用）
 *   `⊡ 链接`  双向链接，直接动作
 * 面板内每个选项都是「图标 + 中文」，避免裸符号看不懂。
 *
 * 格式动作统一走 onAction(action)，由 MarkdownReader 按当前选区改写正文（功能5）；
 * 仅编辑模式下显示；图片识别从全局导入与整理入口使用。
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { AppIcon } from '../common/AppIcon';

@Component
export struct EditorToolbar {
  /** 统一动作回调；本阶段父组件可不实现（默认 no-op） */
  onAction: (action: string) => void = () => {};

  /** 当前展开的面板：'' 无 / 'format' 格式 */
  @State openPanel: string = '';

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  /** 主栏按钮左右内边距：手机收窄，避免三枚按钮溢出窄屏 */
  private btnPad(): number {
    return this.isPhone ? 10 : 14;
  }

  private togglePanel(name: string): void {
    animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
      this.openPanel = this.openPanel === name ? '' : name;
    });
  }

  // ---- 主栏按钮 ----

  @Builder
  mainPanelBtn(icon: Resource, label: string, panel: string) {
    Row({ space: 6 }) {
      AppIcon({ source: icon, iconSize: 18, tint: this.openPanel === panel ? this.palette().accent : this.palette().inkSecondary })
    }
      .height(44)
      .constraintSize({ minWidth: 44 })
      .padding({ left: this.btnPad(), right: this.btnPad() })
      .borderRadius(8)
      .backgroundColor(this.openPanel === panel ? this.palette().accentSoft : Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText(label).bindTips(label)
      .onClick(() => this.togglePanel(panel))
  }

  @Builder
  mainActionBtn(icon: Resource, label: string, action: string) {
    Row({ space: 6 }) {
      AppIcon({ source: icon, iconSize: 18, tint: this.palette().inkSecondary })
    }
      .height(44)
      .constraintSize({ minWidth: 44 })
      .padding({ left: this.btnPad(), right: this.btnPad() })
      .borderRadius(8)
      .hoverEffect(HoverEffect.Highlight)
      .accessibilityText(label).bindTips(label)
      .onClick(() => this.onAction(action))
  }

  @Builder
  groupDivider() {
    Divider()
      .vertical(true)
      .strokeWidth(1)
      .height(20)
      .color(this.palette().borderSubtle)
      .margin({ left: 4, right: 4 })
  }

  // ---- 面板内选项（图标 + 中文） ----

  @Builder
  chip(label: string, action: string) {
    Text(label)
      .fontSize(TypographyTokens.CAPTION)
      .fontColor(this.palette().inkPrimary)
      .textAlign(TextAlign.Center)
      .constraintSize({ minHeight: 44 })
      .padding({ left: 12, right: 12, top: 9, bottom: 9 })
      .borderRadius(8)
      .backgroundColor(this.palette().surfaceSubtle)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.onAction(action))
  }

  @Builder
  sectionCaption(text: string) {
    Text(text)
      .fontSize(TypographyTokens.TINY)
      .fontColor(this.palette().inkMuted)
      .width('100%')
      .margin({ top: 4, bottom: 6 })
  }

  @Builder
  formatPanel() {
    Column({ space: 2 }) {
      this.sectionCaption('标题')
      Row({ space: 8 }) {
        this.chip('标题 1', 'h1')
        this.chip('标题 2', 'h2')
        this.chip('标题 3', 'h3')
      }
      this.sectionCaption('文字')
      Row({ space: 8 }) {
        this.chip('B  加粗', 'bold')
        this.chip('I  斜体', 'italic')
      }
      this.sectionCaption('列表')
      Row({ space: 8 }) {
        this.chip('•  无序', 'bullet')
        this.chip('1.  有序', 'ordered')
        this.chip('☑  待办', 'task')
      }
      this.sectionCaption('段落')
      Row({ space: 8 }) {
        this.chip('❝  引用', 'quote')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 4, right: 4, top: 4, bottom: 8 })
  }

  build() {
    Column() {
      if (this.openPanel === 'format') {
        this.formatPanel()
        Divider().strokeWidth(1).color(this.palette().borderSubtle).margin({ bottom: 6 })
      }

      Row({ space: 6 }) {
        this.mainPanelBtn($r('app.media.ic_format'), '格式', 'format')
        this.groupDivider()
        this.mainActionBtn($r('app.media.ic_link'), '链接', 'wikilink')
      }
      .alignItems(VerticalAlign.Center)
    }
    .constraintSize({ maxWidth: this.isPhone ? '94%' : 460 })
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(16)
    .backgroundColor(this.palette().surface)
    .border({ width: 1, color: this.palette().border })
    .shadow({ radius: 20, color: 'rgba(0,0,0,0.18)' })
  }
}
