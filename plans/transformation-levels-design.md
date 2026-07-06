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
- **History operations** — undo, cherry-pick/rebase. A second family,
  developed in "The edit history is the tower" below: their content
  is about histories of programs, which passes the same admission
  test.

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

First, it is what lets an invocation produce a **complete new
version** rather than a disconnected fragment: the old form has
consumers, and when the new version is built, each consumer is
rebuilt to arrive at the port the correspondence pairs with the one
it read before. (No wire is ever re-attached in place — see "Nothing
mutates" below; the correspondence tells the *rebuild* where to
point.) Without it, a conversion would strand every downstream
consumer. The same map, read in reverse, is what makes conversions
removable later (see "Removing a conversion: cherry-picking").

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

## Nothing mutates: every change builds

A frame correction that governs everything below: **there is no
editing anywhere in this design — only building.** The program is a
persistent structure in the functional-data-structure sense. A
"change" never modifies an existing node; it builds new nodes that
reuse existing parts, yielding a new program *version* that shares
all untouched structure with the previous one. Nothing is destroyed:
the previous version is simply an earlier point in the construction
history.

Concretely, a "tweak" is a path copy, exactly as in a persistent
tree: build the replacement node, rebuild the nodes on the path from
it to the version's outputs, share everything else. Upstream
structure — sources, unrelated branches — is the *same* nodes, not
copies.

This deletes a design problem an earlier draft of this section was
gearing up to solve. If derived views could be edited, an edit made
in a concrete view would need translating back through the
derivation onto the abstract form — the classic bidirectional-update
problem. There are no edits, so there is nothing to translate. What
survives is a strictly smaller *reference*-translation question,
which appears below as cherry-picking.

---

## Two invocation modes: lens and materialize

The catalog says what a level-1 operation *is*. This section says
what invoking one does: one level-1 computation, two dispositions of
its output.

- **Lens mode** — automatic, always-on, read-only. This is the
  derived view of the earlier sections. Every abstract node has its
  expansion available as a lens at all times; nothing is invoked,
  nothing enters the history, and the current version keeps the
  abstract node. Building against a lens reaches its **principal
  ports** only (derived-port references).
- **Materialize mode** — a deliberate construction step, recorded in
  the history like any other step. Its result is a new version in
  which the expansion's nodes exist as ordinary level-0 parts —
  *all* of them referenceable and reusable as parts, not just the
  principal ports — and in which consumers of the abstract node's
  ports arrive instead at the corresponding materialized ports (the
  port correspondence names each arrival point). Nothing is replaced
  or destroyed: the abstract node and every pre-conversion version
  remain in the history.

The difference between the modes is **addressability, not
mutability** — neither mutates anything. The lens exposes principal
ports; materializing puts the entire expansion on the table as parts
to build from.

"Abstraction is the source of truth" is sharpened rather than
violated: **each version reads at the highest level that is true of
it.** A version whose outputs route through a pristine `sum` reads as
a sum; a version built from the materialized parts with a decaying
step reads as the loop it is. No version ever claims "sum, plus a
patch" — that description was only ever conceivable under a mutation
framing, and it dies with it.

Asymmetries by direction:

- Downward operations (`expand`) have both modes: the lens is their
  always-on form, materialize their history-step form. Total on
  their pattern.
- Upward operations (`recognize`) are materialize-only. Recognition
  is partial, so there is no always-on upward lens; its entire point
  is to produce a version that reads at a higher level. Whether the
  IDE *offers* recognition eagerly — "this loop is a sum, collapse
  it?" — is an ergonomics question left open below.

Provenance comes for free. Under a mutation framing, a splice needed
an optional annotation ("this loop was a `sum`") or the old form was
simply lost. Here the materialize step *is* the record: the
conversion sits in the history with its input version intact and
recoverable. The provenance-note question from the earlier draft
dissolves.

---

## Worked example: rebuilding a sum

The motivating scenario, end to end, in the concrete vocabulary of
`iteration-with-state-design.md`.

Starting version:

```
nLst: list
nSum: reduce-close(+) over nLst's flow      -- abstract; monoid (+, 0)
nUse: f(nSum)
```

**Case A — build alongside (lens suffices).** Add a lockstep `max`.
No conversion is invoked. `nSum`'s lens (the augment-loop expansion)
exposes its combined list-with-state flow as a principal derived
port; a *new* augment is built whose `src` references that port and
carries the `max` state. The new version holds `nSum` (still a
pristine reduce-close) plus the new augment with a cross-level `src`
wire. This is the second-accumulator story from the iteration doc,
unchanged.

**Case B — change the step (take the parts).** Make the accumulation
decay: each iteration should compute `state * 0.9 + element`, which
is no monoid — this cannot be expressed as a reduce-close. Invoke
`expand` on `nSum` in materialize mode; the history gains a
conversion step, and the resulting version is:

```
nLst:  list
U:     uncollect  inputs  seed = 0, src = nLst's flow
                  outputs state, element
nStep: U.state + U.element        -- feedback advances U.state
nOut:  collect exposing the final accumulator
nUse:  f(nOut)                    -- arrives here via the port correspondence
```

Now the change — and nothing above is edited. Build a **new loop
from the parts**:

```
U':     uncollect  inputs  seed = 0 (same wire), src = nLst's flow (same wire)
                   outputs state, element
nStep': U'.state * 0.9 + U'.element   -- feedback advances U'.state
nOut':  collect exposing U''s final accumulator
nUse':  f(nOut')
```

This is the path copy from "Nothing mutates": the rebuilt path is
exactly {uncollect, step, collect, use} — the nodes from the changed
step to the outputs — while `nLst`, the seed literal, and everything
upstream are shared, not copied. The head version reads as what it
is, a decaying accumulation loop; the sum version, and the
materialized-but-unchanged version between, remain in the history
untouched.

The two cases give the practical rule of thumb: **reference the lens
to add; take the parts to change.** If Case B's author later
reshapes the loop back into a genuine monoid fold, `recognize` is
the earned way back up.

---

## Removing a conversion: cherry-picking

The persistent frame surfaces the one translation problem that
genuinely remains. Suppose the user materializes `sum`'s conversion
(history step `C`), builds further steps `D` and `E` on top, and
then changes their mind: they want the conversion gone but the later
work kept. In git terms: **cherry-pick `D` and `E` onto the version
before `C`.**

Replaying a construction step onto a different base is a
reference-translation problem — each wire in `D` that targeted the
old base must find its target in the new base:

- References to structure untouched by `C` carry over verbatim; by
  sharing, it is literally the same nodes.
- References to **principal** materialized ports translate: onto the
  abstract node's own ports where the port correspondence pairs them
  (e.g. the final value ↔ `sum`'s output), or into cross-level
  `DerivedPort` references through `sum`'s lens for principal
  expansion ports with no abstract-side twin (e.g. the combined
  list-with-state flow).
- References to **non-principal** materialized internals — the step
  node's own output, say — have no image in a history lacking `C`.
  That is a genuine conflict, surfaced to the user exactly as git
  surfaces one, with the same honest options: keep the conversion,
  drop the dependent step, or restructure by hand.

A pleasing alignment: the conflict class is precisely the extra
addressability that materializing bought. What the lens exposes
(principal ports) is what survives translation; what only
materialization exposes is what pins the conversion into any history
that used it. "Which ports are principal" thus has a second
consequence beyond reference hygiene: **it draws the boundary of
cherry-pickability.**

---

## The edit history is the tower

Because every change builds, the construction history is not an
editor convenience kept beside the program — it is built into the
model. The program of record *is* the history; any version is a fold
of a history prefix; the "current program" is just the version at
the head.

And the history re-runs the tower:

- Every level-0 construction ("add this node") is *also* a level-1
  act: it extends the history, and the history is a level-1 object —
  a sequence of operations on programs. Extending the history is in
  turn describable at level 2, and so on. This is "every operation
  spans [k, ∞)" again, now with the history as the concrete carrier,
  and degeneracy disposes of it identically: the step is stored
  once, at its native level; every higher reading is derived, never
  stored.
- Some operations are *natively* history-level. **Undo** is level 1:
  its content is about the program/history ("revert that step"), not
  about values. **Undoing an undo** operates on a history that now
  contains an undo — level 2. The tower does not top out; degeneracy
  is what keeps each such act one stored step rather than a stored
  stratum.
- The catalog therefore holds two families: **form conversions**
  (`expand`, `recognize`) and **history operations** (undo,
  cherry-pick/rebase). Both pass the admission test — their content
  is about programs, or histories of programs, never about values.

One caution, flagged open below: "undo" has two classical readings —
append a reverting step (git revert) versus move the head (git
reset) — and which the language means, or whether both exist, is not
yet designed. The level analysis is indifferent to the choice: the
native level is ≥ 1 either way.

---

## Representation: history as storage, versions as folds

An earlier section says "the program (with its level-1 steps) is the
thing of record." Concretely: the stored artifact is the
**construction history** — a sequence of steps (linear or DAG, open
below), each stored once at its native level. The history is
heterogeneous in level and that is fine: an add-node step (native
level 0), a materialize step (native level 1), an undo-of-undo
(native level 2) sit in one list, each tagged by what it operates
on. There are no stored strata above the steps themselves; every
higher reading of every step is degenerate.

Everything else is derived:

- A **version** is a fold of a history prefix — a level-0 program
  value. Versions share structure the way persistent-data-structure
  snapshots do: a step touching one path copies that path and shares
  the rest.
- A **lens** stores nothing: it is implied by the node species. A
  reduce-close node *is* the level-1 step whose expansion is its
  lens — one stored datum, read at two levels; degeneracy cashing
  out in the representation.
- A **materialize** is an ordinary history step whose result
  version contains the expansion's nodes as ordinary level-0
  structure.
- **Cross-level wire references**: a wire target of the form
  `DerivedPort(nodeId, portName)` — "the port named `portName` in
  the expansion of node `nodeId`." Resolution computes the
  expansion's *shape* (which ports exist), which is structural and
  cheap; values force lazily as ever. `portName` draws from the
  catalog entry's declared principal ports, so a reference can never
  reach a derivation internal — ill-formed references are
  unrepresentable rather than checked.
- **Materialize and cherry-pick as pure functions** over the
  existing structures (`version → version` and
  `history × step → option<step>` respectively). Nothing new in the
  level-0 syntax.

Level 2 gains its first plausible resident in undo-of-undo (above).
Beyond that the candidates that come to mind — composing two
conversions, applying a conversion at every matching site — are on
inspection still level 1 (a bigger pattern, but content about
level-0 programs either way). Degeneracy means the sparsely
inhabited upper tower costs nothing to keep, and the
single-native-level assumption survives the whole catalog so far: no
entry has independent content at two levels.

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
  Dissolved rather than solved: no stored strata exist above the
  history's steps. Each step is stored once at its native level;
  every higher reading is degenerate. No stored lift map is needed.
- ~~**Provenance notes.**~~ Dissolved by the persistent frame: the
  materialize step in the history *is* the provenance, with the
  pre-conversion version intact and recoverable. No annotation
  mechanism is needed.
- **Which derived ports a derivation exposes** — reduced from a policy
  question to a per-entry field, with a second consequence discovered:
  principal ports also draw the boundary of cherry-pickability. Still
  to pin: the actual port list for each entry as it is implemented
  (for `expand` on reduce-close: the combined list-with-state flow and
  the final value).

Still open:

- **Is the tower load-bearing?** Strengthened: conversions are an
  irreducible level-1 resident, history operations (undo,
  cherry-pick) are a second family, and undo-of-undo is a plausible
  first level-2 resident. What remains is how much *else* collapses
  to level 0 via enrichments like latent flows.
- **The single-native-level assumption** stated above — unfalsified by
  the current catalog, unproven in general.
- **History shape.** Linear sequence or DAG? Branching histories
  (trying a change, keeping the old head alive) and merging are
  natural under the persistent frame but undesigned. Cherry-picking
  already smells like a DAG operation.
- **Node identity across versions.** Path copying makes "the same
  node" subtle: the copied step node in the worked example is a *new*
  node. What identity, if any, connects a node to its rebuilt
  counterpart across versions — and whether the port correspondence
  machinery generalizes to answer it — is undesigned. Cherry-pick
  translation and any diff/blame view both depend on it.
- **The cherry-pick algorithm in detail.** The three translation
  rules above are the spec's skeleton; the actual replay (ordering
  among transplanted steps, conflict presentation, partial
  application) is undesigned.
- **Undo's reading.** Append-a-reverting-step (git revert) versus
  move-the-head (git reset), or both. Interacts with history shape.
- **Editor gesture mapping.** "Grab a part inside a lens view and
  build with it" must denote materialize-then-build (the part is
  non-principal) or a plain derived-port reference (it is principal).
  Whether the editor materializes implicitly on the first
  non-principal grab or requires an explicit gesture is undecided;
  the semantics underneath are fixed either way.
- **Eager recognition.** Whether the IDE proactively offers
  `recognize` ("this loop is a sum — collapse it?") or waits to be
  asked. Eager offers make abstraction cheaper to earn but risk
  nagging on loops deliberately built from materialized parts.
