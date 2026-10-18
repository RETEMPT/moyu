import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const root = path.resolve(import.meta.dirname, '..', 'entry/src/main/ets');
const list = folder => fs.readdirSync(folder, { withFileTypes: true }).flatMap(entry =>
  entry.isDirectory() ? list(path.join(folder, entry.name)) : entry.name.endsWith('.ets') ? [path.join(folder, entry.name)] : []);
const source = new Map(list(root).map(file => [path.relative(root, file).replaceAll('\\', '/'), fs.readFileSync(file, 'utf8')]));
const dependencies = new Map([...source].map(([file, text]) => [file, [...text.matchAll(/(?:from\s+|import\s*)['"](\.[^'"]+)['"]/g)]
  .map(match => path.posix.normalize(path.posix.join(path.posix.dirname(file), match[1] + '.ets')))]));

test('application dependencies stay in the source tree and lower layers never import their callers', () => {
  for (const [file, imports] of dependencies) for (const dependency of imports) {
    assert.ok(source.has(dependency), `Missing dependency: ${file} -> ${dependency}`);
    if (file.startsWith('common/')) assert.match(dependency, /^common\//, `${file} imports an upper layer`);
    if (file.startsWith('services/')) assert.ok(!/^(views|pages)\//.test(dependency), `${file} imports a UI layer`);
    if (file.startsWith('views/')) assert.ok(!dependency.startsWith('pages/'), `${file} imports its composition root`);
  }
});

test('application source has no circular relative imports', () => {
  const visited = new Set(), stack = [];
  function visit(file) {
    assert.ok(!stack.includes(file), `Circular dependency: ${stack.concat(file).join(' -> ')}`);
    if (visited.has(file)) return;
    stack.push(file); for (const next of dependencies.get(file)) visit(next); stack.pop(); visited.add(file);
  }
  for (const file of source.keys()) visit(file);
});

test('reader ownership and note identity policies have no platform, clock or persistence side effects', () => {
  for (const file of ['services/document/ReaderCommitPolicy.ets', 'services/storage/NoteIdentity.ets']) {
    const text = source.get(file);
    assert.ok(!/@kit\.|@ohos\.|AppStorage|Date\.now\(|new Date\(|getContext\(|setTimeout\(|fileIo|relationalStore/.test(text), file);
  }
});

test('release resource policy excludes debugging samples and production bootstrap starts with no seed library', () => {
  const project = path.resolve(root, '../../../..');
  const profile = fs.readFileSync(path.join(project, 'entry/build-profile.json5'), 'utf8');
  for (const sample of ['**/debug-pdf-preview/**', '**/example-course.pdf', '**/example-snapshot.pdf']) assert.ok(profile.includes(sample));
  const page = source.get('pages/Index.ets');
  assert.ok(page.includes('this.storage.load(context, [])'));
  assert.ok(!/from\s+['"][^'"]*(?:SeedContent|fixtures)/.test(page));
});
