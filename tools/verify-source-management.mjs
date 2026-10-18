import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { resolveTypeScript } from './resolve-typescript.mjs';

// Standalone checks for startup source repair and Markdown hydration in NoteStorageService.
// PDF/Image services are mocked at their module boundary, so these tests exercise our policy
// and service code without requiring PDF Kit, an image decoder, or a device.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const base = 'entry/src/main/ets/';
const storageFile = `${base}services/NoteStorageService.ets`;

const ts = resolveTypeScript();

function load(relative, mocks, cache = new Map()) {
  const filename = path.resolve(root, relative);
  if (mocks[filename]) { return mocks[filename]; }
  if (cache.has(filename)) { return cache.get(filename); }
  const module = { exports: {} };
  cache.set(filename, module.exports);
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    fileName: filename.replace(/\.ets$/, '.ts'),
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const localRequire = specifier => {
    if (mocks[specifier]) { return mocks[specifier]; }
    if (specifier.startsWith('.')) {
      return load(path.resolve(path.dirname(filename), `${specifier}.ets`), mocks, cache);
    }
    throw Error(`Unmocked dependency: ${specifier}`);
  };
  vm.runInNewContext(output, { module, exports: module.exports, require: localRequire,
    console, Date, Error, Promise, setTimeout, clearTimeout, decodeURIComponent, JSON, Math });
  return module.exports;
}

function platform(options = {}) {
  const files = new Map();
  const directories = new Set(['/sandbox', '/sandbox/notes', '/sandbox/documents']);
  const descriptors = new Map();
  const calls = [];
  const state = {
    validateCalls: [], copyCalls: [], imageImports: [],
    validateFails: options.validateFails === true,
    readerUnavailable: options.readerUnavailable === true,
    pageCount: options.pageCount || 2
  };
  let nextFd = 1;
  let copyCounter = 0;
  const fileOf = input => typeof input === 'number' ? descriptors.get(input) : input;
  const open = async (file, mode) => {
    if (mode & 4) { files.set(file, Buffer.alloc(0)); }
    if (!files.has(file)) { throw Error(`missing file: ${file}`); }
    const fd = nextFd++;
    descriptors.set(fd, file);
    return { fd };
  };
  const close = async input => {
    const fd = typeof input === 'number' ? input : input.fd;
    descriptors.delete(fd);
  };
  const readStats = { active: 0, max: 0 };
  const fileIo = {
    OpenMode: { READ_ONLY: 0, READ_WRITE: 1, WRITE_ONLY: 2, CREATE: 4, TRUNC: 8 },
    access: async file => directories.has(file) || files.has(file),
    mkdir: async directory => { directories.add(directory); },
    open,
    close,
    statSync: input => {
      const file = fileOf(input);
      if (!files.has(file)) { throw Error(`missing file: ${file}`); }
      return { size: files.get(file).length };
    },
    readText: async file => {
      readStats.active++;
      readStats.max = Math.max(readStats.max, readStats.active);
      try {
        const delay = (options.readDelays && options.readDelays[file]) || options.readDelay || 0;
        if (delay > 0) { await new Promise(resolve => setTimeout(resolve, delay)); }
        if (Array.isArray(options.readFails) && options.readFails.includes(file)) {
          throw Error(`simulated read failure: ${file}`);
        }
        if (!files.has(file)) { throw Error(`missing file: ${file}`); }
        return files.get(file).toString('utf8');
      } finally {
        readStats.active--;
      }
    },
    read: async (input, buffer) => {
      const bytes = files.get(fileOf(input));
      if (!bytes) { throw Error(`missing file: ${fileOf(input)}`); }
      const view = new Uint8Array(buffer);
      const length = Math.min(bytes.length, view.length);
      view.set(bytes.subarray(0, length));
      return length;
    },
    write: async (input, content) => {
      const file = fileOf(input);
      const bytes = Buffer.from(content);
      files.set(file, bytes);
      return bytes.length;
    },
    fsync: async () => {},
    rename: async (from, to) => {
      if (!files.has(from)) { throw Error(`missing file: ${from}`); }
      files.set(to, files.get(from));
      files.delete(from);
    },
    unlink: async file => { calls.push(['unlink', file]); files.delete(file); }
  };

  const preferenceMap = new Map();
  const prefs = {
    get: async (key, fallback) => preferenceMap.has(key) ? preferenceMap.get(key) : fallback,
    put: async (key, value) => { preferenceMap.set(key, value); },
    flush: async () => { if (options.flushFails) { throw Error('disk full'); } }
  };

  let pdfInstance = null;
  class MockPdfDocumentService {
    static getInstance() {
      if (pdfInstance === null) { pdfInstance = new MockPdfDocumentService(); }
      return pdfInstance;
    }
    async savePdfToSandbox(context, source, targetName) {
      const bytes = files.get(source);
      if (!bytes) { throw Error(`missing source: ${source}`); }
      const name = targetName.replace(/[\\/:*?"<>|]/g, '_');
      const target = `${context.filesDir}/documents/${Date.now()}_${++copyCounter}_${name}`;
      files.set(target, Buffer.from(bytes));
      state.copyCalls.push([source, target]);
      return target;
    }
    async validateImport(target) {
      state.validateCalls.push(target);
      if (!files.has(target) || files.get(target).length === 0) { throw Error('invalid PDF'); }
      if (state.validateFails) { throw Error('simulated native validation failure'); }
      if (state.readerUnavailable) { throw Error('离线阅读组件未就绪，请重试'); }
      return { pageCount: state.pageCount };
    }
    async removeManagedPdf(context, target) { files.delete(target); }
  }

  const imageService = {
    importFile: async (context, source, name) => {
      const match = /\.(png|jpe?g|webp|bmp|gif)$/i.exec(name);
      if (!match) { throw Error('unsupported image'); }
      const bytes = files.get(source);
      if (!bytes) { throw Error(`missing source: ${source}`); }
      const target = `${context.filesDir}/documents/image_${Date.now()}_${++copyCounter}${match[0].toLowerCase()}`;
      files.set(target, Buffer.from(bytes));
      state.imageImports.push(source);
      return { path: target, info: { width: 1, height: 1, bytes: bytes.length, format: 'PNG' } };
    }
  };

  const mocks = {
    BuildProfile: { default: { DEBUG: false } },
    '@kit.ArkData': { preferences: { getPreferences: async () => prefs } },
    '@kit.CoreFileKit': { fileIo, picker: { DocumentViewPicker: class {}, DocumentSelectOptions: class {},
      DocumentSaveOptions: class {} } },
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return Buffer.from(text); } } } },
    './NoteCoverService': { NoteCoverService: { removeManaged: async () => {} } },
    './document/PdfDocumentService': { PdfDocumentService: MockPdfDocumentService },
    './document/ImageDocumentService': { ImageDocumentService: imageService }
  };
  const Storage = load(storageFile, mocks).NoteStorageService;
  return { files, directories, descriptors, preferences: preferenceMap, calls, state, readStats,
    context: { filesDir: '/sandbox' }, storage: new Storage(), restartStorage: () => new Storage() };
}

const note = changes => ({ id: 'pdf-1', title: '课程原件', category: '课程', type: 'PDF',
  previewText: '', tag: 'PDF', tagColor: '#2563EB', updateTime: '', contentDetail: '# 正文',
  sourceType: 'pdf', sourceUri: '', pageCount: 2,
  pageAnnotations: '{"version":1,"pageCount":2,"pages":{"0":[]}}', ...changes });
const plain = value => JSON.parse(JSON.stringify(value));
const snapshot = p => JSON.parse(p.preferences.get('notes'));

test('note snapshot captures caller data before awaiting Preferences initialization', async () => {
  const p = platform(); p.storage.storageContext = p.context;
  const notes = [note({ id: 'capture', sourceType: 'markdown', title: 'captured', contentDetail: 'body' })];
  const saving = p.storage.save(notes); notes[0].title = 'mutated while awaiting'; notes.push(note({ id: 'late' }));
  await saving; assert.equal(snapshot(p).length, 1); assert.equal(snapshot(p)[0].title, 'captured');
});

test('workspace captures all collections before async initialization and rejects live-trash identity overlap', async () => {
  const p = platform(); let resume, written;
  p.storage.ensureInitialized = () => new Promise(resolve => { resume = resolve; });
  p.storage.repository = { writeMany: async value => { written = value; } };
  const notes = [note({ id: 'a' })], projects = [], trash = [], groups = [];
  const saving = p.storage.saveWorkspace(p.context, notes, projects, trash, groups);
  notes[0].title = 'late title'; trash.push(note({ id: 'other' })); resume(); await saving;
  assert.equal(JSON.parse(written.find(item => item.scope === 'notes').json)[0].title, '课程原件');
  assert.deepEqual(JSON.parse(written.find(item => item.scope === 'trash').json), []);
  await assert.rejects(p.storage.saveWorkspace(p.context, [note({ id: 'same' })], [], [note({ id: 'same' })], []), /身份重复/);
});

test('ambiguous filename identities cannot overwrite a valid library snapshot or hydrate one shared body twice', async () => {
  const p = platform(), original = JSON.stringify([note({ id: 'safe' })]);
  p.preferences.set('notes', original); p.storage.storageContext = p.context;
  await assert.rejects(p.storage.save([note({ id: 'a/b' }), note({ id: 'a:b' })]), /身份重复/);
  assert.equal(p.preferences.get('notes'), original);
  const broken = JSON.stringify([note({ id: 'a/b' }), note({ id: 'a:b' })]); p.preferences.set('notes', broken);
  await assert.rejects(p.restartStorage().load(p.context, [])); assert.equal(p.preferences.get('notes'), broken);
});

function deletionJournal(p) {
  const rows = new Map(); let failCommit = false, failAck = false;
  p.storage.repository = {
    read: async key => rows.get(key) ?? null,
    writeMany: async writes => { if (failCommit) throw Error('transaction failed'); for (const row of writes) rows.set(row.scope, row.json); },
    write: async (key, value) => { if (failAck) throw Error('ack failed'); rows.set(key, value); }, block() {}
  };
  return { rows, failCommit: () => { failCommit = true; }, failAck: value => { failAck = value; } };
}

test('permanent deletion plan and workspace changes commit together before any file is removed', async () => {
  const p = platform(), journal = deletionJournal(p), removed = note({ id: 'gone', sourceUri: '/sandbox/documents/gone.pdf' });
  addMarkdown(p, removed.id); p.files.set(removed.sourceUri, Buffer.from('PDF'));
  await p.storage.saveWorkspace(p.context, [], [], [], [], [removed]);
  assert.ok(p.files.has('/sandbox/notes/gone.md')); assert.ok(p.files.has(removed.sourceUri));
  assert.equal(JSON.parse(journal.rows.get('pending_deletions_v1')).length, 1);
  assert.equal(await p.storage.cleanupPendingDeletions(p.context, []), 0);
  assert.ok(!p.files.has('/sandbox/notes/gone.md')); assert.ok(!p.files.has(removed.sourceUri));
  assert.deepEqual(JSON.parse(journal.rows.get('pending_deletions_v1')), []);
});

test('a rejected workspace deletion transaction leaves all source and body files intact', async () => {
  const p = platform(), journal = deletionJournal(p), removed = note({ id: 'gone', sourceUri: '/sandbox/documents/gone.pdf' });
  addMarkdown(p, removed.id); p.files.set(removed.sourceUri, Buffer.from('PDF')); journal.failCommit();
  await assert.rejects(p.storage.saveWorkspace(p.context, [], [], [], [], [removed]), /transaction failed/);
  assert.ok(p.files.has('/sandbox/notes/gone.md')); assert.ok(p.files.has(removed.sourceUri)); assert.equal(journal.rows.size, 0);
});

test('durable deletion replay survives an acknowledgement failure and protects reused IDs and shared originals', async () => {
  const p = platform(), journal = deletionJournal(p), removed = note({ id: 'reused', sourceUri: '/sandbox/documents/shared.pdf' });
  addMarkdown(p, removed.id, 'new note body'); p.files.set(removed.sourceUri, Buffer.from('PDF'));
  await p.storage.saveWorkspace(p.context, [], [], [], [], [removed]); journal.failAck(true);
  await assert.rejects(p.storage.cleanupPendingDeletions(p.context, [removed]), /ack failed/);
  assert.ok(p.files.has('/sandbox/notes/reused.md')); assert.ok(p.files.has(removed.sourceUri));
  assert.equal(JSON.parse(journal.rows.get('pending_deletions_v1')).length, 1);
  journal.failAck(false); assert.equal(await p.storage.cleanupPendingDeletions(p.context, [removed]), 0);
  assert.ok(p.files.has('/sandbox/notes/reused.md')); assert.ok(p.files.has(removed.sourceUri));
});

test('deletion jobs remain retryable after partial file cleanup and can be replayed idempotently', async () => {
  const p = platform(), journal = deletionJournal(p), removed = note({ id: 'pending', sourceUri: '/sandbox/documents/pending.pdf' });
  addMarkdown(p, removed.id); p.files.set(removed.sourceUri, Buffer.from('PDF'));
  await p.storage.saveWorkspace(p.context, [], [], [], [], [removed]);
  const actualDelete = p.storage.delete.bind(p.storage); let fail = true;
  p.storage.delete = async (...args) => { if (fail) { p.files.delete(removed.sourceUri); throw Error('busy body file'); } return actualDelete(...args); };
  assert.equal(await p.storage.cleanupPendingDeletions(p.context, []), 1);
  assert.ok(!p.files.has(removed.sourceUri)); assert.ok(p.files.has('/sandbox/notes/pending.md'));
  assert.equal(JSON.parse(journal.rows.get('pending_deletions_v1')).length, 1);
  fail = false; assert.equal(await p.storage.cleanupPendingDeletions(p.context, []), 0);
  assert.equal(await p.storage.cleanupPendingDeletions(p.context, []), 0);
});

function addMarkdown(p, id, content = '# 正文') {
  p.files.set(`/sandbox/notes/${id}.md`, Buffer.from(content));
}

test('a readable sourceUri is migrated instead of being replaced by a missing stored filename', async () => {
  const p = platform();
  const legacy = note({ sourceUri: 'file://picked/course.pdf', sourceFileName: 'stale-local.pdf' });
  p.preferences.set('notes', JSON.stringify([legacy]));
  p.files.set(legacy.sourceUri, Buffer.from('PDF'));
  addMarkdown(p, legacy.id);
  const loaded = await p.storage.load(p.context, []);
  assert.notEqual(loaded[0].sourceUri, '/sandbox/documents/stale-local.pdf');
  assert.match(loaded[0].sourceUri, /^\/sandbox\/documents\//);
  assert.equal(loaded[0].pageAnnotations, legacy.pageAnnotations);
  assert.equal(snapshot(p)[0].sourceUri, loaded[0].sourceUri);
  assert.equal(snapshot(p)[0].sourceFileName, loaded[0].sourceUri.split('/').pop());
  assert.ok(p.files.has(legacy.sourceUri));
});

test('an existing managed sourceUri is kept even when the persisted filename points nowhere', async () => {
  const p = platform();
  const current = '/sandbox/documents/current.pdf';
  const saved = note({ sourceUri: current, sourceFileName: 'missing.pdf' });
  p.preferences.set('notes', JSON.stringify([saved]));
  p.files.set(current, Buffer.from('PDF'));
  addMarkdown(p, saved.id);
  const loaded = await p.storage.load(p.context, []);
  assert.equal(loaded[0].sourceUri, current);
  assert.equal(loaded[0].sourceFileName, 'current.pdf');
  assert.equal(loaded[0].pageAnnotations, saved.pageAnnotations);
  assert.equal(p.state.copyCalls.length, 0);
  assert.equal(p.state.validateCalls.length, 0);
  assert.equal(snapshot(p)[0].sourceFileName, 'current.pdf');
});

test('an existing local copy is accepted with a stat check only, never by parsing or rendering it', async () => {
  const p = platform();
  const saved = note();
  const local = '/sandbox/documents/1790000000000_1_course.pdf';
  saved.sourceUri = local;
  saved.sourceFileName = local.split('/').pop();
  p.preferences.set('notes', JSON.stringify([saved]));
  p.files.set(local, Buffer.from('PDF'));
  addMarkdown(p, saved.id);
  const loaded = await p.storage.load(p.context, []);
  assert.equal(loaded[0].sourceUri, local);
  assert.equal(loaded[0].sourceFileName, saved.sourceFileName);
  assert.equal(loaded[0].pageAnnotations, saved.pageAnnotations);
  assert.equal(p.state.validateCalls.length, 0);
  assert.equal(p.state.copyCalls.length, 0);
});

test('an existing saved filename recovers the copy after the sandbox path changes', async () => {
  const p = platform();
  const saved = note({ sourceUri: '/old-sandbox/files/documents/course.pdf', sourceFileName: 'course.pdf' });
  p.preferences.set('notes', JSON.stringify([saved]));
  const current = { filesDir: '/new-sandbox/files' };
  p.files.set('/new-sandbox/files/documents/course.pdf', Buffer.from('PDF'));
  p.files.set('/new-sandbox/files/notes/pdf-1.md', Buffer.from('# 正文'));
  const loaded = await p.storage.load(current, []);
  assert.equal(loaded[0].sourceUri, '/new-sandbox/files/documents/course.pdf');
  assert.equal(loaded[0].sourceFileName, 'course.pdf');
  assert.equal(snapshot(p)[0].sourceUri, loaded[0].sourceUri);
  assert.equal(p.state.validateCalls.length, 0);
});

test('missing sourceType and type are protected, and a note without a document kind is left alone', async () => {
  const p = platform();
  const readable = note({ sourceUri: 'file://picked/course.pdf', sourceType: undefined, type: undefined });
  p.preferences.set('notes', JSON.stringify([readable]));
  p.files.set(readable.sourceUri, Buffer.from('PDF'));
  addMarkdown(p, readable.id);
  const raw = p.preferences.get('notes');
  const loaded = await p.storage.load(p.context, []);
  assert.equal(loaded[0].sourceUri, readable.sourceUri);
  assert.equal(p.state.copyCalls.length, 0);
  assert.equal(p.preferences.get('notes'), raw);
});

test('sourceType can supply the kind when type is missing, and type can supply it when sourceType is missing', async () => {
  const fromSourceType = platform();
  const current = '/sandbox/documents/current.pdf';
  const first = note({ sourceUri: current, sourceFileName: 'current.pdf', sourceType: 'pdf', type: undefined });
  fromSourceType.preferences.set('notes', JSON.stringify([first]));
  fromSourceType.files.set(current, Buffer.from('PDF'));
  addMarkdown(fromSourceType, first.id);
  assert.equal((await fromSourceType.storage.load(fromSourceType.context, []))[0].sourceUri, current);

  const fromType = platform();
  const legacy = note({ sourceUri: 'file://picked/photo.png', sourceFileName: undefined,
    sourceType: undefined, type: 'Image' });
  fromType.preferences.set('notes', JSON.stringify([legacy]));
  fromType.files.set(legacy.sourceUri, Buffer.from('PNG'));
  addMarkdown(fromType, legacy.id);
  const loaded = await fromType.storage.load(fromType.context, []);
  assert.match(loaded[0].sourceUri, /^\/sandbox\/documents\//);
  assert.equal(loaded[0].sourceType, 'image');
  assert.equal(fromType.state.imageImports.length, 1);
});

test('never attaches a different PDF by filename or matching page count', async () => {
  const p = platform();
  const saved = note({ sourceUri: 'file://gone/original.pdf', sourceFileName: 'wanted.pdf', pageCount: 2 });
  p.preferences.set('notes', JSON.stringify([saved]));
  p.files.set('/sandbox/documents/same-name.pdf', Buffer.from('OTHER'));
  p.files.set('/sandbox/documents/another.pdf', Buffer.from('OTHER'));
  addMarkdown(p, saved.id);
  const raw = p.preferences.get('notes');
  const loaded = await p.storage.load(p.context, []);
  assert.equal(loaded[0].sourceUri, saved.sourceUri);
  assert.equal(loaded[0].sourceFileName, saved.sourceFileName);
  assert.equal(p.state.copyCalls.length, 0);
  assert.equal(p.state.validateCalls.length, 0);
  assert.equal(p.preferences.get('notes'), raw);
});

test('a failed legacy validation preserves the original reference, annotations, and no leaked copy', async () => {
  const p = platform({ validateFails: true });
  const legacy = note({ sourceUri: 'file://picked/course.pdf', sourceFileName: 'stale.pdf' });
  p.preferences.set('notes', JSON.stringify([legacy]));
  p.files.set(legacy.sourceUri, Buffer.from('PDF'));
  addMarkdown(p, legacy.id);
  const raw = p.preferences.get('notes');
  const loaded = await p.storage.load(p.context, []);
  assert.equal(loaded[0].sourceUri, legacy.sourceUri);
  assert.equal(loaded[0].pageAnnotations, legacy.pageAnnotations);
  assert.equal(p.preferences.get('notes'), raw);
  assert.equal([...p.files.keys()].filter(file => file.startsWith('/sandbox/documents/')).length, 0);
  assert.equal(p.descriptors.size, 0);
});

test('a readable legacy PDF is still migrated when the reader component is unavailable', async () => {
  const p = platform({ readerUnavailable: true });
  const legacy = note({ sourceUri: 'file://picked/course.pdf', sourceFileName: 'stale.pdf' });
  p.preferences.set('notes', JSON.stringify([legacy]));
  p.files.set(legacy.sourceUri, Buffer.from('%PDF-1.7\n%synthetic'));
  addMarkdown(p, legacy.id);
  const loaded = await p.storage.load(p.context, []);
  assert.match(loaded[0].sourceUri, /^\/sandbox\/documents\//);
  assert.equal(loaded[0].pageAnnotations, legacy.pageAnnotations);
  assert.equal(p.state.validateCalls.length, 1);
  assert.equal(snapshot(p)[0].sourceUri, loaded[0].sourceUri);
});

test('a malformed legacy file is not published when the reader component is unavailable', async () => {
  const p = platform({ readerUnavailable: true });
  const legacy = note({ sourceUri: 'file://picked/course.pdf', sourceFileName: 'stale.pdf' });
  p.preferences.set('notes', JSON.stringify([legacy]));
  p.files.set(legacy.sourceUri, Buffer.from('not a PDF'));
  addMarkdown(p, legacy.id);
  const raw = p.preferences.get('notes');
  const loaded = await p.storage.load(p.context, []);
  assert.equal(loaded[0].sourceUri, legacy.sourceUri);
  assert.equal(loaded[0].pageAnnotations, legacy.pageAnnotations);
  assert.equal(p.preferences.get('notes'), raw);
  assert.equal([...p.files.keys()].filter(file => file.startsWith('/sandbox/documents/')).length, 0);
});

test('a failed snapshot save publishes none of the repaired references and removes new copies', async () => {
  const p = platform({ flushFails: true });
  const legacy = note({ sourceUri: 'file://picked/course.pdf', sourceFileName: 'stale.pdf' });
  p.preferences.set('notes', JSON.stringify([legacy]));
  p.files.set(legacy.sourceUri, Buffer.from('PDF'));
  addMarkdown(p, legacy.id);
  const raw = p.preferences.get('notes');
  await assert.rejects(p.storage.load(p.context, []), /保存/);
  assert.equal(p.preferences.get('notes'), raw);
  assert.equal([...p.files.keys()].filter(file => file.startsWith('/sandbox/documents/')).length, 0);
  assert.ok(p.files.has(legacy.sourceUri));
});

test('Markdown bodies are read with a fixed concurrency cap and hydrated in note order', async () => {
  const p = platform({ readDelay: 12 });
  const notes = [];
  for (let index = 0; index < 8; index++) {
    const saved = note({ id: `note-${index}`, sourceType: undefined, sourceUri: undefined, type: 'markdown' });
    notes.push(saved);
    addMarkdown(p, saved.id, `body-${index}`);
  }
  p.preferences.set('notes', JSON.stringify(notes));
  const loaded = await p.storage.load(p.context, []);
  assert.equal(loaded.map(saved => saved.id).join(','), notes.map(saved => saved.id).join(','));
  for (let index = 0; index < notes.length; index++) {
    assert.equal(loaded[index].contentDetail, `body-${index}`);
  }
  assert.ok(p.readStats.max <= 4, `read concurrency was ${p.readStats.max}`);
  assert.ok(p.readStats.max > 1, 'reads should overlap');
});

test('one unreadable body fails the load instead of becoming an empty note', async () => {
  const p = platform({ readFails: ['/sandbox/notes/bad.md'] });
  const bad = note({ id: 'bad', sourceType: undefined, sourceUri: undefined, type: 'markdown' });
  const good = note({ id: 'good', sourceType: undefined, sourceUri: undefined, type: 'markdown' });
  p.preferences.set('notes', JSON.stringify([good, bad]));
  addMarkdown(p, 'good', 'kept');
  addMarkdown(p, 'bad', 'should not be empty');
  const raw = p.preferences.get('notes');
  await assert.rejects(p.storage.load(p.context, []), /笔记正文读取失败/);
  assert.equal(p.preferences.get('notes'), raw);
});

test('a local image source is never decoded at startup and a stale filename does not redirect it', async () => {
  const p = platform();
  const current = '/sandbox/documents/photo.png';
  const saved = note({ sourceType: 'image', type: 'Image', sourceUri: current, sourceFileName: 'missing.png' });
  p.preferences.set('notes', JSON.stringify([saved]));
  p.files.set(current, Buffer.from('PNG'));
  addMarkdown(p, saved.id);
  const loaded = await p.storage.load(p.context, []);
  assert.equal(loaded[0].sourceUri, current);
  assert.equal(loaded[0].sourceFileName, 'photo.png');
  assert.equal(loaded[0].pageAnnotations, saved.pageAnnotations);
  assert.equal(p.state.imageImports.length, 0);
  assert.equal(snapshot(p)[0].sourceFileName, 'photo.png');
});

test('a readable legacy image URI is migrated once and keeps its annotations', async () => {
  const p = platform();
  const legacy = note({ sourceType: 'image', type: 'Image', sourceUri: 'file://picked/photo.png',
    sourceFileName: undefined });
  p.preferences.set('notes', JSON.stringify([legacy]));
  p.files.set(legacy.sourceUri, Buffer.from('PNG'));
  addMarkdown(p, legacy.id);
  const loaded = await p.storage.load(p.context, []);
  assert.match(loaded[0].sourceUri, /^\/sandbox\/documents\//);
  assert.equal(loaded[0].sourceFileName, loaded[0].sourceUri.split('/').pop());
  assert.equal(loaded[0].pageAnnotations, legacy.pageAnnotations);
  assert.equal(p.state.imageImports.length, 1);
  assert.equal(p.state.validateCalls.length, 0);
  assert.equal(snapshot(p)[0].sourceUri, loaded[0].sourceUri);
});
