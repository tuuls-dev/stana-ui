import StanaPrimitives

public struct STNConstraints: Hashable, Sendable {
    public let minWidth: Double
    public let maxWidth: Double
    public let minHeight: Double
    public let maxHeight: Double
    public init(
        minWidth: Double = 0, maxWidth: Double = .infinity, minHeight: Double = 0, maxHeight: Double = .infinity
    ) {
        precondition(
            minWidth.isFinite && minHeight.isFinite && minWidth >= 0 && minHeight >= 0 && maxWidth >= minWidth
                && maxHeight >= minHeight, "Stana: invalid constraints")
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }
    package func clamp(_ size: STNSize) -> STNSize {
        .init(width: min(maxWidth, max(minWidth, size.width)), height: min(maxHeight, max(minHeight, size.height)))
    }
}
