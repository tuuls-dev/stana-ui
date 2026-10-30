import Foundation
import StanaPrimitives
import StanaScene

final class PlannedBranch: Sendable {
	let source: PaintSequence.Branch
	let left: PlannedBranch?
	let entry: PlannedEntry
	let right: PlannedBranch?
	let bounds: STNRect
	let allCPU: Bool
	let firstID: STNNodeID

	init(source: PaintSequence.Branch, left: PlannedBranch?, entry: PlannedEntry, right: PlannedBranch?) {
		self.source = source
		self.left = left
		self.entry = entry
		self.right = right
		allCPU = (left?.allCPU ?? true) && entry.isCPU && (right?.allCPU ?? true)
		firstID = left?.firstID ?? entry.id
		var bounds = entry.projectedBounds.cgRect
		if let left {
			bounds = bounds.union(left.bounds.cgRect)
		}

		if let right {
			bounds = bounds.union(right.bounds.cgRect)
		}

		self.bounds = bounds.stana
	}

	struct Iterator {
		private var stack: [PlannedBranch] = []
		private let reversed: Bool

		init(_ root: PlannedBranch?, reversed: Bool = false) {
			self.reversed = reversed
			descend(root)
		}

		private mutating func descend(_ root: PlannedBranch?) {
			var node = root
			while let current = node {
				stack.append(current)
				node = reversed ? current.right : current.left
			}
		}

		mutating func next() -> PlannedEntry? {
			guard let node = stack.popLast() else {
				return nil
			}

			descend(reversed ? node.left : node.right)
			return node.entry
		}
	}

	func visit(_ body: (PlannedEntry) throws -> Void) rethrows {
		try left?.visit(body)
		try body(entry)
		try right?.visit(body)
	}
}

final class PlannedGroup: Sendable {
	let source: PaintGroup
	let children: PlannedBranch?
	let bounds: STNRect

	init(source: PaintGroup, children: PlannedBranch?) {
		self.source = source
		self.children = children
		bounds =
			!source.clips && children != nil
			? source.bounds.cgRect.union(children!.bounds.cgRect).stana : source.bounds
	}
}

enum PlannedEntry: Sendable {
	case cpu(PaintCPUItem)

	case gpu(PaintGPUItem)

	case group(PlannedGroup)

	var isCPU: Bool {
		if case .cpu = self {
			return true
		}

		return false
	}

	var id: STNNodeID {
		switch self {
		case .cpu(let item): item.id
		case .gpu(let item): item.id
		case .group(let group): group.source.id
		}
	}

	var projectedBounds: STNRect {
		switch self {
		case .cpu(let item): item.bounds
		case .gpu(let item): item.bounds
		case .group(let group): group.source.anchoredTransform.enclosing(group.bounds)
		}
	}
}

extension PaintGroup {
	var anchoredTransform: STNAffineTransform {
		STNAffineTransform.translation(x: bounds.minX, y: bounds.minY)
			.concatenating(transform)
			.concatenating(.translation(x: -bounds.minX, y: -bounds.minY))
	}
}

/// Packets own plans; the render owner keeps only weak indexes.
struct ScenePlanner {
	private final class WeakBranch {
		weak var value: PlannedBranch?

		init(_ value: PlannedBranch) {
			self.value = value
		}
	}

	private final class WeakGroup {
		weak var value: PlannedGroup?

		init(_ value: PlannedGroup) {
			self.value = value
		}
	}

	private var branches: [RenderVersion: WeakBranch] = [:]
	private var groups: [RenderVersion: WeakGroup] = [:]
	private var branchKeys: [RenderVersion] = []
	private var groupKeys: [RenderVersion] = []
	private var branchCursor = 0
	private var groupCursor = 0
	private var createdGroups = 0
	private(set) var visitedBranches = 0
	private(set) var createdBranches = 0

	mutating func prepare(_ group: PaintGroup) -> PlannedGroup {
		visitedBranches = 0
		createdBranches = 0
		createdGroups = 0
		return prepareGroup(group)
	}

	private mutating func prepareGroup(_ group: PaintGroup) -> PlannedGroup {
		if let cached = groups[group.version]?.value {
			return cached
		}

		let plan = PlannedGroup(source: group, children: prepareBranch(group.children.root))
		if groups[group.version] == nil {
			groupKeys.append(group.version)
		}

		groups[group.version] = WeakGroup(plan)
		createdGroups += 1
		return plan
	}

	private mutating func prepareBranch(_ branch: PaintSequence.Branch?) -> PlannedBranch? {
		guard let branch else {
			return nil
		}

		visitedBranches += 1
		if let cached = branches[branch.version]?.value {
			return cached
		}

		let left = prepareBranch(branch.left)
		let right = prepareBranch(branch.right)
		let entry: PlannedEntry
		switch branch.entry {
		case .cpu(let item): entry = .cpu(item)
		case .gpu(let item): entry = .gpu(item)
		case .group(let group): entry = .group(prepareGroup(group))
		}

		let plan = PlannedBranch(source: branch, left: left, entry: entry, right: right)
		if branches[branch.version] == nil {
			branchKeys.append(branch.version)
		}

		branches[branch.version] = WeakBranch(plan)
		createdBranches += 1
		return plan
	}

	mutating func prune() {
		// Bound cleanup so a leaf edit cannot trigger a full-tree scan.
		for _ in 0..<max(64, createdBranches * 2) where !branchKeys.isEmpty {
			branchCursor %= branchKeys.count
			let key = branchKeys[branchCursor]
			if branches[key]?.value == nil {
				branches.removeValue(forKey: key)
				branchKeys.swapAt(branchCursor, branchKeys.count - 1)
				branchKeys.removeLast()
			} else {
				branchCursor += 1
			}
		}

		for _ in 0..<max(16, createdGroups * 2) where !groupKeys.isEmpty {
			groupCursor %= groupKeys.count
			let key = groupKeys[groupCursor]
			if groups[key]?.value == nil {
				groups.removeValue(forKey: key)
				groupKeys.swapAt(groupCursor, groupKeys.count - 1)
				groupKeys.removeLast()
			} else {
				groupCursor += 1
			}
		}
	}
}
