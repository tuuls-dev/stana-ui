# Window Configuration

Configure a window once or reactively using the same feature-based API:

```swift
let frameless = STNSignal(true)
let configuration = frameless.map { value in
    STNWindow.Configuration(
        appearance: .init(frame: value ? .frameless : .system),
        resizing: .init(minimumContentSize: .init(width: 320, height: 240))
    )
}
let window = STNWindow(properties: .init(title: "Inspector", configuration: configuration)) {
    STNWindowDragRegion {
        STNText(properties: .init(text: "Drag the window here"))
    }
}
```

There are **no platform sections**. STN applies available options and ignores
unavailable ones. Inactive features are not errors and produce no routine warning.
`window.resolution.value.ignored` describes what was ignored and why.

## Configuration groups

| Group               | Options                                                                                                                                                |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `creation`          | Window/panel/utility/HUD/nonactivating role, identity, initial origin/display, saved-frame name, initial visibility and activation                     |
| `appearance`        | System/frameless frame, background (including `.clear`), opacity, shadow and automatic/light/dark appearance                                           |
| `titleBar`          | Subtitle, title visibility, transparent/full-size title bar, separator, standard control visibility/enabled state and content border                   |
| `resizing`          | Resizability, content/frame minimum/maximum size, content/frame aspect ratio or resize increments, fullscreen size limits and live-resize preservation |
| `interaction`       | Movability, background dragging, mouse passthrough/movement, key/main eligibility, panel focus and inactive tooltips                                   |
| `behavior`          | Level (including custom), animation, close/minimize eligibility, deactivation/hide behavior, panel/modal behavior and window-menu participation        |
| `workspaces`        | Spaces, Mission Control/Stage Manager membership, cycling, fullscreen role, tiling and tabbing                                                         |
| `systemIntegration` | Represented URL, edited status, minimized image/title, Dock badge and tab title/tooltip                                                                |
| `chrome`            | Toolbar, style/display/visibility, title-bar accessories and tab accessory                                                                             |

`automatic` means the host's normal behavior, not disabled. Optional constraints
use `nil` for no explicit constraint. Choose at most one aspect-ratio or
resize-increment policy; frame and content policies are intentionally distinct.
Sizes must be finite; maximum dimensions and aspect/increment components must be
positive. Contradictory constraints are errors, not unavailable features.

`title`, `size` and `environment` remain ordinary window properties. `size` is the
initial content size in logical points. Actions distinguish content size from
outer frame. Screen rectangles use a primary-display top-left origin and may
have negative coordinates on other displays. `STNApplication.screens` lists
available display IDs, geometry and scales.

## Creation and live policy

`creation` is read when a window opens. Changing its values while open records
`requiresReopen` and does not replace the native window. Reopening the same
`STNWindow` reads the latest configuration. Saved geometry, when configured and
available, takes precedence over initial placement and is constrained to an
available screen.

All other supported settings are live. Changing them does not rerun content
builders or replace editor/node identity. Structural changes wait while IME
composition, window movement/resizing, sheets or fullscreen prevent safe changes.
The latest desired snapshot is retained and `resolution.value.isPending` is true
until it can apply. A fullscreen window must leave fullscreen before deferred
chrome changes can apply. Closing cancels pending work and observations.

`appliedConfiguration.value` is the last applied effective configuration.
`state.value` is native state: actual content/frame geometry, safe content bounds,
display/scale, focus, visibility, minimization/fullscreen transition and window/tab
relationships. Both are read-only computeds. User resizing does not overwrite your
initial size or configuration source.

Invalid initial values throw from `STNApplication.open`. Invalid reactive values
leave the last valid snapshot intact and invoke `onConfigurationError`; diagnostics
receive an error category, not application title or text. An unexpected native
failure is reported rather than described as a successful transaction.

## Custom chrome and input

Frameless windows remain keyboard-focusable by default. A `STNWindowDragRegion`
uses native window dragging; controls and pointer-handling descendants keep their
input. Nest a region with `properties: .init(mode: .exclude)` to exclude additional
content. Pointer capture or `preventDefault()` prevents native handoff. Enabling
`interaction.backgroundDragging` uses the same hit-test rules.

Use `STNWindowResizeRegion(properties: .init(edges: [.bottom, .trailing]))` for a
custom resize grip. Native geometry constraints still apply. Use `STNWindowContent`
at the surface root to inset foreground content beneath native title-bar/toolbar
chrome; put full-bleed decoration in a sibling overlay layer. Its
`avoidsChrome: false` option opts out.

A transparent native window also needs a transparent scene background:
`appearance: .init(frame: .frameless, background: .clear)`. Content can still paint
its own opaque backgrounds.

## Toolbars and accessories

```swift
let save = STNCommand(properties: .init(title: "Save", onActivate: { /* save */ }))
let toolbar = STNToolbar(properties: .init(identifier: "editor", allowsCustomization: true), items: [
    .command(id: "save", save),
    .flexibleSpace(id: "spacer")
])
let configuration = STNWindow.Configuration(chrome: .init(toolbar: toolbar))
```

Toolbar items support shared commands, images/tooltips/priority, groups, menus,
separators/spaces and `STNToolbarContent`. Command title/enabled/checked sources
remain reactive. Allowed items and optional default identifiers control native
customization; toolbar configuration persistence is opt-in.

`STNTitlebarAccessory` takes an identifier, size, placement and a Stana builder.
`chrome.tabAccessory` accepts `STNToolbarContent`. Definitions have stable identity:
changing toolbar visibility or style does not remount custom content. Replacing
a definition replaces only that surface. Each surface has independent editing,
accessibility, rendering and cleanup. Native chrome is ignored on frameless
windows without an applicable native title bar.

## Actions and relationships

Actions report unsupported operations rather than silently succeeding:

```swift
try window.setContentSize(.init(width: 900, height: 650))
try window.move(to: .init(x: 100, y: 100))
try await window.setFullscreen(true)
```

Other actions include show/hide/focus, center/order, minimize/restore/zoom, toolbar
customization and tab selection/overview. Fullscreen and sharing are async;
cancellation and window destruction resolve outstanding work once.

`requestClose()` observes `shouldClose`; `close()` always closes immediately and
is idempotent. `addChild`/`removeChild` manage owned window relationships. Closing
a parent closes attached owned children. Cycles and invalid attachments fail.

`presentSheet(_:critical:)` opens an unopened window as a native sheet and returns
its integer result. The sheet calls `endSheet(result:)`. Completion/cancellation
closes the sheet; parent closure cancels outstanding work. Tab actions include
adding, selecting, detaching, moving to a new window and merging compatible windows.
Tab grouping does not remount content or transfer application ownership.

`saveFrame(named:)` and `restoreFrame(named:)` support explicit geometry persistence;
restoration returns false when the name has no saved frame.
`STNApplication.removeSavedWindowFrame(named:)` removes stored geometry.
`requestSharing()` and `transferSharing(to:)` use system sharing where available;
legacy window-sharing flags are not exposed as screenshot protection.

## Deterministic testing

`STNWindowTestHost(window:unsupportedFeatures:)` opens the production window
controller on a recording host, without creating NSApplication. It can simulate
unavailable feature groups, busy transitions, resizing, safe-content changes,
input, composition and toolbar activation. It is not a real platform backend.

Run the example with `swift run --package-path Examples/WindowConfiguration`.
