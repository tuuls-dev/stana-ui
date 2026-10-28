# Local Verification — 2026-10-26

For the subsequent hybrid Metal renderer implementation and current verification, see [Metal verification](Metal.md). The original CPU-renderer evidence below is historical.

For the generic property inputs, shared capability groups, reactive layout/font, and current API migration checks, see [Shared properties verification](SharedProperties.md).

## Configuration

- Host: macOS 27.0.1, Apple Silicon (`arm64`).
- Compiler: Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, clang `2100.3.34.1`).
- SDK: macOS 27.0; package deployment target: macOS 14.
- Mode: Swift 6, explicit nonisolated target defaults and explicit UI-actor annotations.
- Swift and native warnings treated as errors during the full test build.
- Native window tests ran with window-server access. The restricted filesystem sandbox exposes a 1×1 display and cannot qualify drawable windows.

## Completed checks

| Check                                                | Result                                                                                                                                                      |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Full automated suite, `STANA_GUI_TESTS=1 swift test` | 47 passed across six test targets                                                                                                                           |
| Retained identity and reactive graph                 | Diamonds, dynamic/equal-output edge reversal, registration order, cancellation, demand-only cache cleanup                                                   |
| Structural/lifetime behavior                         | Reordering during composition, rejected keys/references, intentional value replacement, stale handles, late tasks, seeded moves                             |
| Layout/input                                         | Independent fixed-box oracle, constraints/flex redistribution, resize proposal restoration, current geometry, capture/bubble, keyboard scrolling            |
| Native rendering/text                                | Incremental raster equals full redraw; native custom-drawn window capture inspected; explicit UTF-8 byte lengths preserve embedded zero and multibyte text  |
| Native accessibility adapter                         | Committed element publication and revision checks; not a VoiceOver interoperability claim                                                                   |
| Public API fixtures                                  | External positive fixture and three intentionally invalid consumer fixtures passed                                                                          |
| Runtime faults                                       | Cycle, write-during-compute, and impure-comparator fixtures failed with the expected diagnosed fault in isolated processes                                  |
| Consumer packages                                    | Counter, Preferences, and Editable Collection built successfully                                                                                            |
| Distribution                                         | Release Counter bundle assembled; `Info.plist` validated; bundled executable passed async state-update/launch/close smoke test                              |
| Address Sanitizer                                    | Reactive, text-buffer, and native text-shaping subsets passed; no sanitizer errors reported                                                                 |
| Boundaries                                           | No Swift AppKit/SwiftUI imports, reverse core dependencies, native imports outside the adapter, unchecked Sendable escape hatches, or unsafe manifest flags |

The unsigned local artifact is generated at `dist/CounterApp.app`. It is not a signed/notarized release or a clean-machine installation test.

## Benchmark evidence

`Benchmarks/Results/local-arm64-macos27.json` records the release-mode headless 10,000-label fixture. It includes full semantic projection and public test-host snapshots, not just dependency-graph time. The fixture verifies zero remounts/builder executions and retains raw timing samples.

This is a local implementation baseline, not performance qualification, a 60/120 Hz guarantee, or a comparison with another toolkit. Full semantic/scene traversals and conservative stack work remain optimization targets.

## Not yet qualified

- Real VoiceOver reading, activation, text navigation, secure entry, hot activation, and modal workflows: use `VoiceOver.md`.
- Actual Japanese, Chinese, Korean, and other OS IME sessions: use `IME.md`; automated composition tests are not substitutes.
- Unfamiliar-developer walkthroughs and disabled-user usability evaluation; no recruitment or participant results exist.
- Minimum-macOS/Intel matrix, clean-machine distribution, signing/notarization, long-running soaks, or GPU performance.
- GitHub Actions execution. The workflow requires a runner providing Swift 6.4; local successful checks are not a hosted CI result.

The correct release tier remains **macOS developer preview**.

## Window configuration — 2026-10-27

The feature-based window configuration change passed the full **73-test optimized
suite with native GUI tests enabled**, Swift warnings as errors and native `-Werror`.
The 26 added tests cover configuration resolution/lifetime, frameless interaction,
constraints and transparency, native chrome/editor identity, relationships,
sheets, saved geometry and fullscreen completion. Consumer/misuse API fixtures,
runtime-fault probes, boundary checks and all four example builds also passed.

See [Windows verification](Windows.md) for the capability matrix, exact local
scope, and the remaining manual and minimum-OS qualification work.
