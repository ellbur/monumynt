# Transformation Levels

This document explores a structural question that arose while designing
the "generalize" / link primitive (see `iteration-with-state-design.md`):
when a construction step is best understood as a *transformation on the
program* rather than as a *node added to the program*, how is it
represented? The answer generalises into a small theory of multi-level
structure with an infinite tower of levels that is kept finite by
degeneracy.

---

## Two levels: transformation and result

A construction step can be viewed at two levels:

- **Transformation level** — the operation, a verb. "Apply `+` to these
  two outputs." "Make this step into a loop." It has a target and
  arguments; it is the edit itself.
- **Result level** — the wires and nodes the operation lays down. The
  `App` node and its two operand wires. The iteration-variable plumbing
  the modified flow now carries.

These are two views of one construction step: the edit, and what the
edit produced. The relationship is the one between a macro and its
expansion — you can look at `loopify(node)` as the call (transformation)
or as the nodes it expands to (result), and which one a tool shows is a
presentation choice, not a fact about the program.

Naming these two levels resolves a confusion that recurred while
designing the link. The question "does the link have a node?" was
spanning both levels at once. At the transformation level the link is an
operation, never a node — it is a verb. At the result level it expands
to structure (a flow's iteration-variable record, some rewiring) but
adds no *value-producing* node, because the previous-value reuses an
existing node. "The link has no node" is true at *both* levels — but for
two different reasons, and the confusion was failing to say which.

---

## The two levels were always there

Every construction step has both levels. Building `0 + element` is, as a
transformation, "apply `+` to these two outputs"; as a result, an `App`
node with two wires. The gap normally goes unnoticed because ordinary
builds are **1:1** — one operation, one node. The transformation reading
is forced by the result reading and carries no extra information.

The link is the first operation that is **1:many** — one operation, a
multi-element expansion. That 1:many-ness is the entire reason the link
*felt* like it did not fit the node model. It is not a different kind of
thing; it is the language's first **non-primitive** operation. A macro,
not a special form.

This gives a home to the "building blocks at the programmer's
abstraction level" principle (see the philosophy section of
`iteration-with-state-design.md` and `CLAUDE.md`). The language is
explicitly *not* minimal-Lisp; programmer-level vocabulary should be
available as building blocks. The two-level view is where that lives:
programmer vocabulary (`loopify`, and later `sum`, `max`, …) are
**transformation-level** operations that elaborate down to a smaller set
of **result-level** primitive nodes. Example-first authoring happens at
the transformation layer; compilation consumes the result layer. The
link will not be the last such operation — it is the first member of a
layer.

A useful corollary: *concreteness is a result-level question.* At the
transformation level "loopify this node over this flow" is fully
specified even while its result-level expansion is still being designed.
The two levels let design proceed on one while the other is open.

---

## The tower is infinite

The "level" of an operation is not a number it *has*; it is a range.
`+` is genuinely a level-0 thing (a node), but it *also* reads as a
level-1 transformation (pre-`+` program → post-`+` program), and as a
level-2 transformation (it transforms the construction history that
produced the pre-`+` program), and so on upward. Every operation spans
`[k, ∞)`.

If each level were stored independently, the program structure would be
infinite: every node would carry its reading at every higher level. That
is unacceptable as a representation.

---

## Degeneracy makes it finite

The fix: store each operation **only at its native level** k — the
lowest level at which it says something new — and treat its action at
`k+1, k+2, …` as **degenerate**: derived by a canonical lift, never
stored.

- `+`'s native level is 0. Its level-1 reading (the transformation "add
  a `+` node") is forced by its level-0 datum, not separate data. Its
  level-2 reading is the degeneracy of that, and so on.
- `loopify`'s native level is 1. It has no level-0 reading — there is no
  single node that *is* the loopify. Its level-2 reading is its own
  degeneracy.

So every stored structure represents operations at levels k, k+1, …,
where everything above k is degenerate and recoverable from the level-k
datum. The representation stores only the non-degenerate core.

### The precedent

This is the standard shape for taming exactly this kind of infinite
tower. Degenerate simplices in a simplicial set are the precedent: an
n-simplex may be *degenerate* (a degeneracy map applied to an
(n−1)-simplex), in which case it carries no new information. The
**non-degenerate** simplices are the real data; the degenerate ones are
forced by lower-dimensional data. Here the analogue is: each operation
is stored at its native level (non-degenerate), and at every higher
level it appears as its own degeneracy.

To make this concrete the representation needs:

- each operation to declare its **native level**, and
- one canonical **lift (degeneracy)** map that produces the level-(k+1)
  reading from the level-k datum.

### The assumption to check

The scheme "store once at native level k, derive everything above" rests
on an assumption: **nothing is genuinely non-degenerate at two different
levels.** If some operation really *acts* at both level 1 and level 2
with independent content — content at level 2 that is not forced by its
level-1 datum — then "store once at native k" loses information and the
scheme breaks. This is believed to hold for the operations under
consideration but has not been proven; it is the property to verify
before relying on the tower.

---

## Relationship to latent flows

`iteration-with-state-design.md` works out a *second* approach to the
same situation: rather than treating `loopify` as a level-1
transformation, it makes generalization a level-0 construction by
enriching the wire model — every value wire carries an implicit place to
cut it (a latent "generalize this" capability), normally dangling.
Tapping it is ordinary level-0 node construction, not a meta-operation,
so no tower is needed for that case.

These two approaches are the **same move** applied to different
material:

- **Levels (this doc):** posit an infinite tower of levels, store only
  the non-degenerate core, let everything above be degenerate.
- **Latent flows (the iteration doc):** posit a flow on every wire,
  store only the tapped ones, let the rest dangle.

A dangling latent flow *is* a degenerate higher-level operation. The
latent-flow approach is the levels principle applied to flows-on-wires
instead of operations-on-operations — and because the enrichment happens
to be a flow (a level-0 concept the language already has), it buys a
collapse to level 0 for free, where the general tower would not.

So the two are somewhat alternatives:

- The levels approach **keeps** the transformation layer and makes it
  finite. It is the general mechanism, covering operations that genuinely
  cannot be pushed down to a port.
- The latent-flow approach **dissolves** the transformation layer into
  the value layer for anything expressible as "tap a latent flow." It is
  cheaper and more in-vocabulary *when it applies*.

The current bet (see the iteration doc) is that generalization
specifically can be handled by latent flows and so does not need the
tower. The tower is retained here as the fallback model for future
operations that cannot be expressed as a port tap — and as the conceptual
frame that explains *why* the latent-flow trick works.

---

## One language, homogeneous levels

The levels are not separate systems. It is **one language**, in which
every operation carries a level and may operate on the structure of the
level below it. A `+` is a level-0 operation over values; a conversion is
a level-1 operation over level-0 programs; and both are authored the same
way, with the same construction vocabulary. The "values" a level-(k+1)
computation manipulates are level-k programs.

This is the reflective-tower stance rather than a two-tier macro system.
Metaprogramming is not a bolt-on with its own syntax; it is the same
language, one level up, with programs as its data.

---

## Conversions are level-1 computations

The concrete inhabitant that motivated all of this is the **conversion**
between two representations of the same computation. In
`iteration-with-state-design.md`, a `sum` (a reduce-close) and its
running-iteration form (an augment-loop) are two distinct level-0
programs that compute the same value. A conversion relates them.

A conversion is **not** a witness that holds both forms in sync. It is a
**directional level-1 computation**: it takes one level-0 program and,
run, produces the other. "It works both ways" means there are two such
computations (or one runnable in either direction), each run on demand —
not a synchronized pair. This is the transformation/result distinction
recursed:

- Running a **level-0** computation produces a **value**.
- Running a **level-1** computation produces a **level-0 program**.

"Run" lowers by exactly one level.

### The first irreducible level-1 resident

`loopify` was pushed down to level 0 (latent flows) because "generalize"
had a value-level realization. A conversion has **none**: at the value
level its two sides compute the *same* value, so its value-level shadow
is the identity — there is nothing there to push down to. Its whole
content is "these two structurally distinct level-0 programs are
value-equal," which is a statement *about* level-0 programs, hence
irreducibly level 1.

So where `loopify` vacated level 1, the conversion inhabits it. This is
the first thing that makes the tower **load-bearing** rather than purely
explanatory (answering the corresponding "what is unresolved" item).

### Degeneracy check

The conversion is consistent with the tower: native level 1 (its real
content), a degenerate lift upward (level 2 and above add nothing), and —
surfaced by this example — a *downward forgetful projection* to
identity-on-values at level 0. Two directions off the native level: the
upward degeneracy the tower already described, and a downward projection
that forgets the form distinction.

---

## The level-0 result is a derived view, not an action

Running a level-1 computation is **not** a user-invoked operation that
produces and inserts a new program. The program (with its level-1 steps)
is the thing of record; the level-0 result is its **denotation** — what
you get by running the level-≥1 steps — and it is **always there**, a
pure function of the program, lazily materialized by the IDE only for the
parts inspected. Inspecting it is a read; it mutates nothing.

The mental model is a spreadsheet: formulas are the program, displayed
values are the level-0 result — always consistent, recomputed on demand,
never edited directly.

Consequences:

- **No staleness, no run-history, no invalidation.** There is no stored
  result to go stale; there is the program and its re-derived meaning.
- **The program of record is the most abstract form.** You edit the
  intent-bearing description; the expanded form is downstream and
  read-only. Intent is therefore *never lost* — the high-level step
  always remains the source of truth, and the concrete form is a lens.
- **The compiler is just another consumer** of the derived view: it
  inspects the fully-lowered level-0 result and emits JS. IDE inspection
  and compilation see the same denotation.
- **It recurses.** A level-2 step's result is a level-1 program, itself an
  always-available view whose own level-0 result is available. One lens
  per level, each a lazy function of the level above.
- **Laziness is cross-cutting.** The runtime is already lazy (the whole
  compile architecture); the meta-level derived views are lazy for the
  same reason — a level-0 view can be large or infinite, so only the
  inspected part is materialized.

---

## Building on a derived view: wires may reference derived ports

If the level-0 result is read-only, how do you *build on* it — e.g. add a
second accumulator to a `sum` while keeping `sum` as intent? Not by
editing the derived view and not by a "lowering edit." The single
primitive needed is: **a wire may reference an output port of a derived
result.**

Then adding a second accumulator is building a *new* program-of-record
step (another augment) whose `src` references the derived combined flow
of `sum`. `sum` stays a pristine reduce-close; nothing about it is
touched or lowered. The derived view gains a second consumer (program
wires) alongside the human inspecting it and the compiler lowering it —
all three **read** the same deterministic derivation; none writes it.
Read-only, but *addressable*.

This dissolves an asymmetry that first looked like a problem. Derivation
runs **downward** (abstract program → concrete view) and is total and
automatic. The upward direction (recovering `sum` from a hand-built loop)
is the partial recognition/collapse. Referencing a derived port lets you
build in the concrete form *without* going upward at all: you keep the
abstract source of truth and attach new structure to its derivation.

Two details this raises:

- **Which ports are referenceable.** A derivation exposes a defined set of
  **principal output ports** (e.g. the combined list-with-state flow) —
  the same discipline as a normal node exposing outputs and not internal
  bindings. Reaching arbitrary derivation *internals* would couple the
  program to a lowering strategy that may change.
- **Representation.** A wire *target* that names a port *through* a step's
  derivation — a cross-level reference. It resolves against the
  derivation's **shape**, which is always available even under lazy value
  evaluation (what ports exist is structural; only their values force
  lazily).

---

## What this says about the language's philosophy

The recent work sharpens and extends the four principles in `CLAUDE.md`.

**Abstraction is the source of truth; concreteness is a derived view.**
This is the load-bearing new principle. The authored program keeps the
highest-level description; every more-concrete form is a read-only
derivation, always available for inspection and reference but never the
thing you edit. This is what makes "building blocks at the programmer's
abstraction level" *durable*: the abstraction is not compiled away in the
program you hold — it stays as the record, and the low-level form is a
lens. `sum` remains `sum` no matter how much you build on its iteration.

**Many authoring paths, few readings.** "One obvious way to express a
program" is really about the result-level *reading*, not the authoring
path. Multiple natural gestures may converge to one result (the augment
loop, built loop-first or value-first), while genuinely different intents
get genuinely different constructs (reduce-close vs augment). So
discoverability (many ways to write, meeting the user wherever they
start) and readability (few ways to read) are not in tension — they live
at different layers.

**Derivation is free and downward; abstraction is earned and upward.**
The language makes dropping to a more concrete form total and automatic,
so a high-level block never traps you — you can always inspect and build
on its expansion. Recovering abstraction from a concrete form is
recognition, and partial. This asymmetry is deliberate: it is the
principled escape hatch that lets the language commit to high-level
building blocks without giving up low-level control.

**Metaprogramming is the same language, one level up.** Rather than a
separate macro system, the language is a homogeneous tower — operations
carry levels, programs are the data of the level above, and the tower is
kept finite by degeneracy. This keeps the "one language, read it
directly" property intact even for the operations that build programs.

**Nothing hidden in a scope; the derivation is inspectable structure.**
The derived level-0 result is not a hidden expansion happening behind a
macro boundary — it is right there, always, as inspectable structure.
This is the "inside-out / cases as values" principle applied to
metaprogramming: the meaning of a higher-level step is a value you look
at, not an opaque scope you cannot see into.

---

## What is unresolved

- **Is the tower load-bearing?** Partially answered: conversions are an
  irreducible level-1 resident, so the tower is load-bearing at least for
  them. What remains is how *many* such residents there are versus how
  much collapses to level 0 via enrichments like latent flows.
- **The single-native-level assumption** stated above.
- **The concrete lift map** and per-operation native-level annotation, if
  the tower is represented directly.
- **Which derived ports a derivation exposes.** The principle is
  "principal output ports, not internals," but the exact set for each
  kind of derived result (e.g. an augment loop) needs pinning.
- **The concrete form of a cross-level (derived-port) wire reference** in
  the representation — how a wire names a port *through* a step's
  derivation, and how the derivation's shape is computed for resolution.
- **How a conversion is authored.** Since it is a level-1 computation in
  the same language, it should be built with the same vocabulary — but
  what its inputs/outputs (level-0 programs as values) look like
  concretely is not yet designed.
