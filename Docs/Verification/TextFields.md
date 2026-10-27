# Text-field verification — 2026-10-27

Environment: macOS 27.0.1, Apple Silicon, Swift 6.4, macOS 27 SDK; deployment target remains macOS 14.

## Automated evidence

- `just check` passed: formatting, boundaries, strict tests, positive/negative API fixtures, isolated runtime-fault probes, all five consumer builds, and the release build. In the restricted environment, SwiftPM used temporary caches with its nested manifest sandbox disabled; no verification steps were omitted.
- `STANA_GUI_TESTS=1 swift test -Xswiftc -warnings-as-errors -Xcc -Werror` passed all 100 tests across six test targets with window-server access.

- Strict Swift Testing coverage exercises pointer capture/default prevention, drag/Shift/multi-click selection, edge autoscroll/cancellation, grapheme-safe selection/deletion, visual RTL movement, grouped undo, composition, external binding replacement, reactive options, callback publication, disposed handles, secure/read-only restrictions, alignment, deterministic caret time, and stale service requests.
- Service-response tests inject annotations/replacements without relying on installed dictionaries or system preference values. Annotations do not enter the binding or undo history.
- Native GUI tests verify checking-client replacements and undo, stale revision rejection, native menu validation for editable/read-only/secure fields, and offscreen rendering. Three new native tests passed with window-server access.
- The captured [styled/mixed-direction field image](Screenshots/TextFields.png) was visually inspected: custom borders, left/right alignment, Arabic shaping, and emoji render correctly.
- Positive consumer fixtures cover configuration and handles; negative fixtures reject read-only model values and baseline alignment on a text field. `TextFields` is an independent consumer package.

## Required manual qualification

These checks have **not** been performed by a human in this change. Automated adapter tests do not establish interoperability.

| Check | Status |
| --- | --- |
| Japanese/Chinese/Korean IME candidate selection, replacement, mouse interaction, and focus changes | Pending |
| Actual spelling/grammar suggestions, automatic correction, smart quotes/dashes, text replacement, and completion in different locales | Pending |
| Dictation, dead keys, and emoji picker in a normal user session | Pending |
| Services and Services-based Writing Tools on eligible devices/OS configurations | Pending |
| VoiceOver reading, selection, editing, secure entry, and read-only state | Pending |
| Native keyboard behavior across mixed RTL/LTR boundaries and minimum-macOS coverage | Pending |

## Deliberate boundaries

Only macOS has a backend. Native service settings default to system preferences, with per-field overrides. Native panel changes are retained until options are next published by the application. Unsupported/inapplicable services are exposed through handle resolution; headless tests never claim native service support.

Completion is available through the platform completion command. Inline prediction and full inline Writing Tools are not implemented. The control remains single-line/plain-text; returned service text is normalized through the same editing path as typing. Secure fields do not participate in text checking, completion, Services, or clipboard copy/cut; read-only fields reject all mutation paths.
