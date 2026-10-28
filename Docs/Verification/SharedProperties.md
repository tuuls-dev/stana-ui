# Shared Properties Verification — 2026-10-28

## Automated results

- Formatting and dependency/native-boundary checks passed.
- Strict Swift/native-warning test builds passed. The GUI-enabled run passed all 131 tests across seven test targets, including six new shared-property regression tests.
- External API fixtures passed: mixed constant/signal/computed inputs, the former nine-way matrices and 27 backdrop combinations, custom conversion, reusable groups, and non-`Equatable` rows.
- Negative fixtures rejected wrong source values, unsupported groups, read-only editor/toggle inputs, bindings used as read-only sources, removed editor appearance fields, and the existing invalid usage cases.
- All 13 isolated runtime probes produced expected diagnostics, including invalid initial and updated padding, frame, opacity, border width, and corner radius.
- Counter, Preferences, EditableCollection, WindowConfiguration, TextFields, and HybridRendering built with Swift warnings treated as errors.
- Release build passed with Swift warnings treated as errors.

The standard `just check` stages completed after correcting one remaining GPU drawing shorthand in the consumer fixtures. Inside the restricted execution environment, SwiftPM required writable temporary module caches and `--disable-sandbox` to avoid nesting its manifest sandbox. These runner-only adjustments are not repository changes. The initial sandboxed GUI attempt could not acquire a Metal device; rerunning `STANA_GUI_TESTS=1 swift test -Xswiftc -warnings-as-errors -Xcc -Werror` with native-service access passed.

## Behavior covered

- Empty and partial groups preserve component-specific padding, backgrounds, borders, and clipping defaults.
- Conversion does not eagerly evaluate computeds; shared groups install independent mount-owned subscriptions.
- Font, padding, and frame updates remeasure intrinsic ancestors, reposition siblings, update semantic bounds and hit testing, and preserve node IDs, mount counts, and builder execution counts.
- Batched updates do not publish intermediate geometry; equal values suppress redundant deliveries.
- Shared editor styling preserves retained editor identity, focus, selection, marked text, revision, and undo; editor-option updates do not overwrite shared styling.
- Removed components stop observing shared sources; mount callbacks remain post-publication.
- Existing opacity/compositing, structural identity, text services, rendering, native chrome, and accessibility-provider tests continue passing.

Native Preferences and mixed-direction text-field captures from this run were visually inspected. Padding, borders, font sizing, left/right alignment, Arabic shaping, and emoji remain intact. The captures are local test artifacts at `/tmp/stana-preferences-verification.png` and `/tmp/stana-text-fields-verification.png`.

## Manual qualification

No new human VoiceOver or real input-method session was performed. Automated marked-text, native text-service, geometry, and accessibility-provider checks are not a substitute for those checks. The pending manual scenarios in [Text-field verification](TextFields.md) remain pending.

See the [migration guide](../../Sources/Stana/Documentation.docc/SharedProperties.md) for the source-breaking authoring changes.
