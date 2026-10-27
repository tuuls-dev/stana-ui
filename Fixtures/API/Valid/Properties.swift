import Stana

@MainActor func authoringFixtures() {
	let text = STNSignal("Hello")
	let background = STNSignal(STNColor.surface)
	let opacity = STNSignal(0.8)
	let enabled = STNSignal(true)
	let _ = STNWindow(properties: .init(title: text)) {
		STNVStack(properties: .init(background: background, opacity: opacity)) {
			STNText(properties: .init(text: "constant"))
			STNText(properties: .init(text: text, accessibility: .init(label: text)))
			STNText(properties: .init(text: text.map { $0.uppercased() }))
			STNTextField(properties: .init(value: text.binding, isEnabled: enabled))
			STNButton(
				properties: .init(text: text, isEnabled: enabled, onMount: { try? $0.requestFocus() }, onActivate: {})
			)
			STNSpacer()
			STNIf(enabled) {
				STNText(properties: .init(text: "yes"))
			} else: {
				STNText(properties: .init(text: "no"))
			}
		}
	}
}
