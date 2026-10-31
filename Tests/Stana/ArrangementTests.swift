import Foundation
import StanaCore
import StanaPrimitives
import StanaText
import Testing

@testable import Stana
@testable import StanaScene

@MainActor private final class CountingTextService: TextService {
	let base = TestTextService()
	var measurements = 0

	func measure(_ text: String, font: STNFont, maxWidth: Double, wraps: Bool) -> TextMeasurement {
		measurements += 1
		return base.measure(text, font: font, maxWidth: maxWidth, wraps: wraps)
	}

	func offset(in text: String, utf16Index: Int, font: STNFont) -> Double {
		base.offset(in: text, utf16Index: utf16Index, font: font)
	}

	func index(in text: String, x: Double, font: STNFont) -> Int {
		base.index(in: text, x: x, font: font)
	}
}

@Suite @MainActor struct ArrangementTests {
	@Test func directionalInsetsPreserveDirectionlessBehaviorAndClampSizes() {
		let rect = STNRect(x: 4, y: 6, width: 100, height: 50)
		let padding = STNInsets(top: 7, leading: 10, bottom: 9, trailing: 30)
		#expect(rect.inset(by: padding) == .init(x: 14, y: 13, width: 60, height: 34))
		#expect(rect.inset(by: padding, direction: .leftToRight) == rect.inset(by: padding))
		#expect(rect.inset(by: padding, direction: .rightToLeft) == .init(x: 34, y: 13, width: 60, height: 34))
		#expect(STNRect(width: 5, height: 5).inset(by: padding, direction: .rightToLeft).size == .zero)
	}

	@Test func scrollDirectionAndRadiusReuseMeasurementsAndPublishGeometrySynchronously() throws {
		let service = CountingTextService()
		let radius = STNSignal(0.0)
		let session = MountSession(size: .init(width: 300, height: 200), text: service)
		defer {
			session.close()
		}

		session.document.layoutCountersEnabled = true
		mountArrangement(session) {
			STNBox(properties: .init(layout: .init(padding: STNInsets(leading: 10, trailing: 30)))) {
				STNScrollView(
					properties: .init(
						layout: .init(
							padding: STNInsets(leading: 5, trailing: 15),
							frame: STNFrame(width: 200, height: 80)
						),
						appearance: .init(cornerRadius: radius)
					)
				) {
					STNVStack {
						for index in 0..<10 {
							STNButton(properties: .init(text: "Button \(index)", onActivate: {}))
						}
					}
				}
			}
		}

		let scroll = try #require(session.document.orderedNodes.first { $0.kind == .scroll })
		let first = try #require(session.document.orderedNodes.first { $0.kind == .button })
		let last = try #require(session.document.orderedNodes.last { $0.kind == .button })
		let measured = service.measurements
		let versions = session.document.orderedNodes.map(\.measureVersion)
		let caches = session.document.orderedNodes.map(\.measureCache)
		let firstLTR = first.bounds
		_ = session.scene.build(surfaceEpoch: 1, backingRevision: 0)
		session.environment.layoutDirection.value = .rightToLeft
		#expect(scroll.bounds.minX == 30)
		#expect(first.bounds.minX == scroll.bounds.minX + 15)
		#expect(first.bounds != firstLTR)
		#expect(session.document.hitTest(.init(x: first.bounds.minX + 1, y: first.bounds.minY + 1))?.id == first.id)
		#expect(session.semanticSnapshot.nodes.first { $0.owner == first.id }?.bounds == first.bounds)
		#expect(service.measurements == measured)
		#expect(session.document.orderedNodes.map(\.measureVersion) == versions)
		#expect(session.document.orderedNodes.map(\.measureCache) == caches)

		let point = STNPoint(x: scroll.bounds.minX + 1, y: scroll.bounds.minY + 1)
		session.document.scroll(at: point, dx: 0, dy: -1000)
		#expect(abs(last.bounds.maxY - scroll.bounds.maxY) < 0.000_001)
		#expect(session.semanticSnapshot.nodes.first { $0.owner == last.id }?.isOffscreen == false)
		#expect(session.document.hitTest(.init(x: last.bounds.minX + 1, y: last.bounds.maxY - 1))?.id == last.id)
		#expect(service.measurements == measured)
		#expect(session.document.orderedNodes.map(\.measureVersion) == versions)
		let commits = session.document.metrics.logicalCommits
		session.document.scroll(at: point, dx: 0, dy: -1)
		session.document.scroll(at: point, dx: 0, dy: 0)
		#expect(session.document.metrics.logicalCommits == commits)

		let before = session.document.orderedNodes.map(\.bounds)
		let scene = session.scene.build(surfaceEpoch: 1, backingRevision: 1)
		radius.value = 30
		#expect(session.document.orderedNodes.map(\.bounds) == before)
		#expect(session.document.orderedNodes.map(\.measureVersion) == versions)
		#expect(service.measurements == measured)
		let rounded = session.scene.build(surfaceEpoch: 1, backingRevision: scene.sceneRevision)
		#expect(rounded.geometry?.entries[last.id]?.clips.last?.radius == 30)
		#expect(session.document.hitTest(point)?.id != scroll.id)
	}

	@Test(arguments: [STNTextField.TextAlignment.leading, .center, .trailing])
	func editorDrawingSelectionAndPointerShareDirectionalContentBounds(alignment: STNTextField.TextAlignment) throws {
		let service = CountingTextService()
		let value = STNSignal("abcdef")
		let session = MountSession(size: .init(width: 300, height: 100), text: service)
		defer {
			session.close()
		}

		mountArrangement(session) {
			STNBox(properties: .init(layout: .init(padding: STNInsets(leading: 7, trailing: 17)))) {
				STNTextField(
					properties: .init(
						value: value.binding,
						options: STNTextField.Options(alignment: alignment),
						layout: .init(
							padding: STNInsets(top: 4, leading: 10, bottom: 6, trailing: 30),
							frame: STNFrame(width: 200)
						)
					)
				)
			}
		}

		let node = try #require(session.document.orderedNodes.first { $0.kind == .textField })
		let editor = try #require(session.editors[node.id])
		_ = session.editingPaint(node)
		let measured = service.measurements
		var backing: UInt64 = 0
		for direction in [STNLayoutDirection.leftToRight, .rightToLeft, .leftToRight] {
			session.environment.layoutDirection.value = direction
			let inner = node.bounds.inset(by: node.style.padding, direction: direction)
			#expect(node.bounds.minX == (direction == .leftToRight ? 7 : 17))
			#expect(inner.minX == node.bounds.minX + (direction == .leftToRight ? 10 : 30))
			let paint = try #require(session.editingPaint(node))
			let start = inner.minX - paint.offset
			let point = STNPoint(x: start + 1, y: inner.minY + 1)
			_ = session.pointer(0, at: point)
			_ = session.pointer(2, at: point)
			#expect(editor.selection.location == 0)
			try editor.select(NSRange(location: 1, length: 2))
			let scene = session.scene.build(surfaceEpoch: 1, backingRevision: backing)
			backing = scene.sceneRevision
			#expect(
				scene.commands.contains {
					if case .text(let text, let bounds, _, _, _) = $0 {
						return text == value.value && bounds.minX == start && bounds.minY == inner.minY
					}
					return false
				}
			)
			#expect(
				scene.commands.contains {
					if case .fill(let rect, let color, _) = $0 {
						let step = node.style.font.size * 0.6
						return color == node.style.selectionColor.resolved(dark: false)
							&& abs(rect.minX - start - step) < 0.000_001
							&& abs(rect.size.width - 2 * step) < 0.000_001
					}
					return false
				}
			)
			#expect(service.measurements == measured)
		}
	}
}

@MainActor private func mountArrangement(_ session: MountSession, @STNBuilder _ content: () -> STNGroup) {
	session.mount(content)
}
