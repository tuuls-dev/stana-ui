import Foundation

/// An immutable balanced ordered sequence. Replacing one item shares untouched
/// branches rather than copying a containing group's complete sibling array.
package struct PaintSequence: Equatable, Sendable, Sequence {
	package final class Branch: Sendable {
		package let version = UUID()
		package let left: Branch?
		package let right: Branch?
		package let entry: PaintEntry
		package let count: Int
		package let requiresExtended: Bool

		package init(left: Branch?, entry: PaintEntry, right: Branch?) {
			self.left = left
			self.entry = entry
			self.right = right
			count = 1 + (left?.count ?? 0) + (right?.count ?? 0)
			requiresExtended =
				entry.requiresExtended || left?.requiresExtended == true || right?.requiresExtended == true
		}

		func replacing(_ index: Int, with entry: PaintEntry) -> Branch {
			let leftCount = left?.count ?? 0
			if index < leftCount {
				return Branch(left: left!.replacing(index, with: entry), entry: self.entry, right: right)
			}
			if index == leftCount { return Branch(left: left, entry: entry, right: right) }
			return Branch(left: left, entry: self.entry, right: right!.replacing(index - leftCount - 1, with: entry))
		}
	}

	package let root: Branch?
	package var count: Int { root?.count ?? 0 }
	package var requiresExtended: Bool { root?.requiresExtended ?? false }

	package init(_ entries: [PaintEntry]) {
		func build(_ range: Range<Int>) -> Branch? {
			guard !range.isEmpty else { return nil }
			let middle = range.lowerBound + range.count / 2
			return Branch(
				left: build(range.lowerBound..<middle),
				entry: entries[middle],
				right: build((middle + 1)..<range.upperBound)
			)
		}
		root = build(entries.indices)
	}

	private init(root: Branch?) { self.root = root }

	package func replacing(at index: Int, with entry: PaintEntry) -> Self {
		precondition(index >= 0 && index < count)
		return Self(root: root!.replacing(index, with: entry))
	}

	package static func == (lhs: Self, rhs: Self) -> Bool { lhs.root?.version == rhs.root?.version }

	package struct Iterator: IteratorProtocol {
		private var stack: [Branch] = []

		init(_ root: Branch?) { descend(root) }

		private mutating func descend(_ root: Branch?) {
			var node = root
			while let current = node { stack.append(current); node = current.left }
		}

		package mutating func next() -> PaintEntry? {
			guard let node = stack.popLast() else { return nil }
			descend(node.right)
			return node.entry
		}
	}

	package func makeIterator() -> Iterator { Iterator(root) }
}
