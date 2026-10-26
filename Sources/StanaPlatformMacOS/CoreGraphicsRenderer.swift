import CStanaMacOS
import StanaGraphics
import StanaPrimitives
import StanaScene

@MainActor package final class CoreGraphicsRenderer: Renderer {
    private weak var window: MacOSWindow?
    package private(set) var backingRevision: UInt64 = 0
    package private(set) var surfaceEpoch: UInt64 = 1
    package init(window: MacOSWindow) { self.window = window }
    package func invalidate() {
        nextRevision(&surfaceEpoch)
        backingRevision = 0
    }
    package func submit(_ scene: SceneSnapshot) throws -> FrameCompletion {
        guard let handle = window?.handle else { throw STNError.nodeDisposed }
        let full =
            scene.damageBaseRevision != backingRevision || scene.surfaceEpoch != surfaceEpoch || backingRevision == 0
        let damage = scene.damage.map(\.native)
        if !damage.isEmpty || full {
            let success = damage.withUnsafeBufferPointer {
                stn_frame_begin(handle, scene.size.width, scene.size.height, $0.baseAddress, $0.count, full)
            }
            guard success else { throw STNError.nativeFailure("Raster surface allocation failed or exceeds 256 MiB") }
            for command in scene.commands {
                switch command {
                case .fill(let r, let c, let radius): stn_draw_fill(handle, r.native, c.native, radius)
                case .stroke(let r, let c, let width, let radius):
                    stn_draw_stroke(handle, r.native, c.native, width, radius)
                case .text(let text, let r, let font, let c, let wraps):
                    text.withNativeUTF8 {
                        stn_draw_text(handle, $0, r.native, font.size, font.weight.rawValue, c.native, wraps)
                    }
                case .image(let data, let r):
                    data.withUnsafeBytes {
                        stn_draw_image(handle, $0.bindMemory(to: UInt8.self).baseAddress, $0.count, r.native)
                    }
                case .pushClip(let r): stn_draw_clip_push(handle, r.native)
                case .popClip: stn_draw_clip_pop(handle)
                case .pushOpacity(let opacity): stn_draw_opacity_push(handle, opacity)
                case .popOpacity: stn_draw_opacity_pop(handle)
                }
            }
            stn_frame_end(handle)
        }
        backingRevision = scene.sceneRevision
        return .init(sceneRevision: backingRevision, surfaceEpoch: surfaceEpoch, presentationConfirmed: false)
    }
    package func detach() { window = nil }
}
