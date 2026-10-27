import Foundation
import StanaAccessibility
import StanaCore
import StanaLayout
import StanaPlatform
import StanaPlatformMacOS
import StanaPrimitives
import StanaScene
import StanaText

@MainActor package final class MountSession {
	package let document: Document
	package let environment: STNEnvironment
	package let text: any TextService
	package let layout: LayoutEngine
	package let scene: SceneBuilder
	package let semantics: SemanticProjection
	package private(set) var semanticSnapshot: STNSemanticSnapshot!
	package private(set) var nodeSnapshots: [STNNodeSnapshot] = []
	package var window: (any PlatformWindow)?
	package var editors: [STNNodeID: TextBuffer] = [:]
	package private(set) var errors: [STNError] = []
	package var onClose: (() -> Void)?
	private var environmentSubscriptions: [STNSubscription] = []
	private var closed = false
	package var onStable: (() -> Void)?
	package let safeContentBounds: STNSignal<STNRect>

	package var hasMarkedText: Bool {
		editors.values.contains { $0.markedText != nil }
	}

	private var editorOffsets: [STNNodeID: Double] = [:]
	private var modalFocus: STNNodeID?
	private var nativeFocus: STNNodeID?
	private var resettingComposition: Set<STNNodeID> = []

	package init(size: STNSize, text: any TextService, environment: STNEnvironment = .init()) {
		safeContentBounds = STNSignal(.init(width: size.width, height: size.height))
		self.environment = environment
		document = Document(size: size)
		self.text = text
		layout = LayoutEngine(document: document, text: text)
		scene = SceneBuilder(document: document)
		semantics = SemanticProjection(document: document)
		document.ensureGeometry = { [weak self] in self?.layout.layout() }
		document.onCommit = { [weak self] in self?.commit() }
		document.onDisposed = { [weak self] id in
			self?.editors.removeValue(forKey: id)
			self?.editorOffsets.removeValue(forKey: id)
		}
		document.onEditingFocusLoss = { [weak self] id in
			guard let self, let editor = self.editors[id] else {
				return
			}

			try? editor.commitComposition()
			(self.window as? MacOSWindow)?.discardMarkedText()
		}
		scene.editing = { [weak self] node in self?.editingPaint(node) }
	}

	package func mount(_ content: () -> STNGroup) {
		STNTransaction.perform {
			MountContext(session: self, parent: document.root, scope: document.root.scope).mount(content())
			observeEnvironment()
			document.changed(document.root, .all)
		}
	}

	private func observeEnvironment() {
		func own<V>(_ signal: STNSignal<V>, layout: Bool = false, _ apply: @escaping (V) -> Void) {
			let subscription = signal.subscribe { [weak self] value in
				guard let self, !self.closed else {
					return
				}

				apply(value)
				self.document.invalidateEnvironment(layout: layout)
			}
			document.root.scope.own { subscription.cancel() }
			environmentSubscriptions.append(subscription)
		}

		own(environment.isDark) { [weak self] in self?.document.dark = $0 }
		own(environment.highContrast) { [weak self] in self?.document.highContrast = $0 }
		own(environment.layoutDirection, layout: true) { [weak self] in self?.document.direction = $0 }
		own(environment.theme) { [weak self] in self?.document.theme = $0 }
		own(environment.textScale, layout: true) { [weak self] value in
			precondition(value.isFinite && value > 0 && value <= 10, "Stana: text scale must be in 0...10")
			self?.document.textScale = value
		}
	}

	package func attach(_ window: any PlatformWindow) {
		self.window = window
		window.onDraw = { [weak self] in self?.draw() }
		window.onEvent = { [weak self] in self?.receive($0) }
		window.onPointer = { [weak self] phase, point in self?.pointer(phase, at: point) ?? 0 }
		(window as? MacOSWindow)?.onText = { [weak self] kind, text, range, selected, revision in
			self?.edit(kind, text: text, range: range, selected: selected, expectedRevision: revision)
		}
		if window.onState == nil {
			window.onState = { [weak self] state in
				guard let self else {
					return
				}

				self.safeContentBounds.value = state.safeContentBounds
				self.document.viewport = state.contentSize
				self.document.changed(self.document.root, .all)
			}
		}

		commit()
	}

	package func commit() {
		guard !closed else {
			return
		}

		layout.layout()
		nodeSnapshots = document.orderedNodes.map { STNNodeSnapshot($0, focused: document.focused) }
		publishEditing()
		semanticSnapshot = semantics.snapshot()
		window?.accessibility.publish(semanticSnapshot)
		if nativeFocus != document.focused {
			nativeFocus = document.focused
			ReactiveRuntime.shared.afterCommit { [weak self] in
				guard let self, !self.closed else {
					return
				}

				(self.window as? MacOSWindow)?.editing(self.document.focused.flatMap { self.editors[$0] } != nil)
			}
		}

		if document.dirty.contains(.paint) {
			window?.requestRedraw()
		}

		if !hasMarkedText {
			ReactiveRuntime.shared.afterCommit { [weak self] in self?.onStable?() }
		}
	}

	package func draw() {
		guard !closed, let window, document.viewport.width > 0, document.viewport.height > 0 else {
			return
		}

		guard document.dirty.contains(.paint) || window.renderer.backingRevision == 0 else {
			return
		}

		layout.layout()
		let snapshot = scene.build(
			surfaceEpoch: window.renderer.surfaceEpoch,
			backingRevision: window.renderer.backingRevision
		)
		do {
			_ = try window.renderer.submit(snapshot)
		} catch {
			report(.nativeFailure("Raster submission failed"))
		}
	}

	package func report(_ error: STNError) {
		errors.append(error)
		STNDiagnostics.report(error)
	}

	package func close() {
		guard !closed else {
			return
		}

		closed = true
		if let focused = document.focused {
			try? editors[focused]?.commitComposition()
		}

		(window as? MacOSWindow)?.editing(false)
		document.close()
		editors.removeAll()
		environmentSubscriptions.removeAll()
		nodeSnapshots = []
		semanticSnapshot = semantics.snapshot()
		window?.accessibility.detach()
		window?.renderer.detach()
		window?.close()
		window = nil
		onClose?()
		onClose = nil
		onStable = nil
	}

	package func installEditor(_ node: NodeRecord, binding: STNBinding<String>) {
		let editor = TextBuffer(binding.value)
		editor.isSecure = node.style.secure
		editors[node.id] = editor
		editor.onChange = { [weak node, weak document] value in
			guard let node, let document, node.scope.isAlive else {
				return
			}

			STNTransaction.perform {
				node.text = value
				binding.value = value
				document.changed(node, .all)
			}
		}
		editor.onPresentationChange = { [weak node, weak document] in
			guard let node, let document, node.scope.isAlive else {
				return
			}

			document.changed(node, [.paint, .semantics])
		}
		let observation = ValueObservation(read: { binding.value }, equals: { $0 == $1 }) {
			[weak self, weak node, weak editor] value in
			guard let self, let node, let editor, node.scope.isAlive else {
				return
			}

			if editor.text != value {
				self.resettingComposition.insert(node.id)
				if self.document.focused == node.id {
					(self.window as? MacOSWindow)?.discardMarkedText()
				}

				editor.external(value)
				self.resettingComposition.remove(node.id)
			}

			if node.text != value {
				node.text = value
				self.document.changed(node, .all)
			}
		}
		node.scope.own { observation.cancel() }
		ReactiveRuntime.shared.enqueue(observation)
	}

	package func editingPaint(_ node: NodeRecord) -> EditingPaint? {
		guard let editor = editors[node.id] else {
			return nil
		}

		let value = editor.displayText
		let shown = node.style.secure ? String(repeating: "•", count: value.utf16.count) : value
		let font = STNFont.system(size: node.style.font.size * document.textScale, weight: node.style.font.weight)
		let selected = editor.displaySelection
		let start = text.offset(in: shown, utf16Index: selected.location, font: font)
		let end = text.offset(in: shown, utf16Index: NSMaxRange(selected), font: font)
		let available = max(1, node.bounds.size.width - node.style.padding.horizontal - 2)
		var offset = editorOffsets[node.id] ?? 0
		if end - offset > available {
			offset = max(0, end - available)
		}

		if end < offset {
			offset = max(0, end)
		}

		editorOffsets[node.id] = offset
		let marked = editor.markedRange
		return .init(
			text: value,
			offset: offset,
			selectionStart: min(start, end),
			selectionEnd: max(start, end),
			markedStart: marked.location == NSNotFound
				? nil : text.offset(in: shown, utf16Index: marked.location, font: font),
			markedEnd: marked.location == NSNotFound
				? nil : text.offset(in: shown, utf16Index: NSMaxRange(marked), font: font)
		)
	}

	private func publishEditing() {
		guard let window = window as? MacOSWindow else {
			return
		}

		for (id, editor) in editors {
			guard let node = document.nodes[id] else {
				continue
			}

			let value = editor.displayText
			let paint = editingPaint(node)
			let shown = node.style.secure ? String(repeating: "•", count: value.utf16.count) : value
			let font = STNFont.system(size: node.style.font.size * document.textScale, weight: node.style.font.weight)
			let offsets = text.offsets(in: shown, font: font).map { $0 - (paint?.offset ?? 0) }
			let bounds = node.bounds.inset(by: node.style.padding)
			window.publishText(
				value,
				selection: editor.displaySelection,
				marked: editor.markedRange,
				bounds: bounds,
				offsets: offsets,
				revision: editor.revision,
				secure: node.style.secure,
				nodeID: id.nativeID
			)
			if document.focused == id {
				window.publishText(
					value,
					selection: editor.displaySelection,
					marked: editor.markedRange,
					bounds: bounds,
					offsets: offsets,
					revision: editor.revision,
					secure: node.style.secure
				)
			}
		}
	}

	package func edit(_ kind: Int32, text: String, range: NSRange?, selected: NSRange, expectedRevision: UInt64? = nil)
	{
		guard let focused = document.focused, let editor = editors[focused], let node = document.nodes[focused],
			document.isEligible(focused)
		else {
			return
		}

		guard !resettingComposition.contains(focused) else {
			return
		}

		if let expectedRevision, editor.revision != expectedRevision {
			if kind == 3 && editor.markedText == nil {
				return
			}

			report(.staleTextPosition)
			return
		}

		STNTransaction.perform {
			do {
				switch kind {
				case 1: try editor.replace(range, with: text)
				case 2: try editor.setMarked(text, selected: selected, replacement: range)
				case 3: try editor.commitComposition()
				case 4: try editingCommand(text, editor: editor, node: node)
				case 5:
					if let range {
						try editor.select(range)
					}
				case 6: try editor.replace(NSRange(location: 0, length: editor.text.utf16.count), with: text)
				default: break
				}

				document.changed(node, [.paint, .semantics])
			} catch {
				report(.invalidTextRange)
			}
		}
		if !hasMarkedText {
			ReactiveRuntime.shared.afterCommit { [weak self] in self?.onStable?() }
		}
	}

	package func pointer(_ phase: Int, at point: STNPoint) -> Int32 {
		if phase == 3 {
			return document.hitTest(point)?.kind == .textField ? 1 : 0
		}

		let action = document.pointer(phase == 0 ? .down : phase == 1 ? .move : .up, at: point)
		if action != 0 {
			document.pointer(.cancel, at: point)
			return action
		}

		if phase == 0, let focused = document.focused, let node = document.nodes[focused],
			let editor = editors[focused], node.bounds.contains(point)
		{
			let x = point.x - node.bounds.minX - node.style.padding.leading + (editorOffsets[focused] ?? 0)
			let index = text.index(in: editor.text, x: x, font: node.style.font)
			try? editor.select(NSRange(location: index, length: 0))
		}

		return 0
	}

	private func editingCommand(_ command: String, editor: TextBuffer, node: NodeRecord) throws {
		switch command {
		case "insertNewline:":
			try editor.commitComposition()
			node.onSubmit?()
		case "insertTab:": document.focusNext()
		case "insertBacktab:": document.focusNext(backward: true)
		case "cancelOperation:":
			editor.cancelComposition()
			(window as? MacOSWindow)?.discardMarkedText()
		case "deleteBackward:": try editor.delete(backward: true)
		case "deleteForward:": try editor.delete(backward: false)
		case "deleteWordBackward:": try editor.delete(backward: true, word: true)
		case "deleteWordForward:": try editor.delete(backward: false, word: true)
		case "moveLeft:", "moveBackward:": editor.move(-1)
		case "moveRight:", "moveForward:": editor.move(1)
		case "moveLeftAndModifySelection:", "moveBackwardAndModifySelection:": editor.move(-1, extending: true)
		case "moveRightAndModifySelection:", "moveForwardAndModifySelection:": editor.move(1, extending: true)
		case "moveWordLeft:", "moveWordBackward:": editor.move(-1, word: true)
		case "moveWordRight:", "moveWordForward:": editor.move(1, word: true)
		case "moveWordLeftAndModifySelection:": editor.move(-1, extending: true, word: true)
		case "moveWordRightAndModifySelection:": editor.move(1, extending: true, word: true)
		case "moveToBeginningOfLine:", "moveToBeginningOfDocument:": editor.move(-1, edge: true)
		case "moveToEndOfLine:", "moveToEndOfDocument:": editor.move(1, edge: true)
		case "moveToBeginningOfLineAndModifySelection:": editor.move(-1, extending: true, edge: true)
		case "moveToEndOfLineAndModifySelection:": editor.move(1, extending: true, edge: true)
		case "selectAll:": try editor.select(NSRange(location: 0, length: editor.text.utf16.count))
		case "undo:": editor.undo()
		case "redo:": editor.redo()
		case "copy:", "cut:":
			guard !node.style.secure, let range = try? TextIndices.range(utf16: editor.selection, in: editor.text)
			else {
				return
			}

			MacOSDesktopServices.writeClipboard(String(editor.text[range]))
			if command == "cut:" {
				try editor.replace(with: "")
			}
		case "paste:":
			if let text = MacOSDesktopServices.readClipboard() {
				try editor.replace(with: text)
			}
		default: break
		}
	}

	package func receive(_ event: PlatformEvent) {
		switch event {
		case .resize(let size, _):
			document.viewport = size
			document.changed(document.root, .all)
		case .pointer(let phase, let point):
			_ = pointer(phase, at: point)
		case .scroll(let point, let dx, let dy): document.scroll(at: point, dx: dx, dy: dy)
		case .key(let key, let shift, _):
			if key == "\t" || key == "\u{19}" {
				document.focusNext(backward: shift)
			} else if key == " " || key == "\r", let focused = document.focused {
				document.activate(focused)
			}
		case .activate(let id):
			if let node = document.lookup(id) {
				document.activate(node.id)
			}
		case .focus(let id):
			if let node = document.lookup(id) {
				document.setFocus(node.id)
			}
		case .appearance(let dark, let contrast, let motion):
			STNTransaction.perform {
				environment.isDark.value = dark
				environment.highContrast.value = contrast
				environment.reducedMotion.value = motion
			}
		case .surfaceFocus(let focused):
			if !focused {
				document.pointer(.cancel, at: .zero)
				document.setFocus(nil)
			}
		case .deactivated:
			document.pointer(.cancel, at: .zero)
			if let id = document.focused {
				try? editors[id]?.commitComposition()
			}
		case .resourcesChanged(let failed):
			if failed {
				report(.invalidAsset)
			}

			document.changed(document.root, .paint)
		case .modalState(let active):
			if active && !document.root.style.inert {
				modalFocus = document.focused
			}

			document.root.style.inert = active
			if !active {
				if let modalFocus, document.isEligible(modalFocus) {
					document.setFocus(modalFocus)
				}

				self.modalFocus = nil
			}

			document.changed(document.root, [.paint, .semantics])
		case .close: close()
		}
	}
}
