import Foundation
import StanaCore
import StanaText

/// A lifetime-checked handle to a retained single-line editor.
@MainActor public struct STNTextFieldHandle {
	private weak var session: MountSession?
	public let id: STNNodeID

	package init(session: MountSession, id: STNNodeID) {
		self.session = session
		self.id = id
	}

	private func resolve() throws -> MountSession {
		guard let session else {
			throw STNError.nodeDisposed
		}

		_ = try session.document.resolve(id)
		return session
	}

	public func requestFocus() throws {
		let session = try resolve()
		guard session.document.isEligible(id) else {
			throw STNError.notFocusable
		}

		session.document.setFocus(id)
	}

	public func resignFocus() throws {
		let session = try resolve()
		if session.document.focused == id {
			session.document.setFocus(nil)
		}
	}

	/// Positions refer to committed text. Marked text is not part of this selection.
	public func selection() throws -> STNTextSelection {
		let session = try resolve()
		return try session.editors[id]!.currentSelection()
	}

	/// A valid explicit selection cancels composition; stale positions never do.
	public func setSelection(_ selection: STNTextSelection) throws {
		let session = try resolve()
		try session.editors[id]!.setSelection(selection)
		session.discardComposition(for: id)
	}

	public func selectAll() throws {
		let session = try resolve()
		let editor = session.editors[id]!
		try editor.select(NSRange(location: 0, length: editor.text.utf16.count))
		session.discardComposition(for: id)
	}

	public func resolution() throws -> STNTextField.Resolution {
		try resolve().editorResolution(id)
	}
}
