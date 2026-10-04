"""Install pinned Flutter and its Android prerequisites from official metadata."""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.cache'
TOOLS = ROOT / '.tools'
VERSION = '3.44.4'
SHA256 = 'c853cda0312a162854c481fe6a1bc286d84fbb74bfab7037c39750061dc9b466'
FLUTTER_MANIFEST = 'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json'
ANDROID_MANIFEST = 'https://dl.google.com/android/repository/repository2-1.xml'


def digest(path: Path, algorithm: str) -> str:
    h = hashlib.new(algorithm)
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, filename: str, checksum: str, algorithm: str, size: int | None = None) -> Path:
    path = CACHE / filename
    if not path.exists() or digest(path, algorithm) != checksum:
        aria = shutil.which('aria2c')
        if not aria:
            raise RuntimeError('aria2c is required (provided by the Pixi environment)')
        subprocess.run([aria, '--continue=true', '--file-allocation=none', '-x', '16', '-s', '16',
                        '--min-split-size=1M', '--console-log-level=warn', '--summary-interval=30',
                        '--show-console-readout=false', '--check-integrity=true',
                        f'--checksum={algorithm.replace("sha", "sha-")}={checksum}',
                        '--dir', str(CACHE), '--out', filename, url], check=True)
    if (size is not None and path.stat().st_size != size) or digest(path, algorithm) != checksum:
        raise RuntimeError(f'Archive size/checksum mismatch: {filename}')
    return path


def metadata(url: str, filename: str) -> bytes:
    data = urllib.request.urlopen(url, timeout=60).read()
    (CACHE / filename).write_bytes(data)
    return data


def install_flutter() -> None:
    target = TOOLS / 'flutter'
    if (target / 'bin/flutter').exists():
        revision = subprocess.check_output(['git', '-C', str(target), 'rev-parse', 'HEAD'], text=True).strip()
        if revision != 'ad70ec4617166f1c38e5d2bfd388af71fda14f06':
            raise RuntimeError('Existing Flutter revision differs from pinned 3.44.4; preserve it and use another checkout')
        return
    release_data = json.loads(metadata(FLUTTER_MANIFEST, 'releases_linux.json'))
    release = next(r for r in release_data['releases'] if r['version'] == VERSION and r['channel'] == 'stable' and r.get('dart_sdk_arch') == 'x64')
    if release['sha256'] != SHA256:
        raise RuntimeError('Official Flutter manifest differs from pinned checksum')
    url = release_data['base_url'] + '/' + release['archive']
    size = int(urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=60).headers['Content-Length'])
    archive = download(url, Path(release['archive']).name, SHA256, 'sha256', size)
    stage = TOOLS / 'flutter-extract'
    stage.mkdir(exist_ok=True)
    with tarfile.open(archive, 'r:xz') as source:
        # Python's data filter rejects traversal, unsafe links and special devices.
        source.extractall(stage, filter='data')
    (stage / 'flutter').rename(target)
    stage.rmdir()
    print(f'Flutter ready: {target / "bin/flutter"}', flush=True)


def install_android(sdk: Path) -> None:
    tree = ET.fromstring(metadata(ANDROID_MANIFEST, 'repository2-1.xml'))
    licenses = {n.attrib['id']: n.text for n in tree.iter('license')}
    required = ['platforms;android-36', 'build-tools;36.0.0', 'ndk;28.2.13676358', 'platform-tools']
    if not (sdk / 'cmdline-tools/latest/bin/sdkmanager').exists():
        stable_tools = [p for p in tree.iter('remotePackage') if p.attrib['path'].startswith('cmdline-tools;') and p.find('channelRef').attrib.get('ref') == 'channel-0']
        required.append(max(stable_tools, key=revision).attrib['path'])
    selected = {}
    for p in tree.iter('remotePackage'):
        name = p.attrib['path']
        if name in required and (name not in selected or revision(p) > revision(selected[name])):
            selected[name] = p
    def install(name: str) -> None:
        target = sdk / ('cmdline-tools/latest' if name.startswith('cmdline-tools;') else name.replace(';', '/'))
        if (target / 'source.properties').exists():
            print(f'Android package already installed: {name}', flush=True)
            return
        package = selected[name]
        a = next(a for a in package.findall('archives/archive') if a.findtext('host-os', 'linux') == 'linux')
        filename, checksum = a.findtext('complete/url'), a.findtext('complete/checksum')
        path = download('https://dl.google.com/android/repository/' + filename, filename, checksum, 'sha1', int(a.findtext('complete/size')))
        stage = TOOLS / ('extract-' + name.replace(';', '-'))
        stage.mkdir(exist_ok=True)
        with zipfile.ZipFile(path) as source:
            roots = set()
            for item in source.infolist():
                dest = (stage / item.filename).resolve()
                if not dest.is_relative_to(stage.resolve()) :
                    raise RuntimeError('Unsafe Android archive path/link')
                roots.add(Path(item.filename).parts[0])
                if ((item.external_attr >> 16) & 0o170000) == 0o120000:
                    link = source.read(item).decode()
                    if Path(link).is_absolute() or not (dest.parent / link).resolve().is_relative_to(stage.resolve()):
                        raise RuntimeError('Unsafe Android archive symlink')
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    if dest.is_symlink():
                        dest.unlink()
                    dest.symlink_to(link)
                    continue
                source.extract(item, stage)
                mode = (item.external_attr >> 16) & 0o777
                if mode:
                    dest.chmod(mode)
        if len(roots) != 1:
            raise RuntimeError('Unexpected Android archive layout')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(stage / roots.pop()), target)
        stage.rmdir()
        ref = package.find('uses-license')
        if ref is not None:
            license_file = sdk / 'licenses' / ref.attrib['ref']
            license_file.parent.mkdir(exist_ok=True)
            accepted = hashlib.sha1(licenses[ref.attrib['ref']].strip().encode()).hexdigest()
            existing = license_file.read_text() if license_file.exists() else ''
            if accepted not in existing.splitlines():
                license_file.write_text(existing.rstrip() + '\n' + accepted + '\n')
        print(f'Android package ready: {name}', flush=True)
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(install, required))


def revision(package):
    return tuple(int(package.find('revision').findtext(k, '0')) for k in ('major', 'minor', 'micro'))


def sdk_path() -> Path:
    saved = TOOLS / 'android-sdk-path'
    return Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or (saved.read_text().strip() if saved.exists() else TOOLS / 'android-sdk')).resolve()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--android-sdk', type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--android-only', action='store_true')
    mode.add_argument('--flutter-only', action='store_true')
    args = parser.parse_args()
    CACHE.mkdir(exist_ok=True)
    TOOLS.mkdir(exist_ok=True)
    sdk = (args.android_sdk or sdk_path()).resolve()
    (TOOLS / 'android-sdk-path').write_text(str(sdk) + '\n')
    if args.flutter_only:
        install_flutter()
    elif args.android_only:
        install_android(sdk)
    else:
        with ThreadPoolExecutor(max_workers=2) as pool:
            f = pool.submit(install_flutter)
            a = pool.submit(install_android, sdk)
            f.result()
            a.result()

if __name__ == '__main__':
    main()
