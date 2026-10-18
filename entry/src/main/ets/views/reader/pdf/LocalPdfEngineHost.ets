import { webview } from '@kit.ArkWeb';
import { LocalPdfEngine } from '../../../services/document/LocalPdfEngine';

const PDF_SCHEME = 'moyu';
const PDF_ORIGIN = PDF_SCHEME + '://local/';
let schemeRegistered: boolean = false;

class PdfNativeBridge {
  async read(token: string, begin: number, end: number): Promise<string> { return await LocalPdfEngine.getInstance().read(token, begin, end); }
  ready(): boolean { LocalPdfEngine.getInstance().markReady(); return true; }
  finish(id: string, result: string): void { LocalPdfEngine.getInstance().finish(id, result); }
}

/** Single local, non-interactive engine. Its bridge can read only registered document ranges. */
@Component
export struct LocalPdfEngineHost {
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: PdfNativeBridge = new PdfNativeBridge();

  private registerScheme(): void {
    if (schemeRegistered) { return; }
    // A rawfile document has an opaque origin, so ESM imports and fetch() fail CORS.
    // A standard, secure custom scheme gives the engine a real same-origin URL.
    webview.WebviewController.customizeSchemes([{
      schemeName: PDF_SCHEME,
      isSupportCORS: true,
      isSupportFetch: true,
      isStandard: true,
      isSecure: true
    }]);
    schemeRegistered = true;
  }

  private mimeType(path: string): string {
    if (path.endsWith('.mjs') || path.endsWith('.js')) { return 'text/javascript'; }
    if (path.endsWith('.html')) { return 'text/html'; }
    if (path.endsWith('.wasm')) { return 'application/wasm'; }
    return 'application/octet-stream';
  }

  private serve(url: string): WebResourceResponse {
    const path = url.substring(PDF_ORIGIN.length);
    const response = new WebResourceResponse();
    response.setResponseIsReady(false);
    this.fillResponse(path, response);
    return response;
  }

  private async fillResponse(path: string, response: WebResourceResponse): Promise<void> {
    try {
      const content = await getContext(this).resourceManager.getRawFileContent(path);
      response.setResponseData(content.buffer.slice(content.byteOffset, content.byteOffset + content.byteLength));
      response.setResponseCode(200);
      response.setResponseMimeType(this.mimeType(path));
      const headers: Array<Header> = [{ headerKey: 'Access-Control-Allow-Origin', headerValue: '*' }];
      response.setResponseHeader(headers);
    } catch {
      response.setResponseCode(404);
    } finally { response.setResponseIsReady(true); }
  }

  aboutToAppear(): void {
    this.registerScheme();
    LocalPdfEngine.getInstance().attach({ execute: (script: string): Promise<string> => this.controller.runJavaScript(script) });
  }
  aboutToDisappear(): void { LocalPdfEngine.getInstance().detach(); }
  build() {
    Web({ src: PDF_ORIGIN + 'offline-pdf/host.html', controller: this.controller })
      .javaScriptAccess(true).domStorageAccess(false).fileAccess(false).blockNetwork(true)
      .javaScriptProxy({ object: this.bridge, name: 'nativePdf', methodList: ['ready', 'finish'], asyncMethodList: ['read'], controller: this.controller })
      .onInterceptRequest((event: OnInterceptRequestEvent): WebResourceResponse => {
        const url = event.request.getRequestUrl();
        if (url.startsWith(PDF_ORIGIN)) { return this.serve(url); }
        const blocked = new WebResourceResponse();
        blocked.setResponseCode(404);
        return blocked;
      })
      // A reloaded page has a new JS context: earlier executions can no longer report back.
      .onPageBegin(() => { LocalPdfEngine.getInstance().reloaded(); })
      .width(1).height(1).opacity(0.01).hitTestBehavior(HitTestMode.None)
  }
}
