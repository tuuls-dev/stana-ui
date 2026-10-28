import Foundation
import Stana

/// Measures completed native work, not UI callbacks or CPU submission duration.
@MainActor enum NativeBenchmark {
	private struct Summary: Codable {
		let count: Int
		let p50: Double
		let p95: Double
		let p99: Double

		init(_ samples: [Double]) {
			let sorted = samples.sorted()
			count = sorted.count
			func percentile(_ fraction: Double) -> Double {
				guard !sorted.isEmpty else { return 0 }
				return sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * fraction)) - 1)]
			}
			p50 = percentile(0.5)
			p95 = percentile(0.95)
			p99 = percentile(0.99)
		}
	}

	private struct Report: Codable {
		let workload: String
		let operatingSystem: String
		let physicalMemory: UInt64
		let thermalState: Int
		let finalMode: String
		let warmupFrames: Int
		let measuredFrames: Int
		let firstMeasuredScene: UInt64
		let lastMeasuredScene: UInt64
		let elapsedSeconds: Double
		let milliseconds: [String: Summary]
		let counterDeltas: [String: Double]
		let diagnostics: STNRenderingDiagnostics
	}

	static func run(window: STNWindow) async throws {
		let clock = ContinuousClock()
		let start = clock.now
		var baseline: STNRenderingDiagnostics?
		var cutoff: UInt64 = 0
		var previousCount = 0
		var lastProgress = start
		var lastLog = start
		while start.duration(to: clock.now) < .seconds(300) {
			try await Task.sleep(for: .milliseconds(250))
			let current = try await window.renderingDiagnostics()
			if let failure = current.lastFailure { throw STNGPUError.execution(failure) }
			let completed = current.timingSamples["offscreenGPU", default: []]
			if completed.count != previousCount {
				previousCount = completed.count
				lastProgress = clock.now
			}
			if lastLog.duration(to: clock.now) >= .seconds(5) {
				let positive = Int(current.counters["positivePresentationObservations", default: 0])
				let zero = Int(current.counters["zeroPresentationObservations", default: 0])
				let state = window.state.value
				log(
					"Completed \(completed.count) frames; positive observations \(positive), zero \(zero); visible \(state.isVisible), occluded \(state.isOccluded), key \(state.isKey)"
				)
				lastLog = clock.now
			}
			if lastProgress.duration(to: clock.now) >= .seconds(15) {
				throw STNGPUError.execution(
					"No completed frame for 15 seconds; keep the benchmark window visible and run GUI tests separately"
				)
			}
			guard let baseline else {
				if completed.count >= 120 {
					cutoff = completed.map(\.sceneRevision).max() ?? 0
					self.log("Warm-up complete at scene \(cutoff)")
					baseline = current
				}
				continue
			}

			let measured = completed.filter { $0.sceneRevision > cutoff }
			guard measured.count >= 1_000 else { continue }
			let last = measured[999].sceneRevision
			let summaries = current.timingSamples.mapValues { samples in
				Summary(samples.filter { $0.sceneRevision > cutoff && $0.sceneRevision <= last }.map(\.milliseconds))
			}
			let delta = current.counters.mapValues { $0 }
				.merging(baseline.counters.mapValues { -$0 }, uniquingKeysWith: +)
			let duration = start.duration(to: clock.now)
			let report = Report(
				workload: "animated mixed-backend chart, HDR compute, blur, distortion, tiled scroll",
				operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
				physicalMemory: ProcessInfo.processInfo.physicalMemory,
				thermalState: ProcessInfo.processInfo.thermalState.rawValue,
				finalMode: ProcessInfo.processInfo.environment["STANA_METAL_FINAL_MODE"] ?? "automatic",
				warmupFrames: completed.filter { $0.sceneRevision <= cutoff }.count,
				measuredFrames: 1_000,
				firstMeasuredScene: measured[0].sceneRevision,
				lastMeasuredScene: last,
				elapsedSeconds: Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18,
				milliseconds: summaries,
				counterDeltas: delta,
				diagnostics: current
			)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			let data = try encoder.encode(report)
			let arguments = CommandLine.arguments
			let path =
				arguments.firstIndex(of: "--output")
				.flatMap { index in
					arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
				} ?? "/tmp/stana-native-benchmark.json"
			try data.write(to: URL(fileURLWithPath: path), options: .atomic)
			log("Measured 1,000 completed offscreen frames; report: \(path)")
			return
		}
		throw STNGPUError.execution("Timed out before 1,000 measured offscreen frames; no passing report emitted")
	}

	private static func log(_ message: String) {
		FileHandle.standardError.write(Data((message + "\n").utf8))
	}
}
