import Testing

@testable import StanaPerformance

@Suite struct OptionsTests {
	@Test func acceptsIndividualWorkloadAndExplicitRunConfiguration() throws {
		let options = try Options([
			"ui-mount", "--sizes", "10,100", "--samples", "7", "--warmup", "0", "--output", "run.json",
		])
		#expect(options.workload == "ui-mount")
		#expect(options.sizes == [10, 100])
		#expect(options.samples == 7)
		#expect(options.warmup == 0)
		#expect(options.output == "run.json")
	}

	@Test(arguments: [
		["--sizes", ""], ["--sizes", "1,"], ["--sizes", "1,1"], ["--sizes", "0"],
		["--sizes", "100001"], ["--sizes", "text"], ["--samples", "0"], ["--warmup", "-1"],
		["--output"], ["--unknown"], ["ui-mount", "extra"],
	]) func rejectsMalformedRuns(arguments: [String]) {
		#expect(throws: BenchmarkFailure.self) { try Options(arguments) }
	}

	@Test func percentilesUseNearestRankWithoutReorderingRawSamples() {
		let samples = Array((1...20).reversed()).map(Double.init)
		let summary = Summary(samples)
		#expect(summary.minimum == 1)
		#expect(summary.p50 == 10)
		#expect(summary.p95 == 19)
		#expect(summary.maximum == 20)
		#expect(samples.first == 20)
	}
}

@Suite @MainActor struct HarnessTests {
	@Test func everyTrialHasFreshSetupVerificationAndCleanupIncludingWarmup() throws {
		var events: [String] = []
		let workload = Workload(name: "fixture", boundary: "test") { _ in
			events.append("setup")
			var performed = false
			return Trial(
				operation: {
					#expect(!performed)
					performed = true
					events.append("operation")
				},
				verify: {
					#expect(performed)
					events.append("verify")
					return ["verified": 1]
				},
				cleanup: { events.append("cleanup") }
			)
		}
		let options = try Options(["--warmup", "2", "--samples", "3"])
		let result = try Harness.run(workload, size: 1, options: options)
		#expect(events == Array(repeating: ["setup", "operation", "verify", "cleanup"], count: 5).flatMap { $0 })
		#expect(result.samples.count == 3)
		#expect(result.samples.allSatisfy { $0.milliseconds != nil && $0.counters == ["verified": 1] })
	}

	@Test func failedValidationCleansUpAndDoesNotProduceAResult() throws {
		var cleanedUp = false
		let workload = Workload(name: "broken", boundary: "test") { _ in
			Trial(
				operation: {},
				verify: { throw BenchmarkFailure("expected failure") },
				cleanup: { cleanedUp = true }
			)
		}
		let options = try Options(["--validate"])
		#expect(throws: BenchmarkFailure.self) { try Harness.run(workload, size: 1, options: options) }
		#expect(cleanedUp)
	}

	@Test func validationModeChecksEveryRealWorkloadWithoutTiming() throws {
		let workloads = ReactiveWorkloads.all + UIWorkloads.all
		#expect(Set(workloads.map(\.name)).count == 11)
		let options = try Options(["--validate"])
		for workload in workloads {
			for size in [1, 8] {
				let result = try Harness.run(workload, size: size, options: options)
				#expect(result.warmupTrials == 0)
				#expect(result.samples.count == 1)
				#expect(result.samples[0].milliseconds == nil)
				#expect(result.milliseconds == nil)
			}
		}
	}
}
