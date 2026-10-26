#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import re
failures=[]
for p in Path('Sources').rglob('*.swift'):
    text=p.read_text()
    if re.search(r'^\s*(?:@\w+\s+)?import\s+(AppKit|SwiftUI|Cocoa)\b',text,re.M):
        failures.append(f'{p}: native UI import outside Objective-C bridge')
    if p.parts[1] == 'StanaCore' and re.search(r'^import Stana(?:Layout|Text|Scene|Graphics|Accessibility|Platform|PlatformMacOS)\b',text,re.M):
        failures.append(f'{p}: core depends on a projection or platform')
    if p.parts[1] != 'StanaPlatformMacOS' and re.search(r'^import CStanaMacOS\b',text,re.M):
        failures.append(f'{p}: native ABI import outside adapter')
    if '@_exported' in text or '@unchecked Sendable' in text:
        failures.append(f'{p}: unsupported export/concurrency escape hatch')
if 'unsafeFlags' in Path('Package.swift').read_text():
    failures.append('Package.swift: unsafe flags prevent normal dependency usage')
if failures: raise SystemExit('\n'.join(failures))
print('Stana dependency and native boundary checks passed')
PY
