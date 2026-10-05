"""Prepare an optional verified Maven repository for two Flutter debug modules."""
from __future__ import annotations
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET
from setup import CACHE, ROOT, TOOLS, digest

MODULES = ('arm64_v8a_debug', 'flutter_embedding_debug')
OFFICIAL = 'https://storage.googleapis.com/download.flutter.io'
REPOSITORY = CACHE / 'engine-maven'
INIT_SCRIPT = CACHE / 'engine-maven.init.gradle'


def public_bytes(url):
    return subprocess.run(['curl', '-fsSL', '--retry', '3', '--retry-all-errors',
                           '--max-time', '60', url], check=True, capture_output=True).stdout


def verify(path, metadata):
    md5 = base64.b64decode(metadata['md5Hash']).hex()
    if path.stat().st_size != int(metadata['size']) or digest(path, 'md5') != md5:
        raise RuntimeError(f'Official Google storage size/MD5 mismatch: {path.name}')
    return md5


def prepare(download_base=OFFICIAL):
    engine = (TOOLS / 'flutter/bin/cache/engine.stamp').read_text().strip()
    if len(engine) != 40 or any(c not in '0123456789abcdef' for c in engine):
        raise RuntimeError('Invalid Flutter engine revision')
    version = '1.0.0-' + engine
    CACHE.mkdir(exist_ok=True)
    evidence = []
    for module in MODULES:
        directory = REPOSITORY / 'io/flutter' / module / version
        directory.mkdir(parents=True, exist_ok=True)
        for extension in ('pom', 'jar'):
            filename = f'{module}-{version}.{extension}'
            object_name = f'io/flutter/{module}/{version}/{filename}'
            metadata_url = 'https://storage.googleapis.com/storage/v1/b/download.flutter.io/o/' + urllib.parse.quote(object_name, safe='')
            metadata = json.loads(public_bytes(metadata_url))
            cached = CACHE / filename
            md5 = base64.b64decode(metadata['md5Hash']).hex()
            if not cached.exists() or cached.stat().st_size != int(metadata['size']) or digest(cached, 'md5') != md5:
                if extension == 'pom':
                    cached.write_bytes(public_bytes(OFFICIAL + '/' + object_name + '?generation=' + metadata['generation']))
                else:
                    subprocess.run(['aria2c', '--continue=true', '--file-allocation=none', '-x', '16', '-s', '16',
                                    '--min-split-size=1M', '--console-log-level=warn', '--summary-interval=30',
                                    '--show-console-readout=false', '--check-integrity=true', f'--checksum=md5={md5}',
                                    '--dir', str(CACHE), '--out', filename, download_base.rstrip('/') + '/' + object_name], check=True)
            verify(cached, metadata)
            if extension == 'pom':
                pom = ET.parse(cached).getroot()
                ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
                if (pom.findtext('m:groupId', namespaces=ns), pom.findtext('m:artifactId', namespaces=ns), pom.findtext('m:version', namespaces=ns)) != ('io.flutter', module, version):
                    raise RuntimeError('Official POM coordinates differ from requested engine')
            destination = directory / filename
            if destination.exists():
                verify(destination, metadata)
            else:
                # Hardlink the verified immutable archive; refuse any concurrent replacement.
                try:
                    os.link(cached, destination)
                except FileExistsError:
                    verify(destination, metadata)
            evidence.append({'module': module, 'file': filename, 'size': int(metadata['size']), 'md5': md5,
                             'sha256': digest(cached, 'sha256'), 'generation': metadata['generation'], 'metadata_url': metadata_url})
            print(f'Official GCS size/MD5 verified: {filename}', flush=True)
    repo_uri = REPOSITORY.as_uri()
    android_path = str(ROOT.parent / 'app/android').replace("\\", "\\\\").replace("'", "\\'")
    INIT_SCRIPT.write_text("""// Optional task-scoped repo: exactly two verified io.flutter debug modules.
gradle.beforeProject { project ->
    if (project.rootProject.projectDir != new File('%s')) return
    project.repositories.exclusiveContent {
        forRepository {
            project.repositories.maven {
                name = 'pimicVerifiedFlutterEngine'
                url = project.uri('%s')
                metadataSources { mavenPom(); artifact() }
            }
        }
        filter {
            includeModule('io.flutter', 'arm64_v8a_debug')
            includeModule('io.flutter', 'flutter_embedding_debug')
        }
    }
}
""" % (android_path, repo_uri))
    (REPOSITORY / 'verification.json').write_text(json.dumps({'engine': engine, 'files': evidence}, indent=2) + '\n')
    print(f'Optional engine init script ready: {INIT_SCRIPT}', flush=True)
    return INIT_SCRIPT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--download-base', default=OFFICIAL, help='Optional public mirror; official GCS verification is always required')
    args = parser.parse_args()
    prepare(args.download_base)

if __name__ == '__main__':
    main()
