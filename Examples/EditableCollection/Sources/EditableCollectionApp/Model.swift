import Foundation
import Stana

@MainActor final class Todo: Identifiable {
	nonisolated let id = UUID()
	let title: STNSignal<String>
	let isDone = STNSignal(false)

	init(_ title: String) {
		self.title = STNSignal(title)
	}
}

@MainActor final class Model {
	let rows = STNSignal<[Todo]>(
		[Todo("Draft the interface"), Todo("Test with a keyboard"), Todo("Review accessibility")],
		equals: { a, b in
			a.count == b.count && zip(a, b).allSatisfy { $0.0 === $0.1 }
		}
	)

	func add() {
		rows.value.append(Todo("New task"))
	}

	func reverse() {
		rows.value.reverse()
	}

	func remove(_ id: UUID) {
		rows.value.removeAll { $0.id == id }
	}
}
