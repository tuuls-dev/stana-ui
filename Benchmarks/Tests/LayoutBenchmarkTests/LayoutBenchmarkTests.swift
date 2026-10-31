import StanaCore
import StanaText
import Testing

@testable import LayoutBenchmarks

@Suite @MainActor struct LayoutBenchmarkTests {
	@Test func everyFixtureSettlesAtSmallAndWideSizes() throws {
		for workload in Workload.allCases {
			for size in [1, 8, 100] {
				let fixture = Fixture(workload: workload, size: size, text: TestTextService())
				defer {
					fixture.document.close()
				}
				fixture.document.layoutCountersEnabled = true
				fixture.document.metrics = .init()
				fixture.operate()
				try fixture.verify()
				#expect(fixture.nodeCount == size + (workload == .scrolling ? 3 : 2))
				#expect(fixture.flexibleChildCount == (workload == .flex ? size : 0))
				if workload == .sameSize {
					#expect(fixture.document.metrics.textMeasureCalls == 1)
					#expect(fixture.document.metrics.measureCacheHits == size - 1)
				}

				if workload == .scrolling {
					#expect(fixture.document.metrics.textMeasureCalls == 0)
				}
			}
		}
	}

	@Test func optionsRejectAmbiguousOrInvalidReports() throws {
		for arguments in [
			["unknown"], ["cold", "flex"], ["--sizes", "0"], ["--sizes", "1,"],
			["--samples", "0"], ["--warmup", "-1"], ["--spans", "unknown"],
			["--text", "unknown"], ["--text", "native", "--validate"], ["--output"],
		] {
			#expect(throws: Failure.self) { try Options(arguments) }
		}

		let options = try Options(["same-size", "--sizes", "1,8", "--counters", "--spans", "all"])
		#expect(options.sizes == [1, 8])
		#expect(options.counters)
		#expect(options.spans == Set(WorkSpan.allCases))
		#expect(try Options([]).spans.isEmpty)
		#expect(try !Options([]).counters)
	}
}
