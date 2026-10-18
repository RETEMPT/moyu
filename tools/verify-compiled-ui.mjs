import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { resolveTypeScript } from './resolve-typescript.mjs';

// Executes the SDK's generated partial-update code. This adapter verifies event wiring,
// state subscriptions and the native menu argument contract; it is NOT a device emulator.
const arg = name => process.argv.includes(name) ? process.argv[process.argv.indexOf(name) + 1] : undefined;
const ts = resolveTypeScript();
const root = path.resolve(import.meta.dirname, '..');
const cacheRoot = path.resolve(root, arg('--compiled-dir') || 'entry/build/default/cache/default/default@CompileArkTS/esmodule/release/entry/src/main/ets');

function renderer() {
  let nextId = 0, current = null;
  const records = new Map(), nodes = new Map(), children = new Map(), queue = new Set(), stack = [], modules = new Map();
  const storedValues = new Map(), storageProperties = new Map();
  const lazySources = [], pdfPages = [], serviceAdapters = new Map();
  const toasts = [];
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
    createStorageProp(key, value, name) {
      const property = new Property(storedValues.has(key) ? storedValues.get(key) : value, this, name);
      if (!storageProperties.has(key)) storageProperties.set(key, new Set());
      storageProperties.get(key).add(property); return property;
    }
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
    forEachUpdateFunction(id, values, builder) { removeBelow(id); values.forEach((value, index) => builder(value, index)); }
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
    const atomic = ['Web', 'Image', 'TextInput', 'TextArea', 'Slider', 'Circle', 'Divider', 'Canvas', 'Path', 'TapGesture'].includes(name);
    if (key === 'pop') { if (!atomic) stack.pop(); return; }
    if (name === 'TapGesture' && key === 'create') { nodes.get(current.id).props.tapGesture = args[0]; return; }
    if (name === 'TapGesture' && key === 'onAction') { nodes.get(current.id).props.onDoubleTap = args[0]; return; }
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
      node.content = args[0]; if (!atomic) stack.push(current.id);
      if (name === 'ListItem' && typeof args[0] === 'function' && !node.deferredBuilt) {
        node.deferredBuilt = true; args[0](current.id, true);
      }
      return;
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
    ViewStackProcessor: { StartGetAccessRecordingFor() {}, StopGetAccessRecording() {} },
    $r: name => ({ resourceName: name }),
    AppStorage: { get: key => storedValues.get(key), setOrCreate(key, value) {
      storedValues.set(key, value); for (const property of storageProperties.get(key) || []) property.set(value);
    } }, getContext: () => ({}),
    setTimeout: () => 1, clearTimeout() {}, setInterval: () => 1, clearInterval() {},
    animateTo: (_, action) => action(), RenderingContextSettings: inert, CanvasRenderingContext2D: inert, OffscreenCanvas: inert, Scroller: inert, TextAreaController: inert, NavPathStack: inert,
    TransitionEffect: new Proxy({}, { get: (_, key) => key === 'OPACITY' ? { animation() { return this; } } : () => ({ combine() { return this; }, animation() { return this; } }) }),
    SourceTool: { Finger: 1, Pen: 2 }, TouchType: { Down: 0, Up: 1, Move: 2, Cancel: 3 } };
  for (const name of ['Web', 'Button', 'Column', 'Row', 'Text', 'Span', 'Blank', 'Image', 'Stack', 'Scroll', 'TextInput', 'TextArea',
    'Divider', 'Canvas', 'Circle', 'Path', 'Menu', 'MenuItem', 'MenuItemGroup', 'If', 'ForEach', 'LazyForEach', 'Slider', 'Flex', 'Context', 'List', 'ListItem', 'Swiper', 'GridRow', 'GridCol', 'Grid', 'GridItem', '__Common__', 'Gesture', 'PinchGesture', 'PanGesture', 'TapGesture', 'LongPressGesture', 'Checkbox', 'Toggle', 'LoadingProgress']) globals[name] = native(name);
  for (const name of ['ButtonType', 'FontWeight', 'Color', 'HorizontalAlign', 'FlexAlign', 'TextAlign', 'TextOverflow',
    'ScrollDirection', 'BarState', 'Alignment', 'ItemAlign', 'Placement', 'Curve', 'HitTestMode', 'HoverEffect', 'Visibility', 'LineCapStyle',
    'GestureMode', 'GestureDirection', 'GesturePriority', 'GestureJudgeResult', 'ScrollAlign', 'TransitionEdge', 'ModifierKey', 'ImageFit', 'ImageInterpolation', 'SliderStyle', 'FlexWrap', 'FlexDirection', 'ItemAlign', 'ResponseType', 'VerticalAlign', 'InputType', 'FontStyle', 'TextDecorationType', 'CopyOptions', 'ToggleType', 'SafeAreaType', 'KeyType']) globals[name] = enums;
  const realViews = new Set(['views/layout/sheets/NewProjectSheet', 'views/common/IconButton', 'views/common/AppIcon', 'views/common/InkWidthSlider', 'views/common/DocumentText',
    'views/reader/HandwritingCanvas', 'views/reader/InkCanvasSurface', 'views/common/DocumentPreview', 'views/common/DocumentCover', 'views/workspace/GraphWorkspace', 'views/layout/BottomNavBar', 'views/settings/SettingsWorkspace',
    'views/reader/huawei/HuaweiDocWorkspace', 'views/reader/ReaderPairPicker', 'views/reader/ReaderSplitWorkspace', 'views/reader/ReaderWorkspace', 'views/layout/sheets/NoteMenuSheet', 'views/layout/sheets/RenameNoteSheet', 'views/layout/sheets/MoveNoteSheet', 'views/layout/sheets/SheetScaffold', 'views/reader/huawei/HuaweiDocActionDialog', 'views/reader/MarkdownReader', 'views/reader/pdf/PdfAnnotatorView', 'views/reader/pdf/PdfPageCanvas', 'views/layout/AppShell', 'views/layout/GlobalTopBar', 'views/layout/Sidebar', 'views/brand/BrandMark', 'views/workspace/HomeWorkspace', 'views/workspace/LibraryWorkspace', 'views/workspace/TodoWorkspace', 'views/workspace/TrashWorkspace', 'views/explore/QuickSearchDialog', 'views/layout/sheets/SmartExtractSheet', 'views/study/StudyBackupSheet']);
  function load(relative, compiled = realViews.has(relative)) {
    const key = `${compiled}:${relative}`; if (modules.has(key)) return modules.get(key).exports;
    const file = path.join(compiled ? cacheRoot : path.join(root, 'entry/src/main/ets'), relative + (compiled ? '.ts' : '.ets'));
    const module = { exports: {} }; modules.set(key, module);
    const localRequire = specifier => {
      if (specifier === 'BuildProfile' || specifier.endsWith('/BuildProfile&')) return { DEBUG: false, default: { DEBUG: false } };
      if (specifier === '@ohos:promptAction') return { default: { showToast: options => toasts.push(options.message), showDialog: async () => ({ index: 0 }) } };
      if (specifier === '@ohos:arkui.node') return { ColorMetrics: { resourceColor: color => {
        assert.match(color, /^#[\da-f]{6}$/i);
        return { red: parseInt(color.slice(1, 3), 16), green: parseInt(color.slice(3, 5), 16), blue: parseInt(color.slice(5, 7), 16), alpha: 255 };
      } } };
      if (specifier === '@ohos:graphics.drawing') return { default: { BlendMode: { SRC_IN: 'SRC_IN' },
        ColorFilter: { createBlendModeColorFilter: (color, mode) => ({ color, mode }) } } };
      if (specifier === '@ohos:web.webview') return { default: { WebviewController: inert } };
      if (specifier.startsWith('@kit.') || specifier.startsWith('@ohos:')) return new Proxy({}, { get: () => inert });
      const match = specifier.match(/&&&entry\/src\/main\/ets\/(.*?)&/);
      const dependency = match?.[1] || (specifier.startsWith('.') ? path.posix.normalize(path.posix.join(path.posix.dirname(relative), specifier)) : '');
      if (!dependency) throw Error(`Unmapped import ${specifier}`);
      if (serviceAdapters.has(dependency)) return serviceAdapters.get(dependency);
      if (dependency === 'views/reader/pdf/PdfPageCanvas') return { PdfPageCanvas: PdfPageAdapter };
      if (realViews.has(dependency) || ['views/common/QuickMemoComposer', 'views/common/MemoTimelineCard', 'views/common/MemoCalendar'].includes(dependency)) return load(dependency, true);
      if (dependency.startsWith('common/') || dependency.startsWith('services/ink/') || dependency.startsWith('services/library/') || dependency === 'services/WorkspaceNotePolicy' || dependency === 'services/WorkspaceBuilder' || dependency === 'services/study/StudySourceService' || dependency === 'services/document/ReadingProgressPolicy' || dependency === 'services/document/PdfPageDataSource' || dependency === 'services/GraphTopicPolicy' || dependency === 'services/document/ReaderPairPolicy' || dependency === 'services/document/MarkdownEditing' || dependency === 'services/document/DocumentTextParser' || dependency === 'services/document/SourceTextStructure' || dependency === 'services/smart/SmartNoteBuilder') {
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
  return { load, nodes, children, flush, find, lazySources, pdfPages, toasts, storage: globals.AppStorage, service: (name, adapter) => serviceAdapters.set(name, adapter), mount(relative, name, props, method = 'initialRender', setup) {
    const Component = load(relative, true)[name]; const view = new Component(null, props, undefined, ++nextId);
    setup?.(view);
    view[method](); flush(); return view;
  }, click(label) {
    const node = find(label); assert.ok(node, `Missing ${label}`); assert.notEqual(node.props.enabled, false, `Disabled ${label}`);
    assert.equal(typeof node.props.onClick, 'function', `No click action: ${label}`); const result = node.props.onClick({ stopPropagation() {} }); flush(); return result;
  } };
}

function assertIconTint(node, hex) {
  assert.equal(node.props.fillColor, undefined, 'SVG outline interiors must stay transparent');
  assert.equal(node.props.supportSvg2, true);
  assert.equal(node.props.colorFilter.mode, 'SRC_IN');
  assert.deepEqual(JSON.parse(JSON.stringify(node.props.colorFilter.color)), {
    red: parseInt(hex.slice(1, 3), 16), green: parseInt(hex.slice(3, 5), 16), blue: parseInt(hex.slice(5, 7), 16), alpha: 255
  });
}

test('compiled whiteboard click updates the actual eraser button, icon and pen selection', () => {
  const ui = renderer(); const view = ui.mount('views/reader/HandwritingCanvas', 'HandwritingCanvas', { note: { id: 'ink', title: '课堂' } });
  assert.equal(ui.find('普通笔').props.backgroundColor, view.palette().accentSoft);
  ui.click('橡皮'); assert.equal(ui.find('橡皮').props.backgroundColor, view.palette().accentSoft);
  const eraser = ui.find('橡皮');
  const eraserIcon = [...ui.nodes.values()].find(node => node.type === 'Image' && node.parents.includes(eraser.id));
  assertIconTint(eraserIcon, view.palette().accent);
  assert.notEqual(ui.find('普通笔').props.backgroundColor, view.palette().accentSoft);
  ui.click('荧光笔'); assert.equal(ui.find('荧光笔').props.backgroundColor, view.palette().accentSoft);
  assertIconTint(eraserIcon, view.palette().inkSecondary);
  assert.notEqual(ui.find('橡皮').props.backgroundColor, view.palette().accentSoft);
});

for (const type of ['PDF','Image','Handwriting','Canvas']) {
  test(`compiled ${type} shares the persistent toolbar and lock saves before making ink read-only`,()=>{
    const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',{
      note:{id:'a',title:'资料',type,sourceType:type==='Image'?'image':'pdf',sourceUri:'/files/source'}
    },'topNavigationBar',v=>{v.pdfSourceReady=true;v.whiteboardReady=true;});
    assert.ok(ui.find('普通笔'));assert.equal(ui.find('普通笔').props.enabled,true);assert.ok(ui.find('解锁批注'));
    ui.click('普通笔');assert.equal(view.isAnnotateMode,true);assert.equal(ui.find('普通笔').props.enabled,true);
    assert.equal(view.penOptionsOpen,false);assert.equal(ui.find('更多笔设置'),undefined);
    ui.click('橡皮');assert.equal(view.activeModal,'');assert.equal(view.penOptionsOpen,false);
    if(type==='Handwriting'||type==='Canvas')assert.equal(view.canvasCommand.action,'eraser');else assert.equal(view.currentTool,'eraser');
    ui.click('锁定只读并保存批注');assert.equal(view.isAnnotateMode,false);assert.equal(view.exitSaving,true);assert.equal(view.exitSaveToken,1);
    assert.ok(ui.find('普通笔'));assert.equal(ui.find('普通笔').props.enabled,false);
  });
}

test('compiled lock returns to document pen after using pan and exposes no floating duplicate button',()=>{
  const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',{
    note:{id:'a',type:'PDF',sourceType:'pdf',sourceUri:'/book.pdf'}
  },'topNavigationBar',v=>{v.pdfSourceReady=true;v.currentTool='pan';v.splitMode='scratchpad';});
  ui.click('解锁批注');assert.equal(view.isAnnotateMode,true);assert.equal(view.currentTool,'pen');
  assert.equal(view.inkTarget,'document');assert.equal(ui.find('打开批注工具'),undefined);
});

test('compiled dedicated whiteboard header omits all filenames and tabs while sharing ink and output tools',()=>{
  const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',{
    note:{id:'canvas-global',type:'canvas',title:'内部画布存储名'},isFreeCanvas:true,
    documentTabs:[{id:'pdf',title:'课本.pdf',type:'PDF'}]},'topNavigationBar',v=>{v.whiteboardReady=true;});
  assert.equal(ui.find('内部画布存储名'),undefined);assert.equal(ui.find('课本.pdf'),undefined);
  assert.equal([...ui.nodes.values()].some(n=>n.props.id==='reader-tabs'),false);
  assert.ok(ui.find('保存正文截图'));ui.click('普通笔');assert.equal(view.isAnnotateMode,true);
  ui.find('普通笔').props.onDoubleTap();ui.flush();assert.equal(view.penOptionsOpen,true);
});

test('compiled unloaded source rejects tool activation with feedback and retains read-only mode',()=>{
  const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',{
    note:{id:'broken',type:'PDF',sourceType:'pdf',sourceUri:'/book.pdf'}},'topNavigationBar');
  ui.click('普通笔');assert.equal(view.isAnnotateMode,false);assert.equal(view.penOptionsOpen,false);
  assert.equal(ui.toasts.length,1);assert.match(ui.toasts[0],/页面读取/);
  assert.equal(ui.find('普通笔').props.opacity,undefined);
});

test('compiled document sidebar keeps project expansion, home navigation and collapse connected',()=>{
  const ui=renderer(),calls=[];
  ui.mount('views/layout/Sidebar','Sidebar',{activeNav:'首页',spaces:[{id:'math',name:'课程笔记',count:0,isOpen:false,notes:[]}],
    onSelectNav:key=>calls.push(key),onToggleSpace:key=>calls.push(key),onToggleSidebar:()=>calls.push('collapse')});
  assert.ok(ui.find('主页'));assert.equal(ui.find('记录日历上个月'),undefined);
  ui.click('项目 课程笔记，0 份资料');ui.click('资料库');ui.click('收起侧栏');assert.deepEqual(calls,['math','资料库','collapse']);
});

test('compiled memo calendar selects and clears local days and navigates across a year boundary',()=>{
  const ui=renderer(),dates=[];
  const view=ui.mount('views/common/MemoCalendar','MemoCalendar',{
    notes:[{id:'a',type:'Markdown',createdAt:new Date(2026,11,17,8).getTime()}],
    onSelectDate:date=>dates.push(date)},'initialRender',v=>{v.year=2026;v.month=11;});
  ui.click('2026-12-17，1 条记录');assert.deepEqual(dates,['2026-12-17']);
  view.selectedDate='2026-12-17';ui.flush();ui.click('2026-12-17，1 条记录');assert.deepEqual(dates,['2026-12-17','']);
  ui.click('记录日历下个月');assert.equal(view.year,2027);assert.equal(view.month,0);
  ui.click('记录日历上个月');assert.equal(view.year,2026);assert.equal(view.month,11);
});

test('compiled shape popup routes geometry to each source adapter without exposing pen parameters',()=>{
  for(const type of ['PDF','Image','Handwriting','Canvas']) {
    const ui=renderer(),view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',
      {note:{id:'a',type,title:'资料',sourceType:type==='Image'?'image':'pdf'}},'topNavigationBar',v=>{v.pdfSourceReady=true;v.whiteboardReady=true;});
    ui.click('图形工具');assert.equal(view.isAnnotateMode,false);assert.ok(ui.find('绘制矩形'));
    assert.equal(ui.find('批注颜色 #2563EB'),undefined);
    ui.click('绘制矩形');assert.equal(view.isAnnotateMode,true);assert.equal(view.shapeOptionsOpen,false);
    if(type==='PDF'||type==='Image') assert.equal(view.currentTool,'rectangle');else assert.equal(view.canvasCommand.action,'rectangle');
  }
});

test('compiled paper popup provides persistent paper commands and read-only viewport reset only on canvas',()=>{
  const ui=renderer(),view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',
    {note:{id:'a',type:'Canvas',title:'白板'}},'topNavigationBar',v=>{v.whiteboardReady=true;});
  ui.click('纸张与视图');assert.ok(ui.find('使用白纸'));assert.ok(ui.find('使用横线'));assert.ok(ui.find('使用方格'));
  ui.click('回到起点');assert.equal(view.canvasCommand.action,'resetView');assert.equal(view.isAnnotateMode,false);
  ui.click('纸张与视图');ui.click('使用横线');assert.equal(view.canvasCommand.action,'paper');assert.equal(view.canvasCommand.value,'ruled');assert.equal(view.isAnnotateMode,true);
  const pdf=renderer();pdf.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',{note:{id:'pdf',type:'PDF'}},'topNavigationBar');
  assert.equal(pdf.find('纸张与视图'),undefined);
  const split=renderer(),source=split.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',
    {note:{id:'pdf',type:'PDF'}},'topNavigationBar',v=>{v.pdfSourceReady=true;v.splitMode='scratchpad';v.inkTarget='scratchpad';});
  split.click('纸张与视图');split.click('使用方格');
  assert.equal(source.inkTarget,'scratchpad');assert.equal(source.canvasCommand.target,'scratchpad');assert.equal(source.canvasCommand.value,'grid');
});

test('compiled covers share a readable title and real metadata without rendering body or ink',()=>{
  for(const extra of [{type:'Markdown',label:'笔记'},{type:'Markdown',label:'笔记',coverUrl:'cover:sage'},
    {type:'PDF',label:'PDF',pageCount:507},{type:'Doc',sourceType:'pdf',label:'PDF',pageCount:507},
    {type:'Image',label:'图片',sourceType:'image',sourceUri:'/photo.jpg'},
    {type:'Canvas',label:'手写',strokes:'[{"points":[{"x":-80,"y":-30},{"x":10,"y":20}]}]'}]) {
    const ui=renderer();ui.mount('views/common/DocumentPreview','DocumentPreview',
      {note:{id:'a',title:'真实标题',contentDetail:'不能冒充封面的正文',previewText:'不能冒充封面的摘录',...extra}});
    const frame=[...ui.nodes.values()].find(n=>n.type==='Stack'&&n.props.border?.radius===8);
    assert.ok(frame);assert.equal(frame.props.clip,true);
    assert.ok(ui.find('真实标题'));assert.ok(ui.find(extra.label));
    assert.equal(ui.find('不能冒充封面的正文'),undefined);assert.equal(ui.find('不能冒充封面的摘录'),undefined);
    assert.equal([...ui.nodes.values()].some(n=>n.type==='Canvas'),false);
    assert.equal(Boolean(ui.find('507 页')),extra.pageCount===507);
  }
  const empty=renderer();empty.mount('views/common/DocumentPreview','DocumentPreview',
    {note:{id:'board',type:'Canvas',title:'自由白板',strokes:'[]',contentDetail:'# 自由白板\n[白纸手写笔记]'}});
  assert.ok(empty.find('自由白板'));assert.ok(empty.find('手写'));
  assert.equal(empty.find('0 页'),undefined);assert.equal(empty.find('1 页'),undefined);
  assert.equal(empty.find('[白纸手写笔记]'),undefined);
});

test('compiled corner page count opens a bounded input popup and rejects invalid jumps', () => {
  const ui = renderer(); const view = ui.mount('views/reader/huawei/HuaweiDocWorkspace', 'HuaweiDocWorkspace',
    { note: { id: 'pdf', type: 'PDF', sourceType: 'pdf', pageCount: 600 } }, 'bottomReadingConsole', view => { view.totalPages = 600; view.pdfSourceReady = true; });
  const label = '当前第 1 页，共 600 页，点击跳转';
  assert.equal(ui.find('上一页').props.enabled,false);ui.click('下一页');assert.equal(view.currentPage,2);
  ui.click('上一页');assert.equal(view.currentPage,1);ui.click('切换为逐页阅读');assert.equal(view.isContinuousScroll,false);
  ui.click(label); assert.equal(view.jumpDialogOpen, true);
  const input = ui.find('输入跳转页码'); input.props.onChange('600'); ui.flush(); ui.click('跳转');
  assert.equal(view.currentPage, 600); assert.equal(view.jumpDialogOpen, false);assert.equal(ui.find('下一页').props.enabled,false);
  view.showToast = () => {}; view.jumpPageInput = '601'; view.submitPageJump(); assert.equal(view.currentPage, 600);
});

test('compiled output dialog selects a real file format, cancels without invoking output and locks repeat submissions',()=>{
  const calls=[],ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocActionDialog','HuaweiDocActionDialog',{
    note:{id:'a',title:'课程'},dialogType:'export_text',onConfirm:value=>calls.push(value),onClose:()=>calls.push('close')});
  ui.click('导出格式 纯文本');ui.click('选择位置');assert.deepEqual(calls,['.txt']);
  view.busy=true;ui.flush();assert.equal(ui.find('处理中…').props.enabled,false);assert.equal(ui.find('取消').props.enabled,false);
  view.busy=false;ui.flush();ui.click('取消');assert.deepEqual(calls,['.txt','close']);
});

test('compiled output results show retry for errors and completion only for successful operations',()=>{
  const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocActionDialog','HuaweiDocActionDialog',{
    note:{id:'a',title:'课程'},dialogType:'export_image',failed:true,resultMessage:'存储空间不足'});
  assert.ok(ui.find('重试'));assert.equal(ui.find('完成'),undefined);
  view.failed=false;view.resultMessage='正文截图已保存';ui.flush();assert.ok(ui.find('完成'));assert.equal(ui.find('选择保存位置'),undefined);
});

test('compiled pen settings stay inside the double-tap popup, with a usable precise color input',()=>{
  const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',
    {note:{id:'a',type:'PDF',title:'课程'}},'topNavigationBar',v=>{v.pdfSourceReady=true;});
  ui.click('解锁批注');ui.click('普通笔');assert.equal(view.penOptionsOpen,false);assert.equal(ui.find('批注颜色 #2563EB'),undefined);
  assert.equal(ui.find('普通笔').props.tapGesture.count,2);assert.equal(ui.find('普通笔').props.tapGesture.fingers,1);
  ui.find('普通笔').props.onDoubleTap();ui.flush();assert.equal(view.penOptionsOpen,true);assert.ok(ui.find('批注颜色 #2563EB'));
  ui.click('笔宽 6 px');assert.equal(view.selectedWidth,6);ui.click('批注颜色 #2563EB');assert.equal(view.selectedColor,'#2563EB');
  ui.find('自定义颜色，6 位十六进制').props.onChange('ab12ef');ui.click('应用');assert.equal(view.selectedColor,'#AB12EF');
  ui.click('收起笔设置');ui.click('橡皮');assert.equal(view.penOptionsOpen,false);
  ui.find('橡皮').props.onDoubleTap();ui.flush();assert.ok(ui.find('区域擦除'));ui.click('区域擦除');assert.equal(view.pdfEraserMode,'area');
  assert.equal(ui.find('批注颜色 #2563EB'),undefined);ui.click('清空本页笔迹');assert.equal(view.clearDialogOpen,true);assert.equal(view.clearTrigger,0);
});

test('compiled home actions use the real navigation ports and recent card uses actual note data',()=>{
  const ui=renderer(),calls=[];ui.mount('views/workspace/HomeWorkspace','HomeWorkspace',{
    recentNotes:[{id:'new',title:'最新课程',type:'PDF',category:'数学',updateTime:'今天',updatedAt:9,lastReadAt:10}],
    onSearchNotes:()=>calls.push('search'),onCreateNote:()=>calls.push('create'),onImportDocument:()=>calls.push('import'),onSelectNote:note=>calls.push(note.id)});
  ui.click('搜索笔记、正文或标签');ui.click('新建笔记');ui.click('导入资料');ui.click('继续打开 最新课程');
  assert.deepEqual(calls,['search','create','import','new']);
  const grid=[...ui.nodes.values()].find(n=>n.type==='GridRow');
  assert.equal(grid.content.columns,2);assert.equal([...ui.nodes.values()].filter(n=>n.type==='GridCol').length,4);
  assert.equal(ui.find('Ctrl K'),undefined);assert.equal(ui.find('本机记录'),undefined);
});

test('compiled native transfer requires an explicit selection and guards repeat taps while packaging',async()=>{
  const ui=renderer(),calls=[];let release;
  ui.service('services/study/StudyBackupService',{StudyBackupService:{createShareFile:async(context,notes,cards)=>{
    calls.push(['package',notes.map(n=>n.id)]);await new Promise(resolve=>{release=resolve;});return '/cache/study-share/study_1_abc.flowmind.json';
  }}});
  ui.service('services/SystemShareService',{SystemShareService:{shareBackup:async(context,file,count)=>calls.push(['native',file,count])}});
  const view=ui.mount('views/study/StudyBackupSheet','StudyBackupSheet',{notes:[{id:'a',title:'讲义',category:'课程'},{id:'b',title:'随记',category:'课程'}]});
  assert.equal(ui.find('附近快传').props.enabled,false);assert.equal(ui.find('导出文件').props.enabled,false);
  assert.equal(ui.find('选择快传资料 讲义'),undefined);ui.click('展开分享文件夹 课程');
  ui.click('选择快传资料 讲义');assert.deepEqual(Array.from(view.selectedIds),['a']);assert.equal(ui.find('附近快传').props.enabled,true);
  const pending=view.shareSelected();ui.flush();assert.equal(ui.find('附近快传').props.enabled,false);
  await view.shareSelected();assert.equal(calls.length,1);release();await pending;ui.flush();
  assert.deepEqual(calls,[['package',['a']],['native','/cache/study-share/study_1_abc.flowmind.json',1]]);
  assert.ok(ui.find('已打开系统分享，请选择接收设备并确认。'));assert.equal(view.busy,false);
  view.notes=[];ui.flush();assert.equal(view.selectedIds.length,0);assert.equal(ui.find('附近快传').props.enabled,false);
});

test('compiled transfer fails visibly and a closed sheet cannot open a late native chooser',async()=>{
  for(const closed of [false,true]) {
    const ui=renderer();let resolvePackage;let shares=0;
    ui.service('services/study/StudyBackupService',{StudyBackupService:{createShareFile:async()=>closed?await new Promise(resolve=>{resolvePackage=resolve;}):Promise.reject(Error('附件未完整读取'))}});
    ui.service('services/SystemShareService',{SystemShareService:{shareBackup:async()=>{shares++;}}});
    const view=ui.mount('views/study/StudyBackupSheet','StudyBackupSheet',{notes:[{id:'a',title:'讲义',category:'课程'}]});
    ui.click('展开分享文件夹 课程');
    ui.click('选择快传资料 讲义');const pending=view.shareSelected();
    if(closed){view.aboutToDisappear();resolvePackage('/cache/file.json');}
    await pending;ui.flush();assert.equal(shares,0);
    if(!closed){assert.equal(view.busy,false);assert.ok(ui.find('附件未完整读取'));assert.deepEqual(Array.from(view.selectedIds),['a']);}
  }
});

test('compiled sharing uses actual project order and independently selects folders or individual files',()=>{
  const ui=renderer(),notes=[{id:'a',title:'讲义一',category:'课程'},{id:'b',title:'讲义二',category:'课程'},
    {id:'c',title:'想法',category:'灵感'},{id:'d',title:'未归档',category:''}];
  const view=ui.mount('views/study/StudyBackupSheet','StudyBackupSheet',{notes,spaces:[
    {id:'ideas',name:'灵感'},{id:'course',name:'课程'},{id:'empty',name:'空文件夹'}]});
  assert.deepEqual(Array.from(view.folders(),f=>f.name),['灵感','课程','未分类']);assert.equal(ui.find('展开分享文件夹 空文件夹'),undefined);
  assert.equal(ui.find('选择快传资料 讲义一'),undefined);ui.click('选择整个文件夹 课程');
  assert.deepEqual(Array.from(view.selectedIds),['a','b']);assert.equal(ui.find('选择整个文件夹 课程').props.accessibilityDescription,'全部已选');
  ui.click('展开分享文件夹 课程');ui.click('选择快传资料 讲义一');assert.deepEqual(Array.from(view.selectedIds),['b']);
  assert.equal(ui.find('选择整个文件夹 课程').props.accessibilityDescription,'部分已选');
  ui.click('选择整个文件夹 灵感');ui.click('选择整个文件夹 课程');assert.deepEqual(new Set(view.selectedIds),new Set(['a','b','c']));
  ui.click('选择整个文件夹 课程');assert.deepEqual(Array.from(view.selectedIds),['c']);
  ui.click('展开分享文件夹 未分类');assert.equal(ui.find('选择快传资料 讲义一'),undefined);assert.ok(ui.find('选择快传资料 未归档'));
  ui.click('全选');assert.equal(view.selectedIds.length,4);ui.click('取消全选');assert.equal(view.selectedIds.length,0);
});

test('compiled folder sharing bounds expansion while folder selection includes files beyond the visible window',()=>{
  const ui=renderer();const notes=Array.from({length:65},(_,i)=>({id:'n'+i,title:'文件'+i,category:'大文件夹'}));
  const view=ui.mount('views/study/StudyBackupSheet','StudyBackupSheet',{notes});
  ui.click('展开分享文件夹 大文件夹');assert.ok(ui.find('选择快传资料 文件39'));assert.equal(ui.find('选择快传资料 文件40'),undefined);
  ui.click('选择整个文件夹 大文件夹');assert.equal(view.selectedIds.length,65);ui.click('显示更多资料');assert.ok(ui.find('选择快传资料 文件64'));
  ui.click('选择快传资料 文件64');assert.equal(view.selectedIds.length,64);assert.equal(ui.find('选择整个文件夹 大文件夹').props.accessibilityDescription,'部分已选');
  view.notes=notes.slice(0,2);ui.flush();assert.deepEqual(Array.from(view.selectedIds),['n0','n1']);assert.equal(ui.find('选择快传资料 文件64'),undefined);
});

test('compiled library keeps views direct and secondary filters in one expandable panel',()=>{
  const ui=renderer();const view=ui.mount('views/workspace/LibraryWorkspace','LibraryWorkspace',{notes:[],totalCount:0});
  assert.equal(ui.find('更新时间'),undefined);assert.ok(ui.find('显示方式：列表'));assert.equal(ui.find('阅读状态：阅读中'),undefined);
  assert.equal(ui.find('导入资料').props.height,44);assert.equal(ui.find('搜索资料标题、正文与标签').props.height,48);
  ui.click('资料筛选与排序');assert.equal(view.optionsExpanded,true);assert.ok(ui.find('更新时间'));assert.ok(ui.find('阅读状态：阅读中'));
  assert.ok(ui.find('还没有标签，在正文中输入 #标签 即可创建。'));
  ui.click('资料筛选与排序');assert.equal(view.optionsExpanded,false);assert.equal(ui.find('更新时间'),undefined);
});

test('compiled quick memo composer keeps text on errors, sends one explicit save and disables empty or busy submission',()=>{
  const ui=renderer(),calls=[];const view=ui.mount('views/common/QuickMemoComposer','QuickMemoComposer',{
    text:'草稿 #复习',ready:true,status:'草稿未能保存',onSave:()=>calls.push('save'),onRetryDraft:()=>calls.push('retry'),onChange:value=>calls.push(value)});
  assert.equal(ui.find('保存记录').props.enabled,true);assert.equal(ui.find('保存记录').props.height,44);
  ui.click('重试草稿');ui.click('保存记录');assert.deepEqual(calls,['retry','save']);assert.equal(view.text,'草稿 #复习');
  ui.find('随手记正文').props.onChange('下一段');assert.equal(calls[2],'下一段');
  view.saving=true;ui.flush();assert.equal(ui.find('保存中').props.enabled,false);assert.equal(ui.find('随手记正文').props.enabled,false);
  view.saving=false;view.text=' ';ui.flush();assert.equal(ui.find('保存记录').props.enabled,false);
});

test('compiled library connects persistent display choices and reading filters to actual visible data',()=>{
  const ui=renderer(),calls=[];
  const note={id:'a',title:'随手记一',type:'Markdown',category:'随手记',tag:'复习',tags:['复习'],contentDetail:'记录正文',previewText:'记录正文',updateTime:'今天',createdAt:1,updatedAt:1};
  const view=ui.mount('views/workspace/LibraryWorkspace','LibraryWorkspace',{notes:[note],allNotes:[note],totalCount:1,
    onViewModeChange:mode=>calls.push(mode),onOpenTag:tag=>calls.push(tag)});
  ui.click('显示方式：时间流');assert.deepEqual(calls,['timeline']);
  view.viewMode='timeline';ui.flush();assert.ok(ui.find('文字记录按创建时间倒序排列'));assert.ok(ui.find('打开记录 随手记一'));
  ui.click('查看标签 复习');assert.deepEqual(calls,['timeline','复习']);
  view.viewMode='list';ui.flush();ui.click('资料筛选与排序');ui.click('阅读状态：阅读中');assert.equal(view.displayNotes().length,0);assert.ok(ui.find('没有匹配的资料'));
  ui.click('清除筛选');assert.equal(view.displayNotes().length,1);
});

test('compiled home more button opens a working menu without opening the note',()=>{
  const ui=renderer(),opened=[],fav=[];const note={id:'a',title:'课程',type:'Markdown',category:'数学',tag:'',updateTime:'今天'};
  ui.mount('views/workspace/HomeWorkspace','HomeWorkspace',{recentNotes:[note],onSelectNote:note=>opened.push(note.id),onToggleFavorite:note=>fav.push(note.id)});
  ui.click('笔记操作 课程');assert.deepEqual(opened,[]);ui.click('☆ 加入收藏');assert.deepEqual(fav,['a']);assert.deepEqual(opened,[]);
});

test('compiled phone Markdown toolbar opens explicit output and share dialogs, and simple editing stays immediate',()=>{
  const ui=renderer();const view=ui.mount('views/reader/MarkdownReader','MarkdownReader',{
    note:{id:'a',title:'课程',category:'数学'}},'editorToolbar',v=>{v.isPhone=true;});
  ui.click('导出笔记文字');assert.equal(view.outputAction,'export_text');view.closeOutput();
  ui.click('保存正文截图');assert.equal(view.outputAction,'export_image');view.closeOutput();
  ui.click('更多笔记操作');ui.click('分享笔记文字');assert.equal(view.outputAction,'share_text');
  view.closeOutput();view.enterEdit=()=>{view.isEditing=true;};ui.click('编辑笔记');assert.equal(view.isEditing,true);assert.equal(view.outputAction,'');
});

test('compiled phone handwriting and PDF tools keep a 44vp mode switch with accessible labels and no squeezed status text',()=>{
  for(const type of ['Canvas','PDF']) {
    const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',{
      note:{id:'a',title:'课程',type,sourceType:type==='PDF'?'pdf':undefined}},'topNavigationBar',v=>{v.isPhone=true;v.whiteboardReady=true;v.pdfSourceReady=true;});
    const toggle=ui.find('解锁批注');assert.equal(toggle.props.width,44);assert.equal(toggle.props.height,44);assert.equal(ui.find('只读'),undefined);
    for(const tool of ['普通笔','荧光笔','橡皮']) {assert.equal(ui.find(tool).props.height,44);assert.equal(ui.find(tool).props.width,44);}
    ui.click('普通笔');assert.equal(view.isAnnotateMode,true);assert.ok(ui.find('锁定只读并保存批注'));assert.equal(ui.find('可批注'),undefined);
  }
});

test('compiled project dialog selects consistent SVG icons with 44vp targets and persists the chosen semantic value',async()=>{
  const ui=renderer(),created=[];const view=ui.mount('views/layout/sheets/NewProjectSheet','NewProjectSheet',{
    onCreateProject:async(...args)=>{created.push(args);return true;}});
  const grid=[...ui.nodes.values()].find(n=>n.type==='GridRow');assert.equal(grid.content.columns,4);
  for(const label of ['文件夹','计划','课本','灵感','实验','工作','目标','创作']) {
    assert.equal(ui.find('项目图标 '+label).props.height,44);
  }
  assert.equal(ui.find('📚'),undefined);assert.ok(ui.find('关闭新建项目'));ui.click('项目图标 课本');
  assert.equal(view.icon,'line:books');assert.equal(ui.find('项目图标 课本').props.accessibilityDescription,'已选择');
  ui.find('项目名称').props.onChange('课本');await view.submit();assert.equal(created[0][0],'课本');assert.equal(created[0][2],'line:books');
  const icons=ui.load('common/utils/ProjectIcons',false);
  assert.equal(icons.projectIcon('📚').resourceName,icons.projectIcon('line:books').resourceName);
  assert.equal(icons.projectIcon('unknown').resourceName,'app.media.ic_folder');
});

test('compiled text reader keeps its title, metadata and output toolbar in the layout while scrolling',()=>{
  const ui=renderer();const view=ui.mount('views/reader/MarkdownReader','MarkdownReader',{
    note:{id:'text',title:'课程正文',category:'数学',type:'Markdown',tag:'',tagColor:'',updateTime:'今天',contentDetail:'',previewText:''}},'initialRender',v=>{v.title='课程正文';});
  const body=[...ui.nodes.values()].find(n=>n.props.id==='markdown-body-text');
  assert.ok(body);assert.equal(body.props.onScroll,undefined);assert.ok(ui.find('课程正文'));
  assert.ok(ui.find('保存正文截图'));assert.equal(ui.find('展开文档工具栏'),undefined);
  assert.equal(view.toolbarExpanded,undefined);
});

test('compiled phone todo keeps the selected week and accessible task state without duplicate statistics',()=>{
  const ui=renderer(),toggled=[];const todos=[{id:'a',date:'2026-10-17',title:'复习定积分',done:false,noteRefs:[]},{id:'b',date:'2026-10-17',title:'整理笔记',done:true,noteRefs:[]}];
  const view=ui.mount('views/workspace/TodoWorkspace','TodoWorkspace',{todos,onToggleTodo:todo=>toggled.push(todo.id)},'initialRender',v=>{v.isPhone=true;v.year=2026;v.month=9;v.selectedDate='2026-10-17';});
  assert.equal(view.visibleCells().length,7);assert.equal(ui.find('当日完成 1 / 2'),undefined);
  assert.ok(ui.find('标为未完成 整理笔记'));
  assert.equal(ui.find('完成待办 复习定积分').props.width,44);ui.click('完成待办 复习定积分');assert.deepEqual(toggled,['a']);
  ui.click('展开月历');assert.ok(view.visibleCells().length>7);assert.equal(view.selectedDate,'2026-10-17');
});

test('compiled image uses the shared document menu for original exports and shares',()=>{
  const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',{
    note:{id:'a',type:'Image',title:'扫描页',sourceType:'image',sourceUri:'/files/documents/a.png'}
  });
  ui.click('导出原始图片');assert.equal(view.activeModal,'export_original');assert.ok(ui.find('完整原图，不含新增笔迹'));ui.click('取消');
  ui.click('更多文档操作');assert.equal(ui.find('重新关联原 PDF'),undefined);assert.equal(ui.find('导出笔记文字'),undefined);
  ui.click('分享原始图片');assert.equal(view.activeModal,'share_image');assert.ok(ui.find('继续分享'));
  assert.ok(ui.find('分享原文件，不含新增笔迹\n通过系统面板选择接收方'));ui.click('取消');assert.equal(view.activeModal,'');
});

test('compiled session tabs select and close the requested document and preserve new-note action',()=>{
  const ui=renderer(),selected=[],closed=[],created=[];
  const tabs=[{id:'a',title:'PDF课本',type:'PDF'},{id:'b',title:'几何图片',type:'Image',sourceType:'image'}];
  ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',{
    note:tabs[0],documentTabs:tabs,onSelectDocument:id=>selected.push(id),onCloseDocumentTab:id=>closed.push(id),onCreateHandwriting:()=>created.push(true)
  },'topNavigationBar');
  ui.click('打开资料 几何图片');ui.click('关闭标签 几何图片');ui.click('新建手写笔记');
  assert.deepEqual(selected,['b']);assert.deepEqual(closed,['b']);assert.deepEqual(created,[true]);
});

test('compiled whole-page pager swipes vertically, keeps page callbacks bound and protects finger ink', () => {
  const ui = renderer(), selected = [], erased = [];
  const pages = Array.from({ length: 4 }, (_, pageIndex) => ({ pageIndex }));
  const view = ui.mount('views/reader/pdf/PdfAnnotatorView', 'PdfAnnotatorView', {
    note: { id: 'book', type:'PDF', pageCount: 4 }, isContinuousScroll: false, onPageChanged: page => selected.push(page)
  }, 'initialRender', view => { view.pages = pages; view.pageDataSource.setPages(pages); });
  const pager = [...ui.nodes.values()].find(node => node.type === 'Swiper');
  assert.equal(pager.props.vertical, true); assert.equal(pager.props.loop, false); assert.equal(pager.props.disableSwipe, false);
  pager.props.onChange(2); ui.flush(); assert.equal(view.currentPageIdx, 2); assert.deepEqual(selected, [3]);
  view.beginErase = index => erased.push(index); ui.pdfPages[1].props.onEraseStarted(); assert.deepEqual(erased, [1]);
  view.isAnnotateMode = true; view.fingerDrawing = true; ui.flush(); assert.equal(pager.props.disableSwipe, true);
  view.currentTool = 'pan'; ui.flush(); assert.equal(pager.props.disableSwipe, false);
  view.zoomScale = 2; ui.flush(); assert.equal(pager.props.disableSwipe, true);
});

test('compiled document more contains working scratchpad navigation without removed companion actions', () => {
  const ui = renderer(); const view = ui.mount('views/reader/huawei/HuaweiDocWorkspace', 'HuaweiDocWorkspace', { note: { id: 'pdf', title: '课堂', type: 'Doc', tag: 'PDF', sourceType: 'pdf' } }, 'topNavigationBar');
  ui.click('更多文档操作'); assert.ok(ui.find('打开随堂稿纸'));
  ui.click('打开随堂稿纸'); assert.equal(view.splitMode, 'scratchpad'); assert.equal(view.documentMenuOpen, false);
  ui.click('更多文档操作'); assert.equal(ui.find('打开 AI 伴读'), undefined);
});

test('compiled home feed is bounded, text-only and has direct pinned and date filtering', () => {
  const ui=renderer(),opened=[];
  const notes=Array.from({length:30},(_,i)=>({id:String(i),title:`记录 ${i}`,type:'Markdown',createdAt:i+1,isPinned:i===0}));
  notes.push({id:'pdf',title:'PDF资料',type:'PDF',createdAt:100});
  const view=ui.mount('views/workspace/HomeWorkspace','HomeWorkspace',{recentNotes:notes,onSelectNote:n=>opened.push(n.id)});
  assert.ok(ui.find('打开记录 记录 29'));assert.equal(ui.find('打开记录 记录 0'),undefined);
  assert.equal(ui.find('打开记录 PDF资料'),undefined);
  ui.click('显示更多记录 · 已显示 12 / 30');assert.ok(ui.find('打开记录 记录 6'));
  ui.click('置顶');assert.ok(ui.find('打开记录 记录 0'));assert.equal(view.displayNotes().length,1);
  ui.click('打开记录 记录 0');assert.deepEqual(opened,['0']);
  ui.click('按日期与标签筛选');assert.ok(ui.find('记录日历上个月'));
});

for (const singleColumn of [true, false]) {
  test(`compiled ${singleColumn ? 'compact' : 'wide'} homepage retains date and tag filtering outside the sidebar`, () => {
    const ui = renderer(), dates = [], tags = [];
    const today = new Date(); today.setHours(8, 0, 0, 0);
    const dateKey = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;
    ui.mount('views/workspace/HomeWorkspace', 'HomeWorkspace', {
      recentNotes: [{ id: 'memo', title: '课程', type: 'Markdown', tags: ['复习'], createdAt: today.getTime() }],
      onSelectDate: date => dates.push(date), onOpenTag: tag => tags.push(tag)
    }, 'initialRender', view => { view.singleColumn = singleColumn; });
    assert.equal(ui.find('记录日历上个月'), undefined);
    ui.click('按日期与标签筛选');
    ui.click(`${dateKey}，1 条记录`); ui.click('#复习 1');
    assert.deepEqual(dates, [dateKey]); assert.deepEqual(tags, ['复习']);
    ui.click('按日期与标签筛选'); assert.equal(ui.find('记录日历上个月'), undefined);
  });
}

test('compiled shell preserves docked and overlay collapse rules across window sizes', () => {
  const ui = renderer();
  const shell = ui.mount('views/layout/AppShell', 'AppShell', { sidebarCollapsed: false });
  for (const width of [360, 600, 839, 840, 1199, 1200]) {
    shell.updateLayout(width); ui.flush();
    assert.equal(shell.isSidebarDocked(), width >= 840);
    assert.equal(shell.isSidebarOverlay(), width < 840);
    assert.equal(ui.storage.get('flowmindSingleColumn'), width < 840);
    shell.sidebarCollapsed = true; ui.flush();
    assert.equal(shell.isSidebarDocked(), false); assert.equal(shell.isSidebarOverlay(), false);
    shell.sidebarCollapsed = false; ui.flush();
  }
});

test('compiled page model subscription preserves readiness for tools but invalidates a different page', () => {
  const ui = renderer(); const view = ui.mount('views/reader/pdf/PdfPageCanvas', 'PdfPageCanvas',
    { pageModel: { pageIndex: 0 }, sourceUri: '/book.pdf' });
  view.setSourceReady(true); view.pageModel = { pageIndex: 0 }; view.isAnnotateMode = true; ui.flush();
  assert.equal(view.sourceReady, true);
  assert.ok([...ui.nodes.values()].some(node => node.type === 'Stack' && typeof node.props.onTouch === 'function'));
  view.pageModel = { pageIndex: 1 }; ui.flush(); assert.equal(view.sourceReady, false);
});

function inkEvent(type, x, y) {
  return {type,sourceTool:2,touches:[{id:7,x,y}],changedTouches:[{id:7,x,y}],pressure:0.5,stopPropagation(){},getHistoricalPoints(){return [];}};
}

test('compiled shared surface delivers PDF input to normalized strokes and blocks read-only writing',()=>{
  const ui=renderer(),strokes=[];const view=ui.mount('views/reader/pdf/PdfPageCanvas','PdfPageCanvas',{
    pageModel:{pageIndex:2},sourceUri:'/book.pdf',onStrokeAdded:s=>strokes.push(s)},'initialRender',v=>{
      v.pageWidth=100;v.pageHeight=200;v.sourceReady=true;v.isAnnotateMode=true;
    });
  const surface=[...ui.nodes.values()].find(n=>n.type==='Stack'&&n.props.onTouch);
  surface.props.onTouch(inkEvent(0,20,40));surface.props.onTouch(inkEvent(1,60,120));
  assert.equal(strokes.length,1);assert.equal(strokes[0].pageIndex,2);assert.equal(strokes[0].points[0].u,0.2);
  assert.equal(strokes[0].points.at(-1).v,0.6);view.isAnnotateMode=false;ui.flush();
  assert.equal(surface.props.hitTestBehavior,'None','read-only ink must not block source recovery buttons or page scrolling');
  surface.props.onTouch(inkEvent(0,20,40));surface.props.onTouch(inkEvent(1,60,120));assert.equal(strokes.length,1);
});

test('compiled shared surface delivers whiteboard input without changing its persisted stroke format',()=>{
  const ui=renderer();const view=ui.mount('views/reader/HandwritingCanvas','HandwritingCanvas',{
    note:{id:'ink',title:'课堂'},showToolbar:false},'initialRender',v=>{v.zoomScale=1;v.canvasWidth=600;v.canvasHeight=600;});
  const surface=[...ui.nodes.values()].find(n=>n.type==='Stack'&&n.props.onTouch);
  surface.props.onTouch(inkEvent(0,80,90));surface.props.onTouch(inkEvent(1,120,130));
  assert.equal(view.strokes.length,1);assert.equal(view.strokes[0].points[0].x,80);assert.equal(view.strokes[0].points[0].y,90);
  assert.equal(view.strokes[0].referenceWidth,1200);view.readOnly=true;ui.flush();
  surface.props.onTouch(inkEvent(0,80,90));surface.props.onTouch(inkEvent(1,120,130));assert.equal(view.strokes.length,1);
});

test('compiled textbook uses a lazy page source and routes last-page annotation callbacks correctly', () => {
  const ui = renderer(), erased = [], strokes = [], selected = [];
  const pages = Array.from({ length: 600 }, (_, pageIndex) => ({ pageIndex, width: 595, height: 842, title: `教材 ${pageIndex + 1}` }));
  const view = ui.mount('views/reader/pdf/PdfAnnotatorView', 'PdfAnnotatorView', {
    note: { id: 'book', type:'PDF', title: '教材', sourceUri: '/files/book.pdf', pageCount: 600 }, onPageChanged: page => selected.push(page)
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

for (const phone of [true, false]) {
  test(`compiled ${phone ? 'phone' : 'tablet'} graph shows empty topics and awaits confirmation`, async () => {
    const ui=renderer();let release;
    const view=ui.mount('views/workspace/GraphWorkspace','GraphWorkspace',{
      projects:[{name:'空主题'}],allNotes:[],onCreateGalaxy:()=>new Promise(resolve=>{release=resolve;})},
      'initialRender', v=>{v.isPhone=phone;});
    assert.ok(ui.find('空主题'));ui.click('新建主题');
    const input=[...ui.nodes.values()].find(node=>node.props.accessibilityText==='主题名称');
    assert.equal(input.props.height,48);assert.equal(input.props.width,'100%');
    input.props.onChange('数学');ui.flush();
    const confirming=ui.find('确定新建主题').props.onClick();ui.flush();
    assert.equal(view.isCreatingGalaxy,true);assert.equal(ui.find('确定新建主题').props.enabled,false);
    release(true);await confirming;ui.flush();
    assert.equal(view.activeGalaxy,'数学');assert.equal(view.isCreatingGalaxy,false);
  });
}

test('compiled phone navigation and tablet sidebar omit removed workspaces',()=>{
  for(const [file,name] of [['views/layout/BottomNavBar','BottomNavBar'],['views/layout/Sidebar','Sidebar']]) {
    const ui=renderer();ui.mount(file,name,{});
    assert.equal(ui.find('墨客'),undefined);assert.equal(ui.find('伴读'),undefined);
    assert.ok(ui.find(name === 'Sidebar' ? '知识图谱' : '记录'));
  }
});

test('compiled local preview retains headings and code and refreshes without streaming state',()=>{
  const ui=renderer();const view=ui.mount('views/common/DocumentText','DocumentText',
    {text:'# 校对结果\n\n```\nx = 12\n```'},'initialRender',v=>v.aboutToAppear());
  assert.ok(ui.find('校对结果'));assert.ok(ui.find('x = 12'));assert.equal(ui.find('生成中…'),undefined);
  view.text='# 更新原文';view.refresh();ui.flush();assert.ok(ui.find('更新原文'));assert.equal(ui.find('x = 12'),undefined);
});

test('compiled extraction exposes source evidence and refreshes confirmed dates while keeping task identity', () => {
  const ui = renderer();
  const task = { id: 'task', title: '复习第三章', deadline: '下周五', priority: 'medium', sourceLine: 2, sourceText: '- [ ] 下周五复习第三章' };
  const view = ui.mount('views/layout/sheets/SmartExtractSheet', 'SmartExtractSheet', {}, 'resultPanel', v => {
    v.result = { id: 'capture', title: '课程', rawMarkdown: '# 课程\n- [ ] 下周五复习第三章', summary: '',
      tags: [], entities: [], relations: [], tasks: [task], createdAt: new Date(2026, 9, 16).getTime() };
    v.title = '课程'; v.body = '# 课程'; v.tasks = [task]; v.selectedTaskIds = ['task']; v.resultTab = 'source';
  });
  assert.ok(ui.find('原文第 2 行：- [ ] 下周五复习第三章'));
  assert.equal(view.pendingDates(), true);
  const input = [...ui.nodes.values()].find(node => node.type === 'TextInput' && node.content?.placeholder?.startsWith('日期：'));
  assert.ok(input); input.props.onChange('2026-10-23'); ui.flush();
  assert.equal(view.pendingDates(), false); assert.ok(ui.find('2026-10-23'));
  assert.equal(view.tasks[0].id, 'task'); assert.equal(view.tasks[0].sourceLine, 2);
  assert.equal(ui.find('已选待办还有待确认日期，请修改日期或取消勾选。'), undefined);
});

test('compiled search shows readable errors, refreshes retry state and provides 44vp controls', () => {
  const ui = renderer(); const view = ui.mount('views/explore/QuickSearchDialog', 'QuickSearchDialog', {});
  assert.equal(ui.find('关闭搜索').props.width, 44); assert.equal(ui.find('开启正则搜索').props.height, 44);
  view.keyword = '['; view.searchError = '正则表达式无效'; ui.flush();
  assert.ok(ui.find('正则表达式无效')); assert.ok(ui.find('修改搜索条件后重试'));
  ui.click('重新搜索'); assert.equal(view.searching, true); assert.equal(view.searchError, '');
  assert.ok(ui.find('正在检索…'));
});

test('compiled search bounds initial result rows and expands only on request', () => {
  const ui = renderer();
  const view = ui.mount('views/explore/QuickSearchDialog', 'QuickSearchDialog', {}, 'initialRender', v => {
    v.keyword = '课程'; v.results = Array.from({ length: 75 }, (_, i) => ({ noteId: String(i), title: `课程 ${i}`,
      fileName: '', preview: '', matchedTags: [], matchedTitle: true, matchedContent: false }));
  });
  assert.equal(view.resultLimit, 30); assert.ok(ui.find('课程 29')); assert.equal(ui.find('课程 30'), undefined);
  ui.click('显示更多结果 · 已显示 30 / 75'); assert.equal(view.resultLimit, 60);
  assert.ok(ui.find('课程 59')); assert.equal(ui.find('课程 60'), undefined);
});

test('compiled theme cards persist the chosen style and repaint mounted reader, icons and dialogs together', async () => {
  const ui = renderer(), values = new Map();
  const { ThemeManager } = ui.load('common/theme/ThemeManager', false);
  ThemeManager.store = { put: async (key, value) => values.set(key, value), flush: async () => {} };
  const settings = ui.mount('views/settings/SettingsWorkspace', 'SettingsWorkspace', {}, 'themePage');
  const reader = ui.mount('views/reader/huawei/HuaweiDocWorkspace', 'HuaweiDocWorkspace',
    { note: { id: 'a', type: 'PDF', title: '课本', sourceType: 'pdf' } }, 'topNavigationBar', view => { view.pdfSourceReady = true; });
  const dialog = ui.mount('views/reader/huawei/HuaweiDocActionDialog', 'HuaweiDocActionDialog',
    { note: { id: 'a', title: '课本' }, dialogType: 'export_image' });
  ui.click('解锁批注'); const originalInk = reader.selectedColor;
  for (const label of ['白蓝','白青','白绿','白玫','暖砂','墨紫','黑白','雾蓝']) assert.ok(ui.find(`主题配色 ${label}`));
  await ui.click('主题配色 白青'); ui.flush();
  assert.equal(values.get('themeStyle'), 'cyan'); assert.equal(settings.themeStyle, 'cyan'); assert.equal(reader.themeStyle, 'cyan'); assert.equal(dialog.themeStyle, 'cyan');
  assert.equal(ui.find('主题配色 白青').props.accessibilityDescription, '已选中');
  assert.equal(ui.find('普通笔').props.backgroundColor, '#E0F4F3'); assert.equal(ui.find('保存 PNG').props.backgroundColor, '#08777E');
  const pen = ui.find('普通笔'); const penIcon = [...ui.nodes.values()].find(node => node.type === 'Image' && node.parents.includes(pen.id));
  assertIconTint(penIcon, '#08777E'); assert.equal(reader.selectedColor, originalInk);
  ui.storage.setOrCreate('flowmindDarkMode', true); ui.flush();
  assert.equal(reader.themeStyle, 'cyan'); assert.equal(ui.find('保存 PNG').props.backgroundColor, '#84D4D7'); assert.equal(reader.selectedColor, originalInk);
});

test('compiled theme selection waits for persistence and keeps the old selection after a failed write', async () => {
  const ui = renderer(); let finish, fail = false, writeStarted;
  const started = new Promise(resolve => { writeStarted = resolve; });
  const { ThemeManager } = ui.load('common/theme/ThemeManager', false);
  ThemeManager.store = { put: async () => {}, flush: () => new Promise((resolve, reject) => { finish = () => fail ? reject(Error('disk')) : resolve(); writeStarted(); }) };
  const view = ui.mount('views/settings/SettingsWorkspace', 'SettingsWorkspace', {}, 'themePage');
  const pending = ui.click('主题配色 白青'); await started; ui.flush();
  assert.equal(view.themeBusy, true); assert.equal(ui.find('主题配色 白蓝').props.enabled, false); assert.equal(view.themeStyle, 'mono');
  fail = true; finish(); await pending; ui.flush(); assert.equal(view.themeStyle, 'mono'); assert.equal(view.themeBusy, false);
  assert.equal(ui.find('主题配色 白青').props.enabled, true);
  assert.deepEqual(ui.toasts, ['外观保存失败，请重试']);
});


test('compiled scratchpad ellipsis opens actionable tools and paper commands target only the scratchpad',()=>{
  const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',
    {note:{id:'pdf',title:'课程',type:'PDF'}},'scratchpadSplitPane',v=>{v.pdfSourceReady=true;v.splitMode='scratchpad';});
  assert.equal(ui.find('随堂稿纸操作').props.width,44);assert.equal(ui.find('随堂稿纸操作').props.height,44);
  ui.click('随堂稿纸操作');assert.equal(view.scratchpadMenuOpen,true);ui.click('方格稿纸');
  assert.equal(view.canvasCommand.target,'scratchpad');assert.equal(view.canvasCommand.action,'paper');assert.equal(view.canvasCommand.value,'grid');
  assert.equal(view.isAnnotateMode,true);ui.click('随堂稿纸操作');ui.click('清空随堂稿纸笔迹');
  assert.equal(view.clearDialogOpen,true);const before=view.canvasCommand.sequence;view.inkTarget='document';view.confirmClearInk();
  assert.equal(view.canvasCommand.sequence,before+1);assert.equal(view.canvasCommand.target,'scratchpad');assert.equal(view.canvasCommand.action,'clearConfirmed');
});

test('compiled Markdown editing updates preview, supports history and gives the source an internal scroll area',()=>{
  const ui=renderer();const view=ui.mount('views/reader/MarkdownReader','MarkdownReader',
    {note:{id:'md',title:'课程',type:'Markdown',category:'',tag:'',tagColor:'',updateTime:'今天'}},'initialRender',v=>{
      v.isEditing=true;v.title='课程';v.applyContent('first\nmiddle\nlast');
    });
  assert.equal(ui.find('Markdown 源码').props.height,'100%');view.selStart=7;view.selEnd=7;view.handleFormatAction('h2');ui.flush();
  assert.equal(view.content,'first\n## middle\nlast');ui.click('撤销');assert.equal(view.content,'first\nmiddle\nlast');ui.click('重做');
  assert.equal(view.content,'first\n## middle\nlast');ui.click('实时预览');assert.equal(view.previewVisible,true);
  assert.ok([...ui.nodes.values()].some(node=>node.props.id==='markdown-preview-md'));
  assert.ok(ui.find('Markdown 源码'));ui.storage.setOrCreate('flowmindIsPhone',true);ui.flush();
  assert.equal(ui.find('Markdown 源码'),undefined);ui.click('返回源码编辑');assert.ok(ui.find('Markdown 源码'));
});

test('compiled trash exposes an explicit restore action for an empty deleted project',()=>{
  const ui=renderer(),restored=[];ui.mount('views/workspace/TrashWorkspace','TrashWorkspace',{trash:[],
    projects:[{id:'deleted',project:{id:'course',name:'空课程'},noteIds:[],deletedAt:1}],onRestoreProject:id=>restored.push(id)});
  ui.click('恢复项目 空课程');assert.deepEqual(restored,['deleted']);assert.equal(ui.find('回收站是空的'),undefined);
});

test('compiled Markdown pairing action waits for persistence and retains the note on a failed save',async()=>{
  const ui=renderer(),events=[];
  const view=ui.mount('views/reader/MarkdownReader','MarkdownReader',
    {note:{id:'md',title:'课程',type:'Markdown'},showCompanionAction:true,onOpenCompanion:()=>events.push('picker')},'editorToolbar');
  view.isDirty=true;view.flushSave=async()=>{events.push('save');};
  await ui.click('分屏阅读');assert.deepEqual(events,['save']);
  view.flushSave=async()=>{events.push('save');view.isDirty=false;};
  await ui.click('分屏阅读');assert.deepEqual(events,['save','save','picker']);
});

for(const phone of [false,true]) {
  test(`compiled ${phone?'phone':'wide'} generic split mounts two independent readers`,()=>{
    const ui=renderer();ui.storage.setOrCreate('flowmindIsPhone',phone);
    const note={id:'left',title:'左侧笔记',type:'Markdown',category:'',tag:'',tagColor:'',contentDetail:'',updateTime:''};
    const view=ui.mount('views/reader/ReaderSplitWorkspace','ReaderSplitWorkspace',{note,secondaryNote:{...note,id:'right',title:'右侧笔记'},documentTabs:[note]});
    assert.ok([...ui.nodes.values()].some(n=>n.props.id==='markdown-body-left'));
    assert.ok([...ui.nodes.values()].some(n=>n.props.id==='markdown-body-right'));
    assert.ok([...ui.nodes.values()].some(n=>n.type==='Flex'&&n.content?.direction===(phone?'Column':'Row')));
    assert.ok(ui.find('收起分屏资料'));view.saveBefore(()=>{});ui.flush();
    assert.equal([...ui.nodes.values()].find(n=>n.type==='Flex'&&n.content?.direction===(phone?'Column':'Row')).props.enabled,false);
  });
}

test('compiled pair chooser bounds results, searches documents and expands only on request',()=>{
  const ui=renderer();const notes=Array.from({length:45},(_,i)=>({id:`md-${i}`,title:`笔记 ${i}`,type:'Markdown',category:'课程',updatedAt:i}));
  notes.push({id:'ignored',title:'电子书',type:'EPUB',category:''});
  const view=ui.mount('views/reader/ReaderPairPicker','ReaderPairPicker',{source:{id:'pdf',title:'原文',type:'PDF'},notes});
  const rows=()=>[...ui.nodes.values()].filter(n=>n.props.accessibilityText?.startsWith('分屏打开 '));
  assert.equal(rows().length,40);assert.equal(ui.find('分屏打开 电子书'),undefined);
  ui.click('显示更多资料');assert.equal(rows().length,45);
  const input=[...ui.nodes.values()].find(n=>n.type==='TextInput');input.props.onChange('笔记 12');ui.flush();
  assert.equal(rows().length,1);assert.ok(ui.find('分屏打开 笔记 12'));assert.equal(view.limit,40);
  input.props.onChange('不存在');ui.flush();assert.ok(ui.find('没有匹配的资料'));
});

test('compiled pair chooser prevents repeated selection and retains errors until a successful retry',async()=>{
  const ui=renderer();let finish,attempts=0,closed=0;
  const view=ui.mount('views/reader/ReaderPairPicker','ReaderPairPicker',
    {source:{id:'md',title:'笔记',type:'Markdown'},notes:[{id:'pdf',title:'课程 PDF',type:'PDF',category:''}],
      onSelect:async()=>{attempts++;return new Promise(resolve=>finish=resolve);},onClose:()=>closed++});
  const pending=ui.click('分屏打开 课程 PDF');assert.equal(view.busy,true);assert.equal(ui.find('关闭分屏选择').props.enabled,false);
  view.select('pdf');view.requestClose();assert.equal(attempts,1);assert.equal(closed,0);
  finish(false);await pending;ui.flush();assert.equal(view.busy,false);assert.equal(closed,0);assert.ok(ui.find('资料未能打开，请检查保存状态后重试'));
  const retry=ui.click('分屏打开 课程 PDF');finish(true);await retry;assert.equal(attempts,2);assert.equal(closed,1);
});

test('compiled generic split saves both Markdown panes and retains failed input',async()=>{
  for(const success of [true,false]){
    const ui=renderer(),writes=[];let closed=0;
    const note={id:'left',title:'笔记',type:'Markdown',category:'',tag:'',tagColor:'',contentDetail:'old',updateTime:''};
    const host=ui.mount('views/reader/ReaderSplitWorkspace','ReaderSplitWorkspace',{note,secondaryNote:{...note,id:'right'},documentTabs:[note],
      onSaved:async(item,text)=>{writes.push([item.id,text]);if(!success&&item.id==='right')throw Error('disk full');},onClose:()=>closed++});
    for(const child of ui.children.values())if(typeof child.flushSave==='function'&&child.note?.type==='Markdown'){
      child.loadedNoteId=child.note.id;child.editingNote={...child.note};child.title='笔记';child.content=child.note.id+' latest';child.isDirty=true;
    }
    host.saveBefore(()=>host.onClose());ui.flush();await new Promise(resolve=>setImmediate(resolve));ui.flush();
    assert.deepEqual(writes.sort(),[['left','left latest'],['right','right latest']]);assert.equal(closed,success?1:0);assert.equal(host.failed,!success);
    assert.ok([...ui.nodes.values()].some(n=>n.props.id==='markdown-paper-right'));
  }
});

for(const mode of ['shelf','list','timeline']) {
  test(`compiled library ${mode} offers a separate bottom action target without opening the document`,()=>{
    const ui=renderer(),opened=[],menus=[];
    const note={id:'a',title:'课程',type:'Markdown',category:'数学',tag:'复习',tags:['复习'],previewText:'摘要',contentDetail:'正文',updateTime:'今天'};
    const view=ui.mount('views/workspace/LibraryWorkspace','LibraryWorkspace',{notes:[note],allNotes:[note],totalCount:1,viewMode:mode,
      onSelectNote:item=>opened.push(item.id),onOpenNoteMenu:item=>menus.push([item.id,item.title])});
    const more=ui.find('资料操作 课程');assert.equal(more.props.width,44);assert.equal(more.props.height,44);
    assert.ok(!more.parents.some(id=>ui.nodes.get(id)?.props.onClick),'action buttons must not be inside a document click target');
    ui.click('资料操作 课程');assert.deepEqual(menus,[['a','课程']]);assert.deepEqual(opened,[]);
    const target=[...ui.nodes.values()].find(n=>n.props.accessibilityText?.startsWith(mode==='timeline'?'打开记录 ':'打开资料 '));
    ui.click(target.props.accessibilityText);assert.deepEqual(opened,['a']);
    view.notes=[{...note,title:'新标题'}];ui.flush();ui.click('资料操作 新标题');assert.deepEqual(menus.at(-1),['a','新标题']);
  });
}

test('compiled material actions route rename and classification and require confirmation before trash',()=>{
  const ui=renderer(),calls=[],note={id:'a',title:'课程',type:'PDF'};
  ui.mount('views/layout/sheets/NoteMenuSheet','NoteMenuSheet',{note,onRequestRename:n=>calls.push(['rename',n.id]),
    onRequestMove:n=>calls.push(['move',n.id]),onDeleteNote:id=>calls.push(['delete',id])});
  ui.click('重命名资料');ui.click('移动到项目');assert.deepEqual(calls,[['rename','a'],['move','a']]);
  assert.equal(ui.find('编辑标签'),undefined);ui.click('移入回收站');assert.equal(calls.length,2);
  ui.click('确认删除');assert.deepEqual(calls.at(-1),['delete','a']);
});

test('compiled rename preserves failed input and ignores repeated save or close while committing',async()=>{
  const ui=renderer();let resolve,closed=0,calls=0;
  const view=ui.mount('views/layout/sheets/RenameNoteSheet','RenameNoteSheet',{note:{id:'a',title:'原标题'},onClose:()=>closed++,
    onRenameNote:async()=>{calls++;return new Promise(r=>resolve=r);}},'initialRender',v=>{v.draft='新标题';});
  const pending=ui.click('保存');view.submit();view.closeToken++;assert.equal(calls,1);assert.equal(closed,0);assert.equal(ui.find('资料新标题').props.enabled,false);
  resolve(false);await pending;ui.flush();assert.equal(view.draft,'新标题');assert.equal(closed,0);assert.ok(ui.find('未能保存标题，请重试'));
  const retry=ui.click('保存');resolve(true);await retry;assert.equal(calls,2);assert.equal(closed,1);
});

test('compiled classification preserves its form on failure and can move a document back to unclassified',async()=>{
  const ui=renderer(),calls=[];let closed=0,success=false;
  const view=ui.mount('views/layout/sheets/MoveNoteSheet','MoveNoteSheet',{note:{id:'a',title:'课程',category:'数学'},categories:['未分类','数学','空项目'],
    onClose:()=>closed++,onMoveNote:async(n,category)=>{calls.push([n.id,category]);return success;}});
  assert.equal(ui.find('归类到 未分类').props.height,44);await ui.click('归类到 未分类');ui.flush();
  assert.equal(closed,0);assert.ok(ui.find('未能移动资料，请重试'));success=true;
  await ui.click('归类到 未分类');assert.equal(closed,1);assert.deepEqual(calls,[['a','未分类'],['a','未分类']]);
});

test('compiled PDF eraser exposes direct area and stroke mode selection with current-mode feedback',()=>{
  const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',
    {note:{id:'pdf',title:'课程',type:'PDF'}},'topNavigationBar',v=>{v.pdfSourceReady=true;});
  ui.click('橡皮');assert.ok(ui.find('选择橡皮擦除方式'));ui.click('选择橡皮擦除方式');
  ui.click('笔画擦除');assert.equal(view.pdfEraserMode,'stroke');assert.equal(ui.find('笔画擦除').props.accessibilityDescription,'已选中');
  ui.click('区域擦除');assert.equal(view.pdfEraserMode,'area');assert.equal(ui.find('区域擦除').props.accessibilityDescription,'已选中');
});

test('compiled scratchpad mode selection targets its own canvas and does not change the PDF eraser',()=>{
  const ui=renderer();const view=ui.mount('views/reader/huawei/HuaweiDocWorkspace','HuaweiDocWorkspace',
    {note:{id:'pdf',title:'课程',type:'PDF'}},'topNavigationBar',v=>{v.pdfSourceReady=true;v.isAnnotateMode=true;v.splitMode='scratchpad';v.inkTarget='scratchpad';v.scratchpadInk={...v.scratchpadInk,tool:'eraser'};});
  ui.click('选择橡皮擦除方式');ui.click('笔画擦除');
  assert.equal(view.canvasCommand.target,'scratchpad');assert.equal(view.canvasCommand.action,'eraserMode');assert.equal(view.canvasCommand.value,'stroke');assert.equal(view.pdfEraserMode,'area');
});

test('compiled handwriting exposes both eraser modes immediately after selecting the eraser',()=>{
  const ui=renderer();const view=ui.mount('views/reader/HandwritingCanvas','HandwritingCanvas',{note:{id:'ink',title:'稿纸'}});
  ui.click('橡皮');assert.equal(view.toolsVisible,false);ui.click('笔画擦除');assert.equal(view.eraserMode,'stroke');
  ui.click('区域擦除');assert.equal(view.eraserMode,'area');assert.equal(view.isEraser,true);
});

test('compiled file tab drag opens a right-side drop target and splits only after the current pane is saved',async()=>{
  const ui=renderer(),splits=[];const note={id:'left',title:'当前笔记',type:'Markdown',category:'',tag:'',tagColor:'',contentDetail:'',updateTime:''};
  const other={...note,id:'other',title:'另一份笔记'};
  const host=ui.mount('views/reader/ReaderSplitWorkspace','ReaderSplitWorkspace',{note,documentTabs:[note,other],onSplitDocument:id=>splits.push(id)});
  const tab=ui.find('打开资料 另一份笔记');assert.equal(tab.props.draggable,true);tab.props.onDragStart();ui.flush();
  const drop=ui.find('右侧分屏放置区');assert.ok(drop);assert.equal(drop.props.width,'50%');drop.props.onDragEnter();ui.flush();assert.equal(host.overDrop,true);
  drop.props.onDrop();ui.flush();assert.deepEqual(splits,[]);assert.equal(host.busy,true);
  host.saved(true,'left',host.saveToken);assert.deepEqual(splits,['other']);tab.props.onDragEnd();host.selectTab('other');assert.equal(host.busy,false);
});

test('compiled scratchpad ignores invalid and repeated surface sizes instead of scheduling redraw loops',()=>{
  const ui=renderer();let redraws=0;const view=ui.mount('views/reader/HandwritingCanvas','HandwritingCanvas',{note:{id:'ink'},showToolbar:false});
  view.requestRedraw=()=>redraws++;
  const live=[...ui.nodes.values()].find(n=>n.type==='Canvas'&&n.props.onAreaChange);
  for(const [width,height]of [[0,0],[NaN,700],[360,700],[360,700],[360.1,700.1]])live.props.onAreaChange({}, {width,height});
  assert.equal(redraws,1);assert.equal(view.canvasWidth,360);assert.equal(view.canvasHeight,700);
});

for(const type of ['PDF','Image','Handwriting']){
  test(`compiled generic split mounts two ${type} readers with separate source and save owners`,()=>{
    const ui=renderer(),note={id:'left',title:'左侧资料',type,category:'',tag:'',tagColor:'',contentDetail:'',sourceType:type==='PDF'?'pdf':type==='Image'?'image':undefined};
    ui.mount('views/reader/ReaderSplitWorkspace','ReaderSplitWorkspace',{note,secondaryNote:{...note,id:'right',title:'右侧资料'},documentTabs:[note]});
    const native=[...ui.children.values()].filter(child=>typeof child.beginReaderSave==='function');
    assert.equal(native.length,2);assert.deepEqual(native.map(child=>child.note.id).sort(),['left','right']);
    assert.ok(native.every(child=>child.paneMode));
    assert.ok([...ui.nodes.values()].some(n=>n.props.id==='reader-document-left'));
    assert.ok([...ui.nodes.values()].some(n=>n.props.id==='reader-document-right'));
  });
}

test('compiled free whiteboard keeps storage names and unrelated file tabs out of the shared header',()=>{
  const ui=renderer();ui.mount('views/reader/ReaderSplitWorkspace','ReaderSplitWorkspace',{
    note:{id:'canvas-global',title:'内部存储名',type:'canvas'},documentTabs:[{id:'pdf',title:'其他课本',type:'PDF'}]});
  assert.equal(ui.find('内部存储名'),undefined);assert.equal(ui.find('打开资料 其他课本'),undefined);assert.ok(ui.find('搜索并打开资料'));
});

for (const phone of [false, true]) {
  test(`compiled ${phone ? 'phone' : 'tablet'} PDF pane uses only the shared filename tab and keeps document actions reachable`, () => {
    const ui = renderer(), note = { id: 'book', title: '墨语阅读测试.pdf', type: 'PDF', sourceType: 'pdf', sourceUri: '/book.pdf' };
    ui.storage.setOrCreate('flowmindIsPhone', phone);
    ui.mount('views/reader/ReaderSplitWorkspace', 'ReaderSplitWorkspace', { note, documentTabs: [note] });
    assert.ok([...ui.children.values()].filter(child => typeof child.beginReaderSave === 'function').every(child => child.isPhone === phone));
    assert.equal([...ui.nodes.values()].filter(node => node.type === 'Text' && node.content === note.title).length, 1);
    assert.equal([...ui.nodes.values()].filter(node => node.props.id === 'reader-tabs').length, 0);
    assert.ok(ui.find('普通笔')); assert.ok(ui.find('更多文档操作'));
    ui.click('更多文档操作'); assert.ok(ui.find('保存正文截图')); assert.ok(ui.find('导出笔记文字')); assert.ok(ui.find('分享原 PDF'));
  });
}

test('compiled offline host registers range reads as asynchronous bridge methods', async () => {
  const ui = renderer(), calls = [];
  ui.service('services/document/LocalPdfEngine', { LocalPdfEngine: { getInstance: () => ({
    read: async (...args) => { calls.push(args); return 'eA=='; }, markReady: () => calls.push('ready')
  }) } });
  ui.mount('views/reader/pdf/LocalPdfEngineHost', 'LocalPdfEngineHost', {});
  const web = [...ui.nodes.values()].find(node => node.type === 'Web');
  const proxy = web.props.javaScriptProxy;
  assert.deepEqual(Array.from(proxy.methodList), ['ready', 'finish']);
  assert.deepEqual(Array.from(proxy.asyncMethodList), ['read']);
  assert.equal(await proxy.object.read('registered', 0, 4), 'eA=='); assert.deepEqual(calls[0], ['registered', 0, 4]);
  assert.equal(proxy.object.ready(), true); assert.equal(calls[1], 'ready');
  assert.equal(web.props.blockNetwork, true); assert.equal(web.props.fileAccess, false);
});

test('SDK emits the PDF parser as a concurrent function and the UI service exposes no native synchronous renderer', () => {
  const worker = fs.readFileSync(path.join(cacheRoot, 'services/document/NativePdfTask.ts'), 'utf8');
  const service = fs.readFileSync(path.join(cacheRoot, 'services/document/PdfDocumentService.ts'), 'utf8');
  assert.match(worker, /readNativePdf\([^]*?["']use concurrent["']/);
  assert.ok(!service.includes('new pdfService.PdfDocument')); assert.ok(!service.includes('getCustomPagePixelMap('));
});
