"""Prefetch plugin-declared Kotlin compiler JARs into Gradle's immutable cache."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import urllib.request
from setup import CACHE, ROOT, digest, download

ARTIFACT = 'kotlin-compiler-embeddable'
REPOSITORY = 'https://repo.maven.apache.org/maven2'
VERSION = r'([0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9]+)*)'


def declared_versions():
    metadata = ROOT.parent / 'app/.flutter-plugins-dependencies'
    plugins = json.loads(metadata.read_text())['plugins']['android']
    directories = [ROOT.parent / 'app/android'] + [Path(p['path']) / 'android' for p in plugins]
    versions = set()
    patterns = [
        rf'''(?:kotlin_version|kotlinVersion)\s*=\s*['"]{VERSION}['"]''',
        rf'''org\.jetbrains\.kotlin(?:\.android|\.jvm)?['"]\)?\s+version\s+['"]{VERSION}['"]''',
        rf'''org\.jetbrains\.kotlin:kotlin-gradle-plugin:{VERSION}['"]''',
    ]
    for directory in directories:
        for name in ('build.gradle', 'build.gradle.kts', 'settings.gradle', 'settings.gradle.kts'):
            path = directory / name
            if path.exists():
                text = path.read_text()
                for pattern in patterns:
                    versions.update(re.findall(pattern, text))
    return sorted(versions)


def prefetch(version):
    filename = f'{ARTIFACT}-{version}.jar'
    url = f'{REPOSITORY}/org/jetbrains/kotlin/{ARTIFACT}/{version}/{filename}'
    checksum = urllib.request.urlopen(url + '.sha1', timeout=30).read().decode().strip().split()[0]
    if not re.fullmatch(r'[a-fA-F0-9]{40}', checksum):
        raise RuntimeError('Invalid Maven Central SHA-1 response')
    checksum = checksum.lower()
    gradle_home = Path(os.environ.get('GRADLE_USER_HOME', Path.home() / '.gradle'))
    directory = gradle_home / 'caches/modules-2/files-2.1/org.jetbrains.kotlin' / ARTIFACT / version / checksum
    destination = directory / filename
    if destination.exists():
        if digest(destination, 'sha1') != checksum:
            raise RuntimeError(f'Existing immutable cache entry differs from official SHA-1: {version}')
        print(f'Already cached: {ARTIFACT} {version}', flush=True)
        return
    (CACHE / (filename + '.sha1')).write_text(checksum + '\n')
    archive = download(url, filename, checksum, 'sha1')
    directory.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(prefix='.prefetch-', dir=directory)
    os.close(fd)
    temporary = Path(temporary_name)
    try:
        shutil.copyfile(archive, temporary)
        # Link publishes atomically and refuses to overwrite a concurrent Gradle entry.
        try:
            os.link(temporary, destination)
        except FileExistsError:
            if digest(destination, 'sha1') != checksum:
                raise RuntimeError(f'Concurrent cache entry differs from official SHA-1: {version}')
    finally:
        temporary.unlink()
    print(f'Official SHA-1 verified; compiler cached: {version}', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', action='append', help='Explicit Kotlin version; default discovers app/plugin declarations')
    args = parser.parse_args()
    versions = args.version or declared_versions()
    if any(not re.fullmatch(VERSION, version) for version in versions):
        raise RuntimeError('Invalid Kotlin version')
    print('Kotlin versions: ' + ', '.join(versions), flush=True)
    CACHE.mkdir(exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(prefetch, versions))

if __name__ == '__main__':
    main()
