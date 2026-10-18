"""Package an audited unsigned local release for a separate signing/publishing owner."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode('utf-8').strip()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def passed(log):
    text = (ROOT / log).read_text(encoding='utf-8-sig')
    count = re.search(r'\btests\s+(\d+)', text)
    successful = re.search(r'\bpass\s+(\d+)', text)
    if not count or not successful or count[1] != successful[1] or not re.search(r'\bfail\s+0\s*$', text, re.M):
        raise ValueError(f'Incomplete or failing test report: {log}')
    return int(count[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True)
    parser.add_argument('--preflight', required=True)
    parser.add_argument('--disassembler', required=True)
    args = parser.parse_args()
    if git('status', '--porcelain'):
        raise ValueError('Commit the reviewed source before packaging')
    commit = git('rev-parse', 'HEAD')
    spec = importlib.util.spec_from_file_location('inspector', ROOT / 'tools/inspect-app.py')
    inspector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inspector)
    app_path = (ROOT / args.app).resolve()
    report = inspector.inspect(app_path)
    preflight = json.loads((ROOT / args.preflight).read_text(encoding='utf-8-sig'))
    if preflight['sourceCommit'] != commit or preflight['appSha256'] != report['appSha256']:
        raise ValueError('Preflight does not match this source and APP')
    required = [row for row in preflight['checks'] if row['scope'] in ('project', 'package')]
    if not required or any(row['status'] != 'PASS' for row in required):
        raise ValueError('Project/package checks must all pass')
    version = report['modules'][0]['app']['versionName']
    version_code = report['modules'][0]['app']['versionCode']
    output = ROOT / 'release/reports' / f'local-v{version}'
    output.mkdir(parents=True, exist_ok=True)
    files = {f'FlowMind-{version}-unsigned.app': app_path.read_bytes()}
    audit = []
    with zipfile.ZipFile(app_path) as app:
        for module in report['modules']:
            metadata = module['app']
            if (metadata['versionName'], metadata['versionCode'], metadata['buildMode'], metadata['debug']) != (version, version_code, 'release', False):
                raise ValueError('Unexpected module metadata')
            if sorted(module['module']['deviceTypes']) != ['phone', 'tablet'] or module['debugResources']:
                raise ValueError('Wrong devices or debug resources included')
            if any(p['name'] == 'ohos.permission.INTERNET' for p in module['module'].get('requestPermissions', [])):
                raise ValueError('Unexpected internet permission')
            payload = app.read(module['name'])
            if digest(payload) != module['sha256']:
                raise ValueError('HAP digest mismatch')
            files[f'FlowMind-{version}-unsigned.hap'] = payload
            with zipfile.ZipFile(io.BytesIO(payload)) as hap, tempfile.TemporaryDirectory(dir=output) as folder:
                retired = [name for name in hap.namelist() if re.search(r'(?:archive/|ic_(?:sparkle|history|send|stop)\.svg|ModelSetup|deepseek)', name, re.I)]
                if retired:
                    raise ValueError(f'Retired assets included: {retired}')
                abc_name = next(name for name in hap.namelist() if name.endswith('modules.abc'))
                abc = Path(folder, 'modules.abc')
                listing = Path(folder, 'modules.pa')
                abc.write_bytes(hap.read(abc_name))
                subprocess.run([args.disassembler, str(abc), str(listing)], check=True, capture_output=True, timeout=120)
                # Panda disassembly can encode emoji as CESU-8 surrogate pairs.
                text = listing.read_text(encoding='utf-8', errors='surrogatepass').replace('SystemCapability.AI.OCR.TextRecognition', '')
                forbidden = re.search(r'(?:services/ai/|views/ai/|AiWorkspace|AssistantText|HuaweiAiSplitPanel|ModelConfigService|ModelProvider|AiModelCatalog|MarkerImportPolicy|aiSummary|aiTags|REMOTE_AI_ENABLED|墨客|伴读|大模型|自配 API|\bAI\b)', text)
                if forbidden:
                    raise ValueError(f'Retired compiled feature: {forbidden[0]}')
                audit.append({'module': module['name'], 'compiledFeatureAudit': 'PASS', 'retiredResourceAudit': 'PASS',
                              'abcSha256': digest(abc.read_bytes()), 'disassemblySha256': digest(listing.read_bytes())})
    validation = {
        'workflows': passed('tmp/local-workflows.log'), 'pdf': passed('tmp/local-pdf.log'),
        'compiledUi': passed('tmp/local-compiled-ui.log'), 'marketRules': passed('tmp/local-market.log'),
        'projectAndPackageChecks': len(required), 'compiledModules': audit,
        'physicalDevices': 'not tested; signing and device verification handled by publishing owner',
    }
    instructions = f'''# 墨语 {version} 签名与发布交接

手机与平板共用未签名 release 包。包名 com.retempt.flowmind，内部版本 {version_code}。
源码提交：{commit}。最低 HarmonyOS 6.1.1 / API 24，目标 API 26。

本地整理、笔记、PDF 批注、稿纸、图谱、待办、自测和文件备份保留。
图谱空主题与保存反馈已修复；首次声明交由平台隐私托管配置提供。

发布负责人须配置真实发布主体、客服、隐私网址和市场发布签名。
修改 release/app-market.json 后执行 node tools/generate-market-materials.mjs，
配置与 AGC 一致的签名，重新构建并检查实际签名后的 APP。
本附件不可直接当作已签名安装包或审核通过证明。

手机和平板真机需检查首次托管隐私声明、图谱创建重启、文字整理、
PDF/笔迹、升级与备份、小屏键盘、大字体、横竖屏与分屏。
升级保持相同签名，卸载前先导出资料。

自动检查共 {sum(validation[k] for k in ('workflows','pdf','compiledUi','marketRules'))} 项通过，
另有项目、包结构和编译内容核查。真实设备验收尚未执行。
完整操作路径见 REVIEW_CHECKLIST.md，SHA256SUMS.txt 用于完整性校验。
'''
    files['INSTALL.md'] = instructions.encode('utf-8')
    files['REVIEW_CHECKLIST.md'] = (ROOT / 'release/STORE_LISTING.md').read_bytes()
    files['PRIVACY.md'] = (ROOT / 'docs/PRIVACY.md').read_bytes()
    files['PREFLIGHT.json'] = (ROOT / args.preflight).read_bytes()
    info = {'versionName': version, 'versionCode': version_code, 'sourceCommit': commit,
            'appSha256': report['appSha256'], 'signing': 'unsigned', 'marketReady': False,
            'validation': validation, 'files': {name: {'bytes': len(data), 'sha256': digest(data)} for name, data in files.items()}}
    files['BUILD_INFO.json'] = (json.dumps(info, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    files['SHA256SUMS.txt'] = ''.join(f'{digest(data)}  {name}\n' for name, data in files.items()).encode('utf-8')
    payload_folder = output / f'FlowMind-{version}'
    payload_folder.mkdir(exist_ok=True)
    for name, data in files.items():
        (payload_folder / name).write_bytes(data)
    release_zip = output / f'FlowMind-{version}-HarmonyOS-unsigned.zip'
    with zipfile.ZipFile(release_zip, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            archive.writestr(f'FlowMind-{version}/{name}', data)
    tracked = git('ls-files').splitlines()
    source_zip = output / f'FlowMind-{version}-source.zip'
    source_prefixes = ('AppScope/', 'entry/', 'hvigor/', 'tools/', 'design/', '.github/', 'docs/', 'archive/ai/')
    source_files = {'README.md', 'PRODUCT_SCOPE.md', 'TECH_STACK.md', 'PROJECT_MEMORY.md', 'SECURITY.md',
                    'LICENSE', 'CONTRIBUTING.md', '.gitignore', '.gitattributes',
                    'build_hap.bat', 'deploy_hap.bat', 'build-profile.json5', 'hvigorfile.ts',
                    'oh-package.json5', 'oh-package-lock.json5', 'code-linter.json5',
                    'docs/USER_GUIDE.md', 'docs/PRIVACY.md',
                    'release/README.md', 'release/STORE_LISTING.md', 'release/DEPENDENCIES.md',
                    'release/app-market.json', 'release/privacy-sections.json', 'release/review-evidence.template.json',
                    'release/device-evidence.template.json', 'release/site/privacy.html'}
    with zipfile.ZipFile(source_zip, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in tracked:
            if name.startswith(source_prefixes) or name in source_files:
                if name == 'local.properties' or re.search(r'\.(p12|pfx|pem|key|p7b|cer)$', name, re.I):
                    raise ValueError('Private signing files must never be packaged')
                archive.write(ROOT / name, f'FlowMind-{version}-source/{name}')
    archive_zip = output / f'FlowMind-{version}-ai-history.zip'
    with zipfile.ZipFile(archive_zip, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in tracked:
            if name.startswith('archive/ai/'):
                archive.write(ROOT / name, name)
    for file in [release_zip, source_zip, archive_zip]:
        with zipfile.ZipFile(file) as archive:
            if archive.testzip():
                raise ValueError('Archive CRC verification failed')
    (output / 'SHA256SUMS.txt').write_text(''.join(f'{digest(file.read_bytes())}  {file.name}\n' for file in [release_zip, source_zip, archive_zip]), encoding='utf-8')
    print(json.dumps({'output': str(output), 'version': version, 'sourceCommit': commit,
                      'appSha256': report['appSha256'], 'checks': validation}, ensure_ascii=False))


if __name__ == '__main__':
    main()
