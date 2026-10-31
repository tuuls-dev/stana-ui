import AppKit
import Testing
import StanaCore
import StanaLayout
import StanaPrimitives

@testable import StanaPlatformMacOS

@Suite @MainActor struct NativeTextTests {
	@Test func nativeStringsPreserveEmbeddedZeroAndMultibyteText() {
		let value = "A\0Bé👩🏽‍💻"
		#expect(NativeText.attributed(value, font: .system()).string == value)
		let text = CoreTextService()
		let prefix = text.measure("A", font: .system(size: 16), maxWidth: .infinity, wraps: false)
		let full = text.measure(value, font: .system(size: 16), maxWidth: .infinity, wraps: false)
		#expect(full.size.width > prefix.size.width)
		#expect(text.offsets(in: value, font: .system(size: 16)).count == value.utf16.count + 1)
	}

	@Test func mixedFontBaselineRowUsesFinalCoreTextMeasurements() {
		let d = Document(size: .init(width: 300, height: 200))
		defer { d.close() }
		let engine = LayoutEngine(document: d, text: CoreTextService())
		let row = d.create(.hStack, parent: d.root)
		row.style.alignment = .firstBaseline
		let small = d.create(.text, parent: row)
		small.text = "Small"
		small.style.font = .system(size: 10)
		small.style.padding = .init(bottom: 20)
		let large = d.create(.text, parent: row)
		large.text = "Large"
		large.style.font = .system(size: 30)
		large.style.flex = 1
		engine.layout()
		let cold = [row.bounds, small.bounds, large.bounds]
		#expect(abs(small.bounds.minY + small.baseline! - large.bounds.minY - large.baseline!) < 0.000_001)
		#expect(row.baseline == max(small.baseline!, large.baseline!))
		#expect(small.bounds.maxY <= row.bounds.maxY + 0.000_001)
		#expect(large.bounds.maxY <= row.bounds.maxY + 0.000_001)
		engine.useCache = false
		d.dirty.insert(.layout)
		engine.layout()
		#expect([row.bounds, small.bounds, large.bounds] == cold)
	}

	@Test func nativeTextShapesWithoutWindowServerInitialization() {
		let text = CoreTextService()
		let result = text.measure("Hello مرحبا 👩🏽‍💻", font: .system(size: 16), maxWidth: 200, wraps: true)
		#expect(result.size.width > 0)
		#expect(result.size.width <= 200)
		#expect(result.baseline > 0)
	}
}

@Suite @MainActor struct NativeEditingGeometryTests {
	@Test func visualArrowsFollowRightToLeftGeometry() {
		let service = CoreTextService()
		let text = "مرحبا"
		let neighbor = service.visualIndex(in: text, from: 0, direction: -1, font: .system())
		#expect(neighbor > 0)
		#expect(service.visualIndex(in: text, from: neighbor, direction: 1, font: .system()) == 0)
	}

	@Test func mixedDirectionSelectionSplitsIntoShapedRuns() {
		let service = CoreTextService()
		let rects = service.selectionRects(
			in: "hello مرحبا world",
			range: .init(location: 3, length: 7),
			font: .system(size: 16)
		)
		#expect(rects.count >= 2)
		#expect(rects.allSatisfy { $0.size.width > 0 && $0.minX >= 0 })
	}

	@Test func selectionGeometryUsesTheSameScaledFontAsMeasurement() {
		let service = CoreTextService()
		let small = service.selectionRects(in: "field", range: .init(location: 0, length: 5), font: .system(size: 13))
		let large = service.selectionRects(in: "field", range: .init(location: 0, length: 5), font: .system(size: 26))
		#expect(large[0].size.width > small[0].size.width * 1.8)
		#expect(service.selectionRects(in: "field", range: .init(location: 2, length: 0), font: .system()).isEmpty)
	}
}

@Test func nativeTextDoesNotInitializeApplicationInFreshProcess() async {
	await #expect(processExitsWith: .success) {
		await MainActor.run {
			precondition(NSApp == nil)
			let measurement = CoreTextService().measure("Headless مرحبا 👩🏽‍💻", font: .system(), maxWidth: 240, wraps: true)
			precondition(measurement.size.width > 0 && NSApp == nil)
		}
	}
}
