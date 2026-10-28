# Text fields

Use `STNTextField` for retained, custom-drawn single-line text editing. The writable string binding contains committed text, never an in-progress IME composition.

## Configure a field

```swift
let name = STNSignal("")
let options = STNSignal(STNTextField.Options())

STNTextField(
	properties: .init(
		value: name.binding,
		placeholder: "Display name",
		options: options,
		accessibility: .init(label: "Display name"),
		onChange: { value in /* a committed user edit */ },
		onSubmit: { /* Return/Enter */  }
	)
)
```

`Options` accepts a constant, signal, or computed value independently of `interaction.isEnabled`. Changing options updates the existing editor without resetting its text, selection, composition, or undo. Entering read-only mode cancels marked text without committing it.

Read-only fields remain focusable, selectable, and copyable. Disabled fields cannot interact. Set `options.isReadOnly` for the former and `isEnabled` for the latter. External binding updates still work in either state.

Options configure logical leading/center/trailing alignment, placeholder color, selection color, caret color, and text services. Leading/trailing follow the environment's layout direction. Shared `textStyle` owns font and foreground; shared `appearance` owns background, border, and corner radius. `layout` owns padding and frame. These shared fields accept constants, signals, and computeds without replacing the editor. Secure entry remains a component-specific property.

## Editing and selection

Fields support insertion clicks, Shift-click extension, drag selection and edge autoscrolling, double-click word selection, and triple-click select-all. Keyboard editing includes word and line movement/deletion, selection extension, clipboard commands, and grouped undo/redo. Selection and deletion preserve extended grapheme clusters.

Use `onEditorMount` to retain an `STNTextFieldHandle`. It supports `requestFocus()`, `resignFocus()`, `selection()`, `setSelection(_:)`, `selectAll()`, and `resolution()`. Calls throw after disposal. Selection positions use UTF-8 offsets and the current editor revision, not native UTF-16 ranges. Preserve anchor/head order for backward selections. Obtain fresh positions after edits or composition changes; stale positions are rejected without changing composition. A valid explicit selection cancels marked text.

`onChange` reports committed user edits, undo/redo, and accepted service replacements, but not external binding updates or marked text. `onFocusChange` and `onSelectionChange` suppress duplicate state. Callbacks run after publication and stop after disposal. Changes within a transaction are coalesced to its final published state. Application callbacks may update state.

## Platform text services

`Options.textServices` configures spelling, grammar, correction, smart quotes/dashes, text replacement, and completion. Each setting accepts `.system`, `.enabled`, or `.disabled`; the default follows platform/user preferences.

On macOS, the custom editor integrates with native text checking, spelling suggestions, correction, substitution panels, completion, and contextual editing actions. Use the **Complete** action or the platform completion key binding to request word completions. Service edits use the same binding and undo path as typing. Native panel changes apply to that retained editor until the application next publishes options. External binding replacement is not treated as newly typed input.

Selected plain text can participate in system Services and Services-based Writing Tools when available on the OS and device. Writing Tools availability is controlled by the system; this is not the full inline Writing Tools experience. IME, dead keys, emoji input, and dictation use the native text-input connection.

Query `handle.resolution()` for feature availability and effective settings. A headless test host reports native services as unavailable, not as successful no-ops. Read-only fields suppress editing services; secure fields suppress all text-disclosing services, clipboard copy/cut, and accessibility text values. Secure fields still allow ordinary text entry and paste.

Only macOS has a native backend today. Inline prediction, rich text, multiline editing, validation/formatters, password-manager autofill, and clear/reveal accessories are not provided by this API. Manual native interoperability qualification is tracked separately from automated tests.

`just example` opens the Calculator, which edits one styled expression field. That example does not demonstrate a read-only field or secure entry.
