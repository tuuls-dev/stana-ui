import Foundation

package struct SymbolCompileError: Error, Equatable, Sendable {
	package let id: String
	package let message: String
	package var line: Int = 1
	package var column: Int = 1

	package init(_ id: String, _ message: String, line: Int = 1, column: Int = 1) {
		self.id = id
		self.message = message
		self.line = line
		self.column = column
	}
}

package func checked(_ value: Double) throws -> Double {
	guard value.isFinite else {
		throw SymbolCompileError("invalidValue", "Nonfinite or overflowing SVG number")
	}

	guard abs(value) <= 1e9 else {
		throw SymbolCompileError("budgetExceeded", "SVG numeric magnitude exceeds 1e9")
	}

	return value == 0 ? 0 : value
}

package func literal(_ value: Double) -> String {
	String(value == 0 ? 0 : value)
}

package struct SymbolTransform: Equatable, Sendable {
	package var v: [Double] = [1, 0, 0, 1, 0, 0]

	package func concatenating(_ r: Self) throws -> Self {
		let a = v, b = r.v
		return try Self(
			v: [
				a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
				a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
				a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5],
			]
			.map(checked)
		)
	}

	package var swift: String {
		"STNAffineTransform(a: \(literal(v[0])), b: \(literal(v[1])), c: \(literal(v[2])), d: \(literal(v[3])), tx: \(literal(v[4])), ty: \(literal(v[5])))"
	}
}

package enum CompiledCommand: Equatable, Sendable {
	case move(Double, Double)
	case line(Double, Double)
	case quadratic(Double, Double, Double, Double)
	case cubic(Double, Double, Double, Double, Double, Double)
	case arc(Double, Double, Double, Double, Double, Double, Double)
	case close

	package var swift: String {
		switch self {
		case .move(let x, let y): return ".move(x: \(literal(x)), y: \(literal(y)))"
		case .line(let x, let y): return ".line(x: \(literal(x)), y: \(literal(y)))"
		case .quadratic(let cx, let cy, let x, let y):
			return ".quadratic(controlX: \(literal(cx)), controlY: \(literal(cy)), x: \(literal(x)), y: \(literal(y)))"
		case .cubic(let ax, let ay, let bx, let by, let x, let y):
			return
				".cubic(control1X: \(literal(ax)), control1Y: \(literal(ay)), control2X: \(literal(bx)), control2Y: \(literal(by)), x: \(literal(x)), y: \(literal(y)))"
		case .arc(let x, let y, let rx, let ry, let rotation, let start, let sweep):
			return
				".arc(centerX: \(literal(x)), centerY: \(literal(y)), radiusX: \(literal(rx)), radiusY: \(literal(ry)), rotation: \(literal(rotation)), startAngle: \(literal(start)), sweepAngle: \(literal(sweep)))"
		case .close: return ".close"
		}
	}
}

package enum CompiledPaint: Equatable, Sendable {
	case none, currentColor
	case rgba(Double, Double, Double, Double)

	package var swift: String {
		switch self {
		case .none: return ".none"
		case .currentColor: return ".currentColor"
		case .rgba(let r, let g, let b, let a):
			return ".rgba(red: \(literal(r)), green: \(literal(g)), blue: \(literal(b)), alpha: \(literal(a)))"
		}
	}
}

package struct CompiledStyle: Equatable, Sendable {
	package var fill = CompiledPaint.rgba(0, 0, 0, 1)
	package var stroke = CompiledPaint.none
	package var fillRule = "nonzero"
	package var fillOpacity = 1.0
	package var strokeOpacity = 1.0
	package var strokeWidth = 1.0
	package var lineCap = "butt"
	package var lineJoin = "miter"
	package var miterLimit = 4.0
}

package indirect enum CompiledElement: Equatable, Sendable {
	case group(SymbolTransform, Double, [CompiledElement])
	case path([CompiledCommand], SymbolTransform, CompiledStyle, Double)

	package var swift: String {
		switch self {
		case .group(let t, let alpha, let children):
			return
				".group(transform: \(t.swift), opacity: \(literal(alpha)), children: [\(children.map(\.swift).joined(separator: ","))])"
		case .path(let commands, let t, let s, let alpha):
			return
				".path(commands: [\(commands.map(\.swift).joined(separator: ","))], transform: \(t.swift), fill: \(s.fill.swift), fillRule: .\(s.fillRule), fillOpacity: \(literal(s.fillOpacity)), stroke: \(s.stroke.swift), strokeOpacity: \(literal(s.strokeOpacity)), strokeWidth: \(literal(s.strokeWidth)), lineCap: .\(s.lineCap), lineJoin: .\(s.lineJoin), miterLimit: \(literal(s.miterLimit)), opacity: \(literal(alpha)))"
		}
	}
}

package struct CompiledSymbol: Equatable, Sendable {
	package let viewBox: [Double]
	package let elements: [CompiledElement]

	package func swift(mirrorsInRTL: Bool) -> String {
		"STNSymbolAsset._compiled(version: 1, viewBox: STNRect(x: \(literal(viewBox[0])), y: \(literal(viewBox[1])), width: \(literal(viewBox[2])), height: \(literal(viewBox[3]))), mirrorsInRTL: \(mirrorsInRTL), elements: [\(elements.map(\.swift).joined(separator: ","))])"
	}
}
