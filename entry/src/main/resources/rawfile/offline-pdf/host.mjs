import {getDocument, GlobalWorkerOptions, PDFDataRangeTransport} from './pdf.mjs';

GlobalWorkerOptions.workerSrc = new URL('./pdf.worker.mjs', import.meta.url).href;

const CACHE_LIMIT = 2;
const RANGE_LIMIT = 8 * 1024 * 1024;
const IDLE_RELEASE_MS = 20000;
const MESSAGES = {
  password: '此 PDF 需要密码，请先解锁后再导入',
  damaged: 'PDF 内容损坏或格式不受支持',
  missing: 'PDF 原文件不存在或不可读，请重新关联原 PDF。',
  read: 'PDF 原文件读取失败，请确认文件仍在原位',
  page: 'PDF 页码超出范围',
  other: 'PDF 页面读取失败，请重试'
};

// token:length -> {task, transport, promise}; at most CACHE_LIMIT idle documents stay parsed.
const documents = new Map();
const loading = new Map();
const inUse = new Map();
const requests = new Map();
let idleTimer = 0;

class NativeRanges extends PDFDataRangeTransport {
  constructor(token, length, onFailure) {
    super(length, null, true);
    this.token = token;
    this.stopped = false;
    this.failure = '';
    this.onFailure = onFailure;
  }
  requestDataRange(begin, end) {
    Promise.resolve().then(async () => {
      if (this.stopped) { return; }
      const size = end - begin;
      if (!Number.isInteger(begin) || !Number.isInteger(end) || begin < 0 || size <= 0 ||
        end > this.length || size > RANGE_LIMIT) {
        throw new Error('PDF 读取范围无效');
      }
      const result = new Uint8Array(size);
      for (let offset = begin; offset < end; offset += 131072) {
        if (this.stopped) { return; }
        const text = await nativePdf.read(this.token, offset, Math.min(end, offset + 131072));
        if (this.stopped) { return; }
        const decoded = atob(text);
        for (let i = 0; i < decoded.length; i++) { result[offset - begin + i] = decoded.charCodeAt(i); }
        // Yield between native reads so a cancelled page stops asking for further ranges.
        await new Promise(resolve => setTimeout(resolve, 0));
      }
      if (!this.stopped) { this.onDataRange(begin, result); }
    }).catch(error => {
      if (this.stopped) { return; }
      this.stopped = true;
      this.failure = error && error.message ? error.message : 'PDF 原文件读取失败';
      // Destroying the loading task rejects every reader still waiting on this range.
      this.onFailure(this.failure);
    });
  }
  abort() { this.stopped = true; }
}

function errorKind(error, transport) {
  if (transport && transport.failure) { return 'read'; }
  const name = error && error.name;
  if (name === 'PasswordException') { return 'password'; }
  if (name === 'InvalidPDFException') { return 'damaged'; }
  if (name === 'MissingPDFException') { return 'missing'; }
  const message = error && error.message ? error.message : '';
  if (message.indexOf('Invalid page') >= 0 || message.indexOf('页码') >= 0) { return 'page'; }
  return 'other';
}

function reply(id, payload) { nativePdf.finish(id, JSON.stringify(payload)); }

function replyError(id, kind, transport) {
  const message = transport && transport.failure ? MESSAGES.read : MESSAGES[kind];
  reply(id, {error: message, errorKind: kind});
}

function retire(key) {
  const entry = documents.get(key);
  if (!entry) { return Promise.resolve(); }
  documents.delete(key);
  try { entry.transport.abort(); } catch { /* Already stopped. */ }
  return entry.task.destroy().catch(() => {});
}

async function retireOldest() {
  while (documents.size >= CACHE_LIMIT) {
    let victim = null;
    for (const key of documents.keys()) {
      if (!inUse.get(key)) { victim = key; break; }
    }
    // Every cached document is still rendering: let the new one in temporarily.
    if (victim === null) { return; }
    await retire(victim);
  }
}

function scheduleIdleRelease() {
  if (idleTimer) { clearTimeout(idleTimer); }
  idleTimer = setTimeout(() => {
    idleTimer = 0;
    for (const key of [...documents.keys()]) {
      if (!inUse.get(key)) { retire(key); }
    }
  }, IDLE_RELEASE_MS);
}

async function createDocument(request, key) {
  await retireOldest();
  let transport = null;
  const onFailure = () => {
    const entry = documents.get(key);
    if (entry && entry.transport === transport) { retire(key); }
  };
  transport = new NativeRanges(request.token, request.length, onFailure);
  const task = getDocument({
    range: transport, length: request.length,
    disableAutoFetch: true, disableStream: true, rangeChunkSize: 65536, isEvalSupported: false,
    useWorkerFetch: false, cMapUrl: new URL('./cmaps/', import.meta.url).href, cMapPacked: true,
    standardFontDataUrl: new URL('./standard_fonts/', import.meta.url).href,
    wasmUrl: new URL('./wasm/', import.meta.url).href, iccUrl: new URL('./iccs/', import.meta.url).href,
    enableXfa: false, maxImageSize: 24000000, canvasMaxAreaInBytes: 16000000
  });
  const entry = {task: task, transport: transport, promise: task.promise};
  documents.set(key, entry);
  task.promise.catch(() => {
    if (documents.get(key) === entry) { documents.delete(key); }
  });
  return task.promise;
}

async function documentFor(request, key) {
  const existing = documents.get(key);
  if (existing) {
    documents.delete(key);
    documents.set(key, existing);
    return existing.promise;
  }
  const pending = loading.get(key);
  if (pending) { return await pending; }
  const creating = createDocument(request, key);
  loading.set(key, creating);
  try { return await creating; } finally { if (loading.get(key) === creating) { loading.delete(key); } }
}

function acquire(key) { inUse.set(key, (inUse.get(key) || 0) + 1); }
function release(key) {
  const left = (inUse.get(key) || 1) - 1;
  if (left <= 0) { inUse.delete(key); } else { inUse.set(key, left); }
}

window.moyuPdf = {
  async request(request) {
    const id = request.id;
    const key = request.token + ':' + request.length;
    const state = {cancelled: false, renderTask: null};
    requests.set(id, state);
    acquire(key);
    scheduleIdleRelease();
    let transport = null;
    try {
      const doc = await documentFor(request, key);
      const cached = documents.get(key);
      transport = cached ? cached.transport : null;
      if (state.cancelled) { return; }
      if (request.action === 'info') {
        reply(id, {pageCount: doc.numPages});
        return;
      }
      if (!Number.isInteger(request.page) || request.page < 0 || request.page >= doc.numPages) {
        replyError(id, 'page', null);
        return;
      }
      const page = await doc.getPage(request.page + 1);
      try {
        if (request.action === 'text') {
          const content = await page.getTextContent();
          let text = '';
          for (const item of content.items) {
            text += (item.str || '') + (item.hasEOL ? '\n' : ' ');
            if (text.length > 80000) { throw new Error('此页文字过多，请缩小提取范围'); }
          }
          if (!state.cancelled) { reply(id, {text: text}); }
          return;
        }
        const original = page.getViewport({scale: 1});
        const scale = Math.min(960 / original.width, 1440 / original.height,
          Math.sqrt(1382400 / (original.width * original.height)));
        const viewport = page.getViewport({scale: scale});
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.ceil(viewport.width));
        canvas.height = Math.max(1, Math.ceil(viewport.height));
        try {
          const context = canvas.getContext('2d', {alpha: false});
          if (!context) { throw new Error('无法创建页面画布'); }
          const renderTask = page.render({canvas: canvas, canvasContext: context, viewport: viewport, background: '#ffffff'});
          state.renderTask = renderTask;
          await renderTask.promise;
          if (state.cancelled) { return; }
          const data = canvas.toDataURL('image/jpeg', 0.85).split(',')[1];
          reply(id, {width: original.width, height: original.height, data: data});
        } finally {
          canvas.width = 0;
          canvas.height = 0;
        }
      } finally {
        page.cleanup();
      }
    } catch (error) {
      if (state.cancelled) { return; }
      const kind = errorKind(error, transport);
      replyError(id, kind, kind === 'read' ? transport : null);
    } finally {
      requests.delete(id);
      release(key);
      if (documents.size > 0) { scheduleIdleRelease(); }
    }
  },
  cancel(id) {
    const state = requests.get(id);
    if (!state) { return; }
    state.cancelled = true;
    try { state.renderTask?.cancel(); } catch { /* Render already finished. */ }
  }
};

// ArkWeb injects the JavaScriptProxy object after the page starts; a module script cannot
// assume it exists on its last line, so poll briefly instead of failing to announce readiness.
let readyDelay = 50;
function announceReady() {
  try {
    // ArkWeb can expose a proxy before the native object is bound. Only the actual
    // native acknowledgement means callers can use it; a failed probe must retry.
    if (typeof nativePdf !== 'undefined' && nativePdf.ready() === true) { return; }
  } catch { /* Proxy registration is still in progress. */ }
  setTimeout(announceReady, readyDelay);
  readyDelay = Math.min(500, readyDelay * 2);
}
announceReady();
