# VoiceOver Manual Protocol

Record OS, VoiceOver version, input language, app commit, settings, and pass/fail observations. Do not infer results from automated semantic snapshots.

1. Start Counter with VoiceOver initially off, then activate VoiceOver. Discover the heading, count, and button in logical order.
2. Activate Increment using pointer, keyboard, and VoiceOver separately. Each activation increments exactly once; label updates preserve context.
3. Open Preferences. Read names/roles/states; type/select/edit the display name and query caret/selection. Exercise character/word navigation and undo.
4. Toggle Notifications; inspect disabled/focus/hidden state fixtures. Open/cancel a system panel and confirm focus restoration.
5. Open Editable Collection. Edit a row, reverse order, remove focused rows, and verify meaningful focus repair without duplicate semantic controls.
6. Resize, scroll, move between displays/scales, enable high contrast, and test hot AT activation after updates.
7. In a secure-field fixture, verify password semantics, no accessible value disclosure, and suppressed copy by default.

Save observed results, barriers, and workarounds. Automated tests are interoperability aids, not usability evidence.
