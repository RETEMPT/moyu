"""Read APP/HAP metadata and optionally verify every HAP with the installed SDK signer.
Never accepts signing passwords, writes only temporary public verification outputs.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile


def checked_zip(data):
    archive = zipfile.ZipFile(data)
    entries = archive.infolist()
    if len(entries) > 10000 or sum(e.file_size for e in entries) > 256 * 1024 * 1024:
        archive.close()
        raise ValueError('Package exceeds inspection limits')
    if len({e.filename for e in entries}) != len(entries) or archive.testzip():
        archive.close()
        raise ValueError('Package has duplicate entries or a failed CRC')
    return archive


def inspect(app_path, java=None, signer=None):
    payload = Path(app_path).read_bytes()
    if len(payload) > 256 * 1024 * 1024:
        raise ValueError('Package exceeds inspection limits')
    result = {'appSha256': hashlib.sha256(payload).hexdigest(), 'modules': []}
    with checked_zip(io.BytesIO(payload)) as app:
        result['pack'] = json.loads(app.read('pack.info'))
        for index, name in enumerate(app.namelist()):
            if not name.endswith(('.hap', '.hsp')):
                continue
            data = app.read(name)
            with checked_zip(io.BytesIO(data)) as hap:
                metadata = json.loads(hap.read('module.json'))
                item = {'name': name, 'sha256': hashlib.sha256(data).hexdigest(),
                        'app': metadata['app'], 'module': metadata['module'],
                        'nativeLibraries': [p for p in hap.namelist() if p.startswith('libs/') and p.endswith('.so')],
                        'backup': json.loads(hap.read('resources/base/profile/backup_config.json')),
                        'signatureVerified': False}
            if java and signer:
                with tempfile.TemporaryDirectory(prefix='flowmind-verify-') as folder:
                    hap_path = Path(folder, f'module-{index}.hap')
                    cert_path = Path(folder, 'chain.cer')
                    profile_path = Path(folder, 'profile.p7b')
                    hap_path.write_bytes(data)
                    verification = subprocess.run([java, '-jar', signer, 'verify-app', '-inFile', str(hap_path),
                        '-outCertChain', str(cert_path), '-outProfile', str(profile_path)],
                        capture_output=True, timeout=90)
                    item['signatureVerified'] = verification.returncode == 0 and cert_path.exists() and profile_path.exists()
                    if item['signatureVerified']:
                        item['certificateChainSha256'] = hashlib.sha256(cert_path.read_bytes()).hexdigest()
                        item['profileSha256'] = hashlib.sha256(profile_path.read_bytes()).hexdigest()
                    else:
                        item['signatureError'] = 'SDK signature verification failed (unsigned or invalid); not market ready'
            result['modules'].append(item)
    if not result['modules']:
        raise ValueError('APP has no HAP or HSP')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('app')
    parser.add_argument('--java')
    parser.add_argument('--signer')
    args = parser.parse_args()
    try:
        print(json.dumps(inspect(args.app, args.java, args.signer), ensure_ascii=False))
    except Exception:
        print(json.dumps({'error': 'APP inspection failed; check package structure and installed SDK tools'}))
        raise SystemExit(1)
