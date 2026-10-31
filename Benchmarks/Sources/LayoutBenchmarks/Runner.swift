import Foundation
import StanaAccessibility
import StanaCore
import StanaPlatformMacOS
import StanaText

struct Trial: Encodable {
	let seconds: Double?
	let spans: [String: Double]
	let counters: [String: Int]
}

struct Result: Encodable {
	let workload: String
	let size: Int
	let nodeCount: Int
	let flexibleChildCount: Int
	let trials: [Trial]
}

struct Report: Encodable {
	let schema = 1
	let suite = "isolated-layout"
	let runID = UUID().uuidString
	let timestamp = Date().ISO8601Format()
	#if DEBUG
		let configuration = "debug-validation-only"
	#else
		let configuration = "release"
	#endif
	let textService: String
	let validation: Bool
	let arguments: [String]
	let instrumentation: Instrumentation
	let machine: Machine
	let results: [Result]
}

struct Instrumentation: Encodable {
	let legacyCounters = "always enabled"
	let layoutCounters: Bool
	let timingSpans: [String]
	let discardedWarmups: Int
	let operationScope = "mutation/invalidation plus LayoutEngine.layout; setup, verification and publications excluded"
	let publicationScope = "selected node/semantic spans are separate post-layout probes, not part of operation seconds"
}

struct Machine: Encodable {
	#if arch(arm64)
		let architecture = "arm64"
	#elseif arch(x86_64)
		let architecture = "x86_64"
	#else
		let architecture = "other"
	#endif
	let os = ProcessInfo.processInfo.operatingSystemVersionString
	let processors = ProcessInfo.processInfo.processorCount
	let memory = ProcessInfo.processInfo.physicalMemory
	let thermalState = ProcessInfo.processInfo.thermalState.rawValue
	let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
	let swift = ProcessInfo.processInfo.environment["STANA_BENCH_SWIFT_VERSION"]
	let revision = ProcessInfo.processInfo.environment["STANA_BENCH_REVISION"]
	let dirty = ProcessInfo.processInfo.environment["STANA_BENCH_DIRTY"]
}

func seconds(_ duration: Duration) -> Double {
	Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

func counters(_ m: STNMetrics) -> [String: Int] {
	[
		"measureCalls": m.measureCalls, "placedNodes": m.placedNodes,
		"measureVisits": m.measureVisits, "measureCacheHits": m.measureCacheHits,
		"textMeasureCalls": m.textMeasureCalls, "placementVisits": m.placementVisits,
		"layoutOutputChanges": m.layoutOutputChanges, "arrangedChildVisits": m.arrangedChildVisits,
		"flexDistributionRounds": m.flexDistributionRounds, "layoutDirtyAncestorVisits": m.layoutDirtyAncestorVisits,
	]
}

@main struct LayoutBenchmarks {
	@MainActor static func main() {
		do {
			try run()
		} catch {
			FileHandle.standardError.write(Data("LayoutBenchmarks: \(error)\n".utf8))
			exit(1)
		}
	}

	@MainActor static func run() throws {
		let arguments = Array(CommandLine.arguments.dropFirst())
		let options = try Options(arguments)
		if options.list {
			print(Workload.allCases.map(\.rawValue).joined(separator: "\n"))
			return
		}

		#if DEBUG
			guard options.validate else {
				throw Failure("Timing requires a release build")
			}
		#endif
		let workloads = options.workload == "all" ? Workload.allCases : [Workload(rawValue: options.workload)!]
		var results: [Result] = []
		for workload in workloads {
			for size in options.sizes {
				var trials: [Trial] = []
				var nodeCount = 0
				var flexibleChildCount = 0
				let warmups = options.validate ? 0 : options.warmup
				for index in 0..<(warmups + (options.validate ? 1 : options.samples)) {
					let text: any TextService = options.native ? CoreTextService() : TestTextService()
					let fixture = Fixture(workload: workload, size: size, text: text)
					let d = fixture.document
					defer {
						d.close()
					}
					nodeCount = fixture.nodeCount
					flexibleChildCount = fixture.flexibleChildCount
					d.metrics = .init()
					d.layoutCountersEnabled = options.counters || options.validate
					d.enabledTimingSpans = options.validate ? [] : options.spans
					let elapsed: Double?
					if options.validate {
						fixture.operate()
						elapsed = nil
					} else {
						let start = ContinuousClock.now
						fixture.operate()
						elapsed = seconds(start.duration(to: .now))
					}

					let measuredCounters = counters(d.metrics)
					try fixture.verify()
					// Publication probes are opt-in and outside the isolated layout interval.
					if options.spans.contains(.nodeSnapshots) && !options.validate {
						_ = d.publishedNodeSnapshots()
					}

					if options.spans.contains(.semanticProjection) && !options.validate {
						_ = SemanticProjection(document: d).snapshot()
					}

					if index >= warmups {
						trials.append(
							.init(
								seconds: elapsed,
								spans: Dictionary(
									uniqueKeysWithValues: d.timings.map { ($0.key.rawValue, seconds($0.value)) }
								),
								counters: measuredCounters
							)
						)
					}
				}

				results.append(
					.init(
						workload: workload.rawValue,
						size: size,
						nodeCount: nodeCount,
						flexibleChildCount: flexibleChildCount,
						trials: trials
					)
				)
			}
		}

		let report = Report(
			textService: options.native ? "native-CoreText" : "deterministic-TestTextService",
			validation: options.validate,
			arguments: arguments,
			instrumentation: .init(
				layoutCounters: options.counters || options.validate,
				timingSpans: options.validate ? [] : options.spans.map(\.rawValue).sorted(),
				discardedWarmups: options.validate ? 0 : options.warmup
			),
			machine: Machine(),
			results: results
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let data = try encoder.encode(report)
		if let output = options.output {
			try data.write(to: URL(fileURLWithPath: output), options: .atomic)
		} else {
			FileHandle.standardOutput.write(data)
			FileHandle.standardOutput.write(Data("\n".utf8))
		}
	}
}
