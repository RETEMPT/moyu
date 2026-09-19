import fs from 'node:fs';

const file = process.argv[2];
const j = JSON.parse(fs.readFileSync(file, 'utf8'));
const rows = [];
(function walk(n) {
  const a = n.attributes || {};
  if (a.type === 'TextInput' || a.text) {
    rows.push({ ty: a.type, t: a.text || '', hint: a.hint || '', b: a.bounds || '', c: a.clickable || 'false' });
  }
  (n.children || []).forEach(walk);
})(j);

const filter = process.argv[3];
for (const r of rows) {
  if (filter && !new RegExp(filter).test(r.t) && !new RegExp(filter).test(r.hint)) continue;
  console.log(`${r.ty} | "${r.t}" hint="${r.hint}" @${r.b} clickable=${r.c}`);
}
