import Foundation

/// Straight (not premultiplied) scene-linear extended sRGB. 1 is reference white.
public struct STNExtendedColor: Hashable, Sendable, Codable {
	public let red: Double
	public let green: Double
	public let blue: Double
	public let alpha: Double

	public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
		precondition([red, green, blue].allSatisfy { $0.isFinite && abs($0) <= 65_504 })
		precondition(alpha.isFinite && (0...1).contains(alpha))
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}
}

public struct STNGPUVertex: Hashable, Sendable {
	public let position: STNPoint
	public let color: STNExtendedColor

	public init(position: STNPoint, color: STNExtendedColor) {
		self.position = position
		self.color = color
	}
}

/// Immutable indexed triangle storage. Copies retain the same identity.
public struct STNGPUMesh: Equatable, Sendable {
	package let version = RenderVersion()
	package let vertices: [STNGPUVertex]
	package let indices: [UInt32]

	public init(vertices: [STNGPUVertex], indices: [UInt32]) {
		precondition(indices.count.isMultiple(of: 3) && indices.allSatisfy { Int($0) < vertices.count })
		self.vertices = vertices
		self.indices = indices
	}

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.version == rhs.version
	}
}

package struct GPUColor: Hashable, Sendable {
	package let components: [Double]
	package let linear: Bool
	package let semantic: STNColor?

	package init(_ color: STNColor) {
		components = [color.red, color.green, color.blue, color.alpha]
		linear = false
		semantic = color
	}

	package init(_ color: STNExtendedColor) {
		components = [color.red, color.green, color.blue, color.alpha]
		linear = true
		semantic = nil
	}

	package func resolved(in environment: GPUColorEnvironment) -> [Double] {
		guard let semantic else { return components }
		let color =
			environment.theme?.resolve(semantic, dark: environment.dark)
			?? semantic.resolved(dark: environment.dark, highContrast: environment.highContrast)
		return [color.red, color.green, color.blue, color.alpha]
	}
}

package struct GPUColorEnvironment: Equatable, Sendable {
	package let dark: Bool
	package let highContrast: Bool
	package let theme: STNTheme?

	package init(dark: Bool = false, highContrast: Bool = false, theme: STNTheme? = nil) {
		self.dark = dark
		self.highContrast = highContrast
		self.theme = theme
	}
}

package enum GPUCommand: Equatable, Sendable {
	case rect(STNRect, Double, GPUColor)
	case ellipse(STNRect, GPUColor)
	case mesh(STNGPUMesh)
	case polyline([STNPoint], Double, GPUColor, Bool)
	case program(STNGPUProgram)
}

/// Ordered GPU operations in canvas-local top-left coordinates.
public struct STNGPUDrawing: Equatable, Sendable {
	package private(set) var version = RenderVersion()
	package private(set) var commands: [GPUCommand] = []

	public init() {}

	public init(program: STNGPUProgram) {
		commands = [.program(program)]
	}

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.version == rhs.version
	}

	public mutating func fillRect(_ rect: STNRect, color: STNColor, cornerRadius: Double = 0) {
		appendRect(rect, radius: cornerRadius, color: GPUColor(color))
	}

	public mutating func fillRect(_ rect: STNRect, color: STNExtendedColor, cornerRadius: Double = 0) {
		appendRect(rect, radius: cornerRadius, color: GPUColor(color))
	}

	private mutating func appendRect(_ rect: STNRect, radius: Double, color: GPUColor) {
		precondition(radius.isFinite && radius >= 0)
		commands.append(.rect(rect, radius, color))
		version = RenderVersion()
	}

	public mutating func fillEllipse(_ rect: STNRect, color: STNColor) {
		commands.append(.ellipse(rect, GPUColor(color)))
		version = RenderVersion()
	}

	public mutating func fillEllipse(_ rect: STNRect, color: STNExtendedColor) {
		commands.append(.ellipse(rect, GPUColor(color)))
		version = RenderVersion()
	}

	public mutating func drawMesh(_ mesh: STNGPUMesh) {
		commands.append(.mesh(mesh))
		version = RenderVersion()
	}

	public mutating func strokePolyline(_ points: [STNPoint], color: STNColor, width: Double = 1, closed: Bool = false)
	{
		precondition(width.isFinite && width >= 0)
		commands.append(.polyline(points, width, GPUColor(color), closed))
		version = RenderVersion()
	}

	public mutating func strokePolyline(
		_ points: [STNPoint],
		color: STNExtendedColor,
		width: Double = 1,
		closed: Bool = false
	) {
		precondition(width.isFinite && width >= 0)
		commands.append(.polyline(points, width, GPUColor(color), closed))
		version = RenderVersion()
	}

	package var requiresExtended: Bool {
		commands.contains {
			switch $0 {
			case .rect(_, _, let c), .ellipse(_, let c), .polyline(_, _, let c, _): c.linear
			case .mesh: true
			case .program(let program): program.outputColor == .extendedLinear
			}
		}
	}
}

public enum STNRenderingColorMode: String, Sendable, Codable {
	case automatic, sdr, extendedLinear
}
