import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';

const root = path.resolve(import.meta.dirname, '..');
const documents = [
  'README.md', 'PRODUCT_SCOPE.md', 'TECH_STACK.md', 'CONTRIBUTING.md', 'SECURITY.md',
  ...['README', 'ROADMAP', 'BUSINESS_PLAN', 'CLOUD_AI_BUSINESS', 'CLOUD_AI_DESIGN', 'WEB_PLATFORM_PLAN', 'INNOVATION',
    'DEVELOPMENT_GUIDE', 'CODE_STANDARDS', 'ARCHITECTURE', 'DESIGN_REVIEW', 'FEATURE_PARITY',
    'KOODO_REFERENCE', 'LOCAL_TEXT_LAYOUT', 'DEPENDENCIES', 'USER_GUIDE', 'PRIVACY'].map(name => `docs/${name}.md`)
];
const privatePath = relative => /^(?:tmp|archive|design)\//.test(relative) ||
  /^(?:PROJECT_MEMORY\.md|local\.properties)$/.test(relative) ||
  /^docs\/(?:COMPETITION_DELIVERY|WORKFLOW_REVIEW|ARCHITECTURE_REVIEW[^/]*)\.md$/.test(relative) ||
  /^release\/(?:reports|evidence)\//.test(relative) || /^release\/.*\.(?:md|template\.json)$/.test(relative);
let links = 0;
for (const file of documents) {
  const absolute = path.join(root, file);
  assert.ok(fs.existsSync(absolute), `Missing public document: ${file}`);
  const source = fs.readFileSync(absolute, 'utf8');
  assert.ok(source.trim().length > 0, `Empty public document: ${file}`);
  assert.doesNotMatch(source, /赛道|评分|评审|参赛|比赛|初赛|决赛|答辩/, `Public document contains internal evaluation context: ${file}`);
  for (const match of source.matchAll(/!?\[[^\]]*\]\(([^)]+)\)/g)) {
    const link = match[1].replace(/^<|>$/g, '').split('#')[0];
    if (!link || /^[a-z][a-z\d+.-]*:/i.test(link)) continue;
    const target = path.resolve(path.dirname(absolute), decodeURIComponent(link));
    const relative = path.relative(root, target).replaceAll('\\', '/');
    assert.ok(relative && !relative.startsWith('../') && !path.isAbsolute(relative), `Link escaped repository: ${file}: ${link}`);
    assert.ok(!privatePath(relative), `Public document links to local-only material: ${file}: ${link}`);
    assert.ok(fs.existsSync(target) && fs.statSync(target).isFile(), `Broken public link: ${file}: ${link}`);
    links++;
  }
}
const scope = fs.readFileSync(path.join(root, 'PRODUCT_SCOPE.md'), 'utf8');
assert.ok(scope.includes('未实现') && scope.includes('不调用云端生成模型'), 'Product scope must distinguish cloud plans from the current local application');
const business = fs.readFileSync(path.join(root, 'docs/CLOUD_AI_BUSINESS.md'), 'utf8');
assert.ok(business.includes('团队托管') && business.includes('未来'), 'Cloud AI documentation must describe the proposed service as a future direction');
console.log(`Public documentation passed: ${documents.length} documents, ${links} repository links; local operational materials excluded.`);
