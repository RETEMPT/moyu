import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { taskpool, util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';

export interface PdfEnginePort { execute: (script: string) => Promise<string>; }
export interface LocalPdfResult {
  pageCount?: number;
  width?: number;
  height?: number;
  data?: string;
  text?: string;
  error?: string;
  /** Machine-readable cause from the host; keep the reader text stable across locales. */
  errorKind?: string;
}
export interface LocalPdfBitmap { pixelMap: image.PixelMap; aspectRatio: number; }
export type PdfFailureKind = 'missing' | 'password' | 'damaged' | 'engine' | 'other';
interface PdfPending {
  resolve: (value: LocalPdfResult) => void;
  reject: (error: Error) => void;
  timer: number;
  poll: number;
}
interface PdfSource { token: string; path: string; length: number; modified: number; }
interface PdfEngineRequest { id: string; token: string; length: number; action: string; page: number; }

const MISSING_MESSAGE = 'PDF 原文件不存在或不可读，请重新关联原 PDF。';
const PASSWORD_MESSAGE = '此 PDF 需要密码，请先解锁后再导入';
const DAMAGED_MESSAGE = 'PDF 内容损坏或格式不受支持';
const ENGINE_MESSAGE = '离线阅读组件未就绪，请重试';
const READ_MESSAGE = 'PDF 原文件读取失败，请确认文件仍在原位';
const PAGE_MESSAGE = 'PDF 页码超出范围';
const CHANGED_MESSAGE = 'PDF 原文件已被更改，请重新打开该资料';
const RANGE_LIMIT = 128 * 1024;

@Concurrent
export function parsePdfReply(json: string): LocalPdfResult {
  return JSON.parse(json) as LocalPdfResult;
}

/** Reader-facing classification. Only a missing original may offer re-linking. */
export function pdfFailureKind(message: string): PdfFailureKind {
  if (message.indexOf('离线阅读组件') >= 0 || message.indexOf('PDF 阅读组件') >= 0 ||
    message.indexOf('未就绪') >= 0 || message.indexOf('阅读组件连接失败') >= 0) {
    return 'engine';
  }
  if (message.indexOf('密码') >= 0) { return 'password'; }
  if (message.indexOf('损坏') >= 0 || message.indexOf('格式不受支持') >= 0) { return 'damaged'; }
  if (message.indexOf('原文件不存在') >= 0 || message.indexOf('缺少 PDF 原文件') >= 0 ||
    message.indexOf('重新关联') >= 0) {
    return 'missing';
  }
  return 'other';
}

/** One offline web engine; bounded range reads never base64-encode the whole textbook. */
export class LocalPdfEngine {
  private static instance: LocalPdfEngine = new LocalPdfEngine();
  static getInstance(): LocalPdfEngine { return LocalPdfEngine.instance; }
  private directory: string = '';
  private port: PdfEnginePort | null = null;
  private ready: boolean = false;
  private sequence: number = 0;
  private sources: Map<string, PdfSource> = new Map();
  private pending: Map<string, PdfPending> = new Map();
  private tail: Promise<void> = Promise.resolve();
  private readBytes: number = 0;
  private readCount: number = 0;
  private requestTimeoutMs: number = 60000;
  private readyPollMs: number = 100;
  private readyAttempts: number = 150;

  bindContext(context: Context): void {
    const directory = context.filesDir + '/documents/';
    if (directory !== this.directory) { this.sources.clear(); }
    this.directory = directory;
  }
  attach(port: PdfEnginePort): void {
    if (this.port !== null && this.port !== port) { this.failPending('阅读组件已重新加载，请重试'); }
    this.port = port;
    this.ready = false;
  }
  markReady(): void { this.ready = true; }
  /** The web page restarted: every earlier execution belonged to the destroyed context. */
  reloaded(): void {
    this.ready = false;
    this.failPending('阅读组件已重新加载，请重试');
  }
  detach(): void {
    this.ready = false;
    this.port = null;
    this.failPending('阅读组件已关闭，请重试');
    this.sources.clear();
  }
  private failPending(reason: string): void {
    for (const item of this.pending.values()) {
      clearTimeout(item.timer);
      clearInterval(item.poll);
      item.reject(new Error(reason));
    }
    this.pending.clear();
  }
  finish(id: string, json: string): void {
    this.acceptReply(id, json);
  }
  private async acceptReply(id: string, json: string): Promise<void> {
    const item = this.pending.get(id);
    if (!item) { return; }
    try {
      if (json.length > 12 * 1024 * 1024) { throw new Error('页面图像过大，请降低显示尺寸'); }
      const result = json.length > 65536 ? await taskpool.execute(parsePdfReply, json) as LocalPdfResult : parsePdfReply(json);
      // Cancellation or a rebuilt host may have invalidated this reply while it was decoded.
      if (this.pending.get(id) !== item) { return; }
      this.pending.delete(id); clearTimeout(item.timer); clearInterval(item.poll);
      if (result.error) {
        item.reject(new Error(this.failureMessage(result.errorKind, result.error)));
      } else {
        item.resolve(result);
      }
    } catch (error) {
      if (this.pending.get(id) !== item) { return; }
      this.pending.delete(id); clearTimeout(item.timer); clearInterval(item.poll);
      item.reject(error instanceof Error ? error : new Error('阅读结果无效'));
    }
  }
  private failureMessage(kind: string | undefined, fallback: string): string {
    if (kind === 'password') { return PASSWORD_MESSAGE; }
    if (kind === 'damaged') { return DAMAGED_MESSAGE; }
    if (kind === 'missing') { return MISSING_MESSAGE; }
    if (kind === 'engine') { return ENGINE_MESSAGE; }
    if (kind === 'read') { return READ_MESSAGE; }
    if (kind === 'page') { return PAGE_MESSAGE; }
    return fallback.length > 0 ? fallback.slice(0, 240) : 'PDF 读取失败';
  }
  async read(token: string, begin: number, end: number): Promise<string> {
    const source = this.sources.get(token);
    if (!source) { throw new Error(MISSING_MESSAGE); }
    if (!Number.isInteger(begin) || !Number.isInteger(end) || begin < 0 || end <= begin ||
      end > source.length || end - begin > RANGE_LIMIT) {
      throw new Error('文档读取范围无效');
    }
    let size = 0;
    let modified = 0;
    try {
      const stat = await fs.stat(source.path);
      size = stat.size; modified = stat.mtime === undefined ? 0 : stat.mtime;
    } catch { throw new Error(MISSING_MESSAGE); }
    if (size <= 0) { throw new Error(MISSING_MESSAGE); }
    if (size !== source.length || modified !== source.modified) { throw new Error(CHANGED_MESSAGE); }
    let handle: fs.File | null = null;
    try {
      handle = await fs.open(source.path, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(end - begin);
      const count = await fs.read(handle.fd, buffer, { offset: begin, length: end - begin });
      if (count !== end - begin) { throw new Error(READ_MESSAGE); }
      this.readBytes += count;
      this.readCount++;
      return await new util.Base64Helper().encodeToString(new Uint8Array(buffer));
    } catch (error) {
      if (error instanceof Error && (error.message === READ_MESSAGE || error.message === CHANGED_MESSAGE)) {
        throw error;
      }
      throw new Error(READ_MESSAGE);
    } finally {
      if (handle !== null) { await fs.close(handle); }
    }
  }
  statistics(): number { return this.readBytes; }
  readOperations(): number { return this.readCount; }

  private source(path: string): PdfSource {
    if (!this.directory || !path.startsWith(this.directory)) { throw new Error('PDF 需先保存到本机资料库'); }
    const name = path.substring(this.directory.length);
    if (!name || /[\\/\u0000-\u001f]/.test(name)) { throw new Error('原文件路径无效'); }
    let length = 0;
    let modified = 0;
    try {
      const stat = fs.statSync(path);
      length = stat.size;
      modified = stat.mtime === undefined ? 0 : stat.mtime;
    } catch { throw new Error(MISSING_MESSAGE); }
    if (!length || length > 1024 * 1024 * 1024) { throw new Error('PDF 为空或超过 1 GB'); }
    for (const item of this.sources.values()) {
      if (item.path !== path) { continue; }
      if (item.length === length && item.modified === modified) { return item; }
      // The file was replaced or rewritten: the old host document no longer matches these bytes.
      this.sources.delete(item.token);
      break;
    }
    const result: PdfSource = { token: 'local_' + (++this.sequence), path: path, length: length, modified: modified };
    this.sources.set(result.token, result);
    return result;
  }

  private post(script: string): void {
    const port = this.port;
    if (port === null) { return; }
    try { port.execute(script).catch(() => {}); } catch { /* Host already gone. */ }
  }

  private async waitForReady(cancelled: () => boolean): Promise<void> {
    for (let attempt = 0; !this.ready && attempt < this.readyAttempts; attempt++) {
      if (cancelled()) { throw new Error('页面已离开'); }
      await new Promise<void>((resolve) => setTimeout(resolve, this.readyPollMs));
    }
  }

  private request(path: string, action: string, page: number, cancelled: () => boolean): Promise<LocalPdfResult> {
    const running = this.tail.then(async (): Promise<LocalPdfResult> => {
      if (cancelled()) { throw new Error('页面已离开'); }
      await this.waitForReady(cancelled);
      const port = this.port;
      if (!this.ready || port === null) { throw new Error(ENGINE_MESSAGE); }
      if (cancelled()) { throw new Error('页面已离开'); }
      const source = this.source(path);
      const id = 'pdf_' + (++this.sequence);
      const payload: PdfEngineRequest = { id: id, token: source.token, length: source.length, action: action, page: page };
      return await new Promise<LocalPdfResult>((resolve, reject) => {
        const timer = setTimeout(() => {
          if (!this.pending.has(id)) { return; }
          this.pending.delete(id);
          clearInterval(poll);
          reject(new Error('页面读取超时，可重试或打开其他资料'));
          this.post('window.moyuPdf.cancel(' + JSON.stringify(id) + ');');
        }, this.requestTimeoutMs);
        // A page that left the viewport must free the host render now, not after the timeout.
        const poll = setInterval(() => {
          if (!cancelled() || !this.pending.has(id)) { return; }
          this.pending.delete(id);
          clearTimeout(timer);
          clearInterval(poll);
          reject(new Error('页面已离开'));
          this.post('window.moyuPdf.cancel(' + JSON.stringify(id) + ');');
        }, 200);
        this.pending.set(id, { resolve: resolve, reject: reject, timer: timer, poll: poll });
        try {
          port.execute('window.moyuPdf.request(' + JSON.stringify(payload) + '); "queued";').catch(() => {
            const item = this.pending.get(id);
            if (item) {
              clearTimeout(item.timer);
              clearInterval(item.poll);
              this.pending.delete(id);
              item.reject(new Error('阅读组件连接失败，请重试'));
            }
          });
        } catch {
          if (this.pending.has(id)) {
            clearTimeout(timer);
            clearInterval(poll);
            this.pending.delete(id);
            reject(new Error('阅读组件连接失败，请重试'));
          }
        }
      });
    });
    this.tail = running.then(() => {}, () => {});
    return running;
  }
  async inspect(path: string, cancelled: () => boolean = () => false): Promise<LocalPdfResult> {
    return await this.request(path, 'info', 0, cancelled);
  }
  async text(path: string, page: number, cancelled: () => boolean): Promise<string> {
    return (await this.request(path, 'text', page, cancelled)).text || '';
  }
  async render(path: string, page: number, cancelled: () => boolean = () => false): Promise<LocalPdfBitmap> {
    const result = await this.request(path, 'page', page, cancelled);
    if (cancelled()) { throw new Error('页面已离开'); }
    if (!result.data || result.data.length > 12 * 1024 * 1024) { throw new Error('页面图像无效'); }
    const bytes = await new util.Base64Helper().decode(result.data);
    if (cancelled()) { throw new Error('页面已离开'); }
    const decoder = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    try {
      const pixels = await decoder.createPixelMap();
      if (cancelled()) { await pixels.release(); throw new Error('页面已离开'); }
      return { pixelMap: pixels, aspectRatio: (result.width || 1) / (result.height || 1) };
    }
    finally { await decoder.release(); }
  }
}
