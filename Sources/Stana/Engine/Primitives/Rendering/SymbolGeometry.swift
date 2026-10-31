import Foundation

package indirect enum SymbolPaint: Hashable, Sendable {
	case none
	case currentColor
	case rgba(red: Double, green: Double, blue: Double, alpha: Double)
}

package indirect enum SymbolFillRule: Hashable, Sendable {
	case nonzero, evenodd
}

package indirect enum SymbolLineCap: Hashable, Sendable {
	case butt, round, square
}

package indirect enum SymbolLineJoin: Hashable, Sendable {
	case miter, round, bevel
}

package indirect enum SymbolPathCommand: Hashable, Sendable {
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

package indirect enum SymbolElement: Hashable, Sendable {
	case group(transform: STNAffineTransform, opacity: Double, children: [SymbolElement])
	case path(
		commands: [SymbolPathCommand],
		transform: STNAffineTransform,
		fill: SymbolPaint,
		fillRule: SymbolFillRule,
		fillOpacity: Double,
		stroke: SymbolPaint,
		strokeOpacity: Double,
		strokeWidth: Double,
		lineCap: SymbolLineCap,
		lineJoin: SymbolLineJoin,
		miterLimit: Double,
		opacity: Double
	)
}

/// Owns normalized geometry independently of mount, platform, and compiler lifetimes.
package final class SymbolStorage: Sendable, Hashable {
	package let viewBox: STNRect
	package let mirrorsInRTL: Bool
	package let elements: [SymbolElement]
	package let estimatedBytes: Int
	package let hasStroke: Bool
	private let semanticHash: Int

	package init(viewBox: STNRect, mirrorsInRTL: Bool, elements: [SymbolElement]) {
		precondition(viewBox.size.width > 0 && viewBox.size.height > 0, "Stana: invalid compiled symbol viewBox")
		var count = 0
		var commands = 0

		func number(_ values: Double...) {
			precondition(values.allSatisfy { $0.isFinite && abs($0) <= 1e9 }, "Stana: invalid compiled symbol number")
		}

		func opacity(_ value: Double) {
			precondition(value.isFinite && (0...1).contains(value), "Stana: invalid compiled symbol opacity")
		}

		func paint(_ value: SymbolPaint) {
			if case .rgba(let r, let g, let b, let a) = value {
				precondition(
					[r, g, b, a].allSatisfy { $0.isFinite && (0...1).contains($0) },
					"Stana: invalid compiled symbol color"
				)
			}
		}

		func visit(_ values: [SymbolElement], depth: Int, parent: STNAffineTransform) {
			guard !values.isEmpty else {
				return
			}

			precondition(depth <= 64, "Stana: compiled symbol nesting limit exceeded")
			for value in values {
				count += 1
				precondition(count <= 4096, "Stana: compiled symbol element limit exceeded")
				let transform: STNAffineTransform
				switch value {
				case .group(let t, _, _), .path(_, let t, _, _, _, _, _, _, _, _, _, _): transform = t
				}
				number(transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty)
				let cumulative = parent.concatenating(transform)
				number(cumulative.a, cumulative.b, cumulative.c, cumulative.d, cumulative.tx, cumulative.ty)
				switch value {
				case .group(_, let alpha, let children):
					opacity(alpha)
					visit(children, depth: depth + 1, parent: cumulative)
				case .path(
					let path,
					_,
					let fill,
					_,
					let fa,
					let stroke,
					let sa,
					let width,
					_,
					_,
					let miter,
					let alpha
				):
					paint(fill)
					paint(stroke)
					opacity(fa)
					opacity(sa)
					opacity(alpha)
					number(width, miter)
					precondition(width >= 0 && miter >= 1, "Stana: invalid compiled symbol stroke")
					commands += path.count
					precondition(commands <= 65536, "Stana: compiled symbol command limit exceeded")
					var started = false
					for command in path {
						func point(_ x: Double, _ y: Double) {
							number(
								x,
								y,
								cumulative.a * x + cumulative.c * y + cumulative.tx,
								cumulative.b * x + cumulative.d * y + cumulative.ty
							)
						}
						switch command {
						case .move(let x, let y):
							point(x, y)
							started = true
						case .line(let x, let y): point(x, y)
						case .quadratic(let cx, let cy, let x, let y): point(cx, cy); point(x, y)
						case .cubic(let ax, let ay, let bx, let by, let x, let y):
							point(ax, ay); point(bx, by); point(x, y)
						case .arc(let x, let y, let rx, let ry, let rotation, let start, let sweep):
							number(x, y, rx, ry, rotation, start, sweep)
							precondition(
								rx > 0 && ry > 0 && abs(sweep) <= 2 * .pi,
								"Stana: invalid compiled symbol arc"
							)
						case .close: break
						}

						precondition(started, "Stana: compiled symbol path must start with move")
					}
				}

				number(transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty)
			}
		}

		number(viewBox.minX, viewBox.minY, viewBox.size.width, viewBox.size.height)
		visit(elements, depth: 1, parent: .identity)
		self.viewBox = viewBox
		self.mirrorsInRTL = mirrorsInRTL
		self.elements = elements

		func stroked(_ elements: [SymbolElement]) -> Bool {
			elements.contains {
				switch $0 {
				case .group(_, _, let children): return stroked(children)
				case .path(_, _, _, _, _, let stroke, _, _, _, _, _, _): return stroke != .none
				}
			}
		}

		hasStroke = stroked(elements)
		var hasher = Hasher()
		hasher.combine(viewBox)
		hasher.combine(mirrorsInRTL)
		hasher.combine(elements)
		semanticHash = hasher.finalize()
		estimatedBytes = 128 + count * 256 + commands * 128
	}

	package static func == (lhs: SymbolStorage, rhs: SymbolStorage) -> Bool {
		lhs === rhs
			|| (lhs.semanticHash == rhs.semanticHash && lhs.viewBox == rhs.viewBox
				&& lhs.mirrorsInRTL == rhs.mirrorsInRTL && lhs.elements == rhs.elements)
	}

	package func hash(into hasher: inout Hasher) {
		hasher.combine(semanticHash)
	}
}

/// Fit and effect are paint-only and never replace node presentation geometry.
package struct SymbolPresentation: Equatable, Sendable {
	package let asset: SymbolStorage
	package let transform: STNAffineTransform
	package let color: STNColor
	package let strokeWidth: Double?
	package let generation: UInt64
	package let preparationLimited: Bool
	package let preparationScale: Double

	package init(
		asset: SymbolStorage,
		transform: STNAffineTransform,
		color: STNColor,
		strokeWidth: Double?,
		generation: UInt64,
		preparationLimited: Bool = false,
		preparationScale: Double? = nil
	) {
		self.asset = asset
		self.transform = transform
		self.color = color
		self.strokeWidth = strokeWidth
		self.generation = generation
		self.preparationLimited = preparationLimited
		self.preparationScale = preparationScale ?? transform.maximumScale
	}
}

package enum SymbolFailureCode: Sendable, Equatable {
	case preparationFailed, resourceLimitExceeded, renderingFailed
}

package struct SymbolRenderResult: Sendable {
	package let node: STNNodeID
	package let generation: UInt64
	package let epoch: UInt64
	package let code: SymbolFailureCode?

	package init(node: STNNodeID, generation: UInt64, epoch: UInt64, code: SymbolFailureCode?) {
		self.node = node
		self.generation = generation
		self.epoch = epoch
		self.code = code
	}
}

package func symbolSquare(size: Double, content: STNRect) -> STNRect {
	let side = min(size, content.size.width, content.size.height)
	return .init(
		x: content.minX + (content.size.width - side) / 2,
		y: content.minY + (content.size.height - side) / 2,
		width: side,
		height: side
	)
}

package struct SymbolEffectSample: Equatable, Sendable {
	package var rotation: Double = 0
	package var scale: Double = 1
	package var verticalFraction: Double = 0

	package init(rotation: Double = 0, scale: Double = 1, verticalFraction: Double = 0) {
		self.rotation = rotation
		self.scale = scale
		self.verticalFraction = verticalFraction
	}

	package func transform(square: STNRect) -> STNAffineTransform {
		let x = square.minX + square.size.width / 2, y = square.minY + square.size.height / 2
		return .translation(x: x, y: y + verticalFraction * square.size.height)
			.concatenating(.rotation(radians: rotation)).concatenating(.scale(x: scale, y: scale))
			.concatenating(.translation(x: -x, y: -y))
	}
}
