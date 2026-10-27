import StanaPrimitives

extension STNTextField {
	public enum TextAlignment: Equatable, Sendable {
		case leading, center, trailing
	}

	/// A preference for a service provided by the active platform.
	public enum TextServicePolicy: Int32, Equatable, Sendable {
		case system, disabled, enabled
	}

	public enum TextServiceFeature: Int, CaseIterable, Sendable {
		case spelling, grammar, correction, smartQuotes, smartDashes, textReplacement, completion
		case systemActions
	}

	public struct TextServices: Equatable, Sendable {
		public var spelling: TextServicePolicy
		public var grammar: TextServicePolicy
		public var correction: TextServicePolicy
		public var smartQuotes: TextServicePolicy
		public var smartDashes: TextServicePolicy
		public var textReplacement: TextServicePolicy
		public var completion: TextServicePolicy

		public init(
			spelling: TextServicePolicy = .system,
			grammar: TextServicePolicy = .system,
			correction: TextServicePolicy = .system,
			smartQuotes: TextServicePolicy = .system,
			smartDashes: TextServicePolicy = .system,
			textReplacement: TextServicePolicy = .system,
			completion: TextServicePolicy = .system
		) {
			self.spelling = spelling
			self.grammar = grammar
			self.correction = correction
			self.smartQuotes = smartQuotes
			self.smartDashes = smartDashes
			self.textReplacement = textReplacement
			self.completion = completion
		}

		package mutating func setPolicy(_ policy: TextServicePolicy, at index: Int) {
			switch index {
			case 0: spelling = policy
			case 1: grammar = policy
			case 2: correction = policy
			case 3: smartQuotes = policy
			case 4: smartDashes = policy
			case 5: textReplacement = policy
			case 6: completion = policy
			default: break
			}
		}

		package var policies: [Int32] {
			[spelling, grammar, correction, smartQuotes, smartDashes, textReplacement, completion].map(\.rawValue)
		}
	}

	/// Reactive configuration does not replace the retained editor.
	public struct Options: Equatable, Sendable {
		public var isReadOnly: Bool
		public var alignment: TextAlignment
		public var foreground: STNColor
		public var placeholderColor: STNColor
		public var background: STNColor
		public var borderColor: STNColor
		public var borderWidth: Double
		public var cornerRadius: Double
		public var selectionColor: STNColor
		public var caretColor: STNColor
		public var textServices: TextServices

		public init(
			isReadOnly: Bool = false,
			alignment: TextAlignment = .leading,
			foreground: STNColor = .text,
			placeholderColor: STNColor = .secondaryText,
			background: STNColor = .surface,
			borderColor: STNColor = .border,
			borderWidth: Double = 1,
			cornerRadius: Double = 5,
			selectionColor: STNColor = .accent,
			caretColor: STNColor = .text,
			textServices: TextServices = .init()
		) {
			self.isReadOnly = isReadOnly
			self.alignment = alignment
			self.foreground = foreground
			self.placeholderColor = placeholderColor
			self.background = background
			self.borderColor = borderColor
			self.borderWidth = borderWidth
			self.cornerRadius = cornerRadius
			self.selectionColor = selectionColor
			self.caretColor = caretColor
			self.textServices = textServices
		}
	}

	public struct Resolution: Equatable, Sendable {
		public enum Availability: Equatable, Sendable {
			case supported, unavailable, inapplicable
		}

		public struct Feature: Equatable, Sendable {
			public let feature: TextServiceFeature
			public let availability: Availability
			/// Nil when the platform cannot determine an effective setting.
			public let isEnabled: Bool?
		}

		public let features: [Feature]
	}
}
