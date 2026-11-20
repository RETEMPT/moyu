import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { parseJsonc } from './app-market-policy.mjs';
import { competitionRuleErrors, competitionEvidenceErrors } from './competition-policy.mjs';

const root = path.resolve(import.meta.dirname, '..');
const argument = name => { const index = process.argv.indexOf(name); return index < 0 ? '' : process.argv[index + 1] || ''; };
const rules = JSON.parse(fs.readFileSync(path.join(root, 'release/competition.json'), 'utf8'));
const app = parseJsonc(fs.readFileSync(path.join(root, 'AppScope/app.json5'), 'utf8')).app;
const stage = argument('--stage') || 'preliminary';
const projectOnly = process.argv.includes('--project-only');
const projectErrors = competitionRuleErrors(rules);
if (!['preliminary', 'final'].includes(stage)) projectErrors.push('阶段必须为preliminary或final');
for (const file of rules.materials || []) {
  const target = path.resolve(root, file);
  if (!target.startsWith(path.join(root, 'docs') + path.sep) || !fs.existsSync(target) || fs.statSync(target).size === 0) projectErrors.push(`缺少本地评审材料：${file}`);
}

const blockers = [];
function readEvidence(file) {
  if (!file) return null;
  const folder = path.join(root, 'release/evidence');
  const target = path.resolve(root, file);
  if (!target.startsWith(folder + path.sep) || !fs.existsSync(target) || !fs.statSync(target).isFile()) throw Error('证据必须是release/evidence内的文件');
  if (!fs.realpathSync(target).startsWith(fs.realpathSync(folder) + path.sep)) throw Error('证据实际路径超出目录');
  return target;
}
function jsonEvidence(flag) {
  try { const file = readEvidence(argument(flag)); return file ? JSON.parse(fs.readFileSync(file, 'utf8')) : null; }
  catch (error) { blockers.push(`${flag}: ${error.message}`); return null; }
}
const evidence = jsonEvidence('--evidence');
const marketReport = jsonEvidence('--market-report');
let appSha256 = '';
try {
  if (argument('--app')) appSha256 = createHash('sha256').update(fs.readFileSync(path.resolve(root, argument('--app')))).digest('hex');
  else blockers.push('须通过--app提供本次实际签名APP以核对SHA-256');
} catch (error) { blockers.push(`APP读取失败：${error.message}`); }
const commit = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8', windowsHide: true });
const status = spawnSync('git', ['status', '--porcelain', '--untracked-files=all'], { cwd: root, encoding: 'utf8', windowsHide: true });
if (commit.status !== 0 || status.status !== 0 || status.stdout.trim()) blockers.push('候选源码须对应当前已保存的干净Git提交');
const expected = { bundleName: app.bundleName, versionName: app.versionName, versionCode: app.versionCode,
  sourceCommit: (commit.stdout || '').trim(), appSha256 };
blockers.push(...competitionEvidenceErrors(rules, stage, evidence, expected, marketReport));
for (const key of ['marketProof', 'downloadProof']) {
  try {
    const file = readEvidence(evidence?.[key]);
    if (!file || fs.statSync(file).size === 0) blockers.push(`${key}需要实际非空证据文件`);
  } catch (error) { blockers.push(`${key}: ${error.message}`); }
}
const report = { generatedAt: new Date().toISOString(), mode: projectOnly ? 'project-only' : 'submission', stage,
  ...expected, projectReady: projectErrors.length === 0, submissionReady: !projectOnly && projectErrors.length === 0 && blockers.length === 0,
  projectErrors, blockers: [...new Set(blockers)], note: '依据具名记录核验；脚本不访问市场，实际公开可下载状态须人工复核。' };
if (argument('--report')) {
  const output = path.resolve(root, argument('--report'));
  if (!output.startsWith(path.join(root, 'tmp') + path.sep) && !output.startsWith(path.join(root, 'release/reports') + path.sep)) throw Error('报告仅写入tmp或release/reports');
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
}
for (const error of projectErrors) console.log(`FAIL project: ${error}`);
for (const error of report.blockers) console.log(`BLOCKED submission: ${error}`);
console.log(projectOnly ? `材料结构${report.projectReady ? '通过' : '失败'}；不表示市场资格通过。` : report.submissionReady ? '本轮记录核验通过；提交前复核官方市场可下载状态。' : '本轮参赛资格尚未满足。');
process.exitCode = projectOnly ? (report.projectReady ? 0 : 1) : (report.submissionReady ? 0 : 1);
