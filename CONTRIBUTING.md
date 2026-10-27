# Contributing

Use Swift 6.4 in Swift 6 mode. Begin API changes with an example in a separate consumer package or `Fixtures/API/Valid`; add a negative fixture when misuse should not compile.

Optionally install `just` with `brew install just`, then run `just` to list the
developer commands. `just check` runs the boundary checks, strict tests, API
fixtures, runtime-fault probes, all four example builds, and release build in
sequence. The underlying Swift commands and scripts remain supported.

1. Read [architecture](Docs/Architecture.md) and [developer experience](Docs/Design/DeveloperExperience.md).
2. Keep shared names/defaults consistent. No public placeholders, modifier chains, implicit observation, or native types in public signatures.
3. Run `just check` (or run the corresponding Swift commands and `Scripts/check-*.sh` scripts directly).
4. All four examples are built by `just build-examples` and `just check`; run affected native/VoiceOver/IME checks and record actual results. Use `just test-gui` in a logged-in macOS session with window-server access for native GUI tests; these are not enabled by `just check`.
5. Update DocC, examples, and platform limitations with the change.

Runtime faults (cycles, forbidden mutation, exhausted budgets) fail deterministically with a diagnostic. Application failures belong in application state. Validate fallible structural plans before mutating the tree.

Public API additions belong in `Stana`; cross-target engine implementation uses `package` visibility. Avoid catch-all helpers/managers and circular subsystem dependencies. Do not initialize `NSApplication` from module loading or a headless test.
