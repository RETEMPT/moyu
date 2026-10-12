import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { createHash, createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

// Run ArkTS service and view snapshot logic with platform adapters mocked. HAP compilation
// separately verifies ArkTS types and UI; these tests do not emulate ArkUI.
const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sdkArg = process.argv.indexOf('--typescript');
const ts = require(sdkArg >= 0 ? path.resolve(process.argv[sdkArg + 1]) : 'typescript');
const base = 'entry/src/main/ets/';
const parserFile = `${base}services/smart/SourceTextParser.ets`;
const builderFile = `${base}services/smart/SmartNoteBuilder.ets`;
const extractFile = `${base}services/smart/SmartExtractService.ets`;
const ocrFile = `${base}services/ocr/OcrService.ets`;

function load(relative, mocks = {}, cache = new Map()) {
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
    if (specifier === 'BuildProfile') return { DEBUG: true, default: { DEBUG: true } };
    if (specifier.startsWith('.')) {
      return load(path.resolve(path.dirname(filename), `${specifier}.ets`), mocks, cache);
    }
    throw new Error(`Unmocked platform dependency: ${specifier}`);
  };
  vm.runInNewContext(output, { module, exports: module.exports, require: localRequire,
    console, Date, Error, Promise, setTimeout: mocks.setTimeout || setTimeout, clearTimeout: mocks.clearTimeout || clearTimeout,
    canIUse: mocks.canIUse || (() => true), AppStorage: mocks.AppStorage,
    SourceTool: mocks.SourceTool, TouchType: mocks.TouchType, Curve: mocks.Curve || { EaseInOut: 'ease' },
    OffscreenCanvas: mocks.OffscreenCanvas, RenderingContextSettings: mocks.RenderingContextSettings }, { filename });
  return module.exports;
}

const { SourceTextParser } = load(parserFile);
const { SmartNoteBuilder } = load(builderFile);
const { SmartCaptureService } = load(`${base}services/smart/SmartCaptureService.ets`);
const plain = value => JSON.parse(JSON.stringify(value));
const reference = new Date(2026, 8, 30, 10);
const source = '【美术课通知】\n2026年10月2日前提交素描作业。\n已经完成报名，无需准备额外材料。\n地点：画室二楼。';
const profile = overrides => ({ id: 'study', label: '学习', protocol: 'openai-compat', baseUrl: 'https://example.com/v1',
  apiKey: 'test-key', modelId: 'test-model', temperature: 0.7, maxTokens: 4096, stream: true,
  systemPrompt: '', createdAt: 1, updatedAt: 1, ...overrides });

function toolPorts(overrides = {}) {
  return { search: () => 'results', list: () => 'notes', read: () => 'body', summarize: () => 'stats',
    outline: () => 'outline', todos: () => 'todos', createTodo: async () => 'saved', addTag: async () => 'saved',
    createLink: async () => 'saved', categorize: async () => 'saved', createNote: async () => 'saved', progress: () => {}, ...overrides };
}

test('note card keys refresh covers, pinning and favorites without losing note identity', () => {
  const { noteRenderKey } = load(`${base}common/utils/ForEachKeys.ets`);
  const note = { id: 'a', title: '算法', type: 'Markdown', category: '学习', tag: '', updatedAt: 1 };
  const original = noteRenderKey(note);
  for (const change of [{ coverUrl: 'cover:mist' }, { favorite: true }, { isPinned: true }, { category: '工作' }]) {
    assert.notEqual(noteRenderKey({ ...note, ...change }), original);
  }
});

test('cover presets require no file access, gallery copies persist and source handles close', async () => {
  const copied = []; const closed = []; const removed = [];
  const { NoteCoverService } = load(`${base}services/NoteCoverService.ets`, { '@kit.CoreFileKit': { fileIo: {
    accessSync: () => true, OpenMode: { READ_ONLY: 0 }, openSync: () => ({ fd: 9 }), statSync: () => ({ size: 1024 }),
    copyFile: async (fd, target) => copied.push([fd, target]), closeSync: file => closed.push(file.fd),
    access: async () => true, unlink: async source => removed.push(source), unlinkSync: source => removed.push(source)
  } } });
  const context = { filesDir: '/sandbox' };
  assert.equal(await NoteCoverService.prepare(context, 'note', 'cover:mist'), 'cover:mist'); assert.equal(copied.length, 0);
  const saved = await NoteCoverService.prepare(context, '../note', 'photo://temporary');
  assert.match(saved, /^\/sandbox\/covers\/[a-zA-Z0-9_-]+\.img$/); assert.deepEqual(closed, [9]);
  await NoteCoverService.removeManaged(context, saved); await NoteCoverService.removeManaged(context, '/sandbox/covers/../private');
  assert.deepEqual(removed, [saved]); assert.equal(await NoteCoverService.prepare(context, 'note', ''), '');
});
test('failed or oversized cover copies clean partial file and release source', async () => {
  for (const oversized of [false, true]) {
    let closed = 0; let removed = 0;
    const { NoteCoverService } = load(`${base}services/NoteCoverService.ets`, { '@kit.CoreFileKit': { fileIo: {
      accessSync: () => true, OpenMode: { READ_ONLY: 0 }, openSync: () => ({ fd: 9 }),
      statSync: () => ({ size: oversized ? 13 * 1024 * 1024 : 100 }), copyFile: async () => { throw new Error('copy failed'); },
      closeSync: () => closed++, unlinkSync: () => removed++
    } } });
    await assert.rejects(NoteCoverService.prepare({ filesDir: '/sandbox' }, 'note', 'photo://temporary'));
    assert.equal(closed, 1); assert.equal(removed, 1);
  }
});

test('local extraction preserves source and never invents subject facts, tags or links', () => {
  const result = SourceTextParser.fromSource(source);
  assert.equal(result.title, '美术课通知');
  assert.equal(result.rawMarkdown, source);
  assert.equal(result.tasks.length, 1);
  assert.equal(result.tasks[0].deadline, '2026年10月2日');
  assert.deepEqual(plain(result.tags), []);
  assert.deepEqual(plain(result.entities), []);
  assert.deepEqual(plain(result.relations), []);
  assert.ok(result.formattedMarkdown.includes('画室二楼'));
  assert.ok(!result.formattedMarkdown.includes('银行家算法'));
});

test('no actionable source yields no invented calendar entries', () => {
  assert.equal(SourceTextParser.fromSource('今天阳光很好。').tasks.length, 0);
  assert.equal(SourceTextParser.fromSource('期末考试地点：艺术楼。').tasks.length, 0);
  assert.equal(SourceTextParser.fromSource('已经提交报告；无需完成练习。').tasks.length, 0);
});

test('line endings, formulas and code remain in locally formatted body', () => {
  const result = SourceTextParser.fromSource('# 数学\r\n\r\n$x=42$\r\n```js\r\nconst x = 42;\r\n```');
  assert.ok(result.formattedMarkdown.includes('$x=42$'));
  assert.ok(result.formattedMarkdown.includes('const x = 42;'));
  assert.ok(!result.formattedMarkdown.includes('\r'));
});

for (const [input, expected] of [
  ['2026-10-2', '2026-10-02'], ['2026年10月2日前', '2026-10-02'],
  ['2028-02-29', '2028-02-29'], ['今天', '2026-09-30'], ['明天', '2026-10-01'], ['后天', '2026-10-02'],
  ['2026-02-29', ''], ['2026-13-01', ''], ['2026-04-31', ''], ['12月25日', ''], ['下周五', ''], ['', '']
]) {
  test(`deadline ${input || '(empty)'} → ${expected || 'requires confirmation'}`, () => {
    assert.equal(SmartNoteBuilder.resolveDeadline(input, reference), expected);
  });
}

test('relative deadline rolls over the local year correctly', () => {
  assert.equal(SmartNoteBuilder.resolveDeadline('明天', new Date(2026, 11, 31)), '2027-01-01');
});

test('saved body matches preview, includes original, edits and only chosen tasks', () => {
  const content = SourceTextParser.fromSource(source);
  content.title = '我的美术课';
  content.formattedMarkdown = '# 旧标题\n\n校对后的正文。';
  content.category = '美术';
  const note = SmartNoteBuilder.buildNote(content, []);
  assert.equal(note.category, '美术');
  assert.ok(note.contentDetail.startsWith('# 我的美术课'));
  assert.ok(note.contentDetail.includes('校对后的正文。'));
  assert.ok(note.contentDetail.includes('> 地点：画室二楼。'));
  assert.ok(!note.contentDetail.includes('## 已选日历待办'));
  assert.equal(note.contentDetail, SmartNoteBuilder.buildMarkdown(content, [], true));
});

test('calendar plans use confirmed dates and keep ambiguous deadlines in titles', () => {
  const tasks = [ { id: 'a', title: '交作业', deadline: '2026-10-02', priority: 'high' },
    { id: 'b', title: '复习', deadline: '下周五', priority: 'medium' } ];
  const todos = SmartNoteBuilder.buildTodos(tasks, 'note-1', reference);
  assert.equal(todos[0].date, '2026-10-02');
  assert.equal(todos[1].date, '2026-09-30');
  assert.ok(todos[1].title.includes('下周五'));
  assert.equal(todos[0].noteRefs[0], 'note-1');
  assert.equal(todos[0].id, SmartNoteBuilder.buildTodos(tasks, 'note-1', reference)[0].id);
});

function captureStore(failStage = '') {
  const state = { notes: [], todos: [], calls: [], failStage };
  return { state, port: {
    currentNotes: () => state.notes, currentTodos: () => state.todos,
    writeDocument: async () => { state.calls.push('document'); if (state.failStage === 'document') throw Error('disk'); },
    writeNotes: async notes => { state.calls.push('notes'); if (state.failStage === 'notes') throw Error('prefs'); state.notes = notes; },
    writeTodos: async todos => { state.calls.push('todos'); if (state.failStage === 'todos') throw Error('prefs'); state.todos = todos; }
  } };
}

for (const stage of ['document', 'notes', 'todos']) {
  test(`saving failure at ${stage} preserves state and retry never duplicates items`, async () => {
    const content = SourceTextParser.fromSource(source);
    const store = captureStore(stage);
    await assert.rejects(SmartCaptureService.commit(content, content.tasks, store.port),
      stage === 'todos' ? /笔记已保存.*待办同步失败/ : /笔记保存未成功/);
    assert.equal(store.state.todos.length, 0);
    if (stage !== 'todos') assert.ok(!store.state.calls.includes('todos'));
    store.state.failStage = '';
    await SmartCaptureService.commit(content, content.tasks, store.port);
    await SmartCaptureService.commit(content, content.tasks, store.port);
    assert.equal(store.state.notes.length, 1);
    assert.equal(store.state.todos.length, 1);
    assert.equal(store.state.todos[0].noteRefs[0], store.state.notes[0].id);
    assert.equal(store.state.calls[0], 'document');
  });
}

test('save without selected tasks never writes calendar or deletes unrelated records', async () => {
  const store = captureStore();
  store.state.todos = [{ id: 'existing', title: 'old' }];
  await SmartCaptureService.commit(SourceTextParser.fromSource('随笔'), [], store.port);
  assert.equal(store.state.todos[0].id, 'existing');
  assert.ok(!store.state.calls.includes('todos'));
});

function ocrService(stage = '', value = '识别文字') {
  const calls = [];
  const map = { release: async () => { calls.push('pixel-release'); } };
  const mocks = {
    '@kit.CoreFileKit': { fileIo: { OpenMode: { READ_ONLY: 0 },
      openSync: () => { calls.push('open'); if (stage === 'open') throw Error('permission'); return { fd: 1 }; },
      closeSync: () => { calls.push('close'); } } },
    '@kit.ImageKit': { image: { PixelMapFormat: { RGBA_8888: 1 }, createImageSource: () => ({
      getImageInfo: async () => ({ size: { width: 6400, height: 3200 } }),
      createPixelMap: async options => { calls.push(options.desiredSize); if (stage === 'decode') throw Error('decode'); return map; },
      release: async () => { calls.push('source-release'); } }) } },
    '@kit.CoreVisionKit': { textRecognition: { recognizeText: async () => {
      calls.push('recognize'); if (stage === 'recognize') throw Error('unsupported'); return { value };
    } } }
  };
  return { calls, service: load(ocrFile, mocks).OcrService.getInstance() };
}

test('OCR returns actual text, downsizes proportionally, releases every resource', async () => {
  const { service, calls } = ocrService('', '  真正的原文  ');
  assert.equal(await service.recognizeTextFromUri('photo://image'), '真正的原文');
  assert.deepEqual(plain(calls[1]), { width: 3200, height: 1600 });
  assert.deepEqual(calls.slice(-3), ['pixel-release', 'source-release', 'close']);
});

for (const stage of ['open', 'decode', 'recognize', 'no-text']) {
  test(`OCR ${stage} rejects without demonstration text and cleans acquired resources`, async () => {
    const { service, calls } = ocrService(stage, stage === 'no-text' ? '' : 'text');
    await assert.rejects(service.recognizeTextFromUri('photo://image'));
    if (stage !== 'open') { assert.ok(calls.includes('source-release')); assert.ok(calls.includes('close')); }
    if (stage === 'recognize' || stage === 'no-text') assert.ok(calls.includes('pixel-release'));
  });
}

test('OCR empty URI rejects before opening files', async () => {
  const { service, calls } = ocrService();
  await assert.rejects(service.recognizeTextFromUri(' '));
  assert.equal(calls.length, 0);
});

function pdfService({ status = 0, pageCount = 3, renderFails = false, copyFails = false, pageTexts = [], ocrFails = false } = {}) {
  const calls = [];
  const bitmap = { release: async () => {} };
  class PdfDocument {
    loadDocument(file) { calls.push(['load', file]); return status; }
    releaseDocument() { calls.push('document-release'); }
    getPageCount() { return pageCount; }
    getPage(index) {
      calls.push(['page', index]);
      return { getWidth: () => 600, getHeight: () => 900,
        getCustomPagePixelMap: matrix => {
          calls.push(['render', matrix.width, matrix.height]);
          if (renderFails) throw Error('render');
          return bitmap;
        }, getTextContent: () => pageTexts[index] || '', release: () => calls.push('page-release') };
    }
  }
  class PdfMatrix {}
  const mocks = {
    '@kit.ImageKit': { image: {} },
    '@kit.PDFKit': { pdfService: { PdfDocument, PdfMatrix, ParseResult: { PARSE_SUCCESS: 0, PARSE_ERROR_PASSWORD: 3 } } },
    [path.resolve(root, `${base}services/ocr/OcrService.ets`)]: { OcrService: { getInstance: () => ({ recognizePixelMap: async () => {
      calls.push('ocr'); if (ocrFails) throw Error('ocr'); return '扫描页真实文字';
    } }) } },
    '@kit.CoreFileKit': { fileIo: { OpenMode: { READ_ONLY: 0 }, accessSync: () => true,
      statSync: () => ({ size: 8000 }), openSync: () => ({ fd: 1 }), closeSync: () => calls.push('file-close'),
      copyFile: async () => { if (copyFails) throw Error('disk'); calls.push('copied'); },
      fsync: async () => calls.push('file-sync'),
      unlinkSync: () => calls.push('partial-copy-removed') } }
  };
  return { calls, bitmap, service: load(`${base}services/document/PdfDocumentService.ets`, mocks).PdfDocumentService.getInstance() };
}

test('PDF metadata uses actual page count and releases document', async () => {
  const { service, calls } = pdfService({ pageCount: 2 });
  const info = await service.getPdfInfo('/sandbox/source.pdf');
  assert.equal(info.pageCount, 2);
  assert.equal(info.fileSize, 8000);
  assert.equal(calls.at(-1), 'document-release');
});

test('PDF rendering uses real page dimensions and returns bitmap ownership to caller', () => {
  const { service, calls, bitmap } = pdfService();
  const page = service.renderPage('/sandbox/source.pdf', 1);
  assert.equal(page.pixelMap, bitmap);
  assert.equal(page.aspectRatio, 2 / 3);
  assert.deepEqual(calls.at(-3), ['render', 1200, 1800]);
  assert.deepEqual(calls.slice(-2), ['page-release', 'document-release']);
});

for (const status of [1, 2, 3, 4]) {
  test(`PDF load error ${status} never fabricates nine pages`, async () => {
    const { service, calls } = pdfService({ status });
    await assert.rejects(service.getPdfInfo('/sandbox/bad.pdf'), status === 3 ? /密码/ : /无法读取/);
    assert.equal(calls.at(-1), 'document-release');
  });
}

test('PDF out-of-range page and render error release acquired native resources', () => {
  const invalid = pdfService();
  assert.throws(() => invalid.service.renderPage('/sandbox/source.pdf', 3), /页码/);
  assert.equal(invalid.calls.at(-1), 'document-release');
  const broken = pdfService({ renderFails: true });
  assert.throws(() => broken.service.renderPage('/sandbox/source.pdf', 0));
  assert.deepEqual(broken.calls.slice(-2), ['page-release', 'document-release']);
});

test('failed PDF copy removes partial file and closes handle, never returns temporary source URI', async () => {
  const { service, calls } = pdfService({ copyFails: true });
  await assert.rejects(service.savePdfToSandbox({ filesDir: '/sandbox' }, 'file://picked.pdf', 'file.pdf'), /复制失败/);
  assert.deepEqual(calls.slice(-2), ['partial-copy-removed', 'file-close']);
});

function importService(uri, { pdfFails = false, writeFails = false, unlinkFails = false, missing = false, initial = '', readFails = false,
  textContent = '# 资料\n\n全文' } = {}) {
  const calls = [];
  let raw = initial;
  const prefs = { get: async () => raw, put: async (key, value) => { raw = value; calls.push(['snapshot', key]); }, flush: async () => {} };
  class DocumentViewPicker { async select() { return uri ? [uri] : []; } }
  class DocumentSelectOptions {}
  const mocks = {
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return Buffer.from(text); } } } },
    '@kit.ArkData': { preferences: { getPreferences: async () => prefs } },
    '@kit.CoreFileKit': { picker: { DocumentViewPicker, DocumentSelectOptions },
      fileIo: { OpenMode: { WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 }, access: async () => !missing,
        mkdir: async () => {},
        readText: async () => { calls.push('read-text'); if (readFails) throw Error('I/O'); return textContent; },
        open: async () => ({ fd: 1 }), write: async (fd, content) => {
          if (writeFails) throw Error('disk full');
          calls.push(['write', content]);
          return Buffer.byteLength(content);
        }, fsync: async () => {}, rename: async () => {}, close: async () => calls.push('close'), unlink: async file => {
          calls.push(['unlink', file]);
          if (unlinkFails) throw Error('permission denied');
        } } },
    [path.resolve(root, `${base}services/document/PdfDocumentService.ets`)]: {
      PdfDocumentService: { getInstance: () => ({ savePdfToSandbox: async () => '/sandbox/copy.pdf', saveBundledExample: async () => '/sandbox/copy.pdf',
        validateImport: async () => { if (pdfFails) throw Error('PDF 损坏'); return { pageCount: 2 }; } }) }
    }
  };
  return { calls, raw: () => raw, service: new (load(`${base}services/NoteStorageService.ets`, mocks).NoteStorageService)() };
}

test('PDF import returns durable original path and actual page count', async () => {
  const { service, calls } = importService('file://picked/book.pdf');
  const result = await service.importDocument({ filesDir: '/sandbox' });
  assert.equal(result.status, 'imported');
  assert.equal(result.sourceUri, '/sandbox/copy.pdf');
  assert.equal(result.pageCount, 2);
  assert.equal(result.noteType, 'PDF');
  assert.ok(!result.document.content.includes('银行家算法'));
  assert.ok(calls.some(c => Array.isArray(c) && c[0] === 'write'));
});

test('a preselected text source uses the shared import path and materializes a local document', async () => {
  const text = importService(''); const result = await text.service.importDocumentUri({ filesDir: '/sandbox' }, 'file://picked/course.txt');
  assert.equal(result.status, 'imported'); assert.equal(result.noteType, 'Markdown');
  assert.match(result.document.filePath, /^\/sandbox\/notes\//); assert.equal(result.document.content, '# 资料\n\n全文');
});

test('preselected Marker results are stored as readable Markdown and invalid JSON never creates a note', async () => {
  const text = '# 课程\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n$$x^2+y^2=1$$';
  const success = importService('', { textContent: JSON.stringify({ success: true, format: 'markdown', output: text }) });
  const result = await success.service.importDocumentUri({ filesDir: '/sandbox' }, 'file://picked/marker.json');
  assert.equal(result.status, 'imported'); assert.equal(result.document.content, text); assert.equal(result.document.title, 'marker');
  assert.ok(success.calls.some(call => Array.isArray(call) && call[0] === 'write' && call[1] === text));
  const invalid = importService('', { textContent: '{broken' });
  assert.equal((await invalid.service.importDocumentUri({ filesDir: '/sandbox' }, 'file://picked/marker.json')).status, 'failed');
  assert.ok(!invalid.calls.some(call => Array.isArray(call) && call[0] === 'write'));
});

test('broken PDF import cleans its sandbox copy and returns failure', async () => {
  const { service, calls } = importService('file://picked/book.pdf', { pdfFails: true });
  const result = await service.importDocument({ filesDir: '/sandbox' });
  assert.equal(result.status, 'failed');
  assert.deepEqual(calls, [['unlink', '/sandbox/copy.pdf']]);
});

test('PDF metadata write failure removes the unreferenced source copy', async () => {
  const { service, calls } = importService('file://picked/book.pdf', { writeFails: true });
  assert.equal((await service.importDocument({ filesDir: '/sandbox' })).status, 'failed');
  assert.deepEqual(calls.at(-1), ['unlink', '/sandbox/copy.pdf']);
  assert.ok(calls.includes('close'));
});

test('permanent deletion cleans the sandbox PDF copy and Markdown file', async () => {
  const { service, calls } = importService('');
  await service.delete({ filesDir: '/sandbox' }, 'note', '/sandbox/documents/book.pdf');
  assert.deepEqual(calls, [['unlink', '/sandbox/documents/book.pdf'], ['unlink', '/sandbox/notes/note.md']]);
});

test('deletion never unlinks external URIs or traversing document paths', async () => {
  for (const source of ['file://picked/book.pdf', '/outside/book.pdf', '/sandbox/documents/../book.pdf',
    '/sandbox/documents/..', '/sandbox/documents/sub/book.pdf', '/sandbox/documents/..\\book.pdf']) {
    const { service, calls } = importService('');
    await service.delete({ filesDir: '/sandbox' }, 'note', source);
    assert.deepEqual(calls, [['unlink', '/sandbox/notes/note.md']]);
  }
});

test('deletion failures propagate for retry, missing files remain harmless', async () => {
  const failed = importService('', { unlinkFails: true });
  await assert.rejects(failed.service.delete({ filesDir: '/sandbox' }, 'note', '/sandbox/documents/book.pdf'));
  assert.equal(failed.calls.length, 1);
  const missing = importService('', { missing: true });
  await missing.service.delete({ filesDir: '/sandbox' }, 'note', '/sandbox/documents/book.pdf');
  assert.equal(missing.calls.length, 0);
});

for (const suffix of ['doc', 'docx']) {
  test(`unsupported ${suffix} import does not produce invented document text`, async () => {
    const { service, calls } = importService(`file://picked/book.${suffix}`);
    const result = await service.importDocument({ filesDir: '/sandbox' });
    assert.equal(result.status, 'unsupported');
    assert.equal(calls.length, 0);
  });
}

test('text import retains full text and cancel performs no writes', async () => {
  const text = importService('file://picked/book.md');
  assert.equal((await text.service.importDocument({ filesDir: '/sandbox' })).document.content, '# 资料\n\n全文');
  const cancelled = importService('');
  assert.equal((await cancelled.service.importDocument({ filesDir: '/sandbox' })).status, 'cancelled');
  assert.equal(cancelled.calls.length, 0);
});

const { StudySourceService } = load(`${base}services/study/StudySourceService.ets`);
const { ReviewPolicy } = load(`${base}services/study/ReviewPolicy.ets`);
const { StudyBackupPolicy } = load(`${base}services/study/StudyBackupPolicy.ets`);
const { StudyRestoreService } = load(`${base}services/study/StudyRestoreService.ets`);
const studyNote = overrides => ({ id: 'course_note', title: '操作系统', category: '操作系统', type: 'Markdown',
  previewText: '', tag: '', tagColor: '#2563EB', updateTime: '', contentDetail: '死锁的必要条件包括互斥、占有且等待、不剥夺和循环等待。', ...overrides });
const pdfStudyNote = () => studyNote({ type: 'PDF', sourceType: 'pdf', pageCount: 3,
  pdfTextJson: JSON.stringify([{ pageNumber: 1, text: '银行家算法通过安全性检查避免进入不安全状态。', method: 'text', extractedAt: 1 },
    { pageNumber: 2, text: '进程虚拟地址需要转换为物理地址。', method: 'ocr', extractedAt: 2 }]) });

test('PDF text batches use real page numbers and empty pages are not fabricated', async () => {
  const f = pdfService({ pageTexts: ['第一页原文', '', '第三页原文'] });
  const progress = [];
  const pages = await f.service.extractPages('/sandbox/book.pdf', 1, 3, false, () => false, page => progress.push(page));
  assert.deepEqual(plain(pages).map(p => [p.pageNumber, p.text, p.method]), [[1, '第一页原文', 'text'], [2, '', 'text'], [3, '第三页原文', 'text']]);
  assert.deepEqual(progress, [1, 2, 3]); assert.ok(!f.calls.includes('ocr'));
  assert.equal(f.calls.filter(c => c === 'page-release').length, 3);
  assert.equal(f.calls.filter(c => c === 'document-release').length, 1);
});
test('PDF scan OCR is opt-in and rendered page maps are released on failure', async () => {
  const f = pdfService({ pageTexts: ['原文', ''], ocrFails: true });
  let released = 0; f.bitmap.release = async () => { released++; };
  await assert.rejects(f.service.extractPages('/sandbox/book.pdf', 1, 2, true, () => false, () => {}), /ocr/);
  assert.equal(released, 1); assert.ok(f.calls.includes('ocr'));
  assert.equal(f.calls.filter(c => c === 'document-release').length, 2);
});
test('PDF extraction cancels between pages and rejects overlarge or invalid ranges', async () => {
  const f = pdfService(); let cancel = false;
  await assert.rejects(f.service.extractPages('/sandbox/book.pdf', 1, 3, false, () => cancel, () => { cancel = true; }), /取消/);
  assert.equal(f.calls.filter(c => c === 'page-release').length, 1);
  for (const range of [[0, 1], [1, 31], [2, 1], [1.5, 2], [1, 4]])
    await assert.rejects(f.service.extractPages('/sandbox/book.pdf', ...range, false, () => false, () => {}));
});
test('PDF index isolates malformed pages and merges only reviewed page replacements', () => {
  const note = pdfStudyNote();
  const replacement = [{ pageNumber: 2, text: '已校对文字', method: 'ocr', extractedAt: 7 }];
  const merged = StudySourceService.pages({ ...note, pdfTextJson: StudySourceService.merge(note, replacement) });
  assert.equal(merged.length, 2); assert.equal(merged[0].text, '银行家算法通过安全性检查避免进入不安全状态。');
  assert.equal(merged[1].text, '已校对文字');
  const bad = [{ pageNumber: 0, text: '假页', method: 'text' }, { pageNumber: 8, text: '越界页', method: 'text' }, null];
  assert.equal(StudySourceService.pages({ ...note, pdfTextJson: JSON.stringify(bad) }).length, 0);
  assert.equal(StudySourceService.pages({ ...note, pdfTextJson: 'broken' }).length, 0);
});
test('PDF annotation snapshots retain indexed text and source metadata while saving current strokes', () => {
  // Execute the actual pure snapshot method, without instantiating ArkUI or simulating gestures.
  const source = fs.readFileSync(path.resolve(root, `${base}views/reader/pdf/PdfAnnotatorView.ets`), 'utf8');
  const method = source.match(/  private annotationSnapshot\(\): NoteItem \{[\s\S]*?\n  \}/)?.[0];
  assert.ok(method, 'Reader snapshot method must exist');
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(`class Snapshot { ${method} } module.exports = Snapshot;`,
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, { module, JSON });
  const instance = new module.exports(); const note = studyNote({ sourceType: 'pdf', sourceUri: '/sandbox/documents/real.pdf', coverUrl: 'cover:ink' });
  instance.note = note; instance.pages = [1, 2]; instance.pageStrokes = { 1: [{ points: [{ x: 1, y: 2 }] }] };
  const result = plain(instance.annotationSnapshot());
  assert.equal(result.pdfTextJson, note.pdfTextJson); assert.equal(result.sourceUri, note.sourceUri);
  assert.equal(result.coverUrl, note.coverUrl); assert.deepEqual(JSON.parse(result.pageAnnotations).pages, instance.pageStrokes);
  assert.equal(note.pageAnnotations, undefined);
});
test('review feedback retains total reviews while resetting successful repetitions after forgetting', () => {
  const date = new Date(2026, 9, 4, 12).getTime();
  const card = ReviewPolicy.create(studyNote(), { question: '死锁条件是什么？', answer: '四个必要条件', sourceText: '' }, date);
  const good = ReviewPolicy.rate(card, 'good', date);
  assert.equal(good.intervalDays, 3); assert.equal(good.reviewCount, 1);
  const again = ReviewPolicy.rate(good, 'again', date);
  assert.equal(again.intervalDays, 1); assert.equal(again.reviewCount, 2); assert.equal(again.repetitions, 0); assert.equal(again.lapses, 1);
  assert.equal(card.reviewCount, 0); assert.ok(again.dueAt > date);
  assert.throws(() => ReviewPolicy.rate(card, 'bad', date));
});
test('review intervals stay bounded and malformed persisted rows do not enter the UI', () => {
  const card = ReviewPolicy.create(studyNote(), { question: 'Q', answer: 'A', sourceText: '' }, 1);
  const normalized = ReviewPolicy.normalize([null, { ...card, question: 42 }, { ...card, intervalDays: 999 }, card]);
  assert.equal(normalized.length, 1); assert.equal(normalized[0].intervalDays, 180);
  assert.equal(ReviewPolicy.rate({ ...card, intervalDays: 180, repetitions: 99 }, 'good', 1).intervalDays, 180);
});
test('course summaries exclude removed source notes and count only linked unfinished tasks', () => {
  const card = ReviewPolicy.create(studyNote(), { question: 'Q', answer: 'A', sourceText: '' }, 1);
  const summary = ReviewPolicy.courses([studyNote()], [card, { ...card, id: 'other', noteId: 'deleted' }],
    [{ done: false, noteRefs: [card.noteId] }, { done: true, noteRefs: [card.noteId] }, { done: false, noteRefs: [] }], 10)[0];
  assert.equal(summary.noteCount, 1); assert.equal(summary.dueCount, 1); assert.equal(summary.cardCount, 1); assert.equal(summary.todoCount, 1);
});
const studyBackup = () => ({ schemaVersion: 1, id: 'backup123', createdAt: 1, notes: [studyNote()], cards: [], assets: [] });
test('study backup rejects duplicate IDs, traversal IDs, invalid assets and orphaned cards', () => {
  const backup = studyBackup();
  for (const input of [{ ...backup, notes: [studyNote({ id: '../note' })] }, { ...backup, notes: [studyNote({ id: undefined })] },
    { ...backup, notes: [studyNote(), studyNote()] }, { ...backup, assets: [{ noteId: 'missing', kind: 'pdf', data: 'YWJj' }] },
    { ...backup, assets: [{ noteId: 'course_note', kind: 'pdf', data: '***bad' }] }, { ...backup, schemaVersion: 9 }])
    assert.throws(() => StudyBackupPolicy.validate(input));
  const card = ReviewPolicy.create(studyNote(), { question: 'Q', answer: 'A', sourceText: '' });
  assert.throws(() => StudyBackupPolicy.validate({ ...backup, cards: [{ ...card, noteId: 'missing' }] }));
  assert.equal(StudyBackupPolicy.restoreId(backup, 0), StudyBackupPolicy.restoreId(backup, 0));
});
test('backup restoration reconnects unique internal links and retains external, ambiguous and code-block links', () => {
  const backup = studyBackup();
  backup.notes = [studyNote({ contentDetail: '[[目标|章节]] [[外部]] [[同名]]\n```text\n[[目标]]\n```\n\n    [[目标]]' }),
    studyNote({ id: 'target', title: '目标' }), studyNote({ id: 'same1', title: '同名' }), studyNote({ id: 'same2', title: '同名' })];
  const text = StudyBackupPolicy.restoreContent(backup, 0);
  assert.ok(text.startsWith('[[目标（备份恢复）|章节]] [[外部]] [[同名]]'));
  assert.ok(text.includes('```text\n[[目标]]\n```')); assert.ok(text.includes('    [[目标]]'));
  assert.equal(backup.notes[0].contentDetail.includes('（备份恢复）'), false);
  assert.notEqual(StudyBackupPolicy.restoreTitle(backup, 2), StudyBackupPolicy.restoreTitle(backup, 3));
  assert.ok(StudyBackupPolicy.restoreTitle({ ...backup, notes: [studyNote({ title: '长'.repeat(500) })] }, 0).length <= 500);
});
test('PDF backups reject missing originals instead of exporting a broken reading copy', async () => {
  const backup = studyBackup(); backup.notes[0].sourceType = 'pdf';
  assert.throws(() => StudyBackupPolicy.validate(backup), /缺少原 PDF/);
  const f = backupFileFixture();
  await assert.rejects(f.service.exportFile({ filesDir: '/sandbox' }, backup.notes, []), /缺少原 PDF/);
});
function restoreFixture() {
  let notes = [studyNote({ id: 'original' })]; let cards = []; const calls = []; let failCards = false; let failNotes = false;
  const ports = { notes: () => notes, cards: () => cards, create: async note => { calls.push(['create', note.id]); },
    saveNotes: async next => { calls.push(['save-notes', next.length]); if (failNotes && next.length > 1) throw Error('disk'); },
    saveCards: async next => { if (failCards) throw Error('cards'); calls.push(['save-cards', next.length]); },
    remove: async note => calls.push(['remove', note.id]), publishNotes: next => { notes = next; }, publishCards: next => { cards = next; } };
  return { ports, calls, notes: () => notes, cards: () => cards, failCards: value => { failCards = value; }, failNotes: value => { failNotes = value; } };
}
test('backup restoration preserves original data and stable IDs make repeated imports idempotent', async () => {
  const f = restoreFixture(); const note = studyNote({ id: 'restored' });
  const card = ReviewPolicy.create(note, { question: 'Q', answer: 'A', sourceText: '' });
  await StudyRestoreService.commit(note, [card], f.ports); await StudyRestoreService.commit(note, [card], f.ports);
  assert.equal(f.notes().length, 2); assert.equal(f.cards().length, 1);
  assert.equal(f.notes()[0].id, 'original'); assert.equal(f.calls.filter(c => c[0] === 'create').length, 1);
});
test('failed backup note write rolls back metadata and cleans only the new note', async () => {
  const f = restoreFixture(); f.failNotes(true);
  await assert.rejects(StudyRestoreService.commit(studyNote({ id: 'restored' }), [], f.ports), /资料保存/);
  assert.equal(f.notes().length, 1); assert.ok(f.calls.some(c => c[0] === 'remove' && c[1] === 'restored'));
});
test('failed backup card write retains a valid restored note and retry fills missing cards', async () => {
  const f = restoreFixture(); const note = studyNote({ id: 'restored' });
  const card = ReviewPolicy.create(note, { question: 'Q', answer: 'A', sourceText: '' });
  f.failCards(true); await assert.rejects(StudyRestoreService.commit(note, [card], f.ports), /题卡保存失败/);
  assert.equal(f.notes().length, 2); assert.equal(f.cards().length, 0);
  f.failCards(false); await StudyRestoreService.commit(note, [card], f.ports);
  assert.equal(f.notes().length, 2); assert.equal(f.cards().length, 1);
});

function backupFileFixture({ selected = ['/picked/backup.json'], failPdf = false, failImage = false, shortRead = false } = {}) {
  const files = new Map(); const opened = new Map(); const calls = []; let fd = 0;
  const mocks = {
    '@kit.AbilityKit': {},
    '@kit.CoreFileKit': { picker: { DocumentSelectOptions: class {}, DocumentSaveOptions: class {}, DocumentViewPicker: class {
      async select() { return selected; } async save() { return selected; }
    } }, fileIo: { OpenMode: { READ_ONLY: 0, WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 },
      accessSync: () => true, mkdirSync: () => {},
      open: async filename => { opened.set(++fd, filename); return { fd }; },
      close: async file => { calls.push(['close', file.fd]); },
      statSync: descriptor => ({ size: files.get(typeof descriptor === 'number' ? opened.get(descriptor) : descriptor)?.length ?? 0 }),
      read: async (descriptor, buffer) => { const bytes = files.get(opened.get(descriptor)); new Uint8Array(buffer).set(bytes); return bytes.length - (shortRead ? 1 : 0); },
      write: async (descriptor, value) => { const bytes = typeof value === 'string' ? Buffer.from(value) : Buffer.from(value); files.set(opened.get(descriptor), bytes); return bytes.length; },
      fsync: async descriptor => calls.push(['flush', descriptor]),
      unlink: async filename => { files.delete(filename); calls.push(['unlink', filename]); }
    } },
    '@kit.ArkTS': { util: { Base64Helper: class {
      encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); }
      decodeSync(value) { return Buffer.from(value, 'base64'); } // Deliberately returns a pooled view with a nonzero byteOffset.
    }, TextEncoder: class { encodeInto(text) { return Buffer.from(text); } },
    TextDecoder: class { decodeToString(bytes) { return Buffer.from(bytes).toString('utf8'); } } } },
    '@kit.ImageKit': { image: { createImageSource: filename => ({ getImageInfo: async () => {
      if (failImage) throw Error('broken image'); return { size: { width: 1, height: 1 } };
    }, release: async () => calls.push(['image-release', filename]) }) } },
    [path.resolve(root, `${base}services/document/PdfDocumentService.ets`)]: { PdfDocumentService: { getInstance: () => ({
      validateImport: async filename => { if (failPdf) throw Error('broken pdf'); return { pageCount: 2 }; }
    }) } }
  };
  const { StudyBackupService } = load(`${base}services/study/StudyBackupService.ets`, mocks);
  return { service: StudyBackupService, files, calls };
}
function reviewStorageFixture(initial = '[]') {
  let raw = initial; let failFlush = false; const writes = [];
  const prefs = { get: async () => raw, put: async (key, value) => { raw = value; writes.push(value); },
    flush: async () => { if (failFlush) throw Error('disk'); } };
  const { ReviewStorageService } = load(`${base}services/study/ReviewStorageService.ets`, {
    '@kit.AbilityKit': {}, '@kit.ArkData': { preferences: { getPreferences: async () => prefs } }
  });
  return { service: new ReviewStorageService(), raw: () => raw, writes, failFlush: value => { failFlush = value; } };
}
test('review persistence survives reopen and failed flush rolls back the preference cache', async () => {
  const f = reviewStorageFixture(); const card = ReviewPolicy.create(studyNote(), { question: 'Q', answer: 'A', sourceText: '' });
  assert.equal((await f.service.load({})).length, 0); await f.service.save({}, [card]);
  assert.equal((await f.service.load({}))[0].question, 'Q'); const previous = f.raw();
  f.failFlush(true); await assert.rejects(f.service.save({}, []), /保存失败/);
  assert.equal(f.raw(), previous); assert.equal((await f.service.load({})).length, 1);
});
test('unreadable review storage blocks writes rather than overwriting the original data', async () => {
  for (const raw of ['{broken', '{"unrecognized":true}']) {
    const f = reviewStorageFixture(raw); await assert.rejects(f.service.load({}), /损坏/);
    await assert.rejects(f.service.save({}, []), /阻止覆盖/); assert.equal(f.raw(), raw); assert.equal(f.writes.length, 0);
  }
});
test('bundled sample backups remain labeled examples and do not block an initial full backup', async () => {
  const { seedNotes } = load('tools/fixtures/SeedContent.ets'); const f = backupFileFixture();
  assert.equal(await f.service.exportFile({ filesDir: '/sandbox' }, seedNotes(), []), true);
  const backup = JSON.parse(f.files.get('/picked/backup.json').toString());
  const index = backup.notes.findIndex(note => note.id === 'note-seed-pdf'); assert.ok(index >= 0);
  const note = await f.service.materialize({ filesDir: '/sandbox' }, backup, index, StudyBackupPolicy.restoreTitle(backup, index));
  assert.ok(note.id.startsWith('note-seed-')); assert.equal(note.sourceUri, undefined); assert.equal(note.pageCount, 9);
  assert.equal(note.pageAnnotations, backup.notes[index].pageAnnotations);
});
test('backup picker cancellation performs no output and partial reads fail explicitly', async () => {
  const cancelled = backupFileFixture({ selected: [] });
  assert.equal(await cancelled.service.exportFile({ filesDir: '/sandbox' }, [studyNote()], []), false);
  assert.equal(await cancelled.service.selectFile({ filesDir: '/sandbox' }), null);
  assert.equal(cancelled.files.size, 0);
  const partial = backupFileFixture({ shortRead: true });
  partial.files.set('/picked/backup.json', Buffer.from(JSON.stringify(studyBackup())));
  await assert.rejects(partial.service.selectFile({ filesDir: '/sandbox' }), /未完整读取/);
  assert.equal(partial.calls.filter(c => c[0] === 'close').length, 1);
});
test('backup restoration writes only decoded asset views and verifies real PDF pages', async () => {
  const f = backupFileFixture(); const backup = studyBackup();
  backup.assets = [{ noteId: 'course_note', kind: 'pdf', data: Buffer.from('%PDF-1.7\noriginal').toString('base64') }];
  const restored = await f.service.materialize({ filesDir: '/sandbox' }, backup, 0, '恢复副本');
  assert.ok(restored.sourceUri.startsWith('/sandbox/documents/restore_backup123_0_'));
  assert.equal(restored.pageCount, 2); assert.equal(f.files.get(restored.sourceUri).toString(), '%PDF-1.7\noriginal');
  assert.equal(backup.notes[0].id, 'course_note');
});
test('failed backup PDF or cover validation removes newly created attachments', async () => {
  for (const kind of ['pdf', 'cover']) {
    const f = backupFileFixture({ failPdf: kind === 'pdf', failImage: kind === 'cover' }); const backup = studyBackup();
    backup.assets = [{ noteId: 'course_note', kind, data: Buffer.from('bad asset').toString('base64') }];
    await assert.rejects(f.service.materialize({ filesDir: '/sandbox' }, backup, 0, '恢复副本'));
    assert.equal(f.files.size, 0); assert.equal(f.calls.filter(c => c[0] === 'unlink').length, 1);
    assert.equal(f.calls.filter(c => c[0] === 'close').length, 1);
    if (kind === 'cover') assert.equal(f.calls.filter(c => c[0] === 'image-release').length, 1);
  }
});

test('empty note libraries stay empty; corrupt or unreadable libraries never overwrite the snapshot', async () => {
  const empty = importService('', { initial: '[]' });
  assert.equal((await empty.service.load({ filesDir: '/sandbox' }, [studyNote()])).length, 0);
  assert.equal(empty.calls.length, 0);
  for (const initial of ['{broken', '{"not":"notes"}', JSON.stringify([studyNote()])]) {
    const f = importService('', { initial, readFails: true });
    await assert.rejects(f.service.load({ filesDir: '/sandbox' }, [studyNote()]));
    await assert.rejects(f.service.save([]), /阻止覆盖/);
    assert.equal(f.raw(), initial);
    assert.ok(!f.calls.some(call => Array.isArray(call) && ['write', 'snapshot'].includes(call[0])));
  }
});

function preferenceFixture(initial = {}) {
  const values = new Map(Object.entries(initial)); const writes = []; let fail = false;
  return { values, writes, fail: value => { fail = value; },
    prefs: { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
      put: async (key, value) => { values.set(key, value); writes.push([key, value]); },
      flush: async () => { if (fail) throw Error('disk full'); } } };
}

test('queued snapshot failures restore the cache and do not stall the next write', async () => {
  const f = preferenceFixture({ notes: '[1]' });
  const { SnapshotStore } = load(`${base}services/storage/SnapshotStore.ets`, { '@kit.ArkData': {} });
  const store = new SnapshotStore(); f.fail(true);
  await assert.rejects(store.write(f.prefs, 'notes', '[2]'), /保存未完成/);
  assert.equal(f.values.get('notes'), '[1]');
  f.fail(false); await store.write(f.prefs, 'notes', '[3]'); assert.equal(f.values.get('notes'), '[3]');
});

test('an unreadable preference read blocks subsequent writes to that key', async () => {
  const { SnapshotStore } = load(`${base}services/storage/SnapshotStore.ets`, { '@kit.ArkData': {} });
  const store = new SnapshotStore(); let writes = 0;
  const prefs = { get: async () => { throw Error('I/O'); }, put: async () => { writes++; }, flush: async () => {} };
  await assert.rejects(store.read(prefs, 'notes', Array.isArray));
  await assert.rejects(store.write(prefs, 'notes', '[]'), /阻止覆盖/); assert.equal(writes, 0);
});

test('todo corruption preserves both raw data and the independent day-note key', async () => {
  const f = preferenceFixture({ todos: '{broken', daynotes: '[]' });
  const { TodoStorageService } = load(`${base}services/TodoStorageService.ets`, {
    '@kit.ArkData': { preferences: { getPreferences: async () => f.prefs } }
  });
  const service = new TodoStorageService(); await assert.rejects(service.loadTodos({}));
  await assert.rejects(service.saveTodos({}, []), /阻止覆盖/); assert.equal(f.values.get('todos'), '{broken');
  await service.saveDayNotes({}, [{ date: '2026-10-06', text: '课表' }]);
  assert.equal((await service.loadDayNotes({}))[0].text, '课表');
});

function atomicFixture({ shortWrite = false, syncFails = false } = {}) {
  const files = new Map([['/note.md', 'last valid']]); const calls = []; const opened = new Map(); let fd = 0;
  const { AtomicTextFile } = load(`${base}services/storage/AtomicTextFile.ets`, {
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return Buffer.from(text); } } } },
    '@kit.CoreFileKit': { fileIo: { OpenMode: { WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 },
      open: async file => { opened.set(++fd, file); files.set(file, ''); return { fd }; },
      write: async (descriptor, text) => { files.set(opened.get(descriptor), text); calls.push(['write', text]); return Buffer.byteLength(text) - (shortWrite ? 1 : 0); },
      fsync: async () => { if (syncFails) throw Error('sync failed'); }, close: async () => {},
      rename: async (from, to) => { calls.push(['rename', from, to]); files.set(to, files.get(from)); files.delete(from); },
      access: async file => files.has(file), unlink: async file => files.delete(file) } }
  });
  return { files, calls, AtomicTextFile };
}

test('short writes and fsync failures preserve the previous Markdown and remove temporary files', async () => {
  for (const options of [{ shortWrite: true }, { syncFails: true }]) {
    const f = atomicFixture(options); await assert.rejects(new f.AtomicTextFile().write('/note.md', '新的正文 📚'));
    assert.equal(f.files.get('/note.md'), 'last valid'); assert.equal(f.files.size, 1);
    assert.ok(!f.calls.some(call => call[0] === 'rename'));
  }
});

test('separate Markdown writers serialize replacement and compare UTF-8 byte counts', async () => {
  const f = atomicFixture();
  await Promise.all([new f.AtomicTextFile().write('/note.md', '第一版 📚'), new f.AtomicTextFile().write('/note.md', '第二版 📖')]);
  assert.equal(f.files.get('/note.md'), '第二版 📖'); assert.equal(f.files.size, 1);
  assert.deepEqual(f.calls.map(call => call[0]), ['write', 'rename', 'write', 'rename']);
});

test('reader commits serialize autosave and exit, preserve PDF indexing, and publish only after persistence', async () => {
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  const service = new ReaderCommitService(); let notes = [studyNote({ pdfTextJson: 'latest index' })]; let unblock;
  const calls = []; let count = 0;
  const ports = { notes: () => notes, saveDocument: async () => { calls.push('document'); },
    saveNotes: async () => { calls.push('save'); if (++count === 1) await new Promise(resolve => { unblock = resolve; }); },
    publish: (next, note) => { notes = next; calls.push(note.contentDetail); } };
  const first = service.commit(studyNote({ pdfTextJson: 'stale index' }), 'autosave', ports, true);
  const second = service.commit(studyNote(), 'exit-save', ports, true);
  await new Promise(resolve => setImmediate(resolve)); assert.equal(notes[0].contentDetail, studyNote().contentDetail);
  assert.deepEqual(calls, ['document', 'save']); unblock(); await Promise.all([first, second]);
  assert.equal(notes[0].contentDetail, 'exit-save'); assert.equal(notes[0].pdfTextJson, 'latest index');
  assert.deepEqual(calls, ['document', 'save', 'autosave', 'document', 'save', 'exit-save']);
  const before = notes; ports.saveNotes = async () => { throw Error('disk'); };
  await assert.rejects(service.commit(studyNote(), 'failed', ports)); assert.equal(notes, before);
});

test('actual PDF and handwriting autosave methods wait for storage and ignore obsolete status updates', async () => {
  for (const relative of ['views/reader/pdf/PdfAnnotatorView.ets', 'views/reader/HandwritingCanvas.ets']) {
    const source = fs.readFileSync(path.join(root, base, relative), 'utf8');
    const method = source.match(/private async flushSave\(\): Promise<void> \{([\s\S]*?)\n  \}/)?.[1]; assert.ok(method);
    const output = ts.transpileModule(`module.exports = async function() {${method}}`, { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
    const context = { module: { exports: {} } }; vm.runInNewContext(output, context); const flush = context.module.exports;
    const statuses = []; let release;
    const view = { saveRevision: 1, loadedNoteId: studyNote().id, strokeSnapshot: studyNote, annotationSnapshot: studyNote,
      onSaved: () => new Promise(resolve => { release = resolve; }), onSaveStateChange: value => statuses.push(value) };
    const running = flush.call(view); await Promise.resolve(); assert.equal(statuses.length, 0);
    view.saveRevision++; release(); await running; assert.equal(statuses.length, 0);
    view.onSaved = async () => { throw Error('disk'); }; await flush.call(view); assert.deepEqual(statuses, ['保存失败']);
    view.loadedNoteId = 'other-document'; view.onSaved = async () => {}; await flush.call(view);
    assert.deepEqual(statuses, ['保存失败']);
  }
});

const { NearbyTransferPolicy } = load(`${base}services/sync/NearbyTransferPolicy.ets`);
const transferDigest = async content => createHash('sha256').update(content).digest('hex');

test('nearby packets preserve full attachments, Unicode boundaries, annotations and cards without secrets or local paths', async () => {
  const backup = studyBackup(); backup.notes[0].contentDetail = '📚'.repeat(40000);
  backup.notes[0].apiKey = 'private-key'; backup.notes[0].sourceUri = '/private/source';
  backup.notes[0].pageAnnotations = '{"pages":[]}';
  backup.assets = [{ noteId: backup.notes[0].id, kind: 'cover', data: Buffer.from('original bytes').toString('base64') }];
  const packet = await NearbyTransferPolicy.pack(backup, transferDigest);
  const restored = await NearbyTransferPolicy.unpack(backup.id, JSON.stringify(packet.manifest), packet.parts.reverse(), transferDigest);
  assert.equal(restored.notes[0].contentDetail, backup.notes[0].contentDetail);
  assert.equal(restored.notes[0].pageAnnotations, backup.notes[0].pageAnnotations);
  assert.deepEqual(plain(restored.assets), backup.assets); assert.deepEqual(plain(restored.cards), plain(backup.cards));
  assert.ok(!JSON.stringify(restored).includes('private-key')); assert.ok(!JSON.stringify(restored).includes('/private/source'));
});

test('nearby reception rejects missing, duplicate, corrupted, expired or unsupported packets before import', async () => {
  const backup = studyBackup(); backup.notes[0].contentDetail = 'A'.repeat(70000);
  const now = Date.now(); const packet = await NearbyTransferPolicy.pack(backup, transferDigest, now);
  const manifest = JSON.stringify(packet.manifest);
  await assert.rejects(NearbyTransferPolicy.unpack(backup.id, manifest, packet.parts.slice(1), transferDigest, now), /完整接收/);
  await assert.rejects(NearbyTransferPolicy.unpack(backup.id, manifest, [...packet.parts, packet.parts[0]], transferDigest, now), /重复/);
  const changed = plain(packet.parts); const original = JSON.parse(changed[0].value);
  changed[0].value = JSON.stringify('X' + original.slice(1));
  await assert.rejects(NearbyTransferPolicy.unpack(backup.id, manifest, changed, transferDigest, now), /完整性校验失败/);
  await assert.rejects(NearbyTransferPolicy.unpack(backup.id, manifest, packet.parts, transferDigest, now + NearbyTransferPolicy.LIFETIME + 1), /过期/);
  await assert.rejects(NearbyTransferPolicy.unpack(backup.id, JSON.stringify({ ...packet.manifest, version: 2 }), packet.parts, transferDigest, now), /不受支持/);
  assert.throws(() => NearbyTransferPolicy.prefix('../other'));
  await assert.rejects(NearbyTransferPolicy.pack({ ...backup, notes: [], cards: [], assets: [] }, transferDigest), /选择/);
});

function nearbyFixture({ denied = false, unsupported = false, deferStore = false } = {}) {
  const data = new Map(); const calls = []; let listener = null; let timeout = null; let openStore;
  const store = { getEntries: async prefix => [...data].filter(([key]) => key.startsWith(prefix)).map(([key, value]) => ({ key, value: { value } })),
    put: async (key, value) => { data.set(key, value); }, delete: async key => { data.delete(key); },
    on: (event, callback) => { listener = callback; calls.push('on'); }, off: (event, callback) => { if (listener === callback) listener = null; calls.push('off'); },
    sync: (ids, query, mode) => calls.push(['sync', ids, query.prefix, mode]) };
  const { HarmonyNearbyService } = load(`${base}services/sync/HarmonyNearbyService.ets`, {
    canIUse: () => !unsupported,
    setTimeout: (callback, delay) => { timeout = callback; assert.equal(delay, 45000); return 1; }, clearTimeout: () => { timeout = null; },
    '@kit.AbilityKit': { abilityAccessCtrl: { createAtManager: () => ({ requestPermissionsFromUser: async () => {
      calls.push('permission'); return { authResults: [denied ? -1 : 0] }; } }) } },
    '@kit.ArkData': { distributedKVStore: { createKVManager: () => ({ getKVStore: async (id, options) => {
      calls.push(['options', options]); if (deferStore) await new Promise(resolve => { openStore = resolve; }); return store;
    }, closeKVStore: async () => calls.push('store-close') }),
      KVStoreType: { SINGLE_VERSION: 1 }, SecurityLevel: { S2: 2 }, SyncMode: { PUSH_ONLY: 0, PULL_ONLY: 1 },
      Query: class { prefixKey(prefix) { this.prefix = prefix; return this; } } } },
    '@kit.DistributedServiceKit': { distributedDeviceManager: { createDeviceManager: () => ({ getAvailableDeviceListSync: () => [
      { networkId: 'trusted', deviceName: '我的 Pad' }, { deviceName: 'not available' }] }), releaseDeviceManager: () => calls.push('device-release') } },
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return Buffer.from(text); } } } },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: () => { let content; return {
      update: async ({ data }) => { content = data; }, digest: async () => ({ data: createHash('sha256').update(content).digest() }) }; } } }
  });
  return { service: new HarmonyNearbyService(), data, calls, ack: (id = 'trusted', code = 0) => listener?.([[id, code]]),
    timeout: () => timeout?.(), listening: () => !!listener, openStore: () => openStore?.() };
}

test('nearby permission is requested only on explicit connection and database uses encrypted manual scoped sync', async () => {
  const f = nearbyFixture(); assert.equal(f.calls.length, 0);
  const devices = await f.service.connect({}); assert.equal(devices.length, 1);
  const options = f.calls.find(call => Array.isArray(call) && call[0] === 'options')[1];
  assert.equal(options.encrypt, true); assert.equal(options.autoSync, false); assert.equal(options.backup, false);
  await assert.rejects(f.service.send('unknown', studyBackup()), /离线/);
  const denied = nearbyFixture({ denied: true }); await assert.rejects(denied.service.connect({}), /未授权/);
  assert.ok(!denied.calls.some(call => Array.isArray(call)));
  const unsupported = nearbyFixture({ unsupported: true }); await assert.rejects(unsupported.service.connect({}), /不支持/);
  assert.equal(unsupported.calls.length, 0);
  await f.service.close(); assert.ok(f.calls.includes('device-release')); assert.ok(f.calls.includes('store-close'));
});

test('nearby send waits for the selected peer acknowledgement and always removes completion listeners', async () => {
  const f = nearbyFixture(); await f.service.connect({}); let done = false;
  const sending = f.service.send('trusted', studyBackup()).then(code => { done = true; return code; });
  await new Promise(resolve => setImmediate(resolve)); assert.equal(done, false); assert.equal(f.listening(), true);
  f.ack('other'); await Promise.resolve(); assert.equal(done, false);
  f.ack(); const code = await sending; assert.equal(code, studyBackup().id); assert.equal(f.listening(), false);
  assert.deepEqual(plain(f.calls.find(call => Array.isArray(call) && call[0] === 'sync').slice(1)), [['trusted'], NearbyTransferPolicy.prefix(code), 0]);
  await f.service.close(); assert.equal(f.data.size, 0);
});

test('nearby receive requires acknowledgement, checks the complete package, and never accepts partial data', async () => {
  const f = nearbyFixture(); await f.service.connect({}); const backup = studyBackup();
  const packet = await NearbyTransferPolicy.pack(backup, transferDigest); const prefix = NearbyTransferPolicy.prefix(backup.id);
  for (const part of packet.parts) f.data.set(part.key, part.value);
  f.data.set(prefix + 'manifest', JSON.stringify(packet.manifest));
  const receiving = f.service.receive('trusted', backup.id); await new Promise(resolve => setImmediate(resolve)); f.ack();
  assert.equal((await receiving).notes[0].id, backup.notes[0].id);
  f.data.delete(packet.parts[0].key);
  const partial = f.service.receive('trusted', backup.id); await new Promise(resolve => setImmediate(resolve)); f.ack();
  await assert.rejects(partial, /完整接收/); await f.service.close();
});

test('nearby timeout, peer failure and page closure reject pending work and require a new connection', async () => {
  for (const fail of ['timeout', 'peer', 'close']) {
    const f = nearbyFixture(); await f.service.connect({});
    const sending = f.service.send('trusted', studyBackup());
    const rejected = assert.rejects(sending, /超时|未完成|关闭/);
    await new Promise(resolve => setImmediate(resolve));
    if (fail === 'timeout') f.timeout(); else if (fail === 'peer') f.ack('trusted', 1); else await f.service.close();
    await rejected; assert.equal(f.listening(), false);
    await assert.rejects(f.service.send('trusted', studyBackup()), /连接已结束/); await f.service.close();
  }
});

test('shared study import resumes a partial batch and maps cards to stable restored IDs', async () => {
  let notes = []; const cards = []; let fail = true; let materializations = 0;
  const { StudyImportService } = load(`${base}services/study/StudyImportService.ets`, {
    [path.resolve(root, `${base}services/study/StudyBackupService.ets`)]: { StudyBackupService: {
      materialize: async (context, backup, index, title) => {
        materializations++; return { ...backup.notes[index], id: StudyBackupPolicy.restoreId(backup, index), title };
      } } }
  });
  const backup = studyBackup(); backup.notes.push(studyNote({ id: 'second' })); const progress = [];
  const ports = { notes: () => notes, progress: message => progress.push(message), commit: async (note, items) => {
    if (note.id.endsWith('_1') && fail) throw Error('disk full');
    if (!notes.some(item => item.id === note.id)) notes.push(note);
    for (const card of items) if (!cards.some(item => item.id === card.id)) cards.push(card);
  } };
  await assert.rejects(StudyImportService.restore({}, backup, ports), /已导入 1 份/);
  assert.equal(notes.length, 1); fail = false;
  const result = await StudyImportService.restore({}, backup, ports);
  assert.deepEqual(plain(result), { imported: 1, skipped: 1 }); assert.equal(notes.length, 2);
  assert.equal(materializations, 3); assert.ok(cards.every(card => notes.some(note => note.id === card.noteId)));
  assert.equal(cards.length, backup.cards.length); assert.equal(progress.length, 4);
});

test('shared study import rejects unsupported packages before materializing or committing any data', async () => {
  let calls = 0;
  const { StudyImportService } = load(`${base}services/study/StudyImportService.ets`, {
    [path.resolve(root, `${base}services/study/StudyBackupService.ets`)]: { StudyBackupService: { materialize: async () => { calls++; } } }
  });
  await assert.rejects(StudyImportService.restore({}, { ...studyBackup(), schemaVersion: 99 }, {
    notes: () => [], commit: async () => { calls++; }, progress: () => {} })); assert.equal(calls, 0);
});

test('closing while nearby database creation is pending also closes the late database instance', async () => {
  const f = nearbyFixture({ deferStore: true }); const connecting = f.service.connect({});
  const rejected = assert.rejects(connecting, /无法初始化/);
  await new Promise(resolve => setImmediate(resolve)); await f.service.close(); f.openStore(); await rejected;
  assert.equal(f.calls.filter(call => call === 'store-close').length, 2);
  assert.equal(f.calls.filter(call => call === 'device-release').length, 1); assert.equal(f.listening(), false);
});

test('reader field ownership preserves simultaneous text, PDF, main handwriting, scratchpad and library metadata', async () => {
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  const service = new ReaderCommitService(); const stale = studyNote({ favorite: false, category: 'old', coverUrl: 'cover:old',
    pdfTextJson: 'old', pageAnnotations: 'old pdf', strokes: 'old ink', scratchpadStrokes: 'old scratch' });
  let notes = [studyNote({ favorite: true, category: 'new', coverUrl: 'cover:mist', tags: ['current'], pdfTextJson: 'current' })];
  const ports = { notes: () => notes, saveDocument: async () => {}, saveNotes: async () => {}, publish: next => { notes = next; } };
  await Promise.all([
    service.commit({ ...stale, title: '新标题' }, '新正文', ports, true, 'markdown'),
    service.commit({ ...stale, pageAnnotations: 'new pdf' }, stale.contentDetail, ports, true, 'pdf'),
    service.commit({ ...stale, strokes: 'new ink' }, stale.contentDetail, ports, true, 'handwriting'),
    service.commit({ ...stale, scratchpadStrokes: 'new scratch' }, stale.contentDetail, ports, true, 'scratchpad')
  ]);
  assert.equal(notes[0].title, '新标题'); assert.equal(notes[0].contentDetail, '新正文');
  assert.equal(notes[0].pageAnnotations, 'new pdf'); assert.equal(notes[0].strokes, 'new ink'); assert.equal(notes[0].scratchpadStrokes, 'new scratch');
  assert.equal(notes[0].favorite, true); assert.equal(notes[0].category, 'new'); assert.equal(notes[0].coverUrl, 'cover:mist');
  assert.equal(notes[0].pdfTextJson, 'current'); assert.deepEqual(plain(notes[0].tags), ['current']);
});

test('reader commits re-read the library after file persistence and do not resurrect a deleted record', async () => {
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  const service = new ReaderCommitService(); let notes = [studyNote()]; let writes = 0;
  const ports = { notes: () => notes, saveDocument: async () => { notes = notes.concat(studyNote({ id: 'newly-added' })); },
    saveNotes: async () => { writes++; }, publish: next => { notes = next; } };
  await service.commit(studyNote(), 'new text', ports, true); assert.equal(notes.length, 2);
  ports.saveDocument = async () => { notes = notes.filter(note => note.id !== 'course_note'); };
  await assert.rejects(service.commit(studyNote(), 'stale', ports, true), /移除/);
  assert.equal(notes.length, 1); assert.equal(writes, 1);
});

const { AiModelCatalog } = load('tools/fixtures/AiModelCatalog.ets');
test('cloud directory stays unavailable and editing returned rows cannot alter its templates', () => {
  assert.equal(AiModelCatalog.CLOUD_AVAILABLE, false);
  assert.deepEqual(plain(AiModelCatalog.FAMILIES), ['Seed','Qwen','DeepSeek','GLM']);
  const models = AiModelCatalog.list(); assert.equal(new Set(models.map(m => m.id)).size, models.length);
  const first = models[0]; first.apiEndpoint = 'http://untrusted';
  assert.ok(AiModelCatalog.find(first.id).apiEndpoint.startsWith('https://'));
  assert.equal(AiModelCatalog.list('unknown').length, 0);
  assert.equal(AiModelCatalog.createApiDraft('unknown'), null);
});
const localContext = (notes = [], pinned = []) => ({ notes, pinned, todos: [] });

const penEnums = { SourceTool:{Unknown:0,Finger:1,Pen:2,MOUSE:3,TOUCHPAD:4},TouchType:{Down:0,Up:1,Move:2,Cancel:3} };
const { InkInputService } = load(`${base}services/ink/InkInputService.ets`,penEnums);

test('enabled pointer ink accepts emulator mouse and touchpad while the stylus-only switch still blocks them', () => {
  for (const sourceTool of [penEnums.SourceTool.MOUSE, penEnums.SourceTool.TOUCHPAD]) {
    const event = { type: 0, sourceTool, touches: [{ id: 1, x: 10, y: 20 }], changedTouches: [{ id: 1, x: 10, y: 20 }] };
    assert.equal(new InkInputService().read(event, false).phase, 'ignore');
    const input = new InkInputService(); assert.equal(input.read(event, true).phase, 'begin');
    assert.equal(input.read({ ...event, type: 1 }, true).phase, 'end');
    assert.equal(new InkInputService().read({ ...event, sourceTool: 0 }, true).phase, 'ignore');
  }
});
function touchEvent(type, id=7, sourceTool=2, overrides={}) {
  const point={id,x:10,y:20,pressure:32768};
  return {type,sourceTool,pressure:0.5,changedTouches:[point],touches:type===1?[]:[point],getHistoricalPoints:()=>[],...overrides};
}
test('stylus tracks its own pointer through palms and uses the final changedTouches sample', () => {
  const input=new InkInputService();
  assert.equal(input.read(touchEvent(0,1,1),false).phase,'ignore');
  assert.equal(input.read(touchEvent(0),false).phase,'begin');
  assert.equal(input.read(touchEvent(0,1,1),true).phase,'ignore');
  assert.equal(input.read(touchEvent(1,1,1),true).phase,'ignore');
  const moved=input.read(touchEvent(2,7,2,{changedTouches:[{id:1,x:1,y:1},{id:7,x:30,y:40}],
    getHistoricalPoints:()=>[{touchObject:{id:7,x:15,y:25},force:16384},{touchObject:{id:1,x:99,y:99},force:65535}]}),false);
  assert.equal(moved.phase,'move');assert.equal(moved.samples.length,2);assert.equal(moved.samples[0].x,15);
  assert.ok(Math.abs(moved.samples[0].pressure-0.25)<0.001);
  assert.equal(input.read(touchEvent(1),false).phase,'end');
  assert.equal(input.read(touchEvent(0,1,1),true).phase,'ignore');
});
test('multitouch cancels finger ink instead of drawing a pinch gesture; orphaned moves are ignored', () => {
  const input=new InkInputService();assert.equal(input.read(touchEvent(0,1,1),true).phase,'begin');
  assert.equal(input.read(touchEvent(2,1,1,{touches:[{id:1,x:1,y:1},{id:2,x:2,y:2}]}),true).phase,'cancel');
  assert.equal(input.read(touchEvent(2,1,1),true).phase,'ignore');
  assert.equal(input.read(touchEvent(0,7,2),false).phase,'begin');
  assert.equal(input.read(touchEvent(3,7,2,{changedTouches:[],touches:[]}),false).phase,'cancel');
});
test('ink pressure has a bounded fallback and rejects invalid coordinates', () => {
  assert.equal(InkInputService.pressure(undefined),0.5);assert.equal(InkInputService.pressure(NaN),0.5);
  assert.equal(InkInputService.pressure(-1),0);assert.equal(InkInputService.pressure(65535,true),1);assert.equal(InkInputService.pressure(1.2),1);
  assert.equal(new InkInputService().read(touchEvent(0,7,2,{changedTouches:[{id:7,x:NaN,y:20}]}),false).phase,'ignore');
});
const { InkRenderer } = load(`${base}services/ink/InkRenderer.ets`);
function inkRecorder() {
  const calls=[];const stack=[];
  const ctx={save(){stack.push({lineWidth:this.lineWidth,globalAlpha:this.globalAlpha,globalCompositeOperation:this.globalCompositeOperation});},restore(){Object.assign(this,stack.pop());},
    beginPath(){calls.push(['begin']);},moveTo(...args){calls.push(['move',...args]);},lineTo(...args){calls.push(['line',...args]);},
    quadraticCurveTo(...args){calls.push(['curve',...args]);},arc(...args){calls.push(['arc',...args]);},
    fill(){calls.push(['fill',this.lineWidth,this.globalAlpha,this.globalCompositeOperation]);},stroke(){calls.push(['stroke',this.lineWidth,this.globalAlpha,this.globalCompositeOperation]);}};
  return {ctx,calls};
}
test('incremental ink rendering stays constant per sample, varies with pressure and ends at the final point', () => {
  const points=Array.from({length:10000},(_,i)=>({x:i,y:i*2,pressure:0.2}));const f=inkRecorder();
  const style={color:'#111',width:4,highlighter:false,eraser:false};
  InkRenderer.segment(f.ctx,points,points.length-1,style);assert.ok(f.calls.length<10);
  const thin=f.calls.find(c=>c[0]==='stroke')[1];points.at(-1).pressure=1;f.calls.length=0;
  InkRenderer.segment(f.ctx,points,points.length-1,style);assert.ok(f.calls.find(c=>c[0]==='stroke')[1]>thin);
  InkRenderer.tail(f.ctx,points,style);assert.deepEqual(f.calls.filter(c=>c[0]==='line').at(-1),['line',9999,19998]);
});
test('eraser reveals the underlying page and highlighter replay is one translucent path', () => {
  const points=[{x:1,y:2},{x:20,y:30},{x:40,y:50}];const f=inkRecorder();
  InkRenderer.stroke(f.ctx,points,{color:'#111',width:4,highlighter:false,eraser:true});
  assert.ok(f.calls.filter(c=>['stroke','fill'].includes(c[0])).every(c=>c[3]==='destination-out'));
  f.calls.length=0;InkRenderer.stroke(f.ctx,points,{color:'#ff0',width:14,highlighter:true,eraser:false});
  assert.equal(f.calls.filter(c=>c[0]==='stroke').length,1);assert.equal(f.calls.find(c=>c[0]==='stroke')[2],0.35);
  assert.equal(InkRenderer.nearSegment(50,3,0,0,100,0,5),true);assert.equal(InkRenderer.nearSegment(50,20,0,0,100,0,5),false);
});
test('pen shortcuts subscribe once, follow the focused canvas and unregister exact callbacks', () => {
  const subscriptions=new Map();const removed=[];let left=0,right=0;
  const {StylusShortcutService}=load(`${base}services/ink/StylusShortcutService.ets`,{
    '@kit.Penkit':{stylusInteraction:{on:(event,cb)=>{const rows=subscriptions.get(event)||[];rows.push(cb);subscriptions.set(event,rows);},
      off:(event,cb)=>removed.push([event,cb])}}
  });
  const a=new StylusShortcutService(),b=new StylusShortcutService();
  a.start(()=>true,()=>left++,()=>left++);b.start(()=>true,()=>right++,()=>right++);
  for(const cb of subscriptions.get('doubleTap'))cb({timestamp:1});assert.equal(left,1);assert.equal(right,0);
  b.claim();for(const cb of subscriptions.get('squeeze'))cb({timestamp:2});assert.equal(left,1);assert.equal(right,1);
  a.stop();b.stop();assert.equal(removed.length,4);
  assert.ok(removed.every(([event,cb])=>subscriptions.get(event).includes(cb)));
});
function fakeTimers() {
  const jobs=new Map();let id=0;
  return {jobs,setTimeout:(fn,delay)=>{jobs.set(++id,{fn,delay});return id;},clearTimeout:key=>jobs.delete(key),
    fire:delay=>{const entry=[...jobs].find(([,value])=>value.delay===delay);assert.ok(entry,`timer ${delay}`);jobs.delete(entry[0]);entry[1].fn();}};
}

function viewMethod(relative,name,globals={}) {
  const source=fs.readFileSync(path.join(root,base,relative),'utf8').replaceAll('\r\n','\n');
  const marker=[`private async ${name}(`,`private ${name}(`,`async ${name}(`,`${name}(`].find(value=>source.includes(`  ${value}`));
  const start=source.indexOf(marker);assert.ok(start>=0,name);const end=source.indexOf('\n  }',start)+4;
  const method=source.slice(start,end).replace('private ','');
  const output=ts.transpileModule(`class Subject {${method}}; module.exports=Subject.prototype.${name};`,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
  const context={module:{exports:{}},console,getContext:()=>({}),clearTimeout,setTimeout,...globals};vm.runInNewContext(output,context);return context.module.exports;
}
test('actual note creation preserves the requested type, awaits both writes and keeps failures reviewable', async () => {
  const create=viewMethod('pages/Index.ets','createNote');let release;const calls=[];
  const original=studyNote({id:'original'});
  const view={notes:[original],noteCreateBusy:false,noteCreateError:'',activeSpaceName:()=>'',formatTime:()=>'',
    storage:{create:async(_,note)=>calls.push(note.type),save:()=>new Promise(resolve=>{release=resolve;})},
    rebuildSpaces(){},refreshGraph(){},openNote(note){calls.push(note);},notify(){}};
  const running=create.call(view,'手写日记','Handwriting','我的课程');await Promise.resolve();await Promise.resolve();
  assert.equal(view.noteCreateBusy,true);assert.equal(view.notes.length,1);assert.equal(calls.length,1);
  assert.equal(await create.call(view,'重复','Markdown'),false);release();assert.equal(await running,true);
  assert.equal(view.notes[0].type,'Handwriting');assert.equal(view.notes[0].strokes,'[]');assert.equal(view.notes[0].category,'我的课程');
  const before=view.notes;view.storage.create=async()=>{throw Error('disk');};assert.equal(await create.call(view,'失败'),false);
  assert.equal(view.notes,before);assert.equal(view.noteCreateBusy,false);assert.match(view.noteCreateError,/创建失败/);
});

function pdfHistoryView() {
  const relative='views/reader/pdf/PdfAnnotatorView.ets';let saved=0;
  const view={pageStrokes:{0:[]},undoStack:[],redoStack:[],eraseBefore:null,erasePage:-1,eraserWidth:20,currentPageIdx:0,scheduleSave:()=>saved++,activeInputFinisher:null,activeInputPage:-1};
  for(const method of ['remember','handleStrokeAdded','beginErase','finishErase','handleEraseAtPoint','handleUndo','onRedoTriggered','onClearTriggered','finishActiveInput'])
    view[method]=viewMethod(relative,method,{InkRenderer, CanvasStrokeEraser});
  return {view,saved:()=>saved};
}

const { CanvasStrokeEraser } = load(`${base}services/ink/CanvasStrokeEraser.ets`);
const { InkToolPolicy } = load(`${base}services/ink/InkToolPolicy.ets`);

test('tool size bounds clamp invalid input without confusing pen, highlighter and eraser', () => {
  for (const [tool, min, max] of [['pen', 1, 16], ['highlighter', 6, 32], ['eraser', 8, 64]]) {
    assert.equal(InkToolPolicy.width(tool, NaN), min);
    assert.equal(InkToolPolicy.width(tool, -1), min);
    assert.equal(InkToolPolicy.width(tool, 999), max);
    assert.equal(InkToolPolicy.width(tool, max - 0.4), max);
  }
});

function inkSelectionHarness() {
  const selected = []; let finishes = 0;
  const view = { readOnly: false, loadError: '', isEraser: false, isHighlighter: false,
    selectedWidth: 3, selectedColor: '#123456', penWidth: 3, penColor: '#123456', highlighterWidth: 14,
    highlighterColor: '#EAB308', eraserWidth: 18, shortcuts: { claim() {} },
    eraserMode: 'area', onToolStateChange() {}, finishStroke: () => finishes++, onToolChange: tool => selected.push(tool) };
  for (const method of ['activeTool', 'rememberInkSettings', 'selectPen', 'selectHighlighter', 'toggleEraser', 'changeWidth', 'changeColor', 'emitToolState']) {
    view[method] = viewMethod('views/reader/HandwritingCanvas.ets', method, { InkToolPolicy });
  }
  return { view, selected, finishes: () => finishes };
}

test('whiteboard slider and color changes preserve the selected tool and remember each ink size', () => {
  const { view: v, selected } = inkSelectionHarness();
  v.changeWidth(7); v.selectHighlighter(); v.changeWidth(24); v.changeColor('#4ADE80');
  assert.equal(v.activeTool(), 'highlighter'); assert.equal(v.selectedWidth, 24);
  v.selectPen(); assert.equal(v.selectedWidth, 7); assert.equal(v.selectedColor, '#123456');
  v.selectHighlighter(); assert.equal(v.selectedWidth, 24); assert.equal(v.selectedColor, '#4ADE80');
  assert.deepEqual(selected, ['highlighter', 'pen', 'highlighter']);
});

test('stylus eraser shortcut restores highlighter and changing eraser size never selects the pen', () => {
  const { view: v, selected, finishes } = inkSelectionHarness();
  v.selectHighlighter(); v.changeWidth(20); v.toggleEraser(); v.changeWidth(48); v.changeColor('#FFFFFF');
  assert.equal(v.activeTool(), 'eraser'); assert.equal(v.eraserWidth, 48); assert.equal(v.selectedColor, '#EAB308');
  v.toggleEraser(); assert.equal(v.activeTool(), 'highlighter'); assert.equal(v.selectedWidth, 20);
  assert.deepEqual(selected, ['highlighter', 'eraser', 'highlighter']); assert.ok(finishes() >= 4);
});

test('read-only and damaged canvases refuse slider, color and tool changes', () => {
  for (const change of [{ readOnly: true }, { loadError: 'broken ink' }]) {
    const { view: v, finishes } = inkSelectionHarness(); Object.assign(v, change);
    v.selectHighlighter(); v.toggleEraser(); v.changeWidth(12); v.changeColor('blue');
    assert.equal(v.activeTool(), 'pen'); assert.equal(v.selectedWidth, 3); assert.equal(finishes(), 0);
  }
});

test('PDF tool selection remembers width and color and hardware eraser restores the previous ink', () => {
  const select = viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets', 'selectPdfTool');
  const width = viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets', 'changePdfWidth', { InkToolPolicy });
  const v = { currentTool: 'pen', selectedWidth: 7, selectedColor: '#2563EB', penWidth: 3, penColor: '#DC2626',
    highlighterWidth: 14, highlighterColor: '#FACC15', eraserWidth: 20 };
  select.call(v, 'highlighter'); width.call(v, 26); v.selectedColor = '#4ADE80';
  select.call(v, 'eraser'); width.call(v, 40); assert.equal(v.currentTool, 'eraser'); assert.equal(v.previousInkTool, 'highlighter');
  select.call(v, v.previousInkTool); assert.equal(v.selectedWidth, 26); assert.equal(v.selectedColor, '#4ADE80');
  select.call(v, 'pen'); assert.equal(v.selectedWidth, 7); assert.equal(v.selectedColor, '#2563EB');
  select.call(v, 'pan'); assert.equal(v.currentTool, 'pan');
});

test('PDF eraser size scales with the displayed page and respects configured radius', () => {
  for (const width of [360, 720, 1440]) {
    for (const [size, erased] of [[8, false], [64, true]]) {
      const v = pdfHistoryView().view; v.eraserWidth = size;
      v.pageStrokes[0] = [{ id: 'a', width: 2, points: [{ u: 0.1, v: 0.5 }, { u: 0.9, v: 0.5 }] }];
      v.beginErase(0); v.handleEraseAtPoint(0, 0.5, 0.5 + 20 / 1000, width, 1000 * width / 720); v.finishErase(true);
      assert.equal(v.pageStrokes[0].length, erased ? 0 : 1);
    }
  }
});

test('new note creation persists independent project destination and topic tags', async () => {
  const create = viewMethod('pages/Index.ets', 'createNote'); let saved;
  const v = { notes: [], noteCreateBusy: false, activeSpaceName: () => '', formatTime: () => '', notify() {},
    storage: { create: async (_, note) => { saved = note; }, save: async () => {} }, rebuildSpaces() {}, refreshGraph() {}, openNote() {} };
  assert.equal(await create.call(v, '微积分', 'Markdown', '数学课程', '', ['复习', '课堂']), true);
  assert.equal(saved.category, '数学课程'); assert.equal(saved.tag, '复习'); assert.deepEqual(plain(saved.tags), ['复习', '课堂']);
});

test('new note submission honors an explicit unfiled destination and keeps the form on failure', async () => {
  const commit = viewMethod('pages/Index.ets', 'commitPendingCreate'); const calls = [];
  const v = { pendingCreate: { type: 'Markdown', projectName: '旧项目' }, activeSpaceName: () => '当前项目',
    createNote: async (...args) => { calls.push(args); return false; } };
  await commit.call(v, '标题', '未分类', ['课堂']); assert.equal(calls[0][2], '未分类'); assert.ok(v.pendingCreate);
  v.createNote = async () => true; await commit.call(v, '标题', '课程'); assert.equal(v.pendingCreate, null);
});
const { MarkerImportPolicy } = load(`${base}services/smart/MarkerImportPolicy.ets`, {
  [path.resolve(root, `${base}services/smart/SmartExtractService.ets`)]: { SMART_INPUT_LIMIT: 12000 } });
test('Marker Markdown and official success JSON preserve formulas, tables and order without treating raw structure as prose', () => {
  const markdown = '# 课程\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n$$x^2+y^2=1$$';
  assert.equal(MarkerImportPolicy.parse(markdown, false), markdown);
  assert.equal(MarkerImportPolicy.parse(JSON.stringify({ success: true, format: 'markdown', output: markdown, images: { 'img.png': 'base64' } }), true), markdown);
  for (const value of [{ success: false, error: 'engine' }, { success: 'false', output: markdown }, { format: 'json', output: '{}' }, { children: [] }, null, []]) {
    assert.throws(() => MarkerImportPolicy.parse(JSON.stringify(value), true));
  }
  assert.throws(() => MarkerImportPolicy.parse('x'.repeat(12001), false), /分段/);
});

function documentImportHarness({ fail = false, cancelled = () => false, text = '真实扫描文字', pdf = true, managed = false } = {}) {
  const calls = [], fsAdapter = { OpenMode: { READ_ONLY: 0 }, openSync: () => ({ fd: 1 }), closeSync: () => calls.push('closed'),
    statSync: () => ({ size: 300 }), readSync: (_, buffer) => { new Uint8Array(buffer).set(Buffer.from(pdf ? '%PDF-' : '# MD\n')); return 5; },
    readText: async () => text };
  const service = { savePdfToSandbox: async () => { calls.push('copied'); return '/sandbox/documents/extract.pdf'; },
    extractPages: async (_, start, end, scan, cancel, progress) => {
      calls.push([start, end, scan]); if (fail) throw Error('OCR failed'); if (cancel()) throw Error('cancel'); progress(start);
      return [{ pageNumber: start, text, method: 'ocr' }];
    }, removeManagedPdf: async (_, uri) => calls.push(['removed', uri]) };
  const { DocumentExtractService } = load(`${base}services/smart/DocumentExtractService.ets`, {
    '@kit.CoreFileKit': { fileIo: fsAdapter }, '@kit.AbilityKit': {},
    [path.resolve(root, `${base}services/smart/SmartExtractService.ets`)]: { SMART_INPUT_LIMIT: 12000 },
    [path.resolve(root, `${base}services/document/PdfDocumentService.ets`)]: { PdfDocumentService: { getInstance: () => service } } });
  const uri = managed ? '/sandbox/documents/original.pdf' : (pdf ? 'file://source.pdf' : 'file://result.md');
  return { calls, read: (start = 1, end = 1) => DocumentExtractService.read({ filesDir: '/sandbox' }, uri, start, end, cancelled, () => {}) };
}

test('local PDF extraction releases the source handle and temporary copy on success, error and cancellation', async () => {
  const success = documentImportHarness(); const result = await success.read();
  assert.match(result.text, /真实扫描文字/); assert.match(result.notice, /本机/); assert.equal(success.calls[0], 'closed');
  assert.deepEqual(success.calls.at(-1), ['removed', '/sandbox/documents/extract.pdf']);
  const failure = documentImportHarness({ fail: true }); await assert.rejects(failure.read()); assert.equal(failure.calls.at(-1)[0], 'removed');
  let checks = 0; const cancel = documentImportHarness({ cancelled: () => ++checks > 1 });
  await assert.rejects(cancel.read(), /取消/); assert.equal(cancel.calls.at(-1)[0], 'removed');
});

test('document extraction rejects oversized results and excessive page ranges without modifying a draft', async () => {
  const text = documentImportHarness({ pdf: false, text: '# 原文\n\n保留内容' }); assert.equal((await text.read()).text, '# 原文\n\n保留内容');
  const range = documentImportHarness(); await assert.rejects(range.read(1, 6), /1–5/); assert.ok(!range.calls.includes('copied'));
  const large = documentImportHarness({ text: 'x'.repeat(12001) }); await assert.rejects(large.read(), /页范围/); assert.equal(large.calls.at(-1)[0], 'removed');
});

test('extraction retains the library PDF on success, failure and cancellation without another copy', async () => {
  const success = documentImportHarness({ managed: true }); assert.match((await success.read()).text, /真实扫描文字/);
  const failure = documentImportHarness({ managed: true, fail: true }); await assert.rejects(failure.read());
  let checks = 0; const cancelled = documentImportHarness({ managed: true, cancelled: () => ++checks > 1 });
  await assert.rejects(cancelled.read(), /取消/);
  for (const result of [success, failure, cancelled]) {
    assert.ok(!result.calls.includes('copied')); assert.ok(!result.calls.some(call => Array.isArray(call) && call[0] === 'removed'));
    assert.ok(result.calls.includes('closed'));
  }
});

test('late document import cannot append into a closed or superseded extraction sheet; repeated taps use one picker', async () => {
  let release, picks = 0;
  class DocumentSelectOptions {}
  class DocumentViewPicker { async select() { picks++; return ['file://source.pdf']; } }
  const pick = viewMethod('views/layout/sheets/SmartExtractSheet.ets', 'pickDocument', {
    picker: { DocumentSelectOptions, DocumentViewPicker }, SMART_INPUT_LIMIT: 12000, AppStorage: { setOrCreate() {} },
    DocumentExtractService: { validateInput() {}, read: () => new Promise(resolve => { release = resolve; }) } });
  const v = { alive: true, requestId: 0, step: 'input', inputText: '保留草稿', pdfStart: '1', pdfEnd: '1',
    onImportSource: async () => '/sandbox/documents/original.pdf', busy() { return this.step !== 'input'; } };
  const pending = pick.call(v); await new Promise(resolve => setTimeout(resolve, 0)); await pick.call(v); assert.equal(picks, 1);
  v.requestId++; v.alive = false; release({ text: '晚到结果', notice: '' }); await pending; assert.equal(v.inputText, '保留草稿');
});

test('the extraction sheet waits for library persistence and reads only the saved local source', async () => {
  let saved; const reads = []; const drafts = [];
  const pick = viewMethod('views/layout/sheets/SmartExtractSheet.ets', 'pickDocument', {
    Error,
    picker: { DocumentSelectOptions: class {}, DocumentViewPicker: class { async select() { return ['file://source.pdf']; } } },
    SMART_INPUT_LIMIT: 12000, AppStorage: { setOrCreate: (_, text) => drafts.push(text) },
    DocumentExtractService: { validateInput() {}, read: async (_, uri) => { reads.push(uri); return { text: '本机文字', notice: '请校对' }; } } });
  const view = { alive: true, requestId: 0, step: 'input', inputText: '', pdfStart: '1', pdfEnd: '1', busy() { return this.step !== 'input'; },
    onImportSource: () => new Promise(resolve => { saved = resolve; }) };
  const pending = pick.call(view); await new Promise(resolve => setTimeout(resolve, 0)); assert.deepEqual(reads, []);
  saved('/sandbox/documents/original.pdf'); await pending;
  assert.deepEqual(reads, ['/sandbox/documents/original.pdf']); assert.equal(view.inputText, '本机文字');
  assert.match(view.sourceNotice, /已保存/); assert.deepEqual(drafts, ['本机文字']);
  view.onImportSource = async () => { throw Error('存储空间不足'); }; view.inputText = '保留原稿'; reads.length = 0;
  await pick.call(view); assert.deepEqual(reads, []); assert.equal(view.inputText, '保留原稿'); assert.match(view.errorMsg, /空间不足/);
});

test('closing during a durable file import suppresses late extraction and leaves the library save to finish', async () => {
  let finish; let reads = 0;
  const pick = viewMethod('views/layout/sheets/SmartExtractSheet.ets', 'pickDocument', {
    picker: { DocumentSelectOptions: class {}, DocumentViewPicker: class { async select() { return ['file://source.pdf']; } } },
    DocumentExtractService: { validateInput() {}, read: async () => { reads++; } } });
  const view = { alive: true, requestId: 0, step: 'input', inputText: '原稿', pdfStart: '1', pdfEnd: '1', busy() { return this.step !== 'input'; },
    onImportSource: () => new Promise(resolve => { finish = resolve; }) };
  const pending = pick.call(view); await new Promise(resolve => setTimeout(resolve, 0)); view.alive = false; view.requestId++;
  finish('/sandbox/documents/original.pdf'); await pending;
  assert.equal(reads, 0); assert.equal(view.inputText, '原稿');
});

const { WorkspaceNotePolicy } = load(`${base}services/WorkspaceNotePolicy.ets`);

test('home shelf sorts once for the same source and filter, then refreshes when the immutable library snapshot changes', () => {
  const display = viewMethod('views/workspace/HomeWorkspace.ets', 'displayNotes');
  const v = { recentNotes: [studyNote({ updatedAt: 1 }), studyNote({ id: 'b', updatedAt: 2 })], activeShelfFilter: 'all', cachedShelfSource: null,
    isPdfNote: n => n.type === 'PDF', isHandwritingNote: n => n.type === 'Handwriting' };
  const sorted = display.call(v); assert.equal(display.call(v), sorted); assert.equal(sorted[0].id, 'b');
  v.recentNotes = v.recentNotes.concat(studyNote({ id: 'c', updatedAt: 3 })); assert.equal(display.call(v)[0].id, 'c');
  assert.equal(v.recentNotes[0].updatedAt, 1); v.activeShelfFilter = 'favorite'; assert.equal(display.call(v).length, 0);
});

test('PDF erasing uses line segments and groups a gesture into one reversible operation', () => {
  const f=pdfHistoryView(),v=f.view;const a={id:'a',pageIndex:0,width:3,points:[{u:0,v:0.5},{u:1,v:0.5}]};
  const b={id:'b',pageIndex:0,width:3,points:[{u:0,v:0.8},{u:1,v:0.8}]};
  v.handleStrokeAdded(a);v.handleStrokeAdded(b);v.beginErase(0);v.handleEraseAtPoint(0,0.5,0.5,720,1000);v.finishErase(true);
  assert.equal(v.undoStack.length,3);assert.equal(v.pageStrokes[0].length,1);assert.equal(v.pageStrokes[0][0].id,'b');
  v.handleUndo();assert.equal(v.pageStrokes[0].length,2);v.onRedoTriggered();assert.equal(v.pageStrokes[0].length,1);
  v.onClearTriggered();assert.equal(v.pageStrokes[0].length,0);v.handleUndo();assert.equal(v.pageStrokes[0].length,1);
  v.handleStrokeAdded({...a,id:'new'});assert.equal(v.redoStack.length,0);
});

test('cancelled PDF erasing restores strokes without adding history or scheduling a write', () => {
  const f=pdfHistoryView(),v=f.view;v.handleStrokeAdded({id:'a',pageIndex:0,width:3,points:[{u:0,v:0.5},{u:1,v:0.5}]});
  const saved=f.saved();v.beginErase(0);v.handleEraseAtPoint(0,0.5,0.5,720,1000);v.finishErase(false);
  assert.equal(v.pageStrokes[0].length,1);assert.equal(v.undoStack.length,1);assert.equal(f.saved(),saved);
});

test('note filters include normalized handwriting and Word types after creation or restoration', () => {
  const filtered=viewMethod('pages/Index.ets','filteredNotes',{FILTER_ALL:'全部'});
  const view={searchText:'',activeSpaceName:()=>'',notes:[studyNote({id:'pen',type:'Handwriting'}),studyNote({id:'old',type:'Canvas'}),studyNote({id:'word',type:'docx'}),studyNote({id:'pdf',type:'PDF'})]};
  view.activeFilter='手写';assert.deepEqual(plain(filtered.call(view)).map(n=>n.id),['pen','old']);
  view.activeFilter='Word';assert.deepEqual(plain(filtered.call(view)).map(n=>n.id),['word']);
});

test('a failed note snapshot write leaves the creation form and original library intact', async () => {
  const create=viewMethod('pages/Index.ets','createNote');const original=studyNote();let opened=0;
  const view={notes:[original],noteCreateBusy:false,noteCreateError:'',activeSpaceName:()=>'',formatTime:()=>'',
    storage:{create:async()=>{},save:async()=>{throw Error('disk');}},rebuildSpaces(){},refreshGraph(){},openNote:()=>opened++,notify(){}};
  assert.equal(await create.call(view,'日记'),false);assert.equal(view.notes.length,1);assert.equal(view.notes[0],original);
  assert.equal(opened,0);assert.ok(view.noteCreateError);assert.equal(view.noteCreateBusy,false);
});

test('leaving a scratchpad or global canvas commits its last stroke and pending save', () => {
  const disappear=viewMethod('views/reader/HandwritingCanvas.ets','aboutToDisappear',{clearTimeout:()=>{}});
  for(const [isScratchpad,persistOnDisappear] of [[true,false],[false,true],[false,false]]) {
    const calls=[];const view={isScratchpad,persistOnDisappear,saveTimer:1,
      finishStroke:()=>calls.push('stroke'),flushSave:()=>calls.push('save'),shortcuts:{stop(){}},input:{reset(){}},inkFrame:{release(){}}};
    disappear.call(view);assert.deepEqual(calls,isScratchpad||persistOnDisappear?['stroke','save']:[]);assert.equal(view.saveTimer,-1);
  }
});

function shareHarness({ supported = true, exists = true, failure = null } = {}) {
  const panels = []; const uris = [];
  class SharedData { constructor(record) { this.record = record; } }
  class ShareController {
    constructor(data) { this.data = data; }
    async show(context, options) { if (failure) throw failure; panels.push({ context, options, record: this.data.record }); }
  }
  const { SystemShareService } = load(`${base}services/SystemShareService.ets`, {
    '@kit.AbilityKit': {},
    '@kit.ShareKit': { systemShare: { SharedData, ShareController, SelectionMode: { SINGLE: 0 }, SharePreviewMode: { DETAIL: 0 } } },
    '@kit.ArkData': { uniformTypeDescriptor: { UniformDataType: { PLAIN_TEXT: 'general.plain-text', PDF: 'com.adobe.pdf' } } },
    '@kit.CoreFileKit': { fileIo: { access: async () => exists }, fileUri: { getUriFromPath: p => { uris.push(p); return `file://app${p}`; } } },
    canIUse: () => supported
  });
  return { service: SystemShareService, panels, uris, context: { filesDir: '/data/app/files' } };
}

test('system sharing hands only the selected literal text to the native chooser', async () => {
  const h = shareHarness(); const text = '# 课程\n用户未保存的文字\n';
  await h.service.shareText(h.context, '课程', text);
  assert.equal(h.panels.length, 1); assert.deepEqual(plain(h.panels[0].record), { utd: 'general.plain-text', content: text, title: '课程' });
  assert.deepEqual(plain(h.panels[0].options), { selectionMode: 0, previewMode: 0 }); assert.equal(h.uris.length, 0);
});

test('system sharing rejects empty and oversized text without silently truncating it', async () => {
  const h = shareHarness();
  await assert.rejects(h.service.shareText(h.context, '空白', ' \n'), /先写入/);
  await assert.rejects(h.service.shareText(h.context, '长资料', '课'.repeat(48 * 1024 + 1)), /导出文件/);
  assert.equal(h.panels.length, 0);
});

test('PDF sharing uses the owned original file and explicitly excludes ink', async () => {
  const h = shareHarness(); await h.service.sharePdf(h.context, '讲义', '/data/app/files/documents/lesson.pdf');
  assert.deepEqual(h.uris, ['/data/app/files/documents/lesson.pdf']);
  assert.deepEqual(plain(h.panels[0].record), { utd: 'com.adobe.pdf', uri: 'file://app/data/app/files/documents/lesson.pdf',
    title: '讲义', description: '原 PDF，不包含应用内笔迹' });
});

test('PDF sharing rejects other sandboxes, traversal, URLs and missing originals', async () => {
  const h = shareHarness();
  for (const p of ['/data/app/files-other/a.pdf', '/data/other/a.pdf', '/data/app/files/../a.pdf',
    '/data/app/files/./a.pdf', 'https://example.com/a.pdf', '/data/app/files/a.txt']) {
    await assert.rejects(h.service.sharePdf(h.context, '资料', p), /原 PDF 不可用/);
  }
  const missing = shareHarness({ exists: false }); await assert.rejects(missing.service.sharePdf(missing.context, '资料', '/data/app/files/a.pdf'));
  assert.equal(h.panels.length, 0); assert.equal(h.uris.length, 0); assert.equal(missing.panels.length, 0);
});

test('native chooser unavailability or failure propagates without reporting delivery', async () => {
  const unavailable = shareHarness({ supported: false });
  await assert.rejects(unavailable.service.shareText(unavailable.context, '资料', '正文'), /不支持系统分享/);
  const failed = shareHarness({ failure: new Error('native chooser failed') });
  await assert.rejects(failed.service.shareText(failed.context, '资料', '正文'), /native chooser failed/);
  assert.equal(unavailable.panels.length, 0); assert.equal(failed.panels.length, 0);
});

const { DocumentTextParser } = load(`${base}services/document/DocumentTextParser.ets`);

const { CanvasViewport } = load(`${base}services/ink/CanvasViewport.ets`);

function canvasNavigationView() {
  const v = { input: { isPenActive: () => false, reset() {} }, readOnly: false, inkContact: true,
    fingerDrawing: true, currentStroke: { points: [{ x: 10, y: 10 }] }, strokes: [], eraseBefore: null,
    navigating: false, pairIds: '', pairDistance: 0, zoomStart: 1, zoomScale: 1, panX: 0, panY: 0,
    pairAnchor: { x: 0, y: 0 }, canvasWidth: 600, canvasHeight: 700, liveContext: { clearRect() {} },
    onDirtyChange() {}, onFocused() {}, redrawAll() {}, requestRedraw() {} };
  for (const method of ['navigateTouch', 'cancelContact', 'revealWritingSpace']) v[method] = viewMethod('views/reader/HandwritingCanvas.ets', method, { CanvasViewport, ...penEnums });
  return v;
}

test('two fingers take over finger ink, pan and zoom around their moving center without an ink tail', () => {
  const v = canvasNavigationView();
  const event = (type, points, changed = points) => ({ type, sourceTool: penEnums.SourceTool.Finger, touches: points, changedTouches: changed });
  const a = { id: 1, x: 100, y: 100 }, b = { id: 2, x: 200, y: 100 };
  assert.equal(v.navigateTouch(event(0, [a, b])), true); assert.equal(v.currentStroke, null); assert.equal(v.inkContact, false);
  v.navigateTouch(event(2, [{ ...a, x: 90, y: 130 }, { ...b, x: 290, y: 130 }]));
  assert.equal(v.zoomScale, 2); assert.equal(v.panX, -110); assert.equal(v.panY, -70);
  v.navigateTouch(event(1, [a], [b])); assert.equal(v.navigating, true);
  v.navigateTouch(event(2, [{ ...a, x: 120 }])); assert.equal(v.currentStroke, null);
  v.navigateTouch(event(1, [a], [a])); assert.equal(v.navigating, false);
  assert.equal(v.navigateTouch(event(0, [a])), false);
  v.navigateTouch(event(0, [a, b])); v.navigateTouch(event(3, [a, b])); assert.equal(v.navigating, false);
});

test('PDF navigation rejects a pen and its palm but allows two fingers to take over finger ink', () => {
  const judge = viewMethod('views/reader/pdf/PdfAnnotatorView.ets', 'judgeNavigation', {
    ...penEnums, GestureJudgeResult: { REJECT: 'reject', CONTINUE: 'continue' } });
  const v = { penContact: false, inkContact: true, isAnnotateMode: true, fingerDrawing: true, currentTool: 'pen' };
  const fingers = n => ({ sourceTool: penEnums.SourceTool.Finger, fingerList: Array(n).fill({}) });
  assert.equal(judge.call(v, fingers(1)), 'reject'); assert.equal(judge.call(v, fingers(2)), 'continue');
  v.penContact = true; assert.equal(judge.call(v, fingers(2)), 'reject');
  assert.equal(judge.call(v, { sourceTool: penEnums.SourceTool.Pen, fingerList: [] }), 'reject');
  Object.assign(v, { activeInputPage: 2, saveRevision: 1, savedRevision: 1, onDirtyChange() {} });
  const change = viewMethod('views/reader/pdf/PdfAnnotatorView.ets', 'setPageInkContact');
  change.call(v, 1, false); assert.equal(v.penContact, true);
  change.call(v, 2, false); assert.equal(v.penContact, false); assert.equal(v.inkContact, false);
});

test('palm contacts cannot transform the whiteboard while a pen owns the pointer', () => {
  const v = canvasNavigationView(); v.input.isPenActive = () => true;
  assert.equal(v.navigateTouch({ sourceTool: penEnums.SourceTool.Finger, type: 0, touches: [{ id: 2, x: 1, y: 1 }, { id: 3, x: 2, y: 2 }] }), false);
  assert.ok(v.currentStroke); assert.equal(v.zoomScale, 1); assert.equal(v.panX, 0);
});

test('writing near an edge reveals more whiteboard space only after lift and preserves stored coordinates', () => {
  const v = canvasNavigationView(); v.strokes = [{ points: [{ x: 590, y: 690 }], isEraser: false }];
  const before = JSON.stringify(v.strokes); v.revealWritingSpace();
  assert.equal(v.panX, -150); assert.equal(v.panY, -210); assert.equal(JSON.stringify(v.strokes), before);
  v.strokes = [{ points: [{ x: 590, y: 690 }], isEraser: true }]; v.revealWritingSpace(); assert.equal(v.panY, -210);
});

test('stroke erasing catches swept crossings and old reference widths without deleting area masks', () => {
  const stroke = { points: [{ x: 50, y: 0 }, { x: 50, y: 100 }], color: '#000', width: 2, referenceWidth: 1200, isEraser: false };
  assert.equal(CanvasStrokeEraser.hit(stroke, { x: 0, y: 50 }, { x: 100, y: 50 }, 4), true);
  assert.equal(CanvasStrokeEraser.hit(stroke, { x: 0, y: 150 }, { x: 100, y: 150 }, 4), false);
  assert.equal(CanvasStrokeEraser.hit({ ...stroke, referenceWidth: 600 }, { x: 100, y: 100 }, { x: 100, y: 100 }, 4), true);
  assert.equal(CanvasStrokeEraser.hit({ ...stroke, isEraser: true }, { x: 50, y: 50 }, { x: 50, y: 50 }, 40), false);
});

test('a whiteboard stroke erase is one undo frame and cancellation restores the entire original snapshot', () => {
  const before = [{ points: [{ x: 1, y: 1 }] }, { points: [{ x: 2, y: 2 }] }];
  const v = canvasNavigationView(); let saved = 0;
  Object.assign(v, { strokes: before.slice(1), eraseBefore: before, undoFrames: [], redoFrames: [before], currentStroke: null, scheduleSave: () => saved++ });
  viewMethod('views/reader/HandwritingCanvas.ets', 'finishStroke').call(v);
  assert.equal(v.undoFrames.length, 1); assert.equal(v.undoFrames[0], before); assert.equal(saved, 1); assert.equal(v.redoFrames.length, 0);
  v.eraseBefore = before; v.strokes = []; v.cancelContact(); assert.equal(v.strokes, before); assert.equal(saved, 1);
});

test('topbar commands route only to the chosen canvas and remember each eraser mode', () => {
  const v = inkSelectionHarness().view; const targets = [];
  v.isScratchpad = true; v.toolCommand = { sequence: 1, target: 'document', action: 'eraser', value: '' };
  v.selectEraser = () => targets.push('eraser'); v.changeEraserMode = viewMethod('views/reader/HandwritingCanvas.ets', 'changeEraserMode');
  const command = viewMethod('views/reader/HandwritingCanvas.ets', 'handleToolCommand');
  command.call(v); assert.equal(targets.length, 0);
  v.toolCommand.target = 'scratchpad'; command.call(v); assert.deepEqual(targets, ['eraser']);
  v.toolCommand = { sequence: 2, target: 'scratchpad', action: 'eraserMode', value: 'stroke' }; command.call(v);
  assert.equal(v.eraserMode, 'stroke'); v.toolCommand.value = 'invalid'; command.call(v); assert.equal(v.eraserMode, 'stroke');
});

test('PDF swept stroke erase skips area eraser masks and can undo the complete gesture', () => {
  const v = pdfHistoryView().view;
  const stroke = { id: 'cross', pageIndex: 0, color: '#000', width: 2, isEraser: false, points: [{ u: .5, v: .1 }, { u: .5, v: .9 }] };
  const mask = { ...stroke, id: 'mask', isEraser: true };
  v.pageStrokes[0] = [stroke, mask]; v.beginErase(0);
  v.handleEraseAtPoint(0, .1, .5, 720, 1000); v.handleEraseAtPoint(0, .9, .5, 720, 1000); v.finishErase(true);
  assert.deepEqual(v.pageStrokes[0].map(item => item.id), ['mask']); v.handleUndo(); assert.equal(v.pageStrokes[0].length, 2);
});

test('PDF area erasing draws a reversible transparent mask and cancellation removes the preview without saving', () => {
  for (const commit of [false, true]) {
    const ink = inkRecorder(), live = inkRecorder(); ink.ctx.clearRect = () => {}; live.ctx.clearRect = () => {};
    const saved = []; let wholeErase = 0, redraws = 0;
    const v = { sourceReady: true, isAnnotateMode: true, tool: 'eraser', eraserMode: 'area', eraserWidth: 24,
      pageWidth: 360, pageHeight: 500, pageModel: { pageIndex: 0 }, selectedColor: '#111', selectedWidth: 3,
      input: new InkInputService(), fingerDrawing: true, context: ink.ctx, liveContext: live.ctx,
      onPenActive() {}, onActiveFinisherChange() {}, onInkContactChange() {}, onEraseStarted: () => wholeErase++,
      onStrokeAdded: stroke => saved.push(stroke), redrawAll: () => redraws++ };
    for (const method of ['handleTouch', 'finishInput', 'resetInput', 'style']) v[method] = viewMethod('views/reader/pdf/PdfPageCanvas.ets', method, { ...penEnums, InkRenderer });
    const event = type => ({ ...touchEvent(type), stopPropagation() {} });
    v.handleTouch(event(0)); v.handleTouch(event(2)); v.handleTouch(event(commit ? 1 : 3));
    assert.equal(wholeErase, 0); assert.equal(saved.length, commit ? 1 : 0); assert.equal(redraws, commit ? 0 : 1);
    assert.ok(ink.calls.some(call => call[0] === 'fill' && call[3] === 'destination-out'));
    assert.equal(live.calls.length, 0);
    if (commit) { assert.equal(saved[0].isEraser, true); assert.equal(saved[0].width, 24); }
  }
});
test('canvas screen and world coordinates round trip across pan, zoom and negative horizontal expansion', () => {
  for(const zoom of [.08,.3,1,8]) for(const [x,y,panX,panY] of [[0,0,320,-200],[420,780,-2000,1500]]) {
    const world=CanvasViewport.world(x,y,zoom,panX,panY);
    assert.ok(Math.abs(world.x*zoom+panX-x)<1e-9); assert.ok(Math.abs(world.y*zoom+panY-y)<1e-9);
  }
  assert.equal(CanvasViewport.world(0,0,.5,500,0).x,-1000);
});
test('legacy canvas reference widths scale without changing stored strokes; culling includes edge ink', () => {
  const stroke={points:[{x:10,y:20},{x:20,y:30}],referenceWidth:600,width:3,color:'#000'};
  const before=JSON.stringify(stroke); const bounds=CanvasViewport.bounds(stroke);
  assert.deepEqual(plain(bounds),{left:14,top:34,right:46,bottom:66});
  assert.equal(CanvasViewport.visible(bounds,100,100,1,0,0),true);
  assert.equal(CanvasViewport.visible(bounds,100,100,1,-47,0),false);
  assert.equal(CanvasViewport.visible(bounds,100,100,1,-46,0),true);
  assert.equal(JSON.stringify(stroke),before);
});
test('canvas redraw scheduling coalesces moves without resizing the viewport', () => {
  const queue=[];const redraw=viewMethod('views/reader/HandwritingCanvas.ets','requestRedraw',{setTimeout:(fn,ms)=>{queue.push([fn,ms]);return 7;}});
  let draws=0;const v={drawTimer:-1,canvasWidth:360,canvasHeight:700,redrawAll:()=>draws++};
  for(let i=0;i<50;i++)redraw.call(v);
  assert.equal(queue.length,1);assert.equal(queue[0][1],16);assert.equal(draws,0);
  queue[0][0]();assert.equal(draws,1);assert.equal(v.drawTimer,-1);assert.equal(v.canvasWidth,360);assert.equal(v.canvasHeight,700);
});
test('cancelled handwriting contacts discard live ink and preserve outstanding save state', () => {
  const handle=viewMethod('views/reader/HandwritingCanvas.ets','handleTouch',{CanvasViewport,...penEnums});
  for(const pending of [false,true]) {
    const dirties=[];let clears=0,redraws=0;
    const v={navigateTouch:()=>false,readOnly:false,input:{read:()=>({phase:'cancel'}),reset(){}},saveRevision:pending?2:1,savedRevision:1,
      inkContact:true,currentStroke:{points:[{x:1,y:2}]},onDirtyChange:d=>dirties.push(d),
      liveContext:{clearRect:()=>clears++},redrawAll:()=>redraws++,strokes:[]};
    v.cancelContact = viewMethod('views/reader/HandwritingCanvas.ets','cancelContact');
    handle.call(v,{stopPropagation(){}});assert.deepEqual(dirties,[pending]);assert.equal(v.currentStroke,null);assert.equal(v.inkContact,false);
    assert.equal(clears,1);assert.equal(redraws,1);assert.equal(v.strokes.length,0);
  }
});

function calendarHarness(formatter=Intl.DateTimeFormat) {
  return load(`${base}common/utils/CalendarInfo.ets`,{'@kit.LocalizationKit':{intl:{DateTimeFormat:formatter}}}).CalendarInfo;
}
test('native lunar calendar finds known lunar festivals and preserves leap month identity', () => {
  const calendar=calendarHarness();
  for(const [date,lunar,festival] of [['2026-02-17','正月初一','春节'],['2026-03-03','正月十五','元宵'],
    ['2026-06-19','五月初五','端午'],['2026-09-25','八月十五','中秋']]) {
    const info=calendar.forDate(date);assert.equal(info.lunarLong,lunar);assert.equal(info.festival,festival);
  }
  const leap=calendar.forDate('2025-07-25');assert.equal(leap.lunarLong,'闰六月初一');assert.equal(leap.festival,'');assert.equal(leap.schedule,'');
});
test('verified 2026 holidays and shifted workdays never leak into another year', () => {
  const calendar=calendarHarness();
  for(const date of ['2026-01-01','2026-01-03','2026-02-15','2026-02-23','2026-04-06','2026-05-05','2026-06-21','2026-09-27','2026-10-07']) assert.equal(calendar.forDate(date).schedule,'休',date);
  for(const date of ['2026-01-04','2026-02-14','2026-02-28','2026-05-09','2026-09-20','2026-10-10']) assert.equal(calendar.forDate(date).schedule,'班',date);
  for(const date of ['2026-10-08','2027-10-01','2025-10-10']) assert.equal(calendar.forDate(date).schedule,'',date);
});
test('calendar rejects invalid dates and retains official holidays when ICU is unavailable', () => {
  const calendar=calendarHarness();
  for(const date of ['2026-02-29','2026-04-31','bad','2026-2-17','2026-13-01']) assert.deepEqual(plain(calendar.forDate(date)),{lunar:'',lunarLong:'',festival:'',schedule:''});
  const unavailable=calendarHarness(class {constructor(){throw Error('no ICU');}});
  assert.equal(unavailable.forDate('2026-10-01').schedule,'休');assert.equal(unavailable.forDate('2026-10-01').festival,'国庆');
  assert.equal(unavailable.forDate('2026-10-01').lunar,'');assert.equal(unavailable.forDate('2026-10-10').schedule,'班');
});

test('read-only documents exit directly; only pending main or scratchpad changes prompt saving', () => {
  const back=viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets','handleBackRequest');
  for(const [main,scratch,expected] of [[false,false,false],[true,false,true],[false,true,true]]) {
    let closed=0;const v={penOptionsOpen:false,jumpDialogOpen:false,activeModal:'',isPhone:false,splitMode:'none',exitDialogOpen:false,
      documentDirty:main,scratchpadDirty:scratch,onClose:()=>closed++};
    back.call(v);assert.equal(v.exitDialogOpen,expected);assert.equal(closed,expected?0:1);
  }
});
test('exit waits for both main and scratchpad writes and keeps the reader open on failure', () => {
  const relative='views/reader/huawei/HuaweiDocWorkspace.ets';
  for(const success of [true,false]) {
    let closed=0;const notices=[];const v={exitSaving:false,saveDestination:'close',splitMode:'scratchpad',exitSaveToken:0,onClose:()=>closed++,showToast:m=>notices.push(m),
      beginReaderSave:viewMethod(relative,'beginReaderSave')};
    viewMethod(relative,'saveAndExit').call(v);assert.equal(v.exitPending,2);assert.equal(v.exitSaveToken,1);
    viewMethod(relative,'exitSaveFinished').call(v,true);assert.equal(closed,0);assert.equal(v.exitSaving,true);
    viewMethod(relative,'exitSaveFinished').call(v,success);assert.equal(closed,success?1:0);assert.equal(v.exitSaving,false);assert.equal(notices.length,success?0:1);
  }
});
test('only the latest successful ink snapshot clears dirty state; failures remain recoverable', async () => {
  for(const relative of ['views/reader/pdf/PdfAnnotatorView.ets','views/reader/HandwritingCanvas.ets']) {
    const flush=viewMethod(relative,'flushSave');const dirty=[];let release;
    const v={saveRevision:2,savedRevision:0,loadedNoteId:'n',strokeSnapshot:()=>({id:'n',contentDetail:''}),annotationSnapshot:()=>({id:'n',contentDetail:''}),
      onDirtyChange:d=>dirty.push(d),onSaveStateChange:()=>{},onSaved:()=>new Promise(r=>release=r)};
    const pending=flush.call(v);v.saveRevision++;release();await pending;assert.deepEqual(dirty,[]);assert.equal(v.savedRevision,0);
    v.onSaved=async()=>{};await flush.call(v);assert.deepEqual(dirty,[false]);assert.equal(v.savedRevision,3);
    v.saveRevision++;v.onSaved=async()=>{throw Error('disk');};await flush.call(v);assert.equal(v.savedRevision,3);assert.deepEqual(dirty,[false]);
  }
});
test('reader parsing preserves Unicode, source line indices, numbered lists and rich block bodies', () => {
  const relative='views/reader/MarkdownReader.ets';
  const parse=viewMethod(relative,'parseBlocks',{DocumentTextParser});
  const source='#### 中文 English αβ\n\n2. 次序\n- [ ] 未完成\n```js\nconst x = "中文";\n```\n$$x²+y²$$\n| 项目 | 值 |\n| --- | --- |\n| α | 1 |';
  const v={parseTask:viewMethod(relative,'parseTask')};const blocks=plain(parse.call(v,source));
  assert.deepEqual(blocks.map(b=>[b.kind,b.line]),[['heading',0],['ordered',2],['task',3],['code',4],['math',7],['table',8]]);
  assert.equal(blocks[0].level,4);assert.equal(blocks[1].marker,'2.');assert.equal(blocks[2].checked,false);
  assert.equal(blocks[3].text,'```js\nconst x = "中文";\n```');assert.equal(blocks[4].text,'$$x²+y²$$');
  assert.match(blocks[5].text,/\| α \| 1 \|/);
});
test('reading toolbar collapses after downward travel, and typing keeps it expanded', () => {
  const relative='views/reader/MarkdownReader.ets';const scroll=viewMethod(relative,'handleReadingScroll');
  const v={isEditing:false,editorFocused:false,scrollTravel:0,toolbarExpanded:true};
  scroll.call(v,12);assert.equal(v.toolbarExpanded,true);scroll.call(v,12);assert.equal(v.toolbarExpanded,false);
  viewMethod(relative,'handleBlankTap').call(v);assert.equal(v.toolbarExpanded,true);
  v.editorFocused=true;scroll.call(v,100);assert.equal(v.toolbarExpanded,true);
  v.toolbarExpanded=false;viewMethod(relative,'handleBlankTap').call(v);assert.equal(v.toolbarExpanded,false);
  v.editorFocused=false;v.isEditing=true;v.toolbarExpanded=true;scroll.call(v,100);assert.equal(v.toolbarExpanded,true);
});
test('PDF toolbar does not collapse while annotating or while a save is outstanding', () => {
  const scroll=viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets','handleReadingScroll');
  for(const flags of [[false,false,false],[true,false,false],[false,true,false],[false,false,true]]) {
    let collapsed=0;const v={isAnnotateMode:flags[0],documentDirty:flags[1],scratchpadDirty:flags[2],scrollTravel:0,toggleBars:visible=>{if(!visible)collapsed++;}};
    scroll.call(v,25);assert.equal(collapsed,flags.some(Boolean)?0:1);
  }
});
test('external PDF import persists library metadata before exposing the reference and ignores duplicate import taps', async () => {
  const method=viewMethod('pages/Index.ets','importDocument');let write;const calls=[];
  const transfer={status:'imported',noteType:'PDF',sourceUri:'/sandbox/copy.pdf',sourceFileName:'copy.pdf',pageCount:2,document:{id:'pdf',title:'测试',fileName:'测试.pdf',content:'# 测试'}};
  const v={documentImportBusy:false,notes:[],getAbilityContext:()=>({}),storage:{importDocument:async()=>transfer,save:()=>new Promise(r=>write=r)},
    formatTime:()=>'',rebuildSpaces:()=>calls.push('library'),refreshGraph:()=>{},notify:()=>{}};
  const pending=method.call(v,'外部参考');await new Promise(r=>setTimeout(r,0));assert.equal(v.notes.length,0);
  assert.equal(await method.call(v),null);write();const imported=await pending;assert.equal(v.notes[0],imported);assert.equal(imported.sourceUri,transfer.sourceUri);
  assert.equal(imported.category,'外部参考');assert.equal(imported.sourceFileName,'copy.pdf');assert.equal(v.documentImportBusy,false);assert.deepEqual(calls,['library']);
  v.storage.delete=async(_,id,source)=>calls.push(['cleanup',id,source]);
  v.storage.save=async()=>{throw Error('disk');};const original=v.notes;assert.equal(await method.call(v),null);assert.equal(v.notes,original);assert.equal(v.documentImportBusy,false);
  assert.deepEqual(calls.at(-1),['cleanup','pdf','/sandbox/copy.pdf']);
});

test('the extraction import adapter returns library PDF and text paths and propagates failed imports', async () => {
  const method = viewMethod('pages/Index.ets', 'importExtractSource'); const calls = [];
  const view = { importDocument: async (...args) => { calls.push(args); return { id: 'pdf', sourceType: 'pdf', sourceUri: '/sandbox/documents/original.pdf' }; } };
  assert.equal(await method.call(view, 'file://source.pdf'), '/sandbox/documents/original.pdf');
  assert.deepEqual(calls[0], ['外部参考', false, false, 'file://source.pdf']);
  view.importDocument = async () => ({ id: 'text', sourceType: 'document' }); view.getAbilityContext = () => ({});
  view.storage = { read: async () => ({ filePath: '/sandbox/notes/text.md' }) };
  assert.equal(await method.call(view, 'file://result.md'), '/sandbox/notes/text.md');
  view.importDocument = async () => null; await assert.rejects(method.call(view, 'file://source.pdf'), /保存/);
});
test('bundled example PDF is explicitly imported with durable source and rejects a broken native document', async () => {
  const fixture=importService('');const result=await fixture.service.importExamplePdf({filesDir:'/sandbox'});
  assert.equal(result.status,'imported');assert.equal(result.noteType,'PDF');assert.equal(result.sourceUri,'/sandbox/copy.pdf');assert.equal(result.pageCount,2);
  const failed=importService('',{pdfFails:true});assert.equal((await failed.service.importExamplePdf({filesDir:'/sandbox'})).status,'failed');
  assert.deepEqual(failed.calls,[['unlink','/sandbox/copy.pdf']]);
  assert.ok(fs.readFileSync(path.join(root,'entry/src/main/resources/rawfile/example-course.pdf')).subarray(0,5).equals(Buffer.from('%PDF-')));
});
test('bundled PDF short writes and invalid resource bytes cannot leave a phantom source', async () => {
  for(const mode of ['ok','short','invalid']) {
    const calls=[];const bytes=Buffer.from(mode==='invalid'?'wrong':'%PDF-real-test');
    const {PdfDocumentService}=load(`${base}services/document/PdfDocumentService.ets`,{'@kit.PDFKit':{pdfService:{}},'@kit.ImageKit':{image:{}},
      '@kit.CoreFileKit':{fileIo:{OpenMode:{CREATE:1,WRITE_ONLY:2,TRUNC:4},accessSync:()=>true,openSync:()=>({fd:1}),
        writeSync:(_,buffer)=>{calls.push('write');assert.equal(Buffer.from(buffer).toString(),bytes.toString());return mode==='short'?1:buffer.byteLength;},
        fsyncSync:()=>calls.push('sync'),unlinkSync:()=>calls.push('remove'),closeSync:()=>calls.push('close')}},
      [path.resolve(root,`${base}services/ocr/OcrService.ets`)]:{OcrService:{}}});
    const pending=new PdfDocumentService().saveBundledExample({filesDir:'/sandbox',resourceManager:{getRawFileContent:async()=>bytes}});
    if(mode==='ok'){assert.match(await pending,/^\/sandbox\/documents\/.*example-course\.pdf$/);assert.deepEqual(calls,['write','sync','close']);}
    else {await assert.rejects(pending);assert.deepEqual(calls,mode==='short'?['write','remove','close']:[]);}
  }
});

const { LocalTextFormatter } = load(`${base}services/smart/LocalTextFormatter.ets`);

test('OCR paragraph repair is opt-in and protects all structural boundaries and explicit hard breaks', () => {
  const input = '这是一段从照片中识别出的课程内容\n继续说明具体要求。\n\nAn introduction to the subject\ncontinues here.\n\n一、学习要求\n- 完成练习\n| 课程 | 学分 |\n| 数学 | 4 |\n\n```text\n这是一段足够长的代码示例文字内容\n这里的代码不能被合并\n```\n$$\n这是足够长的公式中的说明文字\n这一行应保持独立\n$$\n这是一段指定了硬换行的普通文字  \n下一行保持独立';
  const body = LocalTextFormatter.format(input, '记录', 'study', true);
  assert.ok(body.includes('课程内容继续说明具体要求。'));
  assert.ok(body.includes('subject continues here.'));
  assert.ok(body.includes('## 一、学习要求\n- 完成练习\n| 课程 | 学分 |'));
  assert.ok(body.includes('示例文字内容\n这里的代码不能被合并'));
  assert.ok(body.includes('说明文字\n这一行应保持独立'));
  assert.ok(body.includes('普通文字  \n下一行保持独立'));
  assert.ok(LocalTextFormatter.format(input, '记录', 'faithful').endsWith(input));
});

test('unclosed code fences, matching fence lengths and indented code never become headings or tasks', () => {
  const input = '```text\n一、提交报告\n``\n• 完成练习\n\n    二、提交材料';
  const body = LocalTextFormatter.format(input, '笔记', 'study', true);
  assert.ok(body.endsWith(input)); assert.equal(SourceTextParser.fromSource(input).tasks.length, 0);
});

test('completed checkboxes, negative clauses and cancelled actions never become calendar suggestions', () => {
  const input = '- [x] 完成课程报名\n- [X] 提交旧报告\n不需要准备材料，也不要提交重复报告。\n报名取消。\n明天提交新的实验报告。';
  const tasks = SourceTextParser.fromSource(input).tasks;
  assert.equal(tasks.length, 1); assert.equal(tasks[0].title, '明天提交新的实验报告');
});

test('system OCR uses block paragraphs only when all SDK characters and their order match', async () => {
  for (const [value, blocks, expected] of [
    ['课程介绍\n准备材料', [{ value: '课程介绍' }, { value: '准备材料' }], '课程介绍\n\n准备材料'],
    ['课程介绍\n准备材料', [{ value: '课程介绍' }], '课程介绍\n准备材料'],
    ['课程介绍\n准备材料', [{ value: '准备材料' }, { value: '课程介绍' }], '课程介绍\n准备材料']
  ]) {
    const { OcrService } = load(ocrFile, { '@kit.CoreFileKit': {}, '@kit.ImageKit': {},
      '@kit.CoreVisionKit': { textRecognition: { recognizeText: async () => ({ value, blocks }) } } });
    assert.equal(await OcrService.getInstance().recognizePixelMap({}), expected);
  }
});

test('unsupported system OCR fails before file access and leaves caller-owned maps untouched', async () => {
  const { OcrService } = load(ocrFile, { canIUse: () => false, '@kit.CoreFileKit': {}, '@kit.ImageKit': {}, '@kit.CoreVisionKit': {} });
  await assert.rejects(OcrService.getInstance().recognizeTextFromUri('photo://image'), /可粘贴/);
  await assert.rejects(OcrService.getInstance().recognizePixelMap({ release: () => assert.fail('caller-owned map') }), /未提供/);
});

const { paletteForStyle, normalizeThemeStyle, THEME_STYLE_OPTIONS } = load(`${base}common/theme/ThemeStyle.ets`);
function contrastRatio(a, b) {
  const luminance = hex => {
    const channels = hex.slice(1).match(/../g).map(part => parseInt(part, 16) / 255)
      .map(c => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
    return channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
  };
  const first = luminance(a), second = luminance(b);
  return (Math.max(first, second) + .05) / (Math.min(first, second) + .05);
}
for (const option of THEME_STYLE_OPTIONS) {
  test(`${option.label} light and dark palettes have readable text and accent foregrounds`, () => {
    for (const dark of [false, true]) {
      const palette = paletteForStyle(dark, option.id);
      for (const text of ['inkPrimary', 'inkSecondary', 'inkMuted']) {
        for (const background of ['canvas', 'surface', 'surfaceSubtle', 'accentSoft', 'sidebar', 'activeBg', 'hoverBg']) {
          assert.ok(contrastRatio(palette[text], palette[background]) >= 4.5,
            `${option.id} ${dark} ${text}/${background}: ${contrastRatio(palette[text], palette[background])}`);
        }
      }
      assert.ok(contrastRatio(palette.accent, palette.onAccent) >= 4.5);
    }
    assert.equal(normalizeThemeStyle(option.id), option.id);
  });
}
test('legacy and corrupt theme style values resolve to the original brand palette', () => {
  for (const value of ['', 'invalid', undefined, 42]) { assert.equal(normalizeThemeStyle(value), 'ink'); }
});

async function themeFixture(initial = {}) {
  const values = new Map(Object.entries(initial)), app = new Map(), calls = [];
  let fail = false;
  const store = { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
    put: async (key, value) => { calls.push([key, value]); values.set(key, value); },
    flush: async () => { calls.push('flush'); if (fail) throw Error('storage'); } };
  const application = { setColorMode: () => {} };
  const { ThemeManager } = load(`${base}common/theme/ThemeManager.ets`, {
    '@kit.AbilityKit': { ConfigurationConstant: { ColorMode: { COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1, COLOR_MODE_NOT_SET: -1 } }, bundleManager: {} },
    '@kit.BasicServicesKit': { deviceInfo: { sdkApiVersion: 24 } }, '@kit.ArkData': { preferences: { getPreferences: async () => store } },
    AppStorage: { get: key => app.get(key), setOrCreate: (key, value) => app.set(key, value) }
  });
  await ThemeManager.restore({ getApplicationContext: () => application }, 1);
  return { ThemeManager, values, app, calls, fail: value => { fail = value; } };
}

test('theme style and dark mode persist independently and restore before the first page', async () => {
  const f = await themeFixture(); await f.ThemeManager.setStyle('blue'); await f.ThemeManager.setMode(2);
  assert.equal(f.app.get('flowmindThemeStyle'), 'blue'); assert.equal(f.app.get('flowmindDarkMode'), true);
  const restored = await themeFixture(Object.fromEntries(f.values));
  assert.equal(restored.ThemeManager.currentStyle(), 'blue'); assert.equal(restored.ThemeManager.currentMode(), 2);
  assert.equal(restored.app.get('flowmindDarkMode'), true);
});

test('failed appearance persistence rejects, restores preference cache, and does not change the published UI', async () => {
  const f = await themeFixture(); f.fail(true);
  await assert.rejects(f.ThemeManager.setStyle('mono')); await assert.rejects(f.ThemeManager.setMode(2));
  await assert.rejects(f.ThemeManager.setReduceMotion(true));
  assert.equal(f.ThemeManager.currentStyle(), 'ink'); assert.equal(f.ThemeManager.currentMode(), 0);
  assert.equal(f.app.get('flowmindDarkMode'), false); assert.equal(f.app.get('flowmindReduceMotion'), false);
  assert.equal(f.values.get('themeStyle'), 'ink'); assert.equal(f.values.get('themeMode'), 0);
  f.fail(false); await f.ThemeManager.setStyle('mist'); assert.equal(f.app.get('flowmindThemeStyle'), 'mist');
});

test('rapid appearance changes commit in order and the last choice wins without mixing mode and style', async () => {
  const f = await themeFixture();
  await Promise.all([f.ThemeManager.setStyle('blue'), f.ThemeManager.setMode(2), f.ThemeManager.setStyle('mono'), f.ThemeManager.setReduceMotion(true)]);
  assert.equal(f.ThemeManager.currentStyle(), 'mono'); assert.equal(f.ThemeManager.currentMode(), 2);
  assert.equal(f.app.get('flowmindReduceMotion'), true);
  assert.deepEqual(f.calls, [['themeStyle', 'blue'], 'flush', ['themeMode', 2], 'flush', ['themeStyle', 'mono'], 'flush', ['reduceMotion', true], 'flush']);
});

const { SettingsCatalog, SETTINGS_ENTRIES, SETTINGS_GROUPS } = load(`${base}common/constants/SettingsCatalog.ets`);
test('settings search covers names and user vocabulary, preserves group boundaries and returns no fake matches', () => {
  assert.equal(SettingsCatalog.search('OCR')[0].id, 'capture');
  assert.equal(SettingsCatalog.search('浅蓝')[0].id, 'theme');
  assert.equal(SettingsCatalog.search('deepseek API').length, 0);
  assert.equal(SettingsCatalog.search('恢复', 'connection')[0].id, 'backup');
  assert.equal(SettingsCatalog.search('恢复', 'workspace').length, 0);
  assert.equal(SettingsCatalog.search('不存在的选项').length, 0);
  assert.equal(new Set(SETTINGS_ENTRIES.map(entry => entry.id)).size, SETTINGS_ENTRIES.length);
  assert.ok(SETTINGS_ENTRIES.every(entry => SETTINGS_GROUPS.some(group => group.id === entry.group)));
  assert.equal(SettingsCatalog.normalize('cloud'), 'backup'); assert.equal(SettingsCatalog.normalize('unknown'), 'overview');
});

function documentNavigationHarness(overrides = {}) {
  const relative = 'views/reader/huawei/HuaweiDocWorkspace.ets';
  const calls = [];
  const view = { activeModal: '', jumpDialogOpen: false, exitDialogOpen: false, restoreSourceBusy: false,
    isAnnotateMode: true, exitSaving: false, splitMode: 'none', isPhone: false, exitSaveToken: 0,
    documentDirty: true, scratchpadDirty: false, barsVisible: false, penOptionsOpen: true, isPenPaletteExpanded: true,
    scrollTravel: 50, onClose: () => calls.push('close'), showToast: message => calls.push(message),
    ...overrides };
  for (const method of ['handleBackRequest', 'returnToReading', 'beginReaderSave', 'exitSaveFinished', 'switchSplitMode']) {
    view[method] = viewMethod(relative, method);
  }
  return { view, calls };
}

test('back leaves annotation in read-only mode and saves without closing the PDF or whiteboard', () => {
  const { view, calls } = documentNavigationHarness();
  view.handleBackRequest();
  assert.equal(view.isAnnotateMode, false); assert.equal(view.barsVisible, true);
  assert.equal(view.penOptionsOpen, false); assert.equal(view.scrollTravel, 0);
  assert.equal(view.saveDestination, 'reading'); assert.equal(view.exitSaveToken, 1);
  view.handleBackRequest(); assert.equal(view.exitSaveToken, 1); assert.deepEqual(calls, []);
  view.documentDirty = false; view.exitSaveFinished(true);
  assert.equal(view.exitSaving, false); assert.equal(view.exitDialogOpen, false);
  assert.ok(!calls.includes('close'));
  view.handleBackRequest(); assert.equal(calls.at(-1), 'close');
});

test('back closes a transient dialog first and never leaves the document during source recovery', () => {
  const { view } = documentNavigationHarness({ jumpDialogOpen: true });
  view.handleBackRequest(); assert.equal(view.jumpDialogOpen, false); assert.equal(view.isAnnotateMode, true);
  view.restoreSourceBusy = true; view.handleBackRequest(); assert.equal(view.exitSaveToken, 0);
});

test('returning to reading waits for main and scratchpad, and failed persistence stays recoverable', () => {
  const { view, calls } = documentNavigationHarness({ splitMode: 'scratchpad', scratchpadDirty: true });
  view.handleBackRequest(); assert.equal(view.exitPending, 2);
  view.exitSaveFinished(true); assert.equal(view.exitSaving, true);
  view.exitSaveFinished(false); assert.equal(view.exitSaving, false); assert.equal(view.exitDialogOpen, true);
  assert.ok(!calls.includes('close')); assert.equal(view.scratchpadDirty, true);
  view.beginReaderSave(); assert.equal(view.exitPending, 2); assert.equal(view.exitSaveToken, 2);
  view.documentDirty = false; view.scratchpadDirty = false;
  view.exitSaveFinished(true); view.exitSaveFinished(true); assert.equal(view.exitDialogOpen, false);
  assert.ok(!calls.includes('close'));
});

test('closing a dirty scratchpad waits for both saves and never unmounts it on failure', () => {
  for (const success of [true, false]) {
    const { view, calls } = documentNavigationHarness({ splitMode: 'scratchpad', scratchpadDirty: true });
    view.switchSplitMode('none'); assert.equal(view.splitMode, 'scratchpad'); assert.equal(view.saveDestination, 'split');
    view.exitSaveFinished(true); view.exitSaveFinished(success);
    assert.equal(view.splitMode, success ? 'none' : 'scratchpad'); assert.ok(!calls.includes('close'));
  }
});

test('unreadable PDFs cannot enter annotation, while whiteboards and readable PDFs can', () => {
  const mode = viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets', 'setAnnotationMode');
  for (const [whiteboard, ready, expected] of [[false, false, false], [false, true, true], [true, false, true]]) {
    const view = { exitSaving: false, restoreSourceBusy: false, isAnnotateMode: false, pdfSourceReady: ready, annotationError: '',
      whiteboardReady: true,
      note: {}, isHandwritingNote: () => whiteboard, showToast() {} };
    mode.call(view, true); assert.equal(view.isAnnotateMode, expected);
  }
});

test('source restoration is serialized with ink writes and preserves latest library and annotation fields', async () => {
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  const service = new ReaderCommitService();
  let notes = [studyNote({ type: 'PDF', sourceUri: '/sandbox/old.pdf', pageAnnotations: 'old', pdfTextJson: 'old text', favorite: true })];
  const ports = { notes: () => notes, saveNotes: async () => {}, saveDocument: async () => {}, publish: items => { notes = items; } };
  const replacement = { ...notes[0], sourceUri: '/sandbox/new.pdf', pageCount: 2, pdfTextJson: undefined, favorite: false };
  await Promise.all([service.commit({ ...notes[0], pageAnnotations: 'latest ink' }, '', ports, true, 'pdf'),
    service.commit(replacement, '', ports, false, 'pdf-source'),
    service.commit({ ...notes[0], scratchpadStrokes: 'new scratch' }, '', ports, true, 'scratchpad')]);
  assert.equal(notes[0].sourceUri, '/sandbox/new.pdf'); assert.equal(notes[0].pageAnnotations, 'latest ink');
  assert.equal(notes[0].favorite, true); assert.equal(notes[0].pdfTextJson, undefined);
  assert.equal(notes[0].scratchpadStrokes, 'new scratch');
});

test('source restoration cleans only the new copy on save failure and keeps a referenced old source on success', async () => {
  for (const fail of [true, false]) {
    const removed = []; const old = '/sandbox/documents/old.pdf'; const fresh = '/sandbox/documents/new.pdf';
    const restore = viewMethod('pages/Index.ets', 'restoreReaderPdfSource', {
      Error,
      PdfDocumentService: { getInstance: () => ({ removeManagedPdf: async (_, source) => removed.push(source) }) } });
    const view = { getAbilityContext: () => ({}), fullScreenDocOpen: true, fullScreenDocNote: { id: 'a', sourceUri: old },
      storage: { selectReplacementPdf: async () => ({ id: 'a', sourceUri: fresh, contentDetail: '' }) },
      notes: [{ sourceUri: old }], trash: [], notify() {}, handleSaved: async () => { if (fail) throw Error('disk full'); } };
    if (fail) { await assert.rejects(restore.call(view), /disk full/); assert.deepEqual(removed, [fresh]); }
    else { await restore.call(view); assert.deepEqual(removed, []); }
  }
});

test('source picker cancellation does not write or remove existing data', async () => {
  const restore = viewMethod('pages/Index.ets', 'restoreReaderPdfSource'); let saved = 0;
  const view = { getAbilityContext: () => ({}), fullScreenDocNote: { id: 'a', sourceUri: 'old' },
    storage: { selectReplacementPdf: async () => null }, handleSaved: async () => saved++ };
  await restore.call(view); assert.equal(saved, 0); assert.equal(view.fullScreenDocNote.sourceUri, 'old');
});

test('a previous document or save request cannot finish or close the current reader', () => {
  const { view, calls } = documentNavigationHarness({ loadedNoteId: 'new', isAnnotateMode: false });
  view.beginReaderSave(); view.saveDestination = 'close';
  view.exitSaveFinished(true, 'old', view.exitSaveToken);
  view.exitSaveFinished(true, 'new', view.exitSaveToken - 1);
  assert.equal(view.exitPending, 1); assert.equal(view.exitSaving, true); assert.deepEqual(calls, []);
  view.exitSaveFinished(true, 'new', view.exitSaveToken); assert.deepEqual(calls, ['close']);
});

test('late reader persistence publishes library data without replacing a different open document', async () => {
  const save = viewMethod('pages/Index.ets', 'handleSaved');
  for (const currentId of ['new', 'old']) {
    const view = { formatTime: () => 'now', getAbilityContext: () => ({}), notes: [],
      readingNote: { id: currentId, title: 'keep' }, fullScreenDocNote: { id: 'new', title: 'keep' }, refreshGraph() {},
      storage: {}, readerCommits: { commit: async (note, content, ports) => ports.publish([note], { ...note, title: 'saved' }) } };
    await save.call(view, { id: 'old' }, 'body', 'pdf');
    assert.equal(view.readingNote.id, currentId); assert.equal(view.readingNote.title, currentId === 'old' ? 'saved' : 'keep');
    assert.equal(view.fullScreenDocNote.id, 'new'); assert.equal(view.fullScreenDocNote.title, 'keep');
    assert.equal(view.notes[0].id, 'old');
  }
});
test('pen contacts ignore repeated starts and unrelated cancellations without losing their initiating pointer', () => {
  const input = new InkInputService();
  assert.equal(input.read(touchEvent(0, 7, 2), true).phase, 'begin');
  assert.equal(input.read(touchEvent(0, 7, 2), true).phase, 'ignore');
  assert.equal(input.read(touchEvent(0, 9, 2), true).phase, 'ignore');
  assert.equal(input.read(touchEvent(3, 9, 2), true).phase, 'ignore');
  assert.equal(input.isActive(), true);
  assert.equal(input.read(touchEvent(2, 7, 2), true).phase, 'move');
  assert.equal(input.read(touchEvent(1, 7, 2), true).phase, 'end');
  assert.equal(input.isActive(), false);
});

test('whiteboard finger input keeps a stable width and a stylus can take over without accepting palm release', () => {
  const input = new InkInputService();
  const first = input.read(touchEvent(0, 1, 1, { pressure: 0 }), true);
  assert.equal(first.phase, 'begin'); assert.equal(first.samples[0].pressure, 0.5);
  const move = input.read(touchEvent(2, 1, 1, { pressure: 0,
    getHistoricalPoints: () => [{ touchObject: { id: 1, x: 7, y: 9 }, force: 0 }] }), true);
  assert.deepEqual(plain(move.samples).map(point => point.pressure), [0.5, 0.5]);
  assert.equal(input.read(touchEvent(0, 7, 2), true).phase, 'begin');
  assert.equal(input.read(touchEvent(1, 1, 1), true).phase, 'ignore');
  assert.equal(input.read(touchEvent(1, 7, 2), true).phase, 'end');
});

test('whiteboard exit persistence finalizes contact, waits for storage and only then clears current dirty state', async () => {
  const save = viewMethod('views/reader/HandwritingCanvas.ets', 'saveForExit');
  const dirty = [], states = [], finished = []; let release, finalized = 0;
  const view = { saveTimer: -1, saveRevision: 4, savedRevision: 2, loadedNoteId: 'ink', isScratchpad: false,
    finishStroke: () => finalized++, strokeSnapshot: () => ({ id: 'ink', contentDetail: 'body' }),
    onCommitForExit: () => new Promise(resolve => { release = resolve; }),
    onDirtyChange: value => dirty.push(value), onSaveStateChange: value => states.push(value),
    onExitSaveFinished: ok => finished.push(ok) };
  const pending = save.call(view); assert.equal(finalized, 1); assert.deepEqual(dirty, []); assert.deepEqual(finished, []);
  release(); await pending;
  assert.equal(view.savedRevision, 4); assert.deepEqual(dirty, [false]);
  assert.deepEqual(states, ['已保存']); assert.deepEqual(finished, [true]);
});

test('failed or obsolete whiteboard exit saves preserve newer dirty state and do not publish a stale saved status', async () => {
  const save = viewMethod('views/reader/HandwritingCanvas.ets', 'saveForExit');
  for (const obsolete of ['revision', 'note', 'failure']) {
    const dirty = [], states = [], finished = []; let release, reject;
    const view = { saveTimer: -1, saveRevision: 4, savedRevision: 2, loadedNoteId: 'ink',
      finishStroke() {}, strokeSnapshot: () => ({ id: 'ink', contentDetail: 'body' }),
      onCommitForExit: () => new Promise((resolve, fail) => { release = resolve; reject = fail; }),
      onDirtyChange: value => dirty.push(value), onSaveStateChange: value => states.push(value),
      onExitSaveFinished: ok => finished.push(ok) };
    const pending = save.call(view);
    if (obsolete === 'revision') { view.saveRevision++; release(); }
    else if (obsolete === 'note') { view.loadedNoteId = 'other'; release(); }
    else { reject(Error('disk full')); }
    await pending; assert.equal(view.savedRevision, 2); assert.deepEqual(dirty, []);
    assert.deepEqual(states, obsolete === 'failure' ? ['保存失败'] : []);
    assert.deepEqual(finished, [false]);
  }
});

test('viewport redraw preserves an active eraser path instead of restoring ink underneath it', () => {
  const redraw = viewMethod('views/reader/HandwritingCanvas.ets', 'redrawAll', { InkRenderer });
  const recorder = inkRecorder(); let historical = 0, clears = 0;
  Object.assign(recorder.ctx, { clearRect() { clears++; }, translate() {}, scale() {} });
  const active = { points: [{ x: 20, y: 30 }, { x: 30, y: 40 }], isEraser: true };
  redraw.call({ context: recorder.ctx, canvasWidth: 360, canvasHeight: 700, zoomScale: 0.3,
    panX: 4, panY: -8, strokes: [{}], currentStroke: active, drawTimer: -1,
    inkFrame: { render: (_, w, h, paint) => { recorder.ctx.clearRect(0, 0, w, h); paint(recorder.ctx); } },
    drawPaperBackground() {}, drawSingleStroke: () => historical++, style: () => ({ color: '#000', width: 18, highlighter: false, eraser: true }) });
  assert.equal(clears, 1); assert.equal(historical, 1);
  assert.ok(recorder.calls.filter(call => ['stroke', 'fill'].includes(call[0])).every(call => call[3] === 'destination-out'));
  assert.ok(recorder.calls.some(call => call[0] === 'line'));
});

function inkFrameHarness() {
  const surfaces = [], frames = [], closed = [];
  class OffscreenCanvas {
    constructor(width, height) {
      this.width = width; this.height = height; this.ink = inkRecorder(); surfaces.push(this);
      Object.assign(this.ink.ctx, { clearRect: () => { this.ink.calls.length = 0; }, translate() {}, scale() {} });
    }
    getContext() { return this.ink.ctx; }
    transferToImageBitmap() { const frame = { calls: plain(this.ink.calls), close: () => closed.push(frame) }; return frame; }
  }
  const { InkFrameComposer } = load(`${base}services/ink/InkFrameComposer.ets`, { OffscreenCanvas, RenderingContextSettings: class {} });
  const target = { clearRect() { throw Error('visible layer must not expose a cleared or partially replayed frame'); },
    transferFromImageBitmap(frame) { frames.push(frame.calls); } };
  return { composer: new InkFrameComposer(), target, surfaces, frames, closed };
}

test('mixed area and stroke erase replay publishes only finished chronological ink frames, including undo and reload', () => {
  const h = inkFrameHarness(), relative = 'views/reader/HandwritingCanvas.ets';
  const pen = { color: '#000', width: 3, isEraser: false, isHighlighter: false, points: [{ x: 5, y: 50 }, { x: 100, y: 50 }], referenceWidth: 1200 };
  const mask = { ...pen, width: 30, isEraser: true, points: [{ x: 30, y: 50 }] };
  const later = { ...pen, points: [{ x: 30, y: 50 }] };
  const v = { context: h.target, inkFrame: h.composer, canvasWidth: 1200, canvasHeight: 700, zoomScale: 1,
    panX: 0, panY: 0, drawTimer: -1, boundsCache: new Map(), currentStroke: null, strokes: [pen, mask, later], drawPaperBackground() {} };
  for (const name of ['redrawAll', 'drawSingleStroke', 'style']) v[name] = viewMethod(relative, name, { InkRenderer, CanvasViewport });
  const modes = frame => frame.filter(row => ['fill', 'stroke'].includes(row[0])).map(row => row[3]);
  v.redrawAll(); assert.deepEqual(modes(h.frames[0]).slice(-2), ['destination-out', 'source-over']);
  v.strokes = v.strokes.filter(stroke => !CanvasStrokeEraser.hit(stroke, { x: 5, y: 50 }, { x: 5, y: 50 }, 2));
  assert.deepEqual(v.strokes, [mask, later]); v.redrawAll();
  assert.deepEqual(modes(h.frames[1]), ['destination-out', 'source-over']);
  v.strokes = JSON.parse(JSON.stringify([pen, mask, later])); v.redrawAll();
  assert.deepEqual(modes(h.frames[2]), modes(h.frames[0])); assert.equal(h.closed.length, h.frames.length);
});

test('PDF page replay composites saved masks and active area preview without clearing the visible layer', () => {
  const h = inkFrameHarness(), relative = 'views/reader/pdf/PdfPageCanvas.ets';
  const pen = { id: 'p', color: '#000', width: 3, isHighlighter: false, isEraser: false, points: [{ u: .1, v: .2 }] };
  const mask = { ...pen, id: 'mask', width: 20, isEraser: true };
  const active = { ...mask, id: 'active' };
  const v = { context: h.target, inkFrame: h.composer, pageWidth: 720, pageHeight: 1000, strokes: [pen, mask], currentStroke: active };
  for (const name of ['redrawAll', 'renderStroke', 'mapped', 'style']) v[name] = viewMethod(relative, name, { InkRenderer });
  v.redrawAll(); assert.equal(h.frames.length, 1);
  assert.deepEqual(h.frames[0].filter(row => row[0] === 'fill').map(row => row[3]), ['source-over', 'destination-out', 'destination-out']);
  v.currentStroke = null; v.strokes = [mask]; v.redrawAll();
  assert.deepEqual(h.frames[1].filter(row => row[0] === 'fill').map(row => row[3]), ['destination-out']);
});

test('ink frame resources are reused, resized and released; failed rendering never publishes half a frame', () => {
  const h = inkFrameHarness(); h.composer.render(h.target, 360, 700, () => {}); h.composer.render(h.target, 360, 700, () => {});
  assert.equal(h.surfaces.length, 1); h.composer.render(h.target, 700, 360, () => {});
  assert.equal(h.surfaces.length, 2); assert.equal(h.surfaces[0].width, 0); assert.equal(h.closed.length, 3);
  assert.throws(() => h.composer.render(h.target, 700, 360, () => { throw Error('paint'); })); assert.equal(h.frames.length, 3);
  assert.throws(() => h.composer.render({ transferFromImageBitmap() { throw Error('publish'); } }, 700, 360, () => {}));
  assert.equal(h.closed.length, 4); h.composer.release(); assert.equal(h.surfaces[1].height, 0);
});

test('whiteboard stroke erase ignores empty movement and schedules at most one redraw per touch batch', () => {
  const relative = 'views/reader/HandwritingCanvas.ets', batches = []; let redraws = 0;
  const pen = { color: '#000', width: 2, referenceWidth: 1200, points: [{ x: 10, y: 50 }, { x: 100, y: 50 }] };
  const mask = { ...pen, isEraser: true };
  const v = { strokes: [pen, mask], eraseBefore: null, currentStroke: null, isEraser: true, eraserMode: 'stroke',
    eraserWidth: 18, selectedColor: '#000', zoomScale: 1, panX: 0, panY: 0, fingerDrawing: true,
    context: { save() {}, restore() {}, translate() {}, scale() {} }, liveContext: { clearRect() {} },
    input: { read: () => batches.shift(), isActive: () => false }, shortcuts: { claim() {} },
    navigateTouch: () => false, onFocused() {}, onDirtyChange() {}, requestRedraw: () => redraws++ };
  const touch = viewMethod(relative, 'handleTouch', { CanvasViewport, CanvasStrokeEraser, InkRenderer, SourceTool: { Pen: 2 }, TouchType: { Down: 0 } });
  v.style = viewMethod(relative, 'style');
  const event = { sourceTool: 1, type: 0, stopPropagation() {} };
  batches.push({ phase: 'begin', samples: [{ x: 10, y: 200, pressure: .5 }] }); touch.call(v, event);
  const original = v.strokes; assert.equal(redraws, 0);
  batches.push({ phase: 'move', samples: [{ x: 20, y: 200, pressure: .5 }] }); touch.call(v, event);
  assert.equal(v.strokes, original); assert.equal(redraws, 0);
  batches.push({ phase: 'move', samples: [{ x: 20, y: 50, pressure: .5 }, { x: 60, y: 50, pressure: .5 }] }); touch.call(v, event);
  assert.equal(redraws, 1); assert.deepEqual(v.strokes, [mask]);
});

const { PdfPageDataSource } = load(`${base}services/document/PdfPageDataSource.ets`);
test('a 600-page PDF data source keeps every page addressable and reloads only registered lazy listeners', () => {
  const pages = Array.from({ length: 600 }, (_, pageIndex) => ({ pageIndex, sections: [] })), source = new PdfPageDataSource();
  let reloads = 0; const listener = { onDataReloaded: () => reloads++ };
  source.registerDataChangeListener(listener); source.registerDataChangeListener(listener); source.setPages(pages);
  assert.equal(source.totalCount(), 600); assert.equal(source.getData(599), pages[599]); assert.equal(reloads, 1);
  source.unregisterDataChangeListener(listener); source.setPages([]); assert.equal(reloads, 1); assert.equal(source.totalCount(), 0);
});

test('whiteboard title and preview persist while scratchpad saves preserve all main and library fields', async () => {
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  const service = new ReaderCommitService();
  const stale = studyNote({ type: '白板', favorite: false, category: 'old', strokes: 'old ink', scratchpadStrokes: 'old scratch' });
  let notes = [studyNote({ type: '白板', favorite: true, category: 'new', coverUrl: 'cover:mist', tags: ['current'] })];
  const ports = { notes: () => notes, saveDocument: async () => {}, saveNotes: async () => {}, publish: next => { notes = next; } };
  await Promise.all([
    service.commit({ ...stale, title: '课堂白板', previewText: '包含 1 条墨迹', strokes: 'new ink' }, '# 课堂白板', ports, true, 'handwriting'),
    service.commit({ ...stale, title: '旧标题', scratchpadStrokes: 'new scratch' }, '旧正文', ports, true, 'scratchpad')
  ]);
  assert.equal(notes[0].title, '课堂白板'); assert.equal(notes[0].contentDetail, '# 课堂白板');
  assert.equal(notes[0].previewText, '包含 1 条墨迹'); assert.equal(notes[0].strokes, 'new ink');
  assert.equal(notes[0].scratchpadStrokes, 'new scratch'); assert.equal(notes[0].favorite, true);
  assert.equal(notes[0].category, 'new'); assert.deepEqual(plain(notes[0].tags), ['current']);
});

test('re-attached PDF sources and concurrent annotation saves preserve each other and library metadata', async () => {
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  const service = new ReaderCommitService();
  const stale = studyNote({ type: 'PDF', sourceUri: 'old.pdf', pageAnnotations: 'old ink', pdfTextJson: 'old page text' });
  let notes = [studyNote({ type: 'PDF', favorite: true, tags: ['current'], pageAnnotations: 'current ink' })];
  const ports = { notes: () => notes, saveDocument: async () => {}, saveNotes: async () => {}, publish: next => { notes = next; } };
  await Promise.all([
    service.commit({ ...stale, sourceUri: 'new.pdf', sourceType: 'pdf', pageCount: 3, pdfTextJson: undefined }, stale.contentDetail, ports, false, 'pdf-source'),
    service.commit({ ...stale, pageAnnotations: 'new ink' }, stale.contentDetail, ports, false, 'pdf')
  ]);
  assert.equal(notes[0].sourceUri, 'new.pdf'); assert.equal(notes[0].sourceType, 'pdf'); assert.equal(notes[0].pageCount, 3);
  assert.equal(notes[0].pdfTextJson, undefined); assert.equal(notes[0].pageAnnotations, 'new ink');
  assert.equal(notes[0].favorite, true); assert.deepEqual(plain(notes[0].tags), ['current']);
});

test('late whiteboard clear confirmation cannot erase another note or a canvas returned to reading mode', async () => {
  for (const changed of ['note', 'readOnly']) {
    let confirm, mutations = 0;
    const clear = viewMethod('views/reader/HandwritingCanvas.ets', 'handleClear', {
      promptAction: { showDialog: () => new Promise(resolve => { confirm = resolve; }) }
    });
    const view = { readOnly: false, loadedNoteId: 'a', strokes: [{}], finishStroke() {},
      remember: () => mutations++, redrawAll() {}, scheduleSave() {} };
    const pending = clear.call(view);
    if (changed === 'note') { view.loadedNoteId = 'b'; } else { view.readOnly = true; }
    confirm({ index: 1 }); await pending;
    assert.equal(mutations, 0); assert.equal(view.strokes.length, 1);
  }
});

test('paper guides align with world movement, support ruled paper and cap visible work at tiny zoom', () => {
  const { CanvasPaperGuides } = load(`${base}services/ink/CanvasPaperGuides.ets`);
  const a = CanvasPaperGuides.lines(360, 700, 0.3, 0, 0, 'grid');
  const b = CanvasPaperGuides.lines(360, 700, 0.3, 4, 8, 'grid');
  const vertical = rows => rows.filter(line => line.x1 === line.x2);
  const horizontal = rows => rows.filter(line => line.y1 === line.y2);
  assert.ok(Math.abs(vertical(b)[0].x1 - vertical(a)[0].x1 - 4) < 1e-6);
  assert.ok(Math.abs(horizontal(b)[0].y1 - horizontal(a)[0].y1 - 8) < 1e-6);
  const ruled = CanvasPaperGuides.lines(360, 700, 0.3, -80, -500, 'ruled');
  assert.ok(ruled.length); assert.equal(vertical(ruled).length, 0);
  for (const zoom of [0.00001, 0.08, 0.3, 1, 8]) {
    const lines = CanvasPaperGuides.lines(8000, 12000, zoom, -999, 881, 'grid');
    assert.ok(lines.length <= 162); assert.ok(lines.length > 0);
    assert.ok(lines.every(line => line.x1 >= 0 && line.x2 <= 8000 && line.y1 >= 0 && line.y2 <= 12000));
  }
  for (const style of ['blank', 'unknown']) { assert.equal(CanvasPaperGuides.lines(360, 700, 0.3, 0, 0, style).length, 0); }
  assert.equal(CanvasPaperGuides.lines(NaN, 700, 0.3, 0, 0, 'grid').length, 0);
});

test('paper background renders to its own context and never becomes a stored or erasable stroke', () => {
  const { CanvasPaperGuides } = load(`${base}services/ink/CanvasPaperGuides.ets`);
  const render = viewMethod('views/reader/HandwritingCanvas.ets', 'drawPaperBackground', { CanvasPaperGuides });
  const recorder = inkRecorder(); let clears = 0;
  Object.assign(recorder.ctx, { clearRect() { clears++; } });
  const strokes = [{ points: [{ x: 1, y: 2 }], isEraser: true }]; const before = JSON.stringify(strokes);
  render.call({ paperContext: recorder.ctx, canvasWidth: 360, canvasHeight: 700, zoomScale: 0.3, panX: 0, panY: 0,
    paperBackground: 'grid', strokes, palette: () => ({ border: '#ddd' }) });
  assert.equal(clears, 1); assert.ok(recorder.calls.some(call => call[0] === 'stroke'));
  assert.ok(recorder.calls.filter(call => call[0] === 'stroke').every(call => call[3] !== 'destination-out'));
  assert.equal(JSON.stringify(strokes), before);
});

const { CanvasStrokePolicy } = load(`${base}services/ink/CanvasStrokePolicy.ets`);
const validWhiteboardStroke = change => ({ points: [{ x: -42, y: 520, pressure: 0.5 }, { x: 100, y: 600 }],
  color: '#2563EB', width: 18, referenceWidth: 1200, isHighlighter: false, isEraser: false, ...change });

test('whiteboard snapshot validation preserves legacy optional fields, negative coordinates and the wide zoomed eraser', () => {
  const legacy = { points: [{ x: -300, y: 400 }], color: 'black', width: 3 };
  const rows = [legacy, validWhiteboardStroke({ width: 225, isEraser: true }), validWhiteboardStroke({ isHighlighter: true })];
  assert.deepEqual(plain(CanvasStrokePolicy.parse(JSON.stringify(rows))), rows);
  assert.equal(CanvasStrokePolicy.parse(undefined).length, 0); assert.equal(CanvasStrokePolicy.parse('').length, 0);
  assert.equal(CanvasStrokePolicy.parse('[]').length, 0);
});

for (const [label, raw] of [
  ['object instead of strokes', '{}'], ['null strokes', 'null'], ['broken JSON', '[{"points":'],
  ...[null, {}, validWhiteboardStroke({ points: {} }), validWhiteboardStroke({ points: [null] }),
    validWhiteboardStroke({ points: [{ x: '20', y: 30 }] }), validWhiteboardStroke({ points: [{ x: null, y: 30 }] }),
    validWhiteboardStroke({ points: [{ x: 20, y: 30, pressure: 2 }] }), validWhiteboardStroke({ points: [{ x: 20, y: 30, pressure: null }] }),
    validWhiteboardStroke({ points: [{ x: 1e10, y: 30 }] }), validWhiteboardStroke({ width: 0 }),
    validWhiteboardStroke({ width: -1 }), validWhiteboardStroke({ width: '3' }), validWhiteboardStroke({ width: 4097 }),
    validWhiteboardStroke({ referenceWidth: 0 }), validWhiteboardStroke({ referenceWidth: '1200' }),
    validWhiteboardStroke({ isEraser: 'true' }), validWhiteboardStroke({ isHighlighter: null }),
    validWhiteboardStroke({ color: '' }), validWhiteboardStroke({ color: {} })]
    .map((row, index) => [`invalid row ${index}`, JSON.stringify([validWhiteboardStroke(), row])])
]) {
  test(`corrupted whiteboard snapshots reject the entire payload: ${label}`, () => {
    assert.throws(() => CanvasStrokePolicy.parse(raw));
  });
}

test('whiteboard loading failure reports unavailable content while keeping the exact original raw snapshot', () => {
  const loadInk = viewMethod('views/reader/HandwritingCanvas.ets', 'loadStrokes', { CanvasStrokePolicy, CanvasViewport });
  for (const scratchpad of [false, true]) {
    const ready = [], dirty = []; const raw = '[{"points":null,"width":3,"color":"#000"}]';
    const view = { note: { id: 'ink', strokes: raw, scratchpadStrokes: raw }, isScratchpad: scratchpad,
      loadError: '', toolsVisible: true, boundsCache: new Map(), viewportReady: false,
      onContentReady: value => ready.push(value), onDirtyChange: value => dirty.push(value) };
    loadInk.call(view);
    assert.equal(view.loadedRaw, raw); assert.equal(view.note.strokes, raw); assert.equal(view.note.scratchpadStrokes, raw);
    assert.equal(view.strokes.length, 0); assert.ok(view.loadError); assert.equal(view.toolsVisible, false);
    assert.equal(view.saveRevision, 0); assert.deepEqual(dirty, [false]); assert.deepEqual(ready, [false]);
  }
});

test('damaged unchanged whiteboards and scratchpads allow reader return without writing empty data', async () => {
  const save = viewMethod('views/reader/HandwritingCanvas.ets', 'saveForExit');
  for (const scratchpad of [false, true]) {
    let writes = 0; const finished = []; const raw = '{broken ink}';
    const view = { isScratchpad: scratchpad, note: { id: 'ink', strokes: raw, scratchpadStrokes: raw }, loadedNoteId: 'ink',
      exitSaveToken: 8, saveRevision: 0, saveTimer: -1, loadError: 'error', loadedRaw: raw,
      finishStroke() {}, strokeSnapshot() { throw Error('must not generate empty snapshot'); },
      onCommitForExit: async () => { writes++; }, onSaveStateChange() {},
      onExitSaveFinished: (...args) => finished.push(args) };
    await save.call(view); assert.equal(writes, 0); assert.deepEqual(finished, [[true, 'ink', 8]]);
    assert.equal(view.note.strokes, raw); assert.equal(view.note.scratchpadStrokes, raw);
  }
});

test('damaged whiteboard saves fail when revision or original raw has changed and never overwrite the source', async () => {
  const save = viewMethod('views/reader/HandwritingCanvas.ets', 'saveForExit');
  for (const changed of ['revision', 'raw']) {
    let writes = 0; const states = [], finished = [];
    const view = { note: { id: 'ink', strokes: changed === 'raw' ? '{new broken}' : '{broken}' }, loadedNoteId: 'ink',
      exitSaveToken: 9, saveRevision: changed === 'revision' ? 1 : 0, saveTimer: -1, loadError: 'error', loadedRaw: '{broken}',
      finishStroke() {}, strokeSnapshot() { throw Error('must not generate empty snapshot'); },
      onCommitForExit: async () => { writes++; }, onSaveStateChange: value => states.push(value),
      onExitSaveFinished: (...args) => finished.push(args) };
    await save.call(view); assert.equal(writes, 0); assert.deepEqual(finished, [[false, 'ink', 9]]);
    assert.ok(states[0].includes('恢复'));
  }
});

test('damaged whiteboard snapshot and autosave preserve original metadata and refuse storage writes', async () => {
  const snapshot = viewMethod('views/reader/HandwritingCanvas.ets', 'strokeSnapshot');
  const flush = viewMethod('views/reader/HandwritingCanvas.ets', 'flushSave');
  const original = { id: 'ink', title: '原标题', strokes: '{broken}', scratchpadStrokes: '{broken scratch}', contentDetail: '原正文' };
  let writes = 0; const states = [];
  const view = { editingNote: original, loadError: 'error', title: '误改标题', strokes: [], saveTimer: 1,
    onSaved: async () => { writes++; }, onSaveStateChange: value => states.push(value),
    strokeSnapshot() { throw Error('autosave must not create an empty snapshot'); } };
  assert.deepEqual(plain(snapshot.call(view)), original);
  await flush.call(view); assert.equal(writes, 0); assert.equal(view.saveTimer, -1); assert.ok(states[0].includes('恢复'));
});

test('restoring an unreadable whiteboard with the same note ID reloads and re-enables content without losing the original failure data', () => {
  const changed = viewMethod('views/reader/HandwritingCanvas.ets', 'onNoteChanged');
  const repaired = JSON.stringify([validWhiteboardStroke()]); let loads = 0, redraws = 0;
  const view = { note: { id: 'ink', title: '恢复笔记', strokes: repaired }, loadedNoteId: 'ink', loadedRaw: '{broken}',
    loadError: 'error', saveRevision: 0, loadStrokes: () => loads++, redrawAll: () => redraws++ };
  changed.call(view); assert.equal(loads, 1); assert.equal(redraws, 1); assert.equal(view.editingNote.strokes, repaired);
  assert.equal(view.title, '恢复笔记');
});

test('a stylus takeover completes finger ink before acquiring the new pen pointer', () => {
  const handle = viewMethod('views/reader/HandwritingCanvas.ets', 'handleTouch', { ...penEnums, CanvasViewport });
  const order = []; const view = { navigateTouch: () => false, readOnly: false, loadError: '',
    input: { isActive: () => true, isPenActive: () => false, read: () => { order.push('read new pen'); return { phase: 'ignore' }; } },
    finishStroke: () => order.push('finish old finger') };
  handle.call(view, touchEvent(0, 7, 2)); assert.deepEqual(order, ['finish old finger', 'read new pen']);
});

const { GraphTopicPolicy } = load(`${base}services/GraphTopicPolicy.ets`);
test('empty saved projects and note-only categories share one deduplicated topic list', () => {
  assert.deepEqual(plain(GraphTopicPolicy.topics([{category:'课程'}, {category:'课程'}, {category:''}],
    [{name:'空主题'}, {name:'课程'}, {name:' 空主题 '}])),
    [{name:'空主题',count:0},{name:'课程',count:2},{name:'未分类',count:1}]);
  assert.equal(GraphTopicPolicy.topics([], [{name:'all'}])[0].name, 'all');
});

test('actual theme creation waits for persistence, prevents double clicks and survives reload', async () => {
  const create = viewMethod('pages/Index.ets', 'createProject');
  let release, saved; const calls=[];
  const view={customProjects:[], projectCreateBusy:false, getAbilityContext:()=>({}),
    storage:{saveProjects:(_,next)=>new Promise(resolve=>{saved=plain(next);release=resolve;})},
    rebuildSpaces:()=>calls.push('refresh'), notify:message=>calls.push(message)};
  const pending=create.call(view,'空主题','#6366F1','📁');
  assert.equal(view.customProjects.length,0); assert.equal(calls.length,0);
  assert.equal(await create.call(view,'重复点击','#6366F1','📁'),false);
  release(); assert.equal(await pending,true); assert.equal(view.customProjects[0].name,'空主题');
  assert.equal(GraphTopicPolicy.topics([],saved)[0].count,0);
  assert.equal(await create.call(view,'空主题','#6366F1','📁'),false);
});

test('theme persistence failure leaves the original state and permits retry', async () => {
  const create=viewMethod('pages/Index.ets','createProject');
  const original=[{name:'已有主题'}];const messages=[];
  const view={customProjects:original,projectCreateBusy:false,getAbilityContext:()=>({}),
    storage:{saveProjects:async()=>{throw Error('full');}},notify:m=>messages.push(m),rebuildSpaces:()=>assert.fail('uncommitted refresh')};
  assert.equal(await create.call(view,'新主题','',''),false);
  assert.equal(view.customProjects,original);assert.equal(view.projectCreateBusy,false);
  assert.match(messages[0],/失败/);
});

for(const outcome of ['success','failure','exception','leave']) {
  test(`graph confirmation preserves input until its ${outcome} result`,async()=>{
    const submit=viewMethod('views/workspace/GraphWorkspace.ets','submitGalaxy',{promptAction:{showToast(){}}});
    let release,writes=0,draws=0;
    const view={galaxySaving:false,newGalaxyName:' 数学 ',alive:true,activeGalaxy:'__all_topics__',isCreatingGalaxy:true,
      getGalaxies:()=>[],canvasReady:true,drawGraph:()=>draws++,
      onCreateGalaxy:()=>{writes++;return new Promise((resolve,reject)=>{release=()=>outcome==='exception'?reject(Error('full')):resolve(outcome!=='failure');});}};
    const pending=submit.call(view);await submit.call(view);assert.equal(writes,1);assert.equal(view.newGalaxyName,' 数学 ');
    if(outcome==='leave')view.alive=false;
    release();await pending;
    if(outcome==='success'){assert.equal(view.activeGalaxy,'数学');assert.equal(view.newGalaxyName,'');assert.equal(view.isCreatingGalaxy,false);assert.equal(draws,1);}
    else{assert.equal(view.activeGalaxy,'__all_topics__');assert.equal(view.newGalaxyName,' 数学 ');assert.equal(draws,0);}
  });
}

test('local formatter preserves original facts, negation, code and formulas without any provider', async () => {
  const service=load(extractFile).SmartExtractService.getInstance();
  const source='【课程通知】\n一、作业\n2026年10月20日前提交报告。\n无需报名。\n```\n准备删除记录\n```\n$$\nx = 12\n$$';
  const result=await service.extract(source,'整理笔记','study');
  assert.equal(result.processingMode,'local');assert.equal(result.rawMarkdown,source);
  assert.match(result.formattedMarkdown,/## 一、作业/);assert.match(result.formattedMarkdown,/无需报名/);
  assert.equal(result.tasks.length,1);assert.match(result.tasks[0].title,/提交报告/);
  assert.match(result.formattedMarkdown,/x = 12/);assert.match(result.formattedMarkdown,/准备删除记录/);
});

test('project dialog stays open on failure and closes only after successful save',async()=>{
  const submit=viewMethod('views/layout/sheets/NewProjectSheet.ets','submit');let close=0;
  const view={name:'数学',color:'',icon:'',saving:false,error:'',onClose:()=>close++,onCreateProject:async()=>false};
  await submit.call(view);assert.equal(close,0);assert.match(view.error,/未能创建/);
  view.onCreateProject=async()=>true;await submit.call(view);assert.equal(close,1);
});
