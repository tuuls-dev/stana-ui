#!/bin/sh
set -eu
ulimit -c 0
task_root=$(cd "$(dirname "$0")/.." && pwd)
swift build --package-path "$task_root/Fixtures/Faults" --product FaultProbe
task_bin=$(swift build --package-path "$task_root/Fixtures/Faults" --show-bin-path)
task_logs=$(mktemp -d "${TMPDIR:-/tmp}/stana-faults.XXXXXX")
trap 'rm -rf "$task_logs"' EXIT HUP INT TERM
for task_case in cycle write comparator \
    initial-padding update-padding initial-frame update-frame initial-opacity update-opacity \
    initial-border update-border initial-radius update-radius \
    initial-symbol-size update-symbol-size initial-symbol-stroke update-symbol-stroke \
    symbol-bridge-version symbol-bridge-opacity symbol-bridge-depth; do
    if SWIFT_BACKTRACE=enable=no "$task_bin/FaultProbe" "$task_case" >"$task_logs/$task_case.log" 2>&1; then
        echo "Runtime fault unexpectedly succeeded: $task_case" >&2; exit 1
    fi
    if ! grep -q 'Stana:.*\(dependency cycle\|forbidden\|invalid\|symbol\)' "$task_logs/$task_case.log"; then
        cat "$task_logs/$task_case.log" >&2; exit 1
    fi
done
echo 'Stana runtime faults diagnosed in isolated processes'
