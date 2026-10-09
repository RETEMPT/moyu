import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

// Exercise actual storage / PDF / input lifecycle methods with native adapters mocked.
// Native PDFKit rendering, ArkUI hit testing and stylus latency still require a device.
const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sdkArg = process.argv.indexOf('--typescript');
const ts = require(sdkArg >= 0 ? path.resolve(process.argv[sdkArg + 1]) : 'typescript');
const base = 'entry/src/main/ets/';
const pdfFile = `${base}services/document/PdfDocumentService.ets`;
const canvasFile = `${base}views/reader/pdf/PdfPageCanvas.ets`;
const annotatorFile = `${base}views/reader/pdf/PdfAnnotatorView.ets`;
const backgroundFile = `${base}views/reader/pdf/PdfPageBackground.ets`;
const fixture = fs.readFileSync(path.join(root, 'entry/src/main/resources/rawfile/example-course.pdf'));
const plain = value => JSON.parse(JSON.stringify(value));
const { PdfAnnotationPolicy } = load(`${base}services/document/PdfAnnotationPolicy.ets`, {});

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
    if (specifier.startsWith('.')) return load(path.resolve(path.dirname(filename), `${specifier}.ets`), mocks, cache);
    throw Error(`Unmocked dependency: ${specifier}`);
  };
  vm.runInNewContext(output, { module, exports: module.exports, require: localRequire,
    console, Date, Error, Promise, setTimeout, clearTimeout });
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
    setTimeout, clearTimeout, ...globals });
}

function platform({ shortCopy = false, syncFails = false, renderFails = false, parseResult = 0,
  pageCount = 2, selection = 'file://picked/course.pdf', writeFails = false } = {}) {
  const calls = [];
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
    loadDocument(file) { calls.push(['native-load', file]); return parseResult; }
    getPageCount() { return pageCount; }
    getPage(index) { calls.push(['native-page', index]); return {
      getWidth: () => 595.28, getHeight: () => 841.89,
      getCustomPagePixelMap: () => { if (renderFails) throw Error('native render failed');
        calls.push('native-render'); return { release: async () => calls.push('bitmap-release') }; },
      release: () => calls.push('page-release') }; }
    releaseDocument() { calls.push('document-release'); }
  }
  class DocumentViewPicker { async select() { return selection ? [selection] : []; } }
  const preferences = new Map();
  const mocks = {
    '@kit.CoreFileKit': { fileIo, picker: { DocumentViewPicker, DocumentSelectOptions: class {} } },
    '@kit.PDFKit': { pdfService: { PdfDocument, PdfMatrix: class {},
      ParseResult: { PARSE_SUCCESS: 0, PARSE_ERROR_PASSWORD: 3 } } },
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return Buffer.from(text); } } } },
    '@kit.ArkData': { preferences: { getPreferences: async () => ({
      get: async (key, fallback) => preferences.get(key) ?? fallback,
      put: async (key, value) => preferences.set(key, value), flush: async () => {} }) } },
    [path.resolve(root, `${base}services/ocr/OcrService.ets`)]: { OcrService: {} }
  };
  const cache = new Map();
  return { calls, files, descriptors, preferences,
    pdf: load(pdfFile, mocks, cache).PdfDocumentService.getInstance(),
    storage: new (load(`${base}services/NoteStorageService.ets`, mocks, cache).NoteStorageService)() };
}

const context = { filesDir: '/sandbox' };
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
  assert.equal(result.status, 'imported'); assert.equal(result.pageCount, 2); assert.ok(p.calls.includes('bitmap-release'));
  const saved = note({ id: result.document.id, sourceUri: result.sourceUri, contentDetail: result.document.content });
  await p.storage.save([saved]); const reloaded = await p.storage.load(context, []);
  assert.equal(reloaded[0].sourceUri, result.sourceUri); assert.ok(p.files.get(reloaded[0].sourceUri).equals(fixture));
  assert.equal((await p.pdf.validateImport(reloaded[0].sourceUri)).pageCount, 2);
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

test('a pen replaces finger ink only after the finger stroke is committed and before its new pointer is read', () => {
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
  assert.ok(calls.findIndex(call => call[0] === 'stroke' && call[1] === 'finger') < calls.indexOf('read pen'));
  assert.equal(active, true); assert.equal(pen, true); assert.notEqual(view.currentStroke.id, 'finger');
  assert.deepEqual(calls.slice(-2), [['finisher', true], ['contact', true]]);
  registered(); assert.equal(active, false); assert.equal(view.currentStroke, null);
  assert.equal(calls.filter(call => call[0] === 'stroke').length, 2);
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

test('inactive PDF page disposal cannot clear active contact or dirty state on another page', () => {
  const contact = viewMethod(annotatorFile, 'setPageInkContact'); const calls = [];
  const view = { activeInputPage: 2, inkContact: true, saveRevision: 0, savedRevision: 0,
    onDirtyChange: dirty => calls.push(dirty) };
  contact.call(view, 0, false); assert.equal(view.inkContact, true); assert.deepEqual(calls, []);
  contact.call(view, 2, false); assert.equal(view.inkContact, false); assert.deepEqual(calls, [false]);
});

test('changing PDF page finishes the previous page ink before moving the current page index', () => {
  const changePage = viewMethod(annotatorFile, 'onCurrentPageChanged', { ScrollAlign: { START: 'start' } });
  const calls = []; const view = { pages: [{}, {}, {}], currentPage: 3, currentPageIdx: 0, readyPages: { 2: true },
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
  const { seedNotes } = load('tools/fixtures/SeedContent.ets', {});
  const legacy = seedNotes().find(item => item.id === 'note-seed-pdf');
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
