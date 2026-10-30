public struct STNRenderTimingSample: Sendable, Codable {
	public let sceneRevision: UInt64
	public let milliseconds: Double

	package init(sceneRevision: UInt64, milliseconds: Double) {
		self.sceneRevision = sceneRevision
		self.milliseconds = milliseconds
	}
}

/// Renderer telemetry, not a claim of physical display or performance qualification.
public struct STNRenderingDiagnostics: Sendable, Codable {
	public let device: String
	public let workingColorProfile: String
	public let lastFailure: String?
	public let confirmedSceneRevision: UInt64?
	public let confirmedPresentationTime: Double?
	public let counters: [String: Double]
	public let timingSamples: [String: [STNRenderTimingSample]]

	package init(
		device: String,
		workingLinear: Bool,
		failure: String?,
		confirmedRevision: UInt64?,
		confirmedTime: Double?,
		counters: [String: Double],
		timingSamples: [String: [STNRenderTimingSample]]
	) {
		self.device = device
		workingColorProfile = workingLinear ? "extendedLinearSRGB" : "encodedSRGB"
		lastFailure = failure
		confirmedSceneRevision = confirmedRevision
		confirmedPresentationTime = confirmedTime
		self.counters = counters
		self.timingSamples = timingSamples
	}
}
