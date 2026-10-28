# Repository Guidelines

## Project Structure & Module Organization

Stana UI is a swift toolkit for creating crossplatform desktop apps. `Sources/` has four entry points: `Stana` for the authoring API and composition root, `Engine` for portable subsystems, `Platform` for service contracts and native backends, and `StanaTesting` for consumer test hosts. Resources live in `Sources/Stana/Resources`; DocC lives in `Sources/Stana/Documentation.docc`.

Within `Sources/Stana`, `Application` holds public application/window API, `Components` groups controls, layout, and drawing, and `Composition` holds builders and structural components. `Runtime` separates internal mounting, editing, and window lifetimes. `Sources/Engine` contains `Primitives`, `Core`, `Accessibility`, `Graphics`, `Layout`, `Scene`, and `Text`. `Sources/Platform/Contracts` holds portable platform interfaces; `Sources/Platform/MacOS/Adapter` contains Swift adapters and `Sources/Platform/MacOS/Bridge` contains the private Objective-C bridge. Bridge C headers stay in `Bridge/include`; private headers live beside their implementations or at the bridge root. Target names and dependencies remain defined in `Package.swift` with explicit paths for nested targets; organizational folders do not create additional modules.

`Tests/` mirrors source areas: `Tests/Stana` holds authoring/runtime integration tests, `Tests/Engine` groups subsystem tests, and `Tests/Platform/MacOS` groups native rendering, text, and windowing tests with shared helpers in `Support`. Existing test target names and dependencies are preserved through explicit paths in `Package.swift`; do not create empty folders for subsystems without dedicated tests. `Examples/` contains independent consumer packages. `Fixtures/` holds API compilation cases and runtime-fault probes. `Scripts/` provides verification and packaging helpers; `Benchmarks/` contains performance fixtures. Consult `Docs/Architecture.md` and `CONTRIBUTING.md` before architectural changes.

`Docs/README.md` indexes contributor documentation. Historical plans and exploratory design notes live in `Docs/Archive`, separate from current architecture and verification guidance. Use UpperCamelCase folder names inside example source targets, matching the toolkit sources.

## Build, Test, and Development Commands

Use Swift 6.4 or newer in Swift 6 mode; the deployment target is macOS 26.

- `just`: list available recipes.
- `just format` / `just check-format`: format repository Swift and Objective-C files, or check formatting without edits.
- `just build` / `just build-release`: debug/release builds.
- `just test`: tests with Swift and native warnings treated as errors.
- `just check`: sequential formatting and boundary checks, tests, API fixtures, runtime probes, all example builds, and release build.
- `just example`: launch the Calculator example.
- `just benchmark`: release-mode headless benchmark, emitting JSON.
- `just test-gui`: opt-in GUI tests requiring a logged-in macOS window server.

Direct commands such as `swift build`, `swift test`, and `Scripts/check-boundaries.sh` remain supported.

## Coding Style & Naming Conventions

Follow `.swift-format` for Swift and `.clang-format` for Objective-C: one tab per indentation level, a four-column tab width, and 120-column lines. `just format` runs the built-in `swift format` and `clang-format` on `PATH` (`brew install clang-format`). `just check-format` and CI enforce both. CI installs `just` and `clang-format`. EditorConfig supplies matching indentation settings.

Use one blank line between methods, initializers, types, and computed properties; keep related stored properties together. Expand nonempty one-line function and control-flow bodies, and separate multiline control-flow blocks from following statements with a blank line. Do not add padding inside opening/closing braces or multiple consecutive blank lines. These breathing-room conventions must be applied when writing code: the formatter preserves existing gaps and expanded bodies but cannot require their presence. Wrapped argument lists use one argument per line, and multiline expression chains are separated onto lines.

Use UpperCamelCase types, lowerCamelCase members, and the existing `STN` prefix for public toolkit types. Keep public API in `Stana` and cross-target implementation `package`-visible. Avoid circular dependencies, native types in public signatures, and AppKit/SwiftUI imports in Swift sources. Do not initialize `NSApplication` during module loading or headless tests.

## Testing Guidelines

Use Swift Testing (`import Testing`, `@Suite`, `@Test`). Name files `*Tests.swift` and test functions descriptively, such as `leafUpdateDoesNotRemount`. Add regression tests in the matching subsystem. Begin API changes with consumer examples or valid fixtures; add invalid fixtures for rejected usage. No numeric coverage threshold is configured. Record relevant native, VoiceOver, and IME checks separately.

## Commit & Pull Request Guidelines

History is limited; the feature commit uses `feat: ...`. Prefer concise, imperative, descriptive subjects with an appropriate prefix. In PRs, summarize behavior changes, link relevant issues, report verification results and limitations, and include screenshots for visible UI changes. Update DocC, examples, and platform limitations alongside affected behavior.
