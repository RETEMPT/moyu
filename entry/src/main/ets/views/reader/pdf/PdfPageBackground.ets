import { image } from '@kit.ImageKit';
import { PdfDocumentService } from '../../../services/document/PdfDocumentService';

/** 只保留可见页的位图，离开视口即释放，控制手机端内存。 */
@Component
export struct PdfPageBackground {
  @Prop @Watch('reload') sourceUri: string = '';
  @Prop @Watch('reload') pageIndex: number = 0;
  onAspectRatio: (ratio: number) => void = () => {};
  @State private bitmap: image.PixelMap | undefined = undefined;
  @State private errorMessage: string = '';
  private visible: boolean = false;

  aboutToDisappear(): void {
    this.visible = false;
    this.releaseBitmap();
  }

  private releaseBitmap(): void {
    const previous = this.bitmap;
    this.bitmap = undefined;
    if (previous !== undefined) { previous.release().catch(() => {}); }
  }

  private reload(): void {
    this.releaseBitmap();
    this.errorMessage = '';
    if (this.visible) { this.loadPage(); }
  }

  private loadPage(): void {
    if (this.bitmap !== undefined || this.errorMessage.length > 0) { return; }
    if (this.sourceUri.length === 0) {
      this.errorMessage = '这份资料缺少 PDF 原文件，请重新导入。';
      return;
    }
    try {
      const rendered = PdfDocumentService.getInstance().renderPage(this.sourceUri, this.pageIndex);
      this.bitmap = rendered.pixelMap;
      this.onAspectRatio(rendered.aspectRatio);
    } catch {
      this.errorMessage = '页面读取失败，请确认文件可读且设备支持 PDFKit。';
    }
  }

  build() {
    Column({ space: 12 }) {
      if (this.bitmap !== undefined) {
        Image(this.bitmap).width('100%').height('100%').objectFit(ImageFit.Fill).hitTestBehavior(HitTestMode.None)
      } else if (this.errorMessage.length > 0) {
        Text(this.errorMessage).fontSize(14).fontColor('#57534E').padding(16)
        Button('重试读取').height(44).onClick(() => this.reload())
      } else {
        LoadingProgress().width(40).height(40)
        Text('正在读取 PDF 原页…').fontSize(14).fontColor('#57534E')
      }
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor(Color.White)
      .onVisibleAreaChange([0], (visible: boolean) => {
        this.visible = visible;
        if (visible) { this.loadPage(); } else { this.releaseBitmap(); }
      })
  }
}
