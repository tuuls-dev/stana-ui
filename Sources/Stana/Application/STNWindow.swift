import StanaCore
import StanaPlatform
import StanaPrimitives

@MainActor public final class STNWindow {
    @MainActor public struct Properties {
        package let title: Property<String>
        package let configuration: Property<Configuration>
        public let size: STNSize
        public let environment: STNEnvironment
        public let shouldClose: (@MainActor () -> Bool)?
        public let onConfigurationError: (@MainActor (STNWindowError) -> Void)?
        public init(
            title: String, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init(), configuration: Configuration = .init(),
            shouldClose: (@MainActor () -> Bool)? = nil,
            onConfigurationError: (@MainActor (STNWindowError) -> Void)? = nil
        ) {
            self.title = Property(title)
            self.configuration = Property(configuration)
            self.size = size
            self.environment = environment
            self.shouldClose = shouldClose
            self.onConfigurationError = onConfigurationError
        }
        public init(
            title: String, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init(), configuration: STNSignal<Configuration>,
            shouldClose: (@MainActor () -> Bool)? = nil,
            onConfigurationError: (@MainActor (STNWindowError) -> Void)? = nil
        ) {
            self.title = Property(title)
            self.configuration = Property(configuration)
            self.size = size
            self.environment = environment
            self.shouldClose = shouldClose
            self.onConfigurationError = onConfigurationError
        }
        public init(
            title: String, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init(), configuration: STNComputed<Configuration>,
            shouldClose: (@MainActor () -> Bool)? = nil,
            onConfigurationError: (@MainActor (STNWindowError) -> Void)? = nil
        ) {
            self.title = Property(title)
            self.configuration = Property(configuration)
            self.size = size
            self.environment = environment
            self.shouldClose = shouldClose
            self.onConfigurationError = onConfigurationError
        }
        public init(
            title: STNSignal<String>, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init(), configuration: Configuration = .init(),
            shouldClose: (@MainActor () -> Bool)? = nil,
            onConfigurationError: (@MainActor (STNWindowError) -> Void)? = nil
        ) {
            self.title = Property(title)
            self.configuration = Property(configuration)
            self.size = size
            self.environment = environment
            self.shouldClose = shouldClose
            self.onConfigurationError = onConfigurationError
        }
        public init(
            title: STNSignal<String>, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init(), configuration: STNSignal<Configuration>,
            shouldClose: (@MainActor () -> Bool)? = nil,
            onConfigurationError: (@MainActor (STNWindowError) -> Void)? = nil
        ) {
            self.title = Property(title)
            self.configuration = Property(configuration)
            self.size = size
            self.environment = environment
            self.shouldClose = shouldClose
            self.onConfigurationError = onConfigurationError
        }
        public init(
            title: STNSignal<String>, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init(), configuration: STNComputed<Configuration>,
            shouldClose: (@MainActor () -> Bool)? = nil,
            onConfigurationError: (@MainActor (STNWindowError) -> Void)? = nil
        ) {
            self.title = Property(title)
            self.configuration = Property(configuration)
            self.size = size
            self.environment = environment
            self.shouldClose = shouldClose
            self.onConfigurationError = onConfigurationError
        }
        public init(
            title: STNComputed<String>, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init(), configuration: Configuration = .init(),
            shouldClose: (@MainActor () -> Bool)? = nil,
            onConfigurationError: (@MainActor (STNWindowError) -> Void)? = nil
        ) {
            self.title = Property(title)
            self.configuration = Property(configuration)
            self.size = size
            self.environment = environment
            self.shouldClose = shouldClose
            self.onConfigurationError = onConfigurationError
        }
        public init(
            title: STNComputed<String>, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init(), configuration: STNSignal<Configuration>,
            shouldClose: (@MainActor () -> Bool)? = nil,
            onConfigurationError: (@MainActor (STNWindowError) -> Void)? = nil
        ) {
            self.title = Property(title)
            self.configuration = Property(configuration)
            self.size = size
            self.environment = environment
            self.shouldClose = shouldClose
            self.onConfigurationError = onConfigurationError
        }
        public init(
            title: STNComputed<String>, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init(), configuration: STNComputed<Configuration>,
            shouldClose: (@MainActor () -> Bool)? = nil,
            onConfigurationError: (@MainActor (STNWindowError) -> Void)? = nil
        ) {
            self.title = Property(title)
            self.configuration = Property(configuration)
            self.size = size
            self.environment = environment
            self.shouldClose = shouldClose
            self.onConfigurationError = onConfigurationError
        }
    }
    package let properties: Properties
    package let content: () -> STNGroup
    package var controller: WindowController?
    package var onClosed: (() -> Void)?
    package var session: MountSession? { controller?.session }
    package let stateSource = STNSignal(STNWindowState())
    package let resolutionSource = STNSignal(STNWindowResolution())
    package let appliedSource = STNSignal<Configuration?>(nil)
    public private(set) lazy var state: STNComputed<STNWindowState> = stateSource.map { $0 }
    public private(set) lazy var resolution: STNComputed<STNWindowResolution> = resolutionSource.map { $0 }
    public private(set) lazy var appliedConfiguration: STNComputed<Configuration?> = appliedSource.map { $0 }
    public init(properties: Properties, @STNBuilder content: @escaping () -> STNGroup) {
        self.properties = properties
        self.content = content
    }
    public var isOpen: Bool { controller != nil }
    public func close() { controller?.close() }
    package func open(using host: any PlatformHost, show: Bool = true) throws {
        guard controller == nil else { return }
        let controller = try WindowController(owner: self, host: host)
        self.controller = controller
        controller.mount(show: show)
    }
    package var native: any PlatformWindow {
        get throws {
            guard let native = controller?.native else { throw STNWindowError.closed }
            return native
        }
    }
    public func show(activate: Bool = true) throws { try native.perform(activate ? .show : .showInactive) }
    public func hide() throws { try native.perform(.hide) }
    public func focus() throws { try native.perform(.focus) }
    public func center() throws { try native.perform(.center) }
    public func minimize() throws { try native.perform(.minimize) }
    public func restore() throws { try native.perform(.restore) }
    public func zoom() throws { try native.perform(.zoom) }
    public func orderFront() throws { try native.perform(.orderFront) }
    public func orderBack() throws { try native.perform(.orderBack) }
    public func requestClose() throws { try native.perform(.requestClose) }
    public func setFrame(_ frame: STNRect, animate: Bool = false) throws {
        try native.setFrame(frame, animate: animate)
    }
    public func saveFrame(named name: String) throws { try native.saveFrame(name) }
    @discardableResult public func restoreFrame(named name: String) throws -> Bool { try native.restoreFrame(name) }
    public func move(to origin: STNPoint) throws {
        var frame = try native.state.frame
        frame.origin = origin
        try native.setFrame(frame, animate: false)
    }
    public func setContentSize(_ size: STNSize) throws { try native.setContentSize(size) }
    public func setFullscreen(_ value: Bool) async throws { try await native.setFullscreen(value) }
    public func customizeToolbar() throws { try native.perform(.customizeToolbar) }
    public func toggleToolbar() throws { try native.perform(.toggleToolbar) }
    public func selectNextTab() throws { try native.perform(.nextTab) }
    public func selectPreviousTab() throws { try native.perform(.previousTab) }
    public func moveTabToNewWindow() throws { try native.perform(.moveTabToWindow) }
    public func mergeAllWindows() throws { try native.perform(.mergeWindows) }
    public func toggleTabBar() throws { try native.perform(.toggleTabBar) }
    public func toggleTabOverview() throws { try native.perform(.toggleTabOverview) }
    public func addTabbedWindow(_ window: STNWindow, before: Bool = false) throws {
        try native.relate(window.native, before ? .tabBefore : .tabAfter)
    }
    public func selectTabbedWindow(_ window: STNWindow) throws { try native.relate(window.native, .selectTab) }
    public func removeTabbedWindow(_ window: STNWindow) throws { try native.relate(window.native, .detachTab) }
    public func addChild(_ window: STNWindow, above: Bool = true) throws {
        guard let controller, let child = window.controller, controller !== child else {
            throw STNWindowError.invalidRelationship
        }
        for ancestor in sequence(first: controller, next: { $0.parent }) {
            if ancestor === child { throw STNWindowError.invalidRelationship }
        }
        guard child.parent == nil else { throw STNWindowError.invalidRelationship }
        try controller.native.relate(child.native, above ? .childAbove : .childBelow)
        controller.children.append(window)
        child.parent = controller
    }
    public func removeChild(_ window: STNWindow) throws {
        guard let controller, let child = window.controller, child.parent === controller else {
            throw STNWindowError.invalidRelationship
        }
        try controller.native.relate(child.native, .detach)
        controller.children.removeAll { $0 === window }
        child.parent = nil
    }
    public func presentSheet(_ sheet: STNWindow, critical: Bool = false) async throws -> Int32 {
        guard let controller, sheet !== self, sheet.controller == nil else { throw STNWindowError.invalidRelationship }
        try sheet.open(using: controller.host, show: false)
        controller.sheets.append(sheet)
        defer {
            controller.sheets.removeAll { $0 === sheet }
            sheet.close()
        }
        return try await controller.native.presentSheet(sheet.native, critical: critical)
    }
    public func endSheet(result: Int32 = 0) throws { try native.endSheet(result) }
    public func requestSharing() async throws { try await native.requestSharing(of: nil) }
    public func transferSharing(to window: STNWindow) async throws {
        try await native.requestSharing(of: window.native)
    }
}
