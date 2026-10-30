# ADR 0001: Native services behind a portable boundary

Superseded in implementation language and transport by [ADR 0005](0005-swift-macos-backend.md).

Accepted for the developer preview. Ship macOS first, with a common Swift service interface. Use a private Objective-C/C ABI adapter for the native host. AppKit is permitted for windows, the event loop, menus, clipboard, system dialogs, IME, and accessibility. It is not the content-widget, layout, or editing engine. No Swift source imports AppKit.

Keep platform-specific code in the native adapter. Windows/Linux implementations require their own qualification; portability of interfaces is not host support. Source-only SwiftPM distribution avoids external artifact bootstrapping.
