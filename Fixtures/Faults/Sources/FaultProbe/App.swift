import Foundation
import Stana
import StanaTesting

@MakeSTNSymbol
struct FaultSymbol {
	static let svg = "<svg viewBox='0 0 24 24'><path d='M0 0L24 24'/></svg>"
}

@main struct FaultProbe {
	@MainActor static func main() {
		switch CommandLine.arguments.last {
		case "cycle":
			var a: STNComputed<Int>!
			var b: STNComputed<Int>!
			a = STNComputed { b.value }
			b = STNComputed { a.value }
			_ = a.value
		case "write":
			let source = STNSignal(0)
			let computed = STNComputed {
				source.value += 1
				return source.value
			}
			_ = computed.value
		case "comparator":
			let other = STNSignal(0)
			let source = STNSignal(
				0,
				equals: { a, b in
					other.value += 1
					return a == b
				}
			)
			source.value = 1
		case "symbol-bridge-version":
			_ = STNSymbolAsset._compiled(
				version: 2,
				viewBox: .init(width: 24, height: 24),
				mirrorsInRTL: false,
				elements: []
			)
		case "symbol-bridge-depth":
			var elements: [STNSymbolAsset._Element] = []
			for _ in 0..<65 {
				elements = [.group(transform: .identity, opacity: 1, children: elements)]
			}
			_ = STNSymbolAsset._compiled(
				version: 1,
				viewBox: .init(width: 24, height: 24),
				mirrorsInRTL: false,
				elements: elements
			)
		case "symbol-bridge-opacity":
			_ = STNSymbolAsset._compiled(
				version: 1,
				viewBox: .init(width: 24, height: 24),
				mirrorsInRTL: false,
				elements: [.group(transform: .identity, opacity: 2, children: [])]
			)
		case let mode? where mode.contains("symbol"):
			let host = STNTestHost()
			let size = STNSignal(mode == "initial-symbol-size" ? Double.nan : 24)
			let stroke = STNSignal<Double?>(mode == "initial-symbol-stroke" ? -1 : nil)
			host.mount { STNSymbol(properties: .init(symbol: FaultSymbol.asset, size: size, strokeWidth: stroke)) }
			if mode == "update-symbol-size" { size.value = -1 }
			if mode == "update-symbol-stroke" { stroke.value = .infinity }
		case let mode? where mode.hasPrefix("initial-") || mode.hasPrefix("update-"):
			checkPropertyFault(mode)
		default: fatalError("Unknown fault fixture")
		}

		fatalError("Runtime fault was not diagnosed")
	}

	@MainActor private static func checkPropertyFault(_ mode: String) {
		let field = mode.split(separator: "-").last!
		let padding = STNSignal(STNInsets(0))
		let frame = STNSignal(STNFrame())
		let number = STNSignal(field == "opacity" ? 1.0 : 0.0)

		func invalidate() {
			switch field {
			case "padding":
				var invalid = STNInsets(0)
				invalid.top = -1
				padding.value = invalid
			case "frame":
				var invalid = STNFrame()
				invalid.minWidth = -1
				frame.value = invalid
			case "opacity", "border", "radius":
				number.value = .nan
			default:
				fatalError("Unknown property fault fixture")
			}
		}

		if mode.hasPrefix("initial-") {
			invalidate()
		}

		let host = STNTestHost()
		host.mount {
			STNBox(
				properties: .init(
					layout: .init(padding: padding, frame: frame),
					appearance: .init(
						opacity: field == "opacity" ? number.asProperty() : STNProperty(1.0),
						borderWidth: field == "border" ? number.asProperty() : STNProperty(0.0),
						cornerRadius: field == "radius" ? number.asProperty() : STNProperty(0.0)
					)
				)
			) {}
		}
		if mode.hasPrefix("update-") {
			invalidate()
		}
	}
}
