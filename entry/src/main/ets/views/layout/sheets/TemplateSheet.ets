/**
 * 新建模板选择面板（功能10）
 *
 * 点「＋ 新建」时的落点：先选模板再创建。
 * 列出预设模板（空白 / 会议记录 / 日记 / 读书笔记 / 周报），
 * 点选后通过 onPickTemplate 交给父组件按模板预填正文并落盘。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { SheetCancelButton, SheetOverlay } from './SheetScaffold';

/** 一个模板条目的视图数据 */
interface TemplateOption {
  icon: string;
  name: string;
  desc: string;
}

@Component
export struct TemplateSheet {
  @Prop projectName: string = '';

  onClose: () => void = () => {};
  /** 按模板创建笔记；父组件负责预填正文与落盘 */
  onPickTemplate: (templateName: string, projectName: string) => void = () => {};

  private options: TemplateOption[] = [
    { icon: '📄', name: '空白笔记', desc: '从一张白纸开始' },
    { icon: '📝', name: '会议记录', desc: '与会人 / 议题 / 决议 / 待办' },
    { icon: '📅', name: '日记', desc: '日期 / 心情 / 今日记事' },
    { icon: '📚', name: '读书笔记', desc: '书名 / 摘录 / 我的思考' },
    { icon: '📊', name: '周报', desc: '本周完成 / 下周计划 / 风险' }
  ];

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  @Builder
  templateRow(option: TemplateOption) {
    Row({ space: 12 }) {
      Text(option.icon)
        .fontSize(TypographyTokens.TITLE_SUB)
        .width(28)
        .textAlign(TextAlign.Center)
      Column({ space: 2 }) {
        Text(option.name)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .width('100%')
        Text(option.desc)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(TypographyTokens.TITLE_SUB)
        .fontColor(this.palette().inkMuted)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(8)
    .backgroundColor(this.palette().surfaceSubtle)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.onPickTemplate(option.name, this.projectName);
      this.onClose();
    })
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 8 }) {
        Text('选择模板新建')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .width('100%')
        Text(this.projectName.length === 0 ? '新建到「未分类」' : `新建到「${this.projectName}」`)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')
          .margin({ bottom: 4 })

        ForEach(this.options, (option: TemplateOption) => {
          this.templateRow(option)
        }, (option: TemplateOption) => option.name)

        SheetCancelButton({ onCancel: this.onClose })
      }
      .width('100%')
    }
  }
}
