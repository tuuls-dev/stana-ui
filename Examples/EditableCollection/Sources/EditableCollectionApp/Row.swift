import Stana

@MainActor struct TodoRow: STNComponent {
	struct Properties {
		let todo: Todo
		let onRemove: @MainActor () -> Void
	}

	let properties: Properties

	init(properties: Properties) {
		self.properties = properties
	}

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		STNHStack(properties: .init(alignment: .center, spacing: 12, padding: 8)) {
			STNTextField(
				properties: .init(
					value: properties.todo.title.binding,
					frame: .init(width: 260),
					accessibility: .init(label: "Task title")
				)
			)
			STNToggle(properties: .init(text: "Done", isOn: properties.todo.isDone.binding))
			STNButton(properties: .init(text: "Remove", onActivate: properties.onRemove))
		}
	}
}
