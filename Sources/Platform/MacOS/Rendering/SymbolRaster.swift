import CoreGraphics
import StanaPrimitives

extension RasterCanvas {
	func drawSymbol(_ symbol: SymbolPresentation, in context: CGContext) throws {
		guard !symbol.preparationLimited else {
			throw SymbolPreparationFailure(code: .resourceLimitExceeded)
		}

		let deviceTransform = context.ctm
		let scale =
			STNAffineTransform(a: deviceTransform.a, b: deviceTransform.b, c: deviceTransform.c, d: deviceTransform.d)
			.maximumScale * symbol.preparationScale
		let prepared = try SymbolPathCache.shared.prepare(symbol.asset, strokeWidth: symbol.strokeWidth, scale: scale)
		do {
			let paths = prepared.paths
			var index = 0

			func color(_ paint: SymbolPaint, opacity: Double) -> CGColor? {
				let c: STNColor
				switch paint {
				case .none: return nil
				case .currentColor: c = symbol.color
				case .rgba(let r, let g, let b, let a): c = STNColor(red: r, green: g, blue: b, alpha: a)
				}

				return CGColor(
					colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
					components: [c.red, c.green, c.blue, c.alpha * opacity]
				)
			}

			func draw(_ elements: [SymbolElement]) {
				for element in elements {
					context.saveGState()
					switch element {
					case .group(let t, let opacity, let children):
						context.concatenate(t.cgTransform)
						context.setAlpha(opacity)
						context.beginTransparencyLayer(auxiliaryInfo: nil)
						draw(children)
						context.endTransparencyLayer()
					case .path(_, let t, let fill, let rule, let fa, let stroke, let sa, _, _, _, _, let opacity):
						let path = paths[index]
						index += 1
						context.concatenate(t.cgTransform)
						context.setAlpha(opacity)
						context.beginTransparencyLayer(auxiliaryInfo: nil)
						if let c = color(fill, opacity: fa) {
							context.setFillColor(c)
							context.addPath(path.fill)
							context.drawPath(using: rule == .evenodd ? .eoFill : .fill)
						}

						if let outline = path.stroke, let c = color(stroke, opacity: sa) {
							context.setFillColor(c)
							context.addPath(outline)
							context.fillPath()
						}

						context.endTransparencyLayer()
					}

					context.restoreGState()
				}
			}

			context.saveGState()
			context.concatenate(symbol.transform.cgTransform)
			draw(symbol.asset.elements)
			context.restoreGState()
		}
	}
}
