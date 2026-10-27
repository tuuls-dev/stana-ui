import StanaCore
import StanaPrimitives

package struct EditingPaint {
    package let text: String
    package let offset: Double
    package let selectionStart: Double
    package let selectionEnd: Double
    package let markedStart: Double?
    package let markedEnd: Double?
    package init(
        text: String, offset: Double = 0, selectionStart: Double, selectionEnd: Double, markedStart: Double? = nil,
        markedEnd: Double? = nil
    ) {
        self.text = text
        self.offset = offset
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
        self.markedStart = markedStart
        self.markedEnd = markedEnd
    }
}

@MainActor package final class SceneBuilder {
    struct Item: Equatable {
        let commands: [DrawCommand]
        let bounds: STNRect
    }
    package let document: Document
    private var previous: [STNNodeID: Item] = [:]
    private var previousOrder: [STNNodeID] = []
    private var revision: UInt64 = 0
    package var editing: ((NodeRecord) -> EditingPaint?)?
    package init(document: Document) { self.document = document }
    package func build(surfaceEpoch: UInt64, backingRevision: UInt64, forceFull: Bool = false) -> SceneSnapshot {
        nextRevision(&revision)
        var items: [STNNodeID: Item] = [:]
        var order: [STNNodeID] = []
        var commands: [DrawCommand] = []
        var damage = DamageTracker()
        let viewport = STNRect(width: document.viewport.width, height: document.viewport.height)
        func color(_ c: STNColor) -> STNColor {
            document.theme?.resolve(c, dark: document.dark)
                ?? c.resolved(dark: document.dark, highContrast: document.highContrast)
        }
        func visit(_ node: NodeRecord, inheritedClip: STNRect, inheritedOpacity: Double = 1) {
            guard node.style.visibility == .visible else { return }
            let style = node.style
            let bounds = node.bounds
            var local: [DrawCommand] = []
            let clip = style.clip || node.kind == .scroll ? inheritedClip.intersection(bounds) : inheritedClip
            if style.background.alpha > 0 {
                local.append(.fill(bounds, color(style.background), radius: style.cornerRadius))
            }
            if node.kind == .root {
                local.append(.fill(viewport, color(document.surfaceBackground), radius: 0))
            }
            if node.kind == .button || node.kind == .textField {
                local.append(
                    .fill(
                        bounds, color(node.kind == .button && document.pressed == node.id ? .border : .surface),
                        radius: max(5, style.cornerRadius)))
                local.append(.stroke(bounds, color(.border), width: 1, radius: max(5, style.cornerRadius)))
            }
            if style.borderWidth > 0 {
                local.append(
                    .stroke(bounds, color(style.borderColor), width: style.borderWidth, radius: style.cornerRadius))
            }
            let inner = bounds.inset(by: style.padding)
            let font = STNFont.system(size: style.font.size * document.textScale, weight: style.font.weight)
            if node.kind == .text || node.kind == .button || node.kind == .toggle {
                var textBounds = inner
                if node.kind == .toggle {
                    let track = STNRect(
                        x: inner.minX, y: inner.minY + max(0, (inner.size.height - 18) / 2), width: 28, height: 18)
                    local.append(.fill(track, color(node.isOn ? .accent : .border), radius: 9))
                    local.append(
                        .fill(
                            .init(x: track.minX + (node.isOn ? 12 : 2), y: track.minY + 2, width: 14, height: 14),
                            .white, radius: 7))
                    textBounds.origin.x += 36
                    textBounds.size.width = max(0, textBounds.size.width - 36)
                }
                local.append(.text(node.text, textBounds, font, color(style.foreground), wraps: node.kind == .text))
            }
            if node.kind == .textField {
                let edit = editing?(node)
                let value = edit?.text ?? node.text
                let shown = style.secure ? String(repeating: "•", count: value.utf16.count) : value
                local.append(.pushClip(inner))
                if document.focused == node.id, let edit, edit.selectionEnd > edit.selectionStart {
                    local.append(
                        .fill(
                            .init(
                                x: inner.minX + edit.selectionStart - edit.offset, y: inner.minY,
                                width: edit.selectionEnd - edit.selectionStart, height: inner.size.height),
                            color(.accent), radius: 0))
                }
                var textBounds = inner
                textBounds.origin.x -= edit?.offset ?? 0
                textBounds.size.width += edit?.offset ?? 0
                local.append(
                    .text(
                        shown.isEmpty ? node.placeholder : shown, textBounds, font,
                        color(shown.isEmpty ? .secondaryText : style.foreground), wraps: false))
                if document.focused == node.id, let edit {
                    if edit.selectionStart == edit.selectionEnd {
                        local.append(
                            .fill(
                                .init(
                                    x: inner.minX + edit.selectionEnd - edit.offset, y: inner.minY + 1, width: 1,
                                    height: max(0, inner.size.height - 2)), color(.text), radius: 0))
                    }
                    if let start = edit.markedStart, let end = edit.markedEnd {
                        local.append(
                            .fill(
                                .init(
                                    x: inner.minX + start - edit.offset, y: inner.maxY - 1, width: max(1, end - start),
                                    height: 1), color(.text), radius: 0))
                    }
                }
                local.append(.popClip)
            }
            if node.kind == .image, let data = node.imageData { local.append(.image(data, inner)) }
            if node.kind == .canvas {
                for command in node.canvasCommands {
                    switch command {
                    case .fill(var rect, let c, let r):
                        rect.origin.x += inner.minX
                        rect.origin.y += inner.minY
                        local.append(.fill(rect, color(c), radius: r))
                    case .stroke(var rect, let c, let w, let r):
                        rect.origin.x += inner.minX
                        rect.origin.y += inner.minY
                        local.append(.stroke(rect, color(c), width: w, radius: r))
                    }
                }
            }
            if document.focused == node.id {
                local.append(.stroke(bounds, color(.accent), width: 2, radius: max(5, style.cornerRadius)))
            }
            let opacity = style.opacity * (style.isEnabled ? 1 : 0.5)
            // Include inherited compositing state so ancestor opacity/clip changes invalidate descendants.
            let ownCommands: [DrawCommand] =
                [.pushClip(clip), .pushOpacity(opacity * inheritedOpacity)] + local + [.popOpacity, .popClip]
            let item = Item(commands: ownCommands, bounds: bounds.intersection(inheritedClip))
            items[node.id] = item
            order.append(node.id)
            if previous[node.id] != item {
                damage.add(previous[node.id]?.bounds ?? .zero)
                damage.add(item.bounds)
                document.metrics.recordedPaintItems += 1
            }
            commands.append(.pushClip(clip))
            commands.append(.pushOpacity(opacity))
            commands.append(contentsOf: local)
            for child in node.children {
                visit(child, inheritedClip: clip, inheritedOpacity: opacity * inheritedOpacity)
            }
            commands.append(.popOpacity)
            commands.append(.popClip)
        }
        visit(document.root, inheritedClip: viewport)
        for (id, old) in previous where items[id] == nil { damage.add(old.bounds) }
        let full = forceFull || previous.isEmpty || backingRevision + 1 != revision || order != previousOrder
        previous = items
        previousOrder = order
        document.dirty.remove(.paint)
        return .init(
            documentRevision: document.revision, sceneRevision: revision, surfaceEpoch: surfaceEpoch,
            damageBaseRevision: backingRevision, damage: full ? [viewport] : damage.resolved(in: viewport),
            commands: commands, size: document.viewport)
    }
}
