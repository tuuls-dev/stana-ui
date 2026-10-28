import StanaPrimitives

extension Document {
	package func projectGeometry() -> PresentationGeometry {
		var entries: [STNNodeID: GeometryEntry] = [:]
		var order: [STNNodeID] = []
		func visit(_ node: NodeRecord, parent: STNAffineTransform, clips: [GeometryClip], depth: Int) {
			precondition(depth < 512, "Stana: presentation geometry depth budget exceeded")
			guard node.style.visibility == .visible else { return }
			let origin = STNAffineTransform.translation(x: node.bounds.minX, y: node.bounds.minY)
			let anchored = origin.concatenating(node.style.transform)
				.concatenating(.translation(x: -node.bounds.minX, y: -node.bounds.minY))
			let transform = parent.concatenating(anchored)
			let local = transform.concatenating(origin)
			var childClips = clips
			if node.style.clip || node.kind == .scroll {
				childClips.append(
					.init(
						rect: .init(width: node.bounds.size.width, height: node.bounds.size.height),
						localToHost: local,
						radius: node.style.cornerRadius
					)
				)
			}

			entries[node.id] = .init(
				id: node.id,
				layoutBounds: node.bounds,
				localToHost: local,
				clips: childClips,
				textRevision: node.textGeometryRevision
			)
			order.append(node.id)
			for child in node.children { visit(child, parent: transform, clips: childClips, depth: depth + 1) }
		}

		visit(
			root,
			parent: .identity,
			clips: [
				.init(
					rect: .init(width: viewport.width, height: viewport.height),
					localToHost: .identity,
					radius: 0
				)
			],
			depth: 0
		)
		return .init(revision: revision, order: order, entries: entries)
	}

	package var interactionGeometry: PresentationGeometry? {
		usesPresentationGeometry ? confirmedGeometry : projectGeometry()
	}

	package func allowsLocation(_ point: STNPoint) -> Bool {
		!ambiguousGeometryRegions.contains { $0.contains(point) }
	}

	package func pointerEligible(_ id: STNNodeID) -> Bool {
		guard var node = nodes[id], node.scope.isAlive else { return false }
		while true {
			if node.style.visibility != .visible || !node.style.isEnabled || node.style.inert { return false }
			guard let parent = node.parent else { return true }
			node = parent
		}
	}

	package func publishPresentation(_ geometry: PresentationGeometry, confirmed: Bool, preserveAmbiguity: Bool = false)
	{
		if confirmed {
			if confirmedGeometry.map({ $0.revision > geometry.revision }) ?? false { return }
			if preserveAmbiguity {
				mergeAmbiguity(from: confirmedGeometry, to: geometry)
				presentationAcknowledgement = .unknown
			}
			confirmedGeometry = geometry
			if !preserveAmbiguity {
				presentationAcknowledgement = .confirmed
				ambiguousGeometryRegions.removeAll()
			}
			if let captured, geometry.entries[captured]?.localToHost.inverse == nil { self.captured = nil }
		} else {
			presentationAcknowledgement = .unknown
			mergeAmbiguity(from: confirmedGeometry, to: geometry)
		}
	}

	private func mergeAmbiguity(from previous: PresentationGeometry?, to next: PresentationGeometry) {
		let old = previous?.entries ?? [:]
		for id in Set(old.keys).union(next.entries.keys) where old[id] != next.entries[id] {
			if let bounds = old[id]?.projectedBounds { ambiguousGeometryRegions.append(bounds) }
			if let bounds = next.entries[id]?.projectedBounds { ambiguousGeometryRegions.append(bounds) }
		}

		// Returning to the last-known position does not prove an earlier unknown
		// attempt was never displayed. Keep the union until a newer confirmation
		// covers every ambiguous attempt; coalesce conservatively to bound memory.
		if ambiguousGeometryRegions.count > 256 {
			ambiguousGeometryRegions = [ambiguousGeometryRegions.reduce(.zero) { $0.union($1) }]
		}
	}
}
