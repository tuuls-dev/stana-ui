# Contributing

Use Swift 6.4 in Swift 6 mode. Begin API changes with an example in a separate consumer package or `Fixtures/API/Valid`; add a negative fixture when misuse should not compile.

1. Read [architecture](Docs/Architecture.md) and [developer experience](Docs/Design/DeveloperExperience.md).
2. Keep shared names/defaults consistent. No public placeholders, modifier chains, implicit observation, or native types in public signatures.
3. Run `swift test`, `Scripts/check-api-fixtures.sh`, `Scripts/check-runtime-faults.sh`, and `Scripts/check-boundaries.sh`.
4. Build all three examples; run affected native/VoiceOver/IME scripts and record actual results.
5. Update DocC, examples, and platform limitations with the change.

Runtime faults (cycles, forbidden mutation, exhausted budgets) fail deterministically with a diagnostic. Application failures belong in application state. Validate fallible structural plans before mutating the tree.

Public API additions belong in `Stana`; cross-target engine implementation uses `package` visibility. Avoid catch-all helpers/managers and circular subsystem dependencies. Do not initialize `NSApplication` from module loading or a headless test.
