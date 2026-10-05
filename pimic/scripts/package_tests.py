"""Test local Dart/Flutter packages that contain tests, without changing pubspec."""
from pathlib import Path
import sys
from flutter import run, ROOT

for package in sorted((ROOT.parent / 'app/packages').glob('*')):
    if (package / 'pubspec.yaml').exists() and (package / 'test').is_dir():
        print(f'Testing {package.name}', flush=True)
        result = run(['pub', 'get'], package)
        if result == 0:
            result = run(['test'], package)
        if result:
            sys.exit(result)
