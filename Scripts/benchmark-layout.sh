#!/bin/sh
set -eu
task_root=$(cd "$(dirname "$0")/.." && pwd)
swift build --package-path "$task_root" -c release --product LayoutBenchmarks -Xswiftc -warnings-as-errors >&2
task_bin=$(swift build --package-path "$task_root" -c release --show-bin-path)
STANA_BENCH_SWIFT_VERSION=$(swift --version)
STANA_BENCH_REVISION=$(git -C "$task_root" rev-parse HEAD)
if [ -n "$(git -C "$task_root" status --porcelain --untracked-files=normal)" ]; then
    STANA_BENCH_DIRTY=1
else
    STANA_BENCH_DIRTY=0
fi
export STANA_BENCH_SWIFT_VERSION STANA_BENCH_REVISION STANA_BENCH_DIRTY
exec "$task_bin/LayoutBenchmarks" "$@"
