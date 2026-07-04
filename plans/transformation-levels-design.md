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

## What is unresolved

- **Whether the latent-flow collapse covers all the operations we will
  want.** If every programmer-vocabulary operation can be expressed as a
  port tap, the tower is never needed in the representation and remains
  purely explanatory. If some cannot, the tower (with degeneracy)
  becomes load-bearing.
- **The single-native-level assumption** stated above.
- **The concrete lift map.** If the tower is ever made load-bearing, the
  canonical degeneracy map and the per-operation native-level annotation
  need a concrete form in the representation.
