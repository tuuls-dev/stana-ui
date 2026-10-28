# HybridRendering

An external consumer using only `Stana` and Foundation. Run with `just example HybridRendering`.

The chart mixes GPU shapes/HDR polyline, a moving/fading finite-radius frosted panel, ordinary CPU controls, a custom Metal distortion, and a later CPU tooltip. A separate HDR visualization executes compute then fragment passes. The nested isolated panel demonstrates local backdrop scope; the 300-row scroll area exercises tiled worker rasterization. These are authored effects, not native Liquid Glass parity.

The Metal source is loaded from `Bundle.module`, not the current directory. Package with:

```sh
just package Examples/HybridRendering HybridRenderingApp dev.stana.hybrid
```

`--smoke-test` captures pre-display half-float bytes, explicitly display-mapped BGRA8, and diagnostics under `/tmp`, then exits. `--benchmark --output <path>` waits for at least 120 warm-up and 1,000 measured completed offscreen frames. Reports retain raw revision-tagged samples and p50/p95/p99; positive, zero, and missing presentation observations remain distinct. `STANA_METAL_FINAL_MODE=persistent|direct|automatic` selects the native final path. Use release builds without Metal validation for timing, and validation separately for correctness. This mixed workload is not the complete resolution/refresh/workload qualification matrix.

Use `just benchmark-native persistent <report.json>` or `just benchmark-native direct <report.json>` for measurements: these foreground-launch the packaged app. A bare `swift run` process can remain occluded and receive only zero presentation timestamps. An incomplete run exits without publishing a successful report.
