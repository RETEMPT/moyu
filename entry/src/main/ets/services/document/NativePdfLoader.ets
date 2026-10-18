import { taskpool } from '@kit.ArkTS';
import { NativePdfResult, readNativePdf } from './NativePdfTask';

interface PdfJob {
  path: string;
  action: string;
  page: number;
  endPage: number;
  cancelled: () => boolean;
  resolve: (value: NativePdfResult) => void;
  reject: (error: Error) => void;
  timer: number;
  poll: number;
  task: taskpool.Task | null;
  started: boolean;
  finished: boolean;
  holdsSlot: boolean;
}

/**
 * Schedules PDFKit work off the UI thread.
 *
 * A single global promise chain used to make every import, cover, text extraction and both
 * split-screen panes wait for each other. PDFKit instances are independent, so requests are
 * queued per file and at most two files parse concurrently. Requests for a page that has
 * already left the viewport are cancelled before they consume a worker, and a running task
 * is cancelled as soon as its caller is gone.
 */
export class NativePdfLoader {
  private queues: Map<string, PdfJob[]> = new Map();
  private activePaths: Set<string> = new Set();
  private active: number = 0;
  private maxConcurrent: number = 2;
  private timeoutMs: number = 30000;

  run(path: string, action: string, page: number, cancelled: () => boolean, endPage: number = -1): Promise<NativePdfResult> {
    if (cancelled()) { return Promise.reject(new Error('页面已离开')); }
    return new Promise<NativePdfResult>((resolve, reject) => {
      const job: PdfJob = {
        path: path, action: action, page: page, endPage: endPage, cancelled: cancelled, resolve: resolve, reject: reject,
        timer: -1, poll: -1, task: null, started: false, finished: false, holdsSlot: false
      };
      job.timer = setTimeout(() => {
        this.abort(job, new Error('PDF 读取超时，请重试或重新打开资料'));
      }, this.timeoutMs);
      // Cancellation is polled on the host thread because the callback cannot cross into TaskPool.
      this.schedulePoll(job);
      let queue = this.queues.get(path);
      if (queue === undefined) { queue = []; this.queues.set(path, queue); }
      queue.push(job);
      this.pump();
    });
  }

  private schedulePoll(job: PdfJob): void {
    job.poll = setTimeout(() => {
      job.poll = -1;
      if (job.finished) { return; }
      if (job.cancelled()) {
        this.abort(job, new Error('页面已离开'));
        return;
      }
      this.schedulePoll(job);
    }, 100);
  }

  /** Start work only for files that are not already busy, up to the global cap. */
  private pump(): void {
    if (this.active >= this.maxConcurrent) { return; }
    const paths: string[] = [];
    for (const path of this.queues.keys()) { paths.push(path); }
    for (const path of paths) {
      if (this.active >= this.maxConcurrent) { return; }
      if (this.activePaths.has(path)) { continue; }
      const queue = this.queues.get(path);
      if (queue === undefined || queue.length === 0) { this.queues.delete(path); continue; }
      let job: PdfJob | null = null;
      while (queue.length > 0) {
        const candidate = queue.shift();
        if (candidate === undefined || candidate.finished) { continue; }
        if (candidate.cancelled()) { this.abort(candidate, new Error('页面已离开')); continue; }
        job = candidate; break;
      }
      if (job === null) { this.queues.delete(path); continue; }
      this.start(path, job);
    }
  }

  private start(path: string, job: PdfJob): void {
    job.started = true;
    job.holdsSlot = true;
    this.activePaths.add(path);
    this.active++;
    let task: taskpool.Task | null = null;
    try {
      task = new taskpool.Task('pdf_' + job.action, readNativePdf, job.path, job.action, job.page, job.endPage);
    } catch { task = null; }
    job.task = task;
    let execution: Promise<Object>;
    try {
      execution = task !== null ? taskpool.execute(task) :
        taskpool.execute(readNativePdf, job.path, job.action, job.page, job.endPage);
    } catch (error) {
      this.releaseSlot(job);
      this.fail(job, error instanceof Error ? error : new Error('PDF 读取失败，请重试'));
      return;
    }
    execution.then((value: Object) => {
      this.finish(job, value as NativePdfResult);
    }).catch((error: Object) => {
      this.releaseSlot(job);
      this.fail(job, error instanceof Error ? error : new Error('PDF 读取失败，请重试'));
    });
  }

  private finish(job: PdfJob, result: NativePdfResult): void {
    if (job.finished) {
      if (result.pixelMap !== undefined) { result.pixelMap.release().catch(() => {}); }
      this.releaseSlot(job);
      return;
    }
    if (job.cancelled()) {
      if (result.pixelMap !== undefined) { result.pixelMap.release().catch(() => {}); }
      job.finished = true;
      this.clearTimers(job);
      this.releaseSlot(job);
      job.reject(new Error('页面已离开'));
      return;
    }
    job.finished = true;
    this.clearTimers(job);
    this.releaseSlot(job);
    job.resolve(result);
  }

  /**
   * Reject one request immediately. A native call that already started keeps its path slot until
   * it actually settles, so a cancelled/timeout page can never run concurrently with its retry;
   * queued requests that have not started release nothing and are simply dropped.
   */
  private abort(job: PdfJob, error: Error): void {
    if (job.finished) { return; }
    job.finished = true;
    this.clearTimers(job);
    const queue = this.queues.get(job.path);
    if (queue !== undefined) {
      const index = queue.indexOf(job);
      if (index >= 0) { queue.splice(index, 1); }
      if (queue.length === 0) { this.queues.delete(job.path); }
    }
    const task = job.task;
    if (task !== null && job.started) {
      try { taskpool.cancel(task); } catch { /* Task already settled. */ }
    }
    if (!job.started) { this.releaseSlot(job); }
    job.reject(error);
  }

  private fail(job: PdfJob, error: Error): void {
    if (job.finished) { return; }
    job.finished = true;
    this.clearTimers(job);
    this.releaseSlot(job);
    job.reject(error);
  }

  private clearTimers(job: PdfJob): void {
    if (job.timer !== -1) { clearTimeout(job.timer); job.timer = -1; }
    if (job.poll !== -1) { clearTimeout(job.poll); job.poll = -1; }
  }

  private releaseSlot(job: PdfJob): void {
    if (!job.holdsSlot) { return; }
    job.holdsSlot = false;
    this.active = Math.max(0, this.active - 1);
    this.activePaths.delete(job.path);
    this.pump();
  }
}
