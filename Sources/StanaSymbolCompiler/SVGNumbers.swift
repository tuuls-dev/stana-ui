import Foundation

/// An ASCII SVG number scanner. Separators and arc flags are interpreted by the grammar, not Double.
package struct SVGNumbers {
	package let bytes: [UInt8]
	package var index = 0

	package init(_ string: String) {
		bytes = Array(string.utf8)
	}

	package mutating func spaces() {
		while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) {
			index += 1
		}
	}

	package mutating func separator() throws {
		spaces()
		if index < bytes.count && bytes[index] == 44 {
			index += 1
			spaces()
			guard index < bytes.count && bytes[index] != 44 else {
				throw SymbolCompileError("invalidValue", "Invalid SVG number separator")
			}
		}
	}

	package mutating func number(separated: Bool = true) throws -> Double {
		if separated {
			try separator()
		} else {
			spaces()
		}

		let start = index
		if index < bytes.count && (bytes[index] == 43 || bytes[index] == 45) {
			index += 1
		}

		var digits = 0
		while index < bytes.count && (48...57).contains(bytes[index]) {
			index += 1
			digits += 1
		}

		if index < bytes.count && bytes[index] == 46 {
			index += 1
			while index < bytes.count && (48...57).contains(bytes[index]) {
				index += 1
				digits += 1
			}
		}

		guard digits > 0 else {
			throw SymbolCompileError("invalidValue", "Expected SVG number")
		}

		if index < bytes.count && (bytes[index] == 69 || bytes[index] == 101) {
			index += 1
			if index < bytes.count && (bytes[index] == 43 || bytes[index] == 45) {
				index += 1
			}

			let exp = index
			while index < bytes.count && (48...57).contains(bytes[index]) {
				index += 1
			}

			guard index > exp else {
				throw SymbolCompileError("invalidValue", "Invalid SVG number exponent")
			}
		}

		guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)) else {
			throw SymbolCompileError("invalidValue", "Invalid SVG number")
		}

		return try checked(value)
	}

	package mutating func flag() throws -> Bool {
		try separator()
		guard index < bytes.count && (bytes[index] == 48 || bytes[index] == 49) else {
			throw SymbolCompileError("invalidValue", "Arc flag must be 0 or 1")
		}

		let value = bytes[index] == 49
		index += 1
		return value
	}

	package mutating func list() throws -> [Double] {
		spaces()
		var result: [Double] = []
		while index < bytes.count {
			result.append(try number(separated: !result.isEmpty))
			spaces()
		}

		return result
	}
}

package func svgLength(_ string: String) throws -> Double {
	let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
	if ["em", "ex", "rem", "ch"]
		.contains(where: {
			trimmed.hasSuffix($0)
		})
	{
		throw SymbolCompileError("unsupportedFeature", "Font-relative SVG lengths are unsupported")
	}

	var scanner = SVGNumbers(string)
	let value = try scanner.number(separated: false)
	if scanner.bytes.dropFirst(scanner.index).starts(with: [112, 120]) {
		scanner.index += 2
	}

	scanner.spaces()
	guard scanner.index == scanner.bytes.count else {
		throw SymbolCompileError("unsupportedFeature", "Only unitless and px SVG lengths are supported")
	}

	return value
}

package func svgTransform(_ value: String) throws -> SymbolTransform {
	var scanner = SVGNumbers(value)
	var result = SymbolTransform()
	var count = 0
	scanner.spaces()
	while scanner.index < scanner.bytes.count {
		count += 1
		guard count <= 64 else {
			throw SymbolCompileError("budgetExceeded", "More than 64 transforms in an attribute")
		}

		let start = scanner.index
		while scanner.index < scanner.bytes.count
			&& ((65...90).contains(scanner.bytes[scanner.index]) || (97...122).contains(scanner.bytes[scanner.index]))
		{ scanner.index += 1 }

		let name = String(decoding: scanner.bytes[start..<scanner.index], as: UTF8.self)
		scanner.spaces()
		guard scanner.index < scanner.bytes.count && scanner.bytes[scanner.index] == 40 else {
			throw SymbolCompileError("invalidValue", "Invalid SVG transform function")
		}

		scanner.index += 1
		scanner.spaces()
		var args: [Double] = []
		while scanner.index < scanner.bytes.count && scanner.bytes[scanner.index] != 41 {
			args.append(try scanner.number(separated: !args.isEmpty))
			guard args.count <= 6 else {
				throw SymbolCompileError("invalidValue", "Too many SVG transform arguments")
			}

			scanner.spaces()
		}

		guard scanner.index < scanner.bytes.count else {
			throw SymbolCompileError("invalidValue", "Unclosed SVG transform")
		}

		scanner.index += 1
		let t: SymbolTransform
		switch (name, args.count) {
		case ("matrix", 6): t = .init(v: args)
		case ("translate", 1...2): t = .init(v: [1, 0, 0, 1, args[0], args.count == 2 ? args[1] : 0])
		case ("scale", 1...2): t = .init(v: [args[0], 0, 0, args.count == 2 ? args[1] : args[0], 0, 0])
		case ("rotate", 1), ("rotate", 3):
			let angle = args[0] * .pi / 180
			let rotation = SymbolTransform(v: [cos(angle), sin(angle), -sin(angle), cos(angle), 0, 0])
			if args.count == 3 {
				t = try SymbolTransform(v: [1, 0, 0, 1, args[1], args[2]])
					.concatenating(rotation).concatenating(.init(v: [1, 0, 0, 1, -args[1], -args[2]]))
			} else {
				t = rotation
			}
		case ("skewX", 1): t = try .init(v: [1, 0, checked(tan(args[0] * .pi / 180)), 1, 0, 0])
		case ("skewY", 1): t = try .init(v: [1, checked(tan(args[0] * .pi / 180)), 0, 1, 0, 0])
		default:
			throw SymbolCompileError(
				"invalidValue",
				"Unsupported transform or invalid argument count: \(svgDiagnosticName(name))"
			)
		}

		result = try result.concatenating(t)
		scanner.spaces()
		if scanner.index < scanner.bytes.count && scanner.bytes[scanner.index] == 44 {
			scanner.index += 1
			scanner.spaces()
			guard scanner.index < scanner.bytes.count else {
				throw SymbolCompileError("invalidValue", "Trailing transform separator")
			}
		}
	}

	return result
}
