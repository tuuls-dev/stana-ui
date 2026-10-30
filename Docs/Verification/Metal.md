# Hybrid Metal verification — 2026-10-28

## Implementation and environment

The production macOS host now uses worker Core Graphics/Core Text → IOSurface → Metal composition → `CAMetalLayer`. CPU/GPU paint order, retained affine groups, tiled final backing, custom render/compute programs, feedback state, HDR, finite blur, and custom backdrop distortion are implemented. Core Graphics remains an explicit reference renderer, not an automatic fallback.

Local environment: Apple M1 Pro, 16 GiB RAM, macOS 27.0.1, Xcode/SDK 27, Swift 6.4 in Swift 6 mode; deployment target unchanged. Native GUI checks require window-server access. No physical VoiceOver, IME, display-move, or scanout qualification is inferred from offscreen pixels.

## Automated evidence

- `just check` passed: formatting, dependency/native boundaries, warnings-as-errors tests, positive/negative consumer fixtures, isolated runtime-fault probes, all six external examples, and release build. The complete GUI-enabled run passed 125 tests; the final renderer-only validation run passed all nine native Metal regressions.
- The window-server suites share a serialized parent because focus, fullscreen transitions, and display epochs are process-global. Running unrelated GUI suites concurrently can reset the temporal-state test's surface epoch; serialization fixes the test interference rather than weakening state assertions.
- Renderer tests run separately with `MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 STANA_GUI_TESTS=1 swift test --filter NativeMetalTests`. They check worker raster/GPU composition, HDR values above one, 1,000 committed feedback steps, state reset, invalid cached-pipeline buffer replacement, identity/blur references, hosted-surface HDR promotion, translucent mixed CPU/GPU prefix replacement, later-paint order, chained off-output halo propagation, stalled raster admission, and sparse/full/untiled equality.
- Presentation state-machine tests permute GPU/positive/zero/late/old-epoch observations. A return to old geometry and a late older confirmation cannot erase newer ambiguity; gated regions accumulate conservatively with bounded coalescing until a covering confirmation. The test helper's native loop can return only zero drawable timestamps: these remain unknown, not confirmed. The thousand-step test intentionally exercises offscreen execution directly so an unavailable display acknowledgement does not bypass or disable the production adapter's 256-snapshot admission bound.
- A 10,000-entry content edit records one leaf and patches balanced sibling branches plus the ancestor chain. Depth 128/256/512 fixtures preserve immutable old snapshots. The transport regression sends at most 20 changed objects and less than 10 KiB for the 10,000-entry update.
- A small update in a 1920×1080-point window changes no more than 10% of raster/final pixels and is byte-identical to forced-full and untiled reconstruction.

## Performance evidence

The former mixed native showcase, packaged benchmark harness, capture, and retained timing reports have been removed. The replacement [headless workload suite](../../Benchmarks/README.md) does not measure native rendering or presentation. No native performance baseline is currently retained or claimed; renderer correctness checks above remain separate from timing.

## Remaining qualification and optimization

The developer-preview implementation is not a claim that every acceptance gate in the design notes has passed. Remaining work includes balanced backdrop request/spatial indexes (current contributor scans are conservative), sampled per-group contiguous/tiled hysteresis, comprehensive resource-lease assertions/fault injection, focused multiwindow worker/cache weighting and pressure/resize/hidden-cache soaks, and arbitrary named-resource readback. The complete static/sparse/full/scroll/overlap resolution/refresh SDR/HDR matrix, baseline hardware performance budgets, minimum-supported-runtime matrix, and real VoiceOver/IME/display transitions remain unqualified. These do not disable the shipped tiling, damage-updated final backing, worker execution, shaders, HDR, or backdrop support.

## Swift backend verification

The native regressions cover typed snapshot sharing, uniform layout, temporal GPU state, backdrop ordering, HDR, cancellation, teardown, and coordinate input in sheets/secondary/child windows. The coordinate fixture uses a foreground application because the SwiftPM helper can remain occluded; GPU completion or zero timestamps never confirm input readiness.

Actual macOS 26 execution, user-session VoiceOver/IME, external displays, and the full performance matrix remain unqualified. Validation and benchmarks must run separately.
