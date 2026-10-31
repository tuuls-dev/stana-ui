import Foundation
import StanaCore
import StanaPlatformMacOS
import StanaPrimitives
import StanaText

@MainActor package struct EditorCallbacks {
	var onMount: ((STNTextFieldHandle) -> Void)?
	var onChange: ((String) -> Void)?
	var onFocusChange: ((Bool) -> Void)?
	var onSelectionChange: ((STNTextSelection) -> Void)?
}

@MainActor package final class EditorState {
	let callbacks: EditorCallbacks
	var options = STNTextField.Options()
	var pendingChange: String?
	var selection: STNTextSelection?
	var focused = false
	var caretVisible = true
	var lastInteraction: Double = 0
	var annotationRanges: [NSRange] = []
	var dragging = false
	var dragAnchor = 0
	var dragUnit = 1
	var dragInitial = NSRange(location: 0, length: 0)
	var dragPoint = STNPoint.zero
	var widthMeasurement: (text: String, font: STNFont, width: Double)?

	init(callbacks: EditorCallbacks) {
		self.callbacks = callbacks
	}
}

extension MountSession {
	package func configureEditor(_ node: NodeRecord, options: STNTextField.Options) {
		if options.isReadOnly && !node.style.isReadOnly {
			editors[node.id]?.cancelComposition()
			discardComposition(for: node.id)
		}

		editorStates[node.id]?.options = options
		node.style.isReadOnly = options.isReadOnly
		switch options.alignment {
		case .leading: node.style.alignment = .leading
		case .center: node.style.alignment = .center
		case .trailing: node.style.alignment = .trailing
		}
		node.style.placeholderColor = options.placeholderColor
		node.style.selectionColor = options.selectionColor
		node.style.caretColor = options.caretColor
	}

	package func discardComposition(for id: STNNodeID) {
		if document.focused == id {
			(window as? MacOSWindow)?.discardMarkedText()
		}
	}

	package func editorResolution(_ id: STNNodeID) -> STNTextField.Resolution {
		guard let node = document.nodes[id], let state = editorStates[id] else {
			return .init(features: [])
		}

		return .init(
			features: STNTextField.TextServiceFeature.allCases.map { feature in
				if node.style.secure || (node.style.isReadOnly && feature != .systemActions) || !document.isEligible(id)
				{
					return .init(feature: feature, availability: .inapplicable, isEnabled: false)
				}

				guard let native = window as? MacOSWindow else {
					return .init(feature: feature, availability: .unavailable, isEnabled: nil)
				}

				let enabled = native.textServiceEnabled(feature.rawValue, policies: state.options.textServices.policies)
				return .init(feature: feature, availability: .supported, isEnabled: enabled)
			}
		)
	}

	package func resetCaret(_ id: STNNodeID) {
		editorStates[id]?.lastInteraction = editorTime
		editorStates[id]?.caretVisible = true
	}

	package func publishEditorEvents() {
		for (id, state) in editorStates {
			guard let node = document.nodes[id], let editor = editors[id], node.scope.isAlive else {
				continue
			}

			let focused = document.focused == id
			let focusChanged = focused != state.focused
			if focusChanged {
				resetCaret(id)
				editor.breakUndoGroup()
				if !focused {
					state.dragging = false
				}
			}

			let selection = try? editor.currentSelection()
			let selectionChanged = state.selection != nil && selection != state.selection
			let change = state.pendingChange
			state.pendingChange = nil
			state.focused = focused
			state.selection = selection
			if change != nil || focusChanged || selectionChanged {
				ReactiveRuntime.shared.afterCommit { [weak node] in
					guard let node, node.scope.isAlive else {
						return
					}

					if let change {
						state.callbacks.onChange?(change)
					}

					if focusChanged && node.scope.isAlive {
						state.callbacks.onFocusChange?(focused)
					}

					if selectionChanged, node.scope.isAlive, let selection {
						state.callbacks.onSelectionChange?(selection)
					}
				}
			}
		}

		let needsTimer =
			document.focused.flatMap { document.nodes[$0] }
			.map {
				editorSurfaceActive
					&& ((!$0.style.isReadOnly && editors[$0.id]?.selection.length == 0)
						|| editorStates[$0.id]?.dragging == true)
					&& document.isEligible($0.id)
			} ?? false
		if needsTimer && window != nil && editorTask == nil {
			editorTask = Task { [weak self] in
				var previous = ContinuousClock.now
				while !Task.isCancelled {
					do {
						try await Task.sleep(for: .milliseconds(50))
					} catch {
						return
					}

					guard let self else {
						return
					}

					let now = ContinuousClock.now
					let elapsed = previous.duration(to: now).components
					previous = now
					self.tickEditors(by: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
				}
			}
		} else if !needsTimer {
			editorTask?.cancel()
			editorTask = nil
		}
	}

	/// Both native scheduling and deterministic test time use this clock.
	package func tickEditors(by seconds: Double) {
		editorTime += seconds
		guard let id = document.focused, let node = document.nodes[id],
			let state = editorStates[id], document.isEligible(id), editorSurfaceActive
		else {
			return
		}

		let interval = (window as? MacOSWindow)?.caretInterval ?? 0.5
		let offInterval = (window as? MacOSWindow)?.caretOffInterval ?? 0.5
		let elapsed = editorTime - state.lastInteraction
		let visible =
			interval <= 0 || offInterval <= 0
			|| elapsed.truncatingRemainder(dividingBy: max(0.01, interval + offInterval)) < interval
		if !node.style.isReadOnly && editors[id]?.selection.length == 0 && state.caretVisible != visible {
			state.caretVisible = visible
			document.changed(node, .paint)
		}

		if state.dragging {
			let inner = node.bounds.inset(by: node.style.padding, direction: document.direction)
			if state.dragPoint.x < inner.minX || state.dragPoint.x > inner.maxX {
				let delta = (state.dragPoint.x < inner.minX ? -240.0 : 240.0) * seconds
				editorOffsets[id] = max(0, (editorOffsets[id] ?? 0) + delta)
				extendEditorDrag(node, state: state)
			}
		}
	}

	package func editorPointer(_ phase: PointerPhase, node: NodeRecord, event: STNPointerEvent) {
		guard node.kind == .textField, let editor = editors[node.id], let state = editorStates[node.id] else {
			return
		}
		let selected = document.interactionGeometry?.entries[node.id]
		guard selected?.textRevision == editor.revision, let inverse = selected?.localToHost.inverse else { return }
		let local = inverse.applying(to: event.position)
		let point = STNPoint(x: node.bounds.minX + local.x, y: node.bounds.minY + local.y)

		if phase == .up || phase == .cancel {
			if phase == .up && !event.isDefaultPrevented && state.dragging {
				state.dragPoint = point
				extendEditorDrag(node, state: state)
			}

			state.dragging = false
			return
		}

		guard !event.isDefaultPrevented, document.isEligible(node.id) else {
			return
		}

		state.dragPoint = point
		if phase == .down {
			let index = editorIndex(node, at: point)
			if event.button != 0 {
				if !NSLocationInRange(index, editor.selection) {
					try? editor.select(NSRange(location: index, length: 0))
				}

				return
			}

			state.dragging = true
			state.dragUnit = event.clickCount >= 3 ? 3 : event.clickCount
			state.dragAnchor = event.shift ? editor.anchor : index
			if state.dragUnit >= 3 {
				state.dragInitial = NSRange(location: 0, length: editor.text.utf16.count)
				try? editor.select(state.dragInitial)
			} else if state.dragUnit == 2 {
				state.dragInitial = text.wordRange(in: editor.text, at: index)
				try? editor.select(state.dragInitial)
			} else {
				try? editor.select(anchor: state.dragAnchor, head: index)
			}

			discardComposition(for: node.id)
		} else if state.dragging {
			extendEditorDrag(node, state: state)
		}
	}

	package func moveEditorVisually(
		_ direction: Int,
		extending: Bool = false,
		word: Bool = false,
		editor: TextBuffer,
		node: NodeRecord
	) throws {
		try editor.commitComposition()
		let shown = node.style.secure ? String(repeating: "•", count: editor.text.utf16.count) : editor.text
		let font = STNFont.system(size: node.style.font.size * document.textScale, weight: node.style.font.weight)
		if editor.selection.length > 0 && !extending && !word {
			let a = editor.selection.location
			let b = NSMaxRange(editor.selection)
			let first = text.offset(in: shown, utf16Index: a, font: font)
			let last = text.offset(in: shown, utf16Index: b, font: font)
			let target = (direction < 0) == (first <= last) ? a : b
			try editor.select(NSRange(location: target, length: 0))
			return
		}

		let neighbor = TextBoundaries.snap(
			text.visualIndex(in: shown, from: editor.head, direction: direction, font: font, boundaryText: editor.text),
			in: editor.text
		)
		if word && neighbor != editor.head {
			editor.move(neighbor < editor.head ? -1 : 1, extending: extending, word: true)
		} else {
			try editor.select(anchor: extending ? editor.anchor : neighbor, head: neighbor)
		}
	}

	private func editorIndex(_ node: NodeRecord, at point: STNPoint) -> Int {
		guard let editor = editors[node.id] else {
			return 0
		}

		let paint = editingPaint(node, ensureCaret: false)
		let shown = node.style.secure ? String(repeating: "•", count: editor.text.utf16.count) : editor.text
		let font = STNFont.system(size: node.style.font.size * document.textScale, weight: node.style.font.weight)
		let inner = node.bounds.inset(by: node.style.padding, direction: document.direction)
		let x = point.x - inner.minX + (paint?.offset ?? 0)
		return TextBoundaries.snap(text.index(in: shown, x: x, font: font), in: editor.text)
	}

	private func extendEditorDrag(_ node: NodeRecord, state: EditorState) {
		guard let editor = editors[node.id] else {
			return
		}

		let index = editorIndex(node, at: state.dragPoint)
		if state.dragUnit >= 3 {
			return
		}

		if state.dragUnit == 2 {
			let range = text.wordRange(in: editor.text, at: index)
			let backwards = index < state.dragInitial.location
			try? editor.select(
				anchor: backwards ? NSMaxRange(state.dragInitial) : state.dragInitial.location,
				head: backwards ? range.location : NSMaxRange(range)
			)
		} else {
			try? editor.select(anchor: state.dragAnchor, head: index)
		}
	}
}
