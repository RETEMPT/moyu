import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { parseJsonc } from './app-market-policy.mjs';

const root=path.resolve(import.meta.dirname,'..');
const sourceRoot=path.join(root,'entry/src/main/ets');
function files(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const forbidden=/\b(?:AI|AiWorkspace|AssistantText|HuaweiAiSplitPanel|ModelConfigService|ModelProvider|createProvider|NAV_AI)\b|墨客|伴读|大模型|自配 API|模型设置|services\/ai\/|views\/ai\//;
for(const file of files(sourceRoot)) {
  const source=fs.readFileSync(file,'utf8');
  // This system capability name belongs to non-generative OCR; it is never user-facing.
  const checked=source.replaceAll('SystemCapability.AI.OCR.TextRecognition','SystemCapability.OCR.TextRecognition');
  assert.ok(!forbidden.test(checked),`Removed feature remains in ${path.relative(root,file)}`);
  assert.ok(!/@kit\.NetworkKit|createHttp\(|https:\/\/(?:api\.|openrouter|generativelanguage)/.test(source),`Model transport remains in ${file}`);
  for(const m of source.matchAll(/(?:from\s+|import\s*)['"](\.[^'"]+)['"]/g)) {
    assert.ok(fs.existsSync(path.resolve(path.dirname(file),m[1]+'.ets')),`Missing import in ${file}: ${m[1]}`);
  }
}
for(const file of ['release/STORE_LISTING.md','release/site/privacy.html','docs/PRIVACY.md']) {
  assert.ok(!forbidden.test(fs.readFileSync(path.join(root,file),'utf8')),`Retired product copy remains in ${file}`);
}
const module=parseJsonc(fs.readFileSync(path.join(root,'entry/src/main/module.json5'),'utf8')).module;
assert.deepEqual(module.deviceTypes,['phone','tablet']);
assert.ok(!module.requestPermissions.some(p=>p.name==='ohos.permission.INTERNET'));
assert.ok(!fs.existsSync(path.join(sourceRoot,'services/ai/ModelProvider.ets')));
assert.ok(!fs.readFileSync(path.join(sourceRoot,'pages/Index.ets'),'utf8').includes('privacyWelcome'));
console.log(`Local release source audit passed: ${files(sourceRoot).length} files; phone/tablet; no model transport or startup privacy overlay.`);
