# Contributing

Use Swift 6.4 in Swift 6 mode. Begin API changes with an example in a separate consumer package or `Fixtures/API/Valid`; add a negative fixture when misuse should not compile.

Optionally install `just` with `brew install just`, then run `just` to list the
developer commands. `just check` runs formatting and boundary checks, strict tests, API
fixtures, runtime-fault probes, all five example builds, and release build in
sequence. The underlying Swift commands and scripts remain supported.

## Releases

Run `just version major`, `just version minor`, or `just version patch` from a
clean `main` checkout matching `origin/main`. The command asks for confirmation,
bumps `VERSION`, commits it, creates an annotated `vX.Y.Z` tag, and atomically
pushes the commit and tag to `origin`. `VERSION` starts at `0.0.0`; major and
minor bumps reset lower components. No tests run as part of this command. A failed
push retains the local commit and tag and prints the command to retry.

## Swift formatting

Run `just format` before submitting Swift changes, or `just check-format` to check
without editing files. Both use Swift 6.4's built-in `swift format`; no additional
formatter is required. Without `just`, run `Scripts/format-swift.sh` or
`Scripts/format-swift.sh lint`. They cover repository Swift files, including new
unignored files, package manifests, examples, benchmarks, and API fixtures, while
excluding ignored build output. Formatting is checked first by `just check` and CI.

Use tabs (one per indentation level, displayed as four columns), a 120-column
limit, and at most one consecutive blank line. Wrapped argument lists put each
argument on its own line; multiline expression-chain components are separated
onto lines. `.editorconfig` supplies matching Swift indentation settings.

Give code breathing room: separate methods, initializers, types, and computed
properties with one blank line, while keeping related stored properties together.
Expand nonempty one-line function and control-flow bodies and leave a blank line
between multiline control-flow blocks and following statements. Avoid padding
inside opening/closing braces. These are writing conventions, not fully automated
checks: the bundled formatter preserves existing gaps and expanded bodies, but
cannot require their presence.

## Contribution checklist

1. Read [architecture](Docs/Architecture.md) and [developer experience](Docs/Design/DeveloperExperience.md).
2. Keep shared names/defaults consistent. No public placeholders, modifier chains, implicit observation, or native types in public signatures.
3. Run `just check` (or run the corresponding Swift commands and `Scripts/check-*.sh` scripts directly).
4. All five examples are built by `just build-examples` and `just check`; run affected native/VoiceOver/IME checks and record actual results. Use `just test-gui` in a logged-in macOS session with window-server access for native GUI tests; these are not enabled by `just check`.
5. Update DocC, examples, and platform limitations with the change.

Runtime faults (cycles, forbidden mutation, exhausted budgets) fail deterministically with a diagnostic. Application failures belong in application state. Validate fallible structural plans before mutating the tree.

Public API additions belong in `Stana`; cross-target engine implementation uses `package` visibility. Avoid catch-all helpers/managers and circular subsystem dependencies. Do not initialize `NSApplication` from module loading or a headless test.
