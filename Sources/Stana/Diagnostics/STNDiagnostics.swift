import Foundation
import StanaPrimitives

/// Opt-in local diagnostics. Events contain error categories, never model text.
@MainActor public enum STNDiagnostics {
	private static var receive: (@MainActor (STNError) -> Void)?

	public static func configure(onError: (@MainActor (STNError) -> Void)?) {
		receive = onError
	}

	package static func report(_ error: STNError) {
		receive?(error)
	}
}
