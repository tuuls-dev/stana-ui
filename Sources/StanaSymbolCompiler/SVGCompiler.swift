import Foundation
#if canImport(FoundationXML)
	import FoundationXML
#endif
/// Host-only parser. Runtime products depend on typed geometry, never on this target.
package enum SVGCompiler {
	package static func compile(_ svg: String) throws -> CompiledSymbol {
		guard svg.utf8.count <= 1_048_576 else {
			throw SymbolCompileError("budgetExceeded", "Decoded SVG exceeds 1 MiB")
		}

		try preflight(svg)
		let delegate = SVGDelegate()
		let parser = XMLParser(data: Data(svg.utf8))
		parser.shouldResolveExternalEntities = false
		parser.shouldProcessNamespaces = false
		parser.delegate = delegate
		guard parser.parse(), delegate.failure == nil else {
			throw delegate.failure
				?? SymbolCompileError(
					"invalidXML",
					"Malformed SVG XML",
					line: max(1, parser.lineNumber),
					column: max(1, parser.columnNumber)
				)
		}

		guard let viewBox = delegate.viewBox else {
			throw SymbolCompileError("invalidXML", "Expected exactly one svg root with viewBox")
		}

		return CompiledSymbol(viewBox: viewBox, elements: delegate.result)
	}

	private static func preflight(_ svg: String) throws {
		let bytes = Array(svg.utf8)
		var i = bytes.starts(with: [239, 187, 191]) ? 3 : 0
		let beginning = i

		func starts(_ s: String) -> Bool {
			bytes[i...].starts(with: Array(s.utf8))
		}

		func located(_ id: String, _ message: String) -> SymbolCompileError {
			let prefix = bytes[..<min(i, bytes.count)]
			let line = 1 + prefix.filter { $0 == 10 }.count
			let column = prefix.count - (prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0) + 1
			return SymbolCompileError(id, message, line: line, column: column)
		}

		func end(_ marker: String) throws {
			let m = Array(marker.utf8)
			while i < bytes.count && !bytes[i...].starts(with: m) {
				i += 1
			}

			guard i < bytes.count else {
				throw located("invalidXML", "Unclosed XML construct")
			}

			i += m.count
		}

		func reject(_ message: String) throws -> Never {
			throw located("unsupportedFeature", message)
		}

		while i < bytes.count {
			if starts("<!--") {
				i += 4
				try end("-->")
				continue
			}

			if starts("<![CDATA[") {
				i += 9
				try end("]]>")
				continue
			}

			if starts("<!") {
				try reject("SVG DTDs and entity declarations are forbidden")
			}

			if starts("<?") {
				guard
					i == beginning && starts("<?xml") && i + 5 < bytes.count && [9, 10, 13, 32].contains(bytes[i + 5])
				else {
					try reject("Only one leading XML declaration is permitted")
				}

				i += 5; try end("?>"); continue
			}

			if bytes[i] == 60 {
				var end = i + 1
				var quote: UInt8?
				while end < bytes.count {
					let byte = bytes[end]
					if let q = quote {
						if byte == q {
							quote = nil
						}
					} else if byte == 34 || byte == 39 {
						quote = byte
					} else if byte == 62 {
						break
					}

					end += 1
				}

				guard end < bytes.count else {
					throw located("invalidXML", "Unclosed XML tag or attribute")
				}
				if i + 1 < end && bytes[i + 1] != 47 {
					do {
						try svgValidateRawNamespaces(bytes[(i + 1)..<end])
					} catch let error as SymbolCompileError {
						throw located(error.id, error.message)
					}
				}
			}

			if bytes[i] == 38 {
				let start = i + 1
				i += 1
				while i < bytes.count && bytes[i] != 59 {
					i += 1
				}

				guard i < bytes.count else {
					throw located("invalidXML", "Unclosed XML character reference")
				}

				let ref = String(decoding: bytes[start..<i], as: UTF8.self)
				guard ["amp", "lt", "gt", "quot", "apos"].contains(ref) || ref.hasPrefix("#") else {
					try reject("Only predefined and numeric XML character references are permitted")
				}
			}

			i += 1
		}
	}
}

private final class SVGDelegate: NSObject, XMLParserDelegate {
	struct Frame {
		let name: String
		let namespaces: [String: String]
		let style: CompiledStyle
		let transform: SymbolTransform
		let cumulative: SymbolTransform
		let opacity: Double
		var children: [CompiledElement] = []
		let commands: [CompiledCommand]?
	}

	var stack: [Frame] = []
	var result: [CompiledElement] = []
	var failure: SymbolCompileError?
	var viewBox: [Double]?
	var rootNamespace: String?
	var ids: Set<String> = []
	var count = 0
	var commandCount = 0
	let presentation: Set<String> = [
		"fill", "fill-rule", "fill-opacity", "stroke", "stroke-opacity", "stroke-width", "stroke-linecap",
		"stroke-linejoin", "stroke-miterlimit", "opacity", "transform",
	]
	let geometry: [String: Set<String>] = [
		"path": ["d"], "rect": ["x", "y", "width", "height", "rx", "ry"], "circle": ["cx", "cy", "r"],
		"ellipse": ["cx", "cy", "rx", "ry"], "line": ["x1", "y1", "x2", "y2"],
		"polyline": ["points"], "polygon": ["points"],
	]

	func fail(_ error: SymbolCompileError, _ parser: XMLParser) {
		if failure == nil {
			var located = error
			located.line = max(1, parser.lineNumber)
			located.column = max(1, parser.columnNumber)
			failure = located
		}

		parser.abortParsing()
	}

	func parser(
		_ parser: XMLParser,
		didStartElement qualified: String,
		namespaceURI: String?,
		qualifiedName: String?,
		attributes: [String: String]
	) {
		guard failure == nil else {
			return
		}

		do {
			count += 1
			guard count <= 4096 && stack.count < 64 else {
				throw SymbolCompileError("budgetExceeded", "SVG element count or nesting limit exceeded")
			}

			let namespaces = try svgNamespaces(attributes, parent: stack.last?.namespaces)
			let parts = qualified.split(separator: ":", omittingEmptySubsequences: false)
			guard parts.count <= 2 && parts.allSatisfy({ svgNCName(String($0)) }) else {
				throw SymbolCompileError("invalidXML", "Invalid XML qualified element name")
			}

			let name = String(parts.last!)
			let prefix = parts.count == 2 ? String(parts[0]) : ""
			guard prefix != "xmlns", prefix.isEmpty || (namespaces[prefix].map { !$0.isEmpty } ?? false) else {
				throw SymbolCompileError("invalidXML", "Unbound SVG namespace prefix")
			}

			let ns = namespaces[prefix] ?? ""
			guard ns == "" || ns == "http://www.w3.org/2000/svg" else {
				throw SymbolCompileError("unsupportedFeature", "Foreign SVG element namespace")
			}

			if stack.isEmpty {
				guard name == "svg" && viewBox == nil else {
					throw SymbolCompileError("invalidXML", "Expected exactly one svg root")
				}

				rootNamespace = ns
			} else {
				guard ns == rootNamespace else {
					throw SymbolCompileError("unsupportedFeature", "Mixed SVG element namespaces")
				}

				guard stack.last!.name == "svg" || stack.last!.name == "g" else {
					throw SymbolCompileError(
						"unsupportedFeature",
						"Child elements are not permitted inside \(stack.last!.name)"
					)
				}

				guard name != "svg" else {
					throw SymbolCompileError("unsupportedFeature", "Nested svg is unsupported")
				}
			}

			guard ["svg", "g", "title", "desc"].contains(name) || geometry[name] != nil else {
				throw SymbolCompileError("unsupportedFeature", "Unsupported SVG element: \(svgDiagnosticName(name))")
			}

			var allowed = geometry[name] ?? []
			if name != "title" && name != "desc" {
				allowed.formUnion(presentation)
			}

			if name == "svg" {
				allowed.formUnion(["viewBox", "width", "height", "preserveAspectRatio", "role"])
			}

			for (key, value) in attributes.sorted(by: {
				$0.key < $1.key
			}) {
				if key == "xmlns" || key.hasPrefix("xmlns:") {
					continue
				}

				if key == "id" {
					guard !value.isEmpty && ids.insert(value).inserted else {
						throw SymbolCompileError("invalidValue", "SVG id must be nonempty and unique")
					}

					continue
				}

				if !key.contains(":") && (key.hasPrefix("data-") || key.hasPrefix("aria-")) {
					continue
				}

				guard allowed.contains(key) else {
					throw SymbolCompileError(
						"unsupportedFeature",
						"Unsupported \(svgDiagnosticName(name)) attribute: \(svgDiagnosticName(key))"
					)
				}
			}

			if name == "svg" {
				guard let raw = attributes["viewBox"] else {
					throw SymbolCompileError("invalidValue", "svg requires viewBox")
				}

				var scanner = SVGNumbers(raw)
				let box = try scanner.list()
				guard box.count == 4 && box[2] > 0 && box[3] > 0 else {
					throw SymbolCompileError("invalidValue", "viewBox requires four numbers and positive dimensions")
				}

				viewBox = box
				for key in ["width", "height"] {
					if let raw = attributes[key], try svgLength(raw) <= 0 {
						throw SymbolCompileError("invalidValue", "Root \(svgDiagnosticName(key)) must be positive")
					}
				}

				if let aspect = attributes["preserveAspectRatio"], aspect != "xMidYMid meet" {
					throw SymbolCompileError(
						"unsupportedFeature",
						"Only xMidYMid meet preserveAspectRatio is supported"
					)
				}
			}

			let style = try svgStyle(attributes, inheriting: stack.last?.style ?? .init())
			let transform = try attributes["transform"].map(svgTransform) ?? .init()
			let cumulative = try (stack.last?.cumulative ?? .init()).concatenating(transform)
			let opacity = try attributes["opacity"].map(svgScalar) ?? 1
			guard (0...1).contains(opacity) else {
				throw SymbolCompileError("invalidValue", "opacity must be in 0...1")
			}

			let commands: [CompiledCommand]?
			if geometry[name] != nil {
				commands = try svgShape(name, attributes, limit: 65536 - commandCount)
				for command in commands! {
					func point(_ x: Double, _ y: Double) throws {
						_ = try checked(cumulative.v[0] * x + cumulative.v[2] * y + cumulative.v[4])
						_ = try checked(cumulative.v[1] * x + cumulative.v[3] * y + cumulative.v[5])
					}
					switch command {
					case .move(let x, let y), .line(let x, let y): try point(x, y)
					case .quadratic(let cx, let cy, let x, let y): try point(cx, cy); try point(x, y)
					case .cubic(let ax, let ay, let bx, let by, let x, let y):
						try point(ax, ay); try point(bx, by); try point(x, y)
					case .arc(let x, let y, let rx, let ry, let rotation, _, _):
						try point(x, y)
						_ = try checked(rx * (cumulative.v[0] * cos(rotation) + cumulative.v[2] * sin(rotation)))
						_ = try checked(rx * (cumulative.v[1] * cos(rotation) + cumulative.v[3] * sin(rotation)))
						_ = try checked(ry * (-cumulative.v[0] * sin(rotation) + cumulative.v[2] * cos(rotation)))
						_ = try checked(ry * (-cumulative.v[1] * sin(rotation) + cumulative.v[3] * cos(rotation)))
					case .close: break
					}
				}
				commandCount += commands!.count
				guard commandCount <= 65536 else {
					throw SymbolCompileError("budgetExceeded", "Normalized SVG command limit exceeded")
				}
			} else {
				commands = nil
			}

			stack.append(
				Frame(
					name: name,
					namespaces: namespaces,
					style: style,
					transform: transform,
					cumulative: cumulative,
					opacity: opacity,
					commands: commands
				)
			)
		} catch let error as SymbolCompileError {
			fail(error, parser)
		} catch {
			fail(SymbolCompileError("invalidXML", "Invalid SVG document"), parser)
		}
	}

	func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
		guard failure == nil, let frame = stack.popLast() else {
			return
		}

		let elements: [CompiledElement]
		if let path = frame.commands {
			elements = [.path(path, frame.transform, frame.style, frame.opacity)]
		} else if frame.name == "title" || frame.name == "desc" {
			elements = []
		} else if frame.name == "svg" && frame.transform == SymbolTransform() && frame.opacity == 1 {
			elements = frame.children
		} else {
			elements = [.group(frame.transform, frame.opacity, frame.children)]
		}

		if stack.isEmpty {
			result = elements
		} else {
			stack[stack.count - 1].children.append(contentsOf: elements)
		}
	}

	func parser(_ parser: XMLParser, foundCharacters string: String) {
		if stack.last?.name == "title" || stack.last?.name == "desc" {
			return
		}

		if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			fail(SymbolCompileError("unsupportedFeature", "Text is only supported inside title and desc"), parser)
		}
	}

	func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
		self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self))
	}

	func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
		fail(SymbolCompileError("unsupportedFeature", "External XML entities are forbidden"), parser)
		return nil
	}
}
