# Hybrid Rendering

Mix ordinary controls, worker-rasterized `STNCanvas` drawing, and GPU content in one retained paint order. The macOS host uses Metal by default. Application code still imports only `Stana`.

## GPU drawing

`STNGPUDrawing` records immutable, versioned rectangles, rounded rectangles, ellipses, indexed colored meshes, and round-joined polylines. Ordinary `STNColor` values resolve with the current theme. `STNExtendedColor` supplies finite scene-linear HDR RGB values (including values above one), with alpha in zero through one. Colors are authored straight; the renderer premultiplies them.

```swift
var drawing = STNGPUDrawing()
drawing.fillRect(.init(width: 240, height: 120), color: .surface, cornerRadius: 12)
drawing.strokePolyline(
	[.init(x: 10, y: 90), .init(x: 100, y: 20), .init(x: 230, y: 60)],
	color: STNExtendedColor(red: 0.2, green: 2, blue: 0.8),
	width: 3
)
STNGPUCanvas(properties: .init(drawing: drawing, layout: .init(frame: STNFrame(width: 240, height: 120))))
```

Supply accessibility properties or an accessible textual equivalent for meaningful charts; pixels do not create semantics automatically.

## Retained layers and frame callbacks

`STNLayer` isolates its children. Its affine `transform` and group `opacity` accept constants, signals, or computed values. Translation and opacity reuse unchanged foreground content. Rounded clipping and inverse-transformed hit testing use the same geometry projection. A singular transform draws no interactive area.

Use `context.onFrame(isActive:)` inside `makeContent(in:)` for mount-scoped animation. The callback receives `STNFrameTime.timestamp`, `targetTimestamp`, and `elapsed`, in seconds. Registrations run in order within one transaction. The first/resumed callback has zero elapsed time; hiding/minimizing pauses demand and resets elapsed time. Cancellation and scope disposal stop callbacks. Do not use the callback as evidence that its scene was displayed.

## Backdrop scope

`STNBackdrop` captures only earlier siblings in its nearest isolation context, evaluates an effect, then paints its own foreground. Later tooltips remain on top. Nested isolated groups start transparent: an effect inside a layer does not see content outside that layer.

```swift
STNZStack {
	STNGPUCanvas(properties: .init(drawing: drawing))
	STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 8),
			transform: STNAffineTransform.translation(x: 20, y: 20),
			layout: .init(frame: STNFrame(width: 180, height: 70)),
			appearance: .init(cornerRadius: 12)
		)
	) {
		STNText(properties: .init(text: "Foreground stays sharp", layout: .init(padding: STNInsets(12))))
	}
}
```

Move the backdrop itself. Wrapping only the backdrop in an otherwise empty isolated layer changes its source to that empty context. `.identity` is an exact no-op without foreground; `.blur(radius:)` is a normalized finite box blur in local logical points. These are authored effects, not native Liquid Glass parity.

## Application Metal programs

`STNGPUProgram` accepts `.metalSource(String)` or `.metalLibrary(Data)` loaded from application/package resources. It is explicitly trusted Metal, not a cross-platform shader language or an untrusted-code sandbox. Define named immutable buffers/textures, transient storage/targets, samplers, and temporal state slots. Render passes name vertex/fragment functions, attachments, draw counts, and optional UInt32 indices; compute passes declare dispatch dimensions. Bind each resource with its stage, slot, and access. Function constants are explicit.

Same-step producers form a validated acyclic graph. Read/write aliasing, missing resources, duplicate bindings, invalid dimensions, and multiple producers are rejected. Native reflection also checks used bindings and minimum buffer sizes, including replacements on a cached pipeline. Writable targets start clear/zero. Output must be finite premultiplied color in the declared encoding; alpha zero must have zero RGB.

`updatingResources` creates a fresh input version while retaining compatible pipelines and state. A `.state` binding with `previous: true` reads the prior successfully completed offscreen step; a write binding names distinct storage for the next step. All state slots publish atomically after GPU success. Presentation-only retries and unchanged output reuse do not step state. Changing a state slot/reset key, incompatible executable, or renderer epoch resets state. Compilation/binding replacement failures diagnose through `onError` and keep the prior valid output/program; an initially invalid program remains unavailable. GPU execution faults invalidate the epoch and trigger bounded recovery, never a silent raster fallback.

For a backdrop program, use `.backdrop(index:stage:)` for the read-only cropped source and `.backdropCoordinates(index:stage:)` for its mapping buffer. The mapping is seven consecutive `float4` values: source bounds, panel output bounds, local-to-context X/Y affine rows, context-to-local X/Y rows, and `(backingScale, sourceIsLinear, 0, 0)`. Bounds are context logical coordinates. Declare `samplingRadius` in local points; `nil` conservatively requests the full context. `Fixtures/API/Valid/HybridRendering.swift` is the compilation sample for a custom program. `Examples/Calculator` draws its curve with GPU polylines and ellipses and frosts its keys with backdrop blur. It does not ship a custom Metal shader.

## Color, capture, and diagnostics

Window configuration `renderingColorMode` is `.automatic`, `.sdr`, or `.extendedLinear`. HDR demand promotes automatic composition to extended-linear-sRGB half float; SDR output still receives the one final headroom-limited mapping. At headroom one, HDR-composite white is intentionally compressed; an all-SDR window preserves its original SDR white. Input textures explicitly declare encoded/linear sRGB and straight/premultiplied alpha. PQ/HLG and other primaries are not supported.

`try await window.capture()` returns a complete successful **offscreen** scene before display mapping: premultiplied BGRA8 or extended-linear RGBA16Float, tightly packed top-to-bottom rows and a scene revision. It is not a screen capture or proof of presentation. `displayMappedBGRA(headroom:)` performs explicit SDR export. Async capture/diagnostics do not synchronously wait for GPU work on the UI executor.

`try await window.renderingDiagnostics()` reports device/profile, counters, revision-tagged timing samples, errors, and the last confirmed positive native presentation observation. `handle.bounds()` remains current logical layout; `handle.presentationBounds()` separately reports acknowledged geometry and its status. Ordinary pending interaction uses last-confirmed geometry. Unknown changed regions gate location actions until recovery; completion alone never advances them. This is not scanout-atomic event targeting.

Run `just example` for the calculator, or `just test-gui` for the native GUI tests. `just benchmark-native persistent <report.json>` runs the restored mixed CPU/GPU workload from `Benchmarks` as a foreground app. Keep it visible, and run GPU validation separately from timing. Backend comparison evidence and limitations are recorded in `Docs/Verification/SwiftBackend.md`.
