import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

// Run pure ArkTS service logic with platform adapters mocked. HAP compilation
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
    if (specifier.startsWith('.')) {
      return load(path.resolve(path.dirname(filename), `${specifier}.ets`), mocks, cache);
    }
    throw new Error(`Unmocked platform dependency: ${specifier}`);
  };
  vm.runInNewContext(output, { module, exports: module.exports, require: localRequire,
    console, Date, Error, Promise, setTimeout, clearTimeout, AppStorage: mocks.AppStorage }, { filename });
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

function orchestratorFixture(changes = {}, tools = []) {
  const configured = profile(changes); const requests = []; let streamCalls = 0; let completeCalls = 0;
  const provider = { complete: async (_, request) => { completeCalls++; requests.push(request); return '完整答案'; },
    completeStream: async (_, request, onChunk) => {
      streamCalls++; requests.push(request);
      for (let index = 0; index < tools.length; index++) {
        onChunk({ delta: '', done: false, toolCall: { index, id: `call_${index}`, name: tools[index].name, argumentsFragment: JSON.stringify(tools[index].args) } });
      }
      onChunk({ delta: tools.length ? '' : '答案', done: true }); return { abort() {} };
    } };
  const { AgentOrchestrator } = load(`${base}services/ai/AgentOrchestrator.ets`, {
    [path.resolve(root, `${base}services/ai/ModelProvider.ets`)]: { createProvider: () => provider },
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
  const original = profile(); const values = new Map([['profiles', JSON.stringify([original])], ['activeProfileId', original.id]]);
  const publications = []; let fail = true;
  const prefs = { get: async (key, fallback) => values.get(key) ?? fallback, put: async (key, value) => values.set(key, value),
    flush: async () => { if (fail) throw new Error('disk full'); } };
  const { ModelConfigService } = load(`${base}services/ai/ModelConfigService.ets`, {
    '@kit.ArkData': { preferences: { getPreferences: async () => prefs } },
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

function extractService({ key = '', response = '', fails = false } = {}) {
  const calls = [];
  const mocks = {
    [path.resolve(root, `${base}services/ai/ModelConfigService.ets`)]: {
      ModelConfigService: { getInstance: () => ({ getActiveProfile: async () => ({ apiKey: key, protocol: 'openai-compat' }) }) }
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
    const result = await service.extract(source);
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

function pdfService({ status = 0, pageCount = 3, renderFails = false, copyFails = false } = {}) {
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
        }, release: () => calls.push('page-release') };
    }
  }
  class PdfMatrix {}
  const mocks = {
    '@kit.PDFKit': { pdfService: { PdfDocument, PdfMatrix, ParseResult: { PARSE_SUCCESS: 0, PARSE_ERROR_PASSWORD: 3 } } },
    '@kit.CoreFileKit': { fileIo: { OpenMode: { READ_ONLY: 0 }, accessSync: () => true,
      statSync: () => ({ size: 8000 }), openSync: () => ({ fd: 1 }), closeSync: () => calls.push('file-close'),
      copyFile: async () => { if (copyFails) throw Error('disk'); calls.push('copied'); },
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

function importService(uri, { pdfFails = false, writeFails = false, unlinkFails = false, missing = false } = {}) {
  const calls = [];
  const prefs = { get: async () => '', put: async () => {}, flush: async () => {} };
  class DocumentViewPicker { async select() { return uri ? [uri] : []; } }
  class DocumentSelectOptions {}
  const mocks = {
    '@kit.ArkData': { preferences: { getPreferences: async () => prefs } },
    '@kit.CoreFileKit': { picker: { DocumentViewPicker, DocumentSelectOptions },
      fileIo: { OpenMode: { WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 }, access: async () => !missing,
        mkdir: async () => {},
        readText: async () => { calls.push('read-text'); return '# 资料\n\n全文'; },
        open: async () => ({ fd: 1 }), write: async (fd, content) => {
          if (writeFails) throw Error('disk full');
          calls.push(['write', content]);
        }, close: async () => calls.push('close'), unlink: async file => {
          calls.push(['unlink', file]);
          if (unlinkFails) throw Error('permission denied');
        } } },
    [path.resolve(root, `${base}services/document/PdfDocumentService.ets`)]: {
      PdfDocumentService: { getInstance: () => ({ savePdfToSandbox: async () => '/sandbox/copy.pdf',
        getPdfInfo: async () => { if (pdfFails) throw Error('PDF 损坏'); return { pageCount: 2 }; } }) }
    }
  };
  return { calls, service: new (load(`${base}services/NoteStorageService.ets`, mocks).NoteStorageService)() };
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
