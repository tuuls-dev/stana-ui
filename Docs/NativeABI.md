# Native ABI, version 2

`Sources/Platform/MacOS/Bridge/include/stana_abi.h` defines Stana-owned fixed-width records. `stana_macos.h` declares the functions. The Objective-C bridge (`CStanaMacOS`) and Swift adapter (`StanaPlatformMacOS`) remain separate targets under `Sources/Platform/MacOS/Bridge` and `Sources/Platform/MacOS/Adapter`.

- Public headers contain only C scalars, UTF-8 strings, callbacks, and opaque handles.
- UI functions and callbacks run on the main thread. Pure text-shaping functions do not create NSApplication.
- Text payloads use `stn_utf8` (pointer plus explicit byte length), including events, semantics, clipboard, drawing, menus, and dialogs. Embedded zero characters do not terminate text. File-system paths returned by OS dialogs remain NUL-terminated because native paths cannot contain NUL.
- Input strings, records, and arrays are borrowed for the call. Native state copies anything retained.
- A created window transfers one owned opaque reference; destroy exactly once. Destruction unregisters callbacks before releasing host objects.
- Event/text callback contexts are borrowed and owned by the Swift window adapter until destruction.
- Dialog contexts retain a continuation until the single completion callback consumes it.
- Clipboard-copy returns allocated memory; free it using `stn_string_free`.
- Provider snapshots own their strings/geometry. Removed accessibility elements become unavailable, not another element with a reused identity.
- `UINT64_MAX` represents an unspecified text replacement/marked range. Native UTF-16 ranges are validated in Stana before edits.
- Revision counters do not wrap. Invalid ABI versions fail before surface creation.

Do not pass Swift values, mutable node references, C++ containers, borrowed graphics contexts, or native object layouts across this boundary. No native exception is intended to cross it; allocation failure is reported by the raster result channel.

## Window configuration additions (version 2)

`stana_window.h` adds Stana-owned configuration, state, screen, toolbar and
accessory records. Config strings/images/arrays and state arrays are borrowed for
the call; the receiver copies anything retained. Callback tables are copied.
Pointer disposition returns synchronously while the native adapter still owns
the original mouse event; no event pointer crosses the ABI.

Async operation IDs are monotonically allocated per Swift adapter. Native
completion consumes the corresponding continuation once; cancellation/destruction
removes it, making late callbacks harmless. Closing unregisters callbacks and
observers before releasing native objects. Custom chrome uses independent opaque
surface handles; destroying a surface detaches its view, never its parent window.

Configuration resolution ignores unavailable features. Explicit action status
codes distinguish unsupported, invalid-state, native-failure and cancelled
results. The ABI remains private and version-matched, not a third-party plugin ABI.
