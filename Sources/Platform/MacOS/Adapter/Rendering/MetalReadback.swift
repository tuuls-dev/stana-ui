import CStanaMacOS
import Foundation
import StanaPrimitives

@MainActor private final class MetalReadbackRequest {
	let continuation: CheckedContinuation<STNRenderedImage, any Error>

	init(_ continuation: CheckedContinuation<STNRenderedImage, any Error>) {
		self.continuation = continuation
	}
}

@MainActor private final class MetalDiagnosticRequest {
	let continuation: CheckedContinuation<Data, Never>

	init(_ continuation: CheckedContinuation<Data, Never>) { self.continuation = continuation }
}

extension MacOSWindow {
	package func renderingDiagnostics() async throws -> STNRenderingDiagnostics {
		guard let handle else { throw STNError.nodeDisposed }
		let data: Data = await withCheckedContinuation { continuation in
			stn_metal_diagnostics(handle, Unmanaged.passRetained(MetalDiagnosticRequest(continuation)).toOpaque()) {
				context,
				value in
				guard let context else { return }
				MainActor.assumeIsolated {
					let request = Unmanaged<MetalDiagnosticRequest>.fromOpaque(context).takeRetainedValue()
					request.continuation.resume(returning: Data(value.string.utf8))
				}
			}
		}
		return try .init(
			data: data,
			confirmedRevision: graphics.presentation.confirmed?.scene,
			confirmedTime: graphics.presentation.confirmedTimestamp
		)
	}

	package func capture() async throws -> STNRenderedImage {
		guard let handle else { throw STNError.nodeDisposed }
		return try await withCheckedThrowingContinuation { continuation in
			let request = MetalReadbackRequest(continuation)
			stn_metal_readback(handle, Unmanaged.passRetained(request).toOpaque()) {
				context,
				bytes,
				count,
				width,
				height,
				linear,
				revision,
				error in
				guard let context else { return }
				MainActor.assumeIsolated {
					let request = Unmanaged<MetalReadbackRequest>.fromOpaque(context).takeRetainedValue()
					guard let bytes else {
						request.continuation.resume(throwing: STNError.nativeFailure(error.string))
						return
					}
					request.continuation.resume(
						returning: .init(
							width: width,
							height: height,
							format: linear ? .premultipliedRGBA16Float : .premultipliedBGRA8,
							sceneRevision: revision,
							data: Data(bytes: bytes, count: count)
						)
					)
				}
			}
		}
	}
}
