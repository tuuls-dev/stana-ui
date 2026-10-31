import Foundation

/// XML 1.0 NCName: https://www.w3.org/TR/xml/#NT-NameStartChar
/// XMLParser does not enforce namespace constraints, even with namespace processing enabled.
package func svgNCName(_ name: String) -> Bool {
	func start(_ value: UInt32) -> Bool {
		let ranges: [ClosedRange<UInt32>] = [
			0x41...0x5A, 0x61...0x7A, 0xC0...0xD6, 0xD8...0xF6, 0xF8...0x2FF,
			0x370...0x37D, 0x37F...0x1FFF, 0x200C...0x200D, 0x2070...0x218F,
			0x2C00...0x2FEF, 0x3001...0xD7FF, 0xF900...0xFDCF, 0xFDF0...0xFFFD, 0x10000...0xEFFFF,
		]
		return value == 0x5F || ranges.contains { $0.contains(value) }
	}

	guard let first = name.unicodeScalars.first, start(first.value) else {
		return false
	}

	return name.unicodeScalars.dropFirst()
		.allSatisfy {
			let value = $0.value
			return start(value) || value == 0x2D || value == 0x2E || value == 0xB7
				|| (0x30...0x39).contains(value) || (0x300...0x36F).contains(value) || (0x203F...0x2040).contains(value)
		}
}

/// Enforce reserved bindings and no prefix undeclaration: https://www.w3.org/TR/xml-names/#ns-decl
package func svgNamespaces(_ attributes: [String: String], parent: [String: String]?) throws -> [String: String] {
	let xml = "http://www.w3.org/XML/1998/namespace"
	let xmlns = "http://www.w3.org/2000/xmlns/"
	var namespaces = parent ?? ["xml": xml]
	for (name, value) in attributes.sorted(by: { $0.key < $1.key }) {
		guard name == "xmlns" || name.hasPrefix("xmlns:") else {
			continue
		}

		let prefix = name == "xmlns" ? "" : String(name.dropFirst(6))
		guard name == "xmlns" || (svgNCName(prefix) && !value.isEmpty), prefix != "xmlns",
			(prefix == "xml") == (value == xml), value != xmlns
		else {
			throw SymbolCompileError("invalidXML", "Invalid XML namespace declaration or reserved namespace binding")
		}

		namespaces[prefix] = value
	}

	return namespaces
}

package func svgDiagnosticName(_ value: String) -> String {
	let prefix = String(decoding: value.utf8.prefix(80), as: UTF8.self)
	return value.utf8.count > 80 ? prefix + "…" : prefix
}

/// Preserve and validate raw declarations: Foundation silently drops some invalid reserved bindings.
package func svgValidateRawNamespaces(_ tag: ArraySlice<UInt8>) throws {
	let bytes = Array(tag)
	var index = 0
	func space(_ byte: UInt8) -> Bool {
		[9, 10, 13, 32].contains(byte)
	}

	func skipSpaces() {
		while index < bytes.count && space(bytes[index]) {
			index += 1
		}
	}
	while index < bytes.count && !space(bytes[index]) && bytes[index] != 47 {
		index += 1
	}
	var attributes: [String: String] = [:]
	var names: Set<String> = []
	while index < bytes.count {
		skipSpaces()
		if index == bytes.count || bytes[index] == 47 {
			break
		}
		let start = index
		while index < bytes.count && !space(bytes[index]) && bytes[index] != 61 {
			index += 1
		}
		let name = String(decoding: bytes[start..<index], as: UTF8.self)
		skipSpaces()
		guard !name.isEmpty, names.insert(name).inserted, index < bytes.count && bytes[index] == 61 else {
			throw SymbolCompileError("invalidXML", "Malformed or duplicate XML attribute")
		}
		index += 1
		skipSpaces()
		guard index < bytes.count && (bytes[index] == 34 || bytes[index] == 39) else {
			throw SymbolCompileError("invalidXML", "XML attribute requires a quoted value")
		}
		let quote = bytes[index]
		index += 1
		let valueStart = index
		while index < bytes.count && bytes[index] != quote {
			index += 1
		}
		guard index < bytes.count else {
			throw SymbolCompileError("invalidXML", "Unclosed XML attribute value")
		}
		if name == "xmlns" || name.hasPrefix("xmlns:") {
			attributes[name] = try svgNamespaceValue(bytes[valueStart..<index])
		}
		index += 1
		guard index == bytes.count || space(bytes[index]) || bytes[index] == 47 else {
			throw SymbolCompileError("invalidXML", "XML attributes must be separated by whitespace")
		}
	}
	_ = try svgNamespaces(attributes, parent: nil)
}

private func svgNamespaceValue(_ bytes: ArraySlice<UInt8>) throws -> String {
	let source = String(decoding: bytes, as: UTF8.self)
		.replacingOccurrences(of: "\r\n", with: " ")
		.replacingOccurrences(of: "\r", with: " ")
		.replacingOccurrences(of: "\n", with: " ")
		.replacingOccurrences(of: "\t", with: " ")
	var result = ""
	var index = source.startIndex
	let predefined = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
	while index < source.endIndex {
		if source[index] != "&" {
			result.append(source[index])
			index = source.index(after: index)
			continue
		}
		guard let end = source[index...].firstIndex(of: ";") else {
			throw SymbolCompileError("invalidXML", "Unclosed XML namespace character reference")
		}
		let reference = String(source[source.index(after: index)..<end])
		if let value = predefined[reference] {
			result += value
		} else if reference.hasPrefix("#") {
			let hex = reference.hasPrefix("#x")
			guard let value = UInt32(reference.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
				let scalar = Unicode.Scalar(value)
			else {
				throw SymbolCompileError("invalidXML", "Invalid XML namespace numeric character reference")
			}
			result.unicodeScalars.append(scalar)
		} else {
			throw SymbolCompileError(
				"unsupportedFeature",
				"Only predefined and numeric XML character references are permitted"
			)
		}
		index = source.index(after: end)
	}
	return result
}
