import StanaPrimitives

package struct DamageTracker {
    package private(set) var rectangles: [STNRect] = []
    package init() {}
    package mutating func add(_ rect: STNRect) {
        guard !rect.isEmpty else { return }
        var combined = rect
        rectangles.removeAll { existing in
            if existing.intersects(combined) {
                combined = combined.union(existing)
                return true
            }
            return false
        }
        rectangles.append(combined)
    }
    package func resolved(in window: STNRect) -> [STNRect] {
        let area = rectangles.reduce(0) { $0 + $1.size.width * $1.size.height }
        if rectangles.count > 24 || area > window.size.width * window.size.height * 0.6 { return [window] }
        return rectangles.map { $0.intersection(window) }.filter { !$0.isEmpty }
    }
}
