# Trees and recursive structures

Status: design-only exploration, with **the soundness seam decided**
(design conversation, 2026-07-23 — see the end of "Soundness:
verify an ordering, or fall back lazy"): the verifier retires, the
computed-value zipper ports retire as stored surface (the
`childSizes`-from-nowhere ruling), those accesses are drawn
crossings, input-structure zipper reads stay, and the compact form
survives as a derived view. None of it is implemented.
Code samples use the textual syntax of
`textual-representation-design.md`; where the language has no settled
spelling for a recursive construct, the sample is marked *spelling
provisional*. The divide flow — recursion over *virtual* structure,
which this chapter only points at — now has its own worked round
(`divide-flow-design.md`, exploration); this chapter remains the
home of recursion over *data* (the zipper, ADT derivation).

## Your first tree program

You know how to iterate over a list: `open list` hands you each
element in turn. Suppose instead you have a tree — say a document
tree — and you want to render every node in it:

```
tree -> open tree => node, ~T          -- spelling provisional
node.value -> render -~> collect => rendered
```

Read it exactly like a list loop: `open tree` opens the tree into a
per-node flow (`~T`), each node comes through on `node`, its value is
rendered, and the collect gathers the results back into a tree.

Now, you might wonder why the language doesn't just let you write a
recursive function — visit a node, call yourself on the children —
the way you would in a conventional language. After all, a list has
one spread axis, so iteration can walk it in order; a tree branches
in several directions at once, and there is no single axis to walk,
so surely someone has to spell out the walk? It turns out that manual
recursive step-taking is exactly the expert construction the language
exists to remove, and it is rejected: iteration over a recursive
structure must come from a primitive that has the recursion built in,
the same way `open list` has element-iteration built in. (This is a
settled rejection — please don't re-propose hand-written recursive
walks without new evidence.)

## What `node` is: a zipper

So what does `open tree` hand you at each step? More than a bare
value. The unit of tree iteration is a **zipper** — a focused view of
a recursive structure that carries its full context. At each step the
zipper exposes the current node and its value, the path back to the
root, the siblings, the children, and the parent. Context comes for
free; you never navigate by hand, and the *original* structure stays
reachable and safe to read.

**Computed-value zippers.** The zipper can expose more than the input
structure: it can expose values *computed earlier in the same
iteration*. Subtree size is the canonical example — a node's size is
`1 + sum(children's sizes)`, and the children's sizes were computed
on an earlier step of the same traversal:

```
tree -> open tree => node, ~T                    -- spelling provisional
node.childSizes -> sum -> add(1) -~> collect => size
```

*The zipper hands each node the sizes already computed for its
children; the node adds one for itself.*

This is powerful, and it is the source of this chapter's central
risk: if two accesses depend on each other mutually, no evaluation
order exists and the computation is unsound.

## Soundness: verify an ordering, or fall back lazy

Notice what you did *not* say in the subtree-size program: you never
said what order the tree is walked in. You wired a computation
pattern against zipper accesses, and the compiler infers the order
from the dependencies:

- children → parent means "visit children before their parent" (what
  conventional code calls post-order); parent → children means the
  reverse (pre-order); left-sibling → right-sibling walks siblings in
  order. All three admit a valid traversal.
- parent ↔ children, or sibling ↔ sibling, is a cycle. No traversal
  order satisfies it.

When no order exists, the design falls back to lazy evaluation with a
warning: the program may diverge at runtime. This trades the static
guarantee for expressive reach.

Whether tree iteration keeps this verify-or-fall-back scheme is
unresolved — the language hasn't decided this yet. The loop-state
redesign deliberately dropped dependency-analysis and lazy-fallback
for *carried* state — "no dependency analysis, no soundness check, no
lazy fallback" (`iteration-rails-design-notes.md`) — in favour of the
register discipline, where every cycle must cross a register and
productivity is checked structurally. Tree iteration could inherit
that discipline instead of its own verifier. The register precedent
is the stronger current — and the divide-flow round strengthened it
(`divide-flow-design.md`, "What this feeds back to the trees row"):
the verifier's three access directions all have drawn counterparts
there (children→parent = link answers, parent→children = problem
components, sibling→sibling = a register on the drawn children
walk), so the leaning on record was that the zipper's computed-value
accesses re-read as drawn crossings and the verifier retires.

**Decided (design conversation, 2026-07-23), on amended grounds.**
The conversation set the soundness motivation aside entirely
("compile with lazy values; maybe it's sound, maybe it isn't — not
trying to do Agda"; the measure ladder's warned-trust rung is the
record's own accepted floor, so no new guarantee obligation
arrives). What decided the seam was **readability**:

- **The `childSizes`-from-nowhere ruling.** In the subtree-size
  program above, nothing on the page connects `childSizes` to the
  `add(1)` output it must denote — the port is an *undrawn
  self-reference resolved by a magic name*, condemned by the
  record's oldest rejection. Two computed values per node (a size
  and a hash) break it open: two ports, bound to which pipeline,
  by what? The collect binder would be doing invisible double duty
  as a port declaration — the link's job, done secretly. The link
  is not machinery added to this program; it is the wire the
  program was already using and not drawing.
- So: the **verifier retires** (soundness machinery, unwanted on
  its own terms); **computed-value ports retire as stored
  surface** and re-read as drawn crossings (children→parent = link
  answers, parent→children = problem components, sibling→sibling =
  a register on the children walk); **input-structure zipper
  reads** (`node.value`, `node.parent`, the path) **stay** — they
  are innocent data reads.
- **What survives as derived views**: the compact two-layer
  rendering (the link's answer wires drawn as an already-computed
  layer), and the *schedule word* — "post-order" is a data-flow
  fact ("the parent consumes the children's answers", the drawn
  direction of the crossing), never authored, but derivable and
  displayable as a traversal-order view toggle
  (`facets-design-notes.md`, "Facets as view toggles"). Legibility
  over enforcement, applied to traversal order.

Idle notes recorded with the decision (same conversation — none
of them changes it):

- **Soundness and order-legibility nearly coincide.** If the user
  can tell which order a traversal runs in, the recursion is
  more or less sound by accident — it is hard to write unsound
  recursion while knowingly doing a post-order walk. Consequence
  for the compile: where an order is derivable from the data
  flow, the lazy-value compilation isn't even *necessary* — an
  optimization license, not an obligation. We are not doing
  soundness for soundness's sake; when it appears, it appears as
  a side effect of legibility.
- **When does the user actually want the order?** Two answers.
  Data-flow order is the usual care (as decided above). And IO
  makes order *observable*: counting files in a directory tree,
  nobody cares; recursively *deleting* one, the user wants to see
  that children are deleted before the parent. So tree walks that
  thread the IO flow want a *tellable* order — the first
  tree-shaped client for the IO-as-flow direction
  (`effects-design.md`): the children-before-parent sequence is
  the answers-up crossing inducing the IO flow's order, readable
  on the rail.
- **But no order is required.** The lingering worry: some
  ingenious lazy algorithm that wanders up, down, and around the
  tree in no predictable order, works great, and would be
  inexpressible if every traversal had to carry an order. So the
  ruling stays permissive: users draw data-flow order; if their
  dataflow has cycles, that is what they meant — the cycles are
  visible in the graph, so nobody is surprised they're there.
  (Lazy compile is exactly the semantics that honors this.)
- **Reaffirmed:** the basic building block underneath all of it
  is expressing dependencies across realms and identifying
  corresponding values with a thread.

## You get this for free: derivation from recursive types

Nothing about the zipper is tree-specific. For any recursive
algebraic data type — a type defined in terms of itself — the
compiler can mechanically derive the whole apparatus: the zipper, the
iteration flow, and fold/unfold (what the literature calls
catamorphism/anamorphism). There are no special cases for list versus
tree — a user-defined recursive type gets iteration for free, and the
same derivation gives list iteration as the one-child instance.

Type structure carries the constraints for free. A Red-Blue list
whose `BlueCons` tail must be a `BlueList` enforces its one-way
transition through the derived zipper with no special handling.
Heterogeneous trees work identically: an expression type whose
alternatives constrain their children iterates by case-splitting on
the alternatives, and the types do the rest.

**Where the derivation stops.** `tough-use-cases-design.md`
stress-tested this against mergesort and found the limit. Mergesort's
recursion structure is *virtual* — a split tree that exists only as
call structure, never as a value. Now, you might wonder why you
couldn't just build that split tree as data and feed it to the ADT
derivation like any other tree. It turns out this would mean
materialising the tree as data first — declaring structure upfront,
which the example-first principle forbids — and it is rejected in
that document for that reason. (This is a settled rejection —
recorded in `tough-use-cases-design.md`; don't re-propose it without
new evidence.) The **divide flow** proposed in that doc is the
candidate primitive for recursion over virtual structure — now
worked in its own round (`divide-flow-design.md`: the link
transformation tree-shaped, a three-species measure discipline for
termination, recursive descent and the quadtree worked end-to-end).
ADT derivation remains the story for recursion over *data*, with one
new connection: that round reads recursion-over-data as the divide
flow whose division is "take the strict components," which is where
the derivation's termination guarantee was always coming from.

## The two-layer visual pattern

Because a tree can't spread across the page spatially, the design
draws the computation pattern with temporal layers: an upper layer
showing the already-computed neighbourhood (for a children-first
walk, the children's values) and a lower layer showing the current
node's computation, with faint correspondence lines between them. The
drawing is the generic pattern that applies at every node — like a
function definition, not a trace of one run.

This is in tension with the later one-visible-column constraint for
iteration drawing ("the user only sees one iteration",
`iteration-rails-design-notes.md`, which rejected ghost columns for
lists). Whether a tree justifies a schematic already-computed layer
where a list does not is an open visual question — the language
hasn't decided. It is out of scope in this repo and flagged for the
layout side.
