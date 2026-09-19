/**
 * 墨语 (FlowMind) 图标生成器
 *
 * 从 design/*.svg 母版光栅化出应用所需的全部 PNG 资源。
 *
 * 桌面图标采用「默认图标 + 备用图标(alternateIcons)」方案，而不是 dark 资源限定符：
 *   - 默认图标：layered_image.json        -> icon_background / icon_foreground        （浅色）
 *   - 备用图标：layered_image_dark.json   -> icon_background_dark / icon_foreground_dark（深色）
 * 应用内热切换主题时调用 bundleManager.setAlternateIcon('theme_dark' | '') 真正换掉桌面图标。
 * 之所以不用 resources/dark 限定符：那条路由跟随的是「系统」深浅色，而我们要跟随的是
 * 「应用内」选定的主题，两者可能不一致。
 *
 * 应用内品牌标与启动页图标另出一套带圆角的合成图，由组件按主题布尔值显式二选一。
 *
 * 光栅化走 Edge (Chromium) 无头模式，无需额外依赖。
 *
 * 用法:  node tools/generate-icons.mjs
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const DESIGN = join(ROOT, 'design');
const TMP = join(ROOT, '.tmp-icons');

const EDGE_CANDIDATES = [
  'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
];

function findBrowser() {
  for (const candidate of EDGE_CANDIDATES) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }
  throw new Error('未找到 Edge/Chrome，无法光栅化 SVG。请安装其中之一或改用其他工具链。');
}

/**
 * 把单个 SVG 渲染成 PNG。
 * 用 --default-background-color=00000000 保证透明区域真的是透明，
 * 否则 Chromium 会给截图填上白底，前景层就会带上白色方块。
 */
function renderSvg(browser, svgPath, outPath, size) {
  const svg = readFileSync(svgPath, 'utf8');
  const htmlPath = join(TMP, `${outPath.split(/[\\/]/).pop()}.html`);
  writeFileSync(htmlPath, `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;width:${size}px;height:${size}px;overflow:hidden}
svg{display:block;width:${size}px;height:${size}px}
</style></head><body>${svg}</body></html>`, 'utf8');

  mkdirSync(dirname(outPath), { recursive: true });
  rmSync(outPath, { force: true });

  execFileSync(browser, [
    '--headless',
    '--disable-gpu',
    '--no-sandbox',
    '--hide-scrollbars',
    '--force-device-scale-factor=1',
    `--window-size=${size},${size}`,
    '--default-background-color=00000000',
    `--screenshot=${outPath}`,
    `file:///${htmlPath.replace(/\\/g, '/')}`,
  ], { stdio: ['ignore', 'ignore', 'ignore'] });

  if (!existsSync(outPath)) {
    throw new Error(`渲染失败: ${outPath}`);
  }
  return statSync(outPath).size;
}

/**
 * 资源名要同时落到 AppScope（应用级图标，app.json5 用）与 entry 模块
 * （module.json5 里 ability 的图标用）。二者合并进同一张资源表，内容必须一致。
 */
function appAndModuleMedia(fileName) {
  return [
    join(ROOT, 'AppScope', 'resources', 'base', 'media', fileName),
    join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media', fileName),
  ];
}

const browser = findBrowser();
rmSync(TMP, { recursive: true, force: true });
mkdirSync(TMP, { recursive: true });

/** [描述, 源 SVG, [输出路径…], 尺寸] */
const jobs = [];

for (const theme of ['light', 'dark']) {
  const isDark = theme === 'dark';
  const infix = isDark ? '_dark' : '';

  // 1) 桌面分层图标：默认图标（浅色）与备用图标（深色）各一套，
  //    统一放在 base/ 下，由 setAlternateIcon 在运行时切换。
  for (const [role, suffix] of [['background', 'bg'], ['foreground', 'fg']]) {
    jobs.push([
      `分层图标 ${theme}/${role}`,
      join(DESIGN, `launcher_${suffix}_${theme}.svg`),
      appAndModuleMedia(`icon_${role}${infix}.png`),
      1024,
    ]);
  }

  // 2) 应用内品牌标：两份都进 base，靠组件按主题布尔值显式二选一
  jobs.push([
    `应用内品牌标 ${theme}`,
    join(DESIGN, `app_mark_${theme}.svg`),
    [join(ROOT, 'entry', 'src', 'main', 'resources', 'base', 'media', `brand_mark_${theme}.png`)],
    512,
  ]);

  // 3) 启动页图标（仍按系统深浅色限定符自动选，启动页先于应用内主题加载）
  jobs.push([
    `启动页图标 ${theme}`,
    join(DESIGN, `app_mark_${theme}.svg`),
    [join(ROOT, 'entry', 'src', 'main', 'resources', isDark ? 'dark' : 'base', 'media', 'startIcon.png')],
    512,
  ]);
}

// 4) 分层图标的描述文件：默认图标 + 备用图标
const layerDescriptors = [
  ['layered_image.json', '$media:icon_background', '$media:icon_foreground', '默认图标（浅色）'],
  ['layered_image_dark.json', '$media:icon_background_dark', '$media:icon_foreground_dark', '备用图标（深色）'],
];
for (const [fileName, background, foreground, label] of layerDescriptors) {
  const body = `{
  "layered-image":
  {
    "background" : "${background}",
    "foreground" : "${foreground}"
  }
}
`;
  for (const target of appAndModuleMedia(fileName)) {
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, body, 'utf8');
  }
  console.log(`✓ ${label}  ${fileName} ×2`);
}

let total = 0;
for (const [label, svgPath, targets, size] of jobs) {
  let bytes = 0;
  for (const target of targets) {
    bytes = renderSvg(browser, svgPath, target, size);
    total += bytes;
  }
  const short = targets.map((t) => t.replace(ROOT + '\\', '').replace(/\\/g, '/'));
  console.log(`✓ ${label}  ${size}x${size}  ${(bytes / 1024).toFixed(1)}KB  ×${targets.length}`);
  for (const t of short) {
    console.log(`    ${t}`);
  }
}

rmSync(TMP, { recursive: true, force: true });
console.log(`\n完成：共写入 ${total} 字节。`);
