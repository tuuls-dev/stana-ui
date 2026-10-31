import StanaText
import StanaCore
import StanaPrimitives
import StanaTesting
import Testing

@testable import Stana
@MakeSTNSymbol(mirrorsInRTL: true)
private struct TestArrow {
	static let svg = "<svg viewBox='-12 -6 24 12' fill='currentColor'><path d='M-10 -4L10 0-10 4Z'/></svg>"
}

@MakeSTNSymbol
private struct TestPlus {
	static let svg = "<svg viewBox='0 0 24 24' stroke='currentColor' fill='none'><path d='M4 12H20M12 4V20'/></svg>"
}

@Suite @MainActor struct SymbolTests {
	private func mount(_ session: MountSession, @STNBuilder _ content: () -> STNGroup) {
		session.mount(content)
	}

	@Test func extremeFiniteFitUnderSingularAncestorSettlesWithoutRepeatedRetries() {
		let asset = STNSymbolAsset._compiled(
			version: 1,
			viewBox: .init(width: .leastNonzeroMagnitude, height: .leastNonzeroMagnitude),
			mirrorsInRTL: false,
			elements: []
		)
		let session = MountSession(size: .init(width: 100, height: 100), text: TestTextService())
		defer { session.close() }
		session.document.root.style.transform = .scale(x: 0, y: 0)
		mount(session) { STNSymbol(properties: .init(symbol: asset)) }
		#expect(session.document.metrics.logicalCommits < 10)
	}

	@Test func propertiesUpdateWithoutRemountAndTransactionsReconcileOnce() throws {
		let session = MountSession(size: .init(width: 200, height: 200), text: TestTextService())
		defer { session.close() }

		let asset = STNSignal(TestArrow.asset), animation = STNSignal(STNSymbolPlayback.once(.bounce, request: 1))
		let size = STNSignal(24.0), stroke = STNSignal<Double?>(nil), tint = STNSignal(STNColor.text)
		mount(session) {
			STNSymbol(
				properties: .init(symbol: asset, size: size, color: tint, animation: animation, strokeWidth: stroke)
			)
		}

		let mounted = try #require(session.symbols.values.first)
		let id = try #require(mounted.node?.id)
		session.tickFrames(timestamp: 1, target: 1)
		session.tickFrames(timestamp: 1.2, target: 1.2)
		let elapsed = mounted.state.elapsed
		STNTransaction.perform {
			size.value = 32; stroke.value = 2; tint.value = .accent
		}
		#expect(mounted.state.elapsed == elapsed)
		STNTransaction.perform {
			animation.value = .once(.pulse, request: 2)
			asset.value = TestPlus.asset
			animation.value = .once(.rotate, request: 3)
		}
		#expect(mounted.node?.id == id && session.symbols.count == 1)
		#expect(mounted.state.lastRequest == 3 && mounted.state.elapsed == 0 && mounted.state.active == .rotate)
		asset.value = TestArrow.asset
		#expect(!mounted.state.needsFrame)
	}

	@Test func sharedAssetsHaveIndependentClocksAndDisposeRegistrations() throws {
		let session = MountSession(size: .init(width: 200, height: 200), text: TestTextService())
		defer { session.close() }

		let shown = STNSignal(true), animation = STNSignal(STNSymbolPlayback.none)
		mount(session) {
			STNSymbol(properties: .init(symbol: TestArrow.asset, animation: STNSymbolPlayback.loop(.rotate)))
			STNIf(shown) { STNSymbol(properties: .init(symbol: TestArrow.asset, animation: animation)) }
		}

		session.tickFrames(timestamp: 1, target: 1)
		session.tickFrames(timestamp: 1.25, target: 1.25)
		animation.value = .once(.bounce, request: 1)
		let states = session.symbols.values.map(\.state)
		#expect(states.contains { $0.elapsed == 0.25 } && states.contains { $0.elapsed == 0 })
		shown.value = false
		#expect(session.symbols.count == 1 && session.frameRegistrations.count == 1)
		shown.value = true
		#expect(
			session.symbols.count == 2
				&& session.symbols.values.contains { $0.state.elapsed == 0 && $0.state.lastRequest == 1 }
		)
	}

	@Test func labelsRTLAndEffectsKeepGeometryStable() throws {
		let session = MountSession(size: .init(width: 120, height: 100), text: TestTextService())
		defer { session.close() }

		mount(session) {
			STNHStack(properties: .init()) {
				STNSymbol(
					properties: .init(
						symbol: TestArrow.asset,
						animation: STNSymbolPlayback.loop(.rotate),
						accessibility: .init(label: "")
					)
				)
				STNSymbol(properties: .init(symbol: TestArrow.asset))
			}
		}

		let initial = session.document.projectGeometry()
		#expect(session.semanticSnapshot.nodes.filter { $0.role == .image }.count == 1)
		session.tickFrames(timestamp: 1, target: 1)
		session.tickFrames(timestamp: 1.25, target: 1.25)
		#expect(session.document.projectGeometry().entries == initial.entries)
		let elapsed = session.symbols.values.first { $0.state.needsFrame }?.state.elapsed
		session.environment.layoutDirection.value = .rightToLeft
		#expect(session.symbols.values.first { $0.state.needsFrame }?.state.elapsed == elapsed)
	}

	@Test func ancestorHidingAndReducedMotionReleaseDemand() throws {
		let session = MountSession(size: .init(width: 200, height: 200), text: TestTextService())
		defer { session.close() }

		mount(session) {
			STNSymbol(properties: .init(symbol: TestArrow.asset, animation: STNSymbolPlayback.loop(.pulse)))
		}

		let mounted = try #require(session.symbols.values.first)
		#expect(mounted.state.needsFrame)
		session.document.root.style.visibility = .hidden
		STNTransaction.perform { session.document.changed(session.document.root, .all) }
		#expect(!mounted.state.needsFrame)
		session.environment.reducedMotion.value = true
		session.document.root.style.visibility = .visible
		STNTransaction.perform { session.document.changed(session.document.root, .all) }
		#expect(!mounted.state.needsFrame)
		session.environment.reducedMotion.value = false
		#expect(mounted.state.needsFrame)
		session.symbolHostVisible = false
		session.commit()
		#expect(!mounted.state.needsFrame)
	}

	@Test func failuresDeduplicateDiscardStaleAndRecoverOnRelevantChanges() throws {
		let session = MountSession(size: .init(width: 200, height: 200), text: TestTextService())
		defer { session.close() }

		let stroke = STNSignal<Double?>(nil)
		var diagnostics: [STNSymbolDiagnostic] = []
		mount(session) {
			STNSymbol(
				properties: .init(
					symbol: TestPlus.asset,
					animation: STNSymbolPlayback.loop(.rotate),
					strokeWidth: stroke,
					onError: { diagnostics.append($0) }
				)
			)
		}

		let mounted = try #require(session.symbols.values.first), node = try #require(mounted.node)
		let generation = try #require(node.symbol?.generation)
		let failure = SymbolRenderResult(node: node.id, generation: generation, epoch: 1, code: .resourceLimitExceeded)
		mounted.receive(failure); mounted.receive(failure)
		#expect(diagnostics.count == 1 && !mounted.state.needsFrame && node.symbol?.available == false)
		stroke.value = 3
		#expect(mounted.state.needsFrame && node.symbol?.available == true)
		mounted.receive(failure)
		#expect(diagnostics.count == 1 && mounted.state.needsFrame)
		let recoveredGeneration = try #require(node.symbol?.generation)
		mounted.receive(.init(node: node.id, generation: recoveredGeneration, epoch: 1, code: .preparationFailed))
		#expect(!mounted.state.needsFrame)
		session.document.root.style.transform = .scale(x: 2, y: 2)
		STNTransaction.perform { session.document.changed(session.document.root, .compositing) }
		#expect(mounted.state.needsFrame && node.symbol?.generation != recoveredGeneration)
	}
}
