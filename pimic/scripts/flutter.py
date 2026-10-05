"""Run the app with the pinned Flutter and Pixi JDK, using the setup SDK path."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
from setup import ROOT, TOOLS, sdk_path


def environment():
    env = os.environ.copy()
    java = shutil.which('java')
    if not java:
        raise RuntimeError('Run through Pixi to obtain JDK 17')
    env['JAVA_HOME'] = str(Path(java).resolve().parent.parent)
    env['ANDROID_HOME'] = env['ANDROID_SDK_ROOT'] = str(sdk_path())
    env['PATH'] = str(TOOLS / 'flutter/bin') + os.pathsep + env['PATH']
    return env


def run(arguments, cwd=None):
    executable = TOOLS / 'flutter/bin/flutter'
    if not executable.exists():
        raise RuntimeError('Run pixi run setup first')
    return subprocess.call([str(executable), '--no-version-check', *arguments], cwd=cwd or ROOT.parent / 'app', env=environment())

if __name__ == '__main__':
    sys.exit(run(sys.argv[1:]))
