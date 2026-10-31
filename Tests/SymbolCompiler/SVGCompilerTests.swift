import Foundation
import Testing

@testable import StanaSymbolCompiler
@Suite struct SVGCompilerTests {
	private func compile(_ content: String, attributes: String = "") throws -> CompiledSymbol {
		try SVGCompiler.compile("<svg viewBox='-12 -12 24 24' \(attributes)>\(content)</svg>")
	}

	private func rejects(_ source: String, id: String) {
		do {
			_ = try SVGCompiler.compile(source)
			Issue.record("Expected \(id)")
		} catch let error as SymbolCompileError {
			#expect(error.id == id)
			#expect(error.line >= 1 && error.column >= 1)
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}

	@Test func normalizedGeometryAndIgnoredMetadataAreDeterministic() throws {
		let a = try compile("<path d='M0 0h4v5z'/>", attributes: "fill='none' stroke='currentColor'")
		let b = try compile(
			"<!--ignored--><title>Ignored &amp; title</title><path id='one' aria-label='Not a name' data-test='yes' d='M-0 0L4 0L4 5Z'/>",
			attributes: "fill='none' stroke='currentColor'"
		)
		#expect(a == b)
		#expect(a.swift(mirrorsInRTL: false).contains(".line(x: 4.0, y: 5.0)"))
		#expect(!a.swift(mirrorsInRTL: false).contains("svg:"))
		#expect(!a.swift(mirrorsInRTL: false).contains("-0.0"))
	}

	@Test(arguments: [
		"M1 2L3 4H5V6C7 8 9 10 11 12S13 14 15 16Q17 18 19 20T21 22A3 4 30 0 1 23 24Z",
		"m1 2 3 4h5v6c7 8 9 10 11 12s13 14 15 16q17 18 19 20t21 22a3 4 30 011 2z",
		"M.5-.5L1e1,+2E-1 3.2.4Z", "M0 0A0 1 0 0 1 2 3", "M0 0A1 1 0 1 0 0 0",
	])
	func acceptsEveryPathCommand(_ d: String) throws {
		#expect(!(try compile("<path d='\(d)'/>")).elements.isEmpty)
	}

	@Test func reflectionAndArcNormalization() throws {
		let commands = try svgPath("M1 2c1 2 3 4 5 6s1 2 3 4q1 2 3 4t5 6")
		#expect(
			commands == [
				.move(1, 2), .cubic(2, 4, 4, 6, 6, 8), .cubic(8, 10, 7, 10, 9, 12), .quadratic(10, 14, 12, 16),
				.quadratic(14, 18, 17, 22),
			]
		)
		let arc = try svgPath("M0 0A1 1 0 0 1 10 0")
		guard case .arc(let x, let y, let rx, let ry, _, _, let sweep) = arc[1] else {
			Issue.record("Expected normalized arc"); return
		}
		#expect(abs(x - 5) < 1e-10 && y == 0 && rx == 5 && ry == 5)
		#expect(abs(sweep - .pi) < 1e-10)
		#expect(try svgPath("M0 0A0 1 0 0 1 2 3A1 1 0 1 0 2 3") == [.move(0, 0), .line(2, 3)])
	}

	@Test(arguments: [
		"<rect x='-4px' y='2' width='10' height='8' rx='9'/>",
		"<rect width='10' height='8' ry='2'/>", "<circle cx='2' cy='3' r='4'/>",
		"<ellipse rx='2' ry='4'/>", "<line x2='4' y2='5'/>",
		"<polyline points='0,0 1,2 3,4'/>", "<polygon points='0 0 4 0 2 3'/>",
		"<g opacity='.5' transform='translate(1 2) scale(2 3) rotate(20 1 2) skewX(2) skewY(3) matrix(1 0 0 1 2 3)'><path fill='inherit' d='M0 0L2 3'/></g>",
	])
	func acceptsShapesAndTransforms(_ shape: String) throws {
		#expect(!(try compile(shape)).elements.isEmpty)
	}

	@Test func geometricDefaultsAndZeroArea() throws {
		for name in ["rect", "circle", "ellipse"] {
			guard case .path(let commands, _, _, _) = try compile("<\(name)/>").elements[0] else {
				Issue.record("Expected path"); return
			}
			#expect(commands.isEmpty)
		}
	}

	@Test(arguments: [
		"#abc", "#abcd", "#aabbcc", "#aabbccdd", "rgb(1, 2,255)", "rgba(0, 128,255,.5)", "BLACK", "white", "red",
		"green", "blue", "transparent", "none", "currentColor",
	])
	func acceptsPaintGrammar(_ paint: String) throws {
		_ = try compile("<path d='M0 0L1 1' fill='\(paint)' stroke='\(paint)'/>")
	}

	@Test(arguments: [
		"<s:svg xmlns:s='' viewBox='0 0 1 1'/>", "<:svg viewBox='0 0 1 1'/>",
		"<svg xmlns:xml='foreign' viewBox='0 0 1 1'/>", "<svg xmlns:xmlns='foreign' viewBox='0 0 1 1'/>",
		"<svg xmlns:1='foreign' viewBox='0 0 1 1'/>", "<svg xmlns:a:b='foreign' viewBox='0 0 1 1'/>",
		"<svg xmlns='http://www.w3.org/XML/1998/namespace' viewBox='0 0 1 1'/>",
		"<svg xmlns:p='http://www.w3.org/2000/xmlns/' viewBox='0 0 1 1'/>",
	])
	func namespaceConstraintsAreNotDelegatedToFoundation(_ source: String) {
		rejects(source, id: "invalidXML")
	}

	@Test func unicodeNamespacePrefixesRemainSupported() throws {
		_ = try SVGCompiler.compile("<图:svg xmlns:图='http://www.w3.org/2000/svg' viewBox='0 0 1 1'/>")
		_ = try SVGCompiler.compile(
			"<s:svg xmlns:s='http://www.w3.org/2000/sv&#103;' viewBox='0 0 1 1' data-example=\"xmlns:xml='foreign'\"/>"
		)
	}

	@Test func namespacesAndXMLReferences() throws {
		let a = try SVGCompiler.compile(
			"<?xml version='1.0'?><s:svg xmlns:s='http://www.w3.org/2000/svg' viewBox='0 0 2 2'><s:title>&#65; &#x41; &lt; &amp; &quot; &apos;</s:title><s:path d='M0 0L1 1'/></s:svg>"
		)
		let b = try SVGCompiler.compile("<svg viewBox='0 0 2 2'><path d='M0 0L1 1'/></svg>")
		#expect(a == b)
	}

	@Test(arguments: [
		"<defs/>", "<use href='#a'/>", "<image/>", "<text>abc</text>", "<foreignObject/>", "<svg viewBox='0 0 1 1'/>",
		"<path style='fill:red'/>", "<path class='x'/>", "<path color='red'/>", "<path stroke-dasharray='1 2'/>",
		"<path onclick='x'/>", "<path fill='url(#a)'/>", "<path fill='orange'/>", "<path fill='hsl(0,0,0)'/>",
		"<path stroke-width='1em'/>", "<path stroke-width='10%'/>", "<title><g/></title>",
		"<g xmlns='http://www.w3.org/2000/svg'/>", "<x:g xmlns:x='foreign'/>",
	])
	func rejectsUnsupportedContent(_ content: String) {
		rejects("<svg viewBox='0 0 24 24'>\(content)</svg>", id: "unsupportedFeature")
	}

	@Test(arguments: [
		"<!DOCTYPE svg [<!ENTITY x 'bad'>]><svg viewBox='0 0 1 1'/>",
		"<!DOCTYPE svg SYSTEM 'file:///tmp/never-read'><svg viewBox='0 0 1 1'/>",
		"<svg viewBox='0 0 1 1'><title>&unknown;</title></svg>",
		"<?other test?><svg viewBox='0 0 1 1'/>",
		"<svg viewBox='0 0 1 1'><?xml version='1.0'?></svg>",
	])
	func rejectsUnsafeXML(_ source: String) {
		rejects(source, id: "unsupportedFeature")
	}

	@Test(arguments: [
		"<rect width='-1'/>", "<circle r='-1'/>", "<path opacity='1.01'/>", "<path fill-opacity='-1'/>",
		"<path stroke-miterlimit='.5'/>", "<path fill='rgb(256,0,0)'/>", "<path fill='rgba(0,0,0,2)'/>",
		"<path fill='rgb(1.0,0,0)'/>", "<path d='L0 0'/>", "<path d='M0 0A1 1 0 2 0 1 1'/>",
		"<path d='M0 0A-1 1 0 0 0 1 1'/>", "<path d='M,0 0'/>", "<path d='M0 0L'/>",
		"<path d='M0 0Z1 1'/>", "<path d='M0 0,'/>", "<path d='M1e 0'/>",
		"<path id='same'/><path id='same'/>", "<path id=''/>", "<g transform='rotate(1 2)'/>",
	])
	func rejectsInvalidValues(_ content: String) {
		rejects("<svg viewBox='0 0 24 24'>\(content)</svg>", id: "invalidValue")
	}

	@Test func rejectsMalformedXMLAndInvalidRoots() {
		rejects("<svg viewBox='0 0 1 1'><path></svg>", id: "invalidXML")
		rejects("<g/>", id: "invalidXML")
		rejects("<svg/>", id: "invalidValue")
		rejects("<svg viewBox='0 0 0 1'/>", id: "invalidValue")
		rejects("<svg viewBox='0 0 1 1' preserveAspectRatio='none'/>", id: "unsupportedFeature")
	}

	@Test func byteElementAndDepthBudgets() throws {
		let prefix = "<svg viewBox='0 0 1 1'><!--", suffix = "--></svg>"
		let maximum = prefix + String(repeating: "x", count: 1_048_576 - prefix.utf8.count - suffix.utf8.count) + suffix
		_ = try SVGCompiler.compile(maximum)
		rejects(maximum + " ", id: "budgetExceeded")
		_ = try compile(String(repeating: "<g/>", count: 4095))
		rejects("<svg viewBox='0 0 1 1'>" + String(repeating: "<g/>", count: 4096) + "</svg>", id: "budgetExceeded")
		_ = try compile(String(repeating: "<g>", count: 63) + String(repeating: "</g>", count: 63))
		rejects(
			"<svg viewBox='0 0 1 1'>" + String(repeating: "<g>", count: 64) + String(repeating: "</g>", count: 64)
				+ "</svg>",
			id: "budgetExceeded"
		)
	}

	@Test func commandTransformAndNumericBudgets() throws {
		_ = try compile("<path d='M0 0" + String(repeating: "L0 0", count: 65535) + "'/>")
		rejects(
			"<svg viewBox='0 0 1 1'><path d='M0 0" + String(repeating: "L0 0", count: 65536) + "'/></svg>",
			id: "budgetExceeded"
		)
		_ = try compile("<g transform='" + String(repeating: "translate(0) ", count: 64) + "'/>")
		rejects(
			"<svg viewBox='0 0 1 1'><g transform='" + String(repeating: "translate(0) ", count: 65) + "'/></svg>",
			id: "budgetExceeded"
		)
		_ = try compile("<path d='M1e9 -1e9'/>")
		rejects("<svg viewBox='0 0 1 1'><path transform='scale(2)' d='M1e9 0'/></svg>", id: "budgetExceeded")
		rejects("<svg viewBox='0 0 1 1'><path d='M1000000001 0'/></svg>", id: "budgetExceeded")
		rejects("<svg viewBox='0 0 1 1'><path d='M1e9 0l1 0'/></svg>", id: "budgetExceeded")
		rejects(
			"<svg viewBox='0 0 1 1'><g transform='scale(1e9)'><g transform='scale(2)'/></g></svg>",
			id: "budgetExceeded"
		)
		rejects("<svg viewBox='0 0 1 1'><path opacity='1e999'/></svg>", id: "invalidValue")
	}
}
