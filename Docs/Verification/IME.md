# IME Manual Protocol

Run `Examples/Calculator` and edit the expression field. Record OS, keyboard/IME version, language, exact sequence, and results. This protocol has not been run against the current example.

- Latin dead keys and decomposed accents; emoji family/skin-tone sequences.
- Arabic/Hebrew mixed with digits; Indic conjuncts; selection across bidirectional runs and ligatures.
- Japanese conversion, Chinese Pinyin candidates, Korean composition, candidate-window positioning after scrolling or resize.
- Marked text does not update the committed binding; commit updates once; undo removes one composition group.
- An equal external binding echo preserves composition. A different external write cancels composition before replacing committed text.
- While composing, toggle Degrees. The field's composition stays intact until commit or an external replacement.
- Transfer focus, deactivate or close the window, and reopen. No late edit reaches a disposed editor.
- Copy and paste round-trip through Edit → Paste Expression and through the system paste into the field.

The current example has no secure field and no editable collection. Those scenarios still need a separate fixture. Matching-version Unicode conformance and broad language qualification are separate work. A passing automated preedit fixture does not qualify an actual OS input method.
