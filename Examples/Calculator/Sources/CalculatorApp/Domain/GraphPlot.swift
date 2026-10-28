import Foundation
import Stana

struct GraphMark: Equatable {
	let id: String
	let text: String
	let axis: String
	let origin: STNPoint
	var width = 48.0
}

struct GraphFrame: Equatable {
	var grid: STNDrawing
	var curve: STNGPUDrawing
	var data: PlotData
	var marks: [GraphMark]
}

enum GraphPlot {
	static func make(
		source: PlotSource,
		viewport: GraphViewport,
		size: STNSize,
		time: Double,
		highContrast: Bool = false,
		sampleX: Double? = nil
	) -> GraphFrame {
		guard viewport.isValid, size.width >= 160, size.height >= 80 else {
			return .init(
				grid: STNDrawing(),
				curve: STNGPUDrawing(),
				data: .init(segments: [], evaluations: 0, finiteValues: []),
				marks: []
			)
		}

		let data = PlotSampler.sample(source, viewport: viewport, width: size.width, height: size.height, time: time)
		var grid = STNDrawing()
		grid.fillRect(.init(width: size.width, height: size.height), color: CalculatorPalette.plot, cornerRadius: 8)
		let gridColor = highContrast ? CalculatorPalette.axis : CalculatorPalette.grid
		for tick in PlotSampler.ticks(min: viewport.xMin, max: viewport.xMax) {
			let x = (tick - viewport.xMin) / (viewport.xMax - viewport.xMin) * size.width
			grid.fillRect(
				.init(x: x, y: 0, width: tick == 0 ? 1.5 : 1, height: size.height),
				color: tick == 0 ? CalculatorPalette.axis : gridColor
			)
		}

		for tick in PlotSampler.ticks(min: viewport.yMin, max: viewport.yMax) {
			let y = size.height - (tick - viewport.yMin) / (viewport.yMax - viewport.yMin) * size.height
			grid.fillRect(
				.init(x: 0, y: y, width: size.width, height: tick == 0 ? 1.5 : 1),
				color: tick == 0 ? CalculatorPalette.axis : gridColor
			)
		}

		let axisX =
			viewport.xMin <= 0 && viewport.xMax >= 0
			? (0 - viewport.xMin) / (viewport.xMax - viewport.xMin) * size.width : 0
		let axisY =
			viewport.yMin <= 0 && viewport.yMax >= 0
			? size.height - (0 - viewport.yMin) / (viewport.yMax - viewport.yMin) * size.height : size.height
		var marks: [GraphMark] = []
		let xTicks = PlotSampler.ticks(min: viewport.xMin, max: viewport.xMax)
		let longest =
			xTicks.map { Double(tickText($0, lower: viewport.xMin, upper: viewport.xMax).count) * 6.5 + 20 }.max() ?? 24
		let spacing =
			xTicks.count > 1 ? (xTicks[1] - xTicks[0]) / (viewport.xMax - viewport.xMin) * size.width : size.width
		let labelStride = max(1, Int(ceil(longest / max(1, spacing))))
		for (index, tick) in xTicks.enumerated() where index % labelStride == 0 {
			let x = (tick - viewport.xMin) / (viewport.xMax - viewport.xMin) * size.width
			let text = tickText(tick, lower: viewport.xMin, upper: viewport.xMax)
			let width = max(24, Double(text.count) * 6.5 + 8)
			grid.fillRect(.init(x: x - 0.5, y: max(0, axisY - 3), width: 1, height: 6), color: CalculatorPalette.axis)
			marks.append(
				.init(
					id: "x-\(tick)",
					text: text,
					axis: "x",
					origin: .init(
						x: min(max(0, x - width / 2), size.width - width),
						y: min(size.height - 18, max(0, axisY + 5))
					),
					width: width
				)
			)
		}

		for tick in PlotSampler.ticks(min: viewport.yMin, max: viewport.yMax)
		where tick != 0 || viewport.xMin > 0 || viewport.xMax < 0 {
			let y = size.height - (tick - viewport.yMin) / (viewport.yMax - viewport.yMin) * size.height
			let text = tickText(tick, lower: viewport.yMin, upper: viewport.yMax)
			let width = max(24, Double(text.count) * 6.5 + 8)
			grid.fillRect(.init(x: max(0, axisX - 3), y: y - 0.5, width: 6, height: 1), color: CalculatorPalette.axis)
			marks.append(
				.init(
					id: "y-\(tick)",
					text: text,
					axis: "y",
					origin: .init(
						x: min(size.width - width, axisX >= width + 8 ? axisX - width - 8 : axisX + 8),
						y: min(size.height - 18, max(0, y - 9))
					),
					width: width
				)
			)
		}

		marks.append(
			.init(
				id: "axis-x",
				text: "x",
				axis: "name",
				origin: .init(x: size.width - 48, y: max(0, min(size.height - 18, axisY - 22)))
			)
		)
		marks.append(
			.init(id: "axis-y", text: "y", axis: "name", origin: .init(x: min(size.width - 48, axisX + 4), y: 0))
		)
		var curve = STNGPUDrawing()
		for segment in data.segments {
			let points = segment.map { point in
				STNPoint(
					x: (point.x - viewport.xMin) / (viewport.xMax - viewport.xMin) * size.width,
					y: max(
						-size.height,
						min(
							size.height * 2,
							size.height - (point.y - viewport.yMin) / (viewport.yMax - viewport.yMin) * size.height
						)
					)
				)
			}

			curve.strokePolyline(points, color: CalculatorPalette.curve, width: highContrast ? 3 : 2)
		}

		if let x = sampleX, x.isFinite, x >= viewport.xMin, x <= viewport.xMax {
			var values = source.context
			values.x = x
			values.t = time
			if let y = try? source.expression.evaluate(in: values), y >= viewport.yMin, y <= viewport.yMax {
				let sx = (x - viewport.xMin) / (viewport.xMax - viewport.xMin) * size.width
				let sy = size.height - (y - viewport.yMin) / (viewport.yMax - viewport.yMin) * size.height
				curve.fillEllipse(.init(x: sx - 5, y: sy - 5, width: 10, height: 10), color: CalculatorPalette.plot)
				curve.fillEllipse(.init(x: sx - 3.5, y: sy - 3.5, width: 7, height: 7), color: CalculatorPalette.curve)
			}
		}

		return .init(grid: grid, curve: curve, data: data, marks: marks)
	}

	private static func tickText(_ value: Double, lower: Double, upper: Double) -> String {
		let relative = max(abs(lower), abs(upper)) / (upper - lower)
		let digits =
			relative.isFinite && relative > 0
			? min(17, max(4, Int(ceil(log10(relative))) + 3)) : 17
		return String(format: "%.*g", locale: Locale(identifier: "en_US_POSIX"), digits, value).lowercased()
	}
}
