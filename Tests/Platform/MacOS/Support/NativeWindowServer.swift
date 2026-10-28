import Foundation
import Testing

/// Native windows share one application, focus, display/space transitions, and
/// presentation clocks. Serialize the GUI suites together, not just each suite
/// internally, so another test's fullscreen transition cannot reset an epoch in
/// the middle of a temporal-state or presentation test.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["STANA_GUI_TESTS"] == "1"), .serialized)
@MainActor struct NativeWindowServer {}
