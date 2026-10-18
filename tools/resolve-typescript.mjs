import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

// Reuse the installed DevEco compiler; validation needs no separate npm install.
export function resolveTypeScript() {
  const flag = process.argv.indexOf('--typescript');
  if (flag >= 0) {
    if (!process.argv[flag + 1]) throw new Error('--typescript requires a compiler path');
    return require(path.resolve(process.argv[flag + 1]));
  }
  const candidates = [process.env.DSH_TYPESCRIPT, 'typescript'].filter(Boolean);
  const studioRoots = [process.env.DEVECO_STUDIO_HOME,
    process.env['DevEco Studio'] && path.resolve(process.env['DevEco Studio'], '..')].filter(Boolean);
  for (const studio of studioRoots) {
    for (const relative of ['plugins/openharmony/ace-server/node_modules/typescript',
      'plugins/codelinter/node_modules/typescript', 'tools/hvigor/hvigor/node_modules/typescript']) {
      candidates.push(path.join(studio, relative));
    }
  }
  for (const candidate of candidates) {
    try { const ts = require(candidate); if (typeof ts.transpileModule === 'function') return ts; }
    catch { /* Continue with the next installed runtime. */ }
  }
  throw new Error('TypeScript unavailable: set DEVECO_STUDIO_HOME or pass --typescript <typescript.js>.');
}
