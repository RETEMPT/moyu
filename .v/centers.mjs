import fs from 'node:fs';

const j = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const rows = [];
(function walk(n) {
  const a = n.attributes || {};
  const m = /\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(a.bounds || '');
  if (a.text && m) {
    const b = { x1: +m[1], y1: +m[2], x2: +m[3], y2: +m[4] };
    rows.push({
      t: a.text,
      x1: b.x1, y1: b.y1, x2: b.x2, y2: b.y2,
      cx: Math.round((b.x1 + b.x2) / 2),
      cy: Math.round((b.y1 + b.y2) / 2),
      c: a.clickable || 'false',
    });
  }
  (n.children || []).forEach(walk);
})(j);

const maxX = Number(process.argv[3] || 99999);
for (const r of rows) {
  if (r.x1 < maxX) {
    console.log(`"${r.t}"  @[${r.x1},${r.y1}][${r.x2},${r.y2}]  中心=${r.cx},${r.cy}  clickable=${r.c}`);
  }
}
