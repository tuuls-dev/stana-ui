import AppKit
import StanaAccessibility
import StanaPrimitives
import Synchronization

final class AccessibilityStore: Sendable {
	struct Descriptor: Sendable {
		let node: STNSemanticNode
		let text: NativeTextSnapshot?
		let screenBounds: CGRect
	}

	struct Snapshot: Sendable {
		var descriptors: [STNSemanticID: Descriptor] = [:]
		var elements: [STNSemanticID: NativeAccessibilityElement] = [:]
		var order: [STNSemanticID] = []
		var root: ContentView?
		var rootID: STNSemanticID?
	}

	let value = Mutex(Snapshot())
}

private final class WeakAccessibilityStore: Sendable {
	private struct Storage { weak var value: AccessibilityStore? }

	private let storage: Mutex<Storage>

	init(_ store: AccessibilityStore) {
		storage = Mutex(Storage(value: store))
	}

	var value: AccessibilityStore? { storage.withLock { $0.value } }
}

/// AX queries read immutable snapshots without a UI-actor hop.
nonisolated final class NativeAccessibilityElement: NSAccessibilityElement, Sendable {
	enum Action: Sendable {
		case press, focus, select(NSRange, UInt64), replace(String, UInt64)
	}

	private let store: WeakAccessibilityStore
	let id: STNSemanticID
	private let action: @MainActor @Sendable (Action) -> Void

	init(id: STNSemanticID, store: AccessibilityStore, action: @escaping @MainActor @Sendable (Action) -> Void) {
		self.id = id
		self.store = WeakAccessibilityStore(store)
		self.action = action
		super.init()
	}

	var descriptor: AccessibilityStore.Descriptor? { store.value?.value.withLock { $0.descriptors[id] } }

	var node: STNSemanticNode? { descriptor?.node }

	var text: NativeTextSnapshot? { descriptor?.text }

	override func isAccessibilityElement() -> Bool {
		node != nil
	}

	override func accessibilityRole() -> NSAccessibility.Role? {
		switch node?.role {
		case .window: .window
		case .group: .group
		case .heading: NSAccessibility.Role(rawValue: "AXHeading")
		case .staticText: .staticText
		case .button: .button
		case .checkBox: .checkBox
		case .textField: .textField
		case .image: .image
		case .scrollArea: .scrollArea
		case nil: nil
		}
	}

	override func accessibilitySubrole() -> NSAccessibility.Subrole? {
		node?.isSecure == true ? .secureTextField : nil
	}

	override func accessibilityLabel() -> String? {
		node?.label
	}

	override func accessibilityHelp() -> String? {
		node?.hint
	}

	override func accessibilityValue() -> Any? {
		guard let descriptor, !descriptor.node.isSecure else {
			return nil
		}

		if descriptor.node.role == .checkBox {
			return NSNumber(value: descriptor.node.value == "1")
		}

		return descriptor.text?.text ?? descriptor.node.value
	}

	override func isAccessibilityEnabled() -> Bool {
		node.map { !$0.isDisabled } ?? false
	}

	override func isAccessibilityFocused() -> Bool {
		node?.isFocused ?? false
	}

	override func setAccessibilityFocused(_ value: Bool) {
		if value, isAccessibilityEnabled() {
			enqueue(.focus)
		}
	}

	override func accessibilityFrame() -> NSRect {
		descriptor?.screenBounds ?? .zero
	}

	override func accessibilityParent() -> Any? {
		store.value?.value
			.withLock { snapshot -> Any? in
				if let parent = snapshot.descriptors[id]?.node.parent, let element = snapshot.elements[parent] {
					return element
				}

				return snapshot.root
			}
	}

	override func accessibilityChildren() -> [Any]? {
		store.value?.value
			.withLock { snapshot in
				snapshot.order.filter { snapshot.descriptors[$0]?.node.parent == id }
					.compactMap { snapshot.elements[$0] }
			}
	}

	override func accessibilityValueDescription() -> String? {
		nil
	}

	override func accessibilityPerformPress() -> Bool {
		guard isAccessibilityEnabled(), node?.role == .button || node?.role == .checkBox else {
			return false
		}

		enqueue(.press)
		return true
	}

	override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
		if selector == #selector(setAccessibilityValue(_:)) {
			return isAccessibilityEnabled() && node?.isReadOnly == false
		}

		if selector == #selector(accessibilityPerformPress) {
			return isAccessibilityEnabled() && (node?.role == .button || node?.role == .checkBox)
		}

		return super.isAccessibilitySelectorAllowed(selector)
	}

	override func accessibilitySelectedTextRange() -> NSRange {
		text?.selection ?? NSRange()
	}

	override func setAccessibilitySelectedTextRange(_ range: NSRange) {
		if isAccessibilityEnabled(), let text {
			enqueue(.select(range, text.revision))
		}
	}

	override func accessibilitySelectedText() -> String? {
		guard let text else {
			return ""
		}

		return string(for: text.selection) ?? ""
	}

	override func accessibilityNumberOfCharacters() -> Int {
		text.map { $0.secure ? 0 : $0.text.utf16.count } ?? 0
	}

	override func accessibilityInsertionPointLineNumber() -> Int {
		0
	}

	override func accessibilityVisibleCharacterRange() -> NSRange {
		NSRange(location: 0, length: accessibilityNumberOfCharacters())
	}

	override func accessibilityString(for range: NSRange) -> String? {
		string(for: range)
	}

	override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
		string(for: range).map(NSAttributedString.init(string:))
	}

	override func accessibilityRange(for index: Int) -> NSRange {
		guard let text, !text.secure else {
			return NSRange()
		}

		let value = text.text as NSString
		guard index >= 0, index < value.length else {
			return NSRange(location: max(0, min(index, value.length)), length: 0)
		}

		return value.rangeOfComposedCharacterSequence(at: index)
	}

	override func accessibilityLine(for index: Int) -> Int {
		0
	}

	override func accessibilityRange(forLine line: Int) -> NSRange {
		line == 0
			? NSRange(location: 0, length: accessibilityNumberOfCharacters()) : NSRange(location: NSNotFound, length: 0)
	}

	override func accessibilityFrame(for range: NSRange) -> NSRect {
		guard let descriptor, let text = descriptor.text else {
			return accessibilityFrame()
		}

		let rect = text.rect(for: range), local = descriptor.node.bounds.cgRect, screen = descriptor.screenBounds
		return CGRect(
			x: screen.minX + rect.minX - local.minX,
			y: screen.minY + screen.height - (rect.minY - local.minY) - rect.height,
			width: rect.width,
			height: rect.height
		)
	}

	override func setAccessibilityValue(_ value: Any?) {
		guard let value = value as? String, isAccessibilityEnabled(), node?.isReadOnly == false else {
			return
		}

		enqueue(.replace(value, text?.revision ?? 0))
	}

	private func string(for range: NSRange) -> String? {
		guard let text, !text.secure, range.location <= text.text.utf16.count,
			range.length <= text.text.utf16.count - range.location
		else {
			return nil
		}

		return (text.text as NSString).substring(with: range)
	}

	private func enqueue(_ value: Action) {
		let action = action
		Task { @MainActor in action(value) }
	}
}

@MainActor package final class MacOSAccessibility: AccessibilityBridge {
	private weak var window: MacOSWindow?
	let store: AccessibilityStore

	package init(window: MacOSWindow) {
		self.window = window
		store = window.view.accessibilityStore
	}

	package func publish(_ snapshot: STNSemanticSnapshot) {
		guard let window, !window.closed else {
			return
		}

		let rootID = snapshot.nodes.first { $0.role == .window }?.id
		let old = store.value.withLock { $0 }
		var next = AccessibilityStore.Snapshot()
		next.root = window.view
		next.rootID = rootID
		var notifications: [(NativeAccessibilityElement, NSAccessibility.Notification)] = []
		for node in snapshot.nodes where node.role != .window {
			let element =
				old.elements[node.id]
				?? NativeAccessibilityElement(id: node.id, store: store) { [weak window] action in
					guard let window, !window.closed, window.semanticNodes[node.id]?.isAccessibilityEnabled() == true
					else {
						return
					}

					switch action {
					case .press: window.emit(.activate(node.id.nativeID))
					case .focus: window.emit(.focus(node.id.nativeID))
					case .select(let range, let revision):
						window.emit(.focus(node.id.nativeID))
						window.view.textRequest(5, replacement: range, selected: range, revision: revision)
					case .replace(let text, let revision):
						guard window.semanticNodes[node.id]?.node?.isReadOnly == false else {
							return
						}

						window.emit(.focus(node.id.nativeID))
						window.view.textRequest(6, text: text, revision: revision)
					}
				}
			let descriptor = AccessibilityStore.Descriptor(
				node: node,
				text: window.pendingText[node.id.nativeID],
				screenBounds: window.nativeWindow.convertToScreen(window.view.convert(node.bounds.cgRect, to: nil))
			)
			next.descriptors[node.id] = descriptor
			next.elements[node.id] = element
			next.order.append(node.id)
			if old.descriptors[node.id]?.text?.selection != descriptor.text?.selection {
				notifications.append((element, .selectedTextChanged))
			}

			if old.descriptors[node.id]?.node.label != node.label {
				notifications.append((element, .titleChanged))
			}

			if old.descriptors[node.id]?.node.value != node.value {
				notifications.append((element, .valueChanged))
			}

			if node.isFocused, old.descriptors[node.id]?.node.isFocused != true {
				notifications.append((element, .focusedUIElementChanged))
			}
		}

		store.value.withLock { $0 = next }
		window.semanticNodes = next.elements
		window.semanticOrder = next.order
		window.semanticRevision = snapshot.revision
		window.pendingText.removeAll()
		for (element, notification) in notifications {
			NSAccessibility.post(element: element, notification: notification)
		}

		if old.order != next.order {
			NSAccessibility.post(element: window.view!, notification: .layoutChanged)
		}
	}

	package func detach() {
		store.value.withLock { $0 = AccessibilityStore.Snapshot() }
		window = nil
	}
}

extension ContentView {
	override func isAccessibilityElement() -> Bool {
		false
	}

	override func accessibilityChildren() -> [Any]? {
		let state = accessibilityStore.value.withLock { $0 }
		var elements: [Any] = []
		for id in state.order {
			let parent = state.descriptors[id]?.node.parent
			if parent.flatMap({ state.elements[$0] }) == nil, let element = state.elements[id] {
				elements.append(element)
			}
		}

		return elements
	}

	override func accessibilityHitTest(_ point: NSPoint) -> Any? {
		accessibilityStore.value.withLock { state in
			for id in state.order.reversed() {
				if state.descriptors[id]?.screenBounds.contains(point) == true {
					return state.elements[id]
				}
			}

			return self
		}
	}
}
