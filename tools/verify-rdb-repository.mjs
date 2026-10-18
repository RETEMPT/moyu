import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fixture } from './fixtures/rdb-fixture.mjs';

test('real SQLite stores and rereads a complete snapshot, preserving empty collections',async t=>{
  const f=fixture(t);await f.repo.open({});assert.equal(await f.repo.read('notes'),null);
  await f.repo.write('notes','[]');assert.equal(await f.repo.read('notes'),'[]');
  assert.equal(await f.repo.read('trash'),null);
});
test('chunked Unicode, quotes and large annotations round-trip through real SQLite without row truncation',async t=>{
  const f=fixture(t);await f.repo.open({});const content=JSON.stringify([{id:'a',content:'x'.repeat(65510)+'😀汉字\n\"'+'笔'.repeat(90000)}]);
  await f.repo.write('notes',content);
  const rows=await f.sql('SELECT payload FROM snapshot_chunks');
  assert.ok(rows.every(([part])=>JSON.parse(part).length<=65536));
  assert.equal(await f.repo.read('notes'),content);
  assert.ok(rows.length>=2);assert.ok(rows.every(([part])=>part.length<400000));
  const split='a'.repeat(65535)+'😀';assert.equal(f.Repository.chunks(split).map(part=>JSON.parse(part)).join(''),split);
});
test('a failed middle chunk rolls back deletion and partial inserts, and a later retry succeeds',async t=>{
  const f=fixture(t);await f.repo.open({});await f.repo.write('notes','["old"]');
  f.setFailure((sql,args)=>sql.startsWith('INSERT INTO snapshot_chunks')&&args[1]===1);
  await assert.rejects(f.repo.write('notes',JSON.stringify('new'.repeat(50000))),/保存未完成/);
  assert.equal(await f.repo.read('notes'),'["old"]');await f.repo.write('notes','["retry"]');assert.equal(await f.repo.read('notes'),'["retry"]');
});
test('missing chunks fail closed and prevent later empty-snapshot replacement',async t=>{
  const f=fixture(t);await f.repo.open({});await f.repo.write('notes',JSON.stringify('a'.repeat(90000)));
  await f.sql('DELETE FROM snapshot_chunks WHERE ordinal=1');await assert.rejects(f.repo.read('notes'),/读取异常/);
  await assert.rejects(f.repo.write('notes','[]'),/阻止覆盖/);
  assert.equal((await f.sql('SELECT parts FROM snapshot_heads WHERE scope=?',['notes']))[0][0],2);
});
test('a corrupted encoded chunk is retained and cannot be overwritten after a failed read',async t=>{
  const f=fixture(t);await f.repo.open({});await f.repo.write('notes','["old"]');
  await f.sql('UPDATE snapshot_chunks SET payload=?',['{broken']);await assert.rejects(f.repo.read('notes'));
  await assert.rejects(f.repo.write('notes','[]'));assert.equal((await f.sql('SELECT payload FROM snapshot_chunks'))[0][0],'{broken');
});
test('a future schema version is rejected before any schema or user data is written',async t=>{
  const f=fixture(t);f.store.version=3;await assert.rejects(f.repo.open({}),/更新版本/);
  assert.equal((await f.sql("SELECT count(*) FROM sqlite_master WHERE type='table'"))[0][0],0);
});
test('an initialized snapshot with a missing head is corruption, not an empty library or legacy fallback',async t=>{
  const f=fixture(t);await f.repo.open({});await f.repo.write('notes','["saved"]');
  await f.sql('DELETE FROM snapshot_heads WHERE scope=?',['notes']);await assert.rejects(f.repo.read('notes'),/读取异常/);
  await assert.rejects(f.repo.write('notes','[]'),/阻止覆盖/);
});

test('workspace deletion rolls back every collection when any later collection fails',async t=>{
  const f=fixture(t);await f.repo.open({});
  await f.repo.writeMany([{scope:'notes',json:'["active"]'},{scope:'projects',json:'["folder"]'},{scope:'trash',json:'[]'}]);
  f.setFailure((sql,args)=>sql.startsWith('INSERT INTO snapshot_chunks')&&args[0]==='trash');
  await assert.rejects(f.repo.writeMany([{scope:'notes',json:'[]'},{scope:'projects',json:'[]'},{scope:'trash',json:'["active"]'}]));
  assert.equal(await f.repo.read('notes'),'["active"]');assert.equal(await f.repo.read('projects'),'["folder"]');assert.equal(await f.repo.read('trash'),'[]');
});

test('permanent deletion journal cannot commit separately from removal of recycle-bin records', async t => {
  const f = fixture(t); await f.repo.open({}); await f.repo.write('trash', '["retained"]');
  f.setFailure((sql,args) => sql.startsWith('INSERT INTO snapshot_chunks') && args[0] === 'pending_deletions_v1');
  await assert.rejects(f.repo.writeMany([{ scope:'trash',json:'[]' }, { scope:'pending_deletions_v1',json:'[{"id":"retained"}]' }]));
  assert.equal(await f.repo.read('trash'), '["retained"]'); assert.equal(await f.repo.read('pending_deletions_v1'), null);
  await f.repo.writeMany([{ scope:'trash',json:'[]' }, { scope:'pending_deletions_v1',json:'[{"id":"retained"}]' }]);
  assert.equal(await f.repo.read('trash'), '[]'); assert.equal(await f.repo.read('pending_deletions_v1'), '[{"id":"retained"}]');
});
