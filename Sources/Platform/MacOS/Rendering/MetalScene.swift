import Foundation
import Metal
import StanaPrimitives
import StanaScene

extension MetalEncoder {
	func rasterRun(_ tree: CPUCommandTree, scale: Double, visible: CGRect, frame: FrameEncoding) throws -> MetalSurface
	{
		let bounds = tree.bounds

		var tiles: [MetalTile] = []
		for (core, padded) in try layout(bounds, scale: scale, untiled: frame.settings.forceMode == 4, visible: visible)
		{
			let key = SurfaceCacheKey(
				kind: .cpu,
				owner: tree.firstID,
				versions: tree.versions(intersecting: padded),
				bounds: padded.stana,
				scale: scale,
				linear: false,
				epoch: frame.scene.surfaceEpoch,
				untiled: frame.settings.forceMode == 4
			)
			if let cached = cached(key, frame: frame), let tile = cached.tiles.first {
				tiles.append(tile)
				count("tileHits")
				continue
			}

			let allocation = try allocate(
				Int(round(padded.width * scale)),
				Int(round(padded.height * scale)),
				format: .bgra8Unorm,
				raster: true,
				frame: frame
			)
			let tile = MetalTile(version: RenderVersion(), core: core, padded: padded, allocation: allocation)
			frame.rasterJobs.append(
				RasterJob(
					allocation: allocation,
					commands: tree.commands(intersecting: padded),
					padded: padded,
					scale: scale,
					symbolResults: frame.symbolResults,
					epoch: frame.scene.surfaceEpoch
				)
			)
			let version = MetalSurface(version: tile.version, bounds: core, scale: scale, linear: false, tiles: [tile])
			cache(version, for: key, frame: frame)
			tiles.append(tile)
			count("tileMisses")
			count("rasterPixels", allocation.texture.width * allocation.texture.height)
		}

		return MetalSurface(version: RenderVersion(), bounds: bounds, scale: scale, linear: false, tiles: tiles)
	}

	func gpu(_ item: PaintGPUItem, scale: Double, frame: FrameEncoding) throws -> MetalSurface {
		let key = SurfaceCacheKey(
			kind: .gpu,
			owner: item.id,
			versions: [item.version],
			bounds: item.bounds,
			scale: scale,
			linear: frame.settings.linear,
			epoch: frame.scene.surfaceEpoch,
			untiled: frame.settings.forceMode == 4
		)
		if let cached = cached(key, frame: frame) {
			return cached
		}

		let initial = try surface(item.bounds.cgRect, scale: scale, linear: frame.settings.linear, frame: frame)
		var result = initial
		if device.accounting.capacity == device.budget, device.device.supportsTextureSampleCount(4) {
			let tiles = try initial.tiles.map { tile in
				let extra = try device.texture(
					width: tile.allocation.texture.width,
					height: tile.allocation.texture.height,
					format: tile.allocation.texture.pixelFormat,
					samples: 4
				)
				frame.allocations.append(extra)
				count("multisampleBytes", extra.texture.allocatedSize)
				return MetalTile(
					version: tile.version,
					core: tile.core,
					padded: tile.padded,
					allocation: tile.allocation,
					multisample: extra
				)
			}
			result = MetalSurface(
				version: initial.version,
				bounds: initial.bounds,
				scale: initial.scale,
				linear: initial.linear,
				tiles: tiles
			)
		}

		try clear(result, frame: frame)
		let commands = item.drawing.commands
		var index = 0
		while index < commands.count {
			if case .program(let program) = commands[index] {
				let output = try runProgram(
					program,
					instance: .init(node: item.id, backdrop: false, commandIndex: index),
					bounds: result.bounds,
					scale: scale,
					frame: frame
				)
				if let output {
					for tile in result.tiles {
						try drawSurface(output, into: tile, frame: frame)
					}
				}

				index += 1
				continue
			}

			let start = index
			while index < commands.count {
				if case .program = commands[index] {
					break
				}

				index += 1
			}

			for tile in result.tiles {
				let encoder = try encoder(
					frame.buffer,
					target: tile.allocation.texture,
					clear: false,
					multisample: tile.multisample
				)
				defer {
					encoder.endEncoding()
				}

				for command in commands[start..<index] {
					switch command {
					case .rect(let rect, let radius, let color):
						try shape(
							rect,
							radius: radius,
							ellipse: false,
							color: color,
							environment: item.colors,
							bounds: result.bounds,
							tile: tile,
							scale: scale,
							encoder: encoder,
							frame: frame
						)
					case .ellipse(let rect, let color):
						try shape(
							rect,
							radius: 0,
							ellipse: true,
							color: color,
							environment: item.colors,
							bounds: result.bounds,
							tile: tile,
							scale: scale,
							encoder: encoder,
							frame: frame
						)
					case .polyline(let points, let width, let color, let closed):
						guard !points.isEmpty else {
							continue
						}

						var values = points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
						if closed {
							values.append(values[0])
						}

						let buffer = try values.withUnsafeBytes { try makeBuffer(Data($0), frame: frame) }
						var quad = MetalQuad(rect: result.bounds, target: tile.padded, linear: result.linear)
						quad.color = color.vector(in: item.colors)
						quad.sourceLinear = color.linear ? 1 : 0
						quad.options.x = Float(width)
						quad.options.y = Float(values.count)
						encoder.setFragmentBuffer(buffer, offset: 0, index: 1)
						encoder.useResource(buffer, usage: .read, stages: .fragment)
						try draw(
							quad,
							texture: nil,
							encoder: encoder,
							format: tile.allocation.texture.pixelFormat,
							fragment: "stn_line"
						)
					case .mesh(let mesh):
						guard !mesh.vertices.isEmpty, !mesh.indices.isEmpty else {
							continue
						}

						let vertices = mesh.vertices.flatMap { vertex in
							[
								Float(vertex.position.x), Float(vertex.position.y), Float(vertex.color.red),
								Float(vertex.color.green), Float(vertex.color.blue), Float(vertex.color.alpha),
							]
						}
						let vb = try vertices.withUnsafeBytes { try makeBuffer(Data($0), frame: frame) }
						let ib = try mesh.indices.withUnsafeBytes { try makeBuffer(Data($0), frame: frame) }
						var quad = MetalQuad(rect: result.bounds, target: tile.padded, linear: result.linear)
						encoder.setRenderPipelineState(
							try pipeline("stn_mesh_fragment", format: tile.allocation.texture.pixelFormat, mesh: true)
						)
						encoder.setVertexBuffer(vb, offset: 0, index: 0)
						encoder.setVertexBytes(&quad, length: MemoryLayout<MetalQuad>.stride, index: 1)
						encoder.useResource(vb, usage: .read, stages: .vertex)
						encoder.drawIndexedPrimitives(
							type: .triangle,
							indexCount: mesh.indices.count,
							indexType: .uint32,
							indexBuffer: ib,
							indexBufferOffset: 0
						)
					case .program:
						preconditionFailure("Stana: program inside ordinary drawing run")
					}
				}

				count("gpuDrawingEncoders")
			}
		}

		// FrameEncoding retains MSAA scratch through completion; cache only resolved textures.
		let resolved = MetalSurface(
			version: result.version,
			bounds: result.bounds,
			scale: result.scale,
			linear: result.linear,
			tiles: result.tiles.map {
				MetalTile(version: $0.version, core: $0.core, padded: $0.padded, allocation: $0.allocation)
			}
		)
		cache(resolved, for: key, frame: frame)
		count("gpuLeafDraws")
		return resolved
	}

	private func shape(
		_ rect: STNRect,
		radius: Double,
		ellipse: Bool,
		color: GPUColor,
		environment: GPUColorEnvironment,
		bounds: CGRect,
		tile: MetalTile,
		scale: Double,
		encoder: any MTLRenderCommandEncoder,
		frame: FrameEncoding
	) throws {
		let rect = rect.cgRect.offsetBy(dx: bounds.minX, dy: bounds.minY)
		var quad = MetalQuad(
			rect: rect.insetBy(dx: -1 / scale, dy: -1 / scale),
			target: tile.padded,
			linear: frame.settings.linear
		)
		quad.mode = 1
		quad.color = color.vector(in: environment)
		quad.sourceLinear = color.linear ? 1 : 0
		quad.masked = 1
		quad.clip = rect.vector
		quad.options.x = Float(radius)
		quad.options.y = ellipse ? 1 : 0
		try draw(quad, texture: nil, encoder: encoder, format: tile.allocation.texture.pixelFormat)
	}

	struct GroupInput: Sendable {
		let surface: MetalSurface
		let group: PaintGroup?
		var cpuTree: CPUCommandTree? = nil
	}

	func group(
		_ plan: PlannedGroup,
		scale: Double,
		visible: CGRect,
		frame: FrameEncoding,
		root: Bool = false,
		world: STNAffineTransform = .identity
	) throws -> MetalSurface {
		let group = plan.source
		let local = group.anchoredTransform.cgTransform
		var visible = local.isInvertible ? visible.applying(local.inverted()) : .zero
		let bounds = root ? group.bounds.cgRect : plan.bounds.cgRect
		let resolvedWorld = world.concatenating(group.anchoredTransform)
		let scale = chooseRasterScale(
			group.id,
			required: frame.settings.scale * resolvedWorld.maximumScale,
			native: frame.settings.scale
		)
		if group.clips {
			visible = visible.intersection(bounds)
		}

		var reverse = PlannedBranch.Iterator(plan.children, reversed: true)
		while let entry = reverse.next() {
			guard case .group(let child) = entry, let effect = child.source.backdrop else {
				continue
			}

			let transform = child.source.anchoredTransform.cgTransform
			let output = child.source.bounds.cgRect.applying(transform)
			guard output.intersects(visible) else {
				continue
			}

			let radius: Double
			switch effect.operation {
			case .identity: radius = 0
			case .blur(let value): radius = value
			case .program(let program):
				guard let value = program.samplingRadius else {
					visible = bounds
					continue
				}

				radius = value
			}

			let x = (radius + 2 / scale) * (abs(transform.a) + abs(transform.c))
			let y = (radius + 2 / scale) * (abs(transform.b) + abs(transform.d))
			visible = visible.union(output.insetBy(dx: -x, dy: -y).intersection(bounds))
		}

		let key = SurfaceCacheKey(
			kind: .group,
			owner: group.id,
			versions: group.children.root.map { [$0.version] } ?? [],
			bounds: bounds.stana,
			scale: scale,
			linear: frame.settings.linear,
			epoch: frame.scene.surfaceEpoch,
			untiled: frame.settings.forceMode == 4,
			visible: visible.isNull ? .zero : visible.stana
		)
		if !(root && directMode), frame.settings.forceMode < 3, let cached = cached(key, frame: frame) {
			count("groupCacheHits")
			return cached
		}

		retireObsoleteGeneration(for: key)
		let dependencyStart = frame.cacheRecords.count
		var inputs: [GroupInput] = []
		var run: CPUCommandTree?
		try collectInputs(
			plan.children,
			run: &run,
			inputs: &inputs,
			scale: scale,
			visible: visible,
			frame: frame,
			world: resolvedWorld
		)
		try flushCPU(&run, inputs: &inputs, scale: scale, visible: visible, frame: frame)

		let hasBackdrop = inputs.contains { $0.group?.backdrop != nil }
		if root, directMode, !frame.settings.linear, !hasBackdrop {
			return MetalSurface(
				version: RenderVersion(),
				bounds: bounds,
				scale: scale,
				linear: false,
				tiles: [],
				directInputs: inputs
			)
		}

		var outputTiles: [MetalTile] = []
		for (core, padded) in try layout(bounds, scale: scale, untiled: frame.settings.forceMode == 4, visible: visible)
		{
			let versions = inputs.flatMap { input -> [RenderVersion] in
				let transform = input.group?.anchoredTransform.cgTransform ?? .identity
				guard input.surface.bounds.applying(transform).intersects(padded) else {
					return []
				}

				if let tree = input.cpuTree {
					return tree.versions(intersecting: padded)
				}

				var versions: [RenderVersion] = []
				versions += input.surface.tiles.filter { $0.core.applying(transform).intersects(padded) }.map(\.version)
				return versions
			}
			let compositing =
				inputs.filter { input in
					input.surface.bounds.applying(input.group?.anchoredTransform.cgTransform ?? .identity)
						.intersects(padded)
				}
				.map { input in
					CompositingKey(
						transform: input.group?.anchoredTransform ?? .identity,
						opacity: input.group?.opacity ?? 1,
						clip: input.group?.clips == true ? input.group?.bounds : nil,
						radius: input.group?.radius ?? 0
					)
				}
			let tileKey = SurfaceCacheKey(
				kind: .groupTile,
				owner: group.id,
				versions: versions,
				bounds: padded.stana,
				scale: scale,
				linear: frame.settings.linear,
				epoch: frame.scene.surfaceEpoch,
				untiled: frame.settings.forceMode == 4,
				compositing: compositing
			)
			if !hasBackdrop, frame.settings.forceMode < 3, let cached = cached(tileKey, frame: frame),
				let tile = cached.tiles.first
			{
				outputTiles.append(tile)
				count(root ? "finalTileHits" : "groupTileHits")
				continue
			}

			let allocation = try allocate(
				Int(round(padded.width * scale)),
				Int(round(padded.height * scale)),
				format: frame.settings.linear ? .rgba16Float : .bgra8Unorm,
				frame: frame
			)
			let tile = MetalTile(version: RenderVersion(), core: core, padded: padded, allocation: allocation)
			try encoder(frame.buffer, target: allocation.texture, clear: true).endEncoding()
			if !hasBackdrop {
				for input in inputs {
					try drawInput(input, into: tile, frame: frame)
				}

				let version = MetalSurface(
					version: tile.version,
					bounds: core,
					scale: scale,
					linear: frame.settings.linear,
					tiles: [tile]
				)
				cache(version, for: tileKey, frame: frame)
			}

			outputTiles.append(tile)
			count(
				root ? "finalPixelsRedrawn" : "groupPixelsRedrawn",
				allocation.texture.width * allocation.texture.height
			)
		}

		var result = MetalSurface(
			version: RenderVersion(),
			bounds: bounds,
			scale: scale,
			linear: frame.settings.linear,
			tiles: outputTiles
		)
		if hasBackdrop {
			var contributors: [GroupInput] = []
			for input in inputs {
				if let group = input.group, group.backdrop != nil {
					result = try replaceBackdrop(
						group,
						context: result,
						contextID: plan.source.id,
						contributors: contributors,
						foreground: input.surface,
						frame: frame
					)
				} else {
					for tile in result.tiles {
						try drawInput(input, into: tile, frame: frame)
					}
				}

				contributors.append(input)
			}
		}

		cache(result, for: key, frame: frame, dependencyStart: dependencyStart)
		return result
	}

	private func chooseRasterScale(_ node: STNNodeID, required: Double, native: Double) -> Double {
		let now = ProcessInfo.processInfo.systemUptime
		let chosen =
			required <= native ? native : native * pow(sqrt(2), ceil(log(required * 1.125 / native) / log(sqrt(2))))
		var value = rasterScales[node] ?? (scale: chosen, lowSince: 0)
		if required > value.scale * 1.05 {
			value = (chosen, 0)
		} else if required <= value.scale * 0.5 {
			if value.lowSince == 0 {
				value.lowSince = now
			}

			if now - value.lowSince >= 0.5 {
				value = (chosen, 0)
			}
		} else {
			value.lowSince = 0
		}

		if value.scale > 8 {
			count("resolutionLimitedSurfaces")
		}

		value.scale = min(8, max(native, value.scale))
		rasterScales[node] = value
		return value.scale
	}

	private func flushCPU(
		_ run: inout CPUCommandTree?,
		inputs: inout [GroupInput],
		scale: Double,
		visible: CGRect,
		frame: FrameEncoding
	) throws {
		guard let tree = run else {
			return
		}

		inputs.append(
			GroupInput(
				surface: try rasterRun(tree, scale: scale, visible: visible, frame: frame),
				group: nil,
				cpuTree: tree
			)
		)
		run = nil
	}

	private func collectInputs(
		_ branch: PlannedBranch?,
		run: inout CPUCommandTree?,
		inputs: inout [GroupInput],
		scale: Double,
		visible: CGRect,
		frame: FrameEncoding,
		world: STNAffineTransform
	) throws {
		guard let branch else {
			return
		}

		if branch.allCPU {
			let tree = CPUCommandTree(branch: branch)
			run = run.map { CPUCommandTree($0, tree) } ?? tree
			return
		}

		try collectInputs(
			branch.left,
			run: &run,
			inputs: &inputs,
			scale: scale,
			visible: visible,
			frame: frame,
			world: world
		)
		switch branch.entry {
		case .cpu(let item):
			let leaf = CPUCommandTree(leaf: item)
			run = run.map { CPUCommandTree($0, leaf) } ?? leaf
		case .gpu(let item):
			try flushCPU(&run, inputs: &inputs, scale: scale, visible: visible, frame: frame)
			inputs.append(GroupInput(surface: try gpu(item, scale: scale, frame: frame), group: nil))
		case .group(let nested):
			try flushCPU(&run, inputs: &inputs, scale: scale, visible: visible, frame: frame)
			let result = try group(nested, scale: scale, visible: visible, frame: frame, world: world)
			inputs.append(GroupInput(surface: result, group: nested.source))
		}

		try collectInputs(
			branch.right,
			run: &run,
			inputs: &inputs,
			scale: scale,
			visible: visible,
			frame: frame,
			world: world
		)
	}

	func drawInput(_ input: GroupInput, into tile: MetalTile, frame: FrameEncoding) throws {
		try drawSurface(
			input.surface,
			into: tile,
			frame: frame,
			transform: input.group?.anchoredTransform.cgTransform ?? .identity,
			opacity: input.group?.opacity ?? 1,
			clip: input.group?.bounds.cgRect ?? .zero,
			radius: input.group?.radius ?? 0,
			masked: input.group?.clips ?? false
		)
	}

	func capture(_ surface: MetalSurface, region: CGRect, frame: FrameEncoding) throws -> MetalSurface {
		if let inputs = surface.directInputs {
			let materialized = try self.surface(
				surface.bounds,
				scale: surface.scale,
				linear: surface.linear,
				frame: frame
			)
			try clear(materialized, frame: frame)
			for tile in materialized.tiles {
				for input in inputs {
					try drawInput(input, into: tile, frame: frame)
				}
			}

			return try capture(materialized, region: region, frame: frame)
		}

		let scale = surface.scale
		let x = floor(region.minX * scale) / scale, y = floor(region.minY * scale) / scale
		let bounds = CGRect(
			x: x,
			y: y,
			width: ceil(region.maxX * scale) / scale - x,
			height: ceil(region.maxY * scale) / scale - y
		)
		let allocation = try allocate(
			Int(round(bounds.width * scale)),
			Int(round(bounds.height * scale)),
			format: surface.linear ? .rgba16Float : .bgra8Unorm,
			frame: frame
		)
		let tile = MetalTile(version: RenderVersion(), core: bounds, padded: bounds, allocation: allocation)
		try encoder(frame.buffer, target: allocation.texture, clear: true).endEncoding()
		try drawSurface(surface, into: tile, frame: frame)
		count("prefixCopyBytes", allocation.texture.width * allocation.texture.height * (surface.linear ? 8 : 4) * 2)
		return MetalSurface(
			version: RenderVersion(),
			bounds: bounds,
			scale: scale,
			linear: surface.linear,
			tiles: [tile]
		)
	}

	func blur(_ input: MetalSurface, radius: Double, transform: CGAffineTransform, frame: FrameEncoding) throws
		-> MetalSurface
	{
		guard radius > 0 else {
			return input
		}

		let trace =
			transform.a * transform.a + transform.b * transform.b + transform.c * transform.c + transform.d
			* transform.d
		let determinant = transform.a * transform.d - transform.b * transform.c
		let localScale =
			input.scale * sqrt(max(0, (trace + sqrt(max(0, trace * trace - 4 * determinant * determinant))) / 2))
		guard localScale.isFinite, localScale > 0, radius * localScale <= 16_384, let tile = input.tiles.first else {
			throw MetalFailure("Invalid backdrop filter scale or radius")
		}

		let source = tile.allocation.texture
		let scratch = try allocate(source.width, source.height, format: source.pixelFormat, frame: frame)
		let output = try allocate(source.width, source.height, format: source.pixelFormat, frame: frame)
		let pipeline = try compute("stn_blur")
		struct Parameters: BitwiseCopyable {
			var width, height, radius, horizontal: UInt32
			var direction: SIMD2<Float>
		}
		for index in 0..<2 {
			let read = index == 0 ? source : scratch.texture
			let write = index == 0 ? scratch.texture : output.texture
			guard let encoder = frame.buffer.makeComputeCommandEncoder() else {
				throw MetalFailure("Blur encoder unavailable")
			}

			encoder.setComputePipelineState(pipeline)
			encoder.setTexture(read, index: 0)
			encoder.setTexture(write, index: 1)
			encoder.useResource(read, usage: .read)
			encoder.useResource(write, usage: .write)
			let direction = index == 0 ? (x: transform.a, y: transform.b) : (x: transform.c, y: transform.d)
			var parameters = Parameters(
				width: UInt32(source.width),
				height: UInt32(source.height),
				radius: UInt32(ceil(radius * localScale)),
				horizontal: index == 0 ? 1 : 0,
				direction: SIMD2(
					Float(direction.x * input.scale / localScale),
					Float(direction.y * input.scale / localScale)
				)
			)
			encoder.setBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
			encoder.dispatchThreads(
				MTLSize(width: source.width, height: source.height, depth: 1),
				threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
			)
			encoder.endEncoding()
		}

		count("filterPasses", 2)
		let replacement = MetalTile(version: RenderVersion(), core: tile.core, padded: tile.padded, allocation: output)
		return MetalSurface(
			version: RenderVersion(),
			bounds: input.bounds,
			scale: input.scale,
			linear: input.linear,
			tiles: [replacement]
		)
	}

	func replaceBackdrop(
		_ group: PaintGroup,
		context: MetalSurface,
		contextID: STNNodeID,
		contributors: [GroupInput],
		foreground: MetalSurface,
		frame: FrameEncoding
	) throws -> MetalSurface {
		guard let effect = group.backdrop else {
			return context
		}

		let transform = group.anchoredTransform.cgTransform
		guard transform.isInvertible else {
			return context
		}

		let output = group.bounds.cgRect.applying(transform)
		guard output.intersects(context.bounds) else {
			return context
		}

		let radius: Double
		let nonlocal: Bool
		switch effect.operation {
		case .identity:
			radius = 0
			nonlocal = false
		case .blur(let value):
			radius = value
			nonlocal = false
		case .program(let value):
			radius = value.samplingRadius ?? 0
			nonlocal = value.samplingRadius == nil
		}

		let expandX = (radius + 2 / context.scale) * (abs(transform.a) + abs(transform.c))
		let expandY = (radius + 2 / context.scale) * (abs(transform.b) + abs(transform.d))
		let region = nonlocal ? context.bounds : output.insetBy(dx: -expandX, dy: -expandY).intersection(context.bounds)
		var versions: [RenderVersion] = []
		var composites: [CompositingKey] = []
		for contributor in contributors {
			let transform = contributor.group?.anchoredTransform.cgTransform ?? .identity
			guard contributor.surface.bounds.applying(transform).intersects(region) else {
				continue
			}

			count("backdropDependencyVisits")
			if let tree = contributor.cpuTree {
				versions += tree.versions(intersecting: region)
			} else {
				versions += contributor.surface.tiles.filter { $0.core.applying(transform).intersects(region) }
					.map(\.version)
			}

			if let node = contributor.group, let effect = frame.effectVersions[node.id] {
				versions.append(effect)
			}

			composites.append(
				CompositingKey(
					transform: contributor.group?.anchoredTransform ?? .identity,
					opacity: contributor.group?.opacity ?? 1,
					clip: contributor.group?.clips == true ? contributor.group?.bounds : nil,
					radius: contributor.group?.radius ?? 0
				)
			)
		}

		let descriptor: BackdropCacheEffect
		switch effect.operation {
		case .identity: descriptor = .identity
		case .blur(let radius): descriptor = .blur(radius)
		case .program(let program): descriptor = .program(program.version)
		}

		composites.append(CompositingKey(transform: group.anchoredTransform, opacity: 1, clip: group.bounds, radius: 0))
		let key = SurfaceCacheKey(
			kind: .backdrop,
			owner: group.id,
			versions: versions,
			bounds: region.stana,
			scale: context.scale,
			linear: context.linear,
			epoch: frame.scene.surfaceEpoch,
			untiled: frame.settings.forceMode == 4,
			compositing: composites,
			visible: context.bounds.stana,
			effect: descriptor,
			context: contextID
		)
		var filtered: MetalSurface
		if let existing = cached(key, frame: frame) {
			filtered = existing
			count("backdropCacheHits")
		} else {
			filtered = try capture(context, region: region, frame: frame)
			switch effect.operation {
			case .identity: break
			case .blur(let radius): filtered = try blur(filtered, radius: radius, transform: transform, frame: frame)
			case .program(let program):
				guard
					let result = try runProgram(
						program,
						instance: .init(node: group.id, backdrop: true, commandIndex: 0),
						bounds: filtered.bounds,
						scale: context.scale,
						backdrop: filtered,
						backdropGroup: group,
						frame: frame
					)
				else {
					return context
				}

				filtered = result
			}

			if filtered.linear != context.linear {
				let converted = try surface(
					filtered.bounds,
					scale: filtered.scale,
					linear: context.linear,
					frame: frame
				)
				try clear(converted, frame: frame)
				for tile in converted.tiles {
					try drawSurface(filtered, into: tile, frame: frame)
				}

				filtered = try capture(converted, region: filtered.bounds, frame: frame)
			}

			cache(filtered, for: key, frame: frame)
			count("backdropCacheMisses")
		}

		frame.effectVersions[group.id] = filtered.version

		let fg = try capture(foreground, region: foreground.bounds, frame: frame)
		let pipeline = try compute("stn_replace")
		let inverse = transform.inverted()
		struct Parameters: BitwiseCopyable {
			var context, panel, row0, row1, options, source, foreground: SIMD4<Float>
		}
		var tiles: [MetalTile] = []
		for tile in context.tiles {
			let allocation = try allocate(
				tile.allocation.texture.width,
				tile.allocation.texture.height,
				format: tile.allocation.texture.pixelFormat,
				frame: frame
			)
			guard let encoder = frame.buffer.makeComputeCommandEncoder() else {
				throw MetalFailure("Backdrop encoder unavailable")
			}

			encoder.setComputePipelineState(pipeline)
			let textures = [
				tile.allocation.texture, filtered.tiles[0].allocation.texture, fg.tiles[0].allocation.texture,
				allocation.texture,
			]
			for (index, texture) in textures.enumerated() {
				encoder.setTexture(texture, index: index)
				encoder.useResource(texture, usage: index == 3 ? .write : .read)
			}

			let identity: Bool
			if case .identity = effect.operation {
				identity = true
			} else {
				identity = false
			}

			var parameters = Parameters(
				context: tile.padded.vector,
				panel: group.bounds.cgRect.vector,
				row0: SIMD4(Float(inverse.a), Float(inverse.c), Float(inverse.tx), 0),
				row1: SIMD4(Float(inverse.b), Float(inverse.d), Float(inverse.ty), 0),
				options: SIMD4(Float(context.scale), Float(group.radius), Float(group.opacity), identity ? 1 : 0),
				source: filtered.bounds.vector,
				foreground: fg.bounds.vector
			)
			encoder.setBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
			encoder.dispatchThreads(
				MTLSize(width: allocation.texture.width, height: allocation.texture.height, depth: 1),
				threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
			)
			encoder.endEncoding()
			tiles.append(
				MetalTile(version: RenderVersion(), core: tile.core, padded: tile.padded, allocation: allocation)
			)
		}

		count("backdropCaptures")
		return MetalSurface(
			version: RenderVersion(),
			bounds: context.bounds,
			scale: context.scale,
			linear: context.linear,
			tiles: tiles
		)
	}
}

extension GPUColor {
	func vector(in environment: GPUColorEnvironment) -> SIMD4<Float> {
		let values = resolved(in: environment)
		return SIMD4(Float(values[0]), Float(values[1]), Float(values[2]), Float(values[3]))
	}
}
