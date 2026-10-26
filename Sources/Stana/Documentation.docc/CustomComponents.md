# Custom Components

Implement `STNComponent.makeContent(in:)` and return a composition using `some STNComponent`. Keep configuration in a nested `Properties` value, just like built-ins.

```swift
@MainActor
struct CounterPanel: STNComponent {
    struct Properties { let initialCount: Int }
    let properties: Properties

    func makeContent(in context: STNComponentContext) -> some STNComponent {
        let count = context.state(initial: properties.initialCount)
        STNVStack(properties: .init(spacing: 12)) {
            STNText(properties: .init(text: count.map { "Count: \($0)" }))
            STNButton(properties: .init(text: "Increment", onActivate: { count.value += 1 }))
        }
    }
}
```

Each occurrence mounts independently. Removal disposes local state, subscriptions, and tasks. Hoist application state into a model if it must survive removal.

Register external subscriptions through `context.own`, cleanup through `onDispose`, and asynchronous operations through `task(operation:onError:)`. Tasks begin after publication and cancel on disposal. After suspension, check request freshness before publishing results; cancellation alone is not a freshness check.

Use `STNCanvas` for immutable decorative drawing and provide an accessible equivalent for meaningful visualization. Native contexts and mutable node records are not extension APIs.
