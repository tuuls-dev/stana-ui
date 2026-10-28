import Foundation

/// A portable affine mapping: x' = a*x + c*y + tx, y' = b*x + d*y + ty.
public struct STNAffineTransform: Hashable, Sendable, Codable {
	public let a: Double
	public let b: Double
	public let c: Double
	public let d: Double
	public let tx: Double
	public let ty: Double

	public init(a: Double = 1, b: Double = 0, c: Double = 0, d: Double = 1, tx: Double = 0, ty: Double = 0) {
		precondition([a, b, c, d, tx, ty].allSatisfy(\.isFinite), "Stana: nonfinite transform")
		self.a = a
		self.b = b
		self.c = c
		self.d = d
		self.tx = tx
		self.ty = ty
	}

	public static let identity = Self()

	public static func translation(x: Double, y: Double) -> Self {
		.init(tx: x, ty: y)
	}

	public static func scale(x: Double, y: Double) -> Self {
		.init(a: x, d: y)
	}

	public static func rotation(radians: Double) -> Self {
		.init(a: cos(radians), b: sin(radians), c: -sin(radians), d: cos(radians))
	}

	/// Applies `other` first, then this transform.
	public func concatenating(_ other: Self) -> Self {
		.init(
			a: a * other.a + c * other.b,
			b: b * other.a + d * other.b,
			c: a * other.c + c * other.d,
			d: b * other.c + d * other.d,
			tx: a * other.tx + c * other.ty + tx,
			ty: b * other.tx + d * other.ty + ty
		)
	}

	public func applying(to point: STNPoint) -> STNPoint {
		.init(x: a * point.x + c * point.y + tx, y: b * point.x + d * point.y + ty)
	}

	public var inverse: Self? {
		let s = max(abs(a), abs(b), abs(c), abs(d))
		guard s > 0 else {
			return nil
		}

		let determinant = (a / s) * (d / s) - (b / s) * (c / s)
		guard determinant != 0 else {
			return nil
		}

		let values = [
			d / s / determinant / s, -b / s / determinant / s,
			-c / s / determinant / s, a / s / determinant / s,
		]
		let x = -(values[0] * tx + values[2] * ty)
		let y = -(values[1] * tx + values[3] * ty)
		guard (values + [x, y]).allSatisfy(\.isFinite) else {
			return nil
		}

		return .init(a: values[0], b: values[1], c: values[2], d: values[3], tx: x, ty: y)
	}

	public func enclosing(_ rect: STNRect) -> STNRect {
		guard inverse != nil else {
			return .zero
		}

		let points = [
			STNPoint(x: rect.minX, y: rect.minY), .init(x: rect.maxX, y: rect.minY),
			.init(x: rect.minX, y: rect.maxY), .init(x: rect.maxX, y: rect.maxY),
		]
		.map { applying(to: $0) }
		let xs = points.map(\.x)
		let ys = points.map(\.y)
		return .init(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
	}

	package var maximumScale: Double {
		let s = max(abs(a), abs(b), abs(c), abs(d))
		guard s > 0 else {
			return 0
		}

		let p = a / s, q = b / s, r = c / s, t = d / s
		let trace = p * p + q * q + r * r + t * t
		let det = p * t - q * r
		return s * sqrt((trace + sqrt(max(0, trace * trace - 4 * det * det))) / 2)
	}
}
