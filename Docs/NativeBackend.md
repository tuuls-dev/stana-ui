# Native implementation boundary

[ADR 0005](Decisions/0005-swift-macos-backend.md) supersedes the former private C ABI. `StanaPlatformMacOS` is a Swift target at `Sources/Platform/MacOS`; native frameworks and MSL are implementation dependencies, not public API.

## Isolation and ownership

- Application initialization, windows, menus, text-input clients, chrome, and native presentation integration are main-actor-owned. Headless Core Text measurement never creates `NSApplication`.
- Submission transfers an owning immutable `SceneSnapshot` to a serial-queue-backed render actor. Persistent paint and native-plan branches share unchanged storage; no borrowed node references or whole-scene encoding crosses the boundary.
- A device-wide budget accounts for IOSurfaces, textures, buffers, multisample storage, and drawable-pool allowances. Bounded raster workers own their Core Graphics/Core Text contexts. Each surface lock is balanced, including failure paths.
- Prepared packets, cached immutable generations, GPU programs, and feedback state retain their accounting owners through GPU completion. Presentation observations carry scalar attempt identity/timing and do not retain read leases.
- Each host has one replaceable desired scene, one preparation, and one ready packet. Six device-wide execution permits bound admitted work; acquisition is cancellable. The reference-storage mutex is released before [`nextDrawable`](<https://developer.apple.com/documentation/quartzcore/cametallayer/nextdrawable()>), which can block; native UI configuration/callbacks never run under that mutex. Closing unregisters native observers/callbacks, cancels operations, and cannot resurrect the host.
- Accessibility getters synchronously read immutable typed snapshots under a short mutex. Actions enqueue onto the UI actor and revalidate identity. No mutex is held over an actor hop, callback, or GPU wait.

## Presentation and input

Only GPU success **and a positive native drawable timestamp for the same epoch/attempt/scene** confirm display geometry. Apple documents [zero `presentedTime`](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime) for unpresented/dropped frames. Offscreen capture, zero timestamps, and completed GPU work alone do not. Unknown changed regions continue gating location input. History and retry are bounded. A presentation-only retry does not rerun temporal shader state.

Sheet attachment refreshes the drawable queue after native layer reparenting without discarding prepared content. A separate attachment generation rejects stale observations. Coordinate-input qualification runs in a foreground application, because the background SwiftPM helper can remain occluded and receive only dropped drawables.

## Services and identity

Native text clients preserve embedded NULs and convert validated UTF-16 ranges explicitly. IME, checking, Services, spelling, menus, clipboard, and dialogs use native Swift framework APIs. Async operation IDs consume their continuation once; cancellation/close makes late completion harmless.

Process-local document/scope/resource/frame/version tokens contain one checked UInt64 each; zero is reserved and values never wrap or recycle. Composite node IDs retain document ownership (16 bytes). Render cache keys are typed numeric structures containing bounds, scale, profile/mode, revisions, ownership, and surface epoch as appropriate. Textual IDs exist only in exported diagnostics/debug descriptions, not for routing or lookup.

macOS 26 remains the deployment minimum. Swift 6.4 language features are not blanket permission to use macOS 27-only runtime APIs. The implementation uses checked `Sendable` ownership and baseline collection/synchronization APIs, without concurrency escape hatches or unsafe package flags. See [rendering verification](Verification/Metal.md) for actual tested environments and remaining manual checks.
