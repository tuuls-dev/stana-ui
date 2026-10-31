#!/bin/sh
set -eu
task_root=$(cd "$(dirname "$0")/.." && pwd)
swift build --package-path "$task_root/Fixtures/API" -Xswiftc -warnings-as-errors
task_probe=$(mktemp -d "${TMPDIR:-/tmp}/stana-api.XXXXXX")
trap 'rm -rf "$task_probe"' EXIT HUP INT TERM
mkdir -p "$task_probe/Sources/Probe"
python3 - "$task_root" "$task_probe" <<'PY'
import json,sys
from pathlib import Path
root,probe=sys.argv[1:]
Path(probe,'Package.swift').write_text('''// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "Probe", platforms: [.macOS(.v26)],
    dependencies: [.package(path: %s)],
    targets: [.target(name: "Probe", dependencies: [.product(name: "Stana", package: "stana-ui")])])
''' % json.dumps(root))
# Generate large literal rejection fixtures without checking megabytes of repeated SVG into Git.
invalid = Path(probe, 'Invalid')
invalid.mkdir()
prefix, suffix = "<svg viewBox='0 0 1 1'>", "</svg>"
cases = {
    'SymbolByteLimit': prefix + '<!--' + 'x' * 1_048_576 + '-->' + suffix,
    'SymbolElementLimit': prefix + '<g/>' * 4096 + suffix,
    'SymbolDepthLimit': prefix + '<g>' * 64 + '</g>' * 64 + suffix,
    'SymbolCommandLimit': prefix + "<path d='M0 0" + 'L0 0' * 65536 + "'/>" + suffix,
    'SymbolTransformLimit': prefix + "<g transform='" + 'translate(0) ' * 65 + "'/>" + suffix,
    'SymbolNumericLimit': prefix + "<path d='M1000000001 0'/>" + suffix,
}
for name, svg in cases.items():
    (invalid / (name + '.swift')).write_text(
        'import Stana\n@MakeSTNSymbol struct Invalid { static let svg = ' + json.dumps(svg) + ' }\n'
    )
PY
for task_fixture in "$task_root"/Fixtures/API/Invalid/*.swift "$task_probe"/Invalid/*.swift; do
    cp "$task_fixture" "$task_probe/Sources/Probe/Invalid.swift"
    if swift build --package-path "$task_probe" >"$task_probe/build.log" 2>&1; then
        echo "Unexpected compilation success: $task_fixture" >&2; exit 1
    fi
    if ! grep -q 'Invalid.swift:.*error:' "$task_probe/build.log"; then
        cat "$task_probe/build.log" >&2
        echo "Fixture failed for a reason other than the expected source error" >&2; exit 1
    fi
done
echo 'Stana public API fixtures passed'
