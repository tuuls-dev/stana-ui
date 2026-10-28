import Foundation

public struct STNRenderTimingSample: Sendable, Codable {
	public let sceneRevision: UInt64
	public let milliseconds: Double
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

	package init(data: Data, confirmedRevision: UInt64?, confirmedTime: Double?) throws {
		let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
		device = values["device"] as? String ?? "unavailable"
		workingColorProfile = (values["workingLinear"] as? Bool ?? false) ? "extendedLinearSRGB" : "encodedSRGB"
		let failure = values["failure"] as? String ?? ""
		lastFailure = failure.isEmpty ? nil : failure
		confirmedSceneRevision = confirmedRevision
		confirmedPresentationTime = confirmedTime
		counters = values.compactMapValues { ($0 as? NSNumber)?.doubleValue }
		if let raw = values["timingSamples"] {
			let bytes = try JSONSerialization.data(withJSONObject: raw)
			timingSamples = try JSONDecoder().decode([String: [STNRenderTimingSample]].self, from: bytes)
		} else {
			timingSamples = [:]
		}
	}
}
