import Foundation
import StanaPrimitives

package struct TextMeasurement: Sendable {
	package let size: STNSize
	package let baseline: Double

	package init(size: STNSize, baseline: Double) {
		self.size = size
		self.baseline = baseline
	}
}

@MainActor package protocol TextService {
	func measure(_ text: String, font: STNFont, maxWidth: Double, wraps: Bool) -> TextMeasurement

	func offset(in text: String, utf16Index: Int, font: STNFont) -> Double

	func index(in text: String, x: Double, font: STNFont) -> Int

	func selectionRects(in text: String, range: NSRange, font: STNFont) -> [STNRect]

	func wordRange(in text: String, at index: Int) -> NSRange

	func offsets(in text: String, font: STNFont) -> [Double]
}

extension TextService {
	/// Choose a neighboring grapheme caret in visual, rather than logical, order.
	package func visualIndex(
		in text: String,
		from index: Int,
		direction: Int,
		font: STNFont,
		boundaryText: String? = nil
	) -> Int {
		let positions = offsets(in: text, font: font)
		let origin = positions[min(max(0, index), positions.count - 1)]
		var best = index
		var distance = Double.infinity
		let source = boundaryText ?? text
		let boundaries =
			source.indices.map { source.utf16.distance(from: source.utf16.startIndex, to: $0) } + [text.utf16.count]
		for candidate in boundaries {
			let delta = (positions[candidate] - origin) * Double(direction)
			if delta > 0.001 && delta < distance {
				distance = delta
				best = candidate
			}
		}

		return best
	}

	package func wordRange(in text: String, at index: Int) -> NSRange {
		TextBoundaries.wordRange(text, index)
	}

	package func selectionRects(in text: String, range: NSRange, font: STNFont) -> [STNRect] {
		guard range.length > 0 else {
			return []
		}

		let a = offset(in: text, utf16Index: range.location, font: font)
		let b = offset(in: text, utf16Index: NSMaxRange(range), font: font)
		return [.init(x: min(a, b), width: abs(b - a), height: font.size * 1.3)]
	}

	package func offsets(in text: String, font: STNFont) -> [Double] {
		(0...text.utf16.count).map { offset(in: text, utf16Index: $0, font: font) }
	}
}

/// A deterministic test double, never installed by a native application host.
@MainActor package final class TestTextService: TextService {
	package init() {}

	package func measure(_ text: String, font: STNFont, maxWidth: Double, wraps: Bool) -> TextMeasurement {
		let intrinsic = Double(text.count) * font.size * 0.6
		let width = wraps && maxWidth.isFinite ? min(intrinsic, maxWidth) : intrinsic
		let lines = wraps && width > 0 ? max(1, ceil(intrinsic / width)) : 1
		return .init(size: .init(width: width, height: font.size * 1.3 * lines), baseline: font.size)
	}

	package func offset(in text: String, utf16Index: Int, font: STNFont) -> Double {
		Double(utf16Index) * font.size * 0.6
	}

	package func index(in text: String, x: Double, font: STNFont) -> Int {
		min(text.utf16.count, max(0, Int((x / (font.size * 0.6)).rounded())))
	}
}
