import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { test } from 'node:test';

// Executes the SDK's generated partial-update code. This adapter verifies event wiring,
// state subscriptions and the native menu argument contract; it is NOT a device emulator.
const require = createRequire(import.meta.url);
const arg = name => process.argv.includes(name) ? process.argv[process.argv.indexOf(name) + 1] : undefined;
if (!process.argv.includes('--typescript')) throw Error('Pass --typescript <SDK typescript.js> after building the release APP.');
const ts = require(path.resolve(arg('--typescript')));
const root = path.resolve(import.meta.dirname, '..');
const cacheRoot = path.resolve(root, arg('--compiled-dir') || 'entry/build/default/cache/default/default@CompileArkTS/esmodule/release/entry/src/main/ets');

function renderer() {
  let nextId = 0, current = null;
  const records = new Map(), nodes = new Map(), children = new Map(), queue = new Set(), stack = [], modules = new Map();
  const lazySources = [], pdfPages = [];
  const removeBelow = id => {
    for (const [key, record] of records) if (record.parents.includes(id)) { record.active = false; nodes.delete(key); queue.delete(record); }
  };
  class Property {
    constructor(value, owner, name) { Object.assign(this, { value, owner, name, subscribers: new Set() }); }
    get() { if (current) this.subscribers.add(current); return this.value; }
    set(value) {
      if (this.value === value) return;
      this.value = value;
      for (const record of this.subscribers) if (record.active) queue.add(record);
      const watch = this.owner.watches.get(this.name); if (watch) watch.call(this.owner);
    }
    reset(value) { this.set(value); }
    purgeDependencyOnElmtId() {}
    aboutToBeDeleted() {}
  }
  class ViewPU {
    constructor(parent, _, id) { this.parent = parent; this.id = id; this.watches = new Map(); }
    declareWatch(name, action) { this.watches.set(name, action); }
    createStorageProp(_, value, name) { return new Property(value, this, name); }
    finalizeConstruction() {}
    id__() { return this.id; }
    aboutToBeDeletedInternal() {}
    observeComponentCreation2(fn) {
      const record = { id: ++nextId, fn, owner: this, parents: stack.slice(), active: true };
      records.set(record.id, record); const previous = current; current = record;
      fn(record.id, true); current = previous;
    }
    updateStateVarsOfChildByElmtId(id, props) { children.get(id)?.updateStateVars(props); }
    ifElseBranchUpdateFunction(branch, builder) {
      const node = nodes.get(current.id);
      if (node.branch === branch) return;
      removeBelow(current.id); node.branch = branch; builder();
    }
    forEachUpdateFunction(id, values, builder) { removeBelow(id); for (const value of values) builder(value); }
    updateDirtyElements() { flush(); }
    static create(child) {
      children.set(child.id, child); const depth = stack.length; stack.push(child.id);
      child.initialRender(); stack.length = depth;
    }
  }
  class PdfPageAdapter extends ViewPU {
    constructor(parent, props, _, id) { super(parent, _, id); this.props = props; pdfPages.push(this); }
    initialRender() {}
    updateStateVars(props) { Object.assign(this.props, props); }
  }
  const native = name => new Proxy({}, { get: (_, key) => (...args) => {
    if (name === 'Context' && key === 'animateTo') { args[1](); return; }
    const atomic = ['Image', 'TextInput', 'TextArea', 'Slider', 'Circle', 'Divider', 'Canvas'].includes(name);
    if (key === 'pop') { if (!atomic) stack.pop(); return; }
    if (name === 'LazyForEach' && key === 'create') {
      const [, , source, builder, keyFor] = args, id = `lazy-${++nextId}`, parents = stack.slice();
      const entry = { source, keys: [], show(start, count) {
        removeBelow(id); const saved = stack.slice(); stack.splice(0, stack.length, ...parents, id);
        entry.keys = [];
        try {
          for (let index = start; index < Math.min(source.totalCount(), start + count); index++) {
            const page = source.getData(index); entry.keys.push(keyFor(page)); builder(page);
          }
        } finally { stack.splice(0, stack.length, ...saved); }
      } };
      lazySources.push(entry);
      // Explicit visible-window adapter: tests SDK wiring, not ArkUI's physical memory use.
      entry.show(0, 3); stack.push(id); return;
    }
    if (key === 'create' || key === 'createWithChild' || key === 'createWithLabel') {
      let node = nodes.get(current.id);
      if (!node) { node = { id: current.id, type: name, props: {}, parents: stack.slice() }; nodes.set(current.id, node); }
      node.content = args[0]; if (!atomic) stack.push(current.id); return;
    }
    const node = nodes.get(current?.id); if (!node) return;
    node.props[key] = args.length === 1 ? args[0] : args;
    if (key === 'bindMenu') {
      const [show, content, options] = args;
      // The native bridge consumes a builder object. The former arrow function
      // compiled without this wrapper, so this assertion catches that regression.
      assert.equal(typeof content?.builder, 'function', 'native bindMenu requires a builder object');
      if (show && !node.menuOpen) {
        node.menuOpen = true; const depth = stack.length; stack.push(node.id);
        content.builder(); stack.length = depth;
      } else if (!show && node.menuOpen) {
        node.menuOpen = false; removeBelow(node.id); options?.onDisappear?.();
      }
    }
    if (key === 'bindPopup') {
      const [show, options] = args;
      assert.equal(typeof options.builder?.builder, 'function', 'native popup requires a builder object');
      if (show && !node.popupOpen) {
        node.popupOpen = true; const depth = stack.length; stack.push(node.id);
        options.builder.builder(); stack.length = depth;
      } else if (!show && node.popupOpen) { node.popupOpen = false; removeBelow(node.id); }
    }
  } });
  const enums = new Proxy({}, { get: (_, key) => String(key) });
  const inert = new Proxy(function () {}, {
    construct: () => new Proxy({}, { get: () => () => {} }),
    get: (_, key) => key === 'getInstance' ? () => new Proxy({}, { get: () => () => {} }) : enums[key]
  });
  const globals = { console, ViewPU, ObservedPropertySimplePU: Property, ObservedPropertyObjectPU: Property,
    ObservedObject: { GetRawObject: value => value },
    SynchedPropertySimpleOneWayPU: Property, SynchedPropertyObjectOneWayPU: Property,
    SubscriberManager: { Get: () => ({ delete() {} }) },
    AppStorage: { get() {}, setOrCreate() {} }, getContext: () => ({}),
    setTimeout: () => 1, clearTimeout() {}, setInterval: () => 1, clearInterval() {},
    animateTo: (_, action) => action(), RenderingContextSettings: inert, CanvasRenderingContext2D: inert, OffscreenCanvas: inert, Scroller: inert,
    TransitionEffect: new Proxy({}, { get: (_, key) => key === 'OPACITY' ? { animation() { return this; } } : () => ({ combine() { return this; }, animation() { return this; } }) }),
    SourceTool: { Finger: 1, Pen: 2 }, TouchType: { Down: 0, Up: 1, Move: 2, Cancel: 3 } };
  for (const name of ['Button', 'Column', 'Row', 'Text', 'Blank', 'Image', 'Stack', 'Scroll', 'TextInput', 'TextArea',
    'Divider', 'Canvas', 'Circle', 'Menu', 'MenuItem', 'MenuItemGroup', 'If', 'ForEach', 'LazyForEach', 'Slider', 'Flex', 'Context', 'List', 'ListItem', 'Swiper', 'GridRow', 'GridCol', '__Common__', 'Gesture', 'PinchGesture']) globals[name] = native(name);
  for (const name of ['ButtonType', 'FontWeight', 'Color', 'HorizontalAlign', 'FlexAlign', 'TextAlign', 'TextOverflow',
    'ScrollDirection', 'BarState', 'Alignment', 'ItemAlign', 'Placement', 'Curve', 'HitTestMode', 'HoverEffect',
    'GestureMode', 'GestureDirection', 'GesturePriority', 'GestureJudgeResult', 'ScrollAlign', 'TransitionEdge', 'ModifierKey', 'ImageFit', 'ImageInterpolation', 'SliderStyle', 'FlexWrap', 'FlexDirection', 'ItemAlign', 'ResponseType', 'VerticalAlign', 'InputType']) globals[name] = enums;
  const realViews = new Set(['views/common/IconButton', 'views/common/AppIcon', 'views/common/InkWidthSlider',
    'views/reader/HandwritingCanvas', 'views/ai/AiWorkspace', 'views/ai/ChatHistorySidebar',
    'views/reader/huawei/HuaweiDocWorkspace', 'views/reader/pdf/PdfAnnotatorView', 'views/reader/pdf/PdfPageCanvas', 'views/layout/Sidebar', 'views/brand/BrandMark', 'views/workspace/HomeWorkspace']);
  function load(relative, compiled = realViews.has(relative)) {
    const key = `${compiled}:${relative}`; if (modules.has(key)) return modules.get(key).exports;
    const file = path.join(compiled ? cacheRoot : path.join(root, 'entry/src/main/ets'), relative + (compiled ? '.ts' : '.ets'));
    const module = { exports: {} }; modules.set(key, module);
    const localRequire = specifier => {
      if (specifier === 'BuildProfile') return { DEBUG: false, default: { DEBUG: false } };
      if (specifier.startsWith('@kit.') || specifier.startsWith('@ohos:')) return new Proxy({}, { get: () => inert });
      const match = specifier.match(/&&&entry\/src\/main\/ets\/(.*?)&/);
      const dependency = match?.[1] || (specifier.startsWith('.') ? path.posix.normalize(path.posix.join(path.posix.dirname(relative), specifier)) : '');
      if (!dependency) throw Error(`Unmapped import ${specifier}`);
      if (dependency === 'views/reader/pdf/PdfPageCanvas') return { PdfPageCanvas: PdfPageAdapter };
      if (realViews.has(dependency)) return load(dependency, true);
      if (dependency.startsWith('common/') || dependency.startsWith('services/ink/') || dependency === 'services/document/PdfPageDataSource' || dependency === 'services/ai/ChatHistoryPolicy' || dependency === 'services/ai/AiReferenceSearch') {
        if (dependency.endsWith('StylusShortcutService')) return { StylusShortcutService: inert };
        return load(dependency, false);
      }
      return new Proxy({}, { get: () => inert });
    };
    const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
    vm.runInNewContext(output, { ...globals, module, exports: module.exports, require: localRequire }, { filename: file });
    return module.exports;
  }
  function flush() {
    let count = 0;
    while (queue.size) {
      if (++count > 2000) throw Error('Partial update loop');
      const record = queue.values().next().value; queue.delete(record); if (!record.active) continue;
      const previous = current, saved = stack.slice(); current = record; stack.splice(0, stack.length, ...record.parents);
      record.fn(record.id, false); stack.splice(0, stack.length, ...saved); current = previous;
    }
  }
  const find = label => [...nodes.values()].find(node => node.props.accessibilityText === label || node.content === label || node.content?.content === label);
  return { load, nodes, flush, find, lazySources, pdfPages, mount(relative, name, props, method = 'initialRender', setup) {
    const Component = load(relative, true)[name]; const view = new Component(null, props, undefined, ++nextId);
    setup?.(view);
    view[method](); flush(); return view;
  }, click(label) {
    const node = find(label); assert.ok(node, `Missing ${label}`); assert.notEqual(node.props.enabled, false, `Disabled ${label}`);
    assert.equal(typeof node.props.onClick, 'function', `No click action: ${label}`); node.props.onClick(); flush();
  } };
}

test('compiled whiteboard click updates the actual eraser button, icon and pen selection', () => {
  const ui = renderer(); const view = ui.mount('views/reader/HandwritingCanvas', 'HandwritingCanvas', { note: { id: 'ink', title: '课堂' } });
  assert.equal(ui.find('普通笔').props.backgroundColor, view.palette().accentSoft);
  ui.click('橡皮'); assert.equal(ui.find('橡皮').props.backgroundColor, view.palette().accentSoft);
  const eraser = ui.find('橡皮');
  const eraserIcon = [...ui.nodes.values()].find(node => node.type === 'Image' && node.parents.includes(eraser.id));
  assert.equal(eraserIcon.props.fillColor, view.palette().accent);
  assert.notEqual(ui.find('普通笔').props.backgroundColor, view.palette().accentSoft);
  ui.click('荧光笔'); assert.equal(ui.find('荧光笔').props.backgroundColor, view.palette().accentSoft);
  assert.equal(eraserIcon.props.fillColor, view.palette().inkSecondary);
  assert.notEqual(ui.find('橡皮').props.backgroundColor, view.palette().accentSoft);
});

test('compiled AI plus and more open real menu items; switching and outside dismissal reset state', () => {
  const ui = renderer(); const view = ui.mount('views/ai/AiWorkspace', 'AiWorkspace', {});
  ui.click('添加资料与任务'); assert.equal(view.plusMenuOpen, true); assert.ok(ui.find('引用库内资料'));
  assert.equal(ui.find('讲解引用资料').props.enabled, false);
  ui.click('引用库内资料'); assert.equal(view.pickerOpen, true); assert.equal(view.plusMenuOpen, false);
  ui.click('对话操作'); assert.equal(view.conversationMenuOpen, true); assert.ok(ui.find('助手与模型设置'));
  const menu = [...ui.nodes.values()].find(node => node.props.bindMenu?.[0] === true);
  menu.props.bindMenu[2].onDisappear(); ui.flush(); assert.equal(view.conversationMenuOpen, false);
  ui.click('添加资料与任务'); assert.equal(view.plusMenuOpen, true);
  let toggles = 0; view.onToggleHistory = () => { toggles++; view.historyOpen = !view.historyOpen; };
  ui.click('对话记录'); assert.equal(toggles, 1); assert.equal(ui.find('对话记录').props.backgroundColor, view.palette().accentSoft);
  ui.click('对话记录'); assert.equal(toggles, 2); assert.equal(view.historyOpen, false);
  const unchanged = Object.fromEntries(['currentNote', 'todos', 'reviewCards', 'stats', 'activeSessionId', 'externalPinnedNotes',
    'prefilledPrompt', 'toolsEnabled', 'contextPanelOpen', 'backRequestToken', 'historyOpen'].map(name => [name, view[name]]));
  view.updateStateVars({ ...unchanged, allNotes: [{ id: 'new', title: '新导入的资料', type: 'Markdown' }] }); ui.flush();
  assert.equal(view.pickerCandidates()[0].id, 'new');
  view.sessionLoadBusy = true; ui.flush(); assert.ok(ui.find('正在读取对话…'));
  assert.equal(ui.find('添加资料与任务').props.enabled, false);
  assert.equal(ui.find('新建对话').props.enabled, false);
  view.sessionLoadBusy = false; view.sessionLoadError = '对话读取失败'; ui.flush();
  assert.ok(ui.find('重新读取')); assert.equal(ui.find('添加资料与任务').props.enabled, false);
  assert.equal(ui.find('新建对话').props.enabled, true);
  let retried = 0; view.loadSessionById = () => { retried++; }; ui.click('重新读取'); assert.equal(retried, 1);
});

test('compiled compact reader enters writable annotation and restores the single reading row on return', () => {
  const ui = renderer(); const view = ui.mount('views/reader/huawei/HuaweiDocWorkspace', 'HuaweiDocWorkspace', { note: { id: 'pdf', title: '课堂', type: 'Doc', tag: 'PDF', sourceType: 'pdf' } }, 'topNavigationBar');
  assert.ok(ui.find('批注')); assert.equal(ui.find('打开稿纸分屏'), undefined);
  view.pdfSourceReady = true; ui.click('批注'); assert.ok(ui.find('橡皮')); assert.equal(ui.find('批注'), undefined);
  assert.equal(view.fingerDrawing, true);
  assert.equal(ui.find('打开稿纸分屏'), undefined);
  ui.click('橡皮'); assert.equal(view.currentTool, 'eraser');
  assert.equal(ui.find('橡皮').props.backgroundColor, view.palette().accentSoft);
  view.beginReaderSave = () => {}; ui.click('返回阅读并保存批注');
  assert.equal(view.isAnnotateMode, false); assert.ok(ui.find('批注')); assert.equal(ui.find('橡皮'), undefined);
});

test('compiled floating pen is a real button and enters document ink even after using the pan tool', () => {
  const ui = renderer(); const view = ui.mount('views/reader/huawei/HuaweiDocWorkspace', 'HuaweiDocWorkspace',
    { note: { id: 'pdf', type: 'Doc', sourceType: 'pdf', sourceUri: '/book.pdf' } }, 'floatingBall');
  view.pdfSourceReady = true; view.currentTool = 'pan'; view.splitMode = 'scratchpad';
  assert.equal(ui.find('打开批注工具').type, 'Button'); ui.click('打开批注工具');
  assert.equal(view.isAnnotateMode, true); assert.equal(view.currentTool, 'pen');
  assert.equal(view.inkTarget, 'document'); assert.equal(view.fingerDrawing, true);
});

test('compiled corner page count opens a bounded input popup and rejects invalid jumps', () => {
  const ui = renderer(); const view = ui.mount('views/reader/huawei/HuaweiDocWorkspace', 'HuaweiDocWorkspace',
    { note: { id: 'pdf', sourceType: 'pdf', pageCount: 600 } }, 'bottomReadingConsole', view => { view.totalPages = 600; });
  const label = '当前第 1 页，共 600 页，点击跳转';
  assert.equal(ui.find(label).props.position.x, 8); assert.equal(ui.find(label).props.position.y, '100%');
  ui.click(label); assert.equal(view.jumpDialogOpen, true);
  const input = ui.find('输入跳转页码'); input.props.onChange('600'); ui.flush(); ui.click('跳转');
  assert.equal(view.currentPage, 600); assert.equal(view.jumpDialogOpen, false);
  view.showToast = () => {}; view.jumpPageInput = '601'; view.submitPageJump(); assert.equal(view.currentPage, 600);
});

test('compiled whole-page pager swipes vertically, keeps page callbacks bound and protects finger ink', () => {
  const ui = renderer(), selected = [], erased = [];
  const pages = Array.from({ length: 4 }, (_, pageIndex) => ({ pageIndex }));
  const view = ui.mount('views/reader/pdf/PdfAnnotatorView', 'PdfAnnotatorView', {
    note: { id: 'book', pageCount: 4 }, isContinuousScroll: false, onPageChanged: page => selected.push(page)
  }, 'initialRender', view => { view.pages = pages; view.pageDataSource.setPages(pages); });
  const pager = [...ui.nodes.values()].find(node => node.type === 'Swiper');
  assert.equal(pager.props.vertical, true); assert.equal(pager.props.loop, false); assert.equal(pager.props.disableSwipe, false);
  pager.props.onChange(2); ui.flush(); assert.equal(view.currentPageIdx, 2); assert.deepEqual(selected, [3]);
  view.beginErase = index => erased.push(index); ui.pdfPages[1].props.onEraseStarted(); assert.deepEqual(erased, [1]);
  view.isAnnotateMode = true; view.fingerDrawing = true; ui.flush(); assert.equal(pager.props.disableSwipe, true);
  view.currentTool = 'pan'; ui.flush(); assert.equal(pager.props.disableSwipe, false);
  view.zoomScale = 2; ui.flush(); assert.equal(pager.props.disableSwipe, true);
});

test('compiled document more contains working scratchpad and companion navigation actions', () => {
  const ui = renderer(); const view = ui.mount('views/reader/huawei/HuaweiDocWorkspace', 'HuaweiDocWorkspace', { note: { id: 'pdf', title: '课堂', type: 'Doc', tag: 'PDF', sourceType: 'pdf' } }, 'topNavigationBar');
  ui.click('更多文档操作'); assert.ok(ui.find('打开随堂稿纸'));
  ui.click('打开随堂稿纸'); assert.equal(view.splitMode, 'scratchpad'); assert.equal(view.documentMenuOpen, false);
  ui.click('更多文档操作'); ui.click('打开 AI 伴读'); assert.equal(view.splitMode, 'ai');
});

test('compiled history replaces navigation, filters rows and retains callbacks for a selected conversation', () => {
  const ui = renderer(); const selected = [];
  const sessions = [{ id: 'a', title: '数学笔记', messages: [{ role: 'user', text: '复习线性代数' }], updatedAt: Date.now(), pinned: false },
    { id: 'b', title: '英语阅读', messages: [], updatedAt: 1, pinned: true }];
  const view = ui.mount('views/layout/Sidebar', 'Sidebar', { historyOpen: true, sessions, onSelectSession: session => selected.push(session.id) });
  assert.equal(ui.find('项目与资料'), undefined); assert.ok(ui.find('对话记录'));
  ui.click('打开对话：数学笔记'); assert.deepEqual(selected, ['a']);
  const input = [...ui.nodes.values()].find(node => node.type === 'TextInput'); input.props.onChange('英语'); ui.flush();
  assert.equal(ui.find('打开对话：数学笔记'), undefined); assert.ok(ui.find('打开对话：英语阅读'));
  view.historyOpen = false; ui.flush(); assert.ok(ui.find('项目与资料')); assert.equal(ui.find('对话记录'), undefined);
});

test('compiled shelf has bounded initial cards, no cover shortcut and retains cover selection in the context menu', () => {
  const ui = renderer(), chosen = [];
  const notes = Array.from({ length: 30 }, (_, i) => ({ id: String(i), title: `笔记 ${i}`, type: 'Markdown', category: '课程', tag: '', updatedAt: i }));
  const view = ui.mount('views/workspace/HomeWorkspace', 'HomeWorkspace', { recentNotes: notes, onChooseCover: id => chosen.push(id) });
  assert.equal(ui.find('选择笔记封面'), undefined);
  assert.ok(ui.find('笔记 29')); assert.equal(ui.find('笔记 0'), undefined);
  ui.click('显示更多资料 · 已显示 12 / 30'); assert.ok(ui.find('笔记 6'));
  view.cardContextMenu(notes[0]); ui.flush(); ui.click('更换封面'); assert.deepEqual(chosen, ['0']);
});

test('compiled page model subscription preserves readiness for tools but invalidates a different page', () => {
  const ui = renderer(); const view = ui.mount('views/reader/pdf/PdfPageCanvas', 'PdfPageCanvas',
    { pageModel: { pageIndex: 0 }, sourceUri: '/book.pdf' });
  view.setSourceReady(true); view.pageModel = { pageIndex: 0 }; view.isAnnotateMode = true; ui.flush();
  assert.equal(view.sourceReady, true);
  assert.ok([...ui.nodes.values()].some(node => node.type === 'Stack' && typeof node.props.onTouch === 'function'));
  view.pageModel = { pageIndex: 1 }; ui.flush(); assert.equal(view.sourceReady, false);
});

test('compiled textbook uses a lazy page source and routes last-page annotation callbacks correctly', () => {
  const ui = renderer(), erased = [], strokes = [], selected = [];
  const pages = Array.from({ length: 600 }, (_, pageIndex) => ({ pageIndex, width: 595, height: 842, title: `教材 ${pageIndex + 1}` }));
  const view = ui.mount('views/reader/pdf/PdfAnnotatorView', 'PdfAnnotatorView', {
    note: { id: 'book', title: '教材', sourceUri: '/files/book.pdf', pageCount: 600 }, onPageChanged: page => selected.push(page)
  }, 'initialRender', view => { view.pages = pages; view.pageDataSource.setPages(pages); });
  const list = [...ui.nodes.values()].find(node => node.type === 'List');
  assert.equal(list.props.cachedCount, 1); assert.equal(ui.lazySources.length, 1);
  const lazy = ui.lazySources[0]; assert.equal(lazy.source.totalCount(), 600);
  assert.equal(ui.pdfPages.length, 3); assert.deepEqual(lazy.keys, ['page_0', 'page_1', 'page_2']);
  lazy.show(598, 2); assert.equal(ui.pdfPages.length, 5); assert.deepEqual(lazy.keys, ['page_598', 'page_599']);
  const last = ui.pdfPages.at(-1); assert.equal(last.props.pageModel.pageIndex, 599);
  view.beginErase = index => erased.push(index); view.handleStrokeAdded = stroke => strokes.push(stroke);
  last.props.onEraseStarted(); last.props.onStrokeAdded({ pageIndex: 599 });
  assert.deepEqual(erased, [599]); assert.equal(strokes[0].pageIndex, 599);
  list.props.onScrollIndex(599); ui.flush(); assert.equal(view.currentPageIdx, 599); assert.deepEqual(selected, [600]);
});
