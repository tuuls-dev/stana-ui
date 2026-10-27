#!/bin/sh
set -eu
task_root=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [format|lint]" >&2
    exit 2
fi
python3 - "$task_root" "${1:-format}" <<'PY'
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
mode = sys.argv[2]
if mode not in ("format", "lint"):
    raise SystemExit("Expected format or lint")

# Include new Swift files, but never recurse into ignored SwiftPM build output.
listed = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.swift"],
    cwd=root,
)
paths = sorted({os.fsdecode(path) for path in listed.split(b"\0") if path})
paths = [path for path in paths if (root / path).is_file()]
if not paths:
    raise SystemExit("No repository Swift files found")

options = ["--in-place"] if mode == "format" else ["--strict"]
raise SystemExit(subprocess.run(
    ["swift", "format", mode, *options, "--parallel", "--configuration", str(root / ".swift-format"), *paths],
    cwd=root,
).returncode)
PY
