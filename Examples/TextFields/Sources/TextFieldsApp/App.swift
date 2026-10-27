import Stana

@main struct TextFieldsApp {
	@MainActor static func main() {
		let text = STNSignal("Try selecting words, undo, and the context menu.")
		let password = STNSignal("")
		let readOnly = STNSignal(false)
		let enabled = STNSignal(true)
		let status = STNSignal("Platform text services follow your system preferences.")
		let options = STNComputed { STNTextField.Options(isReadOnly: readOnly.value) }
		var editor: STNTextFieldHandle?
		let window = STNWindow(properties: .init(title: "Text fields", size: .init(width: 600, height: 520))) {
			STNVStack(properties: .init(spacing: 18, padding: 28)) {
				STNText(properties: .init(text: "Text fields", font: .system(size: 26, weight: .bold)))
				STNText(properties: .init(text: "Editable text", accessibility: .init(heading: 2)))
				STNTextField(
					properties: .init(
						value: text.binding,
						placeholder: "Enter text",
						frame: .init(width: 540),
						isEnabled: enabled,
						options: options,
						accessibility: .init(label: "Editable text"),
						onEditorMount: { editor = $0 },
						onChange: { _ in status.value = "Committed edit. Use Undo to restore it." },
						onSubmit: { status.value = "Submitted." }
					)
				)
				STNHStack(properties: .init(spacing: 20)) {
					STNToggle(properties: .init(text: "Read only", isOn: readOnly.binding))
					STNToggle(properties: .init(text: "Enabled", isOn: enabled.binding))
					STNButton(
						properties: .init(
							text: "Select all",
							onActivate: {
								try? editor?.requestFocus()
								try? editor?.selectAll()
							}
						)
					)
				}
				STNText(properties: .init(text: "Right-aligned, styled text"))
				STNTextField(
					properties: .init(
						value: text.binding,
						frame: .init(width: 540),
						options: .init(alignment: .trailing, borderColor: .accent, borderWidth: 2, cornerRadius: 10),
						accessibility: .init(label: "Right-aligned text")
					)
				)
				STNText(properties: .init(text: "Secure entry"))
				STNTextField(
					properties: .init(
						value: password.binding,
						placeholder: "Password",
						frame: .init(width: 540),
						secure: true,
						accessibility: .init(label: "Password")
					)
				)
				STNText(properties: .init(text: status, foreground: .secondaryText))
			}
		}
		STNApplication.run(windows: [window])
	}
}
