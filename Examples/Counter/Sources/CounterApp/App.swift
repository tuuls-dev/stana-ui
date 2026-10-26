import Foundation
import Stana

@main
struct CounterApp {
    @MainActor static func main() {
        let count = STNSignal(0)
        let increment = STNCommand(properties: .init(title: "Increment", shortcut: .init("i")) { count.value += 1 })
        let window = STNWindow(properties: .init(title: "Stana Counter", size: .init(width: 480, height: 320))) {
            STNVStack(properties: .init(alignment: .leading, spacing: 16, padding: 28)) {
                STNText(
                    properties: .init(
                        text: "A retained Swift desktop UI", font: .system(size: 24, weight: .semibold),
                        accessibility: .init(heading: 1)))
                STNText(properties: .init(text: count.map { "Count: \($0)" }, font: .system(size: 20)))
                STNButton(
                    properties: .init(
                        text: "Increment", accessibility: .init(hint: "Increases the count by one"),
                        onActivate: { increment.perform() }))
                STNText(
                    properties: .init(text: "The label updates. Its parent never rebuilds.", foreground: .secondaryText)
                )
            }
        }
        if CommandLine.arguments.contains("--smoke-test") {
            Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                count.value += 1
                precondition(count.value == 1 && window.isOpen)
                print("Stana native smoke: async wake-up and retained update passed")
                STNApplication.stop()
            }
        }
        STNApplication.run(
            windows: [window],
            menus: [
                STNMenu(properties: .init(title: "Counter")) { increment }
            ])
    }
}
