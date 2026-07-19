# Iteration Rails: Design Notes

> **Status: a kept exploration — not a settled feature.** The rail
> *mechanisms* this chapter describes are rejected: the diagonal wire,
> the TapIn/TapOut nodes, and `ById` references (the reasons are told
> below, and under Delay in `visual-language-spec.md`). The construct
> the spec now records is **Delay**. So why keep the chapter? Because
> the rail is not promising as drawn, but not fully out either, and
> three of its ideas may need resurrecting to harmonize Delay with
> state flows — the *one-visible-column* constraint, the
> *state-thread* depiction, and the split between how a value is
> *carried* and how it is *named*. Read alongside
> `iteration-with-state-design.md`, which holds the semantic form —
> one register-pair construct, proven equivalent under its two
> candidate drawings — and remains the biggest open design area. The
> open decision there is the *surface*: which drawings exist and
> which is primary. Nothing on this page is that decision's winner.

This is the visual companion to the loop-carried-state question. The
semantic work — what the construct *means* — lives in
`iteration-with-state-design.md`; this chapter asks how the same
construct should be *drawn*, and records why the obvious drawing
failed.

## A running sum

Start with the program the drawing has to depict. Suppose you want to
sum a list of numbers as you walk it: each iteration adds the current
element to a total carried over from the previous iteration. In the
textual form (`textual-representation-design.md`) that carried total
is a register:

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum
sum, a -> add -> step of sum => total    -- running sum: each step adds the element
```

Read it line by line. The list opens into a per-element flow `~L`,
with each element arriving on `a`. `delay init 0` gives you a carried
value that starts at `0`; reading `sum` gets you the value carried in
from the previous iteration. `add` combines the carried value with
the element, and `step of sum` writes the result back, so it becomes
the *next* iteration's `sum`. A value that travels from one iteration
into the next like this is **loop-carried state**, and the question
of this whole chapter is: what should that travelling look like on
the page?

## The problem: drawing a value that crosses iterations

The visual flow language uses a 2D spread for list iteration:
horizontal position is position in the iteration, vertical position
is computational step.

Now, you might wonder why the language doesn't just draw the carry as
a **diagonal wire** — from a value at position *i*, step *n*, down to
a tap at position *i+1*, step *n+1*. That was in fact the first
design; the diagonal *is* the original "iteration rail." It turns out
this drawing fails in two ways.

**Legibility.** The diagonal is a third meaning-bearing axis stacked
on the two the spread already uses (horizontal = position, vertical =
computation). The reader has to translate it as "the same logical
value, one iteration later" — a meaning nothing else in the language
carries. Even for a single carried value the picture is hard to
parse.

**Rigidity.** Only the simplest case — single-step `prev` — renders
cleanly. Two carried values give crossing diagonals. Lookback past
one iteration gives steeper or stacked diagonals. Conditional updates
have no natural diagonal form at all. Everything beyond the trivial
case tangles.

The root diagnosis: the diagonal conflated two separate things — *how
a value is physically carried between iterations* and *how the user
names a previous value*. These need not share a mechanism, and
forcing them together is what made the drawing overload. (This is a
settled rejection — the diagonal drawing, along with the TapIn/TapOut
and `ById` machinery that came with it, should not be re-proposed
without new evidence. The carry-vs-name split it exposed, though, is
one of the ideas this chapter is kept for.)

## Constraints that shaped the redesign

Four constraints, in order of weight.

**Stay visual.** Carrying state across iterations must be visible,
not a hidden meaning the reader simulates in their head. Here you
might wonder why the language doesn't just offer a generic read/write
register node — a slot you read from and write to — and call it done.
It turns out that fails this constraint: two registers side by side
look identical no matter what they hold, so meaning lives entirely in
what is wired to them. That is the imperative paradigm in visual
clothing — exactly what the language avoids. The picture must *show*
what is carried, not just offer a slot for it. (This failure is part
of the record: a bare register slot is not an acceptable drawing.)

**Do not introduce an axis of meaning you can't sustain.** The 2D
model already spends horizontal and vertical on distinct, clear
meanings. A diagonal is a third load-bearing axis that renders
cleanly only for the trivial case. An axis that degenerates under
generalization is the failure mode to avoid.

**The user only ever sees one iteration.** This is the constraint
that changed the picture most. When a spread is opened, the diagram
shows **one column** — the generic iteration. The wire labeled `elem`
means "the element at the current position," not element 0 or element
5. There is no row of concrete columns at design time, because the
data isn't known when the program is written. So a cross-iteration
construct can never *span multiple known positions*; its horizontal
extent must be schematic, standing for the *idea* of adjacent
iterations, never for concrete instances.

**Limit ambition to keep the picture stable.** The original rail
tried to be everything at once — loop variable, arbitrary
cross-iteration reference, scan accumulator, sliding state. That
reach is what made it tangle. Restricting the rail's job tightly
keeps its shape predictable, at the cost of needing other constructs
for the patterns it drops.

## The rail as redesigned

Scope is narrowed to one purpose: **depict a single loop-carried
variable.** It compiles directly to one mutable register in the
generated loop — no dependency analysis, no soundness check, no lazy
fallback.

**Supported:**

- **Single-step `prev`** — the carried value from the immediately
  previous iteration.
- **One carried value per rail.** Several loop variables = several
  parallel rails.
- **An explicit initial value**, joined to the rail by a dotted line.

**Deliberately unsupported:**

- **`prev(prev(...))` — multi-step lookback.** You might wonder why
  you can't simply ask for the value from two iterations back. You
  can get it — but you draw it as two rails, one feeding the other,
  so the chain of carried values is visually explicit rather than
  hidden inside a more powerful operator. Provisionally, in text:

  ```
  ~L ~> delay init 0 => a        -- provisional spelling
  ~L ~> delay init 0 => b
  a -> step of b                 -- b holds a's previous value: two-step lookback, made explicit
  ```

- **`next` — forward reference.** Not expressible as a loop variable.
- **Cross-iteration references to arbitrary computed values.** The
  rail is for state, not for arbitrary peeking into other iterations.

These omissions are intentional: they keep the rail's shape fixed —
enter from the left, get tapped, get written back, exit to the right.

### Visual shape

The user sees only the single generic column. The rail enters from
off-screen-left, crosses the column, and exits off-screen-right. No
ghost columns or schematic neighborhoods are needed, because the rail
reaches only into abstract previous/next space — it never draws
another iteration.

Within the column the rail makes two connections:

- **Read (tap down):** on the left of the column, the rail's value is
  tapped into a wire feeding a node in the body. This is `prev`.
- **Write (writeback up):** on the right, the body's result is wired
  back up onto the rail, becoming the next iteration's `prev`.

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

The body sits between read and writeback. The `⊕` node takes two
inputs (`prev` from the rail, `elem` from the column) and produces
one output (back up to the rail). This is the same program as the
running-sum register you met at the top of the chapter: `prev` is the
read half, the writeback is `step of sum`, the dotted `0` is `init`.

### Initial and final value

The **initial value** sits outside the loop region, joined by a
dotted line. The dotted line signals a *structural* connection — part
of how the rail is set up — as opposed to per-iteration data flow.
Solid wires inside the column are computation that runs every
iteration; the dotted line is one-time wiring. This keeps `init`
syntactically apart from per-iteration inputs, the same separation
the textual `delay init 0` makes.

The **final value** (after the last iteration) emerges as a normal
solid wire from the right end of the rail, outside the spread. No
dotted line is needed: "rail's final value → value available after
the loop" is an ordinary data dependency.

### Why this shape works

- **Direct correspondence to implementation.** The rail compiles to
  one mutable register; picture and generated code line up exactly.
- **Visually unambiguous.** With only `prev` and only single-step
  lookback, there is exactly one shape the rail can take — it cannot
  degenerate.
- **No schematic context needed.** No ghost columns, no represented
  adjacent iterations; the diagram stays a single column.
- **Honest about its limits.** Wanting two-step lookback forces two
  rails, so the chain of state is visible rather than hidden behind a
  more powerful operator.

## Convergence with the Delay node

The semantic thread (`iteration-with-state-design.md`) reached the
same construct from the other side: the **Delay** node expressed as
ports — an `init` input, a `prev` output port, a `step` input port.
The correspondence is exact:

- tap-down read = the `prev` output port
- writeback-up = the `step` input port
- dotted initial value = the `init` input

`visual-language-spec.md` records Delay as the candidate node schema,
superseding the old IterationRail / TapIn / TapOut trio. The rail is
Delay's visual depiction.

Delay is one of **two live drawings** of the semantic form. The other
is the **latent-flow representation**: an augmented uncollect — a
seed input and a state output added to the flow's opener, with a
feedback collect producing the modified flow — which realizes the
same rail picture with the read tapped off the opener's state port.
The two have since been proven result-level equivalent — one register
pair under two drawings — so the choice between them is a surface
question, not a question of meaning; see "The two candidates side by
side" and "The equivalence, worked" in the iteration-with-state
document. That choice is still open — do not read either drawing, or
this rail, as the adopted surface.

That document also settles two things this one left implicit:

- **Cross-rail references are ordinary wiring.** One rail's writeback
  computed from another rail's tap is well-formed. Fibonacci is two
  Delays reading each other's `prev`:

  ```
  steps -> open list => n, ~L
  ~L ~> delay init 1 => fa
  ~L ~> delay init 1 => fb
  fb -> step of fa => lastA
  fa, fb -> add -> step of fb => lastB    -- each register's next value from the other's prev
  ```

- **The productivity check keeps rail wiring sound.** At least in the
  port form, "every cycle must pass through a Delay" is the
  structural rule that admits arbitrary rail wiring without an
  ill-formed configuration.

A further proposal — the **visible state thread** ("A fourth option:
the visible state thread" in the iteration-with-state document) —
promotes the rail from *depiction of* the construct to the construct
*itself*: a first-class path whose geometry carries the timing, with
the Delay node as its point projection (the thread contracted to its
endpoints) and the augmented flow as its flow projection (the thread
absorbed into the opener). Under that proposal, this chapter's rail
shape — enter from initial, tap, writeback, exit as final — is the
primary surface for iteration state, and the two node-level forms are
what it degrades into for tangled cases. That proposal is not
adopted; but it is where the retained ideas above
(one-visible-column, state-thread depiction, carry-vs-name split)
would come back into force.

## What the rail leaves uncovered

The rail covers exactly "one loop-carried variable updated each
iteration" — a small slice of how state appears in real iterative
code. Outside its scope, roughly:

- **Read-only history.** Looking back at recent values without a
  carried variable. (The existing `window` operation partially covers
  this.)
- **Multi-variable loop state with cross-references.** Several
  interacting rails — one feeding another, or two referencing each
  other's previous values. *Resolved:* under the Delay port form
  these are ordinary wires (Fibonacci above), and the productivity
  check rules out the ill-formed configurations.
- **Conditional carry.** A loop variable that updates on some
  iterations and passes through unchanged on others.
- **State that doesn't fit read-compute-write.** State machines
  inside loops, accumulators that reset under conditions, state with
  multiple update sites.

The right abstractions for these are not yet designed. The intended
next step is **not** to invent constructs from first principles —
that risks designing to the theory's existing categories rather than
to what real iterative code looks like. Instead: **sample real loops
randomly from real code.** Across domains (parsing, simulation, UI
handling, data pipelines, numerics), pull whole loops with
surrounding context, don't filter for "interesting" cases, and study
the shape — what state is carried, how it updates, what's read after
the loop, what's set up before. The abstractions should emerge from
what's there, including the proportion of loops that fit the rail
cleanly. If most short loops are one-rail patterns, the rail is the
right central construct and extra vocabulary handles the tail. If
even most short loops break it, the rail is in trouble as a
foundation — worth knowing early.

### Where this shows up in real code

That survey has been run (`real-loop-survey.md`): sixty
seeded-random loops, thirty from Python/Ruby/JS infrastructure code
and thirty from domain corpora (numerics, graph algorithms,
simulation, terminal UI, game logic, 3D graphics). Headline findings:

- Half of everything needs no carried state at all.
- In infrastructure code the carried-state tail is cursors,
  worklists, a resettable buffer, and conditional carries — *not*
  one-rail scans.
- In numerics the scan is the dominant loop shape: multi-register
  recurrence kernels, cross-referencing register pairs, take-while
  termination fused to the carried state.

So the central question gets a split answer. The rail is **tail
vocabulary for everyday code and central vocabulary for numeric
code**; every register drawn in the sample is one-writeback; and the
biggest unserved demand across both corpus families is **data-driven
termination**, not carried arithmetic.

## Summary of the reframe

The original rail tried to be a general cross-iteration reference
mechanism, encoded as a diagonal wire with an implicit "one iteration
later" meaning. It was visually overloaded and broke down past the
trivial case.

The redesigned rail is narrower but stable:

- **One purpose:** depict a loop-carried variable.
- **One operation:** `prev`, single-step.
- **One shape:** a horizontal line crossing the iteration column —
  tap-down read on the left, writeback-up on the right.
- **Explicit initial value** joined by a dotted line.
- **No schematic neighborhood**, because the rail references only
  abstract previous/next space and never draws another iteration.

Everything the old rail overreached for is deferred to future
constructs, designed against real code samples rather than
theoretical categories.
