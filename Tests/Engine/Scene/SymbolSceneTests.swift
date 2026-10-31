import StanaCore
import StanaPrimitives
import Testing

@testable import StanaScene
@Suite @MainActor struct SymbolSceneTests {
	private func symbol(_ document: Document, mirrors: Bool = true) -> NodeRecord {
		let node = document.create(.symbol, parent: document.root)
		let storage = SymbolStorage(
			viewBox: .init(x: -12, y: -6, width: 24, height: 12),
			mirrorsInRTL: mirrors,
			elements: [
				.path(
					commands: [.move(x: -30, y: -20), .line(x: 30, y: 20)],
					transform: .identity,
					fill: .none,
					fillRule: .nonzero,
					fillOpacity: 1,
					stroke: .currentColor,
					strokeOpacity: 1,
					strokeWidth: 2,
					lineCap: .round,
					lineJoin: .round,
					miterLimit: 4,
					opacity: 1
				)
			]
		)
		node.symbol = SymbolContent(asset: storage)
		node.symbol?.inkBounds = storage.inkBounds(strokeWidth: nil)
		node.bounds = .init(x: 50, y: 50, width: 80, height: 40)
		return node
	}

	private func presentation(_ scene: SceneSnapshot) throws -> SymbolPresentation {
		try #require(
			scene.commands
				.compactMap { command in
					if case .symbol(_, let value) = command {
						return value
					}

					return nil
				}
				.first
		)
	}

	@Test func fitNormalizesOriginAndDoesNotGrowWithFrame() throws {
		let document = Document(size: .init(width: 200, height: 200))
		defer { document.close() }

		_ = symbol(document)
		let p = try presentation(SceneBuilder(document: document).build(surfaceEpoch: 1, backingRevision: 0))
		#expect(p.transform.applying(to: .init(x: -12, y: -6)) == .init(x: 78, y: 64))
		#expect(p.transform.applying(to: .init(x: 12, y: 6)) == .init(x: 102, y: 76))
	}

	@Test func rtlMirrorsBeforeEffectAndNeverChangesGeometry() throws {
		let document = Document(size: .init(width: 200, height: 200))
		defer { document.close() }

		let node = symbol(document)
		node.symbol?.effect = .init(rotation: .pi / 2)
		let scene = SceneBuilder(document: document)
		let before = document.projectGeometry().entries
		let ltr = try presentation(scene.build(surfaceEpoch: 1, backingRevision: 0))
		document.direction = .rightToLeft
		let rtl = try presentation(scene.build(surfaceEpoch: 1, backingRevision: 0))
		let l = ltr.transform.applying(to: .init(x: 12, y: 0)), r = rtl.transform.applying(to: .init(x: 12, y: 0))
		#expect(abs(l.x - 90) < 1e-10 && abs(r.x - 90) < 1e-10)
		#expect(l.y > 70 && r.y < 70)
		#expect(document.projectGeometry().entries == before)
	}

	@Test func incrementalDamageAndCullingIncludeAnimatedOverflow() throws {
		let document = Document(size: .init(width: 200, height: 200))
		defer { document.close() }

		let node = symbol(document)
		let scene = SceneBuilder(document: document)
		let initial = scene.build(surfaceEpoch: 1, backingRevision: 0)
		node.symbol?.effect = .init(verticalFraction: -0.12)
		document.changed(node, .paint)
		let animated = scene.build(surfaceEpoch: 1, backingRevision: initial.sceneRevision)
		#expect(animated.damage.contains { $0.minY < node.bounds.minY && $0.maxY > node.bounds.maxY })

		func leafBounds(_ group: PaintGroup?) -> STNRect? {
			guard let group else {
				return nil
			}

			for entry in group.children {
				if case .cpu(let item) = entry, item.id == node.id {
					return item.bounds
				}

				if case .group(let nested) = entry, let found = leafBounds(nested) {
					return found
				}
			}

			return nil
		}
		#expect(try #require(leafBounds(animated.paint)).minY < node.bounds.minY)
		#expect(animated.geometry?.entries == initial.geometry?.entries)
	}
}
