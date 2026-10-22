"""Package release APP/HAP with checksums in a ZIP; keep audit evidence local."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', default='build/outputs/default/apps-default-unsigned.app')
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('inspect_app', ROOT / 'tools/inspect-app.py')
    inspector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inspector)
    app = (ROOT / args.app).resolve()
    report = inspector.inspect(app)
    if len(report['modules']) != 1:
        raise ValueError('Expected exactly one production entry module')
    module = report['modules'][0]
    metadata = module['app']
    version = metadata['versionName']
    expected = json.loads(subprocess.check_output([
        'node', '--input-type=module', '-e',
        "import fs from 'node:fs'; import { parseJsonc } from './tools/app-market-policy.mjs'; "
        "console.log(JSON.stringify(parseJsonc(fs.readFileSync('AppScope/app.json5', 'utf8')).app));"
    ], cwd=ROOT, text=True))
    for field in ('bundleName', 'versionName', 'versionCode'):
        if metadata[field] != expected[field]:
            raise ValueError(f'Release {field} does not match AppScope/app.json5')
    if metadata['buildMode'] != 'release' or metadata['debug'] is not False or module['debugResources']:
        raise ValueError('Debug build or sample resources found')
    if sorted(module['module']['deviceTypes']) != ['phone', 'tablet']:
        raise ValueError('Both phone and tablet must be supported')
    if any(row['name'] == 'ohos.permission.INTERNET' for row in module['module'].get('requestPermissions', [])):
        raise ValueError('Unexpected network permission')
    output = ROOT / 'release/reports' / ('github-v' + version)
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(app) as archive:
        hap_bytes = archive.read(module['name'])
    import io
    with zipfile.ZipFile(io.BytesIO(hap_bytes)) as hap:
        forbidden = [name for name in hap.namelist() if re.search(
            r'(?:^|/)(?:docs|design|archive|fixtures|tests?|ohosTest|debug-pdf-preview)(?:/|$)|'
            r'(?:example-course\.pdf|example-snapshot\.pdf|AGENTS\.md|PROJECT_MEMORY\.md|TECH_STACK\.md)$', name, re.I)]
        if forbidden:
            raise ValueError('Non-production payload found: ' + ', '.join(forbidden))
    files = {f'Moyu-{version}-HarmonyOS-unsigned.app': app.read_bytes(),
             f'Moyu-{version}-HarmonyOS-unsigned.hap': hap_bytes}
    checksums = ''.join(f'{sha256(data)}  {name}\n' for name, data in files.items())
    zip_name = f'Moyu-{version}-HarmonyOS-unsigned.zip'
    zip_path = output / zip_name
    with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            archive.writestr(name, data)
        archive.writestr('SHA256SUMS.txt', checksums)
    files[zip_name] = zip_path.read_bytes()
    (output / 'SHA256SUMS.txt').write_text(f'{sha256(files[zip_name])}  {zip_name}\n', encoding='utf-8')
    report['sourceCommit'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    report['nonProductionPayload'] = forbidden
    report['signature'] = 'unsigned'
    report['files'] = {name: {'bytes': len(data), 'sha256': sha256(data)} for name, data in files.items()}
    (ROOT / f'tmp/release-{version}-audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'output': str(output), 'version': version, 'files': [zip_name, 'SHA256SUMS.txt'],
                      'testResources': [], 'developerDocuments': [], 'signature': 'unsigned'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
