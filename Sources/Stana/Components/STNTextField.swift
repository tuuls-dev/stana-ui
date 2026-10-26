import StanaCore
import StanaPrimitives

/// A custom-drawn, single-line editor. The binding contains committed text only.
@MainActor public struct STNTextField: STNComponent, PrimitiveComponent {
    @MainActor public struct Properties {
        package var configuration = NodeConfiguration()
        package let value: STNBinding<String>
        package let placeholder: String
        package let secure: Bool
        package let onSubmit: (@MainActor () -> Void)?
        public init(
            value: STNBinding<String>, placeholder: String = "", font: STNFont = .system(),
            padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8), frame: STNFrame = .init(),
            isEnabled: Bool = true, secure: Bool = false, accessibility: STNAccessibilityProperties = .init(),
            onMount: (@MainActor (STNNodeHandle) -> Void)? = nil, onSubmit: (@MainActor () -> Void)? = nil
        ) {
            self.value = value
            self.placeholder = placeholder
            self.secure = secure
            self.onSubmit = onSubmit
            configuration.style.font = font
            configuration.style.padding = padding
            configuration.style.frame = frame
            configuration.style.secure = secure
            configuration.isEnabled = Property(isEnabled)
            configuration.accessibility = accessibility
            configuration.onMount = onMount
        }
        public init(
            value: STNBinding<String>, placeholder: String = "", font: STNFont = .system(),
            padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8), frame: STNFrame = .init(),
            isEnabled: STNSignal<Bool>, secure: Bool = false, accessibility: STNAccessibilityProperties = .init(),
            onMount: (@MainActor (STNNodeHandle) -> Void)? = nil, onSubmit: (@MainActor () -> Void)? = nil
        ) {
            self.init(
                value: value, placeholder: placeholder, font: font, padding: padding, frame: frame, secure: secure,
                accessibility: accessibility, onMount: onMount, onSubmit: onSubmit)
            configuration.isEnabled = Property(isEnabled)
        }
        public init(
            value: STNBinding<String>, placeholder: String = "", font: STNFont = .system(),
            padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8), frame: STNFrame = .init(),
            isEnabled: STNComputed<Bool>, secure: Bool = false, accessibility: STNAccessibilityProperties = .init(),
            onMount: (@MainActor (STNNodeHandle) -> Void)? = nil, onSubmit: (@MainActor () -> Void)? = nil
        ) {
            self.init(
                value: value, placeholder: placeholder, font: font, padding: padding, frame: frame, secure: secure,
                accessibility: accessibility, onMount: onMount, onSubmit: onSubmit)
            configuration.isEnabled = Property(isEnabled)
        }
    }
    private let properties: Properties
    public init(properties: Properties) { self.properties = properties }
    public func makeContent(in context: STNComponentContext) -> STNEmpty { return STNEmpty() }
    package func mount(in context: MountContext) {
        properties.configuration.mount(
            .textField, in: context,
            configure: { node in
                node.textBinding = properties.value
                node.placeholder = properties.placeholder
                node.onSubmit = properties.onSubmit
                context.session.installEditor(node, binding: properties.value)
            })
    }
}
