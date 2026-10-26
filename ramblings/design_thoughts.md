# Stana — Production Architecture for a Retained Native UI Engine

**Status:** Implementation specification; no implementation or benchmark evidence exists in this repository yet

**Revision:** Production-readiness and properties-first API revision of `design_v2.md`, 2026-10-21

**Primary language:** Swift 6 language mode; proposed minimum toolchain Swift 6.4, exact patch pinned at M0

**Public type prefix:** `STN`

> **Design thesis:** Stana is a cross-platform, retained-mode UI engine. Swift builders *construct* a persistent tree; they are not functions that rerun whenever state changes. Signals bind to concrete node properties, so ordinary updates avoid component reconciliation entirely. Layout, paint, input, and accessibility are incrementally maintained projections of the same document.

## 0. How to use this specification

**Production-ready is a release outcome, not a property established by this document.** This revision specifies contracts, failure behavior, evidence requirements, and a staged implementation path. Performance, platform support, and accessibility claims remain unvalidated until their gates pass.

The words **must**, **should**, and **may** express Stana's own requirements, recommendations, and optional features. They do not imply certification by an external standard. Code blocks are **proposed API sketches or pseudocode**, not a compilable SDK; examples with the same type name are separate sketches.

### 0.1 Decision baseline

| Area | Default for implementation | Promotion/change gate |
|---|---|---|
| Product scope | Standalone desktop windows; macOS, Windows, Linux are target platforms, not current supported platforms | Per-platform qualification in §14; no blanket cross-platform release claim |
| Runtime | One UI writer on `@MainActor`; synchronous logical commits; demand-driven computeds | Deterministic graph, transaction, disposal, and reentrancy tests |
| Node storage | Class-backed records for M1; opaque identity API permits arena migration | Adopt arena only if equivalent workloads show a useful memory/latency improvement |
| Graphics | Skia evaluation behind a Stana-owned C ABI; raster reference renderer first | Verify exact revision, GPU backend, packaging, and recovery per OS at M0/M4 |
| Accessibility | AccessKit C adapter is the preferred integration candidate | Validate action, text, callback-thread, and lifecycle coverage; native shim where necessary |
| Text | Dedicated paragraph/shaping/editing subsystem, not renderer string drawing | Unicode, IME, screen-reader editing, and selection gates |
| Layout | Box, stacks, overlay, scroll; explicit measure/place contract | Grid and virtualization only after baseline correctness |
| Visual language | Stana-themed widgets that honor platform settings and interaction conventions | Cross-platform interaction and accessibility review |
| Deferred | Mobile, rich text, web compatibility, embedded-host product, plugin ABI | Separate proposals; not implicit v1 commitments |

These are design defaults, not user-selected dependency commitments. Alternatives and decisive experiments are recorded in §16.

### 0.2 Reading map

- **Architecture and API:** §§1–5.
- **Application/library authors:** custom-component guide and examples (§18).
- **Normative runtime contracts:** signals/transactions (§6), layout (§7), rendering (§8), accessibility (§9), input/text (§10), concurrency/lifecycle (§11).
- **Delivery:** packages and native boundaries (§12), verification and budgets (§13), qualification stages (§14), risks and decisions (§§15–16).
- **Evidence:** research-to-design rationale and primary-source catalogue (§17), reviewed on 2026-10-21. Foundational papers are deliberately retained alongside current platform documentation.

## 1. Goals and constraints

### Goals

1. **Persistent identity within a mount.** Property bindings preserve mounted nodes; structural replacement/disposal ends descendant identity, even when a keyed row scope survives (§3.5).
2. **Fine-grained reactivity.** State updates change the smallest possible set of dependent properties.
3. **Native host, custom UI.** Create an OS window and render into its native graphics surface.
4. **Cross-platform core.** Core tree, layout, signals, semantics, and scene representation contain no OS UI dependencies.
5. **Accessibility from the first usable build.** A first-class semantic tree provides native screen-reader, keyboard, and action support.
6. **Declarative ergonomics.** Read component properties before their children, without trailing modifier chains or a virtual-DOM rerender model.
7. **Testability.** Headless layout, pixel snapshots, semantic tree snapshots, mutation counters, and deterministic scheduling.
8. **Performance transparency.** Measure nodes touched, allocations, layout work, paint damage, and input-to-present latency.

### Non-goals for v1

- Browser compatibility, HTML parsing, full CSS, or JavaScript execution.
- A global `body()`/render loop that rebuilds components after state changes.
- Pixel-identical native font metrics and text controls on every operating system.
- A generic animation framework before layout, input, and accessibility are correct.

### Architectural invariants

- Updating `STNSignal` **does not remount or reexecute the original builder closure**.
- A node can be updated without replacing its siblings, parent, or children.
- Removal explicitly disposes signal subscriptions, event handlers, semantic nodes, and GPU resource references.
- All authoritative document mutations happen on one serialized UI executor.
- Accessibility state is a first-class runtime output, not inferred from pixels.
- A text change may affect ancestors or siblings **when real layout dependencies require it**; "fine-grained" never means skipping necessary work.
- Every committed logical revision has internally consistent properties, structure, focus, and semantic data. Rendering may lag; it cannot redefine authoritative state.
- A dropped visual snapshot never loses document mutations, accessibility actions, or damage needed to reach the latest image.
- Incremental projections must match their from-scratch equivalents for the same document, environment, and backend.
- No user callback observes a half-applied structural edit, and no logical commit suspends with `await`.

### 1.1 Proposed contribution and closest alternatives

Stana proposes an **integration and authoring model**, not the invention of retained trees, stable identity, signals, or incremental computation: mount-once Swift composition, explicit property/structural bindings, scope-owned lifetimes, and one document with specified input/semantic/presentation contracts. Its research hypothesis is that this combination reduces update work while keeping identity and lifetime behavior understandable. Neither superiority nor ergonomic simplicity is established here.

| Closest alternative | Existing capability / relevant distinction | Decisive comparison |
|---|---|---|
| Qt Quick/QML | Dependency-tracked property bindings already update object properties; this is a close reactive desktop comparison, not a full-tree-rebuild straw man | Equivalent editable desktop workloads; include graph, layout, text, semantics, memory, and native integration costs |
| SwiftUI | Explicit/structural identity, lifetime, and dependencies already preserve state across view-value updates; reevaluating a description does not imply destroying every control | macOS authoring/lifetime tasks and matched application outcomes; report platform and renderer differences, not just builder counts |
| Simple retained full-recompute reference | Preserve the same mounted controls, but reevaluate all demanded bindings and perform uncached full layout/scene projection at each commit | Isolate incremental bookkeeping benefits/costs without confusing recomputation with remounting |

The capability descriptions are grounded in [Qt's property-binding documentation](https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html) and [Apple's identity/lifetime/dependencies explanation](https://developer.apple.com/videos/play/wwdc2021/10022/). The proposed comparisons are Stana experiments (§13.5), not findings from those sources. A single-writer retained engine may lose on cold mount, high fanout, or nearly full-document changes; those are required workloads, not exclusions. Compare native interaction and accessibility outcomes as well as update time. A custom renderer and explicit bindings do not by themselves establish novelty, performance, or usability.

---

## 2. Overall architecture

```text
                         Swift application
                                │
                  STNWindow { ...builder... }
                                │ mount once
                                ▼
                      ┌────────────────────┐
OS events ───────────►│    STNDocument     │◄───── STNSignal / STNComputed
                      │ retained node arena │       dependency graph
                      └─────────┬──────────┘
                                │
                ┌───────────────┼────────────────┐
                ▼               ▼                ▼
          STNLayoutEngine  STNSceneBuilder  STNSemanticTree
                │               │                │
          layout caches    paint records     accessibility deltas
                │               │                │
                └───────────────┤                ▼
                                ▼         STNAccessibilityBridge
                          STNRenderer           │
                                │        macOS / Windows / Linux
                           GPU or CPU
                                │
                         native OS surface
```

**Threading model:** The tree, signals, focus, and input mutate on an `@MainActor` UI executor. A renderer worker may consume immutable scene snapshots later. Never hand mutable `STNNodeRecord` references to that worker. Native accessibility queries use adapter-owned committed state; actions enter the UI executor without synchronous cross-thread wait cycles. Main-actor isolation does not itself integrate a Windows/Linux native event loop; §11 requires an explicit host-loop spike. Swift's isolation and `Sendable` rules are the baseline, not a substitute for auditing C/Rust/C++ boundaries. See the [Swift concurrency guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html).

### Pipeline for one signal write

```text
stnCount.value += 1
  └─ invalidate computed values that read stnCount
       └─ recompute only observed consumers
            └─ compare new value with old bound property
                 └─ update STNText.text
                      ├─ mark text measurement dirty
                      ├─ propagate layout if size could change
                      ├─ invalidate old/new painted bounds
                      └─ emit semantic value/name update if needed
                           └─ logical commit; schedule/coalesce visual work
```

There is **no step that rebuilds the entire widget tree**.

---

## 3. Public Swift API

The examples here are **proposed syntax**. They are intended to establish API contracts, not to claim the functions already exist or form a compiling package.

Unless a full function is shown, fragments assume an `@MainActor` application setup function. A builder executes once **per mount**, not once per process: explicit removal/recreation and structural scopes can execute new builders. Reading `signal.value` in an ordinary builder captures a value; only a signal/computed binding or explicit structural primitive establishes ongoing observation. Debug tooling should warn about unbound reactive reads during construction.

### 3.0 Properties-first authoring contract

**Configure first, then compose children.** Every built-in node component exposes a component-specific nested `Properties` value, supplied through the labelled `properties:` initializer argument. `STNWindow` uses the same convention. Swift infers the concrete type in `properties: .init(...)`; these are ordinary typed initializer arguments, not a dictionary or a custom language embedded in a closure. Bare `name: value` entries inside `{ ... }` are not Swift configuration syntax.

```swift
STNBox(properties: .init(
    background: .surface,
    cornerRadius: 12
)) {
    STNText(properties: .init(text: "Properties come before children"))
}
```

The public initializer shapes are `STNBox(properties:content:)` for a container and `STNText(properties:)` / `STNButton(properties:)` for leaves. Child closures use `@STNBuilder`; properties are not result builders. The concrete `Properties` type exposes only inputs meaningful for that component. Required content or bindings have no fabricated defaults; optional configuration retains the component's documented defaults. Components whose properties all have defaults may omit the argument, for example `STNSpacer()` or `STNHStack { ... }`.

| Input category | Properties-first representation |
|---|---|
| Content | `text:`, `image:`, or other component-specific named input; no positional title/text overload |
| Editable state | `value: stnName.binding`, `isOn: stnEnabled.binding`; retain explicit `STNBinding<Value>` types |
| Layout and appearance | Applicable fields such as `alignment:`, `spacing:`, `padding:`, `frame: .init(...)`, `background:`, `cornerRadius:`, `font:`, `opacity:` |
| Accessibility | `accessibility: .init(label: ..., hint: ..., heading: ..., group: ...)`, using typed `STNAccessibilityProperties` |
| Actions and events | `onActivate: { ... }`, `onPointerDown: { event in ... }`, and other applicable callbacks |
| Mount notification | `onMount: { handle in ... }`, with the post-attachment/stale-handle contract in §3.6 |

Use the same field names, value types, and defaults for shared capabilities across component-specific `Properties` types. Accessibility fields are optional overrides: omitting them keeps built-in semantics, `heading` supplies a heading level, and `group: true` requests semantic grouping. They do not require applications to restate a button's role or action. Nonapplicable fields must fail type checking rather than being ignored. Do not use stringly typed property bags, `Any`, or dynamic member lookup to approximate this API.

**All component callbacks belong in properties.** In particular, buttons use `onActivate:` rather than a trailing action closure. Application callbacks are `@MainActor`; storing them in a properties value does not invoke them during construction, measurement, or painting. Container trailing closures contain only child content. `STNIf` and `STNForEach` are structural primitives, not configurable render nodes: retain their explicit conditions, collections, keys, and branch/row builders (§3.5).

**Properties preserve explicit reactivity.** Bindable fields accept a constant, `STNSignal<Value>`, or `STNComputed<Value>` through typed `Properties` initializer overloads, normalizing to a typed property source. For example, `STNText.Properties` must support `text:` overloads for `String`, `STNSignal<String>`, and `STNComputed<String>`; a bindable accessibility label follows the same rule. These are real overloads, not implicit Swift conversions; implementation must provide the combinations used by public examples. Two-way fields still require `STNBinding<Value>`, not a read-only computed. Passing `signal.value` instead captures a constant. No component gains implicit observation of arbitrary Swift reads.

A properties value is a mount description, not a live node handle. Mounting installs its individual property bindings and scope-owned handlers once. Updating a bound source changes only the associated retained property and required projections; it does not reexecute a properties initializer, child builder, or `makeContent`. Mutating or replacing a detached configuration value does not update an already mounted node. Signal transformations such as `.map`, explicit transactions, imperative handle operations, and component-context lifetime methods remain ordinary APIs; the prohibition is on **component modifier chains**, not all method calls.

**Property argument order is not an effects pipeline.** Layout/style fields describe one node with fixed semantics (§7.5), regardless of any initializer overload. Use nested `STNBox` components when different layers, bounds, or order-sensitive effects are needed; do not reintroduce a modifier list inside properties. This proposal replaces the earlier positional/configuration initializers and trailing component modifiers. There is no shipped SDK to preserve; legacy overloads are not required (§12.3).

### 3.1 Hello window

```swift
import Stana

@MainActor
func stnLaunch() {
    let stnWindow = STNWindow(properties: .init(
        title: "Hello, Stana",
        size: .init(width: 800, height: 600)
    )) {
        STNVStack(properties: .init(
            alignment: .center,
            spacing: 16,
            padding: 24,
            frame: .init(maxWidth: .infinity, maxHeight: .infinity)
        )) {
            STNText(properties: .init(
                text: "Hello, world!",
                font: .system(size: 28, weight: .semibold)
            ))

            STNButton(properties: .init(
                text: "Continue",
                onActivate: { print("Clicked") }
            ))
        }
    }

    STNApplication.run(windows: [stnWindow])
}
```

`STNWindow` creates the OS window; its builder mounts the root node once. `STNRenderer` paints into the attached OS surface.

### 3.2 Signals update properties, not components

```swift
let stnCount = STNSignal(0)

let stnWindow = STNWindow(properties: .init(title: "Counter")) {
    STNVStack(properties: .init(spacing: 12, padding: 20)) {
        STNText(properties: .init(
            text: stnCount.map { "Count: \($0)" },
            font: .system(size: 24)
        ))

        STNButton(properties: .init(
            text: "Increment",
            accessibility: .init(hint: "Increases the count by one"),
            onActivate: { stnCount.value += 1 }
        ))
    }
}
```

**After a click:** the text binding evaluates again; its mounted `STNText` node receives a new text value. Neither the parent builder nor any component's properties initializer is executed again, and no button is remounted. Layout may still run where the changed text measurement requires it.

### 3.3 Use computed state for derived values

```swift
let stnPrice = STNSignal(120.0)
let stnQuantity = STNSignal(2)
let stnTotal = STNComputed {
    stnPrice.value * Double(stnQuantity.value)
}

STNVStack(properties: .init(spacing: 8)) {
    STNText(properties: .init(
        text: stnTotal.map { "Total: \($0.formatted(.currency(code: "USD")))" }
    ))

    STNButton(properties: .init(
        text: "Add item",
        onActivate: { stnQuantity.value += 1 }
    ))
}
```

`STNComputed` tracks *actual reads*, caches its last value, and updates dependencies when conditional computation branches change.

### 3.4 Explicit two-way binding

```swift
let stnName = STNSignal("")

STNVStack(properties: .init(spacing: 12)) {
    STNTextField(properties: .init(
        value: stnName.binding,
        placeholder: "Your name",
        accessibility: .init(label: "Full name")
    ))

    STNText(properties: .init(text: stnName.map { "Hello, \($0)" }))
}
```

Input composition and selection live in the text-editing node. Each committed edit updates the signal; uncommitted preedit text does not, by default. The mirrored text property then updates through its subscription. Submit/Return is a separate action, not the only time the binding changes. External writes during composition follow the explicit policy in §10.3.

### 3.5 Structural dependencies: conditions and lists

Structural changes are the exception to pure property binding. They require **localized reconciliation** at the owning scope.

```swift
let stnSignedIn = STNSignal(false)

STNIf(stnSignedIn) {
    STNText(properties: .init(text: "Welcome back"))
} else: {
    STNButton(properties: .init(
        text: "Sign in",
        onActivate: { stnSignedIn.value = true }
    ))
}
```

```swift
struct STNTodo: Identifiable, Equatable {
    let id: UUID
    let title: String
}

let stnTodos = STNSignal<[STNTodo]>([])

STNForEach(stnTodos, id: \.id) { stnTodo in
    STNText(properties: .init(text: stnTodo.title))
}
```

Only the `STNIf`/`STNForEach` child region changes. **A stable key preserves the keyed scope, not necessarily its interactive descendants. Prefer stable observable-row bindings for editable collections.** Value rows are convenient for read-only snapshots; they are not the default recommendation for editors.

For v1, `STNIf` disposes its inactive branch and mounts the newly selected branch; switching back does not restore disposed local state. List keys must be unique within one owning scope, stable for the item's logical lifetime, and independent of its position. Duplicate keys reject the scope update before mutation. Reusing a key for a different logical item is application misuse.

**Value-item comparison and replacement:** the overload above requires `Item: Equatable` and compares the last mounted item with the new item using `==`, separately from key matching. A non-`Equatable` overload requires an explicit pure `contentEquals: (Item, Item) -> Bool`; `Identifiable` alone is insufficient. Equality must cover every mount-captured input whose change should be displayed, including closure configuration. Equal items retain their old descendants and captured values; unequal items replace the entire child subtree under the surviving keyed scope. Array-signal equality (§6.1) is an earlier gate: it must not suppress an update that row comparison needs to see. Mutable reference payloads are not value-item change detection.

| Same key, operation | Descendant and lifetime consequences |
|---|---|
| Value item compares equal; insert/move elsewhere | Existing descendants remain; no row-builder rerun |
| Value item compares unequal | Dispose old descendants, then mount replacements. Editing focus is repaired, not preserved by identity; selection, composition, undo, and child-local state are lost. Descendant-scoped tasks/subscriptions are cancelled; replacement mount work starts anew |
| Stable observable row; one property changes | Update that property's bindings, retaining the row and editor nodes, local state, and task scopes unless an explicit nested structural change removes them |

**Preferred editable-row sketch:** `observableRows:` is a distinct overload for reference models with stable per-property signals. The same key must retain the same model instance (`===`); a different instance under an existing key rejects the plan as `rowIdentityChanged` before mutation. Deliberate replacement requires removal/disposal followed by a new mount. It never silently rebinds a builder's captured reference.

```swift
@MainActor
final class STNTodoRow: Identifiable {
    nonisolated let id: UUID
    let title: STNSignal<String>
    let isDone: STNSignal<Bool>

    init(id: UUID, title: String) {
        self.id = id
        self.title = STNSignal(title)
        self.isDone = STNSignal(false)
    }
}

let stnRow = STNTodoRow(id: UUID(), title: "Draft")
let stnRows = STNSignal<[STNTodoRow]>([stnRow], equals: { old, new in
    old.count == new.count && zip(old, new).allSatisfy { $0.0 === $0.1 }
})

STNForEach(observableRows: stnRows, id: \.id) { stnRow in
    STNHStack {
        STNTextField(properties: .init(
            value: stnRow.title.binding,
            accessibility: .init(label: "Title")
        ))
        STNToggle(properties: .init(text: "Done", isOn: stnRow.isDone.binding))
    }
}

// A model update while the title editor is focused/composing:
stnRow.isDone.value = true
```

The last write changes a sibling control, not the title buffer or list membership. The editor must retain its `STNNodeID`, focus, selection/affinity, marked-text/composition session, undo history, and edit revision; neither row builder nor scope-owned task restarts. Layout may move the editor without replacing it. Qualification fixtures capture those identities/states, apply the sibling write and a keyed reorder, and assert preservation (§13.4). A separate unequal-value-row fixture asserts disposal/reset, including task cancellation. Updating `title` externally is a different case governed by §10.3's composition policy; stable identity does not override edit-conflict rules. Removing/evicting the row still ends its lifetime (§7.6).

### 3.6 Imperative node access remains possible

```swift
STNButton(properties: .init(
    text: "Save",
    accessibility: .init(label: "Save document"),
    onMount: { stnHandle in
        // Runs only after attachment; focus is applied when the window is eligible.
        try? stnHandle.requestFocus()
    },
    onActivate: { stnSave() }
))
```

Builders produce single-mount descriptions; they do not expose a live handle before attachment. The optional mount callback receives a stable, document-scoped handle. Queries/mutations on a stale handle return a typed `nodeDisposed` error; focus requests can also fail as `notFocusable`. Do not silently retarget a recycled slot. All handle operations are UI-actor isolated; internal slot indices and mutable records stay private.

---

## 4. Component catalogue

| Public component | Role |
|---|---|
| `STNBox` | Layout/style container: width/height, padding, border, background, clip |
| `STNHStack` | Horizontal sequential layout |
| `STNVStack` | Vertical sequential layout |
| `STNZStack` | Layered children |
| `STNSpacer` | Flexible empty space, omitted from semantic tree |
| `STNGrid` | Rows/columns and named grid placement |
| `STNText` | Shaped and selectable display text |
| `STNImage` | Bitmap/vector image with optional accessible description |
| `STNButton` | Accessible clickable action, keyboard activation |
| `STNToggle` | On/off control with checked state |
| `STNTextField` | Single-line editing, caret, selection, IME, accessibility text APIs |
| `STNTextEditor` | Multiline editing; deferred beyond the baseline text-field milestone |
| `STNScrollView` | Scrollable clipped viewport with semantic scroll actions |
| `STNCanvas` | Custom drawing component; **not** the window-level graphics surface |
| `STNIf` / `STNForEach` | Localized structural scopes |
| `STNLazyVStack` / `STNList` | Virtualized collection components; later milestone |
| `STNFocusScope` | Keyboard/focus grouping |

This catalogue describes intended vocabulary, not a promise that all components ship at the same stage. Grid, selectable display text, multiline editing, advanced custom primitives, and virtualization require their own capability qualification; the first usable build is the vertical slice in §14. Application-defined components compose these same primitives through the public extension model in §18.

Use `STNVStack` and `STNHStack` instead of `STNVertical` and `STNHorizontal`: the names make the layout role explicit. Keep `STNSurface` reserved for an OS/render integration abstraction, rather than a user component.

### Example: complete settings panel

```swift
let stnNotifications = STNSignal(true)
let stnUsername = STNSignal("Alloys")

STNBox(properties: .init(
    background: .surface,
    cornerRadius: 12
)) {
    STNVStack(properties: .init(
        alignment: .leading,
        spacing: 20,
        padding: 24
    )) {
        STNText(properties: .init(
            text: "Preferences",
            font: .system(size: 24, weight: .bold),
            accessibility: .init(heading: 1)
        ))

        STNHStack(properties: .init(spacing: 12)) {
            STNText(properties: .init(text: "Username"))
            STNSpacer()
            STNTextField(properties: .init(
                value: stnUsername.binding,
                accessibility: .init(label: "Username")
            ))
        }

        STNToggle(properties: .init(
            text: "Notifications",
            isOn: stnNotifications.binding
        ))

        STNHStack {
            STNSpacer()
            STNButton(properties: .init(
                text: "Save",
                accessibility: .init(hint: "Saves your preferences"),
                onActivate: { stnSavePreferences() }
            ))
        }
    }
}
```

---

## 5. Retained document: identity and memory model

### 5.1 Opaque generational identity; storage chosen by measurement

Start with document-owned `final class` records to simplify M1 correctness. An arena can later reduce per-node allocation and improve locality, but those are hypotheses to measure, not guaranteed wins. Identity and lifecycle contracts must not depend on storage choice.

```swift
public struct STNNodeID: Hashable, Sendable {
    // Module-internal fields; applications cannot manufacture IDs.
    let document: STNDocumentID
    let slot: Int
    let generation: UInt64
}

struct STNNodeRecord {
    var parent: STNNodeID?
    var children: [STNNodeID]
    var kind: STNNodeKind
    var dirty: STNDirtyFlags
    var layout: STNLayoutBox
    var styleVersion: UInt64
    var contentVersion: UInt64
}

@MainActor
final class STNDocument {
    private var stnSlots: [STNNodeRecord?] = []
    private var stnGenerations: [UInt64] = []
    private var stnFreeSlots: [Int] = []
    private let stnIdentity: STNDocumentID

    func resolve(_ stnID: STNNodeID) -> STNNodeRecord? {
        guard stnID.document == stnIdentity,
              stnSlots.indices.contains(stnID.slot),
              stnGenerations[stnID.slot] == stnID.generation else {
            return nil
        }
        return stnSlots[stnID.slot]
    }
}
```

**Implementation note:** This sketches a possible later arena, not the M1 class implementation or a complete allocator. `STNDocumentID` is an opaque, `Hashable`/`Sendable`, process-unique, non-reused identity. `STNNodeRecord` is a value type here; mutations must happen through document-managed methods, not edits to a detached copy. Generation exhaustion retires the slot permanently rather than wrapping. Array reallocation must not invalidate a public handle or leave borrowed pointers live across mutation.

### 5.2 Required tree operations

```swift
@MainActor
protocol STNTreeMutationAPI {
    func append(_ stnChild: STNNodeID, to stnParent: STNNodeID) throws
    func insert(_ stnChild: STNNodeID, into stnParent: STNNodeID, at stnIndex: Int) throws
    func move(_ stnNode: STNNodeID, into stnParent: STNNodeID, at stnIndex: Int) throws
    func removeSubtree(_ stnNode: STNNodeID) throws
}
```

Every mutation must:

1. Validate IDs, document ownership, indices, and absence of ancestor cycles.
2. Maintain parent/child consistency and order.
3. Dispose subscriptions on removed nodes.
4. Update focus and pointer capture if their nodes disappear.
5. Remove or update semantic nodes.
6. Invalidate affected layout and paint regions, including old bounds.

Validate a complete structural edit plan before touching the live tree. `move` indices refer to the destination **after removing** the source, including same-parent moves; moving a root, adopting an attached node without `move`, and cross-document reparenting are errors. Reparenting within the document preserves identity and subscriptions, but inherited environment and coordinate caches must be invalidated. Structural edits requested during event dispatch are deferred to its transaction boundary (§10.1).

### 5.3 Ownership model

```text
STNDocument
 ├─ owns node arena
 ├─ owns signal observation registrations associated with mounted nodes
 ├─ owns focus, hover, pointer capture, and layout caches
 ├─ owns logical semantic tree
 └─ owns scene items / GPU-resource handles

STNSignal ──────► subscriber tokens or weak/document-scoped callbacks
STNNodeHandle ──► document identity + generational STNNodeID
STNRenderer ────► immutable scene data + separately owned GPU resources
```

Avoid event/observer closures that strongly retain the document or node facade indefinitely. Disposal of a subtree must be enough to sever all subscriptions associated with it.

Each mounted subtree owns an `STNLifetimeScope`: subscriptions, scheduled effects, async tasks, timers, and resource leases register with it. Disposal is idempotent and marks the scope dead **before** cancellation callbacks run. Late async results check both the lifetime token and the request revision; cooperative task cancellation alone does not prevent stale publication. Source signals owned by the application can outlive nodes, but their document edges must not. Shutdown and GPU retirement are separate from immediate logical disposal (§11.3).

---

## 6. Fine-grained signal runtime and transaction semantics

### 6.1 Public abstractions

```swift
@MainActor
public final class STNSignal<Value> {
    public var value: Value { get set }
    public var binding: STNBinding<Value> { get }
    public init(_ value: Value, equals: @escaping (Value, Value) -> Bool)
    public func map<Output>(_ transform: @escaping (Value) -> Output) -> STNComputed<Output>
}

@MainActor
public final class STNComputed<Value> {
    public init(_ compute: @escaping () -> Value,
                equals: @escaping (Value, Value) -> Bool)
    public var value: Value { get }
    public func map<Output>(_ transform: @escaping (Value) -> Output) -> STNComputed<Output>
}

@MainActor
public struct STNBinding<Value> {
    public var value: Value { get nonmutating set }
}
```

Provide `Equatable` convenience initializers using `==`, and corresponding `Equatable` output overloads for `map`. Non-equatable values require an explicit comparator (omitted from the concise `map` signature above). Comparators must be pure equivalence relations and define substitutable observable values: consumers must not distinguish values declared equal, including for branch decisions. An unsound comparator invalidates the consistency guarantee. Reference-type payloads are not deeply observed: mutation behind the same reference without a signal assignment is outside the contract. Prefer immutable/value payloads or observable row models.

Signals represent **current state**, not a lossless event stream. Multiple writes can coalesce to the final value at commit. Use ordered event delivery for commands, keystrokes, accessibility actions, and other events that must not disappear.

### 6.2 Required behavior

| Operation | Required contract |
|---|---|
| Write outside an explicit batch | Open and synchronously finish an implicit logical transaction; writes in an input handler join the dispatch batch and commit after dispatch (§10.1); remaining visual work is scheduled separately |
| Write inside a batch | Update source state immediately; defer bound-property publication until outer commit; document queries reject as `transactionInProgress` except for the captured dispatch snapshot (§§6.4.1, 10.1) |
| Read a source after writing | Read the latest source value in that synchronous transaction |
| Read a stale computed | Recursively validate dependencies and return a value consistent with current sources |
| Equal source/output | Suppress downstream observable changes; equality never suppresses dependency bookkeeping |
| Computed evaluation | Synchronous, pure, nonthrowing; no signal writes, tree mutation, I/O, or task creation |
| Bound-property publication | Run after graph stabilization; no application effects during partial publication |
| Unobserved computed | May remain stale until demanded; owns no permanent document subscription by itself |
| Subscription | Scope-owned, explicitly cancellable, cancellation idempotent; cancelled delivery is skipped even if already queued |
| Runtime fault | Cycles or forbidden mutation produce a dependency-path diagnostic and fail the affected UI runtime in all supported builds; never silently continue with inconsistent projections |

Model application failures as values (`Result`, loading/error state), not exceptions escaping a computed getter. The runtime fault channel is for programmer errors, not routine validation failures. The simplified immediate-callback observer implementation from the earlier proposal is intentionally not a production algorithm: callback order, recursive writes, and teardown would make it inconsistent.

### 6.3 Dynamic dependency tracking and glitch freedom

```text
STNSignal A ──► STNComputed B ──┐
            └► STNComputed C ──┴► STNComputed D ─► Text.text binding
```

Use **push invalidation, ordered pull validation**. The following is normative reference pseudocode, not a choice left to callback registration order. Optimizations must preserve its results, dependency replacement, and fault behavior.

#### 6.3.1 Records and execution boundaries

- A source has a value, monotonic output revision, and reverse dependents. An unequal write increments its revision and marks every reachable dependent stale, using a per-write visited set. Invalidation executes no computed closures; it also deduplicates demanded-binding queue entries. Count edge visits even when later equality prunes recomputation.
- A computed has `clean`/`stale` status, a separate `idle`/`validating`/`evaluating` phase, optional cached output, output revision, an ordered dependency trace of `(ID, observedOutputRevision)`, reverse dependents, and a monotonic attempt token. A new computed is stale with no cache. Status is authoritative only while phase is idle.
- Trace order is **first actual read order**, including branch-selector reads, not sorted IDs or an unordered set. Repeated reads can be deduplicated at their first position because sources cannot change during a demand. Internal validation probes do not count as reads by a caller's compute closure.
- Each demand runs synchronously against fixed current sources. No writes, callbacks, disposal, suspension, or graph-mutating application work can interleave with validation/evaluation. Bindings collect results/plans; they do not publish document mutations while the graph is being traversed.

#### 6.3.2 Demand and dependency replacement

```text
demand(n):                              // internal; does not record a caller edge
    if n is source: return n.value
    if n.phase == evaluating:
        fail actualDemandCycle(evaluationStack, n)
    if n.phase == validating:
        return evaluateFresh(n)          // supersede suspended validation, not a cycle
    if n.status == clean: return n.cache
    if n has no cache: return evaluateFresh(n)

    n.phase = validating
    ticket = ++n.attempt
    oldTrace = snapshot(n.dependencies)
    for (d, seenRevision) in oldTrace, in recorded order:
        if d.phase is validating or evaluating:
            return evaluateFresh(n)      // old edge is not proof of a current cycle
        demand(d)
        if ticket != n.attempt:
            return demand(n)             // never let superseded validation mark clean
        if d.outputRevision != seenRevision:
            return evaluateFresh(n)      // STOP: do not validate the remaining suffix
    n.status = clean
    n.phase = idle
    return n.cache

evaluateFresh(n):
    assert n.phase != evaluating
    ++n.attempt                          // invalidate any suspended validation ticket
    n.phase = evaluating
    detach n's entire old outgoing trace and its reverse-index memberships
    n.dependencies = []                  // obsolete edges stop participating NOW
    push n onto evaluationStack with an empty temporary ordered read collector
    candidate = n.compute()              // all reactive reads use read(d), below
    newTrace = pop n's collector and evaluationStack entry
    install newTrace and corresponding reverse-index memberships
    if n has no cache or not n.equals(n.cache, candidate):
        n.cache = candidate
        ++n.outputRevision
    // Otherwise keep the equivalent cached output/revision, but KEEP the new trace.
    n.status = clean
    n.phase = idle
    return n.cache

read(d):                                 // API read inside a compute closure
    caller = current entry on evaluationStack, if any
    value = demand(d)
    if caller exists:
        record (d.ID, d.outputRevision) in caller's collector at first read position
    return value
```

For the phase checks above, sources always have phase idle. Revision and attempt counters start at zero and must not wrap (§12.3). A closure's reads are recorded only after the demanded value is current. `evaluateFresh` never consults the removed suffix; it discovers dependencies exclusively through fresh execution. Until it succeeds, no partial cache/trace is publicly usable. A runtime fault unwinds collectors/phases and fails the affected runtime (§6.2); there is no continuation using partially detached graph data.

**Cycle policy:** validation-stack membership is not evaluation-stack membership. An old edge reaching active work falls back to fresh evaluation of its owner rather than reporting a cycle. Only an actual `read`/demand reaching a currently executing computed faults; its diagnostic records the current evaluation path, distinguishing intervening validation probes. Attempt tokens prevent an older suspended validator from overwriting a fresh result. Do not solve recursive definitions by arbitrary fixed-point iteration or diagnose cycles from the union of old/new edges.

Only changed output revisions cause bound-property changes. Drain all demanded bindings and structural plans (including bindings introduced by mounts) before logical publication. Effects run after commit, in registration order for v1; their writes queue a new transaction after the effect phase, never reenter stabilization. Bound consecutive effect-driven turns and diagnose feedback loops.

#### 6.3.3 Acceptance fixtures and termination assumptions

**Diamond:** `B = A * 2`, `C = A + 1`, `D = B + C`. Changing `A` from `1` to `2` publishes `D = 7`, never `5` or `6`. In this fixture, a batch with no intermediate reads evaluates each affected demanded computed at most once. Explicit reads between writes may require more evaluations; there is no unconditional once-per-transaction promise.

**Branch-dependent edge reversal:** definitions read `flag` before the conditional arm:

```text
a = if flag then 1 else b
b = if flag then a else 2

flag = false: a = b = 2; traces a:[flag,b], b:[flag]
flag = true:  a = b = 1; traces a:[flag],   b:[flag,a]
```

From false→true, demanding `a` first finds the changed `flag`, detaches `[flag,b]`, and evaluates `a = 1` without validating old `b`. Demanding `b` then records its new `a` edge. Run both directions, both root-demand orders, repeated toggles, and an initially undemanded root. Assert values, exact ordered traces/reverse edges, no false cycle, and no evaluation of an abandoned suffix solely to validate its former owner. For an equal-output variant, use a = if flag then 1 else b and b = if flag then a else 1; verify that dependency replacement still happens without an output-revision increment. Also include a real active cycle (`a` reads `b`, `b` reads `a`) that must fault, and an inactive cyclic branch that must not. Compare every successful result with a pure uncached evaluator of the current branches, not with an evaluator traversing the old graph.

**Termination is conditional:** each source snapshot has a finite reachable demanded graph; each pure deterministic compute/comparator terminates and has finitely many reads; all changing inputs are tracked; equality is substitutable (§6.1); and the currently executed dependency graph is acyclic. Under these assumptions, ordered validation reuses only a consistent prefix and fresh evaluation follows current demands, so a finite demand settles without fixed-point search. Old/new graph unions need not be acyclic. Commit completion additionally requires finitely many mount/binding plans; endlessly generated structure, nonterminating closures, or effect feedback are not covered by the graph argument. Instrument depth/work and diagnose budget exhaustion (§6.5); budgets are a failure bound, not a termination proof. A fixed topological order computed once is insufficient.

**Research rationale:** [Adapton §5.2 and Algorithm 1 (PLDI 2014)](https://matthewhammer.org/adapton/adapton-pldi2014.pdf) explicitly record dependency order, stop propagation at the first inconsistent dependency, and remove outgoing edges before reevaluation. Stana adopts that ordering principle; the phase/token/fault rules above are Stana-specific requirements, not a claim to implement Adapton's calculus or inherit its proof. From-scratch equivalence remains an independent engineering obligation motivated by [Acar, Blume, and Donham's consistency semantics](https://arxiv.org/abs/1106.0478).

### 6.4 Batch writes, commit phases, and publication

```swift
STNTransaction.perform {
    stnFirstName.value = "Ada"
    stnLastName.value = "Lovelace"
    stnAge.value = 36
}
```

`perform` takes a synchronous, nonthrowing closure. Nested calls join the outer transaction. It is a **batch, not a database transaction**: there is no rollback of source writes or external side effects. Validate fallible application operations before entering the batch. Do not hold an open transaction across an `await` or invoke user callbacks under internal locks.

```text
collect source writes / validate requested edits
  → stabilize demanded computeds, bindings, structural edit plans
  → apply document changes and repair focus/capture under a candidate revision
  → ensure geometry required by semantics; construct immutable semantic snapshot
  → install adapter query snapshot and finish logical publication atomically to observers
  → enqueue post-commit effects / ordered native accessibility notifications
  → request remaining visual layout/scene work for the latest committed revision
```

If a structural scope creates bindings, stabilize them in this commit before exposing its children. No semantic relationship may reference an uncommitted node. Public callbacks/effects run only after the boundary. Initial mount evaluates a binding before publication; subsequent delivery uses equality suppression.

#### 6.4.1 Freshness contracts by observer

Let `L` be the latest completed logical/document revision, `S` the source-document revision of the adapter's semantic snapshot, and `G(region)` the revision through which that region's geometry dependencies have been validated. Unchanged cached geometry can be certified through `L` without remeasurement. Geometry includes dependent ancestors/siblings, transforms, clips, scrolling, stacking, and host coordinate/scale epochs; “affected region” is a dependency closure, not necessarily one subtree.

| Observer | Required freshness / linearization point | Permitted delay |
|---|---|---|
| Document property/structure query on UI actor | Latest completed `L`; never a half-applied plan | None after commit. Source/computed reads within a collecting batch see pending sources; document queries during that batch reject as `transactionInProgress` rather than mixing versions |
| Document geometry query on UI actor | Synchronously ensure `G(query closure) = L` before returning, including hit-relevant placement dependencies | Can force layout outside a frame; a stale geometry API must be separately named and carry its revision |
| Pointer hit test / geometric navigation | After preceding commits, ensure `G(target-search closure) = L` before selecting target/path; recheck eligibility/capture against `L` | May wait for synchronous layout, never for GPU presentation; no dispatch using stale scene geometry |
| Native accessibility query served by Stana's provider | Capture one immutable adapter snapshot at query entry. `S = L` at each completed commit; overlapping queries may finish against the previous complete snapshot. All returned fields/ranges/bounds belong to that captured revision | No synchronous callback hop to the UI actor. Native OS/AT caches and notification delivery can lag; their consumption time is not guaranteed by Stana's snapshot installation |
| Painting | A complete immutable scene for its tagged document revision, with geometry current for that snapshot and correct damage base | May coalesce/drop intermediate scenes and lag `L`; never use painting to redefine input or semantic state |

Installing the Stana-owned adapter query snapshot is part of the synchronous publication boundary, independent of native notification delivery. A bridge that cannot satisfy snapshot consistency/freshness needs a qualified shim or a separately proposed contract change, not an unmeasured asynchronous queue. Providers capture snapshots without holding a lock while waiting for the UI actor (§9.4). Multi-call native query sequences can straddle revisions unless the native protocol supplies a snapshot context; range revisions must still be validated (§10.2).

**Scheduling cost:** every semantic node whose bounds/offscreen/text-range geometry may change must be geometrically current before its snapshot is installed, even if its label did not change. A truly label-only change with valid geometry requires no layout/GPU work. Layout that supplies these semantics is therefore synchronous commit work; it cannot also be promised as frame-only/coalesced work. Geometry needed only for later paint can remain deferred. This contract does not become weaker when AT is inactive; activation can always request a complete current tree. Report semantic-required layout, semantic projection, snapshot installation, and notification enqueue costs separately (§13.5).

#### 6.4.2 Delayed presentation and actionable geometry

If a button moves at logical revision `L+1` while `L` remains visible, a click at its old position is hit-tested against **current logical geometry at dispatch**, not the old image and not event-timestamp historical geometry. It may miss the button or target another currently eligible control there. The new location is actionable even before painted. Existing pointer capture remains identity-based; ordinary activation still uses current eligibility and the control's release/cancellation policy (§10.1). Keyboard and AT activation likewise use current identity/state, not pixels.

This is an intentional visible/actionable divergence, not a guarantee of perceptual synchronization. Do not silently retarget an old-position click or defer accepted commands until a frame appears. Retain event receipt/dispatch times, target ID, logical and geometry revisions/coordinate epoch, scene/submission/backing-store revisions, and last confirmed presentation metadata. Increment an `interactionEpoch` whenever hit geometry or eligibility changes and carry it into scenes; revision lag from label-only writes alone does not imply geometric divergence. Record age since the oldest not-yet-confirmed interaction change and whether presentation feedback is available; unknown presentation is not “current.”

For a visible drawable window, crossing two target refresh intervals without confirmation of an interaction-affecting update emits a lag diagnostic and prioritizes the latest pending visual work within the bounded queue (§11.2). This is a diagnostic/service objective, **not a hard time bound** when the renderer, OS, or display stalls; logical correctness must not depend on such a bound. Record occluded/minimized periods separately. Qualification stalls the renderer, moves/removes/overlaps controls, clicks both old/new positions, and verifies these dispatch rules, capture cancellation, semantic bounds, lag reporting, and recovery. Include the usability consequences in §9.7's tasks.

Logical, scene, backing-store, and presented revisions are separate domains. A nonvisual write may advance `L` without a frame; scene ordinals must not be subtracted from document ordinals. Their mapping and monotonic completion rules are in §11.2.

### 6.5 Disposal, errors, and runaway work

Cancel graph edges as part of scope disposal, including conditional and list scopes. A queued callback must revalidate its scope and node generation before acting. Computed caches retain only their current dependency set, not the history of every branch ever visited.

Instrument graph depth, edge count, stabilization work, and effect-turn count. Exceeding a configured work budget should emit a diagnostic and use a documented failure policy; correctness-critical logical publication cannot be arbitrarily split into half-commits. Large application updates should be prepared off-actor and applied in deliberately scoped batches. Research on [Asynchronous Modal FRP (Bahr and Møgelberg, 2023)](https://arxiv.org/abs/2303.03170) reinforces that causality and bounded retention need explicit semantics; Swift ARC plus signals does not establish those properties automatically.

---

## 7. Invalidation and incremental layout

### 7.1 Dirty flags

```swift
struct STNDirtyFlags: OptionSet {
    let rawValue: UInt16

    static let measure   = Self(rawValue: 1 << 0)
    static let layout    = Self(rawValue: 1 << 1)
    static let paint     = Self(rawValue: 1 << 2)
    static let hitTest   = Self(rawValue: 1 << 3)
    static let semantics = Self(rawValue: 1 << 4)
    static let children  = Self(rawValue: 1 << 5)
}
```

### 7.2 Property-specific consequences

| Property mutation | Required invalidation |
|---|---|
| `text` or font change | shape/measure, dependent layout, paint, hit-test/semantic bounds and text data |
| `backgroundColor` | paint only |
| `opacity` | paint/compositor only; does not by itself hide a node from focus or semantics |
| `width`, `padding`, `gap` | measure/layout, subsequent paint/hit-test/semantic bounds |
| `transform` | paint, hit-test, semantics bounds |
| `isEnabled` | paint, hit-test, semantics |
| `accessibilityLabel` | semantics only |
| Child insert/remove | structural scope + affected parent layout, scene and semantics |
| Locale, direction, font fallback, text scale | Invalidate dependent environment/style, shaping/measurement, layout, paint, and semantics as applicable |
| Scroll offset | Viewport transforms, paint, hit-test, semantic bounds; virtual realization if needed |

Paint invalidation must expand through compositing dependencies (for example, a background seen through translucent children). `paint` identifies stale scene content; damage is the affected output region, and the two are not interchangeable. Pure opacity animation keeps layout caches valid. Use explicit `hidden`/`collapsed`/`inert` policies (§9.5), not opacity as an implicit accessibility switch.

### 7.3 Localized layout invalidation

```swift
func setBackgroundColor(_ stnColor: STNColor, on stnNode: STNNodeID) {
    guard updateColorIfChanged(stnNode, stnColor) else { return }
    markDirty(stnNode, .paint) // No measurement or layout.
}

func setText(_ stnText: String, on stnNode: STNNodeID) {
    guard updateTextIfChanged(stnNode, stnText) else { return }
    markDirty(stnNode, [.measure, .paint, .semantics])
    invalidateDependentLayout(stnNode)
}
```

The second example is internal pseudocode: document mutators should be actor-isolated and should preserve old painted bounds until damage is calculated.

### 7.4 Layout API and caching

Use a Stana-specific measure/place engine, not a browser CSS implementation.

```swift
struct STNConstraints: Hashable {
    var minWidth: Double
    var maxWidth: Double
    var minHeight: Double
    var maxHeight: Double
}

struct STNLayoutSize: Equatable {
    var width: Double
    var height: Double
}

struct STNMeasureKey: Hashable {
    let constraints: STNConstraints
    let styleVersion: UInt64
    let contentVersion: UInt64
    let childrenVersion: UInt64
    let environmentVersion: UInt64
    let fontDatabaseVersion: UInt64
}

@MainActor
protocol STNLayoutAlgorithm {
    func measure(_ stnNode: STNNodeID, under stnConstraints: STNConstraints) -> STNLayoutSize
    func place(_ stnNode: STNNodeID, at stnOrigin: STNPoint, size stnSize: STNLayoutSize)
}
```

Cache measurement by normalized constraints and all inputs read by measurement. A descendant's changed intrinsic size increments the dependent ancestor's measurement-input version even if child IDs did not change; `childrenVersion` alone is insufficient. A coarse environment epoch is acceptable first; split it into typography/direction/scale epochs only after profiling. Bound per-node cache entries and global cache bytes.

**Layout containment:** Explicit fixed constraints and isolated layout roots can stop invalidation propagation. Avoid claiming constant-time relayout when intrinsic size affects parents or siblings.

### 7.5 Geometry and stack rules

- Geometry uses device-independent logical units, `Double`, top-left origins, and positive downward Y. Types distinguish local, window, screen, and physical-pixel coordinates; platform adapters convert explicitly. Screen coordinates are not assumed globally available on every host.
- Constraint minima are finite and nonnegative. Maxima are at least the minima and may be positive infinity. Reject NaN, negative extents, and unsupported cyclic percentage sizing. Measured/placed sizes and transforms must be finite; infinity is a constraint sentinel, never a drawable dimension.
- `padding` insets a node's content: `STNBox` subtracts insets before child measurement and adds them back to its own result; stack padding similarly surrounds its arranged children. `frame` constrains the outer padded box, and background/border geometry uses the resulting node bounds. This fixed relationship is not affected by property argument order (§3.0); separate nested boxes express separate style/layout layers. Border sizing, clipping, and overflow are documented separately. Unbounded space does not authorize an infinite spacer.
- A stack measures nonflex children, accounts for gaps, then distributes remaining bounded main-axis space among flexible children according to declared weights/minima/maxima. Clamp and redistribute until constrained children are settled. Under unbounded main-axis constraints, flexible space contributes its minimum, not infinity. An overconstrained stack retains child minima and reports/clips overflow under its explicit policy; it does not produce negative sizes.
- Define leading/trailing in logical direction; preserve separate logical reading order. Baseline alignment uses text metrics, not rectangle bottoms. Overlay children share the parent's content box and explicit z-order.
- Retain logical geometry for measurement. Snap raster edges through one shared physical-edge policy at presentation so neighboring rectangles do not independently round into gaps. Fractional DPI, mixed-monitor moves, and noninvertible transforms have deterministic behavior; noninvertible nodes cannot be pointer hit targets.
- Layout invalidation travels upward through actual size dependencies, then downward through changed placement/constraints. Stop only when output size, baselines, and inherited placement dependencies are unchanged. Enforce a recursion-depth limit or iterative traversal for hostile/deep trees.

The v1 layout contract is deliberately narrower than CSS/Flexbox. Implement a slow, uncached reference evaluator for differential tests before optimizing dirty-root traversal. Never “fix” stale results by indefinitely iterating layout until it appears stable.

### 7.6 Virtualization is a distinct lifecycle contract

Do not market a scroll view that mounts every child as a lazy list. A future `STNList` must distinguish application item identity/state from the lifetime of a realized row. Offscreen eviction cancels row-scoped tasks/subscriptions; persistent item state belongs to the application model, not an assumed immortal row node. Recycled storage receives new generational identity for a different item.

Preserve a scroll anchor (key plus local offset) through insertions and measured-height changes. Variable-height lists need an indexed extent structure; report its update/query cost separately from realized-row work. Define overscan and maximum realization budgets. Keyboard and AT requests for unrealized items must use logical indices/metadata and a bounded realization/scroll path; test first/last-item navigation and item-count/position semantics without materializing the whole list. A focused row may be pinned until a documented focus transfer occurs. “Work proportional to visible rows” applies to realization/painting under stated conditions, not to every model diff, index rebuild, or accessibility query.

---

## 8. Scene recording and rendering

### 8.1 Retained scene, immutable frame snapshots

```swift
public enum STNDrawCommand: Sendable {
    case fillRect(STNRect, STNColor)
    case strokeRect(STNRect, STNColor, width: Double)
    case drawText(STNTextRunID, at: STNPoint)
    case drawImage(STNImageID, in: STNRect)
    case pushClip(STNRect)
    case popClip
}

public struct STNSceneSnapshot: Sendable {
    public let documentRevision: UInt64
    public let sceneRevision: UInt64
    public let interactionEpoch: UInt64
    public let surfaceEpoch: UInt64
    public let damageBaseRevision: UInt64
    public let damage: [STNRect]
    public let displayList: [STNDrawCommand]
    public let resources: STNFrameResourceLease
}
```

Production snapshots require **all** nested command/geometry/color/resource handles to be `Sendable` or immutable snapshots, and may use persistent per-layer lists rather than flattening every node every frame. A snapshot is logically a **complete scene**, not a delta that requires a discarded predecessor. Commands contain typed, versioned resource IDs, never borrowed mutable native pointers. Resource leases keep referenced images, fonts, glyph buffers, and layers valid through GPU completion, even if the document removes their nodes.

### 8.2 Incremental damage

```swift
func invalidatePaint(
    old stnOldBounds: STNRect,
    new stnNewBounds: STNRect
) {
    stnDamage.add(stnOldBounds.union(stnNewBounds))
}
```

Account for transformed bounds, strokes, shadows, blur outsets, clips, scroll offsets, and changes to occlusion. A debug flag should force full-window repaint, enabling differential screenshot tests against incremental drawing.

Damage is relative to `damageBaseRevision`, not simply to the previous snapshot constructed. If snapshots are dropped, accumulate damage from the renderer's acknowledged backing-store revision to the new scene, or force a full repaint. Example: if revision 2 moves A→B and is dropped, revision 3 moving B→C must still erase A from a backing store at revision 1. A new surface epoch, lost backing store, scale change, or unknown history always forces full repaint.

**Partial redraw requires preserved pixels.** The initial implementation uses a retained offscreen backing store and presents a complete image to the acquired window buffer. It must not assume that a newly acquired swapchain image contains the last frame. Direct-to-swapchain incremental rendering is an optional optimization requiring per-image history/buffer-age and backend-specific synchronization. Clearing only damaged regions on an unpreserved target is incorrect.

Damage processing also redraws unchanged content that intersects the damaged region in compositing order; rerecording only dirty nodes cannot reconstruct background pixels or overlapping transparent objects. Cap damage-rectangle count/area and promote to full-window redraw when fragmentation costs more than a full pass.

### 8.3 Renderer contract

```swift
protocol STNRenderer {
    func attach(surface: STNSurface) throws
    func resize(to stnPixelSize: STNPixelSize, scale: Double) throws
    func submit(_ stnScene: STNSceneSnapshot) throws -> STNFrameSubmission
    func pollCompletions() -> [STNFrameCompletion]
    func detach() throws
}
```

All methods run on the backend's designated render context; the host owns any native-window operations required on its main thread. `submit` returning is **not** GPU completion or proof that photons were displayed. Completion reports resource-retirement fences, backing-store revision, and presentation feedback when the OS provides it. `detach` participates in the shutdown handshake (§11.3), not immediate destruction of in-flight resources.

Recommended rendering split:

- **`StanaScene`:** paint commands, layers, z-order, damage, and snapshot creation (Swift).
- **`StanaGraphics`:** rendering backend and GPU resources behind a narrow stable C ABI.
- **`StanaPlatform`:** native window creation, events, display scale, clipboard, text input, and graphics-surface integration.

Evaluate Skia first for drawing and the raster reference path; retain the backend abstraction if build size or packaging invalidates that choice. Stana must own the C ABI shim—this document does not assume an upstream stable Skia C ABI. Skia's documentation distinguishes raster/GPU surface creation and leaves graphics-context/device setup to the client. Verify the chosen Skia revision and backend family (including Ganesh versus Graphite) rather than mixing APIs from different examples. See [Skia surface creation](https://skia.org/docs/user/api/skcanvas_creation/).

### 8.4 Window and platform boundary

```swift
@MainActor
protocol STNPlatformWindow: AnyObject {
    var contentScale: Double { get }
    var drawableSize: STNPixelSize { get }

    func show()
    func requestRedraw()
    func close()
}

@MainActor
protocol STNPlatformHost {
    func createWindow(_ stnOptions: STNWindowOptions) throws -> STNPlatformWindow
    func pollEvents() -> [STNPlatformEvent]
}
```

`STNPlatformEvent` should normalize pointer, scroll, key, character, composition/IME, display-scale, window state, and assistive-technology action events. **Do not reduce IME input to key-down events.**

`pollEvents` describes a host capability, not a required busy loop on every OS. AppKit can drive callbacks from its run loop; other hosts must integrate pumping and Swift executor wake-ups without starving either. Keep native events' monotonic timestamps and window identity through normalization. A closed window's late events are ignored by generation/epoch checks.

### 8.5 Platform targets

| Platform | Native window | Preferred graphics route | Accessibility service |
|---|---|---|---|
| macOS | `NSWindow` / `NSView` | Evaluate Metal + raster presentation | AppKit accessibility / VoiceOver |
| Windows | `HWND` | Verify chosen Skia GPU route (e.g. Vulkan or ANGLE/Direct3D translation) + raster presentation | UI Automation / Narrator and NVDA |
| Linux | Wayland first; X11 separately qualified | Evaluate Vulkan + raster presentation | AT-SPI / Orca |

SDL3 may reduce host/window/event boilerplate. However, **window integration and accessibility integration are separate problems**: windowing libraries do not automatically make custom-drawn nodes visible to screen readers. Prefer OS-specific host shims where text input, surface setup, or accessibility requires them.

SDL's event polling and text-input APIs have main-thread requirements; SDL text input explicitly delivers both committed and composition events. An SDL integration must honor those requirements while participating in the native loop; it is not a generic background polling service. See [SDL event polling](https://wiki.libsdl.org/SDL3/SDL_PollEvent) and [SDL text input](https://wiki.libsdl.org/SDL3/SDL_StartTextInput).

### 8.6 Rendering correctness and resource budgets

- Use premultiplied-alpha surfaces with explicit source/target color-space tags. Establish an SDR sRGB baseline; specify blend-space behavior per backend and test transparent edges, gradients, and image conversion. Wide gamut/HDR is deferred rather than silently mis-tagged.
- Glyph atlas keys include font face/version, variation axes, glyph ID, scale/raster mode, and required subpixel information. A display-scale change invalidates raster caches, not necessarily scale-independent shaping.
- Bound decoded-image bytes, glyph/layer caches, pending uploads, and frame leases. Eviction cannot reclaim an in-flight resource. Shared resources remain alive while any window or submission holds a lease.
- A minimized or zero-sized window does not acquire/present invalid drawables. Keep logical and semantic state current; recreate targets and fully repaint when usable again.
- Device/surface loss transitions through `ready → lost → recreating → ready` or a reported terminal failure. Rebuild resources from CPU descriptors where available; otherwise publish a recoverable asset error. Raster fallback requires a working **presentation** path on that host, not merely a CPU drawing function.
- Only adopt parallel recording, aggressive occlusion, or a custom GPU renderer after profiling demonstrates a bottleneck and full/incremental parity tests exist.

---

## 9. Accessibility: semantic tree from day one

### 9.1 ARIA-inspired semantics, native implementations

Stana is not an HTML engine, so it should implement an **ARIA-inspired portable semantic model**, translating it to actual OS accessibility APIs. Calling a property `ariaLabel` alone does not provide screen-reader support.

Each semantic node needs stable identity, role, accessible name, description, value, states, bounds, relationships, focus status, supported actions, and (for text editing) text ranges/selection/caret information.

The semantic tree is a **projection, not a copy** of the render tree: decorative containers may disappear, one editable node can produce text-run children, and a grouped control can combine descendants. Use a distinct `STNSemanticID` namespace, mapped to an owning `STNNodeID` plus a stable fragment identity. Never recycle a native accessibility identity for a different element while a provider can still reference it.

```swift
public enum STNAccessibilityRole {
    case window
    case group
    case heading
    case staticText
    case button
    case checkBox
    case textField
    case image
    case list
    case listItem
    case scrollArea
}

public struct STNSemanticNode {
    public let id: STNSemanticID
    public let owner: STNNodeID
    public let revision: UInt64
    public var role: STNAccessibilityRole
    public var label: String?
    public var description: String?
    public var value: String?
    public var bounds: STNRect
    public var isDisabled: Bool
    public var isFocused: Bool
    public var children: [STNSemanticID]
    public var actions: Set<STNAccessibilityAction>
}
```

Accessibility primitive types above are interface sketches; conformance and Sendability must be completed in implementation.

### 9.2 Component-provided semantics

```swift
STNButton(properties: .init(
    text: "Delete",
    accessibility: .init(
        label: "Delete document",
        hint: "Moves the document to Trash"
    ),
    onActivate: { stnDeleteDocument() }
))
```

A button must expose role/button action, label, enabled state, focusability, keyboard activation, and bounds by default. Application code should not have to assign these manually.

```swift
STNImage(properties: .init(
    image: stnLogo,
    accessibility: .init(label: "Company logo")
))

STNSpacer() // Intentionally excluded from accessibility traversal.

STNBox(properties: .init(accessibility: .init(group: true))) {
    STNText(properties: .init(
        text: "Account details",
        accessibility: .init(heading: 2)
    ))
}
```

### 9.3 Semantic updates need not wait for rendering

```swift
func setAccessibilityLabel(_ stnLabel: String, on stnNode: STNNodeID) {
    guard updateSemanticLabelIfChanged(stnNode, stnLabel) else { return }
    markDirty(stnNode, .semantics)
    enqueueAccessibilityDelta(stnNode)
}
```

Changing only an accessible label must **not force a GPU repaint**. Semantic snapshot installation follows the synchronous freshness boundary in §6.4.1, independently of dropped/coalesced paint frames. Any dirty geometry affecting exported semantics must be resolved before installation, not deferred merely because this delta changes a label. Native notifications follow installation in adapter-required order.

### 9.4 Native accessibility bridge

The preferred candidate is **AccessKit** through its C bindings. Its upstream documentation describes a push-based initial tree plus incremental updates, native desktop adapters, and single-/multiline text input support; it also explicitly notes incomplete schema/UI coverage and no rich-text/hypertext support in its current released adapters. Treat this as a capability lead, not evidence that Stana's bridge works. Pin and test the selected AccessKit/C release pair. See the [upstream architecture and adapter coverage](https://github.com/AccessKit/accesskit) and [C binding integration](https://github.com/AccessKit/accesskit-c).

```swift
protocol STNAccessibilityBridge {
    func publish(_ stnChanges: [STNSemanticChange])
    func setFocusedNode(_ stnID: STNSemanticID?)
    func handleAction(_ stnAction: STNAccessibilityActionRequest)
}
```

An assistive-technology action such as `press` on a semantic button should resolve its retained node ID, verify that the node is still mounted/enabled, and dispatch the normal Stana button action on the UI executor.

Accessibility activation must reach the same command used by keyboard/pointer activation, without fabricating pointer events or executing the command twice. Queries capture a consistent immutable tree owned by the adapter under §6.4.1, including its revision and validated bounds; never hold an adapter lock while synchronously waiting for `MainActor`, or hold the UI executor while waiting for a callback that needs it. Honor each native provider's actual callback/COM/threading contract. Inspector/test-client calls also need a suitable threading model; Microsoft's [UI Automation threading guide](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-threading) is **client-side** guidance, not a universal provider recipe.

Publish an initial complete tree, then ordered changes with a revision. Coalesce replaceable state only when the adapter can reconstruct the latest state; preserve action ordering and necessary announcements. Activation after inactivity or a lost update history requires a full-tree resynchronization. Focus/removal notifications reference existing committed elements in the order required by the adapter. Native providers retained after removal return “element unavailable,” not recycled node data.

**Text field release gate:** screen readers must be able to query text, selection, caret, insertion/deletion, secure-input state, IME composition, and character/word navigation. A painted text box with a label is *not* an accessible text field.

### 9.5 Portable interaction policies

| State/policy | Layout and pixels | Input/focus | Semantic projection |
|---|---|---|---|
| `opacity(0)` | Layout retained; transparent | Unchanged unless explicitly disabled/inert | Retained |
| `hidden` | Layout retained; not painted | No pointer hit or keyboard focus | Excluded; repair focus |
| `collapsed` | No layout contribution or painting | No interaction | Excluded |
| `inert` subtree | Painted normally | No user or assistive activation/focus | Map platform unavailable/noninteractive semantics; never expose actionable descendants |
| Disabled control | Layout retained; disabled style | No activation; v1 keyboard traversal skips it | Retained with disabled state; AT may inspect it |
| Clipped/offscreen scroll content | Only visible pixels drawn | Visibility-aware hit test; logical focus can scroll into view | Retained/virtualized with correct offscreen state, not arbitrarily deleted |

Modals establish a focus scope, inert background content, an accessible name, Escape/dismiss policy, and focus restoration to a surviving eligible origin. Accessible names use explicit label/label relationship before component-default visible text; hints do not replace names. Bounds must use the same transforms and clip/visibility decisions as input, converted to each OS's required coordinates.

Use [W3C WCAG2ICT guidance](https://www.w3.org/TR/wcag2ict/) to translate relevant WCAG principles to non-web software and build a test checklist for keyboard access, visible/unobscured focus, contrast, names/roles/values, and scalable text. WCAG2ICT is informative guidance, **not** a conformance standard or proof of product accessibility. A toolkit cannot establish an application's accessibility solely by supplying roles.

### 9.6 Accessibility test matrix

- **macOS:** VoiceOver reading, labels, headings, focus, activation, editing.
- **Windows:** Narrator and NVDA, UI Automation inspection, keyboard traversal, text ranges.
- **Linux:** Orca, AT-SPI inspection, reading order, focus, widget actions.
- **Common:** scale changes, keyboard-only use, contrast settings, reduced motion, logical reading order, and no accessibility nodes for decoration.

Record OS/AT versions, host backend, input language, test script, and results for each qualified release. Include hot activation of an AT, modal dismissal, removed focused controls, concurrent queries during commits, and secure text. Snapshot tests validate projection structure; they do not replace actual assistive-technology interaction.

### 9.7 Accessibility usability evaluation (not yet performed)

The native AT matrix establishes interoperability for specified capabilities, not ease, efficiency, or confidence in real tasks. Before making accessibility-usability claims, conduct iterative task-based evaluation with disabled participants using their familiar AT/settings: include screen-reader users, keyboard/switch users, and low-vision users with relevant scaling/contrast configurations. Record recruitment, platform/AT experience, accommodations, participant coverage, and limitations; one AT expert or one disability group does not represent all users.

Use an accessible editable-list/settings sample to test finding a control, editing/composing/selecting text, reordering a focused row, handling validation errors, modal entry/exit, and recovering after delayed presentation. Record unaided/assisted completion, errors and unintended activations, focus/context loss, recovery/debugging effort, time, assistance, and participant explanations of barriers. Do initial technical checks first, obtain informed consent, compensate participants, protect recordings, and allow their own input methods. Triage blockers, revise the implementation, and retest affected tasks; do not count a workaround supplied by a moderator as unaided success. Publish scoped observations and unresolved barriers, not a universal usability score or a population claim from a formative sample.

[W3C WAI's user-evaluation guidance](https://www.w3.org/WAI/test-evaluate/involving-users/) explains why standards-based checks and evaluation with disabled users complement one another. Applying that principle to this native toolkit is a Stana evaluation decision. [WCAG2ICT](https://www.w3.org/TR/wcag2ict/) remains informative guidance; neither it nor passing semantic snapshots replaces these task observations. No such study is claimed to have taken place.

---

## 10. Events, focus, and input

### 10.1 Input pipeline

```text
OS pointer/key/IME event
  └─ STNPlatformHost normalizes event
       └─ STNInputDispatcher
            ├─ ensure current logical hit geometry (§6.4.1)
            ├─ hit test → deepest currently eligible retained node
            ├─ capture phase (ancestors)
            ├─ target handler
            ├─ bubble phase (ancestors)
            └─ update hover/pressed/focus state
```

```swift
STNBox(properties: .init(
    onPointerDown: { stnEvent in
        stnEvent.capturePointer()
    },
    onPointerMove: { stnEvent in
        stnDragPosition.value = stnEvent.position
    },
    onPointerUp: { stnEvent in
        stnEvent.releasePointerCapture()
    }
)) {
    STNText(properties: .init(text: "Drag me"))
}
```

Explicit focus scopes, tab traversal, directional navigation where appropriate, disabled controls, and keyboard equivalents are required in the core. Composition, candidate selection, selection ranges and clipboard form a separate text-editing path.

Before dispatch, finish preceding commits and satisfy §6.4.1's geometry barrier; historical painted bounds do not select the target (§6.4.2). Dispatch follows a snapshot of that target's ancestor path and committed document revision. Handler writes join an implicit dispatch batch: source reads see pending writes, but document/geometry queries remain on the captured dispatch revision until default actions and path traversal finish, then the batch commits. This is an explicit exception to collecting-batch query rejection, not permission to observe partially applied structure. Handlers can request structural changes, but these apply after dispatch; never traverse a child array while a handler mutates it. Define `stopPropagation`, `stopImmediatePropagation`, and `preventDefault` separately. Default button activation occurs only once, after cancellation checks. Pointer capture is per pointer ID and ends with up, explicit release, cancellation, node disposal, or window deactivation; dispatch an appropriate cancellation before cleaning pressed/drag state. Coalescing pointer motion must preserve ordering around down/up/cancel and must not cross coordinate/surface epochs.

Tab order follows declared logical order and focus scopes, not GPU z-order. Removing a focused node selects the next eligible node in its scope, then a surviving scope fallback; never leave an ID pointing to a disposed node. Hit testing applies inverse transforms, clips, scroll offsets, visibility, and hit policy in the same stacking order used by painting.

### 10.2 Text shaping, paragraph layout, and positions

`STNText` is not “draw each Swift Character.” `StanaText` owns font resolution/fallback, script/language runs, bidirectional ordering, shaping, line breaking, baselines, hit testing, selection geometry, and caret affinity. Prefer a qualified paragraph stack (for example SkParagraph with its selected shaping/Unicode dependencies), or platform text engines behind one interface; do not accidentally combine metrics from one engine with caret positions from another. The exact dependency choice is an M0/M3 decision.

Standards and shaping inputs have distinct jobs:

- [Unicode UAX #29](https://www.unicode.org/reports/tr29/) supplies default grapheme/word segmentation; editing commands may need documented language/platform tailoring.
- [Unicode UAX #9](https://www.unicode.org/reports/tr9/) governs bidirectional ordering; storage remains logical rather than visual order.
- [Unicode UAX #14](https://www.unicode.org/reports/tr14/) supplies line-break opportunities, not the final width-constrained paragraph layout.
- [HarfBuzz cluster documentation](https://harfbuzz.github.io/clusters.html) distinguishes shaping clusters from graphemes. Preserve mappings between source ranges and positioned glyphs rather than assuming one glyph equals one character.

**Stana position contract:** a text position is a validated UTF-8 byte offset plus text-buffer revision and caret affinity. A range is half-open and belongs to one buffer revision. Public editing helpers move over grapheme/word boundaries, while adapters convert explicitly to platform UTF-16/code-point/byte indexing and validate endpoints. Offsets from stale text revisions must be transformed by a known edit map or rejected, never reused against a different string. Swift `String.Index`, UTF-8 offsets, UTF-16 offsets, glyph indices, and grapheme counts are not interchangeable integers.

Do not normalize user text silently. Support mixed RTL/LTR, combining marks, emoji ZWJ sequences, font fallback, missing glyphs, and copy/paste round-trips. Cache shaping by text/style/font/environment inputs and paragraph layout by those inputs plus width/wrap policy. Declare the Unicode data version used by the actual runtime dependencies and run **matching-version** conformance data; citing the latest standard does not mean the linked system library implements that version.

### 10.3 Editing and IME contract

An editable node owns committed text, selection anchor/head and affinity, marked/preedit text and selected composition range, undo history, scroll-to-caret state, and an edit revision. Apply each replacement as one edit command, transform/clamp selection using the edit map, then notify bindings and native text services in a defined order. Selection-only changes update caret/selection and semantic ranges without reshaping unchanged text.

| Situation | Required behavior |
|---|---|
| IME preedit update | Update marked text and candidate geometry; do not publish it as committed model text by default |
| IME commit/cancel | Commit one replacement/undo group or discard marked text; never append duplicate key-event characters |
| External binding write during composition | Equal echo is a no-op; a genuinely different value cancels/reset-notifies the native composition first, then replaces text and clamps selection. No implicit merge |
| Focus transfer/window deactivation | Honor the platform's composition commit/cancel protocol; finish the text-service handshake before detaching the client |
| Async validation | Tag by edit/request revision and scope; ignore stale results; expose a separate validation state rather than rewriting newer user text |
| Undo/redo | Group a composition as one edit; document typing/paste boundaries and treat external whole-value replacement as an undo-history reset in v1 |
| Secure entry | Suppress text in diagnostics, snapshots, clipboard-copy defaults, and accessibility values; expose platform password semantics and allowed selection/actions |

Secure entry is a behavioral policy, not a guarantee of zeroized Swift `String` memory. Place limits on pasted text and surrounding-text payloads without cutting encoded code points; an accessibility/text-service API may still legitimately require richer text access according to its secure-input rules.

For macOS, integrate the input context and `NSTextInputClient` composition/command behavior; Apple's [text-editing architecture](https://developer.apple.com/library/archive/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextEditing/TextEditing.html) documents separate inserted text, marked text, and commands. For Win32, qualify a [Text Services Framework](https://learn.microsoft.com/en-us/windows/desktop/TSF/text-services-framework) text-store integration or an explicitly validated host wrapper; ordinary key/character messages are not a full editing bridge. Linux requires an explicitly qualified Wayland/X11 IME path; compositor/IME support is a capability matrix, not “Linux text input” as a single feature. SDL composition events may be part of this bridge, but their existence alone does not establish full text-service or accessibility support.

**M3 acceptance corpus:** Latin dead keys, decomposed accents, Arabic/Hebrew mixed with digits, Indic conjuncts, emoji families/skin tones, Japanese conversion, Chinese Pinyin, Korean composition, selection across ligatures/RTL runs, replacement during composition, undo/redo, clipboard, and screen-reader character/word navigation. A native text-field overlay is an acceptable explicit fallback where custom editing cannot qualify; its geometry, focus, semantics, and binding ownership must be integrated without duplicate controls.

### 10.4 Animation without component rebuilding

```swift
let stnOpacity = STNSignal(1.0)

STNBox(properties: .init(opacity: stnOpacity)) {
    STNText(properties: .init(text: "Saved"))
}

STNAnimator.animate(duration: .milliseconds(180)) {
    stnOpacity.value = 0
}
```

An animated opacity should update presentation/paint state rather than force text measure. Layout-affecting animation can still cause relayout. Reduced-motion configuration must be observable.

---

## 11. Scheduler, concurrency, and shutdown

### 11.1 Single writer and native loop integration

- The UI actor owns source signals, dependency edges, document mutations, focus, dispatch, and semantic projection. Logical commits and event dispatch are synchronous and non-reentrant; no `await` inside either.
- A per-window frame scheduler batches remaining visual layout, scene recording, and raster submission against host frame opportunities; layout required for semantic publication or current geometry queries/hit testing runs synchronously under §6.4.1 and is charged to that work. A document with no visual dirtiness, animation, or pending surface event does not continuously redraw.
- Choose and test the application's entry point, native message pump, and Swift main-executor integration on **each** OS. `STNApplication.run` must allow async continuations, timers, native text services, accessibility callbacks, and resize/modal loops to progress. A blocking polling loop on the main actor is not a valid cross-platform implementation.
- Render work is confined to the backend's required context; native-window calls stay on their required thread. Immutable snapshots, typed resource handles, and completion messages cross the boundary—not mutable nodes.
- Decode assets and perform expensive application computation on an explicitly selected worker/actor. Merely writing `Task { ... }` or `async` does not establish that CPU work leaves the UI actor. Swift 6.2 introduces configurable default isolation and `@concurrent`; pin target settings and make worker isolation explicit. See the [Swift 6.2 concurrency changes](https://www.swift.org/blog/swift-6.2-released/).

```swift
// Proposed usage in a UI-isolated async function.
let stnRequest = stnLifetime.beginRequest()
let stnResult = try await stnAssetWorker.loadUser()
// An await allowed other UI work; both lifetime and freshness need validation.
guard stnLifetime.isCurrent(stnRequest) else { return }
stnUser.value = stnResult
```

An actor hop must carry `Sendable` data. A worker cannot smuggle native UI objects or borrowed font/image pointers back in a nominally immutable wrapper. Swift checks do not verify a foreign function's thread-affinity or ownership promises.

### 11.2 Back-pressure and revision ordering

Start with a bounded queue of **one submitted frame plus one replaceable pending complete snapshot per window**; a backend may explicitly negotiate a different maximum in-flight count. Scene construction should be skipped/coalesced when there is no submission capacity, instead of allocating an unbounded series of snapshots. Retire leases for superseded pending snapshots immediately when safe; submitted leases wait for completion.

A newer pending snapshot replaces an older one only with correct accumulated damage (§8.2). Each message carries document/window identity and surface epoch. Ignore a stale completion for presentation state, but still process its resource-retirement obligations. `documentRevision`, `sceneRevision`, backing-store revision, and last-presented revision are distinct diagnostics.

Every scene ordinal maps to a document revision, interaction epoch, and surface epoch; document tags of successive built/submitted scenes must be nondecreasing. For one surface epoch's ordered render stream, confirmed presented scene ≤ completed backing-store scene ≤ latest submitted scene ≤ latest built scene; these are scene ordinals, not logical revision numbers. All map to document revisions ≤ current `L`. Reset/unknown surface history has no comparable presentation watermark until resynchronized. A stale completion cannot move watermarks backward. A logical-only update can advance `L` without requiring a new scene, so freshness is dependency validity plus tags, not equality of all counters.

Queue capacity bounds retained work, not elapsed display delay. Keep only the latest replaceable pending scene, carry damage forward, and apply §6.4.2's interaction-lag diagnostic/priority policy. Never stall logical commits, semantic publication, or accepted actions waiting for presentation. Measure the synchronous geometry barriers and delayed-presentation input behavior, not only queue length; native OS presentation feedback is distinct from submission/GPU completion.

Input and accessibility actions use ordered delivery on the UI executor and are never replaced by a “latest action.” Replaceable state/visual work may coalesce; ordered actions and required native notifications do not. Queue policies are explicit: a suspected action flood reports pressure and throttles acceptance through the host policy rather than silently dropping already accepted commands.

Paused/minimized windows continue to process logical changes and relevant accessibility requests without a GPU frame loop. Frame pacing uses monotonic host time, handles variable refresh rates, and stops animation clocks on disposal. State whether an animation pauses or catches up after occlusion; v1 uses elapsed monotonic time with reduced-motion overrides and no replay of every missed frame.

### 11.3 Window lifecycle and teardown

```text
created → attached → visible/occluded/suspended → closing → closed
```

Close is idempotent and serialized:

1. Transition to `closing`; reject new application dispatch/submission for that window and finish any already-running synchronous commit.
2. Resolve/cancel active composition under the host protocol, release pointer capture, repair/clear focus, and publish final native accessibility teardown while the host objects still exist.
3. Mark root lifetime dead; cancel its subscriptions, timers, effects, and tasks. Invalidate handles so late results cannot remount content accidentally.
4. Drop pending unsubmitted scenes. Ask the renderer to stop using the surface; fence/complete or safely abandon submitted work according to the backend's device-loss contract. Do not block the main actor waiting for a render callback that needs that actor.
5. Detach the accessibility/native providers and render surface in host-required order, then destroy the window and release unshared resources. Shared caches survive only while other owners exist.

Lifecycle transitions, errors, and time spent draining are observable. A hung/lost device must have a bounded, documented abandonment path; never free resources still usable by a healthy GPU queue simply because a timeout elapsed. Multiwindow shutdown does not destroy shared fonts, devices, or assets until the last owner and in-flight lease are gone.

---

## 12. Package organization

```text
Stana/
├── Package.swift
├── Sources/
│   ├── Stana/                  # public builders, components, typed properties
│   ├── StanaCore/              # arena, signals, transactions, scheduler
│   ├── StanaLayout/            # measure/place and layout caches
│   ├── StanaText/              # shaping, font resolution, editing
│   ├── StanaScene/             # display lists and damage
│   ├── StanaGraphics/          # Skia or custom backend adapter
│   ├── StanaPlatform/          # shared platform protocols
│   ├── StanaPlatformMacOS/     # NSWindow, events, Metal surface
│   ├── StanaPlatformWindows/   # Win32 window/events/surface
│   ├── StanaPlatformLinux/     # Wayland/X11 window/events/surface
│   ├── StanaAccessibility/     # semantic tree and native bridge
│   └── StanaTesting/           # headless backend and diagnostics
├── Tests/
│   ├── StanaCoreTests/
│   ├── StanaLayoutTests/
│   ├── StanaTextTests/
│   ├── StanaAccessibilityTests/
│   └── StanaRendererTests/
├── Native/                    # versioned C headers, C++/Rust adapters, build recipes
├── Benchmarks/                # fixtures, runner, raw results, machine manifests
├── Docs/                      # ADRs, support matrix, API/lifecycle contracts
├── ThirdParty/                # dependency lock manifest, notices, artifact checksums
└── Examples/
    ├── Counter/
    ├── Preferences/
    └── LargeList/
```

The internal Swift packages should depend on protocols at boundaries, not concrete SDL3/Skia/AppKit types. Use a small version-pinned C ABI shim for native renderer and accessibility libraries where necessary.

### 12.1 Dependency direction and isolation

These are initially **SwiftPM targets in one package**, not independently versioned packages. Keep `StanaCore` free of layout, graphics, and OS imports; `StanaLayout`/`StanaText`/`StanaScene` depend on core value protocols, not on the public builder facade. Place cross-boundary IDs/geometry and immutable descriptors in a low-level target to avoid a `Scene ↔ Graphics` cycle. Native hosts implement `StanaPlatform`; the public `Stana` facade wires services together. Headless tests select explicit services without loading a window server.

Compile production Swift targets in Swift 6 language mode with concurrency diagnostics treated as errors. Set default-isolation/upcoming-feature options explicitly per target so a toolchain update does not accidentally actor-isolate portable geometry or make UI entry points nonisolated. Keep exported annotations explicit even if an executable adopts default main-actor isolation. Evaluate newer safe low-level facilities only if the pinned toolchain/platform matrix supports them; do not require an unsafe-pointer optimization before profiling it.

### 12.2 Native ABI and build contract

- Expose Stana-owned opaque handles, fixed-width integers, explicit byte lengths/encoding, ABI version queries, and typed result codes. Do not pass Swift values, C++ STL layouts, or Rust-owned structs by value across the ABI.
- Every function declares whether parameters are borrowed or transferred, who frees returned memory, whether it can call back synchronously, and on which thread callbacks/destruction occur. Swift closures retained by C need a context and matching release function; unregister before destroying that context.
- Native exceptions and Rust panics must not unwind across a C boundary. Translate recoverable failures to result codes; document abort-only faults. Check integer/length conversions and allocation sizes on both sides.
- Pin native source revisions, toolchains, build flags, target triples, adapter versions, and checksums. SwiftPM alone is not a build recipe for Skia and Rust adapters. CI must support source builds and verify any distributed binary artifacts against their declared source/build manifest.
- The release matrix specifies OS **and** architecture, minimum deployment version, Swift runtime distribution, CRT/system-library dependencies, signing/notarization where needed, and clean-machine installation tests. Swift's [platform support page](https://www.swift.org/platform-support/) describes language/tooling coverage, not Stana GUI qualification.
- Publish transitive license notices, font redistribution permissions, dependency inventory/SBOM, and a vulnerability-update/rollback process. Verify licenses from the pinned artifacts rather than guessing from repository badges.

### 12.3 Compatibility and asset boundaries

Use semantic versioning for the public Swift API; keep backend details internal and document intentional pre-1.0 breaks with migration examples. The properties-first proposal (§3.0) supersedes the earlier API sketches: move positional content and configuration into `properties: .init(...)`, collect accessibility overrides under `accessibility: .init(...)`, move trailing modifiers to their corresponding fields, and move button action closures to `onActivate:`. Only child builders remain trailing closures on ordinary components; structural primitives retain their explicit branch/row builders. No released implementation exists, so this revision does not require deprecated positional or modifier overloads. A source package does not promise cross-toolchain binary compatibility. Revision/epoch counters must not wrap silently; exhaust/retire the owning runtime or namespace through a diagnosed failure before reuse. Version the C ABI separately; refuse mismatched adapters before creating a surface.

Images, fonts, vector data, and clipboard input are untrusted bytes even in a native app. Decode off-actor with dimension, decompressed-byte, recursion, and time/cancellation limits; malformed input returns an asset error, not a document corruption. Vector assets must not execute scripts or fetch resources implicitly. Network fetching is application-owned/opt-in rather than an engine side effect of rendering a URL. Asset failures have deterministic placeholders and cache invalidation when a later valid resource arrives.

Diagnostics omit text, passwords, clipboard content, and file paths by default. Offer opt-in local traces with explicit redaction; no unsolicited telemetry. Bound caches and retained trace buffers. These are engine resource/privacy contracts, not a claim that all host applications share one threat model.

---

## 13. Testing, diagnostics, and benchmarks

### 13.1 Test the absence of unnecessary work

```swift
@Test
@MainActor
func testSingleSignalWriteDoesNotRebuildParents() async throws {
    let stnHost = STNTestHost()
    let stnCount = STNSignal(0)

    stnHost.mount {
        STNVStack {
            STNText(properties: .init(text: stnCount.map { String($0) }))
            STNText(properties: .init(text: "Static sibling"))
        }
    }

    let stnInitial = stnHost.metrics
    let stnInitialIDs = stnHost.nodeIDs
    stnCount.value = 1
    stnHost.flush()

    #expect(stnHost.nodeIDs == stnInitialIDs)
    #expect(stnHost.metrics.totalMounts == stnInitial.totalMounts)
    #expect(stnHost.metrics.mountedNodes == stnInitial.mountedNodes)
    #expect(stnHost.metrics.builderExecutions == stnInitial.builderExecutions)
    #expect(stnHost.textValues.contains("1"))
}
```

This is a proposed test API. Add explicit counters for computed recomputations, property updates, measure calls, placed nodes, recorded paint items, and semantic changes. API qualification must also compile consumer examples for constant/signal/computed property overloads, two-way bindings, nested accessibility, default properties, and callbacks stored in properties. Verify that callbacks do not run during description construction, activation runs exactly once, `onMount` runs only after attachment, and signal-backed appearance/accessibility updates preserve node IDs without rerunning builders. Include layout fixtures for padding plus frame and explicit nested style layers. Positional content initializers, trailing action closures, unsupported property fields, and trailing component modifiers are not part of the revised API and must not accidentally remain as public overloads.

### 13.2 Benchmarks

| Scenario | Invariant to verify |
|---|---|
| One text update in a 10,000-node tree | No remounts and no unrelated builder executions |
| 100 writes inside one transaction | Each affected consumer evaluated no more than necessary |
| Update only background color | No text measurements or layout passes |
| Keyed list reorder / editable sibling-property change | Stable observable-row editor IDs, focus, selection, composition, undo, local state, and task scope; separately measure intentional value-row replacement |
| Scroll a virtualized 10,000-item list | Bound realization/paint to visible items + overscan; report extent-index and semantic costs separately |
| Repeated mount/unmount | No accumulated subscriptions or GPU-resource leaks |
| Resize/high-DPI change | Correct cache invalidation and repaint |
| Forced full redraw vs incremental redraw | Equivalent pixels for deterministic test fixtures |
| Accessibility-only label change | Current semantic snapshot without visual repaint; report projection/installation cost |
| Geometry change with a large semantic tree | Include required layout in synchronous commit latency; report AT-active and AT-inactive costs |
| Paused/slow renderer with moving controls | Current hit targets/semantic bounds despite old pixels; lag age, barrier cost, and recovery under bounded buffering |

Avoid hard performance claims until hardware, backend, dataset, DPI, font, and profiling methodology are fixed. As reference, 60 Hz has approximately **16.7 ms** between frames and 120 Hz approximately **8.3 ms**, including work outside Stana.

### 13.3 Diagnostics API

```swift
STNDiagnostics.configure(
    trackSignalDependencies: true,
    recordDirtyNodes: true,
    showPaintDamage: true,
    captureFrameTimings: true
)
```

Debug tools should answer: *Which signal changed? Which binding ran? Which nodes were measured and painted? What semantic updates were sent? Why did an ancestor relayout?*

Trace each transaction/frame with window ID, logical/geometry/semantic revisions, interaction epoch, mapped scene/backing-store/presented revisions and surface epoch, input receipt/dispatch timestamps and target ID, phase durations, queue depth, lag age/feedback availability, and cache/resource counters. Split geometry-barrier time, semantic-required layout, projection, snapshot installation, and notification enqueue from deferred visual work; avoid counting the same layout work twice. Distinguish event receipt→commit, receipt→submission, and receipt→presentation feedback. GPU completion is not display presentation; true input-to-photon claims require an appropriate external measurement setup. Instrumentation overhead must be measured and heavy tracing disabled in normal benchmarks.

### 13.4 Correctness oracles and adversarial cases

| Subsystem | Required verification |
|---|---|
| Reactive graph | §6.3 diamond and branch-dependent edge-reversal fixtures in both directions/demand orders; equal-output trace replacement; abandoned-suffix nonvalidation; active/inactive cycles; explicit reads between writes; nested batches; cancellation during queued delivery; effect feedback |
| Tree/lifetimes | Seeded random append/move/remove vs reference tree; duplicate keys and changed observable-row instance rejection; §3.5 sibling update/reorder preserving editor identity, focus, selection, composition, undo, local state and task tokens; unequal-value-row disposal/reset/cancellation; stale/wrong-document handles; generation exhaustion; parent/child consistency; late async completion after unmount |
| Layout | Cached incremental vs uncached full measure/place for identical inputs; min/max/unbounded/overflow; RTL/baselines; ancestor intrinsic-size changes; font/environment epoch changes |
| Scene/damage | Incremental vs full repaint from the same scene/backend; moves/removals/transparency/blur/clips; dropped A→B→C snapshots; unknown buffer history; surface epoch changes |
| Text | Matching Unicode bidi/segmentation/line-break data; golden shaping/range fixtures; index round-trip properties; revision-stale edits; §10.3 IME corpus; native/AT manual scripts |
| Accessibility | Initial tree + delta replay equals full semantic projection; relationship integrity; action exactly once; removal/focus order; query overlapping commit sees one old/new complete snapshot; post-commit provider query sees current bounds; hot AT activation |
| Input/freshness | Forced deferred layout and stalled presentation; old/new-position and overlapping-control clicks; capture/removal; coordinate epochs; current hit-test barrier; dispatch-batch query exception; lag diagnostics and recovery (§6.4) |
| Concurrency/FFI | Swift 6 diagnostics; appropriate Swift/native address/thread sanitizers where supported; teardown with callbacks in flight; no callbacks after context release |
| Fault recovery | Inject device loss, failed allocation/decode, zero drawable, resize/scale races, paused renderer, malformed assets, shutdown with GPU work in flight |

Use seeded generation and save minimal failing mutation/event traces. Reference evaluators must not share the optimized invalidation algorithm they are checking. Pixel comparisons use a deterministic raster backend/font fixture first; GPU/OS-specific baselines need justified tolerances for antialiasing/color differences, not one universal “identical pixels” claim.

The from-scratch consistency oracle is an engineering consequence we draw from [self-adjusting computation semantics](https://arxiv.org/abs/1106.0478), not a formal proof of this implementation. Likewise, [the 2006 experimental analysis](https://www.cs.cmu.edu/~blelloch/papers/ABBT06.pdf) motivates measuring initial-run and bookkeeping costs as well as update speed; its workload speedups are not Stana predictions.

### 13.5 Performance targets and measurement protocol

**Provisional engineering targets, not results:** freeze a representative desktop machine per qualified platform and the fixture manifest at M0. Record any target change in an ADR before interpreting a release run. Beta/1.0 cannot claim a passed target while its machine or fixture is unspecified.

| Metric/fixture | Initial acceptance target |
|---|---|
| One bound color update in a warm 10,000-node tree | Zero remounts, builder reruns, measure calls, and layout passes; only required scene/damage work |
| Batch of 100 writes feeding one diamond graph, no intermediate read | One final publication; each demanded computed evaluated at most once during commit |
| Warm local-update fixture: UI logical commit (including semantic-required layout/projection/installation) + remaining visual layout/recording | p95 ≤ 4 ms at a 60 Hz target, ≤ 2 ms at a 120 Hz target, excluding GPU/OS work; report p99/max too |
| Same fixture: event receipt→presentation feedback | p95 ≤ two target refresh intervals when host feedback is available; label submission-only proxies explicitly |
| Renderer backlog | At most negotiated in-flight submissions + one pending complete scene; zero unbounded growth under a deliberately slow renderer |
| 10,000 mount/unmount cycles after warm-up | Live node/subscription/task/lease counters return to baseline after drain; process memory reaches a documented cache plateau rather than growing with cycle count |
| Idle visible window with no caret blink/animation/input | Zero engine-requested continuous redraws after pending invalidation is drained |

The timing fixture changes one leaf without intrinsic-size propagation; add separate expensive text, resize, scrolling, high-fanout, and worst-case layout fixtures. Do not generalize the local-update target to every 10,000-node operation. Node-storage benchmarks compare class/arena implementations with equal payloads, semantics, and compiler settings.

#### 13.5.1 Two evaluation layers

| Evaluation | Question / evidence | What it does not establish |
|---|---|---|
| Release qualification | Does the pinned implementation meet its fixture budgets and avoid regressions? Compare to its pinned release baseline; report uncertainty around timings and threshold decisions | That this architecture is superior to other architectures |
| Research evaluation | Does the design improve outcomes relative to alternatives, on which workloads, and through which mechanisms? Use matched comparisons, ablations, and effect-size intervals | Universal superiority, or usability from performance alone |

Deterministic invariants (zero remounts, bounded queues, correct output) are direct gates. Timing qualification uses the predeclared workload estimand and a one-sided 95% upper confidence bound against its budget: pass only if the bound is within budget; if the interval crosses the budget, report **inconclusive**, not pass. Apply a declared multiplicity policy for a family of timing gates. Retain per-run distributions and failures. Investigate a >10% p95 regression in a relevant phase or a new memory-growth slope even when absolute budgets still pass; a noisy point estimate is an investigation trigger, not proof of regression.

#### 13.5.2 Run design, warm-up, and uncertainty

For each run record commit, build/binary identity, compiler/native revisions and flags, release/debug mode, CPU/GPU/RAM, OS, power/thermal state, DPI/window size, refresh rate, fonts/locale, AT activation, dataset/seed, input pacing, and cache policy. Save raw ordered event/phase/presentation observations, exclusion reasons, analysis scripts, and the experiment manifest.

1. **Define independent repetition.** An execution-run is a fresh process with freshly mounted document/graph, queues drained before measurement, and restored fixture state/seed. Shared OS/font/shader caches are either intentionally warmed under a recorded policy or reset by a documented cold-start procedure; a process restart does not make them cold. Do not treat several windows or chunks from one process as independent runs. Nest runs within build/session/day/machine levels when those vary, and do not pretend executions in one thermal session are unconditionally independent. Pilot these sources of variation and allocate repetitions at the levels contributing uncertainty. A fixed-binary study limits its claims to that binary unless build variation is sampled.
2. **Randomize/counterbalance order.** Within each machine/session block, run all variants on equivalent fixtures/seeds with fresh processes; randomize their order and counterbalance across blocks. Record the schedule and cooldown/reset policy. Keep paired blocks paired during analysis. Do not always run Stana after a cold baseline, or tune only Stana's fixture/flags.
3. **Demonstrate warm-up.** Five seconds, 1,000 updates, and five runs are pilot starting parameters only. Inspect time series for font/shader/cache initialization, allocation/cache plateaus, CPU/GPU clocks, and thermal drift. Before confirmatory collection, freeze a warm-up rule based on pilot evidence (for example, consecutive fixed windows with stable latency quantiles and cache/allocation levels under declared tolerances), a maximum warm-up duration, and treatment of failures to stabilize. If no suitable steady state is reached, report the nonstationary workload/time course separately; do not discard inconvenient slow segments. Cold mount is a distinct measured endpoint, not warm-up waste.
4. **Specify estimands and precision first.** Declare phase, input pacing/load, p95/p99 definition and quantile estimator, population (for example, equal-duration steady-state runs on one machine), comparative effect (latency difference or ratio), confidence level, desired interval width, and sampling/stopping plan before confirmatory runs. Use pilot variation and a minimum meaningful effect to choose repetitions; retain a fixed confirmatory sample or a valid predeclared sequential procedure. Do not repeatedly inspect conventional intervals and stop when favorable.
5. **Preserve correlation.** Consecutive updates share frame scheduling, caches, and bursts; they are not independent replicates. Estimate correlation times/block lengths from pilots. Use a declared hierarchical/cluster analysis that resamples independent session/build/run units and, when estimating within-run event uncertainty, contiguous blocks long enough to preserve dependence. For paired comparisons resample paired variant blocks together. Report the method, block-length sensitivity, assumptions, and per-run distributions; if too few independent units support interval estimation, collect more or label the result exploratory. An IID bootstrap over all pooled updates is not acceptable.
6. **Report comparative uncertainty.** Report absolute timing distributions and 95% confidence intervals for the predeclared difference/ratio, including p95 effects when claimed. Do not substitute a CI for the mean, an average of per-run p95s, or a ratio of those averages for a pooled-event p95 unless that is explicitly the estimand. Show practical-effect thresholds, negative results, outliers, dropped frames, and missing/censored presentation observations; absence of feedback must not become zero latency. Claims spanning several fixtures must use a declared multiple-comparison policy or be labeled exploratory.
7. **Justify tails separately.** Publish run/event counts, duration, effective independent units/blocks, observed exceedances, and interval widths/coverage rationale for each tail claim. Under an IID approximation, 1,000 samples yield only about ten observations above p99; correlation can make evidence weaker. That count does not validate a p99 improvement. Size tail experiments by pilot/simulation or suitable dependent-data/order-statistic analysis for the target precision, include burst/stress traces, and validate interval sensitivity. Report p99/max descriptively when precision is inadequate; max is an observed extreme, not an estimated worst-case bound.

[Kalibera and Jones, *Rigorous Benchmarking in Reasonable Time* (ISMM 2013; corrected author manuscript)](https://kar.kent.ac.uk/33611/) motivates allocating repetition across sources of variation and reporting effect-size confidence intervals. Its execution-time methodology is not automatically a UI percentile estimator. The clustered, paced, tail-specific protocol above is a Stana requirement whose assumptions and analysis must be justified for the collected data.

#### 13.5.3 Comparative research matrix and semantic cost

Before research claims, pin implementations and publish fixture code for:

- **Full-recompute baseline:** the same retained node/editor identities, input traces, and semantic contract, with fresh evaluation of all demanded bindings and uncached full layout/scene projection at each commit. Do not remount text fields to manufacture an identity disadvantage; compare outputs with Stana's incremental oracle.
- **Comparable reactive toolkit:** Qt Quick/QML is the initial desktop candidate because it already provides property bindings (§1.1). Pin a released version/backend and build equivalent controls, text/editing, semantics, dataset, update pacing, fonts, and window configuration. Record unavoidable differences and run both native-AT and headless/CPU comparisons where meaningful. Do not disable the comparator's normal optimizations or omit its semantics while charging Stana for them. SwiftUI can provide an additional macOS comparison, not a cross-platform proxy.
- **Ablations:** disable layout/text/paint caches by category; split source writes into otherwise equivalent commits to remove batching; replace selective invalidation with conservative all-consumer invalidation while retaining equality/caching. Include the full configuration, one-factor removals, and selected combinations to expose interactions. Preserve observable final-state/action/lifetime contracts and state when an ablation intentionally changes publication frequency. Count edge visits, evaluations, measurements, allocations, mounts, and semantic changes alongside latency/bytes to explain mechanisms rather than infer causes from a single speedup.

Cover cold mount, sparse updates, branch reversal/high fanout, batched bursts, editable row changes/reorders, full-document changes, text-size propagation, resize/scroll, and teardown. Report initial-run/bookkeeping cost and workloads where incremental maintenance loses. Compare equivalent application outcomes, not only Stana-specific builder counters.

**Semantic-publication benchmark:** vary semantic-tree size and geometry-affecting update fanout, AT active/inactive, and renderer fast/stalled. Measure source write→completed logical publication, synchronous geometry-barrier/semantic-required layout, projection/delta construction, adapter snapshot installation, notification enqueue/native receipt where observable, and deferred layout/scene work separately. Compare label-only and bounds/text-range/offscreen changes; charge all forced layout to commit cost without double counting. Research-only semantics-disabled runs may estimate overhead but cannot qualify an accessible release. Publish CIs for semantic overhead and input latency and test whether the synchronous contract still meets budgets. Include physical input-to-photon measurements only when the external setup supports that claim (§13.3).

Parallel graph/layout work is deferred. [Anderson et al. (2021)](https://arxiv.org/abs/2105.06712) derive work/span bounds for a particular parallel self-adjusting system; those results do not transfer automatically to a Swift UI actor or show that parallelization is worth Stana's synchronization costs.

### 13.6 CI and release evidence

- **Every change:** headless core/layout/semantic tests; compile relevant targets/examples in Swift 6 mode; document/API-link checks; deterministic regression fixtures.
- **Native integration changes:** build and smoke-test every affected qualified OS/architecture/backend, including clean-machine runtime/library loading. Run one real native host path; a headless mock is not sufficient.
- **Nightly or scheduled:** seeded fuzzing, mount/unmount soak, sanitizer jobs where supported, Unicode corpus, GPU/raster parity, and benchmark trend capture on controlled hardware.
- **Release candidate:** repeat platform/IME/AT scripts, fault-injection suite, dependency/license review, installer/signing checks, migration examples, and performance report against the release targets.

Attach the test results, fixtures, support matrix, known limitations, raw benchmark data, and build/dependency manifest to the release. This repository currently has none of those executable artifacts; these requirements become work items, not fictitious passing checks.

---

## 14. Implementation sequence and release qualification

Stages are dependency gates, not calendar estimates. Owners below are implementation roles; actual maintainers and supported OS/toolchain versions must be assigned at M0.

| Stage | Deliverable / responsible role | Required evidence to exit |
|---|---|---|
| **M0 — Feasibility** | Platform/graphics/accessibility owners: pin toolchains/dependencies, first host loop and raster path, one accessible button; spike remaining target OSes | Native async wake-up, draw/resize, AT discovery/activation, composition feasibility and clean build on first host; recorded build/host/adapter findings for every intended OS; explicit stop/go ADRs |
| **M1 — Retained core** | Core/layout owners: opaque IDs, class storage, scopes, signals/computeds/transactions, box/stacks/text, basic `If` and keyed `ForEach` | Ordered-validation/edge-reversal fixtures (§6.3), graph/transaction/reference-tree tests; no parent builder reruns on leaf binding updates; conditional/list disposal and stale-result checks; deterministic headless host |
| **M2 — Interaction and semantics** | Input/accessibility owners: buttons, toggles, focus, semantic projection, host adapters | Per-advertised-platform keyboard and AT scripts; action exactly once, delta replay, focus/removal/modal tests, freshness barriers and delayed-presentation dispatch; accessibility available before GPU optimization |
| **M3 — Text and scrolling** | Text/platform owners: shaped paragraphs, scroll, single-line editing, text services and AT editing | §10.3 corpus and matching Unicode tests; range conversions, secure input, undo, clipboard, external updates during composition; observable-row sibling/reorder identity/composition preservation (§3.5); native-field fallback if explicitly selected |
| **M4 — Rendering and resilience** | Graphics/release owners: qualified GPU routes, damage/caches, resource budgets, native packaging | Raster/incremental parity, dropped-frame damage, loss/resize/close tests, bounded queue/memory soak, clean-machine artifact installation |
| **M5 — Scale and extensibility** | Component/tooling owners: custom-component APIs (§18), virtualization, themes, selected animation | External sample custom controls with state/input/semantics/disposal; large-list navigation and AT realization; controlled benchmark reports with uncertainty (§13.5), formative developer tasks (§18.8) and disabled-user task evaluation (§9.7); profiling justifies optimizations |
| **M6 — 1.0 qualification** | Release maintainer with subsystem owners | Every advertised capability passes its matrix; public examples compile; API migration/support docs, dependency manifest, release evidence and unresolved-issue disposition published |

**Smallest useful vertical slice:** one native window with a shaped label and accessible counter button; a click/keyboard/AT action updates the existing label without remounting; resize and close leave no live subscriptions, callbacks, or frame leases. Complete this before expanding the widget catalogue.

### Release tiers

- **Developer preview:** explicitly named experimental hosts/features; no production-readiness or performance claim. Known missing functionality is listed rather than hidden behind a generic “cross-platform” label.
- **Public beta:** M1–M4 pass for each advertised platform and its shipping basic controls, including a production-quality text field or declared integrated native-field fallback. Composition-based reusable custom components (§18) have a tested public path; advanced custom primitives and lazy lists may remain experimental. Accessibility is not optional in beta.
- **1.0:** M6 evidence complete and supported API/capability matrix stable. A platform can remain experimental without blocking qualified platforms, but advertising macOS/Windows/Linux support requires each to qualify independently.

The matrix records OS/version/architecture, Swift toolchain, renderer/backend, window system, text path/IME, AT/version, installer/runtime setup, and component limitations. Unsupported combinations return an explicit capability/error result, not a silently degraded editable or semantic control. Mobile/embedding/rich text require separate gates.

---

## 15. Trade-offs and operational risks

| Risk / trade-off | Failure signal | Mitigation and deciding evidence |
|---|---|---|
| Class records vs arena | Allocation/ARC dominates measured mount/update profiles | Start simple; compare equivalent workloads before storage migration; preserve opaque IDs |
| Fine-grained graph bookkeeping | Edge visits/caches cost more than recomputation, or dependencies leak | Demand-driven evaluation, scope cleanup, fanout/branch-switch benchmarks, graph vs reference tests |
| Keyed scope identity | Duplicate keys, stale captured row values, focus moving to the wrong item | Validate plans before mutation; explicit value-row vs observable-row semantics (§3.5) |
| Native host/Swift integration | Async tasks or IME/AT callbacks stall in resize/modal loops | M0 host-loop spike on each intended OS; no assumptions from macOS behavior |
| Custom-painted text fields | Composition/selection or screen-reader text navigation fails | M3 is a release gate; qualified native-field fallback or withhold unsupported capability |
| Skia/native build footprint | Backend unavailable, binary too large, unreproducible artifacts | Pinned build spike, CPU presentation path, measured package size; retain adapter boundary |
| AccessKit capability mismatch | Required pattern/property/action unavailable in pinned bindings | Minimal custom-control/text spike; contribute/fix upstream or add isolated native shim |
| Incorrect partial repaint | Ghost pixels after move/removal/dropped frames | Backing-store revision and surface epoch tracking; differential full redraw; safe full-repaint fallback |
| GPU resource lifetime | Use-after-free, leak, device-loss/close hang | Frame leases, completion fences, bounded queues, fault-injection and teardown soak |
| Virtualization vs semantics | AT cannot discover/focus unrealized items | Logical metadata plus bounded realization; test large-list AT navigation before release |
| Cross-platform typography | Snapshot/selection drift after font/OS update | Font/database epochs, pinned deterministic fixtures, platform-specific qualification |
| API complexity | Stale builder reads, row resets, lifetime/token errors, or costly debugging despite a public API | Composition-first guide (§18), external samples plus formative error/debugging evidence (§18.8), narrow advanced SPI |
| Freshness vs frame coalescing | Synchronous semantic geometry consumes commit budget; old pixels invite unintended activation | Explicit observer/input contracts (§6.4), lag diagnostics, semantic-cost benchmarks and disabled-user tasks; no claim that all layout is frame-only |

Fallbacks must preserve observable semantics and be diagnosable. “It draws” is insufficient evidence for a control's production support.

---

## 16. Decision register and implementation blockers

Defaults below are proposed architectural decisions, not completed ADR approvals. Resolve blockers with experiments before freezing dependent APIs. The document can proceed without asking the user to decide every implementation detail now.

| ADR | Default / status | Experiment or criterion that resolves it |
|---|---|---|
| **001 — Host/release scope** | Desktop first; first reference host macOS; Windows/Linux target qualification independently | Pin minimum OS, architectures, Swift patch/settings, CI hardware, and native loop integration at M0; no versions implied by `Swift 6+` |
| **002 — Graphics integration** | Evaluate pinned Skia via Stana-owned C ABI, raster first; GPU selection open | Render text/clip/transparency, resize, present, device loss, and source/binary build on each target; record chosen backend family, dependency size and licenses |
| **003 — Accessibility adapter** | Prefer pinned AccessKit/C release pair; unvalidated | End-to-end button + editable field + hot AT activation + teardown; record missing native capabilities and shim strategy |
| **004 — Text stack** | One paragraph/layout/editing abstraction; backend open | Compare qualified SkParagraph/shaping/Unicode stack with native engines for index mappings, fallback, bidi, IME and AT requirements; no “Skia draws text” shortcut |
| **005 — Storage** | Class records for M1; arena deferred | Benchmark allocation, retained bytes, mount/update p95, and iteration costs with identical content/lifetimes; migrate only for demonstrated benefit |
| **006 — Reactive implementation** | Explicit signal/computed/transaction semantics in §6; backend replaceable | Prototype against reference graph. Evaluate Swift Observation/transactional observation as an implementation aid, but require identical scheduling, disposal, equality, and synchronous commit semantics; native observation alone is not the API contract |
| **007 — Layout scope** | Box/stacks/overlay/scroll first; grid/virtualization staged | Differential measure/place tests and dependency/invalidation rules before adding algorithms |
| **008 — Component extension** | Composition-first public protocol; advanced layout/paint/input SPI experimental | Implement §18 examples outside the core target; no access to mutable records/renderer internals; semantics and disposal verified |
| **009 — Theme/native integration** | Stana-themed controls, inherited environment, native interaction conventions | Light/dark/high-contrast/reduced-motion/text-scale/RTL review. Resolve theme tokens without invalidating unrelated geometry |
| **010 — Packaging/API stability** | Source-distributed SwiftPM targets, independently versioned native shim; no plugin ABI promise | Clean-machine installs on qualified targets, reproducible manifest, notices/signing/runtime coverage; explicitly document breaking changes |

Swift's evolving observation and isolation APIs are worth evaluating, but adopting a new language feature does not waive Stana's contracts. The [Swift 6.2 release notes](https://www.swift.org/blog/swift-6.2-released/) document transactional observations and concurrency changes; exact portability and suitability must be tested with the pinned toolchain.

---

## 17. Evidence, academic rationale, and primary sources

**Research reviewed:** 2026-10-21. The following are source-backed concepts; Stana-specific policies and thresholds elsewhere are design decisions. Living documentation and repository `main` pages are not dependency locks. Implementation ADRs must record the actual release/revision, build options, and standard-data versions used. Older foundational research is identified by its original publication date, not the search engine's crawl date.

### 17.1 Research-to-design mapping

| Research | Relevant result or concept | Stana application / limit |
|---|---|---|
| [Acar et al., *An Experimental Analysis of Self-Adjusting Computation*, PLDI 2006](https://www.cs.cmu.edu/~blelloch/papers/ABBT06.pdf) | Dynamic dependencies/memoization have update benefits and initial-run/bookkeeping costs | Benchmark both construction and updates; do not borrow its speedup numbers for UI workloads |
| [Acar, Blume, Donham, *A Consistent Semantics of Self-Adjusting Computation*, ESOP 2007; full version 2011](https://arxiv.org/abs/1106.0478) | Formal correctness/consistency of a particular change-propagation semantics | Motivate from-scratch equivalence oracles; the paper does not verify Stana's runtime |
| [Hammer et al., *Adapton: Composable, Demand-Driven Incremental Computation*, PLDI 2014, §5/Algorithm 1](https://matthewhammer.org/adapton/adapton-pldi2014.pdf) | Ordered dependency checks; first inconsistency triggers outgoing-edge removal and reevaluation | §6.3 ordered validation and edge-reversal fixtures; Stana phase/token/fault policy requires its own verification |
| [Anderson et al., *Efficient Parallel Self-Adjusting Computation*, 2021](https://arxiv.org/abs/2105.06712) | Parallel change propagation with system-specific work/span analysis | Parallelism is a measured future option, not a reason to abandon single-writer correctness |
| [Bahr and Møgelberg, *Asynchronous Modal FRP*, 2023](https://arxiv.org/abs/2303.03170) | Operational guarantees for causality/productivity/space behavior in a modal FRP language | Treat lifetime, clock/event distinctions and retention as explicit contracts; ARC does not inherit the paper's type-theoretic guarantees |
| [Kalibera and Jones, *Rigorous Benchmarking in Reasonable Time*, ISMM 2013, corrected manuscript](https://kar.kent.ac.uk/33611/) | Repetition across variation levels; effect-size confidence intervals | §13.5 separates qualification/research; dependent UI latency tails need additional analysis, not direct reuse of throughput formulas |
| [Green and Blackwell, *Cognitive Dimensions of Information Artefacts: a Tutorial*, 1998](https://www.cl.cam.ac.uk/~afb21/CognitiveDimensions/CDtutorial.pdf) | Vocabulary for hidden dependencies, visibility, and error-proneness | §18.8 formative developer tasks; a discussion framework, not proof of ergonomic quality |

These papers support reasoning and test design. They do not establish that retained-mode signals universally outperform other UI architectures or that a custom renderer is necessarily faster than native controls.

### 17.2 Maintained implementation references

| Primary source | Used for |
|---|---|
| [Swift concurrency language guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html) | Actor isolation, suspension, and `Sendable` boundary concepts |
| [Swift 6.2 release notes — 2025-09-15](https://www.swift.org/blog/swift-6.2-released/) | Default isolation options, `@concurrent`, transactional observations, and safe low-level feature evaluation; not a claim that 6.2 is the latest release |
| [Swift platform support](https://www.swift.org/platform-support/) | Toolchain/platform capability baseline, distinct from Stana host qualification |
| [Skia surface creation](https://skia.org/docs/user/api/skcanvas_creation/) | Raster/GPU surfaces and client-owned context integration |
| [AccessKit upstream architecture/adapters](https://github.com/AccessKit/accesskit) | Push-based semantic updates, actions, adapter capability boundaries |
| [AccessKit C bindings](https://github.com/AccessKit/accesskit-c) | Swift-facing FFI integration candidate and native build requirements |
| [SDL3 event polling](https://wiki.libsdl.org/SDL3/SDL_PollEvent) | Event-loop and thread-affinity requirements when choosing SDL |
| [SDL3 text input](https://wiki.libsdl.org/SDL3/SDL_StartTextInput) | Separate committed/composition events and activation lifecycle |
| [Unicode UAX #29 — Text Segmentation](https://www.unicode.org/reports/tr29/) | Grapheme/word boundaries and matching-version conformance testing |
| [Unicode UAX #9 — Bidirectional Algorithm](https://www.unicode.org/reports/tr9/) | Logical/visual ordering and bidi test data |
| [Unicode UAX #14 — Line Breaking](https://www.unicode.org/reports/tr14/) | Break opportunities, distinct from paragraph width fitting |
| [HarfBuzz shaping clusters](https://harfbuzz.github.io/clusters.html) | Source-to-glyph mappings; clusters are not graphemes |
| [Apple Cocoa Text Architecture: Text Editing](https://developer.apple.com/library/archive/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextEditing/TextEditing.html) | Foundational input-context/marked-text/command model; archived documentation, validate concrete APIs against the shipping SDK |
| [Microsoft Text Services Framework](https://learn.microsoft.com/en-us/windows/desktop/TSF/text-services-framework) | Advanced Win32 text-input integration baseline |
| [Microsoft UI Automation threading](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-threading) | Client/inspection threading hazards; not a provider implementation prescription |
| [W3C WCAG2ICT](https://www.w3.org/TR/wcag2ict/) | Informative application of accessibility principles to non-web software; not usability evidence |
| [W3C WAI: Involving Users in Evaluating Web Accessibility](https://www.w3.org/WAI/test-evaluate/involving-users/) | Complement technical checks with disabled-user evaluation; native task protocol is Stana's adaptation (§9.7) |
| [Qt QML property bindings](https://doc.qt.io/qt-6/qtqml-syntax-propertybinding.html) | Close reactive desktop alternative and candidate matched comparator; pin a release for experiments |
| [Apple: Demystify SwiftUI, WWDC21](https://developer.apple.com/videos/play/wwdc2021/10022/) | Identity/lifetime/dependency comparison without equating view-value reevaluation to control remounting |

## 18. End-user guide: implementing custom components

This section specifies the **proposed extension API** that Stana must make available to application/library authors. It is not an assertion that these symbols exist today. Composition is the supported first path; advanced custom leaf/layout interfaces remain experimental until external examples and qualification tests pass.

### 18.1 Composition-first contract

```swift
@MainActor
public protocol STNComponent {
    associatedtype Content: STNComponent

    @STNBuilder
    func makeContent(in stnContext: STNComponentContext) -> Content
}
```

Built-in primitives provide engine-defined terminal implementations. User components return compositions of those primitives using `some STNComponent`; the protocol is not a requirement to recursively construct content forever.

**`makeContent` is a mount function, not a rerender function.** Stana invokes it once for each mounted instance, scopes its content/lifetimes, and retains the resulting nodes. Signal updates do not call it again. Explicit disposal and a later mount create a new instance of local state. Two occurrences of the same component value create distinct mounted scopes; descriptions are not live node objects and should not cache handles.

Custom components follow the same property rules as built-ins (§3.0): declare a component-specific nested `Properties`, accept it through `init(properties:)`, and put configuration/bindings/callbacks there. The composition protocol does not impose a universal property bag or require access to internal node records. Defaults and any typed reactive overloads belong to the component author. Scope-owned state and context capabilities are runtime resources, not public configuration inputs:

| Component input | Appropriate representation | Behavior after mount |
|---|---|---|
| Immutable title/configuration | Plain value (`String`, enum, configuration struct) | Captured for that mount; not automatically reactive |
| Read-only changing content | `STNComputed<Value>` or signal overload | Bind directly to child properties |
| Editable application state | `STNBinding<Value>` | Child edits write the application's model |
| Local UI state | `stnContext.state(initial:)` | Owned by this mounted scope, disposed with it |
| User action | `@MainActor` callback | Invoked by normal input/AT command path, never by painting |
| Conditional children / collections | `STNIf` / `STNForEach` | Explicit localized structural updates; stable-key rules apply |

Do not put ordinary Swift `if stnSignal.value` around a child and expect it to change later. Do not call `makeContent` manually on each signal write. Do not store mutable global state to simulate per-instance state.

### 18.2 Example: a reusable field with application-owned state

```swift
@MainActor
struct STNLabelledField: STNComponent {
    struct Properties {
        let title: String
        let value: STNBinding<String>
        let onSave: @MainActor () -> Void
    }

    let properties: Properties

    init(properties: Properties) {
        self.properties = properties
    }

    @STNBuilder
    func makeContent(in stnContext: STNComponentContext) -> some STNComponent {
        STNVStack(properties: .init(alignment: .leading, spacing: 8, padding: 16)) {
            STNText(properties: .init(text: properties.title))

            STNTextField(properties: .init(
                value: properties.value,
                accessibility: .init(label: properties.title)
            ))

            STNButton(properties: .init(
                text: "Save",
                onActivate: properties.onSave
            ))
        }
    }
}

// Inside an @MainActor application setup function:
let stnName = STNSignal("")
let stnWindow = STNWindow(properties: .init(title: "Profile")) {
    STNLabelledField(properties: .init(
        title: "Display name",
        value: stnName.binding,
        onSave: { stnSaveName(stnName.value) }
    ))
}
```

These application-local types use internal access. A library publishing the component must also publish its `Properties` type, explicit properties initializer, and `init(properties:)`; Swift does not synthesize a public memberwise initializer.

The component does not copy the name into a second source of truth. `STNTextField` owns caret/composition mechanics while the binding owns committed model text. The save callback reads the latest name when invoked. The visible title is plain mount-time configuration; pass a reactive input and bind both visible/accessibility labels if that title must change after mounting. A future accessibility label-relationship property can replace duplicate label strings without changing the ownership model.

Reuse built-in controls to retain their keyboard, focus, IME, disabled-state, and native semantic behavior. Do not recreate a button by attaching a pointer-down handler to a painted rectangle unless implementing and qualifying the complete control contract deliberately.

### 18.3 Example: mount-scoped local state and derived properties

```swift
@MainActor
struct STNCounterPanel: STNComponent {
    struct Properties {
        let initialCount: Int
    }

    let properties: Properties

    init(properties: Properties) {
        self.properties = properties
    }

    @STNBuilder
    func makeContent(in stnContext: STNComponentContext) -> some STNComponent {
        let stnInitialCount = properties.initialCount
        let stnCount = stnContext.state(initial: stnInitialCount)
        let stnSummary = stnCount.map { "Count: \($0)" }

        STNVStack(properties: .init(spacing: 12, padding: 16, background: .surface)) {
            STNText(properties: .init(text: stnSummary))

            STNHStack(properties: .init(spacing: 8)) {
                STNButton(properties: .init(
                    text: "Increment",
                    onActivate: { stnCount.value += 1 }
                ))
                STNButton(properties: .init(
                    text: "Reset",
                    onActivate: { stnCount.value = stnInitialCount }
                ))
            }
        }
    }
}

// Inside an @MainActor parent builder:
STNCounterPanel(properties: .init(initialCount: 0))
```

`state(initial:)` creates a signal owned by the current mount; its `Equatable` convenience overload applies here. It does not run on every click. Incrementing updates the existing text binding; no parent/custom-component builder reruns. Removing this panel disposes its local state and graph edges. Recreating it starts from its configured `initialCount`; hoist a signal/binding to the application's model if the count must survive removal, lazy-row eviction, or navigation.

The composed text/button semantics already describe this control group. Adding a second actionable semantic parent would risk duplicate activation; apply grouping only when its reading/navigation behavior is intentional.

### 18.4 Lifetime hooks, subscriptions, and asynchronous work

The proposed `STNComponentContext` is a UI-actor-isolated, mount-scoped capability, not access to mutable document records. Its supported capabilities must include:

| Capability | Required semantics |
|---|---|
| `state(initial:equals:)` | Allocate local signal state; `Equatable` convenience; no implicit model persistence |
| `own(subscription)` | Register cancellation with the mount scope; idempotent teardown and no queued delivery after cancellation |
| `onDispose { ... }` | Register synchronous, nonthrowing application cleanup; mark scope dead first, run user cleanup only after the structural commit is consistent |
| `task(operation:onError:)` | Start after successful mount publication, not during pure construction; own/cancel task with scope; operation/error handler use documented UI isolation |
| Request token / `isCurrent(token)` | Validate scope and request revision after every suspension before updating UI state; starting a replacement request invalidates the previous token |
| Environment read/binding | Capture immutable configuration or explicitly observe changing theme/direction/text-scale values with dependency-scoped invalidation |

For a loading component: mount a loading signal and text binding, start a scope-owned task after mount, await an explicitly isolated application service, then check the request token before assigning success/error state. Handle errors explicitly; cancellation does not show a failure message. Never start I/O from a computed, `measure`, `paint`, or semantic query. Do not rely on `deinit` for actor-isolated teardown, and do not make cleanup await renderer shutdown.

A subscription to a non-Stana service must deliver onto the UI actor before changing a signal. Scope ownership avoids an application callback retaining a removed component forever. Temporary hiding does not dispose a component; collapsed/hidden content can remain mounted. `STNIf` branch removal and list eviction do dispose it, according to their respective contracts.

### 18.5 Custom drawing and leaf primitives

Use `STNCanvas` for decorative visualization that can be composed with existing controls and semantic text. For a genuinely new primitive, expose a narrow **experimental** `STNCustomLeaf` adapter rather than subclassing an internal node or borrowing a GPU surface.

A proposed leaf renderer has three pure responsibilities:

```text
measure(value, constraints, environment) -> finite size + baselines
recordPaint(value, placedBounds, environment) -> immutable paint commands
semantics(value, placedBounds, environment) -> semantic descriptor(s)
```

`STNCustomLeaf(properties: .init(value: stnSnapshot, renderer: stnRenderer))` binds an immutable `Sendable` value/snapshot to that renderer. The descriptor never receives a live signal, mutable node record, native window, raw graphics context, or arbitrary retained Swift closure on a renderer thread. Measurement and semantic projection are initially UI-actor work; immutable recorded commands are consumed by the backend. The extension contract leaves room to move pure work later without changing component behavior.

For example, an application-authored progress ring would:

1. Bind a progress signal/computed and validate its finite `0...1` value before publication.
2. Measure to a constrained intrinsic diameter without depending on the previous placement.
3. Record track/fill drawing plus any paint outsets through versioned commands; declare whether a value change affects paint, measure, or semantics. Use conservative invalidation when classification is uncertain.
4. Expose a read-only progress role, accessible name, range/value, and bounds through the semantic descriptor; avoid a second duplicate label/value subtree.
5. Let Stana manage damage, surface scale, resources, and native semantic publication. Never clear the whole window or retain raw GPU resources from the paint callback.

The advanced API must validate sizes, balanced clips, command/resource ownership, and semantic relationships. Debug diagnostics identify the custom component responsible for an invalid result. If `STNCanvas` is purely decorative, explicitly exclude it from semantic traversal; meaningful visualization needs an accessible textual or structured equivalent.

### 18.6 Custom layout and interactive controls

Most layouts should compose stacks/boxes. If composition cannot express the layout, an experimental custom-layout descriptor may measure children through an `STNLayoutContext`, then place them through an engine-owned placement API. It cannot mutate child arrays, invoke builders during measurement, directly set another node's layout record, or assume measurement is called exactly once. Measurement may be repeated with different constraints; cache keys include every environment/value/child input it reads. Declare intrinsic-size dependencies so the engine can invalidate correctly.

A new interactive leaf (for example a range slider) requires more than drawing plus pointer events:

- A binding for committed value and separate transient drag/presentation state if needed.
- Keyboard commands, pointer capture/cancel, disabled and focus-visible behavior, coordinate/clip-aware hit testing, and platform-conventional increments.
- A portable semantic role, name, current/min/max values, supported increment/decrement/set actions, and native capability mapping.
- The **same command path** for keyboard, pointer, and assistive actions, producing one committed update.
- Theme/contrast/text-scale/reduced-motion support and lifetime-safe cancellation.

If the public semantic vocabulary lacks the role/actions, extend and qualify that vocabulary instead of mapping the slider to a misleading button. Portable custom controls must not call AppKit/UIA/AT-SPI directly; isolate an explicitly platform-specific extension if necessary.

### 18.7 How application authors verify a custom component

Use the public `StanaTesting` host to mount the component with controlled signals, drive actions, and inspect committed text/layout/semantics. Before publishing a reusable component:

1. Confirm property changes update existing IDs without rerunning `makeContent`; verify explicit structural changes affect only their scopes.
2. Exercise two simultaneous instances to detect accidentally shared state; remove/remount to check persistence expectations and zero leftover subscriptions/tasks.
3. Check different constraints, long localized labels, RTL, text scaling, high contrast, keyboard traversal, and disabled/hidden/modal behavior.
4. Compare full/incremental paint for custom drawing, including old/new outsets; verify semantic-only changes do not require GPU repaint.
5. Drive native AT actions and query ranges/values on every platform the component advertises. Semantic snapshots alone are insufficient.

Keep these extension examples in a separate consumer/sample target and compile them in CI. An API that only engine-internal code can use is not a completed custom-component feature. External samples establish API sufficiency, not developer comprehension or accessibility usability; those require §§18.8 and 9.7.

### 18.8 Formative developer evaluation (not yet performed)

**Ergonomics is a hypothesis.** The API asks developers to distinguish mount-time values, reactive signals/computeds, two-way bindings, structural scopes, scope-owned state, and request/lifetime tokens. Successful sample compilation only shows that a task can be expressed without privileged internals. Evaluate whether developers predict and debug the behavior correctly.

Recruit Swift developers with varied declarative/reactive experience, including participants unfamiliar with Stana. Use a fixed onboarding guide, public diagnostics, and realistic small tasks in separate consumer targets; record prior experience and assistance. Start with a small formative cohort, revise, then retest with fresh participants. Declare recruitment/stopping rationale and limits; do not treat a convenient small cohort as a statistical population comparison.

| Task | Probe / observable failure |
|---|---|
| Repair a stale builder read | Explain why `STNText(properties: .init(text: signal.value))` freezes after mount; choose a binding/computed; find the missing edge using diagnostics |
| Build an editable keyed collection | Change a sibling property and reorder during editing; preserve editor identity/composition; explain why unequal value rows reset descendants and choose observable rows |
| Choose local-state persistence | Predict move vs hide vs `STNIf` disposal/remount/virtualized eviction behavior; hoist state only when the task needs persistence |
| Cancel/replace asynchronous work | Resolve out-of-order responses and removal during a request; distinguish cooperative cancellation, scope validity, and request freshness without stale publication |

Capture unaided/assisted completion, incorrect predictions, error type/count/severity, time to first correct model, debugging time/attempts, documentation/diagnostic use, moderator interventions, and final explanation of ownership/dependency behavior. Use think-aloud or retrospective walkthroughs as appropriate; report their effect on timing. Save anonymized error traces, not only final working code. Counterbalance task order; if comparing APIs, counterbalance toolkit order and account for prior experience/training. A timed comparative ergonomics claim needs a separately justified sample/analysis plan.

Use [Green and Blackwell's Cognitive Dimensions tutorial](https://www.cl.cam.ac.uk/~afb21/CognitiveDimensions/CDtutorial.pdf) as an analysis vocabulary: **hidden dependencies** (captured vs tracked reads and async freshness), **visibility** (which scope owns state/tasks and which edges are active), and **error-proneness** (plausible code that freezes values or resets editors). These lenses organize observations; they are not a validated numerical ease-of-use score. Identify recurring errors, change naming/defaults/docs/diagnostics, and retest the relevant tasks before API stabilization. Publish unresolved misconceptions and task-specific findings; no developer study or ergonomic advantage is asserted in this specification.

---

**Summary:** Stana's authoring model is declarative, but its runtime is a persistent document with explicit bindings and structural scopes. Production qualification depends on consistent transactions, correct text/semantics, damage/resource lifetimes, measurable budgets, and verified native integration. End users extend the engine through composition and scoped state first, with narrow, qualified layout/paint/input extension points when composition is insufficient.
