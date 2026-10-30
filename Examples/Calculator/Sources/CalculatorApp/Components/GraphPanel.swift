import Foundation
import Stana

@MainActor struct GraphPanel: STNComponent {
	let session: CalculatorSession

	func makeContent(in context: STNComponentContext) -> some STNComponent {
		let drag = context.state(initial: GraphDrag?.none)
		let active = STNComputed {
			session.animate.value && session.graphVisible.value && !context.environment.reducedMotion.value
		}

		context.onFrame(isActive: active) { frame in
			session.advanceAnimation(elapsed: frame.elapsed)
		}

		let size = session.geometry.map { STNSize(width: $0.plotWidth, height: $0.plotHeight) }
		let frame = STNComputed {
			GraphPlot.make(
				source: session.plotSource.value,
				viewport: session.viewport.value,
				size: size.value,
				time: session.time.value,
				highContrast: context.environment.highContrast.value,
				sampleX: Double(session.sampleX.value)
			)
		}

		let sample = STNComputed<String> {
			guard let x = Double(session.sampleX.value), x.isFinite else {
				return "Enter a finite x value."
			}

			var values = session.plotSource.value.context
			values.x = x
			values.t = session.time.value
			do {
				return "y ≈ " + CalculatorMath.format(try session.plotSource.value.expression.evaluate(in: values))
			} catch { return "Undefined at this x" }
		}

		STNVStack(
			properties: .init(
				spacing: 10,
				layout: .init(
					padding: STNInsets(16),
					frame: session.geometry.map { STNFrame(width: $0.workspaceWidth) }
				),
				appearance: .init(
					background: CalculatorPalette.panel,
					borderColor: CalculatorPalette.line,
					borderWidth: 1,
					cornerRadius: 12
				),
				accessibility: .init(label: "Function plot", group: true)
			)
		) {
			STNHStack(properties: .init(spacing: 8)) {
				InstrumentLabel(text: "01 / PLOT")
				STNSpacer()
				STNText(
					properties: .init(
						text: session.plotIsCurrent.map { $0 ? "LIVE PREVIEW" : "PREVIOUS VALID EXPRESSION" },
						layout: .init(frame: STNFrame(height: 18)),
						textStyle: .init(
							font: STNFont.system(size: 10, weight: .semibold),
							foreground: session.plotIsCurrent.map {
								$0 ? CalculatorPalette.curve : CalculatorPalette.amber
							}
						)
					)
				)
			}
			STNText(
				properties: .init(
					text: session.plotSource.map { "y = " + $0.expression.source },
					layout: .init(frame: size.map { STNFrame(width: $0.width, height: 24) }),
					textStyle: .init(
						font: STNFont.system(size: 17, weight: .medium),
						foreground: CalculatorPalette.ink
					),
					accessibility: .init(heading: 2)
				)
			)
			STNZStack(
				properties: .init(
					alignment: .center,
					layout: .init(frame: size.map { STNFrame(width: $0.width, height: $0.height) }),
					appearance: .init(cornerRadius: 8, clip: true)
				)
			) {
				STNCanvas(
					properties: .init(
						drawing: frame.map(\.grid),
						layout: .init(frame: size.map { STNFrame(width: $0.width, height: $0.height) })
					)
				)
				STNGPUCanvas(
					properties: .init(
						drawing: frame.map(\.curve),
						layout: .init(frame: size.map { STNFrame(width: $0.width, height: $0.height) }),
						onError: { session.note.value = $0.message }
					)
				)
				STNForEach(frame.map(\.marks), id: \.id) { mark in
					STNLayer(
						properties: .init(
							transform: size.map {
								.translation(
									x: mark.origin.x - ($0.width - mark.width) / 2,
									y: mark.origin.y - ($0.height - 18) / 2
								)
							},
							layout: .init(frame: STNFrame(width: mark.width, height: 18))
						)
					) {
						STNZStack(properties: .init(layout: .init(frame: STNFrame(width: mark.width, height: 18)))) {
							STNText(
								properties: .init(
									text: mark.text,
									layout: .init(frame: STNFrame(height: 16)),
									textStyle: .init(
										font: STNFont.system(size: 10, weight: .medium),
										foreground: CalculatorPalette.muted
									),
									accessibility: .init(
										label: mark.axis == "name" ? mark.text + " axis" : mark.axis + " = " + mark.text
									)
								)
							)
						}
					}
				}
				STNBox(
					properties: .init(
						layout: .init(frame: size.map { STNFrame(width: $0.width, height: $0.height) }),
						interaction: .init(
							onPointerDown: { event in
								event.preventDefault()
								event.capturePointer()
								drag.value = .init(start: event.localPosition, viewport: session.viewport.value)
							},
							onPointerMove: { event in
								guard let drag = drag.value else {
									return
								}

								let dx =
									(event.localPosition.x - drag.start.x) / size.value.width
									* (drag.viewport.xMax - drag.viewport.xMin)
								let dy =
									(event.localPosition.y - drag.start.y) / size.value.height
									* (drag.viewport.yMax - drag.viewport.yMin)
								session.viewport.value = .init(
									xMin: drag.viewport.xMin - dx,
									xMax: drag.viewport.xMax - dx,
									yMin: drag.viewport.yMin + dy,
									yMax: drag.viewport.yMax + dy
								)
							},
							onPointerUp: { _ in drag.value = nil },
							onPointerCancel: { _ in drag.value = nil }
						),
						accessibility: .init(
							label: "Sampled function plot. Drag to pan; use controls below for keyboard navigation."
						)
					)
				) {}
				STNIf(frame.map { $0.data.segments.isEmpty }) {
					STNText(
						properties: .init(
							text: "No curve in this viewport",
							textStyle: .init(foreground: CalculatorPalette.muted)
						)
					)
				}
			}
			STNText(
				properties: .init(
					text: session.viewport.map {
						"x  \(CalculatorMath.format($0.xMin)) … \(CalculatorMath.format($0.xMax))     y  \(CalculatorMath.format($0.yMin)) … \(CalculatorMath.format($0.yMax))"
					},
					layout: .init(frame: size.map { STNFrame(width: $0.width, height: 16) }),
					textStyle: .init(font: STNFont.system(size: 11), foreground: CalculatorPalette.muted),
					accessibility: .init(label: "Plot axis ranges")
				)
			)
			STNHStack(properties: .init(spacing: 6)) {
				InstrumentButton(title: "−", hint: "Zoom out", width: 30, height: 28) { zoom(1.25) }
				InstrumentButton(title: "+", hint: "Zoom in", width: 30, height: 28) { zoom(0.8) }
				InstrumentButton(title: "←", hint: "Pan left", width: 30, height: 28) { pan(-0.2) }
				InstrumentButton(title: "→", hint: "Pan right", width: 30, height: 28) { pan(0.2) }
				InstrumentButton(title: "↑", hint: "Pan up", width: 30, height: 28) { panY(0.2) }
				InstrumentButton(title: "↓", hint: "Pan down", width: 30, height: 28) { panY(-0.2) }
				InstrumentButton(title: "Fit", hint: "Fit vertical range to sampled values", width: 38, height: 28) {
					fit(frame.value.data)
				}
				InstrumentButton(title: "Reset", width: 52, height: 28) { session.viewport.value = GraphViewport() }
				STNSpacer()
				STNToggle(
					properties: .init(
						text: "Animate",
						isOn: session.animate.binding,
						textStyle: .init(font: STNFont.system(size: 11), foreground: CalculatorPalette.ink),
						interaction: .init(isEnabled: context.environment.reducedMotion.map { !$0 }),
						accessibility: .init(
							label: "Animate trace and time",
							hint:
								"Sweeps the inspection point along the function; t also advances for time-dependent expressions."
						)
					)
				)
			}
			STNHStack(properties: .init(spacing: 8)) {
				InstrumentLabel(text: "AT x =")
				STNTextField(
					properties: .init(
						value: session.sampleX.binding,
						placeholder: "0",
						layout: .init(frame: STNFrame(width: 90, height: 28)),
						textStyle: .init(font: STNFont.system(size: 12), foreground: CalculatorPalette.ink),
						appearance: .init(background: CalculatorPalette.field),
						accessibility: .init(label: "Evaluate function at x"),
						onChange: { _ in session.animate.value = false },
						onFocusChange: { focused in
							if focused {
								session.animate.value = false
							}
						}
					)
				)
				STNText(
					properties: .init(
						text: sample,
						layout: .init(frame: STNFrame(width: 145)),
						textStyle: .init(font: STNFont.system(size: 12), foreground: CalculatorPalette.curve)
					)
				)
				STNSpacer()
				STNText(
					properties: .init(
						text: session.time.map { "t = " + CalculatorMath.format($0) },
						layout: .init(frame: STNFrame(height: 18)),
						textStyle: .init(font: STNFont.system(size: 11), foreground: CalculatorPalette.muted)
					)
				)
			}
		}
	}

	private func zoom(_ factor: Double) {
		let v = session.viewport.value
		let x = v.xMin / 2 + v.xMax / 2
		let y = v.yMin / 2 + v.yMax / 2
		let w = max(abs(x).ulp * 8, min(1e8, max(1e-8, (v.xMax - v.xMin) * factor)) / 2)
		let h = max(abs(y).ulp * 8, min(1e8, max(1e-8, (v.yMax - v.yMin) * factor)) / 2)
		let updated = GraphViewport(xMin: x - w, xMax: x + w, yMin: y - h, yMax: y + h)
		if updated.isValid {
			session.viewport.value = updated
		}
	}

	private func pan(_ fraction: Double) {
		var v = session.viewport.value
		let dx = (v.xMax - v.xMin) * fraction
		v.xMin += dx
		v.xMax += dx
		if v.isValid {
			session.viewport.value = v
		}
	}

	private func panY(_ fraction: Double) {
		var v = session.viewport.value
		let dy = (v.yMax - v.yMin) * fraction
		v.yMin += dy
		v.yMax += dy
		if v.isValid {
			session.viewport.value = v
		}
	}

	private func fit(_ data: PlotData) {
		let values = data.finiteValues.sorted()
		guard !values.isEmpty else {
			return
		}
		// Robust percentiles keep a few samples next to a pole from swallowing the useful curve.
		let low = values[values.count / 20]
		let high = values[min(values.count - 1, values.count * 19 / 20)]
		let pad = max(1e-6, (high - low) * 0.15, abs(high) * 0.05)
		guard (low - pad).isFinite, (high + pad).isFinite else {
			return
		}

		var v = session.viewport.value
		v.yMin = low - pad
		v.yMax = high + pad
		if v.isValid {
			session.viewport.value = v
		}
	}
}

private struct GraphDrag: Equatable {
	let start: STNPoint
	let viewport: GraphViewport
}
