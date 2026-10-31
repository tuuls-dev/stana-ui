import Foundation

package func svgShape(_ name: String, _ a: [String: String], limit: Int) throws -> [CompiledCommand] {
	func length(_ key: String, _ fallback: Double = 0) throws -> Double {
		try a[key].map(svgLength) ?? fallback
	}

	func positive(_ key: String, _ fallback: Double = 0) throws -> Double {
		let v = try length(key, fallback)
		guard v >= 0 else {
			throw SymbolCompileError("invalidValue", "Negative \(name) \(key)")
		}

		return v
	}

	func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) throws -> [CompiledCommand] {
		guard rx > 0 && ry > 0 else {
			return []
		}

		let right = try checked(x + rx)
		_ = try checked(x - rx); _ = try checked(y - ry); _ = try checked(y + ry)
		return [.move(right, y), .arc(x, y, rx, ry, 0, 0, 2 * .pi), .close]
	}

	switch name {
	case "path": return try svgPath(a["d"] ?? "", limit: limit)
	case "circle": return try ellipse(length("cx"), length("cy"), positive("r"), positive("r"))
	case "ellipse": return try ellipse(length("cx"), length("cy"), positive("rx"), positive("ry"))
	case "line": return try [.move(length("x1"), length("y1")), .line(length("x2"), length("y2"))]
	case "polyline", "polygon":
		var scanner = SVGNumbers(a["points"] ?? "")
		var result: [CompiledCommand] = []
		scanner.spaces()
		while scanner.index < scanner.bytes.count {
			guard result.count < limit else {
				throw SymbolCompileError("budgetExceeded", "Normalized SVG command limit exceeded")
			}

			let x = try scanner.number(separated: !result.isEmpty), y = try scanner.number()
			result.append(result.isEmpty ? .move(x, y) : .line(x, y))
			scanner.spaces()
		}

		if name == "polygon" && !result.isEmpty {
			result.append(.close)
		}

		return result
	case "rect":
		let x = try length("x"), y = try length("y"), width = try positive("width"), height = try positive("height")
		let ex = try checked(x + width), ey = try checked(y + height)
		let rawRX = try a["rx"].map { _ in try positive("rx") }

		let rawRY = try a["ry"].map { _ in try positive("ry") }

		let rx = min(rawRX ?? rawRY ?? 0, width / 2), ry = min(rawRY ?? rawRX ?? 0, height / 2)
		guard width > 0 && height > 0 else {
			return []
		}

		if rx == 0 || ry == 0 {
			return [.move(x, y), .line(ex, y), .line(ex, ey), .line(x, ey), .close]
		}

		return [
			.move(x + rx, y), .line(ex - rx, y), .arc(ex - rx, y + ry, rx, ry, 0, -.pi / 2, .pi / 2),
			.line(ex, ey - ry), .arc(ex - rx, ey - ry, rx, ry, 0, 0, .pi / 2),
			.line(x + rx, ey), .arc(x + rx, ey - ry, rx, ry, 0, .pi / 2, .pi / 2),
			.line(x, y + ry), .arc(x + rx, y + ry, rx, ry, 0, .pi, .pi / 2), .close,
		]
	default: return []
	}
}
