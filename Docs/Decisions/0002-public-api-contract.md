# ADR 0002: Properties-first, explicit retained authoring

Accepted. Built-ins expose nested component-specific `Properties` through a labelled initializer. Actions are properties, not trailing action closures. Only children use ordinary component trailing closures. Structural branches/rows remain explicit.

Use typed overloads to accept constants, signals, and computeds at supported read-only fields; writable fields take bindings. Internal typed property sources install subscriptions once. No implicit observation, property dictionaries, dynamic members, or modifier chains.

Builders and `makeContent` are mount operations. Defaults never fabricate required text or writable state. Shared capabilities have shared names, types, and defaults. External consumer builds and misuse compilation fixtures gate changes.
