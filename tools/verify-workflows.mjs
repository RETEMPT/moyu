import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { resolveTypeScript } from './resolve-typescript.mjs';

// Run ArkTS service and view snapshot logic with platform adapters mocked. HAP compilation
// separately verifies ArkTS types and UI; these tests do not emulate ArkUI.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ts = resolveTypeScript();
const base = 'entry/src/main/ets/';
const parserFile = `${base}services/smart/SourceTextParser.ets`;
const builderFile = `${base}services/smart/SmartNoteBuilder.ets`;
const extractFile = `${base}services/smart/SmartExtractService.ets`;
const ocrFile = `${base}services/ocr/OcrService.ets`;

test('project trees start collapsed and retain explicit session expansion after note changes', () => {
  const { buildSpaces } = load(`${base}services/WorkspaceBuilder.ets`);
  const registered = { id:'course', name:'课程', isOpen:true, notes:[], children:[], count:0 };
  const initial = buildSpaces([{id:'a',category:'课程'},{id:'b',category:'随记'}], [registered], []);
  assert.deepEqual(plain(initial).map(s=>[s.name,s.isOpen,s.count]), [['课程',false,1],['随记',false,1]]);
  initial[0].isOpen=true;
  const updated = buildSpaces([{id:'a',category:'课程'},{id:'c',category:'课程'},{id:'b',category:'随记'}], [registered], initial);
  assert.deepEqual(plain(updated).map(s=>[s.name,s.isOpen,s.count]), [['课程',true,2],['随记',false,1]]);
  assert.equal(initial[0].count,1);assert.equal(registered.isOpen,true);
});

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
    setInterval, clearInterval,
    canIUse: mocks.canIUse || (() => true), AppStorage: mocks.AppStorage,
    SourceTool: mocks.SourceTool, TouchType: mocks.TouchType, Curve: mocks.Curve || { EaseInOut: 'ease' },
    OffscreenCanvas: mocks.OffscreenCanvas, RenderingContextSettings: mocks.RenderingContextSettings }, { filename });
  return module.exports;
}

const { SourceTextParser } = load(parserFile);
const { copyNote } = load(`${base}common/utils/NoteSnapshot.ets`);
const { SmartNoteBuilder } = load(builderFile);
const { SmartCaptureService } = load(`${base}services/smart/SmartCaptureService.ets`);
const { LibraryPolicy } = load(`${base}services/library/LibraryPolicy.ets`);
const { ReadingProgressPolicy } = load(`${base}services/document/ReadingProgressPolicy.ets`);
const { ReaderPairPolicy } = load(`${base}services/document/ReaderPairPolicy.ets`);
const plain = value => JSON.parse(JSON.stringify(value));
const reference = new Date(2026, 8, 30, 10);

test('quick capture preserves Markdown, derives a title and ignores tags inside code and math', () => {
  const {QuickMemoService}=load(`${base}services/library/QuickMemoService.ets`);
  const content='\n# 课堂灵感\n\n试一试 #复习 #复习\n```text\n#不算标签\n```\n';
  const note=QuickMemoService.note({id:'memo_draft1',content},1000);
  assert.equal(note.contentDetail,content);assert.equal(note.title,'课堂灵感');
  assert.deepEqual(plain(note.tags),['复习']);assert.equal(note.category,'随手记');assert.equal(note.type,'Markdown');
  for(const body of ['   ','x'.repeat(12001)])assert.throws(()=>QuickMemoService.note({id:'memo_draft1',content:body},1000));
});

test('quick capture publishes after body and metadata succeed, and retries the same draft without duplication', async () => {
  const {QuickMemoService}=load(`${base}services/library/QuickMemoService.ets`);
  let notes=[];const calls=[];const draft={id:'memo_stable',content:'要记住的原文 #复习'};
  const ports={notes:()=>notes,create:async()=>calls.push('body'),saveNotes:async()=>calls.push('metadata'),
    publish:value=>{calls.push('publish');notes=value;}};
  await QuickMemoService.commit(draft,ports);assert.deepEqual(calls,['body','metadata','publish']);
  await QuickMemoService.commit(draft,ports);assert.equal(notes.length,1);assert.equal(calls.length,3);
  await assert.rejects(QuickMemoService.commit({...draft,content:'不能覆盖已保存笔记'},ports),/已保存/);
});

test('quick capture keeps its draft on metadata failure and never announces success', async () => {
  const {QuickMemoService}=load(`${base}services/library/QuickMemoService.ets`);
  const draft={id:'memo_failure',content:'这段内容要保留'};let published=0;
  await assert.rejects(QuickMemoService.commit(draft,{notes:()=>[],create:async()=>{},saveNotes:async()=>{throw Error('disk');},publish:()=>published++}),/disk/);
  assert.equal(published,0);assert.equal(draft.content,'这段内容要保留');
});



test('timeline selects text documents by creation time and keeps edited older notes in their original order', () => {
  const {MemoFeedPolicy}=load(`${base}services/library/MemoFeedPolicy.ets`);
  const display=viewMethod('views/workspace/HomeWorkspace.ets','displayNotes',{MemoFeedPolicy});
  const view={recentNotes:[studyNote({id:'old',type:'Markdown',createdAt:1,updatedAt:100}),
    studyNote({id:'new',type:'Markdown',createdAt:2,updatedAt:2}),studyNote({id:'pdf',type:'PDF',createdAt:3})],
    activeShelfFilter:'all',viewMode:'timeline',sortKey:'update',sortAsc:false,cachedShelfSource:null};
  assert.deepEqual(plain(display.call(view)).map(n=>n.id),['new','old']);
});

test('library searches complete local bodies, secondary tags and validated PDF page text', () => {
  const body=studyNote({id:'body',contentDetail:'摘要之外的互斥锁原文',tags:['期末','复习'],tag:'旧标签'});
  const pdf=studyNote({id:'pdf',type:'PDF',sourceType:'pdf',pageCount:3,pdfTextJson:JSON.stringify([
    {pageNumber:2,text:'校对后的死锁例题',method:'ocr',extractedAt:1},
    {pageNumber:99,text:'无效页码不参与搜索',method:'ocr',extractedAt:1}])});
  const ids=keyword=>plain(LibraryPolicy.query([body,pdf],{keyword})).map(n=>n.id);
  assert.deepEqual(ids('互斥锁'),['body']);assert.deepEqual(ids('#复习'),['body']);assert.deepEqual(ids('#旧标签'),['body']);
  assert.deepEqual(ids('死锁例题'),['pdf']);assert.deepEqual(ids('无效页码'),[]);
});

test('library combines project, normalized format and reading status without including trash', () => {
  const notes=[studyNote({id:'a',category:'数学',type:'pdf',pageCount:20,lastReadAt:100,readPage:6}),
    studyNote({id:'b',category:'数学',type:'pdf',pageCount:20,lastReadAt:200,readPage:20}),
    studyNote({id:'c',category:'数学',type:'PDF'}),studyNote({id:'trash',category:'数学',type:'PDF',deletedAt:1})];
  for(const [status,expected]of [['reading',['a']],['finished',['b']],['unread',['c']]]){
    assert.deepEqual(plain(LibraryPolicy.query(notes,{category:'数学',type:'PDF',status})).map(n=>n.id),expected);
  }
  assert.deepEqual(plain(LibraryPolicy.query(notes,{category:'物理'})),[]);
});

test('library sorts pinned notes first, orders unpinned false and missing flags, and leaves input untouched', () => {
  const notes=[studyNote({id:'old',updatedAt:1,isPinned:false}),studyNote({id:'new',updatedAt:9}),studyNote({id:'pin',updatedAt:0,isPinned:true})];
  assert.deepEqual(plain(LibraryPolicy.query(notes,{pinnedFirst:true})).map(n=>n.id),['pin','new','old']);
  assert.deepEqual(notes.map(n=>n.id),['old','new','pin']);
  assert.deepEqual(plain(LibraryPolicy.query(notes.map((n,i)=>({...n,lastReadAt:i+1})),{sort:'read'})).map(n=>n.id),['pin','new','old']);
});

test('reading labels never invent history or a percentage for unpaged notes', () => {
  assert.equal(ReadingProgressPolicy.latest([studyNote({updatedAt:999})]),null);
  assert.equal(ReadingProgressPolicy.label(studyNote()),'未打开');
  assert.equal(ReadingProgressPolicy.label(studyNote({lastReadAt:1})),'最近打开');
  assert.equal(ReadingProgressPolicy.page(studyNote({pageCount:12,readPage:100})),12);
  assert.equal(ReadingProgressPolicy.page(studyNote({pageCount:12,readPage:NaN})),1);
  assert.equal(ReadingProgressPolicy.latest([studyNote({id:'edited',updatedAt:900,lastReadAt:1}),studyNote({id:'read',lastReadAt:2})]).id,'read');
});

test('reading commits merge only progress and preserve newer annotations, source, title and edit times', async () => {
  const {ReaderCommitService}=load(`${base}services/document/ReaderCommitService.ets`);
  let notes=[studyNote({id:'a',title:'最新标题',pageCount:40,updatedAt:9,updateTime:'昨天',pageAnnotations:'new ink',sourceUri:'/new.pdf'})];
  let bodies=0;
  const ports={notes:()=>notes,saveDocument:async()=>bodies++,saveNotes:async()=>{},publish:value=>{notes=value;}};
  await new ReaderCommitService().commit(studyNote({id:'a',title:'旧标题',pageCount:999,lastReadAt:20,readPage:300}), 'stale',ports,false,'reading');
  assert.equal(notes[0].title,'最新标题');assert.equal(notes[0].updatedAt,9);assert.equal(notes[0].updateTime,'昨天');
  assert.equal(notes[0].sourceUri,'/new.pdf');assert.equal(notes[0].pageAnnotations,'new ink');assert.equal(notes[0].readPage,40);assert.equal(bodies,0);
});

test('old reading events cannot move progress backwards and failed writes never publish success', async () => {
  const {ReaderCommitService}=load(`${base}services/document/ReaderCommitService.ets`);
  const current=studyNote({id:'a',pageCount:50,lastReadAt:30,readPage:20});let published=0;
  const ports={notes:()=>[current],saveDocument:async()=>{},saveNotes:async value=>{assert.equal(value[0].readPage,20);},publish:()=>published++};
  const writer=new ReaderCommitService();
  await writer.commit(studyNote({id:'a',lastReadAt:10,readPage:2}),'',ports,false,'reading');assert.equal(published,1);
  await assert.rejects(writer.commit(studyNote({id:'a',lastReadAt:20,readPage:3}),'', {...ports,saveNotes:async()=>{throw Error('disk');}},false,'reading'),/disk/);
  assert.equal(published,1);assert.equal(current.readPage,20);
});

test('library view preferences survive service recreation and a failed flush rolls back the cached value', async () => {
  const data=new Map();let fail=false;
  const prefs={get:async(k,f)=>data.has(k)?data.get(k):f,put:async(k,v)=>data.set(k,v),flush:async()=>{if(fail)throw Error('disk');}};
  const {LibraryPreferencesService}=load(`${base}services/library/LibraryPreferencesService.ets`,{'@kit.ArkData':{preferences:{getPreferences:async()=>prefs}}});
  const service=new LibraryPreferencesService();const selected={view:'list',sort:'read',ascending:false};
  await service.save({},selected);assert.deepEqual(plain(await new LibraryPreferencesService().load({})),selected);
  fail=true;await assert.rejects(service.save({},{view:'shelf',sort:'title',ascending:true}));
  fail=false;assert.deepEqual(plain(await service.load({})),selected);
});

test('reading position is retained by backup sanitation but invalid offsets are omitted', () => {
  const {StudyBackupPolicy}=load(`${base}services/study/StudyBackupPolicy.ets`);
  const note=studyNote({pageCount:40,readPage:12,lastReadAt:100});
  assert.equal(StudyBackupPolicy.note(note).readPage,12);assert.equal(StudyBackupPolicy.note(note).lastReadAt,100);
  assert.equal(StudyBackupPolicy.note({...note,readPage:999}).readPage,undefined);
});

test('page changes coalesce and exiting waits for a position write already in flight', async () => {
  const file='views/reader/huawei/HuaweiDocWorkspace.ets',clock=fakeTimers(),calls=[];let release;
  const view={loadedNoteId:'a',lastRecordedPage:0,pendingReadingPage:0,readingTimer:-1,readingWrite:Promise.resolve(),
    readingWritePending:false,isFreeCanvas:false,isHandwritingNote:()=>false,showToast(){},
    onReadingPageChange:async(id,page)=>{calls.push([id,page]);await new Promise(r=>{release=r;});}};
  for(const name of ['rememberReadingPage','flushReadingProgress'])view[name]=viewMethod(file,name,clock);
  view.rememberReadingPage(12);view.rememberReadingPage(13);assert.equal(clock.jobs.size,1);
  clock.fire(600);await new Promise(r=>setImmediate(r));assert.deepEqual(calls,[['a',13]]);
  let completed=false;const exit=view.flushReadingProgress().then(()=>{completed=true;});
  await Promise.resolve();assert.equal(completed,false);release();await exit;assert.equal(completed,true);
});

test('only rows displaying reading position rebuild for page turns', () => {
  const {noteRenderKey,readingRenderKey}=load(`${base}common/utils/ForEachKeys.ets`);
  const a=studyNote({lastReadAt:1,readPage:1}),b={...a,lastReadAt:2,readPage:2};
  assert.equal(noteRenderKey(a),noteRenderKey(b));assert.notEqual(readingRenderKey(a),readingRenderKey(b));
});

test('a read-only tab switch waits for unsaved progress without requiring annotation changes', () => {
  let saves=0,switches=0;
  const view={note:{id:'a'},isAnnotateMode:false,documentDirty:false,scratchpadDirty:false,pendingReadingPage:35,
    readingWritePending:false,exitSaving:false,outputBusy:false,restoreSourceBusy:false,beginReaderSave:()=>saves++,onSelectDocument:()=>switches++};
  viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets','requestDocument').call(view,'b');
  assert.equal(saves,1);assert.equal(switches,0);assert.equal(view.saveDestination,'tab');assert.equal(view.pendingDocumentId,'b');
});

test('delayed progress retains the time of reading rather than the later time of flushing another tab', async () => {
  const file='views/reader/huawei/HuaweiDocWorkspace.ets',clock=fakeTimers();let captured;
  const view={loadedNoteId:'a',lastRecordedPage:0,pendingReadingPage:0,readingTimer:-1,readingWrite:Promise.resolve(),
    isFreeCanvas:false,isHandwritingNote:()=>false,onReadingPageChange:async(...args)=>{captured=args;}};
  view.rememberReadingPage=viewMethod(file,'rememberReadingPage',{...clock,Date:{now:()=>100}});
  view.flushReadingProgress=viewMethod(file,'flushReadingProgress',clock);
  view.rememberReadingPage(35);await view.flushReadingProgress();assert.deepEqual(captured,['a',35,100]);
});

const source = '【美术课通知】\n2026年10月2日前提交素描作业。\n已经完成报名，无需准备额外材料。\n地点：画室二楼。';

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
  assert.equal('entities' in result, false);
  assert.equal('relations' in result, false);
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
  assert.equal(note.contentDetail, SmartNoteBuilder.buildMarkdown(content, []));
});

test('calendar plans use confirmed dates and reject ambiguous deadlines before scheduling', () => {
  const tasks = [ { id: 'a', title: '交作业', deadline: '2026-10-02', priority: 'high' },
    { id: 'b', title: '复习', deadline: '下周五', priority: 'medium' } ];
  assert.throws(() => SmartNoteBuilder.buildTodos(tasks, 'note-1', reference), /日期尚未确认/);
  const todos = SmartNoteBuilder.buildTodos([tasks[0], { ...tasks[1], deadline: '' }], 'note-1', reference);
  assert.equal(todos[0].date, '2026-10-02');
  assert.equal(todos[1].date, '2026-09-30');
  assert.equal(todos[1].title, '复习');
  assert.equal(todos[0].noteRefs[0], 'note-1');
  assert.equal(todos[0].id, SmartNoteBuilder.buildTodos([tasks[0]], 'note-1', reference)[0].id);
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
    '@kit.ArkTS': { taskpool: { execute: async (fn,...args) => fn(...args) }, util: {} },
    '@kit.PDFKit': { pdfService: { PdfDocument, PdfMatrix, ParseResult: { PARSE_SUCCESS: 0, PARSE_ERROR_PASSWORD: 3 } } },
    [path.resolve(root, `${base}services/ocr/OcrService.ets`)]: { OcrService: { getInstance: () => ({ recognizePixelMap: async () => {
      calls.push('ocr'); if (ocrFails) throw Error('ocr'); return '扫描页真实文字';
    } }) } },
    '@kit.CoreFileKit': { fileIo: { OpenMode: { READ_ONLY: 0 }, accessSync: () => true,
      statSync: () => ({ size: 8000 }), stat: async () => ({ size: 8000 }), openSync: () => ({ fd: 1 }), closeSync: () => calls.push('file-close'),
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

test('PDF rendering uses real page dimensions and returns bitmap ownership to caller', async () => {
  const { service, calls, bitmap } = pdfService();
  const page = await service.renderPageAsync('/sandbox/source.pdf', 1);
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

test('PDF out-of-range page and render error release acquired native resources', async () => {
  const invalid = pdfService();
  await assert.rejects(invalid.service.renderPageAsync('/sandbox/source.pdf', 3), /页码/);
  assert.equal(invalid.calls.at(-1), 'document-release');
  const broken = pdfService({ renderFails: true });
  await assert.rejects(broken.service.renderPageAsync('/sandbox/source.pdf', 0));
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
    '@kit.ImageKit': { image: {} },
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return text.length ? Buffer.from(text) : undefined; } } } },
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
        removeManagedPdf: async (context, file) => { calls.push(['unlink', file]); },
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

test('ordinary Markdown preserves formulas and tables and response JSON is not a document import format', async () => {
  const text = '# 课程\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n$$x^2+y^2=1$$';
  const success = importService('', { textContent: text });
  const result = await success.service.importDocumentUri({ filesDir: '/sandbox' }, 'file://picked/course.md');
  assert.equal(result.status, 'imported'); assert.equal(result.document.content, text); assert.equal(result.document.title, 'course');
  assert.ok(success.calls.some(call => Array.isArray(call) && call[0] === 'write' && call[1] === text));
  const invalid = importService('', { textContent: '{"output":"not a document"}' });
  assert.equal((await invalid.service.importDocumentUri({ filesDir: '/sandbox' }, 'file://picked/result.json')).status, 'unsupported');
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
  // The reviewed range is read in one native batch, so cancellation takes effect before the
  // next page is published rather than between per-page parses.
  assert.equal(f.calls.filter(c => c === 'page-release').length, 3);
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
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText, { module, JSON, copyNote });
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
const { LearningProgressPolicy } = load(`${base}services/study/LearningProgressPolicy.ets`);
const { LearningResultPolicy } = load(`${base}services/study/LearningResultPolicy.ets`);
const exchangeFixture = JSON.parse(fs.readFileSync(path.join(root, 'tools/fixtures/learning-result.json'), 'utf8'));
for (const scenario of exchangeFixture.cases) {
  test(`offline learning result contract: ${scenario.name}`, () => {
    const value = structuredClone(exchangeFixture.result);
    for (const [key, replacement] of scenario.changes) {
      const parts = key.split('.'); let current = value;
      for (const part of parts.slice(0, -1)) current = current[part];
      current[parts.at(-1)] = replacement;
    }
    if (scenario.valid) assert.deepEqual(plain(LearningResultPolicy.parse(JSON.stringify(value))), value);
    else assert.throws(() => LearningResultPolicy.parse(JSON.stringify(value)));
  });
}

test('offline result enforces byte, UTF-16 and duplicate source bounds', () => {
  const value = structuredClone(exchangeFixture.result);
  value.title = '🧭'.repeat(100);
  LearningResultPolicy.parse(JSON.stringify(value));
  value.title += '🧭';
  assert.throws(() => LearningResultPolicy.parse(JSON.stringify(value)));
  assert.throws(() => LearningResultPolicy.parse(' '.repeat(131073)));
  assert.throws(() => LearningResultPolicy.parse('中'.repeat(50000)));
  const duplicate = structuredClone(exchangeFixture.result);
  duplicate.sources.push(duplicate.sources[0]);
  assert.throws(() => LearningResultPolicy.parse(JSON.stringify(duplicate)));
});

test('offline card candidate requires exact live fragment and keeps local identity and scheduling unset', () => {
  const value = structuredClone(exchangeFixture.result), raw = JSON.stringify(value);
  const draft = LearningResultPolicy.cardDraft(raw, 0, 'source1', value.sources[0].text);
  assert.deepEqual(plain(draft), { question: value.cards[0].question, answer: value.cards[0].answer,
    sourceText: value.cards[0].citations[0].quote });
  for (const index of [-1, 0.5, 1]) assert.throws(() => LearningResultPolicy.cardDraft(raw, index, 'source1', value.sources[0].text));
  assert.throws(() => LearningResultPolicy.cardDraft(raw, 0, 'missing', value.sources[0].text));
  assert.throws(() => LearningResultPolicy.cardDraft(raw, 0, 'source1', value.sources[0].text + '已修订'));
  value.sources.push({ ...value.sources[0], id: 'source2' });
  value.cards[0].citations.push({ ...value.cards[0].citations[0], source_id: 'source2' });
  assert.throws(() => LearningResultPolicy.cardDraft(JSON.stringify(value), 0, 'source1', value.sources[0].text));
});
test('local learning overview follows live course membership and separates self-ratings from reading', () => {
  const notes = [studyNote({id:'a',category:'数学',lastReadAt:100,pageCount:20,readPage:20}),
    studyNote({id:'b',category:'数学'}),studyNote({id:'other',category:'物理'}),studyNote({id:'trash',category:'数学',deletedAt:1})];
  const make=(id,noteId,extra={})=>({...ReviewPolicy.create(notes[0],{question:'Q',answer:'A',sourceText:''},1),id,noteId,course:'旧分类',...extra});
  const cards=[make('new','a'),make('weak','a',{lastRating:'again',reviewCount:2,dueAt:20}),
    make('good','b',{lastRating:'good',reviewCount:3,lapses:2}),make('future','b',{lastRating:'hard',reviewCount:1,dueAt:99}),
    make('other','other'),make('trash','trash'),make('missing','missing')];
  const before=JSON.stringify({notes,cards});
  const overview=LearningProgressPolicy.overview(notes,cards,'数学',50);
  assert.equal(overview.noteCount,2);assert.equal(overview.openedCount,1);assert.equal(overview.cardCount,4);
  assert.equal(overview.newCount,1);assert.equal(overview.weakCount,2);assert.equal(overview.goodCount,1);
  assert.equal(overview.dueCount,3);assert.equal(overview.weakDueCount,1);
  assert.equal(overview.materials[0].readingLabel,'第 20 / 20 页');
  assert.equal(overview.materials[0].course,'数学');
  assert.match(LearningProgressPolicy.suggestion(overview),/3 道到期题卡/);
  assert.equal(JSON.stringify({notes,cards}),before);
});
test('local review queue prioritizes due weak cards and never brings forward future reviews', () => {
  const note=studyNote();const baseCard=ReviewPolicy.create(note,{question:'Q',answer:'A',sourceText:''},1);
  const cards=[{...baseCard,id:'old',dueAt:1},{...baseCard,id:'weakB',lastRating:'hard',dueAt:20},
    {...baseCard,id:'weakA',lastRating:'again',dueAt:20},{...baseCard,id:'future',lastRating:'again',dueAt:100}];
  assert.deepEqual(plain(LearningProgressPolicy.queue([note],cards,'',50)).map(c=>c.id),['weakA','weakB','old']);
  assert.deepEqual(plain(LearningProgressPolicy.queue([note],cards,'',50,true)).map(c=>c.id),['weakA','weakB']);
  assert.deepEqual(plain(LearningProgressPolicy.queue([note],cards,'另一个课程',50)),[]);
  assert.match(LearningProgressPolicy.suggestion(LearningProgressPolicy.overview([note],[], '',50)),/手动建立题卡/);
});
test('editing a local card preserves its identity, source, feedback and scheduled review', () => {
  const note=studyNote();const card={...ReviewPolicy.create(note,{question:'Q',answer:'A',sourceText:'原文',pageNumber:3},1),
    lastRating:'hard',reviewCount:3,intervalDays:7,dueAt:100,lapses:2};
  const updated=ReviewPolicy.edit(card,{question:'新问题',answer:'新答案',sourceText:'校对原文'},200);
  for(const key of ['id','noteId','course','pageNumber','dueAt','intervalDays','reviewCount','repetitions','lastRating','lapses','createdAt'])assert.equal(updated[key],card[key],key);
  assert.equal(updated.question,'新问题');assert.equal(updated.updatedAt,200);assert.equal(card.question,'Q');
  assert.throws(()=>ReviewPolicy.edit(card,{question:'',answer:'A',sourceText:''},200));
});
test('local card editor keeps the draft when persistence fails and clears it only after a successful save', async () => {
  const card=ReviewPolicy.create(studyNote(),{question:'旧问题',answer:'旧答案',sourceText:''},1);
  let fail=true, saved;
  const view={busy:false,alive:true,editingId:card.id,question:'修正问题',answer:'修正答案',sourceText:'原文',cards:[card],
    status:'',reveal:true,selectedNote:()=>studyNote(),activeCards:()=>[card],
    onSave:async next=>{if(fail)throw Error('disk');saved=next;},switchTab(tab){this.tab=tab;},
    cancelEdit(){this.editingId='';this.question='';this.answer='';this.sourceText='';}};
  view.commit=viewMethod('views/study/StudySheet.ets','commit');
  const save=viewMethod('views/study/StudySheet.ets','manual',{ReviewPolicy});
  await save.call(view);assert.equal(view.question,'修正问题');assert.equal(view.editingId,card.id);assert.equal(view.busy,false);
  assert.match(view.status,/保存失败/);assert.equal(saved,undefined);
  fail=false;await save.call(view);assert.equal(saved[0].question,'修正问题');assert.equal(saved[0].reviewCount,card.reviewCount);
  assert.equal(view.editingId,'');assert.equal(view.question,'');assert.equal(view.tab,0);
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

function backupFileFixture({ selected = ['/picked/backup.json'], failPdf = false, failImage = false, shortRead = false, failWrite = false } = {}) {
  const files = new Map(); const opened = new Map(); const calls = []; let fd = 0;
  const mocks = {
    '@kit.AbilityKit': {},
    '@kit.CoreFileKit': { picker: { DocumentSelectOptions: class {}, DocumentSaveOptions: class {}, DocumentViewPicker: class {
      async select() { return selected; } async save() { return selected; }
    } }, fileIo: { OpenMode: { READ_ONLY: 0, WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 },
      accessSync: () => true, mkdirSync: () => {},
      access: async () => true, mkdir: async () => {}, listFile: async dir => [...files.keys()].filter(p => p.startsWith(dir+'/')).map(p => p.slice(dir.length+1)),
      open: async (filename, mode) => { opened.set(++fd, filename); if(mode & 4)files.delete(filename); return { fd }; },
      close: async file => { calls.push(['close', file.fd]); },
      statSync: descriptor => ({ size: files.get(typeof descriptor === 'number' ? opened.get(descriptor) : descriptor)?.length ?? 0 }),
      read: async (descriptor, buffer) => { const bytes = files.get(opened.get(descriptor)); new Uint8Array(buffer).set(bytes); return bytes.length - (shortRead ? 1 : 0); },
      write: async (descriptor, value) => { if (failWrite) throw Error('disk full'); const bytes = Buffer.from(value); const p=opened.get(descriptor); files.set(p, Buffer.concat([files.get(p)||Buffer.alloc(0), bytes])); calls.push(['write',bytes.length]); return bytes.length; },
      fsync: async descriptor => calls.push(['flush', descriptor]),
      unlink: async filename => { files.delete(filename); calls.push(['unlink', filename]); }
    } },
    '@kit.ArkTS': { taskpool: { execute: async (fn,...args) => { calls.push(['worker',fn.name]); return fn(...args); } }, util: { Base64Helper: class {
      async encodeToString(bytes) { return Buffer.from(bytes).toString('base64'); }
      async decode(value) { return Buffer.from(value, 'base64'); }
      decodeSync(value) { return Buffer.from(value, 'base64'); } // Deliberately returns a pooled view with a nonzero byteOffset.
    }, TextEncoder: class { encodeInto(text) { return Buffer.from(text); } },
    TextDecoder: class { decodeToString(bytes) { return Buffer.from(bytes).toString('utf8'); } } } },
    '@kit.ImageKit': { image: { createImageSource: filename => ({ getImageInfo: async () => {
      if (failImage) throw Error('broken image'); return { size: { width: 1, height: 1 }, mimeType:'image/png' };
    }, createPixelMap:async()=>({release:async()=>calls.push('preview-release')}), release: async () => calls.push(['image-release', filename]) }) } },
    [path.resolve(root, `${base}services/document/PdfDocumentService.ets`)]: { PdfDocumentService: { getInstance: () => ({
      validateImport: async filename => { if (failPdf) throw Error('broken pdf'); return { pageCount: 2 }; }
    }) } }
  };
  const { StudyBackupService } = load(`${base}services/study/StudyBackupService.ets`, mocks);
  return { service: StudyBackupService, files, calls };
}



test('bundled sample backups remain labeled examples and do not block an initial full backup', async () => {
  const f = backupFileFixture();
  const example = studyNote({ id: 'note-seed-pdf', title: '旧版阅读示例', type: 'Doc', sourceType: 'pdf', pageCount: 9,
    contentDetail: '# 阅读示例', pageAnnotations: '{"pages":[]}' });
  assert.equal(await f.service.exportFile({ filesDir: '/sandbox' }, [example], []), true);
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



function atomicFixture({ shortWrite = false, syncFails = false } = {}) {
  const files = new Map([['/note.md', 'last valid']]); const calls = []; const opened = new Map(); let fd = 0;
  const { AtomicTextFile } = load(`${base}services/storage/AtomicTextFile.ets`, {
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return text.length ? Buffer.from(text) : undefined; } } } },
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

test('empty whiteboard body is created atomically without passing an empty buffer to the native writer', async () => {
  const f=atomicFixture();await new f.AtomicTextFile().write('/note.md','');
  assert.equal(f.files.get('/note.md'),'');assert.equal(f.files.size,1);
  assert.deepEqual(f.calls.map(call=>call[0]),['rename']);
  const failed=atomicFixture({syncFails:true});await assert.rejects(new failed.AtomicTextFile().write('/note.md',''));
  assert.equal(failed.files.get('/note.md'),'last valid');
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

test('shared study import resumes a partial batch and maps cards to stable restored IDs', async () => {
  let notes = []; const cards = []; let fail = true; let materializations = 0;
  const { StudyImportService } = load(`${base}services/study/StudyImportService.ets`, {
    [path.resolve(root, `${base}services/study/StudyBackupService.ets`)]: { StudyBackupService: {
      validate: async input => StudyBackupPolicy.validate(input),
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
    [path.resolve(root, `${base}services/study/StudyBackupService.ets`)]: { StudyBackupService: {
      validate: async input => StudyBackupPolicy.validate(input), materialize: async () => { calls++; } } }
  });
  await assert.rejects(StudyImportService.restore({}, { ...studyBackup(), schemaVersion: 99 }, {
    notes: () => [], commit: async () => { calls++; }, progress: () => {} })); assert.equal(calls, 0);
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

test('reader index failure restores the committed body and a later retry still succeeds', async () => {
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  const service = new ReaderCommitService(); let notes = [studyNote({ contentDetail: 'committed' })], body = 'committed', fail = true;
  const writes = [], ports = { notes: () => notes, saveDocument: async (_, text) => { body = text; writes.push(text); },
    saveNotes: async () => { if (fail) throw Error('index unavailable'); }, publish: next => { notes = next; } };
  await assert.rejects(service.commit(notes[0], 'unsaved input', ports, true), /index unavailable/);
  assert.equal(body, 'committed'); assert.equal(notes[0].contentDetail, 'committed'); assert.deepEqual(writes, ['unsaved input', 'committed']);
  fail = false; await service.commit(notes[0], 'retry input', ports, true); assert.equal(body, 'retry input'); assert.equal(notes[0].contentDetail, 'retry input');
});

test('reader rollback failure is explicit and publication errors never roll back a committed document', async () => {
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  const note = studyNote({ contentDetail: 'old' }); let body = 'old', writes = 0;
  const ports = { notes: () => [note], saveDocument: async (_, text) => { if (++writes === 2) throw Error('disk'); body = text; },
    saveNotes: async () => { throw Error('index'); }, publish: () => { throw Error('must not publish'); } };
  await assert.rejects(new ReaderCommitService().commit(note, 'pending', ports, true), /正文回退未完成/); assert.equal(body, 'pending');
  writes = 0; ports.saveNotes = async () => {}; ports.publish = () => { throw Error('view unavailable'); };
  await assert.rejects(new ReaderCommitService().commit(note, 'committed', ports, true), /view unavailable/);
  assert.equal(body, 'committed'); assert.equal(writes, 1);
});

test('reader field policy is deterministic and rejects unknown kinds before touching storage', async () => {
  const { ReaderCommitPolicy } = load(`${base}services/document/ReaderCommitPolicy.ets`);
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  const current = studyNote({ updatedAt: 1, tags: ['live'], favorite: true }), input = { ...current, favorite: false, contentDetail: 'changed' };
  const before = plain(current), incoming = plain(input);
  assert.deepEqual(plain(ReaderCommitPolicy.merge(current, input, 'markdown', 123)), plain(ReaderCommitPolicy.merge(current, input, 'markdown', 123)));
  assert.deepEqual(plain(current), before); assert.deepEqual(plain(input), incoming);
  let writes = 0; await assert.rejects(new ReaderCommitService().commit(input, 'changed', { notes: () => [current],
    saveDocument: async () => writes++, saveNotes: async () => writes++, publish: () => writes++ }, true, 'misspelled'), /不支持/);
  assert.equal(writes, 0);
});

test('note identities reject duplicate IDs and colliding legacy filenames without changing safe IDs', () => {
  const { NoteIdentity } = load(`${base}services/storage/NoteIdentity.ets`);
  assert.equal(NoteIdentity.fileName('note-a_123'), 'note-a_123');
  for (const notes of [[studyNote(), studyNote()], [studyNote({ id: 'a/b' }), studyNote({ id: 'a:b' })],
    [studyNote({ id: '' })], [studyNote({ id: 'a'.repeat(252) })], [null]]) {
    assert.equal(NoteIdentity.validNotes(notes), false); assert.throws(() => NoteIdentity.requireNotes(notes), /阻止覆盖/);
  }
  assert.equal(NoteIdentity.validNotes([studyNote({ id: 'a' }), studyNote({ id: 'b' })]), true);
});

test('permanent deletion and empty-trash actions never remove files before their workspace transaction succeeds', async () => {
  for (const method of ['purgeNote', 'emptyTrash']) for (const fail of [false, true]) {
    const calls = [], removed = studyNote({ id: 'removed', deletedAt: 1 });
    const view = { notes: [], customProjects: [], trash: [removed], trashedProjects: [], confirmDestructive: async () => true,
      noteMutationQueue: { run: action => action() }, getAbilityContext: () => ({}), notify() {},
      commitWorkspace: async (next, pending) => { calls.push('commit'); assert.equal(pending[0].id, 'removed');
        if (fail) throw Error('commit failed'); view.trash = next.trash; },
      storage: { delete: async () => { throw Error('must use journal'); }, cleanupPendingDeletions: async () => { calls.push('cleanup'); return 0; } } };
    await viewMethod('pages/Index.ets', method).call(view, removed);
    assert.deepEqual(calls, fail ? ['commit'] : ['commit', 'cleanup']);
    assert.equal(view.trash.length, fail ? 1 : 0);
  }
});

test('trash expiry keeps invalid deletion timestamps and preserves valid records when deferred cleanup fails', async () => {
  const expired = studyNote({ id: 'expired', deletedAt: Date.now() - 31 * 86400000 });
  const retained = studyNote({ id: 'retained', deletedAt: 0 }); const calls = [];
  const view = { notes: [], customProjects: [], trash: [], trashedProjects: [], notify() {}, storage: {
    loadTrash: async () => [expired, retained], loadTrashedProjects: async () => [],
    saveWorkspace: async (_, notes, projects, trash, groups, pending) => { calls.push('commit'); assert.deepEqual(plain(pending), [expired]); assert.deepEqual(plain(trash), [retained]); },
    cleanupPendingDeletions: async () => { calls.push('cleanup'); throw Error('temporarily unavailable'); },
    delete: async () => { throw Error('must not remove files before the transaction'); }
  } };
  await viewMethod('pages/Index.ets', 'loadTrash', { TRASH_RETENTION_DAYS: 30 }).call(view, {});
  assert.deepEqual(calls, ['commit', 'cleanup']); assert.deepEqual(Array.from(view.trash), [retained]);
});


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
  const context={module:{exports:{}},console,CATEGORY_UNFILED:'未分类',NAV_LIBRARY:'资料库',FILTER_ALL:'全部',SAVE_IDLE:'已保存',SAVE_SAVING:'保存中',SAVE_FAILED:'保存失败',ReaderPairPolicy,getContext:()=>({}),clearTimeout,setTimeout,InkShapePolicy,copyNote,...globals};vm.runInNewContext(output,context);return context.module.exports;
}
test('actual note creation preserves the requested type, awaits both writes and keeps failures reviewable', async () => {
  const create=viewMethod('pages/Index.ets','createNote');let release;const calls=[];
  const original=studyNote({id:'original'});
  const view={notes:[original],noteCreateBusy:false,noteMutationQueue:{run:fn=>fn()},noteCreateError:'',activeSpaceName:()=>'',formatTime:()=>'',
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
  const view={pageStrokes:{0:[]},undoStack:[],redoStack:[],eraseBefore:null,erasePage:-1,eraserWidth:20,currentPageIdx:0,scheduleSave:()=>saved++,activeInputFinisher:null,activeInputPage:-1,annotationRevision:0};
  for(const method of ['remember','handleStrokeAdded','beginErase','finishErase','handleEraseAtPoint','handleUndo','onRedoTriggered','onClearTriggered','finishActiveInput'])
    view[method]=viewMethod(relative,method,{InkRenderer, CanvasStrokeEraser});
  return {view,saved:()=>saved};
}

const { CanvasStrokeEraser } = load(`${base}services/ink/CanvasStrokeEraser.ets`);
const { InkToolPolicy } = load(`${base}services/ink/InkToolPolicy.ets`);
const { InkShapePolicy } = load(`${base}services/ink/InkShapePolicy.ets`);

test('shape paths survive existing ink validation and stroke erase at reversed and negative coordinates', () => {
  const { CanvasStrokePolicy } = load(`${base}services/ink/CanvasStrokePolicy.ets`);
  for (const tool of ['line', 'rectangle', 'ellipse', 'arrow']) {
    const points = InkShapePolicy.points(tool, { x: 180, y: 150 }, { x: -80, y: -50 });
    assert.ok(points.length >= 2 && points.length <= 65);
    const stroke = { points, color: '#2563EB', width: 3, referenceWidth: 1200, isHighlighter: false, isEraser: false };
    const restored = CanvasStrokePolicy.parse(JSON.stringify([stroke]));
    assert.deepEqual(plain(restored[0].points), plain(points));
    assert.ok(CanvasStrokeEraser.hit(restored[0], points[0], points[0], 2));
  }
  assert.equal(InkShapePolicy.points('line', {x:0,y:0}, {x:0,y:0}).length, 0);
  assert.equal(InkShapePolicy.points('arrow', {x:NaN,y:0}, {x:10,y:10}).length, 0);
});

test('PDF shape gestures preview without committing, create one undo step and discard cancelled geometry', () => {
  const h = pdfHistoryView(), batches = [], committed = [];
  const touch = viewMethod('views/reader/pdf/PdfPageCanvas.ets', 'handleTouch', { InkRenderer, ...penEnums });
  const finish = viewMethod('views/reader/pdf/PdfPageCanvas.ets', 'finishInput');
  const v = { sourceReady:true,isAnnotateMode:true,tool:'rectangle',pageWidth:720,pageHeight:1000,pageModel:{pageIndex:0},
    selectedColor:'#2563EB',selectedWidth:3,fingerDrawing:true,shapeAnchor:null,currentStroke:null,
    liveContext:{clearRect(){}},input:{read:()=>batches.shift(),reset(){},isActive:()=>false},
    onActiveFinisherChange(){},onPenActive(){},onInkContactChange(){},renderStroke(){},
    onStrokeAdded:stroke=>{committed.push(stroke);h.view.handleStrokeAdded(stroke);},
    finishInput:finish,resetInput(){this.finishInput(false);} };
  const e = {sourceTool:1,type:0,stopPropagation(){}};
  batches.push({phase:'begin',pen:false,samples:[{x:72,y:100}]}); touch.call(v,e);
  batches.push({phase:'move',samples:[{x:360,y:500}]}); touch.call(v,e);
  assert.equal(committed.length,0);assert.equal(v.currentStroke.points.length,10);
  batches.push({phase:'end',samples:[{x:360,y:500}]});touch.call(v,e);
  assert.equal(committed.length,1);assert.equal(h.view.undoStack.length,1);
  assert.ok(committed[0].points.every(p=>p.u>=0&&p.u<=1&&p.v>=0&&p.v<=1));
  h.view.handleUndo();assert.equal(h.view.pageStrokes[0].length,0);
  batches.push({phase:'begin',samples:[{x:0,y:0}]});touch.call(v,e);
  batches.push({phase:'cancel',samples:[]});touch.call(v,e);
  assert.equal(committed.length,1);assert.equal(v.shapeAnchor,null);
});

test('paper settings persist separately for the document and scratchpad through concurrent saves and backup', async () => {
  const { ReaderCommitService } = load(`${base}services/document/ReaderCommitService.ets`);
  let notes = [studyNote({type:'Handwriting',strokes:'[]',scratchpadStrokes:'[]',paperStyle:'blank',scratchpadPaperStyle:'grid'})];
  const stale = plain(notes[0]); const service = new ReaderCommitService();
  const ports={notes:()=>notes,saveNotes:async()=>{},saveDocument:async()=>{},publish:next=>{notes=next;}};
  await service.commit({...stale,paperStyle:'ruled'},stale.contentDetail,ports,false,'handwriting');
  await service.commit({...stale,scratchpadPaperStyle:'blank'},stale.contentDetail,ports,false,'scratchpad');
  const restored=StudyBackupPolicy.note(notes[0]);
  assert.equal(restored.paperStyle,'ruled');assert.equal(restored.scratchpadPaperStyle,'blank');
  assert.equal(StudyBackupPolicy.note({...notes[0],paperStyle:'invalid'}).paperStyle,undefined);
});

test('read-only view reset changes only viewport, while paper editing requires an unlocked healthy canvas', () => {
  const command=viewMethod('views/reader/HandwritingCanvas.ets','handleToolCommand', { CanvasViewport });
  const v={toolCommand:{sequence:1,target:'document',action:'resetView'},isScratchpad:false,readOnly:true,loadError:'',
    canvasWidth:600,panX:600,panY:-500,zoomScale:4,finishStroke(){},requestRedraw(){},paperBackground:'blank'};
  command.call(v);assert.equal(v.panX,0);assert.equal(v.panY,0);assert.equal(v.zoomScale,.5);
  v.toolCommand={sequence:2,target:'document',action:'paper',value:'ruled'};command.call(v);assert.equal(v.paperBackground,'blank');
  v.readOnly=false;v.shortcuts={claim(){}};let saves=0;v.scheduleSave=()=>saves++;v.emitToolState=()=>{};
  command.call(v);assert.equal(v.paperBackground,'ruled');assert.equal(saves,1);
});

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

test('PDF nested page-array writes bump the redraw revision', () => {
  const { view: v } = pdfHistoryView();
  const stroke = { id: 'a', pageIndex: 0, color: '#111', width: 2, points: [{ u: 0.1, v: 0.5 }, { u: 0.9, v: 0.5 }] };
  const before = v.annotationRevision;
  v.handleStrokeAdded(stroke); assert.ok(v.annotationRevision > before);
  v.pageStrokes[0] = [stroke]; v.eraseBefore = [stroke]; v.erasePage = 0; v.eraserWidth = 64;
  const erased = v.annotationRevision;
  v.handleEraseAtPoint(0, 0.5, 0.5, 720, 1000);
  assert.ok(v.annotationRevision > erased);
  v.finishErase(true);
  const undone = v.annotationRevision; v.handleUndo(); assert.ok(v.annotationRevision > undone);
});

test('new note creation persists independent project destination and topic tags', async () => {
  const create = viewMethod('pages/Index.ets', 'createNote'); let saved;
  const v = { notes: [], noteCreateBusy: false,noteMutationQueue:{run:fn=>fn()}, activeSpaceName: () => '', formatTime: () => '', notify() {},
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
const { TextImportPolicy } = load(`${base}services/smart/TextImportPolicy.ets`);
test('plain text imports preserve formulas and tables, normalize newlines and reject empty or oversized input', () => {
  const markdown = '# 课程\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n$$x^2+y^2=1$$';
  assert.equal(TextImportPolicy.parse(markdown), markdown);
  assert.equal(TextImportPolicy.parse('\uFEFF# 课程\r\n正文'), '# 课程\n正文');
  assert.throws(() => TextImportPolicy.parse(' \n '), /没有可导入/);
  assert.throws(() => TextImportPolicy.parse('x'.repeat(12001)), /分段/);
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

test('free canvas never adopts a handwriting note, another canvas or a matching display title', async () => {
  const originals=[studyNote({id:'note-seed-handwriting',type:'Handwriting',strokes:'original ink'}),
    studyNote({id:'ordinary-canvas',type:'canvas',title:'自由白板演算',strokes:'another ink'})];
  let created,saved,opened;const view={notes:originals,trash:[],activeNav:'首页',activeNoteId:'',freeCanvasOpening:false,noteMutationQueue:{run:fn=>fn()},
    getAbilityContext:()=>({}),storage:{create:async(_,n)=>{created=n;},save:async ns=>{saved=ns;}},
    rebuildSpaces(){},refreshGraph(){},openNote:n=>{opened=n;},notify(){throw Error('unexpected failure');}};
  await viewMethod('pages/Index.ets','openFreeCanvas',{WorkspaceNotePolicy}).call(view);
  assert.equal(created.id,'canvas-global');assert.equal(created.strokes,'[]');assert.equal(saved[0],created);
  assert.equal(opened,created);assert.deepEqual(originals.map(n=>n.strokes),['original ink','another ink']);
});

test('free canvas reopens its own saved ink and leaves ordinary documents untouched', async () => {
  const board=studyNote({id:'canvas-global',type:'canvas',strokes:'saved board'});let opened;
  const view={notes:[studyNote({id:'note-seed-handwriting',type:'Handwriting'}),board],activeNav:'首页',activeNoteId:'',noteMutationQueue:{run:fn=>fn()},
    openNote:n=>{opened=n;},notify(){throw Error('unexpected failure');}};
  await viewMethod('pages/Index.ets','openFreeCanvas',{WorkspaceNotePolicy}).call(view);assert.equal(opened,board);
  assert.equal(board.strokes,'saved board');
  const next=WorkspaceNotePolicy.createFreeCanvas(['canvas-global'],100);assert.notEqual(next.id,board.id);
  assert.equal(WorkspaceNotePolicy.isFreeCanvas(next),true);
});

test('free canvas waits for persistence, ignores duplicate taps and does not open after leaving the page', async () => {
  let finish, writes=0, opened=0;const notes=[];const view={notes,trash:[],activeNav:'首页',activeNoteId:'',noteMutationQueue:{run:fn=>fn()},
    getAbilityContext:()=>({}),storage:{create:async()=>{},save:()=>{writes++;return new Promise(r=>{finish=r;});}},
    rebuildSpaces(){},refreshGraph(){},openNote(){opened++;},notify(){}};
  const open=viewMethod('pages/Index.ets','openFreeCanvas',{WorkspaceNotePolicy});const pending=open.call(view);
  await new Promise(r=>setTimeout(r,0));await open.call(view);assert.equal(writes,1);assert.equal(view.notes,notes);
  view.activeNav='设置';finish();await pending;assert.equal(view.notes.length,1);assert.equal(opened,0);
});

test('failed free canvas persistence publishes no blank replacement and keeps existing notes', async () => {
  const notes=[studyNote({id:'note-seed-handwriting',type:'Handwriting'})],messages=[];let opened=0;
  const view={notes,trash:[],activeNav:'首页',activeNoteId:'',noteMutationQueue:{run:fn=>fn()},getAbilityContext:()=>({}),
    storage:{create:async()=>{},save:async()=>{throw Error('disk');}},openNote(){opened++;},notify:m=>messages.push(m)};
  await viewMethod('pages/Index.ets','openFreeCanvas',{WorkspaceNotePolicy}).call(view);
  assert.equal(view.notes,notes);assert.equal(opened,0);assert.equal(view.freeCanvasOpening,false);assert.equal(messages.length,1);
});

test('home feed composes date, tag and pinned filters without mutating the library', () => {
  const {MemoFeedPolicy}=load(`${base}services/library/MemoFeedPolicy.ets`);
  const display=viewMethod('views/workspace/HomeWorkspace.ets','displayNotes',{MemoFeedPolicy});
  const day=new Date(2026,9,17,8).getTime();
  const notes=[studyNote({id:'old',type:'Markdown',createdAt:day-86400000,tags:['复习']}),
    studyNote({id:'today',type:'Markdown',createdAt:day,tags:['复习'],isPinned:true}),
    studyNote({id:'other',type:'Markdown',createdAt:day+1,tags:['项目']}),
    studyNote({id:'pdf',type:'PDF',createdAt:day,tags:['复习']})];
  const view={recentNotes:notes,selectedDate:'2026-10-17',selectedTag:'复习',pinnedOnly:true};
  assert.deepEqual(plain(display.call(view)).map(n=>n.id),['today']);
  view.selectedDate='2026-10-18';assert.equal(display.call(view).length,0);
  assert.deepEqual(notes.map(n=>n.id),['old','today','other','pdf']);
});

test('memo calendar uses local creation dates, covers leap years and excludes PDF activity', () => {
  const {MemoFeedPolicy}=load(`${base}services/library/MemoFeedPolicy.ets`);
  const local=new Date(2024,1,29,0,1).getTime();
  const notes=[studyNote({type:'Markdown',createdAt:local,updatedAt:Date.now(),tags:['复习','复习']}),
    studyNote({id:'pdf',type:'PDF',createdAt:local,tags:['PDF']}),studyNote({id:'unknown',type:'Markdown',createdAt:0})];
  assert.equal(MemoFeedPolicy.dateKey(local),'2024-02-29');
  assert.equal(MemoFeedPolicy.dateKey(Infinity),'');assert.equal(MemoFeedPolicy.dateKey(0),'');
  const cells=MemoFeedPolicy.month(notes,2024,1);assert.equal(cells.length%7,0);
  assert.equal(cells.filter(c=>c.inMonth).length,29);assert.equal(cells.find(c=>c.key==='2024-02-29').count,1);
  assert.equal(new Set(cells.map(c=>c.key)).size,cells.length);
  assert.deepEqual(plain(MemoFeedPolicy.tags(notes)),[{tag:'复习',count:1}]);
  assert.equal(MemoFeedPolicy.query(notes).length,2);
  assert.equal(MemoFeedPolicy.month([],2026,11).filter(c=>c.inMonth).length,31);
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
  const filtered=viewMethod('pages/Index.ets','filteredNotes',{LibraryPolicy});
  const view={searchText:'',activeSpaceName:()=>'',notes:[studyNote({id:'pen',type:'Handwriting'}),studyNote({id:'old',type:'Canvas'}),studyNote({id:'word',type:'docx'}),studyNote({id:'pdf',type:'PDF'})]};
  view.activeFilter='手写';assert.deepEqual(plain(filtered.call(view)).map(n=>n.id),['old','pen']);
  view.activeFilter='Word';assert.deepEqual(plain(filtered.call(view)).map(n=>n.id),['word']);
});

test('a failed note snapshot write leaves the creation form and original library intact', async () => {
  const create=viewMethod('pages/Index.ets','createNote');const original=studyNote();let opened=0;
  const view={notes:[original],noteCreateBusy:false,noteMutationQueue:{run:fn=>fn()},noteCreateError:'',activeSpaceName:()=>'',formatTime:()=>'',
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
    '@kit.ArkData': { uniformTypeDescriptor: { UniformDataType: { PLAIN_TEXT: 'general.plain-text', PDF: 'com.adobe.pdf', FILE: 'general.file' }, getUniformDataTypeByFilenameExtension: ext => { assert.equal(ext,'.json'); return 'general.json'; } } },
    '@kit.CoreFileKit': { fileIo: { access: async () => exists }, fileUri: { getUriFromPath: p => { uris.push(p); return `file://app${p}`; } } },
    canIUse: () => supported
  });
  return { service: SystemShareService, panels, uris, context: { filesDir: '/data/app/files', cacheDir: '/data/app/cache' } };
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

test('selected backup sharing uses a native file URI with the JSON UTD and no delivery assertion', async () => {
  const h=shareHarness(); const file='/data/app/cache/study-share/study_1792280000000_abc123.flowmind.json';
  await h.service.shareBackup(h.context,file,2);
  assert.deepEqual(h.uris,[file]);
  assert.deepEqual(plain(h.panels[0].record),{utd:'general.json',uri:'file://app'+file,title:'墨语资料包',description:'2 份资料，包含正文、原文件与笔迹'});
  for(const invalid of ['/data/app/cache-other/study-share/study_1_a.flowmind.json','/data/app/cache/study-share/../study_1_a.flowmind.json',
    '/data/app/cache/study-share/sub/study_1_a.flowmind.json','/data/app/files/documents/a.pdf']) {
    await assert.rejects(h.service.shareBackup(h.context,invalid,1),/资料包不可用/);
  }
  assert.equal(h.panels.length,1);
  const missing=shareHarness({exists:false});await assert.rejects(missing.service.shareBackup(missing.context,file,1));assert.equal(missing.panels.length,0);
});

test('native transfer packages preserve only selected notes and their full assets, ink and linked cards', async () => {
  const f=backupFileFixture(), note=studyNote({id:'chosen',sourceType:'pdf',sourceUri:'/sandbox/documents/course.pdf',coverUrl:'/sandbox/covers/course.png',
    contentDetail:'📚复习\n'.repeat(130000),pageAnnotations:'{"pages":[{"strokes":[1]}]}'});
  f.files.set(note.sourceUri,Buffer.from('%PDF-1.7 original')); f.files.set(note.coverUrl,Buffer.from('original cover'));
  const card=ReviewPolicy.create(note,{question:'原文问题',answer:'原文答案',sourceText:'复习'});
  const cards=[card,{...card,id:'unselected-card',noteId:'other'}];
  const file=await f.service.createShareFile({filesDir:'/sandbox',cacheDir:'/cache'},[note],cards);
  const pack=JSON.parse(f.files.get(file).toString());
  assert.deepEqual(pack.notes.map(n=>n.id),['chosen']);assert.equal(pack.notes[0].contentDetail,note.contentDetail);assert.equal(pack.notes[0].pageAnnotations,note.pageAnnotations);
  assert.equal(pack.cards.length,1);assert.equal(pack.cards[0].noteId,'chosen');assert.equal(pack.assets.length,2);
  assert.equal(Buffer.from(pack.assets[0].data,'base64').toString(),'%PDF-1.7 original');
  assert.ok(f.calls.filter(c=>c[0]==='write').length>1);assert.ok(f.calls.filter(c=>c[0]==='write').every(c=>c[1]<=512*1024));
  assert.deepEqual(f.calls.filter(c=>c[0]==='worker').map(c=>c[1]),['validateBackupData','encodeBackupData']);
  f.files.set('/picked/backup.json',f.files.get(file));const decoded=await f.service.selectFile({filesDir:'/sandbox'});
  assert.equal(decoded.notes[0].contentDetail,note.contentDetail);assert.equal(f.calls.at(-2)[1],'decodeBackupData');
});

test('transfer cache cleanup removes only its own expired packages and failed writes never leave a successful package', async () => {
  const f=backupFileFixture(); const old='/cache/study-share/study_1_old.flowmind.json';
  f.files.set(old,Buffer.from('expired'));f.files.set('/cache/study-share/manual.json',Buffer.from('keep'));
  const recent='/cache/study-share/study_'+Date.now()+'_recent.flowmind.json';f.files.set(recent,Buffer.from('in use'));
  await f.service.createShareFile({filesDir:'/sandbox',cacheDir:'/cache'},[studyNote()],[]);
  assert.equal(f.files.has(old),false);assert.equal(f.files.has(recent),true);assert.equal(f.files.has('/cache/study-share/manual.json'),true);
  const failed=backupFileFixture({failWrite:true});await assert.rejects(failed.service.createShareFile({filesDir:'/sandbox',cacheDir:'/cache'},[studyNote()],[]),/disk full/);
  assert.equal(failed.files.size,0);assert.equal(failed.calls.filter(c=>c[0]==='close').length,1);
  await assert.rejects(f.service.createShareFile({filesDir:'/sandbox',cacheDir:'/cache'},[],[]),/选择/);
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

test('read-only documents exit directly and pending changes save automatically without a confirmation', () => {
  const back=viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets','handleBackRequest');
  for(const [main,scratch,pending] of [[false,false,false],[true,false,true],[false,true,true]]) {
    let closed=0,saves=0;const v={penOptionsOpen:false,jumpDialogOpen:false,activeModal:'',isPhone:false,splitMode:'none',exitDialogOpen:false,
      documentDirty:main,scratchpadDirty:scratch,onClose:()=>closed++,beginReaderSave:()=>saves++};
    back.call(v);assert.equal(v.exitDialogOpen,false);assert.equal(closed,pending?0:1);assert.equal(saves,pending?1:0);
  }
});

test('exit waits for both main and scratchpad writes and keeps the reader open on failure', () => {
  const relative='views/reader/huawei/HuaweiDocWorkspace.ets';
  for(const success of [true,false]) {
    let closed=0;const notices=[];const v={exitSaving:false,saveDestination:'close',splitMode:'scratchpad',loadedNoteId:'a',exitSaveToken:0,onClose:()=>closed++,showToast:m=>notices.push(m),
      onSaveStateChange(){},beginReaderSave:viewMethod(relative,'beginReaderSave')};
    v.beginReaderSave();assert.equal(v.exitPending,2);assert.equal(v.exitSaveToken,1);
    viewMethod(relative,'exitSaveFinished').call(v,true,'a',1,'document');assert.equal(closed,0);assert.equal(v.exitSaving,true);
    viewMethod(relative,'exitSaveFinished').call(v,success,'a',1,'scratchpad');assert.equal(closed,success?1:0);assert.equal(v.exitSaving,false);assert.equal(notices.length,success?0:1);
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
test('external PDF import persists library metadata before exposing the reference and ignores duplicate import taps', async () => {
  const method=viewMethod('pages/Index.ets','importDocument');let write;const calls=[];
  const transfer={status:'imported',noteType:'PDF',sourceUri:'/sandbox/copy.pdf',sourceFileName:'copy.pdf',pageCount:2,document:{id:'pdf',title:'测试',fileName:'测试.pdf',content:'# 测试'}};
  const v={documentImportBusy:false,notes:[],getAbilityContext:()=>({}),storage:{selectDocumentUris:async()=>['file://book.pdf'],importDocumentUri:async()=>transfer,save:()=>new Promise(r=>write=r)},
    noteMutationQueue:{run:task=>task()},formatTime:()=>'',rebuildSpaces:()=>calls.push('library'),refreshGraph:()=>{},notify:()=>{}};
  v.importOneDocument=viewMethod('pages/Index.ets','importOneDocument');
  const pending=method.call(v,'外部参考');await new Promise(r=>setTimeout(r,0));assert.equal(v.notes.length,0);
  assert.equal(await method.call(v),null);write();const imported=await pending;assert.equal(v.notes[0],imported);assert.equal(imported.sourceUri,transfer.sourceUri);
  assert.equal(imported.category,'外部参考');assert.equal(imported.sourceFileName,'copy.pdf');assert.equal(v.documentImportBusy,false);assert.deepEqual(calls,['library']);
  v.storage.delete=async(_,id,source)=>calls.push(['cleanup',id,source]);
  v.storage.save=async()=>{throw Error('disk');};const original=v.notes;assert.equal(await method.call(v),null);assert.equal(v.notes,original);assert.equal(v.documentImportBusy,false);
  assert.deepEqual(calls.at(-1),['cleanup','pdf','/sandbox/copy.pdf']);
});

test('an import waits for earlier note mutations and retains their latest committed content',async()=>{
  const {SerialTaskQueue}=load(`${base}services/storage/SerialTaskQueue.ets`);
  const queue=new SerialTaskQueue();let release;const writes=[];
  const view={notes:[{id:'existing',contentDetail:'old'}],noteMutationQueue:queue,getAbilityContext:()=>({}),
    storage:{importDocumentUri:async()=>({status:'imported',noteType:'PDF',sourceUri:'/sandbox/book.pdf',
      document:{id:'book',title:'课本.pdf',content:'# 课本'}}),save:async notes=>writes.push(plain(notes))},
    formatTime:()=>'',rebuildSpaces(){},refreshGraph(){},notify(){}};
  const editing=queue.run(async()=>{await new Promise(resolve=>{release=resolve;});view.notes=[{id:'existing',contentDetail:'latest'}];});
  const importing=viewMethod('pages/Index.ets','importOneDocument').call(view,'课本',false,false,'file://book.pdf');
  await new Promise(resolve=>setTimeout(resolve,0));assert.equal(writes.length,0);release();await editing;await importing;
  assert.deepEqual(plain(view.notes).map(note=>note.id),['book','existing']);
  assert.equal(view.notes[1].contentDetail,'latest');assert.equal(writes[0][1].contentDetail,'latest');
});

test('batch imports keep the chosen project, process sequentially and retain committed files after a partial failure',async()=>{
  const importBatch=viewMethod('pages/Index.ets','importDocument');const calls=[],messages=[];let active=0,peak=0;
  const view={documentImportBusy:false,getAbilityContext:()=>({}),storage:{selectDocumentUris:async()=>['a','broken','b']},
    notify:message=>messages.push(message),importOneDocument:async(category,example,snapshot,uri)=>{
      peak=Math.max(peak,++active);await Promise.resolve();calls.push([category,uri]);active--;return uri==='broken'?null:{id:uri};
    }};
  assert.equal((await importBatch.call(view,'课本')).id,'a');assert.equal(peak,1);assert.equal(view.documentImportBusy,false);
  assert.deepEqual(calls,[['课本','a'],['课本','broken'],['课本','b']]);assert.match(messages.at(-1),/2\/3/);
  view.storage.selectDocumentUris=async()=>[];assert.equal(await importBatch.call(view),null);assert.equal(calls.length,3);
});

test('the document picker initially includes PDF, images and text and bounds each batch to twenty files',async()=>{
  let options;
  const select=viewMethod('services/NoteStorageService.ets','selectDocumentUris',{picker:{DocumentSelectOptions:class{},
    DocumentViewPicker:class{async select(value){options=value;return ['file://book.pdf','file://photo.jpg'];}}}});
  const result=await select.call({}, {},100);assert.equal(options.maxSelectNumber,20);
  assert.match(options.fileSuffixFilters[0],/\.pdf/);assert.match(options.fileSuffixFilters[0],/\.jpg/);assert.match(options.fileSuffixFilters[0],/\.md/);
  assert.equal(result.length,2);await select.call({}, {},1);assert.equal(options.maxSelectNumber,1);
});

test('reader note snapshots preserve every declared field and copy tags without JSON-encoding large ink',()=>{
  const declaration=fs.readFileSync(path.join(root,base,'common/types/NoteItem.ets'),'utf8');
  const fields=[...declaration.matchAll(/^  (\w+)\??:/gm)].map(m=>m[1]);
  const original=Object.fromEntries(fields.map(name=>[name,name==='tags'?['复习']:name]));
  original.strokes='大笔迹'.repeat(100000);const snapshot=copyNote(original);
  for(const field of fields)assert.deepEqual(plain(snapshot[field]),plain(original[field]),field);
  original.tags.push('新标签');assert.deepEqual(Array.from(snapshot.tags),['复习']);assert.equal(snapshot.strokes,original.strokes);
});

for(const [file,prepare]of [['HandwritingCanvas.ets','finishStroke'],['pdf/PdfAnnotatorView.ets','finishActiveInput']]) {
  test(`${file} leaves unchanged or already-saved ink without creating a new snapshot or storage write`,async()=>{
    const exit=viewMethod('views/reader/'+file,'saveForExit');const finished=[];
    const view={loadedNoteId:'n',exitSaveToken:3,saveRevision:4,savedRevision:4,saveTimer:-1,
      [prepare](){},onDirtyChange(){},onExitSaveFinished:(...args)=>finished.push(args),strokeSnapshot(){throw Error('redundant snapshot');},annotationSnapshot(){throw Error('redundant snapshot');}};
    await exit.call(view);assert.deepEqual(finished,[[true,'n',3]]);
  });
  test(`${file} waits for in-flight autosave and reuses its success before closing`,async()=>{
    const flush=viewMethod('views/reader/'+file,'flushSave'),exit=viewMethod('views/reader/'+file,'saveForExit');
    let release,writes=0;const finished=[];const note={id:'n',contentDetail:''};
    const view={loadedNoteId:'n',exitSaveToken:5,saveRevision:2,savedRevision:1,saveTimer:-1,
      [prepare](){},strokeSnapshot:()=>note,annotationSnapshot:()=>note,onDirtyChange(){},onSaveStateChange(){},
      onSaved:()=>{writes++;return new Promise(resolve=>{release=resolve;});},onCommitForExit:async()=>{writes++;},onExitSaveFinished:(...args)=>finished.push(args)};
    const saving=flush.call(view),leaving=exit.call(view);assert.equal(writes,1);assert.equal(finished.length,0);
    release();await saving;await leaving;assert.equal(writes,1);assert.deepEqual(finished,[[true,'n',5]]);
  });
  test(`${file} retries a failed autosave before permitting exit and preserves unsaved state if retry fails`,async()=>{
    const exit=viewMethod('views/reader/'+file,'saveForExit');const finished=[];
    const view={loadedNoteId:'n',exitSaveToken:7,saveRevision:2,savedRevision:1,saveTimer:-1,
      saveInFlight:Promise.reject(Error('disk')),[prepare](){},strokeSnapshot:()=>({id:'n',contentDetail:''}),annotationSnapshot:()=>({id:'n',contentDetail:''}),
      onCommitForExit:async()=>{throw Error('disk');},onSaveStateChange(){},onExitSaveFinished:(...args)=>finished.push(args)};
    await exit.call(view);assert.equal(view.savedRevision,1);assert.deepEqual(finished,[[false,'n',7]]);
  });
}

test('ink-only reader commits do not rebuild the text graph while changed text and titles do',async()=>{
  const save=viewMethod('pages/Index.ets','handleSaved');
  for(const kind of ['pdf','scratchpad','reading','handwriting','markdown']) {
    let graphs=0;const note=studyNote({strokes:'old',pageAnnotations:'old'});
    const view={notes:[note],readingNote:{id:''},fullScreenDocNote:{id:''},formatTime:()=>'',getAbilityContext:()=>({}),storage:{},
      noteMutationQueue:{run:fn=>fn()},readerCommits:{commit:async(snapshot,content,ports)=>ports.publish([snapshot],snapshot)},refreshGraph:()=>{graphs++;}};
    await save.call(view,note,note.contentDetail,kind);assert.equal(graphs,kind==='markdown'?1:0);
    if(kind==='handwriting'){await save.call(view,{...note,title:'改标题'},note.contentDetail,kind);assert.equal(graphs,1);}
  }
});

test('the extraction import adapter returns library PDF and text paths and propagates failed imports', async () => {
  const method = viewMethod('pages/Index.ets', 'importExtractSource'); const calls = [];
  const view = { importDocument: async (...args) => { calls.push(args); return { id: 'pdf', sourceType: 'pdf', sourceUri: '/sandbox/documents/original.pdf' }; } };
  assert.equal(await method.call(view, 'file://source.pdf'), '/sandbox/documents/original.pdf');
  assert.deepEqual(calls[0], ['未分类', false, false, 'file://source.pdf']);
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
    const {PdfDocumentService}=load(`${base}services/document/PdfDocumentService.ets`,{'@kit.PDFKit':{pdfService:{}},'@kit.ImageKit':{image:{}},'@kit.ArkTS':{util:{}},
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
      assert.ok(contrastRatio(palette.accent, palette.accentSoft) >= 4.5, `${option.id} selected-control text contrast`);
    }
    assert.equal(normalizeThemeStyle(option.id), option.id);
  });
}
test('unrecognized theme values resolve to the neutral default and saved accents remain compatible', () => {
  for (const value of ['', 'invalid', undefined, 42]) { assert.equal(normalizeThemeStyle(value), 'mono'); }
  assert.equal(normalizeThemeStyle('ink'), 'ink');
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
  assert.equal(f.ThemeManager.currentStyle(), 'mono'); assert.equal(f.ThemeManager.currentMode(), 0);
  assert.equal(f.app.get('flowmindDarkMode'), false); assert.equal(f.app.get('flowmindReduceMotion'), false);
  assert.equal(f.values.get('themeStyle'), 'mono'); assert.equal(f.values.get('themeMode'), 0);
  f.fail(false); await f.ThemeManager.setStyle('mist'); assert.equal(f.app.get('flowmindThemeStyle'), 'mist');
});

test('rapid appearance changes commit in order and the last choice wins without mixing mode and style', async () => {
  const f = await themeFixture();
  await Promise.all([f.ThemeManager.setStyle('blue'), f.ThemeManager.setMode(2), f.ThemeManager.setStyle('mono'), f.ThemeManager.setReduceMotion(true)]);
  assert.equal(f.ThemeManager.currentStyle(), 'mono'); assert.equal(f.ThemeManager.currentMode(), 2);
  assert.equal(f.app.get('flowmindReduceMotion'), true);
  assert.deepEqual(f.calls, [['themeStyle', 'blue'], 'flush', ['themeMode', 2], 'flush', ['themeStyle', 'mono'], 'flush', ['reduceMotion', true], 'flush']);
});

for (const style of ['cyan', 'jade', 'rose', 'sand']) {
  test(`${style} restores across restart and preserves the independently chosen light or dark mode`, async () => {
    for (const mode of [1, 2]) {
      const initial = { themeMode: mode, themeStyle: 'blue' }, f = await themeFixture(initial);
      await f.ThemeManager.setStyle(style);
      const restored = await themeFixture(Object.fromEntries(f.values));
      assert.equal(restored.ThemeManager.currentStyle(), style); assert.equal(restored.ThemeManager.currentMode(), mode);
      assert.equal(restored.app.get('flowmindDarkMode'), mode === 2); assert.equal(restored.app.get('flowmindThemeStyle'), style);
    }
  });
}

test('reader palette follows every chosen style in both modes without mutating shared palettes', () => {
  const { ReaderTheme } = load(`${base}common/theme/ReaderTheme.ets`);
  const original = JSON.stringify(paletteForStyle(false, 'blue'));
  for (const option of THEME_STYLE_OPTIONS) {
    for (const dark of [false, true]) assert.deepEqual(plain(ReaderTheme.palette(dark, option.id)), plain(paletteForStyle(dark, option.id)));
  }
  assert.equal(JSON.stringify(paletteForStyle(false, 'blue')), original);
  assert.deepEqual([...THEME_STYLE_OPTIONS].map(option => option.id), ['blue', 'cyan', 'jade', 'rose', 'sand', 'ink', 'mono', 'mist']);
});

const { SettingsCatalog, SETTINGS_ENTRIES, SETTINGS_GROUPS } = load(`${base}common/constants/SettingsCatalog.ets`);
test('settings search covers names and user vocabulary, preserves group boundaries and returns no fake matches', () => {
  assert.equal(SettingsCatalog.search('OCR')[0].id, 'capture');
  assert.equal(SettingsCatalog.search('浅蓝')[0].id, 'theme');
  for (const label of ['白蓝', '白青', '白绿', '白玫', '暖砂', '雾蓝']) { assert.equal(SettingsCatalog.search(label)[0].id, 'theme'); }
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
    isAnnotateMode: true, exitSaving: false, splitMode: 'none', isPhone: false, exitSaveToken: 0, loadedNoteId: 'a',
    documentDirty: true, scratchpadDirty: false, penOptionsOpen: false,
    onClose: () => calls.push('close'), onSaveStateChange(){}, showToast: message => calls.push(message),
    ...overrides };
  for (const method of ['handleBackRequest', 'returnToReading', 'beginReaderSave', 'exitSaveFinished', 'switchSplitMode']) {
    view[method] = viewMethod(relative, method);
  }
  return { view, calls };
}

test('back saves and exits annotation in one operation without a redundant confirmation', () => {
  const {view,calls}=documentNavigationHarness();view.handleBackRequest();
  assert.equal(view.isAnnotateMode,false);assert.equal(view.saveDestination,'close');assert.equal(view.exitSaveToken,1);
  view.handleBackRequest();assert.equal(view.exitSaveToken,1);assert.deepEqual(calls,[]);
  view.exitSaveFinished(true,'a',1,'document');assert.equal(view.exitSaving,false);assert.equal(view.exitDialogOpen,false);
  assert.equal(view.documentDirty,false);assert.equal(view.scratchpadDirty,false);assert.deepEqual(calls,['close']);
});

test('back closes a transient dialog first and never leaves the document during source recovery', () => {
  const { view } = documentNavigationHarness({ jumpDialogOpen: true });
  view.handleBackRequest(); assert.equal(view.jumpDialogOpen, false); assert.equal(view.isAnnotateMode, true);
  view.restoreSourceBusy = true; view.handleBackRequest(); assert.equal(view.exitSaveToken, 0);
});

test('locking annotation waits for main and scratchpad, and failed persistence stays recoverable', () => {
  const { view, calls } = documentNavigationHarness({ splitMode: 'scratchpad', scratchpadDirty: true });
  view.returnToReading(); assert.equal(view.exitPending, 2);
  view.exitSaveFinished(true,'a',1,'document'); assert.equal(view.exitSaving, true);
  view.exitSaveFinished(false,'a',1,'scratchpad'); assert.equal(view.exitSaving, false); assert.equal(view.exitDialogOpen, true);
  assert.ok(!calls.includes('close')); assert.equal(view.scratchpadDirty, true);
  view.beginReaderSave(); assert.equal(view.exitPending, 2); assert.equal(view.exitSaveToken, 2);
  view.documentDirty = false; view.scratchpadDirty = false;
  view.exitSaveFinished(true,'a',2,'document'); view.exitSaveFinished(true,'a',2,'scratchpad'); assert.equal(view.exitDialogOpen, false);
  assert.ok(!calls.includes('close'));
});

test('closing a dirty scratchpad waits for both saves and never unmounts it on failure', () => {
  for (const success of [true, false]) {
    const { view, calls } = documentNavigationHarness({ splitMode: 'scratchpad', scratchpadDirty: true });
    view.switchSplitMode('none'); assert.equal(view.splitMode, 'scratchpad'); assert.equal(view.saveDestination, 'split');
    view.exitSaveFinished(true,'a',1,'document'); view.exitSaveFinished(success,'a',1,'scratchpad');
    assert.equal(view.splitMode, success ? 'none' : 'scratchpad'); assert.ok(!calls.includes('close'));
  }
});

test('unreadable PDFs cannot enter annotation, while whiteboards and readable PDFs can', () => {
  const mode = viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets', 'setAnnotationMode');
  for (const [whiteboard, ready, expected] of [[false, false, false], [false, true, true], [true, false, true]]) {
    const view = { exitSaving: false, restoreSourceBusy: false, isAnnotateMode: false, pdfSourceReady: ready, annotationError: '',
      whiteboardReady: true,
      note: {}, isHandwritingNote: () => whiteboard, isImageDocument: () => false, showToast() {} };
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
  view.exitSaveFinished(true, 'old', view.exitSaveToken, 'document');
  view.exitSaveFinished(true, 'new', view.exitSaveToken - 1, 'document');
  assert.equal(view.exitPending, 1); assert.equal(view.exitSaving, true); assert.deepEqual(calls, []);
  view.exitSaveFinished(true, 'new', view.exitSaveToken, 'document'); assert.deepEqual(calls, ['close']);
});

test('late reader persistence publishes library data without replacing a different open document', async () => {
  const save = viewMethod('pages/Index.ets', 'handleSaved');
  for (const currentId of ['new', 'old']) {
    const view = { formatTime: () => 'now', getAbilityContext: () => ({}), notes: [],
      readingNote: { id: currentId, title: 'keep' }, fullScreenDocNote: { id: 'new', title: 'keep' }, refreshGraph() {},
      storage: {}, noteMutationQueue: { run: action => action() }, readerCommits: { commit: async (note, content, ports) => ports.publish([note], { ...note, title: 'saved' }) } };
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
  redraw.call({ context: recorder.ctx, viewportReady:true, canvasWidth: 360, canvasHeight: 700, zoomScale: 0.3,
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
  const v = { context: h.target, inkFrame: h.composer, viewportReady:true, canvasWidth: 1200, canvasHeight: 700, zoomScale: 1,
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

test('PDF page replay draws saved masks and active area preview on the visible layer', () => {
  const f = inkRecorder(); f.ctx.clearRect = () => f.calls.push(['clear']);
  const relative = 'views/reader/pdf/PdfPageCanvas.ets';
  const pen = { id: 'p', color: '#000', width: 3, isHighlighter: false, isEraser: false, points: [{ u: .1, v: .2 }] };
  const mask = { ...pen, id: 'mask', width: 20, isEraser: true };
  const active = { ...mask, id: 'active' };
  const v = { context: f.ctx, pageWidth: 720, pageHeight: 1000, strokes: [pen, mask], currentStroke: active };
  for (const name of ['redrawAll', 'renderStroke', 'mapped', 'style']) v[name] = viewMethod(relative, name, { InkRenderer });
  v.redrawAll();
  assert.equal(f.calls[0][0], 'clear');
  assert.deepEqual(f.calls.filter(row => row[0] === 'fill').map(row => row[3]), ['source-over', 'destination-out', 'destination-out']);
  f.calls.length = 0; v.currentStroke = null; v.strokes = [mask]; v.redrawAll();
  assert.deepEqual(f.calls.filter(row => row[0] === 'fill').map(row => row[3]), ['destination-out']);
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

test('whiteboard loading failure reports unavailable content while keeping the exact original raw snapshot', async () => {
  const loadInk = viewMethod('views/reader/HandwritingCanvas.ets', 'loadStrokes', { CanvasViewport });
  const readInk = viewMethod('views/reader/HandwritingCanvas.ets', 'readStrokes', {CanvasStrokeLoader:{load:async raw=>CanvasStrokePolicy.parse(raw)}});
  for (const scratchpad of [false, true]) {
    const ready = [], dirty = []; const raw = '[{"points":null,"width":3,"color":"#000"}]';
    const view = { note: { id: 'ink', strokes: raw, scratchpadStrokes: raw }, isScratchpad: scratchpad,
      loadError: '', loadGeneration:0, toolsVisible: true, boundsCache: new Map(), viewportReady: false, emitToolState() {},readStrokes:readInk,requestRedraw(){},
      onContentReady: value => ready.push(value), onDirtyChange: value => dirty.push(value) };
    loadInk.call(view);await view.loadInFlight;
    assert.equal(view.loadedRaw, raw); assert.equal(view.note.strokes, raw); assert.equal(view.note.scratchpadStrokes, raw);
    assert.equal(view.strokes.length, 0); assert.ok(view.loadError); assert.equal(view.toolsVisible, false);
    assert.equal(view.saveRevision, 0); assert.deepEqual(dirty, [false]); assert.deepEqual(ready, [false,false]);
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

test('a stylus takeover discards an unfinished palm or finger mark before acquiring the new pen pointer', () => {
  const handle = viewMethod('views/reader/HandwritingCanvas.ets', 'handleTouch', { ...penEnums, CanvasViewport });
  const order = []; const view = { navigateTouch: () => false, readOnly: false, loadError: '',
    input: { isActive: () => true, isPenActive: () => false, read: () => { order.push('read new pen'); return { phase: 'ignore' }; } },
    cancelContact: () => order.push('cancel old finger') };
  handle.call(view, touchEvent(0, 7, 2)); assert.deepEqual(order, ['cancel old finger', 'read new pen']);
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
  const view={customProjects:[], projectCreateBusy:false,noteMutationQueue:{run:fn=>fn()}, getAbilityContext:()=>({}),
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
  const view={customProjects:original,projectCreateBusy:false,noteMutationQueue:{run:fn=>fn()},getAbilityContext:()=>({}),
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

test('formatting, task extraction, display and graph indexing agree on matching fences', () => {
  const input = '~~~~text\n准备提交假任务 [[假链接]] #假标签\n~~~\n~~~~ invalid\n完成另一个假任务\n~~~~~\n\n# 真标题\n明天提交报告 [[真链接]] #真标签';
  const result = SourceTextParser.fromSource(input);
  assert.equal(result.title, '真标题');
  assert.equal(result.tasks.length, 1); assert.equal(result.tasks[0].sourceLine, 9);
  const { MarkdownParserService } = load(`${base}services/MarkdownParserService.ets`);
  const parsed = new MarkdownParserService().parse({ title: 'fallback', content: input });
  assert.deepEqual(plain(parsed.links.map(link => link.target)), ['真链接']);
  assert.deepEqual(plain(parsed.tags.map(tag => tag.value)), ['#真标签']);
  const { DocumentTextParser } = load(`${base}services/document/DocumentTextParser.ets`);
  const blocks = DocumentTextParser.parse(input);
  assert.equal(blocks[0].kind, 'code'); assert.equal(blocks[0].endLine, 5);
  assert.ok(blocks[0].text.includes('~~~~ invalid'));
  assert.equal(blocks[1].text, '真标题');
});

test('explicit unchecked items retain evidence without requiring an action keyword', () => {
  const input = '# 复习安排\n- [ ] 阅读第三章\n1. [ ] 明天复习错题\n- [x] 复习第一章\n- [ ] 阅读第三章\n> 明天提交旧报告\n整理算法用于分析数据。\n完成状态表示任务已经结束。\n任务：复习公式';
  const result = SourceTextParser.fromSource(input);
  assert.deepEqual(plain(result.tasks.map(task => task.title)), ['阅读第三章', '明天复习错题', '复习公式']);
  assert.equal(result.tasks[0].sourceLine, 2); assert.equal(result.tasks[0].sourceText, '- [ ] 阅读第三章');
  assert.equal(result.tasks[1].deadline, '明天');
  assert.equal(SourceTextParser.fromSource('```text\n准备材料\n```').title, '已提取知识');
});

test('OCR joining respects setext headings, spaced dividers, references and comments', () => {
  const input = '这是一段长度超过十二字的正文内容\n课程内容\n===\n- - -\n<!--\n明天提交隐藏的报告\n-->\n[参考]: https://example.com\n\n$$\n```\n提交公式中的变量\n$$\n明天提交真实报告';
  const result = LocalTextFormatter.format(input, '记录', 'study', true);
  assert.ok(result.includes('正文内容\n课程内容\n===\n- - -'));
  assert.equal(SourceTextParser.fromSource(input).tasks.length, 1);
  assert.equal(SourceTextParser.fromSource('\uFEFF# 课程\r正文').title, '课程');
});

test('multiple date mentions require confirmation and invalid selected dates cause no writes', async () => {
  const content = SourceTextParser.fromSource('10月1日准备材料，10月2日提交报告。');
  assert.equal(content.tasks[0].deadline, '10月1日 / 10月2日');
  const store = captureStore();
  await assert.rejects(SmartCaptureService.commit(content, content.tasks, store.port), /日期尚未确认/);
  assert.deepEqual(store.state.calls, []);
});

test('restored drafts resolve relative dates against extraction day, with undated tasks on save day', () => {
  const saved = new Date(2027, 0, 3, 9); const captured = new Date(2026, 11, 31, 23);
  const todos = SmartNoteBuilder.buildTodos([{ id: 'a', title: '报告', deadline: '明天' },
    { id: 'b', title: '阅读', deadline: '' }], 'note', saved, captured);
  assert.equal(todos[0].date, '2027-01-01'); assert.equal(todos[1].date, '2027-01-03');
});

test('oversized OCR append preserves the existing input and source image', async () => {
  const pick = viewMethod('views/layout/sheets/SmartExtractSheet.ets', 'pickImageAndOcr', {
    Error, SMART_INPUT_LIMIT: 10, AppStorage: { setOrCreate: () => assert.fail('must retain existing draft') },
    picker: { PhotoSelectOptions: class {}, PhotoViewMIMETypes: { IMAGE_TYPE: 'image' },
      PhotoViewPicker: class { async select() { return { photoUris: ['new-image'] }; } } },
    OcrService: { getInstance: () => ({ recognizeTextFromUri: async () => '识别内容超过上限' }) } });
  const view = { alive: true, requestId: 0, inputText: '保留原稿', imageUri: 'old-image', step: 'input', busy: () => false };
  await pick.call(view);
  assert.equal(view.inputText, '保留原稿'); assert.equal(view.imageUri, 'old-image');
  assert.match(view.errorMsg, /超过上限/); assert.equal(view.step, 'input');
});

function searchHarness(read) {
  const { NoteSearchService } = load(`${base}services/NoteSearchService.ets`, {
    [path.resolve(root, `${base}services/NoteStorageService.ets`)]: { NoteStorageService: class {} } });
  return new NoteSearchService({ read: read || (async (_, note) => ({ id: note.id, title: note.title,
    content: note.contentDetail || '', fileName: `${note.id}.md`, filePath: '', updatedAt: 0 })) });
}

test('search ranks exact titles, other titles, tags and body hits with stable ties', async () => {
  const notes = [{ id: 'body', title: '随笔', contentDetail: '课程' }, { id: 'tag', title: '记录', tags: ['课程'] },
    { id: 'title', title: '课程笔记' }, { id: 'exact', title: '课程' }, { id: 'body2', title: '另一个', contentDetail: '课程' }];
  const found = await searchHarness().search({}, notes, '课程');
  assert.deepEqual(plain(found.map(row => row.noteId)), ['exact', 'title', 'tag', 'body', 'body2']);
});

test('one unreadable body leaves metadata and other corrected PDF page results searchable', async () => {
  const service = searchHarness(async (_, note) => {
    if (note.id === 'broken') throw Error('disk');
    return { id: note.id, title: note.title, fileName: `${note.id}.md`, content: note.contentDetail || '' };
  });
  const unreadable = [];
  const found = await service.search({}, [{ id: 'broken', title: '课程', contentDetail: '陈旧快照不能被检索' },
    { id: 'pdf', title: '扫描', type: 'PDF', pageCount: 3,
      pdfTextJson: JSON.stringify([{ pageNumber: 2, text: '课程要求', method: 'ocr' }]) }], '课程', false,
    { onUnreadable: id => unreadable.push(id) });
  assert.deepEqual(plain(found.map(row => row.noteId)), ['broken', 'pdf']);
  assert.equal(found[1].pageNumber, 2); assert.deepEqual(unreadable, ['broken']);
  assert.equal((await service.search({}, [{ id: 'broken', title: '课程', contentDetail: '陈旧快照' }], '陈旧')).length, 0);
});

test('cancelled search stops scheduling reads and discards in-flight completions', async () => {
  let cancelled = false; const pending = []; let reads = 0;
  const service = searchHarness((_, note) => { reads++; return new Promise(resolve => pending.push(() =>
    resolve({ id: note.id, title: note.title, fileName: '', content: '课程' }))); });
  const running = service.search({}, Array.from({ length: 40 }, (_, i) => ({ id: String(i), title: '资料' })), '课程', false,
    { cancelled: () => cancelled });
  assert.equal(reads, 4); cancelled = true; pending.forEach(finish => finish());
  assert.equal((await running).length, 0); assert.equal(reads, 4);
});

test('invalid regex is reported before any file reads', async () => {
  const service = searchHarness(() => assert.fail('invalid query must not read'));
  await assert.rejects(service.search({}, [{ id: 'a' }], '[', true), /正则表达式无效/);
});

test('search request generations isolate same-query races and closed dialogs', async () => {
  const run = viewMethod('views/explore/QuickSearchDialog.ets', 'runSearch', { Error });
  const pending = [];
  const view = { requestId: 0, alive: true, regexOn: false, searching: true, notes: [], results: [],
    searchService: { search: (_, __, ___, ____, options) => new Promise(resolve => pending.push({ resolve, options })) } };
  const older = run.call(view, '课程'); const newer = run.call(view, '课程');
  assert.equal(pending[0].options.cancelled(), true);
  pending[1].resolve(['new']); await newer; pending[0].resolve(['old']); await older;
  assert.deepEqual(view.results, ['new']); assert.equal(view.searching, false);
  const closing = run.call(view, '课程'); view.alive = false;
  pending[2].resolve(['closed']); await closing; assert.deepEqual(view.results, ['new']);
});

test('graph aliases resolve deterministically and cancelled rebuilds stop reading', async () => {
  const notes = [{ id: 'first', title: '同名', contentDetail: '[[同名]] [[SECOND.md]] [[missing]]' },
    { id: 'second', title: '同名', contentDetail: '' }];
  const graph = await searchHarness().buildLinkGraph({}, notes);
  assert.deepEqual(plain(graph.backlinks.map(link => link.targetNoteId)), ['first', 'second']);
  assert.equal(graph.unresolvedLinks[0].target, 'missing');
  let cancelled = false; let reads = 0;
  const service = searchHarness(async (_, note) => { reads++; cancelled = true; return { id: note.id, content: '', title: note.title }; });
  await service.buildLinkGraph({}, notes, () => cancelled); assert.equal(reads, 1);
});

test('late graph success or failure cannot replace the graph from the latest library snapshot', async () => {
  const refresh = viewMethod('pages/Index.ets', 'refreshGraph'); const pending = []; let stats = 0;
  const view = { graphRequestId: 0, notes: [], linkGraph: { backlinks: ['original'] }, refreshStats: () => stats++, notify: () => {},
    searchService: { buildLinkGraph: () => new Promise((resolve, reject) => pending.push({ resolve, reject })) } };
  const first = refresh.call(view); view.notes = []; const second = refresh.call(view);
  pending[1].resolve({ backlinks: ['new'] }); await second; pending[0].reject(Error('old read failed')); await first;
  assert.deepEqual(view.linkGraph.backlinks, ['new']); assert.equal(stats, 1);
  const failed = refresh.call(view); pending[2].reject(Error('disk')); await failed;
  assert.deepEqual(view.linkGraph.backlinks, ['new']); assert.equal(stats, 2);
});

test('Unicode mandatory line and paragraph separators survive optional OCR joining', () => {
  const line = '这是一段长度超过十二字的课程正文';
  for (const separator of ['\u0085', '\u2028']) {
    const formatted = LocalTextFormatter.format(`${line}${separator}继续说明`, '记录', 'study', true);
    assert.ok(formatted.includes(`${line}  \n继续说明`));
  }
  assert.ok(LocalTextFormatter.format(`${line}\u2029继续说明`, '记录', 'study', true).includes(`${line}\n\n继续说明`));
});

test('OCR joining does not remove explicit no-break characters at line boundaries', () => {
  const line = '这是一段长度超过十二字的课程正文';
  for (const separator of ['\u00A0', '\u202F', '\u2060']) {
    const source = `${line}${separator}\n继续说明`;
    assert.ok(LocalTextFormatter.format(source, '记录', 'study', true).endsWith(source));
  }
});

test('display and outline agree on Setext headings and preserve literal hashes in titles', () => {
  const source = '# C#\n\n二级标题\n---\n## 小节 ###';
  const { MarkdownParserService } = load(`${base}services/MarkdownParserService.ets`);
  const outline = new MarkdownParserService().parse({ title: 'fallback', content: source });
  assert.equal(outline.title, 'C#');
  assert.deepEqual(plain(outline.headings.map(row => [row.text,row.level,row.line])), [['C#',1,1],['二级标题',2,3],['小节',2,5]]);
  const blocks = DocumentTextParser.parse(source);
  assert.deepEqual(plain(blocks.map(row => [row.text,row.level])), [['C#',1],['二级标题',2],['小节',2]]);
});

test('local study formatting is idempotent and preserves original numeric and formula tokens', () => {
  const source = '【课程记录】\n一、要求\n• 复习 2026-10-16 的内容\n\n| 项目 | 数值 |\n| --- | --- |\n| A | 1.025 |\n\n$$x^2 + y^2 = 1$$';
  const formatted = LocalTextFormatter.format(source, '课程记录', 'study', true);
  assert.equal(LocalTextFormatter.format(formatted, '课程记录', 'study', true), formatted);
  for (const token of ['2026-10-16','1.025','$$x^2 + y^2 = 1$$']) assert.ok(formatted.includes(token));
});

test('Unicode separator handling leaves literal code, formulas and table cells unchanged', () => {
  for (const source of ['```js\nconst value = "a\u2028b";\n```', '$$a\u2028b$$', '| a\u2028b | c |']) {
    assert.ok(LocalTextFormatter.format(source, '记录', 'study', true).endsWith(source));
  }
});

test('reader source offsets still address the original file when it contains Unicode line separators', () => {
  const source = '# 课程\n正文\u2028续行\n\n```js\nconst x = 12;\n```';
  const parse = viewMethod('views/reader/MarkdownReader.ets','parseBlocks',{DocumentTextParser});
  const view = { parseTask: viewMethod('views/reader/MarkdownReader.ets','parseTask') };
  for (const input of [source,source.replaceAll('\n','\r'),source.replaceAll('\n','\r\n')]) {
    const blocks = parse.call(view,input);
    assert.equal(blocks.at(-1).line,3); assert.equal(blocks.at(-1).text,'```js\nconst x = 12;\n```');
  }
});

function screenshotHarness(options = {}) {
  const events = [], written = [], input = Uint8Array.from([137,80,78,71,1,2,3,4]);
  const pixels = { getImageInfo: async () => ({ size: { width: options.tooLarge ? 40000 : 400, height: 800 } }), release: async () => events.push('pixels.release') };
  const packer = { packing: async () => { events.push('pack'); if (options.packError) throw Error('图片编码失败'); return input.buffer; }, release: async () => events.push('packer.release') };
  const ui = { getComponentSnapshot: () => ({ get: async (id, config) => { events.push(['capture',id,config.waitUntilRenderFinished]); if (options.captureError) throw Error('页面未就绪'); return pixels; } }) };
  const fileIo = { OpenMode: { WRITE_ONLY:1, CREATE:2, TRUNC:4 },
    open: async () => { events.push('open'); return {fd:7}; },
    write: async (_, data, config) => {
      assert.equal(config,undefined,'writes continue from the native file pointer without a relative offset');
      events.push('write'); if (options.writeError) throw Error('空间不足');
      if (options.zeroWrite) return 0;
      const bytes = new Uint8Array(data), count = Math.min(bytes.length,3); written.push(...bytes.slice(0,count)); return count;
    }, fsync: async () => events.push('sync'), close: async () => events.push('close') };
  const picker = { DocumentSaveOptions: class {}, DocumentViewPicker: class {
    async save(config) { events.push('picker'); assert.ok(events.includes('pixels.release')); assert.deepEqual([...config.fileSuffixChoices],['PNG 图片|.png']); return options.cancel ? [] : ['file://chosen.png']; }
  } };
  const { ReaderOutputService } = load(`${base}services/document/ReaderOutputService.ets`, {
    '@kit.AbilityKit': {}, '@kit.ArkUI': {}, '@kit.ImageKit': { image: { createImagePacker: () => packer } }, '@kit.CoreFileKit': {fileIo,picker}
  });
  return {run:()=>ReaderOutputService.saveScreenshot({},ui,'document-a','课程/第一章'),events,written,input};
}

test('screenshot exports the named document viewport, handles partial writes and releases image memory before the picker',async()=>{
  const h=screenshotHarness();const result=await h.run();assert.equal(result.status,'exported');
  assert.deepEqual(h.events[0],['capture','document-a',true]);assert.deepEqual(h.written,[...h.input]);
  assert.deepEqual(h.events.slice(-2),['sync','close']);
  assert.equal(h.events.filter(event=>event==='pixels.release').length,1);
  assert.equal(h.events.filter(event=>event==='packer.release').length,1);
});

test('cancelling screenshot output does not create a file or claim success',async()=>{
  const h=screenshotHarness({cancel:true});assert.equal((await h.run()).status,'cancelled');
  assert.equal(h.events.includes('open'),false);assert.deepEqual(h.written,[]);
});

for(const [name,option,message] of [['capture','captureError','页面未就绪'],['encoding','packError','图片编码失败'],['write','writeError','空间不足'],['zero write','zeroWrite','完整写入'],['oversized viewport','tooLarge','区域过大']]) {
  test(`screenshot ${name} failure remains a failure and frees acquired resources`,async()=>{
    const h=screenshotHarness({[option]:true});const result=await h.run();assert.equal(result.status,'failed');assert.ok(result.message.includes(message));
    if(option!=='captureError')assert.ok(h.events.includes('pixels.release'));
    if(option==='writeError'||option==='zeroWrite')assert.ok(h.events.includes('close'));
    else assert.equal(h.events.includes('open'),false);
  });
}

test('reader waits for document and scratchpad commits before opening an output dialog',()=>{
  const file='views/reader/huawei/HuaweiDocWorkspace.ets';
  const view={note:{id:'a'},loadedNoteId:'a',isAnnotateMode:true,documentDirty:true,scratchpadDirty:true,splitMode:'scratchpad',
    exitSaveToken:4,exitSaving:false,outputBusy:false,restoreSourceBusy:false,activeModal:'',
    beginReaderSave:viewMethod(file,'beginReaderSave'),showToast(){},onSaveStateChange(){},onClose(){throw Error('must remain in reader');}};
  viewMethod(file,'openOutput').call(view,'export_image');assert.equal(view.activeModal,'');assert.equal(view.exitPending,2);
  const finish=viewMethod(file,'exitSaveFinished');finish.call(view,true,'a',5,'document');assert.equal(view.activeModal,'');
  finish.call(view,true,'a',5,'scratchpad');assert.equal(view.activeModal,'export_image');assert.equal(view.exitSaving,false);
});

test('reader save failure keeps the output pending for retry and never opens a picker',()=>{
  const file='views/reader/huawei/HuaweiDocWorkspace.ets', view={loadedNoteId:'a',exitSaveToken:1,exitPending:1,exitSaving:true,
    expectedSaveAreas:new Set(['document']),completedSaveAreas:new Set(),
    exitFailed:false,saveDestination:'output',pendingOutput:'export_text',activeModal:'',onSaveStateChange(){},showToast(){}};
  viewMethod(file,'exitSaveFinished').call(view,false,'a',1,'document');assert.equal(view.activeModal,'');assert.equal(view.exitDialogOpen,true);
  assert.equal(view.pendingOutput,'export_text');
});

test('output confirmation ignores repeated taps, holds dismissal while busy and reports native cancellation',async()=>{
  let release,calls=0;const file='views/reader/huawei/HuaweiDocWorkspace.ets';
  const view={note:{id:'a'},activeModal:'export_text',outputBusy:false,getUIContext:()=>({getHostContext:()=>({})}),
    onExportText:()=>{calls++;return new Promise(resolve=>{release=resolve;});}};
  const perform=viewMethod(file,'performOutput');const work=perform.call(view,'.txt');await perform.call(view,'.txt');
  viewMethod(file,'closeOutput').call(view);assert.equal(view.activeModal,'export_text');assert.equal(calls,1);
  release({status:'cancelled',message:'取消'});await work;assert.equal(view.activeModal,'');assert.equal(view.outputBusy,false);
});

test('output errors stay visible for retry and stale results cannot overwrite another note',async()=>{
  const file='views/reader/huawei/HuaweiDocWorkspace.ets',perform=viewMethod(file,'performOutput',{Error});
  const view={note:{id:'a'},activeModal:'export_text',getUIContext:()=>({getHostContext:()=>({})}),onExportText:async()=>{throw Error('保存失败');}};
  await perform.call(view,'.md');assert.equal(view.outputFailed,true);assert.equal(view.outputMessage,'保存失败');assert.equal(view.activeModal,'export_text');
  let release;view.onExportText=()=>new Promise(resolve=>{release=resolve;});const work=perform.call(view,'.md');
  view.note={id:'b'};view.outputMessage='b 的提示';view.outputBusy=false;release({status:'exported',message:'a 完成'});await work;
  assert.equal(view.outputMessage,'b 的提示');
});

test('Markdown output takes current editor text and back closes the output before leaving the note',async()=>{
  const file='views/reader/MarkdownReader.ets';let snapshot;
  const view={editingNote:{id:'a'},loadedNoteId:'a',outputAction:'export_text',shareBusy:false,
    buildSnapshot:()=>({id:'a',title:'刚改的标题',contentDetail:'未保存的新内容'}),getUIContext:()=>({getHostContext:()=>({})}),
    storage:{exportDocument:async(_,note,extension)=>{snapshot={...note,extension};return {status:'exported',message:'已导出'};}}};
  await viewMethod(file,'performOutput').call(view,'.txt');assert.equal(snapshot.contentDetail,'未保存的新内容');assert.equal(snapshot.extension,'.txt');
  view.closeOutput=viewMethod(file,'closeOutput');view.onRequestClose=()=>{throw Error('dialog must close first');};
  viewMethod(file,'handleBackRequest').call(view);assert.equal(view.outputAction,'');
});

test('compact calendar follows the selected week and the month expansion retains the selected date',()=>{
  const file='views/workspace/TodoWorkspace.ets';const all=Array.from({length:35},(_,i)=>({dateKey:`day-${i}`,day:i,inMonth:true}));
  const view={isPhone:true,calendarExpanded:false,selectedDate:'day-24',cells:()=>all};
  const visible=viewMethod(file,'visibleCells');assert.deepEqual([...visible.call(view)].map(v=>v.dateKey),all.slice(21,28).map(v=>v.dateKey));
  view.calendarExpanded=true;assert.equal(visible.call(view).length,35);assert.equal(view.selectedDate,'day-24');
});

test('todo deletion needs explicit confirmation while cancellation preserves the task',async()=>{
  const file='views/workspace/TodoWorkspace.ets';let answer=0,deleted=0;
  const request=viewMethod(file,'requestDeleteTodo',{promptAction:{showDialog:async()=>({index:answer})}});
  const task={id:'a',title:'课程任务'},view={todos:[task],palette:()=>({}),onDeleteTodo:()=>deleted++};
  await request.call(view,task);assert.equal(deleted,0);answer=1;await request.call(view,task);assert.equal(deleted,1);
  view.todos=[];await request.call(view,task);assert.equal(deleted,1);assert.equal(view.deletePromptOpen,false);
});

test('reader back dismisses the tool settings card before ending the annotation session',()=>{
  const view={activeModal:'',penOptionsOpen:true,isAnnotateMode:true,returnToReading:()=>{throw Error('must close settings first');}};
  viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets','handleBackRequest').call(view);assert.equal(view.penOptionsOpen,false);assert.equal(view.isAnnotateMode,true);
});

for(const shortWrite of [false,true]) {
  test(`text export ${shortWrite?'rejects a short UTF-8 write':'flushes the complete UTF-8 content before reporting success'}`,async()=>{
    const events=[],content='中文与符号 🙂';
    const fileIo={OpenMode:{},open:async()=>({fd:1}),write:async(_,value)=>Buffer.byteLength(value)-(shortWrite?1:0),fsync:async()=>events.push('sync'),close:async()=>events.push('close')};
    const picker={DocumentSaveOptions:class{},DocumentViewPicker:class{async save(){return ['picked.md'];}}};
    const util={TextEncoder:class{encodeInto(value){return Buffer.from(value);}}};
    const exportText=viewMethod('services/NoteStorageService.ets','exportDocument',{fileIo,picker,util});
    const result=await exportText.call({safeFileName:value=>value,fileNameFromUri:value=>value},{},{title:'课程',contentDetail:content},'.md');
    assert.equal(result.status,shortWrite?'failed':'exported');assert.deepEqual(events,shortWrite?['close']:['sync','close']);
  });
}

const { ImageDocumentPolicy }=load(`${base}services/document/ImageDocumentPolicy.ets`);
function imageDocumentFixture(options={}) {
  const bytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jK7sAAAAASUVORK5CYII=','base64');
  const source=`file://picked/scan${options.extension||'.png'}`,files=new Map([[source,bytes]]),opened=new Map(),events=[];let nextFd=0;
  const context={filesDir:'/sandbox/files'};
  const resolve=value=>typeof value==='number'?opened.get(value):value;
  const fileIo={OpenMode:{READ_ONLY:0,WRITE_ONLY:1,CREATE:2,TRUNC:4},
    access:async name=>name===`${context.filesDir}/documents`||files.has(name),mkdir:async()=>{},
    open:async(name,mode)=>{if((mode&4)!==0)files.set(name,Buffer.alloc(0));if(!files.has(name))throw Error('missing source');opened.set(++nextFd,name);events.push(['open',name]);return {fd:nextFd};},
    close:async file=>{events.push(['close',opened.get(file.fd)]);opened.delete(file.fd);},
    statSync:value=>({size:options.largeFile&&resolve(value)===source?17*1024*1024:files.get(resolve(value)).length}),
    copyFile:async(fd,target)=>{events.push(['copy',target]);files.set(target,Buffer.from(options.shortCopy?bytes.subarray(0,8):files.get(resolve(fd))));},
    unlink:async path=>{files.delete(path);events.push(['unlink',path]);},
    read:async(fd,data)=>{const input=files.get(resolve(fd));new Uint8Array(data).set(input);return input.length-(options.shortRead?1:0);},
    write:async(fd,data)=>{const input=Buffer.from(data);files.set(resolve(fd),input);return input.length-(options.shortWrite?1:0);},
    fsync:async()=>events.push('sync')};
  const image={PropertyKey:{ORIENTATION:'Orientation'},createImageSource:()=>({
    getImageProperty:async()=>{if(options.exifError)throw Error('no exif');return options.orientation||'1';},
    getImageInfo:async()=>({size:options.huge?{width:40000,height:40000}:options.size||{width:1,height:1},
    mimeType:options.mime||ImageDocumentPolicy.mime(options.extension||'.png')}),
    createPixelMap:async config=>{events.push(['decode',config]);if(options.decodeError)throw Error('corrupt image');return {release:async()=>events.push('pixels-release'),
      flip:async(x,y)=>{events.push(['flip',x,y]);if(options.transformError)throw Error('transform failed');},
      rotate:async(angle)=>{events.push(['rotate',angle]);if(options.transformError)throw Error('transform failed');}};},
    release:async()=>events.push('source-release')})};
  const picker={DocumentSaveOptions:class{},DocumentViewPicker:class{async save(){events.push('picker');return options.cancel?[]:['file://export/image.png'];}}};
  const {ImageDocumentService}=load(`${base}services/document/ImageDocumentService.ets`,{'@kit.AbilityKit':{},'@kit.CoreFileKit':{fileIo,picker},'@kit.ImageKit':{image}});
  return {service:ImageDocumentService,files,events,source,bytes,context,opened};
}

test('raster import accepts named common formats and rejects mismatched content, SVG and invalid dimensions',()=>{
  for(const [extension,mime] of [['.png','image/png'],['.JPG','image/jpeg'],['.jpeg','image/jpeg'],['.webp','image/webp'],['.bmp','image/bmp'],['.gif','image/gif']]) {
    const suffix=ImageDocumentPolicy.extension(`scan${extension}`);assert.ok(suffix);assert.ok(ImageDocumentPolicy.info(100,200,2000,mime,suffix));
  }
  assert.equal(ImageDocumentPolicy.extension('scan.svg'),'');assert.equal(ImageDocumentPolicy.extension('scan.png.exe'),'');
  assert.throws(()=>ImageDocumentPolicy.info(1,1,10,'image/jpeg','.png'),/不一致/);
  for(const [width,height] of [[0,10],[Infinity,10],[40000,40000]])assert.throws(()=>ImageDocumentPolicy.info(width,height,10,'image/png','.png'),/尺寸/);
  assert.equal(ImageDocumentPolicy.isManaged('/sandbox','/sandbox/documents/../scan.png'),false);
});

test('large raster previews preserve aspect ratio within the pixel budget',()=>{
  const size=ImageDocumentPolicy.previewSize(8000,4000);assert.ok(size.width<=4096);assert.ok(size.width*size.height<=8*1024*1024);
  assert.ok(Math.abs(size.width/size.height-2)<0.002);assert.deepEqual(plain(ImageDocumentPolicy.previewSize(1,2)),{width:1,height:2});
});

test('image import preserves original bytes in a durable copy and closes all handles after validation',async()=>{
  const f=imageDocumentFixture(),result=await f.service.importFile(f.context,f.source,'scan.png');
  assert.ok(result.path.startsWith('/sandbox/files/documents/image_'));assert.deepEqual(f.files.get(result.path),f.bytes);assert.deepEqual(f.files.get(f.source),f.bytes);
  assert.equal(result.info.format,'PNG');assert.equal(f.opened.size,0);assert.ok(f.events.includes('source-release'));assert.ok(f.events.includes('pixels-release'));
  assert.equal(f.events.find(v=>Array.isArray(v)&&v[0]==='decode')[1].index,0);
});

for(const [name,option] of [['corrupt image','decodeError'],['short copy','shortCopy'],['too many pixels','huge'],['oversized file','largeFile']]) {
  test(`image import rejects ${name} and removes only its new copy`,async()=>{
    const f=imageDocumentFixture({[option]:true});await assert.rejects(f.service.importFile(f.context,f.source,'scan.png'));
    assert.deepEqual([...f.files.keys()],[f.source]);assert.deepEqual(f.files.get(f.source),f.bytes);assert.equal(f.opened.size,0);
  });
}

test('image export preserves the complete original rather than the zoomed preview',async()=>{
  const f=imageDocumentFixture(),imported=await f.service.importFile(f.context,f.source,'scan.png');
  const result=await f.service.exportOriginal(f.context,{title:'扫描页',sourceUri:imported.path});
  assert.equal(result.status,'exported');assert.deepEqual(f.files.get('file://export/image.png'),f.bytes);assert.deepEqual(f.files.get(imported.path),f.bytes);assert.ok(f.events.includes('sync'));assert.equal(f.opened.size,0);
});

for(const [name,option,status] of [['cancel','cancel','cancelled'],['short read','shortRead','failed'],['short write','shortWrite','failed']]) {
  test(`image export ${name} never claims success or changes its source`,async()=>{
    const f=imageDocumentFixture({[option]:true}),imported=await f.service.importFile(f.context,f.source,'scan.png');
    const result=await f.service.exportOriginal(f.context,{title:'图片',sourceUri:imported.path});assert.equal(result.status,status);
    assert.deepEqual(f.files.get(imported.path),f.bytes);assert.equal(f.opened.size,0);
    if(option!=='shortWrite')assert.equal(f.files.has('file://export/image.png'),false);
  });
}

test('image URI import publishes Image metadata only after the local source and index are saved',async()=>{
  const f=imageDocumentFixture(),writes=[];
  const method=viewMethod('services/NoteStorageService.ets','importDocumentUri',{ImageDocumentPolicy,ImageDocumentService:f.service,Error});
  const view={fileNameFromUri:()=> 'scan.png',isTextDocument:()=>false,ensureInitialized:async()=>{},
    noteFromImportedFile:(id,title,content)=>({id,title,contentDetail:content}),writeMarkdown:async(id,content)=>writes.push([id,content]),
    documentFor:(_,note,content)=>({id:note.id,title:note.title,content})};
  const result=await method.call(view,f.context,f.source);assert.equal(result.noteType,'Image');assert.ok(result.sourceUri.endsWith('.png'));assert.equal(writes.length,1);
  assert.deepEqual(f.files.get(result.sourceUri),f.bytes);assert.equal(JSON.parse(result.documentMeta).format,'PNG');
});

test('a failed image index save removes the unreferenced copy without touching the selected original',async()=>{
  const f=imageDocumentFixture();
  const method=viewMethod('services/NoteStorageService.ets','importDocumentUri',{ImageDocumentPolicy,ImageDocumentService:f.service,Error,fileIo:{unlink:async name=>f.files.delete(name)}});
  const view={fileNameFromUri:()=> 'scan.png',isTextDocument:()=>false,ensureInitialized:async()=>{},noteFromImportedFile:()=>({}),writeMarkdown:async()=>{throw Error('disk full');}};
  assert.equal((await method.call(view,f.context,f.source)).status,'failed');assert.deepEqual([...f.files.keys()],[f.source]);
});

test('image backup keeps bytes and format through restoration and refuses missing or unsafe image assets',async()=>{
  const f=backupFileFixture(),source='/sandbox/documents/photo.png',raw=Buffer.from('original-image-content');f.files.set(source,raw);
  const note=studyNote({id:'image_note',type:'Image',sourceType:'image',sourceUri:source,sourceFileName:'photo.png'});
  const backup=await f.service.create({filesDir:'/sandbox'},[note],[]);assert.equal(backup.assets[0].kind,'image');assert.equal(backup.assets[0].extension,'.png');
  const restored=await f.service.materialize({filesDir:'/sandbox'},backup,0,'副本');assert.equal(restored.sourceType,'image');assert.equal(restored.type,'Image');
  assert.deepEqual(f.files.get(restored.sourceUri),raw);assert.ok(restored.sourceUri.endsWith('.png'));
  const missing=plain(backup);missing.assets=[];assert.throws(()=>StudyBackupPolicy.validate(missing),/缺少原始图片/);
  const unsafe=plain(backup);unsafe.assets[0].extension='/../escape.png';assert.throws(()=>StudyBackupPolicy.validate(unsafe),/附件无效/);
});

test('late image decoding releases its bitmap without replacing another document page',async()=>{
  const requests=[],released=[],ready=[],ratios=[];
  const service={preview:(_,path)=>new Promise(resolve=>requests.push({path,resolve}))};
  const file='views/reader/pdf/PdfPageBackground.ets';
  const loadImage=viewMethod(file,'loadImage',{ImageDocumentService:service,Error});
  const view={sourceUri:'/a.png',requestId:0,visible:true,onSourceReady:value=>ready.push(value),
    onAspectRatio:value=>ratios.push(value),getUIContext:()=>({getHostContext:()=>({})})};
  const a=loadImage.call(view);view.sourceUri='/b.png';const b=loadImage.call(view);
  const pixel=id=>({release:async()=>released.push(id)});
  requests[1].resolve({pixels:pixel('b'),info:{width:20,height:10}});await b;const current=view.bitmap;
  requests[0].resolve({pixels:pixel('a'),info:{width:1,height:1}});await a;
  assert.equal(view.bitmap,current);assert.deepEqual(ratios,[2]);assert.deepEqual(ready,[true]);assert.deepEqual(released,['a']);
});

test('leaving an image page cancels decoding readiness and releases the eventual bitmap',async()=>{
  let resolve;const released=[],ready=[],file='views/reader/pdf/PdfPageBackground.ets';
  const service={preview:()=>new Promise(done=>{resolve=done;})};
  const view={sourceUri:'/a.png',requestId:0,visible:true,onSourceReady:value=>ready.push(value),
    onAspectRatio:()=>{throw Error('hidden page must not resize');},getUIContext:()=>({getHostContext:()=>({})})};
  const work=viewMethod(file,'loadImage',{ImageDocumentService:service,Error}).call(view);
  view.visible=false;viewMethod(file,'releaseBitmap').call(view);
  resolve({pixels:{release:async()=>released.push(true)},info:{width:10,height:10}});await work;
  assert.equal(view.bitmap,undefined);assert.equal(view.loading,false);assert.deepEqual(ready,[false]);assert.equal(released.length,1);
});

test('image decoding errors preserve the source and allow a later retry',async()=>{
  const file='views/reader/pdf/PdfPageBackground.ets',source='/files/documents/a.png',ready=[];
  const view={sourceUri:source,sourceType:'image',requestId:0,visible:true,
    onSourceReady:v=>ready.push(v),getUIContext:()=>({getHostContext:()=>({})})};
  await viewMethod(file,'loadImage',{ImageDocumentService:{preview:async()=>{throw Error('损坏图片');}},Error}).call(view);
  assert.equal(view.sourceUri,source);assert.equal(view.errorMessage,'损坏图片');assert.equal(view.loading,false);assert.deepEqual(ready,[false]);
});

test('imported images route to the full-screen viewer and cannot be updated as text notes',()=>{
  const image=studyNote({id:'picture',type:'Image',sourceType:'image',sourceUri:'/sandbox/documents/photo.png'});
  const isHeavy=viewMethod('pages/Index.ets','isHeavyDocument');assert.equal(isHeavy.call({},image),true);
  assert.throws(()=>WorkspaceNotePolicy.mutate(image,'update_note','replacement',image.updatedAt||0),/仅允许更新文字笔记/);
});

test('images always expose one annotation page and retain their original aspect ratio callback',()=>{
  const totals=[],published=[];
  const view={note:{id:'image',type:'Image',sourceType:'image',pageCount:999,title:'几何'},pageRatios:{0:0.707},
    pageDataSource:{setPages:pages=>published.push(pages)}};
  viewMethod('views/reader/pdf/PdfAnnotatorView.ets','initPages',{PdfDocumentService:{getInstance:()=>({generatePageModels:(total,title)=>{
    totals.push(total);return Array.from({length:total},(_,pageIndex)=>({pageIndex,title}));}})}}).call(view);
  assert.deepEqual(totals,[1]);assert.equal(view.pages.length,1);assert.equal(published[0].length,1);assert.deepEqual(plain(view.pageRatios),{});
});

test('image pages decode through the raster service and never invoke the PDF renderer',()=>{
  let imageLoads=0;
  const view={sourceType:'image',sourceUri:'/files/documents/image.png',errorMessage:'',loading:false,loadImage:()=>imageLoads++};
  viewMethod('views/reader/pdf/PdfPageBackground.ets','loadPage',{PdfDocumentService:{getInstance:()=>{throw Error('unexpected PDF decode');}}}).call(view);
  assert.equal(imageLoads,1);
});

for(const action of ['tab','closeTab','new']) {
  test(`reader ${action} waits for both ink commits and retains the current document on a failed save`,()=>{
    const file='views/reader/huawei/HuaweiDocWorkspace.ets',calls=[];
    const view={note:{id:'a'},loadedNoteId:'a',exitSaveToken:3,exitSaving:false,restoreSourceBusy:false,outputBusy:false,
      documentDirty:true,scratchpadDirty:true,isAnnotateMode:true,splitMode:'scratchpad',
      onSelectDocument:id=>calls.push(['tab',id]),onCloseDocumentTab:id=>calls.push(['closeTab',id]),onCreateHandwriting:()=>calls.push(['new']),onSaveStateChange(){},showToast(){}};
    view.beginReaderSave=viewMethod(file,'beginReaderSave');
    if(action==='new')viewMethod(file,'createDocument').call(view);else viewMethod(file,'requestDocument').call(view,action==='closeTab'?'a':'b',action==='closeTab');
    assert.deepEqual(calls,[]);assert.equal(view.exitPending,2);
    const finish=viewMethod(file,'exitSaveFinished');finish.call(view,true,'a',4,'document');assert.deepEqual(calls,[]);
    finish.call(view,false,'a',4,'scratchpad');assert.deepEqual(calls,[]);assert.equal(view.exitDialogOpen,true);
    view.beginReaderSave();finish.call(view,true,'a',4,'document');assert.equal(view.exitPending,2,'stale callbacks do not consume a retry');
    finish.call(view,true,'a',5,'document');finish.call(view,true,'a',5,'scratchpad');
    assert.equal(calls.length,1);assert.equal(calls[0][0],action);if(action!=='new')assert.equal(calls[0][1],action==='tab'?'b':'a');
  });
}

test('clearing image annotations needs confirmation and never writes to the original image source',async()=>{
  const file='views/reader/huawei/HuaweiDocWorkspace.ets',view={isAnnotateMode:true,exitSaving:false,penOptionsOpen:true,clearTrigger:0,
    usesCanvasTools:()=>false,clearCurrentPageAnnotations:viewMethod(file,'clearCurrentPageAnnotations')};
  viewMethod(file,'requestClearInk').call(view);assert.equal(view.clearDialogOpen,true);assert.equal(view.clearTrigger,0);
  view.clearDialogOpen=false;assert.equal(view.clearTrigger,0);
  viewMethod(file,'confirmClearInk').call(view);assert.equal(view.clearTrigger,1);assert.equal(view.clearDialogOpen,false);
  const {ReaderCommitService}=load(`${base}services/document/ReaderCommitService.ets`);
  const source=studyNote({id:'image',type:'Image',sourceType:'image',sourceUri:'/files/documents/a.jpg',contentDetail:'original text'});
  let notes=[source],documentWrites=0;
  await new ReaderCommitService().commit({...source,sourceUri:'/wrong.jpg',contentDetail:'wrong',pageAnnotations:'one-page-ink'},'wrong',{
    notes:()=>notes,saveDocument:async()=>documentWrites++,saveNotes:async()=>{},publish:values=>{notes=values;}
  },false,'pdf');
  assert.equal(notes[0].sourceUri,source.sourceUri);assert.equal(notes[0].contentDetail,'original text');assert.equal(notes[0].pageAnnotations,'one-page-ink');assert.equal(documentWrites,0);
});

for(const [orientation,expected] of [
  ['1',[0,false,false,false]],['Top-right',[0,true,false,false]],['3',[180,false,false,false]],['Bottom-left',[0,false,true,false]],
  ['Left-top',[270,true,false,true]],['6',[90,false,false,true]],['Right-bottom',[90,true,false,true]],['8',[270,false,false,true]]
]) {
  test(`raster EXIF orientation ${orientation} preserves pixels, upright aspect ratio and original bytes`,async()=>{
    const transform=ImageDocumentPolicy.orientation(orientation);
    assert.deepEqual([transform.rotate,transform.flipHorizontal,transform.flipVertical,transform.swapAxes],expected);
    const f=imageDocumentFixture({orientation,size:{width:200,height:100}});
    const result=await f.service.importFile(f.context,f.source,'scan.png');
    assert.equal(result.info.width,expected[3]?100:200);assert.equal(result.info.height,expected[3]?200:100);
    assert.deepEqual(f.files.get(f.source),f.bytes);assert.deepEqual(f.files.get(result.path),f.bytes);
    if(expected[0])assert.ok(f.events.some(v=>Array.isArray(v)&&v[0]==='rotate'&&v[1]===expected[0]));
    assert.equal(f.opened.size,0);
  });
}
test('missing EXIF metadata leaves a valid image usable and a failed transform releases its bitmap',async()=>{
  const f=imageDocumentFixture({exifError:true});assert.ok((await f.service.importFile(f.context,f.source,'scan.png')).path);
  const broken=imageDocumentFixture({orientation:'6',transformError:true});
  await assert.rejects(broken.service.importFile(broken.context,broken.source,'scan.png'));
  assert.ok(broken.events.includes('pixels-release'));assert.equal(broken.opened.size,0);assert.deepEqual([...broken.files.keys()],[broken.source]);
});

test('switching a long PDF tab to an image resets the visible page count and pending dialogs',()=>{
  const view={loadedNoteId:'pdf',note:{id:'image',type:'Image',sourceType:'image',pageCount:1},totalPages:549,currentPage:300,
    isImageDocument:()=>true,isHandwritingNote:()=>false,penOptionsOpen:true,clearDialogOpen:true,flushReadingProgress:async()=>{}};
  viewMethod('views/reader/huawei/HuaweiDocWorkspace.ets','onNoteChanged',{ReadingProgressPolicy}).call(view);
  assert.equal(view.totalPages,1);assert.equal(view.currentPage,1);assert.equal(view.penOptionsOpen,false);assert.equal(view.clearDialogOpen,false);
});

for(const action of ['search','extract']) {
  test(`reader ${action} saves both surfaces before opening another task`,()=>{
    const file='views/reader/huawei/HuaweiDocWorkspace.ets',calls=[];
    const view={loadedNoteId:'a',exitSaveToken:0,isAnnotateMode:true,documentDirty:true,scratchpadDirty:true,splitMode:'scratchpad',
      exitSaving:false,outputBusy:false,restoreSourceBusy:false,onSearchNotes:()=>calls.push('search'),onSmartExtract:()=>calls.push('extract'),onSaveStateChange(){},showToast(){}};
    view.beginReaderSave=viewMethod(file,'beginReaderSave');
    viewMethod(file,action==='search'?'openSearch':'openSmartExtract').call(view);assert.deepEqual(calls,[]);
    const finish=viewMethod(file,'exitSaveFinished');finish.call(view,true,'a',1,'document');assert.deepEqual(calls,[]);finish.call(view,true,'a',1,'scratchpad');
    assert.deepEqual(calls,[action]);
  });
}


const {WorkspaceLifecycle}=load(`${base}services/library/WorkspaceLifecycle.ets`);
const {MarkdownEditing,MarkdownHistory}=load(`${base}services/document/MarkdownEditing.ets`);

function lifecycleView(fail=false) {
  const notices=[],writes=[];const original=studyNote({id:'a',category:'课程'});
  const view={notes:[original],customProjects:[{id:'course',name:'课程',count:1,isOpen:true,children:[]}],trash:[],trashedProjects:[],
    readerTabIds:['a'],readingNote:original,fullScreenDocNote:{id:''},activeNoteId:'a',activeSpaceId:'course',saveState:'已保存',
    noteMutationQueue:{run:task=>task()},getAbilityContext:()=>({}),rebuildSpaces(){this.spaces=this.customProjects.slice();},refreshGraph(){},
    storage:{saveWorkspace:async(...args)=>{if(fail)throw Error('disk full');writes.push(plain(args.slice(1)));}},
    notify:m=>notices.push(m),notifyUndoable:m=>notices.push(m)};
  for(const name of ['workspaceState','commitWorkspace','deleteProject','restoreTrashedProject','deleteNote','restoreFromTrashById']) {
    view[name]=viewMethod('pages/Index.ets',name,{WorkspaceLifecycle,SAVE_IDLE:'已保存'});
  }
  return {view,notices,writes,original};
}

test('actual project delete publishes only a successful workspace transaction and restores the whole folder',async()=>{
  const {view,writes}=lifecycleView();await view.deleteProject('课程');
  assert.equal(writes.length,1);assert.equal(view.notes.length,0);assert.equal(view.customProjects.length,0);assert.equal(view.trash.length,1);
  assert.equal(view.spaces.length,0);assert.equal(view.activeNoteId,'');assert.equal(view.activeSpaceId,'');assert.equal(view.readerTabIds.length,0);
  await view.restoreTrashedProject(view.trashedProjects[0].id);assert.equal(view.notes.length,1);assert.equal(view.customProjects.length,1);assert.equal(view.trash.length,0);
});

test('failed project deletion retains all state and never reports a successful delete',async()=>{
  const {view,notices,original}=lifecycleView(true);const before=view.customProjects;await view.deleteProject('课程');
  assert.equal(view.notes[0],original);assert.equal(original.deletedAt,undefined);assert.equal(view.customProjects,before);assert.equal(view.trash.length,0);
  assert.equal(notices.length,1);assert.match(notices[0],/失败|disk/);
});

test('unclassified import returns to the library and clears stale project and search filters',async()=>{
  const view={spaces:[],documentImportBusy:false,activeNav:'首页',activeSpaceId:'old',searchText:'old',activeFilter:'PDF',getAbilityContext:()=>({}),
    storage:{selectDocumentUris:async()=>['book']},notify(){},importOneDocument:async()=>({id:'book'})};
  const result=await viewMethod('pages/Index.ets','importDocument').call(view);
  assert.equal(result.id,'book');assert.equal(view.activeNav,'资料库');assert.equal(view.activeSpaceId,'');assert.equal(view.searchText,'');assert.equal(view.activeFilter,'全部');
});

test('metadata writes fail without mutating live notes or reporting success',async()=>{
  const original=studyNote({favorite:false});const notices=[];
  const view={notes:[original],findNoteById:()=>original,noteMutationQueue:{run:fn=>fn()},saveLinkedNote:async()=>{throw Error('disk');},notify:m=>notices.push(m)};
  view.updateNoteMetadata=viewMethod('pages/Index.ets','updateNoteMetadata');
  await viewMethod('pages/Index.ets','toggleFavorite').call(view,original);assert.equal(original.favorite,false);assert.equal(notices.length,1);assert.match(notices[0],/失败|disk/);
});

test('todo dialog keeps its input on a failed save and ignores a second submit while pending',async()=>{
  const commit=viewMethod('views/workspace/TodoEditDialog.ets','commit');let release,calls=0;
  const view={titleInput:'课程复习',selected:['n'],saving:false,saveError:'',onSave:()=>{calls++;return new Promise(resolve=>release=resolve);}};
  const pending=commit.call(view);await commit.call(view);assert.equal(calls,1);release(false);await pending;
  assert.equal(view.titleInput,'课程复习');assert.deepEqual(view.selected,['n']);assert.match(view.saveError,/输入已保留/);assert.equal(view.saving,false);
});

test('Markdown exit waits for the active save and commits input that arrived during that save',async()=>{
  const globals={SAVE_IDLE:'已保存',SAVE_FAILED:'保存失败'};
  const flush=viewMethod('views/reader/MarkdownReader.ets','flushSave',globals),commit=viewMethod('views/reader/MarkdownReader.ets','commitSnapshot',globals);
  let release;const writes=[];const view={saveTimer:-1,saveInFlight:null,isDirty:true,title:'标题',content:'first',editingNote:{id:'a'},saveState:'保存中',
    buildSnapshot:()=>({id:'a',title:view.title,contentDetail:view.content}),onSaved:async note=>{writes.push(note.contentDetail);if(writes.length===1)await new Promise(r=>release=r);},onSaveStateChange(){}};
  view.flushSave=flush;view.commitSnapshot=commit;const initial=flush.call(view);await Promise.resolve();
  view.content='latest';view.isDirty=true;const exit=flush.call(view);release();await Promise.all([initial,exit]);
  assert.deepEqual(writes,['first','latest']);assert.equal(view.isDirty,false);assert.equal(view.saveState,'已保存');
  view.isDirty=true;view.onSaved=async()=>{throw Error('disk');};await flush.call(view);assert.equal(view.isDirty,true);assert.equal(view.saveState,'保存失败');
});

test('Markdown keyboard commands are consumed before native text history and do not handle ordinary typing',()=>{
  const calls=[],KeyCode={KEYCODE_Z:1,KEYCODE_Y:2,KEYCODE_B:3,KEYCODE_I:4,KEYCODE_S:5};
  const key=viewMethod('views/reader/MarkdownReader.ets','handleEditorKey',{KeyCode,KeyType:{Down:0}});
  const view={undoEdit:redo=>calls.push(['undo',redo]),handleFormatAction:action=>calls.push(action),flushSave:()=>calls.push('save')};
  assert.equal(key.call(view,{keyCode:3,type:0,getModifierKeyState:keys=>keys.includes('Ctrl')}),true);
  assert.equal(key.call(view,{keyCode:1,type:0,getModifierKeyState:()=>true}),true);
  assert.equal(key.call(view,{keyCode:5,type:0,getModifierKeyState:keys=>keys.includes('Ctrl')}),true);
  assert.equal(key.call(view,{keyCode:3,type:0,getModifierKeyState:()=>false}),false);
  assert.deepEqual(calls,['bold',['undo',true],'save']);
});

test('Markdown links are displayed without executing markup or promoting unsafe URL schemes',()=>{
  const spans=DocumentTextParser.spans('参考 [官网](https://example.com/docs) 与 [文本](javascript:alert) 和 `[代码](https://example.com)`');
  assert.equal(spans.filter(span=>span.target).length,1);assert.equal(spans.find(span=>span.target).text,'官网');
  assert.ok(spans.some(span=>span.style==='code'&&span.text.includes('[代码]')));
});


test('an import resolves a renamed project by ID and never resurrects a deleted folder',async()=>{
  const importing=viewMethod('pages/Index.ets','importOneDocument');
  for(const spaces of [[],[{id:'stable',name:'新项目名'}]]) {
    const view={spaces,notes:[],noteMutationQueue:{run:fn=>fn()},getAbilityContext:()=>({}),
      storage:{importDocumentUri:async()=>({status:'imported',noteType:'Markdown',document:{id:'imported',title:'文件',content:'原文'}}),save:async()=>{}},
      formatTime:()=>'',rebuildSpaces(){},refreshGraph(){},notify(){}};
    const note=await importing.call(view,'旧项目名',false,false,'source','stable');
    assert.equal(note.category,spaces.length?'新项目名':'未分类');
  }
});

test('cover preparation cannot revert an edit that completed before its queued commit',async()=>{
  let release;const first=studyNote({id:'cover',title:'old',contentDetail:'old'});const calls=[];
  const view={notes:[first],trash:[],getAbilityContext:()=>({}),noteMutationQueue:{run:fn=>fn()},
    findNoteById:id=>view.notes.find(note=>note.id===id),saveLinkedNote:async note=>{calls.push(note);view.notes=[note];},notify(){}};
  const method=viewMethod('pages/Index.ets','updateNoteCover',{NoteCoverService:{prepare:()=>new Promise(resolve=>release=resolve),removeManaged:async()=>{}}});
  const pending=method.call(view,'cover','picked');view.notes=[{...first,title:'latest',contentDetail:'latest body'}];release('/cover/new.png');await pending;
  assert.equal(calls[0].title,'latest');assert.equal(calls[0].contentDetail,'latest body');assert.equal(calls[0].coverUrl,'/cover/new.png');
});

test('startup initialization always releases its loading state and reports unexpected failures',async()=>{
  const bootstrap=viewMethod('pages/Index.ets','bootstrap');const messages=[];
  const view={workspaceLoading:true,loadWorkspace:async()=>{throw Error('startup');},notify:message=>messages.push(message)};
  await bootstrap.call(view);assert.equal(view.workspaceLoading,false);assert.equal(messages.length,1);assert.match(messages[0],/初始化未完成/);
});


test('the text reader combines independent body and scratchpad save states without hiding pending work',()=>{
  const statuses=[];const update=viewMethod('views/reader/ReaderWorkspace.ets','updateSaveState',{SAVE_IDLE:'已保存',SAVE_SAVING:'保存中'});
  const view={textState:'已保存',inkState:'已保存',onSaveStateChange:state=>statuses.push(state)};
  update.call(view,'text','保存中');update.call(view,'ink','已保存');assert.equal(statuses.at(-1),'保存中');
  update.call(view,'text','保存失败');update.call(view,'ink','已保存');assert.equal(statuses.at(-1),'保存失败');
  update.call(view,'text','已保存');update.call(view,'ink','笔迹无法保存');assert.equal(statuses.at(-1),'笔迹无法保存');
});

test('closing the text scratchpad waits for its matching save result and retains the panel on failure',()=>{
  const finished=viewMethod('views/reader/ReaderWorkspace.ets','inkExitFinished',{SAVE_IDLE:'已保存',SAVE_FAILED:'保存失败'});
  const save=viewMethod('views/reader/ReaderWorkspace.ets','saveInkBeforeLeaving');const calls=[];
  const view={note:{id:'a'},inkExitToken:0,closingInk:false,inkDestination:'',updateSaveState:(...args)=>calls.push(args),onBack:()=>calls.push('back'),onToggleAnnotation:()=>calls.push('toggle')};
  save.call(view,'pane');save.call(view,'pane');assert.equal(view.inkExitToken,1);assert.equal(calls.length,0);
  finished.call(view,true,'other',1);assert.equal(view.closingInk,true);
  finished.call(view,false,'a',1);assert.equal(view.closingInk,false);assert.equal(calls.includes('toggle'),false);
  save.call(view,'pane');finished.call(view,true,'a',2);assert.equal(calls.at(-1),'toggle');
});

test('navigation cannot destroy a reader whose save is pending or has failed',()=>{
  const navigation=viewMethod('pages/Index.ets','afterSettingsExit',{SAVE_IDLE:'已保存',NAV_SETTINGS:'设置'});
  let invoked=0;const notices=[];const view={readingOpen:true,fullScreenDocOpen:false,saveState:'保存中',activeNav:'资料库',notify:message=>notices.push(message)};
  navigation.call(view,()=>invoked++);view.saveState='保存失败';navigation.call(view,()=>invoked++);assert.equal(invoked,0);assert.equal(notices.length,2);
  view.saveState='已保存';navigation.call(view,()=>invoked++);assert.equal(invoked,1);
});

test('generic pairing preserves pane order for every supported format and rejects deleted or duplicate documents',()=>{
  const types=['PDF','Markdown','Image','Handwriting','Canvas'];
  for(const a of types)for(const b of types){
    assert.deepEqual(plain(ReaderPairPolicy.pair(studyNote({id:'left',type:a}),studyNote({id:'right',type:b}))),{primaryId:'left',secondaryId:'right'});
  }
  assert.throws(()=>ReaderPairPolicy.pair(studyNote({id:'same'}),studyNote({id:'same'})));
  for(const other of [studyNote({deletedAt:1}),studyNote({type:'EPUB'}),studyNote({type:'Markdown',sourceType:'doc'})]){
    assert.throws(()=>ReaderPairPolicy.pair(studyNote({id:'pdf',type:'PDF'}),other));
  }
});

test('opening a ninth tab for a split retains both visible documents and stable order of remaining tabs',()=>{
  const original=Array.from({length:8},(_,i)=>String(i));
  assert.deepEqual(Array.from(ReaderPairPolicy.rememberTabs(original,'0','8')),['0','2','3','4','5','6','7','8']);
  assert.deepEqual(original,Array.from({length:8},(_,i)=>String(i)));
  assert.deepEqual(Array.from(ReaderPairPolicy.rememberTabs(['a','a','b'],'a','b')),['a','b']);
});

test('pair selection searches actual title and project, sorts stably and leaves the library order intact',()=>{
  const pdf=studyNote({id:'pdf',type:'PDF'}),md=id=>studyNote({id,type:'Markdown',title:`课程 ${id}`,category:'数学',updatedAt:100});
  const notes=[md('b'),pdf,md('a'),md('c'),{...md('gone'),deletedAt:1},studyNote({id:'image',type:'Image'})];
  const before=plain(notes);
  assert.deepEqual(plain(ReaderPairPolicy.candidates(notes,pdf,' 数学 ')).map(n=>n.id),['a','b','c']);
  assert.deepEqual(plain(ReaderPairPolicy.candidates(notes,pdf,'课程 b')).map(n=>n.id),['b']);
  assert.deepEqual(plain(ReaderPairPolicy.candidates(notes,notes[0],'')).map(n=>n.id),['a','c','image','pdf']);
  assert.deepEqual(plain(notes),before);
});

for(const sourceId of ['pdf','md']) {
  test(`opening a pair from ${sourceId} retains the requested primary pane and separate save ownership`,async()=>{
    const pdf=studyNote({id:'pdf',type:'PDF'}),md=studyNote({id:'md',type:'Markdown'}),events=[];
    const view={notes:[pdf,md],saveState:'已保存',pairPickerSourceId:sourceId,readerTabIds:[sourceId],fullScreenDocOpen:false,fullScreenDocNote:{id:''},
      recordReading:async id=>events.push(['read',id]),openNote:note=>{events.push(['open',note.id]);view.fullScreenDocOpen=true;view.fullScreenDocNote=note;}};
    assert.equal(await viewMethod('pages/Index.ets','selectReaderPair').call(view,sourceId==='pdf'?'md':'pdf'),true);
    const otherId=sourceId==='pdf'?'md':'pdf';
    assert.equal(view.companionNoteId,otherId);assert.deepEqual(events,[['read',otherId],['open',sourceId]]);
  });
}

test('late pair selection revalidates both documents and save state before changing the reader',async()=>{
  const select=viewMethod('pages/Index.ets','selectReaderPair');
  for(const change of ['removePdf','removeMarkdown','wrongFormat','dirty','differentPicker']) {
    const view={notes:[studyNote({id:'pdf',type:'PDF'}),studyNote({id:'md',type:'Markdown'})],saveState:'已保存',pairPickerSourceId:'pdf',
      fullScreenDocOpen:true,fullScreenDocNote:{id:'pdf'},companionNoteId:'',openNote(){throw Error('unexpected navigation');},
      recordReading:async()=>{
        if(change==='removePdf')view.notes=view.notes.filter(n=>n.id!=='pdf');
        if(change==='removeMarkdown')view.notes=view.notes.filter(n=>n.id!=='md');
        if(change==='wrongFormat')view.notes[1]={...view.notes[1],type:'EPUB'};
        if(change==='dirty')view.saveState='保存中';
        if(change==='differentPicker')view.pairPickerSourceId='md';
      }};
    await assert.rejects(select.call(view,'md'));assert.equal(view.companionNoteId,'');
  }
});

function splitReaderHarness(){
  const events=[],view={note:{id:'left'},secondaryNote:{id:'right'},states:new Map(),expected:new Set(),saveToken:0,busy:false,
    onSaveStateChange:state=>events.push(state)};
  for(const method of ['updateState','saveBefore','saved','dropDocument'])view[method]=viewMethod('views/reader/ReaderSplitWorkspace.ets',method,{promptAction:{showToast(){}}});
  return {view,events};
}

test('split save state retains a failed or pending pane when the other pane reports idle',()=>{
  const {view,events}=splitReaderHarness();view.updateState('right','保存中');view.updateState('left','已保存');assert.equal(events.at(-1),'保存中');
  view.updateState('right','保存失败');view.updateState('left','已保存');assert.equal(events.at(-1),'保存失败');
});

test('split navigation waits for distinct document IDs and rejects duplicate or obsolete callbacks',()=>{
  const {view}=splitReaderHarness();let changed=0;view.saveBefore(()=>changed++);
  view.saved(true,'left',1);view.saved(true,'left',1);view.saved(true,'old',1);view.saved(true,'right',0);
  assert.equal(changed,0);assert.equal(view.expected.size,1);view.saved(true,'right',1);assert.equal(changed,1);assert.equal(view.busy,false);
});

test('failed split save retains both documents and retry cannot be completed by an old acknowledgement',()=>{
  const {view}=splitReaderHarness();let changed=0;view.saveBefore(()=>changed++);view.saved(false,'left',1);view.saved(true,'right',1);
  assert.equal(changed,0);assert.equal(view.failed,true);assert.equal(view.secondaryNote.id,'right');
  view.saveBefore(view.pendingAction);view.saved(true,'left',1);assert.equal(view.expected.size,2);
  view.saved(true,'right',2);view.saved(true,'left',2);assert.equal(changed,1);assert.equal(view.failed,false);
});

test('dragging an actual tab into the drop zone waits for both saves and rejects self or foreign IDs',()=>{
  const {view}=splitReaderHarness(),opened=[];view.documentTabs=[{id:'left'},{id:'right'}];view.onSplitDocument=id=>opened.push(id);
  for(const id of ['left','foreign','']){view.draggedId=id;view.dropDocument();assert.equal(view.busy,false);}
  view.draggedId='right';view.dropDocument();assert.equal(view.draggedId,'');assert.deepEqual(opened,[]);
  view.saved(true,'left',1);view.saved(true,'right',1);assert.deepEqual(opened,['right']);
});

test('opening a pair from the text reader waits for its scratchpad and never clears its content',()=>{
  const file='views/reader/ReaderWorkspace.ets',calls=[];
  const view={note:{id:'md'},annotationPaneOpen:true,closingInk:false,inkExitToken:0,onOpenCompanion:()=>calls.push('pair'),updateSaveState(){}};
  view.saveInkBeforeLeaving=viewMethod(file,'saveInkBeforeLeaving');viewMethod(file,'requestCompanion').call(view);
  assert.equal(view.inkDestination,'companion');assert.deepEqual(calls,[]);
  viewMethod(file,'inkExitFinished').call(view,true,'md',1);assert.deepEqual(calls,['pair']);
});

test('host-requested Markdown save acknowledges only persisted content belonging to the current request',async()=>{
  const save=viewMethod('views/reader/MarkdownReader.ets','saveForHost');
  for(const result of ['ok','failed','loading','sharing','staleToken','staleNote']) {
    const events=[];const view={loadedNoteId:'md',saveRequestToken:7,isDirty:true,documentLoading:false,saveState:'保存中',
      onSaveRequestFinished:(...args)=>events.push(args),flushSave:async()=>{
        view.isDirty=false;view.saveState='已保存';
        if(result==='failed'){view.isDirty=true;view.saveState='保存失败';}
        if(result==='loading')view.documentLoading=true;
        if(result==='sharing')view.shareBusy=true;
        if(result==='staleToken')view.saveRequestToken++;
        if(result==='staleNote')view.loadedNoteId='other';
      }};
    await save.call(view);assert.deepEqual(events,[[result==='ok','md',7]]);
  }
});

test('Markdown back saves and exits in one action, while a failed write preserves the editor',async()=>{
  for(const success of [true,false]) {
    const events=[],view={isEditing:true,isDirty:true,documentLoading:false,exitEdit:()=>events.push('finish-edit'),
      flushSave:async()=>{events.push('save');view.isDirty=!success;},onRequestClose:()=>events.push('close')};
    await viewMethod('views/reader/MarkdownReader.ets','handleBackRequest').call(view);
    assert.deepEqual(events,success?['finish-edit','save','close']:['finish-edit','save']);
  }
});

test('concurrent PDF ink and companion Markdown commits never overwrite the other document or their metadata',async()=>{
  const {ReaderCommitService}=load(`${base}services/document/ReaderCommitService.ets`),service=new ReaderCommitService();
  let notes=[studyNote({id:'pdf',type:'PDF',pageAnnotations:'old ink',favorite:true}),studyNote({id:'md',type:'Markdown',contentDetail:'old body',category:'数学'})];
  const bodies=[],ports={notes:()=>notes,saveNotes:async()=>{},saveDocument:async(note,text)=>bodies.push([note.id,text]),publish:items=>{notes=items;}};
  await Promise.all([service.commit({...notes[0],pageAnnotations:'new ink',favorite:false},'',ports,true,'pdf'),
    service.commit({...notes[1],title:'新标题',contentDetail:'new body'},'new body',ports,true,'markdown')]);
  assert.equal(notes[0].pageAnnotations,'new ink');assert.equal(notes[0].favorite,true);
  assert.equal(notes[1].contentDetail,'new body');assert.equal(notes[1].category,'数学');assert.equal(notes[1].title,'新标题');
  assert.deepEqual(bodies.map(([id])=>id).filter(id=>id==='md'),['md']);
});

test('closing a PDF tab preserves its Markdown companion for the next PDF and clears it only on final exit',()=>{
  const close=viewMethod('pages/Index.ets','closeReaderTab'),opened=[];
  const next=studyNote({id:'next',type:'PDF'}),view={readerTabIds:['pdf','next'],fullScreenDocOpen:true,
    fullScreenDocNote:{id:'pdf'},companionNoteId:'md',activeNoteId:'pdf',saveState:'已保存',
    readerDocuments:()=>view.readerTabIds.map(id=>({id,type:'PDF'})),openNote:(note,preserve)=>opened.push([note.id,preserve])};
  close.call(view,'pdf');assert.deepEqual(opened,[['next',true]]);assert.equal(view.companionNoteId,'md');
  view.fullScreenDocNote=next;close.call(view,'next');assert.equal(view.fullScreenDocOpen,false);assert.equal(view.companionNoteId,'');
});

test('opening the same PDF or closing its tab cannot unmount a companion with pending or failed changes',()=>{
  for(const state of ['保存中','保存失败']) {
    const notices=[],view={readerTabIds:['pdf'],fullScreenDocOpen:true,readingOpen:false,fullScreenDocNote:{id:'pdf'},activeNoteId:'pdf',
      companionNoteId:'md',saveState:state,notify:m=>notices.push(m)};
    viewMethod('pages/Index.ets','openNote').call(view,{id:'pdf'});viewMethod('pages/Index.ets','closeReaderTab').call(view,'pdf');
    assert.equal(view.fullScreenDocOpen,true);assert.equal(view.companionNoteId,'md');assert.deepEqual(view.readerTabIds,['pdf']);assert.equal(notices.length,2);
  }
});

test('external body mutations cannot overwrite the Markdown currently open alongside a PDF',async()=>{
  const md=studyNote({id:'md',type:'Markdown'}),view={notes:[md],readingOpen:false,fullScreenDocOpen:true,
    fullScreenDocNote:{id:'pdf'},companionNoteId:'md',getAbilityContext:()=>({}),storage:{saveDocument(){throw Error('unexpected body overwrite');}}};
  await assert.rejects(viewMethod('pages/Index.ets','saveLinkedNote').call(view,{...md,contentDetail:'external'},true),/先结束当前笔记编辑/);
  assert.equal(view.notes[0].contentDetail,md.contentDetail);
});

test('library actions resolve the latest live note and ignore a removed or deleted item',()=>{
  const open=viewMethod('pages/Index.ets','openNoteMenu'),notices=[];
  const view={notes:[studyNote({id:'a',title:'最新标题'})],sheetProject:{id:'old'},activeSheet:'',notify:m=>notices.push(m)};
  open.call(view,{id:'a',title:'旧标题'});assert.equal(view.sheetNote.title,'最新标题');assert.equal(view.activeSheet,'note_menu');assert.equal(view.sheetProject,null);
  view.activeSheet='';view.notes=[];open.call(view,{id:'a'});assert.equal(view.activeSheet,'');assert.equal(notices.length,1);
});

test('classification choices include unclassified and empty projects without duplicates',()=>{
  const view={spaces:[{name:'空项目'},{name:'数学'}],notes:[{category:'数学'},{category:'历史遗留分类'},{category:''}]};
  assert.deepEqual(Array.from(viewMethod('pages/Index.ets','allCategories').call(view)),['未分类','空项目','数学','历史遗留分类']);
});

test('shared reader tabs retain the Markdown shell and its context features when opening text documents',()=>{
  const {WorkspaceNotePolicy}=load(`${base}services/WorkspaceNotePolicy.ets`);
  const md=studyNote({id:'md',type:'Markdown'}),pdf=studyNote({id:'pdf',type:'PDF'});
  const view={notes:[md,pdf],readerTabIds:[],activeNav:'资料库',saveState:'已保存',readingOpen:false,fullScreenDocOpen:false,
    recordReading:async()=>{},dismissNavigationOverlay(){},notify(){},isHeavyDocument:viewMethod('pages/Index.ets','isHeavyDocument')};
  const open=viewMethod('pages/Index.ets','openNote',{WorkspaceNotePolicy,ReadingProgressPolicy,NAV_SETTINGS:'设置',
    PdfDocumentService:{getInstance:()=>({clearPageCache(){}})},
    AnimationTokens:{DURATION_FAST:1,DURATION_PAGE_TRANSITION:2,CURVE_STANDARD:'linear'},animateTo:(_,apply)=>apply()});
  open.call(view,md);assert.equal(view.readingOpen,true);assert.equal(view.fullScreenDocOpen,false);assert.equal(view.readingNote.id,'md');
  assert.deepEqual(Array.from(view.readerTabIds),['md']);assert.deepEqual(Array.from(view.outlineItems),[]);
  open.call(view,pdf);assert.equal(view.readingOpen,false);assert.equal(view.fullScreenDocOpen,true);assert.equal(view.fullScreenDocNote.id,'pdf');
  assert.deepEqual(Array.from(view.readerTabIds),['md','pdf']);
});

test('rename and move report persistence failure to their forms instead of reporting success',async()=>{
  for(const method of ['commitRename','commitMove']){
    const messages=[],view={updateNoteMetadata:async()=>null,notify:m=>messages.push(m),formatTime:()=>''};
    assert.equal(await viewMethod('pages/Index.ets',method).call(view,{id:'a'},'新名称'),false);assert.deepEqual(messages,[]);
    view.updateNoteMetadata=async(id,change)=>{const next={id};change(next);return next;};
    assert.equal(await viewMethod('pages/Index.ets',method).call(view,{id:'a'},'新名称'),true);assert.equal(messages.length,1);
  }
});

test('scratchpad loading yields to the UI and cannot replace a newer canvas after a delayed decode',async()=>{
  let finish;const read=viewMethod('views/reader/HandwritingCanvas.ets','readStrokes',{CanvasStrokeLoader:{load:()=>new Promise(r=>finish=r)}});
  const view={note:{id:'old'},loadGeneration:1,strokes:[],loadingInk:true,onContentReady(){throw Error('stale readiness');},requestRedraw(){throw Error('stale repaint');}};
  const pending=read.call(view,'raw','old',1);assert.equal(view.loadingInk,true);
  view.note={id:'new'};view.loadGeneration=2;finish([validWhiteboardStroke()]);await pending;
  assert.deepEqual(view.strokes,[]);assert.equal(view.loadingInk,true);
});

test('canvas decoding uses the worker for actual ink and keeps empty scratchpad opening cheap',async()=>{
  const calls=[];const {CanvasStrokeLoader}=load(`${base}services/ink/CanvasStrokeLoader.ets`,{'@kit.ArkTS':{taskpool:{execute:async(fn,raw)=>{calls.push(raw);return fn(raw);}}}});
  for(const raw of [undefined,'','[]'])assert.deepEqual(plain(await CanvasStrokeLoader.load(raw)),[]);
  assert.deepEqual(calls,[]);const raw=JSON.stringify([validWhiteboardStroke()]);
  assert.deepEqual(plain(await CanvasStrokeLoader.load(raw)),[validWhiteboardStroke()]);assert.deepEqual(calls,[raw]);
});

test('returning during scratchpad loading waits for real data before acknowledging and never writes an empty snapshot',async()=>{
  let finish;const events=[];const view={note:{id:'a'},loadedNoteId:'a',exitSaveToken:3,loadInFlight:new Promise(r=>finish=r),saveRevision:0,savedRevision:0,
    saveTimer:-1,finishStroke(){},onDirtyChange(){},onExitSaveFinished:(...args)=>events.push(args),strokeSnapshot(){throw Error('unexpected empty write');}};
  const saving=viewMethod('views/reader/HandwritingCanvas.ets','saveForExit').call(view);assert.deepEqual(events,[]);
  finish();await saving;assert.deepEqual(events,[[true,'a',3]]);
});

test('an untouched scratchpad can close immediately during background decoding without rewriting its original bytes',async()=>{
  const raw=JSON.stringify([validWhiteboardStroke()]),events=[];
  const view={note:{id:'a',scratchpadStrokes:raw},isScratchpad:true,loadedNoteId:'a',loadedRaw:raw,loadGeneration:1,loadingInk:true,
    saveRevision:0,exitSaveToken:2,loadInFlight:new Promise(()=>{}),onExitSaveFinished:(...args)=>events.push(args),
    finishStroke(){throw Error('must not reconstruct unloaded ink');}};
  await viewMethod('views/reader/HandwritingCanvas.ets','saveForExit').call(view);assert.deepEqual(events,[[true,'a',2]]);
  assert.equal(view.note.scratchpadStrokes,raw);
});

test('an empty scratchpad paints only paper and skips offscreen bitmap allocation',()=>{
  const calls=[],view={context:{clearRect:()=>calls.push('clear')},viewportReady:true,canvasWidth:600,canvasHeight:800,drawTimer:-1,
    strokes:[],currentStroke:null,drawPaperBackground:()=>calls.push('paper'),inkFrame:{release:()=>calls.push('release'),render(){throw Error('empty bitmap allocation');}}};
  viewMethod('views/reader/HandwritingCanvas.ets','redrawAll').call(view);assert.deepEqual(calls,['paper','clear','release']);
});

test('text pane host save waits for body and scratchpad and reports the same host request once',()=>{
  const file='views/reader/ReaderWorkspace.ets',acks=[];const view={note:{id:'md'},hostSaveToken:5,textSaveToken:0,inkExitToken:0,
    closingText:false,closingInk:false,annotationPaneOpen:true,updateSaveState(){},onHostSaveFinished:(...args)=>acks.push(args)};
  view.saveInkBeforeLeaving=viewMethod(file,'saveInkBeforeLeaving');viewMethod(file,'saveForHost').call(view);
  viewMethod(file,'textSaveFinished').call(view,true,'md',1);assert.equal(view.inkDestination,'host');assert.deepEqual(acks,[]);
  viewMethod(file,'inkExitFinished').call(view,true,'md',1);assert.deepEqual(acks,[[true,'md',5]]);
});
