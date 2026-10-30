import Foundation
import Metal
import StanaPrimitives
import StanaScene

struct ProgramInstance: Hashable, Sendable {
	let node: STNNodeID
	let backdrop: Bool
	let commandIndex: Int
}

struct ProgramState: Sendable {
	let version: RenderVersion
	let slots: [String: MetalAllocation]
	let step: UInt64
}

struct ProgramOutputKey: Hashable, Sendable {
	let instance: ProgramInstance
	let version: RenderVersion
	let bounds: STNRect
	let scale: Double
	let epoch: UInt64
	let backdrop: RenderVersion?
}

struct CompiledProgram {
	enum Pass {
		case render(any MTLRenderPipelineState, MTLRenderPipelineReflection)

		case compute(any MTLComputePipelineState, MTLComputePipelineReflection)
	}

	let library: any MTLLibrary
	let passes: [Pass]
}

extension STNGPUTextureFormat {
	var metal: MTLPixelFormat {
		switch self {
		case .bgra8Unorm: .bgra8Unorm
		case .rgba16Float: .rgba16Float
		case .r8Unorm: .r8Unorm
		}
	}
}

extension STNGPUResource {
	var textureFormat: MTLPixelFormat {
		switch self {
		case .texture(let texture): texture.format.metal
		case .target(_, _, let format): format.metal
		case .state(let state): state.format.metal
		default: .rgba16Float
		}
	}

	var bindingKind: MTLBindingType {
		switch self {
		case .buffer, .storage: .buffer
		case .sampler: .sampler
		default: .texture
		}
	}
}

extension MetalEncoder {
	func function(_ name: String, library: any MTLLibrary, constants: [String: STNGPUFunctionConstant]) throws
		-> any MTLFunction
	{
		guard !constants.isEmpty else {
			guard let function = library.makeFunction(name: name) else {
				throw MetalFailure("Missing shader entry point: \(name)")
			}

			return function
		}

		let values = MTLFunctionConstantValues()
		for (name, constant) in constants {
			switch constant {
			case .bool(var value): values.setConstantValue(&value, type: .bool, withName: name)
			case .int(var value): values.setConstantValue(&value, type: .int, withName: name)
			case .float(var value): values.setConstantValue(&value, type: .float, withName: name)
			}
		}

		return try library.makeFunction(name: name, constantValues: values)
	}

	func validate(_ bindings: [any MTLBinding], pass: STNGPUPass, stage: STNGPUBinding.Stage, program: STNGPUProgram)
		throws
	{
		for reflected in bindings where reflected.isUsed && reflected.isArgument {
			guard
				let declared = pass.bindings.first(where: { binding in
					let kind =
						binding.resource == "$backdropCoordinates"
						? MTLBindingType.buffer
						: program.resources[binding.resource]?.bindingKind ?? .texture
					return binding.stage == stage && binding.index == reflected.index && kind == reflected.type
				}), reflected.access == .readOnly || declared.access == .write
			else {
				throw STNGPUError.binding("Missing or incompatible \(stage) binding at \(reflected.index)")
			}

			if let texture = reflected as? any MTLTextureBinding,
				texture.textureType != .type2D || texture.arrayLength > 1
			{
				throw STNGPUError.binding("Only declared two-dimensional texture bindings are supported")
			}

			if let buffer = reflected as? any MTLBufferBinding, declared.resource != "$backdropCoordinates" {
				let length: Int
				switch program.resources[declared.resource] {
				case .buffer(let value): length = value.data.count
				case .storage(let value): length = value
				default: length = 0
				}

				guard length >= buffer.bufferDataSize else {
					throw STNGPUError.binding("Buffer is shorter than the reflected argument")
				}
			}
		}
	}

	func compile(_ program: STNGPUProgram) throws -> CompiledProgram {
		if let cached = applicationPipelines[program.pipelineVersion] {
			for (index, compiled) in cached.passes.enumerated() {
				let pass = program.passes[program.executionOrder[index]]
				switch compiled {
				case .compute(_, let reflection):
					try validate(reflection.bindings, pass: pass, stage: .compute, program: program)
				case .render(_, let reflection):
					try validate(reflection.vertexBindings, pass: pass, stage: .vertex, program: program)
					try validate(reflection.fragmentBindings, pass: pass, stage: .fragment, program: program)
				}
			}

			count("applicationPipelineHits")
			return cached
		}

		let library: any MTLLibrary
		switch program.shader {
		case .metalSource(let source): library = try device.device.makeLibrary(source: source, options: nil)
		case .metalLibrary(let bytes):
			let data = bytes.withUnsafeBytes { DispatchData(bytes: $0) }
			library = try device.device.makeLibrary(data: data)
		}

		var passes: [CompiledProgram.Pass] = []
		for index in program.executionOrder {
			let pass = program.passes[index]
			switch pass {
			case .compute(let compute):
				let function = try function(compute.function, library: library, constants: program.constants)
				var reflection: MTLComputePipelineReflection?
				let pipeline = try device.device.makeComputePipelineState(
					function: function,
					options: .bindingInfo,
					reflection: &reflection
				)
				guard let reflection else {
					throw MetalFailure("Missing compute reflection")
				}

				try validate(reflection.bindings, pass: pass, stage: .compute, program: program)
				passes.append(.compute(pipeline, reflection))
			case .render(let render):
				let descriptor = MTLRenderPipelineDescriptor()
				descriptor.vertexFunction = try function(render.vertex, library: library, constants: program.constants)
				descriptor.fragmentFunction = try function(
					render.fragment,
					library: library,
					constants: program.constants
				)
				descriptor.colorAttachments[0].pixelFormat = program.resources[render.target]!.textureFormat
				descriptor.colorAttachments[0].isBlendingEnabled = render.blends
				descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
				descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
				descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
				descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
				var reflection: MTLRenderPipelineReflection?
				let pipeline = try device.device.makeRenderPipelineState(
					descriptor: descriptor,
					options: .bindingInfo,
					reflection: &reflection
				)
				guard let reflection else {
					throw MetalFailure("Missing render reflection")
				}

				try validate(reflection.vertexBindings, pass: pass, stage: .vertex, program: program)
				try validate(reflection.fragmentBindings, pass: pass, stage: .fragment, program: program)
				passes.append(.render(pipeline, reflection))
			}
		}

		let result = CompiledProgram(library: library, passes: passes)
		if applicationPipelines.count >= 64 {
			applicationPipelines.removeAll(keepingCapacity: true)
		}

		applicationPipelines[program.pipelineVersion] = result
		count("applicationPipelineMisses")
		return result
	}

	func upload(_ data: Data, to texture: any MTLTexture, frame: FrameEncoding) throws {
		let width = texture.width, height = texture.height
		let bpp = texture.pixelFormat == .rgba16Float ? 8 : texture.pixelFormat == .r8Unorm ? 1 : 4
		let raw = width * bpp
		let row = (raw + 255) & ~255
		guard data.count == raw * height, row <= 268_435_456 / height else {
			throw MetalFailure("Texture upload length or stride is invalid")
		}

		var padded = Data(count: row * height)
		padded.withUnsafeMutableBytes { destination in
			data.withUnsafeBytes { source in
				for y in 0..<height {
					destination.baseAddress!.advanced(by: y * row)
						.copyMemory(from: source.baseAddress!.advanced(by: y * raw), byteCount: raw)
				}
			}
		}

		let buffer = try makeBuffer(padded, frame: frame)
		guard let encoder = frame.buffer.makeBlitCommandEncoder() else {
			throw MetalFailure("Upload encoder unavailable")
		}

		encoder.copy(
			from: buffer,
			sourceOffset: 0,
			sourceBytesPerRow: row,
			sourceBytesPerImage: row * height,
			sourceSize: MTLSize(width: width, height: height, depth: 1),
			to: texture,
			destinationSlice: 0,
			destinationLevel: 0,
			destinationOrigin: MTLOrigin()
		)
		encoder.endEncoding()
	}

	func runProgram(
		_ requested: STNGPUProgram,
		instance: ProgramInstance,
		bounds: CGRect,
		scale: Double,
		backdrop: MetalSurface? = nil,
		backdropGroup: PaintGroup? = nil,
		frame: FrameEncoding
	) throws -> MetalSurface? {
		var program = requested
		let compiled: CompiledProgram
		do {
			compiled = try compile(program)
		} catch {
			let category: STNGPUDiagnostic.Category
			if case STNGPUError.binding = error {
				category = .binding
			} else {
				category = .compiler
			}

			if diagnostics.count >= 256 {
				diagnostics.removeFirst()
			}

			diagnostics.append(
				.init(
					node: instance.node,
					diagnostic: .init(
						category: category,
						programVersion: String(requested.version.rawValue),
						message: String(describing: error),
						instance: instance.node.description
					)
				)
			)
			guard let previous = validPrograms[instance] else {
				return nil
			}

			program = previous
			compiled = try compile(program)
		}

		frame.programs[instance] = program
		let key = ProgramOutputKey(
			instance: instance,
			version: program.version,
			bounds: bounds.stana,
			scale: scale,
			epoch: frame.scene.surfaceEpoch,
			backdrop: backdrop?.version
		)
		if let cached = programOutputs[key] {
			frame.outputs[key] = cached
			return cached
		}

		var textures: [String: any MTLTexture] = [:]
		var buffers: [String: any MTLBuffer] = [:]
		var samplers: [String: any MTLSamplerState] = [:]
		var previous: [String: any MTLTexture] = [:]
		var nextState: [String: MetalAllocation] = [:]
		var owners: [String: MetalAllocation] = [:]
		let committed = programStates[instance]
		let sameEpoch = committed?.version == program.stateVersion
		for (name, resource) in program.resources {
			var data: Data?
			var width = Int(ceil(bounds.width * scale)), height = Int(ceil(bounds.height * scale))
			switch resource {
			case .sampler(let sampler):
				let descriptor = MTLSamplerDescriptor()
				descriptor.minFilter = sampler.filter == .nearest ? .nearest : .linear
				descriptor.magFilter = descriptor.minFilter
				descriptor.sAddressMode = .clampToZero
				descriptor.tAddressMode = .clampToZero
				guard let value = device.device.makeSamplerState(descriptor: descriptor) else {
					throw MetalFailure("Sampler allocation failed")
				}

				samplers[name] = value
				continue
			case .buffer(let buffer):
				buffers[name] = try makeBuffer(buffer.data, frame: frame)
				continue
			case .storage(let length):
				let owner = try device.buffer(length: length)
				frame.buffers.append(owner)
				let encoder = frame.buffer.makeBlitCommandEncoder()!
				encoder.fill(buffer: owner.buffer, range: 0..<length, value: 0)
				encoder.endEncoding()
				buffers[name] = owner.buffer
				continue
			case .target(let w, let h, _):
				width = w == 0 ? width : w
				height = h == 0 ? height : h
			case .texture(let texture):
				width = texture.width
				height = texture.height
				data = texture.data
			case .state(let state):
				width = state.width
				height = state.height
				data = state.initialData
			}

			let allocation = try allocate(width, height, format: resource.textureFormat, frame: frame)
			owners[name] = allocation
			textures[name] = allocation.texture
			var uploadTarget = allocation.texture
			if case .state = resource {
				let old: MetalAllocation
				if sameEpoch, let cached = committed?.slots[name] {
					old = cached
					data = nil
				} else {
					old = try allocate(width, height, format: resource.textureFormat, frame: frame)
					try encoder(frame.buffer, target: old.texture, clear: true).endEncoding()
				}

				frame.allocations.append(old)
				previous[name] = old.texture
				uploadTarget = old.texture
				nextState[name] = allocation
			}

			if let data {
				try upload(data, to: uploadTarget, frame: frame)
			}

			if case .texture(let source) = resource, source.format != .r8Unorm {
				let sourceLinear = source.colorEncoding == .extendedLinear
				let linear = program.outputColor == .extendedLinear
				if sourceLinear != linear || !source.premultiplied {
					let converted = try allocate(
						width,
						height,
						format: linear ? .rgba16Float : .bgra8Unorm,
						frame: frame
					)
					let render = try encoder(frame.buffer, target: converted.texture, clear: true)
					let rect = CGRect(x: 0, y: 0, width: width, height: height)
					var quad = MetalQuad(rect: rect, target: rect, linear: linear)
					quad.sourceLinear = sourceLinear ? 1 : 0
					quad.mode = source.premultiplied ? 0 : 2
					try draw(
						quad,
						texture: allocation.texture,
						encoder: render,
						format: converted.texture.pixelFormat,
						blends: false
					)
					render.endEncoding()
					textures[name] = converted.texture
					owners[name] = converted
					count("colorIngressPasses")
				}
			}
		}

		if let backdrop, let tile = backdrop.tiles.first, let group = backdropGroup {
			textures["$backdrop"] = tile.allocation.texture
			let transform = group.anchoredTransform.cgTransform
			let inverse = transform.inverted()
			let coordinates: [SIMD4<Float>] = [
				backdrop.bounds.vector, group.bounds.cgRect.vector,
				SIMD4(Float(transform.a), Float(transform.c), Float(transform.tx), 0),
				SIMD4(Float(transform.b), Float(transform.d), Float(transform.ty), 0),
				SIMD4(Float(inverse.a), Float(inverse.c), Float(inverse.tx), 0),
				SIMD4(Float(inverse.b), Float(inverse.d), Float(inverse.ty), 0),
				SIMD4(Float(backdrop.scale), backdrop.linear ? 1 : 0, 0, 0),
			]
			buffers["$backdropCoordinates"] = try coordinates.withUnsafeBytes { try makeBuffer(Data($0), frame: frame) }
		}

		for (index, compiledPass) in compiled.passes.enumerated() {
			let pass = program.passes[program.executionOrder[index]]
			switch (pass, compiledPass) {
			case (.compute(let compute), .compute(let pipeline, _)):
				guard let encoder = frame.buffer.makeComputeCommandEncoder() else {
					throw MetalFailure("Application compute encoder unavailable")
				}

				defer {
					encoder.endEncoding()
				}

				encoder.setComputePipelineState(pipeline)
				for binding in compute.bindings {
					let texture = binding.previous ? previous[binding.resource] : textures[binding.resource]
					if let texture {
						encoder.setTexture(texture, index: binding.index)
						encoder.useResource(texture, usage: binding.access == .write ? .write : .read)
					} else if let sampler = samplers[binding.resource] {
						encoder.setSamplerState(sampler, index: binding.index)
					} else if let buffer = buffers[binding.resource] {
						encoder.setBuffer(buffer, offset: 0, index: binding.index)
						encoder.useResource(buffer, usage: binding.access == .write ? .write : .read)
					} else {
						throw MetalFailure("Missing application compute resource")
					}
				}

				let width = min(8, pipeline.threadExecutionWidth)
				let height = min(8, pipeline.maxTotalThreadsPerThreadgroup / width)
				encoder.dispatchThreads(
					MTLSize(width: compute.width, height: compute.height, depth: compute.depth),
					threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
				)
			case (.render(let render), .render(let pipeline, _)):
				guard let target = textures[render.target] else {
					throw MetalFailure("Missing application render target")
				}

				let encoder = try encoder(frame.buffer, target: target, clear: true)
				defer {
					encoder.endEncoding()
				}

				encoder.setRenderPipelineState(pipeline)
				for binding in render.bindings {
					let texture = binding.previous ? previous[binding.resource] : textures[binding.resource]
					if let texture {
						if binding.stage == .vertex {
							encoder.setVertexTexture(texture, index: binding.index)
						} else {
							encoder.setFragmentTexture(texture, index: binding.index)
						}

						encoder.useResource(
							texture,
							usage: binding.access == .write ? .write : .read,
							stages: binding.stage == .vertex ? .vertex : .fragment
						)
					} else if let sampler = samplers[binding.resource] {
						if binding.stage == .vertex {
							encoder.setVertexSamplerState(sampler, index: binding.index)
						} else {
							encoder.setFragmentSamplerState(sampler, index: binding.index)
						}
					} else if let buffer = buffers[binding.resource] {
						if binding.stage == .vertex {
							encoder.setVertexBuffer(buffer, offset: 0, index: binding.index)
						} else {
							encoder.setFragmentBuffer(buffer, offset: 0, index: binding.index)
						}

						encoder.useResource(
							buffer,
							usage: binding.access == .write ? .write : .read,
							stages: binding.stage == .vertex ? .vertex : .fragment
						)
					} else {
						throw MetalFailure("Missing application render resource")
					}
				}

				if let name = render.indexBuffer, let indices = buffers[name] {
					encoder.drawIndexedPrimitives(
						type: .triangle,
						indexCount: render.vertexCount,
						indexType: .uint32,
						indexBuffer: indices,
						indexBufferOffset: 0,
						instanceCount: render.instanceCount
					)
				} else {
					encoder.drawPrimitives(
						type: .triangle,
						vertexStart: 0,
						vertexCount: render.vertexCount,
						instanceCount: render.instanceCount
					)
				}
			default:
				throw MetalFailure("Compiled pass mismatch")
			}
		}

		if !nextState.isEmpty {
			var step = sameEpoch ? committed!.step : 0
			nextRevision(&step)
			frame.states[instance] = ProgramState(version: program.stateVersion, slots: nextState, step: step)
		}

		guard let owner = owners[program.output] else {
			throw MetalFailure("Program output is not a texture")
		}

		let tile = MetalTile(version: RenderVersion(), core: bounds, padded: bounds, allocation: owner)
		let result = MetalSurface(
			version: RenderVersion(),
			bounds: bounds,
			scale: scale,
			linear: program.outputColor == .extendedLinear,
			tiles: [tile]
		)
		frame.outputs[key] = result
		count("programPasses", compiled.passes.count)
		return result
	}
}
