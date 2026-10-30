import Foundation
import StanaPrimitives
import StanaScene

/// Share CPU subtrees; materialize commands only for dirty tiles.
final class CPUCommandTree: Sendable {
	enum Storage: Sendable {
		case branch(PlannedBranch)

		case leaf(PaintCPUItem)

		case concat(CPUCommandTree, CPUCommandTree)
	}

	let storage: Storage
	let bounds: CGRect
	let firstID: STNNodeID

	init(branch: PlannedBranch) {
		precondition(branch.allCPU)
		storage = .branch(branch)
		bounds = branch.bounds.cgRect
		firstID = branch.firstID
	}

	init(leaf: PaintCPUItem) {
		storage = .leaf(leaf)
		bounds = leaf.bounds.cgRect
		firstID = leaf.id
	}

	init(_ left: CPUCommandTree, _ right: CPUCommandTree) {
		storage = .concat(left, right)
		bounds = left.bounds.union(right.bounds)
		firstID = left.firstID
	}

	func versions(intersecting rect: CGRect) -> [RenderVersion] {
		var result: [RenderVersion] = []
		appendVersions(intersecting: rect, to: &result)
		return result
	}

	private func appendVersions(intersecting rect: CGRect, to result: inout [RenderVersion]) {
		guard bounds.intersects(rect) else {
			return
		}

		switch storage {
		case .leaf(let item):
			if !item.commands.isEmpty {
				result.append(item.version)
			}
		case .branch(let branch): Self.appendBranchVersions(branch, rect: rect, result: &result)
		case .concat(let left, let right):
			left.appendVersions(intersecting: rect, to: &result)
			right.appendVersions(intersecting: rect, to: &result)
		}
	}

	private static func appendBranchVersions(_ branch: PlannedBranch?, rect: CGRect, result: inout [RenderVersion]) {
		guard let branch, branch.bounds.cgRect.intersects(rect) else {
			return
		}

		if rect.contains(branch.bounds.cgRect) {
			result.append(branch.source.version)
			return
		}

		appendBranchVersions(branch.left, rect: rect, result: &result)
		if case .cpu(let item) = branch.entry, !item.commands.isEmpty, item.bounds.cgRect.intersects(rect) {
			result.append(item.version)
		}

		appendBranchVersions(branch.right, rect: rect, result: &result)
	}

	func commands(intersecting rect: CGRect) -> [DrawCommand] {
		var result: [DrawCommand] = []
		appendCommands(intersecting: rect, to: &result)
		return result
	}

	private func appendCommands(intersecting rect: CGRect, to result: inout [DrawCommand]) {
		guard bounds.intersects(rect) else {
			return
		}

		switch storage {
		case .leaf(let item): result.append(contentsOf: item.commands)
		case .branch(let branch): Self.appendBranchCommands(branch, rect: rect, result: &result)
		case .concat(let left, let right):
			left.appendCommands(intersecting: rect, to: &result)
			right.appendCommands(intersecting: rect, to: &result)
		}
	}

	private static func appendBranchCommands(_ branch: PlannedBranch?, rect: CGRect, result: inout [DrawCommand]) {
		guard let branch, branch.bounds.cgRect.intersects(rect) else {
			return
		}

		appendBranchCommands(branch.left, rect: rect, result: &result)
		if case .cpu(let item) = branch.entry, item.bounds.cgRect.intersects(rect) {
			result.append(contentsOf: item.commands)
		}

		appendBranchCommands(branch.right, rect: rect, result: &result)
	}
}
