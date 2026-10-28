import Foundation
import StanaCore
import StanaPlatformMacOS
import StanaPrimitives

public struct STNShortcut: Sendable {
	public struct Modifiers: OptionSet, Sendable {
		public let rawValue: UInt32

		public init(rawValue: UInt32) {
			self.rawValue = rawValue
		}

		public static let primary = Self(rawValue: 1)
		public static let shift = Self(rawValue: 2)
		public static let option = Self(rawValue: 4)
		public static let control = Self(rawValue: 8)
	}

	public let key: String
	public let modifiers: Modifiers

	public init(_ key: String, modifiers: Modifiers = .primary) {
		self.key = key
		self.modifiers = modifiers
	}
}

@MainActor public final class STNCommand {
	@MainActor public struct Properties {
		package var title: Property<String>
		package var enabled: Property<Bool>
		package var checked: Property<Bool>
		public let shortcut: STNShortcut?
		package let onActivate: @MainActor () -> Void

		public init(
			title: some STNPropertyConvertible<String>,
			shortcut: STNShortcut? = nil,
			isEnabled: some STNPropertyConvertible<Bool> = true,
			isChecked: some STNPropertyConvertible<Bool> = false,
			onActivate: @escaping @MainActor () -> Void
		) {
			self.title = title.asProperty()
			self.shortcut = shortcut
			enabled = isEnabled.asProperty()
			checked = isChecked.asProperty()
			self.onActivate = onActivate
		}
	}

	package let properties: Properties
	package var observations: [Observation] = []

	public init(properties: Properties) {
		self.properties = properties
	}

	public func perform() {
		guard properties.enabled.read() else {
			return
		}

		STNTransaction.perform(properties.onActivate)
	}

	package func install(parent: UInt64) {
		let id = MacOSDesktopServices.addCommand(
			parent: parent,
			title: properties.title.read(),
			key: properties.shortcut?.key ?? "",
			modifiers: properties.shortcut?.modifiers.rawValue ?? 0,
			enabled: properties.enabled.read(),
			checked: properties.checked.read()
		) { [weak self] in self?.perform() }

		func observe<V: Equatable>(_ property: Property<V>) {
			guard property.reactive else {
				return
			}

			let observation = ValueObservation(read: property.read, equals: { $0 == $1 }) { [weak self] _ in
				guard let self else {
					return
				}

				MacOSDesktopServices.updateMenu(
					id,
					title: self.properties.title.read(),
					enabled: self.properties.enabled.read(),
					checked: self.properties.checked.read()
				)
			}
			observations.append(observation)
			ReactiveRuntime.shared.batch { ReactiveRuntime.shared.enqueue(observation) }
		}

		observe(properties.title)
		observe(properties.enabled)
		observe(properties.checked)
	}

	package func uninstall() {
		observations.forEach { $0.cancel() }
		observations.removeAll()
	}
}

public enum STNMenuItem {
	case command(STNCommand)
	case submenu(STNMenu)
}

@resultBuilder public enum STNMenuBuilder {
	public static func buildExpression(_ command: STNCommand) -> [STNMenuItem] {
		[.command(command)]
	}

	public static func buildExpression(_ menu: STNMenu) -> [STNMenuItem] {
		[.submenu(menu)]
	}

	public static func buildBlock(_ groups: [STNMenuItem]...) -> [STNMenuItem] {
		groups.flatMap { $0 }
	}

	public static func buildOptional(_ group: [STNMenuItem]?) -> [STNMenuItem] {
		group ?? []
	}

	public static func buildEither(first: [STNMenuItem]) -> [STNMenuItem] {
		first
	}

	public static func buildEither(second: [STNMenuItem]) -> [STNMenuItem] {
		second
	}

	public static func buildArray(_ groups: [[STNMenuItem]]) -> [STNMenuItem] {
		groups.flatMap { $0 }
	}
}

@MainActor public struct STNMenu {
	@MainActor public struct Properties {
		public let title: String

		public init(title: String) {
			self.title = title
		}
	}

	private let properties: Properties
	private let items: [STNMenuItem]

	public init(properties: Properties, @STNMenuBuilder content: () -> [STNMenuItem]) {
		self.properties = properties
		items = content()
	}

	package func install(parent: UInt64) {
		let id = MacOSDesktopServices.addMenu(parent: parent, title: properties.title)
		for item in items {
			switch item {
			case .command(let command): command.install(parent: id)
			case .submenu(let menu): menu.install(parent: id)
			}
		}
	}

	package func uninstall() {
		for item in items {
			switch item {
			case .command(let command): command.uninstall()
			case .submenu(let menu): menu.uninstall()
			}
		}
	}
}
