import CoreGraphics
import Foundation
import StanaPrimitives
import StanaScene
import Testing

@testable import Stana
@testable import StanaPlatformMacOS
@MakeSTNSymbol
private struct RasterColors {
	static let svg =
		"<svg viewBox='0 0 24 24'><rect width='12' height='24' fill='currentColor'/><rect x='12' width='12' height='24' fill='#ff0000'/></svg>"
}

@MakeSTNSymbol
private struct RasterGroupOpacity {
	static let svg =
		"<svg viewBox='0 0 24 24'><g opacity='.5' fill='red'><rect width='16' height='24'/><rect x='8' width='16' height='24'/></g></svg>"
}

@MakeSTNSymbol
private struct RasterTransformedStroke {
	static let svg =
		"<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='2'><g transform='scale(2 1)'><path d='M3 2V22'/></g></svg>"
}

@MakeSTNSymbol
private struct RasterCurves {
	static let svg =
		"<svg viewBox='0 0 24 24' fill='currentColor'><path fill-rule='evenodd' d='M12 0A12 12 0 1 1 12 24A12 12 0 1 1 12 0ZM12 6A6 6 0 1 1 12 18A6 6 0 1 1 12 6Z'/></svg>"
}

@Suite struct SymbolRasterTests {
	private func draw(_ asset: STNSymbolAsset, scale: Double = 1, stroke: Double? = nil, tint: STNColor = .black) throws
		-> CGContext
	{
		let side = Int(24 * scale)
		let context = try #require(
			CGContext(
				data: nil,
				width: side,
				height: side,
				bitsPerComponent: 8,
				bytesPerRow: side * 4,
				space: CGColorSpace(name: CGColorSpace.sRGB)!,
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
			)
		)
		context.translateBy(x: 0, y: Double(side))
		context.scaleBy(x: scale, y: -scale)
		let canvas = RasterCanvas()
		let presentation = SymbolPresentation(
			asset: asset.storage,
			transform: .identity,
			color: tint,
			strokeWidth: stroke,
			generation: 1
		)
		try canvas.drawSymbol(presentation, in: context)
		return context
	}

	private func pixel(_ context: CGContext, _ x: Int, _ y: Int) -> [UInt8] {
		let memory = context.data!.assumingMemoryBound(to: UInt8.self)
		let offset = y * context.bytesPerRow + x * 4
		return Array(UnsafeBufferPointer(start: memory + offset, count: 4))
	}

	@Test(arguments: [1.0, 2.0])
	func currentColorFixedColorsAndGroupOpacity(scale: Double) throws {
		let colors = try draw(RasterColors.asset, scale: scale, tint: .init(red: 0, green: 0, blue: 1))
		#expect(pixel(colors, Int(4 * scale), Int(12 * scale)) == [0, 0, 255, 255])
		#expect(pixel(colors, Int(18 * scale), Int(12 * scale)) == [255, 0, 0, 255])
		let opacity = try draw(RasterGroupOpacity.asset, scale: scale)
		let single = pixel(opacity, Int(4 * scale), Int(12 * scale)),
			overlap = pixel(opacity, Int(12 * scale), Int(12 * scale))
		#expect(single == overlap)
		#expect(abs(Int(single[3]) - 128) <= 1)
	}

	@Test func transformedStrokesRespectLocalOverrideAndZero() throws {
		let authored = try draw(RasterTransformedStroke.asset)
		#expect(pixel(authored, 4, 12)[3] > 0)
		let thin = try draw(RasterTransformedStroke.asset, stroke: 1)
		#expect(pixel(thin, 4, 12)[3] == 0)
		let zero = try draw(RasterTransformedStroke.asset, stroke: 0)
		#expect(pixel(zero, 6, 12)[3] == 0)
	}

	@Test(arguments: [1.0, 2.0])
	func arcsAndEvenOddHolesRetainVectorFidelity(scale: Double) throws {
		let image = try draw(RasterCurves.asset, scale: scale)
		#expect(pixel(image, Int(12 * scale), Int(12 * scale))[3] == 0)
		#expect(pixel(image, Int(12 * scale), Int(3 * scale))[3] == 255)
	}

	@Test func semanticCacheSharesAndEvictsWhileOwnersRemainUsable() throws {
		let cache = SymbolPathCache(entryLimit: 2, byteLimit: 16 * 1_024 * 1_024)
		let first = try cache.prepare(RasterColors.asset.storage, strokeWidth: nil, scale: 1)
		#expect(try cache.prepare(RasterColors.asset.storage, strokeWidth: nil, scale: 1) === first)
		_ = try cache.prepare(RasterGroupOpacity.asset.storage, strokeWidth: nil, scale: 1)
		_ = try cache.prepare(RasterCurves.asset.storage, strokeWidth: nil, scale: 1)
		#expect(cache.accounting.entries == 2 && cache.accounting.preparations == 3)
		#expect(!first.paths.isEmpty)
		let second = try cache.prepare(RasterColors.asset.storage, strokeWidth: nil, scale: 1)
		#expect(second !== first)
		#expect(cache.accounting.bytes <= 16 * 1_024 * 1_024)
		let tiny = SymbolPathCache(entryLimit: 256, byteLimit: 1)
		_ = try tiny.prepare(RasterColors.asset.storage, strokeWidth: nil, scale: 1)
		#expect(tiny.accounting.entries == 0)
	}

	@Test func strokeVariantsShareFillPreparationAndNoStrokeIgnoresOverride() throws {
		let cache = SymbolPathCache()
		let first = try cache.prepare(RasterTransformedStroke.asset.storage, strokeWidth: nil, scale: 1)
		let second = try cache.prepare(RasterTransformedStroke.asset.storage, strokeWidth: 1, scale: 1)
		#expect(first.paths[0].fill === second.paths[0].fill)
		#expect(cache.accounting.fillPreparations == 1 && cache.accounting.preparations == 2)
		let fixed = try cache.prepare(RasterColors.asset.storage, strokeWidth: nil, scale: 1)
		#expect(try cache.prepare(RasterColors.asset.storage, strokeWidth: 4, scale: 1) === fixed)
	}

	@Test func defaultCacheEnforcesBothHardLimits() throws {
		let cache = SymbolPathCache()
		for index in 0..<257 {
			let asset = SymbolStorage(
				viewBox: .init(x: Double(index), width: 24, height: 24),
				mirrorsInRTL: false,
				elements: RasterColors.asset.storage.elements
			)
			_ = try cache.prepare(asset, strokeWidth: nil, scale: 1)
		}
		#expect(cache.accounting.entries == 256)
		#expect(cache.accounting.bytes <= 16 * 1_024 * 1_024)
	}

	@Test func validOversizedPreparationIsTransient() throws {
		var commands: [SymbolPathCommand] = [.move(x: 0, y: 0)]
		for index in 1..<65536 {
			commands.append(.line(x: Double(index % 24), y: Double((index / 24) % 24)))
		}

		let asset = SymbolStorage(
			viewBox: .init(width: 24, height: 24),
			mirrorsInRTL: false,
			elements: [
				.path(
					commands: commands,
					transform: .identity,
					fill: .currentColor,
					fillRule: .nonzero,
					fillOpacity: 1,
					stroke: .none,
					strokeOpacity: 1,
					strokeWidth: 1,
					lineCap: .butt,
					lineJoin: .miter,
					miterLimit: 4,
					opacity: 1
				)
			]
		)
		let cache = SymbolPathCache()
		let owner = try cache.prepare(asset, strokeWidth: nil, scale: 1)
		#expect(owner.bytes > 16 * 1_024 * 1_024)
		#expect(cache.accounting.entries == 0 && !owner.paths.isEmpty)
	}

	@MainActor @Test func resourceLimitProducesNoPaintAndGenerationTaggedFeedback() throws {
		let context = try draw(RasterColors.asset)
		context.clear(CGRect(x: 0, y: 0, width: 24, height: 24))
		let results = SymbolRasterResults()
		let presentation = SymbolPresentation(
			asset: RasterCurves.asset.storage,
			transform: .scale(x: 1e30, y: 1e30),
			color: .black,
			strokeWidth: nil,
			generation: 7
		)
		var canvas = RasterCanvas()
		let id = STNNodeID(document: DocumentID(), serial: 1)
		canvas.draw([.symbol(id, presentation)], in: context, symbolResults: results, epoch: 3)
		#expect(results.results.first?.code == .resourceLimitExceeded)
		#expect(results.results.first?.generation == 7 && results.results.first?.epoch == 3)
		#expect(pixel(context, 12, 12)[3] == 0)
	}
}
