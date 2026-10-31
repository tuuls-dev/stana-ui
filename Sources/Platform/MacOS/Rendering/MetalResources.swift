import CoreGraphics
import Foundation
import IOSurface
import Metal
import StanaPrimitives
import StanaScene
import Synchronization

struct MetalFailure: Error, Sendable {
	enum Kind: Sendable { case preparation, execution }

	let message: String
	let kind: Kind

	init(_ message: String, kind: Kind = .preparation) {
		self.message = message
		self.kind = kind
	}
}

final class MetalDevice: Sendable {
	static let shared: MetalDevice? = MetalDevice()
	let device: any MTLDevice
	let budget: Int

	private struct Ledger {
		var bytes = 0
		var peak = 0
		var capacity: Int
		var pressureEpoch: UInt64 = 0
	}

	private let ledger: Mutex<Ledger>
	private let pressureSource = Mutex<(any DispatchSourceMemoryPressure)?>(nil)
	private let bandwidth = Mutex<Double>(8e9)

	var copyBandwidth: Double { bandwidth.withLock { $0 } }

	private init?() {
		guard let device = MTLCreateSystemDefaultDevice() else {
			return nil
		}

		self.device = device
		let physical = Int(ProcessInfo.processInfo.physicalMemory / 4)
		budget = min(
			physical,
			device.recommendedMaxWorkingSetSize > 0 ? Int(device.recommendedMaxWorkingSetSize / 2) : physical
		)
		ledger = Mutex(Ledger(capacity: budget))
		let source = DispatchSource.makeMemoryPressureSource(
			eventMask: [.warning, .critical],
			queue: .global(qos: .utility)
		)
		source.setEventHandler { [weak self] in
			guard let self else {
				return
			}

			let epoch = self.beginPressure()
			DispatchQueue.global(qos: .utility)
				.asyncAfter(deadline: .now() + 10) { [weak self] in
					guard let self, self.endPressure(epoch: epoch) else {
						return
					}

					Task { @MainActor in MetalRenderer.devicePressureRecovered() }
				}
		}
		pressureSource.withLock { $0 = source }
		source.resume()
		DispatchQueue.global(qos: .utility).async { [weak self] in self?.calibrateBandwidth() }
	}

	private func calibrateBandwidth() {
		do {
			let length = 32 * 1_024 * 1_024
			let first = try buffer(length: length), second = try buffer(length: length)
			guard let queue = device.makeCommandQueue(), let buffer = queue.makeCommandBuffer(),
				let encoder = buffer.makeBlitCommandEncoder()
			else {
				return
			}

			encoder.fill(buffer: first.buffer, range: 0..<length, value: 1)
			for index in 0..<8 {
				encoder.copy(
					from: index.isMultiple(of: 2) ? first.buffer : second.buffer,
					sourceOffset: 0,
					to: index.isMultiple(of: 2) ? second.buffer : first.buffer,
					destinationOffset: 0,
					size: length
				)
			}

			encoder.endEncoding()
			buffer.commit()
			buffer.waitUntilCompleted()
			let seconds = buffer.gpuEndTime - buffer.gpuStartTime
			if buffer.status == .completed, seconds > 0 {
				bandwidth.withLock { $0 = Double(length * 8 * 2) / seconds }
			}
		} catch {
			// Keep the conservative bandwidth estimate if calibration fails.
		}
	}

	func reserve(_ bytes: Int) throws -> MetalLease {
		guard bytes > 0,
			ledger.withLock({ state in
				guard bytes <= state.capacity, state.bytes <= state.capacity - bytes else {
					return false
				}

				state.bytes += bytes
				state.peak = max(state.peak, state.bytes)
				return true
			})
		else {
			throw MetalFailure("Device-wide surface budget exhausted")
		}

		return MetalLease(device: self, bytes: bytes)
	}

	fileprivate func release(_ bytes: Int) {
		ledger.withLock {
			precondition($0.bytes >= bytes, "Stana: Metal ledger underflow")
			$0.bytes -= bytes
		}
	}

	private func beginPressure() -> UInt64 {
		ledger.withLock {
			nextRevision(&$0.pressureEpoch)
			$0.capacity = max(1, budget / 2)
			return $0.pressureEpoch
		}
	}

	private func endPressure(epoch: UInt64) -> Bool {
		ledger.withLock {
			guard $0.pressureEpoch == epoch else {
				return false
			}

			$0.capacity = budget
			return true
		}
	}

	func pressure(_ active: Bool) {
		ledger.withLock { $0.capacity = active ? max(1, budget / 2) : budget }
	}

	var accounting: (bytes: Int, peak: Int, capacity: Int) {
		ledger.withLock { ($0.bytes, $0.peak, $0.capacity) }
	}

	func texture(width: Int, height: Int, format: MTLPixelFormat, raster: Bool = false, samples: Int = 1) throws
		-> MetalAllocation
	{
		let bpp = format == .rgba16Float ? 8 : format == .r8Unorm ? 1 : 4
		guard width > 0, height > 0, width <= 16_384, height <= 16_384,
			width <= 268_435_456 / height / bpp
		else {
			throw MetalFailure("Surface dimensions exceed checked allocation limit")
		}

		let row = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * bpp)
		guard row <= 268_435_456 / height / samples else {
			throw MetalFailure("Surface stride exceeds checked allocation limit")
		}

		let lease = try reserve(IOSurfaceAlignProperty(kIOSurfaceAllocSize, row * height * samples))
		let descriptor = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: format,
			width: width,
			height: height,
			mipmapped: false
		)
		descriptor.hazardTrackingMode = .tracked
		descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
		descriptor.storageMode = raster ? .shared : .private
		if samples > 1 {
			descriptor.textureType = .type2DMultisample
			descriptor.sampleCount = samples
			descriptor.usage = .renderTarget
		}

		var surface: IOSurfaceRef?
		let texture: (any MTLTexture)?
		if raster {
			surface = IOSurfaceCreate(
				[
					kIOSurfaceWidth: width, kIOSurfaceHeight: height,
					kIOSurfaceBytesPerElement: bpp, kIOSurfaceBytesPerRow: row,
					kIOSurfaceAllocSize: row * height, kIOSurfacePixelFormat: 0x42475241,
				] as CFDictionary
			)
			texture = surface.flatMap { device.makeTexture(descriptor: descriptor, iosurface: $0, plane: 0) }
		} else {
			texture = device.makeTexture(descriptor: descriptor)
		}

		guard let texture else {
			throw MetalFailure("Metal texture allocation failed")
		}

		let actual = surface.map { IOSurfaceGetAllocSize($0) } ?? max(lease.bytes, texture.allocatedSize)
		let extra = actual > lease.bytes ? try reserve(actual - lease.bytes) : nil
		return MetalAllocation(
			storage: .init(texture: texture, surface: surface),
			leases: [lease] + (extra.map { [$0] } ?? [])
		)
	}

	func buffer(data: Data? = nil, length: Int) throws -> MetalBuffer {
		guard length > 0, length <= 268_435_456 else {
			throw MetalFailure("Buffer exceeds checked allocation limit")
		}

		let lease = try reserve((length + 4_095) & ~4_095)
		guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
			throw MetalFailure("Metal buffer allocation failed")
		}

		if let data {
			guard data.count == length else {
				throw MetalFailure("Buffer initializer length mismatch")
			}

			data.withUnsafeBytes { bytes in
				buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: length)
			}
		}

		return MetalBuffer(buffer: buffer, lease: lease)
	}
}

final class MetalLease: Sendable {
	private let device: MetalDevice
	let bytes: Int

	init(device: MetalDevice, bytes: Int) {
		self.device = device
		self.bytes = bytes
	}

	deinit {
		device.release(bytes)
	}
}

final class MetalBuffer: Sendable {
	private let storage: Mutex<any MTLBuffer>

	var buffer: any MTLBuffer {
		storage.withLock { $0 }
	}

	private let lease: MetalLease

	init(buffer: sending any MTLBuffer, lease: MetalLease) {
		storage = Mutex(buffer)
		self.lease = lease
	}
}

final class MetalAllocation: Sendable {
	struct Storage {
		let texture: any MTLTexture
		let surface: IOSurfaceRef?
	}

	// Transfer the texture and its IOSurface alias as one synchronized owner.
	private let storage: Mutex<Storage>

	var texture: any MTLTexture {
		storage.withLock { $0.texture }
	}

	private let leases: [MetalLease]

	var accountedBytes: Int { leases.reduce(0) { $0 + $1.bytes } }

	init(storage: sending Storage, leases: [MetalLease]) {
		self.storage = Mutex(storage)
		self.leases = leases
	}

	func raster(
		_ commands: [DrawCommand],
		padded: CGRect,
		scale: Double,
		symbolResults: SymbolRasterResults? = nil,
		epoch: UInt64 = 0
	) throws {
		try storage.withLock { storage in
			guard let surface = storage.surface, IOSurfaceLock(surface, [], nil) == kIOReturnSuccess else {
				throw MetalFailure("IOSurface writer lock failed")
			}

			defer {
				IOSurfaceUnlock(surface, [], nil)
			}

			guard
				let context = CGContext(
					data: IOSurfaceGetBaseAddress(surface),
					width: IOSurfaceGetWidth(surface),
					height: IOSurfaceGetHeight(surface),
					bitsPerComponent: 8,
					bytesPerRow: IOSurfaceGetBytesPerRow(surface),
					space: CGColorSpace(name: CGColorSpace.sRGB)!,
					bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
				)
			else {
				throw MetalFailure("Core Graphics worker context creation failed")
			}

			context.clear(CGRect(x: 0, y: 0, width: context.width, height: context.height))
			context.translateBy(x: 0, y: Double(context.height))
			context.scaleBy(x: scale, y: -scale)
			context.translateBy(x: -padded.minX, y: -padded.minY)
			var canvas = RasterCanvas()
			canvas.draw(commands, in: context, symbolResults: symbolResults, epoch: epoch)
			context.flush()
		}
	}
}

struct RasterJob: Sendable {
	let allocation: MetalAllocation
	let commands: [DrawCommand]
	let padded: CGRect
	let scale: Double
	var symbolResults: SymbolRasterResults? = nil
	var epoch: UInt64 = 0
}

/// Shared admission bounds workers across all windows.
struct RasterTiming: Sendable {
	let queueDelay, wall, cpu: Double
}

actor RasterWorkers {
	static let shared = RasterWorkers()
	nonisolated let limit = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 1))
	private var running = 0
	private var peak = 0
	private var waiters: [CheckedContinuation<Void, Never>] = []

	private func acquire() async {
		if running < limit {
			running += 1
			peak = max(peak, running)
			return
		}

		await withCheckedContinuation { waiters.append($0) }
	}

	private func release() {
		if waiters.isEmpty {
			running -= 1
		} else {
			waiters.removeFirst().resume()
		}
	}

	var accounting: (limit: Int, active: Int, peak: Int, waiting: Int) { (limit, running, peak, waiters.count) }

	private nonisolated static func cpuTime() -> Double {
		var value = timespec()
		clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value)
		return Double(value.tv_sec) + Double(value.tv_nsec) / 1e9
	}

	func run(_ job: RasterJob, delay: Double) async throws -> RasterTiming {
		let enqueued = ProcessInfo.processInfo.systemUptime
		await acquire()
		defer {
			release()
		}

		return try await withCheckedThrowingContinuation {
			(continuation: CheckedContinuation<RasterTiming, any Error>) in
			DispatchQueue.global(qos: .userInitiated)
				.async {
					let result = Result {
						let start = ProcessInfo.processInfo.systemUptime, cpu = Self.cpuTime()
						try autoreleasepool {
							if delay > 0 {
								Thread.sleep(forTimeInterval: delay)
							}

							try job.allocation.raster(
								job.commands,
								padded: job.padded,
								scale: job.scale,
								symbolResults: job.symbolResults,
								epoch: job.epoch
							)
						}
						return RasterTiming(
							queueDelay: start - enqueued,
							wall: ProcessInfo.processInfo.systemUptime - start,
							cpu: Self.cpuTime() - cpu
						)
					}
					continuation.resume(with: result)
				}
		}
	}
}
