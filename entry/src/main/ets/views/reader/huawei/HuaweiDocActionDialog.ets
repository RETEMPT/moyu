/** Output actions describe their scope before opening a system picker or share panel. */
import { ColorPalette } from '../../../common/constants/DesignTokens';
import { ReaderTheme } from '../../../common/theme/ReaderTheme';
import { AppIcon } from '../../common/AppIcon';
import { NoteItem } from '../../../common/types/NoteItem';
import { IconButton } from '../../common/IconButton';

export type HuaweiDocDialogType = 'export_text' | 'export_image' | 'share_pdf' | 'share_text' | 'share_image' | 'export_original' | '';

@Component
export struct HuaweiDocActionDialog {
  @Require @Prop note: NoteItem;
  @Prop documentTitle: string = '';
  @Require @Prop dialogType: HuaweiDocDialogType = '';
  @Prop busy: boolean = false;
  @Prop resultMessage: string = '';
  @Prop failed: boolean = false;
  onClose: () => void = () => {};
  onConfirm: (extension: string) => void = () => {};
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @State extension: string = '.md';

  private palette(): ColorPalette { return ReaderTheme.palette(this.isDarkMode, this.themeStyle); }
  private dialogTitle(): string {
    if (this.resultMessage && !this.failed) { return this.dialogType.startsWith('share_') ? '已打开分享面板' : '已保存'; }
    if (this.dialogType === 'share_image') { return '分享原文件'; }
    if (this.dialogType === 'export_original') { return '导出原图'; }
    if (this.dialogType === 'export_image') { return '保存截图'; }
    if (this.dialogType === 'share_pdf') { return '分享原文件'; }
    if (this.dialogType === 'share_text') { return '分享笔记文字'; }
    return '导出文字';
  }
  private description(): string {
    if (this.dialogType === 'share_image' || this.dialogType === 'share_pdf') {
      return '分享原文件，不含新增笔迹\n通过系统面板选择接收方';
    }
    if (this.dialogType === 'export_original') { return '完整原图，不含新增笔迹'; }
    if (this.dialogType === 'export_image') { return '当前可见页面与笔迹\n不含屏幕外内容与随堂稿纸'; }
    if (this.dialogType === 'share_text') { return '仅正文，不包含图片与笔迹'; }
    return '仅正文，不包含图片与笔迹';
  }
  private confirmLabel(): string {
    if (this.busy) { return '处理中…'; }
    if (this.failed) { return '重试'; }
    return this.dialogType === 'share_pdf' || this.dialogType === 'share_text' || this.dialogType === 'share_image' ? '继续分享' : this.dialogType === 'export_image' ? '保存 PNG' : '选择位置';
  }

  @Builder
  formatOption(value: string, title: string, detail: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
        Text(detail).fontSize(12).fontColor(this.palette().inkSecondary)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.layoutWeight(1).height(64).padding(12).borderRadius(5)
      .backgroundColor(this.extension === value ? this.palette().accentSoft : this.palette().surfaceSubtle)
      .border({ width: 1, color: this.extension === value ? this.palette().accent : this.palette().borderSubtle, radius: 5 })
      .accessibilityText(`导出格式 ${title}`).accessibilityDescription(this.extension === value ? '已选中' : '')
      .enabled(!this.busy).onClick(() => { this.extension = value; })
  }

  build() {
    Column() {
      Column({ space: 16 }) {
        Row({ space: 8 }) {
          AppIcon({ source: this.resultMessage && !this.failed ? $r('app.media.ic_check') : this.dialogType.startsWith('share_') ? $r('app.media.ic_share') : this.dialogType === 'export_image' ? $r('app.media.ic_screenshot') : $r('app.media.ic_export'), iconSize: 22, tint: this.palette().accent })
          Text(this.dialogTitle()).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1)
          IconButton({ icon: $r('app.media.ic_close'), label: '关闭操作弹窗', available: !this.busy, onAction: () => this.onClose() })
        }.width('100%')
        Text(this.documentTitle || this.note.title).fontSize(14).fontColor(this.palette().inkSecondary).maxLines(2).width('100%')
        if (!this.resultMessage || this.failed) {
          if (this.dialogType === 'export_text') {
            Row({ space: 10 }) {
              this.formatOption('.md', 'Markdown', '.md')
              this.formatOption('.txt', '纯文本', '.txt')
            }.width('100%')
          }
          Text(this.description()).fontSize(13).lineHeight(21).fontColor(this.palette().inkSecondary).width('100%')
        }
        if (this.resultMessage) {
          Text(this.resultMessage).fontSize(14).lineHeight(22).fontColor(this.failed ? this.palette().danger : this.palette().inkPrimary)
            .width('100%').padding(12).borderRadius(5).backgroundColor(this.palette().surfaceSubtle)
        }
        if (this.resultMessage && !this.failed) {
          Button('完成').height(48).width('100%').borderRadius(5).backgroundColor(this.palette().accent).fontColor(this.palette().onAccent)
            .onClick(() => this.onClose())
        } else {
          Row({ space: 10 }) {
            Button('取消').height(48).layoutWeight(1).borderRadius(5).enabled(!this.busy).backgroundColor(this.palette().surfaceSubtle)
              .fontColor(this.palette().inkSecondary).onClick(() => this.onClose())
            Button(this.confirmLabel()).height(48).layoutWeight(1).borderRadius(5).enabled(!this.busy).backgroundColor(this.palette().accent)
              .fontColor(this.palette().onAccent).onClick(() => this.onConfirm(this.extension))
          }.width('100%')
        }
      }.width('90%').constraintSize({ maxWidth: 400 }).padding(24).borderRadius(8).backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().borderSubtle }).shadow({ radius: 20, color: 'rgba(0,0,0,0.12)', offsetY: 6 }).onClick(() => {})
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      .backgroundColor('rgba(0,0,0,0.18)').zIndex(250)
      .onClick(() => { if (!this.busy) { this.onClose(); } })
  }
}
