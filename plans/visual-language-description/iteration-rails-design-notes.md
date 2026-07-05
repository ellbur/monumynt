# Iteration Rails: Design Notes

## Background and Problem

The visual flow language uses a 2D spread model for list iteration: horizontal position represents position in the iteration, vertical position represents computational steps. To carry a value from one iteration to the next, the original design used a **diagonal wire** — a line from a value at position *i*, step *n* down to a tap at position *i+1*, step *n+1*. This is the "iteration rail."

Two problems with the diagonal rail motivated this redesign:

1. **Legibility.** A diagonal introduces a third semantic axis on top of the existing two (horizontal = position, vertical = computation). The reader has to mentally translate the diagonal as "same logical value, one iteration later" — a meaning that nothing else in the language uses. The picture in the original document is hard to parse even for a single carried value.

2. **Rigidity.** Only the simplest case — single-step `prev` — renders cleanly. Two carried values produce crossing diagonals. Lookback by more than one iteration produces steeper or stacked diagonals. Conditional updates have no natural diagonal form. Anything beyond the trivial case is a mess.

A deeper diagnosis: the diagonal was conflating two distinct things — *how a value is physically carried between iterations* and *how the user names a previous value*. These don't need to share a mechanism.

## Constraints That Shaped the Design

Several constraints emerged during the design conversation, in order of importance:

### Stay visual

The language is visual; carrying state across iterations should be too. An "elegant" mechanism that requires the reader to mentally simulate hidden semantics — for example, a generic register with read/write ports — fails this test. Two registers next to each other look identical regardless of what they hold; meaning lives entirely in what's wired to them. That collapses into the imperative paradigm wearing visual clothing, which is precisely what the language is trying to avoid.

The picture has to *show* what's being carried, not just provide a slot for it.

### Don't introduce semantic dimensions you can't sustain

The 2D model already uses horizontal and vertical for clear, distinct things. A diagonal is a third axis with its own meaning, and that meaning ("one iteration later") only renders cleanly for the trivial case. Adding load-bearing semantic axes that degenerate under generalization is the failure mode to avoid.

### The user only sees one iteration

This is the most important constraint and the one that changed the picture most. When a spread is opened, the diagram shows **one column** — the generic iteration. The wire labeled `elem` is "the element at the current position," not element 0 or element 5. There is no row of real columns at design time, because the data isn't known when the program is being written.

This rules out drawing the rail as something that visibly spans multiple known positions. The horizontal extent of any cross-iteration construct must be schematic — it can only represent the *idea* of adjacent iterations, not concrete instances.

### Limit ambition to keep the picture stable

The original rail tried to be everything: loop variable, arbitrary cross-iteration reference, scan accumulator, sliding state. Trying to generalize is what made it tangle. Restricting the rail's job tightly keeps its visual shape predictable, at the cost of needing other constructs for the patterns it no longer covers.

## The Rail as Currently Designed

The rail is now restricted to a single, narrow purpose: **the visual depiction of a loop-carried variable.** It compiles directly to a single mutable register in the generated loop. No dependency analysis, no soundness check, no lazy fallback.

### What the rail supports

- **Single-step `prev`.** The value of the carried variable from the immediately previous iteration.
- **Single carried value per rail.** Multiple loop variables = multiple parallel rails.
- **An explicit initial value**, connected to the rail by a dotted line.

### What the rail explicitly does not support

- **`prev(prev(...))`** — multi-step lookback. If you want it, draw two rails, one feeding the other. This forces the chain of carried values to be visually explicit, which is correct.
- **`next`** — forward reference. Not expressible as a loop variable.
- **Cross-iteration references to arbitrary computed values.** The rail is for state, not for arbitrary peeking.

These omissions are intentional. They keep the rail's visual shape stable: enter from the left, get tapped, get written back, exit to the right.

### Visual shape

The user only sees the single generic iteration column. The rail enters from off-screen-left, crosses the column, and exits to off-screen-right. No ghost columns or schematic neighborhoods are needed, because the rail only reaches into abstract previous/next space — it never visualizes another iteration.

Within the column, the rail makes two connections:

- **Read (tap down):** On the left side of the column, the rail's value is tapped into a wire that feeds a node in the iteration body. This is `prev`.
- **Write (writeback up):** On the right side of the column, the result of the iteration's computation is wired back up onto the rail. This becomes the next iteration's `prev`.

```
       ┌─────┐
       │  0  │   initial value
       └──┬──┘
          ┊
          ┊       (dotted: structural connection,
          ┊        not per-iteration data flow)
          ┊
   ═══════•══════════════════════════•══════════
          │ prev                     ▲
          │                          │ writeback
          │                          │
          │       ┌── elem ──────────┤
          │       │                  │
          └───────⊕──────────────────┘
                  (running sum)
```

The body of the iteration sits between the read and the writeback. The `⊕` node has two inputs (`prev` from the rail, `elem` from the column) and one output (back up to the rail). The rail's shape is fixed: one read, one write, with the body between them.

### Initial value and final value

The **initial value** sits outside the rail's loop region, connected by a dotted line. The dotted line signals that the connection is structural — it's part of how the rail is set up — rather than per-iteration data flow. Solid wires inside the column represent computation that happens every iteration; the dotted line represents one-time wiring.

The **final value** of the rail (after the last iteration) is available as a normal solid wire emerging from the right end of the rail, outside the spread region. No dotted line needed there — the connection from "rail's final value" to "value available after the loop" is itself a normal data dependency.

### Why this works

- **Direct correspondence to implementation.** The rail compiles to a single mutable register. The picture and the generated code line up exactly.
- **Visually unambiguous.** With only `prev` and only single-step lookback, there is one shape the rail can take. It can't degenerate.
- **No schematic context needed.** No ghost columns, no representational adjacent iterations. The diagram remains a single column.
- **Honest about its limits.** A user who wants two-step lookback has to draw two rails. The chain of state is visible in the picture, not hidden behind a more powerful operator.

## Convergence with the Delay Node

The non-visual design thread (`plans/iteration-with-state-design.md`) arrived at the same construct from the semantic side: the Delay node expressed as ports — an `init` input, a `prev` output port, and a `step` input port. The correspondence is exact:

- tap-down read = the `prev` output port
- writeback-up = the `step` input port
- dotted initial value = the `init` input

The rail is the Delay node's visual depiction; `visual-language-spec.md` now records Delay as the current node schema (superseding the old IterationRail / TapIn / TapOut trio). The Delay document also settles two things this one left implicit: cross-rail references (one rail's writeback computed from another rail's tap) are ordinary, well-formed wiring, and the "every cycle must pass through a Delay" productivity check is the structural rule that keeps arbitrary rail wiring sound.

## What This Leaves Uncovered

The rail now covers exactly the pattern "one loop-carried variable updated each iteration." This is a small slice of how state is actually used in iterative code. The patterns that fall outside the rail's scope include, roughly:

- **Read-only history.** Looking back at recent values without maintaining a carried variable. (The existing `window` operation partially covers this.)
- **Multi-variable loop state with cross-references.** Several rails interacting — one feeding another, or two rails referencing each other's values from the previous iteration. *(Since resolved: under the Delay port form, cross-references are ordinary wires — Fibonacci is two Delays reading each other's `prev` — and the productivity check rules out the ill-formed configurations. See `plans/iteration-with-state-design.md`.)*
- **Conditional carry.** A loop variable that updates only on some iterations and passes through unchanged on others.
- **State that doesn't fit the read-compute-write rhythm.** State machines inside loops, accumulators that reset under certain conditions, state with multiple update sites.

The right abstractions for these are not yet designed. The intended next step is **not** to invent constructs from first principles — that risks designing to the theory's existing categories rather than to what real iterative code actually looks like. Instead:

**Sample real loops randomly from real code.** Across different domains (parsing, simulation, UI handling, data pipelines, numerical routines, etc.), pull whole loops with surrounding context, don't filter for "interesting" cases, and study the shape — what state is carried, how it updates, what's read after the loop, what's set up before.

The abstractions should emerge from what's actually there, including the proportion of loops that fit the simple rail pattern cleanly. If most short loops are one-rail patterns, the rail is the right central construct and additional vocabulary handles the tail. If even most short loops break the pattern, the rail is in trouble as a foundation and that's worth knowing early.

## Summary of the Reframe

The original rail tried to be a general cross-iteration reference mechanism, encoded as a diagonal wire with implicit semantics about "value one iteration later." It was visually overloaded and broke down beyond the trivial case.

The redesigned rail is narrower in scope but stable in shape:

- **One purpose:** depict a loop-carried variable.
- **One operation:** `prev`, single-step.
- **One shape:** horizontal line crossing the iteration column, with a tap-down read on the left and a writeback-up on the right.
- **Explicit initial value** connected by a dotted line.
- **No schematic neighborhood** required, because the rail only references abstract previous/next space — it never visualizes other iterations.

Everything the old rail was overreaching for is deferred to future constructs, to be designed against real code samples rather than theoretical categories.
