#!/bin/sh
set -eu
task_mode=${1:-persistent}
task_output=${2:-/tmp/stana-native-benchmark.json}
case "$task_mode" in persistent|direct|automatic) ;; *) echo 'Mode must be persistent, direct, or automatic' >&2; exit 2 ;; esac
task_root=$(cd "$(dirname "$0")/.." && pwd)
task_scratch=$(mktemp -d "${TMPDIR:-/tmp}/stana-native-benchmark.XXXXXX")
trap 'rm -rf "$task_scratch"' EXIT HUP INT TERM
"$task_root/Scripts/package-macos-app.sh" "$task_root/Benchmarks" NativeRenderingBenchmarks dev.stana.benchmark >"$task_scratch/build.log" 2>&1 || {
    cat "$task_scratch/build.log" >&2
    exit 1
}
# Launch Services foreground activation is important: a bare swift-run process
# can remain occluded and receive only zero drawable presentation timestamps.
# Keep the run isolated from other native GUI tests and GPU validation.
open -W -n --env "STANA_METAL_FINAL_MODE=$task_mode" \
    --stdout "$task_scratch/stdout.log" --stderr "$task_scratch/stderr.log" \
    "$task_root/dist/NativeRenderingBenchmarks.app" --args --benchmark --output "$task_scratch/report.json"
cat "$task_scratch/stdout.log" "$task_scratch/stderr.log"
if [ ! -s "$task_scratch/report.json" ]; then
    echo 'Native benchmark did not complete; no report was published.' >&2
    exit 1
fi
cp "$task_scratch/report.json" "$task_output"
echo "Native benchmark report: $task_output"
