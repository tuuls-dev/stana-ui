import Stana
import StanaTesting
import Testing

@Suite @MainActor struct ZStackTests {
	@Test(arguments: [STNZStack.Alignment.leading, .center, .trailing], [false, true])
	func alignmentUsesPaddedContentAndMirrorsWithDirection(alignment: STNZStack.Alignment, padded: Bool) throws {
		let padding = padded ? STNInsets(top: 7, leading: 11, bottom: 13, trailing: 19) : .zero
		let host = STNTestHost(size: .init(width: 200, height: 200))
		defer {
			host.close()
		}

		host.mount {
			STNZStack(
				properties: .init(
					alignment: alignment,
					layout: .init(
						padding: padding,
						frame: STNFrame(width: 100 + padding.horizontal, height: 80 + padding.vertical)
					)
				)
			) {
				STNBox(properties: .init(layout: .init(frame: STNFrame(width: 10, height: 20)))) {}
				STNBox(properties: .init(layout: .init(frame: STNFrame(width: 40, height: 60)))) {}
			}
		}

		let smallX: [Double]
		let largeX: [Double]
		switch alignment {
		case .leading:
			smallX = [0, 90]
			largeX = [0, 60]
		case .center:
			smallX = [45, 45]
			largeX = [30, 30]
		case .trailing:
			smallX = [90, 0]
			largeX = [60, 0]
		}

		let ids = host.nodeIDs
		for (index, direction) in [STNLayoutDirection.leftToRight, .rightToLeft].enumerated() {
			host.environment.layoutDirection.value = direction
			let children = host.nodes.filter { $0.kind == "box" }
			try #require(children.count == 2)
			#expect(
				children[0].bounds
					== STNRect(x: padding.leading + smallX[index], y: padding.top + 30, width: 10, height: 20)
			)
			#expect(
				children[1].bounds
					== STNRect(x: padding.leading + largeX[index], y: padding.top + 10, width: 40, height: 60)
			)
			#expect(host.nodeIDs == ids)
		}
	}

	@Test func omittedAlignmentCentersChildrenInAnExplicitFrame() throws {
		let host = STNTestHost()
		defer {
			host.close()
		}

		host.mount {
			STNZStack(properties: .init(layout: .init(frame: STNFrame(width: 100, height: 80)))) {
				STNBox(properties: .init(layout: .init(frame: STNFrame(width: 10, height: 20)))) {}
			}
		}

		for direction in [STNLayoutDirection.leftToRight, .rightToLeft] {
			host.environment.layoutDirection.value = direction
			let child = try #require(host.nodes.first { $0.kind == "box" })
			#expect(child.bounds == .init(x: 45, y: 30, width: 10, height: 20))
		}
	}

	@Test func defaultPropertiesMeasureLargestChildAndCenterSmallerChildren() throws {
		let host = STNTestHost()
		defer {
			host.close()
		}

		host.mount {
			STNZStack {
				STNBox(properties: .init(layout: .init(frame: STNFrame(width: 10, height: 20)))) {}
				STNBox(properties: .init(layout: .init(frame: STNFrame(width: 40, height: 60)))) {}
			}
		}

		let stack = try #require(host.nodes.first { $0.kind == "zStack" })
		let children = host.nodes.filter { $0.kind == "box" }
		try #require(children.count == 2)
		#expect(stack.bounds == .init(width: 40, height: 60))
		#expect(children[0].bounds == .init(x: 15, y: 20, width: 10, height: 20))
		#expect(children[1].bounds == .init(width: 40, height: 60))
	}

	@Test(arguments: [STNZStack.Alignment.leading, .center, .trailing])
	func laterChildrenRemainOnTopWhenOverlapping(alignment: STNZStack.Alignment) throws {
		let environment = STNEnvironment()
		var clicks: [String] = []
		let window = STNWindow(properties: .init(title: "Overlay order", environment: environment)) {
			STNZStack(
				properties: .init(alignment: alignment, layout: .init(frame: STNFrame(width: 100, height: 80)))
			) {
				STNBox(
					properties: .init(
						layout: .init(frame: STNFrame(width: 40, height: 60)),
						appearance: .init(background: STNColor.white),
						interaction: .init(onPointerDown: { _ in clicks.append("first") })
					)
				) {}
				STNBox(
					properties: .init(
						layout: .init(frame: STNFrame(width: 10, height: 20)),
						appearance: .init(background: STNColor.black),
						interaction: .init(onPointerDown: { _ in clicks.append("last") })
					)
				) {}
			}
		}

		let host = try STNWindowTestHost(window: window)
		defer {
			host.close()
		}

		for direction in [STNLayoutDirection.leftToRight, .rightToLeft] {
			environment.layoutDirection.value = direction
			#expect(Array(host.renderedFillColors().suffix(2)) == [.white, .black])
			let top = try #require(host.nodes.last { $0.kind == "box" })
			let point = STNPoint(x: top.bounds.minX + 5, y: top.bounds.minY + 5)
			host.pointerDown(at: point)
			host.pointerUp(at: point)
		}

		#expect(clicks == ["last", "last"])
	}
}
