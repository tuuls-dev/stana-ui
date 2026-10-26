import CStanaMacOS
import Foundation
import StanaAccessibility

@MainActor package final class MacOSAccessibility: AccessibilityBridge {
    private weak var window: MacOSWindow?
    package init(window: MacOSWindow) { self.window = window }
    package func publish(_ snapshot: STNSemanticSnapshot) {
        guard let handle = window?.handle else { return }
        let roles: [STNAccessibilityRole] = [
            .window, .group, .heading, .staticText, .button, .checkBox, .textField, .image, .scrollArea,
        ]
        var strings: [UnsafeMutablePointer<CChar>] = []
        func copy(_ text: String?) -> stn_utf8 {
            guard let text else { return stn_utf8(bytes: nil, length: 0) }
            let bytes = text.utf8CString
            let p = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
            bytes.withUnsafeBufferPointer { p.initialize(from: $0.baseAddress!, count: $0.count) }
            strings.append(p)
            return stn_utf8(bytes: UnsafePointer(p), length: bytes.count - 1)
        }
        let nodes = snapshot.nodes.map { node in
            stn_semantic_node(
                identity: node.id.nativeID, parent: node.parent?.nativeID ?? 0,
                role: Int32(roles.firstIndex(of: node.role)!), label: copy(node.label), hint: copy(node.hint),
                value: copy(node.value), bounds: node.bounds.native,
                disabled: node.isDisabled, focused: node.isFocused, offscreen: node.isOffscreen, secure: node.isSecure,
                heading: Int32(node.headingLevel ?? 0))
        }
        nodes.withUnsafeBufferPointer {
            stn_window_publish_semantics(handle, snapshot.revision, $0.baseAddress, $0.count)
        }
        for pointer in strings { pointer.deallocate() }
    }
    package func detach() { window = nil }
}
