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
		_ = measure(
			document.root,
			under: .init(minWidth: size.width, maxWidth: size.width, minHeight: size.height, maxHeight: size.height)
		)
		place(document.root, in: .init(width: size.width, height: size.height))
		document.dirty.remove(.layout)
	}

	package func arrangedChildren(_ node: NodeRecord) -> [NodeRecord] {
		node.children.flatMap { child -> [NodeRecord] in
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
		precondition(depth < 512, "Stana: layout depth budget exceeded")
		if node.style.visibility == .collapsed {
			node.measured = .zero
			return .zero
		}

		if useCache, let size = node.measureCache[AnyHashable(outer)] {
			node.measured = size
			return size
		}

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

			var remaining = maxMain.isFinite ? max(0, maxMain - main) : 0
			var unsettled = flexible
			var allocations: [STNNodeID: Double] = [:]
			while !unsettled.isEmpty {
				let largestWeight = unsettled.map(weight).max() ?? 1
				let totalWeight = unsettled.reduce(0) { $0 + weight($1) / largestWeight }
				var minima: [NodeRecord] = []
				var maxima: [NodeRecord] = []
				var sum = 0.0
				for child in unsettled {
					let f = child.style.frame
					let minV = horizontal ? (f.width ?? f.minWidth) : (f.height ?? f.minHeight)
					let maxV = horizontal ? (f.width ?? f.maxWidth) : (f.height ?? f.maxHeight)
					let share = maxMain.isFinite ? remaining * (weight(child) / largestWeight / totalWeight) : minV
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

				if !maxMain.isFinite || abs(sum - remaining) < 0.000_001 {
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

			if horizontal && node.style.alignment == .firstBaseline {
				cross =
					(children.map(\.baseline).max() ?? 0)
					+ (children.map { max(0, $0.measured.height - $0.baseline) }.max() ?? 0)
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

			intrinsic = horizontal ? .init(width: main, height: cross) : .init(width: cross, height: main)
			node.baseline = (children.first?.baseline ?? cross) + p.top
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
		// A size-only cache cannot restore child proposals from an older pass.
		// Keep the current proposal only until full placement plans are cached.
		if useCache {
			node.measureCache.removeAll(keepingCapacity: true)
			node.measureCache[AnyHashable(outer)] = result
		}

		return result
	}

	package func place(_ node: NodeRecord, in bounds: STNRect) {
		if node.bounds == bounds && node.placedMeasureVersion == node.measureVersion {
			return
		}

		node.placedMeasureVersion = node.measureVersion
		document.metrics.placedNodes += 1
		node.bounds = bounds
		let inner = bounds.inset(by: node.style.padding)
		let children = arrangedChildren(node)
		if node.kind == .hStack || node.kind == .vStack {
			let horizontal = node.kind == .hStack
			let rtl = horizontal && document.direction == .rightToLeft
			var cursor = horizontal ? (rtl ? inner.maxX : inner.minX) : inner.minY
			let baseline = children.map(\.baseline).max() ?? 0
			for child in children {
				let s = child.measured
				var x = inner.minX
				var y = inner.minY
				if horizontal {
					x = rtl ? cursor - s.width : cursor
					switch node.style.alignment {
					case .center: y += (inner.size.height - s.height) / 2
					case .trailing: y += inner.size.height - s.height
					case .firstBaseline: y += baseline - child.baseline
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

				place(child, in: .init(x: x, y: y, width: s.width, height: s.height))
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
				place(child, in: .init(x: x, y: y, width: s.width, height: s.height))
			}
		} else {
			for child in children {
				let s = child.measured
				let x = inner.minX - (node.kind == .scroll ? node.scrollOffset.x : 0)
				let y = inner.minY - (node.kind == .scroll ? node.scrollOffset.y : 0)
				place(child, in: .init(x: x, y: y, width: s.width, height: s.height))
			}
		}
	}
}
