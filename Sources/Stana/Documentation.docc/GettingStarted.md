# Getting Started

Create a SwiftPM executable depending on the `Stana` library product. Import `Stana` in a synchronous `@MainActor` entry point, create an `STNWindow`, then call `STNApplication.run(windows:)`.

```swift
let window = STNWindow(properties: .init(title: "Hello")) {
	STNVStack(properties: .init(spacing: 12, layout: .init(padding: STNInsets(24)))) {
		STNText(properties: .init(text: "Hello, desktop"))
		STNButton(properties: .init(text: "Continue", onActivate: { print("Continue") }))
	}
}
STNApplication.run(windows: [window])
```

Configure a node through its typed properties before composing children. Child closures contain only components. Built-in controls already supply keyboard behavior and semantic roles.

Run the separate `Examples/Calculator` package for a complete application. `Scripts/package-macos-app.sh` assembles a distributable unsigned bundle; signing remains the application's responsibility.
