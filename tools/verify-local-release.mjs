import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { parseJsonc } from './app-market-policy.mjs';

const root=path.resolve(import.meta.dirname,'..');
const sourceRoot=path.join(root,'entry/src/main/ets');
function files(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(dir,e.name)):[path.join(dir,e.name)]);}
// Runtime modules must be reachable; the explicitly authorized offline contract stays dormant.
const sourceFiles=files(sourceRoot).filter(file=>file.endsWith('.ets'));
const reached=new Set();
function visit(file){
  if(reached.has(file))return;reached.add(file);
  for(const match of fs.readFileSync(file,'utf8').matchAll(/(?:from\s+|import\s*)['"](\.[^'"]+)['"]/g)){
    const dependency=path.resolve(path.dirname(file),match[1]+'.ets');
    assert.ok(inSource(dependency),`Source dependency escaped application: ${file}`);
    visit(dependency);
  }
}
function inSource(file){return file.startsWith(sourceRoot+path.sep);}
sourceFiles.filter(file=>/[/\\](?:pages|entryability|entrybackupability)[/\\]/.test(file)).forEach(visit);
const preparationFiles = ['common/types/LearningResult.ets', 'services/study/LearningResultPolicy.ets']
  .map(file => path.join(sourceRoot, file)).sort();
assert.deepEqual(sourceFiles.filter(file=>!reached.has(file)).sort(), preparationFiles,
  'Only the explicitly isolated learning result contract may be dormant; it must not become a runtime entry');
const forbidden=/\b(?:AI|AiWorkspace|AssistantText|HuaweiAiSplitPanel|ModelConfigService|ModelProvider|AiModelCatalog|MarkerImportPolicy|SmartEntity|SmartRelation|aiSummary|aiTags|createProvider|NAV_AI)\b|墨客|伴读|大模型|自配 API|模型设置|services\/ai\/|views\/ai\//;
const inFolder=(folder,file)=>{const relative=path.relative(folder,file);return relative!==''&&relative!=='..'&&!relative.startsWith('..'+path.sep)&&!path.isAbsolute(relative);};
for(const file of files(sourceRoot)) {
  const source=fs.readFileSync(file,'utf8');
  // This system capability name belongs to non-generative OCR; it is never user-facing.
  const checked=source.replaceAll('SystemCapability.AI.OCR.TextRecognition','SystemCapability.OCR.TextRecognition');
  assert.ok(!forbidden.test(checked),`Removed feature remains in ${path.relative(root,file)}`);
  assert.ok(!/@kit\.NetworkKit|createHttp\(|https:\/\/(?:api\.|openrouter|generativelanguage)/.test(source),`Model transport remains in ${file}`);
  for(const m of source.matchAll(/(?:from\s+|import\s*)['"](\.[^'"]+)['"]/g)) {
    const dependency=path.resolve(path.dirname(file),m[1]+'.ets');
    assert.ok(inFolder(sourceRoot,dependency),`Runtime import escaped current source: ${file}: ${m[1]}`);
    assert.ok(fs.existsSync(dependency),`Missing import in ${file}: ${m[1]}`);
  }
}
// Operational records and historical inventories are optional local audits.
let archivedCount=0;
if(process.argv.includes('--local-docs')) {
const currentDocs=['README.md','TECH_STACK.md','PROJECT_MEMORY.md','SECURITY.md','CONTRIBUTING.md','design/ICON_SYSTEM.md',
  ...files(path.join(root,'docs')).filter(file=>file.endsWith('.md')).map(file=>path.relative(root,file)),
  ...fs.readdirSync(path.join(root,'release')).filter(file=>file.endsWith('.md')).map(file=>`release/${file}`)];
// Current product copy stays local-only; developer documents may describe planned cloud services.
// Source, permissions and archive isolation checks above remain mandatory for every release.
for(const file of ['README.md','docs/USER_GUIDE.md','docs/PRIVACY.md','release/STORE_LISTING.md','release/site/privacy.html']) {
  let source=fs.readFileSync(path.join(root,file),'utf8');
  // The overview separately describes the app, standalone experiment and dormant preparation.
  // Audit the local app introduction here; production imports and permissions are checked above.
  if(file==='README.md')source=source.split(/^## (?:[\d.]+ 更新与能力边界|发展方向（规划）)/m)[0];
  assert.ok(!forbidden.test(source),`Retired product copy remains in ${file}`);
}
for(const file of [...currentDocs,'PRODUCT_SCOPE.md']) {
  const source=fs.readFileSync(path.join(root,file),'utf8');
  for(const match of source.matchAll(/!?\[[^\]]*\]\(([^)]+)\)/g)) {
    const link=match[1].replace(/^<|>$/g,'').split('#')[0];
    if(!link||/^[a-z][a-z0-9+.-]*:/i.test(link))continue;
    const target=path.resolve(path.dirname(path.join(root,file)),decodeURIComponent(link));
    assert.ok(inFolder(root,target)&&fs.existsSync(target),`Broken current document link: ${file}: ${link}`);
  }
}
const archiveRoot=path.join(root,'archive/ai');
const manifest=JSON.parse(fs.readFileSync(path.join(archiveRoot,'MANIFEST.json'),'utf8').replace(/^\uFEFF/,''));
assert.ok(manifest.files.length>0,'Archive inventory is missing');
const archivedPaths=new Set();
for(const record of manifest.files) {
  const target=path.resolve(root,record.archived);
  assert.ok(inFolder(archiveRoot,target)&&fs.existsSync(target),`Archive target is missing: ${record.archived}`);
  assert.ok(inFolder(archiveRoot,fs.realpathSync(target)),`Archive target resolved outside its directory: ${record.archived}`);
  assert.ok(!archivedPaths.has(target),`Duplicate archive record: ${record.archived}`);archivedPaths.add(target);
  assert.equal(createHash('sha256').update(fs.readFileSync(target)).digest('hex'),record.sha256,`Historical bytes changed: ${record.archived}`);
}
assert.ok(!fs.existsSync(path.join(root,'archive/optional-features')),'Historical features must have one archive directory');
assert.ok(!fs.existsSync(path.join(root,'AI_AGENT_PLAN.md')),'Historical roadmap remains at the current root');
archivedCount=archivedPaths.size;
}
for(const file of ['tools/verify-workflows.mjs','tools/verify-pdf-chain.mjs','tools/verify-compiled-ui.mjs']) {
  const source=fs.readFileSync(path.join(root,file),'utf8');
  assert.ok(!/(?:load|import)\(\s*['"][^'"]*archive[\\/]/.test(source),`Current regression imports the archive: ${file}`);
  assert.ok(!/AiModelCatalog|tools\/fixtures\/SeedContent/.test(source),`Historical fixture remains in current regression: ${file}`);
}
for(const file of files(path.join(root,'entry/src/main/resources'))) {
  assert.ok(!/ic_(?:sparkle|send|history|stop)\.svg$/.test(file),`Retired icon remains in the application: ${file}`);
}
const release=JSON.parse(fs.readFileSync(path.join(root,'release/app-market.json'),'utf8'));
assert.equal(release.productMode,'local-study');assert.equal(release.systemOcr,true);assert.ok(!('assistantMode' in release));
const module=parseJsonc(fs.readFileSync(path.join(root,'entry/src/main/module.json5'),'utf8')).module;
assert.deepEqual(module.deviceTypes,['phone','tablet']);
assert.ok(!module.requestPermissions.some(p=>p.name==='ohos.permission.INTERNET'));
assert.ok(!fs.existsSync(path.join(sourceRoot,'services/ai/ModelProvider.ets')));
assert.ok(!fs.readFileSync(path.join(sourceRoot,'pages/Index.ets'),'utf8').includes('privacyWelcome'));
console.log(`Local release source audit passed: ${files(sourceRoot).length} files; ${archivedCount} optional historical files verified; system OCR retained.`);
