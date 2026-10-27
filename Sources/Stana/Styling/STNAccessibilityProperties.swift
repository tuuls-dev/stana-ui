import StanaPrimitives

@MainActor public struct STNAccessibilityProperties {
	package var label: Property<String>?
	public let hint: String?
	public let heading: Int?
	public let group: Bool

	public init(label: String? = nil, hint: String? = nil, heading: Int? = nil, group: Bool = false) {
		precondition(heading.map { (1...6).contains($0) } ?? true)
		self.label = label.map(Property.init)
		self.hint = hint
		self.heading = heading
		self.group = group
	}

	public init(label: STNSignal<String>, hint: String? = nil, heading: Int? = nil, group: Bool = false) {
		self.init(hint: hint, heading: heading, group: group)
		self.label = Property(label)
	}

	public init(label: STNComputed<String>, hint: String? = nil, heading: Int? = nil, group: Bool = false) {
		self.init(hint: hint, heading: heading, group: group)
		self.label = Property(label)
	}
}
