import Foundation
import ImageIO
import Testing
@testable import CalculatorApp

@Suite struct ImageTests {
	@Test func exportedPNGDecodesWithThePlatformImageReader() throws {
		let png = PNGImage.encode(width: 2, height: 1, rgba: [255, 0, 0, 255, 0, 255, 0, 128])
		let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
		let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
		#expect(image.width == 2)
		#expect(image.height == 1)
	}
}
