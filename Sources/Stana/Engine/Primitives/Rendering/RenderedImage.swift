import Foundation

/// A complete offscreen scene, before the display transform. HDR values are not
/// clipped to a screenshot's SDR range. Rows run top to bottom without padding.
public struct STNRenderedImage: Sendable {
	public enum Format: Sendable {
		case premultipliedBGRA8, premultipliedRGBA16Float
	}

	public let width: Int
	public let height: Int
	public let format: Format
	public let sceneRevision: UInt64
	public let data: Data

	package init(width: Int, height: Int, format: Format, sceneRevision: UInt64, data: Data) {
		self.width = width
		self.height = height
		self.format = format
		self.sceneRevision = sceneRevision
		self.data = data
	}

	/// Explicit headroom-limited sRGB export. Calling this on SDR bytes is a no-op.
	public func displayMappedBGRA(headroom: Double = 1) -> Data {
		precondition(headroom.isFinite && headroom >= 1)
		guard format == .premultipliedRGBA16Float else { return data }
		return data.withUnsafeBytes { raw in
			let pixels = raw.bindMemory(to: Float16.self)
			var output = Data(count: width * height * 4)
			output.withUnsafeMutableBytes { destination in
				let bytes = destination.bindMemory(to: UInt8.self)
				for i in 0..<(width * height) {
					let a = Double(pixels[i * 4 + 3])
					let rgb = a > 0 ? (0..<3).map { Double(pixels[i * 4 + $0]) / a } : [0, 0, 0]
					let l = max(0, rgb.max() ?? 0)
					let k = min(1, 0.75 * headroom)
					let factor = l > k ? (k + (headroom - k) * (l - k) / (l - k + headroom - k)) / l : 1
					for j in 0..<3 {
						let v = rgb[j] * factor
						let encoded = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(max(0, v), 1 / 2.4) - 0.055
						bytes[i * 4 + 2 - j] = UInt8((max(0, min(1, encoded * a)) * 255).rounded())
					}
					bytes[i * 4 + 3] = UInt8((max(0, min(1, a)) * 255).rounded())
				}
			}
			return output
		}
	}
}
