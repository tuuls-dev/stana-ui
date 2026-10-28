#!/bin/sh
set -eu
task_root=$(cd "$(dirname "$0")/.." && pwd)
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [format|lint]" >&2
    exit 2
fi
if ! command -v clang-format >/dev/null 2>&1; then
    echo "clang-format is required on PATH. Install it with: brew install clang-format" >&2
    exit 1
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

# Include new Objective-C and C headers, but never recurse into ignored build output.
listed = subprocess.check_output(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.h", "*.m", "*.mm"],
    cwd=root,
)
paths = sorted({os.fsdecode(path) for path in listed.split(b"\0") if path})
paths = [path for path in paths if (root / path).is_file()]
if not paths:
    raise SystemExit("No repository Objective-C files found")

options = ["-i"] if mode == "format" else ["--dry-run", "--Werror"]
raise SystemExit(subprocess.run(
    ["clang-format", *options, "--style=file", *paths],
    cwd=root,
).returncode)
PY
