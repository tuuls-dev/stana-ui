# Benchmark Results

Run `swift run --package-path Benchmarks -c release` and retain its JSON alongside the commit, exact Swift toolchain, OS/hardware, display/environment settings, and instrumentation configuration.

The fixture warms up ten writes and records 100 updates of one bound label in a 10,000-label tree. It asserts zero new mounts/builders and reports synchronous headless update time, including semantic projection and testing snapshots. It does not measure native input-to-presentation or establish architecture superiority.

Raw reports are evidence, not universal budgets. Do not compare debug and release runs or claim cross-toolkit speedups from this fixture.
