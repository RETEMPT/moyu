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
    if (specifier.startsWith('.')) {
      return load(path.resolve(path.dirname(filename), `${specifier}.ets`), mocks, cache);
    }
    throw new Error(`Unmocked platform dependency: ${specifier}`);
  };
  vm.runInNewContext(output, { module, exports: module.exports, require: localRequire,
    console, Date, Error, Promise, setTimeout: mocks.setTimeout || setTimeout, clearTimeout: mocks.clearTimeout || clearTimeout,
    canIUse: mocks.canIUse || (() => true), AppStorage: mocks.AppStorage }, { filename });
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
      PdfDocumentService: { getInstance: () => ({ savePdfToSandbox: async () => '/sandbox/copy.pdf',
        getPdfInfo: async () => { if (pdfFails) throw Error('PDF 损坏'); return { pageCount: 2 }; } }) }
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
      getPdfInfo: async filename => { if (failPdf) throw Error('broken pdf'); return { pageCount: 2 }; }
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
  const { seedNotes } = load(`${base}common/seed/SeedContent.ets`); const f = backupFileFixture();
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
  await assert.rejects(service.clearAll(), /阻止覆盖/); assert.equal(f.values.get('sessions'), '{broken');
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
    const view = { saveRevision: 1, strokeSnapshot: studyNote, annotationSnapshot: studyNote,
      onSaved: () => new Promise(resolve => { release = resolve; }), onSaveStateChange: value => statuses.push(value) };
    const running = flush.call(view); await Promise.resolve(); assert.equal(statuses.length, 0);
    view.saveRevision++; release(); await running; assert.equal(statuses.length, 0);
    view.onSaved = async () => { throw Error('disk'); }; await flush.call(view); assert.deepEqual(statuses, ['保存失败']);
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

const { AiModelCatalog } = load(`${base}services/ai/AiModelCatalog.ets`);
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

test('loopback Ollama template is usable without a credential or an empty bearer header', async () => {
  const { getPresetTemplates } = load(`${base}common/types/ModelConfig.ets`);
  const draft = getPresetTemplates().find(p => p.profile.baseUrl.startsWith('http://127.0.0.1')).profile;
  assert.equal(draft.apiKey, ''); assert.equal(ModelProfilePolicy.validate(draft), '');
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

function compatibleStreamFixture() {
  const events = new Map(), chunks = []; let resolveStatus, destroyed = 0;
  const { createProvider } = load(`${base}services/ai/ModelProvider.ets`, {
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
