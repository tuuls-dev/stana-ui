import Stana

@MakeSTNSymbol
private struct CalculatorAddSymbol {
	static let svg = #"""
		<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
		<path d="M5 12h14M12 5v14"/>
		</svg>
		"""#
}

@MakeSTNSymbol(mirrorsInRTL: true)
private struct CalculatorForwardSymbol {
	static let svg = #"""
		<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
		<path d="M5 12h14M13 6l6 6-6 6"/>
		</svg>
		"""#
}

/// Independent mounted timelines share the same immutable asset, not clocks.
@MainActor struct SymbolDemo: STNComponent {
	func makeContent(in context: STNComponentContext) -> some STNComponent {
		let asset: STNSignal<STNSymbolAsset> = context.state(initial: CalculatorAddSymbol.asset)
		let playback: STNSignal<STNSymbolPlayback> = context.state(initial: .none)
		let stroke: STNSignal<Double?> = context.state(initial: nil)
		let request: STNSignal<UInt64> = context.state(initial: 0)
		STNVStack(properties: .init(spacing: 8, accessibility: .init(label: "Symbol demonstration", group: true))) {
			STNHStack(properties: .init(spacing: 12)) {
				STNSymbol(
					properties: .init(
						symbol: asset,
						size: 20,
						color: CalculatorPalette.ink,
						animation: playback,
						strokeWidth: stroke,
						accessibility: .init(label: "Replay symbol")
					)
				)
				STNSymbol(
					properties: .init(
						symbol: asset,
						size: 20,
						color: CalculatorPalette.ink,
						animation: STNSymbolPlayback.loop(.rotate),
						strokeWidth: stroke,
						accessibility: .init(label: "Looping symbol")
					)
				)
				STNButton(
					properties: .init(
						text: "Replay",
						onActivate: {
							precondition(request.value < .max, "Calculator: symbol request generation exhausted")
							STNTransaction.perform {
								request.value += 1
								playback.value = .once(.bounce, request: request.value)
							}
						}
					)
				)
				STNButton(
					properties: .init(
						text: "Swap",
						onActivate: {
							asset.value =
								asset.value == CalculatorAddSymbol.asset
								? CalculatorForwardSymbol.asset : CalculatorAddSymbol.asset
						}
					)
				)
				STNButton(
					properties: .init(text: "Stroke", onActivate: { stroke.value = stroke.value == nil ? 1 : nil })
				)
			}

			STNText(
				properties: .init(
					text: context.environment.reducedMotion.map {
						$0 ? "Reduced motion: symbols at rest" : "Symbols respect system Reduce Motion"
					},
					textStyle: .init(font: STNFont.system(size: 10), foreground: CalculatorPalette.muted)
				)
			)
		}
	}
}
