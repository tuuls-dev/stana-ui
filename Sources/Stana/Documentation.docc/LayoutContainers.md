# Layout Containers

Arrange children side by side, vertically, or in overlapping layers.

## Overlay alignment

`STNZStack` overlays its children in declaration order; later children paint on top and receive hit tests first. Its size is the largest child on each axis plus padding, subject to its frame. Each child is centered vertically within the padded content rectangle.

Horizontal alignment uses ``STNZStack/Alignment``: `.leading`, `.center`, or `.trailing`. The default is `.center`, preserving the appearance of existing overlays that omit alignment. Leading and trailing follow the document's layout direction; center is unchanged in right-to-left layouts.

```swift
let alignment: STNZStack.Alignment = .leading
STNZStack(
	properties: .init(
		alignment: alignment,
		layout: .init(padding: STNInsets(12), frame: STNFrame(width: 124, height: 104))
	)
) {
	STNBox(properties: .init(layout: .init(frame: STNFrame(width: 10, height: 20)))) {}
	STNBox(properties: .init(layout: .init(frame: STNFrame(width: 40, height: 60)))) {}
}
```

For a 10-point-wide child in a 100-point-wide content rectangle, leading, center, and trailing produce horizontal offsets of 0, 45, and 90 points in left-to-right layouts. Leading and trailing swap in right-to-left layouts. Padding offsets the content rectangle; differently sized children are aligned independently within it.

ZStack has no spacing parameter or baseline alignment. `STNHStack` and `STNVStack` continue to use `STNAlignment` and retain their spacing behavior.

## Migrating ZStack properties

Remove `spacing:` from `STNZStack.Properties`; it previously had no effect. Existing inferred `.leading`, `.center`, and `.trailing` values remain valid, but explicit leading/trailing now affect placement.

An explicitly typed `STNAlignment` value can no longer be passed to ZStack. Change overlay-only declarations from `let alignment: STNAlignment = .leading` to `let alignment: STNZStack.Alignment = .leading`. If configuration is shared with a linear stack, keep separate typed values or explicitly switch over the shared value to map the three horizontal cases; `.firstBaseline` has no overlay equivalent. Keep `STNAlignment` for HStack/VStack.
