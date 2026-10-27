import Stana

@MainActor
struct LabelledField: STNComponent {
	struct Properties {
		let title: String
		let value: STNBinding<String>
	}

	let properties: Properties

	init(properties: Properties) {
		self.properties = properties
	}

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		STNVStack(properties: .init(spacing: 6)) {
			STNText(properties: .init(text: properties.title))
			STNTextField(properties: .init(value: properties.value, accessibility: .init(label: properties.title)))
		}
	}
}
