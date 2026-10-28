import Foundation
import StanaCore
import StanaPrimitives

public struct STNImageSource: Equatable, Sendable {
	package let data: Data

	public init(data: Data) throws {
		guard !data.isEmpty, data.count <= 32 * 1024 * 1024 else {
			throw STNError.invalidAsset
		}

		self.data = data
	}

	/// Reads bytes off the UI executor. Decoding remains bounded by the native backend.
	public static func load(contentsOf url: URL) async throws -> Self {
		try await Task.detached { try Self(data: Data(contentsOf: url, options: .mappedIfSafe)) }.value
	}
}

@MainActor public struct STNImage: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()
		package let image: STNImageSource

		public init(
			image: STNImageSource,
			layout: STNLayoutProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init()
		) {
			self.image = image
			configuration.apply(
				layout: layout,
				appearance: appearance,
				interaction: interaction,
				accessibility: accessibility,
				lifecycle: lifecycle
			)
		}
	}

	private let properties: Properties

	public init(properties: Properties) {
		self.properties = properties
	}

	public func makeContent(in context: STNComponentContext) -> STNEmpty {
		return STNEmpty()
	}

	package func mount(in context: MountContext) {
		properties.configuration.mount(.image, in: context, configure: { $0.imageData = properties.image.data })
	}
}
