import Foundation

package enum TextBoundaries {
	package static func ceiling(_ offset: Int, in text: String) -> Int {
		for index in text.indices {
			let boundary = text.utf16.distance(from: text.utf16.startIndex, to: index)
			if boundary >= offset {
				return boundary
			}
		}

		return text.utf16.count
	}

	/// Clamp platform hit-test results to a complete extended grapheme cluster.
	package static func snap(_ offset: Int, in text: String) -> Int {
		let bounded = min(max(0, offset), text.utf16.count)
		var previous = 0
		for index in text.indices {
			let next = text.utf16.distance(from: text.utf16.startIndex, to: index)
			if next >= bounded {
				return bounded - previous < next - bounded ? previous : next
			}

			previous = next
		}

		return bounded - previous < text.utf16.count - bounded ? previous : text.utf16.count
	}

	package static func wordRange(_ text: String, _ offset: Int) -> NSRange {
		guard !text.isEmpty else {
			return NSRange(location: 0, length: 0)
		}

		let location = min(max(0, offset), text.utf16.count - 1)
		var result: NSRange?
		text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, range, _, stop in
			let candidate = NSRange(range, in: text)
			if NSLocationInRange(location, candidate) {
				result = candidate
				stop = true
			}
		}
		return result ?? (text as NSString).rangeOfComposedCharacterSequence(at: location)
	}
}
