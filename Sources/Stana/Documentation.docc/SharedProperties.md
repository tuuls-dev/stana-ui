# Shared Properties

Reuse configuration without changing Stana’s mount-once composition model.

## Capability groups

Ordinary visual components accept `layout`, `appearance`, `interaction`, `accessibility`, and `lifecycle`. Text, buttons, toggles, and text fields also accept `textStyle`. Structural components such as `STNIf`, `STNForEach`, and `STNSpacer`, and specialized window-region wrappers retain their specialized APIs.

| Group                        | Configuration                                                                                   |
| ---------------------------- | ----------------------------------------------------------------------------------------------- |
| `STNLayoutProperties`        | Reactive padding and frame                                                                      |
| `STNTextProperties`          | Reactive font and foreground                                                                    |
| `STNAppearanceProperties`    | Reactive background, opacity, border color/width, corner radius; static clipping and visibility |
| `STNInteractionProperties`   | Reactive enabled state; static inert state and pointer callbacks                                |
| `STNAccessibilityProperties` | Reactive label; static hint, heading, and grouping                                              |
| `STNLifecycleProperties`     | Mount callback, after publication                                                               |

Group fields are overrides, not replacement defaults. An omitted field—including a field omitted inside an explicitly supplied empty group—retains the receiving component’s default. For example, supplying only a button’s frame preserves its padding, and supplying only a text field’s background preserves its border.

```swift
let font = STNSignal(STNFont.system(size: 16))
let padding = STNSignal(STNInsets(12))
let layout = STNLayoutProperties(padding: padding)
let textStyle = STNTextProperties(font: font, foreground: STNColor.text)

STNVStack {
	STNText(properties: .init(text: "Shared", layout: layout, textStyle: textStyle))
	STNButton(
		properties: .init(text: "Save", layout: layout, textStyle: textStyle, onActivate: {})
	)
}
```

Sharing a group does not share a node or its lifetime. Each mounted component owns its subscriptions. Font, padding, and frame updates invalidate layout, paint, and accessibility geometry; ordinary property updates do not rerun builders or replace retained nodes. Opacity updates remain compositing-only. Removing a component cancels its subscriptions.

Text styling is local to a text-bearing component, not inherited by descendants. Component-specific properties remain direct arguments: bindings, actions, content, stack spacing/alignment, editor options/callbacks, drawings, transforms, and backdrop effects.

## Frame maximums and filling

An omitted `STNFrame` maximum has the numeric value `.infinity`, but does not request filling. Explicitly supplying or assigning `.infinity` to `maxWidth` or `maxHeight` requests filling on that axis when the available size is bounded. Assigning a finite maximum clears that axis's fill intent; it caps the size without requesting growth. The other axis is unchanged. Fixed `width` and `height` take precedence over fill allocation, and unbounded proposals remain content-sized subject to the frame's minimums.

```swift
var frame = STNFrame()          // Content-sized; both maximums read as infinity.
frame.maxWidth = .infinity      // Same fill intent as STNFrame(maxWidth: .infinity).
frame.maxWidth = 200            // Cap width at 200 without filling.
frame.maxHeight = .infinity     // Request vertical filling only.

let sizing = STNSignal(frame)
STNBox(properties: .init(layout: .init(frame: sizing))) {}
sizing.value.maxWidth = .infinity
```

Copies retain fill intent. Equality and hashing distinguish an omitted maximum from an explicitly infinite maximum, even though their numeric values match, so reactive frame updates observe changes in fill intent. Replacing the value with `STNFrame()` restores the omitted-maximum behavior.
Linear stacks accept spacing and `STNAlignment`. ZStack accepts only `STNZStack.Alignment` and defaults to centered overlays; see <doc:LayoutContainers> for placement and migration guidance.

## Generic reactive inputs

`STNPropertyConvertible<Value>` converts an input with `asProperty()` into `STNProperty<Value>`. Supported ordinary values, signals, and computeds conform. Conversion preserves the source without reading its current value. Reading a signal’s `.value` yourself during construction still captures a constant.

The conversion protocol does not require equality. Leaf subscriptions require equatable values, while keyed collections retain their explicit content-comparison and observable-reference identity rules. Writable fields still take `STNBinding`; bindings are not read-only property sources.

Wrap a custom constant in `STNProperty(value)`, or implement the protocol by returning a wrapped constant, signal, or computed. No node records or subscription-installation capabilities are exposed by this protocol.

## Migrating flat properties

This change replaces flat styling parameters and their overload matrices; there are no compatibility initializers.

| Previous parameter                                                           | New location                     |
| ---------------------------------------------------------------------------- | -------------------------------- |
| `padding`, `frame`                                                           | `layout: .init(...)`             |
| `font`, `foreground`                                                         | `textStyle: .init(...)`          |
| `background`, `opacity`, border fields, `cornerRadius`, `clip`, `visibility` | `appearance: .init(...)`         |
| `isEnabled`, `inert`, pointer callbacks                                      | `interaction: .init(...)`        |
| `onMount`                                                                    | `lifecycle: .init(onMount: ...)` |

Generic source parameters need explicit types for domain-specific shorthand: use `STNColor.surface`, `STNFont.system(...)`, `STNFrame(...)`, and `STNInsets(12)` instead of `.surface`, `.system(...)`, `.init(...)`, or a bare padding literal. Ordinary string, Boolean, and Double literals still work. Groups themselves have concrete contextual types, so `layout: .init(...)` remains supported. Omit optional group fields rather than passing an untyped `nil`.

Text-field `Options` no longer contain foreground, background, border color/width, or corner radius. Move them to the shared groups. If an options signal previously drove both styling and editor settings, split it into shared styling sources and the remaining editor options, batching related changes with `STNTransaction.perform`. Updating options never overwrites shared styling or resets selection, composition, focus, or undo unless an editor-specific operation requires it, such as entering read-only mode.

Window configuration and text-field options are also generic inputs: use `STNWindow.Configuration(...)` and `STNTextField.Options(...)` when constructing their constant values explicitly. Commands, accessibility labels, frame callback activation, and structural inputs use the same conversion protocol.

Scoped cleanup remains `STNComponentContext.onDispose`; the lifecycle group does not introduce a second cleanup mechanism.
