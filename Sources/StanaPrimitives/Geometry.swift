import Foundation

public struct STNPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) {
        precondition(x.isFinite && y.isFinite)
        self.x = x
        self.y = y
    }
    public static let zero = Self()
}

public struct STNSize: Hashable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double = 0, height: Double = 0) {
        precondition(
            width.isFinite && height.isFinite && width >= 0 && height >= 0,
            "Stana: sizes must be finite and nonnegative")
        self.width = width
        self.height = height
    }
    public static let zero = Self()
}

public struct STNRect: Hashable, Sendable {
    public var origin: STNPoint
    public var size: STNSize
    public init(x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
        origin = .init(x: x, y: y)
        size = .init(width: width, height: height)
    }
    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { minX + size.width }
    public var maxY: Double { minY + size.height }
    public var isEmpty: Bool { size.width == 0 || size.height == 0 }
    public func contains(_ p: STNPoint) -> Bool { p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY }
    public func intersects(_ r: Self) -> Bool { maxX > r.minX && r.maxX > minX && maxY > r.minY && r.maxY > minY }
    public func union(_ r: Self) -> Self {
        if isEmpty { return r }
        if r.isEmpty { return self }
        return .init(
            x: min(minX, r.minX), y: min(minY, r.minY), width: max(maxX, r.maxX) - min(minX, r.minX),
            height: max(maxY, r.maxY) - min(minY, r.minY))
    }
    public func intersection(_ r: Self) -> Self {
        .init(
            x: max(minX, r.minX), y: max(minY, r.minY), width: max(0, min(maxX, r.maxX) - max(minX, r.minX)),
            height: max(0, min(maxY, r.maxY) - max(minY, r.minY)))
    }
    public func inset(by p: STNInsets) -> Self {
        .init(
            x: minX + p.leading, y: minY + p.top, width: max(0, size.width - p.horizontal),
            height: max(0, size.height - p.vertical))
    }
    public static let zero = Self()
}

public struct STNInsets: Hashable, Sendable, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double
    public init(_ all: Double) { self.init(top: all, leading: all, bottom: all, trailing: all) }
    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        precondition([top, leading, bottom, trailing].allSatisfy { $0.isFinite && $0 >= 0 })
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
    public init(integerLiteral value: Int) { self.init(Double(value)) }
    public init(floatLiteral value: Double) { self.init(value) }
    public var horizontal: Double { leading + trailing }
    public var vertical: Double { top + bottom }
    public static let zero = Self(0)
}

public struct STNFrame: Hashable, Sendable {
    public var width: Double?
    public var height: Double?
    public var minWidth: Double
    public var maxWidth: Double
    public var minHeight: Double
    public var maxHeight: Double
    package let fillsWidth: Bool
    package let fillsHeight: Bool
    public init(
        width: Double? = nil, height: Double? = nil, minWidth: Double = 0, maxWidth: Double? = nil,
        minHeight: Double = 0, maxHeight: Double? = nil
    ) {
        let resolvedMaxWidth = maxWidth ?? .infinity
        let resolvedMaxHeight = maxHeight ?? .infinity
        precondition(
            minWidth.isFinite && minHeight.isFinite && minWidth >= 0 && minHeight >= 0 && resolvedMaxWidth >= minWidth
                && resolvedMaxHeight >= minHeight)
        precondition(width.map { $0.isFinite && $0 >= 0 } ?? true)
        precondition(height.map { $0.isFinite && $0 >= 0 } ?? true)
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.maxWidth = resolvedMaxWidth
        self.minHeight = minHeight
        self.maxHeight = resolvedMaxHeight
        fillsWidth = maxWidth == .infinity
        fillsHeight = maxHeight == .infinity
    }
}

public enum STNAlignment: Sendable { case leading, center, trailing, firstBaseline }
public enum STNLayoutDirection: Sendable { case leftToRight, rightToLeft }
public enum STNVisibility: Sendable { case visible, hidden, collapsed }
