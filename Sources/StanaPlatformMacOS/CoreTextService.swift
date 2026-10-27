import CStanaMacOS
import StanaPrimitives
import StanaText

@MainActor package final class CoreTextService: TextService {
	package init() {}

	package func measure(_ text: String, font: STNFont, maxWidth: Double, wraps: Bool) -> TextMeasurement {
		let m = text.withNativeUTF8 { stn_text_measure($0, font.size, font.weight.rawValue, maxWidth, wraps) }
		return .init(size: .init(width: m.width, height: m.height), baseline: m.baseline)
	}

	package func offset(in text: String, utf16Index: Int, font: STNFont) -> Double {
		text.withNativeUTF8 { stn_text_offset($0, font.size, font.weight.rawValue, UInt64(max(0, utf16Index))) }
	}

	package func index(in text: String, x: Double, font: STNFont) -> Int {
		text.withNativeUTF8 { Int(stn_text_index($0, font.size, font.weight.rawValue, x)) }
	}

	package func offsets(in text: String, font: STNFont) -> [Double] {
		var values = [Double](repeating: 0, count: text.utf16.count + 1)
		text.withNativeUTF8 { native in
			values.withUnsafeMutableBufferPointer {
				stn_text_offsets(native, font.size, font.weight.rawValue, $0.baseAddress, $0.count)
			}
		}
		return values
	}
}
