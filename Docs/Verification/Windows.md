# Window configuration coverage and verification

## Contract and coverage

The interface is feature-based. Every production host must resolve each explicit
option, apply it or report an ignored reason. There is no application-side platform
switch. Only macOS is implemented; the recording host deliberately varies supported
features to exercise this contract.

| Feature / native surface                                                                         | Stana interface                                        | Lifecycle / current evidence                                                                                                                          |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Titled/borderless and resizable styles                                                           | `appearance.frame`, `resizing.isResizable`             | Live; native masks, root/editor identity, key/main eligibility verified                                                                               |
| Window, panel, utility, HUD, nonactivating panel                                                 | `creation.role`                                        | Creation-only; native panel class/nonactivation mask verified; changes require reopening                                                              |
| Close/minimize/zoom controls                                                                     | `behavior`, `titleBar.*Button`                         | Live; visibility, constraints and close veto verified; unavailable controls ignored                                                                   |
| Title/subtitle, title visibility, transparent/full-size title bar, separator and content borders | `title`, `titleBar`                                    | Live; native title/full-size/hidden close control and safe geometry verified                                                                          |
| Native appearance, alpha, shadow and background                                                  | `appearance`                                           | Live; native opacity/shadow/opaque state and transparent backing verified                                                                             |
| Content/frame min/max, aspect ratios and increments; fullscreen size limits                      | `resizing`                                             | Live; actual constrained resizing, distinct frame/content ratios and infeasible-update rejection verified                                             |
| Movability and native background dragging                                                        | `interaction`; `STNWindowDragRegion`                   | Live; retained hit-test exclusions, handlers, controls, capture and cancellation tested headlessly; physical native drag qualification remains manual |
| Explicit edge/corner resize regions                                                              | `STNWindowResizeRegion`                                | Live; hit-test disposition tested; native event tracking enforces configured geometry; physical grip/cursor qualification remains manual              |
| Mouse passthrough/movement, key/main eligibility, panel key-only-when-needed                     | `interaction`                                          | Live; frameless key eligibility and editing shortcuts verified; native keyboard-focus inquiry is side-effect-free                                     |
| Level, animation, hide/deactivate, modal behavior, window-menu and pre-login policy              | `behavior`                                             | Live; maps to corresponding native properties; compositor/login/session behavior requires manual qualification                                        |
| Spaces, Mission Control, Stage Manager, cycling, fullscreen participation/tiling                 | `workspaces`                                           | Live; fullscreen entry/exit completion verified; actual multi-Space/tiling/Stage Manager arrangements remain manual                                   |
| Show/hide/focus/order/center, move/frame/content-size, minimize/restore/zoom                     | Window actions                                         | Explicit unsupported/invalid-state errors; geometry and native focus verified                                                                         |
| Fullscreen transitions and failure/cancellation                                                  | `setFullscreen`; `state`                               | Async; real entry/exit and unsupported borderless action verified                                                                                     |
| Child windows                                                                                    | `addChild`, `removeChild`; `state`                     | Native relationships and cycle rejection verified; parent owns attached-child lifetime                                                                |
| Normal/critical sheets                                                                           | `presentSheet`, `endSheet`; `state`                    | Async; real sheet result and parent-close cancellation verified; critical-sheet presentation maps to native API                                       |
| Native tabbing mode/identifier, grouping, selection, detachment, overview and merging            | `workspaces`; tab actions; `state`                     | Live; real grouping and published relationships verified; native group/content-layout changes observed                                                |
| Tab labels/tooltips and custom accessory                                                         | `systemIntegration`, `chrome.tabAccessory`             | Live; labels use native tab properties; custom surface follows retained chrome lifecycle                                                              |
| Native toolbar, allowed/default items, customization and autosave                                | `STNToolbar`, `chrome`                                 | Live; real toolbar installation, style update and removal verified; user customization/persistence remains manual                                     |
| Toolbar commands, icons/tooltips/priority, groups/menus/spaces/custom content                    | Toolbar items, `STNCommand`, `STNToolbarContent`       | Reactive command state and shared action tested; native custom surface retained across presentation changes                                           |
| Title-bar accessory placement, fullscreen minimum height and visibility                          | `STNTitlebarAccessory`                                 | Live; native insertion/removal and stable surface mount count verified                                                                                |
| Editing, accessibility and rendering in custom chrome                                            | Independent chrome mount sessions                      | Native accessory IME callback deferral/focus regression tested; real IME and VoiceOver sessions remain manual                                         |
| Display enumeration and portable positioning                                                     | `STNApplication.screens`, `creation`, geometry actions | Actual screen discovery and screen identity verified; hot-plug/mixed-DPI configurations remain manual                                                 |
| Frame autosave and explicit save/restore/remove                                                  | `creation.frameAutosaveName`, frame actions            | Real saved geometry round-trip and cleanup verified; restored geometry constrained to available screen                                                |
| Represented URL, document-edited state, miniwindow image/title, Dock badge                       | `systemIntegration`                                    | Live native metadata; document model/lifecycle remains application-owned                                                                              |
| Native system sharing and sharing transfer                                                       | Async sharing actions; `state`                         | Availability checked natively; initiating sharing requires macOS 15+, otherwise explicit unsupported result; user sharing consent flow remains manual |
| Native visibility, focus, occlusion, fullscreen, display/scale, safe bounds and relationships    | Read-only `state`                                      | Published from native delegates/KVO; headless and native tests exercise coherent transitions                                                          |
| Unavailable and construction-dependent settings                                                  | Read-only `resolution`                                 | Ignored without routine warnings; unsupported vs inapplicable vs requires-reopen tested                                                               |

### Deliberate exclusions

Deprecated/no-effect flags (including textured/unified legacy masks and legacy
sharing restrictions), raw AppKit objects, inherited responder plumbing, native
content-view replacement, renderer/backing/color-space policy, rich-text tab
labels, custom application/Dock rendering, printing/export, and a document-app
restoration framework are not window configuration. Use the existing renderer,
content/desktop APIs or application-owned document model for those concerns.

A native sharing flag is not exposed as screenshot protection. Native capabilities
and configured policy do not override compositor decisions, user settings, or
system permissions.

## Automated checks

The implementation adds deterministic `WindowConfigurationTests` plus native
`NativeWindowConfigurationTests`. The deterministic host uses the **production
window controller**, not a second implementation of its reactive lifecycle.

Commands (Swift 6.4 / macOS 27 SDK):

```sh
swift test -Xswiftc -warnings-as-errors -Xcc -Werror
STANA_GUI_TESTS=1 swift test -Xswiftc -warnings-as-errors -Xcc -Werror
Scripts/check-api-fixtures.sh
Scripts/check-runtime-faults.sh
Scripts/check-boundaries.sh
swift build --package-path Examples/WindowConfiguration -Xswiftc -warnings-as-errors
```

Restricted tool execution used `--disable-sandbox` for SwiftPM's nested manifest
sandbox and temporary module-cache paths. This does not grant access to the window
server: GUI verification was run separately in the logged-in macOS session.
An empty/virtual display inside the filesystem sandbox is not qualification for
native window geometry, tabs, sheets, rendering or fullscreen.

The local verification result is recorded below after the final run. Original
Counter, Preferences and Editable Collection consumer builds are also checked.

## Manual qualification still required

- Physical dragging across Spaces and screens; custom edge/corner resizing at all limits.
- Japanese/Chinese/Korean IME in both body and chrome; no lost marked text on native focus changes.
- VoiceOver navigation between body, toolbar, accessories and modal sheets.
- Multiple displays, negative origins, mixed scales, hot-plug and saved offscreen geometry.
- Stage Manager, Mission Control, fullscreen tiling and nonactivating utility panels.
- Toolbar customization, persisted layouts, native sharing consent and critical sheets.
- Minimum macOS 14 / Intel matrix, rather than inferring support from the deployment target.

## Local result — 2026-10-27

- macOS 27.0.1, Apple Silicon; Swift 6.4; macOS 27 SDK; deployment target remains macOS 14.
- Final optimized run: **73 tests passed**, with `STANA_GUI_TESTS=1`, Swift warnings as errors and native `-Werror`.
- This includes 13 new deterministic window tests and 13 new native window tests, plus the existing suite.
- Native tests cover real fullscreen entry/exit, sheet result and parent-close cancellation, saved geometry, tab/child relationships, native style/constraints, retained custom chrome and accessory-editor composition/focus.
- Transparent native PNG was 320×240 with every alpha channel byte equal to zero; no opaque root background remained.
- External positive/misuse API fixtures passed, including unified-window authoring and rejection of writable state/platform sections.
- Runtime-fault fixtures and dependency/native-boundary checks passed.
- Counter, Preferences, Editable Collection and Window Configuration consumers built with Swift warnings as errors.

These are local automated checks, not a claim that the manual qualification matrix
or the minimum-macOS/Intel matrix has been completed.
