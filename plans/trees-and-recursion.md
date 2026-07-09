# Trees and recursive structures

*Distilled 2026-07-09 from the retired design narrative
(`visual-flow-language.md`, git history). Design-only — none of this
is implemented. Status notes mark where later rounds bear on it.*

## The challenge

Trees branch in multiple directions; there is no single spread axis.
The language's answer must not be "write a recursive function" —
manual recursive step-taking is rejected — it demands exactly the
expert construction the language exists to avoid. Iteration over
recursive structures comes from primitives with recursion built in.

## Zipper-based iteration

A **zipper** is a focused view of a recursive structure with full
context: the current node and its value, the path to the root,
siblings, children, the parent. It gives access to context without
manual navigation, and access to the *original* structure is always
safe.

**Computed-value zippers.** The zipper can also expose values
*computed earlier in the same iteration* — e.g. subtree sizes:
`1 + sum(child_sizes)` needs the children's already-computed values.
This is powerful and risky: mutually dependent accesses would be
unsound.

## Soundness: verify an ordering, or fall back lazy

The user wires a computation pattern against zipper accesses; the
compiler looks for a traversal order that satisfies the dependencies:

- children → parent (post-order), parent → children (pre-order),
  left-sibling → right-sibling — all fine;
- parent ↔ children or sibling ↔ sibling cycles — no valid order.

When verification fails, the recorded design falls back to lazy
evaluation with a warning (may diverge at runtime), trading safety
for flexibility.

> **Status.** The loop-state redesign deliberately dropped
> dependency-analysis/lazy-fallback machinery for *carried state*
> ("no dependency analysis, no soundness check, no lazy fallback" —
> `iteration-rails-design-notes.md`). Whether tree iteration keeps
> this verifier or inherits the register discipline (every cycle
> crosses a register, productivity-checked) is unresolved; the
> register precedent is the stronger current.

## Automatic derivation from recursive ADTs

For any recursive algebraic data type the compiler can mechanically
derive: the zipper, the iteration flow, and fold/unfold
(catamorphism/anamorphism). No special cases for list or tree; a
user-defined type gets iteration for free. Type structure carries
constraints for free too — a Red-Blue list whose `BlueCons` tail is
`BlueList` enforces its one-way transition through the derived zipper
without any special handling, and heterogeneous trees (an expression
type whose alternatives constrain their children) work the same way:
case splitting exposes the alternatives, the types do the rest.

> **Status.** `tough-use-cases-design.md` stress-tested this
> machinery against mergesort and found its limit: when the recursion
> structure is *virtual* (a split tree that exists only as call
> structure), feeding the derivation would mean materialising the
> tree as data — rejected there as declaring structure upfront,
> exactly what example-first forbids. The
> **divide flow** proposed there is the candidate primitive for
> recursion over virtual structure; the ADT derivation remains the
> story for recursion over *data*.

## The two-layer visual pattern

Since trees can't spread spatially, the recorded design draws the
computation pattern with temporal layers: an upper layer showing the
already-computed neighbourhood (children's values, for post-order)
and a lower layer showing the current node's computation, with faint
correspondence lines. The drawing shows the generic pattern that
applies at each node — like defining a function, not tracing a run.

> **Status.** In tension with the later one-visible-column constraint
> for iteration drawing ("the user only sees one iteration" —
> `iteration-rails-design-notes.md`, which rejected ghost columns for
> lists). Whether trees justify a schematic already-computed layer
> where lists don't is an open visual question; out of scope in this
> repo, flagged for the layout side.
