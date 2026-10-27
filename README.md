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

## Run the examples

```sh
swift run --package-path Examples/Counter
swift run --package-path Examples/Preferences
swift run --package-path Examples/EditableCollection
swift run --package-path Examples/WindowConfiguration
```

If a build reports `unknown argument: '-target-arch-variant'` followed by missing
Foundation types or `STNNodeID` conformance errors, check
`xcrun --toolchain XcodeDefault swift --version`. Swift 6.3 cannot read the
macOS 27 SDK's Swift interfaces; use the matching Xcode toolchain above rather
than changing the identity types. The package requires Swift 6.4 or newer.

Each example is a separate consumer package importing only `Stana`.

- **Counter:** state, derived text, a shared command, keyboard shortcut, and menu.
- **Preferences:** reusable fields, two-way bindings, toggles, save dialog, and asynchronous file writing.
- **Window Configuration:** reactive framed/frameless chrome, native drag regions, control exclusions, and a custom resize grip.
- **Editable Collection:** stable observable rows, editing, reordering, removal, and scrolling. This is not a virtualized list.

## The small mental model

| Input | Meaning |
|---|---|
| `text: "Hello"` | Constant for this mount |
| `text: name` | Subscribe to a signal |
| `text: name.map { "Hello, \($0)" }` | Subscribe to derived state |
| `value: name.binding` | Read and write committed application state |
| `text: name.value` | Capture the current value; **not** a subscription |
| `STNIf(flag) { ... }` | Dispose/mount a localized branch |
| `STNForEach(observableRows: rows, id: \.id)` | Preserve row/editor identity across reordering |

Properties come before children. Actions belong in properties. Ordinary Swift `if` and `for` in a builder run at mount time; use structural components for later changes.

Preview reactive inputs are text (labels/buttons/toggles), container background and opacity, control enabled state, accessibility labels, window titles, canvas drawings, command title/enabled/checked state, and structural sources. Window configuration also accepts constant/signal/computed snapshots; unavailable options are ignored by the host. Other properties are mount-time configuration. Editable controls use bindings; environment theme/direction/text scale can change independently.

## Architecture

Swift owns the document, reactivity, layout, custom controls, editing state, scene, and semantic projection. A private Objective-C bridge uses AppKit only for host integration, IME, accessibility, menus, and system dialogs. There are no AppKit content controls, no SwiftUI, and no external binary dependencies. Rendering uses Core Graphics and Core Text behind portable service contracts.

See [window configuration](Sources/Stana/Documentation.docc/WindowConfiguration.md), [architecture](Docs/Architecture.md), [API decisions](Docs/Decisions/0002-public-api-contract.md), and the original [design specification](ramblings/design_thoughts.md).

## Test and package

```sh
swift test
Scripts/check-api-fixtures.sh
Scripts/check-runtime-faults.sh
Scripts/check-boundaries.sh
Scripts/package-macos-app.sh Examples/Counter CounterApp dev.stana.counter
```

Consumers can depend on `StanaTesting` and drive `STNTestHost` without creating a native application. The packaging script creates an unsigned `.app` in `dist/`; signing and notarization are application-owned.

For native host/raster verification in a logged-in macOS session, run `STANA_GUI_TESTS=1 swift test`. GUI tests require window-server access; a filesystem sandbox may expose only a non-drawable virtual display.
