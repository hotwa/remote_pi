"""Run explicit Android checks with the same Pixi JDK and SDK as Flutter."""
import subprocess
import sys

from flutter import ROOT, environment

android = ROOT.parent / 'app/android'
wrapper = android / 'gradlew'
if not wrapper.exists():
    raise SystemExit('Run the Flutter build once to generate the wrapper files.')
raise SystemExit(subprocess.call(
    ['bash', str(wrapper), '--console=plain', *sys.argv[1:]],
    cwd=android, env=environment(),
))
