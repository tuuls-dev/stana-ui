# Benchmark Results

Run `just benchmark` and retain its JSON alongside the commit, exact Swift toolchain, OS/hardware, display/environment settings, and instrumentation configuration.

The fixture warms up ten writes and records 100 updates of one bound label in a 10,000-label tree. It asserts zero new mounts/builders and reports synchronous headless update time, including semantic projection and testing snapshots. It does not measure native input-to-presentation or establish architecture superiority.

Raw reports are evidence, not universal budgets. Do not compare debug and release runs or claim cross-toolkit speedups from this fixture.

`native-hybrid-persistent-arm64-macos27.json` and `native-hybrid-direct-arm64-macos27.json` retain separate native release runs (123/120 warm-up, 1,000 measured completed offscreen frames each). See [Metal verification](../../Docs/Verification/Metal.md) for the exact scope, presentation observations, and timing limitations. Those runs packaged the HybridRendering example and foreground-launched it through Launch Services. That former consumer is restored as `Benchmarks/Sources/NativeRenderingBenchmarks`, and `just benchmark-native persistent <report.json>` now packages and runs it. The historical JSON files remain the record of those older runs.
