# Stana hybrid renderer — revised implementation plan

## 1. Outcome and public interfaces

Deliver the complete retained hybrid renderer: tiled CoreGraphics raster surfaces, GPU-backed leaves and application shaders, ordered paint chunks, correct isolated groups, backdrop sampling, compositor-only updates, persistent damage-updated final composites, SDR/HDR output, bounded resources, worker-thread rasterization, and asynchronous presentation.

Preserve Stana’s UI document, signal model, component lifetimes, and subsystem boundaries. Components choose their rendering requirement; the compositor owns presentation.

Backdrop sampling extends the existing ordered compositor and pass dependency DAG; it does not introduce a second renderer or a new document/layout architecture. It enables application-authored Liquid Glass-style effects, backdrop filters, acrylic materials, frosted panels, distortion, and translucent overlays. Deliver the sampling primitive, a finite-radius blur, and custom distortion examples in this implementation; named material presets and exact reproduction of native system materials are not prerequisites.

### macOS 26 baseline and API choices

- Target macOS 26 or newer, matching the package deployment target. Keep the Apple Silicon/M1 acceptance baseline; OS availability does not replace device/format/feature checks. No macOS 14/15 compatibility path is required by this plan.
- Keep the existing `MTLCommandQueue`/`MTLCommandBuffer` API deliberately, not because of the former deployment floor. macOS 26 permits Metal 4 adoption but does not require it. `MTL4CommandQueue` ignores `hazardTrackingMode`; adopting it would require explicit synchronization, resource/residency ownership, drawable signaling, and completion-feedback changes, not a type-name substitution. That migration is outside this implementation. [Apple Metal 4 core API](https://developer.apple.com/documentation/metal/understanding-the-metal-4-core-api), [resource synchronization](https://developer.apple.com/documentation/metal/resource-synchronization)
- Use a view-associated `CADisplayLink` for demand-driven frame pacing and keep drawable acquisition separate and late. Display-link timestamps predict timing; they do not acknowledge presentation. Do not substitute `CAMetalDisplayLink.Update` as a drop-in preparation trigger: it already supplies a drawable, conflicting with the no-drawable-during-preparation contract. [Apple view display link](<https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)>), [Metal display-link update](<https://developer.apple.com/documentation/quartzcore/cametaldisplaylinkdelegate/metaldisplaylink(_:needsupdate:)>)
- `MTLDrawable.addPresentedHandler` and `presentedTime` are available on macOS from **10.15.4**, according to Apple's API availability metadata and the installed macOS SDK's `MTLDrawable.h`. The claim that they are unavailable on macOS does not apply to these declarations. A header diff with no availability change is not evidence of unavailability. Register the handler before presentation and read its drawable's timestamp there; command-buffer completion is never its substitute. [Apple presentation handler](<https://developer.apple.com/documentation/metal/mtldrawable/addpresentedhandler(_:)>), [presentation timestamp](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime)

**Verification status (2026-10-27):** inspected Xcode 27.0 (`27A266a`), macOS SDK 27.0, and Apple's availability metadata for both presentation APIs. A private Objective-C bridge probe calling both on `CAMetalDrawable` passed `clang -target arm64-apple-macos26.0 -fsyntax-only -Wall -Wextra -Werror -Wunguarded-availability`. This verifies declarations and compilation targeting 26, not execution on macOS 26; no macOS 26 SDK or native presentation/window-server probe was run. Native minimum-OS acknowledgement and interaction checks remain explicit delivery gates below.

### Public additions

- **`STNGPUCanvas`**: separate from `STNCanvas`, with constant/signal/computed drawing properties, frame, accessibility, and canvas-local top-left coordinates.
- **`STNGPUDrawing`**: ordered rectangles, rounded rectangles, ellipses, indexed colored meshes, and round-capped/round-joined polylines. Text remains Core Text/CoreGraphics content composed around GPU leaves.
- **Immutable GPU geometry resources**: retain geometry storage with opaque resource identity and immutable version tokens. Replacing geometry creates a new version; callers cannot mutate published storage.
- **Cheap drawing equality**: compare drawing/version tokens, never mesh arrays. Mutating a drawing creates a fresh token; independently constructed identical drawings are not implicitly deduplicated.
- **`STNGPUProgram` and render/compute pass descriptors**: application-authored shader programs with immutable buffers/textures, uniforms, entry points, resource bindings, render state, and dispatch/draw descriptions. Support Metal source and packaged precompiled libraries without exposing native handles or command encoders.
- **`STNExtendedColor`**: explicitly extended-linear sRGB colors for GPU drawings and shaders, with finite signed RGB components representable in half-float and alpha in `0...1`. Preserve `STNColor`'s existing SDR range and meaning.
- **Window rendering color mode**: `.automatic` promotes the window and its hosted presentation surfaces to extended-linear composition when visible content requires it; `.sdr` requests encoded SDR presentation with final HDR tone mapping when needed; `.extendedLinear` explicitly selects floating-point composition. Working color space and output format are separate choices. These are color-output policies, not application-wide CPU/GPU backend switches.
- **`STNLayer`**: explicitly retained subtree with portable affine transform and opacity. Provide constant/signal/computed combinations; transforms do not change layout proposals.
- **`STNBackdrop`**: an explicit effect container with foreground content, output bounds/clip, and a backdrop-effect descriptor. Provide constant/signal/computed effect properties and the same transform/opacity semantics as retained groups. Its source is earlier paint in the enclosing compositing context, not its own foreground or the last displayed frame. Descriptors support a built-in finite-radius blur and application render/compute programs with a named read-only backdrop input, declared sampling footprint, and portable coordinate mapping. Finalize signatures through consumer fixtures rather than exposing native textures or encoders.
- **Scope-owned `onFrame(isActive:_:)`**: cancellable frame registration with monotonic timestamp, target timestamp, and elapsed duration.
- **Testing diagnostics**: expose paint-item/chunk identities, resource generations, revision changes, submission outcomes, backdrop prefix/input dependencies, and renderer counters without exposing native handles.

Existing components and `STNCanvas` remain source-compatible. Metal becomes native presentation on the Apple Silicon acceptance target; headless hosts continue using a recording renderer.

**Required in this implementation:** tiling, persistent damage-updated final composites, arbitrary application shaders, HDR, worker-thread raster execution, and backdrop sampling. Each is a delivery and acceptance requirement, not an optional follow-up or profiling-gated extension.

### Application shader contract

- Programs may define arbitrary application vertex, fragment, and compute functions. Stana describes and schedules the passes; applications own the shader algorithms, not presentation or native resource lifetimes.
- Keep the descriptor/resource interface portable. Shader payloads explicitly identify their backend language or library format; Metal source itself is not advertised as portable to another graphics API.
- Support versioned storage/uniform buffers, sampled and writable textures, samplers, indexed/nonindexed geometry, compute dispatches, function constants, and transient or retained pass outputs. Validate declared bindings, formats, access modes, target sizes, and device capabilities before encoding.
- Compile source and create application pipelines asynchronously off the UI executor, with caches keyed by program version, specialization, color profile, and target format. Load precompiled libraries from consumer package/application resources without assuming a working-directory path.
- Require a pass dependency DAG. Every resource declares read/write access; reject cycles and simultaneous read/write attachment aliasing. Apply the same lease protocol to compute outputs, scratch resources, and retained shader state as to built-in surfaces.
- Programs declare premultiplied encoded-sRGB or premultiplied extended-linear-sRGB output, an HDR source peak when applicable, and conservative output/effect bounds. Unknown or nonlocal shader influence invalidates the complete declared output; do not infer safe incremental damage from changed uniform bytes.
- Shader output remains a component-owned offscreen surface. Programs cannot write the drawable, escape parent clips, reorder siblings, or bypass group opacity. Arbitrary readback uses an asynchronous, version-tagged result rather than a UI-executor wait.
- A backdrop-effect program receives only the planner-selected immutable prefix input described below. Ordinary GPU leaves do not implicitly gain scene access. The binding is read-only and scoped to that effect evaluation, not a native framebuffer handle or a retained state slot; any temporal accumulation must use the explicit state-slot contract.
- Return structured compiler, binding, capability, and execution diagnostics. Keep the last valid program/output during a failed replacement; initial failure reports an unavailable component output rather than silently switching to CPU rendering. A replacement does not become current until its required pipelines and resources are ready.

### Stateful shader and trusted-program contract

- Separate immutable scene inputs from `STNGPUStateSlot` resources. A state slot declares size, format, initializer (zero/upload/initialization pass), and an explicit reset key. Bindings distinguish `previous(slot)` from the current step's output; an ordinary scene resource cannot silently become mutable feedback storage.
- Identify simulation state by `(programInstance, stateEpoch, successfulStep, allocationGeneration)`. `previous` means the last successfully completed simulation step, not the last desired, submitted, or displayed scene. Initialization is step `0`; initialization failure prevents the first update.
- Allow at most one outstanding state-changing step per program instance. A step reads the committed previous generation and writes a distinct ping-pong generation. Retain two generations normally and acquire a third only when an older generation is still leased; otherwise defer without blocking the UI executor. Never update previous-state storage in place.
- Treat previous-step edges as temporal inputs outside the current-step DAG. Current-step producer/consumer edges remain acyclic. Multiple slots publish atomically only after the complete step succeeds; dependent outputs record their state epoch/step explicitly.
- A successful offscreen simulation step advances even if its later presentation is dropped or starved. Retrying presentation of its output must not execute the state update again. Coalesced animation ticks produce one admitted step with actual elapsed time; no implicit catch-up loop.
- Freeze inputs/time for an admitted step. Cancel an uncommitted superseded step; after GPU commit, let it finish and advance its still-current state epoch, then prepare the newest scene. Never relabel its output as a newer geometry/content version.
- Reset through a new state epoch on explicit reset-key changes, successful program replacement, state size/format changes, disposal/remount, or renderer/device recovery. Display headroom changes do not reset scene-referred state. Start the new epoch from its declared initializer; no implicit state migration.
- A failed producer publishes neither its state nor any dependent output. Invalidate dependent prepared packets, drain their leases, and reset affected GPU state through renderer recovery. Late old-epoch completions cannot advance the replacement state. A failed program compilation retains the old program/state rather than resetting it.
- Application shaders are trusted application code, not a GPU sandbox. Stana validates descriptors and resource access declarations but cannot prove shader memory access, effect footprints, or declared radiometric peaks. Incorrect declarations are application errors; validation/debug modes diagnose detectable violations without promising containment.
- The default damage policy for any changed custom program/input/state is its full output. Tile-local/finite-footprint damage is an explicit author correctness promise; unknown or unverifiable footprints disable that optimization. Declared output bounds cannot bypass the component's actual render target, parent clips, or isolation.

## 2. Formal rendering and invalidation contracts

### Paint order and isolation

The paint tree contains ordered CPU items, GPU leaves, groups, and explicit backdrop-effect entries. Traversal order is authoritative; no global `zIndex` sorting.

Use these invariants:

1. Every visible drawing operation occurs exactly once in paint order.
2. Chunking never moves an operation across another operation or group boundary.
3. Subtree opacity applies once to the subtree’s combined pixels.
4. Antialiased clip coverage applies once to the subtree’s combined pixels.
5. A group’s external transform/opacity does not alter its children’s content identities.
6. Ordinary content intermediates contain only their owning subtree. A backdrop input is the sole explicit exception: it is a read-only snapshot of the declared enclosing paint prefix, with its own dependencies and bounds. Backdrop-inclusive results cannot masquerade as reusable source-over child textures.

**Mandatory isolation promotion**

Promote a subtree when it has:

- an explicit `STNLayer`;
- effective local opacity other than `1`, including disabled-state opacity;
- reactive opacity, even while its current value is `1`;
- an independently updated transform;
- rounded, transformed, fractional-pixel, or otherwise antialiased clipping.

A backdrop entry also establishes a mandatory effect/isolation boundary. Capture its input from the enclosing context before opening its own foreground context; isolation must not accidentally turn its input into an empty self-backdrop.

A hard rectangular clip may distribute across descendants only when it is axis-aligned, pixel-aligned in the target pass, and has binary coverage. Otherwise, isolate.

For an isolated group:

1. Render children in order into transparent local storage.
2. Apply the group’s clip coverage once.
3. Apply group opacity once.
4. Transform and composite that result into its parent.

Nested groups retain this order recursively. Ancestor clips remain ancestor operations; they are not baked repeatedly into descendant textures.

Backdrop entries use the replacement/interpolation rule below at their parent boundary rather than source-over compositing a backdrop-inclusive image. Their foreground still observes ordinary subtree isolation internally.

A GPU leaf’s existing surface can serve as its isolated content. Ordinary containers and text do not allocate surfaces merely because they are nodes.

### Backdrop source, evaluation, and compositing

- Define a compositing context as the root host or an isolated group's local target, initialized with that context's clear value. At a backdrop entry, its source `B` is that context's accumulated pixels from strictly earlier paint entries in the same prepared scene, including earlier CPU chunks, GPU leaves, groups, and backdrop results. Exclude the effect itself, its foreground descendants, and later siblings. It is never the previous frame, a completed final composite containing later paint, or an acquired drawable.
- Scope sampling to the nearest enclosing compositing context. An effect inside an isolated group sees that group's earlier local paint, not ancestor/sibling pixels outside the group. An effect wrapping a group may sample the parent prefix before rendering its foreground. Nested effects obey these same rules recursively; there is no implicit ancestor escape or cross-window/desktop/native-window capture. Document this authoring distinction with nested-container fixtures.
- Record a backdrop request with stable effect identity, source-context identity and prefix boundary, input revision, output region, conservative source region, effect/program version, local-to-context mapping, sampling scale/profile, and edge behavior. Map output positions into context coordinates explicitly, including fractional translations, rotation, nonuniform scale, and distortion offsets. Sample outside the context's valid extent as transparent zero; never clamp each source tile independently or expose uninitialized padding.
- Distinguish visible output bounds from source sampling bounds. A finite blur declares its truncated kernel radius; distortion declares maximum displacement plus interpolation/filter support. Expand the source region accordingly before clipping to the context extent, even where contributors lie outside the panel's output clip or normal visible-tile ring. Unknown/nonlocal influence reads the complete context and invalidates the complete effect output. Reject invalid/nonfinite bounds; enforce checked dimensions and normal allocation/admission limits rather than silently shrinking the footprint.
- Materialize only the needed prefix region into a separately leased, sampleable offscreen generation. Finish/store the prefix producer before copy/filter/render consumers; never sample the attachment currently being written. Compose overlapping prefix entries once in order; a tiled source may be gathered into a padded input or accessed through an explicitly tile-aware binding with cross-tile filtering. Do not cull prefix contributors merely because the panel or later opaque paint covers them in final output; sampling dependencies keep them live. Sharing a prefix capture requires matching context, prefix, region coverage, scale/profile, and input versions, not merely overlapping panel rectangles.
- Evaluate `F(B)` in offscreen effect passes, then render foreground `C` over it: `R = C over F(B)`. At the parent boundary use premultiplied interpolation `B' = (1 - w) * B + w * R`, where `w` is the effect's output clip coverage times its opacity. This applies coverage and opacity once to the combined effect/foreground, preserves `B` outside the output region, and makes an identity effect with empty foreground a no-op even over translucent pixels. Do not source-over `R` onto `B`, which would count the captured background twice. Ancestor coverage/opacity remains at the ancestor boundary.
- Use a distinct output generation or a legal ordered replacement pass with blending disabled as appropriate; replacement is not permission to sample/write the same attachment. Effect passes cannot write beyond their output region or bypass ancestor isolation/clips. Backdrop pixels are visual dependencies, not children, hit targets, or accessibility elements; interaction continues using the shared geometry snapshot.
- Tag the input with the context's working color profile and premultiplication contract. Built-in blur filters premultiplied RGB and alpha with a normalized finite kernel and canonical zero-alpha output. Define/freeze its kernel and radius units in consumer/reference fixtures. Custom programs declare matching input/output interpretation; nonlinear color operations safely unpremultiply and repremultiply. Preserve extended values through HDR filtering and apply the final display transform only after all backdrop/foreground composition. Sampling HDR content inherits its HDR requirement; a lower custom source-peak declaration cannot make the sampled prefix SDR.

### Backdrop dependency damage and reuse

- Add explicit same-frame edges from intersecting earlier prefix contributors to each backdrop input, from input/effect parameters to effect output, and onward to parent/final composites and later effects. Paint order makes these edges acyclic; reject self/later-prefix reads. These are spatial dependencies, not `previous(slot)` temporal feedback edges.
- Index requests by source context, prefix position, and source bounds. A contributor change, insertion/removal/reorder, or old/new movement intersecting a request's source region invalidates that input even if the contributor does not intersect the effect's visible output. Later siblings cannot invalidate an earlier effect's source. Propagate changed effect output through later requests in paint order until the affected dependency closure is complete.
- With a declared finite footprint, conservatively map changed source pixels through the filter/displacement support into output damage, intersect with the output region, and then select output tiles/gutters. A reverse influence mapping is a separate correctness promise from a bounded read footprint; if it is unavailable, invalidate the entire effect output for any intersecting source change. Unknown/nonlocal footprints invalidate the complete output. Prefix replay for an output tile may therefore need undamaged neighboring source tiles; final-damage scissoring must not truncate filter inputs.
- Keep ordinary foreground content, backdrop input, effect output, and parent-composite revisions separate. Changing only blur/tint/uniforms reuses compatible foreground pixels but reruns the effect; changing only foreground leaves the prefix input reusable. A backdrop's translation or transform changes its sample mapping/source region and may rerun sampling/filtering even when foreground content and scale are unchanged. Opacity-only changes reuse the effect result and update parent interpolation. Moving a containing group reuses its local backdrop results when local source/mapping/profile remain unchanged.
- Cache prefix/input tiles and effect outputs by their actual dependency versions, not by the last presented scene or a blanket global scene revision. Reuse unchanged disjoint requests without rerecording their foregrounds. Eviction, missing prefix history, incompatible scale/profile/epoch, or unknown damage requires prefix/effect reconstruction before publication; never copy stale final pixels as a substitute for the current prefix.
- A failed effect-program replacement retains the prior valid program. Reuse its prior output only while its source/mapping/parameter versions still match; otherwise evaluate that program against the current prefix or keep the last coherent frame. Compilation failure is not permission to attach stale sampled pixels to a new scene.

This is a targeted extension to retained planning: a backdrop request, ordered prefix producers, explicit dependency edges, and effect passes use the same resource leases and scheduler as existing intermediates. No independent screen-snapshot subsystem is introduced.

### Chunk formation

Within each group, accumulate consecutive CPU items. Flush before a GPU leaf, isolated child group, or backdrop entry, emit that entry, then resume CPU accumulation. A backdrop prefix boundary must never fall inside an already flattened CPU chunk.

- CPU items contain independently balanced local drawing state.
- Hard rectangular clips do not force one chunk per node.
- Chunk identity uses containing-group identity plus a stable anchor paint item.
- Membership changes invalidate the affected chunk’s backing, not unrelated chunks.
- Bounds include conservative ink/antialiasing extents and transparent sampling gutters.
- Allocations cover relevant visible paint bounds, not an entire window by default.

### Separate revision domains

Retain these independent revisions:

| Revision         | Changes when                                                                                                        |
| ---------------- | ------------------------------------------------------------------------------------------------------------------- |
| Content          | Drawing commands, geometry version, text, resolved colors, or size-dependent paint changes                          |
| Geometry         | Placement, transform, bounds, or required raster scale changes                                                      |
| Mask             | Clip shape, mask pixel grid, or clip-to-target mapping changes                                                      |
| Backdrop input   | Selected enclosing prefix pixels, source region/mapping, sampling scale/profile, or source-context identity changes |
| Composite        | Ordered child inputs, their selected versions, or local compositing parameters change                               |
| Output transform | Current EDR headroom, final display transform, or output format changes                                             |
| Final backing    | Complete-scene baseline, per-tile content validity, and accumulated final-composite damage change                   |
| Surface epoch    | Host rendering configuration or resource validity is reset                                                          |

A group’s external translation/opacity changes its parent’s composite input, not its own content. Moving a child inside an intermediate group invalidates that intermediate’s composite result, but not the child’s pixels.

For backdrop entries, source changes advance backdrop-input/effect-output dependencies without advancing foreground content. External movement can change sampling even when content is stable; the compositor-only reuse guarantee does not imply zero backdrop-filter work.

Moving a group together with its local mask reuses both. Changing an ancestor clip updates that ancestor’s mask/composite dependencies without repainting descendant content.

### Shared presentation-geometry projection

Here, **confirmed presentation** means the platform reported a positive presentation timestamp for the matching successful attempt. The selected snapshot is **last presentation-confirmed geometry**, not proof of the pixels physically visible at the instant of an input event. Notification delivery and UI-executor publication can lag display, and a later submitted frame can appear before its acknowledgement is processed. This plan guarantees revision-coherent, last-known interaction with conservative gating on acknowledgement failure, not scanout-atomic/pixel-perfect event routing or visibility through occluding windows. GPU completion, a display-link tick, a requested presentation time, and a Core Animation transaction completion cannot establish that stronger guarantee.

- Produce one immutable, revisioned geometry snapshot from layout plus retained transform/clip state. Store stable node identities, logical bounds, local-to-host transform chains, inverses where valid, clip ancestry, text-layout revision, and conservative projected ink bounds. Rendering, hit testing, pointer coordinates, accessibility, selection, and IME use this same projection rather than independent matrix calculations.
- Define local, host-content, and screen coordinate spaces explicitly. Convert native screen origin/axis conventions only at the platform boundary. Apply affine transforms in ancestor-to-descendant order; evaluate rectangular/rounded clips in each clip owner's local coordinates.
- Hit test in reverse paint order using inverse-transformed points and the entire clip chain. Pointer capture retains identity, not an outdated inverse matrix; each delivered event includes local coordinates from the selected geometry snapshot and still validates current scope/eligibility.
- Keep `STNNodeHandle.bounds()` as committed layout bounds. Add separately named optional presentation bounds tagged with the last presentation-confirmed geometry revision and acknowledgement status; do not silently change the existing API's coordinate semantics or call last-known bounds current scanout bounds.
- Layout/desired geometry continues updating while raster workers run. Native pointer targeting and location-bearing accessibility/IME queries select the last presentation-confirmed snapshot, atomically advanced only after the matching positive timestamp and successful onscreen GPU attempt are both known. Preparation, submission, or GPU completion alone cannot move that snapshot. Headless tests inject explicit presentation outcomes to exercise this policy; their synthetic acknowledgements are not native feasibility evidence.
- Check current document lifetime/eligibility before delivering against displayed identity. Removed or disabled nodes stop receiving events immediately even if old pixels remain visible; newly mounted nodes have no native displayed target until their first confirmed frame. Semantic values may update logically, but their location is tagged with the displayed geometry revision.
- Publish transformed axis-aligned accessibility bounds, with clip-aware offscreen state; input uses exact inverse/local clip tests, not those axis-aligned bounds. Project text selection/caret rectangles through the same matrix chain; native IME rectangles are screen-space enclosing rectangles of those transformed shapes. Native AX/IME rectangle APIs receive last-known compatible rectangles while acknowledgement is pending/unknown; internal diagnostics retain their revision/status rather than claiming the native APIs expose that status or guarantee current pixels.
- Match text geometry with its text-buffer/layout revision. Reject stale selection commands through the existing revision checks; when the requested text position has no matching displayed geometry, return the last valid caret rectangle and request a frame instead of indexing unrelated glyph offsets.
- Treat a transform as noninvertible when its determinant is zero or its normalized inverse is nonfinite. Such a subtree has no drawable/hittable area and is accessibility-offscreen. Cancel pointer capture on disposal immediately or when confirmed geometry becomes noninvertible; keyboard focus remains governed by logical eligibility.
- Out-of-order presentation callbacks never roll confirmed geometry backward. During ordinary pending presentation, continue using the last confirmed snapshot and tag delivered pointer-local coordinates with its revision; acknowledge that this can lag current pixels. Do not freeze all moving controls merely because another frame is pending. If acknowledgement becomes unknown while geometry differs, retain last-known geometry, diagnose/recover, and suspend new location-targeted actions in ambiguous old/new changed regions; unchanged regions and keyboard input continue. Identity-based pointer capture remains lifetime-checked, and location-dependent captured actions in those ambiguous regions are suspended too. Do not replay a deferred click later against a different target or clear ambiguity using an unrelated/older acknowledgement. Never promote a guessed snapshot or silently switch to latest logical geometry. This is a defined last-known/failure policy, not proof of scanout/event-time identity.

### Incremental paint-tree projection

The current aggregate dirty flags are insufficient. Extend `Document.changed` with a coalesced, per-node change journal while retaining aggregate flags for scheduling.

- Record content, geometry, compositing, structural, and environment invalidation separately.
- Journal creation, removal, reparenting, and reorder explicitly.
- Have layout report nodes whose actual bounds changed; layout invalidation alone must not force every node’s paint commands to be reconstructed.
- Record old/new focus and pressed nodes directly rather than treating those changes as blanket root repaint requests.
- Maintain retained paint entries indexed by node identity and node-to-chunk membership.
- Patch dirty entries and affected ancestor summaries using structurally shared immutable snapshots.
- Keep inherited transforms/clips as references to retained group state; avoid materializing changed ancestor state into every descendant item.
- Maintain bounds indexes for damage queries so raster preparation can select intersecting items without rebuilding all drawing commands.
- Maintain the backdrop request/dependency index alongside paint bounds; patch affected prefix ranges on structural changes and propagate spatial input damage without reconstructing unrelated subtrees.

A content-only leaf update may revisit affected ancestor summaries and its chunk’s relevant damage entries, but must not reconstruct unrelated paint subtrees.

Full traversal remains valid for initial mount, explicit full invalidation, and genuinely global environment changes. Initial/invalid final backings and conservative full damage may require full visible-scene composition; ordinary small updates must use retained final-composite damage rather than always rebuilding every visible pixel.

For `n` paint entries, depth `d`, dirty entries `m`, and intersecting replay items `k`, use balanced ordered child sequences with cached aggregates and a balanced bounds index. A content-only leaf records one paint entry, updates at most `d` ancestor aggregates in `O(d log n)` work, and updates its bounds index in `O(log n)`; do not copy or rescan full sibling arrays. Coalesce shared ancestor work for multiple dirty leaves; prohibit quadratic-in-depth reconstruction. Damage queries record index visits and replay only returned intersecting items; fully overlapping content may legitimately require `k = n` replay but not `n` paint reconstructions. Enforce the existing 512-level layout/paint depth budget and test depths 128, 256, and 512 plus broad 10,000-child trees.

Those bounds describe ordinary paint-entry projection. Backdrop dependency propagation may additionally touch every genuinely affected request and its composite ancestors; measure that work separately from content recording. Use indexed spatial/prefix queries rather than scanning all requests for each dirty leaf, and coalesce shared dependency/ancestor work. A broad filter can legitimately expand replay, but cannot justify rerecording unchanged foregrounds or an unconditional full-tree/request scan.

### Tiled backing and damage

- Use a stable surface-local pixel grid with 512 × 512 core tiles. Tile CPU chunks/masks when either dimension exceeds 1024 pixels or area exceeds one million pixels; smaller surfaces use one allocation. Persistent-final backing uses tiles at the same threshold.
- Classify isolated GPU groups rather than tiling solely by size. Keep a group contiguous when it fits checked dimensions and 64 MiB, unless at least 30 sampled frames show mean damaged area below 25% and its area exceeds one million pixels. Tile groups exceeding those limits or requiring viewport-local residency. A tiled group may return to contiguous storage after 30 frames above 60% damage if it fits; require 120 frames between nonmandatory mode changes. Mode switches reconstruct a coherent backing and preserve isolation.
- Key tiles by logical surface, coordinate, scale level, color format/profile, and content generation. Anchor the grid to stable local coordinates, not the changing damage or visible rectangle.
- Allocate visible tiles and one neighboring prefetch ring, subject to the memory budget. Release offscreen unleased tiles through the cache policy; newly exposed or evicted tiles require complete reconstruction.
- Add a two-device-pixel sampling gutter, enlarged to a pass's declared finite sampling footprint where needed. Render gutter pixels from the same scene, sample only each tile's core, and never composite gutter overlap twice.
- Expand damage by stroke/antialiasing/effect bounds before selecting tiles. Updates crossing boundaries dirty all affected cores and gutters; clear/replay intersecting content in paint order.
- Apply group opacity and mask coverage once per output pixel after rendering that group's content; tiling must not become separate per-child opacity or repeated edge coverage.
- GPU programs default to whole-surface execution because arbitrary compute/fragment algorithms can have nonlocal dependencies. They may explicitly declare tile-local execution and a finite input halo to participate in tiled dispatch. Nonlocal programs remain fully supported as whole-surface passes within checked device/allocation limits; never silently tile an incompatible shader.
- Backdrop input halos are source requirements, not repeated output coverage. Reserve/reconstruct all required neighboring prefix tiles even beyond the normal prefetch ring, then filter into each output core without seams or duplicated opacity. A large finite footprint may require multistage scratch; a nonlocal effect requires its complete declared source/output working set and cannot be silently approximated as independent tiles.
- Maintain a bounded journal of final damage. If a cached backing predates the available journal or has incompatible scale/profile, mark it fully invalid rather than dropping damage.

### Persistent damage-updated final composite

- Retain a complete per-host final-composite backing, tiled under the same policy. Its pixels are authoritative offscreen scene output; drawables are only presentation destinations.
- Final damage includes changed content, old/new projected ink bounds for movement/removal, clip/mask changes, shader influence, backdrop dependency closure, and affected ancestor intermediate outputs. Working color-profile changes invalidate affected final tiles; display headroom/final tone-mapping changes do not invalidate scene-linear final pixels.
- For each damaged final tile, clear damaged pixels and replay every intersecting composite entry in exact paint order, including unchanged background/overlapping entries. Use full reconstruction where damage is unknown or a tile has no valid baseline.
- Backdrop replay reconstructs the needed earlier prefix before evaluating each effect, including source halos outside that final tile's damage. Retained final pixels may already include the effect or later siblings and are not a valid prefix baseline without explicit prefix provenance.
- Never mutate a final backing while a previous presentation packet reads it. Reuse unchanged tiles read-only; for changed leased tiles acquire a new generation and copy the valid baseline before applying partial damage, or fully redraw that tile. Missing baseline pixels cannot be left undefined.
- Publish the new coherent final tile map only for the matching prepared scene and successful producer dependency chain. Keep GPU completion, final-cache validity, and presentation acknowledgement distinct.
- Present by clearing the new drawable and copying/compositing every visible final tile. Do not apply only window damage to an arbitrary drawable, and do not rebuild unchanged final tiles merely because a new drawable was acquired.
- Include baseline-copy bytes, final tiles/regions redrawn, and presentation-copy cost in diagnostics. Capture/readback samples the complete persistent composite, including custom shaders and HDR content.

Use a measured final-pass selector, not an assumption that persistence always wins. Sparse scenes use persistent damage updates. After eight consecutive frames with at least 60% damage, allow direct full-frame composition if measured GPU cost or bandwidth is lower. In SDR compatibility mode it may render directly into the drawable after offscreen producers finish. In linear/HDR working mode it must first compose into a transient complete linear target, then apply the final display transform in the late presentation copy; do not tone-map separate children to avoid that pass. Return to persistent mode after 30 frames at or below 20% damage, require 60 frames between discretionary switches, and rebuild the final baseline from current content/journal before resuming partial updates. Direct frames mark affected persistent tiles stale rather than falsely acknowledging them. Both paths are required, share geometry/color/isolation semantics, and are tested against one another; the direct path does not defer or remove persistent-composite support. A direct-SDR capture explicitly constructs the requested complete offscreen result.

Estimate each path using pass/pixel/copy-byte counts until it has timing samples; then use per-profile GPU-time EWMAs with weight `0.2`. Record every selection reason and the reconstruction cost of switching. Benchmark both forced modes to check that the adaptive selector is choosing a genuinely competitive path, not merely satisfying a damage-percentage heuristic.

Direct mode must preserve backdrop semantics too. Prepare all prefix captures and effect outputs offscreen before drawable acquisition. A backdrop-enabled direct SDR frame uses a complete transient offscreen composite, just like direct linear/HDR mode, then copies it onscreen; it never captures/samples the drawable or inserts filter work after acquisition. Include that extra target/copy in selection and admission costs. The no-backdrop direct SDR fast path remains available.

### Presentation batching and bandwidth admission

- Batch final tile quads in one render encoder/pipeline per output profile, binding up to 16 source textures per draw and supplying per-instance destination/UV data. Disable blending for the full final copy, avoid one encoder/draw per tile, and preserve sampling gutters. All sampled resources remain explicitly declared to Metal.
- Count baseline copies, offscreen writes, final reads, and drawable writes separately. The unavoidable HDR final-copy floor is `width * height * (8 + 8) * fps` bytes/second; for 5120 × 2880 at 120 Hz this is approximately 28.3 GB/s before other work. Do not describe a full-window copy as negligible.
- Count backdrop prefix replay/copies, halo gathers, filter reads/writes, replacement passes, and scratch traffic separately. Include them in total GPU-time/bandwidth estimates and the device admission ledger; overlapping panels do not make repeated captures free.
- Calibrate effective GPU copy bandwidth once per device in the background with at most 64 MiB scratch charged to the aggregate budget, and cache the result. Limit aggregate admitted presentation-copy traffic to 25% of that measured bandwidth, including all visible hosts; use actual format sizes and selected refresh divisors.
- Prefer the cheaper correct final path when the copy budget or GPU-time gate would be exceeded. If neither path fits, lower presentation rate to the highest display refresh divisor that meets the budget; coalesce intermediate visual ticks instead of building a queue. Keep input/commit processing unthrottled, report the chosen rate/reason, and never silently miss a claimed refresh-rate target.
- Enforce the latency/rendering-cost gates in Section 5 for 1080p, 4K, and 5K SDR/HDR workloads, including 60/120 Hz where the display supports them. Record GPU timestamps rather than inferring bandwidth from CPU submission duration.

### Independently executable raster jobs

Create immutable `RasterJob` snapshots containing resolved commands, selected immutable assets, tile/core/gutter bounds, raster scale, damage, expected backing baseline, and host/scene/resource generation tokens.

They must not capture document records, signals, window objects, actor-bound closures, or mutable image-cache state.

Refactor native drawing functions to target a raster surface/context rather than retrieve `window.backing`. Each job uses its own exclusively leased context. Asset resolution and image-decode notifications occur outside raster execution.

Execute raster and image-decode jobs on one process-wide pool shared by all windows, with `W = max(1, min(4, activeProcessorCount - 1))` workers and at most `2 * W` runnable queued jobs globally. Maintain lazy per-host work cursors rather than enqueuing all tiles. No CPU painting, image decoding, or shader compilation runs on the UI executor. A serial worker mode remains available for deterministic tests, not as the production implementation.

- Schedule visible hosts with deficit round-robin using estimated tile/command cost, with focused-host weight 2 and other visible-host weight 1. Admit at least one job from every runnable visible host per round before spending surplus weight; hidden prefetch gets no work while visible demand exists.
- When multiple hosts are runnable, cap one host at `max(1, ceil(W / 2))` active workers. Newly runnable hosts take the next available fair slot; cancel obsolete prefetch rather than letting a large window occupy the global queue. A running noncooperative draw is not forcibly interrupted, so fairness latency is bounded by running-job duration plus scheduler rounds, not by a false preemption guarantee.
- Use one process-wide shader compiler lane with version-coalesced pending requests and fair host order. Its internal Metal compiler threads are outside Stana's worker-count claim and are measured separately.

- Give each active job an exclusive native surface/context lease; no `CGContext` or mutable Core Text layout object is shared across jobs. Construct thread-confined text layout state from immutable text/font inputs and explicitly owned assets.
- Keep document/native-view access, cache policy, and resource bookkeeping on the UI executor. Implement worker dispatch and opaque native ownership in the private bridge; return completion tokens to the UI executor without `@unchecked Sendable` or actor-isolation escape hatches.
- Cancel superseded queued jobs before execution and check cancellation between paint items for running jobs. Dispose/resize/profile changes invalidate publication tokens immediately; cancellation never releases an allocation before its running writer exits.
- Reuse completed work for a newer desired scene only when resource identity, content version, scale, dimensions, and color contract still match. Otherwise discard the result and release its lease.
- Await the required raster results asynchronously, leaving input and logical commits responsive. Freeze a coherent scene version for submission; do not mix results from incompatible layout/clip generations to finish sooner.
- Resolve image-cache state outside jobs. Image decode completion invalidates affected asset users through the normal document path, never by invoking a window callback from a raster worker.

Core Text functions are thread-safe, but individual mutable layout/context instances remain confined to their job. [Apple Core Text documentation](https://developer.apple.com/documentation/CoreText?language=objc)

## 3. Native formats, resources, scale, and memory

### Exact pixel contract

Implement two working profiles: encoded-sRGB SDR compatibility and scene-linear extended-sRGB HDR composition. Select the working profile from content/policy, and select the drawable format independently from output policy/display. Explicit SDR output with HDR content still composites in linear half-float before its final SDR display transform. Propagate configuration consistently to the window's hosted presentation surfaces.

| Resource                                                                       | SDR compatibility profile                                  | Extended-linear/HDR profile                                                                                                                     |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| CoreGraphics backing                                                           | BGRA bytes, 8-bit, premultiplied-first/little-endian, sRGB | Same SDR raster storage, explicitly converted at GPU ingress                                                                                    |
| Raster Metal texture                                                           | `MTLPixelFormatBGRA8Unorm`                                 | `MTLPixelFormatBGRA8Unorm`, tagged encoded SDR input                                                                                            |
| GPU leaf/resolve texture                                                       | `BGRA8Unorm` for encoded SDR-only content                  | `RGBA16Float` for linear/extended output; encoded SDR sources remain explicitly tagged inputs                                                   |
| Converted source, group, backdrop prefix/effect, and persistent-final textures | `MTLPixelFormatBGRA8Unorm`                                 | `MTLPixelFormatRGBA16Float`                                                                                                                     |
| Drawable                                                                       | `MTLPixelFormatBGRA8Unorm`, sRGB layer color space         | `RGBA16Float` with `kCGColorSpaceExtendedLinearSRGB` and EDR enabled; explicit `.sdr` output instead uses `BGRA8Unorm` with final sRGB encoding |
| Coverage mask                                                                  | `MTLPixelFormatR8Unorm`, scalar coverage                   | Same; coverage has no color transfer function                                                                                                   |
| MSAA color attachment                                                          | Match its pass's color/resolve format                      | Match its pass's color/resolve format                                                                                                           |

Do **not** substitute `_sRGB` texture views or attachments for these formats: those introduce implicit transfer-function conversion. Conversion is explicit at source boundaries, not an accidental sampler/attachment behavior. [Apple pixel-format documentation](https://developer.apple.com/documentation/metal/mtlpixelformat/bgra8unorm?language=objc)

- In the compatibility profile, RGB is encoded-sRGB and premultiplied by linear coverage alpha. Preserve existing SDR appearance and the reference tolerances below.
- In the HDR profile, composition RGB is linear extended sRGB, with `1.0` representing SDR reference white and values above `1.0` representing extended brightness. Blend and interpolate premultiplied colors in that linear space.
- Converting premultiplied encoded input requires safe unpremultiplication, sRGB decoding, and repremultiplication; zero-alpha input becomes zero RGBA. Perform the inverse operation only when producing encoded SDR output. Never decode already-premultiplied RGB as though it were straight color.
- CPU chunks preserve CoreGraphics' SDR rasterization semantics internally. Linear HDR composition applies between surfaces; do not claim this retroactively changes the blending of overlapping commands already flattened by CoreGraphics. Extended colors and HDR images/program output enter through GPU surfaces rather than the existing SDR `STNColor` API.
- Ordinary SDR UI white and a shader's scene-linear `1.0` are identical reference white in the linear working composite. Retain the persistent final composite scene-referred, before display tone mapping; never tone-map individual sources automatically. A headroom change updates the final presentation transform without repainting CPU content, advancing shader feedback, or recomposing linear intermediates.
- Convert imported SDR/HDR textures according to declared primaries, transfer function, alpha mode, and HDR source peak. Support explicit metadata for application texture data; decoded images use asset metadata. Do not normalize HDR sources into an 8-bit SDR intermediate.
- Query current display EDR headroom on screen/brightness changes and each admitted HDR frame. Headroom is at least `1`; a non-EDR display uses `1` while the floating-point working path remains valid.
- Use `H = 1` for explicit SDR output, otherwise current display headroom. Replace the prior per-source extended-Reinhard mapping with one fixed final shoulder: let `K = min(1, 0.75 * H)` and positive straight-RGB maximum be `L`; `F(L) = L` for `L <= K`, otherwise `F(L) = K + (H - K) * (L - K) / ((L - K) + (H - K))`. Scale RGB by `F(L) / L`, handle zero explicitly, and leave alpha unchanged. Safely unpremultiply before this nonlinear transform and repremultiply afterward. Final SDR output then applies the sRGB transfer function; floating-point EDR output stays linear.
- This intentionally compresses near-white values for constrained HDR-to-SDR output: with `H = 1`, scene `1.0` maps to `0.875` for both ordinary UI and HDR-source pixels; `0.18` remains `0.18`. With `H = 2`, scene `1.0` stays `1.0` and `4.0` maps to `1.75`. Pure SDR compatibility output bypasses the HDR shoulder and preserves legacy white exactly. Do not claim simultaneous exact SDR-white preservation and highlight separation at headroom `1`.
- Apply the display transform after subtree composition, not independently before source-over blending. Provide numerical/overlap fixtures comparing the rejected source-first mapping against final mapping before freezing the implementation; specifically catch the former `P = 16, H = 1, L = 1` result of approximately `0.502`. Custom shaders can deliberately implement their own artistic mapping, but their declared output is still interpreted as scene-referred input to this pipeline.
- Use declared finite source peak metadata for validation/diagnostics, not a content-varying exposure adjustment; default to `16` for an HDR asset without peak metadata. Do not make brightness pump merely because the observed image maximum changes.
- Cache linear ingress conversions by source version and working profile. Headroom/final output-transform changes update the presentation pass only; changing the working profile invalidates dependent intermediates/final tiles. HDR readback exposes both raw scene-linear content and explicitly display-transformed exports, without reapplying tone mapping to already mapped pixels.
- Opacity/masks multiply RGB and alpha.
- Blend RGB and alpha using `one` / `oneMinusSourceAlpha`.
- Transparent gutters contain zero RGBA; sampling clamps to valid padded extents.
- A profile change drains or retires incompatible generations, updates layer configuration before acquiring its next drawable, and fully rebuilds format-dependent final storage. Do not reuse SDR bytes as half-float content or tone-map a retained source twice.

Use floating-point drawables with an extended-linear layer color space and `wantsExtendedDynamicRangeContent` for EDR presentation. [Apple EDR/tone-mapping documentation](https://developer.apple.com/documentation/metal/performing-your-own-tone-mapping)

IOSurface allocations use actual aligned stride and allocation size, with checked arithmetic. Lock once per raster job, draw/flush, then unlock before publication.

### Automatic profile hysteresis

- Start `.automatic` in compatibility mode for SDR-only content. Promote when the first visible extended-source requirement is committed; do not wait for a brightness threshold or measured pixel scan.
- Retain linear working mode for at least five seconds after promotion and demote only after ten continuous seconds without any visible/pending HDR producer or stateful HDR output. Hidden content does not hold promotion, but its in-flight leases must still drain safely.
- Cancel demotion immediately when HDR demand returns. Coalesce repeated appearance/disappearance while a switch is preparing; allow only one profile switch in flight. Explicit user policy changes bypass the delay but not resource safety.
- Continue showing the old coherent profile until the new working backing/configuration is ready. Apply the layer format/color-space change on the native queue immediately before late drawable acquisition; never mix host surfaces from incompatible profile epochs.
- Headroom/brightness changes do not change working formats and cannot trigger a profile-switch allocation. Source geometry, CPU tiles, and state slots keep their compatible versions. Use monotonic-clock fixtures for promotion, delayed demotion, cancellation, and screen moves.

### One lifetime protocol for every mutable allocation

Apply the same protocol to raster tiles, GPU leaves, shader buffers/textures and retained compute state, group intermediates, backdrop prefix captures/halo gathers/filter outputs/scratch, masks, resolve targets, MSAA attachments, upload buffers, HDR conversion outputs, persistent-final tiles, and readback resources.

Each allocation records:

- logical resource identity and allocation generation;
- host generation and surface epoch;
- content/version token and validity;
- exclusive writer reservation;
- queued/running CPU worker ownership and cancellation/publication token;
- queued/in-flight read leases;
- producer packet and completion dependencies;
- retirement state and accounted bytes.

**Rules**

- A new writer reservation requires no outstanding leases from older packets.
- Sealing a submission packet freezes its resource bindings and acquires leases before enqueueing.
- Multiple packets may read an unchanged generation.
- Within one packet, producers precede consumers through explicit ordered passes; a resource cannot be sampled while attached for writing.
- CPU workers release exclusive write ownership only after flushing/unlocking their context and returning a completion token. GPU read leases cannot become executable while a CPU writer is active.
- GPU baseline copies, shader render/compute passes, backdrop prefix/copy/filter/replacement passes, output conversion, intermediate updates, final-tile damage updates, and presentation copies form one explicit dependency DAG. Include copy-source reads and copy-destination writes in lease checks. A captured prefix remains immutable while later paint continues in a different writable target/generation.
- Later packets may consume a pending producer only on the same owning command queue with the dependency recorded. No implicit cross-queue resource sharing.
- Every rewrite uses an unleased allocation or waits through scheduler deferral—not a UI-thread GPU wait.
- GPU completion releases execution leases. Presentation notification is not required for recycling offscreen resources.
- Destruction retires allocations immediately, but physical release waits for the final execution lease.
- Failed producers invalidate their outputs and dependent cached results.
- A failed/canceled backdrop prefix or filter producer invalidates its effect and downstream composites, including later effects that sample it. Never publish a new foreground over an old mismatched backdrop input; retain the last coherent ready/displayed frame until a complete replacement succeeds. Presentation-only retries reuse successful captures/effects without rerunning shader state.

Keep one allocation for static resources. Grow writable versions lazily, up to three per logical retained target. Scratch attachments use a bounded pool and cannot be reused until their packet completes.

Raster damage applies only to a writable backing containing the required baseline. Otherwise, fully rerasterize that chunk. Partial redraw into an unrelated pooled generation is forbidden.

### Metal hazard synchronization

- Use `MTLCommandQueue`/`MTLCommandBuffer` on macOS 26, explicit tracked hazard mode for individually allocated buffers/textures, directly bound declared resources, and serial compute encoders. This is the classic submission API, not `MTL4CommandQueue`; the automatic tracked-hazard guarantees below cannot be carried unchanged to Metal 4. No untracked heaps, allocation aliasing, cross-host mutable GPU resources, or concurrent compute dispatch mode in this implementation.
- Encode dependent render/compute/blit passes separately in DAG order on the host's one command queue. Tracked Metal resources provide GPU read/write ordering; command-buffer completion provides CPU ownership handoff. Leases additionally prohibit CPU rewriting/recycling a generation merely because commands were encoded in order.
- Offscreen and presentation command buffers use that same queue and enqueue in producer-before-consumer order. Track scheduled versus successfully completed validity separately; never interpret queue ordering as proof the producer succeeded. Stateful steps wait for their previous step's success before scheduling another update.
- For any indirectly referenced resource, explicitly declare its encoder usage with `useResource`/`useResources`; a hidden reference in shader data is not an acceptable resource declaration. Reject a descriptor that omits a needed binding/access declaration.
- Shader-internal race freedom, threadgroup synchronization, and legal in-place compute algorithms remain the application program's responsibility. Metal hazard tracking orders encoders; it cannot fix conflicting threads inside one shader dispatch.
- GPU failure invalidates queued dependent results and their acknowledgement eligibility even if already submitted work cannot be canceled. Stop new admission, drain callbacks, reconstruct the renderer/state epochs, and publish no failed descendant as valid.

This synchronization contract deliberately uses Metal's tracked-resource ordering rather than unspecified implicit synchronization or treating IOSurface locks as GPU fences. [Apple hazard-tracking documentation](https://developer.apple.com/documentation/metal/mtlhazardtrackingmode)

### Scale policy

For cached local CPU tiles, masks, and group intermediates:

- Required scale is backing scale multiplied by the maximum singular value of the local-to-host affine transform.
- At an untransformed 1:1 presentation, rasterize at the exact native backing scale to preserve text/pixel compatibility. For magnified content, choose from a native-scale-anchored `√2` ladder, initially selecting a level at least 12.5% above required scale.
- Upscale only when required scale exceeds cached scale by 5%.
- Downscale only after required scale remains at or below half the cached scale for 500 ms.
- Pure translation/opacity never changes raster scale, but damages old/new final-composite regions and may invalidate an ancestor intermediate. Translation of a backdrop entry may additionally invalidate its input mapping/effect output; reuse of its ordinary foreground raster remains valid.
- Cap at 8 pixels per logical point, device texture dimensions, and the per-allocation limit.
- If capped, record a resolution-limited diagnostic; never overflow dimensions or allocate an invalid texture.
- Memory pressure may discard superseded cached resolutions without waiting for hysteresis, but not resources with outstanding leases.

Use monotonic time and deterministic test-clock advancement for hysteresis.

Persistent-final backing and drawable grids always use the exact current host pixel dimensions/backing scale, not the local-surface oversampling ladder. A resize/backing-scale change selects a new final grid and reconstructs its visible tiles before presentation.

### Accounted memory and pressure behavior

Retain a 256 MiB single-allocation limit, but replace the fixed 512 MiB per-host hard limit with one aggregate per-device admission ledger shared by all Stana hosts. Default aggregate reservation capacity is `min(0.5 * recommendedMaxWorkingSetSize, 0.25 * physicalMemory)`; when the recommendation is unavailable, use the physical-memory term. Count shared allocations once, and reserve estimated allocation bytes before creating them.

Use 512 MiB as a soft per-host cache target, not a correctness limit. A large HDR host can borrow unused device capacity for its required final/state/resize working set. Divide remaining cache capacity by visible-host weight (focused 2, other visible 1, hidden 0); minimum coherent active working sets take precedence over optional caches/prefetch. Query `currentAllocatedSize` as corroborating telemetry, not as a second charge for already-accounted IOSurface-backed textures. The device recommendation is a sizing input, not an allocation-success guarantee. [Apple working-set guidance](https://developer.apple.com/videos/play/tech-talks/10580/)

Account for actual IOSurface allocation sizes and Metal allocation sizes/reservations, including:

- current and retired generations;
- intermediate groups and masks;
- backdrop prefix generations, required source halos, gathered inputs, filter ping-pong scratch, and effect outputs;
- tiled core/gutter allocations, prefetch tiles, and baseline-copy destinations;
- resolved and multisample textures;
- geometry/upload buffers, shader storage/scratch resources, and retained compute outputs;
- scene-referred HDR resources, converted outputs, and profile-switch overlap;
- persistent-final generations and their readback/presentation-copy dependencies;
- readback storage;
- reserved queued/running raster-job destinations and immutable asset working sets;
- simultaneous resize generations.

Track drawable-pool estimates and implementation-private overhead separately; do not claim toolkit accounting measures all driver memory.

Reserve a conservative drawable-pool allowance inside admission capacity, while reporting its estimated versus measured status separately. Charge working-profile transitions and temporal ping-pong versions at simultaneous peak, not steady state. Across hosts, grant preparation and GPU slots in fair rounds; require a complete coherent working-set reservation before starting a batch so partially allocated large windows cannot deadlock each other.

Before admitting a frame:

1. Evict unleased obsolete and offscreen caches.
2. Remove surplus pooled allocations.
3. Drop prefetch work and cancel obsolete queued jobs; retain required visible work.
4. Defer until outstanding CPU/GPU work releases transient resize/profile-switch/retired resources.
5. Reduce frame concurrency to one and disable optional MSAA if needed.

Never flatten away required isolation, omit GPU content/backdrop effects, reduce a declared sampling footprint, or silently violate the required raster scale to fit memory.

If active hosts' minimum coherent working sets cannot all fit, first serialize preparation/GPU work, discard reconstructible caches, and pause hidden hosts. Do not exceed the aggregate budget to satisfy each host's former soft quota. If a required host frame still cannot fit, retain its last successful display, report the requested/available byte counts, and retry only after changed desired content, visibility/budget changes, or capacity release. No allocation retry loop or silent loss of isolation/HDR precision.

On OS memory pressure, cancel prefetch and shrink the admission target by 50%. Existing leased allocations may temporarily exceed the reduced target, but no new reservation may increase the excess; drain/retire until within target. Report that transient separately, and restore capacity only after ten seconds without pressure. Never free active CPU writers or GPU readers to satisfy a ledger immediately.

## 4. Scheduler and presentation state machines

### Execution ownership and starvation admission

The UI executor owns document updates, retained planning, immutable job preparation, and resource bookkeeping. Bounded raster workers own active CoreGraphics execution; an asynchronous compiler queue owns application shader compilation. Each presentation host has a serial native encoding queue. Device/pipeline caches are shared; mutable surface resources remain host-owned.

Use this admission sequence:

1. Logical commits update retained projections and replace the latest desired-scene reference.
2. Obtain a preparation permit from the fair process-wide worker/device scheduler; check visibility, memory reservation, and bounded offscreen capacity. This permit is not a drawable.
3. Run one frame-callback transaction, settle the newest scene, compute backdrop dependency closure and required source halos, select dirty tiles/passes, and dispatch required raster jobs. Reserve prefix/filter peak storage before execution. Await workers asynchronously with no acquired drawable.
4. Seal an immutable offscreen packet; encode/commit baseline copies, application and built-in producers, linear ingress conversions, ordered backdrop prefix/capture/filter/replacement passes, and dirty intermediate/final tiles on the host queue. Direct linear/HDR mode and backdrop-enabled direct SDR mode render their complete transient targets here; no-backdrop direct SDR compatibility mode prepares offscreen inputs and leaves only onscreen composition pending.
5. After successful offscreen completion, retain one coherent ready frame with its geometry snapshot/resource leases. Failures recover before attempting presentation. Coalesce newer desired changes; no drawable is needed to validate this output.
6. On the native queue, apply ready output configuration and call `nextDrawable()` immediately before the final onscreen encoder. Validate the acquired target against the ready epoch/size/profile; register its `addPresentedHandler`, encode the batched persistent/transient final copy plus display transform, or no-backdrop direct SDR compatibility composition, and present/commit immediately. Install the immutable attempt/geometry record before callbacks can refer to it; do not wait for a UI-executor round trip while holding a drawable. There is no worker wait, shader compilation, resource upload, backdrop filtering, or unrelated offscreen encoding between acquisition and presentation encoding.

Acquire drawables as late as possible and release application references immediately after presentation submission in a scoped autorelease pool. Presentation callbacks retain only lightweight tokens. [Apple drawable lifetime guidance](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html)

Allow one CPU preparation batch and one ready-offscreen slot per host, at most three committed execution packets per host and six globally per device, allocated fairly. Resource reservations include all stages. No ready-frame history grows with desired updates.

During an outstanding/failed drawable acquisition, freeze further frame-specific preparation after the current bounded batch/ready slot. New signal writes replace one desired reference; compatible cached resource builds may complete, but do not continuously rasterize/upload unseen frame versions or advance feedback steps. Successful acquisition consumes the latest coherent ready frame; a newer desired scene remains pending for the next permit. Never submit a scene older than the last submitted scene; it need not equal a newer scene that is still unprepared.

Size/profile/host-generation changes invalidate incompatible ready frames; release any just-acquired incompatible drawable immediately and prepare a replacement without holding it. Otherwise a coherent ready frame may present while newer compatible desired changes remain pending. Input/logical commits continue throughout, using the last presentation-confirmed geometry/ambiguity contract rather than partially prepared transforms.

`nextDrawable()` can wait up to one second, always off the UI executor. If it returns nil, retain the single ready frame and latest desired reference; retry visible hosts with exponential backoff from 16 ms to 250 ms. Hidden/minimized hosts wait for visibility changes. Never queue parallel acquisitions or reserve drawables during CPU preparation. [Apple drawable timeout documentation](https://developer.apple.com/documentation/quartzcore/cametallayer/1478172-nextdrawable?language=objc)

### Frame callback transaction

For each admitted animation tick:

- Snapshot active subscriptions in registration order.
- Invoke each at most once inside one outer Stana transaction.
- Settle bindings, structural changes, commits, and effects through the existing runtime.
- Prepare rendering only after stabilization completes.
- Defer frame requests generated during stabilization to a later tick; never recursively render.
- New registrations start next tick; canceled/disposed registrations are skipped.
- Keep the existing deterministic stabilization budgets. Budget exhaustion remains a diagnosed runtime fault, not an unbounded frame loop.
- Raster workers, shader compilation, and encoding cannot mutate signals. Their results return through generation-checked UI-executor messages; application frame callbacks remain the explicit signal-mutation phase.
- Reset callback elapsed time when resuming visibility.

### Explicit submission and acknowledgement model

Tag every attempt with:

`(hostGeneration, surfaceEpoch, submissionSequence, sceneRevision)`

Submission sequence increases for every attempt, including retries of the same scene.

Maintain independent states:

- **Preparation:** desired → permitted → raster-ready → offscreen-submitted → ready, or superseded/canceled.
- **Offscreen GPU:** pending → succeeded/failed; governs produced-content and feedback validity.
- **Presentation GPU:** not-submitted → pending → succeeded/failed; governs onscreen-copy success.
- **Presentation observation:** pending → reported-presented/explicitly-dropped/unknown/canceled. `reported-presented` means a matching positive native timestamp, not independently observed physical scanout. An explicit drop is accepted only from a backend with a documented terminal drop signal or a test injection; do not assume macOS supplies a separate drop callback.

These are not one linear state: presentation and GPU callbacks can arrive in either order.

Maintain monotonic high-water marks for accepted, submitted, GPU-succeeded, and presentation-confirmed scene revisions, plus the confirming submission sequence/timestamp. A high-water mark is not proof that every earlier attempt succeeded. Repeated presentation of one scene still has distinct attempt identities; match both observations to the same attempt before advancing confirmation.

| Event                              | Behavior                                                                                                                                                                                                                                                                                                 |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| New desired scene                  | Replace unprepared desired state; retain at most one coherent ready version and never submit backward relative to the submitted high-water mark                                                                                                                                                          |
| Superseded preparation             | Release uncommitted reservations; preserve latest desired scene                                                                                                                                                                                                                                          |
| Raster success                     | Publish a prepared tile only if its writer token/version still matches; release CPU write ownership exactly once                                                                                                                                                                                         |
| Raster cancellation/failure        | Wait for the running writer to exit, invalidate incomplete pixels, and release reservations without submitting a mixed-generation scene                                                                                                                                                                  |
| Shader replacement failure         | Report the program diagnostic, preserve the prior valid program/output, and do not reset unrelated renderer state                                                                                                                                                                                        |
| Offscreen GPU success              | Publish valid produced versions/final tile map and atomic feedback state; release its execution leases exactly once while retaining ready-frame read leases                                                                                                                                              |
| Presentation GPU success           | Release onscreen execution leases; join with that attempt's positive presentation observation if already available; completion alone never advances geometry                                                                                                                                             |
| GPU failure                        | Invalidate produced/dependent results; stop admission and reset renderer epoch before rebuilding latest desired state                                                                                                                                                                                    |
| Positive presentation timestamp    | Record the callback drawable's finite timestamp greater than zero against its captured attempt; after that onscreen GPU attempt succeeds, atomically advance last presentation-confirmed revision/geometry without regressing attempt order; do not clear ambiguity belonging to a newer unknown attempt |
| Explicit dropped presentation      | Do not advance confirmation; retry latest desired scene only if not already covered by a newer confirmed/pending attempt                                                                                                                                                                                 |
| Zero timestamp or missing callback | Remain unconfirmed; do not infer a successful display or a terminal drop, and do not clear changed-region ambiguity                                                                                                                                                                                      |
| Late/out-of-order callback         | Update that attempt only; never decrease high-water marks or overwrite newer confirmed geometry                                                                                                                                                                                                          |
| Host destruction/epoch mismatch    | Ignore acknowledgement effects; still perform independent lease cleanup                                                                                                                                                                                                                                  |
| Exposure/restore                   | Present the latest complete scene, even when content is unchanged                                                                                                                                                                                                                                        |

A zero `presentedTime` means not-yet-presented or dropped; do not interpret a zero observed merely at GPU completion as a definitive drop. [Apple presentation timestamp documentation](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime)

If no positive presentation observation arrives within one second, mark acknowledgement **unknown**, not successful or definitively dropped. Release no resources based on this timeout. Allow one watchdog-driven retry for that desired revision; further timeout-only retries wait for a new external rendering event. Late valid notifications remain eligible for monotonic acknowledgement. If the supported native configuration cannot provide usable observations, fail the presentation-feasibility gate and report the capability failure; do not let a permanently frozen interaction snapshot count as a working renderer or substitute GPU completion as acknowledgement.

Presentation handlers capture only lightweight attempt tokens, read `presentedTime` from the callback's drawable, and enqueue that scalar observation through the private bridge; do not retain the drawable/frame packet or synchronously hop to the UI executor. GPU-completion cleanup owns resource leases independently, so missing presentation callbacks cannot retain entire frame packets. A Core Animation transaction completion or `CADisplayLink`/`CAMetalDisplayLink` target time is not an alternate positive observation.

Every presented drawable is cleared and receives the complete visible scene, through the persistent copy or selected direct path. Incompatible acquired drawables are released without presentation. Presentation failure never becomes the baseline for raster/final-cache validity; cache validity follows successful offscreen producers and their recorded content revisions. A presentation retry reuses ready state and never reruns its stateful simulation step.

## 5. Delivery, verification, and acceptance

### Delivery order

1. **Native feasibility:** prove CoreGraphics → IOSurface → Metal texture → `CAMetalLayer` on macOS 26, including worker-owned raster contexts, alpha, row stride, orientation, resizing, SDR/half-float EDR output, GPU completion and positive drawable-presentation observations as separate events, packaged shader loading, and an application-authored compute/render program. Compile the bridge's presentation calls with availability warnings as errors and record SDK, deployment target, OS, GPU, and window configuration. Run a logged-in minimum-OS windowed probe with numbered/moving frames, callback timestamps, occlusion/minimize/restore, resize, and screen moves; demonstrate usable positive observations and unknown/recovery behavior without inferring display from GPU completion. Demonstrate CPU/GPU prefix → separate backdrop input → blur/distortion → foreground, without attachment read/write aliasing or drawable sampling.
2. **Rendering contracts:** encode isolation, backdrop source scope/prefix/replacement semantics and dependency damage, tile/gutter rules, color/output separation, temporal shader epochs/steps, Metal hazard rules, last presentation-confirmed geometry and pending/unknown interaction policy, resource leases, global admission, worker cancellation, late drawable acquisition, persistent-final baselines, and acknowledgement state machines as types and deterministic tests. Exercise positive/zero/missing observations separately from GPU success/failure, including either callback order. Establish public consumer fixtures for custom shader, backdrop, and HDR authoring before engine API implementation; reject invalid footprints, writable backdrop bindings, and self/later-prefix dependencies.
3. **Retained planner and tiled rasterization:** implement the per-node journal, structurally shared paint snapshots, stable chunks/prefix boundaries, tile damage/indexing, backdrop request indexes and damage propagation, bounded worker execution, and generation-safe publication.
4. **Mixed rendering and shader execution:** add GPU geometry resources, arbitrary CPU/GPU ordering, asynchronous application program compilation, declared render/compute resources, and coherent pass outputs.
5. **Retained compositing, backdrops, and HDR:** implement groups, tiled masks/intermediates, ordered prefix captures, finite-radius blur/custom backdrop programs, replacement compositing, transforms, scale caching, presentation geometry, persistent damage-updated final tiles, SDR/HDR conversion, EDR headroom changes, and full drawable copies.
6. **Hardening:** complete shader/worker/backdrop failure handling, starvation/cancellation tests, multiwindow fairness/device-budget tests, memory-pressure and resize/profile-overlap tests, source-first versus final HDR fixtures, backdrop dependency/seam/alpha fixtures, adaptive-path/bandwidth benchmarks, seam/HDR captures, packaging verification, and documentation.

Native feasibility is an early executable checkpoint, not a reason to weaken the completed architecture. All six steps, including the five previously deferred capabilities and backdrop sampling, are required before this implementation is considered complete.

**Stage 3 entry gate:** require the Stage 1 native macOS 26 presentation-feasibility evidence, not merely header availability, a newer-SDK compile, or headless callbacks. Stage 2 must demonstrate late drawable lifetime under a stalled worker, deterministic feedback-step/reset/failure semantics, coherent last presentation-confirmed geometry publication plus ordinary pending/unknown-failure handling, and deterministic backdrop prefix selection/replacement with dependency propagation across overlapping effects. GPU completion alone must fail the geometry-advance test. If usable native acknowledgements cannot be demonstrated, stop at this gate and explicitly revise the interaction contract/presentation backend before planner work; do not silently redefine completion as display. Scanout-atomic input is not an acceptance claim of this plan.

### Visual reference and tolerances

Retain CoreGraphics as the SDR reference renderer. Extend its test interpreter to apply the same portable transform, clip, and group semantics. For the HDR path, use an independent CPU reference for transfer functions, premultiplication, linear blending, and the final display transform; do not compare linear HDR pixels directly to encoded SDR screenshots.

Extend the reference interpreter with independent ordered prefix capture, the frozen finite blur kernel, a deterministic bounded distortion, and premultiplied backdrop replacement. Keep source/input readbacks as well as final output so a plausible-looking effect cannot hide later-sibling contamination or duplicated translucent alpha.

Compare canonical premultiplied BGRA pixels, ignoring padding and normalizing RGB to zero where alpha is zero:

- CPU passthrough and incremental-versus-full rendering: byte-exact on the same machine/configuration.
- Flat-color/group-opacity interiors: maximum two 8-bit levels per channel.
- Text at identical raster scale: maximum four levels at antialiased pixels; interiors retain the two-level limit.
- Transformed/rounded boundaries: differences confined to a two-device-pixel boundary band, edge displacement no greater than 0.5 pixel, and integrated coverage error no greater than 1% per test shape.
- Tiled versus untiled rendering: byte-exact core pixels for equal-format copies and incremental/full paths; raster/filter boundary comparisons must satisfy the same fixed edge tolerances without an extra tile-seam allowance.
- HDR transfer/tone/blend interiors: absolute channel error at most `0.002` for reference magnitudes at or below `1.0`, and relative error at most `0.2%` above `1.0`, compared with the float CPU reference; alpha absolute error at most `0.002`. Check values above SDR white numerically before display tone mapping.
- HDR incremental versus full reconstruction: identical half-float output for deterministic shaders and identical pass ordering. Nondeterministic application shaders are excluded from equality fixtures, not from lease/lifecycle checks.
- Backdrop identity with empty foreground: byte-exact no-op in SDR and identical half-float output in HDR, including fractional coverage/opacity and translucent prefixes. Built-in blur/distortion versus the CPU reference uses the same SDR interior/boundary and HDR numeric tolerances; freeze kernel/sample rules first. Incremental/full and tiled/untiled backdrop paths retain the existing equality/seam requirements with no extra filter allowance.
- Preserve a scene-linear floating-point readback artifact for HDR validation. Display-preview/PNG export applies the requested headroom-1 final transform and sRGB encoding to that raw composite; never transform an already display-mapped artifact a second time. PNG alone is not evidence that extended brightness survived the render path.

Freeze these thresholds before native implementation. A failing comparison requires investigation, not automatic tolerance expansion.

### Required scenarios

- CPU → GPU → CPU → GPU order, overlapping controls/tooltips, insertion/removal/reorder.
- Rounded clipping plus overlapping mixed-backend children and nested opacity.
- Translation/opacity reuse; child movement invalidating only ancestor intermediate composites.
- Scale oscillation around thresholds and delayed downscale.
- Dirty-rectangle updates after backing rotation.
- All mutable resource types with delayed readers/writers, failed producers, resize retirement, and destruction.
- Reversed/duplicated GPU/presentation callbacks, positive/zero/missing timestamps, explicitly injected drops, unknown presentation, stale epochs, and retries. A zero/missing native observation cannot prove a terminal drop or advance confirmed geometry.
- Drawable starvation while signals change repeatedly: at most the permitted preparation/ready slots, no continuous unseen raster/feedback work, and no frame-specific resource growth.
- Frame callback mutation, registration/cancellation during callbacks, and stabilization-budget failure.
- Memory pressure with current, retired, MSAA, mask, intermediate, and resize allocations simultaneously live.
- Transformed hit testing, accessibility bounds, and IME rectangle conversion.
- Full composited PNG/readback containing GPU leaves.
- Tile-boundary text, strokes, diagonal geometry, rounded masks, transparency, nested opacity, and shader halos at fractional translations and multiple scales; newly exposed scroll tiles and cache eviction/reconstruction.
- Persistent-final damage for movement/removal, transparent foregrounds, overlapping unchanged content, newly allocated generations, missing/expired baseline journals, and shader outputs with unknown influence. Compare each incremental result with forced full reconstruction.
- Concurrent worker raster jobs, bounded queue depth, cancellation during drawing, resize/close/profile change during rasterization, decode completion, stale result rejection, and reused results whose content version still matches.
- Application vertex/fragment/compute functions using uniforms, indexed geometry, sampled/storage textures, multipass dependencies, and retained state. Exercise precompiled/source loading, specialization, invalid bindings, compilation errors, program replacement, async readback, and device capability errors.
- Tile-local shader halos versus whole-surface programs with global dependencies; a nonlocal program must never run as independent tiles without an explicit compatible declaration.
- Backdrop over CPU → GPU → CPU prefixes, with foreground text/controls and later overlapping tooltips. Assert input contains exactly the earlier prefix, not the foreground, later siblings, previous displayed scene, or drawable. Cover root versus isolated-group scope, nested/overlapping backdrops, and insertion/removal/reorder across a prefix boundary.
- Stationary frosted panels over animated/moving backgrounds; background changes outside output bounds but inside blur/displacement support; chained overlapping effects; disjoint/later updates that must leave the earlier input cached. Compare every incremental result with full prefix/effect reconstruction and record dependency-index visits versus actual affected requests.
- Identity and finite blur over transparent/semitransparent prefixes with partial opacity, rounded masks, nested group opacity, and transparent windows. Validate the replacement equation without double background/alpha, once-only mask coverage, correct foreground order, and transparent-zero context edges.
- Backdrop blur/distortion across tile boundaries at fractional translations, rotation, reflection, shear/nonuniform scale, and multiple backing scales. Use footprints larger than the default gutter/prefetch ring, off-output source contributors, evicted input tiles, and unknown/nonlocal footprints. Verify source completeness, no per-tile edge clamp, and no seam.
- Moving/transformed backdrop versus moving its entire containing group: foreground pixels remain reusable, but sampling reruns only when source/mapping dependencies change. Opacity-only changes reuse prefix/filter outputs. Headroom-only changes do not rerun scene-referred filters; profile changes reconstruct compatible prefix/effect generations and preserve values above `1.0`.
- Backdrop capture/filter failure, compilation replacement failure, canceled preparation, delayed readers, resize/profile changes, memory pressure, destruction, and dropped/starved presentation. No stale input/foreground mixing, attachment read/write aliasing, unbounded prefix history, premature scratch reuse, repeated state step on retry, or acquired drawable during filter waits. Exercise both persistent and direct paths, including backdrop-enabled direct SDR's offscreen final target.
- Mixed SDR text/controls and HDR shader content; encoded/linear and straight/premultiplied input conversion, zero alpha, HDR values above `1`, declared source peaks, no double tone mapping, and numerical SDR fallback on a headroom-1 display. Equal scene-linear whites in ordinary UI and shader output must match after the one final transform, including the explicitly compressed headroom-1 case.
- EDR-capable and SDR-only display transitions, current-headroom changes, hosted chrome surfaces, transparent windows, profile switching while worker/GPU generations are live, and HDR floating-point readback. Headless numeric fixtures do not substitute for recorded physical-display checks.
- Hold a raster worker for 100 ms and one second: assert no drawable has been acquired for that preparation, input remains serviced, and no drawable lifetime includes the wait. Repeat with delayed shader compilation and offscreen GPU completion.
- Stateful diffusion/particle feedback across 1,000 successful steps, dropped presentations, zero drawables, superseded scenes, explicit reset, program/size changes, failed initialization/producer, and late old-epoch completion. Verify previous-step values against a CPU model, distinct write generations, exactly-once advancement, and no state advance on presentation-only retries.
- Geometry agreement for nested translation/rotation/nonuniform scale/shear/reflection and singular transforms: compare pixel placement, inverse hit target, pointer-local coordinates, AX bounds, caret/selection, and IME screen rectangles from the same snapshot. Update transforms/text/remove nodes while workers are blocked; confirm geometry advances only after matching GPU success plus a positive presentation observation. Delay acknowledgement delivery after a frame can have presented; verify ordinary pending events use revision-tagged last-known geometry without freezing animation input, unknown-failure changed regions gate actions, AX/IME rectangles remain compatible, clicks are not retargeted later, and older callbacks cannot overwrite newer confirmation/unknown state. Use quiescent native captures to validate projection and instrument acknowledgement/publication lag separately; do not label these tests proof of exact event-time/scanout correspondence.
- Four simultaneously active windows plus one newly visible window: stress global worker/queue/GPU-packet caps, round-robin fairness, large HDR borrowing, aggregate peak reservation, pressure shrink/drain, and simultaneous resize/profile generations. A single large host must not starve the others or reserve its soft quota outside the device ledger.
- Toggle HDR presence faster than the demotion interval and vary headroom independently: one promotion, canceled pending demotions, no headroom-driven reallocation, and eventual demotion only after the full monotonic interval.
- Compare source-first and final mapping on overlapping semitransparent HDR/SDR values and identical reference-white patches. Freeze the selected final-curve expected values and perceptual screenshots; do not retain the prior source curve as an accidental alternative execution path.
- Benchmark static, 1% local updates, full-window animation, scrolling, and heavy overlap in both persistent and direct modes, with contiguous/tiled groups, at 1080p/4K/5K and supported 60/120 Hz. Include mode-switch baseline reconstruction and output-conversion cost.

### Measurable acceptance

| Requirement              | Acceptance                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Incremental projection   | One content-only update in 10,000 entries records one leaf, touches at most `d` ordinary projection ancestors, performs balanced-index updates, and does not rescan sibling arrays; separately counted backdrop propagation touches affected requests/composite ancestors without rerecording their content; depth-128/256/512 counters demonstrate no quadratic-in-depth reconstruction |
| Retained composition     | Stable-scale translation/opacity produces zero CPU rerasterization and zero ordinary GPU-leaf redraws; backdrop movement may rerun input/effect passes but not unchanged foreground content                                                                                                                                                                                              |
| Tiling                   | A local update schedules only intersecting tile cores/gutters; newly exposed tiles reconstruct correctly; tiled/untiled captures show no seam outside the fixed visual tolerance                                                                                                                                                                                                         |
| Persistent final output  | Sparse scenes use partial final-tile updates; dense scenes may select the measured direct path without losing isolation/color equivalence; every presented drawable receives a complete scene and baseline-copy traffic is reported separately                                                                                                                                           |
| Application shaders      | An external consumer imports only `Stana`, loads source and packaged programs, executes dependent compute/render passes, and updates immutable resources without native handles or UI-executor compilation                                                                                                                                                                               |
| Backdrop correctness     | External consumer renders finite blur and custom distortion over mixed CPU/GPU content; prefix scope, foreground order, alpha/coverage replacement, and HDR behavior match the independent reference in both final paths                                                                                                                                                                 |
| Backdrop invalidation    | Earlier source changes propagate through footprint/dependency closure, including off-output halos and chained effects; disjoint/later changes reuse unaffected inputs; unchanged foregrounds are not rerecorded/rasterized                                                                                                                                                               |
| Backdrop resource bounds | Prefix/effect/scratch generations use the same leases, checked dimensions, admission caps, and failure rules as other targets; all effect work completes offscreen before drawable acquisition                                                                                                                                                                                           |
| HDR                      | Scene-linear storage preserves values above `1.0`; shader/UI reference whites match under the same final display transform; compatibility SDR white stays exact, while HDR-to-headroom-1 white follows the documented `0.875` mapping                                                                                                                                                    |
| Worker rasterization     | Production raster jobs execute off the UI executor; pool/queue limits hold under load; input dispatch continues during deliberately stalled workers; canceled jobs cannot publish or free an active writer's storage                                                                                                                                                                     |
| Resource integrity       | Instrumented lease assertions detect no conflicting rewrite or premature release across every allocation class                                                                                                                                                                                                                                                                           |
| Presentation ordering    | Only a matching positive native timestamp plus onscreen GPU success advances confirmation; permuted/zero/missing observations, injected drops, and stale epochs cannot falsely advance or regress it; native minimum-OS evidence is recorded                                                                                                                                             |
| Drawable lifetime        | Zero acquired drawables during worker/compile/offscreen-completion waits; acquisition is followed immediately by onscreen encoding/submission, not asynchronous preparation                                                                                                                                                                                                              |
| Stateful shaders         | Exactly one state advance per successful offscreen simulation step; ping-pong generations never conflict; failed/reset/late epochs cannot publish, and presentation retry causes no extra step                                                                                                                                                                                           |
| Presentation geometry    | All native location consumers share last presentation-confirmed geometry/revision while ordinary presentation is pending; unknown-failure changed regions gate location-targeted actions, AX/IME use compatible last-known rectangles, and singular/disposed targets receive no pointer delivery; no scanout-atomic event-routing claim                                                  |
| Multiwindow admission    | Global worker/queue/GPU-slot/reservation caps hold; each runnable visible host receives a fair turn; large HDR borrowing stays within device capacity rather than per-host hard quotas                                                                                                                                                                                                   |
| Starvation               | Repeated updates coalesce to one desired reference and the bounded preparation/ready slots; no unlimited hidden work or feedback advancement while acquisition is blocked                                                                                                                                                                                                                |
| Idle behavior            | No callbacks, raster jobs, or submissions when there is no active demand                                                                                                                                                                                                                                                                                                                 |
| Responsiveness           | Report p50/p95/p99 UI-executor planning/publication time, input-dispatch latency, raster-worker queue delay and CPU time, total UI occupancy, shader compilation, encoding, GPU execution, native presentation timestamp delay, acknowledgement delivery/publication lag, and ambiguity-gating duration separately; report zero/missing observations rather than manufacturing timings   |

### Performance gates and measurement protocol

These are release gates for the standard fixtures, not promises for arbitrary user shader complexity. Use a baseline Apple M1/8 GiB Mac at native backing scale, macOS 26 or newer, release builds without validation, 120 warm-up frames and at least 1,000 measured frames per case. Record hardware, OS, SDK/deployment target, display resolution/refresh, headroom, negotiated presentation rate, and thermal state. Include a separate native run on the minimum supported macOS 26; a newer OS/SDK is not proof of that runtime gate. Run validation/fault tests separately. If the baseline machine or minimum OS is unavailable, record the affected gate as unverified rather than claiming a faster machine/newer OS proves it.

- For steady 10,000-entry content-only updates, renderer-owned UI planning/publication time must be p95 <= 2 ms and p99 <= 4 ms. Input arrival-to-dispatch must be p95 <= 8 ms and p99 <= 16.7 ms, including the stalled-worker/compile tests. Report the existing document/layout/semantic costs separately as well as total UI occupancy; do not hide a total input-latency failure by subtracting them.
- At negotiated frame period `T`, standard 4K SDR/HDR animation must have total GPU frame time p95 <= `0.8 * T`, p99 <= `T`, and fewer than 1% missed presentation targets after warm-up, measured from positive native presentation timestamps against the requested targets. Record unconfirmed/unknown attempts separately; missing observations cannot be excluded to claim a passing presentation-rate gate or replaced with GPU timings. The final-copy/display-transform pass must be p95 <= `0.2 * T`, p99 <= `0.3 * T`. Reduce the advertised/negotiated rate if bandwidth or timing cannot meet it; report requested and achieved rates, not just averages.
- Across static/local-update/animated/scroll/overlap fixtures, the selected path's GPU p95 must be within 15% and p99 within 25% of the faster correct forced-mode baseline on the same device/profile/rate. Sparse 1% damage fixtures must recompose no more than 10% of visible final pixels after gutter expansion; count baseline/presentation copies separately instead of treating them as zero-cost updates.
- Add fixed backdrop workloads: one frosted panel over animated mixed content, overlapping panels, a large-radius tile-crossing blur, and bounded custom distortion, in SDR/HDR and both forced final paths. Freeze dimensions/radii/panel counts with the fixtures and apply the same total GPU-time, latency, and adaptive-selection gates at the reported negotiated rate. Report output damage, expanded source pixels, prefix replay/copy bytes, and filter time separately; the sparse 10% pixel gate applies to the standard local-damage fixture, not effects whose declared influence legitimately expands beyond it. Do not drop sampling or shrink the effect to pass a timing gate.
- Global worker count must never exceed `W`, runnable queue length `2 * W`, or device packet slots six. With standard bounded tile jobs, every continuously runnable visible host must receive a dispatch within two fair rounds, regardless of another host's tile count. An injected nonpreemptible worker stall is accounted for explicitly and must not stall the UI executor.
- Device reservations plus committed accounted allocations must remain within the admission ledger, including resize/profile peaks. During a pressure-target reduction, excess is allowed only for already existing leases and must decline without new oversubscribing allocations. Verify steady-state recovery and no monotonically growing tile/packet/program caches over a ten-minute multiwindow stress run.
- Inspect depth/breadth operation counters as well as timings. Doubling depth from 128 to 256 to 512 must not produce quadratic paint-projection work; one-leaf recording count remains one even if damage replay legitimately touches overlapping siblings.

Any failed gate requires optimization, an explicitly lower negotiated rate, or a documented unverified/failed result before release. Do not relax thresholds retrospectively, disable a mandatory capability, or report instrumentation alone as acceptance.

Add a `HybridRendering` external example and native benchmark covering animated charts, ordinary controls, rounded clips, overlapping CPU tooltips, moving/fading retained groups, large tiled scroll content, persistent local damage, application-authored compute/fragment shaders, an HDR visualization with SDR-display fallback, and frosted/acrylic-style panels plus a custom glass-like distortion over moving mixed-backend content. Show nested backdrop scope explicitly; describe these as authored effects, not native Liquid Glass parity.

Report tile hit/miss/eviction counts, raster pixels and worker occupancy, final regions redrawn, baseline-copy/presentation-copy bytes, backdrop request/dependency visits and cache hits/misses, captured/expanded source pixels, prefix replay/copy traffic, filter passes/GPU time/scratch peaks, pipeline-cache behavior, HDR conversion passes, allocation bytes by resource class, and current/retired resize/profile generations. Test-only forced-untiled/full-final/serial-worker modes provide baselines without becoming substitutes for the shipped features.

Run `just check`, native GUI/Metal-validation tests, benchmarks, and affected VoiceOver/IME checks. Update architecture, DocC, packaging/example recipes, renderer limitations, and verification results with measured evidence.
