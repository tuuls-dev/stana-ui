import Foundation
import StanaCore
import StanaPrimitives
import StanaText

@MainActor package final class LayoutEngine {
	package let document: Document
	package let text: any TextService
	package var useCache = true

	package init(document: Document, text: any TextService) {
		self.document = document
		self.text = text
	}

	package func layout() {
		guard document.dirty.contains(.layout) else {
			return
		}

		let size = document.viewport
		document.withTiming(.layoutMeasurement) {
			_ = measure(
				document.root,
				under: .init(minWidth: size.width, maxWidth: size.width, minHeight: size.height, maxHeight: size.height)
			)
		}
		document.withTiming(.layoutPlacement) {
			place(document.root, in: .init(width: size.width, height: size.height))
		}
		document.dirty.remove(.layout)
	}

	package func arrangedChildren(_ node: NodeRecord) -> [NodeRecord] {
		node.children.flatMap { child -> [NodeRecord] in
			if document.layoutCountersEnabled {
				document.metrics.arrangedChildVisits += 1
			}
			if child.style.visibility == .collapsed {
				return []
			}

			return child.kind == .group ? arrangedChildren(child) : [child]
		}
	}

	private func effective(_ outer: STNConstraints, _ frame: STNFrame) -> STNConstraints {
		let maxW = frame.width ?? max(frame.minWidth, min(frame.maxWidth, outer.maxWidth))
		let maxH = frame.height ?? max(frame.minHeight, min(frame.maxHeight, outer.maxHeight))
		return .init(
			minWidth: min(maxW, frame.width ?? max(frame.minWidth, outer.minWidth)),
			maxWidth: maxW,
			minHeight: min(maxH, frame.height ?? max(frame.minHeight, outer.minHeight)),
			maxHeight: maxH
		)
	}

	package func measure(_ node: NodeRecord, under outer: STNConstraints, depth: Int = 0) -> STNSize {
		if document.layoutCountersEnabled {
			document.metrics.measureVisits += 1
		}
		precondition(depth < 512, "Stana: layout depth budget exceeded")
		if node.style.visibility == .collapsed {
			node.measured = .zero
			node.baseline = nil
			return .zero
		}

		if useCache, let size = node.measureCache[AnyHashable(outer)] {
			if document.layoutCountersEnabled {
				document.metrics.measureCacheHits += 1
			}
			node.measured = size
			refreshArrangementBaselines(node)
			return node.measured
		}

		let oldSize = node.measured
		let oldBaseline = node.baseline
		let oldContentSize = node.contentSize
		node.baseline = nil
		document.metrics.measureCalls += 1
		nextRevision(&node.measureVersion)
		let c = effective(outer, node.style.frame)
		let p = node.style.padding
		let inner = STNConstraints(
			maxWidth: max(0, c.maxWidth - p.horizontal),
			maxHeight: max(0, c.maxHeight - p.vertical)
		)
		let children = arrangedChildren(node)
		var intrinsic = STNSize.zero
		switch node.kind {
		case .text, .button, .toggle, .textField:
			let content =
				node.kind == .textField
				? (node.text.isEmpty
					? node.placeholder
					: node.style.secure ? String(repeating: "•", count: node.text.utf16.count) : node.text) : node.text
			if document.layoutCountersEnabled {
				document.metrics.textMeasureCalls += 1
			}
			let measured = text.measure(
				content,
				font: .system(size: node.style.font.size * document.textScale, weight: node.style.font.weight),
				maxWidth: max(0, inner.maxWidth - (node.kind == .toggle ? 36 : 0)),
				wraps: node.kind == .text
			)
			node.baseline = measured.baseline + p.top
			intrinsic = measured.size
			if node.kind == .toggle {
				intrinsic.width += 36
			}

			if node.kind == .textField {
				intrinsic.width = max(160, intrinsic.width)
				intrinsic.height = max(20, intrinsic.height)
			}
		case .spacer: break
		case .image: intrinsic = .init(width: 64, height: 64)
		case .canvas, .gpuCanvas: intrinsic = .init(width: 100, height: 100)
		case .hStack, .vStack:
			let horizontal = node.kind == .hStack
			let maxMain = horizontal ? inner.maxWidth : inner.maxHeight
			let gap = node.style.spacing * Double(max(0, children.count - 1))
			var main = gap
			var cross: Double = 0

			func weight(_ child: NodeRecord) -> Double {
				max(
					child.style.flex,
					(horizontal ? child.style.frame.fillsWidth : child.style.frame.fillsHeight) ? 1 : 0
				)
			}

			let fixed = children.filter { weight($0) == 0 }
			let flexible = children.filter { weight($0) > 0 }
			for child in fixed {
				let childC =
					horizontal
					? STNConstraints(maxWidth: .infinity, maxHeight: inner.maxHeight)
					: STNConstraints(maxWidth: inner.maxWidth)
				let s = measure(child, under: childC, depth: depth + 1)
				main += horizontal ? s.width : s.height
				cross = max(cross, horizontal ? s.height : s.width)
			}

			if !maxMain.isFinite {
				// Fill consumes finite space only. On an unbounded axis, preserve
				// intrinsic content and let each child's own frame constrain it.
				let proposal =
					horizontal
					? STNConstraints(maxHeight: inner.maxHeight)
					: STNConstraints(maxWidth: inner.maxWidth)
				for child in flexible {
					let size = measure(child, under: proposal, depth: depth + 1)
					main += horizontal ? size.width : size.height
					cross = max(cross, horizontal ? size.height : size.width)
				}
			} else {
				var remaining = max(0, maxMain - main)
				var unsettled = flexible
				var allocations: [STNNodeID: Double] = [:]
				while !unsettled.isEmpty {
					if document.layoutCountersEnabled {
						document.metrics.flexDistributionRounds += 1
					}
					let largestWeight = unsettled.map(weight).max() ?? 1
					let totalWeight = unsettled.reduce(0) { $0 + weight($1) / largestWeight }
					var minima: [NodeRecord] = []
					var maxima: [NodeRecord] = []
					var sum = 0.0
					for child in unsettled {
						let f = child.style.frame
						let minV = horizontal ? (f.width ?? f.minWidth) : (f.height ?? f.minHeight)
						let maxV = horizontal ? (f.width ?? f.maxWidth) : (f.height ?? f.maxHeight)
						let share = remaining * (weight(child) / largestWeight / totalWeight)
						let allocation = min(maxV, max(minV, share))
						allocations[child.id] = allocation
						sum += allocation
						if share < minV {
							minima.append(child)
						}

						if share > maxV {
							maxima.append(child)
						}
					}

					if abs(sum - remaining) < 0.000_001 {
						break
					}

					// Freeze only the constraints on the side containing the solution.
					// Freezing minima and maxima together can strand distributable space.
					let settled = sum > remaining ? minima : maxima
					if settled.isEmpty {
						break
					}

					for child in settled {
						remaining = max(0, remaining - (allocations[child.id] ?? 0))
					}

					let ids = Set(settled.map(\.id))
					unsettled.removeAll { ids.contains($0.id) }
				}

				for child in flexible {
					let allocation = allocations[child.id] ?? 0
					let c =
						horizontal
						? STNConstraints(minWidth: allocation, maxWidth: allocation, maxHeight: inner.maxHeight)
						: STNConstraints(maxWidth: inner.maxWidth, minHeight: allocation, maxHeight: allocation)
					let s = measure(child, under: c, depth: depth + 1)
					main += horizontal ? s.width : s.height
					cross = max(cross, horizontal ? s.height : s.width)
				}
			}

			// Flexible text must be measured before aggregating baseline ascent/descent.
			if horizontal && node.style.alignment == .firstBaseline {
				cross =
					commonBaseline(children)
					+ (children.map { max(0, $0.measured.height - alignmentBaseline($0)) }.max() ?? 0)
			}

			intrinsic = horizontal ? .init(width: main, height: cross) : .init(width: cross, height: main)
		case .scroll:
			for child in children {
				let size = measure(child, under: .init(maxWidth: inner.maxWidth), depth: depth + 1)
				intrinsic.width = max(intrinsic.width, size.width)
				intrinsic.height = max(intrinsic.height, size.height)
			}

			node.contentSize = intrinsic
			intrinsic = .init(
				width: inner.maxWidth.isFinite ? inner.maxWidth : intrinsic.width,
				height: inner.maxHeight.isFinite ? inner.maxHeight : min(intrinsic.height, 300)
			)
		default:
			for child in children {
				let size = measure(child, under: inner, depth: depth + 1)
				intrinsic.width = max(intrinsic.width, size.width)
				intrinsic.height = max(intrinsic.height, size.height)
			}
		}

		// An explicitly unbounded max frame is the fill signal on bounded axes.
		if node.style.frame.fillsWidth, c.maxWidth.isFinite {
			intrinsic.width = max(0, c.maxWidth - p.horizontal)
		}

		if node.style.frame.fillsHeight, c.maxHeight.isFinite {
			intrinsic.height = max(0, c.maxHeight - p.vertical)
		}

		let result = c.clamp(.init(width: intrinsic.width + p.horizontal, height: intrinsic.height + p.vertical))
		node.measured = result
		if node.kind == .scroll {
			// Range normalization needs the final constrained viewport, not its proposal.
			node.scrollOffset = node.normalizedScrollOffset(node.scrollOffset, in: result)
		}

		updateContainerBaseline(node, children: children)
		node.baselineArrangementVersion = node.arrangementVersion

		if document.layoutCountersEnabled,
			oldSize != result || oldBaseline != node.baseline || oldContentSize != node.contentSize
		{
			document.metrics.layoutOutputChanges += 1
		}

		// A size-only cache cannot restore child proposals from an older pass.
		// Keep the current proposal only until full placement plans are cached.
		node.measureCache.removeAll(keepingCapacity: true)
		if useCache {
			node.measureCache[AnyHashable(outer)] = result
		}

		return result
	}

	/// Exported baselines include local placement (notably scroll offsets), but
	/// refreshing them must not discard text measurements or child proposals.
	private func refreshArrangementBaselines(_ node: NodeRecord) {
		guard node.baselineArrangementVersion != node.arrangementVersion else {
			return
		}

		let children = arrangedChildren(node)
		var sizingChanged = false
		for child in children {
			let oldSize = child.measured
			let oldBaseline = child.baseline
			refreshArrangementBaselines(child)
			if child.measured != oldSize
				|| (node.kind == .hStack && node.style.alignment == .firstBaseline && child.baseline != oldBaseline)
			{
				sizingChanged = true
			}
		}

		if sizingChanged, let proposal = node.measureCache.keys.first?.base as? STNConstraints {
			// A moving exported baseline can change a baseline row's intrinsic
			// height. Recompute dependent container sizing, retaining leaf caches.
			node.measureCache.removeAll(keepingCapacity: true)
			_ = measure(node, under: proposal)
			return
		}

		let old = node.baseline
		if node.kind == .scroll {
			node.scrollOffset = node.normalizedScrollOffset(node.scrollOffset, in: node.measured)
		}

		updateContainerBaseline(node, children: children)
		node.baselineArrangementVersion = node.arrangementVersion
		if document.layoutCountersEnabled, old != node.baseline {
			document.metrics.layoutOutputChanges += 1
		}
	}

	private func updateContainerBaseline(_ node: NodeRecord, children: [NodeRecord]) {
		switch node.kind {
		case .text, .button, .toggle, .textField:
			return
		default:
			break
		}

		node.baseline = nil
		if node.kind == .hStack && node.style.alignment == .firstBaseline {
			node.baseline = children.isEmpty ? nil : node.style.padding.top + commonBaseline(children)
		} else {
			arrange(node, children: children, in: .init(width: node.measured.width, height: node.measured.height)) {
				child,
				rect in
				if node.baseline == nil, let baseline = child.baseline {
					node.baseline = rect.minY + baseline
				}
			}
		}
	}

	private func alignmentBaseline(_ child: NodeRecord) -> Double {
		child.baseline ?? max(0, child.measured.height - child.style.padding.bottom)
	}

	private func commonBaseline(_ children: [NodeRecord]) -> Double {
		children.map(alignmentBaseline).max() ?? 0
	}

	package func place(_ node: NodeRecord, in bounds: STNRect) {
		if document.layoutCountersEnabled {
			document.metrics.placementVisits += 1
		}
		if node.bounds == bounds && node.placedMeasureVersion == node.measureVersion
			&& node.placedArrangementVersion == node.arrangementVersion
		{
			return
		}

		node.placedMeasureVersion = node.measureVersion
		node.placedArrangementVersion = node.arrangementVersion
		document.metrics.placedNodes += 1
		node.bounds = bounds
		if node.kind == .scroll {
			node.scrollOffset = node.normalizedScrollOffset(node.scrollOffset)
		}

		arrange(node, children: arrangedChildren(node), in: bounds) { child, rect in
			place(child, in: rect)
		}
	}

	/// Shared local placement rules also determine a container's exported baseline.
	private func arrange(
		_ node: NodeRecord,
		children: [NodeRecord],
		in bounds: STNRect,
		_ apply: (NodeRecord, STNRect) -> Void
	) {
		let inner = bounds.inset(by: node.style.padding, direction: document.direction)
		if node.kind == .hStack || node.kind == .vStack {
			let horizontal = node.kind == .hStack
			let rtl = horizontal && document.direction == .rightToLeft
			var cursor = horizontal ? (rtl ? inner.maxX : inner.minX) : inner.minY
			let baseline = commonBaseline(children)
			for child in children {
				let s = child.measured
				var x = inner.minX
				var y = inner.minY
				if horizontal {
					x = rtl ? cursor - s.width : cursor
					switch node.style.alignment {
					case .center: y += (inner.size.height - s.height) / 2
					case .trailing: y += inner.size.height - s.height
					case .firstBaseline: y += baseline - alignmentBaseline(child)
					case .leading: break
					}

					cursor += (rtl ? -1 : 1) * (s.width + node.style.spacing)
				} else {
					y = cursor
					let trailing = (node.style.alignment == .trailing) != (document.direction == .rightToLeft)
					if node.style.alignment == .center {
						x += (inner.size.width - s.width) / 2
					} else if trailing {
						x += inner.size.width - s.width
					}

					cursor += s.height + node.style.spacing
				}

				apply(child, .init(x: x, y: y, width: s.width, height: s.height))
			}
		} else if node.kind == .zStack {
			for child in children {
				let s = child.measured
				var x = inner.minX
				if node.style.alignment == .center {
					x += (inner.size.width - s.width) / 2
				} else if (node.style.alignment == .trailing) != (document.direction == .rightToLeft) {
					x += inner.size.width - s.width
				}

				let y = inner.minY + (inner.size.height - s.height) / 2
				apply(child, .init(x: x, y: y, width: s.width, height: s.height))
			}
		} else {
			for child in children {
				let s = child.measured
				let x = inner.minX - (node.kind == .scroll ? node.scrollOffset.x : 0)
				let y = inner.minY - (node.kind == .scroll ? node.scrollOffset.y : 0)
				apply(child, .init(x: x, y: y, width: s.width, height: s.height))
			}
		}
	}
}
