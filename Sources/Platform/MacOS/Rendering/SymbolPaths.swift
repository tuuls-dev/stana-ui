import CoreGraphics
import Foundation
import StanaPrimitives
import Synchronization

struct SymbolPreparationFailure: Error {
	let code: SymbolFailureCode
}

/// One frame's worker feedback. A failure dominates successes from other tiles.
final class SymbolRasterResults: Sendable {
	private struct Key: Hashable {
		let node: STNNodeID
		let generation: UInt64
	}

	private let values = Mutex<[Key: SymbolRenderResult]>([:])

	func record(node: STNNodeID, generation: UInt64, epoch: UInt64, code: SymbolFailureCode?) {
		values.withLock {
			let key = Key(node: node, generation: generation)
			if $0[key]?.code == nil {
				$0[key] = .init(node: node, generation: generation, epoch: epoch, code: code)
			}
		}
	}

	func failed(node: STNNodeID, generation: UInt64) -> Bool {
		values.withLock { $0[Key(node: node, generation: generation)]?.code != nil }
	}

	var results: [SymbolRenderResult] {
		values.withLock {
			Array($0.values)
		}
	}
}

private final class SymbolPreparationBudget {
	var segments = 0
	var bytes: Int
	var reserved = 0
	var leases: [MetalLease] = []

	init(baseBytes: Int) throws {
		bytes = baseBytes
		try account(0)
	}

	func account(_ segments: Int) throws {
		self.segments += segments
		guard self.segments <= 1_048_576 else {
			throw SymbolPreparationFailure(code: .resourceLimitExceeded)
		}

		bytes += segments * 96
		if bytes > reserved, let device = MetalDevice.shared {
			let request = max(65_536, bytes - reserved)
			do {
				leases.append(try device.reserve(request))
				reserved += request
			} catch {
				throw SymbolPreparationFailure(code: .resourceLimitExceeded)
			}
		}
	}
}

/// Only immutable CGPath copies are published. CGMutablePath builders never escape preparation.
/// Core Graphics permits concurrent reads of immutable paths; contexts remain worker-local.
fileprivate final class PreparedSymbolBase: Sendable {
	let paths: [PreparedSymbolPaths.PathPair]
	let bytes: Int
	let segments: Int
	private let leases: [MetalLease]

	init(budget: SymbolPreparationBudget, build: (inout [PreparedSymbolPaths.PathPair]) throws -> Void) rethrows {
		var paths: [PreparedSymbolPaths.PathPair] = []
		try build(&paths)
		self.paths = paths
		bytes = max(budget.bytes, budget.reserved)
		segments = budget.segments
		leases = budget.leases
	}
}

final class PreparedSymbolPaths: Sendable {
	struct PathPair: @unchecked Sendable {
		let fill: CGPath
		let stroke: CGPath?
	}

	let paths: [PathPair]
	let bytes: Int
	fileprivate let base: PreparedSymbolBase
	private let leases: [MetalLease]

	fileprivate init(
		base: PreparedSymbolBase,
		budget: SymbolPreparationBudget,
		build: (inout [PathPair]) throws -> Void
	) rethrows {
		var paths = base.paths
		try build(&paths)
		self.paths = paths
		self.base = base
		bytes = base.bytes + max(budget.bytes, budget.reserved)
		leases = budget.leases
	}
}

/// Device-wide semantic LRU. Native preparation is serialized; published owners remain immutable during worker drawing.
final class SymbolPathCache: Sendable {
	static let shared = SymbolPathCache()

	private struct Key: Hashable {
		let asset: SymbolStorage
		let stroke: Double?
		let scale: Double
	}

	private struct Entry {
		let paths: PreparedSymbolPaths
		var age: UInt64
	}

	private struct State {
		var entries: [Key: Entry] = [:]
		var bytes = 0
		var age: UInt64 = 0
		var preparations = 0
		var fillPreparations = 0
	}

	private let state = Mutex(State())
	private let entryLimit: Int
	private let byteLimit: Int

	init(entryLimit: Int = 256, byteLimit: Int = 16 * 1_024 * 1_024) {
		self.entryLimit = entryLimit
		self.byteLimit = byteLimit
	}

	var accounting: (entries: Int, bytes: Int, preparations: Int, fillPreparations: Int) {
		state.withLock { ($0.entries.count, $0.bytes, $0.preparations, $0.fillPreparations) }
	}

	func prepare(_ asset: SymbolStorage, strokeWidth: Double?, scale: Double) throws -> PreparedSymbolPaths {
		guard scale.isFinite && scale >= 0 else {
			throw SymbolPreparationFailure(code: .resourceLimitExceeded)
		}

		// A bucket is always at least as precise as the actual device transform.
		let quality = scale > 0 ? pow(2, ceil(log2(scale))) : 1
		guard quality.isFinite else {
			throw SymbolPreparationFailure(code: .resourceLimitExceeded)
		}

		let key = Key(asset: asset, stroke: asset.hasStroke ? strokeWidth : nil, scale: quality)
		return try state.withLock { state in
			nextRevision(&state.age)
			if var entry = state.entries[key] {
				entry.age = state.age
				state.entries[key] = entry
				return entry.paths
			}

			let base: PreparedSymbolBase
			if let shared = state.entries.first(where: { $0.key.asset == asset && $0.key.scale == quality }) {
				base = shared.value.paths.base
			} else {
				let budget = try SymbolPreparationBudget(baseBytes: asset.estimatedBytes)
				base = try PreparedSymbolBase(budget: budget) { paths in
					func visit(_ elements: [SymbolElement], parent: STNAffineTransform) throws {
						for element in elements {
							switch element {
							case .group(let t, _, let children):
								try visit(children, parent: parent.concatenating(t))
							case .path(let commands, let t, _, _, _, _, _, _, _, _, _, _):
								let localScale = max(1e-300, quality * parent.concatenating(t).maximumScale)
								let native = try SymbolFlattener.native(
									commands,
									tolerance: 0.125 / localScale,
									strokeWidth: 0,
									budget: budget
								)
								let fill = try SymbolFlattener.flatten(
									native,
									tolerance: 0.125 / localScale,
									budget: budget
								)
								paths.append(.init(fill: fill, stroke: nil))
							}
						}
					}
					try visit(asset.elements, parent: .identity)
				}
				state.fillPreparations += 1
			}
			let budget = try SymbolPreparationBudget(baseBytes: 0)
			budget.segments = base.segments
			let prepared = try PreparedSymbolPaths(base: base, budget: budget) { paths in
				var index = 0
				func visit(_ elements: [SymbolElement], parent: STNAffineTransform) throws {
					for element in elements {
						switch element {
						case .group(let t, _, let children):
							try visit(children, parent: parent.concatenating(t))
						case .path(
							let commands,
							let t,
							_,
							_,
							_,
							let stroke,
							_,
							let width,
							let cap,
							let join,
							let miter,
							_
						):
							var outline: CGPath?
							let width = strokeWidth ?? width
							if stroke != .none && width > 0 {
								let localScale = max(1e-300, quality * parent.concatenating(t).maximumScale)
								let native = try SymbolFlattener.native(
									commands,
									tolerance: 0.125 / localScale,
									strokeWidth: width,
									budget: budget
								)
								let lineCap: CGLineCap = cap == .round ? .round : cap == .square ? .square : .butt
								let lineJoin: CGLineJoin = join == .round ? .round : join == .bevel ? .bevel : .miter
								let stroked = native.copy(
									strokingWithWidth: width,
									lineCap: lineCap,
									lineJoin: lineJoin,
									miterLimit: miter
								)
								outline = try SymbolFlattener.flatten(
									stroked,
									tolerance: 0.125 / localScale,
									budget: budget
								)
							}
							paths[index] = .init(fill: base.paths[index].fill, stroke: outline)
							index += 1
						}
					}
				}
				try visit(asset.elements, parent: .identity)
			}
			state.preparations += 1
			if prepared.bytes <= byteLimit && entryLimit > 0 {
				while state.entries.count >= entryLimit || state.bytes + prepared.bytes > byteLimit {
					guard
						let oldest = state.entries.min(by: {
							$0.value.age < $1.value.age
						})
					else {
						break
					}

					state.bytes -= oldest.value.paths.bytes
					state.entries.removeValue(forKey: oldest.key)
				}

				state.entries[key] = Entry(paths: prepared, age: state.age)
				state.bytes += prepared.bytes
			}

			return prepared
		}
	}
}

private enum SymbolFlattener {
	/// Preserve authored Beziers for native stroking, so approximation vertices never acquire authored joins.
	/// Ellipse arcs use tangent-matched Hermite curves with conservative position/normal error bounds.
	static func native(
		_ commands: [SymbolPathCommand],
		tolerance: Double,
		strokeWidth: Double,
		budget: SymbolPreparationBudget
	) throws -> CGPath {
		let path = CGMutablePath()
		for command in commands {
			try budget.account(1)
			switch command {
			case .move(let x, let y): path.move(to: CGPoint(x: x, y: y))
			case .line(let x, let y): path.addLine(to: CGPoint(x: x, y: y))
			case .quadratic(let cx, let cy, let x, let y):
				path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
			case .cubic(let ax, let ay, let bx, let by, let x, let y):
				path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: ax, y: ay), control2: CGPoint(x: bx, y: by))
			case .close: path.closeSubpath()
			case .arc(let cx, let cy, let rx, let ry, let rotation, let start, let sweep):

				func point(_ t: Double) -> CGPoint {
					CGPoint(
						x: cx + rx * cos(t) * cos(rotation) - ry * sin(t) * sin(rotation),
						y: cy + rx * cos(t) * sin(rotation) + ry * sin(t) * cos(rotation)
					)
				}

				func derivative(_ t: Double) -> CGPoint {
					CGPoint(
						x: -rx * sin(t) * cos(rotation) - ry * cos(t) * sin(rotation),
						y: -rx * sin(t) * sin(rotation) + ry * cos(t) * cos(rotation)
					)
				}

				func arc(_ angle: Double, _ delta: Double, depth: Int) throws {
					let positionError = max(rx, ry) * pow(abs(delta), 4) / 192
					let derivativeError = max(rx, ry) * pow(abs(delta), 3) / 12
					let normalError = strokeWidth > 0 ? strokeWidth * derivativeError / min(rx, ry) : 0
					if abs(delta) <= .pi / 2 && positionError + normalError <= tolerance {
						try budget.account(1)
						let end = point(angle + delta)
						path.addCurve(
							to: end,
							control1: point(angle) + derivative(angle) * (delta / 3),
							control2: end - derivative(angle + delta) * (delta / 3)
						)
					} else {
						guard depth < 32 else {
							throw SymbolPreparationFailure(code: .resourceLimitExceeded)
						}

						try arc(angle, delta / 2, depth: depth + 1)
						try arc(angle + delta / 2, delta / 2, depth: depth + 1)
					}
				}

				try arc(start, sweep, depth: 0)
			}
		}

		guard let copy = path.copy() else {
			throw SymbolPreparationFailure(code: .preparationFailed)
		}
		return copy
	}

	static func make(_ commands: [SymbolPathCommand], tolerance: Double, budget: SymbolPreparationBudget) throws
		-> CGPath
	{
		let output = CGMutablePath()
		var current = CGPoint.zero, start = CGPoint.zero

		func line(_ p: CGPoint) throws {
			try budget.account(1)
			output.addLine(to: p)
			current = p
		}

		for command in commands {
			switch command {
			case .move(let x, let y):
				current = CGPoint(x: x, y: y); start = current
				output.move(to: current)
			case .line(let x, let y): try line(CGPoint(x: x, y: y))
			case .quadratic(let cx, let cy, let x, let y):
				let end = CGPoint(x: x, y: y), c = CGPoint(x: cx, y: cy)
				try cubic(
					current,
					current + (c - current) * (2.0 / 3),
					end + (c - end) * (2.0 / 3),
					end,
					tolerance: tolerance,
					depth: 0,
					line: line
				)
			case .cubic(let ax, let ay, let bx, let by, let x, let y):
				try cubic(
					current,
					CGPoint(x: ax, y: ay),
					CGPoint(x: bx, y: by),
					CGPoint(x: x, y: y),
					tolerance: tolerance,
					depth: 0,
					line: line
				)
			case .arc(let cx, let cy, let rx, let ry, let rotation, let angle, let sweep):

				func point(_ a: Double) -> CGPoint {
					CGPoint(
						x: cx + rx * cos(a) * cos(rotation) - ry * sin(a) * sin(rotation),
						y: cy + rx * cos(a) * sin(rotation) + ry * sin(a) * cos(rotation)
					)
				}

				func arc(_ a: Double, _ delta: Double, depth: Int) throws {
					if abs(delta) <= .pi && max(rx, ry) * 2 * pow(sin(delta / 4), 2) <= tolerance {
						try line(point(a + delta)); return
					}

					guard depth < 32 else {
						throw SymbolPreparationFailure(code: .resourceLimitExceeded)
					}

					try arc(a, delta / 2, depth: depth + 1)
					try arc(a + delta / 2, delta / 2, depth: depth + 1)
				}

				try arc(angle, sweep, depth: 0)
			case .close:
				try budget.account(1)
				output.closeSubpath()
				current = start
			}
		}

		guard let copy = output.copy() else {
			throw SymbolPreparationFailure(code: .preparationFailed)
		}
		return copy
	}

	static func cubic(
		_ p: CGPoint,
		_ a: CGPoint,
		_ b: CGPoint,
		_ end: CGPoint,
		tolerance: Double,
		depth: Int,
		line: (CGPoint) throws -> Void
	) throws {
		func distance(_ c: CGPoint) -> Double {
			let v = end - p
			let square = v.x * v.x + v.y * v.y
			let fraction = square > 0 ? max(0, min(1, ((c.x - p.x) * v.x + (c.y - p.y) * v.y) / square)) : 0
			return hypot(c.x - (p.x + fraction * v.x), c.y - (p.y + fraction * v.y))
		}

		if max(distance(a), distance(b)) <= tolerance {
			try line(end)
			return
		}

		guard depth < 32 else {
			throw SymbolPreparationFailure(code: .resourceLimitExceeded)
		}

		let pa = (p + a) * 0.5, ab = (a + b) * 0.5, be = (b + end) * 0.5
		let left = (pa + ab) * 0.5, right = (ab + be) * 0.5, middle = (left + right) * 0.5
		try cubic(p, pa, left, middle, tolerance: tolerance, depth: depth + 1, line: line)
		try cubic(middle, right, be, end, tolerance: tolerance, depth: depth + 1, line: line)
	}

	static func flatten(_ path: CGPath, tolerance: Double, budget: SymbolPreparationBudget) throws -> CGPath {
		var commands: [SymbolPathCommand] = []
		var excessive = false
		path.applyWithBlock { pointer in
			guard commands.count <= 1_048_576 else {
				excessive = true
				return
			}

			let e = pointer.pointee, p = e.points
			switch e.type {
			case .moveToPoint: commands.append(.move(x: p[0].x, y: p[0].y))
			case .addLineToPoint: commands.append(.line(x: p[0].x, y: p[0].y))
			case .addQuadCurveToPoint:
				commands.append(.quadratic(controlX: p[0].x, controlY: p[0].y, x: p[1].x, y: p[1].y))
			case .addCurveToPoint:
				commands.append(
					.cubic(
						control1X: p[0].x,
						control1Y: p[0].y,
						control2X: p[1].x,
						control2Y: p[1].y,
						x: p[2].x,
						y: p[2].y
					)
				)
			case .closeSubpath: commands.append(.close)
			@unknown default: excessive = true
			}
		}

		guard !excessive else {
			throw SymbolPreparationFailure(code: .resourceLimitExceeded)
		}

		return try make(commands, tolerance: tolerance, budget: budget)
	}
}

private extension CGPoint {
	static func + (lhs: Self, rhs: Self) -> Self {
		.init(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
	}

	static func - (lhs: Self, rhs: Self) -> Self {
		.init(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
	}

	static func * (lhs: Self, rhs: Double) -> Self {
		.init(x: lhs.x * rhs, y: lhs.y * rhs)
	}
}
