"""Prefetch the existing Gradle wrapper archive with official checksum validation."""
import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import urllib.request
from setup import CACHE, ROOT, download

VERSION = '8.14'
SHA256 = 'efe9a3d147d948d7528a9887fa35abcf24ca1a43ad06439996490f77569b02d1'
OFFICIAL = f'https://services.gradle.org/distributions/gradle-{VERSION}-all.zip'


def base36(value):
    alphabet = '0123456789abcdefghijklmnopqrstuvwxyz'
    result = ''
    while value:
        value, digit = divmod(value, 36)
        result = alphabet[digit] + result
    return result or '0'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', default=f'https://downloads.gradle.org/distributions/gradle-{VERSION}-all.zip', help='Optional download mirror; official pinned checksum still required')
    args = parser.parse_args()
    properties = ROOT.parent / 'app/android/gradle/wrapper/gradle-wrapper.properties'
    url = next(line.split('=', 1)[1].strip().replace('\\:', ':') for line in properties.read_text().splitlines() if line.startswith('distributionUrl='))
    if url != OFFICIAL:
        raise RuntimeError('Wrapper distribution differs from pinned 8.14-all; update tooling pin before prefetching')
    checksum = urllib.request.urlopen(OFFICIAL + '.sha256', timeout=30).read().decode().strip()
    if checksum != SHA256:
        raise RuntimeError('Official Gradle checksum differs from tooling pin')
    CACHE.mkdir(exist_ok=True)
    (CACHE / f'gradle-{VERSION}-all.zip.sha256').write_text(checksum + '\n')
    archive = download(args.source, f'gradle-{VERSION}-all.zip', SHA256, 'sha256')
    # Match Gradle PathAssembler's positive MD5 integer encoded in base 36.
    url_hash = base36(int.from_bytes(hashlib.md5(url.encode(), usedforsecurity=False).digest(), 'big'))
    gradle_user = Path(os.environ.get('GRADLE_USER_HOME', Path.home() / '.gradle'))
    target = gradle_user / 'wrapper/dists' / f'gradle-{VERSION}-all' / url_hash
    target.mkdir(parents=True, exist_ok=True)
    destination = target / archive.name
    # Java FileChannel locks use fcntl record locks, not BSD flock locks.
    with (target / (archive.name + '.lck')).open('a+b') as lock:
        try:
            fcntl.lockf(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError('Gradle wrapper is active; stop it before publishing the prefetched ZIP') from exc
        temporary = target / (archive.name + '.prefetch')
        shutil.copyfile(archive, temporary)
        temporary.replace(destination)
        fcntl.lockf(lock.fileno(), fcntl.LOCK_UN)
    print(f'Official SHA-256 verified; wrapper archive ready: {destination}', flush=True)

if __name__ == '__main__':
    main()
