import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parseJsonc, packageErrors, deviceEvidenceErrors, REQUIRED_CASES } from './app-market-policy.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const argument = name => { const i = process.argv.indexOf(name); return i < 0 ? '' : process.argv[i + 1] || ''; };
const projectOnly = process.argv.includes('--project-only');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const json = file => parseJsonc(read(file));
const rows = [];
const record = (id, scope, passed, detail) => rows.push({ id, scope, status: passed ? 'PASS' : 'BLOCKED', detail });
const config = json('release/app-market.json');
const app = json('AppScope/app.json5').app;
const module = json('entry/src/main/module.json5').module;
const product = json('build-profile.json5').app.products.find(p => p.name === 'default');
const permissions = module.requestPermissions.map(p => p.name);
const devices = module.deviceTypes;
const expected = { bundleName: app.bundleName, versionName: app.versionName, versionCode: app.versionCode,
  devices, permissions, minApi: Number(/\((\d+)\)/.exec(product.compatibleSdkVersion)?.[1]), targetApi: Number(product.targetSdkVersion.split('.')[0]) };
record('identity', 'project', app.bundleName === config.bundleName && /^([A-Za-z][\w]*\.)+[A-Za-z][\w]*$/.test(app.bundleName), '统一应用身份与市场登记配置');
record('upgrade_version', 'project', Number.isInteger(app.versionCode) && app.versionCode > config.previousReleaseCode && /^\d+\.\d+\.\d+$/.test(app.versionName), '候选版本高于现有 v1.0.0');
record('devices', 'project', JSON.stringify([...devices].sort()) === JSON.stringify(['phone', 'tablet']), '首发统一手机与 Pad 应用包');
record('permissions', 'project', JSON.stringify([...permissions].sort()) === JSON.stringify(['ohos.permission.DISTRIBUTED_DATASYNC','ohos.permission.INTERNET']), '仅联网与主动附近传递权限');
const distributed = module.requestPermissions.find(p => p.name === 'ohos.permission.DISTRIBUTED_DATASYNC');
record('permission_reason', 'project', !!distributed?.reason && distributed?.usedScene?.when === 'inuse' && distributed.usedScene.abilities.includes('EntryAbility'), '设备权限有用途说明，使用时申请');
record('backup', 'project', json('entry/src/main/resources/base/profile/backup_config.json').allowToBackupRestore === false, '关闭整包备份；保留应用内资料导出');
const release = json('entry/build-profile.json5').buildOptionSet.find(p => p.name === 'release');
const rules = read('entry/obfuscation-rules.txt');
record('release_obfuscation', 'project', release?.arkOptions?.obfuscation?.ruleOptions?.enable === true && /^-remove-log$/m.test(rules) && !/^-enable-(property|export|filename)-obfuscation$/m.test(rules), '发布混淆保留 JSON、协议与存储字段，移除 console');
record('dependencies', 'project', Object.keys(json('entry/oh-package.json5').dependencies || {}).length === 0 && !json('entry/build-profile.json5').buildOption.externalNativeOptions, '生产包没有额外 SDK 或未使用的原生模板');
const generated = spawnSync(process.execPath, [path.join(root,'tools/generate-market-materials.mjs'), '--check'], { cwd: root, encoding: 'utf8' });
record('privacy_consistency', 'project', generated.status === 0, '应用内与可托管隐私说明来自同一份数据');
record('secret_protection', 'project', read('entry/src/main/ets/services/ai/ModelConfigService.ets').includes("clean.apiKey = ''") &&
  read('entry/src/main/ets/services/ai/HuksCredentialStore.ets').includes('HUKS_MODE_GCM'), '模型元数据不保存明文密钥；运行行为由工作流测试核验');
for (const file of ['providers/OpenAiCompatProvider.ets', 'providers/GeminiProvider.ets', 'providers/AnthropicProvider.ets', 'EmbeddingProvider.ets']) {
  const source = read(`entry/src/main/ets/services/ai/${file}`);
  record(`transport_${file}`, 'project', source.includes('RemoteAiPolicy.assertAllowed(profile)') && source.includes('maxRedirects: 0'), '聊天、连接测试与向量入口检查授权和安全传输');
}
record('stream_transport', 'project', read('entry/src/main/ets/services/ai/SseHttpClient.ets').includes('maxRedirects: 0'), '原生流式接收不跟随重定向');
record('first_launch_empty', 'project', read('entry/src/main/ets/pages/Index.ets').includes('this.storage.load(context, [])') &&
  !fs.existsSync(path.join(root,'entry/src/main/ets/common/seed/SeedContent.ets')), '首次启动为空，示例仅在开发测试目录');
record('offline_assistant_release', 'project', config.assistantMode === 'local-only' &&
  read('entry/src/main/ets/common/constants/RuntimeCapabilities.ets').includes('REMOTE_AI_ENABLED: boolean = DEBUG') &&
  read('entry/src/main/ets/services/ai/RemoteAiPolicy.ets').includes('if (!REMOTE_AI_ENABLED)'), '发布模式仅提供本地助手，远程模型入口由编译模式与网络策略共同关闭');
record('public_identity', 'submission', typeof config.publisher === 'string' && config.publisher.trim().length > 0 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(config.supportEmail || '') &&
  Number.isInteger(config.privacyResponseWorkingDays) && config.privacyResponseWorkingDays > 0 && config.privacyResponseWorkingDays <= 15, '填写与 AGC 一致的真实发布者、有效客服邮箱及隐私回复期限');
record('public_privacy', 'submission', /^https:\/\/[^\s@]+$/i.test(config.privacyUrl || '') && !/example\.(com|org)|localhost|待填写/.test(config.privacyUrl), '填写已托管且可公开访问的 HTTPS 隐私政策网址，提交前人工核对全文');

function evidence(file) {
  if (!file || !file.startsWith('release/evidence/')) return null;
  const resolved = path.resolve(root, file);
  const folder = path.resolve(root, 'release/evidence') + path.sep;
  if (!resolved.startsWith(folder) || !fs.existsSync(resolved) || !fs.realpathSync(resolved).startsWith(fs.realpathSync(path.dirname(folder)) + path.sep)) return null;
  try { return JSON.parse(fs.readFileSync(resolved, 'utf8')); } catch { return null; }
}
function currentReview(file, kind, extra = () => true) {
  const value = evidence(file);
  const date = Date.parse(value?.checkedAt);
  return value?.kind === kind && value?.reviewed === true && value.reviewer && value.reference &&
    Number.isFinite(date) && date <= Date.now() + 60000 && Date.now() - date <= 30 * 86400000 && extra(value);
}
record('sdk_eligibility', 'submission', currentReview(config.sdkReleaseEvidence, 'sdk', e => e.targetSdkVersion === product.targetSdkVersion && e.compatibleSdkVersion === product.compatibleSdkVersion), '核对当前 AGC 接受的 SDK 与系统版本；包内 Release 字段不能替代此证据');
record('qualification', 'submission', currentReview(config.qualificationEvidence, 'qualification', e => e.publisher === config.publisher && e.bundleName === app.bundleName), '发布帐号、类别资质/备案与素材授权按实际发布地区完成核对');
record('ai_service_review', 'submission', currentReview(config.aiServiceReviewEvidence, 'ai-service'), '按本地助手的实际发布范围核对地区与类别要求；本次发布不包含远程生成式模型入口');

const status = spawnSync('git', ['status','--porcelain','--untracked-files=all'], { cwd: root, encoding:'utf8' });
const dirty = (status.stdout || '').trim().split(/\r?\n/).filter(line => line && !line.endsWith(' pack.info'));
const commit = spawnSync('git', ['rev-parse','HEAD'], { cwd:root, encoding:'utf8' });
expected.sourceCommit = (commit.stdout || '').trim();
record('source_snapshot', 'submission', status.status === 0 && commit.status === 0 && dirty.length === 0, '提交包应对应已保存的干净 Git 提交');

let packageReport = null;
const appPath = argument('--app');
const studio = argument('--studio') || process.env.DEVECO_STUDIO_HOME || '';
if (appPath) {
  const inspectArgs = [path.join(root,'tools/inspect-app.py'), path.resolve(root,appPath)];
  if (studio) inspectArgs.push('--java', path.join(studio,'jbr/bin/java.exe'), '--signer', path.join(studio,'sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar'));
  const result = spawnSync(argument('--python') || 'python', inspectArgs, { cwd:root, encoding:'utf8', timeout:180000, maxBuffer:8*1024*1024 });
  try { packageReport = JSON.parse(result.stdout); } catch { packageReport = null; }
  if (result.status !== 0) packageReport = null;
  const errors = packageErrors(packageReport, expected);
  record('package_metadata', 'package', errors.length === 0, errors.join('；') || 'APP/HAP 版本、设备、权限、备份与发布模式一致');
  const signed = packageErrors(packageReport, expected, true);
  record('package_signature', 'submission', !!studio && signed.length === 0, signed.join('；') || 'SDK 已校验每个 HAP；另需核对 AGC 发布证书及 profile');
  const chain = packageReport?.modules?.[0]?.certificateChainSha256;
  record('signing_identity', 'submission', !!chain && currentReview(config.signingEvidence, 'signing', e =>
    e.bundleName === app.bundleName && e.publisher === config.publisher && e.profileType === 'release' && e.distribution === 'app_gallery' &&
    e.certificateChainSha256 === chain && e.appSha256 === packageReport.appSha256), '用对应 AGC 发布证书与分发 profile；不能使用开发或自签证书代替');
} else {
  record('package_metadata','package',false,'需检查本次 APP 实际内容');
  record('package_signature','submission',false,'需正式签名 APP 和当前 SDK 签名校验');
  record('signing_identity','submission',false,'需核对 AGC 发布证书、profile 与主体');
}
expected.appSha256 = packageReport?.appSha256;
const qa = evidence(config.deviceEvidence);
const qaErrors = deviceEvidenceErrors(qa, expected);
const fileExists = file => file && file.startsWith('release/evidence/') && path.resolve(root,file).startsWith(path.resolve(root,'release/evidence') + path.sep) && fs.existsSync(path.resolve(root,file)) && fs.statSync(path.resolve(root,file)).isFile() && fs.statSync(path.resolve(root,file)).size > 0;
const qaFiles = qa && (qa.devices || []).every(d => REQUIRED_CASES.every(id => fileExists(d.cases?.[id]?.evidence)));
record('physical_devices','submission', !!expected.appSha256 && qaErrors.length === 0 && qaFiles, qaErrors.join('；') || (qaFiles ? '双端真机完整记录对应本次包' : '真机检查需实际证据文件'));
const screenshotTypes = new Set((config.screenshots || []).filter(s => devices.includes(s.device) && /^release\/evidence\/.+\.(png|jpe?g)$/i.test(s.path) && fileExists(s.path) && s.appSha256 === expected.appSha256).map(s => s.device));
record('screenshots','submission', !!expected.appSha256 && devices.every(d => screenshotTypes.has(d)), '每种设备至少有真实候选包截图；数量与尺寸以当前 AGC 页面为准');

const blockers = rows.filter(r => r.status === 'BLOCKED');
const report = { generatedAt:new Date().toISOString(), mode:projectOnly?'project-only':'submission', sourceCommit:expected.sourceCommit,
  versionName:app.versionName, versionCode:app.versionCode, appSha256:expected.appSha256 || null,
  marketReady:blockers.length === 0, checks:rows };
const output = argument('--report');
if (output) { const full = path.resolve(root,output); fs.mkdirSync(path.dirname(full),{recursive:true}); fs.writeFileSync(full,JSON.stringify(report,null,2)+'\n'); }
for (const row of rows) console.log(`${row.status.padEnd(7)} ${row.id}: ${row.detail}`);
console.log(report.marketReady ? '发布前置检查通过；仍需在 AGC 完成最终提交审核。' : '候选尚不可提交市场，以上 BLOCKED 项必须补齐。');
const activeBlockers = blockers.filter(r => !projectOnly || r.scope === 'project' || (appPath && r.scope === 'package'));
process.exitCode = activeBlockers.length ? 1 : 0;
