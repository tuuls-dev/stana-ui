# Platform Support and Qualification

## Current release tier

Developer preview. Swift 6.4, Swift 6 language mode, macOS 26 deployment target. Native backend: worker Core Graphics/Core Text rasterization plus retained Metal composition and a Swift AppKit host. No Windows/Linux host implementation and no production/performance claim.

The deployment target is not evidence that every OS/architecture combination has been tested. Automated/local evidence is recorded in `Verification/Results.md`; manual checks remain separate.

## Included

Boxes/stacks/overlays, spacers, shaped labels, bitmap images, custom buttons/toggles, single-line editing (mouse/keyboard selection, read-only configuration, grouped undo, styling, and native macOS text services), vertical scrolling, explicit conditional/keyed regions, reusable components, focus grouping, recorded decorative drawing, multiple configurable windows (including frameless windows), native panels/sheets/tabs, toolbars and retained chrome surfaces, commands/menus/shortcuts, clipboard, system file panels/alerts, and unsigned app assembly.

## Known boundaries

- Shared layout/font inputs are reactive, but do not introduce animation, custom font families, or inherited typography. Text-field common styling belongs to shared groups, not editor Options.
- No virtualized list: scroll views mount all children.
- Text-field completion uses the platform completion action; inline predictive text and full inline Writing Tools are not implemented. System Services/Writing Tools availability follows OS/device configuration.
- No multiline editor, selectable display text, grid, SVG interpreter, animation framework, plugin ABI, or document-app lifecycle.
- Metal is the default renderer. CPU decorative drawing remains supported alongside GPU shapes, trusted application Metal programs, affine retained layers, and ordered backdrop effects. There is no silent CPU fallback for an unavailable Metal device or failed shader.
- Submission/offscreen completion do not prove presentation. Native positive timestamps and matching GPU success confirm last-known geometry; zero/missing observations remain explicitly unknown.
- Native shaping/segmentation behavior follows OS data, not a claimed fixed latest Unicode release.
- Heading roles use native heading support on all supported macOS versions.
- Custom font-family selection, rich text, and advanced custom layouts are not public preview capabilities. Arbitrary non-affine transforms are not supported.
- GPU texture ingress supports encoded sRGB and extended-linear sRGB, not PQ/HLG or arbitrary color primaries. Shaders must produce finite premultiplied output; custom GPU work is trusted, not isolated from the process.
- Render-group tiling uses checked size/viewport thresholds. Sampled per-group contiguous/tiled hysteresis, balanced backdrop dependency indexes, full multiwindow pressure/fairness qualification, and the complete 1080p/4K/5K benchmark matrix remain follow-up work. Full-scene async readback is available; arbitrary named-resource readback is not yet public.
- User-session VoiceOver and IME verification must be completed and recorded before beta qualification.

No unavailable API is exposed as a successful no-op. Treat issues discovered during preview as tracked limitations, not blanket cross-platform support.

Window configuration coverage, ignored-feature behavior and remaining manual qualification are documented in [Windows verification](Verification/Windows.md).

Text-field behavior, native service coverage, captures, and pending interoperability checks are recorded in [Text-field verification](Verification/TextFields.md).

Hybrid rendering evidence, benchmark commands, and remaining qualification are recorded in [Metal verification](Verification/Metal.md).

The Swift backend’s coordinate-input regression and remaining qualification limits are recorded in [Metal verification](Verification/Metal.md).
