"""Export small upstream seams separately from the independent addon source."""
from pathlib import Path
import hashlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASE = '577e70b79528cc6c7da463ecd14c42ff8b9d9ed9'
GROUPS = {
    'host.patch': ['app/pubspec.yaml', 'app/pubspec.lock',
                   'app/lib/config/dependencies.dart',
                   'app/lib/ui/chat/chat_page.dart',
                   'app/lib/ui/chat/widgets/input_bar.dart',
                   'app/lib/ui/settings/settings_page.dart'],
    'test-portability.patch': ['app/test/data/voice/speech_service_test.dart'],
    'packaging.patch': ['.gitignore', 'app/android/app/build.gradle.kts',
                        'app/android/app/src/main/AndroidManifest.xml'],
}
destination = ROOT / 'pimic/.patches'
destination.mkdir(exist_ok=True)
for name, paths in GROUPS.items():
    patch = subprocess.check_output(['git', 'diff', '--binary', BASE, '--', *paths], cwd=ROOT)
    (destination / name).write_bytes(patch)
    print(name, hashlib.sha256(patch).hexdigest(), len(patch), 'bytes')
