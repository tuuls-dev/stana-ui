import Foundation
import StanaAccessibility
import StanaGraphics
import StanaPrimitives
import StanaText

package enum PlatformEvent: Sendable {
    case resize(STNSize, Double)
    case pointer(Int, STNPoint)
    case scroll(STNPoint, Double, Double)
    case key(String, Bool, Bool)
    case close
    case activate(UInt64)
    case focus(UInt64)
    case appearance(Bool, Bool, Bool)
    case deactivated
    case resourcesChanged(Bool)
    case modalState(Bool)
}

@MainActor package protocol PlatformWindow: AnyObject {
    var renderer: any Renderer { get }
    var accessibility: any AccessibilityBridge { get }
    var onEvent: ((PlatformEvent) -> Void)? { get set }
    var onDraw: (() -> Void)? { get set }
    func show()
    func requestRedraw()
    func setTitle(_ title: String)
    func close()
}

@MainActor package protocol PlatformHost {
    var textService: any TextService { get }
    func createWindow(title: String, size: STNSize) throws -> any PlatformWindow
    func run()
}
