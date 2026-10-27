import Foundation
import Stana
import StanaTesting

@main struct Benchmarks {
	@MainActor static func main() throws {
		let clock = ContinuousClock()
		let count = STNSignal(0)
		let host = STNTestHost()
		let mountStart = clock.now
		host.mount {
			STNVStack {
				STNText(properties: .init(text: count.map { "Count: \($0)" }))
				for index in 0..<9_999 {
					STNText(properties: .init(text: "Static \(index)"))
				}
			}
		}
		let mount = mountStart.duration(to: clock.now)
		let original = host.metrics
		var samples: [Double] = []
		for iteration in 0..<110 {
			let start = clock.now
			count.value += 1
			if iteration >= 10 {
				samples.append(milliseconds(start.duration(to: clock.now)))
			}
		}

		samples.sort()
		precondition(
			original.totalMounts == host.metrics.totalMounts
				&& original.builderExecutions == host.metrics.builderExecutions
		)
		let report: [String: Any] = [
			"fixture": "one-bound-label-in-10000-labels", "backend": "deterministic-headless",
			"os": ProcessInfo.processInfo.operatingSystemVersionString,
			"mount_ms": milliseconds(mount), "samples": samples,
			"median_ms": samples[samples.count / 2], "p95_ms": samples[Int(Double(samples.count - 1) * 0.95)],
			"new_mounts": host.metrics.totalMounts - original.totalMounts,
			"builder_executions": host.metrics.builderExecutions - original.builderExecutions,
			"measure_calls": host.metrics.measureCalls - original.measureCalls,
			"note":
				"Includes synchronous layout/semantic projection and testing snapshots. Not native presentation latency.",
		]
		let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
		print(String(decoding: json, as: UTF8.self))
		host.close()
	}

	static func milliseconds(_ duration: Duration) -> Double {
		Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1_000_000_000_000_000
	}
}
