# Stana UI

A retained, custom-drawn desktop UI toolkit for Swift Package Manager.

**Developer preview:** macOS backend; Swift 6.4; macOS 14 deployment target. Windows and Linux are architectural targets, not implemented hosts. See [platform support](Docs/PlatformSupport.md) for qualification and limitations.

## Start with a working application

Add this repository as a SwiftPM dependency and depend on its `Stana` product. Until a release is tagged, use a local path or an explicitly pinned revision.

```swift
// Package.swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../stana-ui")],
    targets: [.executableTarget(
        name: "MyApp",
        dependencies: [.product(name: "Stana", package: "stana-ui")]
    )]
)
```

```swift
import Stana

@main
struct MyApp {
    @MainActor static func main() {
        let count = STNSignal(0)
        let window = STNWindow(properties: .init(title: "Hello, Stana")) {
            STNVStack(properties: .init(spacing: 16, padding: 24)) {
                STNText(properties: .init(text: count.map { "Count: \($0)" }))
                STNButton(properties: .init(text: "Increment", onActivate: {
                    count.value += 1
                }))
            }
        }
        STNApplication.run(windows: [window])
    }
}
```

Builders mount once. Changing `count` updates the existing text node; it does not rerun the window or stack builder.

## Developer commands

The optional root `justfile` provides shortcuts for the existing Swift commands and
scripts. Install `just` with `brew install just`; Swift 6.4 or newer and macOS are
still required. Commands also work from repository subdirectories.

```sh
just                 # List available commands
just format          # Format Swift files with the bundled formatter (tabs, four-column width)
just check-format    # Check Swift formatting without editing files
just build           # Debug build
just build-release   # Release build, Swift warnings as errors
just test            # Tests, Swift and native warnings as errors
just check           # All non-GUI checks, all five example builds, and release build
just version patch   # Confirm, bump VERSION, commit, tag, and push (also minor/major)
just example         # Run Counter
just example Counter # Run a named example
just benchmark       # Release-mode headless benchmark; prints JSON
just package Examples/Counter CounterApp dev.stana.counter
```

The `example` recipe accepts a positional name (`just example Counter`) or an
`example=` argument (`just example example=Counter`). Omitting it defaults to Counter.

Formatting runs first in `just check` and CI; see [contributing](CONTRIBUTING.md#swift-formatting)
for the spacing conventions. Individual checks are available as `just check-boundaries`, `just check-api`, and
`just check-runtime`; `just build-examples` builds all five examples. Direct Swift
commands and scripts below remain supported, and CI does not require `just`.

## Run the examples

```sh
swift run --package-path Examples/Counter
swift run --package-path Examples/Preferences
swift run --package-path Examples/EditableCollection
swift run --package-path Examples/WindowConfiguration
swift run --package-path Examples/TextFields
```

If a build reports `unknown argument: '-target-arch-variant'` followed by missing
Foundation types or `STNNodeID` conformance errors, check
`xcrun --toolchain XcodeDefault swift --version`. Swift 6.3 cannot read the
macOS 27 SDK's Swift interfaces; use the matching Xcode toolchain above rather
than changing the identity types. The package requires Swift 6.4 or newer.

Each example is a separate consumer package importing only `Stana`.

- **Counter:** state, derived text, a shared command, keyboard shortcut, and menu.
- **Text Fields:** selection, native text services, reactive read-only/enabled state, styling, and secure entry.
- **Preferences:** reusable fields, two-way bindings, toggles, save dialog, and asynchronous file writing.
- **Window Configuration:** reactive framed/frameless chrome, native drag regions, control exclusions, and a custom resize grip.
- **Editable Collection:** stable observable rows, editing, reordering, removal, and scrolling. This is not a virtualized list.

## The small mental model

| Input                                        | Meaning                                           |
| -------------------------------------------- | ------------------------------------------------- |
| `text: "Hello"`                              | Constant for this mount                           |
| `text: name`                                 | Subscribe to a signal                             |
| `text: name.map { "Hello, \($0)" }`          | Subscribe to derived state                        |
| `value: name.binding`                        | Read and write committed application state        |
| `text: name.value`                           | Capture the current value; **not** a subscription |
| `STNIf(flag) { ... }`                        | Dispose/mount a localized branch                  |
| `STNForEach(observableRows: rows, id: \.id)` | Preserve row/editor identity across reordering    |

Properties come before children. Actions belong in properties. Ordinary Swift `if` and `for` in a builder run at mount time; use structural components for later changes.

Preview reactive inputs are text (labels/buttons/toggles), container background and opacity, control enabled state, accessibility labels, window titles, canvas drawings, command title/enabled/checked state, and structural sources. Text-field options and window configuration also accept constant/signal/computed snapshots; unavailable options are ignored by the host. Other properties are mount-time configuration. Editable controls use bindings; environment theme/direction/text scale can change independently.

## Architecture

Swift owns the document, reactivity, layout, custom controls, editing state, scene, and semantic projection. A private Objective-C bridge uses AppKit only for host integration, IME, accessibility, menus, and system dialogs. There are no AppKit content controls, no SwiftUI, and no external binary dependencies. Rendering uses Core Graphics and Core Text behind portable service contracts.

See [text fields](Sources/Stana/Documentation.docc/TextFields.md), [window configuration](Sources/Stana/Documentation.docc/WindowConfiguration.md), [architecture](Docs/Architecture.md), [API decisions](Docs/Decisions/0002-public-api-contract.md), and the original [design specification](ramblings/design_thoughts.md).

## Test and package

```sh
swift test
Scripts/check-api-fixtures.sh
Scripts/check-runtime-faults.sh
Scripts/check-boundaries.sh
Scripts/package-macos-app.sh Examples/Counter CounterApp dev.stana.counter
```

Consumers can depend on `StanaTesting` and drive `STNTestHost` without creating a native application. The packaging script creates an unsigned `.app` in `dist/`; signing and notarization are application-owned.

For native host/raster verification in a logged-in macOS session, run `just test-gui` or `STANA_GUI_TESTS=1 swift test`. GUI tests require window-server access; a filesystem sandbox may expose only a non-drawable virtual display. They are opt-in and are not enabled by `just check`.
