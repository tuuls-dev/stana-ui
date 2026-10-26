import Foundation
import StanaCore
import StanaPlatformMacOS
import StanaPrimitives

@MainActor public enum STNApplication {
    private static var windows: [ObjectIdentifier: STNWindow] = [:]
    private static var menus: [STNMenu] = []
    /// Enters the native event loop. Call from a synchronous `@MainActor` entry point.
    public static func run(windows: [STNWindow], menus: [STNMenu] = []) {
        install(menus: menus)
        for window in windows {
            do { try open(window) } catch { STNDiagnostics.report(.nativeFailure("Window creation failed")) }
        }
        MacOSHost().run()
    }
    public static func open(_ window: STNWindow) throws {
        if window.session != nil { return }
        let host = MacOSHost()
        let session = MountSession(
            size: window.properties.size, text: host.textService, environment: window.properties.environment)
        let native = try host.createWindow(title: window.properties.title.read(), size: window.properties.size)
        window.session = session
        windows[ObjectIdentifier(window)] = window
        session.onClose = { [weak window] in
            guard let window else { return }
            window.session = nil
            windows.removeValue(forKey: ObjectIdentifier(window))
        }
        session.attach(native)
        session.mount(window.content)
        if window.properties.title.reactive {
            let observation = ValueObservation(read: window.properties.title.read, equals: { $0 == $1 }) {
                [weak native] in native?.setTitle($0)
            }
            session.document.root.scope.own { observation.cancel() }
            ReactiveRuntime.shared.batch { ReactiveRuntime.shared.enqueue(observation) }
        }
        native.show()
    }
    public static func install(menus: [STNMenu]) {
        for menu in self.menus { menu.uninstall() }
        self.menus = menus
        MacOSDesktopServices.resetMenus()
        for menu in menus { menu.install(parent: 0) }
    }
    public static func stop() {
        for window in Array(windows.values) { window.close() }
        windows.removeAll()
        menus.forEach { $0.uninstall() }
        menus.removeAll()
        MacOSDesktopServices.resetMenus()
        MacOSDesktopServices.stop()
    }
}
