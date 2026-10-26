# State and Bindings

`STNSignal` holds current state on the UI executor. Pass a signal or computed directly to a supported reactive property. Reading `.value` in an ordinary builder captures a constant.

```swift
let name = STNSignal("")
STNVStack {
    STNTextField(properties: .init(value: name.binding, accessibility: .init(label: "Name")))
    STNText(properties: .init(text: name.map { "Hello, \($0)" }))
}
```

Computeds are synchronous, pure, nonthrowing functions. They dynamically track actual reads and demand current dependencies. Do not mutate signals, perform I/O, or create tasks inside them. Comparators must be substitutable equivalence relations.

`STNTransaction.perform` batches writes synchronously. Source reads see the latest writes; bound properties publish at commit. Nested transactions join the outer batch. Transactions do not provide rollback and cannot span an `await`.

Use `STNIf` for changing branches. Value-item `STNForEach` replaces descendants when an item changes; stable observable reference rows preserve editors during sibling updates and moves. A key never silently captures a different model instance.
