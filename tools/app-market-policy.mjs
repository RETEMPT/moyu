export const REQUIRED_CASES = [
  'privacy_offline', 'offline_learning', 'ocr_pdf_cancel', 'reader_restart', 'upgrade_persistence',
  'permission_denied', 'ai_consent_revoke', 'ai_failure_cancel', 'backup_restore', 'nearby_transfer',
  'nearby_interruption_cleanup', 'keyboard_small_screen', 'font_rotation_multiwindow',
  'dark_reduce_motion', 'performance', 'delete_export',
  'first_launch_empty', 'local_assistant', 'create_note', 'stylus_handwriting'
];

/** Parse JSON with comments/trailing commas without executing configuration as JavaScript. */
export function parseJsonc(source) {
  let out = ''; let quoted = false; let escaped = false;
  for (let i = 0; i < source.length; i++) {
    const c = source[i];
    if (quoted) {
      out += c;
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === '"') quoted = false;
    } else if (c === '"') { quoted = true; out += c; }
    else if (c === '/' && source[i + 1] === '/') { while (i < source.length && source[i] !== '\n') i++; out += '\n'; }
    else if (c === '/' && source[i + 1] === '*') {
      i += 2; while (i < source.length && !(source[i] === '*' && source[i + 1] === '/')) i++;
      if (i >= source.length) throw Error('Unterminated comment'); i++; out += ' ';
    } else out += c;
  }
  let clean = ''; quoted = false; escaped = false;
  for (let i = 0; i < out.length; i++) {
    const c = out[i];
    if (!quoted && c === ',') { let j = i + 1; while (/\s/.test(out[j] || '') && j < out.length) j++; if (out[j] === '}' || out[j] === ']') continue; }
    clean += c;
    if (quoted) { if (escaped) escaped = false; else if (c === '\\') escaped = true; else if (c === '"') quoted = false; }
    else if (c === '"') quoted = true;
  }
  return JSON.parse(clean);
}

export function packageErrors(report, expected, requireSignature = false) {
  const errors = [];
  if (!report || report.error || !Array.isArray(report.modules) || !report.modules.length) return ['无法检查 APP'];
  const version = report.pack?.summary?.app;
  if (version?.bundleName !== expected.bundleName || version?.version?.code !== expected.versionCode || version?.version?.name !== expected.versionName) errors.push('APP 汇总身份或版本不匹配');
  if (report.modules.length !== 1 || report.modules[0].module?.name !== 'entry') errors.push('APP 模块不符合当前发布结构');
  for (const module of report.modules) {
    const app = module.app;
    if (app?.bundleName !== expected.bundleName || app?.versionCode !== expected.versionCode || app?.versionName !== expected.versionName) errors.push('HAP 身份或版本不匹配');
    if (app?.debug !== false || app?.buildMode !== 'release') errors.push('存在调试模块');
    if (app?.apiReleaseType !== 'Release' || app?.compileSdkType !== 'HarmonyOS') errors.push('SDK 包类型不符合候选配置');
    if (expected.minApi && app?.minAPIVersion % 100 !== expected.minApi) errors.push('最低 API 与工程不匹配');
    if (expected.targetApi && app?.targetAPIVersion % 100 !== expected.targetApi) errors.push('目标 API 与工程不匹配');
    if (JSON.stringify([...(module.module?.deviceTypes || [])].sort()) !== JSON.stringify([...expected.devices].sort())) errors.push('设备声明与工程不匹配');
    if (module.backup?.allowToBackupRestore !== false) errors.push('整包备份未关闭');
    if ((module.nativeLibraries || []).length) errors.push('出现未声明的原生库');
    const permissions = (module.module?.requestPermissions || []).map(p => p.name).sort();
    if (JSON.stringify(permissions) !== JSON.stringify([...expected.permissions].sort())) errors.push('打包权限与工程不匹配');
    if (requireSignature && module.signatureVerified !== true) errors.push('未通过 SDK 签名校验');
  }
  return [...new Set(errors)];
}

export function deviceEvidenceErrors(evidence, expected, now = Date.now()) {
  if (!evidence || evidence.versionCode !== expected.versionCode || evidence.appSha256 !== expected.appSha256 || evidence.sourceCommit !== expected.sourceCommit) return ['真机记录未对应本次包和提交'];
  const errors = [];
  for (const type of expected.devices) {
    const rows = (evidence.devices || []).filter(d => d.type === type && d.physical === true && d.model && d.systemVersion && d.tester);
    const passed = rows.some(d => {
      const checked = Date.parse(d.checkedAt);
      if (!Number.isFinite(checked) || checked > now + 60000 || now - checked > 30 * 86400000) return false;
      return REQUIRED_CASES.every(id => d.cases?.[id]?.status === 'PASS' && typeof d.cases[id].evidence === 'string' && d.cases[id].evidence.trim());
    });
    if (!passed) errors.push(`${type} 缺少有效的完整真机记录`);
  }
  return errors;
}
