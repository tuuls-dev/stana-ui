import Foundation
import StanaCore
import StanaPrimitives

package struct EditingPaint {
	package let text: String
	package let offset: Double
	package let hasSelection: Bool
	package let caretVisible: Bool
	package let selectionRects: [STNRect]
	package let annotations: [STNRect]
	package let selectionStart: Double
	package let selectionEnd: Double
	package let markedStart: Double?
	package let markedEnd: Double?

	package init(
		text: String,
		offset: Double = 0,
		caretVisible: Bool = true,
		hasSelection: Bool? = nil,
		selectionRects: [STNRect] = [],
		annotations: [STNRect] = [],
		selectionStart: Double,
		selectionEnd: Double,
		markedStart: Double? = nil,
		markedEnd: Double? = nil
	) {
		self.hasSelection = hasSelection ?? (selectionStart != selectionEnd)
		self.caretVisible = caretVisible
		self.selectionRects = selectionRects
		self.annotations = annotations
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
	private var contentVersions: [STNNodeID: RenderVersion] = [:]
	private var previousGeometry: PresentationGeometry?
	private var previousCompositing: [STNNodeID: NodeStyle] = [:]
	private var previousGPU: [STNNodeID: STNGPUDrawing] = [:]
	private var previousBackdrops: [STNNodeID: STNBackdropEffect] = [:]
	private var revision: UInt64 = 0
	private enum ProjectionVisit {
		case enter(NodeRecord, STNRect, Double, Int)
		case leave(NodeRecord, Bool)
	}
	private struct Location {
		let group: STNNodeID
		let index: Int
	}
	private var cpuLocations: [STNNodeID: Location] = [:]
	private var gpuLocations: [STNNodeID: Location] = [:]
	private var groupLocations: [STNNodeID: Location] = [:]
	private var groups: [STNNodeID: PaintGroup] = [:]
	private var groupDepths: [STNNodeID: Int] = [:]
	private var structureRevision: UInt64 = .max
	private var environmentRevision: UInt64 = .max
	package var editing: ((NodeRecord) -> EditingPaint?)?

	package init(document: Document) {
		self.document = document
	}

	private func record(_ node: NodeRecord) -> [DrawCommand] {
		let style = node.style
		let bounds = node.bounds
		let viewport = STNRect(width: document.viewport.width, height: document.viewport.height)
		var local: [DrawCommand] = []
		func color(_ c: STNColor) -> STNColor {
			document.theme?.resolve(c, dark: document.dark)
				?? c.resolved(dark: document.dark, highContrast: document.highContrast)
		}

		if style.background.alpha > 0 {
			local.append(.fill(bounds, color(style.background), radius: style.cornerRadius))
		}

		if node.kind == .root {
			local.append(.fill(viewport, color(document.surfaceBackground), radius: 0))
		}

		if node.kind == .button {
			local.append(
				.fill(
					bounds,
					color(node.kind == .button && document.pressed == node.id ? .border : .surface),
					radius: max(5, style.cornerRadius)
				)
			)
			local.append(.stroke(bounds, color(.border), width: 1, radius: max(5, style.cornerRadius)))
		}

		if style.borderWidth > 0 {
			local.append(
				.stroke(bounds, color(style.borderColor), width: style.borderWidth, radius: style.cornerRadius)
			)
		}

		let inner = bounds.inset(by: style.padding, direction: document.direction)
		let font = STNFont.system(size: style.font.size * document.textScale, weight: style.font.weight)
		if node.kind == .text || node.kind == .button || node.kind == .toggle {
			var textBounds = inner
			if node.kind == .toggle {
				let track = STNRect(
					x: inner.minX,
					y: inner.minY + max(0, (inner.size.height - 18) / 2),
					width: 28,
					height: 18
				)
				local.append(.fill(track, color(node.isOn ? .accent : .border), radius: 9))
				local.append(
					.fill(
						.init(x: track.minX + (node.isOn ? 12 : 2), y: track.minY + 2, width: 14, height: 14),
						.white,
						radius: 7
					)
				)
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
			if document.focused == node.id, let edit, edit.hasSelection {
				let rects =
					edit.selectionRects.isEmpty
					? [STNRect(x: edit.selectionStart, width: edit.selectionEnd - edit.selectionStart)]
					: edit.selectionRects
				for rect in rects {
					local.append(
						.fill(
							.init(
								x: inner.minX + rect.minX - edit.offset,
								y: inner.minY,
								width: rect.size.width,
								height: inner.size.height
							),
							color(style.selectionColor),
							radius: 0
						)
					)
				}
			}

			var textBounds = inner
			textBounds.origin.x -= edit?.offset ?? 0
			textBounds.size.width += edit?.offset ?? 0
			local.append(
				.text(
					shown.isEmpty ? node.placeholder : shown,
					textBounds,
					font,
					color(shown.isEmpty ? style.placeholderColor : style.foreground),
					wraps: false
				)
			)
			if document.focused == node.id, let edit {
				if !edit.hasSelection && edit.caretVisible {
					local.append(
						.fill(
							.init(
								x: inner.minX + edit.selectionEnd - edit.offset,
								y: inner.minY + 1,
								width: 1,
								height: max(0, inner.size.height - 2)
							),
							color(style.caretColor),
							radius: 0
						)
					)
				}

				if let start = edit.markedStart, let end = edit.markedEnd {
					local.append(
						.fill(
							.init(
								x: inner.minX + start - edit.offset,
								y: inner.maxY - 1,
								width: max(1, end - start),
								height: 1
							),
							color(.text),
							radius: 0
						)
					)
				}
			}

			for annotation in edit?.annotations ?? [] {
				local.append(
					.fill(
						.init(
							x: inner.minX + annotation.minX - (edit?.offset ?? 0),
							y: inner.maxY - 2,
							width: annotation.size.width,
							height: 1
						),
						color(.init(red: 0.85, green: 0.15, blue: 0.15)),
						radius: 0
					)
				)
			}

			local.append(.popClip)
		}

		if node.kind == .image, let data = node.imageData {
			local.append(.image(data, inner))
		}

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
		return local
	}

	package func build(surfaceEpoch: UInt64, backingRevision: UInt64, forceFull: Bool = false) -> SceneSnapshot {
		nextRevision(&revision)
		if !forceFull, structureRevision == document.structureRevision,
			environmentRevision == document.environmentRevision,
			let patched = patch(surfaceEpoch: surfaceEpoch, backingRevision: backingRevision)
		{
			return patched
		}
		cpuLocations.removeAll()
		gpuLocations.removeAll()
		groupLocations.removeAll()
		groups.removeAll()
		groupDepths.removeAll()
		var items: [STNNodeID: Item] = [:]
		var order: [STNNodeID] = []
		var commands: [DrawCommand] = []
		var paintStack: [[PaintEntry]] = [[]]
		var groupStack: [STNNodeID] = []
		var damage = DamageTracker()
		let geometry = document.projectGeometry()
		let viewport = STNRect(width: document.viewport.width, height: document.viewport.height)

		var work: [ProjectionVisit] = [.enter(document.root, viewport, 1, 0)]
		while let action = work.popLast() {
			if case .leave(let node, let isolated) = action {
				commands.append(.popOpacity)
				commands.append(.popClip)
				if isolated {
					let children = paintStack.removeLast()
					groupStack.removeLast()
					let style = node.style
					let group = PaintGroup(
						id: node.id,
						bounds: node.bounds,
						transform: style.transform,
						opacity: style.opacity * (style.isEnabled ? 1 : 0.5),
						clips: style.clip || node.kind == .scroll,
						radius: style.cornerRadius,
						backdrop: node.backdropEffect,
						children: children
					)
					groups[node.id] = group
					if let parent = groupStack.last {
						groupLocations[node.id] = Location(group: parent, index: paintStack.last!.count)
					}
					paintStack[paintStack.count - 1].append(.group(group))
				}
				continue
			}
			guard case .enter(let node, let inheritedClip, let inheritedOpacity, let depth) = action else { continue }
			precondition(depth < 512, "Stana: paint depth budget exceeded")
			guard node.style.visibility == .visible else { continue }
			let style = node.style
			let bounds = node.bounds
			let oldStyle = previousCompositing[node.id]
			if oldStyle?.opacity != style.opacity || oldStyle?.transform != style.transform
				|| oldStyle?.clip != style.clip || oldStyle?.cornerRadius != style.cornerRadius
				|| previousGPU[node.id] != node.gpuDrawing || previousBackdrops[node.id] != node.backdropEffect
			{
				damage.add(previousGeometry?.entries[node.id]?.projectedBounds ?? .zero)
				damage.add(geometry.entries[node.id]?.projectedBounds ?? .zero)
			}
			previousCompositing[node.id] = style
			previousGPU[node.id] = node.gpuDrawing
			previousBackdrops[node.id] = node.backdropEffect
			let clip = style.clip || node.kind == .scroll ? inheritedClip.intersection(bounds) : inheritedClip
			let local = record(node)
			let inner = bounds.inset(by: style.padding, direction: document.direction)

			let opacity = style.opacity * (style.isEnabled ? 1 : 0.5)
			// Include inherited compositing state so ancestor opacity/clip changes invalidate descendants.
			let item = Item(commands: local, bounds: bounds)
			items[node.id] = item
			order.append(node.id)
			if previous[node.id] != item {
				damage.add(previous[node.id]?.bounds ?? .zero)
				damage.add(item.bounds)
				document.metrics.recordedPaintItems += 1
				contentVersions[node.id] = RenderVersion()
			}

			let isolated = node.kind == .root || style.retained || opacity != 1 || style.clip || node.kind == .scroll
			if isolated {
				paintStack.append([])
				groupStack.append(node.id)
				groupDepths[node.id] = groupStack.count
			}

			cpuLocations[node.id] = Location(group: groupStack.last!, index: paintStack.last!.count)
			paintStack[paintStack.count - 1]
				.append(.cpu(.init(id: node.id, version: contentVersions[node.id]!, bounds: bounds, commands: local)))

			if node.kind == .gpuCanvas {
				gpuLocations[node.id] = Location(group: groupStack.last!, index: paintStack.last!.count)
				paintStack[paintStack.count - 1]
					.append(
						.gpu(
							.init(
								id: node.id,
								bounds: inner,
								drawing: node.gpuDrawing,
								colors: .init(
									dark: document.dark,
									highContrast: document.highContrast,
									theme: document.theme
								)
							)
						)
					)
			}

			commands.append(.pushClip(clip))
			commands.append(.pushOpacity(opacity))
			commands.append(contentsOf: local)
			work.append(.leave(node, isolated))
			for child in node.children.reversed() {
				work.append(.enter(child, clip, opacity * inheritedOpacity, depth + 1))
			}
		}

		for (id, old) in previous where items[id] == nil {
			damage.add(old.bounds)
		}

		let full = forceFull || previous.isEmpty || backingRevision + 1 != revision || order != previousOrder
		previous = items
		previousOrder = order
		previousGeometry = geometry
		let live = Set(items.keys)
		contentVersions = contentVersions.filter { live.contains($0.key) }
		previousCompositing = previousCompositing.filter { live.contains($0.key) }
		previousGPU = previousGPU.filter { live.contains($0.key) }
		previousBackdrops = previousBackdrops.filter { live.contains($0.key) }
		document.dirty.remove(.paint)
		document.paintChanges.removeAll(keepingCapacity: true)
		structureRevision = document.structureRevision
		environmentRevision = document.environmentRevision
		return .init(
			documentRevision: document.revision,
			sceneRevision: revision,
			surfaceEpoch: surfaceEpoch,
			damageBaseRevision: backingRevision,
			damage: full ? [viewport] : damage.resolved(in: viewport),
			commands: commands,
			size: document.viewport,
			paint: paintStack[0].first.flatMap { if case .group(let group) = $0 { group } else { nil } },
			colorMode: document.renderingColorMode,
			geometry: geometry
		)
	}

	private func patch(surfaceEpoch: UInt64, backingRevision: UInt64) -> SceneSnapshot? {
		guard groups[document.root.id] != nil else { return nil }
		let changes = document.paintChanges
		for (id, _) in changes {
			guard let node = document.nodes[id], cpuLocations[id] != nil,
				previousCompositing[id]?.visibility == node.style.visibility
			else { return nil }
			let opacity = node.style.opacity * (node.style.isEnabled ? 1 : 0.5)
			let isolated =
				node.kind == .root || node.style.retained || opacity != 1 || node.style.clip || node.kind == .scroll
			if isolated != (groups[id] != nil) { return nil }
		}

		var dirtyGroups = Set<STNNodeID>()
		var damage = DamageTracker()
		let geometryChanged = changes.values.contains { $0.contains(.geometry) || $0.contains(.composite) }
		let geometry = geometryChanged ? document.projectGeometry() : previousGeometry ?? document.projectGeometry()
		for (id, change) in changes {
			guard let node = document.nodes[id], let location = cpuLocations[id] else { continue }
			damage.add(previousGeometry?.entries[id]?.projectedBounds ?? .zero)
			damage.add(geometry.entries[id]?.projectedBounds ?? .zero)
			if change.contains(.content) || change.contains(.geometry) {
				let commands = record(node)
				let item = Item(commands: commands, bounds: node.bounds)
				if previous[id] != item {
					contentVersions[id] = RenderVersion()
					previous[id] = item
					document.metrics.recordedPaintItems += 1
				}
				groups[location.group]!.children = groups[location.group]!.children
					.replacing(
						at: location.index,
						with: .cpu(
							.init(id: id, version: contentVersions[id]!, bounds: node.bounds, commands: commands)
						)
					)
				document.metrics.paintIndexUpdates += 1
				if let gpu = gpuLocations[id] {
					groups[gpu.group]!.children = groups[gpu.group]!.children
						.replacing(
							at: gpu.index,
							with: .gpu(
								.init(
									id: id,
									bounds: node.bounds.inset(by: node.style.padding, direction: document.direction),
									drawing: node.gpuDrawing,
									colors: .init(
										dark: document.dark,
										highContrast: document.highContrast,
										theme: document.theme
									)
								)
							)
						)
				}
			}
			if let group = groups[id] {
				groups[id] = group.updating(
					bounds: node.bounds,
					transform: node.style.transform,
					opacity: node.style.opacity * (node.style.isEnabled ? 1 : 0.5),
					clips: node.style.clip || node.kind == .scroll,
					radius: node.style.cornerRadius,
					backdrop: node.backdropEffect
				)
				dirtyGroups.insert(id)
			}
			dirtyGroups.insert(location.group)
			previousCompositing[id] = node.style
			previousGPU[id] = node.gpuDrawing
			previousBackdrops[id] = node.backdropEffect
		}
		var ancestors = Set<STNNodeID>()
		for id in dirtyGroups {
			var current: STNNodeID? = id
			while let next = current {
				if !ancestors.insert(next).inserted { break }
				current = groupLocations[next]?.group
			}
		}
		for id in ancestors.sorted(by: { groupDepths[$0, default: 0] > groupDepths[$1, default: 0] }) {
			if let location = groupLocations[id], let group = groups[id] {
				groups[location.group]!.children = groups[location.group]!.children
					.replacing(at: location.index, with: .group(group))
				document.metrics.paintIndexUpdates += 1
			}
			document.metrics.paintAncestorUpdates += 1
		}
		previousGeometry = geometry
		document.paintChanges.removeAll(keepingCapacity: true)
		document.dirty.remove(.paint)
		let viewport = STNRect(width: document.viewport.width, height: document.viewport.height)
		return .init(
			documentRevision: document.revision,
			sceneRevision: revision,
			surfaceEpoch: surfaceEpoch,
			damageBaseRevision: backingRevision,
			damage: backingRevision + 1 == revision ? damage.resolved(in: viewport) : [viewport],
			commands: [],
			size: document.viewport,
			paint: groups[document.root.id],
			colorMode: document.renderingColorMode,
			geometry: geometry
		)
	}
}
