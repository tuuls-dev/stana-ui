import CStanaMacOS
import Foundation
import StanaAccessibility
import StanaGraphics
import StanaPlatform
import StanaPrimitives
import StanaScene
import StanaText

@MainActor package final class MacOSHost: PlatformHost {
    package let textService: any TextService = CoreTextService()
    package init() {}
    package func createWindow(title: String, size: STNSize) throws -> any PlatformWindow {
        try MacOSWindow(title: title, size: size)
    }
    package func run() { stn_app_run() }
}

@MainActor package final class MacOSWindow: PlatformWindow {
    package private(set) var handle: UnsafeMutableRawPointer?
    package var onEvent: ((PlatformEvent) -> Void)?
    package var onDraw: (() -> Void)?
    package var onText: ((Int32, String, NSRange?, NSRange, UInt64) -> Void)?
    private var graphics: CoreGraphicsRenderer!
    private var semantics: MacOSAccessibility!
    package var renderer: any Renderer { graphics }
    package var accessibility: any AccessibilityBridge { semantics }
    package init(title: String, size: STNSize) throws {
        guard stn_abi_version() == STN_ABI_VERSION else { throw STNError.nativeFailure("Native ABI version mismatch") }
        handle = title.withNativeUTF8 { nativeTitle in
            stn_window_create(
                nativeTitle, size.width, size.height, Unmanaged.passUnretained(self).toOpaque(),
                { context, event in
                    guard let context, let event else { return }
                    MainActor.assumeIsolated {
                        Unmanaged<MacOSWindow>.fromOpaque(context).takeUnretainedValue().receive(event.pointee)
                    }
                },
                { context in
                    guard let context else { return }
                    MainActor.assumeIsolated {
                        Unmanaged<MacOSWindow>.fromOpaque(context).takeUnretainedValue().onDraw?()
                    }
                },
                { context, kind, text, location, length, selected, selectedLength, revision in
                    guard let context else { return }
                    MainActor.assumeIsolated {
                        let window = Unmanaged<MacOSWindow>.fromOpaque(context).takeUnretainedValue()
                        let range =
                            location == UInt64.max
                            ? nil : NSRange(location: Int(clamping: location), length: Int(clamping: length))
                        window.onText?(
                            kind, text.string, range,
                            NSRange(location: Int(clamping: selected), length: Int(clamping: selectedLength)), revision)
                    }
                })
        }
        guard handle != nil else { throw STNError.nativeFailure("Could not create native window") }
        graphics = CoreGraphicsRenderer(window: self)
        semantics = MacOSAccessibility(window: self)
    }
    package func show() { if let handle { stn_window_show(handle) } }
    package func requestRedraw() { if let handle { stn_window_redraw(handle) } }
    package func setTitle(_ title: String) { if let handle { title.withNativeUTF8 { stn_window_title(handle, $0) } } }
    package func close() {
        guard let handle else { return }
        self.handle = nil
        onEvent = nil
        onDraw = nil
        onText = nil
        stn_window_destroy(handle)
    }
    package func receive(_ e: stn_event) {
        switch e.kind {
        case 1:
            graphics?.invalidate()
            onEvent?(.resize(.init(width: max(0, e.x), height: max(0, e.y)), e.a))
        case 2...4: onEvent?(.pointer(Int(e.kind - 2), .init(x: e.x, y: e.y)))
        case 5: onEvent?(.scroll(.init(x: e.x, y: e.y), e.a, e.b))
        case 6: onEvent?(.key(e.text.string, e.a != 0, e.b != 0))
        case 7: onEvent?(.close)
        case 8: onEvent?(.activate(e.identity))
        case 9: onEvent?(.focus(e.identity))
        case 10: onEvent?(.appearance(e.x != 0, e.y != 0, e.a != 0))
        case 11: onEvent?(.deactivated)
        case 12, 13:
            graphics?.invalidate()
            onEvent?(.resourcesChanged(e.kind == 13))
        case 14: onEvent?(.modalState(e.x != 0))
        default: break
        }
    }
    package func editing(_ value: Bool) { if let handle { stn_window_focus_text(handle, value) } }
    package func discardMarkedText() { if let handle { stn_window_discard_marked(handle) } }
    package func publishText(
        _ text: String, selection: NSRange, marked: NSRange, bounds: STNRect, offsets: [Double], revision: UInt64,
        secure: Bool, nodeID: UInt64? = nil
    ) {
        guard let handle else { return }
        text.withNativeUTF8 { nativeText in
            offsets.withUnsafeBufferPointer { buffer in
                if let nodeID {
                    stn_window_semantic_text(
                        handle, nodeID, nativeText, UInt64(selection.location), UInt64(selection.length), bounds.native,
                        buffer.baseAddress, buffer.count, revision, secure)
                } else {
                    stn_window_text_state(
                        handle, nativeText, UInt64(selection.location), UInt64(selection.length),
                        marked.location == NSNotFound ? UInt64.max : UInt64(marked.location), UInt64(marked.length),
                        bounds.native, buffer.baseAddress, buffer.count, revision, secure)
                }
            }
        }
    }
}

extension STNRect {
    package var native: stn_rect { stn_rect(x: minX, y: minY, width: size.width, height: size.height) }
}
extension STNColor {
    package var native: stn_color { stn_color(red: red, green: green, blue: blue, alpha: alpha) }
}
