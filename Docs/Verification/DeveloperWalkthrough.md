# Developer Walkthrough

Use a fresh consumer package and the README, not implementation imports. Record OS/toolchain, prior reactive experience, assistance, outcome, errors, and documentation used.

1. **First window:** add the dependency and build/run `Examples/Calculator`. Record setup steps and any undocumented intervention.
2. **Captured read:** replace a signal input with `.value`; predict and explain why the label freezes. Repair it using the public API.
3. **Reusable component:** create two independent counter components using `context.state(initial:)`; hide, remove, and remount one. Explain state persistence.
4. **Editable rows:** compose text, toggle a sibling, and reorder. Predict editor ID/focus/undo behavior. Contrast value-item replacement.
5. **Async work:** start two requests and complete them out of order, then remove the component. Use scope/request tokens to prevent stale publication.
6. **Desktop behavior:** connect a button and menu shortcut to one command; open/cancel a save dialog without native imports.

Capture misunderstandings and workarounds. Revise naming/defaults/docs/diagnostics together; retest affected tasks. Do not report an internal walkthrough as a participant study.
