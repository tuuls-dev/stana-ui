import Stana
import StanaTesting

@MainActor enum UIWorkloads {
	private enum Action: String, CaseIterable {
		case mount = "ui-mount"
		case leaf = "ui-leaf-commit"
		case batch = "ui-batched-commit"
		case equal = "ui-equal-write"
		case reorder = "ui-keyed-reverse"
		case remove = "ui-branch-remove"
		case resize = "ui-resize"
		case close = "ui-close"

		var boundary: String {
			switch self {
			case .mount:
				"Mount N static labels in a stack through complete headless commit; host creation excluded"
			case .leaf:
				"Change one of N bound labels through synchronous headless commit"
			case .batch:
				"Change N independent bound labels in one transaction through synchronous headless commit"
			case .equal:
				"Equal write to one of N bound labels; no-op commit control"
			case .reorder:
				"Reverse N keyed value rows through synchronous headless commit; no descendant remounts"
			case .remove:
				"Remove a composed conditional branch containing N bound labels through cleanup delivery"
			case .resize:
				"Resize an N-label stack from 800x600 to 1024x768 through synchronous headless commit"
			case .close:
				"Close an N-bound-label host, including document removal, binding cancellation and cleanup"
			}
		}
	}

	static var all: [Workload] {
		Action.allCases.map { action in
			Workload(name: action.rawValue, boundary: action.boundary) { size in
				makeTrial(size: size, action: action)
			}
		}
	}

	private static func makeTrial(size: Int, action: Action) -> Trial {
		let host = STNTestHost(size: .init(width: 800, height: 600))
		let signals =
			[Action.leaf, .batch, .equal, .close].contains(action)
			? (0..<size).map { _ in STNSignal("before") } : []
		let rows = STNSignal(action == .reorder ? Array(0..<size) : [])
		let shown = STNSignal(true)
		let branchText = STNSignal("branch")
		var disposals = 0

		func mount() {
			switch action {
			case .reorder:
				host.mount {
					STNVStack {
						STNForEach(rows, id: \.self) { index in
							STNText(properties: .init(text: "row \(index)"))
						}
					}
				}
			case .remove:
				host.mount {
					STNVStack {
						STNIf(shown) {
							for _ in 0..<size {
								BoundLabel(properties: .init(text: branchText, onDispose: { disposals += 1 }))
							}
						}
						STNText(properties: .init(text: "persistent"))
					}
				}
			case .mount, .resize:
				host.mount {
					STNVStack {
						for index in 0..<size {
							STNText(properties: .init(text: "label \(index)"))
						}
					}
				}
			default:
				host.mount {
					STNVStack {
						for signal in signals {
							BoundLabel(properties: .init(text: signal, onDispose: { disposals += 1 }))
						}
					}
				}
			}
		}

		if action != .mount {
			mount()
		}

		let before = host.metrics
		let originalNodes = host.nodes
		let originalIDs = originalNodes.map(\.id)
		let originalLabels = originalNodes.filter { $0.kind == "text" }
		return Trial(
			operation: {
				switch action {
				case .mount:
					mount()
				case .leaf:
					signals[0].value = "after!"
				case .batch:
					STNTransaction.perform {
						for signal in signals {
							signal.value = "after!"
						}
					}
				case .equal:
					signals[0].value = "before"
				case .reorder:
					rows.value.reverse()
				case .remove:
					shown.value = false
				case .resize:
					host.resize(to: .init(width: 1024, height: 768))
				case .close:
					host.close()
				}
			},
			verify: {
				let after = host.metrics
				let nodes = host.nodes
				let labels = nodes.filter { $0.kind == "text" }
				try require(host.errors.isEmpty, "Host reported errors: \(host.errors)")
				switch action {
				case .mount:
					try require(labels.map(\.text) == (0..<size).map { "label \($0)" }, "Mount contents mismatch")
				case .leaf, .batch, .equal:
					try require(nodes.map(\.id) == originalIDs, "Property update changed node identity")
					let changed = action == .batch ? size : (action == .leaf ? 1 : 0)
					try require(
						labels.count == size && labels.filter { $0.text == "after!" }.count == changed,
						"Bound text mismatch"
					)
					try require(after.propertyUpdates - before.propertyUpdates == changed, "Property delivery mismatch")
					try require(
						after.logicalCommits - before.logicalCommits == (action == .equal ? 0 : 1),
						"Unexpected transaction count"
					)
				case .reorder:
					try require(
						labels.map(\.id) == Array(originalLabels.map(\.id).reversed()),
						"Keyed identity/order mismatch"
					)
				case .remove:
					try require(
						labels.map(\.id) == originalLabels.filter { $0.text == "persistent" }.map(\.id),
						"Removal affected persistent sibling"
					)
					try require(disposals == size, "Removed branch did not dispose every component")
					branchText.value = "removed"
					try require(host.metrics.propertyUpdates == after.propertyUpdates, "Removed binding still active")
				case .resize:
					try require(nodes.map(\.id) == originalIDs, "Resize changed node identity")
					try require(nodes.map(\.bounds) != originalNodes.map(\.bounds), "Resize did not change geometry")
					try require(after.logicalCommits == before.logicalCommits + 1, "Resize did not commit once")
				case .close:
					try require(
						nodes.isEmpty && after.mountedNodes == 0 && disposals == size,
						"Close did not release tree"
					)
					signals[0].value = "closed"
					try require(host.metrics.propertyUpdates == after.propertyUpdates, "Closed binding still active")
				}

				if action != .mount && action != .close && action != .remove {
					try require(
						after.totalMounts == before.totalMounts && after.builderExecutions == before.builderExecutions,
						"Unexpected remount or composition"
					)
				}

				return [
					"mounts": after.totalMounts - before.totalMounts,
					"builders": after.builderExecutions - before.builderExecutions,
					"propertyUpdates": after.propertyUpdates - before.propertyUpdates,
					"logicalCommits": after.logicalCommits - before.logicalCommits,
					"measureCalls": after.measureCalls - before.measureCalls,
					"placedNodes": after.placedNodes - before.placedNodes,
					"mountedNodesAfter": after.mountedNodes,
					"disposals": disposals,
				]
			},
			cleanup: { host.close() }
		)
	}
}

@MainActor private struct BoundLabel: STNComponent {
	struct Properties {
		let text: STNSignal<String>
		let onDispose: @MainActor @Sendable () -> Void
	}

	let properties: Properties

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		context.onDispose(properties.onDispose)
		STNText(properties: .init(text: properties.text))
	}
}
