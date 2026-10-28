import StanaPrimitives

@MainActor public struct STNAccessibilityProperties {
	package let label: Property<String>?
	public let hint: String?
	public let heading: Int?
	public let group: Bool

	public init(
		label: (some STNPropertyConvertible<String>)? = Optional<String>.none,
		hint: String? = nil,
		heading: Int? = nil,
		group: Bool = false
	) {
		precondition(heading.map { (1...6).contains($0) } ?? true)
		self.label = label?.asProperty()
		self.hint = hint
		self.heading = heading
		self.group = group
	}
}
