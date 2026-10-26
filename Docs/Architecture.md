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

## One authoritative document

The UI executor owns the tree, graph, input, focus, and logical commits. Node IDs contain a unique document namespace and a monotonically increasing serial. IDs are never reused; exhaustion is a fatal diagnosed fault rather than wrapping. Class storage is deliberately chosen before arena optimization.

Sources push invalidation through weak reverse edges. Demands validate the old ordered dependency prefix, stop at its first changed output, and reevaluate against current sources after removing obsolete edges. Actual evaluation cycles differ from obsolete validation edges. Equality suppresses output changes, never dependency replacement.

Transactions batch synchronously and do not roll back source writes. All queued binding values are demanded before their deliveries. New structural bindings settle before document publication. Layout needed by hit testing and semantics is current at commit; painting is requested separately. Scope effects run after publication.

## Lifetimes

A mounted scope owns subscriptions, child scopes, tasks, and cleanup. Disposal marks it dead before cancellation, invalidates handles, and queues application cleanup after commit. Request tokens distinguish both scope lifetime and superseded work. Hiding is not disposal; `STNIf` removal is.

Keyed value rows retain their scope but replace descendants when unequal. Observable reference rows retain descendants and require the same instance for an existing key. Duplicate keys and changed observable instances reject the update before tree mutation.

## Projections and native services

Layout measures then places in top-left logical coordinates. Per-node caches are bounded and invalidated through intrinsic-size ancestors. Scene recording creates complete immutable command lists with old/new-bounds damage. A retained sRGB bitmap supplies complete images to the native view; acquired window pixels are never assumed preserved.

Native text measurement and drawing both use Core Text. Stana owns editing state and revisioned UTF-8 positions; native adapters convert UTF-16 ranges explicitly. IME marked text is separate from committed model text.

Accessibility elements are separate from drawing nodes. Complete snapshots are installed at logical commits and queried without a synchronous UI-actor hop. Native accessibility actions enqueue the normal Stana command path.

## Deliberate initial tradeoffs

- Native raster rendering on the UI executor; no GPU worker, device-loss protocol, or presentation-timing claim.
- Conservative full semantic projection and full scene traversal; cached local geometry and actual paint damage avoid remounting and unnecessary measurement.
- Native capabilities sit behind common protocols; additional OS implementations are not stubbed into the public API.
