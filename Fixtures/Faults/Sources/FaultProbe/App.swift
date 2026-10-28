import Foundation
import Stana
import StanaTesting

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
