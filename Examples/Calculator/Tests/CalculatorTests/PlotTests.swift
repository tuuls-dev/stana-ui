import Foundation
import Testing
@testable import CalculatorApp

@Suite struct PlotTests {
	private func source(_ expression: String) throws -> PlotSource {
		.init(expression: try CalculatorMath.compile(expression), context: .init())
	}

	@Test func sineSamplesUseTheDeclaredCoordinatesAndStayBounded() throws {
		let data = PlotSampler.sample(try source("sin(x)"), viewport: .init(), width: 600, height: 300, time: 0)
		#expect(!data.segments.isEmpty)
		#expect(data.evaluations <= 4096)
		for point in data.segments.flatMap({ $0 }) {
			#expect(abs(point.y - sin(point.x)) < 1e-14)
		}
	}

	@Test func polesAreNeverBridgedAcrossTheOrigin() throws {
		let data = PlotSampler.sample(try source("1/x"), viewport: .init(), width: 600, height: 300, time: 0)
		#expect(data.segments.count >= 2)
		for segment in data.segments {
			#expect(!(segment.first!.x < 0 && segment.last!.x > 0))
		}
	}

	@Test func tangentDiscontinuitiesAndRestrictedDomainsSplitRuns() throws {
		let tangent = PlotSampler.sample(try source("tan(x)"), viewport: .init(), width: 600, height: 300, time: 0)
		for segment in tangent.segments {
			for pole in [-3 * Double.pi / 2, -.pi / 2, .pi / 2, 3 * .pi / 2] {
				#expect(!(segment.first!.x < pole && segment.last!.x > pole))
			}
		}

		let root = PlotSampler.sample(try source("sqrt(x)"), viewport: .init(), width: 600, height: 300, time: 0)
		#expect(!root.segments.isEmpty)
		#expect(root.segments.flatMap { $0 }.allSatisfy { $0.x >= 0 })
		let empty = PlotSampler.sample(try source("sqrt(-1)"), viewport: .init(), width: 600, height: 300, time: 0)
		#expect(empty.segments.isEmpty)
	}

	@Test func timeAndConstantsHaveHonestValues() throws {
		let data = PlotSampler.sample(
			try source("t+3"),
			viewport: .init(yMin: 0, yMax: 10),
			width: 600,
			height: 300,
			time: 2
		)
		#expect(!data.segments.isEmpty)
		#expect(data.segments.flatMap { $0 }.allSatisfy { $0.y == 5 })
	}
	@Test func axesHaveNumberedTicksAndNamesEvenWhenTheOriginIsOffscreen() throws {
		for viewport in [GraphViewport(), .init(xMin: 10, xMax: 20, yMin: -2, yMax: 2)] {
			let frame = GraphPlot.make(
				source: try source("sin(x)"),
				viewport: viewport,
				size: .init(width: 600, height: 300),
				time: 0
			)
			#expect(frame.marks.filter { $0.axis == "x" }.count >= 5)
			#expect(frame.marks.filter { $0.axis == "y" }.count >= 5)
			#expect(frame.marks.contains { $0.text == "x" && $0.axis == "name" })
			#expect(frame.marks.contains { $0.text == "y" && $0.axis == "name" })
			#expect(
				frame.marks.allSatisfy {
					$0.origin.x >= 0 && $0.origin.x + $0.width <= 600 && $0.origin.y >= 0 && $0.origin.y + 18 <= 300
				}
			)
		}
	}

	@Test func tracingMovesTheMarkerWithoutChangingATimeIndependentFunction() throws {
		let source = try source("sin(x)")
		let first = GraphPlot.make(
			source: source,
			viewport: .init(),
			size: .init(width: 600, height: 300),
			time: 0,
			sampleX: 0
		)
		let second = GraphPlot.make(
			source: source,
			viewport: .init(),
			size: .init(width: 600, height: 300),
			time: 1,
			sampleX: 1
		)
		#expect(first.data == second.data)
		#expect(first.curve != second.curve)
	}
	@Test func tightlyZoomedLabelsStayDistinctAndDegenerateViewportsAreSafe() throws {
		let frame = GraphPlot.make(
			source: try source("sin(x)"),
			viewport: .init(xMin: 1.2345678, xMax: 1.2345679),
			size: .init(width: 600, height: 300),
			time: 0
		)
		let labels = frame.marks.filter { $0.axis == "x" }.map(\.text)
		#expect(labels.count >= 2)
		#expect(Set(labels).count == labels.count)
		let empty = GraphPlot.make(
			source: try source("x"),
			viewport: .init(xMin: 1, xMax: 1),
			size: .init(width: 600, height: 300),
			time: 0
		)
		#expect(empty.marks.isEmpty)
		#expect(empty.data.segments.isEmpty)
	}
}
