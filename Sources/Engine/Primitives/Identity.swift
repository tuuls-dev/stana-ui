import Foundation

public struct STNNodeID: Hashable, Sendable, CustomStringConvertible {
	package let document: DocumentID
	package let serial: UInt64

	package init(document: DocumentID, serial: UInt64) {
		self.document = document
		self.serial = serial
	}

	public var description: String {
		"node:\(serial)"
	}

	package var nativeID: UInt64 {
		serial
	}
}

/// Accessibility identity is a separate namespace, even when one node currently
/// projects to one semantic element. Fragment allocation remains engine-owned.
public struct STNSemanticID: Hashable, Sendable, CustomStringConvertible {
	package let owner: STNNodeID
	package let fragment: UInt32

	package init(owner: STNNodeID, fragment: UInt32 = 0) {
		self.owner = owner
		self.fragment = fragment
	}

	package var nativeID: UInt64 {
		owner.nativeID
	}

	public var description: String {
		"semantic:\(owner.serial):\(fragment)"
	}
}

public enum STNError: Error, Equatable, Sendable {
	case nodeDisposed, notFocusable, transactionInProgress, wrongDocument, invalidStructure
	case duplicateKey, rowIdentityChanged, staleTextPosition, invalidTextRange
	case unsupportedPlatform, invalidAsset, cancelled
	case nativeFailure(String)
}

package func nextRevision(_ revision: inout UInt64) {
	guard revision < .max else {
		fatalError("Stana: revision namespace exhausted")
	}

	revision += 1
}
