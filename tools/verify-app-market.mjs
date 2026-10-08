import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseJsonc, packageErrors, deviceEvidenceErrors, REQUIRED_CASES } from './app-market-policy.mjs';

const expected = { bundleName:'com.retempt.flowmind', versionName:'1.0.3', versionCode:1001003,
  minApi:24,targetApi:26, devices:['phone','tablet'], permissions:['ohos.permission.INTERNET','ohos.permission.DISTRIBUTED_DATASYNC'],
  sourceCommit:'abcdef',appSha256:'artifact-sha' };
const pack = () => ({ appSha256:'artifact-sha',pack:{ summary:{app:{bundleName:expected.bundleName,version:{code:expected.versionCode,name:expected.versionName}}}},
  modules:[{module:{name:'entry',deviceTypes:expected.devices,requestPermissions:expected.permissions.map(name=>({name}))},
    app:{...expected,debug:false,buildMode:'release',apiReleaseType:'Release',compileSdkType:'HarmonyOS',minAPIVersion:60101024,targetAPIVersion:260000026},
    nativeLibraries:[],backup:{allowToBackupRestore:false},signatureVerified:true}] });
test('JSONC parser preserves URL and string content while removing comments and trailing commas',()=>{
  assert.deepEqual(parseJsonc('{/*comment*/ "url":"https://test/v1", //line\n "literal":",]/*x*/", "items":[1,],}'),
    {url:'https://test/v1',literal:',]/*x*/',items:[1]});
  assert.throws(()=>parseJsonc('{/* unterminated')); assert.throws(()=>parseJsonc('process.exit()'));
});
test('matching release package passes metadata and signature checks',()=> assert.deepEqual(packageErrors(pack(),expected,true),[]));
for (const [name,change] of [
  ['debug module', p=>{p.modules[0].app.debug=true;}],
  ['wrong version',p=>{p.modules[0].app.versionCode=1000000;}],
  ['extra permission',p=>{p.modules[0].module.requestPermissions=[{name:'ohos.permission.READ_CONTACTS'}];}],
  ['unverified signature',p=>{p.modules[0].signatureVerified=false;}],
  ['system backup',p=>{p.modules[0].backup.allowToBackupRestore=true;}],
  ['unexpected native code',p=>{p.modules[0].nativeLibraries=['libs/arm64-v8a/libentry.so'];}],
  ['device mismatch',p=>{p.modules[0].module.deviceTypes=['phone'];}],
  ['unexpected SDK',p=>{p.modules[0].app.targetAPIVersion=250000025;}]
]) test(`submission gate blocks ${name}`,()=>{const p=pack();change(p);assert.ok(packageErrors(p,expected,true).length);});

const qa = () => ({versionCode:expected.versionCode,appSha256:expected.appSha256,sourceCommit:expected.sourceCommit,
  devices:expected.devices.map(type=>({type,physical:true,model:'test fixture',systemVersion:'6.1.1',tester:'fixture',checkedAt:new Date().toISOString(),
    cases:Object.fromEntries(REQUIRED_CASES.map(id=>[id,{status:'PASS',evidence:'release/evidence/test.txt'}]))}))});
test('complete recent physical-device evidence must match the exact APP and source',()=>{
  assert.deepEqual(deviceEvidenceErrors(qa(),expected),[]);
  for (const change of [e=>{e.appSha256='old-package';}, e=>{e.sourceCommit='old-commit';}, e=>{e.devices[0].physical=false;},
    e=>{e.devices[0].cases.ai_consent_revoke.status='TODO';},e=>{e.devices[1].cases.backup_restore.evidence='';},
    e=>{e.devices[0].checkedAt='2000-01-01';},e=>{e.devices[0].checkedAt='2099-01-01';}]) {
    const e=qa();change(e);assert.ok(deviceEvidenceErrors(e,expected).length);
  }
});
