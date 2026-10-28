import Stana

@MainActor func propertyCombinationFixtures() {
	let text = STNSignal("Text")
	let enabled = STNSignal(true)
	let options = STNSignal(STNTextField.Options())
	let configuration = STNSignal(STNWindow.Configuration())
	let effect = STNSignal(STNBackdropEffect.blur(radius: 4))
	let transform = STNSignal(STNAffineTransform.identity)
	let opacity = STNSignal(1.0)
	_ = STNText(properties: .init(text: "Constant", interaction: .init(isEnabled: true)))
	_ = STNText(properties: .init(text: "Constant", interaction: .init(isEnabled: enabled)))
	_ = STNText(properties: .init(text: "Constant", interaction: .init(isEnabled: enabled.map { $0 })))
	_ = STNText(properties: .init(text: text, interaction: .init(isEnabled: true)))
	_ = STNText(properties: .init(text: text, interaction: .init(isEnabled: enabled)))
	_ = STNText(properties: .init(text: text, interaction: .init(isEnabled: enabled.map { $0 })))
	_ = STNText(properties: .init(text: text.map { $0 }, interaction: .init(isEnabled: true)))
	_ = STNText(properties: .init(text: text.map { $0 }, interaction: .init(isEnabled: enabled)))
	_ = STNText(properties: .init(text: text.map { $0 }, interaction: .init(isEnabled: enabled.map { $0 })))
	_ = STNWindow(properties: .init(title: "Constant", configuration: STNWindow.Configuration())) {}
	_ = STNWindow(properties: .init(title: "Constant", configuration: configuration)) {}
	_ = STNWindow(properties: .init(title: "Constant", configuration: configuration.map { $0 })) {}
	_ = STNWindow(properties: .init(title: text, configuration: STNWindow.Configuration())) {}
	_ = STNWindow(properties: .init(title: text, configuration: configuration)) {}
	_ = STNWindow(properties: .init(title: text, configuration: configuration.map { $0 })) {}
	_ = STNWindow(properties: .init(title: text.map { $0 }, configuration: STNWindow.Configuration())) {}
	_ = STNWindow(properties: .init(title: text.map { $0 }, configuration: configuration)) {}
	_ = STNWindow(properties: .init(title: text.map { $0 }, configuration: configuration.map { $0 })) {}
	_ = STNTextField(
		properties: .init(value: text.binding, options: STNTextField.Options(), interaction: .init(isEnabled: true))
	)
	_ = STNTextField(properties: .init(value: text.binding, options: options, interaction: .init(isEnabled: true)))
	_ = STNTextField(
		properties: .init(value: text.binding, options: options.map { $0 }, interaction: .init(isEnabled: true))
	)
	_ = STNTextField(
		properties: .init(value: text.binding, options: STNTextField.Options(), interaction: .init(isEnabled: enabled))
	)
	_ = STNTextField(properties: .init(value: text.binding, options: options, interaction: .init(isEnabled: enabled)))
	_ = STNTextField(
		properties: .init(value: text.binding, options: options.map { $0 }, interaction: .init(isEnabled: enabled))
	)
	_ = STNTextField(
		properties: .init(
			value: text.binding,
			options: STNTextField.Options(),
			interaction: .init(isEnabled: enabled.map { $0 })
		)
	)
	_ = STNTextField(
		properties: .init(value: text.binding, options: options, interaction: .init(isEnabled: enabled.map { $0 }))
	)
	_ = STNTextField(
		properties: .init(
			value: text.binding,
			options: options.map { $0 },
			interaction: .init(isEnabled: enabled.map { $0 })
		)
	)
	_ = STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 4),
			transform: STNAffineTransform.identity,
			appearance: .init(opacity: 1.0)
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 4),
			transform: STNAffineTransform.identity,
			appearance: .init(opacity: opacity)
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 4),
			transform: STNAffineTransform.identity,
			appearance: .init(opacity: opacity.map { $0 })
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 4),
			transform: transform,
			appearance: .init(opacity: 1.0)
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 4),
			transform: transform,
			appearance: .init(opacity: opacity)
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 4),
			transform: transform,
			appearance: .init(opacity: opacity.map { $0 })
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 4),
			transform: transform.map { $0 },
			appearance: .init(opacity: 1.0)
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 4),
			transform: transform.map { $0 },
			appearance: .init(opacity: opacity)
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: STNBackdropEffect.blur(radius: 4),
			transform: transform.map { $0 },
			appearance: .init(opacity: opacity.map { $0 })
		)
	) {}
	_ = STNBackdrop(
		properties: .init(effect: effect, transform: STNAffineTransform.identity, appearance: .init(opacity: 1.0))
	) {}
	_ = STNBackdrop(
		properties: .init(effect: effect, transform: STNAffineTransform.identity, appearance: .init(opacity: opacity))
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: effect,
			transform: STNAffineTransform.identity,
			appearance: .init(opacity: opacity.map { $0 })
		)
	) {}
	_ = STNBackdrop(properties: .init(effect: effect, transform: transform, appearance: .init(opacity: 1.0))) {}
	_ = STNBackdrop(properties: .init(effect: effect, transform: transform, appearance: .init(opacity: opacity))) {}
	_ = STNBackdrop(
		properties: .init(effect: effect, transform: transform, appearance: .init(opacity: opacity.map { $0 }))
	) {}
	_ = STNBackdrop(properties: .init(effect: effect, transform: transform.map { $0 }, appearance: .init(opacity: 1.0)))
	{}
	_ = STNBackdrop(
		properties: .init(effect: effect, transform: transform.map { $0 }, appearance: .init(opacity: opacity))
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: effect,
			transform: transform.map { $0 },
			appearance: .init(opacity: opacity.map { $0 })
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: effect.map { $0 },
			transform: STNAffineTransform.identity,
			appearance: .init(opacity: 1.0)
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: effect.map { $0 },
			transform: STNAffineTransform.identity,
			appearance: .init(opacity: opacity)
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: effect.map { $0 },
			transform: STNAffineTransform.identity,
			appearance: .init(opacity: opacity.map { $0 })
		)
	) {}
	_ = STNBackdrop(properties: .init(effect: effect.map { $0 }, transform: transform, appearance: .init(opacity: 1.0)))
	{}
	_ = STNBackdrop(
		properties: .init(effect: effect.map { $0 }, transform: transform, appearance: .init(opacity: opacity))
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: effect.map { $0 },
			transform: transform,
			appearance: .init(opacity: opacity.map { $0 })
		)
	) {}
	_ = STNBackdrop(
		properties: .init(effect: effect.map { $0 }, transform: transform.map { $0 }, appearance: .init(opacity: 1.0))
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: effect.map { $0 },
			transform: transform.map { $0 },
			appearance: .init(opacity: opacity)
		)
	) {}
	_ = STNBackdrop(
		properties: .init(
			effect: effect.map { $0 },
			transform: transform.map { $0 },
			appearance: .init(opacity: opacity.map { $0 })
		)
	) {}
}

@MainActor private final class NonEquatableRow {
	let id: Int

	init(id: Int) {
		self.id = id
	}
}

@MainActor func collectionSourceFixtures() {
	let values = STNSignal([1, 2])
	_ = STNForEach(values, id: \.self) { item in STNText(properties: .init(text: String(item))) }
	_ = STNForEach(values.map { $0 }, id: \.self) { item in STNText(properties: .init(text: String(item))) }
	_ = STNForEach([1, 2], id: \.self) { item in STNText(properties: .init(text: String(item))) }
	let rows = STNSignal([NonEquatableRow(id: 1)], equals: { _, _ in false })
	_ = STNForEach(rows, id: \.id, contentEquals: { $0 === $1 }) { _ in STNSpacer() }
	_ = STNForEach(rows.map({ $0 }, equals: { _, _ in false }), id: \.id, contentEquals: { $0 === $1 }) { _ in
		STNSpacer()
	}
	_ = STNForEach(observableRows: rows, id: \.id) { _ in STNSpacer() }
	_ = STNForEach(observableRows: rows.map({ $0 }, equals: { _, _ in false }), id: \.id) { _ in STNSpacer() }
}
