# VoiceOver Manual Protocol

Record OS, VoiceOver version, input language, app commit, settings, and pass/fail observations. Do not infer results from automated semantic snapshots. This protocol has not been run against the current example.

1. Start `Examples/Calculator` with VoiceOver initially off, then activate VoiceOver. Discover the heading, result, expression field, toggles, keypad, and history in logical order.
2. Activate Equals using the pointer, the keyboard, and VoiceOver separately. Each activation evaluates once. The result and history update and keep their place.
3. Type and edit the expression. Query the caret and selection, then exercise character navigation and undo.
4. Toggle Degrees, Animate, and Graph. Confirm each checked state, and confirm that hiding the graph removes the plot from the accessibility tree.
5. Open the Functions sheet from the menu, read it, close it, and confirm focus returns to the calculator.
6. Resize, scroll the history, move between displays and scales, enable high contrast, and test hot activation after updates.

Secure-field and editable-collection scenarios are not part of this example. Do not mark them passed from the calculator. Save observed results, barriers, and workarounds. Automated tests are interoperability aids, not usability evidence.
