import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { resolveTypeScript } from './resolve-typescript.mjs';

// Exercise actual storage / PDF / input lifecycle methods with native adapters mocked.
// Native PDFKit rendering, ArkUI hit testing and stylus latency still require a device.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ts = resolveTypeScript();
const base = 'entry/src/main/ets/';
const pdfFile = `${base}services/document/PdfDocumentService.ets`;
const canvasFile = `${base}views/reader/pdf/PdfPageCanvas.ets`;
const annotatorFile = `${base}views/reader/pdf/PdfAnnotatorView.ets`;
const backgroundFile = `${base}views/reader/pdf/PdfPageBackground.ets`;
const fixture = fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/example-course.pdf'));
const plain = value => JSON.parse(JSON.stringify(value));
const { PdfAnnotationPolicy } = load(`${base}services/document/PdfAnnotationPolicy.ets`, {});
const { InkShapePolicy } = load(`${base}services/ink/InkShapePolicy.ets`, {});

function load(relative, mocks, cache = new Map()) {
  const filename = path.resolve(root, relative);
  if (mocks[filename]) return mocks[filename];
  if (cache.has(filename)) return cache.get(filename);
  const module = { exports: {} };
  cache.set(filename, module.exports);
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const localRequire = specifier => {
    if (mocks[specifier]) return mocks[specifier];
    if (specifier === 'BuildProfile') return { default: { DEBUG: true } };
    if (specifier.startsWith('.')) return load(path.resolve(path.dirname(filename), `${specifier}.ets`), mocks, cache);
    throw Error(`Unmocked dependency: ${specifier}`);
  };
  vm.runInNewContext(output, { module, exports: module.exports, require: localRequire,
    console, Date, Error, Promise, setTimeout, clearTimeout, setInterval, clearInterval,
    canIUse: mocks.canIUse || (() => true) });
  return module.exports;
}

function viewMethod(relative, name, globals = {}) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const expression = new RegExp(`^  (?:private\\s+)?(?:async\\s+)?${name}\\(`, 'm');
  const start = source.search(expression);
  assert.ok(start >= 0, `Missing view method ${name}`);
  const end = source.indexOf('\n  }', start);
  assert.ok(end >= 0, `Missing method end ${name}`);
  const method = source.slice(start, end + 4);
  const output = ts.transpileModule(`class Subject { ${method} }`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  return vm.runInNewContext(`${output}; Subject.prototype.${name}`, { console, Date, Error, Promise,
    setTimeout, clearTimeout, InkShapePolicy, ...globals });
}

function platform({ shortCopy = false, syncFails = false, renderFails = false, parseResult = 0,
  pageCount = 2, selection = 'file://picked/course.pdf', writeFails = false, flushFails = false,
  nativeMissing = false, debug = true, offlineInfo, offlineError, nativeExecutor } = {}) {
  const calls = [];
  let inWorker = false;
  const files = new Map([['file://picked/course.pdf', Buffer.from(fixture)]]);
  const directories = new Set(['/sandbox']);
  const descriptors = new Map(); let nextFd = 1;
  const filePath = input => typeof input === 'number' ? descriptors.get(input) : input;
  const open = (file, mode) => {
    if (mode & 4) files.set(file, Buffer.alloc(0));
    if (!files.has(file)) throw Error('missing file');
    const fd = nextFd++; descriptors.set(fd, file); calls.push(['open', file]); return { fd };
  };
  const close = input => { const fd = typeof input === 'number' ? input : input.fd;
    calls.push(['close', descriptors.get(fd)]); descriptors.delete(fd); };
  const unlink = file => { calls.push(['unlink', file]); files.delete(file); };
  const fileIo = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 1, WRITE_ONLY: 2, CREATE: 4, TRUNC: 8 },
    accessSync: file => directories.has(file) || files.has(file),
    access: async file => directories.has(file) || files.has(file),
    mkdirSync: directory => directories.add(directory), mkdir: async directory => directories.add(directory),
    statSync: input => ({ size: files.get(filePath(input))?.length || 0 }),
    stat: async input => ({ size: files.get(filePath(input))?.length || 0 }),
    readSync: (fd, buffer) => { const bytes = files.get(filePath(fd)); new Uint8Array(buffer).set(bytes); return bytes.length; },
    openSync: open, open: async (file, mode) => open(file, mode),
    closeSync: close, close: async file => close(file),
    copyFile: async (fd, dest) => { calls.push(['copy', dest]); const bytes = files.get(filePath(fd));
      files.set(dest, Buffer.from(shortCopy ? bytes.subarray(0, 10) : bytes)); },
    fsync: async fd => { calls.push(['sync', filePath(fd)]); if (syncFails) throw Error('sync failed'); },
    fsyncSync: fd => calls.push(['sync', filePath(fd)]),
    unlinkSync: unlink, unlink: async file => unlink(file),
    write: async (fd, content) => { if (writeFails) throw Error('disk full');
      files.set(filePath(fd), Buffer.from(content)); return Buffer.byteLength(content); },
    writeSync: (fd, data) => { files.set(filePath(fd), Buffer.from(data)); return data.byteLength; },
    rename: async (from, to) => { files.set(to, files.get(from)); files.delete(from); },
    readText: async file => files.get(file).toString()
  };
  class PdfDocument {
    constructor() { assert.ok(inWorker, 'PDFKit must only be constructed inside a background task'); }
    loadDocument(file) { calls.push(['native-load', file]); return parseResult; }
    getPageCount() { return pageCount; }
    getPage(index) { calls.push(['native-page', index]); return {
      getWidth: () => 595.28, getHeight: () => 841.89, getTextContent: () => `Page ${index + 1}`,
      getCustomPagePixelMap: () => { if (renderFails) throw Error('native render failed');
        calls.push('native-render'); return { release: async () => calls.push('bitmap-release') }; },
      release: () => calls.push('page-release') }; }
    releaseDocument() { calls.push('document-release'); }
  }
  class DocumentViewPicker { async select() { return selection ? [selection] : []; } }
  const preferences = new Map();
  const mocks = {
    [path.resolve(root, `${base}services/document/LocalPdfEngine.ets`)]: { LocalPdfEngine: { getInstance: () => ({
      bindContext() {},
      inspect: async file => { calls.push(['offline-info', file]);
        if (offlineError) throw Error(offlineError);
        if (!offlineInfo) throw Error('离线阅读组件未就绪，请重试');
        return offlineInfo; },
      render: async (file, page, cancelled) => { calls.push(['offline-page', file, page]);
        if (cancelled()) throw Error('页面已离开');
        if (renderFails) throw Error('offline render failed');
        return { aspectRatio: 2 / 3, pixelMap: { release: async () => calls.push('offline-bitmap-release') } }; }
    }) } },
    canIUse: () => !nativeMissing,
    BuildProfile: { default: { DEBUG: debug } },
    '@kit.ImageKit': { image: { PixelMapFormat: { RGBA_8888: 1 }, createImageSource: bytes => {
      assert.equal(Buffer.from(bytes).subarray(1, 4).toString(), 'PNG'); calls.push('debug-image-source');
      return { getImageInfo: async () => ({ size: { width: 1200, height: 1698 } }),
        createPixelMap: async () => ({ release: async () => calls.push('debug-bitmap-release') }),
        release: async () => calls.push('debug-image-release') };
    } } },
    '@kit.CoreFileKit': { fileIo, picker: { DocumentViewPicker, DocumentSelectOptions: class {} } },
    '@kit.PDFKit': nativeMissing ? {} : { pdfService: { PdfDocument, PdfMatrix: class {},
      ParseResult: { PARSE_SUCCESS: 0, PARSE_ERROR_PASSWORD: 3 } } },
    '@kit.ArkTS': { taskpool: { execute: async (fn, ...args) => {
      calls.push(['worker', fn.name]);
      if (nativeExecutor) return nativeExecutor(fn, args);
      await Promise.resolve(); inWorker = true;
      try { return fn(...args); } finally { inWorker = false; }
    } }, util: { TextEncoder: class { encodeInto(text) { return Buffer.from(text); } } } },
    '@kit.ArkData': { preferences: { getPreferences: async () => ({
      get: async (key, fallback) => preferences.get(key) ?? fallback,
      put: async (key, value) => preferences.set(key, value), flush: async () => { if (flushFails) throw Error('disk full'); } }) } },
    [path.resolve(root, `${base}services/ocr/OcrService.ets`)]: { OcrService: {} }
  };
  const cache = new Map();
  const Storage = load(`${base}services/NoteStorageService.ets`, mocks, cache).NoteStorageService;
  return { calls, files, descriptors, preferences,
    bundledContext: { filesDir: '/sandbox', resourceManager: {
      getRawFileContent: async name => Buffer.from(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile', name))),
      getRawFileContentSync: name => Buffer.from(fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile', name)))
    } },
    pdf: load(pdfFile, mocks, cache).PdfDocumentService.getInstance(),
    storage: new Storage(), restartStorage: () => new Storage() };
}

test('debug emulator can validate and render only byte-identical bundled PDF pages without PDF Kit', async () => {
  const p = platform({ nativeMissing: true });
  const result = await p.storage.importExamplePdf(p.bundledContext);
  assert.equal(result.status, 'imported'); assert.equal(result.pageCount, 2);
  const second = await p.pdf.renderPageAsync(result.sourceUri, 1); await second.pixelMap.release();
  assert.equal(second.aspectRatio, 1200 / 1698); assert.equal(p.descriptors.size, 0);
  assert.ok(p.calls.includes('debug-image-release')); assert.ok(!p.calls.includes('native-load'));
  await assert.rejects(p.pdf.renderPageAsync(result.sourceUri, 2), /页码/);
  const different = Buffer.from(p.files.get(result.sourceUri)); different[different.length - 1] ^= 1;
  p.files.set(result.sourceUri, different);
  await assert.rejects(p.pdf.getPdfInfo(result.sourceUri), /离线阅读组件未就绪/);
  await p.pdf.renderPageAsync(result.sourceUri, 0);
  assert.ok(p.calls.some(call => Array.isArray(call) && call[0] === 'offline-page'));
  p.files.set('/sandbox/other.pdf', fixture);
  await assert.rejects(p.pdf.getPdfInfo('/sandbox/other.pdf'), /离线阅读组件未就绪/);
  assert.equal(p.descriptors.size, 0);
});

test('debug bootstrap preserves existing notes and persists exactly one real PDF across restarts', async () => {
  const p = platform({ nativeMissing: true }); const existing = note({ id: 'user-note' });
  await p.storage.load(p.bundledContext, [existing]);
  const first = await p.storage.ensureDebugPdf(p.bundledContext, [existing]);
  assert.equal(first.length, 2); assert.equal(first[0].id, 'debug-pdf-demo-v1');
  assert.equal(first[0].category, '示例资料'); assert.equal(first[0].pageCount, 2);
  assert.ok(p.files.get(first[0].sourceUri).equals(fixture)); assert.deepEqual(first[1], existing);
  const reloaded = await p.restartStorage().load(p.bundledContext, []);
  const second = await p.restartStorage().ensureDebugPdf(p.bundledContext, reloaded);
  assert.equal(second.length, 2); assert.equal(second[0].sourceUri, first[0].sourceUri);
  const writes = p.calls.filter(call => Array.isArray(call) && call[0] === 'open' && call[1].endsWith('example-course.pdf')).length;
  await p.storage.save([existing]); await p.storage.delete(p.bundledContext, first[0].id, first[0].sourceUri);
  assert.equal((await p.storage.ensureDebugPdf(p.bundledContext, [existing])).length, 1);
  assert.equal(p.calls.filter(call => Array.isArray(call) && call[0] === 'open' && call[1].endsWith('example-course.pdf')).length, writes);
});

test('a preexisting example in the recycle bin is not recreated when its install marker is absent', async () => {
  const p = platform(); await p.storage.load(context, []);
  p.preferences.set('trash', JSON.stringify([note({ id: 'debug-pdf-demo-v1' })]));
  assert.equal((await p.storage.ensureDebugPdf(context, [])).length, 0);
  assert.equal(p.preferences.get('debug_pdf_demo_v1'), true);
  assert.ok(!p.calls.some(call => Array.isArray(call) && call[0] === 'copy'));
});

test('failed example snapshot leaves the existing library intact and cleans only the uncommitted example', async () => {
  const p = platform({ flushFails: true });
  await assert.rejects(p.storage.ensureDebugPdf(p.bundledContext, [note({ id: 'user-note' })]));
  assert.ok(!p.files.has('/sandbox/notes/debug-pdf-demo-v1.md'));
  assert.ok(![...p.files.keys()].some(key => key.startsWith('/sandbox/documents/')));
  assert.ok(p.files.has('file://picked/course.pdf'));
});

test('release neither seeds nor permits bundled preview imports or rendering', async () => {
  const p = platform({ nativeMissing: true, debug: false }); const notes = [note()];
  assert.equal(await p.storage.ensureDebugPdf(p.bundledContext, notes), notes);
  assert.equal((await p.storage.importExamplePdf(p.bundledContext)).status, 'unsupported');
  p.files.set('/sandbox/documents/example-course.pdf', fixture); p.pdf.bindContext(p.bundledContext);
  await assert.rejects(p.pdf.getPdfInfo('/sandbox/documents/example-course.pdf'), /离线阅读组件未就绪/);
  assert.ok(!p.calls.includes('debug-image-source')); assert.equal(p.descriptors.size, 0);
});

const context = { filesDir: '/sandbox' };
test('missing PDF Kit routes real metadata and page rendering through the offline adapter', async () => {
  const p=platform({nativeMissing:true,debug:false,offlineInfo:{pageCount:549}});
  const source=await p.pdf.savePdfToSandbox(context,'file://picked/course.pdf','course.pdf');
  p.pdf.bindContext(context);
  assert.equal((await p.pdf.getPdfInfo(source)).pageCount,549);
  const page=await p.pdf.renderPageAsync(source,274);assert.equal(page.aspectRatio,2/3);
  await page.pixelMap.release();assert.ok(p.calls.includes('offline-bitmap-release'));
  assert.ok(p.calls.some(c=>Array.isArray(c)&&c[0]==='offline-page'&&c[2]===274));
  assert.ok(!p.calls.includes('debug-image-source'));assert.equal(p.descriptors.size,0);
});
test('offline capability failures preserve their cause without claiming the source is missing', async () => {
  const p=platform({nativeMissing:true,debug:false,offlineError:'离线阅读组件连接失败'});
  const source=await p.pdf.savePdfToSandbox(context,'file://picked/course.pdf','course.pdf');p.pdf.bindContext(context);
  await assert.rejects(p.pdf.getPdfInfo(source),/离线阅读组件连接失败/);
  assert.ok(p.files.has(source));assert.equal(p.descriptors.size,0);
});
test('offline page cancellation prevents native or offline rendering from starting', async () => {
  const p=platform({nativeMissing:true,debug:false,offlineInfo:{pageCount:2}});
  const source=await p.pdf.savePdfToSandbox(context,'file://picked/course.pdf','course.pdf');p.pdf.bindContext(context);
  await assert.rejects(p.pdf.renderPageAsync(source,0,()=>true),/页面已离开/);
  assert.ok(!p.calls.some(c=>Array.isArray(c)&&c[0]==='offline-page'));
});
const note = changes => ({ id: 'existing-pdf', title: '课程原件', category: '课程', type: 'PDF',
  previewText: '', tag: 'PDF', tagColor: '#2563EB', updateTime: '', contentDetail: '# 已有资料',
  sourceType: 'pdf', sourceUri: '', pageCount: 2, pageAnnotations: '{"version":1,"pageCount":2,"pages":{"0":[]}}',
  pdfTextJson: '[{"pageNumber":1,"text":"旧文字"}]', ...changes });

test('real PDF fixture is copied byte-for-byte, synced and returned as a durable source', async () => {
  const p = platform(); const source = await p.pdf.savePdfToSandbox(context, 'file://picked/course.pdf', 'course.pdf');
  assert.ok(p.files.get(source).equals(fixture)); assert.match(source, /^\/sandbox\/documents\//);
  assert.ok(p.calls.some(call => call[0] === 'sync' && call[1] === source)); assert.equal(p.descriptors.size, 0);
});

for (const failure of [{ shortCopy: true }, { syncFails: true }]) {
  test(`failed durable PDF copy removes its partial source: ${Object.keys(failure)[0]}`, async () => {
    const p = platform(failure);
    await assert.rejects(p.pdf.savePdfToSandbox(context, 'file://picked/course.pdf', 'course.pdf'), /复制失败/);
    assert.equal([...p.files.keys()].filter(file => file.startsWith('/sandbox/documents/')).length, 0);
    assert.equal(p.descriptors.size, 0); assert.ok(p.files.get('file://picked/course.pdf').equals(fixture));
  });
}

test('missing or empty sources never invoke the native parser', async () => {
  const p = platform(); p.files.set('/sandbox/documents/empty.pdf', Buffer.alloc(0));
  for (const source of ['', '/sandbox/documents/absent.pdf', '/sandbox/documents/empty.pdf']) {
    await assert.rejects(p.pdf.getPdfInfo(source), /原文件/);
  }
  assert.ok(!p.calls.some(call => call[0] === 'native-load'));
});

test('a native parse success alone cannot publish an unrenderable imported PDF', async () => {
  const p = platform({ renderFails: true }); const result = await p.storage.importDocument(context);
  assert.equal(result.status, 'failed'); assert.match(result.message, /native render/);
  assert.ok(![...p.files.keys()].some(file => file.startsWith('/sandbox/documents/')));
  assert.ok(![...p.files.keys()].some(file => file.startsWith('/sandbox/notes/')));
  assert.ok(p.calls.includes('page-release')); assert.equal(p.descriptors.size, 0);
});

test('import then snapshot reload retains the actual PDF source bytes and page count', async () => {
  const p = platform(); const result = await p.storage.importDocument(context);
  assert.equal(result.status, 'imported'); assert.equal(result.pageCount, 2);
  const saved = note({ id: result.document.id, sourceUri: result.sourceUri, sourceFileName: result.sourceFileName, contentDetail: result.document.content });
  await p.storage.save([saved]); p.files.delete('file://picked/course.pdf');
  const reloaded = await p.restartStorage().load(context, []);
  assert.equal(reloaded[0].sourceUri, result.sourceUri); assert.ok(p.files.get(reloaded[0].sourceUri).equals(fixture));
  assert.equal((await p.pdf.validateImport(reloaded[0].sourceUri)).pageCount, 2);
  // The first import keeps its cover for an instant note open; validating the same source
  // again must replace (and release) that retained bitmap rather than leaking it.
  assert.ok(p.calls.includes('bitmap-release'));
});

test('a restarted sandbox resolves its imported PDF by the saved local filename', async () => {
  const p = platform(); const result = await p.storage.importDocument(context);
  const saved = note({ id: result.document.id, sourceUri: result.sourceUri, sourceFileName: result.sourceFileName, contentDetail: result.document.content });
  await p.storage.save([saved]);
  const current = { filesDir: '/new-sandbox/files' };
  const newSource = `${current.filesDir}/documents/${result.sourceFileName}`;
  p.files.set(newSource, p.files.get(result.sourceUri)); p.files.delete(result.sourceUri);
  p.files.set(`${current.filesDir}/notes/${saved.id}.md`, Buffer.from(saved.contentDetail));
  p.files.delete('file://picked/course.pdf');
  const reloaded = await p.restartStorage().load(current, []);
  assert.equal(reloaded[0].sourceUri, newSource); assert.equal(reloaded[0].pageAnnotations, saved.pageAnnotations);
  assert.equal((await p.pdf.validateImport(newSource)).pageCount, 2);
  assert.equal(JSON.parse(p.preferences.get('notes'))[0].sourceUri, newSource);
});

test('legacy sandbox paths are recovered for both library notes and the recycle bin', async () => {
  const p = platform(); const legacy = note({ sourceUri: '/old-sandbox/files/documents/original.pdf' });
  p.preferences.set('notes', JSON.stringify([legacy]));
  p.preferences.set('trash', JSON.stringify([{ ...legacy, id: 'trashed', deletedAt: 1 }]));
  p.files.set('/sandbox/documents/original.pdf', Buffer.from(fixture));
  p.files.set('/sandbox/notes/existing-pdf.md', Buffer.from(legacy.contentDetail));
  const storage = p.restartStorage();
  const reloaded = await storage.load(context, []); const trash = await storage.loadTrash(context);
  for (const recovered of [reloaded[0], trash[0]]) {
    assert.equal(recovered.sourceUri, '/sandbox/documents/original.pdf'); assert.equal(recovered.sourceFileName, 'original.pdf');
    assert.equal(recovered.pageAnnotations, legacy.pageAnnotations);
  }
  assert.equal(JSON.parse(p.preferences.get('trash'))[0].sourceFileName, 'original.pdf');
});

test('legacy picker references get independent owned copies and survive revocation after migration', async () => {
  const p = platform(); const legacy = note({ sourceUri: 'file://picked/course.pdf' });
  p.preferences.set('notes', JSON.stringify([legacy, { ...legacy, id: 'same-source' }]));
  const reloaded = await p.storage.load(context, []);
  assert.match(reloaded[0].sourceUri, /^\/sandbox\/documents\//);
  assert.notEqual(reloaded[1].sourceUri, reloaded[0].sourceUri);
  assert.equal(p.calls.filter(call => call[0] === 'copy').length, 2);
  assert.ok(p.files.has(legacy.sourceUri)); p.files.delete(legacy.sourceUri);
  const restarted = await p.restartStorage().load(context, []);
  assert.ok(p.files.get(restarted[0].sourceUri).equals(fixture));
  await p.storage.delete(context, restarted[0].id, restarted[0].sourceUri);
  assert.ok(p.files.get(restarted[1].sourceUri).equals(fixture));
});

test('unavailable or invalid legacy originals retain their records and annotations without leaking copies', async () => {
  for (const unavailable of [true, false]) {
    const p = platform({ renderFails: !unavailable }); const legacy = note({ sourceUri: 'file://picked/course.pdf' });
    if (unavailable) p.files.delete(legacy.sourceUri);
    p.preferences.set('notes', JSON.stringify([legacy]));
    const reloaded = await p.storage.load(context, []);
    assert.equal(reloaded[0].sourceUri, legacy.sourceUri); assert.equal(reloaded[0].pageAnnotations, legacy.pageAnnotations);
    assert.ok(![...p.files.keys()].some(file => file.startsWith('/sandbox/documents/')));
    assert.equal(p.descriptors.size, 0);
  }
});

test('failed migration metadata persistence removes only its newly created copy', async () => {
  const p = platform({ flushFails: true }); const legacy = note({ sourceUri: 'file://picked/course.pdf' });
  const raw = JSON.stringify([legacy]); p.preferences.set('notes', raw);
  p.files.set('/sandbox/notes/existing-pdf.md', Buffer.from(legacy.contentDetail));
  await assert.rejects(p.storage.load(context, []), /保存/);
  assert.equal(p.preferences.get('notes'), raw); assert.ok(p.files.has(legacy.sourceUri));
  assert.ok(![...p.files.keys()].some(file => file.startsWith('/sandbox/documents/')));
});

test('malformed local filenames never redirect a PDF into a different directory', async () => {
  for (const name of ['../private.pdf', 'sub/file.pdf', '..\\private.pdf', '.']) {
    const p = platform(); const legacy = note({ sourceUri: '/original.pdf', sourceFileName: name });
    p.preferences.set('notes', JSON.stringify([legacy]));
    p.files.set('/sandbox/notes/existing-pdf.md', Buffer.from(legacy.contentDetail));
    const reloaded = await p.storage.load(context, []);
    assert.equal(reloaded[0].sourceUri, legacy.sourceUri); assert.ok(!p.calls.some(call => call[0] === 'copy'));
  }
});

test('a 600-page textbook import parses metadata and renders only the first page before publishing', async () => {
  const p = platform({ pageCount: 600 }); const result = await p.storage.importDocument(context);
  assert.equal(result.status, 'imported'); assert.equal(result.pageCount, 600);
  assert.deepEqual(p.calls.filter(call => call[0] === 'native-page').map(call => call[1]), [0]);
  assert.equal(p.descriptors.size, 0); assert.ok(p.files.get(result.sourceUri).equals(fixture));
});

test('restoring metadata without its PDF attachment preserves the reference and annotations without fabricating a replacement', async () => {
  const p = platform(); const result = await p.storage.importDocument(context);
  const saved = note({ id: result.document.id, sourceUri: result.sourceUri, contentDetail: result.document.content });
  await p.storage.save([saved]); p.files.delete(result.sourceUri);
  const restored = await p.storage.load(context, []);
  assert.equal(restored[0].sourceUri, saved.sourceUri); assert.equal(restored[0].pageAnnotations, saved.pageAnnotations);
  await assert.rejects(p.pdf.validateImport(restored[0].sourceUri), /原文件|原件/);
  assert.equal(p.files.has(saved.sourceUri), false); assert.equal(p.descriptors.size, 0);
});

test('a note write failure does not leave a phantom PDF import', async () => {
  const p = platform({ writeFails: true }); const result = await p.storage.importDocument(context);
  assert.equal(result.status, 'failed'); assert.ok(![...p.files.keys()].some(file => file.startsWith('/sandbox/documents/')));
  assert.equal(p.descriptors.size, 0);
});

test('cancelled replacement never mutates the existing note or creates a source', async () => {
  const p = platform({ selection: '' }); const existing = note(); const before = plain(existing);
  assert.equal(await p.storage.selectReplacementPdf(context, existing), null); assert.deepEqual(existing, before);
  assert.ok(!p.calls.some(call => call[0] === 'copy'));
});

test('replacement preserves note identity and annotations but invalidates old extracted text', async () => {
  const p = platform(); const existing = note(); const before = plain(existing);
  const replacement = await p.storage.selectReplacementPdf(context, existing);
  assert.equal(replacement.id, existing.id); assert.equal(replacement.title, existing.title);
  assert.equal(replacement.pageAnnotations, existing.pageAnnotations); assert.equal(replacement.pdfTextJson, undefined);
  assert.equal(replacement.pageCount, 2); assert.ok(p.files.get(replacement.sourceUri).equals(fixture));
  assert.deepEqual(existing, before);
});

test('replacement with incompatible page count keeps annotations and deletes only the new copy', async () => {
  const p = platform(); const existing = note({ pageCount: 9 }); const before = plain(existing);
  await assert.rejects(p.storage.selectReplacementPdf(context, existing), /不一致/);
  assert.deepEqual(existing, before); assert.ok(![...p.files.keys()].some(file => file.startsWith('/sandbox/documents/')));
  assert.ok(p.files.has('file://picked/course.pdf'));
});

test('cleanup cannot follow traversal or remove selected external originals', async () => {
  const p = platform(); const valid = '/sandbox/documents/valid.pdf'; p.files.set(valid, fixture);
  for (const source of ['file://picked/course.pdf', '/sandbox/documents/../outside.pdf', '/sandbox/documents/a/b.pdf']) {
    await p.pdf.removeManagedPdf(context, source);
  }
  assert.ok(!p.calls.some(call => call[0] === 'unlink'));
  await p.pdf.removeManagedPdf(context, valid); assert.ok(!p.files.has(valid)); assert.ok(p.files.has('file://picked/course.pdf'));
});

test('missing PDF original gives recovery and never calls renderer or reports ready', () => {
  const calls = []; const loadPage = viewMethod(backgroundFile, 'loadPage', {
    PdfDocumentService: { getInstance: () => ({ renderPage: () => calls.push('render') }) }
  });
  const view = { sourceUri: '', bitmap: undefined, errorMessage: '', onSourceReady: ready => calls.push(ready) };
  loadPage.call(view); assert.match(view.errorMessage, /原文件/); assert.deepEqual(calls, [false]);
});

test('PDF error placeholders cannot accept pen or eraser input', () => {
  const handleTouch = viewMethod(canvasFile, 'handleTouch', { InkRenderer: {} });
  for (const tool of ['pen', 'eraser']) {
    let reads = 0;
    handleTouch.call({ sourceReady: false, isAnnotateMode: true, tool, pageWidth: 720, pageHeight: 1000,
      input: { read: () => { reads++; } } }, {});
    assert.equal(reads, 0);
  }
});

test('read-only or tool switching finishes the active PDF stroke before notifying idle', () => {
  const finish = viewMethod(canvasFile, 'finishInput'); const calls = [];
  const stroke = { points: [{ u: .1, v: .2 }] };
  const view = { currentStroke: stroke, erasing: false, pageWidth: 720, pageHeight: 1000,
    input: { reset: () => calls.push('reset') }, liveContext: { clearRect: () => calls.push('clear') },
    onStrokeAdded: value => calls.push(['stroke', value]), onActiveFinisherChange: value => calls.push(['finisher', value]),
    onInkContactChange: value => calls.push(['contact', value]) };
  finish.call(view, true); assert.equal(view.currentStroke, null); assert.deepEqual(calls[1], ['stroke', stroke]);
  assert.deepEqual(calls.at(-1), ['contact', false]);
});

test('a pen discards an unfinished palm or finger mark before its new pointer is read', () => {
  const calls = []; let active = true; let pen = false; let registered = null;
  const finishInput = viewMethod(canvasFile, 'finishInput');
  const handleTouch = viewMethod(canvasFile, 'handleTouch', { SourceTool: { Pen: 2 }, TouchType: { Down: 0 },
    InkRenderer: { segment: () => {} } });
  const fingerStroke = { id: 'finger', points: [{ u: .1, v: .2 }] };
  const view = { sourceReady: true, isAnnotateMode: true, tool: 'pen', pageWidth: 720, pageHeight: 1000,
    currentStroke: fingerStroke, erasing: false, fingerDrawing: true, pageModel: { pageIndex: 0 },
    selectedColor: '#2563EB', selectedWidth: 3, style: () => ({}),
    input: { isActive: () => active, isPenActive: () => pen,
      reset: () => { active = false; pen = false; calls.push('reset'); },
      read: () => { assert.equal(active, false); calls.push('read pen'); active = true; pen = true;
        return { phase: 'begin', samples: [{ x: 30, y: 40, pressure: .5 }] }; } },
    liveContext: { clearRect: () => {} }, onPenActive: () => {},
    onStrokeAdded: stroke => calls.push(['stroke', stroke.id]),
    onActiveFinisherChange: finish => { registered = finish; calls.push(['finisher', finish !== null]); },
    onInkContactChange: value => calls.push(['contact', value]) };
  view.finishInput = commit => finishInput.call(view, commit);
  handleTouch.call(view, { type: 0, sourceTool: 2, stopPropagation: () => {} });
  assert.equal(calls.some(call => call[0] === 'stroke' && call[1] === 'finger'),false);
  assert.ok(calls.indexOf('reset') < calls.indexOf('read pen'));
  assert.equal(active, true); assert.equal(pen, true); assert.notEqual(view.currentStroke.id, 'finger');
  assert.deepEqual(calls.slice(-2), [['finisher', true], ['contact', true]]);
  registered(); assert.equal(active, false); assert.equal(view.currentStroke, null);
  assert.equal(calls.filter(call => call[0] === 'stroke').length, 1);
});

test('active PDF erasing commits on mode exit and cancellation rolls back without a new stroke', () => {
  const finish = viewMethod(canvasFile, 'finishInput');
  for (const commit of [true, false]) {
    const calls = []; const view = { currentStroke: null, erasing: true, pageWidth: 720, pageHeight: 1000,
      input: { reset: () => {} }, liveContext: { clearRect: () => {} }, onStrokeAdded: () => calls.push('unexpected stroke'),
      onEraseFinished: value => calls.push(value), onActiveFinisherChange: () => {}, onInkContactChange: () => {} };
    finish.call(view, commit); assert.deepEqual(calls, [commit]); assert.equal(view.erasing, false);
  }
});

test('releasing an inactive PDF page cannot unregister another page active pen', () => {
  const setFinisher = viewMethod(annotatorFile, 'setActiveInputFinisher'); const active = () => {};
  const view = { activeInputPage: 2, activeInputFinisher: active, finishActiveInput: () => { throw Error('should remain active'); } };
  setFinisher.call(view, 0, null); assert.equal(view.activeInputFinisher, active); assert.equal(view.activeInputPage, 2);
});

test('inactive PDF page disposal cannot clear active contact or publish dirty state for another page', () => {
  const contact = viewMethod(annotatorFile, 'setPageInkContact'); const calls = [];
  const view = { activeInputPage: 2, inkContact: true, saveRevision: 0, savedRevision: 0,
    onDirtyChange: dirty => calls.push(dirty) };
  contact.call(view, 0, false); assert.equal(view.inkContact, true); assert.deepEqual(calls, []);
  // Dirty state now belongs to an actual stroke commit, not to contacting the page.
  contact.call(view, 2, false); assert.equal(view.inkContact, false); assert.deepEqual(calls, []);
});

test('tool updates that recopy the current page model keep its loaded bitmap writable', () => {
  const changed = viewMethod(canvasFile, 'onSourceChanged'); const calls = [];
  const view = { sourceUri: '/book.pdf', pageModel: { pageIndex: 0 }, loadedSourceUri: '/book.pdf', loadedPageIndex: 0,
    sourceReady: true, pageAspectRatio: 1.5, resetInput: () => calls.push('reset'), onSourceReady: ready => calls.push(ready) };
  changed.call(view); assert.equal(view.sourceReady, true); assert.equal(view.pageAspectRatio, 1.5); assert.deepEqual(calls, []);
  view.pageModel = { pageIndex: 1 }; changed.call(view);
  assert.equal(view.sourceReady, false); assert.deepEqual(calls, ['reset', false]);
  view.sourceReady = true; view.sourceUri = '/replacement.pdf'; changed.call(view); assert.equal(view.sourceReady, false);
});

test('changing PDF page finishes the previous page ink before moving the current page index', () => {
  const changePage = viewMethod(annotatorFile, 'onCurrentPageChanged', { ScrollAlign: { START: 'start' } });
  const calls = []; const view = { pages: [{}, {}, {}], currentPage: 3, currentPageIdx: 0, isContinuousScroll: true, readyPages: { 2: true },
    finishActiveInput: () => calls.push(['finish', view.currentPageIdx]),
    onSourceReady: ready => calls.push(['ready', ready, view.currentPageIdx]),
    scroller: { scrollToIndex: index => calls.push(['scroll', index]) } };
  changePage.call(view); assert.deepEqual(calls, [['finish', 0], ['ready', true, 2], ['scroll', 2]]);
});

test('PDF page changes during initial empty-page setup do not scroll to an invalid index', () => {
  const changePage = viewMethod(annotatorFile, 'onCurrentPageChanged');
  const view = { pages: [], currentPage: 99, currentPageIdx: 0,
    finishActiveInput: () => { throw Error('unexpected active ink'); } };
  changePage.call(view); assert.equal(view.currentPageIdx, 0);
});

test('single-page jumps update the pager without scrolling the inactive continuous list', () => {
  const changePage = viewMethod(annotatorFile, 'onCurrentPageChanged');
  const view = { pages: [{}, {}, {}], currentPage: 3, currentPageIdx: 0, isContinuousScroll: false,
    readyPages: { 2: true }, finishActiveInput() {}, onSourceReady() {},
    scroller: { scrollToIndex() { throw Error('inactive list must not scroll'); } } };
  changePage.call(view); assert.equal(view.currentPageIdx, 2);
});

test('whole-page fitting respects portrait phone, landscape tablet and actual PDF page proportions', () => {
  const fit = viewMethod(annotatorFile, 'fittedPageWidth');
  for (const [width, height, ratio] of [[360, 700, 0.707], [1440, 840, 0.707], [360, 700, 1.5], [1440, 840, 1.5]]) {
    const view = { viewportWidth: width, viewportHeight: height, pageRatios: { 0: ratio }, zoomScale: 1 };
    const fitted = fit.call(view, { pageIndex: 0 });
    assert.ok(fitted <= width - 16); assert.ok(fitted / ratio <= height - 16 + 0.001);
    view.zoomScale = 2; assert.equal(fit.call(view, { pageIndex: 0 }), fitted * 2);
  }
});

test('swipe page changes finish active ink before publishing the new page and its source readiness', () => {
  const select = viewMethod(annotatorFile, 'selectVisiblePage'); const calls = [];
  const view = { pages: [{}, {}], currentPageIdx: 0, readyPages: { 1: false }, annotationError: '',
    finishActiveInput: () => calls.push(['finish', view.currentPageIdx]),
    onPageChanged: page => calls.push(['page', page]), onSourceReady: ready => calls.push(['ready', ready]) };
  select.call(view, 99); assert.equal(view.currentPageIdx, 1);
  assert.deepEqual(calls, [['finish', 0], ['page', 2], ['ready', false]]);
});

test('PDF exit-save finalizes ink first and reports the initiating note and save token', async () => {
  const saveForExit = viewMethod(annotatorFile, 'saveForExit'); const calls = [];
  const view = { exitSaveToken: 7, saveTimer: -1, saveRevision: 1, savedRevision: 0, loadedNoteId: 'pdf',
    finishActiveInput: () => { calls.push('finish'); view.saveRevision++; },
    annotationSnapshot: () => { calls.push('snapshot'); return { id: 'pdf', contentDetail: '' }; },
    onCommitForExit: async () => { calls.push('commit'); view.exitSaveToken = 8; },
    onDirtyChange: dirty => calls.push(['dirty', dirty]), onSaveStateChange: state => calls.push(state),
    onExitSaveFinished: (...args) => calls.push(args) };
  await saveForExit.call(view); assert.deepEqual(calls.slice(0, 3), ['finish', 'snapshot', 'commit']);
  assert.equal(view.savedRevision, 2); assert.deepEqual(calls.at(-1), [true, 'pdf', 7]);
});

test('PDF exit-save failure and late revision do not clear unsaved annotations', async () => {
  const saveForExit = viewMethod(annotatorFile, 'saveForExit');
  for (const failure of ['write', 'new-stroke', 'other-note']) {
    const calls = []; const view = { exitSaveToken: 3, saveTimer: -1, saveRevision: 2, savedRevision: 0, loadedNoteId: 'pdf',
      finishActiveInput: () => {}, annotationSnapshot: () => ({ id: 'pdf', contentDetail: '' }),
      onCommitForExit: async () => {
        if (failure === 'write') throw Error('disk');
        if (failure === 'new-stroke') view.saveRevision++;
        if (failure === 'other-note') view.loadedNoteId = 'other';
      }, onDirtyChange: dirty => calls.push(['dirty', dirty]), onSaveStateChange: () => {},
      onExitSaveFinished: (...args) => calls.push(args) };
    await saveForExit.call(view); assert.equal(view.savedRevision, 0); assert.deepEqual(calls.at(-1), [false, 'pdf', 3]);
    assert.ok(!calls.some(call => call[0] === 'dirty' && call[1] === false));
  }
});

test('a late PDF save rejection cannot publish failure state over the newly opened document', async () => {
  const saveForExit = viewMethod(annotatorFile, 'saveForExit'); const states = []; const completions = [];
  const view = { exitSaveToken: 4, saveTimer: -1, saveRevision: 2, savedRevision: 0, loadedNoteId: 'old',
    finishActiveInput: () => {}, annotationSnapshot: () => ({ id: 'old', contentDetail: '' }),
    onCommitForExit: async () => { view.loadedNoteId = 'new'; throw Error('late rejection'); },
    onDirtyChange: () => { throw Error('must not touch new document dirty state'); },
    onSaveStateChange: state => states.push(state), onExitSaveFinished: (...args) => completions.push(args) };
  await saveForExit.call(view); assert.deepEqual(states, []); assert.deepEqual(completions, [[false, 'old', 4]]);
});

const validInk = () => ({ version: 1, pageCount: 1, pages: { 0: [{ id: 'stroke', pageIndex: 0,
  color: '#2563EB', width: 3, isHighlighter: false, isEraser: false, points: [{ u: .2, v: .3, pressure: .5 }] }] } });

test('PDF ink accepts empty data, legacy optional pressure / flags and old empty second-page rows', () => {
  assert.deepEqual(plain(PdfAnnotationPolicy.read(undefined, 1)).pages, {});
  assert.deepEqual(plain(PdfAnnotationPolicy.read('', 1)).pages, {});
  const legacy = validInk(); delete legacy.pages[0][0].isHighlighter; delete legacy.pages[0][0].isEraser;
  delete legacy.pages[0][0].points[0].pressure; legacy.pages[1] = [];
  const raw = JSON.stringify(legacy); assert.deepEqual(plain(PdfAnnotationPolicy.read(raw, 1)), legacy);
  assert.equal(JSON.stringify(legacy), raw);
  assert.deepEqual(plain(PdfAnnotationPolicy.read(raw, 9)), legacy);
});

test('legacy nine-page PDF metadata keeps its valid seeded annotation records intact without inventing a source', () => {
  const legacy = note({ id: 'note-seed-pdf', sourceUri: undefined, pageCount: 9, pageAnnotations: JSON.stringify({ ...validInk(), pageCount: 9 }) });
  assert.equal(legacy.pageCount, 9); assert.equal(legacy.sourceUri, undefined);
  const annotations = PdfAnnotationPolicy.read(legacy.pageAnnotations, legacy.pageCount);
  assert.deepEqual(plain(annotations), JSON.parse(legacy.pageAnnotations));
  assert.ok(Object.values(annotations.pages).some(strokes => strokes.length > 0));
});

test('PDF ink rejects malformed arrays, pages, finite coordinates and widths without filtering records', () => {
  const invalid = [];
  for (const pages of [[], null, 'not-pages', { 0: null }, { 0: {} }, { '-1': [] }]) invalid.push({ ...validInk(), pages });
  for (const change of [{ pageIndex: 2 }, { width: 0 }, { width: Infinity }, { points: {} }, { isEraser: 'false' },
    { points: [null] }, { points: [{ u: NaN, v: .3 }] }, { points: [{ u: .2, v: 1.1 }] },
    { points: [{ u: .2, v: .3, pressure: -1 }] }]) {
    const data = validInk(); Object.assign(data.pages[0][0], change); invalid.push(data);
  }
  invalid.push({ ...validInk(), pageCount: 0 });
  const wrongPage = validInk(); wrongPage.pages[1] = wrongPage.pages[0]; invalid.push(wrongPage);
  for (const data of invalid) {
    const raw = JSON.stringify(data); assert.throws(() => PdfAnnotationPolicy.read(raw, 1), /原记录已保留/);
    assert.equal(JSON.stringify(data), raw);
  }
  assert.throws(() => PdfAnnotationPolicy.read('{broken json', 1), /原记录已保留/);
});

test('unreadable PDF ink remains in the original note and does not mark read mode dirty', () => {
  const loadAnnotations = viewMethod(annotatorFile, 'loadAnnotations', { PdfAnnotationPolicy });
  const calls = []; const original = note({ pageCount: 1, pageAnnotations: '{corrupt ink' });
  const view = { note: original, pages: [{}], onDirtyChange: dirty => calls.push(['dirty', dirty]),
    onAnnotationError: message => calls.push(['error', message]), onSourceReady: ready => calls.push(['ready', ready]),
    onSaveStateChange: state => calls.push(['state', state]) };
  loadAnnotations.call(view); assert.equal(original.pageAnnotations, '{corrupt ink');
  assert.ok(view.annotationError); assert.deepEqual(plain(view.pageStrokes), {});
  assert.ok(calls.some(call => call[0] === 'dirty' && call[1] === false));
  assert.ok(!calls.some(call => call[0] === 'dirty' && call[1] === true));
});

test('unreadable PDF ink blocks annotation entry even if the original PDF renders correctly', () => {
  const setReady = viewMethod(annotatorFile, 'setPageSourceReady'); const calls = [];
  const view = { annotationError: 'bad ink', currentPageIdx: 0, readyPages: {}, onSourceReady: ready => calls.push(ready) };
  setReady.call(view, 0, true); assert.equal(view.readyPages[0], true); assert.deepEqual(calls, [false]);
});

test('unreadable PDF ink cannot be erased, replaced with an empty snapshot or sent to persistence', async () => {
  const saveForExit = viewMethod(annotatorFile, 'saveForExit');
  const snapshot = viewMethod(annotatorFile, 'annotationSnapshot');
  const addStroke = viewMethod(annotatorFile, 'handleStrokeAdded'); const erase = viewMethod(annotatorFile, 'beginErase');
  const calls = []; const view = { annotationError: 'bad ink retained', exitSaveToken: 8, loadedNoteId: 'pdf',
    note: { pageAnnotations: '{raw' }, loadedAnnotationRaw: '{raw', saveRevision: 1,
    pageStrokes: { 0: [] }, onSaveStateChange: state => calls.push(state), onExitSaveFinished: (...args) => calls.push(args),
    onCommitForExit: () => { throw Error('must never write'); } };
  addStroke.call(view, validInk().pages[0][0]); erase.call(view, 0);
  assert.deepEqual(view.pageStrokes, { 0: [] }); assert.throws(() => snapshot.call(view), /retained/);
  await saveForExit.call(view); assert.deepEqual(calls.at(-1), [false, 'pdf', 8]);
});

test('unchanged unreadable PDF ink may leave read mode without rewriting the preserved raw', async () => {
  const saveForExit = viewMethod(annotatorFile, 'saveForExit');
  for (const unchanged of [true, false]) {
    const calls = []; const view = { annotationError: 'bad ink retained', exitSaveToken: 9, loadedNoteId: 'pdf',
      note: { pageAnnotations: unchanged ? '{original raw' : '{changed raw' }, loadedAnnotationRaw: '{original raw', saveRevision: 0,
      onSaveStateChange: state => calls.push(state), onExitSaveFinished: (...args) => calls.push(args),
      onCommitForExit: () => { throw Error('must never write invalid ink'); } };
    await saveForExit.call(view); assert.deepEqual(calls.at(-1), [unchanged, 'pdf', 9]);
    assert.equal(view.note.pageAnnotations, unchanged ? '{original raw' : '{changed raw');
  }
});

// ---- Offline engine lifecycle: bounded ranges, cancellation, timeouts, file changes. ----
const engineFile = `${base}services/document/LocalPdfEngine.ets`;

function engineHarness(seed = [['/sandbox/documents/book.pdf', 300000, 100]]) {
  const files = new Map(seed.map(([file, size, mtime]) => [file, { size, mtime }]));
  const calls = []; const descriptors = new Map(); let nextFd = 1;
  class Base64Helper {
    async encodeToString(bytes) { calls.push('encode-async'); return Buffer.from(bytes).toString('base64'); }
    async decode(text) { calls.push('decode-async'); return Buffer.from(text, 'base64'); }
  }
  class PixelMap { release() { return Promise.resolve(); } }
  const fileIo = {
    OpenMode: { READ_ONLY: 0 },
    accessSync: file => files.has(file),
    statSync: file => { const entry = files.get(file); if (!entry) { throw Error('missing'); }
      return { size: entry.size, mtime: entry.mtime }; },
    openSync: file => { const entry = files.get(file); if (!entry) { throw Error('missing'); }
      const fd = nextFd++; descriptors.set(fd, file); calls.push(['open', file]); return { fd }; },
    readSync: (fd, buffer, options) => {
      const entry = files.get(descriptors.get(fd));
      const length = Math.min(options.length, Math.max(0, entry.size - options.offset));
      new Uint8Array(buffer).fill(7, 0, length); return length;
    },
    closeSync: input => { const fd = typeof input === 'number' ? input : input.fd;
      calls.push(['close', fd]); descriptors.delete(fd); }
  };
  fileIo.stat = async path => fileIo.statSync(path);
  fileIo.open = async path => fileIo.openSync(path);
  fileIo.read = async (...args) => fileIo.readSync(...args);
  fileIo.close = async file => fileIo.closeSync(file);
  const mocks = {
    '@kit.CoreFileKit': { fileIo },
    '@kit.ArkTS': { taskpool: { execute: async (fn,...args) => fn(...args) }, util: { Base64Helper } },
    '@kit.ImageKit': { image: { createImageSource: () => ({
      createPixelMap: async () => new PixelMap(), release: async () => {} }) } },
    '@kit.AbilityKit': { Context: class {} },
    canIUse: () => false
  };
  const module = load(engineFile, mocks);
  const port = { scripts: [], execute(script) { this.scripts.push(script); return Promise.resolve(''); } };
  const engine = module.LocalPdfEngine.getInstance();
  engine.bindContext({ filesDir: '/sandbox' });
  engine.attach(port); engine.markReady();
  return { engine, port, calls, files, descriptors, mocks, pdfFailureKind: module.pdfFailureKind };
}

async function nextRequest(port, index = 0) {
  for (let attempt = 0; attempt < 200; attempt++) {
    if (port.scripts.length > index) {
      const match = port.scripts[index].match(/moyuPdf\.request\((\{.*?\})\);/s);
      assert.ok(match, `Unexpected host script: ${port.scripts[index]}`);
      return JSON.parse(match[1]);
    }
    await new Promise(resolve => setTimeout(resolve, 5));
  }
  throw Error('host request was not executed');
}

const bookPath = '/sandbox/documents/book.pdf';

test('offline failures arrive as distinct reader messages and keep classification consistent', async () => {
  const cases = [
    ['password', /密码/, 'password'], ['damaged', /损坏/, 'damaged'],
    ['missing', /重新关联/, 'missing'], ['engine', /未就绪/, 'engine'],
    ['read', /读取失败/, 'other'], ['page', /页码超出范围/, 'other']
  ];
  for (const [kind, pattern, classified] of cases) {
    const h = engineHarness();
    const task = h.engine.render(bookPath, 0, () => false);
    const request = await nextRequest(h.port);
    h.engine.finish(request.id, JSON.stringify({ error: 'English host text', errorKind: kind }));
    await assert.rejects(task, pattern);
    const message = await task.catch(error => error.message);
    assert.equal(h.pdfFailureKind(message), classified);
    assert.equal(h.engine.pending.size, 0);
  }
});

test('an unknown host error is still reported without inventing a re-link action', async () => {
  const h = engineHarness();
  const task = h.engine.render(bookPath, 0, () => false);
  const request = await nextRequest(h.port);
  h.engine.finish(request.id, JSON.stringify({ error: 'Worker was destroyed' }));
  await assert.rejects(task, /Worker was destroyed/);
  assert.equal(h.pdfFailureKind('Worker was destroyed'), 'other');
});

test('a page that leaves the viewport rejects at once and cancels the host render', async () => {
  const h = engineHarness(); let cancelled = false;
  const task = h.engine.render(bookPath, 3, () => cancelled);
  const request = await nextRequest(h.port);
  const started = Date.now(); cancelled = true;
  await assert.rejects(task, /页面已离开/);
  assert.ok(Date.now() - started < 2000);
  assert.ok(h.port.scripts.some(script => script.includes(`moyuPdf.cancel(${JSON.stringify(request.id)})`)));
  assert.equal(h.engine.pending.size, 0);
  h.engine.finish(request.id, JSON.stringify({ width: 10, height: 20, data: 'eA==' }));
  assert.equal(h.engine.pending.size, 0);
});

test('a timed-out page request cancels the host work instead of leaving it rendering', async () => {
  const h = engineHarness(); h.engine.requestTimeoutMs = 40;
  const task = h.engine.render(bookPath, 0, () => false);
  const request = await nextRequest(h.port);
  await assert.rejects(task, /超时/);
  assert.ok(h.port.scripts.some(script => script.includes(`moyuPdf.cancel(${JSON.stringify(request.id)})`)));
  assert.equal(h.engine.pending.size, 0);
});

test('a queued cancelled page never reaches the host and does not block the queue', async () => {
  const h = engineHarness();
  const first = h.engine.render(bookPath, 0, () => false);
  const request = await nextRequest(h.port);
  const queued = h.engine.render(bookPath, 1, () => true);
  h.engine.finish(request.id, JSON.stringify({ width: 10, height: 20, data: 'eA==' }));
  const bitmap = await first; await bitmap.pixelMap.release();
  await assert.rejects(queued, /页面已离开/);
  assert.equal(h.port.scripts.filter(script => script.includes('moyuPdf.request')).length, 1);
  assert.equal(h.engine.pending.size, 0);
});

test('host rebuild rejects in-flight work and ignores the old host callback', async () => {
  const h = engineHarness();
  const task = h.engine.render(bookPath, 0, () => false);
  const request = await nextRequest(h.port);
  h.engine.reloaded();
  await assert.rejects(task, /已重新加载/);
  h.engine.finish(request.id, JSON.stringify({ width: 10, height: 20, data: 'eA==' }));
  assert.equal(h.engine.pending.size, 0);
  h.engine.detach();
  assert.equal(h.engine.sources.size, 0);
});

test('range reads stay bounded, close their descriptor and report a replaced original', async () => {
  const h = engineHarness();
  const info = h.engine.inspect(bookPath);
  const request = await nextRequest(h.port);
  h.engine.finish(request.id, JSON.stringify({ pageCount: 3 }));
  assert.equal((await info).pageCount, 3);
  const token = request.token;
  assert.equal((await h.engine.read(token, 0, 1024)).length > 0, true);
  assert.equal(h.descriptors.size, 0);
  await assert.rejects(h.engine.read(token, 0, 128 * 1024 + 1), /范围无效/);
  await assert.rejects(h.engine.read(token, 10, 10), /范围无效/);
  await assert.rejects(h.engine.read(token, 0, 300001), /范围无效/);
  await assert.rejects(h.engine.read('local_999', 0, 10), /原文件不存在/);
  h.files.get(bookPath).size = 400000;
  await assert.rejects(h.engine.read(token, 0, 1024), /已被更改/);
});

test('a rewritten original gets a new host token instead of reusing stale page data', async () => {
  const h = engineHarness();
  const first = h.engine.inspect(bookPath);
  const one = await nextRequest(h.port);
  h.engine.finish(one.id, JSON.stringify({ pageCount: 2 })); await first;
  h.files.get(bookPath).mtime = 101;
  const second = h.engine.inspect(bookPath);
  const two = await nextRequest(h.port, 1);
  h.engine.finish(two.id, JSON.stringify({ pageCount: 2 })); await second;
  assert.notEqual(two.token, one.token);
  assert.equal(h.engine.sources.size, 1);
});

test('native parse failures separate corruption from password and missing originals', async () => {
  for (const [parseResult, pattern] of [[1, /损坏/], [3, /密码/]]) {
    const p = platform({ parseResult });
    p.files.set('/sandbox/documents/course.pdf', fixture);
    await assert.rejects(p.pdf.getPdfInfo('/sandbox/documents/course.pdf'), pattern);
  }
  const p = platform({ parseResult: 1 }); p.files.set('/sandbox/documents/course.pdf', fixture);
  await assert.rejects(p.pdf.getPdfInfo('/sandbox/documents/course.pdf'), error => {
    assert.ok(!error.message.includes('设备'));
    assert.ok(!error.message.includes('重新关联'));
    return true;
  });
  await assert.rejects(p.pdf.getPdfInfo(''), /重新关联/);
});

test('only a missing PDF original offers re-linking in the page background', () => {
  const canRestore = viewMethod(backgroundFile, 'canRestore');
  assert.equal(canRestore.call({ sourceType: 'pdf', failure: 'missing' }), true);
  for (const failure of ['damaged', 'password', 'engine', 'other']) {
    assert.equal(canRestore.call({ sourceType: 'pdf', failure }), false);
  }
  assert.equal(canRestore.call({ sourceType: 'image', failure: 'missing' }), false);
});

test('a page bitmap that arrives after leaving the page is released, never adopted', async () => {
  const deferred = {};
  const pending = new Promise((resolve, reject) => { deferred.resolve = resolve; deferred.reject = reject; });
  const loadPage = viewMethod(backgroundFile, 'loadPage', {
    PdfDocumentService: { getInstance: () => ({ renderPageAsync: () => pending }) }
  });
  const calls = [];
  const view = { sourceUri: '/book.pdf', sourceType: 'pdf', pageIndex: 0, bitmap: undefined,
    errorMessage: '', loading: false, visible: true, requestId: 0,
    onSourceReady: ready => calls.push(['ready', ready]), onAspectRatio: () => {},
    adopt: () => calls.push('adopt') };
  const task = loadPage.call(view);
  await new Promise(resolve => setTimeout(resolve, 0));
  view.requestId++;
  deferred.resolve({ pixelMap: { release: async () => calls.push('release') }, aspectRatio: 1.4 });
  await task;
  assert.deepEqual(calls, ['release']);
  assert.equal(view.bitmap, undefined);
});

test('offline host reports machine-readable failure kinds and verifies its own range bound', () => {
  const source = fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/offline-pdf/host.mjs'), 'utf8');
  for (const name of ['PasswordException', 'InvalidPDFException', 'MissingPDFException']) {
    assert.ok(source.includes(name), `host must classify ${name}`);
  }
  assert.ok(source.includes('errorKind: kind'));
  assert.ok(source.includes('window.moyuPdf.cancel') || source.includes(' cancel(id)'));
  assert.ok(source.includes('RANGE_LIMIT'));
  assert.ok(source.includes('onFailure'));
  const html = fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/offline-pdf/host.html'), 'utf8');
  assert.ok(html.includes('worker-src'));
  assert.ok(html.includes('base-uri'));
  assert.ok(!html.includes('unsafe-eval'));
});

test('native metadata, rasterization and extraction all dispatch through the background task', async () => {
  const p = platform(); const source = '/sandbox/documents/course.pdf'; p.files.set(source, fixture);
  const opening = p.pdf.getPdfInfo(source);
  assert.ok(!p.calls.some(call => Array.isArray(call) && call[0] === 'native-load'));
  assert.equal((await opening).pageCount, 2);
  const bitmap = await p.pdf.renderPageAsync(source, 1); await bitmap.pixelMap.release();
  const pages = await p.pdf.extractPages(source, 1, 2, false, () => false, () => {});
  assert.deepEqual(Array.from(pages, page => page.text), ['Page 1', 'Page 2']);
  // info, one page render, and one batched text extraction for the whole reviewed range.
  assert.equal(p.calls.filter(call => Array.isArray(call) && call[0] === 'worker').length, 3);
  assert.equal(typeof p.pdf.renderPage, 'undefined', 'no synchronous rendering entry may remain on the UI service');
});

function nativeQueue() {
  const pending = [], calls = [];
  const { NativePdfLoader } = load(`${base}services/document/NativePdfLoader.ets`, {
    [path.resolve(root, `${base}services/document/NativePdfTask.ets`)]: { readNativePdf() { throw Error('must run in a worker'); } },
    '@kit.ArkTS': { taskpool: { execute: (fn, ...args) => {
      calls.push(args); return new Promise((resolve, reject) => pending.push({ resolve, reject }));
    } } }
  });
  return { loader: new NativePdfLoader(), pending, calls };
}
const tick = () => new Promise(resolve => setTimeout(resolve, 0));

test('two PDF panes run concurrently per file and queued cancelled pages never dispatch', async () => {
  const h = nativeQueue(); let cancelled = false, released = 0;
  const first = h.loader.run('/left.pdf', 'page', 0, () => false);
  const leaving = h.loader.run('/right.pdf', 'page', 2, () => cancelled);
  const handled = assert.rejects(leaving, /页面已离开/);
  const last = h.loader.run('/right.pdf', 'info', 0, () => false);
  await tick(); assert.equal(h.calls.length, 2, 'separate files may render concurrently');
  cancelled = true;
  h.pending[0].resolve({ pageCount: 2, fileSize: 10, pixelMap: { release: async () => released++ } });
  const result = await first; await result.pixelMap.release();
  h.pending[1].resolve({ pageCount: 2, fileSize: 10, pixelMap: { release: async () => released++ } });
  await handled; await tick();
  // The right-file page was already running; its late bitmap is released, then the queued
  // info request starts on the freed file slot.
  assert.equal(released, 2); assert.equal(h.calls.length, 3); assert.equal(h.calls[2][1], 'info');
  h.pending[2].resolve({ pageCount: 3, fileSize: 10 }); assert.equal((await last).pageCount, 3);
});

test('leaving a running native page stops waiting and releases its late bitmap', async () => {
  const h = nativeQueue(); let cancelled = false, released = 0;
  const request = h.loader.run('/book.pdf', 'page', 0, () => cancelled);
  const handled = assert.rejects(request, /页面已离开/);
  await tick(); cancelled = true; await handled;
  h.pending[0].resolve({ pageCount: 2, fileSize: 10, pixelMap: { release: async () => released++ } });
  await tick(); assert.equal(released, 1);
});

test('native timeout ends loading, keeps the actual native call serial and disposes its late image', async () => {
  const h = nativeQueue(); h.loader.timeoutMs = 25; let released = 0;
  const first = h.loader.run('/book.pdf', 'page', 0, () => false);
  await assert.rejects(first, /读取超时/);
  h.loader.timeoutMs = 1000;
  const retry = h.loader.run('/book.pdf', 'page', 1, () => false);
  await tick(); assert.equal(h.calls.length, 1, 'timeout cannot allow overlapping calls into the native library');
  h.pending[0].resolve({ pageCount: 2, fileSize: 10, pixelMap: { release: async () => released++ } });
  await tick(); assert.equal(released, 1); assert.equal(h.calls.length, 2);
  h.pending[1].resolve({ pageCount: 2, fileSize: 10 }); await retry;
});

test('a queued native timeout is skipped and a failed native task does not poison the queue', async () => {
  const h = nativeQueue(); h.loader.timeoutMs = 1000;
  const first = h.loader.run('/book.pdf', 'page', 0, () => false);
  const handledFirst = assert.rejects(first, /损坏/);
  h.loader.timeoutMs = 25;
  await assert.rejects(h.loader.run('/book.pdf', 'page', 1, () => false), /超时/);
  h.pending[0].reject(new Error('PDF 损坏')); await handledFirst;
  h.loader.timeoutMs = 1000;
  const next = h.loader.run('/next.pdf', 'info', 0, () => false);
  await tick(); assert.equal(h.calls.length, 2); assert.equal(h.calls[1][0], '/next.pdf');
  h.pending[1].resolve({ pageCount: 1, fileSize: 10 }); assert.equal((await next).pageCount, 1);
});

test('offline asynchronous range failure closes its descriptor and never returns a partial chunk', async () => {
  const h = engineHarness(); const info = h.engine.inspect(bookPath); const request = await nextRequest(h.port);
  h.engine.finish(request.id, JSON.stringify({ pageCount: 1 })); await info;
  h.mocks['@kit.CoreFileKit'].fileIo.read = async () => 3;
  await assert.rejects(h.engine.read(request.token, 0, 100), /读取失败/);
  assert.equal(h.descriptors.size, 0); assert.equal(h.engine.statistics(), 0);
});

test('a page cancelled during asynchronous image decoding releases the image and decoder', async () => {
  const h = engineHarness(); let complete, cancelled = false, releases = 0, decoders = 0;
  h.mocks['@kit.ImageKit'].image.createImageSource = () => ({
    createPixelMap: () => new Promise(resolve => { complete = resolve; }), release: async () => decoders++
  });
  const reading = h.engine.render(bookPath, 0, () => cancelled);
  const handled = assert.rejects(reading, /页面已离开/);
  const request = await nextRequest(h.port);
  h.engine.finish(request.id, JSON.stringify({ width: 10, height: 20, data: 'eA==' }));
  await tick(); assert.equal(typeof complete, 'function'); cancelled = true;
  complete({ release: async () => releases++ }); await handled;
  assert.equal(releases, 1); assert.equal(decoders, 1); assert.ok(h.calls.includes('decode-async'));
});

test('a large offline reply decoded after a host rebuild cannot publish its old page', async () => {
  const h = engineHarness(); let decoded;
  h.mocks['@kit.ArkTS'].taskpool.execute = () => new Promise(resolve => { decoded = resolve; });
  const reading = h.engine.render(bookPath, 0, () => false);
  const handled = assert.rejects(reading, /重新加载/);
  const request = await nextRequest(h.port);
  h.engine.finish(request.id, JSON.stringify({ width: 10, height: 20, data: 'A'.repeat(70000) }));
  assert.equal(typeof decoded, 'function'); h.engine.reloaded(); await handled;
  decoded({ width: 10, height: 20, data: 'eA==' }); await tick();
  assert.ok(!h.calls.includes('decode-async')); assert.equal(h.engine.pending.size, 0);
});

function offlineHost(nativePdf) {
  const callbacks = [];
  const source = fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/offline-pdf/host.mjs'), 'utf8')
    .replace(/^import[^\n]+\n/, '').replaceAll('import.meta.url', JSON.stringify('moyu://local/offline-pdf/host.mjs'));
  const window = {};
  class PDFDataRangeTransport {
    constructor(length) { this.length = length; }
    onDataRange(begin, result) { this.result = Array.from(result); this.begin = begin; }
  }
  vm.runInNewContext(source + '\nwindow.TestRanges = NativeRanges;', { window, nativePdf, GlobalWorkerOptions: {},
    getDocument() { throw Error('not requested'); }, PDFDataRangeTransport, URL, atob, console,
    setTimeout: (fn, delay) => { callbacks.push({ fn, delay }); return callbacks.length; }, clearTimeout() {} });
  return { window, callbacks };
}

test('offline host retries missing and unbound proxies until native readiness is acknowledged', () => {
  let attempts = 0;
  const h = offlineHost({ ready() { attempts++; if (attempts === 1) throw Error('native proxy object not found'); return attempts > 2; } });
  assert.equal(attempts, 1); h.callbacks.shift().fn(); assert.equal(attempts, 2);
  h.callbacks.shift().fn(); assert.equal(attempts, 3); assert.equal(h.callbacks.length, 0);
  const absent = offlineHost(undefined); assert.equal(absent.callbacks.length, 1);
});

test('offline range transport awaits the asynchronous native bridge and ignores cancelled chunks', async () => {
  const reads = [], resolvers = [];
  const h = offlineHost({ ready: () => true, read: (...args) => {
    reads.push(args); return new Promise(resolve => resolvers.push(resolve));
  } });
  const failures = [];
  const range = new h.window.TestRanges('token', 4, error => failures.push(error));
  range.requestDataRange(0, 4); await tick(); assert.equal(reads.length, 1); assert.equal(range.result, undefined);
  resolvers[0](Buffer.from([1,2,3,4]).toString('base64')); await tick();
  assert.equal(h.callbacks.length, 1); h.callbacks.shift().fn(); await tick();
  assert.deepEqual(Array.from(range.result), [1,2,3,4]); assert.deepEqual(failures, []);
  range.requestDataRange(0, 4); await tick(); range.abort(); resolvers[1](Buffer.from([9,9,9,9]).toString('base64'));
  await tick(); assert.deepEqual(Array.from(range.result), [1,2,3,4]);
});

test('offline resource response waits for asynchronous bytes and completes both success and failure', async () => {
  let bytes, reject;
  const context = { resourceManager: { getRawFileContent: () => new Promise((resolve, fail) => { bytes = resolve; reject = fail; }) } };
  const fill = viewMethod(`${base}views/reader/pdf/LocalPdfEngineHost.ets`, 'fillResponse', { getContext: () => context });
  const response = { setResponseData(value) { this.data = value; }, setResponseCode(value) { this.code = value; },
    setResponseMimeType(value) { this.mime = value; }, setResponseHeader() {}, setResponseIsReady(value) { this.ready = value; } };
  const view = { mimeType: () => 'text/javascript' };
  const first = fill.call(view, 'offline-pdf/pdf.mjs', response);
  assert.equal(response.ready, undefined); bytes(new Uint8Array([1,2,3])); await first;
  assert.equal(response.ready, true); assert.equal(response.code, 200); assert.equal(response.data.byteLength, 3);
  const next = { ...response, data: undefined, ready: false }; const failed = fill.call(view, 'missing.mjs', next);
  reject(Error('missing')); await failed; assert.equal(next.ready, true); assert.equal(next.code, 404);
});

test('switching an image background into a PDF never recycles its old image as a PDF page', () => {
  const calls = [];
  const release = viewMethod(backgroundFile, 'releaseBitmap', { PdfDocumentService: { getInstance: () => ({ recyclePage: () => { calls.push('cache'); return true; } }) } });
  const view = { requestId: 1, bitmap: { release: async () => calls.push('release') }, bitmapSource: '/image.png',
    bitmapSourceType: 'image', bitmapPage: 0, bitmapRatio: 1, sourceType: 'pdf', onSourceReady() {} };
  release.call(view, true); assert.deepEqual(calls, ['release']); assert.equal(view.bitmap, undefined);
});

test('a native page cancelled while queued is skipped even before its cancellation poll fires', async () => {
  const h = nativeQueue(); let cancelled = false;
  const first = h.loader.run('/book.pdf', 'info', 0, () => false);
  const queued = h.loader.run('/book.pdf', 'page', 1, () => cancelled);
  const handled = assert.rejects(queued, /页面已离开/);
  cancelled = true; h.pending[0].resolve({ pageCount: 2, fileSize: 10 });
  await first; await handled; assert.equal(h.calls.length, 1);
});

test('PDF page cache transfers a bitmap to only one reader and rejects a changed or missing original', async () => {
  const p = platform(); const source = '/sandbox/documents/course.pdf'; p.files.set(source, fixture);
  const first = await p.pdf.renderPageAsync(source, 0);
  assert.equal(p.pdf.recyclePage(source, 0, first.pixelMap, first.aspectRatio), true);
  const cached = await p.pdf.renderPageAsync(source, 0); assert.equal(cached.pixelMap, first.pixelMap);
  assert.equal(p.calls.filter(call => call === 'native-render').length, 1);
  const secondOwner = await p.pdf.renderPageAsync(source, 0); assert.notEqual(secondOwner.pixelMap, cached.pixelMap);
  await secondOwner.pixelMap.release(); p.pdf.recyclePage(source, 0, cached.pixelMap, cached.aspectRatio);
  p.files.set(source, Buffer.concat([fixture, Buffer.from('changed')]));
  const refreshed = await p.pdf.renderPageAsync(source, 0); assert.notEqual(refreshed.pixelMap, cached.pixelMap);
  assert.equal(p.calls.filter(call => call === 'bitmap-release').length, 2);
  p.pdf.recyclePage(source, 0, refreshed.pixelMap, refreshed.aspectRatio); p.files.delete(source);
  await assert.rejects(p.pdf.renderPageAsync(source, 0), /重新关联/); assert.equal(p.pdf.pageCache.size, 0);
});

test('bounded PDF cache releases evictions and all retained pages on reader exit', async () => {
  const p = platform({ pageCount: 5 }); const source = '/sandbox/documents/course.pdf'; p.files.set(source, fixture);
  for (let index = 0; index < 5; index++) {
    const result = await p.pdf.renderPageAsync(source, index); p.pdf.recyclePage(source, index, result.pixelMap, result.aspectRatio);
  }
  assert.equal(p.pdf.pageCache.size, 3); assert.equal(p.calls.filter(call => call === 'bitmap-release').length, 2);
  p.pdf.clearPageCache(); assert.equal(p.pdf.pageCache.size, 0); assert.equal(p.calls.filter(call => call === 'bitmap-release').length, 5);
});

test('offline ranges reject same-sized source rewrites instead of mixing bytes from two versions', async () => {
  const h = engineHarness(); const info = h.engine.inspect(bookPath); const request = await nextRequest(h.port);
  h.engine.finish(request.id, JSON.stringify({ pageCount: 1 })); await info;
  h.files.get(bookPath).mtime++;
  await assert.rejects(h.engine.read(request.token, 0, 100), /已被更改/); assert.equal(h.descriptors.size, 0);
});
