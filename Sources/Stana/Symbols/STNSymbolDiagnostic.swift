/// A recoverable symbol backend failure, delivered after commit on MainActor.
public struct STNSymbolDiagnostic: Sendable, Equatable {
	public enum Code: Sendable, Equatable {
		case preparationFailed
		case resourceLimitExceeded
		case renderingFailed
	}

	public let code: Code
	public let message: String

	package init(code: Code, message: String) {
		self.code = code
		self.message = message
	}
}
