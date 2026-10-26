import Stana
import StanaTesting
import Testing

@Suite @MainActor struct InputAndEnvironmentTests {
    @Test func captureAndBubbleUseCommittedDispatchGeometry() throws {
        let host = STNTestHost()
        let visible = STNSignal(true)
        var phases: [STNEventPhase] = []
        var boxHandle: STNNodeHandle?
        var observedWidth: Double?
        host.mount {
            STNBox(
                properties: .init(
                    frame: .init(width: 200, height: 100),
                    onPointerDown: { event in
                        phases.append(event.phase)
                        observedWidth = try? boxHandle?.bounds().size.width
                    },
                    onPointerDownCapture: { event in
                        phases.append(event.phase)
                        visible.value = false
                    }, onMount: { boxHandle = $0 })
            ) {
                STNIf(visible) { STNButton(properties: .init(text: "Remove on down", onActivate: {})) }
            }
        }
        let button = try #require(host.nodes.first { $0.kind == "button" })
        host.pointerDown(at: .init(x: button.bounds.minX + 2, y: button.bounds.minY + 2))
        #expect(phases == [.capture, .bubble])
        #expect(observedWidth == 200)
        #expect(!host.nodeIDs.contains(button.id))
        host.pointerUp(at: .zero)
        host.close()
    }
    @Test func pointerCaptureDeliversCancelAndSuppressesDefaultActivation() throws {
        let host = STNTestHost()
        var cancellations = 0
        var activations = 0
        host.mount {
            STNBox(
                properties: .init(
                    frame: .init(width: 200, height: 100), onPointerUp: { $0.preventDefault() },
                    onPointerCancel: { _ in cancellations += 1 })
            ) {
                STNButton(properties: .init(text: "Press", onActivate: { activations += 1 }))
            }
        }
        let b = try #require(host.nodes.first { $0.kind == "button" }).bounds
        let point = STNPoint(x: b.minX + 2, y: b.minY + 2)
        host.pointerDown(at: point)
        host.pointerUp(at: point)
        #expect(activations == 0)
        host.pointerDown(at: point)
        host.cancelPointer()
        #expect(cancellations == 1)
        host.close()
    }
    @Test func themeOnlyChangesPaintWhileTextScaleRemeasures() throws {
        let host = STNTestHost()
        host.mount { STNVStack { STNText(properties: .init(text: "Hello")) } }
        _ = host.render()
        let original = host.metrics.measureCalls
        host.environment.theme.value = .dark
        #expect(host.metrics.measureCalls == original)
        #expect(host.needsDisplay)
        let width = try #require(host.nodes.first { $0.kind == "text" }).bounds.size.width
        host.environment.textScale.value = 2
        #expect(host.nodes.first { $0.kind == "text" }?.bounds.size.width == width * 2)
        host.close()
    }
    @Test func keyboardFocusRealizesCurrentScrollGeometry() throws {
        let host = STNTestHost(size: .init(width: 200, height: 150))
        host.mount {
            STNScrollView(properties: .init(frame: .init(width: 200, height: 100))) {
                STNVStack(properties: .init(spacing: 8)) {
                    for index in 0..<8 { STNButton(properties: .init(text: "Button \(index)", onActivate: {})) }
                }
            }
        }
        let last = try #require(host.nodes.last { $0.kind == "button" })
        #expect(last.bounds.maxY > 100)
        try host.focus(last.id)
        let moved = try #require(host.nodes.first { $0.id == last.id })
        #expect(abs(moved.bounds.maxY - 100) < 0.000_001)
        #expect(host.semantics.nodes.first { $0.owner == last.id }?.isOffscreen == false)
        host.close()
    }
}
