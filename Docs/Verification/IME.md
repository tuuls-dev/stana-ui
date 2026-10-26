# IME Manual Protocol

Run Preferences and Editable Collection. Record OS, keyboard/IME version, language, exact sequence, and results.

- Latin dead keys and decomposed accents; emoji family/skin-tone sequences.
- Arabic/Hebrew mixed with digits; Indic conjuncts; selection across bidirectional runs and ligatures.
- Japanese conversion, Chinese Pinyin candidates, Korean composition, candidate-window positioning after scrolling/resize.
- Marked text does not update committed binding; commit updates once; undo removes one composition group.
- Equal external binding echoes preserve composition. Different external writes cancel/reset composition before replacing committed text.
- While composing in a collection row, toggle a sibling and reverse the list; editor identity/composition/selection/undo remain intact.
- Transfer focus, deactivate/close the window, remove the row, and reopen; no late edit reaches a disposed editor.
- Copy/paste round trips and secure-field text-service behavior.

Matching-version Unicode conformance and broad language qualification are separate work. A passing automated preedit fixture does not qualify an actual OS input method.
