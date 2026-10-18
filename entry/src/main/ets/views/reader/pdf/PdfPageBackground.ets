import { image } from '@kit.ImageKit';
import { PdfDocumentService } from '../../../services/document/PdfDocumentService';
import { ImageDocumentService } from '../../../services/document/ImageDocumentService';
import { pdfFailureKind, PdfFailureKind } from '../../../services/document/LocalPdfEngine';

/** 只保留可见页的位图，离开视口即释放，控制手机端内存。 */
@Component
export struct PdfPageBackground {
  @Prop @Watch('reload') sourceUri: string = '';
  @Prop @Watch('reload') sourceType: string = 'pdf';
  @Prop @Watch('reload') pageIndex: number = 0;
  onAspectRatio: (ratio: number) => void = () => {};
  onSourceReady: (ready: boolean) => void = () => {};
  onRestoreSource: () => void = () => {};
  @State private bitmap: image.PixelMap | undefined = undefined;
  @State private errorMessage: string = '';
  @State private failure: PdfFailureKind = 'other';
  private visible: boolean = false;
  private requestId: number = 0;
  private loading: boolean = false;
  private bitmapSource: string = '';
  private bitmapSourceType: string = '';
  private bitmapPage: number = -1;
  private bitmapRatio: number = 0.707;

  aboutToDisappear(): void {
    this.visible = false;
    this.releaseBitmap(false);
  }

  /** Only a missing original can be repaired by picking the file again. */
  private canRestore(): boolean {
    return this.sourceType !== 'image' && this.failure === 'missing';
  }

  /**
   * Release ownership. Scrolling away or switching the source hands the bitmap back to the
   * service cache, so returning to the page can paint without parsing the PDF again.
   */
  private releaseBitmap(cache: boolean = false): void {
    this.requestId++;
    this.loading = false;
    const previous = this.bitmap;
    const source = this.bitmapSource;
    const sourceType = this.bitmapSourceType;
    const page = this.bitmapPage;
    const ratio = this.bitmapRatio;
    this.bitmap = undefined;
    this.bitmapSource = ''; this.bitmapSourceType = ''; this.bitmapPage = -1; this.bitmapRatio = 0.707;
    this.onSourceReady(false);
    if (previous === undefined) { return; }
    if (cache && sourceType === 'pdf' && source.length > 0 && page >= 0 &&
      PdfDocumentService.getInstance().recyclePage(source, page, previous, ratio)) {
      return;
    }
    previous.release().catch(() => {});
  }

  private reload(): void {
    // Keep the outgoing page when only the page/source changed. A replaced original has a new
    // managed path, so its stale cache entry is evicted by removeManagedPdf instead.
    this.releaseBitmap(true);
    this.errorMessage = '';
    this.failure = 'other';
    if (this.visible) { this.loadPage(); }
  }

  private async loadPage(): Promise<void> {
    if (this.bitmap !== undefined || this.loading || this.errorMessage.length > 0) { return; }
    if (this.sourceUri.length === 0) {
      this.failure = 'missing';
      this.errorMessage = this.sourceType === 'image' ? '图片原件不可用，请重新导入。已保存的笔迹仍保留。' : '这份资料缺少 PDF 原文件。关联原文件后可恢复阅读，已保存的批注会保留。';
      this.onSourceReady(false);
      return;
    }
    if (this.sourceType === 'image') { await this.loadImage(); return; }
    const request = ++this.requestId;
    this.loading = true;
    try {
      const rendered = await PdfDocumentService.getInstance().renderPageAsync(this.sourceUri, this.pageIndex, () => request !== this.requestId || !this.visible);
      if (request !== this.requestId || !this.visible) { await rendered.pixelMap.release(); return; }
      if (this.bitmap !== undefined) { await rendered.pixelMap.release(); return; }
      this.bitmap = rendered.pixelMap;
      this.bitmapSource = this.sourceUri; this.bitmapSourceType = 'pdf'; this.bitmapPage = this.pageIndex; this.bitmapRatio = rendered.aspectRatio;
      this.failure = 'other';
      this.errorMessage = '';
      try { this.onAspectRatio(rendered.aspectRatio); this.onSourceReady(true); } catch { /* A host callback must not leak the bitmap. */ }
    } catch (error) {
      if (request !== this.requestId || !this.visible) { return; }
      const message: string = error instanceof Error ? error.message : '页面读取失败，请确认文件可读且设备支持 PDFKit。';
      this.errorMessage = message;
      this.failure = pdfFailureKind(message);
      this.onSourceReady(false);
    } finally { if (request === this.requestId) { this.loading = false; } }
  }

  private async loadImage(): Promise<void> {
    const request = ++this.requestId;
    this.loading = true;
    try {
      const preview = await ImageDocumentService.preview(this.getUIContext().getHostContext() as Context, this.sourceUri);
      if (request !== this.requestId || !this.visible) { await preview.pixels.release(); return; }
      if (this.bitmap !== undefined) { await preview.pixels.release(); return; }
      this.bitmap = preview.pixels;
      this.bitmapSource = this.sourceUri; this.bitmapSourceType = 'image'; this.bitmapPage = 0; this.bitmapRatio = preview.info.width / preview.info.height;
      this.failure = 'other';
      this.errorMessage = '';
      try { this.onAspectRatio(preview.info.width / preview.info.height); this.onSourceReady(true); } catch { /* A host callback must not leak the bitmap. */ }
    } catch (error) {
      if (request !== this.requestId || !this.visible) { return; }
      // Image errors are never repairable by re-linking a PDF; keep only the retry action.
      this.errorMessage = error instanceof Error ? error.message : '图片读取失败，请重试';
      this.failure = 'other';
      this.onSourceReady(false);
    } finally { if (request === this.requestId) { this.loading = false; } }
  }

  build() {
    Column({ space: 12 }) {
      if (this.bitmap !== undefined) {
        Image(this.bitmap).width('100%').height('100%').objectFit(ImageFit.Fill).hitTestBehavior(HitTestMode.None)
      } else if (this.errorMessage.length > 0) {
        Text(this.errorMessage).fontSize(14).fontColor('#57534E').padding(16)
          .constraintSize({ maxWidth: 560 }).textAlign(TextAlign.Center)
        if (this.canRestore()) {
          Button('重新关联原 PDF').height(44).onClick(() => this.onRestoreSource())
        }
        if (this.sourceUri.length > 0) {
          Button('重试读取').height(44).type(ButtonType.Normal).backgroundColor('#F3F4F6')
            .fontColor('#374151').onClick(() => this.reload())
        }
      } else {
        LoadingProgress().width(40).height(40)
        Text(this.sourceType === 'image' ? '正在读取图片…' : '正在读取 PDF 原页…').fontSize(14).fontColor('#57534E')
      }
    }.width('100%').height('100%').justifyContent(this.bitmap !== undefined ? FlexAlign.Center : FlexAlign.Start)
      .padding({ top: this.bitmap !== undefined ? 0 : 48 }).backgroundColor(Color.White)
      .onVisibleAreaChange([0], (visible: boolean) => {
        this.visible = visible;
        if (visible) { this.loadPage(); } else { this.releaseBitmap(true); }
      })
  }
}
