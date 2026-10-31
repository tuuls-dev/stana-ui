# Symbols

Compile your own SVG literals into portable vector assets, then style and animate retained symbol instances. SVG parsing happens in the build-host macro, never in the application. The current renderer is macOS-only; the asset data and public API are native-independent.

## Define and display an asset

```swift
import Stana

@MakeSTNSymbol
public struct AddIcon {
    private static let svg = #"""
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
         stroke-width="2" stroke-linecap="round">
        <path d="M5 12h14M12 5v14"/>
    </svg>
    """#
}

// In makeContent(in:):
STNSymbol(properties: .init(symbol: AddIcon.asset))
STNSymbol(properties: .init(
    symbol: AddIcon.asset,
    size: 20,
    color: STNColor.accent,
    strokeWidth: Optional(1.5),
    accessibility: .init(label: "Add")
))
```

The macro requires a non-generic struct outside generic types, with exactly one `static let svg` initialized directly from a string literal. Ordinary, multiline, and raw literals work; escapes are decoded. Interpolation, concatenation, variables, functions, computed properties, and file imports do not. `mirrorsInRTL` must be a Boolean literal and defaults to false. Rename any existing `asset` member.

The generated member is `public nonisolated static let asset: STNSymbolAsset`. It can cross package boundaries using only `import Stana`, even when its authoring type is actor-isolated or `svg` is private. Enclosing visibility still applies. Expansion contains typed geometry, not a runtime SVG constructor. Source strings can remain in binaries or debug information.

Assets are immutable, nonisolated, `Sendable`, and semantically `Equatable`, backed by shared storage. Equality includes normalized artwork, paints, viewBox, transforms, and RTL metadata; comments, IDs, metadata, and Swift type names do not matter. Assets have no SVG/data/file/URL initializer, registry, or string-name lookup.

## Reactive inputs and replay

`symbol`, `size`, `color`, `animation`, and `strokeWidth` accept constants, `STNSignal`, and `STNComputed`. Retain signals in your model or use mount-owned `context.state(initial:)`. Reading `.value` into a property initializer captures a constant rather than subscribing.

```swift
let asset: STNSignal<STNSymbolAsset> = context.state(initial: AddIcon.asset)
let playback: STNSignal<STNSymbolPlayback> = context.state(initial: .none)
let stroke: STNSignal<Double?> = context.state(initial: nil)
let request: STNSignal<UInt64> = context.state(initial: 0)

STNSymbol(properties: .init(
    symbol: asset, animation: playback, strokeWidth: stroke,
    accessibility: .init(label: "Activity")
))
STNSymbol(properties: .init(
    symbol: asset, animation: STNSymbolPlayback.loop(.rotate),
    accessibility: .init(label: "Background activity")
))
STNButton(properties: .init(text: "Replay", onActivate: {
    precondition(request.value < .max)
    STNTransaction.perform {
        request.value += 1
        playback.value = .once(.bounce, request: request.value)
    }
}))
```

The application owns request generations. Any different committed UInt64 is new, including a previously used value after an intervening request; Stana remembers only the last observed request. Equal requests do not replay. Latest committed inputs win; there is no queue or requirement to observe intermediate assignments.

| Effect | Duration | Whole-symbol paint effect |
| --- | --- | --- |
| `rotate` | 1 second | Clockwise `2πp` rotation around the fitted square center. |
| `pulse` | 1 second | Uniform scale `1 + 0.08 sin²(πp)`, without fading. |
| `bounce` | 0.6 seconds | Upward translation `0.12 × square side × sin²(πp)`. |

`.none` is the default. All effects support `.loop(effect)` and `.once(effect, request:)`. One-shots finish exactly at rest and release frame demand; loops have no inter-cycle delay. Effects never change measurement, baseline, hit targets, or semantic bounds. Two instances sharing an asset have independent clocks.

Asset replacement immediately cancels prior progress. Loops restart at zero; one-shots require a new request in that transaction. Changing a once effect without changing its request cancels rather than replays. Switching through none or loop retains the last once request. Styling, themes, and RTL do not restart progress. Removal disposes the clock; remounting starts a fresh lifetime.

Explicit hidden/collapsed ancestors and hidden/minimized/detached hosts pause playback. Resume adds zero elapsed time on the first frame, without catch-up. Hidden requests replace pending work at zero. Focus loss, opacity zero, disabled/inert state, viewport position, and occlusion do not count as hiding.

`environment.reducedMotion` cancels progress and consumes one-shot requests without saving them. Loops restart at zero when motion is permitted again; consumed one-shots need a new request. Labels and artwork still update. There is no per-symbol reduced-motion override. Calculator's symbol demonstration shows the system setting without changing its image labels.

## Styling, layout, and accessibility

- Size defaults to 24 logical points; finite nonnegative values only. Zero paints nothing. Text scaling does not implicitly change size.
- Intrinsic size is `size × size`, plus normal padding. Frames and constraints use ordinary layout rules. Artwork fits the centered square with side `min(size, content width, content height)`, then aspect-fits the viewBox. Larger frames add space; smaller constraints shrink without stretching.
- The baseline is the local bottom of that fitted square, including centering and top padding but excluding bottom padding. A zero-side square exports its center y-coordinate.
- Color defaults to themed `STNColor.text`, including the existing high-contrast resolution. It changes only `currentColor`; literal colors stay fixed. Black is not implicitly a template color.
- `strokeWidth: nil` preserves authored widths. `Optional(2.0)` overrides stroked paths in viewBox units before transforms. Zero disables strokes; an override never enables `stroke='none'`. Reactive optional signals/computeds work; a bare Double is not a second initializer overload.
- Invalid runtime size or stroke values are programmer-error preconditions, not backend diagnostics.
- `@MakeSTNSymbol(mirrorsInRTL: true)` mirrors artwork in RTL before the effect transform. Rotation direction remains clockwise. Layout, pointer coordinates, semantic bounds, and playback identity do not mirror or restart.
- Paint can overflow; clipping defaults off and normal ancestor/appearance clips apply. Damage includes old and new animated ink, including stroke overflow.
- No label means decorative, with no semantic image. A supplied label, including an empty string, creates one image. SVG title/desc, IDs, and type names never become accessibility labels. Symbols are not buttons; use existing text buttons for actions.

## Supported SVG V1

Names are case-sensitive. Use the SVG namespace `http://www.w3.org/2000/svg` consistently or leave all elements unnamespaced. Foreign or mixed element namespaces and qualified rendering attributes are rejected.

| Area | Accepted |
| --- | --- |
| Root | Exactly one `svg`, required finite `viewBox` with positive dimensions; negative origins allowed. Optional positive width/height do not determine component size. `preserveAspectRatio` absent or exactly `xMidYMid meet`. |
| Containers | `g`, inherited presentation, local transforms, composited group opacity; document paint order. |
| Shapes | `path`, `rect` including rx/ry defaults/clamping, `circle`, `ellipse`, `line`, `polyline`, `polygon`. Missing geometric values default to zero; negative dimensions/radii fail; zero-area primitives paint nothing. |
| Path commands | Absolute/relative M/L/H/V/C/S/Q/T/A/Z, repeated/implicit arguments, SVG separators and exponents. Reflected controls and relative coordinates resolve at compile time. Arc flags are 0/1; radii normalize by endpoint-to-center rules. Zero-radius arcs become lines; coincident endpoints add no arc. |
| Paints | `none`, `currentColor`, supported solid literals. Fill rule nonzero/default or evenodd. Open fills close without closing their strokes. |
| Strokes | Nonnegative width; butt/round/square caps; miter/round/bevel joins; miter limit at least 1. |
| Opacity | Local composited `opacity`; inherited fill/stroke opacity. Finite values in 0...1; out-of-range values fail. |
| Transforms | matrix, translate, scale, rotate with optional center, skewX, skewY; ordered SVG composition. Nonuniform transforms preserve local strokes. |
| Lengths | Unitless numbers or px, where px equals a viewBox unit. Path/transform/viewBox numbers are unitless. |
| Colors | #rgb, #rgba, #rrggbb, #rrggbbaa; comma-form rgb with integer RGB 0...255; comma-form rgba with those RGB values and alpha 0...1. Case-insensitive black, white, red, green (#008000), blue, transparent. |
| Inheritance | Fill, fill-rule/opacity, stroke, stroke-opacity/width/cap/join/miter, including explicit inherit. Root defaults: black fill, no stroke, opacity 1, width 1, butt, miter, miter limit 4, nonzero. Opacity itself is local. |
| Metadata | Unique nonempty IDs, data-*, aria-*, root role; text-only title/desc; comments, whitespace, and an optional leading XML declaration. Metadata is ignored at runtime. |

Everything else fails compilation, including style/class/color attributes, defs/use/symbol, text/images/external resources, CSS/SMIL animation, dashes/markers/paint-order, gradients, masks, clipping, filters, patterns, and non-scaling strokes. Percentages, physical/font-relative lengths, calc/var, other named colors/functions/spaces, DTDs, entity declarations, processing instructions, XInclude, and external entity expansion are unsupported. Only predefined and numeric XML character references are accepted. The compiler performs no resource reads or network access.

## Limits and failures

Compile-time limits per asset are 1 MiB decoded UTF-8, 4,096 elements including metadata, depth 64, 65,536 normalized path commands, 64 transforms per attribute, and absolute numeric inputs/derived geometry/transform coefficients at most 1e9. Nonfinite/overflowing values fail. Limits are not configurable, and input is never truncated.

Compile errors use the `StanaSymbol` domain with identifiers `invalidDeclaration`, `literalRequired`, `invalidXML`, `unsupportedFeature`, `invalidValue`, `budgetExceeded`, and `memberConflict`, anchored to the offending Swift declaration, literal, or argument. SVG diagnostics include line/column and do not dump entire assets.

Native preparation targets at most 0.25 device-pixel curve error and is bounded to depth 32 and 1,048,576 generated segments including stroke outlines. Prepared geometry uses a shared LRU bounded to 256 entries and 16 MiB; larger valid resources can be transient under the renderer budget. In-flight owners survive cache eviction. Tint, translation, rotation, and opacity do not invalidate base paths; stroke and required scale can invalidate relevant preparation. SVG is never reparsed.

Backend failures deliver `STNSymbolDiagnostic` through `onError` on MainActor after commit: `preparationFailed`, `resourceLimitExceeded`, or `renderingFailed`. Failed symbols paint nothing and release animation demand but preserve layout, interaction, and semantics. Errors deduplicate by asset generation and code; stale/disposed callbacks are discarded. Without a callback they use renderer diagnostics. Retrying requires a changed asset, relevant stroke/scale input, or renderer epoch. Recovered loops restart at rest; interrupted one-shots require a fresh request.

The public underscored `STNSymbolAsset` bridge types and `_compiled(version:viewBox:mirrorsInRTL:elements:)` support generated code across package boundaries. They are typed values, not an import format or a supported general drawing API. Bridge version 1 is source-versioned with Stana; invalid typed inputs and version mismatches precondition-fail deterministically.
