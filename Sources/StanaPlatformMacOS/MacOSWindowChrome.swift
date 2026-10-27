import CStanaMacOS
import Foundation
import StanaPlatform
import StanaPrimitives

extension MacOSHost {
    package func createSurface(in window: any PlatformWindow, size: STNSize) throws -> any PlatformWindow {
        guard let parent = window as? MacOSWindow else { throw STNWindowError.invalidRelationship }
        return try MacOSWindow(title: "", size: size, parent: parent)
    }
}
extension MacOSWindow {
    package var supportsChrome: Bool { !isSurface }
    package func setToolbar(
        _ toolbar: WindowToolbar?, replacing: Bool, visible: Bool,
        style: STNWindowOptions.ToolbarStyle, display: STNWindowOptions.ToolbarDisplay
    ) throws {
        guard let handle else { throw STNWindowError.closed }
        let storage = NativeToolbarStorage()
        let items = try storage.items(toolbar?.items ?? [])
        let strings = NativeWindowStrings([toolbar?.identifier ?? ""] + (toolbar?.defaultIdentifiers ?? []))
        defer { withExtendedLifetime((storage, strings)) {} }
        let defaults = (0..<(toolbar?.defaultIdentifiers.count ?? 0)).map { strings[$0 + 1] }
        try defaults.withUnsafeBufferPointer { buffer in
            try checkWindowStatus(
                stn_window_toolbar(
                    handle, strings[0], items, toolbar?.items.count ?? 0,
                    buffer.baseAddress, buffer.count, toolbar?.allowsCustomization ?? false,
                    toolbar?.autosavesConfiguration ?? false, replacing, visible, style.rawValue, display.rawValue))
        }
    }
    package func updateToolbarCommand(_ id: UInt64, title: String, enabled: Bool, checked: Bool) {
        guard let handle else { return }
        title.withNativeUTF8 { stn_window_toolbar_update(handle, id, $0, enabled, checked) }
    }
    package func setTabAccessory(_ surface: (any PlatformWindow)?) throws {
        guard let handle else { throw STNWindowError.closed }
        let target = (surface as? MacOSWindow)?.handle
        if surface != nil && target == nil { throw STNWindowError.invalidRelationship }
        try checkWindowStatus(stn_window_tab_accessory(handle, target))
    }
    package func setAccessories(_ accessories: [WindowAccessory]) throws {
        guard let handle else { throw STNWindowError.closed }
        let strings = NativeWindowStrings(accessories.map(\.identifier))
        defer { withExtendedLifetime(strings) {} }
        let values = try accessories.enumerated().map { index, value -> stn_window_accessory in
            guard let surface = value.surface as? MacOSWindow, let surfaceHandle = surface.handle else {
                throw STNWindowError.invalidRelationship
            }
            return .init(
                identifier: strings[index], placement: value.placement,
                fullscreen_minimum_height: value.fullscreenMinimumHeight, hidden: value.hidden, surface: surfaceHandle)
        }
        try values.withUnsafeBufferPointer { buffer in
            try checkWindowStatus(stn_window_accessories(handle, buffer.baseAddress, buffer.count))
        }
    }
}

@MainActor private final class NativeToolbarStorage {
    var strings: [NativeWindowStrings] = []
    var arrays: [UnsafeMutablePointer<stn_toolbar_item>] = []
    var images: [UnsafeMutablePointer<UInt8>] = []
    func items(_ items: [WindowToolbarItem]) throws -> UnsafePointer<stn_toolbar_item>? {
        guard !items.isEmpty else { return nil }
        let pointer = UnsafeMutablePointer<stn_toolbar_item>.allocate(capacity: items.count)
        arrays.append(pointer)
        for (index, item) in items.enumerated() {
            let text = NativeWindowStrings([item.identifier, item.title, item.tooltip ?? ""])
            strings.append(text)
            var value = stn_toolbar_item()
            value.identifier = text[0]
            value.title = text[1]
            value.tooltip = text[2]
            value.kind = item.kind
            value.priority = item.priority
            value.command = item.command
            value.enabled = item.enabled
            value.checked = item.checked
            if let image = item.image, !image.isEmpty {
                let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: image.count)
                images.append(bytes)
                image.copyBytes(to: bytes, count: image.count)
                value.image = UnsafePointer(bytes)
                value.image_length = image.count
            }
            value.children = try self.items(item.children)
            value.child_count = item.children.count
            if let surface = item.surface {
                guard let surface = surface as? MacOSWindow else { throw STNWindowError.invalidRelationship }
                value.surface = surface.handle
            }
            pointer.advanced(by: index).initialize(to: value)
        }
        return UnsafePointer(pointer)
    }
    isolated deinit {
        for pointer in arrays { pointer.deallocate() }
        for pointer in images { pointer.deallocate() }
    }
}
