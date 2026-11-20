function zonedTimestamp(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value) || !Number.isFinite(Date.parse(value))) return false;
  const [year, month, day] = value.slice(0, 10).split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day)).toISOString().slice(0, 10) === value.slice(0, 10);
}
const nonempty = value => typeof value === 'string' && value.trim().length > 0;
const localDate = value => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit'
}).format(new Date(value));
const fresh = (value, now, maxDays) => zonedTimestamp(value) &&
  Date.parse(value) <= now && now - Date.parse(value) <= maxDays * 86400000;
// The strict market preflight emits all of these checks; a truncated PASS report is insufficient.
export const REQUIRED_MARKET_CHECKS = [
  'identity', 'upgrade_version', 'devices', 'permissions', 'backup', 'release_obfuscation', 'dependencies',
  'privacy_consistency', 'feature_source_audit', 'first_launch_empty', 'release_debug_samples', 'local_rules_only',
  'public_identity', 'public_privacy', 'sdk_eligibility', 'qualification', 'feature_scope_review', 'source_snapshot',
  'package_metadata', 'package_signature', 'signing_identity', 'physical_devices', 'screenshots'
];
const sameMembers = (actual, expected) => Array.isArray(actual) && actual.length === expected.length &&
  new Set(actual).size === expected.length && expected.every(value => actual.includes(value));

/** Rules supplied by the user; project structure checks do not imply market eligibility. */
export function competitionRuleErrors(rules) {
  const errors = [];
  if (rules?.schemaVersion !== 1 || rules.timezone !== 'Asia/Shanghai' || !nonempty(rules.ruleSource)) errors.push('比赛规则版本、时区或来源缺失');
  const weights = { businessValue: 40, innovation: 30, completion: 20, engineering: 10 };
  if (!rules?.scoring || Object.keys(rules.scoring).length !== 4 || Object.entries(weights).some(([key, value]) => rules.scoring[key] !== value)) errors.push('评审权重必须为40/30/20/10');
  const first = rules?.stages?.preliminary, final = rules?.stages?.final;
  if (first?.deadlineDate !== '2026-10-31' || first.deadlineExclusive !== false ||
    !sameMembers(first.allowedChannels, ['appgallery_public_preview', 'appgallery_formal']) || first.requiresPublicAccess !== true) errors.push('初赛须在10月31日提交，允许公开尝鲜或正式市场');
  if (final?.deadlineDate !== '2026-11-27' || final.deadlineExclusive !== true ||
    !sameMembers(final.allowedChannels, ['appgallery_formal']) || final.requiresPublicAccess !== true) errors.push('决赛须在11月27日前正式市场上架');
  if (!['apptest_invitation', 'invitation_test', 'github_release', 'local_package'].every(channel => rules?.rejectedChannels?.includes(channel))) errors.push('必须排除邀请测试和本地／GitHub包');
  if (!Number.isInteger(rules?.evidenceMaxAgeDays) || rules.evidenceMaxAgeDays < 1 || rules.evidenceMaxAgeDays > 7) errors.push('内部证据复核期限必须在1至7天内');
  if (!Array.isArray(rules?.materials) || !rules.materials.length || rules.materials.some(file => typeof file !== 'string' || !/^docs\/[A-Z_]+\.md$/.test(file))) errors.push('比赛材料清单缺失或路径不合法');
  return errors;
}

/** Validate recorded evidence only. Market facts still require the named human review. */
export function competitionEvidenceErrors(rules, stage, evidence, expected, marketReport, now = Date.now()) {
  const errors = competitionRuleErrors(rules);
  if (errors.length) return errors;
  const policy = rules?.stages?.[stage];
  if (!['preliminary', 'final'].includes(stage) || !policy) return [...errors, '必须指定preliminary或final阶段'];
  if (!Number.isFinite(now)) return [...errors, '核验时间无效'];
  if (!evidence || typeof evidence !== 'object') return [...errors, '缺少本轮真实市场上架证据'];
  if (evidence.schemaVersion !== 1 || evidence.stage !== stage) errors.push('证据版本或阶段不匹配');
  for (const key of ['bundleName', 'versionName', 'versionCode', 'sourceCommit', 'appSha256']) {
    if (expected?.[key] === undefined || expected[key] === '' || evidence[key] !== expected[key]) errors.push(`市场证据与候选${key}不匹配`);
  }
  if (!/^[a-f\d]{40}$/i.test(expected?.sourceCommit || '') || !/^[a-f\d]{64}$/i.test(expected?.appSha256 || '')) errors.push('候选源码提交或实际APP摘要无效');
  if (!policy.allowedChannels?.includes(evidence.channel) || rules.rejectedChannels?.includes(evidence.channel)) errors.push('上架渠道不满足本轮要求，AppTest邀请测试不得替代上架');
  if (evidence.status !== 'published' || evidence.publicAccessible !== true || evidence.requiresInvitation !== false) errors.push('必须已发布且公开可获取，不能是邀请、草稿或审核中');
  try {
    const url = new URL(evidence.marketUrl);
    if (url.protocol !== 'https:' || url.username || url.password || !['appgallery.huawei.com', 'appgallery.cloud.huawei.com'].includes(url.hostname)) throw Error();
  } catch { errors.push('需要官方应用市场HTTPS详情链接'); }
  const published = zonedTimestamp(evidence.publishedAt), checked = zonedTimestamp(evidence.checkedAt);
  if (!published || Date.parse(evidence.publishedAt) > now) errors.push('上架时间缺失、无时区或在未来');
  if (published) {
    const day = localDate(evidence.publishedAt);
    if (policy.deadlineExclusive ? day >= policy.deadlineDate : day > policy.deadlineDate) errors.push('上架时间超过本轮北京时间截止日');
  }
  if (evidence.reviewed !== true || !nonempty(evidence.reviewer) || !fresh(evidence.checkedAt, now, rules.evidenceMaxAgeDays)) errors.push('需具名且近期的真实可下载复核记录');
  if (published && checked && Date.parse(evidence.publishedAt) > Date.parse(evidence.checkedAt)) errors.push('复核时间不能早于上架时间');
  if (!nonempty(evidence.marketProof) || !nonempty(evidence.downloadProof)) errors.push('缺少上架状态与公开下载证据文件');
  if (marketReport?.mode !== 'submission' || marketReport.marketReady !== true ||
    !Array.isArray(marketReport.checks) || marketReport.checks.some(row => row?.status !== 'PASS') ||
    !REQUIRED_MARKET_CHECKS.every(id => marketReport.checks.some(row => row?.id === id && row.status === 'PASS'))) errors.push('市场严格预检尚未全部通过或缺少检查项，project-only报告不可替代');
  for (const key of ['versionName', 'versionCode', 'sourceCommit', 'appSha256']) {
    if (marketReport?.[key] !== expected?.[key]) errors.push(`市场预检报告与候选${key}不匹配`);
  }
  if (!fresh(marketReport?.generatedAt, now, rules.evidenceMaxAgeDays)) errors.push('市场预检报告过期或时间无效');
  return errors;
}
