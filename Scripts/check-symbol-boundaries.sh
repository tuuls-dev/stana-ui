#!/bin/sh
set -eu
task_root=$(cd "$(dirname "$0")/.." && pwd)
task_bin=$(swift build --package-path "$task_root/Examples/Calculator" --show-bin-path)
python3 - "$task_bin/CalculatorApp" <<'PY'
import subprocess
import sys

binary = sys.argv[1]
symbols = subprocess.check_output(['nm', '-j', binary], text=True)
linked = subprocess.check_output(['otool', '-L', binary], text=True)
for forbidden in ('StanaSymbolCompiler', 'StanaSymbolMacros', 'SwiftSyntax', 'SwiftParser', 'SwiftCompilerPlugin'):
    if forbidden in symbols or forbidden in linked:
        raise SystemExit('Host-only symbol implementation leaked into application linkage: ' + forbidden)
print('Symbol compiler and SwiftSyntax are absent from application linkage')
PY
