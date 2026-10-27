import Foundation
import StanaPlatform

/// Native window chrome. Command state remains shared with menus and content.
@MainActor public final class STNToolbar: Equatable {
    public struct Properties: Sendable {
        public var identifier: String
        public var allowsCustomization: Bool
        public var autosavesConfiguration: Bool
        public var defaultItemIdentifiers: [String]?
        public init(
            identifier: String, allowsCustomization: Bool = false, autosavesConfiguration: Bool = false,
            defaultItemIdentifiers: [String]? = nil
        ) {
            self.identifier = identifier
            self.allowsCustomization = allowsCustomization
            self.autosavesConfiguration = autosavesConfiguration
            self.defaultItemIdentifiers = defaultItemIdentifiers
        }
    }
    public indirect enum Item {
        case command(id: String, STNCommand, image: Data? = nil, tooltip: String? = nil, priority: Int = 0)
        case separator(id: String)
        case space(id: String)
        case flexibleSpace(id: String)
        case group(id: String, title: String, items: [Item])
        case menu(id: String, title: String, items: [Item])
        case content(STNToolbarContent)
        package var identifier: String {
            switch self {
            case .command(let id, _, _, _, _), .separator(let id), .space(let id), .flexibleSpace(let id),
                .group(let id, _, _), .menu(let id, _, _):
                return id
            case .content(let content): return content.identifier
            }
        }
    }
    package let properties: Properties
    package let items: [Item]
    public init(properties: Properties, @STNToolbarBuilder content: () -> [Item]) {
        self.properties = properties
        items = content()
    }
    public init(properties: Properties, items: [Item]) {
        self.properties = properties
        self.items = items
    }
    nonisolated public static func == (lhs: STNToolbar, rhs: STNToolbar) -> Bool { lhs === rhs }
    package func validate() throws {
        guard !properties.identifier.isEmpty else {
            throw STNWindowError.invalidConfiguration("Empty toolbar identifier")
        }
        var ids = Set<String>()
        func validate(_ items: [Item], depth: Int) throws {
            guard depth < 32 else { throw STNWindowError.invalidConfiguration("Toolbar nesting exceeds 32") }
            for item in items {
                guard !item.identifier.isEmpty, ids.insert(item.identifier).inserted else {
                    throw STNWindowError.invalidConfiguration("Empty or duplicate toolbar item identifier")
                }
                switch item {
                case .group(_, _, let children), .menu(_, _, let children): try validate(children, depth: depth + 1)
                case .content(let content): try validateChromeSize(content.size)
                case .command(_, _, let image, _, _):
                    if let image, image.count > 32 * 1024 * 1024 {
                        throw STNWindowError.invalidConfiguration("Toolbar image exceeds 32 MiB")
                    }
                default: break
                }
            }
        }
        try validate(items, depth: 0)
        if let defaults = properties.defaultItemIdentifiers {
            let top = Set(items.map(\.identifier))
            guard Set(defaults).count == defaults.count, defaults.allSatisfy({ top.contains($0) }) else {
                throw STNWindowError.invalidConfiguration("Invalid default toolbar items")
            }
        }
    }
}

@resultBuilder @MainActor public enum STNToolbarBuilder {
    public static func buildExpression(_ item: STNToolbar.Item) -> [STNToolbar.Item] { [item] }
    public static func buildBlock(_ groups: [STNToolbar.Item]...) -> [STNToolbar.Item] { groups.flatMap { $0 } }
    public static func buildOptional(_ group: [STNToolbar.Item]?) -> [STNToolbar.Item] { group ?? [] }
    public static func buildEither(first: [STNToolbar.Item]) -> [STNToolbar.Item] { first }
    public static func buildEither(second: [STNToolbar.Item]) -> [STNToolbar.Item] { second }
    public static func buildArray(_ groups: [[STNToolbar.Item]]) -> [STNToolbar.Item] { groups.flatMap { $0 } }
}

@MainActor public final class STNToolbarContent: Equatable {
    public let identifier: String
    public let size: STNSize
    package let content: () -> STNGroup
    public init(identifier: String, size: STNSize, @STNBuilder content: @escaping () -> STNGroup) {
        self.identifier = identifier
        self.size = size
        self.content = content
    }
    nonisolated public static func == (lhs: STNToolbarContent, rhs: STNToolbarContent) -> Bool { lhs === rhs }
}

@MainActor public final class STNTitlebarAccessory: Equatable {
    public enum Placement: Int32, Sendable { case leading, trailing, bottom }
    public struct Properties: Sendable {
        public var identifier: String
        public var size: STNSize
        public var placement: Placement
        public var fullscreenMinimumHeight: Double
        public var hidden: Bool
        public init(
            identifier: String, size: STNSize, placement: Placement = .trailing,
            fullscreenMinimumHeight: Double = 0, hidden: Bool = false
        ) {
            self.identifier = identifier
            self.size = size
            self.placement = placement
            self.fullscreenMinimumHeight = fullscreenMinimumHeight
            self.hidden = hidden
        }
    }
    package let properties: Properties
    package let content: () -> STNGroup
    public init(properties: Properties, @STNBuilder content: @escaping () -> STNGroup) {
        self.properties = properties
        self.content = content
    }
    nonisolated public static func == (lhs: STNTitlebarAccessory, rhs: STNTitlebarAccessory) -> Bool { lhs === rhs }
}
@MainActor package func validateChromeSize(_ size: STNSize) throws {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
        throw STNWindowError.invalidConfiguration("Chrome content size must be finite and positive")
    }
}
