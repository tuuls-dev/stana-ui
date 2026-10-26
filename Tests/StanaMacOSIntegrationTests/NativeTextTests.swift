import Testing

@testable import StanaPlatformMacOS

@Suite @MainActor struct NativeTextTests {
    @Test func explicitUTF8LengthsPreserveEmbeddedZeroAndMultibyteText() {
        let value = "A\0Bé👩🏽‍💻"
        value.withNativeUTF8 { #expect($0.string == value) }
        let text = CoreTextService()
        let prefix = text.measure("A", font: .system(size: 16), maxWidth: .infinity, wraps: false)
        let full = text.measure(value, font: .system(size: 16), maxWidth: .infinity, wraps: false)
        #expect(full.size.width > prefix.size.width)
        #expect(text.offsets(in: value, font: .system(size: 16)).count == value.utf16.count + 1)
    }
    @Test func nativeTextShapesWithoutWindowServerInitialization() {
        let text = CoreTextService()
        let result = text.measure("Hello مرحبا 👩🏽‍💻", font: .system(size: 16), maxWidth: 200, wraps: true)
        #expect(result.size.width > 0)
        #expect(result.size.width <= 200)
        #expect(result.baseline > 0)
    }
}
