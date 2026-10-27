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
			font: STNFont = .system(),
			padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8),
			frame: STNFrame = .init(),
			isEnabled: Bool = true,
			secure: Bool = false,
			options: Options = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.init(
				value: value,
				placeholder: placeholder,
				font: font,
				padding: padding,
				frame: frame,
				isEnabled: Property(isEnabled),
				secure: secure,
				options: Property(options),
				accessibility: accessibility,
				onMount: onMount,
				onEditorMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange,
				onSubmit: onSubmit
			)
		}

		public init(
			value: STNBinding<String>,
			placeholder: String = "",
			font: STNFont = .system(),
			padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8),
			frame: STNFrame = .init(),
			isEnabled: Bool = true,
			secure: Bool = false,
			options: STNSignal<Options>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.init(
				value: value,
				placeholder: placeholder,
				font: font,
				padding: padding,
				frame: frame,
				isEnabled: Property(isEnabled),
				secure: secure,
				options: Property(options),
				accessibility: accessibility,
				onMount: onMount,
				onEditorMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange,
				onSubmit: onSubmit
			)
		}

		public init(
			value: STNBinding<String>,
			placeholder: String = "",
			font: STNFont = .system(),
			padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8),
			frame: STNFrame = .init(),
			isEnabled: Bool = true,
			secure: Bool = false,
			options: STNComputed<Options>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.init(
				value: value,
				placeholder: placeholder,
				font: font,
				padding: padding,
				frame: frame,
				isEnabled: Property(isEnabled),
				secure: secure,
				options: Property(options),
				accessibility: accessibility,
				onMount: onMount,
				onEditorMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange,
				onSubmit: onSubmit
			)
		}

		public init(
			value: STNBinding<String>,
			placeholder: String = "",
			font: STNFont = .system(),
			padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8),
			frame: STNFrame = .init(),
			isEnabled: STNSignal<Bool>,
			secure: Bool = false,
			options: Options = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.init(
				value: value,
				placeholder: placeholder,
				font: font,
				padding: padding,
				frame: frame,
				isEnabled: Property(isEnabled),
				secure: secure,
				options: Property(options),
				accessibility: accessibility,
				onMount: onMount,
				onEditorMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange,
				onSubmit: onSubmit
			)
		}

		public init(
			value: STNBinding<String>,
			placeholder: String = "",
			font: STNFont = .system(),
			padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8),
			frame: STNFrame = .init(),
			isEnabled: STNSignal<Bool>,
			secure: Bool = false,
			options: STNSignal<Options>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.init(
				value: value,
				placeholder: placeholder,
				font: font,
				padding: padding,
				frame: frame,
				isEnabled: Property(isEnabled),
				secure: secure,
				options: Property(options),
				accessibility: accessibility,
				onMount: onMount,
				onEditorMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange,
				onSubmit: onSubmit
			)
		}

		public init(
			value: STNBinding<String>,
			placeholder: String = "",
			font: STNFont = .system(),
			padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8),
			frame: STNFrame = .init(),
			isEnabled: STNSignal<Bool>,
			secure: Bool = false,
			options: STNComputed<Options>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.init(
				value: value,
				placeholder: placeholder,
				font: font,
				padding: padding,
				frame: frame,
				isEnabled: Property(isEnabled),
				secure: secure,
				options: Property(options),
				accessibility: accessibility,
				onMount: onMount,
				onEditorMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange,
				onSubmit: onSubmit
			)
		}

		public init(
			value: STNBinding<String>,
			placeholder: String = "",
			font: STNFont = .system(),
			padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8),
			frame: STNFrame = .init(),
			isEnabled: STNComputed<Bool>,
			secure: Bool = false,
			options: Options = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.init(
				value: value,
				placeholder: placeholder,
				font: font,
				padding: padding,
				frame: frame,
				isEnabled: Property(isEnabled),
				secure: secure,
				options: Property(options),
				accessibility: accessibility,
				onMount: onMount,
				onEditorMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange,
				onSubmit: onSubmit
			)
		}

		public init(
			value: STNBinding<String>,
			placeholder: String = "",
			font: STNFont = .system(),
			padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8),
			frame: STNFrame = .init(),
			isEnabled: STNComputed<Bool>,
			secure: Bool = false,
			options: STNSignal<Options>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.init(
				value: value,
				placeholder: placeholder,
				font: font,
				padding: padding,
				frame: frame,
				isEnabled: Property(isEnabled),
				secure: secure,
				options: Property(options),
				accessibility: accessibility,
				onMount: onMount,
				onEditorMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange,
				onSubmit: onSubmit
			)
		}

		public init(
			value: STNBinding<String>,
			placeholder: String = "",
			font: STNFont = .system(),
			padding: STNInsets = .init(top: 7, leading: 8, bottom: 7, trailing: 8),
			frame: STNFrame = .init(),
			isEnabled: STNComputed<Bool>,
			secure: Bool = false,
			options: STNComputed<Options>,
			accessibility: STNAccessibilityProperties = .init(),
			onMount: (@MainActor (STNNodeHandle) -> Void)? = nil,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)? = nil,
			onChange: (@MainActor (String) -> Void)? = nil,
			onFocusChange: (@MainActor (Bool) -> Void)? = nil,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)? = nil,
			onSubmit: (@MainActor () -> Void)? = nil
		) {
			self.init(
				value: value,
				placeholder: placeholder,
				font: font,
				padding: padding,
				frame: frame,
				isEnabled: Property(isEnabled),
				secure: secure,
				options: Property(options),
				accessibility: accessibility,
				onMount: onMount,
				onEditorMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange,
				onSubmit: onSubmit
			)
		}
		private init(
			value: STNBinding<String>,
			placeholder: String,
			font: STNFont,
			padding: STNInsets,
			frame: STNFrame,
			isEnabled: Property<Bool>,
			secure: Bool,
			options: Property<Options>,
			accessibility: STNAccessibilityProperties,
			onMount: (@MainActor (STNNodeHandle) -> Void)?,
			onEditorMount: (@MainActor (STNTextFieldHandle) -> Void)?,
			onChange: (@MainActor (String) -> Void)?,
			onFocusChange: (@MainActor (Bool) -> Void)?,
			onSelectionChange: (@MainActor (STNTextSelection) -> Void)?,
			onSubmit: (@MainActor () -> Void)?
		) {
			self.value = value
			self.placeholder = placeholder
			self.options = options
			callbacks = EditorCallbacks(
				onMount: onEditorMount,
				onChange: onChange,
				onFocusChange: onFocusChange,
				onSelectionChange: onSelectionChange
			)
			configuration.style.font = font
			configuration.style.padding = padding
			configuration.style.frame = frame
			configuration.style.secure = secure
			configuration.isEnabled = isEnabled
			configuration.accessibility = accessibility
			configuration.onMount = onMount
			configuration.onSubmit = onSubmit
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
