# ADR 0004: Stana-owned editing and native semantics

Accepted. Do not wrap NSTextField/NSTextView. Stana owns the editing buffer, selection, composition, edit revision, and undo history. A private NSTextInputClient bridge services native IME requests. External different binding values cancel marked text before replacement; equal echoes preserve composition.

Publish portable semantics through private native accessibility elements rather than AccessKit. Actions use the normal command dispatcher. Secure text is redacted from test snapshots and omitted from accessibility values and clipboard-copy defaults.

Automated semantic tests and native provider checks do not establish VoiceOver/IME usability. Record actual manual interoperability results and unresolved limitations before beta qualification.

Native text checking uses revision- and editor-scoped clients, not a second editable text store. Annotation snapshots are presentation-only values recorded by Stana's scene renderer. Corrections, completion, Services, and accessibility writes enter the normal validated edit path; read-only and secure policies apply there as well as in native action validation.
