# Window configuration: accepted design and implementation plan

## Contract

One feature-based `STNWindow.Configuration` is the authoring interface. There are
no macOS/Windows/Linux sections. STN resolves the requested policy against its
host, applies supported settings, and ignores unavailable settings. Explicit
window actions, unlike configuration, report unsupported operations.

The interface covers creation, appearance, title bars, resizing, interaction,
behavior, workspaces, system metadata, toolbars and retained custom chrome.
Configuration accepts constants, signals and computeds. Title and initial content
size remain source-compatible. No raw native objects or arbitrary property bags
are part of this API.

Creation settings are frozen for one native lifetime. Changes are recorded as
`requiresReopen`; reopening reads the current source. Other settings update live.
Structural chrome updates wait for composition, resize/move, sheets and fullscreen
to finish. Latest desired configuration wins. Observed state is read-only and is
not written back into the policy source.

Unsupported, inapplicable and creation-only settings are inspectable through
`window.resolution`. Invalid values reject the update, retain the last valid
configuration and invoke the configuration error callback. Actions have typed
errors and async completion where the native operation is asynchronous.

## Code-change overview

| Subsystem | Responsibilities |
|---|---|
| Stana public API | Grouped configuration, reactive overloads, explicit actions, state/resolution outputs, toolbars, accessory definitions and move/resize/content wrappers |
| WindowController | Native ownership, resolution, creation policy, update deferral, command subscriptions, child/sheet lifetime and stable chrome surfaces |
| MountSession | Retained content, editing and semantic state; native pointer disposition and safe-content geometry |
| StanaPlatform | Stana-owned option/state/error records, resolved descriptors and platform-window contracts |
| StanaPlatformMacOS | Option translation, callback ownership, async operation cancellation, UTF-8 lifetimes and native chrome descriptors |
| CStanaMacOS | Window/panel classes, styles, controls, constraints, native movement/resizing, state notifications, tabs/sheets/children, toolbar/accessory hosting and frame persistence |
| Scene/input | Configurable root background, alpha-preserving drawing, exclusion-aware drag/resize hit testing and cancellation before native handoff |
| StanaTesting | Recording host exercising the production controller without a window server; configurable unavailable features |

The private C ABI moves to version 2. Native object pointers remain opaque handles;
records and strings are borrowed only during synchronous calls. Each custom chrome
surface has its own document, editor, raster and accessibility identity.

## Delivery and verification

1. Configuration and portable descriptors; controller/lifecycle integration.
2. Native creation, settings, state and explicit actions.
3. Frameless keyboard eligibility, movement/resizing, safe content and transparency.
4. Native relationships, chrome, metadata, displays and frame persistence.
5. Consumer fixtures, deterministic tests, native checks, example and documentation.

Completion evidence and the native capability matrix are maintained in
[Windows verification](../Verification/Windows.md). The public authoring guide is
[Window Configuration](../../Sources/Stana/Documentation.docc/WindowConfiguration.md).

## Boundaries

macOS is the only production host. The recording host is a test double, not a
Windows/Linux implementation. Future hosts implement the same resolver and
feature interface; unsupported policies are ignored without application-side
conditional compilation.

Native content-widget replacement, inherited responder plumbing, deprecated or
no-effect flags, rich-text tab titles, renderer/backing-store policy, and a
full document-application restoration framework are not window configuration.
Frame persistence and represented-resource metadata are included. Native sharing
is exposed as an operation, not as a claim of screenshot protection.
