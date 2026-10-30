# Stana performance workloads

A fresh headless suite for answering specific questions about the public authoring
API and deterministic host.

## Run one workload

```sh
just benchmark --list
just benchmark ui-mount --sizes 100,1000 --samples 30 --warmup 3 --output /tmp/mount.json
just benchmark signal-fanout --sizes 100,1000,10000 --output /tmp/fanout.json
just benchmark ui-keyed-reverse --sizes 1000 --output /tmp/reverse.json
```

Each name selects **only that workload**: other workloads do not create fixtures,
warm up, or run. All workloads share one package and reporting harness, not one
combined benchmark. `all` is an explicit convenience for running the matrix:

```sh
just benchmark all --sizes 100,1000 --output /tmp/stana-performance.json
```

Without `just`, use `Scripts/benchmark.sh` with the same arguments. It builds the
release executable with warnings as errors before launching it, and supplies the
Swift version, Git revision, and working-tree state. Build and progress output go
to stderr; stdout contains JSON only. `--output` atomically writes the JSON after
all selected trials pass instead. A failed run exits nonzero and emits no new
report; an existing output file is left untouched, so always check the exit status.
Direct executable invocation leaves unavailable toolchain/Git metadata absent.

Defaults: sizes 100 and 1,000, 3 discarded warmup trials, 30 measured trials per
size. With no positional name the runner selects `all`. Sizes are workload units,
**not total retained node counts**; structural nodes and the host root are extra.
Use explicit sizes to investigate scaling; 10,000-node cases are opt-in rather
than imposing a large unrelated mount on every measurement. There are no timing
thresholds or performance assertions.

## Workload contracts

| Name                 | Size means                                     | Timed operation                                         | Correctness guard outside timing                                    |
| -------------------- | ---------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------- |
| `signal-fanout`      | Subscribers                                    | One changed source write through synchronous delivery   | Exactly N deliveries and expected accumulated value                 |
| `signal-equal-write` | Subscribers                                    | One equal source write                                  | No deliveries; equality-suppression control                         |
| `computed-diamond`   | Parallel computed branches                     | One source write and demand of a cached sum             | All N branches reevaluate once and the sum changes correctly        |
| `ui-mount`           | Static text labels in a stack                  | Mount through initial headless commit                   | Complete expected label sequence                                    |
| `ui-leaf-commit`     | Independently bound text labels                | One label change through synchronous commit             | One property update/commit; stable IDs, mounts, and builders        |
| `ui-batched-commit`  | Independently bound text labels                | N source writes in one transaction through commit       | N property updates, one commit, no remount or composition           |
| `ui-equal-write`     | Independently bound text labels                | One equal source write                                  | Zero property updates/commits and stable IDs                        |
| `ui-keyed-reverse`   | Keyed rows containing a text label             | Reverse the row order through commit                    | Reversed original label IDs; no remount or builder execution        |
| `ui-branch-remove`   | Composed, bound labels in a conditional branch | Remove branch through cleanup delivery                  | N disposals; persistent sibling identity; removed bindings inactive |
| `ui-resize`          | Static text labels in a stack                  | Change viewport from 800×600 to 1024×768 through commit | Geometry changes in one commit without identity/composition changes |
| `ui-close`           | Composed, independently bound labels           | Close the mounted host                                  | Empty tree, N disposals, no binding delivery after close            |

The first three exercise public reactive primitives without UI machinery. UI
operations include the host's actual synchronous document work, deterministic
text measurement, layout, semantic projection, and published node snapshots.
They are **end-to-end headless operations**, not isolated graph, layout, or
lifetime-registry timings. `ui-close` includes document removal costs; do not
attribute it solely to resource unregister. The fixed-length leaf strings limit
text-size differences, but do not disable text measurement or layout.

None of these workloads builds a native window, performs scene recording/raster,
executes GPU programs, or measures presentation/input latency, HDR, FPS, memory
peaks, or native text shaping. Native correctness tests remain available via
`just test-gui`; they are not replacement performance evidence. A future native
performance suite needs its own operation boundaries and display-completion
contract, rather than resurrecting a combined feature showcase.

## Measurement protocol

- A fresh fixture is prepared for **every** warmup and measured trial. Setup,
  initial mount (except `ui-mount`), verification, and cleanup (except `ui-close`)
  are outside the timed interval. Each interval contains exactly one described
  operation, not an adaptive loop or multiple unrelated stages.
- Warmups execute and validate the same operation, then are discarded. Fresh
  fixtures avoid measurements silently becoming equal writes or no-op reorders.
  They do not represent a cold process: allocator/compiler/OS caches can be warm.
- `ContinuousClock` surrounds the operation. Tiny equality controls can be close
  to timer/closure overhead; no subtraction or invented zero-cost estimate is
  applied. No subprocess/build duration is counted as operation latency.
- Raw samples remain in execution order. Each includes metric deltas or reactive
  counters. UI metrics are read before correctness probes change any signals.
  Summaries use nearest-rank min/p50/p95/max on a sorted copy. Small-sample tails
  are descriptive only; p99 and confidence intervals are intentionally absent.
- Reports identify the schema/suite, run UUID, UTC timestamp, build configuration,
  command arguments, OS, CPU architecture/count, physical memory, thermal state,
  low-power mode, and available compiler/Git provenance. No machine identifiers
  are collected. Thermal/power fields are a start-of-run snapshot, not monitoring.
- Use the same machine, power/thermal conditions, compiler, sizes, and options for
  comparisons. Run workloads individually without concurrent builds, tests,
  validation, or GUI workloads. Repeat in independent processes and alternate
  revision order when comparing changes; the runner does not claim independent
  samples, statistical significance, or causal attribution from one process.
- Results are generated locally, not committed as evergreen performance claims.
  Save reports outside the repository, or under ignored `Benchmarks/Runs/` after
  creating that directory. Compare only matching suite/schema/workload contracts.

## Validate separately

```sh
just benchmark-test                         # harness, argument, and fixture tests
just benchmark-validate                     # all workloads, sizes 1 and 8, no timings
just benchmark ui-close --validate --sizes 1000  # validate an individual larger case
```

Validation runs one fresh trial per size without reading a clock or emitting
latency summaries. The package tests check fixture correctness at sizes 1 and 8,
raw sample/warmup handling, cleanup on failure, percentile calculation, and option
validation. `just check` includes these tests, **not performance runs**. Debug
executables reject timing mode to prevent accidental debug/release comparisons.
