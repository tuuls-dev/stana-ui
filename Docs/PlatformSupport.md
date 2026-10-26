# Platform Support and Qualification

## Current release tier

Developer preview. Swift 6.4, Swift 6 language mode, macOS 14 deployment target. Native backend: Core Graphics/Core Text plus a private Objective-C host. No Windows/Linux host implementation and no production/performance claim.

The deployment target is not evidence that every OS/architecture combination has been tested. Automated/local evidence is recorded in `Verification/Results.md`; manual checks remain separate.

## Included

Boxes/stacks/overlays, spacers, shaped labels, bitmap images, custom buttons/toggles, single-line editing, vertical scrolling, explicit conditional/keyed regions, reusable components, focus grouping, recorded decorative drawing, multiple windows, commands/menus/shortcuts, clipboard, system file panels/alerts, and unsigned app assembly.

## Known boundaries

- No virtualized list: scroll views mount all children.
- No multiline editor, selectable display text, grid, SVG interpreter, animation framework, plugin ABI, or document-app lifecycle.
- Initial rendering is CPU raster on the UI executor. Submission does not prove presentation.
- Native shaping/segmentation behavior follows OS data, not a claimed fixed latest Unicode release.
- Heading roles use native heading support on macOS 26+; older macOS versions retain readable text semantics.
- Custom font-family selection, rich text, transformed geometry, and advanced custom leaves/layouts are not public preview capabilities.
- User-session VoiceOver and IME verification must be completed and recorded before beta qualification.

No unavailable API is exposed as a successful no-op. Treat issues discovered during preview as tracked limitations, not blanket cross-platform support.
