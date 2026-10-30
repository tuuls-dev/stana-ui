import Foundation
import StanaAccessibility
import StanaCore
import StanaPrimitives
import Testing

@testable import StanaPlatformMacOS

extension NativeWindowServer {
	@Suite(.serialized)
	@MainActor struct NativeAccessibilityTests {
		@Test func offActorQueriesKeepFullIdentityAndRemovedElementsBecomeUnavailable() async throws {
			let window = try MacOSWindow(title: "AX ownership", size: .init(width: 120, height: 80))
			defer { window.close() }
			let first = Document(size: .init(width: 120, height: 80))
			let second = Document(size: .init(width: 120, height: 80))
			defer {
				first.close()
				second.close()
			}
			func button(in document: Document, label: String) -> NodeRecord {
				let node = document.create(.button, parent: document.root)
				node.text = label
				node.bounds = .init(x: 10, y: 10, width: 80, height: 30)
				return node
			}

			let firstButton = button(in: first, label: "First")
			let secondButton = button(in: second, label: "Second")
			#expect(firstButton.id.nativeID == secondButton.id.nativeID)
			#expect(firstButton.id != secondButton.id)
			window.accessibility.publish(SemanticProjection(document: first).snapshot())
			let stale = try #require(window.semanticNodes[STNSemanticID(owner: firstButton.id)])
			let answer =
				await Task.detached {
					(stale.accessibilityLabel(), stale.isAccessibilityEnabled(), stale.accessibilityFrame().width)
				}
				.value
			#expect(answer.0 == "First")
			#expect(answer.1)
			#expect(answer.2 == 80)
			var activations = 0
			window.onEvent = { event in
				if case .activate = event {
					activations += 1
				}
			}
			// Replace the document before the queued action runs; equal serials must not alias.
			#expect(stale.accessibilityPerformPress())
			window.accessibility.publish(SemanticProjection(document: second).snapshot())
			let current = try #require(window.semanticNodes[STNSemanticID(owner: secondButton.id)])
			#expect(stale !== current)
			let removed =
				await Task.detached {
					(stale.accessibilityLabel(), stale.isAccessibilityElement(), stale.accessibilityPerformPress())
				}
				.value
			#expect(removed.0 == nil)
			#expect(!removed.1 && !removed.2)
			#expect(activations == 0)
			window.close()
			let closed = await Task.detached { current.isAccessibilityElement() }.value
			#expect(!closed)
		}
	}
}
