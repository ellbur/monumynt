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

(Homogeneous does not mean user-authored: see "No user macros: level 1
is a built-in catalog" below for who gets to write level-1 operations.)

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

## No user macros: level 1 is a built-in catalog

A boundary decision that resolves "how a conversion is authored":
**users do not write level-1 operations.** Even in the languages that
make macro writing easiest, it is still hard — the author must reason
about programs-as-data, hygiene, and all the shapes their pattern might
meet. That difficulty is not an implementation accident to be designed
away; it is intrinsic to operating on programs. The language therefore
does not offer a user-facing macro surface.

But some features of the language *must* live at level 1 anyway,
because of what they do: they operate on the program, not on its
runtime values. A conversion between a reduce-close and its
running-iteration form has no value-level content at all (its
value-level shadow is the identity); there is nowhere below level 1 to
put it. These features form a **built-in catalog** of level-1
operations, shipped with the language like the level-0 node species
are.

The "one language, homogeneous levels" stance above is retained, but
re-aimed: it is the *account of what catalog operations are* (level-1
computations in the same language, with level-0 programs as their
values) and the eventual substrate the implementors would write them
in — not a user authoring surface. A user meets level 1 only by
*invoking* catalog entries, never by defining them. If user-defined
transformations ever become worth their cost, the catalog is the
shape they would slot into; nothing forecloses it, and nothing waits
on it.

The admission test for the catalog is exactly the level test: an
operation belongs at level 1 iff its content is a statement about
level-0 programs rather than about values. Current and expected
residents:

- **`expand`** — reduce-close → its augment-loop form (the worked
  conversion below). More generally, one entry per abstract node
  species with a defined lowering.
- **`recognize`** — the partial upward direction: a hand-built augment
  loop whose step matches a known monoid collapses to a reduce-close.
- **`generalize` (the link)** — *if* represented at the transformation
  level. Under the latent-flow bet it is level-0 construction and
  leaves the catalog; the entry is noted here because the port-form
  candidate (see `iteration-with-state-design.md`) would place it
  here.
- Future form conversions as they arise — any pair of level-0 forms
  the language treats as the same computation differently arranged.

---

## Anatomy of a level-1 operation

Making the catalog concrete: every entry is specified by three parts.

- **Pattern** — the level-0 shape the operation applies to. For
  `expand` on sums: a reduce-close node (any reduce-close; the pattern
  is the species). For `recognize`: an augment loop whose seed is a
  known operator identity and whose step is that operator applied to
  (state, element) — a genuinely partial pattern, most loops don't
  match.
- **Expansion** — the level-0 structure produced. For `expand` on a
  reduce-close over `+`: the uncollect `U` with `seed = 0` and
  `src =` the input list flow, the step `U.state + U.element` fed
  back, and the exposing collect that reads the final accumulator out.
- **Port correspondence** — a map pairing the input form's ports with
  the output form's ports. For `expand`: the reduce-close's value
  output ↔ the exposing collect's output; the reduce-close's source
  flow input ↔ `U`'s `src` input.

The port correspondence is the load-bearing part, for two reasons.

First, it is what makes invoking the operation an **edit** rather
than a construction: the form being replaced has consumers, and the
correspondence says where each consumer's wire re-attaches. Without
it, a conversion would strand every downstream wire.

Second, it is the no-bottleneck principle lifted one level. A level-0
barrier (join, race) passes value wires through as themselves, with
pairwise-corresponding inputs and outputs. A level-1 operation does
the same to *program ports*: nothing is packed into an opaque blob on
one side and unpacked on the other; each port of the old form survives
as an identified port of the new form. For **conversions**
specifically the correspondence carries the semantic guarantee — each
corresponding pair computes the same value. That per-port
value-equality *is* the conversion's content (the thing that made it
irreducibly level 1), now stated as a checkable discipline rather
than a slogan.

Principal derived ports fall out of the same structure: the ports a
derivation exposes for cross-level reference (previous section) are
declared per catalog entry, alongside the expansion. For `expand` on a
reduce-close these are the combined list-with-state flow and the final
value — not the derivation's internal bindings. "Which ports are
referenceable" is thus not a global policy question; it is a field in
each catalog entry.

---

## Two invocation modes: lens and splice

The catalog says what a level-1 operation *is*. This section says what
invoking one *does* — and resolves a tension that has been implicit
since "the level-0 result is a derived view."

The tension: the derived view is read-only, and that is what keeps
`sum` durable while you build on it. But the motivating scenario for
conversions is wanting to **tweak** the expanded form — convert the
reduction to a general iteration precisely in order to change the
step into something that is no longer a sum. A read-only view cannot
support that, and recording the tweak as a patch *on top of* `sum`
would make the program of record claim a sum-ness that is false.

The resolution: one level-1 computation, **two dispositions of its
output**.

- **Lens mode** — automatic, always-on, read-only. This is the derived
  view of the earlier sections. Every abstract node has its expansion
  available as a lens at all times; nothing is invoked, nothing is
  stored, and the program of record keeps the abstract node. Used to
  **inspect** and to **build on** (derived-port references). `sum`
  stays `sum`.
- **Splice mode** — deliberate, one-shot. The operation runs as an
  edit: its expansion is materialized into the program of record,
  replacing the matched form, with consumers rewired along the port
  correspondence. The abstract node is gone from the record. Used to
  **tweak the interior**.

Losing the abstract node under splice is not a defect to be repaired;
it is the honest outcome. The edits that motivated the splice are
about to falsify the abstraction — a sum whose step you change to
`state * 0.9 + element` is not a sum, and a record that said
"sum, plus this patch" would be fake abstraction: the reader would
have to mentally execute the patch to know what the program does,
which is exactly the intent-decoding the one-obvious-reading principle
forbids. The principle "abstraction is the source of truth" is
sharpened, not violated: **the source of truth is the highest-level
description that is still true.** Splice is the sanctioned descent for
when the current abstraction is about to stop being true.

The two modes are connected by a copy-on-write rule: **reads are free
through the lens; a write into a lens view forces a splice.** The IDE
gesture "edit this thing inside the expansion of `sum`" is well-formed
— it means "splice, then apply the edit to the now-materialized
form." Whether that escalation is silent or confirmed is an editor
question, but its semantics are fixed: after the gesture, the record
holds the expansion, not the abstract node.

Asymmetries between the modes, by direction:

- Downward operations (`expand`) have **both** modes: the lens is
  their always-on form, the splice their edit form. They are total on
  their pattern.
- Upward operations (`recognize`) are **splice-only**. Recognition is
  partial, so there is no always-on upward lens; and its entire point
  is to change the record (earn the abstraction). Whether the IDE
  *offers* recognition eagerly — "this loop is a sum, collapse it?" —
  is an ergonomics question left open below.

A splice may leave an inert **provenance note** ("this loop was
spliced from a `sum` here") — pure annotation, no semantic weight,
never consulted by derivation or compile. Whether it is worth having
is left open below; the design must not lean on it.

---

## Worked example: tweaking a sum

The motivating scenario, end to end, in the concrete vocabulary of
`iteration-with-state-design.md`.

Starting program of record:

```
nLst: list
nSum: reduce-close(+) over nLst's flow      -- abstract; monoid (+, 0)
nUse: f(nSum)
```

**Case A — build alongside (lens suffices).** Add a lockstep `max`.
No conversion is invoked. `nSum`'s lens (the augment-loop expansion)
exposes its combined list-with-state flow as a principal derived
port; a *new* augment is built whose `src` references that port and
carries the `max` state. The record now holds `nSum` (still a
pristine reduce-close) plus the new augment with a cross-level `src`
wire. This is the second-accumulator story from the iteration doc,
unchanged.

**Case B — tweak the interior (splice required).** Make the sum decay:
each iteration should compute `state * 0.9 + element`, which is no
monoid — this cannot remain a reduce-close. Invoke `expand` on `nSum`
in splice mode. The record becomes:

```
nLst:  list
U:     uncollect  inputs  seed = 0, src = nLst's flow
                  outputs state, element
nStep: U.state + U.element                  -- feedback advances U.state
nOut:  collect exposing the final accumulator
nUse:  f(nOut)                              -- rewired by port correspondence
```

`nUse` moved from `nSum`'s value output to `nOut` automatically —
that is the port correspondence doing its job. Now the tweak is
ordinary level-0 editing: change `nStep` to
`U.state * 0.9 + U.element`. The record reads as what it is — a
decaying accumulation loop — with no false `sum` claim anywhere.

The two cases give the practical rule of thumb: **reference the lens
to add; splice to change.** If Case B's author later regrets the
descent and reshapes the loop back into a genuine monoid fold,
`recognize` is the earned way back up.

---

## Representation: the tower is machinery, not storage

An earlier section says "the program (with its level-1 steps) is the
thing of record." The lens/splice split sharpens this into something
almost anticlimactic, and that is its virtue: **the stored program
remains level-0 syntax throughout.**

- A **lens** never stores anything: it is implied by the node species.
  A reduce-close node *is* the level-1 step whose expansion is its
  lens — the abstract node and "the step that produces the concrete
  form" are one stored datum, read at two levels. This is degeneracy
  cashing out in the representation: the node is stored once, at its
  native reading, and its transformation-level reading is derived.
- A **splice** never stores anything either: it is an edit, living in
  edit history like any other edit, its output ordinary level-0
  structure.

So the tower is inhabited — the catalog operations are real, run, and
have irreducibly level-1 content — but it is inhabited by
**machinery** (derivation and edit-time computation), not by stored
strata. The only representational additions the whole design needs:

- **Abstract node species** (reduce-close today; each future entry as
  it arrives) in the level-0 syntax, each with a catalog entry giving
  pattern / expansion / port correspondence / principal ports.
- **Cross-level wire references**: a wire target of the form
  `DerivedPort(nodeId, portName)` — "the port named `portName` in the
  expansion of node `nodeId`." Resolution computes the expansion's
  *shape* (which ports exist), which is structural and cheap; values
  force lazily as ever. `portName` draws from the catalog entry's
  declared principal ports, so a reference can never reach a
  derivation internal — ill-formed references are unrepresentable
  rather than checked.
- **Splice as a pure function** `program → program` over the existing
  structures, per catalog entry. Nothing new in the syntax.

Level 2 and above remain concretely uninhabited. The candidates that
come to mind — composing two conversions, applying a conversion at
every matching site — are on inspection still level 1 (a bigger
pattern or a derived catalog entry, but content about level-0
programs either way). Degeneracy means the empty upper tower costs
nothing to keep, and the single-native-level assumption survives the
whole catalog so far: no entry has independent content at two levels.

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

Resolved since first drafted (see the sections above):

- ~~**How a conversion is authored.**~~ Resolved by the catalog
  decision: users never author level-1 operations; they invoke
  built-in catalog entries. The same-language-one-level-up story is
  the account of what entries *are* and the implementors' eventual
  substrate, not a user surface.
- ~~**The concrete form of a cross-level wire reference.**~~
  `DerivedPort(nodeId, portName)`, resolving against the expansion's
  shape, with `portName` drawn from the catalog entry's declared
  principal ports. Remaining detail: whether `portName` ever needs to
  be a *path* (a port of a node nested inside the expansion of a node
  inside the expansion…) or whether one level of naming always
  suffices because expansions recurse through their own principal
  ports.
- ~~**The concrete lift map, if the tower is represented directly.**~~
  Dissolved rather than solved: the tower is not represented directly.
  Stored programs stay level-0; lenses are implied by node species and
  splices are edits. No stored lift map is needed.
- **Which derived ports a derivation exposes** — reduced from a policy
  question to a per-entry field. Still to pin: the actual port list for
  each entry as it is implemented (for `expand` on reduce-close: the
  combined list-with-state flow and the final value).

Still open:

- **Is the tower load-bearing?** Partially answered: conversions are an
  irreducible level-1 resident, so the tower is load-bearing at least
  for them. What remains is how *many* such residents there are versus
  how much collapses to level 0 via enrichments like latent flows.
- **The single-native-level assumption** stated above — unfalsified by
  the current catalog, unproven in general.
- **Splice escalation ergonomics.** Editing inside a lens view forces a
  splice by rule; whether the editor escalates silently or confirms
  first is undecided. (Semantics are fixed either way.)
- **Provenance notes.** Whether a splice leaves an inert "was a `sum`"
  annotation, and whether the IDE ever surfaces it. The design must not
  lean on it; the question is only whether it earns its noise.
- **Eager recognition.** Whether the IDE proactively offers `recognize`
  ("this loop is a sum — collapse it?") or waits to be asked. Eager
  offers make abstraction cheaper to earn but risk nagging on loops
  deliberately left concrete (e.g. one just spliced).
- **Rewiring existing derived-port references across a splice.** If a
  wire references a principal port of `sum`'s lens (Case A) and `sum`
  is later spliced (Case B), the port correspondence should carry the
  reference onto the materialized structure — principal ports are
  exactly the ports the correspondence tracks — but this interaction
  has not been worked in detail.
