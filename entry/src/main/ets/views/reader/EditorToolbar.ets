/**
 * 编辑格式工具栏（功能5）+ 插入入口（功能4 图片 / 15 OCR / 14 录音）
 *
 * iOS 备忘录风格：主栏只放三个高频入口——
 *   `Aa 格式`  展开格式面板（标题级别 / 加粗 / 斜体 / 列表 / 待办 / 引用）
 *   `🔗 链接`  双向链接（Word 链条图标），直接动作
 *   `📎 插入`  展开插入面板（图片 / OCR / 录音），取代原来的省略号
 * 面板内每个选项都是「图标 + 中文」，避免裸符号看不懂。
 *
 * 格式动作统一走 onAction(action)，由 MarkdownReader 按当前选区改写正文（功能5）；
 * 图片 / OCR / 录音属后续阶段，点击暂提示「即将上线」。仅编辑模式下悬浮于正文底部。
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';

@Component
export struct EditorToolbar {
  /** 统一动作回调；本阶段父组件可不实现（默认 no-op） */
  onAction: (action: string) => void = () => {};

  /** 当前展开的面板：'' 无 / 'format' 格式 / 'insert' 插入 */
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
    animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
      this.openPanel = this.openPanel === name ? '' : name;
    });
  }

  // ---- 主栏按钮 ----

  @Builder
  mainPanelBtn(label: string, panel: string) {
    Text(label)
      .fontSize(TypographyTokens.CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.openPanel === panel ? this.palette().accent : this.palette().inkSecondary)
      .textAlign(TextAlign.Center)
      .height(36)
      .padding({ left: this.btnPad(), right: this.btnPad() })
      .borderRadius(8)
      .backgroundColor(this.openPanel === panel ? this.palette().accentSoft : Color.Transparent)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.togglePanel(panel))
  }

  @Builder
  mainActionBtn(label: string, action: string) {
    Text(label)
      .fontSize(TypographyTokens.CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.palette().inkSecondary)
      .textAlign(TextAlign.Center)
      .height(36)
      .padding({ left: this.btnPad(), right: this.btnPad() })
      .borderRadius(8)
      .hoverEffect(HoverEffect.Highlight)
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

  @Builder
  insertPanel() {
    Row({ space: 8 }) {
      this.chip('🖼  图片', 'insert_image')
      this.chip('📷  OCR', 'ocr')
      this.chip('🎙  录音', 'record')
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 4, bottom: 8 })
  }

  build() {
    Column() {
      if (this.openPanel === 'format') {
        this.formatPanel()
        Divider().strokeWidth(1).color(this.palette().borderSubtle).margin({ bottom: 6 })
      } else if (this.openPanel === 'insert') {
        this.insertPanel()
        Divider().strokeWidth(1).color(this.palette().borderSubtle).margin({ bottom: 6 })
      }

      Row({ space: 6 }) {
        this.mainPanelBtn('Aa  格式', 'format')
        this.groupDivider()
        this.mainActionBtn('🔗  链接', 'wikilink')
        this.groupDivider()
        this.mainPanelBtn('📎  插入', 'insert')
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
