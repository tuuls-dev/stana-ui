import StanaPrimitives

@MainActor public final class STNEnvironment {
    public let isDark = STNSignal(false)
    public let highContrast = STNSignal(false)
    public let reducedMotion = STNSignal(false)
    public let textScale = STNSignal(1.0)
    public let layoutDirection = STNSignal(STNLayoutDirection.leftToRight)
    public let theme = STNSignal<STNTheme?>(nil)
    public init() {}
}
