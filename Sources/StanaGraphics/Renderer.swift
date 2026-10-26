import StanaPrimitives
import StanaScene

package struct FrameCompletion: Sendable {
    package let sceneRevision: UInt64
    package let surfaceEpoch: UInt64
    package let presentationConfirmed: Bool
    package init(sceneRevision: UInt64, surfaceEpoch: UInt64, presentationConfirmed: Bool) {
        self.sceneRevision = sceneRevision
        self.surfaceEpoch = surfaceEpoch
        self.presentationConfirmed = presentationConfirmed
    }
}

@MainActor package protocol Renderer: AnyObject {
    var backingRevision: UInt64 { get }
    var surfaceEpoch: UInt64 { get }
    func submit(_ scene: SceneSnapshot) throws -> FrameCompletion
    func detach()
}
