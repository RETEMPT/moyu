/**
 * 华为风文档工作台统一顶层操作弹窗 (HuaweiDocActionDialog)
 *
 * 统一承接：
 *   1. 「另存为」：重命名、归属项目、格式选择 (PDF / Word / Markdown)
 *   2. 「格式转换」：导出为目标格式 (PDF / Markdown / Docx / TXT)
 *   3. 「输出为长图 / 逐页输出」：图片清晰度、分页范围、加盖水印
 *   4. 「打印设置」：纸张尺寸 (A4 / A3)、打印方向、双面打印
 *
 * 视觉规范：半透明暗化遮罩 + 居中毛玻璃圆角卡片 + 品牌强调色 + 暗黑模式适配。
 */
import { ColorPalette, TypographyTokens, LayoutTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';

export type HuaweiDocDialogType = 'save_as' | 'convert' | 'export_image' | 'print' | '';

@Component
export struct HuaweiDocActionDialog {
  @Require @Prop note: NoteItem;
  @Require @Prop dialogType: HuaweiDocDialogType = '';
  onClose: () => void = () => {};
  onConfirm: (actionType: string, payload: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  // 表单状态
  @State fileName: string = '';
  @State targetFormat: string = 'PDF';
  @State imageResolution: string = '高清 (2x)';
  @State paperSize: string = 'A4';
  @State printCopies: number = 1;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.fileName = this.note.title;
    if (this.dialogType === 'convert') {
      this.targetFormat = this.note.type.toUpperCase() === 'PDF' ? 'Markdown' : 'PDF';
    }
  }

  private dialogTitle(): string {
    if (this.dialogType === 'save_as') {
      return '另存为';
    }
    if (this.dialogType === 'convert') {
      return '格式转换';
    }
    if (this.dialogType === 'export_image') {
      return '输出为图片';
    }
    if (this.dialogType === 'print') {
      return '打印文档';
    }
    return '操作';
  }

  private submitAction(): void {
    let payload: string = this.fileName;
    if (this.dialogType === 'convert') {
      payload = this.targetFormat;
    } else if (this.dialogType === 'export_image') {
      payload = this.imageResolution;
    } else if (this.dialogType === 'print') {
      payload = `${this.paperSize}, ${this.printCopies}份`;
    }
    this.onConfirm(this.dialogType, payload);
    this.onClose();
  }

  @Builder
  formatOption(name: string) {
    Text(name)
      .fontSize(TypographyTokens.CAPTION)
      .fontColor(this.targetFormat === name ? this.palette().accent : this.palette().inkSecondary)
      .fontWeight(this.targetFormat === name ? FontWeight.Medium : FontWeight.Normal)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(6)
      .backgroundColor(this.targetFormat === name ? this.palette().accentSoft : this.palette().surfaceSubtle)
      .onClick(() => {
        this.targetFormat = name;
      })
  }

  @Builder
  dialogBody() {
    if (this.dialogType === 'save_as') {
      Column({ space: 10 }) {
        Text('文档名称')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')

        TextInput({ text: this.fileName })
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(8)
          .height(38)
          .width('100%')
          .onChange((v: string) => {
            this.fileName = v;
          })

        Text('保存格式')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')
          .margin({ top: 4 })

        Row({ space: 8 }) {
          this.formatOption('PDF')
          this.formatOption('Word')
          this.formatOption('Markdown')
        }
        .width('100%')
      }
      .width('100%')
    } else if (this.dialogType === 'convert') {
      Column({ space: 10 }) {
        Text('转换为目标格式')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')

        Row({ space: 8 }) {
          this.formatOption('Markdown')
          this.formatOption('PDF')
          this.formatOption('Docx')
          this.formatOption('TXT')
        }
        .width('100%')

        Text('转换后将自动提取原盘文本、批注与手写草稿，生成新格式副本存入当前项目。')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .margin({ top: 6 })
      }
      .width('100%')
    } else if (this.dialogType === 'export_image') {
      Column({ space: 10 }) {
        Text('输出画质')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')

        Row({ space: 8 }) {
          Text('标清 (1x)')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.imageResolution.includes('1x') ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.imageResolution.includes('1x') ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .onClick(() => { this.imageResolution = '标清 (1x)'; })

          Text('高清 (2x)')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.imageResolution.includes('2x') ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.imageResolution.includes('2x') ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .onClick(() => { this.imageResolution = '高清 (2x)'; })

          Text('超清 (4x 适合打印)')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.imageResolution.includes('4x') ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.imageResolution.includes('4x') ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .onClick(() => { this.imageResolution = '超清 (4x 适合打印)'; })
        }
        .width('100%')

        Text('包含页面矢量笔迹与答题批改，输出为纵向长图并保存至相册。')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .margin({ top: 4 })
      }
      .width('100%')
    } else if (this.dialogType === 'print') {
      Column({ space: 10 }) {
        Row() {
          Text('纸张尺寸')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkPrimary)
          Blank()
          Row({ space: 6 }) {
            Text('A4')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.paperSize === 'A4' ? this.palette().accent : this.palette().inkSecondary)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.paperSize === 'A4' ? this.palette().accentSoft : this.palette().surfaceSubtle)
              .onClick(() => { this.paperSize = 'A4'; })

            Text('A3 试卷')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.paperSize === 'A3' ? this.palette().accent : this.palette().inkSecondary)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(6)
              .backgroundColor(this.paperSize === 'A3' ? this.palette().accentSoft : this.palette().surfaceSubtle)
              .onClick(() => { this.paperSize = 'A3'; })
          }
        }
        .width('100%')

        Row() {
          Text('打印份数')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkPrimary)
          Blank()
          Row({ space: 8 }) {
            Text('－')
              .fontSize(TypographyTokens.BODY_REGULAR)
              .fontColor(this.palette().inkSecondary)
              .width(28)
              .height(28)
              .textAlign(TextAlign.Center)
              .borderRadius(6)
              .backgroundColor(this.palette().surfaceSubtle)
              .onClick(() => {
                if (this.printCopies > 1) {
                  this.printCopies--;
                }
              })

            Text(`${this.printCopies}`)
              .fontSize(TypographyTokens.BODY_REGULAR)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)
              .width(28)
              .textAlign(TextAlign.Center)

            Text('＋')
              .fontSize(TypographyTokens.BODY_REGULAR)
              .fontColor(this.palette().inkSecondary)
              .width(28)
              .height(28)
              .textAlign(TextAlign.Center)
              .borderRadius(6)
              .backgroundColor(this.palette().surfaceSubtle)
              .onClick(() => {
                this.printCopies++;
              })
          }
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  build() {
    Column() {
      Column({ space: 14 }) {
        // 卡片标题
        Row() {
          Text(this.dialogTitle())
            .fontSize(TypographyTokens.TITLE_SUB)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)

          Blank()

          Button('✕')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .width(44)
            .height(44)
            .padding(0)
            .borderRadius(22)
            .backgroundColor(this.palette().surfaceSubtle)
            .onClick(() => this.onClose())
        }
        .width('100%')

        // 内容插槽
        this.dialogBody()

        // 底部确认 / 取消按钮
        Row({ space: 10 }) {
          Button('取消')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
            .backgroundColor(this.palette().surfaceSubtle)
            .height(34)
            .layoutWeight(1)
            .borderRadius(8)
            .onClick(() => this.onClose())

          Button('确定')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(Color.White)
            .backgroundColor(this.palette().accent)
            .height(34)
            .layoutWeight(1)
            .borderRadius(8)
            .onClick(() => this.submitAction())
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width(360)
      .padding(18)
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 24, color: this.isDarkMode ? 'rgba(0,0,0,0.6)' : 'rgba(0,0,0,0.18)', offsetY: 6 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .hitTestBehavior(HitTestMode.Block)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(0,0,0,0.55)' : 'rgba(0,0,0,0.35)')
    .onClick(() => this.onClose())
  }
}
