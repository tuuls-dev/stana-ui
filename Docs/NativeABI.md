# Native ABI, version 1

`Sources/CStanaMacOS/include/stana_abi.h` defines Stana-owned fixed-width records. `stana_macos.h` declares the functions. Native/Swift sources are separate targets.

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
