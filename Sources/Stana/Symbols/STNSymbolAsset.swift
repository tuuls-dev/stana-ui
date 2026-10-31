import StanaPrimitives

/// Immutable shared artwork, normally produced by `@MakeSTNSymbol`.
public struct STNSymbolAsset: Sendable, Equatable {
	package let storage: SymbolStorage

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.storage == rhs.storage
	}
}

extension STNSymbolAsset {
	/// Generated-code support, not a general SVG authoring API.
	public indirect enum _Paint: Sendable, Equatable {
		case none
		case currentColor
		case rgba(red: Double, green: Double, blue: Double, alpha: Double)
	}

	/// Generated-code support, not a general SVG authoring API.
	public indirect enum _FillRule: Sendable, Equatable {
		case nonzero, evenodd
	}

	/// Generated-code support, not a general SVG authoring API.
	public indirect enum _LineCap: Sendable, Equatable {
		case butt, round, square
	}

	/// Generated-code support, not a general SVG authoring API.
	public indirect enum _LineJoin: Sendable, Equatable {
		case miter, round, bevel
	}

	/// Generated-code support, not a general SVG authoring API.
	public indirect enum _PathCommand: Sendable, Equatable {
		case move(x: Double, y: Double)
		case line(x: Double, y: Double)
		case quadratic(controlX: Double, controlY: Double, x: Double, y: Double)
		case cubic(control1X: Double, control1Y: Double, control2X: Double, control2Y: Double, x: Double, y: Double)
		case arc(
			centerX: Double,
			centerY: Double,
			radiusX: Double,
			radiusY: Double,
			rotation: Double,
			startAngle: Double,
			sweepAngle: Double
		)
		case close
	}

	/// Generated-code support, not a general SVG authoring API.
	public indirect enum _Element: Sendable, Equatable {
		case group(transform: STNAffineTransform, opacity: Double, children: [_Element])
		case path(
			commands: [_PathCommand],
			transform: STNAffineTransform,
			fill: _Paint,
			fillRule: _FillRule,
			fillOpacity: Double,
			stroke: _Paint,
			strokeOpacity: Double,
			strokeWidth: Double,
			lineCap: _LineCap,
			lineJoin: _LineJoin,
			miterLimit: Double,
			opacity: Double
		)
	}

	/// Constructs typed macro output. This source-versioned bridge accepts version 1 only.
	public static func _compiled(version: UInt32, viewBox: STNRect, mirrorsInRTL: Bool, elements: [_Element]) -> Self {
		precondition(version == 1, "Stana: symbol compiler/runtime package mismatch (expected bridge version 1)")
		var elementCount = 0, commandCount = 0
		func validateBudgets(_ values: [_Element], depth: Int) {
			guard !values.isEmpty else {
				return
			}

			precondition(depth <= 64, "Stana: compiled symbol nesting limit exceeded")
			precondition(values.count <= 4096 - elementCount, "Stana: compiled symbol element limit exceeded")
			elementCount += values.count
			for element in values {
				switch element {
				case .group(_, _, let children): validateBudgets(children, depth: depth + 1)
				case .path(let commands, _, _, _, _, _, _, _, _, _, _, _):
					precondition(
						commands.count <= 65536 - commandCount,
						"Stana: compiled symbol command limit exceeded"
					)
					commandCount += commands.count
				}
			}
		}
		validateBudgets(elements, depth: 1)

		return Self(
			storage: SymbolStorage(
				viewBox: STNRect(
					x: symbolZero(viewBox.minX),
					y: symbolZero(viewBox.minY),
					width: symbolZero(viewBox.size.width),
					height: symbolZero(viewBox.size.height)
				),
				mirrorsInRTL: mirrorsInRTL,
				elements: elements.map(\.prepared)
			)
		)
	}
}

extension STNSymbolAsset._Paint {
	fileprivate var prepared: SymbolPaint {
		switch self {
		case .none: return .none
		case .currentColor: return .currentColor
		case .rgba(let red, let green, let blue, let alpha):
			return .rgba(
				red: symbolZero(red),
				green: symbolZero(green),
				blue: symbolZero(blue),
				alpha: symbolZero(alpha)
			)
		}
	}
}

extension STNSymbolAsset._FillRule {
	fileprivate var prepared: SymbolFillRule {
		switch self {
		case .nonzero: return .nonzero
		case .evenodd: return .evenodd
		}
	}
}

extension STNSymbolAsset._LineCap {
	fileprivate var prepared: SymbolLineCap {
		switch self {
		case .butt: return .butt
		case .round: return .round
		case .square: return .square
		}
	}
}

extension STNSymbolAsset._LineJoin {
	fileprivate var prepared: SymbolLineJoin {
		switch self {
		case .miter: return .miter
		case .round: return .round
		case .bevel: return .bevel
		}
	}
}

extension STNSymbolAsset._PathCommand {
	fileprivate var prepared: SymbolPathCommand {
		switch self {
		case .move(let x, let y):
			return .move(x: symbolZero(x), y: symbolZero(y))
		case .line(let x, let y):
			return .line(x: symbolZero(x), y: symbolZero(y))
		case .quadratic(let controlX, let controlY, let x, let y):
			return .quadratic(
				controlX: symbolZero(controlX),
				controlY: symbolZero(controlY),
				x: symbolZero(x),
				y: symbolZero(y)
			)
		case .cubic(let control1X, let control1Y, let control2X, let control2Y, let x, let y):
			return .cubic(
				control1X: symbolZero(control1X),
				control1Y: symbolZero(control1Y),
				control2X: symbolZero(control2X),
				control2Y: symbolZero(control2Y),
				x: symbolZero(x),
				y: symbolZero(y)
			)
		case .arc(let centerX, let centerY, let radiusX, let radiusY, let rotation, let startAngle, let sweepAngle):
			return .arc(
				centerX: symbolZero(centerX),
				centerY: symbolZero(centerY),
				radiusX: symbolZero(radiusX),
				radiusY: symbolZero(radiusY),
				rotation: symbolZero(rotation),
				startAngle: symbolZero(startAngle),
				sweepAngle: symbolZero(sweepAngle)
			)
		case .close: return .close
		}
	}
}

extension STNSymbolAsset._Element {
	fileprivate var prepared: SymbolElement {
		switch self {
		case .group(let transform, let opacity, let children):
			return .group(
				transform: symbolTransform(transform),
				opacity: symbolZero(opacity),
				children: children.map(\.prepared)
			)
		case .path(
			let commands,
			let transform,
			let fill,
			let fillRule,
			let fillOpacity,
			let stroke,
			let strokeOpacity,
			let strokeWidth,
			let lineCap,
			let lineJoin,
			let miterLimit,
			let opacity
		):
			return .path(
				commands: commands.map(\.prepared),
				transform: symbolTransform(transform),
				fill: fill.prepared,
				fillRule: fillRule.prepared,
				fillOpacity: symbolZero(fillOpacity),
				stroke: stroke.prepared,
				strokeOpacity: symbolZero(strokeOpacity),
				strokeWidth: symbolZero(strokeWidth),
				lineCap: lineCap.prepared,
				lineJoin: lineJoin.prepared,
				miterLimit: symbolZero(miterLimit),
				opacity: symbolZero(opacity)
			)
		}
	}
}

private func symbolZero(_ value: Double) -> Double {
	value == 0 ? 0 : value
}

private func symbolTransform(_ value: STNAffineTransform) -> STNAffineTransform {
	.init(
		a: symbolZero(value.a),
		b: symbolZero(value.b),
		c: symbolZero(value.c),
		d: symbolZero(value.d),
		tx: symbolZero(value.tx),
		ty: symbolZero(value.ty)
	)
}
