import StanaCore
import StanaPrimitives

@MainActor public final class STNWindow {
    @MainActor public struct Properties {
        package let title: Property<String>
        public let size: STNSize
        public let environment: STNEnvironment
        public init(
            title: String, size: STNSize = .init(width: 800, height: 600), environment: STNEnvironment = .init()
        ) {
            self.title = Property(title)
            self.size = size
            self.environment = environment
        }
        public init(
            title: STNSignal<String>, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init()
        ) {
            self.title = Property(title)
            self.size = size
            self.environment = environment
        }
        public init(
            title: STNComputed<String>, size: STNSize = .init(width: 800, height: 600),
            environment: STNEnvironment = .init()
        ) {
            self.title = Property(title)
            self.size = size
            self.environment = environment
        }
    }
    package let properties: Properties
    package let content: () -> STNGroup
    package var session: MountSession?
    public init(properties: Properties, @STNBuilder content: @escaping () -> STNGroup) {
        self.properties = properties
        self.content = content
    }
    public var isOpen: Bool { session != nil }
    public func close() {
        session?.close()
        session = nil
    }
}
