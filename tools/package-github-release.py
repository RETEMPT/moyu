"""Package an unsigned development release from one verified APP and clean commit.

This does not sign, install, publish, or grant app-market readiness.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, check=True, capture_output=True,
                          text=True).stdout.strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def passed_checks(log_path):
    log = (ROOT / log_path).read_text(encoding='utf-8')
    counts = re.search(r'\btests\s+(\d+)', log)
    passed = re.search(r'\bpass\s+(\d+)', log)
    if not counts or not passed or counts[1] != passed[1] or not re.search(r'\bfail\s+0\s*$', log, re.M):
        raise ValueError('Expected a completed passing test log')
    return int(counts[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True)
    parser.add_argument('--preflight', required=True)
    parser.add_argument('--ci-url', required=True)
    parser.add_argument('--workflow-log', required=True)
    parser.add_argument('--market-log', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'https://github\.com/RETEMPT/moyu/actions/runs/\d+', args.ci_url):
        raise ValueError('Expected the actual repository CI run URL')
    git('diff', '--quiet', 'HEAD', '--')
    commit = git('rev-parse', 'HEAD')
    preflight = json.loads((ROOT / args.preflight).read_text(encoding='utf-8'))
    spec = importlib.util.spec_from_file_location('app_inspection', ROOT / 'tools/inspect-app.py')
    inspector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inspector)
    app_path = (ROOT / args.app).resolve()
    if not app_path.name.endswith('-unsigned.app'):
        raise ValueError('This packager is only for unsigned development APPs')
    package = inspector.inspect(app_path)
    app = package['modules'][0]['app']
    version = app['versionName']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid release version')
    if preflight.get('sourceCommit') != commit or preflight.get('appSha256') != package['appSha256']:
        raise ValueError('Preflight must match the current commit and exact APP')
    if (preflight.get('versionName'), preflight.get('versionCode')) != (version, app['versionCode']):
        raise ValueError('Preflight version mismatch')
    checks = preflight['checks']
    required = [c for c in checks if c['scope'] in ('project', 'package')]
    if not required or any(c['status'] != 'PASS' for c in required):
        raise ValueError('Project and actual-package preflight must pass')
    for item in package['modules']:
        metadata = item['app']
        if (metadata['bundleName'], metadata['versionName'], metadata['versionCode'],
            metadata['buildMode'], metadata['debug']) != (
                'com.retempt.flowmind', version, app['versionCode'], 'release', False):
            raise ValueError('Module identity, version or release mode mismatch')
    folder_name = f'FlowMind-{version}'
    output = ROOT / 'release/reports' / f'github-v{version}'
    payload = output / folder_name
    payload.mkdir(parents=True, exist_ok=True)
    files = {f'FlowMind-{version}-unsigned.app': app_path.read_bytes()}
    with zipfile.ZipFile(app_path) as archive:
        for item in package['modules']:
            name = Path(item['name']).name
            if name != item['name'] or not name.endswith('.hap'):
                raise ValueError('Unexpected module filename')
            data = archive.read(name)
            if digest(data) != item['sha256']:
                raise ValueError('Module digest mismatch')
            files[name.removesuffix('.hap') + '-unsigned.hap'] = data
    instructions = f'''# 墨语 {version} 安装说明

本附件为未签名的 HarmonyOS release 开发构建，手机与 Pad 共用。
设备安装需要适用签名。请检出源码标签 v{version}，在 DevEco Studio
配置设备签名，再执行：

.\\build_hap.bat -StudioDir "<DevEco Studio 安装目录>" -BuildMode release -AppPackage -Clean

源码提交：{commit}
GitHub CI：{args.ci_url}
包名：{app['bundleName']}，内部版本：{app['versionCode']}
升级时保持签名一致；先导出学习资料，避免卸载导致资料丢失。

无需 API Key：笔记、PDF 批注和本地助手可离线使用。
本地助手是检索与摘录，不是端侧大模型；需要生成式问答时可授权自配 API。
设置中云服务、云 AI 和云备份标记未开放，本地文件备份可用。
星闪笔延迟、防误触、系统分享接收方和多设备传递尚待真机验收。
原 PDF 分享不包含应用内笔迹。正式应用市场签名及资料尚未补齐。
SHA256SUMS.txt 提供文件完整性校验，不等同于数字签名。
完整指引：https://github.com/RETEMPT/moyu/blob/v{version}/docs/USER_GUIDE.md
'''
    files['INSTALL.md'] = instructions.encode('utf-8')
    info = {
        'application': 'FlowMind（墨语）', 'versionName': version, 'versionCode': app['versionCode'],
        'bundleName': app['bundleName'], 'sourceCommit': commit, 'sourceTag': f'v{version}',
        'repository': 'https://github.com/RETEMPT/moyu',
        'packagedAt': datetime.now(timezone.utc).isoformat(), 'buildMode': 'release',
        'signing': 'unsigned development build; device signature required',
        'marketReady': False, 'ciUrl': args.ci_url,
        'compileSdkVersion': app['compileSdkVersion'], 'compileSdkType': app['compileSdkType'],
        'targetAPIVersion': app['targetAPIVersion'], 'minAPIVersion': app['minAPIVersion'],
        'devices': package['modules'][0]['module']['deviceTypes'], 'appSha256': package['appSha256'],
        'validation': {'workflowChecks': passed_checks(args.workflow_log),
                       'marketRuleChecks': passed_checks(args.market_log),
                       'projectAndPackageChecks': len(required),
                       'vectorAssetsChecked': len(list((ROOT / 'entry/src/main/resources/base/media').glob('ic_*.svg'))) + 7,
                       'physicalDeviceValidation': 'not performed',
                       'platformTests': 'service adapters mocked; SDK compilation separately performed'},
        'modules': [{'name': m['name'], 'sha256': m['sha256'],
                     'buildMode': m['app']['buildMode']} for m in package['modules']],
        'files': {name: {'bytes': len(data), 'sha256': digest(data)} for name, data in files.items()},
    }
    files['BUILD_INFO.json'] = (json.dumps(info, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    internal = ''.join(f'{digest(data)}  {name}\n' for name, data in files.items()).encode('utf-8')
    files['SHA256SUMS.txt'] = internal
    for name, data in files.items():
        (payload / name).write_bytes(data)
    zip_path = output / f'FlowMind-{version}-HarmonyOS-unsigned.zip'
    with zipfile.ZipFile(zip_path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in files.items():
            archive.writestr(f'{folder_name}/{name}', data)
    with zipfile.ZipFile(zip_path) as archive:
        if archive.testzip():
            raise ValueError('Release archive CRC failed')
        for name, data in files.items():
            if archive.read(f'{folder_name}/{name}') != data:
                raise ValueError('Release archive content mismatch')
    (output / 'BUILD_INFO.json').write_bytes(files['BUILD_INFO.json'])
    external = f'{digest(zip_path.read_bytes())}  {zip_path.name}\n'
    external += f"{digest(files['BUILD_INFO.json'])}  BUILD_INFO.json\n"
    external += ''.join(f'{digest(data)}  {folder_name}/{name}\n' for name, data in files.items())
    (output / 'SHA256SUMS.txt').write_text(external, encoding='utf-8', newline='\n')
    print(json.dumps({'output': str(output), 'sourceCommit': commit, 'version': version,
                      'appSha256': package['appSha256'], 'archiveBytes': zip_path.stat().st_size},
                     ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f'Release packaging failed: {error}', file=sys.stderr)
        raise SystemExit(1)
