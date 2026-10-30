import Dispatch
import Foundation
import Metal
import QuartzCore
import StanaGraphics
import StanaPrimitives
import StanaScene
import Synchronization

private final class GPUReadLease: Sendable {
	private struct Owners: Sendable {
		let allocations: [MetalAllocation]
		let buffers: [MetalBuffer]
		let surface: MetalSurface
	}

	private let owners: Mutex<Owners?>

	init(allocations: [MetalAllocation], buffers: [MetalBuffer], surface: MetalSurface) {
		owners = Mutex(Owners(allocations: allocations, buffers: buffers, surface: surface))
	}

	func complete() {
		// Command buffers can retain fired handlers; release owners at completion, not handler deinit.
		owners.withLock { $0 = nil }
	}
}

struct NativeGPUDiagnostic: Sendable {
	let node: STNNodeID
	let diagnostic: STNGPUDiagnostic
}

struct MetalQuad: BitwiseCopyable {
	var rect, uv, color, clip: SIMD4<Float>
	var row0, row1, target, options: SIMD4<Float>
	var mode, linear, sourceLinear, masked: UInt32

	init(rect: CGRect, target: CGRect, transform: CGAffineTransform = .identity, linear: Bool) {
		self.rect = rect.vector
		uv = SIMD4(0, 0, 1, 1)
		color = SIMD4(repeating: 1)
		clip = .zero
		row0 = SIMD4(Float(transform.a), Float(transform.c), Float(transform.tx), 0)
		row1 = SIMD4(Float(transform.b), Float(transform.d), Float(transform.ty), 0)
		self.target = target.vector
		options = SIMD4(0, 0, 1, 1)
		mode = 0
		self.linear = linear ? 1 : 0
		sourceLinear = 0
		masked = 0
	}
}

extension CGRect {
	var vector: SIMD4<Float> {
		SIMD4(Float(minX), Float(minY), Float(width), Float(height))
	}
}

struct CompositingKey: Hashable, Sendable {
	let transform: STNAffineTransform
	let opacity: Double
	let clip: STNRect?
	let radius: Double
}

enum BackdropCacheEffect: Hashable, Sendable {
	case identity, blur(Double), program(RenderVersion)
}

struct SurfaceCacheKey: Hashable, Sendable {
	enum Kind: Hashable, Sendable {
		case cpu, gpu, group, groupTile, backdrop, program
	}

	let kind: Kind
	let owner: STNNodeID
	let versions: [RenderVersion]
	let bounds: STNRect
	let scale: Double
	let linear: Bool
	let epoch: UInt64
	let untiled: Bool
	var compositing: [CompositingKey] = []
	var visible: STNRect? = nil
	var effect: BackdropCacheEffect? = nil
	var context: STNNodeID? = nil
}

/// Stable replacement location; freshness remains in SurfaceCacheKey.
private struct SurfaceCacheSlot: Hashable {
	let kind: SurfaceCacheKey.Kind
	let owner: STNNodeID
	let bounds: STNRect
	let scale: Double
	let linear: Bool
	let epoch: UInt64
	let untiled: Bool
	let visible: STNRect?
	let context: STNNodeID?

	init(_ key: SurfaceCacheKey) {
		kind = key.kind
		owner = key.owner
		bounds = key.bounds
		scale = key.scale
		linear = key.linear
		epoch = key.epoch
		untiled = key.untiled
		visible = key.visible
		context = key.context
	}
}

final class CachedSurface: Sendable {
	let key: SurfaceCacheKey
	let surface: MetalSurface
	let dependencies: [CachedSurface]

	init(key: SurfaceCacheKey, surface: MetalSurface, dependencies: [CachedSurface]) {
		self.key = key
		self.surface = surface
		self.dependencies = dependencies
	}
}

struct MetalTile: Sendable {
	let version: RenderVersion
	let core, padded: CGRect
	let allocation: MetalAllocation
	let multisample: MetalAllocation?

	init(
		version: RenderVersion,
		core: CGRect,
		padded: CGRect,
		allocation: MetalAllocation,
		multisample: MetalAllocation? = nil
	) {
		self.version = version
		self.core = core
		self.padded = padded
		self.allocation = allocation
		self.multisample = multisample
	}
}

final class MetalSurface: Sendable {
	let version: RenderVersion
	let bounds: CGRect
	let scale: Double
	let linear: Bool
	let tiles: [MetalTile]
	let directInputs: [MetalEncoder.GroupInput]?

	init(
		version: RenderVersion,
		bounds: CGRect,
		scale: Double,
		linear: Bool,
		tiles: [MetalTile],
		directInputs: [MetalEncoder.GroupInput]? = nil
	) {
		self.version = version
		self.bounds = bounds
		self.scale = scale
		self.linear = linear
		self.tiles = tiles
		self.directInputs = directInputs
	}
}

struct RenderSettings: Sendable {
	let scale: Double
	let linear: Bool
	let headroom: Double
	let forceMode: Int
	let rasterDelay: Double
}

final class PreparedFrame: Sendable {
	let scene: SceneSnapshot
	let plan: PlannedGroup?
	let surface: MetalSurface
	let settings: RenderSettings
	let offscreenSeconds: Double
	let preparationSeconds: Double

	init(
		scene: SceneSnapshot,
		plan: PlannedGroup?,
		surface: MetalSurface,
		settings: RenderSettings,
		offscreenSeconds: Double,
		preparationSeconds: Double
	) {
		self.scene = scene
		self.plan = plan
		self.surface = surface
		self.settings = settings
		self.offscreenSeconds = offscreenSeconds
		self.preparationSeconds = preparationSeconds
	}
}

final class FrameEncoding {
	let scene: SceneSnapshot
	let settings: RenderSettings
	let buffer: any MTLCommandBuffer
	var allocations: [MetalAllocation] = []
	var buffers: [MetalBuffer] = []
	var rasterJobs: [RasterJob] = []
	var cacheRecords: [CachedSurface] = []
	var effectVersions: [STNNodeID: RenderVersion] = [:]
	var states: [ProgramInstance: ProgramState] = [:]
	var programs: [ProgramInstance: STNGPUProgram] = [:]
	var outputs: [ProgramOutputKey: MetalSurface] = [:]
	var activePrograms: Set<ProgramInstance> = []
	var activeGroups: Set<STNNodeID> = []

	init(scene: SceneSnapshot, settings: RenderSettings, buffer: any MTLCommandBuffer) {
		self.scene = scene
		self.settings = settings
		self.buffer = buffer
	}
}

actor MetalEncoder {
	nonisolated let executor = DispatchSerialQueue(label: "dev.stana.render")

	nonisolated var unownedExecutor: UnownedSerialExecutor {
		executor.asUnownedSerialExecutor()
	}

	let device: MetalDevice
	let queue: any MTLCommandQueue
	private var library: (any MTLLibrary)?
	private var renderPipelines: [PipelineKey: any MTLRenderPipelineState] = [:]
	private var computePipelines: [String: any MTLComputePipelineState] = [:]
	var applicationPipelines: [RenderVersion: CompiledProgram] = [:]
	var validPrograms: [ProgramInstance: STNGPUProgram] = [:]
	var programStates: [ProgramInstance: ProgramState] = [:]
	var programOutputs: [ProgramOutputKey: MetalSurface] = [:]
	var diagnostics: [NativeGPUDiagnostic] = []
	var counts: [String: Double] = [:]
	var timings: [String: [STNRenderTimingSample]] = [:]
	private var cache: [SurfaceCacheKey: CachedSurface] = [:]
	private var cacheSlots: [SurfaceCacheSlot: SurfaceCacheKey] = [:]
	private var planner = ScenePlanner()
	private var previousPlan: PlannedGroup?
	var rasterScales: [STNNodeID: (scale: Double, lowSince: Double)] = [:]
	private var epoch: UInt64 = 0
	private var preparing = false
	private var transparent: MetalAllocation?
	private var currentSamples = 1
	var directMode = false
	private var frameIndex: UInt64 = 0
	private var lastModeSwitch: UInt64 = 0
	private var denseFrames = 0
	private var sparseFrames = 0

	private struct PathKey: Hashable {
		let linear: Bool
		let direct: Bool
	}

	private var pathCosts: [PathKey: Double] = [:]
	private var lastFailure: String?

	struct PipelineKey: Hashable {
		let fragment: String
		let format: UInt
		let blends: Bool
		let mesh: Bool
		let samples: Int
	}

	init(device: MetalDevice) throws {
		self.device = device
		guard let queue = device.device.makeCommandQueue() else {
			throw MetalFailure("Metal command queue unavailable")
		}

		self.queue = queue
	}

	func count(_ name: String, _ value: Int = 1) {
		counts[name, default: 0] += Double(value)
	}

	func timing(_ name: String, _ seconds: Double, scene: UInt64) {
		guard seconds.isFinite, seconds >= 0 else {
			return
		}

		if timings[name, default: []].count >= 8_192 {
			timings[name]?.removeFirst()
		}

		timings[name, default: []].append(.init(sceneRevision: scene, milliseconds: seconds * 1_000))
	}

	func allocate(_ width: Int, _ height: Int, format: MTLPixelFormat, raster: Bool = false, frame: FrameEncoding)
		throws -> MetalAllocation
	{
		let allocation = try device.texture(width: width, height: height, format: format, raster: raster)
		frame.allocations.append(allocation)
		count("surfaceAllocations")
		return allocation
	}

	func makeBuffer(_ data: Data, frame: FrameEncoding) throws -> any MTLBuffer {
		let owner = try device.buffer(data: data, length: data.count)
		frame.buffers.append(owner)
		count("bufferAllocations")
		count("bufferUploadBytes", data.count)
		return owner.buffer
	}

	func shaderLibrary() throws -> any MTLLibrary {
		if let library {
			return library
		}

		guard let url = Bundle.module.url(forResource: "Stana", withExtension: "metal", subdirectory: "Shaders") else {
			throw MetalFailure("Bundled Metal shader source missing")
		}

		let source = try String(contentsOf: url, encoding: .utf8)
		let result = try device.device.makeLibrary(source: source, options: nil)
		library = result
		return result
	}

	func pipeline(_ fragment: String, format: MTLPixelFormat, blends: Bool = true, mesh: Bool = false) throws
		-> any MTLRenderPipelineState
	{
		let key = PipelineKey(
			fragment: fragment,
			format: format.rawValue,
			blends: blends,
			mesh: mesh,
			samples: currentSamples
		)
		if let cached = renderPipelines[key] {
			return cached
		}

		let descriptor = MTLRenderPipelineDescriptor()
		let library = try shaderLibrary()
		descriptor.vertexFunction = library.makeFunction(
			name: fragment == "stn_present_batch" ? "stn_batch_quad" : mesh ? "stn_mesh" : "stn_quad"
		)
		descriptor.fragmentFunction = library.makeFunction(name: fragment)
		descriptor.rasterSampleCount = currentSamples
		descriptor.colorAttachments[0].pixelFormat = format
		descriptor.colorAttachments[0].isBlendingEnabled = blends
		descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
		descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
		descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
		descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
		let result = try device.device.makeRenderPipelineState(descriptor: descriptor)
		renderPipelines[key] = result
		return result
	}

	func compute(_ name: String) throws -> any MTLComputePipelineState {
		if let cached = computePipelines[name] {
			return cached
		}

		guard let function = try shaderLibrary().makeFunction(name: name) else {
			throw MetalFailure("Missing built-in compute function")
		}

		let result = try device.device.makeComputePipelineState(function: function)
		computePipelines[name] = result
		return result
	}

	func encoder(
		_ buffer: any MTLCommandBuffer,
		target: any MTLTexture,
		clear: Bool,
		multisample: MetalAllocation? = nil
	) throws -> any MTLRenderCommandEncoder {
		let descriptor = MTLRenderPassDescriptor()
		currentSamples = multisample == nil ? 1 : 4
		descriptor.colorAttachments[0].texture = multisample?.texture ?? target
		descriptor.colorAttachments[0].resolveTexture = multisample == nil ? nil : target
		descriptor.colorAttachments[0].loadAction = clear ? .clear : .load
		descriptor.colorAttachments[0].storeAction = multisample == nil ? .store : .storeAndMultisampleResolve
		descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
		guard let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
			throw MetalFailure("Metal render encoder unavailable")
		}

		return encoder
	}

	func draw(
		_ quad: MetalQuad,
		texture: (any MTLTexture)?,
		encoder: any MTLRenderCommandEncoder,
		format: MTLPixelFormat,
		fragment: String = "stn_fragment",
		blends: Bool = true
	) throws {
		var quad = quad
		encoder.setRenderPipelineState(try pipeline(fragment, format: format, blends: blends))
		encoder.setVertexBytes(&quad, length: MemoryLayout<MetalQuad>.stride, index: 0)
		encoder.setFragmentBytes(&quad, length: MemoryLayout<MetalQuad>.stride, index: 0)
		if let texture {
			encoder.setFragmentTexture(texture, index: 0)
			encoder.useResource(texture, usage: .read, stages: .fragment)
		}

		encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
	}

	func layout(_ bounds: CGRect, scale: Double, untiled: Bool, visible: CGRect? = nil) throws -> [(
		core: CGRect, padded: CGRect
	)] {
		let x = floor(bounds.minX * scale), y = floor(bounds.minY * scale)
		let maxX = ceil(bounds.maxX * scale), maxY = ceil(bounds.maxY * scale)
		guard x.isFinite, y.isFinite, maxX.isFinite, maxY.isFinite, maxX > x, maxY > y else {
			return []
		}

		let width = maxX - x, height = maxY - y
		let tiled = !untiled && (width > 1_024 || height > 1_024 || width * height > 1_000_000)
		let edge = tiled ? 512.0 : max(width, height)
		let needed = bounds.intersection((visible ?? bounds).insetBy(dx: -edge / scale, dy: -edge / scale))
		guard !needed.isNull, !needed.isEmpty else {
			return []
		}

		let firstX = x + max(0, floor((needed.minX * scale - x) / edge)) * edge
		let firstY = y + max(0, floor((needed.minY * scale - y) / edge)) * edge
		let endX = min(maxX, x + ceil((needed.maxX * scale - x) / edge) * edge)
		let endY = min(maxY, y + ceil((needed.maxY * scale - y) / edge) * edge)
		guard (endX - firstX) / edge * (endY - firstY) / edge <= 16_384 else {
			throw MetalFailure("Visible surface tile budget exceeded")
		}

		var result: [(CGRect, CGRect)] = []
		for ty in stride(from: firstY, to: endY, by: edge) {
			for tx in stride(from: firstX, to: endX, by: edge) {
				let core = CGRect(
					x: tx / scale,
					y: ty / scale,
					width: min(edge, maxX - tx) / scale,
					height: min(edge, maxY - ty) / scale
				)
				result.append((core, core.insetBy(dx: -2 / scale, dy: -2 / scale)))
			}
		}

		return result
	}

	func surface(_ bounds: CGRect, scale: Double, linear: Bool, frame: FrameEncoding) throws -> MetalSurface {
		let tiles = try layout(bounds, scale: scale, untiled: frame.settings.forceMode == 4)
			.map { core, padded in
				let allocation = try allocate(
					Int(round(padded.width * scale)),
					Int(round(padded.height * scale)),
					format: linear ? .rgba16Float : .bgra8Unorm,
					frame: frame
				)
				return MetalTile(version: RenderVersion(), core: core, padded: padded, allocation: allocation)
			}
		return MetalSurface(version: RenderVersion(), bounds: bounds, scale: scale, linear: linear, tiles: tiles)
	}

	func drawSurface(
		_ surface: MetalSurface,
		into target: MetalTile,
		frame: FrameEncoding,
		transform: CGAffineTransform = .identity,
		opacity: Double = 1,
		clip: CGRect = .zero,
		radius: Double = 0,
		masked: Bool = false
	) throws {
		guard transform.isInvertible else {
			return
		}

		var render: (any MTLRenderCommandEncoder)?
		defer {
			render?.endEncoding()
		}

		for tile in surface.tiles where tile.core.applying(transform).intersects(target.padded) {
			frame.allocations.append(tile.allocation)
			if render == nil {
				render = try encoder(
					frame.buffer,
					target: target.allocation.texture,
					clear: false,
					multisample: target.multisample
				)
			}

			var quad = MetalQuad(
				rect: tile.core,
				target: target.padded,
				transform: transform,
				linear: target.allocation.texture.pixelFormat == .rgba16Float
			)
			quad.uv = SIMD4(
				Float((tile.core.minX - tile.padded.minX) / tile.padded.width),
				Float((tile.core.minY - tile.padded.minY) / tile.padded.height),
				Float(tile.core.width / tile.padded.width),
				Float(tile.core.height / tile.padded.height)
			)
			quad.sourceLinear = surface.linear ? 1 : 0
			quad.options.z = Float(opacity)
			quad.clip = clip.vector
			quad.options.x = Float(radius)
			quad.masked = masked ? 1 : 0
			try draw(
				quad,
				texture: tile.allocation.texture,
				encoder: render!,
				format: target.allocation.texture.pixelFormat
			)
		}
	}

	func retireObsoleteGeneration(for key: SurfaceCacheKey) {
		let slot = SurfaceCacheSlot(key)
		if let previous = cacheSlots[slot], previous != key {
			cache.removeValue(forKey: previous)
			cacheSlots.removeValue(forKey: slot)
		}
	}

	func cached(_ key: SurfaceCacheKey, frame: FrameEncoding) -> MetalSurface? {
		retireObsoleteGeneration(for: key)
		guard let record = cache[key] else {
			return nil
		}

		frame.cacheRecords.append(record)
		return record.surface
	}

	func cache(_ surface: MetalSurface, for key: SurfaceCacheKey, frame: FrameEncoding, dependencyStart: Int? = nil) {
		let dependencies = dependencyStart.map { Array(frame.cacheRecords[$0...]) } ?? []
		let record = CachedSurface(key: key, surface: surface, dependencies: dependencies)
		retireObsoleteGeneration(for: key)
		cache[key] = record
		cacheSlots[SurfaceCacheSlot(key)] = key
		if let dependencyStart {
			frame.cacheRecords.removeSubrange(dependencyStart...)
		}

		frame.cacheRecords.append(record)
	}

	private func pruneCache(_ roots: [CachedSurface]) {
		var reachable: Set<SurfaceCacheKey> = []
		var pending = roots
		while let record = pending.popLast() {
			if reachable.insert(record.key).inserted {
				pending.append(contentsOf: record.dependencies)
			}
		}

		cache = cache.filter { reachable.contains($0.key) }
		cacheSlots = cacheSlots.filter { cache[$0.value] != nil }
	}

	func clear(_ surface: MetalSurface, frame: FrameEncoding) throws {
		for tile in surface.tiles {
			try encoder(frame.buffer, target: tile.allocation.texture, clear: true, multisample: tile.multisample)
				.endEncoding()
		}
	}
}

extension CGAffineTransform {
	var isInvertible: Bool {
		let scale = max(abs(a), abs(b), abs(c), abs(d))
		guard scale.isFinite, scale > 0 else {
			return false
		}

		let determinant = (a / scale) * (d / scale) - (b / scale) * (c / scale)
		return determinant.isFinite && determinant != 0
	}
}

extension MetalEncoder {
	func reset(epoch: UInt64) {
		self.epoch = epoch
		cache.removeAll()
		cacheSlots.removeAll()
		programStates.removeAll()
		programOutputs.removeAll()
		validPrograms.removeAll()
		previousPlan = nil
		rasterScales.removeAll()
		planner = ScenePlanner()
	}

	private func selectFinalPath(_ scene: SceneSnapshot, settings: RenderSettings) {
		nextRevision(&frameIndex)
		let area = scene.size.width * scene.size.height
		let viewport = CGRect(x: 0, y: 0, width: scene.size.width, height: scene.size.height)
		let damage = scene.damage.reduce(0.0) { sum, value in
			let clipped = value.cgRect.intersection(viewport)
			return sum + (clipped.isNull ? 0 : Double(clipped.width * clipped.height))
		}
		let fraction = area > 0 ? min(1, damage / area) : 1
		denseFrames = fraction >= 0.6 ? denseFrames + 1 : 0
		sparseFrames = fraction <= 0.2 ? sparseFrames + 1 : 0
		var next = directMode
		switch settings.forceMode {
		case 1, 3, 4: next = false
		case 2: next = true
		default:
			if frameIndex - lastModeSwitch >= 60 {
				let direct = pathCosts[PathKey(linear: settings.linear, direct: true)] ?? 0
				let persistent = pathCosts[PathKey(linear: settings.linear, direct: false)] ?? 0
				if !directMode, denseFrames >= 8, direct == 0 || direct < persistent {
					next = true
				}

				if directMode, sparseFrames >= 30 {
					next = false
				}
			}
		}

		if next != directMode {
			directMode = next
			lastModeSwitch = frameIndex
			count("finalModeSwitches")
		}

		counts["directMode"] = next ? 1 : 0
		counts["damageFraction"] = fraction
	}

	private func collectReachability(_ group: PlannedGroup, frame: FrameEncoding) {
		frame.activeGroups.insert(group.source.id)
		if case .program = group.source.backdrop?.operation {
			frame.activePrograms.insert(.init(node: group.source.id, backdrop: true, commandIndex: 0))
		}

		collectReachability(group.children, frame: frame)
	}

	private func collectReachability(_ branch: PlannedBranch?, frame: FrameEncoding) {
		guard let branch, !branch.allCPU else {
			return
		}

		collectReachability(branch.left, frame: frame)
		switch branch.entry {
		case .cpu: break
		case .gpu(let item):
			for (index, command) in item.drawing.commands.enumerated() {
				if case .program = command {
					frame.activePrograms.insert(.init(node: item.id, backdrop: false, commandIndex: index))
				}
			}
		case .group(let group): collectReachability(group, frame: frame)
		}

		collectReachability(branch.right, frame: frame)
	}

	func prepare(_ scene: SceneSnapshot, settings: RenderSettings, referenceID: STNNodeID) async throws -> PreparedFrame
	{
		guard !preparing else {
			throw MetalFailure("Renderer preparation overlap")
		}

		preparing = true
		var succeeded = false
		defer {
			preparing = false
			if !succeeded {
				cache.removeAll()
				cacheSlots.removeAll()
			}
		}

		if epoch != scene.surfaceEpoch {
			reset(epoch: scene.surfaceEpoch)
		}

		guard let buffer = queue.makeCommandBuffer() else {
			throw MetalFailure("Offscreen command buffer unavailable")
		}

		let start = CACurrentMediaTime()
		let frame = FrameEncoding(scene: scene, settings: settings, buffer: buffer)
		selectFinalPath(scene, settings: settings)
		let plan: PlannedGroup?
		let result: MetalSurface
		if let paint = scene.paint {
			plan = planner.prepare(paint)
			collectReachability(plan!, frame: frame)
			count("plannedBranches", planner.createdBranches)
			count("visitedBranches", planner.visitedBranches)
			result = try group(
				plan!,
				scale: settings.scale,
				visible: CGRect(x: 0, y: 0, width: scene.size.width, height: scene.size.height),
				frame: frame,
				root: true
			)
		} else {
			plan = nil
			let item = PaintCPUItem(
				id: referenceID,
				version: RenderVersion(),
				bounds: .init(width: scene.size.width, height: scene.size.height),
				commands: scene.commands
			)
			result = try rasterRun(
				CPUCommandTree(leaf: item),
				scale: settings.scale,
				visible: item.bounds.cgRect,
				frame: frame
			)
		}

		// Read leases let obsolete cache generations retire before the GPU wait.
		pruneCache(frame.cacheRecords)
		timing("nativeEncoding", CACurrentMediaTime() - start, scene: scene.sceneRevision)
		let jobs = frame.rasterJobs
		let rasterStart = CACurrentMediaTime()
		try await withThrowingTaskGroup(of: RasterTiming.self) { group in
			var next = 0
			for _ in 0..<min(RasterWorkers.shared.limit, jobs.count) {
				let job = jobs[next]
				next += 1
				group.addTask { try await RasterWorkers.shared.run(job, delay: settings.rasterDelay) }
			}

			while let sample = try await group.next() {
				timing("rasterQueueDelay", sample.queueDelay, scene: scene.sceneRevision)
				timing("rasterWorkerWall", sample.wall, scene: scene.sceneRevision)
				timing("rasterWorkerCPU", sample.cpu, scene: scene.sceneRevision)
				if next < jobs.count {
					let job = jobs[next]
					next += 1
					group.addTask { try await RasterWorkers.shared.run(job, delay: settings.rasterDelay) }
				}
			}
		}
		timing("rasterBatchLatency", CACurrentMediaTime() - rasterStart, scene: scene.sceneRevision)
		try Task.checkCancellation()
		guard epoch == scene.surfaceEpoch else {
			throw STNError.cancelled
		}

		count("offscreenSubmissions")
		let seconds = try await commit(buffer, allocations: frame.allocations, buffers: frame.buffers, surface: result)
		guard epoch == scene.surfaceEpoch else {
			throw STNError.cancelled
		}

		programStates.merge(frame.states, uniquingKeysWith: { _, next in next })
		programStates = programStates.filter { frame.activePrograms.contains($0.key) }
		validPrograms.merge(frame.programs, uniquingKeysWith: { _, next in next })
		validPrograms = validPrograms.filter { frame.activePrograms.contains($0.key) }
		let updatedInstances = Set(frame.outputs.keys.map(\.instance))
		programOutputs = programOutputs.filter {
			frame.activePrograms.contains($0.key.instance) && !updatedInstances.contains($0.key.instance)
		}
		programOutputs.merge(frame.outputs, uniquingKeysWith: { _, next in next })
		rasterScales = rasterScales.filter { frame.activeGroups.contains($0.key) }
		previousPlan = plan
		planner.prune()
		timing("offscreenGPU", seconds, scene: scene.sceneRevision)
		timing("preparationLatency", CACurrentMediaTime() - start, scene: scene.sceneRevision)
		count("offscreenCompletions")
		succeeded = true
		lastFailure = nil
		return PreparedFrame(
			scene: scene,
			plan: plan,
			surface: result,
			settings: settings,
			offscreenSeconds: seconds,
			preparationSeconds: CACurrentMediaTime() - start
		)
	}

	private func commit(
		_ buffer: any MTLCommandBuffer,
		allocations: [MetalAllocation],
		buffers: [MetalBuffer],
		surface: MetalSurface
	) async throws -> Double {
		let readLease = GPUReadLease(allocations: allocations, buffers: buffers, surface: surface)
		return try await withCheckedThrowingContinuation { continuation in
			buffer.addCompletedHandler { completed in
				readLease.complete()
				if completed.status == .completed {
					continuation.resume(returning: max(0, completed.gpuEndTime - completed.gpuStartTime))
				} else {
					continuation.resume(
						throwing: MetalFailure(
							completed.error?.localizedDescription ?? "GPU execution failed",
							kind: .execution
						)
					)
				}
			}
			buffer.commit()
		}
	}

	func present(
		_ frame: PreparedFrame,
		layer: MetalLayer,
		onSubmitted: @escaping @MainActor @Sendable () -> Bool,
		onPresented: @escaping @Sendable (Double) -> Void
	) async throws -> Double? {
		guard frame.scene.surfaceEpoch == epoch,
			let buffer = queue.makeCommandBuffer()
		else {
			throw STNError.cancelled
		}

		guard let drawable = layer.nextDrawable() else {
			return nil
		}

		count("drawableAcquisitions")
		let texture = drawable.texture
		let expectedFormat: MTLPixelFormat =
			frame.settings.linear && frame.scene.colorMode != .sdr ? .rgba16Float : .bgra8Unorm
		guard texture.width == Int(ceil(frame.scene.size.width * frame.settings.scale)),
			texture.height == Int(ceil(frame.scene.size.height * frame.settings.scale)),
			texture.pixelFormat == expectedFormat
		else {
			// Retry stale pool generations without rerunning offscreen/temporal work.
			return nil
		}

		let encoder = try encoder(buffer, target: texture, clear: true)
		var ended = false
		defer {
			if !ended {
				encoder.endEncoding()
			}
		}

		let target = CGRect(x: 0, y: 0, width: frame.scene.size.width, height: frame.scene.size.height)
		if let inputs = frame.surface.directInputs {
			for input in inputs {
				let transform = input.group?.anchoredTransform.cgTransform ?? .identity
				guard transform.isInvertible else {
					continue
				}

				for tile in input.surface.tiles where tile.core.applying(transform).intersects(target) {
					var quad = MetalQuad(rect: tile.core, target: target, transform: transform, linear: false)
					quad.uv = SIMD4(
						Float((tile.core.minX - tile.padded.minX) / tile.padded.width),
						Float((tile.core.minY - tile.padded.minY) / tile.padded.height),
						Float(tile.core.width / tile.padded.width),
						Float(tile.core.height / tile.padded.height)
					)
					quad.sourceLinear = input.surface.linear ? 1 : 0
					quad.options.z = Float(input.group?.opacity ?? 1)
					quad.clip = input.group?.bounds.cgRect.vector ?? .zero
					quad.options.x = Float(input.group?.radius ?? 0)
					quad.masked = input.group?.clips == true ? 1 : 0
					try draw(quad, texture: tile.allocation.texture, encoder: encoder, format: texture.pixelFormat)
				}
			}
		} else {
			encoder.setRenderPipelineState(
				try pipeline("stn_present_batch", format: texture.pixelFormat, blends: false)
			)
			let tiles = frame.surface.tiles
			for start in stride(from: 0, to: tiles.count, by: 16) {
				let count = min(16, tiles.count - start)
				var quads = InlineArray<16, MetalQuad>(
					repeating: MetalQuad(rect: .zero, target: target, linear: frame.surface.linear)
				)
				var images = Array<(any MTLTexture)?>(repeating: tiles[start].allocation.texture, count: 16)
				for index in 0..<count {
					let tile = tiles[start + index]
					var quad = MetalQuad(rect: tile.core, target: target, linear: frame.surface.linear)
					quad.uv = SIMD4(
						Float((tile.core.minX - tile.padded.minX) / tile.padded.width),
						Float((tile.core.minY - tile.padded.minY) / tile.padded.height),
						Float(tile.core.width / tile.padded.width),
						Float(tile.core.height / tile.padded.height)
					)
					quad.sourceLinear = frame.settings.linear && frame.scene.colorMode != .sdr ? 1 : 0
					quad.options.w = Float(frame.settings.headroom)
					quads[index] = quad
					let image = tile.allocation.texture
					images[index] = image
					encoder.useResource(image, usage: .read, stages: .fragment)
				}

				withUnsafeBytes(of: &quads) { bytes in
					encoder.setVertexBytes(bytes.baseAddress!, length: MemoryLayout<MetalQuad>.stride * count, index: 0)
					encoder.setFragmentBytes(
						bytes.baseAddress!,
						length: MemoryLayout<MetalQuad>.stride * count,
						index: 0
					)
				}

				encoder.setFragmentTextures(images, range: 0..<16)
				encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
			}
		}

		encoder.endEncoding()
		ended = true
		guard await onSubmitted(), frame.scene.surfaceEpoch == epoch else {
			throw STNError.cancelled
		}

		drawable.addPresentedHandler { drawable in
			let timestamp = drawable.presentedTime
			onPresented(timestamp)
		}
		if frame.scene.targetTimestamp > 0 {
			buffer.present(drawable, atTime: frame.scene.targetTimestamp)
		} else {
			buffer.present(drawable)
		}

		let seconds = try await commit(buffer, allocations: [], buffers: [], surface: frame.surface)
		timing("presentationGPU", seconds, scene: frame.scene.sceneRevision)
		let key = PathKey(linear: frame.surface.linear, direct: frame.surface.directInputs != nil)
		let total = seconds + frame.offscreenSeconds
		pathCosts[key] = pathCosts[key].map { $0 * 0.8 + total * 0.2 } ?? total
		count("presentationSubmissions")
		return seconds
	}

	func readback(_ frame: PreparedFrame) async throws -> STNRenderedImage {
		guard let buffer = queue.makeCommandBuffer() else {
			throw MetalFailure("Readback command buffer unavailable")
		}

		let encoding = FrameEncoding(scene: frame.scene, settings: frame.settings, buffer: buffer)
		let gathered = try capture(frame.surface, region: frame.surface.bounds, frame: encoding)
		guard let texture = gathered.tiles.first?.allocation.texture else {
			throw MetalFailure("No backing to capture")
		}

		let bpp = gathered.linear ? 8 : 4
		let rawRow = texture.width * bpp
		let row = (rawRow + 255) & ~255
		let output = try device.buffer(length: row * texture.height)
		encoding.buffers.append(output)
		guard let blit = buffer.makeBlitCommandEncoder() else {
			throw MetalFailure("Readback encoder unavailable")
		}

		blit.copy(
			from: texture,
			sourceSlice: 0,
			sourceLevel: 0,
			sourceOrigin: MTLOrigin(),
			sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
			to: output.buffer,
			destinationOffset: 0,
			destinationBytesPerRow: row,
			destinationBytesPerImage: row * texture.height
		)
		blit.endEncoding()
		_ = try await commit(
			buffer,
			allocations: encoding.allocations,
			buffers: encoding.buffers,
			surface: frame.surface
		)
		var data = Data(count: rawRow * texture.height)
		data.withUnsafeMutableBytes { destination in
			for y in 0..<texture.height {
				destination.baseAddress!.advanced(by: y * rawRow)
					.copyMemory(from: output.buffer.contents().advanced(by: y * row), byteCount: rawRow)
			}
		}
		return .init(
			width: texture.width,
			height: texture.height,
			format: gathered.linear ? .premultipliedRGBA16Float : .premultipliedBGRA8,
			sceneRevision: frame.scene.sceneRevision,
			data: data
		)
	}

	func report(linear: Bool, confirmed: UInt64?, timestamp: Double?) -> STNRenderingDiagnostics {
		var values = counts
		let accounting = device.accounting
		values["allocatedBytes"] = Double(accounting.bytes)
		values["deviceAccountedBytes"] = Double(accounting.bytes)
		values["driverAllocatedBytes"] = Double(device.device.currentAllocatedSize)
		values["surfaceEpoch"] = Double(epoch)
		values["peakAllocatedBytes"] = Double(accounting.peak)
		values["deviceCapacityBytes"] = Double(accounting.capacity)
		var allocations: [ObjectIdentifier: MetalAllocation] = [:]
		for record in cache.values {
			for tile in record.surface.tiles {
				allocations[ObjectIdentifier(tile.allocation)] = tile.allocation
				if let multisample = tile.multisample { allocations[ObjectIdentifier(multisample)] = multisample }
			}
		}

		values["cacheAccountedBytes"] = Double(allocations.values.reduce(0) { $0 + $1.accountedBytes })
		values["cacheEntries"] = Double(cache.count)
		return .init(
			device: device.device.name,
			workingLinear: linear,
			failure: lastFailure,
			confirmedRevision: confirmed,
			confirmedTime: timestamp,
			counters: values,
			timingSamples: timings
		)
	}

	func failed(_ message: String) {
		lastFailure = message
	}

	func drainDiagnostics() -> [NativeGPUDiagnostic] {
		let result = diagnostics
		diagnostics.removeAll(keepingCapacity: true)
		return result
	}
}
