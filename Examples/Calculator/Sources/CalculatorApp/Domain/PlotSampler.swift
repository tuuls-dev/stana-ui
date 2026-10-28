import Foundation

struct PlotPoint: Equatable {
	let x: Double
	let y: Double
}

struct PlotData: Equatable {
	var segments: [[PlotPoint]]
	var evaluations: Int
	var finiteValues: [Double]
}

/// Bounded screen-space subdivision. Undefined samples and unresolved jumps break the curve.
enum PlotSampler {
	static func sample(_ source: PlotSource, viewport: GraphViewport, width: Double, height: Double, time: Double)
		-> PlotData
	{
		guard width.isFinite, height.isFinite, width > 0, height > 0,
			viewport.xMin.isFinite, viewport.xMax.isFinite, viewport.yMin.isFinite, viewport.yMax.isFinite,
			viewport.xMax > viewport.xMin, viewport.yMax > viewport.yMin
		else {
			return .init(segments: [], evaluations: 0, finiteValues: [])
		}

		var context = source.context
		context.t = time
		var evaluations = 0
		var values: [Double] = []
		var segments: [[PlotPoint]] = []
		var run: [PlotPoint] = []
		let budget = 4096
		let ySpan = viewport.yMax - viewport.yMin

		func value(_ x: Double) -> PlotPoint? {
			guard evaluations < budget else {
				return nil
			}
			evaluations += 1
			context.x = x
			guard let y = try? source.expression.evaluate(in: context), y.isFinite else {
				return nil
			}

			values.append(y)
			return PlotPoint(x: x, y: y)
		}

		func flush() {
			if run.count > 1 {
				segments.append(run)
			}

			run.removeAll(keepingCapacity: true)
		}

		func append(_ a: PlotPoint, _ b: PlotPoint) {
			// Entirely offscreen runs cannot be useful line segments, and may hide a pole.
			if (a.y < viewport.yMin && b.y < viewport.yMin) || (a.y > viewport.yMax && b.y > viewport.yMax) {
				flush()
				return
			}

			if run.last != a {
				flush()
				run.append(a)
			}

			run.append(b)
		}

		func subdivide(_ x0: Double, _ a: PlotPoint?, _ x1: Double, _ b: PlotPoint?, depth: Int) {
			let midX = x0 + (x1 - x0) / 2
			let mid = value(midX)
			if a == nil && b == nil && mid == nil {
				flush()
				return
			}

			let narrow = (x1 - x0) / (viewport.xMax - viewport.xMin) * width <= 0.5
			if let a, let b, let mid {
				let error = abs(mid.y - (a.y / 2 + b.y / 2)) / ySpan * height
				let jump = abs(b.y - a.y) / ySpan * height
				if error <= 0.65 && jump <= height * 0.6 {
					append(a, b)
					return
				}
			}

			guard depth < 10, !narrow, evaluations + 2 < budget else {
				flush()
				return
			}
			subdivide(x0, a, midX, mid, depth: depth + 1)
			subdivide(midX, mid, x1, b, depth: depth + 1)
		}

		let count = min(256, max(64, Int(width / 4)))
		var x = viewport.xMin
		var previous = value(x)
		for index in 1...count {
			let nextX = viewport.xMin + (viewport.xMax - viewport.xMin) * Double(index) / Double(count)
			let next = value(nextX)
			subdivide(x, previous, nextX, next, depth: 0)
			x = nextX
			previous = next
		}
		flush()
		return PlotData(segments: segments, evaluations: evaluations, finiteValues: values)
	}

	static func ticks(min: Double, max: Double) -> [Double] {
		let raw = (max - min) / 8
		guard raw.isFinite, raw > 0 else {
			return []
		}

		let power = pow(10, floor(log10(raw)))
		let fraction = raw / power
		let step = (fraction <= 1 ? 1.0 : fraction <= 2 ? 2.0 : fraction <= 5 ? 5.0 : 10.0) * power
		guard step.isFinite, step > 0 else {
			return []
		}

		var result: [Double] = []
		var value = ceil(min / step) * step
		while value <= max, result.count < 32 {
			result.append(value == 0 ? 0 : value)
			let next = value + step
			guard next > value else {
				break
			}
			value = next
		}

		return result
	}
}
