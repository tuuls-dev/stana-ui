import Foundation

extension SymbolStorage {
	/// Conservative local ink hull, including transformed stroke joins and authored overflow.
	package func inkBounds(strokeWidth override: Double?) -> STNRect? {
		func visit(_ elements: [SymbolElement], parent: STNAffineTransform) -> STNRect? {
			var result = STNRect.zero
			for element in elements {
				switch element {
				case .group(let transform, let opacity, let children):
					if opacity > 0 {
						guard let bounds = visit(children, parent: parent.concatenating(transform)) else {
							return nil
						}

						result = result.union(bounds)
					}
				case .path(
					let commands,
					let transform,
					let fill,
					_,
					let fillAlpha,
					let stroke,
					let strokeAlpha,
					let authoredWidth,
					let cap,
					let join,
					let miter,
					let opacity
				):
					guard opacity > 0 else {
						continue
					}

					let hasFill = fill != .none && fillAlpha > 0
					let width = override ?? authoredWidth
					let hasStroke = stroke != .none && strokeAlpha > 0 && width > 0
					guard hasFill || hasStroke else {
						continue
					}

					var points: [STNPoint] = []
					for command in commands {
						switch command {
						case .move(let x, let y), .line(let x, let y): points.append(.init(x: x, y: y))
						case .quadratic(let x, let y, let ex, let ey):
							points.append(contentsOf: [.init(x: x, y: y), .init(x: ex, y: ey)])
						case .cubic(let x, let y, let bx, let by, let ex, let ey):
							points.append(contentsOf: [.init(x: x, y: y), .init(x: bx, y: by), .init(x: ex, y: ey)])
						case .arc(let x, let y, let rx, let ry, let rotation, _, _):
							let dx = hypot(rx * cos(rotation), ry * sin(rotation))
							let dy = hypot(rx * sin(rotation), ry * cos(rotation))
							points.append(contentsOf: [.init(x: x - dx, y: y - dy), .init(x: x + dx, y: y + dy)])
						case .close: break
						}
					}

					guard !points.isEmpty else {
						continue
					}

					let margin =
						hasStroke ? width / 2 * max(join == .miter ? miter : 1, cap == .square ? sqrt(2) : 1) : 0
					let left = points.map(\.x).min()! - margin, top = points.map(\.y).min()! - margin
					let right = points.map(\.x).max()! + margin, bottom = points.map(\.y).max()! + margin
					guard [left, top, right, bottom, right - left, bottom - top].allSatisfy(\.isFinite) else {
						return nil
					}

					let local = STNRect(x: left, y: top, width: right - left, height: bottom - top)
					guard let bounds = symbolEnclosing(parent.concatenating(transform), local) else {
						return nil
					}

					result = result.union(bounds)
				}
			}

			return result
		}

		return visit(elements, parent: .identity)
	}
}

/// Checked symbol projection, allowing a backend resource diagnostic instead of overflowing a geometry precondition.
package func symbolEnclosing(_ transform: STNAffineTransform, _ rect: STNRect) -> STNRect? {
	guard transform.inverse != nil else {
		return .zero
	}

	let corners = [(rect.minX, rect.minY), (rect.maxX, rect.minY), (rect.minX, rect.maxY), (rect.maxX, rect.maxY)]
	let xs = corners.map { transform.a * $0.0 + transform.c * $0.1 + transform.tx }

	let ys = corners.map { transform.b * $0.0 + transform.d * $0.1 + transform.ty }

	let width = xs.max()! - xs.min()!, height = ys.max()! - ys.min()!
	guard (xs + ys + [width, height]).allSatisfy(\.isFinite) else {
		return nil
	}

	return .init(x: xs.min()!, y: ys.min()!, width: width, height: height)
}
