# Trees and recursive structures

Status: design-only exploration — none of this is implemented. Code
samples use the textual syntax of `textual-representation-design.md`;
where the language has no settled spelling for a recursive construct,
the sample is marked *spelling provisional*.

## The challenge

A list has one spread axis, so iteration walks it in order. A tree
branches in several directions at once — there is no single axis to
walk. The tempting answer, "write a recursive function that visits a
node and calls itself on the children," is exactly the expert
construction the language exists to remove: manual recursive
step-taking is rejected. Iteration over a recursive structure must come
from a primitive that has the recursion built in, the same way `open
list` has element-iteration built in.

## Zipper-based iteration

The unit of tree iteration is a **zipper** — a focused view of a
recursive structure that carries its full context. At each step the
zipper exposes the current node and its value, the path back to the
root, the siblings, the children, and the parent. Context comes for
free; you never navigate by hand, and the *original* structure stays
reachable and safe to read.

```
tree -> open tree => node, ~T          -- spelling provisional
node.value -> render -~> collect => rendered
```

*Opens a tree into a per-node flow; the zipper's `node` port carries
the focus, `~T` the flow. Each node's value is rendered and collected
back into a tree.*

**Computed-value zippers.** The zipper can expose more than the input
structure: it can expose values *computed earlier in the same
iteration*. Subtree size is the canonical example — a node's size is
`1 + sum(children's sizes)`, and the children's sizes were computed on
an earlier step of the same traversal.

```
tree -> open tree => node, ~T                    -- spelling provisional
node.childSizes -> sum -> add(1) -~> collect => size
```

*The zipper hands each node the sizes already computed for its
children; the node adds one for itself.*

This is powerful and it is the source of the doc's central risk: if two
accesses depend on each other mutually, no evaluation order exists and
the computation is unsound.

## Soundness: verify an ordering, or fall back lazy

The user wires a computation pattern against zipper accesses without
saying what order the tree is walked in. The compiler infers the order
from the dependencies:

- children → parent is post-order; parent → children is pre-order;
  left-sibling → right-sibling walks siblings in order. All three admit
  a valid traversal.
- parent ↔ children, or sibling ↔ sibling, is a cycle. No traversal
  order satisfies it.

When no order exists, the design falls back to lazy evaluation with a
warning: the program may diverge at runtime. This trades the static
guarantee for expressive reach.

Whether tree iteration keeps this verify-or-fall-back scheme is
unresolved. The loop-state redesign deliberately dropped
dependency-analysis and lazy-fallback for *carried* state — "no
dependency analysis, no soundness check, no lazy fallback"
(`iteration-rails-design-notes.md`) — in favour of the register
discipline, where every cycle must cross a register and productivity is
checked structurally. Tree iteration could inherit that discipline
instead of its own verifier. The register precedent is the stronger
current.

## Automatic derivation from recursive ADTs

For any recursive algebraic data type the compiler can mechanically
derive the whole apparatus: the zipper, the iteration flow, and
fold/unfold (catamorphism/anamorphism). There are no special cases for
list versus tree — a user-defined recursive type gets iteration for
free, and the same derivation gives list iteration as the one-child
instance.

Type structure carries the constraints for free. A Red-Blue list whose
`BlueCons` tail must be a `BlueList` enforces its one-way transition
through the derived zipper with no special handling. Heterogeneous trees
work identically: an expression type whose alternatives constrain their
children iterates by case-splitting on the alternatives, and the types
do the rest.

**Where the derivation stops.** `tough-use-cases-design.md`
stress-tested this against mergesort and found the limit. When the
recursion structure is *virtual* — a split tree that exists only as
call structure, never as a value — feeding it to the ADT derivation
would mean materialising that tree as data first. That is declaring
structure upfront, which example-first forbids, and it is rejected
there for that reason. The **divide flow** proposed in that doc is the
candidate primitive for recursion over virtual structure. ADT
derivation remains the story for recursion over *data*.

## The two-layer visual pattern

Because a tree can't spread across the page spatially, the design draws
the computation pattern with temporal layers: an upper layer showing
the already-computed neighbourhood (for post-order, the children's
values) and a lower layer showing the current node's computation, with
faint correspondence lines between them. The drawing is the generic
pattern that applies at every node — like a function definition, not a
trace of one run.

This is in tension with the later one-visible-column constraint for
iteration drawing ("the user only sees one iteration",
`iteration-rails-design-notes.md`, which rejected ghost columns for
lists). Whether a tree justifies a schematic already-computed layer
where a list does not is an open visual question. It is out of scope in
this repo and flagged for the layout side.
