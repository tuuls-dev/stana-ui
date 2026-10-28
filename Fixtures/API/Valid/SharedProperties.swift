import Stana

@MainActor private struct CustomTitle: STNPropertyConvertible {
	let signal: STNSignal<String>

	func asProperty() -> STNProperty<String> {
		signal.asProperty()
	}
}

@MainActor func sharedPropertyFixtures() {
	let title = STNSignal("Title")
	let padding = STNSignal(STNInsets(12))
	let font = STNSignal(STNFont.system(size: 18))
	let layout = STNLayoutProperties(padding: padding, frame: STNFrame(width: 200))
	let appearance = STNAppearanceProperties(background: STNColor.surface, opacity: STNSignal(0.8))
	let _ = STNText(properties: .init(text: CustomTitle(signal: title), layout: layout, textStyle: .init(font: font)))
	let _ = STNButton(properties: .init(text: title, layout: layout, appearance: appearance, onActivate: {}))
	let _ = STNTextField(
		properties: .init(
			value: title.binding,
			layout: layout,
			textStyle: .init(font: font, foreground: STNColor.text),
			appearance: appearance,
			interaction: .init(isEnabled: STNSignal(true))
		)
	)
}
