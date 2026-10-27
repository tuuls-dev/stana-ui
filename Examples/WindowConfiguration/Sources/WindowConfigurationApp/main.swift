import Stana

@main struct WindowConfigurationApp {
    @MainActor static func main() {
        let frameless = STNSignal(true)
        let configuration = frameless.map { value in
            STNWindow.Configuration(
                appearance: .init(frame: value ? .frameless : .system, background: .background, shadow: .enabled),
                resizing: .init(minimumContentSize: .init(width: 400, height: 280))
            )
        }
        let window = STNWindow(
            properties: .init(
                title: "Configurable windows", size: .init(width: 640, height: 420), configuration: configuration
            )
        ) {
            STNVStack(
                properties: .init(spacing: 16, padding: 16, frame: .init(maxWidth: .infinity, maxHeight: .infinity))
            ) {
                STNWindowDragRegion(properties: .init(frame: .init(height: 44, maxWidth: .infinity))) {
                    STNHStack(properties: .init(spacing: 12)) {
                        STNText(properties: .init(text: "Drag this header", font: .system(size: 16, weight: .semibold)))
                        STNSpacer()
                        STNButton(properties: .init(text: "Toggle frame", onActivate: { frameless.value.toggle() }))
                        STNButton(properties: .init(text: "Close", onActivate: { STNApplication.stop() }))
                    }
                }
                STNText(
                    properties: .init(text: "One configuration interface. STN applies each feature where supported."))
                STNText(
                    properties: .init(
                        text: "Buttons keep their input inside the drag region. Drag the corner to resize."))
                STNSpacer()
                STNHStack {
                    STNSpacer()
                    STNWindowResizeRegion(
                        properties: .init(edges: [.bottom, .trailing], frame: .init(width: 20, height: 20))
                    ) {
                        STNText(properties: .init(text: "◢"))
                    }
                }
            }
        }
        STNApplication.run(windows: [window])
    }
}
