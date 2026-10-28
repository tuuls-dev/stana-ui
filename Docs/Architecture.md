# Architecture

## Ownership and dependency direction

All targets belong to one source package and version together. The supported consumer products are `Stana` and `StanaTesting`.

```text
StanaPrimitives                 geometry, colors, opaque IDs, revisions
       ↑
StanaCore                       retained document, graph, lifetimes, input
       ↑
StanaLayout / StanaText / StanaScene / StanaAccessibility
       ↑
StanaGraphics / StanaPlatform  portable service contracts
       ↑
StanaPlatformMacOS → CStanaMacOS (private Objective-C bridge)
       ↑
Stana                           public API and composition root
       ↑
StanaTesting                    deterministic consumer host
```

The diagram expresses layer direction, not every individual import. Core never imports projections, the authoring facade, or native services. Text buffer algorithms do not depend on a window. Scene commands and semantic snapshots are values, not borrowed node/native pointers.

The authoring facade owns `STNPropertyConvertible`, erased `STNProperty` inputs, and shared capability groups. Conversion preserves constants or reactive sources without installing subscriptions. Groups override only specified fields over component defaults; internal node configuration installs subscriptions into mounted scopes. Declarative components never become retained records, and these public types introduce no dependency from Core back to Stana.

## Source organization

`Sources/` groups the authoring API, portable engine, platform backends, and consumer testing support. Existing targets remain the module and dependency boundaries; `Package.swift` specifies explicit paths for nested targets. Organizational folders do not introduce additional modules.

```text
Sources/
├── Stana/                         public authoring API and composition root
├── Engine/
│   ├── Primitives/                StanaPrimitives
│   │   ├── Appearance/
│   │   ├── Geometry/
│   │   ├── Rendering/
│   │   └── Identity.swift
│   ├── Core/                      StanaCore
│   │   ├── Document/
│   │   ├── Input/
│   │   ├── Lifecycle/
│   │   └── Reactivity/
│   ├── Accessibility/             StanaAccessibility
│   ├── Graphics/                  StanaGraphics
│   ├── Layout/                    StanaLayout
│   ├── Scene/                     StanaScene
│   └── Text/                      StanaText
├── Platform/
│   ├── Contracts/                 StanaPlatform
│   └── MacOS/
│       ├── Adapter/               StanaPlatformMacOS (Swift)
│       │   ├── Accessibility/
│       │   ├── Desktop/
│       │   ├── Rendering/
│       │   ├── Text/
│       │   └── Windowing/
│       └── Bridge/                CStanaMacOS (Objective-C)
│           ├── include/           exported C headers
│           ├── Accessibility/
│           ├── Application/
│           ├── Desktop/
│           ├── Rendering/
│           ├── Text/
│           ├── Windowing/
│           └── STNPrivate.h
└── StanaTesting/                  deterministic consumer test hosts
```

Within `Stana`, subdirectories organize related responsibilities:

- `Stana/Application`: public application, window configuration, and window-region API.
- `Stana/Components/Controls`, `Layout`, and `Drawing`: interactive/text controls, layout containers, and rendering components.
- `Stana/Composition`: builders, component contracts, and structural components such as `STNIf` and `STNForEach`.
- `Stana/Runtime/Mounting`, `Editing`, and `Windows`: internal mounted-content, editor, and native-window lifetime coordination.
- `Stana/Desktop`, `Reactivity`, `Styling`, and `Diagnostics`: public desktop integration, reactive property inputs, shared styling, and diagnostics.

`Engine/Primitives/Geometry` holds geometry, affine transforms, and presentation geometry; `Appearance` holds colors and themes; `Rendering` holds GPU values, rendered images, and rendering diagnostics. Smaller subsystem targets stay flat unless a meaningful responsibility grouping is needed.

`Platform/Contracts` contains portable service interfaces and window configuration values. Each native backend owns its Swift adapter and Objective-C bridge together under `Platform`; macOS implementations are grouped by service. Bridge headers in `include` remain C-only, while private headers stay beside their implementations or at the bridge root. Relative private-header imports do not require additional header search paths or expose native types to Swift consumers. No placeholder backends are created for unsupported platforms.

Tests mirror the source areas, while preserving the existing test targets through explicit paths:

```text
Tests/
├── Stana/                         StanaAPITests
├── Engine/
│   ├── Core/                      StanaCoreTests
│   │   ├── Document/
│   │   └── Reactivity/
│   ├── Graphics/                  StanaGraphicsTests
│   ├── Layout/                    StanaLayoutTests
│   ├── Scene/                     StanaSceneTests
│   └── Text/                      StanaTextTests
└── Platform/
    └── MacOS/                     StanaMacOSIntegrationTests
        ├── Rendering/
        ├── Support/               shared native test helpers and GUI gating
        ├── Text/
        └── Windowing/
```

`Tests/Stana` covers authoring and runtime integration; the native test target keeps its existing opt-in GUI gating. Only existing test coverage gets folders, rather than adding placeholders for every source target. Examples, API/fault fixtures, and benchmarks retain their existing package boundaries. DocC and resources stay with `Stana`. Boundary checks use the nested core and adapter target roots rather than assuming every target is a direct child of `Sources`.

See the [documentation index](README.md) for current guidance and [archived plans and design notes](Archive/README.md) for historical context.

## One authoritative document

The UI executor owns the tree, graph, input, focus, and logical commits. Node IDs contain a unique document namespace and a monotonically increasing serial. IDs are never reused; exhaustion is a fatal diagnosed fault rather than wrapping. Class storage is deliberately chosen before arena optimization.

Sources push invalidation through weak reverse edges. Demands validate the old ordered dependency prefix, stop at its first changed output, and reevaluate against current sources after removing obsolete edges. Actual evaluation cycles differ from obsolete validation edges. Equality suppresses output changes, never dependency replacement.

Transactions batch synchronously and do not roll back source writes. All queued binding values are demanded before their deliveries. New structural bindings settle before document publication. Layout needed by hit testing and semantics is current at commit; painting is requested separately. Scope effects run after publication.

## Lifetimes

A mounted scope owns subscriptions, child scopes, tasks, and cleanup. Disposal marks it dead before cancellation, invalidates handles, and queues application cleanup after commit. Request tokens distinguish both scope lifetime and superseded work. Hiding is not disposal; `STNIf` removal is.

Keyed value rows retain their scope but replace descendants when unequal. Observable reference rows retain descendants and require the same instance for an existing key. Duplicate keys and changed observable instances reject the update before tree mutation.

## Projections and native services

Layout measures then places in top-left logical coordinates. Per-node caches are bounded and invalidated through intrinsic-size ancestors. The scene projection is an immutable ordered paint tree: CPU chunks, GPU leaves, and isolated groups. Content and compositing invalidations are separate. A balanced persistent sequence shares unchanged sibling branches; content-only edits patch the leaf and its ancestor chain. Structural and global-environment changes currently rebuild the projection. Flattened commands remain a lazy reference-renderer view, not the production transport.

The macOS adapter sends immutable object deltas to a native serial encoding lane. A device-wide bounded worker pool rasterizes independent CPU tiles into locked IOSurfaces using worker-owned Core Graphics/Core Text objects. Metal imports those same surfaces; no UI-executor raster pass or whole-window CPU upload is required. GPU canvases, custom render/compute programs, isolated groups, and backdrop filters execute in ordered offscreen passes with tracked hazards and distinct read/write generations. The default final backing is damage-updated, tiled, and complete; a measured/hysteretic direct path is available for dense updates. Every acquired drawable is fully reconstructed.

Each isolation context starts transparent. A backdrop captures only its strictly earlier local paint prefix, evaluates the declared finite/nonlocal footprint, and replaces that prefix under the panel mask before later siblings paint. It never reads the drawable or a previous displayed scene. Identity replacement is exact; blur uses a normalized finite separable box kernel. Immutable resource owners retain CPU writers, GPU readers, cached generations, feedback state, and drawable-pool allowances inside a shared device budget. A frame owns its leases until GPU completion, independently of presentation callbacks.

Display-link demand admits preparation before drawable acquisition. At most one preparation and one ready packet per host are retained; newer desired scenes coalesce. A drawable is acquired only after worker, compiler, and offscreen GPU completion. A distinct presentation attempt is confirmed only by joining GPU success with a positive native drawable timestamp for the same epoch/sequence/revision. Zero/missing timestamps remain unknown, bounded history eventually suspends admission, and one presentation-only retry never reruns shader state.

The document publishes one revision-tagged affine/clip geometry snapshot for pointer-local coordinates, hit testing, accessibility, and text-service screen geometry. Ordinary pending events use last-confirmed geometry; unknown changed regions gate location actions. Logical text stays current, but native glyph/caret geometry is not relabeled as displayed when its text revision is incompatible. This is acknowledged last-known geometry, not scanout-atomic input.

SDR CPU tiles retain their encoded-sRGB premultiplied contract. HDR demand promotes the working composite to extended-linear-sRGB half float. Ingress safely unpremultiplies, converts, and premultiplies; only the final output transform applies display-headroom mapping. Public capture returns complete pre-display scene bytes asynchronously, with explicit SDR export available separately.

Native text measurement and drawing both use Core Text. Stana owns editing state and revisioned UTF-8 positions; native adapters convert UTF-16 ranges explicitly. IME marked text is separate from committed model text.

Accessibility elements are separate from drawing nodes. Complete snapshots are installed at logical commits and queried without a synchronous UI-actor hop. Native accessibility actions enqueue the normal Stana command path.

## Current tradeoffs

- Conservative full layout/semantic publication and structural scene rebuilds remain separate from incremental renderer planning.
- Backdrop dependency lookup currently scans the ordered contributors; large dependency-index performance gates are not yet qualified.
- Shader code is trusted application Metal, not a portable shader language or a sandbox. Compilation/binding failure retains a prior valid program; GPU execution failure invalidates the renderer epoch and permits bounded recovery.
- Renderer diagnostics report measured timings, copies, workers, memory, and native timestamps; they are not a performance or physical-display qualification claim.
- Native capabilities sit behind common protocols; additional OS implementations are not stubbed into the public API.
