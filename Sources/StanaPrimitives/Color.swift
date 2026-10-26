import Foundation

public struct STNColor: Hashable, Sendable {
    public enum Token: Sendable { case explicit, surface, background, text, secondaryText, accent, border }
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public let token: Token
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        precondition([red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) })
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        token = .explicit
    }
    private init(_ token: Token) {
        red = 0
        green = 0
        blue = 0
        alpha = 1
        self.token = token
    }
    public static let clear = Self(red: 0, green: 0, blue: 0, alpha: 0)
    public static let white = Self(red: 1, green: 1, blue: 1)
    public static let black = Self(red: 0, green: 0, blue: 0)
    public static let surface = Self(.surface)
    public static let background = Self(.background)
    public static let text = Self(.text)
    public static let secondaryText = Self(.secondaryText)
    public static let accent = Self(.accent)
    public static let border = Self(.border)
    public func resolved(dark: Bool, highContrast: Bool = false) -> Self {
        switch token {
        case .explicit: return self
        case .accent: return .init(red: 0.1, green: 0.43, blue: 0.95)
        case .text: return dark ? .white : .black
        case .secondaryText: return .init(red: dark ? 0.72 : 0.36, green: dark ? 0.72 : 0.36, blue: dark ? 0.74 : 0.38)
        case .surface: return dark ? .init(red: 0.17, green: 0.17, blue: 0.18) : .white
        case .background:
            return dark ? .init(red: 0.11, green: 0.11, blue: 0.12) : .init(red: 0.96, green: 0.96, blue: 0.97)
        case .border:
            let v = highContrast ? (dark ? 0.8 : 0.2) : (dark ? 0.36 : 0.76)
            return .init(red: v, green: v, blue: v)
        }
    }
}

public struct STNFont: Hashable, Sendable {
    public enum Weight: Double, Sendable {
        case regular = 0
        case medium = 0.23
        case semibold = 0.3
        case bold = 0.4
    }
    public let size: Double
    public let weight: Weight
    public static func system(size: Double = 13, weight: Weight = .regular) -> Self {
        precondition(size.isFinite && size > 0)
        return Self(size: size, weight: weight)
    }
}
