# Calculator rebuild verification

Verified on 2026-10-28 with Swift 6.4 on macOS, using the public Stana consumer package.

## Automated

- Repository `just check`: passed for the initial rebuild (formatting, boundaries, strict subsystem tests, API fixtures, runtime faults, example build, and library release build). The subsequent calculator-only library fix was revalidated with the strict example tests/release build, formatting, and boundary checks. Opt-in GUI suites were skipped by `just check` as intended.
- Strict Calculator consumer release build: passed.
- Calculator-local Swift Testing suite: 29 tests across six suites, including parameterized arithmetic, syntax, and domain cases. Passed with Swift/native warnings treated as errors.
- Explicit regressions cover large fractional values, tiny nonzero values, tangent poles, invalid domains, unrounded continuation, function/scalar separation, contextual history, Unicode/cursor editing, no-op deletion, and memory overflow.
- Plot regressions cover restricted domains, poles, bounded sampling, constant/time-dependent expressions, numbered axes, zoomed label precision, degenerate viewports, and a moving trace that does not alter a time-independent curve.
- Consumer-host checks cover minimum/default/wide layouts, actual pointer activation through centered button labels, panel removal, and animation pausing for reduced motion or a hidden plot.
- Window-host checks verify transparent full-size chrome, hidden title, retained native close/minimize/zoom controls, and absence of toolbar surfaces.
- PNG exports and the generated icon decode with the platform ImageIO reader; this guards against the inherited raw-DEFLATE PNG bug.

## Native checks actually performed

- Opened the real calculator window and inspected its custom-drawn output at minimum, default, and wide sizes. Corrected clipped small labels, key alignment, console spacing, and tape layout discovered during inspection.
- Confirmed real native traffic lights on the frameless-looking window, without a visible titlebar/toolbar surface. The main window uses the native titled/full-size-content configuration because fully borderless native windows cannot retain system traffic lights.
- Typed `2+2` through native keyboard input, pressed Return, and observed a recorded result of `4` in the tape.
- The initial native sheet opened visually but later native testing reproduced an input failure: search did not accept typing while modal presentation blocked the calculator. A process sample showed an idle event loop, not a computation loop.
- A separate non-modal window restored keyboard search and calculator commands, but direct first-open pointer checks still failed. The final implementation removes the separate native window entirely: the catalog is a bounded, paged panel in the existing calculator workspace.
- Confirmed a direct coordinate mouse click on the first function immediately after opening the final in-window library: it inserted the function and restored the plot, without first typing a search.
- Confirmed native search for `sqrt`, closing/reopening with cleared search, and evaluating `2+2 = 4` while the library panel remained open.
- Added regressions for search, no-match recovery, insertion/Done, panel closing/reopening, keypad availability while browsing, restoration of the plot, and browsing every function across bounded pages.
- Enabled Animate on `sin(x)` and observed the trace point move, with changing x/y inspector values and time. The equation remained `sin(x)`.
- Confirmed numeric x/y ticks, tick marks, axis names, and native accessibility entries for the axis values.
- Native captures exercise offscreen capture, BGRA-to-PNG conversion, and writing a valid PNG. These scene captures do not contain native traffic-light pixels; those were checked in the live native window.

## Remaining manual qualification

Full VoiceOver navigation/speech, multilingual IME composition, native save-dialog cancellation/failure, fullscreen/Spaces behavior, and drag/resize ergonomics have not been comprehensively qualified. Do not infer those checks from headless tests or the presence of accessibility labels.

Keypad edits remain external text-binding replacements and reset the native editor undo history. This is an existing public API boundary, not bypassed by the example. Numerical computation is binary64 and plotting is sampled; neither constitutes exact symbolic mathematics.
