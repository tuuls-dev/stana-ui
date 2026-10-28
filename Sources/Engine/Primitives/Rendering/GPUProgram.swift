import Foundation

public enum STNGPUError: Error, Equatable, Sendable {
	case invalidDescriptor(String)
	case compiler(String)
	case binding(String)
	case capability(String)
	case execution(String)
}

public struct STNGPUDiagnostic: Equatable, Sendable, Codable {
	public enum Category: String, Sendable, Codable {
		case compiler, binding, capability, execution
	}

	public let category: Category
	public let programVersion: String
	public let message: String
	public let instance: String
}

public enum STNGPUColorEncoding: String, Sendable, Codable {
	case encodedSRGB, extendedLinear
}

public enum STNGPUTextureFormat: String, Sendable, Codable {
	case bgra8Unorm, rgba16Float, r8Unorm

	package var bytesPerPixel: Int {
		switch self {
		case .bgra8Unorm: 4
		case .rgba16Float: 8
		case .r8Unorm: 1
		}
	}
}

public enum STNGPUShader: Equatable, Sendable {
	case metalSource(String)
	/// Bytes loaded from application/package resources, never a working-directory path.
	case metalLibrary(Data)
}

public struct STNGPUBuffer: Equatable, Sendable {
	package let version = UUID()
	public let data: Data

	public init(data: Data) {
		self.data = data
	}

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.version == rhs.version
	}
}

public struct STNGPUTexture: Equatable, Sendable {
	package let version = UUID()
	public let width: Int
	public let height: Int
	public let format: STNGPUTextureFormat
	public let data: Data
	public let colorEncoding: STNGPUColorEncoding
	public let premultiplied: Bool
	public let sourcePeak: Double

	public init(
		width: Int,
		height: Int,
		format: STNGPUTextureFormat,
		data: Data,
		colorEncoding: STNGPUColorEncoding = .encodedSRGB,
		premultiplied: Bool = true,
		sourcePeak: Double = 16
	) throws {
		guard width > 0, height > 0, width <= 16_384, height <= 16_384,
			width <= 268_435_456 / height / format.bytesPerPixel,
			data.count == width * height * format.bytesPerPixel,
			sourcePeak.isFinite, sourcePeak > 0, sourcePeak <= 65_504
		else {
			throw STNGPUError.invalidDescriptor("Texture dimensions, data length, or source peak")
		}

		self.width = width
		self.height = height
		self.format = format
		self.data = data
		self.colorEncoding = colorEncoding
		self.premultiplied = premultiplied
		self.sourcePeak = sourcePeak
	}

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.version == rhs.version
	}
}

public enum STNGPUResource: Equatable, Sendable {
	case buffer(STNGPUBuffer)
	/// Zero-initialized same-step compute storage, with explicit read/write bindings.
	case storage(length: Int)
	case texture(STNGPUTexture)
	/// Zero dimensions select the canvas's current backing dimensions.
	case target(width: Int = 0, height: Int = 0, format: STNGPUTextureFormat = .rgba16Float)
	/// A temporal ping-pong texture, initialized to zero at the start of each epoch.
	case state(STNGPUStateSlot)
	case sampler(STNGPUSampler)
}

public struct STNGPUStateSlot: Equatable, Sendable {
	public let width: Int
	public let height: Int
	public let format: STNGPUTextureFormat
	public let initialData: Data?
	public let resetKey: String

	public init(
		width: Int,
		height: Int,
		format: STNGPUTextureFormat = .rgba16Float,
		initialData: Data? = nil,
		resetKey: String = ""
	) throws {
		guard width > 0, height > 0, width <= 16_384, height <= 16_384,
			width <= 268_435_456 / height / format.bytesPerPixel,
			initialData.map({ $0.count == width * height * format.bytesPerPixel }) ?? true
		else {
			throw STNGPUError.invalidDescriptor("State slot dimensions or initializer")
		}

		self.width = width
		self.height = height
		self.format = format
		self.initialData = initialData
		self.resetKey = resetKey
	}
}

public struct STNGPUSampler: Equatable, Sendable, Codable {
	public enum Filter: String, Sendable, Codable {
		case nearest, linear
	}

	public let filter: Filter

	/// Sampling outside the declared texture extent returns transparent zero.
	public init(filter: Filter = .linear) {
		self.filter = filter
	}
}

public struct STNGPUBinding: Equatable, Sendable, Codable {
	public enum Access: String, Sendable, Codable {
		case read, write
	}

	public enum Stage: String, Sendable, Codable {
		case vertex, fragment, compute
	}

	public let resource: String
	public let index: Int
	public let access: Access
	public let stage: Stage
	public let previous: Bool

	public init(resource: String, index: Int, access: Access = .read, stage: Stage, previous: Bool = false) {
		self.resource = resource
		self.index = index
		self.access = access
		self.stage = stage
		self.previous = previous
	}

	/// A named, read-only input provided only to backdrop effect evaluations.
	public static func backdrop(index: Int, stage: Stage = .fragment) -> Self {
		.init(resource: "$backdrop", index: index, stage: stage)
	}

	public static func backdropCoordinates(index: Int, stage: Stage = .fragment) -> Self {
		.init(resource: "$backdropCoordinates", index: index, stage: stage)
	}
}

public struct STNGPURenderPass: Equatable, Sendable {
	public let vertex: String
	public let fragment: String
	public let target: String
	public let vertexCount: Int
	public let instanceCount: Int
	public let indexBuffer: String?
	public let bindings: [STNGPUBinding]
	public let blends: Bool

	public init(
		vertex: String,
		fragment: String,
		target: String = "output",
		vertexCount: Int = 3,
		instanceCount: Int = 1,
		indexBuffer: String? = nil,
		bindings: [STNGPUBinding] = [],
		blends: Bool = false
	) {
		self.vertex = vertex
		self.fragment = fragment
		self.target = target
		self.vertexCount = vertexCount
		self.instanceCount = instanceCount
		self.indexBuffer = indexBuffer
		self.bindings = bindings
		self.blends = blends
	}
}

public struct STNGPUComputePass: Equatable, Sendable {
	public let function: String
	public let width: Int
	public let height: Int
	public let depth: Int
	public let bindings: [STNGPUBinding]

	public init(function: String, width: Int, height: Int = 1, depth: Int = 1, bindings: [STNGPUBinding]) {
		self.function = function
		self.width = width
		self.height = height
		self.depth = depth
		self.bindings = bindings
	}
}

public enum STNGPUPass: Equatable, Sendable {
	case render(STNGPURenderPass)
	case compute(STNGPUComputePass)

	package var bindings: [STNGPUBinding] {
		switch self {
		case .render(let p): p.bindings
		case .compute(let p): p.bindings
		}
	}
}

public enum STNGPUFunctionConstant: Equatable, Sendable {
	case bool(Bool), int(Int32), float(Float)
}

/// Trusted application shaders, with explicit immutable inputs and pass dependencies.
public struct STNGPUProgram: Equatable, Sendable {
	package let version = UUID()
	package private(set) var pipelineVersion = UUID()
	package private(set) var stateVersion = UUID()
	public let shader: STNGPUShader
	public let resources: [String: STNGPUResource]
	public let passes: [STNGPUPass]
	public let output: String
	public let outputColor: STNGPUColorEncoding
	public let sourcePeak: Double
	public let constants: [String: STNGPUFunctionConstant]
	public let samplingRadius: Double?
	package let executionOrder: [Int]

	public init(
		shader: STNGPUShader,
		resources: [String: STNGPUResource] = ["output": .target()],
		passes: [STNGPUPass],
		output: String = "output",
		outputColor: STNGPUColorEncoding = .extendedLinear,
		sourcePeak: Double = 16,
		constants: [String: STNGPUFunctionConstant] = [:],
		samplingRadius: Double? = nil
	) throws {
		guard !passes.isEmpty, passes.count <= 128, resources.count <= 128,
			sourcePeak.isFinite, sourcePeak > 0, sourcePeak <= 65_504,
			samplingRadius.map({ $0.isFinite && $0 >= 0 }) ?? true,
			let result = resources[output]
		else {
			throw STNGPUError.invalidDescriptor("Program output, bounds, or pass/resource budget")
		}

		switch result {
		case .target, .state: break
		default: throw STNGPUError.invalidDescriptor("Output must be a produced texture")
		}

		for (name, resource) in resources {
			guard !name.isEmpty, !name.hasPrefix("$") else {
				throw STNGPUError.invalidDescriptor("Reserved or empty resource name")
			}

			if case .target(let w, let h, let f) = resource {
				guard w >= 0, h >= 0, w <= 16_384, h <= 16_384,
					w == 0 || h == 0 || w <= 268_435_456 / h / f.bytesPerPixel
				else {
					throw STNGPUError.invalidDescriptor("Target dimensions exceed allocation limit")
				}
			}
			if case .storage(let length) = resource, length <= 0 || length > 268_435_456 {
				throw STNGPUError.invalidDescriptor("Storage buffer size exceeds allocation limit")
			}
		}

		var writers: [String: Int] = [:]
		for (index, pass) in passes.enumerated() {
			var written = Set(pass.bindings.filter { $0.access == .write }.map(\.resource))
			if case .render(let p) = pass {
				guard p.vertexCount > 0, p.vertexCount <= Int(UInt32.max), p.instanceCount > 0,
					p.instanceCount <= Int(UInt32.max), !p.vertex.isEmpty, !p.fragment.isEmpty
				else {
					throw STNGPUError.invalidDescriptor("Render entry points or draw counts")
				}
				switch resources[p.target] {
				case .target, .state: break
				default: throw STNGPUError.invalidDescriptor("Render attachment must be a writable texture")
				}

				written.insert(p.target)
				if let name = p.indexBuffer {
					guard case .buffer(let buffer) = resources[name], buffer.data.count / 4 >= p.vertexCount else {
						throw STNGPUError.invalidDescriptor("Indexed drawing requires a UInt32 index buffer")
					}
				}
			}

			if case .compute(let p) = pass {
				guard !p.function.isEmpty, p.width > 0, p.height > 0, p.depth > 0,
					p.width <= Int(UInt32.max), p.height <= Int(UInt32.max), p.depth <= Int(UInt32.max)
				else {
					throw STNGPUError.invalidDescriptor("Compute entry point or dispatch dimensions")
				}
			}

			var slots = Set<String>()
			for binding in pass.bindings {
				let resource = resources[binding.resource]
				let kind: String
				switch resource {
				case .buffer, .storage: kind = "buffer"
				case .sampler: kind = "sampler"
				default: kind = binding.resource == "$backdropCoordinates" ? "buffer" : "texture"
				}

				guard binding.index >= 0, binding.index < (kind == "texture" ? 128 : kind == "sampler" ? 16 : 31),
					slots.insert("\(binding.stage):\(kind):\(binding.index)").inserted,
					resource != nil || binding.resource == "$backdrop" || binding.resource == "$backdropCoordinates"
				else {
					throw STNGPUError.invalidDescriptor("Missing resource or duplicate/out-of-range binding")
				}

				if binding.previous {
					guard case .state = resource, binding.access == .read else {
						throw STNGPUError.invalidDescriptor("previous requires a read-only state slot")
					}
				} else if binding.access == .read, written.contains(binding.resource) {
					throw STNGPUError.invalidDescriptor("Simultaneous attachment/resource read and write")
				}

				if binding.access == .write {
					switch resource {
					case .target, .state, .storage: break
					default: throw STNGPUError.invalidDescriptor("Immutable or backdrop resource cannot be written")
					}
				}
				if case .compute = pass, binding.stage != .compute {
					throw STNGPUError.invalidDescriptor("Compute bindings require the compute stage")
				}
				if case .render = pass, binding.stage == .compute {
					throw STNGPUError.invalidDescriptor("Render bindings require vertex or fragment stage")
				}
			}

			for name in written {
				guard resources[name] != nil, writers.updateValue(index, forKey: name) == nil else {
					throw STNGPUError.invalidDescriptor("Missing target or multiple same-step producers")
				}
			}
		}

		guard writers[output] != nil else {
			throw STNGPUError.invalidDescriptor("Output has no producer")
		}

		var visited = Set<Int>()
		var visiting = Set<Int>()
		var order: [Int] = []
		func visit(_ index: Int) throws {
			if visited.contains(index) { return }
			guard visiting.insert(index).inserted else {
				throw STNGPUError.invalidDescriptor("Current-step pass dependency cycle")
			}

			for binding in passes[index].bindings where binding.access == .read && !binding.previous {
				if let producer = writers[binding.resource] { try visit(producer) }
			}

			visiting.remove(index)
			visited.insert(index)
			order.append(index)
		}

		for index in passes.indices { try visit(index) }
		self.shader = shader
		self.resources = resources
		self.passes = passes
		self.output = output
		self.outputColor = outputColor
		self.sourcePeak = sourcePeak
		self.constants = constants
		self.samplingRadius = samplingRadius
		executionOrder = order
	}

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.version == rhs.version
	}

	/// Replaces immutable inputs without recompiling an unchanged executable or
	/// resetting temporal state. Changing a state slot starts a fresh state epoch.
	public func updatingResources(_ replacements: [String: STNGPUResource]) throws -> Self {
		var values = resources
		for (name, value) in replacements { values[name] = value }
		var next = try Self(
			shader: shader,
			resources: values,
			passes: passes,
			output: output,
			outputColor: outputColor,
			sourcePeak: sourcePeak,
			constants: constants,
			samplingRadius: samplingRadius
		)
		let formatsUnchanged = values.allSatisfy { name, value in
			guard let previous = resources[name] else { return false }
			switch (previous, value) {
			case (.target(_, _, let a), .target(_, _, let b)): return a == b
			case (.state(let a), .state(let b)): return a.format == b.format
			case (.buffer, .buffer), (.storage, .storage), (.texture, .texture), (.sampler, .sampler): return true
			default: return false
			}
		}
		if formatsUnchanged { next.pipelineVersion = pipelineVersion }
		let oldSlots = resources.filter { if case .state = $0.value { true } else { false } }
		let newSlots = values.filter { if case .state = $0.value { true } else { false } }
		if oldSlots == newSlots && formatsUnchanged { next.stateVersion = stateVersion }
		return next
	}
}

public struct STNBackdropEffect: Equatable, Sendable {
	package enum Operation: Equatable, Sendable {
		case identity, blur(Double), program(STNGPUProgram)
	}

	package let operation: Operation

	public static let identity = Self(operation: .identity)

	/// Normalized finite box blur; radius is in local logical points.
	public static func blur(radius: Double) -> Self {
		precondition(radius.isFinite && radius >= 0)
		return .init(operation: .blur(radius))
	}

	public static func program(_ program: STNGPUProgram) -> Self {
		.init(operation: .program(program))
	}
}
