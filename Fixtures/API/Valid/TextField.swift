import Stana

@MainActor func textFieldConsumer() {
	let value = STNSignal("")
	let enabled = STNSignal(true)
	let options = STNSignal(STNTextField.Options(isReadOnly: false, alignment: .trailing))
	_ = STNTextField(
		properties: .init(
			value: value.binding,
			options: options,
			interaction: .init(isEnabled: enabled),
			onEditorMount: { editor in
				try? editor.requestFocus()
				try? editor.selectAll()
				_ = try? editor.resolution()
			},
			onChange: { _ in },
			onFocusChange: { _ in },
			onSelectionChange: { _ in }
		)
	)
}

@MainActor func textFieldReactiveCombinations() {
	let value = STNSignal("")
	let enabled = STNSignal(true)
	let computedEnabled = STNComputed { enabled.value }
	let options = STNSignal(STNTextField.Options())
	let computedOptions = STNComputed { options.value }
	_ = STNTextField(properties: .init(value: value.binding))
	_ = STNTextField(properties: .init(value: value.binding, options: options))
	_ = STNTextField(properties: .init(value: value.binding, options: computedOptions))
	_ = STNTextField(properties: .init(value: value.binding, interaction: .init(isEnabled: enabled)))
	_ = STNTextField(properties: .init(value: value.binding, options: options, interaction: .init(isEnabled: enabled)))
	_ = STNTextField(
		properties: .init(value: value.binding, options: computedOptions, interaction: .init(isEnabled: enabled))
	)
	_ = STNTextField(properties: .init(value: value.binding, interaction: .init(isEnabled: computedEnabled)))
	_ = STNTextField(
		properties: .init(value: value.binding, options: options, interaction: .init(isEnabled: computedEnabled))
	)
	_ = STNTextField(
		properties: .init(
			value: value.binding,
			options: computedOptions,
			interaction: .init(isEnabled: computedEnabled)
		)
	)
}
