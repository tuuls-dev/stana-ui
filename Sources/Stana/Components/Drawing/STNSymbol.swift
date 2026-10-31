import StanaCore
import StanaPrimitives

/// A retained vector symbol with reactive styling and mount-owned deterministic playback.
@MainActor public struct STNSymbol: STNComponent, PrimitiveComponent {
	@MainActor public struct Properties {
		package var configuration = NodeConfiguration()
		package let symbol: Property<STNSymbolAsset>
		package let size: Property<Double>
		package let color: Property<STNColor>
		package let animation: Property<STNSymbolPlayback>
		package let strokeWidth: Property<Double?>
		package let onError: (@MainActor (STNSymbolDiagnostic) -> Void)?

		public init(
			symbol: some STNPropertyConvertible<STNSymbolAsset>,
			size: some STNPropertyConvertible<Double> = 24,
			color: some STNPropertyConvertible<STNColor> = STNColor.text,
			animation: some STNPropertyConvertible<STNSymbolPlayback> = STNSymbolPlayback.none,
			strokeWidth: some STNPropertyConvertible<Double?> = Optional<Double>.none,
			layout: STNLayoutProperties = .init(),
			appearance: STNAppearanceProperties = .init(),
			interaction: STNInteractionProperties = .init(),
			accessibility: STNAccessibilityProperties = .init(),
			lifecycle: STNLifecycleProperties = .init(),
			onError: (@MainActor (STNSymbolDiagnostic) -> Void)? = nil
		) {
			self.symbol = symbol.asProperty()
			self.size = size.asProperty()
			self.color = color.asProperty()
			self.animation = animation.asProperty()
			self.strokeWidth = strokeWidth.asProperty()
			self.onError = onError
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
		properties.configuration.mount(
			.symbol,
			in: context,
			configure: { node in
				node.symbol = SymbolContent(asset: properties.symbol.read().storage)
				let mounted = MountedSymbol(node: node, session: context.session, onError: properties.onError)
				context.session.symbols[node.id] = mounted
				let registration = FrameRegistration(
					scope: node.scope,
					active: { [weak mounted] in mounted?.state.needsFrame == true },
					callback: { [weak mounted] in mounted?.tick($0) }
				)
				mounted.registration = registration
				context.session.frameRegistrations.append(registration)
				let nodeID = node.id
				node.scope.own { [weak session = context.session] in
					registration.cancelled = true
					session?.frameRegistrations.removeAll { $0.id == registration.id }

					session?.symbols.removeValue(forKey: nodeID)
					session?.refreshFrameDemand()
				}

				properties.symbol.install(in: context, node: node, dirty: .paint) { $0.symbol?.asset = $1.storage }

				properties.size.install(in: context, node: node, dirty: .all) {
					precondition($1.isFinite && $1 >= 0, "Stana: symbol size must be finite and nonnegative")
					$0.symbol?.size = $1
				}

				properties.color.install(in: context, node: node, dirty: .paint) { $0.symbol?.color = $1 }

				properties.strokeWidth.install(in: context, node: node, dirty: .paint) {
					precondition(
						$1.map { $0.isFinite && $0 >= 0 } ?? true,
						"Stana: symbol stroke width must be finite and nonnegative"
					)
					$0.symbol?.strokeWidth = $1
				}

				properties.animation.install(in: context, node: node, dirty: .paint) { [weak mounted] _, value in
					mounted?.playback = value
				}
			}
		)
	}
}
