import StanaCore
import StanaPrimitives

@MainActor public struct STNText: STNComponent, PrimitiveComponent {
    @MainActor public struct Properties {
        package var configuration = NodeConfiguration()

        public init(
            text: String, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: Bool = true,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            self.init(
                text: Property(text), font: font, foreground: foreground, padding: padding, frame: frame,
                background: background, isEnabled: Property(isEnabled), accessibility: accessibility, onMount: onMount)
        }
        public init(
            text: String, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: STNSignal<Bool>,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            self.init(
                text: Property(text), font: font, foreground: foreground, padding: padding, frame: frame,
                background: background, isEnabled: Property(isEnabled), accessibility: accessibility, onMount: onMount)
        }
        public init(
            text: String, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: STNComputed<Bool>,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            self.init(
                text: Property(text), font: font, foreground: foreground, padding: padding, frame: frame,
                background: background, isEnabled: Property(isEnabled), accessibility: accessibility, onMount: onMount)
        }
        public init(
            text: STNSignal<String>, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: Bool = true,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            self.init(
                text: Property(text), font: font, foreground: foreground, padding: padding, frame: frame,
                background: background, isEnabled: Property(isEnabled), accessibility: accessibility, onMount: onMount)
        }
        public init(
            text: STNSignal<String>, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: STNSignal<Bool>,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            self.init(
                text: Property(text), font: font, foreground: foreground, padding: padding, frame: frame,
                background: background, isEnabled: Property(isEnabled), accessibility: accessibility, onMount: onMount)
        }
        public init(
            text: STNSignal<String>, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: STNComputed<Bool>,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            self.init(
                text: Property(text), font: font, foreground: foreground, padding: padding, frame: frame,
                background: background, isEnabled: Property(isEnabled), accessibility: accessibility, onMount: onMount)
        }
        public init(
            text: STNComputed<String>, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: Bool = true,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            self.init(
                text: Property(text), font: font, foreground: foreground, padding: padding, frame: frame,
                background: background, isEnabled: Property(isEnabled), accessibility: accessibility, onMount: onMount)
        }
        public init(
            text: STNComputed<String>, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: STNSignal<Bool>,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            self.init(
                text: Property(text), font: font, foreground: foreground, padding: padding, frame: frame,
                background: background, isEnabled: Property(isEnabled), accessibility: accessibility, onMount: onMount)
        }
        public init(
            text: STNComputed<String>, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: STNComputed<Bool>,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            self.init(
                text: Property(text), font: font, foreground: foreground, padding: padding, frame: frame,
                background: background, isEnabled: Property(isEnabled), accessibility: accessibility, onMount: onMount)
        }
        private init(
            text: Property<String>, font: STNFont = .system(), foreground: STNColor = .text, padding: STNInsets = 0,
            frame: STNFrame = .init(), background: STNColor = .clear, isEnabled: Property<Bool>,
            accessibility: STNAccessibilityProperties = .init(), onMount: (@MainActor (STNNodeHandle) -> Void)? = nil
        ) {
            configuration.text = text
            configuration.isEnabled = isEnabled
            configuration.style.font = font
            configuration.style.foreground = foreground
            configuration.style.padding = padding
            configuration.style.frame = frame
            configuration.background = Property(background)
            configuration.accessibility = accessibility
            configuration.onMount = onMount

        }

    }
    private let properties: Properties
    public init(properties: Properties) { self.properties = properties }
    public func makeContent(in context: STNComponentContext) -> STNEmpty { return STNEmpty() }
    package func mount(in context: MountContext) {
        properties.configuration.mount(
            .text, in: context,
            configure: { node in

            })
    }
}
