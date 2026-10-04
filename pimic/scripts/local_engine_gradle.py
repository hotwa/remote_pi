"""Run optional Gradle tasks using only the verified local Flutter ARM64 modules."""
import json
import subprocess
import sys
from setup import ROOT, TOOLS, digest
from prepare_engine_repo import INIT_SCRIPT, REPOSITORY

if not INIT_SCRIPT.exists():
    raise SystemExit('Run pixi run prepare-engine-repo before this optional task.')
evidence = json.loads((REPOSITORY / 'verification.json').read_text())
if evidence['engine'] != (TOOLS / 'flutter/bin/cache/engine.stamp').read_text().strip():
    raise SystemExit('Engine revision changed; run prepare-engine-repo again.')
for item in evidence['files']:
    path = REPOSITORY / 'io/flutter' / item['module'] / ('1.0.0-' + evidence['engine']) / item['file']
    if path.stat().st_size != item['size'] or digest(path, 'md5') != item['md5']:
        raise SystemExit('Verified engine repository changed; run prepare-engine-repo again.')
raise SystemExit(subprocess.call([
    sys.executable, str(ROOT / 'scripts/gradle.py'),
    '--init-script', str(INIT_SCRIPT), '-Ptarget-platform=android-arm64',
    '-Ptarget=lib/main.dart', *sys.argv[1:],
]))
