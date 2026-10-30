import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const bundledPython = path.join(os.homedir(), '.cache', 'codex-runtimes', 'codex-primary-runtime', 'dependencies', 'python', 'python.exe');
const python = process.env.PYTHON || (process.platform === 'win32' && fs.existsSync(bundledPython) ? bundledPython : process.platform === 'win32' ? 'python' : 'python3');
const run = spawnSync(python, ['-X', 'utf8', '-m', 'unittest', 'discover', '-s', 'cloud/ai/tests', '-v'], {
  cwd: root, encoding: 'utf8', windowsHide: true, maxBuffer: 2 * 1024 * 1024
});
const output = (run.stdout || '') + (run.stderr || '');
process.stdout.write(output);
if (run.error) console.error(`Python 3.10+ with sqlite3 is required. Set PYTHON: ${run.error.message}`);
const count = Number(output.match(/Ran (\d+) tests?/)?.[1] || 0);
console.log(`# tests ${count}`);
process.exitCode = run.status === 0 && !run.error && count > 0 ? 0 : 1;
