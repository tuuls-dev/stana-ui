import CoreGraphics
import CoreText
import Foundation
import StanaPrimitives
import StanaText

enum NativeText {
	static func font(_ font: STNFont) -> CTFont {
		let base = CTFontCreateUIFontForLanguage(.system, font.size, nil)!
		let descriptor = CTFontDescriptorCreateWithAttributes(
			[
				kCTFontTraitsAttribute: [kCTFontWeightTrait: font.weight.rawValue]
			] as CFDictionary
		)
		return CTFontCreateCopyWithAttributes(base, font.size, nil, descriptor)
	}

	static func attributed(_ text: String, font: STNFont, color: CGColor? = nil) -> NSAttributedString {
		var attributes: [NSAttributedString.Key: Any] = [
			NSAttributedString.Key(kCTFontAttributeName as String): self.font(font)
		]
		if let color {
			attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color
		}

		return NSAttributedString(string: text, attributes: attributes)
	}

	static func line(_ text: String, font: STNFont) -> CTLine {
		CTLineCreateWithAttributedString(attributed(text, font: font))
	}

	static func selectionRects(_ text: String, range: NSRange, font: STNFont) -> [STNRect] {
		guard range.location <= text.utf16.count, range.length <= text.utf16.count - range.location,
			range.length > 0
		else {
			return []
		}

		let line = line(text, font: font)
		var result: [STNRect] = []
		for run in CTLineGetGlyphRuns(line) as! [CTRun] {
			let runRange = CTRunGetStringRange(run)
			let intersection = NSIntersectionRange(range, NSRange(location: runRange.location, length: runRange.length))
			guard intersection.length > 0 else {
				continue
			}

			let count = CTRunGetGlyphCount(run)
			var indices = [CFIndex](repeating: 0, count: count)
			var positions = [CGPoint](repeating: .zero, count: count)
			var advances = [CGSize](repeating: .zero, count: count)
			CTRunGetStringIndices(run, CFRange(), &indices)
			CTRunGetPositions(run, CFRange(), &positions)
			CTRunGetAdvances(run, CFRange(), &advances)
			let boundaries = Set(indices + [runRange.location + runRange.length]).sorted()
			var left = Double.infinity
			var right = -Double.infinity
			for index in indices.indices {
				let start = indices[index]
				let end = boundaries.first { $0 > start } ?? start
				guard NSIntersectionRange(intersection, NSRange(location: start, length: end - start)).length > 0 else {
					continue
				}

				left = min(left, positions[index].x, positions[index].x + advances[index].width)
				right = max(right, positions[index].x, positions[index].x + advances[index].width)
			}

			if left <= right {
				result.append(.init(x: left, width: max(0, right - left), height: font.size * 1.3))
			}
		}

		return result
	}
}

@MainActor package final class CoreTextService: TextService {
	package init() {}

	package func measure(_ text: String, font: STNFont, maxWidth: Double, wraps: Bool) -> TextMeasurement {
		let nativeFont = NativeText.font(font)
		let baseline = CTFontGetAscent(nativeFont)
		let minimum = ceil(baseline + CTFontGetDescent(nativeFont) + CTFontGetLeading(nativeFont))
		if wraps && maxWidth.isFinite && maxWidth > 0 {
			let setter = CTFramesetterCreateWithAttributedString(NativeText.attributed(text, font: font))
			let size = CTFramesetterSuggestFrameSizeWithConstraints(
				setter,
				CFRange(),
				nil,
				CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
				nil
			)
			return .init(
				size: .init(width: ceil(size.width), height: max(minimum, ceil(size.height))),
				baseline: baseline
			)
		}

		let width = CTLineGetTypographicBounds(NativeText.line(text, font: font), nil, nil, nil)
		return .init(size: .init(width: ceil(width), height: minimum), baseline: baseline)
	}

	package func offset(in text: String, utf16Index: Int, font: STNFont) -> Double {
		CTLineGetOffsetForStringIndex(NativeText.line(text, font: font), min(max(0, utf16Index), text.utf16.count), nil)
	}

	package func index(in text: String, x: Double, font: STNFont) -> Int {
		let line = NativeText.line(text, font: font)
		let index = CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0))
		if index != kCFNotFound {
			return max(0, index)
		}

		return (0...text.utf16.count)
			.min {
				abs(x - CTLineGetOffsetForStringIndex(line, $0, nil))
					< abs(x - CTLineGetOffsetForStringIndex(line, $1, nil))
			} ?? 0
	}

	package func selectionRects(in text: String, range: NSRange, font: STNFont) -> [STNRect] {
		NativeText.selectionRects(text, range: range, font: font)
	}

	package func offsets(in text: String, font: STNFont) -> [Double] {
		let line = NativeText.line(text, font: font)
		return (0...text.utf16.count).map { CTLineGetOffsetForStringIndex(line, $0, nil) }
	}
}
