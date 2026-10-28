import StanaCore
import StanaPrimitives

/// A custom-drawn, single-line editor. The binding contains committed text only.
@MainActor public struct STNTextField: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()
		package let value: STNBinding<String>
		package let placeholder: String
		package var options: Property<Options>
		package let callbacks: EditorCallbacks

		public init(
			value: STNBinding<String>,
			placeholder: String = "",
			secure: Bool = false,
			options: some STNPropertyConvertible<Options> = Options(),
			layout: STNLayoutProperties = .init(),
			textStyle: STNTextProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init(),
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.value = value
			self.placeholder = placeholder
			self.options = options.asProperty()
			configuration.style.secure = secure
			configuration.style.padding = .init(top: 7, leading: 8, bottom: 7, trailing: 8)
			configuration.background = Property(STNColor.surface)
			configuration.style.borderWidth = 1
			configuration.style.cornerRadius = 5
			callbacks = EditorCallbacks(
				onMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange
			)
			configuration.onSubmit = onSubmit
			configuration.apply(
				layout: layout,
				textStyle: textStyle,
				appearance: appearance,
				interaction: interaction,
				accessibility: accessibility,
				lifecycle: lifecycle
			)
		}
	}

	private let properties: Properties

	public init(properties: Properties) {
		self.properties = properties
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		properties.configuration.mount(
			.textField,
			in: context,
			configure: { node in
				node.textBinding = properties.value
				node.placeholder = properties.placeholder
				context.session.installEditor(node, binding: properties.value, callbacks: properties.callbacks)
				properties.options.install(in: context, node: node, dirty: .all) {
					[weak session = context.session] node, options in
					session?.configureEditor(node, options: options)
				}
			}
		)
	}
}
