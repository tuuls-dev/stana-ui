/// Semantic colors shared by built-ins. Platform adapters may supply different defaults.
public struct STNTheme: Equatable, Sendable {
    public var background: STNColor
    public var surface: STNColor
    public var text: STNColor
    public var secondaryText: STNColor
    public var accent: STNColor
    public var border: STNColor
    public init(
        background: STNColor, surface: STNColor, text: STNColor, secondaryText: STNColor, accent: STNColor,
        border: STNColor
    ) {
        self.background = background
        self.surface = surface
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
        self.border = border
    }
    public static let light = Self(
        background: .background.resolved(dark: false), surface: .surface.resolved(dark: false),
        text: .text.resolved(dark: false), secondaryText: .secondaryText.resolved(dark: false),
        accent: .accent.resolved(dark: false), border: .border.resolved(dark: false))
    public static let dark = Self(
        background: .background.resolved(dark: true), surface: .surface.resolved(dark: true),
        text: .text.resolved(dark: true), secondaryText: .secondaryText.resolved(dark: true),
        accent: .accent.resolved(dark: true), border: .border.resolved(dark: true))
    package func resolve(_ color: STNColor, dark: Bool) -> STNColor {
        let selected: STNColor
        switch color.token {
        case .explicit: selected = color
        case .background: selected = background
        case .surface: selected = surface
        case .text: selected = text
        case .secondaryText: selected = secondaryText
        case .accent: selected = accent
        case .border: selected = border
        }
        return selected.resolved(dark: dark)
    }
}
