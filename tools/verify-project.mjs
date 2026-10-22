import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const output = path.join(root, 'tmp', 'verification-latest');
fs.mkdirSync(output, { recursive: true });
const index = process.argv.indexOf('--typescript');
if (index >= 0 && !process.argv[index + 1]) throw new Error('--typescript requires a compiler path');
const compiler = index >= 0 ? ['--typescript', path.resolve(process.argv[index + 1])] : [];
const suites = [
  ['architecture', 'verify-architecture.mjs'],
  ['workflows', 'verify-workflows.mjs', ...compiler],
  ['pdf', 'verify-pdf-chain.mjs', ...compiler],
  ['sources', 'verify-source-management.mjs', ...compiler],
  ['repository', 'verify-rdb-repository.mjs', ...compiler],
  ['editor-lifecycle', 'verify-editor-lifecycle.mjs', ...compiler],
  ['market', 'verify-app-market.mjs'],
  ['documentation', 'verify-documentation.mjs'],
  ['scope', 'verify-local-release.mjs'],
  ['icons', 'generate-ui-icons.mjs', '--check'],
  ['materials', 'generate-market-materials.mjs', '--check'],
  ['preflight', 'app-market-preflight.mjs', '--project-only']
];
if (process.argv.includes('--local-docs')) suites.push(
  ['local-docs', 'verify-local-release.mjs', '--local-docs'],
  ['competition', 'verify-competition.mjs'],
  ['competition-materials', 'competition-preflight.mjs', '--project-only', '--report', 'tmp/competition-project-latest.json']
);
if (process.argv.includes('--compiled')) suites.push(['compiled-ui', 'verify-compiled-ui.mjs', ...compiler]);
const results = [];
for (const [name, script, ...args] of suites) {
  const started = Date.now();
  const run = spawnSync(process.execPath, [path.join(root, 'tools', script), ...args], {
    cwd: root, encoding: 'utf8', windowsHide: true, maxBuffer: 12 * 1024 * 1024
  });
  const log = (run.stdout || '') + (run.stderr || '') + (run.error ? '\n' + run.error.message : '');
  fs.writeFileSync(path.join(output, name + '.log'), log);
  const passed = run.status === 0 && !run.error;
  const tests = Number(log.match(/(?:ℹ|#) tests (\d+)/)?.[1] || 0);
  results.push({ name, passed, tests, exitCode: run.status, elapsedMs: Date.now() - started });
  console.log(`${passed ? 'PASS' : 'FAIL'} ${name}${tests ? ` (${tests} tests)` : ''}`);
  if (!passed) console.error(log.slice(-5000));
}
const report = { checkedAt: new Date().toISOString(), compiledUi: process.argv.includes('--compiled'),
  passed: results.every(result => result.passed), tests: results.reduce((count, result) => count + result.tests, 0), results };
fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(report, null, 2) + '\n');
console.log(`${report.passed ? 'All checks passed' : 'Checks failed'}; ${report.tests} tests. Logs: tmp/verification-latest/`);
process.exitCode = report.passed ? 0 : 1;
