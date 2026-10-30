import Foundation

@MainActor struct Trial {
	let operation: @MainActor () throws -> Void
	let verify: @MainActor () throws -> [String: Int]
	let cleanup: @MainActor () -> Void
}

@MainActor struct Workload {
	let name: String
	let boundary: String
	let makeTrial: @MainActor (Int) throws -> Trial
}

func require(_ condition: Bool, _ message: String) throws {
	guard condition else {
		throw BenchmarkFailure(message)
	}
}

struct Summary: Encodable {
	let minimum: Double
	let p50: Double
	let p95: Double
	let maximum: Double

	init(_ samples: [Double]) {
		precondition(!samples.isEmpty)
		let sorted = samples.sorted()
		minimum = sorted[0]
		p50 = sorted[Int(ceil(Double(sorted.count) * 0.5)) - 1]
		p95 = sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]
		maximum = sorted[sorted.count - 1]
	}
}

struct Sample: Encodable {
	let milliseconds: Double?
	let counters: [String: Int]
}

struct Result: Encodable {
	let workload: String
	let size: Int
	let timedBoundary: String
	let warmupTrials: Int
	let samples: [Sample]
	let milliseconds: Summary?
}

@MainActor enum Harness {
	static func run(_ workload: Workload, size: Int, options: Options) throws -> Result {
		let warmup = options.validate ? 0 : options.warmup
		let count = options.validate ? 1 : options.samples
		var samples: [Sample] = []
		for iteration in 0..<(warmup + count) {
			let trial = try workload.makeTrial(size)
			defer { trial.cleanup() }
			let elapsed: Double?
			if options.validate {
				try trial.operation()
				elapsed = nil
			} else {
				let clock = ContinuousClock()
				let start = clock.now
				try trial.operation()
				let duration = start.duration(to: clock.now)
				elapsed =
					Double(duration.components.seconds) * 1_000
					+ Double(duration.components.attoseconds) / 1e15
			}

			let counters = try trial.verify()
			if iteration >= warmup {
				samples.append(Sample(milliseconds: elapsed, counters: counters))
			}
		}

		return Result(
			workload: workload.name,
			size: size,
			timedBoundary: workload.boundary,
			warmupTrials: warmup,
			samples: samples,
			milliseconds: options.validate ? nil : Summary(samples.compactMap(\.milliseconds))
		)
	}
}
