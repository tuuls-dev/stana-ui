import Foundation

package func svgPaint(_ value: String) throws -> CompiledPaint {
	if value == "none" {
		return .none
	}

	if value == "currentColor" {
		return .currentColor
	}

	let lower = value.lowercased()
	switch lower {
	case "black": return .rgba(0, 0, 0, 1)
	case "white": return .rgba(1, 1, 1, 1)
	case "red": return .rgba(1, 0, 0, 1)
	case "green": return .rgba(0, 128.0 / 255, 0, 1)
	case "blue": return .rgba(0, 0, 1, 1)
	case "transparent": return .rgba(0, 0, 0, 0)
	default: break
	}

	if lower.hasPrefix("#") {
		let hex = Array(lower.dropFirst())
		guard [3, 4, 6, 8].contains(hex.count),
			hex.allSatisfy({
				$0.isHexDigit && $0.isASCII
			})
		else {
			throw SymbolCompileError("invalidValue", "Invalid hexadecimal SVG color")
		}

		let short = hex.count < 5
		var values: [Double] = []
		for i in stride(from: 0, to: hex.count, by: short ? 1 : 2) {
			let pair = short ? String(repeating: String(hex[i]), count: 2) : String(hex[i...i + 1])
			values.append(Double(UInt8(pair, radix: 16)!) / 255)
		}

		return .rgba(values[0], values[1], values[2], values.count == 4 ? values[3] : 1)
	}

	let alpha = lower.hasPrefix("rgba(")
	if alpha || lower.hasPrefix("rgb(") {
		guard lower.hasSuffix(")") else {
			throw SymbolCompileError("invalidValue", "Unclosed SVG color function")
		}

		let parts = lower.dropFirst(alpha ? 5 : 4).dropLast().split(separator: ",", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

		guard parts.count == (alpha ? 4 : 3) else {
			throw SymbolCompileError("invalidValue", "SVG colors require comma-separated channels")
		}

		var values: [Double] = []
		for part in parts.prefix(3) {
			guard !part.isEmpty,
				part.utf8.allSatisfy({
					(48...57).contains($0)
				}), let integer = Int(part),
				(0...255).contains(integer)
			else {
				throw SymbolCompileError("invalidValue", "SVG RGB channels must be integers in 0...255")
			}

			values.append(Double(integer) / 255)
		}

		let a = alpha ? try svgScalar(parts[3]) : 1
		guard (0...1).contains(a) else {
			throw SymbolCompileError("invalidValue", "SVG color alpha must be in 0...1")
		}

		return .rgba(values[0], values[1], values[2], a)
	}

	throw SymbolCompileError(
		"unsupportedFeature",
		"Unsupported SVG paint (use currentColor, none, or a supported literal color)"
	)
}

package func svgScalar(_ value: String) throws -> Double {
	var scanner = SVGNumbers(value)
	let result = try scanner.number(separated: false)
	scanner.spaces()
	guard scanner.index == scanner.bytes.count else {
		throw SymbolCompileError("invalidValue", "Expected a unitless SVG number")
	}

	return result
}

package func svgStyle(_ attributes: [String: String], inheriting parent: CompiledStyle) throws -> CompiledStyle {
	var result = parent
	for (key, raw) in attributes.sorted(by: {
		$0.key < $1.key
	}) {
		let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		if value == "inherit" {
			continue
		}

		switch key {
		case "fill": result.fill = try svgPaint(value)
		case "stroke": result.stroke = try svgPaint(value)
		case "fill-rule":
			guard ["nonzero", "evenodd"].contains(value) else {
				throw SymbolCompileError("invalidValue", "Invalid fill-rule")
			}

			result.fillRule = value
		case "stroke-linecap":
			guard ["butt", "round", "square"].contains(value) else {
				throw SymbolCompileError("invalidValue", "Invalid stroke-linecap")
			}

			result.lineCap = value
		case "stroke-linejoin":
			guard ["miter", "round", "bevel"].contains(value) else {
				throw SymbolCompileError("invalidValue", "Invalid stroke-linejoin")
			}

			result.lineJoin = value
		case "fill-opacity", "stroke-opacity":
			let alpha = try svgScalar(value)
			guard (0...1).contains(alpha) else {
				throw SymbolCompileError("invalidValue", "\(key) must be in 0...1")
			}

			if key == "fill-opacity" {
				result.fillOpacity = alpha
			} else {
				result.strokeOpacity = alpha
			}
		case "stroke-width":
			result.strokeWidth = try svgLength(value)
			guard result.strokeWidth >= 0 else {
				throw SymbolCompileError("invalidValue", "Negative stroke-width")
			}
		case "stroke-miterlimit":
			result.miterLimit = try svgScalar(value)
			guard result.miterLimit >= 1 else {
				throw SymbolCompileError("invalidValue", "stroke-miterlimit must be at least 1")
			}
		default: break
		}
	}

	return result
}
