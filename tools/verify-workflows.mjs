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
const parserFile = `${base}services/ai/AiParser.ets`;
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
    if (specifier === 'BuildProfile') return { DEBUG: true };
    if (specifier.startsWith('.')) {
      return load(path.resolve(path.dirname(filename), `${specifier}.ets`), mocks, cache);
    }
    throw new Error(`Unmocked platform dependency: ${specifier}`);
  };
  vm.runInNewContext(output, { module, exports: module.exports, require: localRequire,
    console, Date, Error, Promise, setTimeout: mocks.setTimeout || setTimeout, clearTimeout: mocks.clearTimeout || clearTimeout,
    canIUse: mocks.canIUse || (() => true), AppStorage: mocks.AppStorage,
    SourceTool: mocks.SourceTool, TouchType: mocks.TouchType, Curve: mocks.Curve || { EaseInOut: 'ease' } }, { filename });
  return module.exports;
}

const { AiParser } = load(parserFile);
const { SmartNoteBuilder } = load(builderFile);
const { SmartCaptureService } = load(`${base}services/smart/SmartCaptureService.ets`);
const { ChatSessionSanitizer } = load(`${base}services/ai/ChatSessionSanitizer.ets`);
const plain = value => JSON.parse(JSON.stringify(value));
const reference = new Date(2026, 8, 30, 10);
const source = '【美术课通知】\n2026年10月2日前提交素描作业。\n已经完成报名，无需准备额外材料。\n地点：画室二楼。';

const { ModelProfilePolicy } = load(`${base}services/ai/ModelProfilePolicy.ets`);
const { ToolArgumentValidator } = load(`${base}services/ai/ToolArgumentValidator.ets`);
const { AGENT_TOOLS } = load(`${base}services/ai/ToolRegistry.ets`);
const { WorkspaceToolExecutor } = load(`${base}services/ai/WorkspaceToolExecutor.ets`);
const { ActionProposalService } = load(`${base}services/ai/ActionProposalService.ets`);
const { NoteToolReader } = load(`${base}services/ai/NoteToolReader.ets`);
const profile = overrides => ({ id: 'study', label: '学习', protocol: 'openai-compat', baseUrl: 'https://example.com/v1',
  apiKey: 'test-key', modelId: 'test-model', temperature: 0.7, maxTokens: 4096, stream: true,
  systemPrompt: '', createdAt: 1, updatedAt: 1, ...overrides });

test('model validation rejects incomplete or unsafe endpoints and invalid numeric configuration', () => {
  assert.equal(ModelProfilePolicy.validate(profile()), '');
  for (const change of [{ label: '' }, { apiKey: '' }, { baseUrl: 'https://key@example.com/v1' },
    { baseUrl: 'https://example.com/v1?key=secret' }, { baseUrl: 'file:///notes' },
    { modelId: '' }, { temperature: NaN }, { temperature: 3 }, { maxTokens: 10 },
    { maxTokens: 1024.5 }, { maxToolRounds: 7 }]) {
    assert.notEqual(ModelProfilePolicy.validate(profile(change)), '', JSON.stringify(change));
  }
  assert.equal(ModelProfilePolicy.validate(profile({ baseUrl: 'http://127.0.0.1:11434/v1', apiKey: '' })), '');
});

test('model restoration isolates malformed rows and preserves user model IDs', () => {
  assert.equal(ModelProfilePolicy.restore(null), null);
  assert.equal(ModelProfilePolicy.restore({ id: 'bad', label: 'bad', protocol: 'invalid' }), null);
  const restored = ModelProfilePolicy.restore(profile({ modelId: 'my-model', apiKey: '***broken', maxTokens: -8,
    temperature: null, maxToolRounds: 'bad', stream: false }));
  assert.equal(restored.modelId, 'my-model'); assert.equal(restored.apiKey, '');
  assert.equal(restored.maxTokens, 8192); assert.equal(restored.stream, false); assert.equal(restored.maxToolRounds, 5);
});

test('tool configuration limits actual capabilities by protocol, stream and permission', () => {
  assert.equal(ModelProfilePolicy.availableTools(profile({ toolAccess: 'none' }), AGENT_TOOLS).length, 0);
  assert.equal(ModelProfilePolicy.availableTools(profile({ stream: false }), AGENT_TOOLS).length, 0);
  assert.equal(ModelProfilePolicy.availableTools(profile({ protocol: 'gemini' }), AGENT_TOOLS).length, 0);
  assert.equal(ModelProfilePolicy.availableTools(profile({ protocol: 'anthropic' }), AGENT_TOOLS).length, 0);
  const read = ModelProfilePolicy.availableTools(profile({ toolAccess: 'read' }), AGENT_TOOLS);
  assert.ok(read.length >= 6); assert.ok(read.every(tool => tool.permission === 'read'));
  assert.equal(ModelProfilePolicy.availableTools(profile({ toolAccess: 'confirm-write' }), AGENT_TOOLS).length, AGENT_TOOLS.length);
});

for (const [name, args] of [['create_todo', null], ['create_todo', []], ['create_todo', { title: 7 }],
  ['create_todo', { title: '   ' }], ['create_todo', { title: '任务', date: '2026-02-29' }],
  ['create_todo', { title: '任务', date: '2026-04-31' }], ['create_todo', { title: '任务', date: '下周五' }],
  ['create_note', { title: '笔记', content: '' }], ['create_link', { sourceIdentifier: 'A', targetTitle: 'B]]\nextra' }],
  ['search_notes', { query: 'A', limit: 2.5 }], ['search_notes', { query: 'A', limit: 11 }],
  ['read_note', { identifier: 'A', extra: true }], ['list_todos', { status: 'maybe' }]]) {
  test(`tool arguments reject malformed ${name}: ${JSON.stringify(args)}`, () => {
    assert.throws(() => ToolArgumentValidator.parse(name, JSON.stringify(args)));
  });
}
test('explicit dates accept leap days and relative dates never silently guess ambiguous input', () => {
  assert.equal(ToolArgumentValidator.date('2028-02-29'), '2028-02-29');
  assert.match(ToolArgumentValidator.date('明天'), /^\d{4}-\d{2}-\d{2}$/);
  assert.throws(() => ToolArgumentValidator.date('12月25日'));
});

function toolPorts(overrides = {}) {
  return { search: () => 'results', list: () => 'notes', read: () => 'body', summarize: () => 'stats',
    outline: () => 'outline', todos: () => 'todos', createTodo: async () => 'saved', addTag: async () => 'saved',
    createLink: async () => 'saved', categorize: async () => 'saved', createNote: async () => 'saved', progress: () => {}, ...overrides };
}
test('write executor waits for persistence and never reports successful storage failures', async () => {
  let release; let writes = 0; const statuses = [];
  const executor = new WorkspaceToolExecutor(toolPorts({ createTodo: () => { writes++; return new Promise(resolve => { release = resolve; }); },
    progress: status => statuses.push(status) }));
  let done = false; const running = executor.execute('create_todo', '{"title":"任务"}').then(result => { done = true; return result; });
  await Promise.resolve(); assert.equal(done, false); assert.equal(writes, 1);
  release('saved'); assert.equal((await running).ok, true);
  const broken = new WorkspaceToolExecutor(toolPorts({ createNote: async () => { throw new Error('storage full'); } }));
  const failed = await broken.execute('create_note', '{"title":"笔记","content":"正文"}');
  assert.equal(failed.ok, false); assert.match(failed.content, /storage full/);
  await executor.execute('create_todo', '{"title":12}'); assert.equal(writes, 1);
});

test('note tools reject ambiguous and partial titles while IDs resolve exactly', () => {
  const notes = [{ id: 'a', title: '算法', contentDetail: '# 算法\n```\n# 代码注释\n```\n## 搜索' },
    { id: 'b', title: '算法', contentDetail: '' }];
  assert.throws(() => NoteToolReader.resolve(notes, '算法'), /ID/);
  assert.throws(() => NoteToolReader.resolve(notes, '算'));
  const outline = NoteToolReader.outline(NoteToolReader.resolve(notes, 'a'));
  assert.match(outline, /第 5 行/); assert.ok(!outline.includes('代码注释'));
});

test('note card keys refresh covers, pinning and favorites without losing note identity', () => {
  const { noteRenderKey } = load(`${base}common/utils/ForEachKeys.ets`);
  const note = { id: 'a', title: '算法', type: 'Markdown', category: '学习', tag: '', updatedAt: 1 };
  const original = noteRenderKey(note);
  for (const change of [{ coverUrl: 'cover:mist' }, { favorite: true }, { isPinned: true }, { category: '工作' }]) {
    assert.notEqual(noteRenderKey({ ...note, ...change }), original);
  }
});

test('manual proposals use the same validated, awaited tools and propagate incomplete actions', async () => {
  const executor = new WorkspaceToolExecutor(toolPorts({ createTodo: async () => { throw new Error('disk full'); } }));
  assert.equal((await ActionProposalService.execute({ id: '1', type: 'todo', title: '任务', date: '2026-10-01', desc: '' }, executor)).ok, false);
  assert.equal((await ActionProposalService.execute({ id: '1', type: 'delete-all', title: '任务', desc: '' }, executor)).ok, false);
});

function orchestratorFixture(changes = {}, tools = [], providerChanges = {}, mocks = {}) {
  const configured = profile(changes); const requests = []; let streamCalls = 0; let completeCalls = 0;
  const provider = { complete: async (_, request) => { completeCalls++; requests.push(request); return '完整答案'; },
    completeStream: async (_, request, onChunk) => {
      streamCalls++; requests.push(request);
      for (let index = 0; index < tools.length; index++) {
        onChunk({ delta: '', done: false, toolCall: { index, id: `call_${index}`, name: tools[index].name, argumentsFragment: JSON.stringify(tools[index].args) } });
      }
      onChunk({ delta: tools.length ? '' : '答案', done: true }); return { abort() {} };
    } };
  Object.assign(provider, providerChanges);
  const { AgentOrchestrator } = load(`${base}services/ai/AgentOrchestrator.ets`, {
    ...mocks,
    [path.resolve(root, `${base}services/ai/ModelProvider.ets`)]: { createProvider: () => provider,
      StreamHandleImpl: class { constructor(abort) { this.abort = abort; } } },
    [path.resolve(root, `${base}services/ai/ModelConfigService.ets`)]: { ModelConfigService: { getInstance: () => ({ getActiveProfile: async () => configured }) } }
  });
  return { orchestrator: new AgentOrchestrator(), configured, requests, counts: () => ({ streamCalls, completeCalls }) };
}
test('agent respects nonstream configuration and includes saved instructions', async () => {
  const f = orchestratorFixture({ stream: false, systemPrompt: '先给结论' });
  const result = await f.orchestrator.run('L3', { query: '总结', history: [], profile: f.configured }, () => {});
  assert.equal(result.text, '完整答案'); assert.deepEqual(f.counts(), { completeCalls: 1, streamCalls: 0 });
  assert.match(f.requests[0].messages[0].content, /先给结论/); assert.equal(f.requests[0].toolsJson, undefined);
});
for (const mode of ['disabled', 'readonly', 'invalid', 'denied', 'cancelled']) {
  test(`agent never writes when tool request is ${mode}`, async () => {
    let writes = 0; let confirmations = 0; let cancelled = false;
    const f = orchestratorFixture({ maxToolRounds: 1, toolAccess: mode === 'disabled' ? 'none' : mode === 'readonly' ? 'read' : 'confirm-write' },
      [{ name: 'create_todo', args: mode === 'invalid' ? { title: 7 } : { title: '任务' } }]);
    await f.orchestrator.run('L2', { query: '规划', history: [], profile: f.configured, tools: AGENT_TOOLS,
      executor: { execute: async () => { writes++; return { ok: true, content: 'saved' }; } },
      isCancelled: () => cancelled, confirm: async () => { confirmations++; if (mode === 'cancelled') cancelled = true; return mode !== 'denied'; }
    }, () => {});
    assert.equal(writes, 0);
    if (['disabled', 'readonly', 'invalid'].includes(mode)) assert.equal(confirmations, 0);
    assert.equal(f.counts().streamCalls, 1);
  });
}
test('agent enforces configured round limit and executes each write only after confirmation', async () => {
  let writes = 0; let confirmations = 0;
  const f = orchestratorFixture({ maxToolRounds: 1 }, [{ name: 'create_todo', args: { title: '任务' } }]);
  const result = await f.orchestrator.run('L2', { query: '规划', history: [], profile: f.configured, tools: AGENT_TOOLS,
    confirm: async () => { confirmations++; return true; }, executor: { execute: async () => { assert.equal(confirmations, 1); writes++; return { ok: true, content: 'saved' }; } }
  }, () => {});
  assert.equal(writes, 1); assert.equal(f.counts().streamCalls, 1); assert.match(result.text, /上限/);
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

test('configuration flush failure preserves the active profile and never broadcasts success', async () => {
  const original = profile({ apiKey: '', credentialRef: 'key_000000000000000000000001' }); const values = new Map([['profiles', JSON.stringify([original])], ['activeProfileId', original.id]]);
  const publications = []; let fail = true;
  const prefs = { get: async (key, fallback) => values.get(key) ?? fallback, put: async (key, value) => values.set(key, value),
    flush: async () => { if (fail) throw new Error('disk full'); } };
  const { ModelConfigService } = load(`${base}services/ai/ModelConfigService.ets`, {
    '@kit.ArkData': { preferences: { getPreferences: async () => prefs } },
    [path.resolve(root, `${base}services/ai/HuksCredentialStore.ets`)]: { HuksCredentialStore: class {
      async init() {} async read() { return 'test-key'; } async write() { return 'key_000000000000000000000002'; } async remove() {}
    } },
    AppStorage: { setOrCreate: (key, value) => publications.push([key, value]) }
  });
  const service = ModelConfigService.getInstance(); await service.init({});
  await assert.rejects(service.saveAndActivate(profile({ id: 'new', label: '新配置' })));
  assert.equal((await service.getActiveProfile()).id, original.id); assert.equal(publications.length, 0);
  fail = false; const saved = await service.saveAndActivate(profile({ id: 'new', label: '新配置' }));
  assert.equal(saved.length, 2); assert.equal((await service.getActiveProfile()).id, 'new'); assert.equal(publications.length, 2);
});

test('semantic search is explicit and embedding cache refreshes changed content', async () => {
  const inputs = [];
  const { EmbeddingIndexService } = load(`${base}services/ai/EmbeddingIndexService.ets`, {
    [path.resolve(root, `${base}services/ai/EmbeddingProvider.ets`)]: {
      createEmbeddingProvider: () => ({ embed: async (_, texts) => { inputs.push(texts); return texts.map(() => [1, 2]); } })
    }
  });
  const service = EmbeddingIndexService.getInstance();
  const configured = profile({ embeddingModelId: 'example' });
  const chunk = { id: 'chunk', noteId: 'note', noteTitle: '标题', headingPath: '', text: '旧正文', startLine: 0, tokenEstimate: 2 };
  assert.equal(await service.ensure(configured, [chunk]), false); assert.equal(inputs.length, 0);
  configured.semanticSearch = true;
  assert.equal(await service.ensure(configured, [chunk]), true);
  assert.equal(await service.ensure(configured, [chunk]), true); assert.equal(inputs.length, 1);
  assert.equal(await service.ensure(configured, [{ ...chunk, text: '新正文' }]), true); assert.equal(inputs.length, 2);
  assert.match(inputs[1][0], /新正文/);
});

test('embedding cancellation and invalid vectors cannot populate a successful index', async () => {
  for (const cancelled of [false, true]) {
    let cancel = false;
    const { EmbeddingIndexService } = load(`${base}services/ai/EmbeddingIndexService.ets`, {
      [path.resolve(root, `${base}services/ai/EmbeddingProvider.ets`)]: {
        createEmbeddingProvider: () => ({ embed: async () => { cancel = cancelled; return cancelled ? [[1, 2]] : [[]]; } })
      }
    });
    const service = EmbeddingIndexService.getInstance();
    assert.equal(await service.ensure(profile({ semanticSearch: true, embeddingModelId: 'example' }),
      [{ id: 'chunk', noteTitle: '标题', headingPath: '', text: '正文' }], () => cancel), false);
    assert.equal(service.size(), 0);
  }
});

test('local extraction preserves source and never invents subject facts, tags or links', () => {
  const result = AiParser.fromSource(source);
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
  assert.equal(AiParser.fromSource('今天阳光很好。').tasks.length, 0);
  assert.equal(AiParser.fromSource('期末考试地点：艺术楼。').tasks.length, 0);
  assert.equal(AiParser.fromSource('已经提交报告；无需完成练习。').tasks.length, 0);
});

test('line endings, formulas and code remain in locally formatted body', () => {
  const result = AiParser.fromSource('# 数学\r\n\r\n$x=42$\r\n```js\r\nconst x = 42;\r\n```');
  assert.ok(result.formattedMarkdown.includes('$x=42$'));
  assert.ok(result.formattedMarkdown.includes('const x = 42;'));
  assert.ok(!result.formattedMarkdown.includes('\r'));
});

test('model arrays reject malformed rows, normalize fields and regenerate unique IDs', () => {
  const model = { title: '报告', type: 'unexpected', summary: 42, formattedMarkdown: '# 报告\n\n正文',
    tags: [null, '工作', 8, '工作'], entities: [null, {}, { name: '会议', type: '???' }],
    tasks: [null, {}, { title: '提交报告', id: 'same', priority: '???', deadline: 7 },
      { title: '提交报告', id: 'same' }, { title: '整理资料', id: 'same' }],
    relations: [null, { targetTitle: '[[资料]]\n', reason: 9 }] };
  const result = AiParser.parseModelContent('```json\n' + JSON.stringify(model) + '\n```');
  assert.equal(result.type, 'general');
  assert.equal(result.summary, '');
  assert.deepEqual(plain(result.tags), ['工作']);
  assert.equal(result.tasks.length, 2);
  assert.notEqual(result.tasks[0].id, result.tasks[1].id);
  assert.equal(result.tasks[0].priority, 'medium');
  assert.equal(result.tasks[0].deadline, '');
  assert.equal(result.entities[0].type, 'other');
  assert.equal(result.relations[0].targetTitle, '资料');
});

test('invalid or irrelevant model JSON cannot masquerade as successful extraction', () => {
  for (const text of ['not json', 'null', '[]', '{"unrelated":true}', '{"title":', '```json\n{}\n```']) {
    assert.throws(() => AiParser.parseModelContent(text));
  }
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
  const content = AiParser.fromSource(source);
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
    const content = AiParser.fromSource(source);
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
  await SmartCaptureService.commit(AiParser.fromSource('随笔'), [], store.port);
  assert.equal(store.state.todos[0].id, 'existing');
  assert.ok(!store.state.calls.includes('todos'));
});

function extractService({ key = '', response = '', fails = false, baseUrl = 'https://example.com/v1' } = {}) {
  const calls = [];
  const mocks = {
    [path.resolve(root, `${base}services/ai/ModelConfigService.ets`)]: {
      ModelConfigService: { getInstance: () => ({ getActiveProfile: async () => ({ apiKey: key, protocol: 'openai-compat', baseUrl }) }) }
    },
    [path.resolve(root, `${base}services/ai/ModelProvider.ets`)]: {
      createProvider: () => ({ complete: async (profile, request) => {
        calls.push(request); if (fails) throw Error('network'); return response;
      } })
    }
  };
  return { calls, service: load(extractFile, mocks).SmartExtractService.getInstance() };
}

test('local-only mode and missing key never invoke a network provider', async () => {
  for (const [key, useAi] of [['secret', false], ['', true]]) {
    const { service, calls } = extractService({ key });
    const result = await service.extract(source, 'note', 'faithful', useAi);
    assert.equal(result.processingMode, 'local');
    assert.equal(calls.length, 0);
    assert.equal(result.rawMarkdown, source);
  }
});

test('AI formatting carries style instruction and preserves input instead of response JSON', async () => {
  const { service, calls } = extractService({ key: 'test', response: JSON.stringify({ title: '笔记', formattedMarkdown: '# 笔记\n\n内容', tasks: [] }) });
  const result = await service.extract(source, 'note', 'study', true);
  assert.equal(result.processingMode, 'ai');
  assert.equal(result.rawMarkdown, source);
  assert.ok(calls[0].messages[1].content.includes('学习笔记'));
  assert.ok(calls[0].messages[0].content.includes('不是指令'));
});

for (const config of [{ fails: true }, { response: 'bad JSON' }, { response: '{"title":"标题"}' }]) {
  test(`AI failure falls back to original source (${JSON.stringify(config)})`, async () => {
    const { service } = extractService({ key: 'test', ...config });
    const result = await service.extract(source, 'note', 'faithful', true);
    assert.equal(result.processingMode, 'local');
    assert.equal(result.rawMarkdown, source);
    assert.ok(result.processingNotice.includes('未成功'));
  });
}

test('empty and oversized input reject before any network call', async () => {
  const { service, calls } = extractService({ key: 'test' });
  await assert.rejects(service.extract('   '), /不能为空/);
  await assert.rejects(service.extract('a'.repeat(12001)), /超过/);
  assert.equal(calls.length, 0);
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

test('damaged sessions and messages preserve valid history without crashes', () => {
  const sessions = ChatSessionSanitizer.normalize([null, 42, {},
    { id: 'old', updatedAt: 1, messages: [null, 42, { text: 7, citations: [null, {}] }] },
    { id: 'new', title: '标题', updatedAt: 2, messages: [{ id: 'm', role: 'user', text: '文字', streaming: true,
      citations: [{ noteId: 'n', noteTitle: '笔记', chunkText: '正文' }] }] }]);
  assert.equal(sessions.length, 2);
  assert.equal(sessions[0].id, 'new');
  assert.equal(sessions[0].messages[0].streaming, false);
  assert.equal(sessions[0].messages[0].citations[0].headingPath, '');
  assert.equal(sessions[1].messages.length, 1);
  assert.equal(sessions[1].messages[0].text, '');
  assert.equal(sessions[1].messages[0].citations.length, 0);
  assert.equal(sessions[1].title, '新对话');
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

function importService(uri, { pdfFails = false, writeFails = false, unlinkFails = false, missing = false, initial = '', readFails = false } = {}) {
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
        readText: async () => { calls.push('read-text'); if (readFails) throw Error('I/O'); return '# 资料\n\n全文'; },
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
test('PDF chunks carry page provenance and IDs do not collide across pages', () => {
  const { ChunkIndexService } = load(`${base}services/ai/ChunkIndexService.ets`);
  const index = new ChunkIndexService();
  const chunks = StudySourceService.documents([pdfStudyNote()]).flatMap(doc => plain(index.build(doc)));
  assert.equal(new Set(chunks.map(c => c.id)).size, chunks.length);
  assert.ok(chunks.some(c => c.pageNumber === 1 && c.text.includes('银行家')));
  assert.ok(chunks.some(c => c.pageNumber === 2 && c.text.includes('物理地址')));
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
test('AI review drafts require an exact source excerpt from the claimed PDF page', () => {
  const note = pdfStudyNote();
  const good = { question: '银行家算法如何避免风险？', answer: '执行安全性检查', sourceText: '银行家算法通过安全性检查', pageNumber: 1 };
  assert.equal(ReviewPolicy.generated(JSON.stringify([good]), note).length, 1);
  for (const draft of [{ ...good, pageNumber: 2 }, { ...good, pageNumber: 99 }, { ...good, sourceText: '资料从未说过的内容' },
    { ...good, question: '' }, { ...good, sourceText: '短文' }]) assert.throws(() => ReviewPolicy.generated(JSON.stringify([draft]), note));
  assert.equal(ReviewPolicy.generated(JSON.stringify([good, good]), note).length, 1);
  assert.throws(() => ReviewPolicy.generated('[{"answer":"虚构内容"}]', note));
});
test('course summaries exclude removed source notes and count only linked unfinished tasks', () => {
  const card = ReviewPolicy.create(studyNote(), { question: 'Q', answer: 'A', sourceText: '' }, 1);
  const summary = ReviewPolicy.courses([studyNote()], [card, { ...card, id: 'other', noteId: 'deleted' }],
    [{ done: false, noteRefs: [card.noteId] }, { done: true, noteRefs: [card.noteId] }, { done: false, noteRefs: [] }], 10)[0];
  assert.equal(summary.noteCount, 1); assert.equal(summary.dueCount, 1); assert.equal(summary.cardCount, 1); assert.equal(summary.todoCount, 1);
});
const studyBackup = () => ({ schemaVersion: 1, id: 'backup123', createdAt: 1, notes: [studyNote()], cards: [], assets: [] });
test('study backup strips device paths, model credentials, unknown properties and keeps bundled covers', () => {
  const backup = studyBackup();
  backup.notes[0] = studyNote({ sourceUri: '/outside/private.pdf', apiKey: 'secret', modelConfig: { secret: true }, coverUrl: 'cover:ink' });
  const normalized = plain(StudyBackupPolicy.validate(backup));
  assert.equal(normalized.notes[0].coverUrl, 'cover:ink');
  assert.ok(!JSON.stringify(normalized).includes('secret')); assert.ok(!JSON.stringify(normalized).includes('/outside'));
});
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
test('local backup exports actual PDF and cover bytes without credentials and selection validates the package', async () => {
  const f = backupFileFixture(); const context = { filesDir: '/sandbox' };
  f.files.set('/sandbox/documents/book.pdf', Buffer.from('%PDF-1.7\noriginal'));
  f.files.set('/sandbox/covers/photo.img', Buffer.from('original image bytes'));
  const note = studyNote({ type: 'PDF', sourceType: 'pdf', sourceUri: '/sandbox/documents/book.pdf', coverUrl: '/sandbox/covers/photo.img', apiKey: 'never-export' });
  assert.equal(await f.service.exportFile(context, [note], []), true);
  const backup = JSON.parse(f.files.get('/picked/backup.json').toString('utf8'));
  assert.equal(backup.assets.length, 2);
  assert.equal(Buffer.from(backup.assets[0].data, 'base64').toString(), '%PDF-1.7\noriginal');
  assert.ok(!JSON.stringify(backup).includes('never-export'));
  assert.ok(!JSON.stringify(backup).includes('/sandbox'));
  assert.equal((await f.service.selectFile(context)).notes.length, 1);
  assert.equal(f.calls.filter(c => c[0] === 'close').length, 4);
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

test('concurrent chat upserts and deletion preserve independent sessions and capture mutable inputs', async () => {
  const f = preferenceFixture({ sessions: '[]' });
  const { ChatSessionService } = load(`${base}services/ai/ChatSessionService.ets`, {
    '@kit.ArkData': { preferences: { getPreferences: async () => f.prefs } }
  });
  const service = ChatSessionService.getInstance(); await service.init({});
  const session = id => ({ id, title: id, messages: [], createdAt: 1, updatedAt: 1 });
  const first = session('first'); const saved = service.saveSession(first); first.title = 'mutated'; first.id = 'mutated';
  await Promise.all([saved, service.saveSession(session('second')), service.saveSession(session('third')), service.deleteSession('second')]);
  assert.deepEqual(plain((await service.loadSessions()).map(item => item.id).sort()), ['first', 'third']);
  assert.equal((await service.loadSessions()).find(item => item.id === 'first').title, 'first');
});

test('corrupt chat history cannot be replaced by an upsert or a clearing action', async () => {
  const f = preferenceFixture({ sessions: '{broken' });
  const { ChatSessionService } = load(`${base}services/ai/ChatSessionService.ets`, {
    '@kit.ArkData': { preferences: { getPreferences: async () => f.prefs } }
  });
  const service = ChatSessionService.getInstance(); await service.init({});
  await assert.rejects(service.saveSession({ id: 'new', title: '', messages: [] }));
  await assert.rejects(service.clearAll(), /原数据已保留|阻止覆盖/); assert.equal(f.values.get('sessions'), '{broken');
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


const { RemoteAiPolicy } = load(`${base}services/ai/RemoteAiPolicy.ets`);
const consentProfile = overrides => profile({ remoteConsentVersion: RemoteAiPolicy.VERSION,
  remoteConsentEndpoint: 'https://example.com/v1', remoteConsentProtocol: 'openai-compat', remoteConsentedAt: 1, ...overrides });

test('AI consent binds version, complete endpoint and protocol; HTTP and header injection are rejected', () => {
  assert.doesNotThrow(() => RemoteAiPolicy.assertAllowed(consentProfile()));
  for (const change of [{ remoteConsentVersion: undefined }, { remoteConsentVersion: 0 }, { remoteConsentedAt: 0 },
    { baseUrl: 'https://other.example/v1' }, { baseUrl: 'https://example.com/v2' }, { protocol: 'gemini' },
    { baseUrl: 'http://example.com/v1' }, { baseUrl: 'http://localhost.evil/v1' },
    { baseUrl: 'http://127.0.0.1:11434/v1' }, { apiKey: 'key\r\nInjected: value' }, { credentialUnavailable: true }]) {
    assert.throws(() => RemoteAiPolicy.assertAllowed(consentProfile(change)));
  }
  const local = consentProfile({ baseUrl: 'http://127.0.0.1:11434/v1', apiKey: '', remoteConsentEndpoint: 'http://127.0.0.1:11434/v1' });
  assert.doesNotThrow(() => RemoteAiPolicy.assertAllowed(local));
});

function modelFixture(initial = [profile()], changes = {}) {
  const values = new Map([['profiles', JSON.stringify(initial)], ['activeProfileId', initial[0]?.id || '']]);
  const secrets = new Map(); const publications = []; let counter = 0;
  for (const p of initial) if (p.credentialRef) secrets.set(p.credentialRef, { id: p.id, key: 'original-key' });
  const state = { failFlush: false, failEncrypt: false, ...changes };
  const prefs = { get: async (k, fallback) => values.get(k) ?? fallback, put: async (k, v) => values.set(k, v),
    flush: async () => { if (state.failFlush) throw Error('disk full'); } };
  class Credentials {
    async init() {}
    async write(id, key) {
      if (state.failEncrypt) throw Error('keystore unavailable');
      const ref = `key_${(++counter + 100).toString(16).padStart(24, '0')}`;
      secrets.set(ref, { id, key }); return ref;
    }
    async read(id, ref) { const value = secrets.get(ref); if (!value || value.id !== id) throw Error('missing key'); return value.key; }
    async remove(ref) { secrets.delete(ref); }
    async clear() { secrets.clear(); }
  }
  const { ModelConfigService } = load(`${base}services/ai/ModelConfigService.ets`, {
    '@kit.ArkData': { preferences: { getPreferences: async () => prefs } },
    [path.resolve(root, `${base}services/ai/HuksCredentialStore.ets`)]: { HuksCredentialStore: Credentials },
    AppStorage: { setOrCreate: (k, v) => publications.push([k, v]) }
  });
  return { service: ModelConfigService.getInstance(), values, secrets, publications, state };
}

test('legacy key migration encrypts before commit and no key appears in model metadata', async () => {
  const f = modelFixture(); await f.service.init({});
  const loaded = await f.service.loadProfiles(); assert.equal(loaded[0].apiKey, 'test-key');
  const stored = JSON.parse(f.values.get('profiles'));
  assert.equal(stored[0].apiKey, ''); assert.ok(stored[0].credentialRef); assert.equal(f.values.get('profiles').includes('test-key'), false);
  assert.equal((await f.service.getActiveProfile()).apiKey, 'test-key');
  assert.equal(f.publications.length, 0);
});

for (const failure of ['failFlush', 'failEncrypt']) test(`legacy migration preserves raw data when ${failure}`, async () => {
  const f = modelFixture(undefined, { [failure]: true }); await f.service.init({});
  const raw = f.values.get('profiles'); await assert.rejects(f.service.loadProfiles());
  assert.equal(f.values.get('profiles'), raw); assert.equal(f.secrets.size, 0);
  f.state[failure] = false; assert.equal((await f.service.loadProfiles())[0].apiKey, 'test-key');
});

test('key replacement flush failure keeps the old key and activation; successful deletion removes the reference', async () => {
  const f = modelFixture([profile({ apiKey: '', credentialRef: 'key_000000000000000000000001' }), profile({ id: 'other', apiKey: '' })]);
  await f.service.init({}); f.state.failFlush = true;
  await assert.rejects(f.service.saveAndActivate(profile({ apiKey: 'replacement-key' })));
  assert.equal((await f.service.getActiveProfile()).apiKey, 'original-key'); assert.equal(f.secrets.size, 1);
  assert.equal(f.publications.length, 0); f.state.failFlush = false;
  await f.service.saveAndActivate(profile({ apiKey: 'replacement-key' }));
  assert.equal((await f.service.getActiveProfile()).apiKey, 'replacement-key'); assert.equal(f.secrets.size, 1);
  await f.service.deleteProfile('study'); assert.equal(f.secrets.size, 0); assert.equal(await f.service.getActiveProfileId(), 'other');
});

test('unreadable device key is visible and retained when saving unrelated settings', async () => {
  const f = modelFixture([profile({ apiKey: '', credentialRef: 'key_000000000000000000000001' })]); await f.service.init({}); f.secrets.clear();
  const p = await f.service.getActiveProfile(); assert.equal(p.credentialUnavailable, true);
  await f.service.saveAndActivate({ ...p, label: 'renamed' });
  const stored = JSON.parse(f.values.get('profiles'))[0]; assert.equal(stored.credentialRef, 'key_000000000000000000000001');
  assert.equal(stored.apiKey, ''); assert.equal(stored.credentialUnavailable, undefined);
});

test('concurrent model saves retain both profiles; corrupt metadata never becomes a default overwrite', async () => {
  const f = modelFixture(); await f.service.init({});
  await Promise.all([f.service.upsertProfile(profile({ id: 'a' })), f.service.upsertProfile(profile({ id: 'b' }))]);
  assert.deepEqual(plain((await f.service.loadProfiles()).map(p => p.id)).sort(), ['a', 'b', 'study']);
  const bad = modelFixture(); await bad.service.init({}); bad.values.set('profiles', '{broken');
  await assert.rejects(bad.service.loadProfiles()); await assert.rejects(bad.service.upsertProfile(profile()));
  assert.equal(bad.values.get('profiles'), '{broken');
});

function huksFixture() {
  const values = new Map(); const sessions = new Map(); const key = randomBytes(32); let generated = false; let handle = 0;
  const tags = { HUKS_TAG_ALGORITHM: 1, HUKS_TAG_PURPOSE: 2, HUKS_TAG_KEY_SIZE: 3, HUKS_TAG_BLOCK_MODE: 4,
    HUKS_TAG_PADDING: 5, HUKS_TAG_NONCE: 6, HUKS_TAG_ASSOCIATED_DATA: 7, HUKS_TAG_AE_TAG: 8 };
  const huks = { HuksTag: tags, HuksKeyAlg: { HUKS_ALG_AES: 1 }, HuksKeyPurpose: { HUKS_KEY_PURPOSE_ENCRYPT: 1, HUKS_KEY_PURPOSE_DECRYPT: 2 },
    HuksKeySize: { HUKS_AES_KEY_SIZE_256: 256 }, HuksCipherMode: { HUKS_MODE_GCM: 32 }, HuksKeyPadding: { HUKS_PADDING_NONE: 0 },
    isKeyItemExist: async () => generated, generateKeyItem: async () => { generated = true; },
    initSession: async (_, options) => { const id = ++handle; sessions.set(id, options); return { handle: id }; },
    finishSession: async (id, options) => {
      const props = new Map(options.properties.map(p => [p.tag, p.value])); const nonce = Buffer.from(props.get(tags.HUKS_TAG_NONCE));
      const encrypt = props.get(tags.HUKS_TAG_PURPOSE) === 1;
      const cipher = encrypt ? createCipheriv('aes-256-gcm', key, nonce) : createDecipheriv('aes-256-gcm', key, nonce);
      cipher.setAAD(Buffer.from(props.get(tags.HUKS_TAG_ASSOCIATED_DATA)));
      if (!encrypt) cipher.setAuthTag(Buffer.from(props.get(tags.HUKS_TAG_AE_TAG)));
      const data = Buffer.concat([cipher.update(Buffer.from(options.inData)), cipher.final()]);
      sessions.delete(id); return { outData: encrypt ? Buffer.concat([data, cipher.getAuthTag()]) : data };
    }, abortSession: async id => { sessions.delete(id); } };
  const prefs = { get: async (k, fallback) => values.get(k) ?? fallback, put: async (k,v) => values.set(k,v), flush: async () => {} };
  const { HuksCredentialStore } = load(`${base}services/ai/HuksCredentialStore.ets`, {
    '@kit.ArkData': { preferences: { getPreferences: async () => prefs } }, '@kit.UniversalKeystoreKit': { huks },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createRandom: () => ({ generateRandom: async n => ({ data: randomBytes(n) }) }) } },
    '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } }, TextDecoder } }
  });
  return { store: new HuksCredentialStore(), values, sessions };
}

test('HUKS adapter supplies nonce, AAD and GCM tag; tampering or cross-profile use fails without plaintext fallback', async () => {
  const f = huksFixture(); await f.store.init({});
  const ref = await f.store.write('study', 'secret-密钥'); assert.equal(await f.store.read('study', ref), 'secret-密钥');
  assert.ok(!f.values.get(ref).includes('secret')); await assert.rejects(f.store.read('other', ref));
  const packet = JSON.parse(f.values.get(ref)); packet.cipher = `${packet.cipher[0] === '0' ? '1' : '0'}${packet.cipher.slice(1)}`;
  f.values.set(ref, JSON.stringify(packet)); await assert.rejects(f.store.read('study', ref)); assert.equal(f.sessions.size, 0);
});

for (const protocol of ['openai-compat', 'gemini', 'anthropic']) test(`${protocol} rejects unapproved chat and connection tests before HTTP creation`, async () => {
  let creations = 0;
  const { createProvider } = load(`${base}services/ai/ModelProvider.ets`, {
    '@kit.NetworkKit': { http: { createHttp: () => { creations++; throw Error('unexpected network'); } } }, '@kit.ArkTS': { util: {} }
  });
  const p = profile({ protocol }); const provider = createProvider(protocol);
  await assert.rejects(provider.complete(p, { messages: [] }));
  await assert.rejects(provider.completeStream(p, { messages: [] }, () => {}));
  assert.equal((await provider.testConnection(p)).ok, false); assert.equal(creations, 0);
});

for (const protocol of ['openai-compat', 'gemini']) test(`${protocol} rejects unapproved embeddings before HTTP creation`, async () => {
  let creations = 0;
  const { createEmbeddingProvider } = load(`${base}services/ai/EmbeddingProvider.ets`, {
    '@kit.NetworkKit': { http: { createHttp: () => { creations++; throw Error('unexpected network'); } } }
  });
  await assert.rejects(createEmbeddingProvider(protocol).embed(profile({ protocol }), ['private notes'])); assert.equal(creations, 0);
});

for (const protocol of ['openai-compat', 'gemini', 'anthropic']) test(`${protocol} disables redirects and destroys non-stream HTTP resources on failure`, async () => {
  let destroyed = 0; const requests = [];
  const { createProvider } = load(`${base}services/ai/ModelProvider.ets`, {
    '@kit.NetworkKit': { http: { RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 0 },
      createHttp: () => ({ request: async (url, options) => { requests.push(options); return { responseCode: 401, result: 'private echoed-key' }; }, destroy: () => destroyed++ }) } },
    '@kit.ArkTS': { util: {} }
  });
  const p = consentProfile({ protocol, remoteConsentProtocol: protocol });
  await assert.rejects(createProvider(protocol).complete(p, { messages: [] }), error => !error.message.includes('echoed-key'));
  assert.equal(requests[0].maxRedirects, 0); assert.equal(destroyed, 1);
});


test('removing one key preserves other profile keys; all legacy keys can be removed with HUKS unavailable', async () => {
  const f = modelFixture([profile({apiKey:'',credentialRef:'key_000000000000000000000001'}),
    profile({id:'other',apiKey:'',credentialRef:'key_000000000000000000000002'})]);
  await f.service.init({}); await f.service.clearCredentials('study');
  const profiles = await f.service.loadProfiles(); assert.equal(profiles[0].apiKey,''); assert.equal(profiles[1].apiKey,'original-key');
  assert.equal(f.secrets.size,1); assert.equal(profiles[0].remoteConsentVersion,undefined);
  const legacy = modelFixture([consentProfile(),consentProfile({id:'other'})],{failEncrypt:true});
  await legacy.service.init({}); await legacy.service.clearCredentials();
  assert.equal(legacy.values.get('profiles').includes('test-key'),false);
  assert.ok((await legacy.service.loadProfiles()).every(p=>!p.apiKey && !p.remoteConsentVersion));
});

for (const protocol of ['openai-compat','gemini','anthropic']) test(`${protocol} streams UTF-8 across byte boundaries and closes once without callbacks after abort`, async () => {
  const events = new Map(); let resolveStatus; let destroyed=0; const chunks=[];
  const client = {on:(event,callback)=>events.set(event,callback),destroy:()=>destroyed++,
    requestInStream:()=>new Promise(resolve=>{resolveStatus=resolve;})};
  const { createProvider } = load(`${base}services/ai/ModelProvider.ets`, {
    '@kit.NetworkKit':{http:{createHttp:()=>client,RequestMethod:{POST:'POST'},HttpDataType:{ARRAY_BUFFER:1}}},
    '@kit.ArkTS':{util:{TextDecoder:{create:()=>{const d=new TextDecoder();return {decodeToString:(bytes,options)=>d.decode(bytes,options)};}}}}
  });
  const p=consentProfile({protocol,remoteConsentProtocol:protocol});
  const handle = await createProvider(protocol).completeStream(p,{messages:[]},chunk=>chunks.push(chunk));
  const text = protocol==='openai-compat' ? 'data: {"choices":[{"delta":{"content":"中文😀"},"finish_reason":"stop"}]}' :
    protocol==='gemini' ? 'data: {"candidates":[{"content":{"parts":[{"text":"中文😀"}]},"finishReason":"STOP"}]}' :
    'data: {"type":"content_block_delta","delta":{"text":"中文😀"}}\ndata: {"type":"message_stop"}';
  const bytes=new TextEncoder().encode(text); resolveStatus(200); await Promise.resolve();
  for(const byte of bytes) events.get('dataReceive')(Uint8Array.of(byte).buffer);
  await events.get('dataEnd')();
  assert.equal(chunks.filter(c=>!c.done).map(c=>c.delta).join(''),'中文😀'); assert.equal(chunks.filter(c=>c.done).length,1); assert.equal(destroyed,1);
  const count=chunks.length;handle.abort();events.get('dataReceive')(new TextEncoder().encode('data: {}\n').buffer);
  assert.equal(chunks.length,count);assert.equal(destroyed,1);
});

test('notice rejection is recorded without authorizing remote AI, and a corrupt receipt can be replaced',async()=>{
  const values=new Map([['notice','{broken']]);
  const prefs={get:async(k,fallback)=>values.get(k)??fallback,put:async(k,v)=>values.set(k,v),flush:async()=>{}};
  const { PrivacyNoticeService }=load(`${base}services/PrivacyNoticeService.ets`,{'@kit.ArkData':{preferences:{getPreferences:async()=>prefs}}});
  const service=new PrivacyNoticeService();assert.equal(await service.shown({}),false);await service.choose({},false);
  assert.equal(await service.shown({}),true);assert.equal(JSON.parse(values.get('notice')).agree,false);
  assert.throws(()=>RemoteAiPolicy.assertAllowed(profile()));
});


test('explicit model reset recovers corrupt metadata; failed reset preserves the original snapshot', async () => {
  const f=modelFixture();await f.service.init({});f.values.set('profiles','{broken');await assert.rejects(f.service.loadProfiles());
  f.state.failFlush=true;await assert.rejects(f.service.resetProfiles());assert.equal(f.values.get('profiles'),'{broken');
  f.state.failFlush=false;await f.service.resetProfiles();const profiles=await f.service.loadProfiles();
  assert.equal(profiles.length,1);assert.equal(profiles[0].apiKey,'');assert.equal(profiles[0].remoteConsentVersion,undefined);
  assert.equal(await f.service.getActiveProfileId(),profiles[0].id);
});


test('SSE transport releases client when SDK request startup throws synchronously',async()=>{
  let destroyed=0;const chunks=[];
  const { createProvider }=load(`${base}services/ai/ModelProvider.ets`,{
    '@kit.NetworkKit':{http:{createHttp:()=>({on(){},destroy(){destroyed++;},requestInStream(){throw Error('SDK unavailable');}}),RequestMethod:{POST:'POST'},HttpDataType:{ARRAY_BUFFER:1}}},
    '@kit.ArkTS':{util:{TextDecoder:{create:()=>({decodeToString:()=>''})}}}
  });
  const handle=await createProvider('gemini').completeStream(consentProfile({protocol:'gemini',remoteConsentProtocol:'gemini'}),{messages:[]},c=>chunks.push(c));
  assert.equal(destroyed,1);assert.equal(chunks.length,1);assert.ok(chunks[0].error);handle.abort();assert.equal(destroyed,1);
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

test('catalog API drafts have unique identity, no key or consent, and require explicit user setup', () => {
  for (const entry of AiModelCatalog.list()) {
    const p = AiModelCatalog.createApiDraft(entry.id), other = AiModelCatalog.createApiDraft(entry.id);
    assert.notEqual(p.id, other.id); assert.equal(p.apiKey, '');
    assert.equal(p.credentialRef, undefined); assert.equal(p.remoteConsentVersion, undefined);
    assert.equal(p.semanticSearch, false); assert.equal(p.protocol, 'openai-compat');
    assert.notEqual(ModelProfilePolicy.validate(p), '');
    assert.throws(() => RemoteAiPolicy.assertAllowed(p), /授权/);
  }
});

for (const entry of AiModelCatalog.list()) test(`catalog ${entry.name} uses its exact compatible chat endpoint after consent`, async () => {
  const requests = []; let destroyed = 0;
  const { createProvider } = load(`${base}services/ai/ModelProvider.ets`, {
    '@kit.NetworkKit': { http: { RequestMethod: { POST: 'POST' }, HttpDataType: { STRING: 0 }, createHttp: () => ({
      request: async (url, options) => { requests.push({url,options}); return { responseCode: 200, result: JSON.stringify({ choices: [{message:{content:'mock reply'}}] }) }; },
      destroy: () => destroyed++ }) } }, '@kit.ArkTS': { util: {} }
  });
  const draft = AiModelCatalog.createApiDraft(entry.id);
  draft.apiKey = 'test-key'; draft.remoteConsentVersion = RemoteAiPolicy.VERSION;
  draft.remoteConsentEndpoint = draft.baseUrl; draft.remoteConsentProtocol = draft.protocol; draft.remoteConsentedAt = Date.now();
  assert.equal(ModelProfilePolicy.validate(draft), '');
  assert.equal(await createProvider(draft.protocol).complete(draft, {messages:[{role:'user',content:'test'}]}), 'mock reply');
  assert.equal(requests[0].url, entry.apiEndpoint.endsWith('/chat/completions') ? entry.apiEndpoint : `${entry.apiEndpoint}/chat/completions`);
  assert.equal(JSON.parse(requests[0].options.extraData).model, entry.modelId);
  assert.equal(requests[0].options.maxRedirects, 0); assert.equal(destroyed, 1);
});

test('loopback template requires an installed model ID and never sends an empty bearer header', async () => {
  const { getPresetTemplates } = load(`${base}common/types/ModelConfig.ets`);
  const draft = getPresetTemplates().find(p => p.profile.baseUrl.startsWith('http://127.0.0.1')).profile;
  assert.equal(draft.apiKey, ''); assert.equal(draft.modelId, ''); assert.notEqual(ModelProfilePolicy.validate(draft), '');
  draft.modelId = 'installed-test-model'; assert.equal(ModelProfilePolicy.validate(draft), '');
  draft.remoteConsentVersion = RemoteAiPolicy.VERSION; draft.remoteConsentEndpoint = draft.baseUrl;
  draft.remoteConsentProtocol = draft.protocol; draft.remoteConsentedAt = Date.now();
  let headers;
  const { createProvider } = load(`${base}services/ai/ModelProvider.ets`, {
    '@kit.NetworkKit': { http: { RequestMethod: { POST:'POST' }, HttpDataType: { STRING:0 }, createHttp: () => ({
      request: async (_, options) => { headers = options.header; return {responseCode:200,result:'{"choices":[{"message":{"content":"ok"}}]}'}; }, destroy() {} }) } },
    '@kit.ArkTS': { util:{} }
  });
  await createProvider(draft.protocol).complete(draft, {messages:[]}); assert.equal(headers.Authorization, undefined);
});

test('message replacement captures input, preserves pinned metadata and never revives a deleted session', async () => {
  const f = preferenceFixture();
  const { ChatSessionService } = load(`${base}services/ai/ChatSessionService.ets`, {
    '@kit.ArkData': { preferences: { getPreferences: async () => f.prefs } }
  });
  const service = ChatSessionService.getInstance(); await service.init({});
  const session = { id:'study',title:'课程',pinned:true,agentMode:'L1',createdAt:1,updatedAt:1,messages:[] };
  await service.saveSession(session);
  const messages = [{id:'q',role:'user',text:'原输入',createdAt:2}];
  const running = service.replaceMessages('study', messages); messages[0].text = '后续更改';
  const saved = await running; assert.equal(saved.messages[0].text, '原输入');
  assert.equal(saved.title, '课程'); assert.equal(saved.pinned, true); assert.equal(saved.agentMode, 'L1');
  await service.deleteSession('study'); await assert.rejects(service.replaceMessages('study', []), /删除/);
  assert.equal((await service.loadSessions()).length, 0);
});

test('failed message replacement preserves the original conversation and remains retryable', async () => {
  const f = preferenceFixture();
  const { ChatSessionService } = load(`${base}services/ai/ChatSessionService.ets`, {
    '@kit.ArkData': { preferences: { getPreferences: async () => f.prefs } }
  });
  const service = ChatSessionService.getInstance(); await service.init({});
  await service.saveSession({id:'study',title:'课程',createdAt:1,updatedAt:1,messages:[{id:'q',role:'user',text:'原文',createdAt:1}]});
  f.fail(true); await assert.rejects(service.replaceMessages('study', []));
  assert.equal((await service.loadSessions())[0].messages[0].text, '原文');
  f.fail(false); await service.replaceMessages('study', []); assert.equal((await service.loadSessions())[0].messages.length, 0);
});

function compatibleStreamFixture(timers = {}) {
  const events = new Map(), chunks = []; let resolveStatus, destroyed = 0;
  const { createProvider } = load(`${base}services/ai/ModelProvider.ets`, {
    ...timers,
    '@kit.NetworkKit': { http: { RequestMethod:{POST:'POST'},HttpDataType:{ARRAY_BUFFER:1},createHttp:()=>({
      on:(event,callback)=>events.set(event,callback),destroy:()=>destroyed++,requestInStream:()=>new Promise(resolve=>{resolveStatus=resolve;}) }) } },
    '@kit.ArkTS': { util: { TextDecoder:{create:()=>{const d=new TextDecoder();return {decodeToString:(bytes,options)=>d.decode(bytes,options)};}} } }
  });
  return { events,chunks,provider:createProvider('openai-compat'),status:code=>resolveStatus(code),destroyed:()=>destroyed,
    receive:text=>events.get('dataReceive')(new TextEncoder().encode(text).buffer) };
}

test('compatible streaming preserves reasoning and tool fragments and emits one terminal result', async () => {
  const f=compatibleStreamFixture(); await f.provider.completeStream(consentProfile(),{messages:[]},c=>f.chunks.push(c));
  f.status(200);await Promise.resolve();
  for (const delta of [{reasoning_content:'推理'}, {tool_calls:[{index:0,id:'call_a',function:{name:'create_todo',arguments:'{"title":'}}]},
    {tool_calls:[{index:0,function:{arguments:'"复习"}'}}]}]) f.receive(`data: ${JSON.stringify({choices:[{delta,finish_reason:null}]})}\n`);
  f.receive('data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\ndata: [DONE]\n');await f.events.get('dataEnd')();
  assert.equal(f.chunks.filter(c=>c.done).length,1);assert.equal(f.chunks.at(-1).finishReason,'tool_calls');
  assert.equal(f.chunks.find(c=>c.reasoningDelta).reasoningDelta,'推理');
  assert.equal(f.chunks.filter(c=>c.toolCall).map(c=>c.toolCall.argumentsFragment).join(''),'{"title":"复习"}');assert.equal(f.destroyed(),1);
});

test('compatible stream buffers early data until status and never treats HTTP failure as an answer', async () => {
  const f=compatibleStreamFixture();await f.provider.completeStream(consentProfile(),{messages:[]},c=>f.chunks.push(c));
  f.receive('data: {"choices":[{"delta":{"content":"private server data"},"finish_reason":null}]}\n');
  assert.equal(f.chunks.length,0);f.status(401);await Promise.resolve();await f.events.get('dataEnd')();
  assert.equal(f.chunks.length,1);assert.ok(f.chunks[0].error.includes('401'));
  assert.ok(!JSON.stringify(f.chunks).includes('private server data'));assert.equal(f.destroyed(),1);
});

test('compatible stream provider errors and cancellation close exactly once without leaking payload', async () => {
  const f=compatibleStreamFixture();await f.provider.completeStream(consentProfile(),{messages:[]},c=>f.chunks.push(c));
  f.status(200);await Promise.resolve();f.receive('data: {"error":{"message":"echoed secret"}}\n');await f.events.get('dataEnd')();
  assert.equal(f.chunks.length,1);assert.ok(f.chunks[0].error);assert.ok(!f.chunks[0].error.includes('secret'));assert.equal(f.destroyed(),1);
  const cancelled=compatibleStreamFixture();const handle=await cancelled.provider.completeStream(consentProfile(),{messages:[]},c=>cancelled.chunks.push(c));
  handle.abort();cancelled.status(200);await cancelled.events.get('dataEnd')();
  cancelled.receive('data: {"choices":[{"delta":{"content":"late"}}]}\n');assert.equal(cancelled.chunks.length,0);assert.equal(cancelled.destroyed(),1);
});

test('explicit model formatting can use a keyless loopback service while the default still performs no model request', async () => {
  const { service, calls } = extractService({ baseUrl: 'http://127.0.0.1:11434/v1', response: '{"title":"课程","formattedMarkdown":"# 课程\\n\\n正文"}' });
  await service.extract(source); assert.equal(calls.length, 0);
  const result = await service.extract(source, '课程', 'faithful', true);
  assert.equal(result.processingMode, 'ai'); assert.equal(calls.length, 1);
});

const { LocalAssistantService } = load(`${base}services/ai/LocalAssistantService.ets`);
const localContext = (notes = [], pinned = []) => ({ notes, pinned, todos: [] });
test('offline assistant works with an empty workspace without any platform or network dependency', async () => {
  const result = await new LocalAssistantService().answer('提取要点', localContext());
  assert.match(result.text, /新建笔记|导入资料/); assert.equal(result.citations.length, 0);
});
test('Chinese natural questions find exact original text and source lines without whitespace', async () => {
  const notes = [studyNote({ id:'os',title:'操作系统',contentDetail:'# 课程\n\n## 死锁条件\n\n死锁需要互斥、占有等待、不可剥夺和循环等待。' }),
    studyNote({ id:'math',title:'数学',contentDetail:'# 数学\n\n三角函数周期为 2π。' })];
  const before = JSON.stringify(notes);
  const result = await new LocalAssistantService().answer('请问死锁有哪些条件？', localContext(notes));
  assert.match(result.text, /不可剥夺/); assert.equal(result.citations[0].noteId, 'os');
  assert.equal(result.citations[0].startLine, 5); assert.equal(JSON.stringify(notes), before);
  assert.ok(!result.text.includes('三角函数'));
});
test('local attachments constrain extraction and unmatched questions give a usable next step', async () => {
  const os = studyNote({id:'os',title:'操作系统',contentDetail:'# 课程\n\n死锁需要互斥。'});
  const math = studyNote({id:'math',title:'数学',contentDetail:'# 数学\n\n圆周率约为 3.14。'});
  const assistant = new LocalAssistantService();
  const result = await assistant.answer('提取要点', localContext([os, math], [math]));
  assert.match(result.text, /3\.14/); assert.ok(result.citations.every(c=>c.noteId==='math'));
  assert.match((await assistant.answer('死锁', localContext([os,math],[math]))).text, /未找到/);
});
test('offline PDF retrieval cites the actual extracted page and does not treat file metadata as content', async () => {
  const note = studyNote({ id:'pdf',type:'PDF',sourceType:'pdf',pageCount:4,
    contentDetail:'# PDF\n\n已导入文件',pdfTextJson:JSON.stringify([{pageNumber:3,text:'银行家算法通过安全序列判断分配。',method:'text',extractedAt:1}]) });
  const assistant = new LocalAssistantService();
  const result = await assistant.answer('银行家算法',localContext([note]));
  assert.equal(result.citations[0].pageNumber,3); assert.match(result.text,/安全序列/);
  note.pdfTextJson='[]'; assert.match((await assistant.answer('提取要点',localContext([note]))).text,/提取并校对/);
});
test('offline task extraction preserves explicit tasks without creating or guessing deadlines', async () => {
  const notes = [studyNote({contentDetail:'# 通知\n\n- [ ] 2026年10月12日前提交报告\n- [x] 已完成报名'})];
  const result = await new LocalAssistantService().answer('整理待办',localContext(notes));
  assert.match(result.text,/提交报告/); assert.ok(!result.text.includes('已完成报名')); assert.match(result.text,/未自动创建/);
});
test('local scanning yields for cancellation and never returns a late answer', async () => {
  const result = await new LocalAssistantService().answer('提取要点',localContext([studyNote()]),()=>true);
  assert.equal(result.text,''); assert.equal(result.citations.length,0);
});
test('local mode is the persisted default and a failed switch never enables remote use', async () => {
  const values = new Map(); const app = new Map(); let fail=false;
  const { AssistantModeService, ASSISTANT_MODE_KEY } = load(`${base}services/ai/AssistantModeService.ets`, {
    '@kit.ArkData':{preferences:{getPreferences:async()=>({get:async(k,d)=>values.get(k)??d,put:async(k,v)=>values.set(k,v),flush:async()=>{if(fail)throw Error('disk');}})}},
    AppStorage:{setOrCreate:(k,v)=>app.set(k,v)}
  });
  const service=AssistantModeService.getInstance(); await service.init({}); assert.equal(app.get(ASSISTANT_MODE_KEY),'local');
  fail=true;await assert.rejects(service.setMode('remote'));assert.equal(app.get(ASSISTANT_MODE_KEY),'local');assert.equal(values.get('mode'),'local');
  fail=false;await service.setMode('remote');assert.equal(app.get(ASSISTANT_MODE_KEY),'remote');
  await service.setMode('local');assert.equal(values.get('mode'),'local');
});

const penEnums = { SourceTool:{Unknown:0,Finger:1,Pen:2},TouchType:{Down:0,Up:1,Move:2,Cancel:3} };
const { InkInputService } = load(`${base}services/ink/InkInputService.ets`,penEnums);
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
  const ctx={save(){stack.push({width:this.lineWidth,alpha:this.globalAlpha,mode:this.globalCompositeOperation});},restore(){Object.assign(this,stack.pop());},
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
test('silent streams and interrupted streams end with actionable errors and clear all timers', async () => {
  for(const timeout of [45000,30000,180000]) {
    const timers=fakeTimers(),f=compatibleStreamFixture(timers);
    await f.provider.completeStream(consentProfile(),{messages:[]},c=>f.chunks.push(c));f.status(200);await Promise.resolve();
    if(timeout===30000)f.receive('data: {"choices":[{"delta":{"content":"部分答案"},"finish_reason":null}]}\n');
    timers.fire(timeout);assert.equal(f.destroyed(),1);assert.ok(f.chunks.at(-1).done);assert.ok(f.chunks.at(-1).error);
    assert.equal(timers.jobs.size,0);f.receive('data: {"choices":[{"delta":{"content":"late"}}]}\n');
    assert.equal(f.chunks.filter(c=>c.done).length,1);
  }
});

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

test('assistant defaults to offline and persists only the mode explicitly selected by the user', async () => {
  const values=new Map();const app=new Map();
  const {AssistantModeService,ASSISTANT_MODE_KEY}=load(`${base}services/ai/AssistantModeService.ets`,{
    BuildProfile:{DEBUG:false},AppStorage:{setOrCreate:(key,value)=>app.set(key,value)},
    '@kit.ArkData':{preferences:{getPreferences:async()=>({get:async(k,d)=>values.get(k)??d,put:async(k,v)=>values.set(k,v),flush:async()=>{}})}}
  });
  const service=AssistantModeService.getInstance();await service.init({});assert.equal(app.get(ASSISTANT_MODE_KEY),'local');
  await service.setMode('remote');assert.equal(app.get(ASSISTANT_MODE_KEY),'remote');assert.equal(values.get('mode'),'remote');
  await service.setMode('local');assert.equal(app.get(ASSISTANT_MODE_KEY),'local');assert.equal(values.get('mode'),'local');
});

test('unconfigured release blocks chat, connection tests and embeddings before any network client is created', async () => {
  let creations=0;const mocks={BuildProfile:{DEBUG:false},'@kit.NetworkKit':{http:{createHttp:()=>{creations++;throw Error('network');}}},'@kit.ArkTS':{util:{}}};
  const {createProvider}=load(`${base}services/ai/ModelProvider.ets`,mocks);
  const {createEmbeddingProvider}=load(`${base}services/ai/EmbeddingProvider.ets`,mocks);
  for(const protocol of ['openai-compat','gemini','anthropic']) {
    const p=consentProfile({protocol,remoteConsentProtocol:protocol,remoteConsentVersion:undefined});const provider=createProvider(protocol);
    await assert.rejects(provider.complete(p,{messages:[]}),/授权/);
    await assert.rejects(provider.completeStream(p,{messages:[]},()=>{}),/授权/);
    assert.equal((await provider.testConnection(p)).ok,false);
    if(protocol!=='anthropic')await assert.rejects(createEmbeddingProvider(protocol).embed(p,['正文']),/授权/);
  }
  assert.equal(creations,0);
});

test('stream cancellation settles immediately and aborts a handle that arrives after stopping', async () => {
  let callback,releaseHandle,control,aborts=0;const deltas=[];
  const f=orchestratorFixture({},[],{completeStream:(_,request,onChunk)=>{callback=onChunk;return new Promise(resolve=>{releaseHandle=resolve;});}});
  const running=f.orchestrator.run('L3',{query:'总结',history:[],profile:f.configured},text=>deltas.push(text),handle=>{control=handle;});
  const stopped=assert.rejects(running,/停止/);control.abort();await stopped;
  callback({delta:'晚到内容',done:true});releaseHandle({abort:()=>aborts++});await Promise.resolve();await Promise.resolve();
  assert.equal(deltas.length,0);assert.equal(aborts,1);
});

test('nonstream cancellation and deadlines abort the transport and ignore late answers', async () => {
  for(const timeout of [false,true]) {
    const timers=fakeTimers();let resolveAnswer,control,aborts=0;const deltas=[];
    const f=orchestratorFixture({stream:false},[],{complete:(_,request,onHandle)=>{
      onHandle({abort:()=>aborts++});return new Promise(resolve=>{resolveAnswer=resolve;});
    }},timers);
    const running=f.orchestrator.run('L3',{query:'总结',history:[],profile:f.configured},text=>deltas.push(text),handle=>{control=handle;});
    const ended=assert.rejects(running,timeout?/响应/:/停止/);if(timeout)timers.fire(60000);else control.abort();await ended;
    resolveAnswer('晚到内容');await Promise.resolve();await Promise.resolve();
    assert.equal(aborts,1);assert.equal(deltas.length,0);assert.equal(timers.jobs.size,0);
  }
});

test('each nonstream adapter exposes cancellation before sending and destroys the client once', async () => {
  for(const protocol of ['openai-compat','gemini','anthropic']) {
    let requests=0,destroyed=0;const {createProvider}=load(`${base}services/ai/ModelProvider.ets`,{
      '@kit.NetworkKit':{http:{createHttp:()=>({request:async()=>{requests++;},destroy:()=>destroyed++})}},'@kit.ArkTS':{util:{}}
    });
    const p=consentProfile({protocol,remoteConsentProtocol:protocol});
    await assert.rejects(createProvider(protocol).complete(p,{messages:[]},handle=>handle.abort()),/取消|停止/);
    assert.equal(requests,0);assert.equal(destroyed,1);
  }
});

function pdfHistoryView() {
  const relative='views/reader/pdf/PdfAnnotatorView.ets';let saved=0;
  const view={pageStrokes:{0:[]},undoStack:[],redoStack:[],eraseBefore:null,erasePage:-1,currentPageIdx:0,scheduleSave:()=>saved++,activeInputFinisher:null,activeInputPage:-1};
  for(const method of ['remember','handleStrokeAdded','beginErase','finishErase','handleEraseAtPoint','handleUndo','onRedoTriggered','onClearTriggered','finishActiveInput'])
    view[method]=viewMethod(relative,method,{InkRenderer});
  return {view,saved:()=>saved};
}
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
      finishStroke:()=>calls.push('stroke'),flushSave:()=>calls.push('save'),shortcuts:{stop(){}},input:{reset(){}}};
    disappear.call(view);assert.deepEqual(calls,isScratchpad||persistOnDisappear?['stroke','save']:[]);assert.equal(view.saveTimer,-1);
  }
});

test('switching companion documents saves the partial reply under the original document only', () => {
  const cache=new Map([['b',[{text:'文档B的对话'}]]]);const globals={COMPANION_CACHE:cache};const relative='views/reader/huawei/HuaweiAiSplitPanel.ets';
  const view={note:{id:'b'},loadedNoteId:'a',messages:[{text:'文档A的问题'}],isLoading:true,accumulated:'文档A的部分答案',
    streamingCard:{id:'answer-a'},streamHandle:{abort(){}},requestId:1,parseCard:text=>({text})};
  for(const method of ['persist','cancelStream','onNoteChanged'])view[method]=viewMethod(relative,method,globals);
  view.onNoteChanged();assert.equal(cache.get('a').at(-1).text,'文档A的部分答案');assert.equal(cache.get('b').length,1);
  assert.equal(view.messages[0].text,'文档B的对话');assert.equal(view.loadedNoteId,'b');assert.equal(view.isLoading,false);
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

const { AssistantTextParser } = load(`${base}services/ai/AssistantTextParser.ets`);
test('assistant output preserves interleaved text, multiple formulas, lists, code and citations', () => {
  const text = '# 回答\n先说明。\n$$a+b$$\n1. 第一步\n$$\nc=d\n$$\n```js\nconst x = 1;\n```\n> 来源：资料第 2 页\n最后说明。';
  const blocks = plain(AssistantTextParser.parse(text));
  assert.deepEqual(blocks.map(b => b.kind), ['heading','paragraph','math','list','math','code','quote','paragraph']);
  assert.equal(blocks[2].text,'a+b'); assert.equal(blocks[4].text,'c=d');
  assert.equal(blocks[5].language,'js'); assert.equal(blocks[5].text,'const x = 1;');
  assert.match(blocks[6].text,/第 2 页/); assert.equal(blocks[7].text,'最后说明。');
});
test('partial assistant streams retain unfinished code and formulas without losing their body', () => {
  assert.deepEqual(plain(AssistantTextParser.parse('说明\n```python\nprint(1)')).map(b=>b.text),['说明','print(1)']);
  assert.equal(AssistantTextParser.parse('$$\nx+y')[0].text,'x+y');
  assert.equal(AssistantTextParser.parse('$$x+y\n下一行')[0].text,'x+y\n下一行');
});
test('assistant tables preserve escaped pipes and surrounding paragraphs', () => {
  const blocks=plain(AssistantTextParser.parse('前文\n| 项目 | 结果 |\n| --- | --- |\n| A \\| B | 通过 |\n后文'));
  assert.deepEqual(blocks.map(b=>b.kind),['paragraph','table','paragraph']);
  assert.deepEqual(blocks[1].rows,[['项目','结果'],['A | B','通过']]);
  assert.equal(blocks[2].text,'后文');
});
test('assistant inline formatting preserves plain text and literal markup that is still streaming', () => {
  const spans=plain(AssistantTextParser.spans('原文 **重点** `code` ~~删除~~ *斜体* 未完 **'));
  assert.deepEqual(spans.filter(s=>s.style!=='plain').map(s=>[s.text,s.style]),[['重点','bold'],['code','code'],['删除','strike'],['斜体','italic']]);
  assert.ok(spans.at(-1).text.endsWith('**'));
});

const { CanvasViewport } = load(`${base}services/ink/CanvasViewport.ets`);
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
    const v={navigateTouch:()=>false,readOnly:false,input:{read:()=>({phase:'cancel'})},saveRevision:pending?2:1,savedRevision:1,
      inkContact:true,currentStroke:{points:[{x:1,y:2}]},onDirtyChange:d=>dirties.push(d),
      liveContext:{clearRect:()=>clears++},redrawAll:()=>redraws++,strokes:[]};
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

test('chat deletion requires confirmation, ignores duplicate taps and waits for actual storage', async () => {
  const remove=viewMethod('pages/Index.ets','handleDeleteSession');let confirm,write;
  const calls=[];const v={sessions:[{id:'a'},{id:'b'}],activeSessionId:'a',sessionDeleteBusy:false,
    confirmDestructive:()=>new Promise(r=>confirm=r),chatStorage:{deleteSession:id=>{calls.push(id);return new Promise(r=>write=r);}},notify:()=>{}};
  const pending=remove.call(v,'a');await remove.call(v,'a');assert.deepEqual(calls,[]);assert.equal(v.sessionDeleteBusy,true);
  confirm(true);await new Promise(resolve=>setTimeout(resolve,0));assert.deepEqual(calls,['a']);assert.equal(v.sessions.length,2);
  write();await pending;assert.deepEqual(v.sessions.map(s=>s.id),['b']);assert.equal(v.activeSessionId,'');assert.equal(v.sessionDeleteBusy,false);
});
test('cancelled or failed chat deletion leaves the original history and selection intact', async () => {
  const remove=viewMethod('pages/Index.ets','handleDeleteSession');
  for(const confirmed of [false,true]) {
    let writes=0;const sessions=[{id:'a'}];const v={sessions,activeSessionId:'a',sessionDeleteBusy:false,confirmDestructive:async()=>confirmed,
      chatStorage:{deleteSession:async()=>{writes++;throw Error('disk');}},notify:()=>{}};
    await remove.call(v,'a');assert.equal(writes,confirmed?1:0);assert.equal(v.sessions,sessions);assert.equal(v.activeSessionId,'a');assert.equal(v.sessionDeleteBusy,false);
  }
});
test('companion clearing requires confirmation and cannot clear a different document after navigation', async () => {
  const relative='views/reader/huawei/HuaweiAiSplitPanel.ets';
  for(const [index,moved,expected] of [[0,false,0],[1,false,1],[1,true,0]]) {
    let resolve,clears=0;const clear=viewMethod(relative,'requestClearThread',{promptAction:{showDialog:()=>new Promise(r=>resolve=r)}});
    const v={isLoading:false,clearConfirmBusy:false,messages:[{text:'keep'}],loadedNoteId:'a',alive:true,palette:()=>({}),clearThread:()=>clears++};
    const pending=clear.call(v);if(moved)v.loadedNoteId='b';resolve({index});await pending;assert.equal(clears,expected);assert.equal(v.clearConfirmBusy,false);
  }
});
test('AI back navigation first closes the anchored action or model menu', () => {
  const back=viewMethod('views/ai/AiWorkspace.ets','handleBackRequest');let exits=0;
  const v={plusMenuOpen:true,modelMenuOpen:false,onNavigateBack:()=>exits++};back.call(v);assert.equal(v.plusMenuOpen,false);assert.equal(exits,0);
  v.modelMenuOpen=true;back.call(v);assert.equal(v.modelMenuOpen,false);assert.equal(exits,0);back.call(v);assert.equal(exits,1);
});

test('deleted conversations reject late streamed answers and stale bulk snapshots', async () => {
  const f=preferenceFixture({sessions:'[]'});
  const {ChatSessionService}=load(`${base}services/ai/ChatSessionService.ets`,{'@kit.ArkData':{preferences:{getPreferences:async()=>f.prefs}}});
  const service=new ChatSessionService();await service.init({});
  const row={id:'late',title:'原回答',messages:[],createdAt:1,updatedAt:1};
  await service.saveSession(row);await service.deleteSession(row.id);
  await assert.rejects(service.saveSession(row),/删除/);await service.saveSessions([row]);
  assert.equal((await service.loadSessions()).length,0);
  await service.saveSession({...row,id:'new'});await service.clearAll();
  await assert.rejects(service.saveSession({...row,id:'new'}),/删除/);
});
test('reader parsing preserves Unicode, source line indices, numbered lists and rich block bodies', () => {
  const relative='views/reader/MarkdownReader.ets';
  const parse=viewMethod(relative,'parseBlocks',{AssistantTextParser});
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
  const transfer={status:'imported',noteType:'PDF',sourceUri:'/sandbox/copy.pdf',pageCount:2,document:{id:'pdf',title:'测试',fileName:'测试.pdf',content:'# 测试'}};
  const v={documentImportBusy:false,notes:[],getAbilityContext:()=>({}),storage:{importDocument:async()=>transfer,save:()=>new Promise(r=>write=r)},
    formatTime:()=>'',rebuildSpaces:()=>calls.push('library'),refreshGraph:()=>{},notify:()=>{}};
  const pending=method.call(v,'外部参考');await new Promise(r=>setTimeout(r,0));assert.equal(v.notes.length,0);
  assert.equal(await method.call(v),null);write();const imported=await pending;assert.equal(v.notes[0],imported);assert.equal(imported.sourceUri,transfer.sourceUri);
  assert.equal(imported.category,'外部参考');assert.equal(v.documentImportBusy,false);assert.deepEqual(calls,['library']);
  v.storage.save=async()=>{throw Error('disk');};const original=v.notes;assert.equal(await method.call(v),null);assert.equal(v.notes,original);assert.equal(v.documentImportBusy,false);
});
test('AI external import waits for persistence and never pins into a different or closed conversation', async () => {
  const method=viewMethod('views/ai/AiWorkspace.ets','importExternalFile',{promptAction:{showToast:()=>{}}});
  for(const moved of [false,true]) {
    let resolve;const v={alive:true,loadedSessionId:'a',activeSessionId:'a',attachmentRequestId:0,pinnedNotes:[],menuActionsAvailable:()=>true,
      onImportExternal:()=>new Promise(r=>resolve=r),emitContext:()=>{},onPinnedNotesChange:()=>{}};
    const pending=method.call(v);assert.equal(v.pinnedNotes.length,0);if(moved)v.loadedSessionId='b';resolve({id:'pdf',title:'PDF'});await pending;
    assert.equal(v.pinnedNotes.length,moved?0:1);
  }
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
    const {PdfDocumentService}=load(`${base}services/document/PdfDocumentService.ets`,{'@kit.PDFKit':{pdfService:{}},
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
test('local formatting has distinct study layout without discarding code, tables, formulas or source', async () => {
  const input = '【课程记录】\n一、基本概念\n• 第一条定义\n• 第二条定义\n\n二、例题\n```python\n    prepare = "提交代码示例"\n```\n\n| 名称 | 数量 |\n| --- | --- |\n| 实验 | 42 |\n\n$$\nx = 42\n$$\n\n$$\ny = 7\n$$';
  const { service, calls } = extractService({ key: 'configured' });
  const faithful = await service.extract(input, '课程', 'faithful');
  const study = await service.extract(input, '课程', 'study');
  assert.equal(calls.length, 0); assert.equal(study.rawMarkdown, input);
  assert.ok(study.formattedMarkdown.includes('## 一、基本概念'));
  assert.ok(study.formattedMarkdown.includes('- 第一条定义'));
  assert.ok(!faithful.formattedMarkdown.includes('## 一、基本概念'));
  assert.ok(faithful.formattedMarkdown.endsWith(input));
  for (const fragment of ['    prepare = "提交代码示例"', '| 实验 | 42 |', '$$\nx = 42\n$$', '$$\ny = 7\n$$']) {
    assert.ok(study.formattedMarkdown.includes(fragment), fragment);
  }
  assert.equal(study.tasks.length, 0);
});

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
  assert.ok(body.endsWith(input)); assert.equal(AiParser.fromSource(input).tasks.length, 0);
});

test('local extraction preserves leading code indentation and explicit trailing line breaks inside the original source', async () => {
  const input = '    prepare = "提交代码示例"\n    total = 42\n\n正常正文  \n下一行';
  const { service, calls } = extractService();
  const result = await service.extract(input, '代码与正文', 'study', false, true);
  assert.equal(result.rawMarkdown, input); assert.equal(result.tasks.length, 0); assert.equal(calls.length, 0);
  assert.ok(result.formattedMarkdown.endsWith(input));
});

test('completed checkboxes, negative clauses and cancelled actions never become calendar suggestions', () => {
  const input = '- [x] 完成课程报名\n- [X] 提交旧报告\n不需要准备材料，也不要提交重复报告。\n报名取消。\n明天提交新的实验报告。';
  const tasks = AiParser.fromSource(input).tasks;
  assert.equal(tasks.length, 1); assert.equal(tasks[0].title, '明天提交新的实验报告');
});

test('failed or unconfigured optional AI keeps the selected local study layout and OCR repair', async () => {
  for (const config of [{}, { key: 'test', fails: true }]) {
    const { service } = extractService(config);
    const input = '一、课程介绍\n这是一段从照片中识别出的课程内容\n继续说明具体要求。';
    const result = await service.extract(input, '课程', 'study', true, true);
    assert.equal(result.processingMode, 'local'); assert.equal(result.rawMarkdown, input);
    assert.ok(result.formattedMarkdown.includes('## 一、课程介绍'));
    assert.ok(result.formattedMarkdown.includes('课程内容继续说明'));
    assert.ok(result.processingNotice.includes('核对'));
  }
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
  assert.equal(SettingsCatalog.search('deepseek API')[0].id, 'ai');
  assert.equal(SettingsCatalog.search('恢复', 'connection')[0].id, 'backup');
  assert.equal(SettingsCatalog.search('恢复', 'workspace').length, 0);
  assert.equal(SettingsCatalog.search('不存在的选项').length, 0);
  assert.equal(new Set(SETTINGS_ENTRIES.map(entry => entry.id)).size, SETTINGS_ENTRIES.length);
  assert.ok(SETTINGS_ENTRIES.every(entry => SETTINGS_GROUPS.some(group => group.id === entry.group)));
  assert.equal(SettingsCatalog.normalize('cloud'), 'backup'); assert.equal(SettingsCatalog.normalize('unknown'), 'overview');
});

test('settings categories and system back wait for the AI draft guard before modifying native page history', () => {
  const navigate = viewMethod('views/settings/SettingsWorkspace.ets', 'navigate', { SettingsCatalog });
  const applyNavigation = viewMethod('views/settings/SettingsWorkspace.ets', 'applyNavigation');
  const calls = [], view = { section: 'ai', pendingSection: 'overview', modelCloseToken: 0, reduceMotion: true,
    paths: { size: () => 1, replacePath: (...args) => calls.push(['replace', ...args]), clear: (...args) => calls.push(['clear', ...args]) } };
  view.applyNavigation = () => applyNavigation.call(view);
  navigate.call(view, 'theme'); assert.equal(view.modelCloseToken, 1); assert.equal(view.section, 'ai'); assert.equal(calls.length, 0);
  // Only the guarded model's successful close callback allows navigation.
  applyNavigation.call(view); assert.equal(view.section, 'theme'); assert.equal(calls[0][2], false);
  navigate.call(view, 'overview'); assert.equal(view.section, 'overview'); assert.deepEqual(calls[1], ['clear', false]);
});

test('leaving settings through the main navigation waits for model draft confirmation and executes the selected action once', () => {
  const requestExit = viewMethod('views/settings/SettingsWorkspace.ets', 'requestExit');
  const applyNavigation = viewMethod('views/settings/SettingsWorkspace.ets', 'applyNavigation');
  let confirmed = 0;
  const view = { section: 'ai', leavePending: false, modelCloseToken: 0, onExitConfirmed: () => confirmed++ };
  view.applyNavigation = () => applyNavigation.call(view);
  requestExit.call(view); assert.equal(view.modelCloseToken, 1); assert.equal(confirmed, 0);
  assert.equal(view.section, 'ai'); applyNavigation.call(view); assert.equal(confirmed, 1); assert.equal(view.leavePending, false);
  const afterExit = viewMethod('pages/Index.ets', 'afterSettingsExit', { NAV_SETTINGS: 'settings' });
  const complete = viewMethod('pages/Index.ets', 'completeSettingsExit', { NAV_HOME: 'home' });
  const shell = { activeNav: 'settings', settingsExitToken: 0, settingsExitAction: null };
  let opened = 0; afterExit.call(shell, () => opened++); assert.equal(opened, 0); assert.equal(shell.settingsExitToken, 1);
  complete.call(shell); assert.equal(opened, 1); assert.equal(shell.activeNav, 'home'); assert.equal(shell.settingsExitAction, null);
});

test('recognition drafts retain layout choices, images and edited results while a save in progress cannot be dismissed', () => {
  const app = new Map(), storage = { setOrCreate: (key, value) => app.set(key, value), get: key => app.get(key) };
  const close = viewMethod('views/layout/sheets/SmartExtractSheet.ets', 'requestClose', { AppStorage: storage });
  const appear = viewMethod('views/layout/sheets/SmartExtractSheet.ets', 'aboutToAppear', { AppStorage: storage,
    REMOTE_AI_ENABLED: true, KeyboardAvoidMode: { RESIZE: 1 } });
  let closed = 0;
  const view = { step: 'result', inputText: '实际输入', imageUri: 'photo://selected', result: { id: 'actual-result' },
    title: '校对标题', category: '课程', body: '校对正文', tasks: [], selectedTaskIds: [], includeRelations: false,
    layoutStyle: 'study', mergeWrappedLines: true, useAi: false, requestId: 0, onClose: () => closed++ };
  close.call(view); assert.equal(closed, 1);
  const restored = { getUIContext: () => ({ getKeyboardAvoidMode: () => 0, setKeyboardAvoidMode: () => {} }) };
  appear.call(restored); assert.equal(restored.layoutStyle, 'study'); assert.equal(restored.mergeWrappedLines, true);
  assert.equal(restored.body, '校对正文'); assert.equal(restored.imageUri, 'photo://selected'); assert.equal(restored.step, 'result');
  view.step = 'saving'; close.call(view); assert.equal(closed, 1);
  app.set('smartExtractResultDraft', { input: '旧草稿', imageUri: '', result: null }); appear.call(restored);
  assert.equal(restored.layoutStyle, 'faithful'); assert.equal(restored.mergeWrappedLines, false); assert.equal(restored.useAi, false);
});

const { AiProviderCatalog } = load(`${base}services/ai/AiProviderCatalog.ets`);
test('provider catalog exposes the requested families without sharing mutable rows, keys or default consent', () => {
  const entries = AiProviderCatalog.list();
  for (const family of ['Seed', 'Qwen', 'DeepSeek', 'GLM']) { assert.ok(entries.some(entry => entry.label.includes(family))); }
  for (const entry of entries) {
    const draft = AiProviderCatalog.createDraft(entry.id, `draft-${entry.id}`);
    assert.equal(draft.apiKey, ''); assert.equal(draft.remoteConsentVersion, undefined); assert.equal(draft.credentialRef, undefined);
    assert.equal(draft.semanticSearch, false); assert.equal(draft.toolAccess, 'none'); assert.ok(draft.baseUrl.startsWith('https://'));
  }
  entries[0].baseUrl = 'https://changed.example.com'; assert.notEqual(AiProviderCatalog.list()[0].baseUrl, entries[0].baseUrl);
  assert.equal(AiProviderCatalog.createDraft('unknown', 'new'), null);
  assert.equal(AiProviderCatalog.createDraft('seed', ''), null);
});

test('choosing a service template creates a fresh draft and preserves the existing unsaved profile and active selection', () => {
  const add = viewMethod('views/settings/ModelSettingsSheet.ets', 'addFromCatalog', { AiProviderCatalog });
  const existing = profile({ id: 'existing', apiKey: 'test-existing-key' });
  const view = { busy: false, currentId: 'existing', activeId: 'existing', profiles: [existing], drafts: new Map(), newProfiles: new Set(),
    form: () => existing, fill(draft) { this.currentId = draft.id; }, report() {} };
  add.call(view, AiProviderCatalog.list()[0]);
  assert.equal(view.drafts.get('existing').apiKey, 'test-existing-key'); assert.equal(view.activeId, 'existing');
  assert.equal(view.profiles.length, 2); assert.equal(view.profiles[1].apiKey, ''); assert.equal(view.newProfiles.size, 1);
  assert.equal(view.sourceTab, 1); assert.equal(view.tab, 0);
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

test('AI attachment import ignores repeated taps while awaiting durable import', async () => {
  const importFile = viewMethod('views/ai/AiWorkspace.ets', 'importExternalFile', { promptAction: { showToast() {} } });
  let release, imports = 0;
  const view = { alive: true, loadedSessionId: 'a', activeSessionId: 'a', attachmentRequestId: 0, attachmentBusy: false,
    menuActionsAvailable() { return !this.attachmentBusy; }, pinnedNotes: [], emitContext() {}, onPinnedNotesChange() {},
    onImportExternal: () => { imports++; return new Promise(resolve => { release = resolve; }); } };
  const pending = importFile.call(view); await importFile.call(view); assert.equal(imports, 1);
  release(null); await pending; assert.equal(view.attachmentBusy, false); assert.deepEqual(view.pinnedNotes, []);
});

test('removing AI references respects newer selections and synchronizes confirmed context', async () => {
  for (const changed of [false, true]) {
    let answer, updates = 0;
    const clear = viewMethod('views/ai/AiWorkspace.ets', 'clearPinnedReferences', {
      promptAction: { showDialog: () => new Promise(resolve => { answer = resolve; }) } });
    const view = { loadedSessionId: 'a', activeSessionId: 'a', pinnedNotes: [{ id: 'old' }], menuActionsAvailable: () => true,
      palette: () => ({}), onPinnedNotesChange() { updates++; }, emitContext() { updates++; } };
    const pending = clear.call(view); if (changed) { view.pinnedNotes = [{ id: 'new' }]; }
    answer({ index: 1 }); await pending;
    assert.deepEqual(plain(view.pinnedNotes), changed ? [{ id: 'new' }] : []); assert.equal(updates, changed ? 0 : 2);
  }
});

test('AI context notifications coalesce latest state and cannot publish after leaving', () => {
  const queued = [], published = [];
  const emit = viewMethod('views/ai/AiWorkspace.ets', 'emitContext', { setTimeout: action => queued.push(action) });
  const view = { alive: true, contextRevision: 0, lastCitations: ['old'], pinnedNotes: [{ id: 'old' }], runningLayer: 'L1',
    layerTitle: layer => layer, modelLabel: 'local', onContextChange: (...args) => published.push(args) };
  emit.call(view); view.pinnedNotes = [{ id: 'new' }]; view.lastCitations = ['new']; emit.call(view);
  queued.splice(0).forEach(action => action()); assert.equal(published.length, 1);
  assert.equal(published[0][1][0].id, 'new'); assert.equal(published[0][0][0], 'new');
  emit.call(view); view.alive = false; queued[0](); assert.equal(published.length, 1);
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
    panX: 4, panY: -8, strokes: [{}], currentStroke: active,
    drawPaperBackground() {}, drawSingleStroke: () => historical++, style: () => ({ color: '#000', width: 18, highlighter: false, eraser: true }) });
  assert.equal(clears, 1); assert.equal(historical, 1);
  assert.ok(recorder.calls.filter(call => ['stroke', 'fill'].includes(call[0])).every(call => call[3] === 'destination-out'));
  assert.ok(recorder.calls.some(call => call[0] === 'line'));
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
