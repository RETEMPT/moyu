/** Original 24-unit line icons and the purple-ink brand masters. No network or font dependency. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const icons = {
  home: '<path d="m3 10 9-7 9 7v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/><path d="M9 21v-7h6v7"/>',
  note: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9Z"/><path d="M14 3v6h6M8 13h8M8 17h5"/>',
  sparkle: '<path d="m12 3 2.1 6.9L21 12l-6.9 2.1L12 21l-2.1-6.9L3 12l6.9-2.1Z"/><path d="M20 3v4M18 5h4"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/>',
  canvas: '<rect x="3" y="3" width="18" height="18" rx="3"/><path d="m7 16 2-5 5-5 4 4-5 5-6 1ZM9 11l4 4"/>',
  graph: '<path d="m7 7 10 1M7 7l3 11M17 8l-7 10"/><circle cx="6" cy="6" r="3"/><circle cx="18" cy="8" r="3"/><circle cx="10" cy="19" r="3"/>',
  check: '<rect x="3" y="3" width="18" height="18" rx="5"/><path d="m7 12 3.2 3.2L17 8.5"/>',
  star: '<path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9Z"/>',
  tag: '<path d="M3 4h8l10 10-7 7L3 10Z"/><circle cx="7.5" cy="8" r="1"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/>',
  menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
  link: '<path d="m10 14 4-4M9 16l-2 2a4.2 4.2 0 0 1-6-6l4-4a4.2 4.2 0 0 1 6 0M15 8l2-2a4.2 4.2 0 0 1 6 6l-4 4a4.2 4.2 0 0 1-6 0" transform="translate(1 0) scale(.92 1)"/>',
  import: '<path d="M4 14v5a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-5M12 3v12m-5-5 5 5 5-5"/>',
  cover: '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="8" cy="9" r="1.5"/><path d="m4 17 5-5 4 4 3-3 4 4"/>',
  pen: '<path d="m14 3 7 7-7 7-11 4 4-11Z"/><path d="m14 3-3 3 7 7 3-3M3 21l7-7"/><circle cx="11" cy="13" r="1.4"/>',
  highlighter: '<path d="m14 3 7 7-8 8-7-7ZM6 11l-3 6 4 4 6-3M3 21h8"/>',
  eraser: '<path d="m14 3 7 7-10 11H6l-4-4ZM8 11l7 7M11 21h10"/>',
  undo: '<path d="m8 4-5 5 5 5M3 9h10a7 7 0 0 1 0 14" transform="translate(0 -2)"/>',
  redo: '<path d="m16 4 5 5-5 5M21 9H11a7 7 0 0 0 0 14" transform="translate(0 -2)"/>',
  hand: '<path d="M8 12V5a2 2 0 0 1 4 0v7-9a2 2 0 0 1 4 0v9-7a2 2 0 0 1 4 0v10c0 4-3 7-7 7h-1c-2 0-4-1-5-3l-4-6a2 2 0 0 1 3-2l2 2"/>',
  settings: '<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="8" cy="6" r="2" fill="#000"/><circle cx="16" cy="12" r="2" fill="#000"/><circle cx="10" cy="18" r="2" fill="#000"/>',
  more: '<circle cx="5" cy="12" r="1.4" fill="#000"/><circle cx="12" cy="12" r="1.4" fill="#000"/><circle cx="19" cy="12" r="1.4" fill="#000"/>',
  back: '<path d="M20 12H4m7-7-7 7 7 7"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  copy: '<rect x="8" y="8" width="13" height="13" rx="2"/><path d="M16 8V3H3v13h5"/>',
  send: '<path d="m3 3 18 9-18 9 4-9ZM7 12h14"/>',
  stop: '<rect x="5" y="5" width="14" height="14" rx="3"/>',
  refresh: '<path d="M20 9a8 8 0 0 0-14-3L3 9m0-6v6h6M4 15a8 8 0 0 0 14 3l3-3m0 6v-6h-6"/>',
  chevron_left: '<path d="m15 5-7 7 7 7"/>',
  chevron_right: '<path d="m9 5 7 7-7 7"/>',
  chevron_down: '<path d="m5 9 7 7 7-7"/>',
  chevron_up: '<path d="m5 15 7-7 7 7"/>',
  panel: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M15 4v16M18 8v8"/>',
  split: '<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M12 4v16"/>',
  fullscreen: '<path d="M3 9V3h6M15 3h6v6M21 15v6h-6M9 21H3v-6"/>',
  read: '<path d="M12 5c-3-2-6-2-9-1v15c3-1 6-1 9 1 3-2 6-2 9-1V4c-3-1-6-1-9 1Zm0 0v15"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
  format: '<path d="M4 5h16M12 5v14M8 19h8M4 12v-3M20 12v-3"/>',
  quote: '<path d="M10 5H4v7h6v-7Zm0 7c0 4-2 6-5 7M21 5h-6v7h6v-7Zm0 7c0 4-2 6-5 7"/>',
  list: '<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>',
  ordered: '<path d="M10 6h10M10 12h10M10 18h10M3 4h2v5M3 13c0-3 4-3 4-1 0 2-4 3-4 6h4"/>',
  bold: '<path d="M6 4h7a4 4 0 0 1 0 8H6Zm0 8h8a4 4 0 0 1 0 8H6Z"/>',
  italic: '<path d="M10 4h8M6 20h8M14 4l-4 16"/>',
  pin: '<path d="M8 3h8l-1 6 4 4v2H5v-2l4-4ZM12 15v6"/>',
  export: '<path d="M4 11v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8M12 16V3m-5 5 5-5 5 5"/>',
  folder: '<path d="M3 6a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/>',
  pdf: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9ZM14 3v6h6M8 13h8M8 17h8"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4M17 3v4M3 10h18M8 14h2M14 14h2M8 18h2"/>',
  cloud: '<path d="M6 19h12a4 4 0 0 0 1-7.9A7 7 0 0 0 5.4 9 5 5 0 0 0 6 19Z"/>',
  help: '<circle cx="12" cy="12" r="9"/><path d="M9 9a3 3 0 1 1 5 2c-2 1-2 1-2 3M12 17v.1"/>',
  clear: '<path d="M5 4v16M9 4h10a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H9M9 12h8m-3-3 3 3-3 3"/>',
  page: '<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 7h6M9 11h6M9 15h4"/>',
  code: '<path d="m8 6-6 6 6 6M16 6l6 6-6 6M14 3l-4 18"/>',
  strike: '<path d="M17 6c-2-4-11-4-11 1 0 2 2 3 5 4M7 18c3 4 11 3 11-1 0-2-2-3-5-4M3 12h18"/>',
  divider: '<path d="M3 12h18"/>',
  h1: '<path d="M3 5v14M12 5v14M3 12h9M17 8l3-2v13"/>',
  h2: '<path d="M3 5v14M12 5v14M3 12h9M17 9c0-4 5-4 5-1 0 3-5 4-5 9h5"/>',
  h3: '<path d="M3 5v14M12 5v14M3 12h9M17 6h5l-3 5c4 0 4 7 0 7l-2-1"/>'
};
const outputs = new Map();
for (const [name, body] of Object.entries(icons)) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">\n  ${body}\n</svg>\n`;
  outputs.set(`entry/src/main/resources/base/media/ic_${name}.svg`, svg);
}
for (const name of ['note', 'cover']) {
  outputs.set(`entry/src/main/resources/base/media/ic_${name}_white.svg`, outputs.get(`entry/src/main/resources/base/media/ic_${name}.svg`).replaceAll('#000000', '#FFFFFF').replaceAll('#000"', '#FFFFFF"'));
}

for (const theme of ['light', 'dark']) {
  const dark = theme === 'dark';
  const paper = dark ? '#221B32' : '#F5F1FC';
  const bg = `<defs><linearGradient id="paper" x1="0" y1="0" x2="1" y2="1"><stop stop-color="${dark ? '#181322' : '#FCFAFF'}"/><stop offset="1" stop-color="${dark ? '#30233F' : '#EDE7FA'}"/></linearGradient></defs>`;
  const mark = `<defs><linearGradient id="ink" x1="0" y1="0" x2="1" y2="1"><stop stop-color="${dark ? '#F1EBFF' : '#37304B'}"/><stop offset="1" stop-color="${dark ? '#D7CAFA' : '#1E192E'}"/></linearGradient><linearGradient id="accent" x1="0" y1="0" x2="1" y2="1"><stop stop-color="${dark ? '#C4B5FF' : '#9C7FFF'}"/><stop offset="1" stop-color="${dark ? '#9D80EE' : '#6D4AFF'}"/></linearGradient></defs>
  <path d="M239 794c58-69 100-8 193 18 91 26 179-9 233-66" fill="none" stroke="url(#accent)" stroke-width="24" stroke-linecap="round"/>
  <g transform="rotate(38 512 512)">
    <rect x="424" y="202" width="176" height="130" rx="36" fill="url(#accent)"/>
    <path d="M424 351h176l54 191c-20 101-86 181-142 248-56-67-122-147-142-248Z" fill="url(#ink)"/>
    <path d="M512 487v195" stroke="${paper}" stroke-width="20" stroke-linecap="round"/>
    <circle cx="512" cy="474" r="31" fill="${paper}"/>
  </g>`;
  const wrap = body => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n${body}\n</svg>\n`;
  outputs.set(`design/launcher_bg_${theme}.svg`, wrap(`${bg}<rect width="1024" height="1024" fill="url(#paper)"/>`));
  outputs.set(`design/launcher_fg_${theme}.svg`, wrap(mark));
  outputs.set(`design/app_mark_${theme}.svg`, wrap(`${bg}<rect x="40" y="40" width="944" height="944" rx="230" fill="url(#paper)"/>${mark}`));
}

// Source-asset overview for review. This is not a device screenshot.
const brandPanels = ['light', 'dark'].map((theme, i) => {
  const svg = outputs.get(`design/app_mark_${theme}.svg`)
    .replace(/id="([^"]+)"/g, (_, id) => `id="${theme}_${id}"`)
    .replace(/url\(#([^)]+)\)/g, (_, id) => `url(#${theme}_${id})`)
    .replace('width="1024" height="1024"', 'width="192" height="192"')
    .replace('<svg ', `<svg x="${48 + i * 224}" y="76" `);
  return `${svg}<text x="${144 + i * 224}" y="290" text-anchor="middle" font-size="14" fill="#575267">${theme}</text>`;
}).join('\n');
const tiles = Object.entries(icons).map(([name, body], i) => {
  const x = 48 + i % 8 * 116, y = 328 + Math.floor(i / 8) * 80;
  return `<g transform="translate(${x} ${y})"><rect width="108" height="68" rx="12" fill="#FFFFFF"/><svg x="42" y="10" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#575267" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${body.replaceAll('#000', '#575267')}</svg><text x="54" y="54" text-anchor="middle" font-size="11" fill="#716A80">${name}</text></g>`;
}).join('\n');
outputs.set('design/icon-preview.svg', `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#F8F7FB"/><g font-family="Arial,sans-serif"><text x="48" y="48" font-size="26" fill="#242033">FlowMind / Purple ink</text>${brandPanels}<rect x="520" y="92" width="452" height="164" rx="24" fill="#221E2D"/><text x="550" y="130" font-size="16" fill="#F8FAFC">Theme-aware vector assets</text><text x="550" y="166" font-size="14" fill="#BBA4FF">24-unit grid / 1.8-unit strokes</text><text x="550" y="202" font-size="14" fill="#B8B0C7">44vp native button targets</text><text x="550" y="232" font-size="12" fill="#A49AB6">Asset review, not a device screenshot</text>${tiles}</g></svg>\n`);

if (process.argv.includes('--check')) {
  const stale = [...outputs].filter(([name, value]) => !fs.existsSync(path.join(root, name)) || fs.readFileSync(path.join(root, name), 'utf8').replace(/\r\n/g, '\n') !== value);
  if (stale.length) { console.error('Icon masters need regeneration: ' + stale.map(([name]) => name).join(', ')); process.exitCode = 1; }
  else console.log(`${outputs.size} vector assets match the icon source.`);
} else {
  for (const [name, value] of outputs) { fs.mkdirSync(path.dirname(path.join(root, name)), { recursive: true }); fs.writeFileSync(path.join(root, name), value); }
  console.log(`Generated ${outputs.size} vector assets.`);
}
