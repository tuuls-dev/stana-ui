# Developer Experience Design

## Audience and problem definition

Primary audience: Swift developers building desktop tools, settings applications, and editable data interfaces. Assume language familiarity, not renderer, IME, accessibility-provider, or dependency-graph expertise.

The product must make a retained mental model understandable without disguising it as SwiftUI-style reevaluation. A shorter API that silently captures the wrong state is not an ergonomic success.

## Developer journeys and hypotheses

| Journey              | Hypothesis                                                                        | Evidence required                                                   |
| -------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| First application    | One import and a copyable complete entry point avoid host setup friction          | Build/run Calculator as an external package                         |
| Bind state           | Generic constant/signal/computed inputs and explicit `.binding` reveal intent     | Positive inference fixtures; explain captured `.value`              |
| Reuse a component    | Ordinary Swift properties and scoped context are sufficient                       | Compile a reusable labelled field without engine imports            |
| Edit a collection    | Observable row identity prevents accidental editor resets                         | Reorder during composition; inspect same editor/undo state          |
| Add desktop behavior | Portable commands and dialogs remove routine native escape hatches                | Calculator saves history through a system dialog using only `Stana` |
| Debug a mistake      | Inspectable IDs, metrics, semantic state, and typed errors make ownership visible | Walk through all four tasks below                                   |

## Design decisions

- Preserve properties-first construction and mount-once composition.
- Share layout, text, appearance, interaction, accessibility, and lifecycle capability groups; preserve component-specific defaults and reject meaningless groups at compile time.
- Keep read-only reactive values distinct from writable bindings.
- Use nested boxes for order-sensitive styling; argument order is not a modifier pipeline.
- Prefer composition over custom leaf/layout APIs until external examples establish a real need.
- Keep the default path free of explicit node IDs, schedulers, native handles, and graphics resources.

## Prototype and evaluate

Use [the walkthrough](../Verification/DeveloperWalkthrough.md) before stabilizing API changes. Record unaided/assisted outcomes, incorrect predictions, errors, documentation use, and workarounds—not just whether a final sample compiles.

An internal walkthrough is an engineering check, not a user study. Recruitment and participant evaluation have not been performed. Do not claim measured usability superiority or exceptional usability from fixture compilation alone.

## Acceptance rubric

1. **Discoverable:** documented names match completion-visible types and shared capabilities.
2. **Consistent:** constants, signals, computeds, and bindings work in documented combinations.
3. **Predictable:** developers can distinguish updates, moves, hiding, disposal, and remounting.
4. **Composable:** a library author uses the same public API as an application.
5. **Diagnosable:** failure identifies the category; diagnostics do not expose model/secure text.
6. **Progressive:** simple tasks avoid engine configuration; advanced controls remain explicit.

## Internal validation completed

These are implementation checks, not participant-study findings:

- Counter, Preferences, and Editable Collection build as separate packages with one framework import.
- A reusable field compiles without internal node/layout/native APIs.
- Public fixtures exercise simultaneous reactive properties and reject meaningless fields, read-only editor values, and positional content.
- Lifetime registration statements work naturally inside `makeContent`; the builder accepts their `Void` results without extra wrapper components.
- Editable-row tests preserve focus, marked text, undo, and identity during sibling writes and reorders.
- A controlled non-cooperative task cannot publish after removal; explicit replacement tokens invalidate older requests.
- Native window captures verify actual custom-drawn output, not only authoring syntax.

The consumer example is now `Examples/Calculator`. Counter, Preferences, and Editable Collection were removed after the checks above. This section does not record a new walkthrough of Calculator.

Open research work remains: observe unfamiliar developers performing the walkthrough, record mistaken predictions and assistance, and refine the API from those findings before stabilization.
