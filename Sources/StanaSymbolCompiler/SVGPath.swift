import Foundation

package func svgPath(_ source: String, limit: Int = 65536) throws -> [CompiledCommand] {
	var scanner = SVGNumbers(source)
	var commands: [CompiledCommand] = []
	var command: UInt8 = 0
	var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0
	var cubicControl: (Double, Double)?
	var quadraticControl: (Double, Double)?

	func add(_ value: CompiledCommand) throws {
		guard commands.count < limit else {
			throw SymbolCompileError("budgetExceeded", "Normalized SVG path command limit exceeded")
		}

		commands.append(value)
	}

	scanner.spaces()
	while scanner.index < scanner.bytes.count {
		let byte = scanner.bytes[scanner.index]
		let explicit = (65...90).contains(byte) || (97...122).contains(byte)
		if explicit {
			command = byte
			scanner.index += 1
		}

		let lower = command | 32
		let relative = command >= 97
		guard [109, 108, 104, 118, 99, 115, 113, 116, 97, 122].contains(lower) else {
			throw SymbolCompileError("invalidValue", "Unsupported or missing SVG path command")
		}

		guard !commands.isEmpty || lower == 109 else {
			throw SymbolCompileError("invalidValue", "SVG path must begin with moveto")
		}

		if lower == 122 {
			guard explicit else {
				throw SymbolCompileError("invalidValue", "Unexpected arguments after closepath")
			}

			try add(.close)
			x = startX; y = startY
			cubicControl = nil; quadraticControl = nil
			command = 0
			scanner.spaces()
			continue
		}

		var firstArgument = true

		func n() throws -> Double {
			defer { firstArgument = false }

			return try scanner.number(separated: !(explicit && firstArgument))
		}

		func point() throws -> (Double, Double) {
			try (checked(n() + (relative ? x : 0)), checked(n() + (relative ? y : 0)))
		}

		var nextCubic: (Double, Double)?
		var nextQuadratic: (Double, Double)?
		switch lower {
		case 109, 108:
			let p = try point()
			try add(lower == 109 ? .move(p.0, p.1) : .line(p.0, p.1))
			x = p.0; y = p.1
			if lower == 109 {
				startX = x
				startY = y
				command = relative ? 108 : 76
			}
		case 104:
			x = try checked(n() + (relative ? x : 0))
			try add(.line(x, y))
		case 118:
			y = try checked(n() + (relative ? y : 0))
			try add(.line(x, y))
		case 99, 115:
			let a: (Double, Double)
			if lower == 99 {
				a = try point()
			} else if let c = cubicControl {
				a = try (checked(2 * x - c.0), checked(2 * y - c.1))
			} else {
				a = (x, y)
			}

			let b = try point(), p = try point()
			try add(.cubic(a.0, a.1, b.0, b.1, p.0, p.1))
			nextCubic = b
			x = p.0; y = p.1
		case 113, 116:
			let a: (Double, Double)
			if lower == 113 {
				a = try point()
			} else if let c = quadraticControl {
				a = try (checked(2 * x - c.0), checked(2 * y - c.1))
			} else {
				a = (x, y)
			}

			let p = try point()
			try add(.quadratic(a.0, a.1, p.0, p.1))
			nextQuadratic = a
			x = p.0; y = p.1
		case 97:
			let rx = try n(), ry = try n(), degrees = try n()
			let large = try scanner.flag(), sweep = try scanner.flag()
			let p = try point()
			guard rx >= 0 && ry >= 0 else {
				throw SymbolCompileError("invalidValue", "Negative SVG arc radius")
			}

			if p.0 != x || p.1 != y {
				if rx == 0 || ry == 0 {
					try add(.line(p.0, p.1))
				} else {
					try add(
						normalizedArc(
							x: x,
							y: y,
							endX: p.0,
							endY: p.1,
							rx: rx,
							ry: ry,
							degrees: degrees,
							large: large,
							sweep: sweep
						)
					)
				}
			}

			x = p.0; y = p.1
		default: break
		}

		cubicControl = nextCubic
		quadraticControl = nextQuadratic
		scanner.spaces()
	}

	return commands
}

private func normalizedArc(
	x: Double,
	y: Double,
	endX: Double,
	endY: Double,
	rx: Double,
	ry: Double,
	degrees: Double,
	large: Bool,
	sweep: Bool
) throws -> CompiledCommand {
	let phi = degrees.truncatingRemainder(dividingBy: 360) * .pi / 180
	let c = cos(phi), s = sin(phi)
	let dx = (x - endX) / 2, dy = (y - endY) / 2
	let px = c * dx + s * dy, py = -s * dx + c * dy
	var radiusX = rx, radiusY = ry
	let correction = hypot(px / rx, py / ry)
	if correction > 1 {
		radiusX *= correction
		radiusY *= correction
	}

	_ = try checked(radiusX); _ = try checked(radiusY)
	let ux = px / radiusX, uy = py / radiusY
	let norm = ux * ux + uy * uy
	let coefficient = (large == sweep ? -1.0 : 1.0) * sqrt(max(0, (1 - norm) / norm))
	let cx = coefficient * radiusX * uy, cy = -coefficient * radiusY * ux
	let centerX = try checked(c * cx - s * cy + (x + endX) / 2)
	let centerY = try checked(s * cx + c * cy + (y + endY) / 2)
	let a = (px - cx) / radiusX, b = (py - cy) / radiusY
	let d = (-px - cx) / radiusX, e = (-py - cy) / radiusY
	let start = atan2(b, a)
	var delta = atan2(a * e - b * d, a * d + b * e)
	if sweep && delta < 0 {
		delta += 2 * .pi
	}

	if !sweep && delta > 0 {
		delta -= 2 * .pi
	}

	return .arc(centerX, centerY, radiusX, radiusY, phi, start, delta)
}
