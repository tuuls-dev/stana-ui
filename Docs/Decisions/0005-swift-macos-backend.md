# ADR 0005: Swift macOS implementation and typed rendering

Accepted for issue #6; supersedes ADR 0001's implementation-language and private-C-ABI policy.

Native frameworks belong in `StanaPlatformMacOS`, not in portable targets or public signatures. SwiftUI is not a dependency. Stana continues to own content layout, reactivity, editing, and semantics. Native application initialization remains explicit and main-actor isolated; importing or using headless text shaping must not initialize NSApplication.

Scene submission transfers an owning immutable `SceneSnapshot`. Persistent paint branches remain shared. The render owner is a serial-queue-backed actor; AppKit lifecycle and presentation integration are main-actor-owned. Native callbacks carry typed observations. Offscreen completion does not confirm presentation. Device-wide budgets, bounded worker admission, and GPU-completion-owned read leases remain mandatory.

Identities are process-local typed UInt64 values. Zero is reserved. Isolated domains use checked counters; freely constructed GPU values use a checked synchronized allocator. Cross-scope adoption uses a shared domain. Exhaustion is fatal before reuse. Node IDs retain a document namespace and node serial (16 bytes); ownership validation is not weakened to obtain an 8-byte composite node ID.

macOS 26 remains the minimum. Swift 6.4 compiler availability does not imply macOS 26 runtime availability for every standard-library API. Baseline storage uses owned arrays, fixed-size `InlineArray` presentation uniforms available on macOS 26, and checked isolation, without unchecked sendability, unsafe manifest flags, or experimental prerequisites.

The original backend is captured as a frozen benchmark/parity oracle during qualification; the shipped package has one Swift backend. Benchmark reports distinguish offscreen work from positive presentation observations, and never treat capture or AXPress as proof of coordinate-input readiness.
