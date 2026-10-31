import StanaPrimitives
import Testing
@testable import Stana

@MainActor
@MakeSTNSymbol
private struct IsolatedSymbol {
	private static let svg = "<svg viewBox='0 0 2 2' fill='#000'><path d='M-0 0h1'/></svg>"
}

@MakeSTNSymbol
private struct EquivalentSymbol {
	static let svg = "<svg viewBox='0 0 2 2' fill='black'><!--ignored--><path id='ignored' d='M0 0L1 0'/></svg>"
}

@Suite struct SymbolAssetTests {
	@Test func assetsInitializeAndCompareOutsideMainActor() async {
		let equivalent =
			await Task.detached {
				let a = IsolatedSymbol.asset, b = EquivalentSymbol.asset
				return a == b
			}
			.value
		#expect(equivalent)
	}

	@Test func bridgeAcceptsExactlySixtyFourElementLevels() {
		var elements: [STNSymbolAsset._Element] = []
		for _ in 0..<64 {
			elements = [.group(transform: .identity, opacity: 1, children: elements)]
		}
		let asset = STNSymbolAsset._compiled(
			version: 1,
			viewBox: .init(width: 24, height: 24),
			mirrorsInRTL: false,
			elements: elements
		)
		#expect(asset.storage.elements.count == 1)
	}

	@Test func copiedAssetSharesStorageAndBridgeNormalizesNegativeZero() {
		let asset = EquivalentSymbol.asset
		let copy = asset
		#expect(asset.storage === copy.storage)
		let compiled = STNSymbolAsset._compiled(
			version: 1,
			viewBox: .init(x: -0.0, width: 2, height: 2),
			mirrorsInRTL: false,
			elements: [
				.path(
					commands: [.move(x: -0.0, y: -0.0), .line(x: 1, y: 0)],
					transform: .identity,
					fill: .rgba(red: 0, green: 0, blue: 0, alpha: 1),
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
		#expect(compiled == asset)
		#expect(compiled.storage.viewBox.minX.sign == .plus)
		guard case .path(let commands, _, _, _, _, _, _, _, _, _, _, _) = compiled.storage.elements[0],
			case .move(let x, let y) = commands[0]
		else {
			Issue.record("Expected typed geometry")
			return
		}
		#expect(x.sign == .plus && y.sign == .plus)
	}
}
