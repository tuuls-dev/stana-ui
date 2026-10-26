# Desktop Applications

`STNCommand` is the shared action for a button, menu item, and keyboard shortcut. `perform()` checks enabled state and batches the action.

```swift
let save = STNCommand(properties: .init(title: "Save…", shortcut: .init("s")) {
    Task { @MainActor in
        guard let url = await STNFileDialog.save(suggestedName: "Untitled.txt") else { return }
        // File serialization/writing is application-owned.
        print(url.lastPathComponent)
    }
})
let fileMenu = STNMenu(properties: .init(title: "File")) { save }
```

`STNFileDialog.open`/`save` return nil on cancellation. `STNAlert.show` presents asynchronously. `STNClipboard` exposes plain text. Native AppKit types never appear in these APIs.

Open additional windows with `STNApplication.open`, close an individual window with `window.close()`, and stop the application with `STNApplication.stop()`. Keep authoritative model state application-owned when sharing it across windows.
