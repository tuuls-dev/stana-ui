import Foundation

struct Environment: Encodable {
	let operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
	let processorCount = ProcessInfo.processInfo.processorCount
	let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
	let thermalState = ProcessInfo.processInfo.thermalState.rawValue
	let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
	let architecture: String
	let swiftVersion: String?
	let revision: String?
	let workingTreeDirty: Bool?

	init() {
		#if arch(arm64)
			architecture = "arm64"
		#elseif arch(x86_64)
			architecture = "x86_64"
		#else
			architecture = "other"
		#endif
		let values = ProcessInfo.processInfo.environment
		swiftVersion = values["STANA_BENCH_SWIFT_VERSION"]
		revision = values["STANA_BENCH_REVISION"]
		workingTreeDirty = values["STANA_BENCH_DIRTY"].map { $0 == "1" }
	}
}

struct Report: Encodable {
	let schemaVersion = 1
	let suite = "stana-headless-v1"
	let instrumentation = [
		"legacyCounters": "always enabled",
		"layoutTraversalCounters": "disabled",
		"timingSpans": "disabled; only end-to-end operation clock enabled",
	]
	let runID = UUID().uuidString
	let timestamp = ISO8601DateFormatter().string(from: Date())
	let mode: String
	let buildConfiguration: String
	let environment: Environment
	let arguments: [String]
	let results: [Result]
}

@main struct Runner {
	@MainActor static func main() {
		do {
			try run()
		} catch {
			FileHandle.standardError.write(Data("Benchmark failed: \(error)\n".utf8))
			exit(1)
		}
	}

	@MainActor private static func run() throws {
		let arguments = Array(CommandLine.arguments.dropFirst())
		let options = try Options(arguments)
		let workloads = ReactiveWorkloads.all + UIWorkloads.all
		if options.list {
			for workload in workloads {
				print("\(workload.name)\t\(workload.boundary)")
			}

			return
		}

		let selected = workloads.filter { options.workload == "all" || $0.name == options.workload }
		try require(!selected.isEmpty, "Unknown workload: \(options.workload). Use --list.")
		#if DEBUG
			let configuration = "debug"
			try require(options.validate, "Timing requires a release build; use Scripts/benchmark.sh")
		#else
			let configuration = "release"
		#endif
		let environment = Environment()
		var results: [Result] = []
		for workload in selected {
			for size in options.sizes {
				FileHandle.standardError.write(Data("Running \(workload.name), size \(size)\n".utf8))
				results.append(try Harness.run(workload, size: size, options: options))
			}
		}

		let report = Report(
			mode: options.validate ? "validation" : "timing",
			buildConfiguration: configuration,
			environment: environment,
			arguments: arguments,
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
