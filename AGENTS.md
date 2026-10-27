# Repository Guidelines

## Project Structure & Module Organization

Stana UI is a swift toolkit for creating crossplatform desktop apps. `Sources/Stana` exposes the public API; sibling targets separate reactivity, layout, text, scenes, rendering, accessibility, and platform services. `Sources/CStanaMacOS` contains the private Objective-C bridge. Resources live in `Sources/Stana/Resources`; DocC lives in `Sources/Stana/Documentation.docc`.

`Tests/` mirrors subsystem targets. `Examples/` contains independent consumer packages. `Fixtures/` holds API compilation cases and runtime-fault probes. `Scripts/` provides verification and packaging helpers; `Benchmarks/` contains performance fixtures. Consult `Docs/Architecture.md` and `CONTRIBUTING.md` before architectural changes.

## Build, Test, and Development Commands

Use Swift 6.4 or newer in Swift 6 mode; the deployment target is macOS 14.

- `just`: list available recipes.
- `just build` / `just build-release`: debug/release builds.
- `just test`: tests with Swift and native warnings treated as errors.
- `just check`: sequential boundary checks, tests, API fixtures, runtime probes, all example builds, and release build.
- `just run Preferences`: launch an example; `just run` defaults to Counter.
- `just benchmark`: release-mode headless benchmark, emitting JSON.
- `just test-gui`: opt-in GUI tests requiring a logged-in macOS window server.

Direct commands such as `swift build`, `swift test`, and `Scripts/check-boundaries.sh` remain supported.

## Coding Style & Naming Conventions

Follow `.swift-format`: four-space indentation and 120-column lines; use `swift format` for formatting. Use UpperCamelCase types, lowerCamelCase members, and the existing `STN` prefix for public toolkit types. Keep public API in `Stana` and cross-target implementation `package`-visible. Avoid circular dependencies, native types in public signatures, and AppKit/SwiftUI imports in Swift sources. Do not initialize `NSApplication` during module loading or headless tests.

## Testing Guidelines

Use Swift Testing (`import Testing`, `@Suite`, `@Test`). Name files `*Tests.swift` and test functions descriptively, such as `leafUpdateDoesNotRemount`. Add regression tests in the matching subsystem. Begin API changes with consumer examples or valid fixtures; add invalid fixtures for rejected usage. No numeric coverage threshold is configured. Record relevant native, VoiceOver, and IME checks separately.

## Commit & Pull Request Guidelines

History is limited; the feature commit uses `feat: ...`. Prefer concise, imperative, descriptive subjects with an appropriate prefix. In PRs, summarize behavior changes, link relevant issues, report verification results and limitations, and include screenshots for visible UI changes. Update DocC, examples, and platform limitations alongside affected behavior.
