import StanaPrimitives

public enum STNEventPhase: Sendable { case capture, target, bubble }

@MainActor public final class STNPointerEvent {
    public let position: STNPoint
    public let pointerID: Int
    public package(set) var target: STNNodeID?
    public package(set) var currentTarget: STNNodeID?
    public package(set) var phase = STNEventPhase.target
    public private(set) var isPropagationStopped = false
    public private(set) var isImmediatePropagationStopped = false
    public private(set) var isDefaultPrevented = false
    package var capture: (() -> Void)?
    package var release: (() -> Void)?
    package init(position: STNPoint, pointerID: Int = 0) {
        self.position = position
        self.pointerID = pointerID
    }
    public func stopPropagation() { isPropagationStopped = true }
    public func stopImmediatePropagation() {
        isImmediatePropagationStopped = true
        stopPropagation()
    }
    public func preventDefault() { isDefaultPrevented = true }
    public func capturePointer() { capture?() }
    public func releasePointerCapture() { release?() }
}

package enum PointerPhase { case down, move, up, cancel }

extension Document {
    @discardableResult package func pointer(_ phase: PointerPhase, at point: STNPoint) -> Int32 {
        let target = captured.flatMap { nodes[$0] } ?? hitTest(point)
        guard let target else {
            if phase == .up || phase == .cancel {
                pressed = nil
                captured = nil
                changed(root, .paint)
            }
            return 0
        }
        var path: [NodeRecord] = []
        var current: NodeRecord? = target
        while let node = current {
            path.append(node)
            current = node.parent
        }
        let event = STNPointerEvent(position: point)
        var windowAction: Int32 = 0
        event.target = target.id
        event.capture = { [weak self, weak target] in self?.captured = target?.id }
        event.release = { [weak self] in self?.captured = nil }
        dispatchSnapshots = orderedNodes.map { STNNodeSnapshot($0, focused: focused) }
        defer { dispatchSnapshots = nil }
        STNTransaction.perform {
            defer { dispatchSnapshots = nil }
            event.phase = .capture
            for node in path.dropFirst().reversed() {
                event.currentTarget = node.id
                switch phase {
                case .down: node.onPointerDownCapture?(event)
                case .move: node.onPointerMoveCapture?(event)
                case .up: node.onPointerUpCapture?(event)
                case .cancel: break
                }
                if event.isPropagationStopped { break }
            }
            for node in path {
                if event.isPropagationStopped { break }
                event.currentTarget = node.id
                event.phase = node === target ? .target : .bubble
                switch phase {
                case .down: node.onPointerDown?(event)
                case .move: node.onPointerMove?(event)
                case .up: node.onPointerUp?(event)
                case .cancel: node.onPointerCancel?(event)
                }
                if event.isPropagationStopped { break }
            }
            if phase == .up || phase == .cancel {
                let wasPressed = pressed
                pressed = nil
                captured = nil
                if phase == .up, !event.isDefaultPrevented, wasPressed == target.id, target.bounds.contains(point),
                    target.kind != .textField
                {
                    activate(target.id)
                }
                changed(target, .paint)
                return
            }
            guard !event.isDefaultPrevented else { return }
            switch phase {
            case .down:
                let interaction = path.first { $0.style.windowInteraction != 0 }?.style.windowInteraction ?? 0
                let interactive = path.contains {
                    $0.isFocusable || $0.onActivate != nil || $0.onPointerDown != nil
                        || $0.onPointerMove != nil || $0.onPointerUp != nil
                        || $0.onPointerDownCapture != nil || $0.onPointerMoveCapture != nil
                        || $0.onPointerUpCapture != nil || $0.kind == .scroll
                }
                if captured == nil, !interactive, target.scope.isAlive,
                    path.allSatisfy({ $0.style.visibility == .visible && $0.style.isEnabled && !$0.style.inert }),
                    interaction != -1
                {
                    windowAction = interaction > 0 ? interaction : (windowBackgroundDragging ? 1 : 0)
                }
                if target.isFocusable {
                    setFocus(target.id)
                    pressed = target.id
                    captured = target.id
                    changed(target, .paint)
                }
            default: break
            }
        }
        return target.scope.isAlive && nodes[target.id] != nil ? windowAction : 0
    }
    package func scroll(at point: STNPoint, dx: Double, dy: Double) {
        ensureGeometry?()
        func find(_ node: NodeRecord) -> NodeRecord? {
            guard node.style.visibility == .visible else { return nil }
            for child in node.children.reversed() { if let found = find(child) { return found } }
            return node.kind == .scroll && node.bounds.contains(point) ? node : nil
        }
        guard let node = find(root) else { return }
        node.scrollOffset.x = min(
            max(0, node.scrollOffset.x - dx), max(0, node.contentSize.width - node.bounds.size.width))
        node.scrollOffset.y = min(
            max(0, node.scrollOffset.y - dy), max(0, node.contentSize.height - node.bounds.size.height))
        changed(node, .all)
    }
}
