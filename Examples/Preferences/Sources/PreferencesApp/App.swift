import Foundation
import Stana

@main
struct PreferencesApp {
	@MainActor static func main() {
		let name = STNSignal("Alloys")
		let notifications = STNSignal(true)
		let status = STNSignal("Changes are local until saved.")
		let save = STNCommand(
			properties: .init(title: "Save Preferences…", shortcut: .init("s")) {
				Task { @MainActor in
					guard let url = await STNFileDialog.save(suggestedName: "preferences.txt") else {
						return
					}

					let data = Data("Name: \(name.value)\nNotifications: \(notifications.value)\n".utf8)
					do {
						try await Task.detached { try data.write(to: url, options: .atomic) }.value
						status.value = "Preferences saved."
					} catch {
						status.value = "Could not save preferences."
						await STNAlert.show(title: "Save failed", message: "Choose another destination and try again.")
					}
				}
			}
		)
		let window = STNWindow(properties: .init(title: "Preferences", size: .init(width: 520, height: 420))) {
			STNVStack(properties: .init(spacing: 20, layout: .init(padding: STNInsets(28)))) {
				STNText(
					properties: .init(
						text: "Preferences",
						textStyle: .init(font: STNFont.system(size: 26, weight: .bold)),
						accessibility: .init(heading: 1)
					)
				)
				LabelledField(properties: .init(title: "Display name", value: name.binding))
				STNToggle(properties: .init(text: "Notifications", isOn: notifications.binding))
				STNText(properties: .init(text: status, textStyle: .init(foreground: STNColor.secondaryText)))
				STNButton(properties: .init(text: "Save Preferences…", onActivate: { save.perform() }))
			}
		}
		STNApplication.run(windows: [window], menus: [STNMenu(properties: .init(title: "File")) { save }])
	}
}
