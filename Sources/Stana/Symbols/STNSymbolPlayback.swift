/// A deterministic paint-only effect. Effects do not change layout or accessibility bounds.
public enum STNSymbolEffect: Sendable, Equatable {
	case rotate
	case pulse
	case bounce
}

/// Requests are caller-owned generations; a different committed request restarts a one-shot.
public enum STNSymbolPlayback: Sendable, Equatable {
	case none
	case loop(STNSymbolEffect)
	case once(STNSymbolEffect, request: UInt64)
}
