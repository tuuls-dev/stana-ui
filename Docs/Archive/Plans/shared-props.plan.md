# Shared Configuration and Reactive Property Inputs

## Summary

Replace reactive overload matrices with generic property conversion, introduce reusable public capability groups, and migrate the full authoring facade. Preserve mount-once
declarative components, retained-node identity, and existing visual defaults.

This is a source-breaking cleanup without compatibility initializers. Font, padding, and frame become reactive.

## Public API

• Add @MainActor STNPropertyConvertible<Value> with an associated value type and asProperty() -> STNProperty<Value>.
• Add public, type-erased STNProperty<Value>, supporting constants, signals, and computeds without exposing engine records or subscription installation.
• Provide conformances in Stana for supported concrete values, STNSignal, STNComputed, and arrays. Allow custom conformances and explicit constant wrapping.
• Keep the conversion protocol unconstrained by Equatable; require equality only when installing equality-suppressed leaf properties. This preserves collection APIs supporting non-
Equatable rows and custom comparators.

• Keep writable STNBinding separate; editors and toggles still require bindings.

Introduce these public groups:

Group Fields
━━━━━━━━━━━━━━━━━━━━━━━━━━ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
STNLayoutProperties Reactive padding and frame
────────────────────────── ─────────────────────────────────────────────────────────────────────────────────────────────────
STNTextProperties Reactive font and foreground
────────────────────────── ─────────────────────────────────────────────────────────────────────────────────────────────────
STNAppearanceProperties Reactive background, opacity, border color/width, corner radius; static clipping and visibility
────────────────────────── ─────────────────────────────────────────────────────────────────────────────────────────────────
STNInteractionProperties Reactive enabled state; static inert state and existing pointer callbacks
────────────────────────── ─────────────────────────────────────────────────────────────────────────────────────────────────
STNLifecycleProperties Existing mount callback

Retain STNAccessibilityProperties as the accessibility group, with generic label conversion. Disposal remains scope-owned through STNComponentContext.

Groups contain optional overrides: omitted fields preserve each component’s defaults. Each group has one initializer, using typed optional defaults for generic inputs.

## Implementation

• Expose layout, appearance, interaction, lifecycle, and accessibility groups across ordinary visual components; expose text properties only on text-bearing controls. Keep
structural components and specialized window-region wrappers specialized.

• Keep unique inputs directly on component properties: content, spacing/alignment, actions, bindings, editor callbacks/options, transforms, backdrop effects, and drawing.
• Replace constant/signal/computed overload matrices throughout components, window properties, accessibility labels, and structural inputs with generic initializers. Retain
collection overloads that express different equality or identity semantics.

• Adapt existing NodeConfiguration and property installation rather than adding another node hierarchy. Components remain descriptions; retained records and lifetime scopes remain
internal.

• Initialize component defaults once, then apply specified group fields through shared helpers. Preserve button/editor padding, editor borders, and scroll/backdrop clipping
defaults.

• Move foreground, background, border color/width, and corner radius out of text-field Options into shared groups. Remove their writes from editor configuration and remove the
text-field background-installation exception. Keep editor-only settings in Options.

• Install reactive font, padding, and frame with layout, paint, and semantic invalidation, including ancestor measurement-cache invalidation. Preserve compositing-only opacity
updates, equality suppression, transaction batching, and disposal cancellation.

• Preserve validation of opacity, borders, radii, and frame constraints for both initial and subsequent values.

## Migration and Verification

• Begin with consumer compilation fixtures, then migrate examples, tests, benchmarks, README, DocC, and design documentation.
• Use explicit types where generic inference loses shorthand: STNColor.surface, STNFont.system(...), typed configuration constructors, and STNInsets literals where required.
• Compile constant/signal/computed combinations, including the former nine-way matrices and 27 backdrop combinations; cover omitted defaults, reusable groups, custom sources, and
non-Equatable collection rows.

• Retain negative fixtures for meaningless properties and writable-binding requirements; add wrong-value-type and unsupported-group cases.
• Test reactive font/layout changes against measurement, sibling positioning, hit testing, semantics, and editor geometry. Assert unchanged node IDs, mount counts, and builder
executions.

• Test editor appearance updates preserving focus, selection, marked text, and undo; verify editor-option updates do not overwrite shared styling.
• Verify omitted and empty groups preserve current defaults, and disposed components receive no later deliveries.
• Run just check; record native visual, VoiceOver, and IME verification separately.

## Assumptions

• Capability expansion is intentional where the existing visual-node model supports it; no ignored fields or inherited typography are introduced.
• Reactive callbacks, spacing, alignment, clipping, visibility, and inert state are outside this change.
• Preserve unrelated working-tree changes; no renderer redesign, release, or deployment is included.
