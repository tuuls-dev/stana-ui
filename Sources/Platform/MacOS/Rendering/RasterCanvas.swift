import CoreGraphics
import CoreText
import Foundation
import ImageIO
import StanaPrimitives
import StanaScene

extension STNRect {
	var cgRect: CGRect {
		CGRect(x: minX, y: minY, width: size.width, height: size.height)
	}
}

extension STNAffineTransform {
	var cgTransform: CGAffineTransform {
		CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
	}
}

extension CGRect {
	var stana: STNRect {
		.init(x: origin.x, y: origin.y, width: width, height: height)
	}
}

/// Worker-local contexts and image caches are not shared.
struct RasterCanvas {
	private var images: [Data: CGImage] = [:]
	private var imageBytes = 0

	static func path(_ rect: CGRect, radius: Double) -> CGPath {
		let radius = max(0, min(radius, min(rect.width, rect.height) / 2))
		return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
	}

	mutating func draw(
		_ commands: [DrawCommand],
		in context: CGContext,
		symbolResults: SymbolRasterResults? = nil,
		epoch: UInt64 = 0
	) {
		for command in commands {
			switch command {
			case .fill(let rect, let color, let radius):
				context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
				context.addPath(Self.path(rect.cgRect, radius: radius))
				context.fillPath()
			case .stroke(let rect, let color, let width, let radius):
				let inset = rect.cgRect.insetBy(dx: width / 2, dy: width / 2)
				guard inset.width >= 0, inset.height >= 0 else {
					continue
				}

				context.setStrokeColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
				context.setLineWidth(width)
				context.addPath(Self.path(inset, radius: max(0, radius - width / 2)))
				context.strokePath()
			case .text(let text, let rect, let font, let color, let wraps):
				let space = CGColorSpace(name: CGColorSpace.sRGB)!
				let color = CGColor(colorSpace: space, components: [color.red, color.green, color.blue, color.alpha])!
				let string = NativeText.attributed(text, font: font, color: color)
				context.saveGState()
				context.translateBy(x: rect.minX, y: rect.maxY)
				context.scaleBy(x: 1, y: -1)
				context.textMatrix = .identity
				if wraps && rect.size.width > 0 && rect.size.height > 0 {
					let setter = CTFramesetterCreateWithAttributedString(string)
					let path = CGPath(rect: CGRect(origin: .zero, size: rect.cgRect.size), transform: nil)
					CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), path, nil), context)
				} else {
					context.textPosition = CGPoint(
						x: 0,
						y: max(0, rect.size.height - CTFontGetAscent(NativeText.font(font)))
					)
					CTLineDraw(CTLineCreateWithAttributedString(string), context)
				}

				context.restoreGState()
			case .symbol(let node, let symbol):
				guard symbolResults?.failed(node: node, generation: symbol.generation) != true else { continue }
				do {
					try drawSymbol(symbol, in: context)
					symbolResults?.record(node: node, generation: symbol.generation, epoch: epoch, code: nil)
				} catch {
					let code = (error as? SymbolPreparationFailure)?.code ?? .preparationFailed
					symbolResults?.record(node: node, generation: symbol.generation, epoch: epoch, code: code)
				}
			case .image(let data, let rect):
				var image = images[data]
				if image == nil, data.count <= 32 * 1_024 * 1_024,
					let source = CGImageSourceCreateWithData(data as CFData, nil),
					let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
					let width = properties[kCGImagePropertyPixelWidth] as? Int,
					let height = properties[kCGImagePropertyPixelHeight] as? Int,
					width > 0, height > 0, width <= 16_777_216 / height
				{
					image = CGImageSourceCreateImageAtIndex(
						source,
						0,
						[kCGImageSourceShouldCacheImmediately: true] as CFDictionary
					)
					if let decoded = image {
						let cost = decoded.bytesPerRow * decoded.height + data.count
						if cost <= 64 * 1_024 * 1_024 {
							if images.count >= 128 || imageBytes + cost > 64 * 1_024 * 1_024 {
								images.removeAll()
								imageBytes = 0
							}

							images[data] = decoded
							imageBytes += cost
						}
					}
				}

				if let image {
					context.saveGState()
					context.translateBy(x: rect.minX, y: rect.maxY)
					context.scaleBy(x: 1, y: -1)
					context.draw(image, in: CGRect(origin: .zero, size: rect.cgRect.size))
					context.restoreGState()
				} else {
					context.setFillColor(red: 0.8, green: 0.8, blue: 0.82, alpha: 1)
					context.addPath(Self.path(rect.cgRect, radius: 3))
					context.fillPath()
				}
			case .pushClip(let rect):
				context.saveGState()
				context.clip(to: rect.cgRect)
			case .popClip, .popTransform:
				context.restoreGState()
			case .pushOpacity(let opacity):
				context.saveGState()
				context.setAlpha(opacity)
				context.beginTransparencyLayer(auxiliaryInfo: nil)
			case .popOpacity:
				context.endTransparencyLayer()
				context.restoreGState()
			case .pushTransform(let transform):
				context.saveGState()
				context.concatenate(transform.cgTransform)
			case .pushRoundedClip(let rect, let radius):
				context.saveGState()
				context.addPath(Self.path(rect.cgRect, radius: radius))
				context.clip()
			}
		}
	}
}
