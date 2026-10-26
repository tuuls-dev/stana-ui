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
let package = Package(name: "Probe", platforms: [.macOS(.v14)],
    dependencies: [.package(path: %s)],
    targets: [.target(name: "Probe", dependencies: [.product(name: "Stana", package: "stana-ui")])])
''' % json.dumps(root))
PY
for task_fixture in "$task_root"/Fixtures/API/Invalid/*.swift; do
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
