import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture } from './fixtures/rdb-fixture.mjs';

const base='entry/src/main/ets/';
const plain=value=>JSON.parse(JSON.stringify(value));
const todo={id:'todo1',date:'2026-10-18',title:'课程复习',done:false,noteRefs:['n1','n2'],createdAt:1,updatedAt:2};
const card={id:'card1',noteId:'n1',course:'课程',question:'问题',answer:'答案',sourceText:'原文',dueAt:1000,intervalDays:1.5,repetitions:1,lapses:0,createdAt:1,updatedAt:2};

test('todos, day notes, cards and draft migrate to typed columns in the same SQLite database',async t=>{
  const f=fixture(t,{'flowmind_todos.todos':JSON.stringify([todo]),'flowmind_todos.daynotes':JSON.stringify([{date:todo.date,text:'备忘',updatedAt:2}]),
    'flowmind_study.cards':JSON.stringify([card]),'flowmind_memo_draft.draft':JSON.stringify({id:'memo_legacy',content:'草稿原文😀'})});
  const {TodoStorageService}=f.load(base+'services/TodoStorageService.ets');
  const {ReviewStorageService}=f.load(base+'services/study/ReviewStorageService.ets');
  const {MemoDraftService}=f.load(base+'services/library/MemoDraftService.ets');
  assert.deepEqual(plain(await new TodoStorageService().loadTodos({})),[todo]);
  assert.equal((await new TodoStorageService().loadDayNotes({}))[0].text,'备忘');
  assert.equal((await new ReviewStorageService().load({}))[0].intervalDays,1.5);
  assert.equal((await new MemoDraftService().load({})).content,'草稿原文😀');
  assert.deepEqual(await f.sql('SELECT id,date,done FROM todo_items'),[['todo1','2026-10-18',0]]);
  assert.deepEqual(await f.sql('SELECT note_id FROM todo_note_refs ORDER BY position'),[['n1'],['n2']]);
  assert.deepEqual(await f.sql('SELECT note_id,due_at FROM review_cards'),[['n1',1000]]);
  assert.equal((await f.sql('SELECT count(*) FROM domain_heads'))[0][0],4);
  assert.equal((await f.sql('SELECT count(*) FROM snapshot_chunks'))[0][0],0);
  assert.equal(f.preferenceWrites.length,0);
  f.preferences.set('flowmind_todos.todos','{old corrupt backup');
  assert.deepEqual(plain(await new TodoStorageService().loadTodos({})),[todo]);
});

test('a failed replacement of todo references rolls back rows and permits a safe retry',async t=>{
  const f=fixture(t);const {TodoStorageService}=f.load(base+'services/TodoStorageService.ets');const service=new TodoStorageService();
  await service.saveTodos({},[todo]);
  f.setFailure(sql=>sql.startsWith('INSERT INTO todo_note_refs'));
  await assert.rejects(service.saveTodos({},[{...todo,title:'不能半保存',noteRefs:['new']}]),/保存失败/);
  assert.deepEqual(plain(await service.loadTodos({})),[todo]);
  await service.saveTodos({},[{...todo,done:true}]);assert.equal((await service.loadTodos({}))[0].done,true);
});

test('corrupt legacy data blocks write-first replacement and preserves other domains',async t=>{
  const f=fixture(t,{'flowmind_todos.todos':'{broken','flowmind_study.cards':'[{"id":"invalid"}]','flowmind_memo_draft.draft':'{broken'});
  const {TodoStorageService}=f.load(base+'services/TodoStorageService.ets');const todos=new TodoStorageService();
  await assert.rejects(todos.saveTodos({},[]),/阻止覆盖/);await assert.rejects(todos.loadTodos({}));
  await todos.saveDayNotes({},[{date:todo.date,text:'仍能保存独立日期',updatedAt:2}]);
  const {ReviewStorageService}=f.load(base+'services/study/ReviewStorageService.ets');await assert.rejects(new ReviewStorageService().save({},[]));
  const {MemoDraftService}=f.load(base+'services/library/MemoDraftService.ets');await assert.rejects(new MemoDraftService().save({},{id:'memo_new',content:'new'}));
  assert.equal(f.preferences.get('flowmind_todos.todos'),'{broken');assert.equal(f.preferenceWrites.length,0);
});

test('missing initialized domain rows, fields or heads fail closed instead of resurrecting legacy data',async t=>{
  for(const damage of ['DELETE FROM todo_items','DELETE FROM todo_note_refs',"UPDATE todo_items SET title='changed'","DELETE FROM domain_heads WHERE scope='todos'"]){
    const f=fixture(t,{'flowmind_todos.todos':JSON.stringify([todo])});const {TodoStorageService}=f.load(base+'services/TodoStorageService.ets');
    const service=new TodoStorageService();await service.loadTodos({});await f.sql(damage);
    await assert.rejects(service.loadTodos({}));await assert.rejects(service.saveTodos({},[]),/阻止覆盖/);
  }
});

test('empty migrated collections and an empty draft never fall back to stale Preferences',async t=>{
  const f=fixture(t);const {MemoDraftService}=f.load(base+'services/library/MemoDraftService.ets');const {TodoStorageService}=f.load(base+'services/TodoStorageService.ets');
  const draft=new MemoDraftService();assert.equal(await draft.load({}),null);assert.equal(await new MemoDraftService().load({}),null);
  await draft.save({},{id:'memo_same',content:'草稿'});await draft.save({},{id:'memo_same',content:''});
  assert.equal((await new MemoDraftService().load({})).content,'');
  await new TodoStorageService().saveTodos({},[]);f.preferences.set('flowmind_todos.todos',JSON.stringify([todo]));
  assert.deepEqual(plain(await new TodoStorageService().loadTodos({})),[]);
  await f.sql("DELETE FROM domain_heads WHERE scope='todos'");await assert.rejects(new TodoStorageService().loadTodos({}));
});

test('normalized cards retain optional fields and a failed update leaves the prior review schedule',async t=>{
  const f=fixture(t);const {ReviewStorageService}=f.load(base+'services/study/ReviewStorageService.ets');const service=new ReviewStorageService();
  await service.save({},[{...card,pageNumber:3,lastRating:'hard',reviewCount:5}]);
  const saved=plain(await service.load({}));assert.equal(saved[0].pageNumber,3);assert.equal(saved[0].lastRating,'hard');
  f.setFailure(sql=>sql.startsWith('INSERT INTO review_cards'));await assert.rejects(service.save({},[{...saved[0],dueAt:9999}]));
  assert.deepEqual(plain(await new ReviewStorageService().load({})),saved);
});

test('editor commands affect selected lines, preserve the rest and keep a meaningful selection',async t=>{
  const f=fixture(t);const {MarkdownEditing:M}=f.load(base+'services/document/MarkdownEditing.ets');
  let edit=M.command({text:'first\nmiddle\nlast',start:7,end:7},'h2');
  assert.equal(edit.text,'first\n## middle\nlast');assert.equal(edit.start,10);
  edit=M.command({text:'one\ntwo\nlast',start:0,end:8},'task');assert.equal(edit.text,'- [ ] one\n- [ ] two\nlast');
  assert.equal(M.command(edit,'task').text,'one\ntwo\nlast');
  assert.equal(M.command({text:'a\nb\nc',start:0,end:3},'ordered').text,'1. a\n2. b\nc');
  edit=M.command({text:'中文😀',start:4,end:2},'bold');assert.equal(edit.text,'中文**😀**');
  assert.equal(M.command(edit,'bold').text,'中文😀');
  assert.equal(M.command({text:'x\ny\nz',start:2,end:3},'divider').text,'x\n\n---\n\nz');
});

test('editor insertion keeps CRLF and headings never target the last line by accident',async t=>{
  const f=fixture(t);const {MarkdownEditing:M}=f.load(base+'services/document/MarkdownEditing.ets');
  assert.equal(M.command({text:'first\r\nsecond\r\nlast',start:8,end:8},'h1').text,'first\r\n# second\r\nlast');
  const edit=M.command({text:'first\r\nlast',start:7,end:7},'table');assert.ok(edit.text.includes('| 标题 | 内容 |\r\n| --- | --- |'));
  assert.ok(edit.text.endsWith('last'));
});

test('history groups typing, isolates toolbar commands, restores selection and clears redo after a new edit',async t=>{
  const f=fixture(t);const {MarkdownHistory,MarkdownEditing:M}=f.load(base+'services/document/MarkdownEditing.ets');
  const history=new MarkdownHistory();const a={text:'',start:0,end:0},b={text:'a',start:1,end:1},c={text:'ab',start:2,end:2};
  history.record(a,b,true,100);history.record(b,c,true,200);
  assert.equal(history.undo(c).text,'');assert.equal(history.redo(a).text,'ab');
  const bold=M.command(c,'bold');history.record(c,bold);assert.equal(history.undo(bold).text,'ab');
  history.record(c,{text:'abc',start:3,end:3},true,300);assert.equal(history.canRedo(),false);
  history.reset();assert.equal(history.canUndo(),false);
});

const note=(id,category)=>({id,title:id,category,type:'Markdown',contentDetail:'正文',previewText:'正文',tag:'',tagColor:'',updateTime:'今天'});
test('project deletion removes derived and registered folders and supports whole-project and empty-project restore',async t=>{
  const f=fixture(t);const {WorkspaceLifecycle:L}=f.load(base+'services/library/WorkspaceLifecycle.ets');const {buildSpaces}=f.load(base+'services/WorkspaceBuilder.ets');
  const state={notes:[note('a','课程'),note('b','课程'),note('u','未分类')],projects:[{id:'course',name:'课程',count:2,isOpen:true,children:[]}],trash:[],trashedProjects:[]};
  const deleted=L.deleteProject(state,'课程',1000);assert.equal(state.notes[0].deletedAt,undefined);
  assert.equal(deleted.trash.length,2);assert.equal(deleted.trashedProjects.length,1);assert.deepEqual(plain(buildSpaces(deleted.notes,deleted.projects,[])),[]);
  const restored=L.restoreProject(deleted,deleted.trashedProjects[0].id);assert.deepEqual(plain(restored.notes).map(n=>n.id),['a','b','u']);assert.equal(restored.trash.length,0);
  const implicit=L.deleteProject({...state,projects:[]},'课程',1001);assert.equal(implicit.trashedProjects[0].project.name,'课程');
  const empty=L.deleteProject({...state,notes:[]},'课程',1002);assert.equal(L.restoreProject(empty,empty.trashedProjects[0].id).projects.length,1);
});

test('individual restore, name collisions and a late duplicate delete preserve identities',async t=>{
  const f=fixture(t);const {WorkspaceLifecycle:L}=f.load(base+'services/library/WorkspaceLifecycle.ets');
  const state={notes:[note('a','课程')],projects:[],trash:[],trashedProjects:[]};const deleted=L.deleteProject(state,'课程',1);
  const restored=L.restoreNote(deleted,'a');assert.equal(restored.trashedProjects[0].noteIds.length,1);
  assert.equal(L.restoreProject(restored,deleted.trashedProjects[0].id).projects.length,1);
  assert.throws(()=>L.restoreProject({...restored,projects:[{id:'new',name:'课程'}]},deleted.trashedProjects[0].id),/同名/);
  assert.throws(()=>L.deleteProject(deleted,'课程',2),/不存在/);
  assert.throws(()=>L.renameProject({...state,projects:[{id:'b',name:'其他'}]},'课程','其他'),/同名/);
});

test('empty source formatting and task changes preserve selection and source boundaries',async t=>{
  const f=fixture(t);const {MarkdownEditing:M}=f.load(base+'services/document/MarkdownEditing.ets');
  assert.equal(M.command({text:'',start:0,end:0},'h1').text,'# ');
  assert.equal(M.command({text:'\nlast',start:0,end:0},'bullet').text,'- \nlast');
  const source='```text\n- [ ] literal\n```\n- [ ] task\r\nrest';
  assert.equal(M.toggleTask({text:source,start:0,end:0},3).text,'```text\n- [ ] literal\n```\n- [x] task\r\nrest');
});

test('restoring a project does not absorb a member that was individually restored and deleted again',async t=>{
  const f=fixture(t);const {WorkspaceLifecycle:L}=f.load(base+'services/library/WorkspaceLifecycle.ets');
  const state={notes:[note('a','课程'),note('b','课程')],projects:[],trash:[],trashedProjects:[]};
  const deleted=L.deleteProject(state,'课程',1),individual=L.restoreNote(deleted,'a'),deletedAgain=L.deleteNote(individual,'a',2);
  const restored=L.restoreProject(deletedAgain,deleted.trashedProjects[0].id);
  assert.deepEqual(plain(restored.notes).map(item=>item.id),['b']);assert.deepEqual(plain(restored.trash).map(item=>item.id),['a']);
});
