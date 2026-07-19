# The divide flow: recursion over virtual structure

Status: exploration — a worked proposal with leanings, prepared for a
design conversation and *not* adopted. This is the round the
recursion row (`open-problems.md`) owed: the divide flow was proposed
in `tough-use-cases-design.md` (use case 3, the mergesort limit) as
the candidate primitive for recursion whose tree exists only as call
structure, and left with an unworked termination story, an owed
non-list example (quadtree), and a named candidate first program
(recursive descent, `raku-grammars-comparison.md`). This chapter
works those three, plus the `walk`-style deep rewrite that
`focused-update-design.md` filed here. Code samples use the textual
syntax of `textual-representation-design.md`; every spelling
involving the link is provisional (open question 1).

What this round consumes from the record: the link transformation
(the register's construction gesture, `iteration-with-state-design.md`);
the confluence distinction against saturation
(`saturation-design.md`, "Relationships"); the m-sibling-collects
leaning (`barrier-value-crossing-design.md`); zip's shared-provenance
alignment (`product-flows-design.md`); and the four-part parsing
vocabulary of which this is the last part
(`speculation-design.md`).

## One level, written concretely

Start where the record's example-first principle says to start: with
no recursion at all. Here is *one level* of mergesort — a case split
on the problem, nothing more:

```
xs -> split singleton? of Base, Divide => s
s.Divide -> splitInHalf => subA, subB
~s.Base:   s.Base                -- a one-element list is already sorted
~s.Divide: ???                   -- a hole: needs subA and subB *sorted*
-~> collect => sorted
```

This program is honest as far as it goes. A singleton list is its own
answer. A longer list splits in half — and then the Divide lane
stalls, because what it needs is not `subA` and `subB` but their
*sorted* versions, and nothing on the page sorts them. The lane holds
a **hole** (`program-editing-design.md`: holes are representable
partiality, legal to draw).

Notice what the hole's filler would have to be: *this same
computation*, applied to a smaller input. The page already contains
the thing the hole needs.

## The link

The register was earned by exactly this move, one dimension down.
There, you write one step of a running computation concretely, and
then **link** the step's output back to the state input: "this output
and this input are the same thing across iterations"
(`iteration-with-state-design.md` — the link transformation). The
linear link produced iteration.

The divide flow is **the link, tree-shaped**. You write one level
concretely — the program above — and then link the sub-problems back
to the problem: "these wires and that input are the same thing across
*levels*." The linking gesture mints a node, the **link**, and the
hole fills:

```
-- spelling provisional (open question 1)
xs -> split singleton? of Base, Divide => s
s.Divide -> splitInHalf => subA, subB
subA -> level of xs => sortedA        -- the link: this, one level down
subB -> level of xs => sortedB
sortedA, sortedB -> mergeSorted => merged
~s.Base:   s.Base
~s.Divide: merged
-~> collect => sorted
```

Read `subA -> level of xs => sortedA` as: *sortedA is what this page
computes for `sorted`, when its `xs` is `subA`.* The link is a node
with input ports corresponding pairwise to the **problem wires** (here
one, `xs`) and output ports corresponding pairwise to the level's
**answer wires** (here one, `sorted`). "Split until singletons, merge
upward" — the diagram says the sentence, and mergesort reads at its
own abstraction level.

The meaning is denotational and needs no operational stack in the
picture: the page is a system of equations; the link says the same
equations hold again with the problem wires rebound. Each firing of a
link mints an **instance** — a fresh copy of the level's computation
— and the instances form a runtime tree, the recursion tree that the
data never contained. That is what "recursion over virtual structure"
means: the tree exists as instances of the drawing, not as a value.

Two precedents anchor the representation and the vocabulary:

- **Representation.** The link is a cycle in the wiring, and the
  record already owns the move: like DelayWrite, the later linking
  act mints its own node, the object graph stays a DAG, and the cycle
  is recovered from identity (`tough-use-cases-design.md`, use case
  3, "Representation").
- **Runtime-minted extent.** The divide flow and saturation are the
  two constructs whose firing count is not fixed by opened data. The
  distinction is confluence: divide spawns a *tree* of instances (no
  firing shared, termination at leaves); saturation's minted firings
  dedup against a seen-set, giving a *DAG* with merges and a fixpoint
  (`saturation-design.md`). Tree without dedup = divide. The
  concurrent collect's settle node is the third member of the
  honestly-primitive family — like it, the divide flow has no
  lowering, and that is acceptable for the same reason: list
  iteration doesn't lower either (`concurrent-collect-design.md`,
  "Primitive, not catalog block").

## What is per-instance, and what is shared

There is no scope anywhere in this. Which parts of the page are "in
the recursion"? The answer is derived, exactly as "inside the loop"
is derived for ordinary flows (`textual-representation-design.md`,
P3): **a node is per-instance iff it is downstream of a problem
wire.** Everything else — constants, configuration, a comparator, a
lookup table — is a single shared value that every instance reads,
by the same prefix rule that lets a constant appear inside a nested
loop (`bundle-provenance-design.md`). Nothing is copied down the
tree; nothing needs transport machinery.

This also answers where recursion *stops operationally*. The case
collect demands one lane per instance — the lane the split chose —
and only that lane's cone runs. A link fires only when its lane is
demanded, so a Base instance never fires a link. The laziness the
compile already lives by (`lazy-compile-design.md`) is the mechanism;
the *guarantee* that the chain of demanded links is finite is the
measure discipline below.

Provenance extends without new machinery: a link crossing appends a
segment to the context path, so parent-child instance contexts nest
(the child lives below the parent's link firing) and sibling
instances are incomparable — their values can meet only through
their answers at the shared parent. The spec-side detail (the path
segment's exact form) is owed bookkeeping, filed with
`bundle-provenance-design.md`'s path vocabulary.

## A leaf is an alt with no links

Now, you might wonder whether the language needs a *base-case
construct* — a marked pair of roles, "base" and "divide," the way
the original sketch in `tough-use-cases-design.md` drew them. It
turns out the roles dissolve: the head of a divide flow is an
ordinary case split, and **a leaf alt is simply an alt whose lane
fires no links**. Mergesort has one leaf alt and one two-link alt; a
quadtree has a leaf and a four-link alt; an expression evaluator has
per-alt link counts (Lit 0, Neg 1, Add 2) — the alts constrain their
own recursion the way a heterogeneous ADT's alternatives constrain
their children (`trees-and-recursion.md`). Nothing about "base" is
special structure, so nothing new has to be learned to read it.
(This is a dissolution, not a construct — recorded so the two-role
sketch isn't re-proposed as syntax.)

## Termination: the measure discipline

The linear link's soundness condition was crisp: every cycle crosses
a register, and productivity is checked structurally — no dependency
analysis, no lazy fallback (`iteration-rails-design-notes.md`). The
tree link needs its analog. "Sub-problems get smaller" is
undecidable in general, and `tough-use-cases-design.md` (question 4)
left a leaning — catalog divisions with a size-measure check, warned
trust for user divisions — with the instruction to work a non-list
example so the catalog doesn't come out list-shaped.

Working the three clients of this round produced not one measure but
**three measure species**, and that is the round's first result:

- **Structural shrink.** The sub-problem is a strict part of the
  parent's data. Catalog divisions carry this as a property with a
  witness — `splitInHalf` yields two strictly shorter lists (given
  length ≥ 2, which the split's discriminator establishes),
  `tail` a strictly shorter list, "strict components of a value" a
  structurally smaller value. This is the collect family's catalog
  discipline reused: rows are properties carrying witnesses, minted
  for user operations through the same trusted authoring surface
  (`collect-family-design.md`; `types-design.md` question 4).
- **Progress.** The sub-problem is the *same* data at a strictly
  advanced position — parsing's species. The measure is "the cursor
  moved": a link whose sub-problem position provably consumed at
  least one token terminates over finite input. The classic
  violation has a famous name: **left recursion** — a grammar that
  recurses at the same position — and the fact that PEG tooling
  rejects it is field confirmation that this check is real
  vocabulary, not an invention (worked in the parsing section
  below).
- **Fuel.** The problem carries a counter the divide alt strictly
  decreases, and an alt covers zero. The measure is *drawn*: the
  decrement is on the page, the zero case is an ordinary alt of the
  split. Quadtree's species (worked next), and the honest form of
  what would otherwise be trust.

The ladder, then, leaning as question 4 leaned but sharper:

1. **Catalog division** — the shrink or progress property comes from
   a catalog row, checked by construction.
2. **Drawn measure** — no catalog row applies, so the author threads
   a fuel counter; the check is structural (the decrement is a
   catalog `minus1`-style row; the split covers the zero case).
3. **Warned trust** — neither; the program is legal and flagged "may
   diverge," the exact precedent of the derived-iteration soundness
   check's documented fallback (`trees-and-recursion.md`).

Flix's `@Terminates` is the prior art that termination is *declared,
checked* vocabulary rather than an ambient hope
(`flix-comparison.md`), and rung 3 matching the derived-iteration
precedent keeps one policy across both recursion stories. Note what
is absent: no dependency analysis anywhere. The only cross-instance
edges are the drawn link (down) and its answer ports (up) — the
register discipline's shape, one level up.

## Quadtree build: the non-list example

The owed example — a tree from *use*, not from data. Problem: a set
of points, a square region, and (we will discover why) a depth
budget. Build the quadtree: a region with few points is a leaf;
otherwise split the region into four quadrants and recurse.

First, watch the obvious measure fail. "The sub-problem has fewer
points" is *false*: if many points are coincident (or merely fall in
one quadrant), one child can inherit every point of its parent.
Point count does not decrease, and a divide flow trusting it would
recurse forever on ten identical points. Field quadtrees know this:
real implementations bound depth. So the problem honestly carries a
budget, and the measure is fuel:

```
-- spelling provisional
diagram quadtree
  in pts, region, budget
  pts, budget -> classify => c        -- Leaf if few points or budget 0
  c -> split kind of Leaf, Quad => s
  region -> quadrants => q1, q2, q3, q4
  budget -> minus1 => b
  pts -> within(q1) => p1             -- likewise p2, p3, p4
  p1, q1, b -> level of (pts, region, budget) => t1
  p2, q2, b -> level of (pts, region, budget) => t2
  p3, q3, b -> level of (pts, region, budget) => t3
  p4, q4, b -> level of (pts, region, budget) => t4
  ~s.Leaf: pts -> leafNode
  ~s.Quad: t1, t2, t3, t4 -> quadNode
  -~> collect => tree
  out tree
end
```

What the example was ordered to check, it delivers:

- **The catalog isn't list-shaped.** Nothing here shrinks a list.
  The division splits a *region*; the data (points) may not shrink
  at all; termination rides the drawn `minus1` on the budget, with
  `classify` covering zero. Rung 2 of the ladder, exercised.
- **The link is a barrier, not a bottleneck.** The problem is three
  wires — points, region, budget — and each link crossing carries
  three corresponding wires. No problem-struct is packed to cross
  the link and torn apart inside; each wire passes as itself, the
  same pairwise-correspondence discipline every barrier in the
  record obeys.
- **Inherited attributes are problem components.** The budget flows
  *down*; the subtrees flow *up*. What an attribute-grammar person
  would call inherited and synthesized attributes are just the
  link's two directions — ordinary wires, no new mechanism. (Depth,
  a path prefix, an indentation level: all the same shape.)
- Only the Quad lane demands `t1…t4`, so a Leaf instance fires no
  links — the demand story from the sharing section, visible.

## Recursive descent: the everyday client

Parsing is the everyday client of recursion-over-virtual-structure
(`raku-grammars-comparison.md` §4) — the divide flow's constructed
examples needed a program someone actually writes on a Tuesday.
`speculation-design.md` split the parsing vocabulary into four
parts: speculation (ordered choice), position-threading
(concatenation), commit + fail (commitment and diagnosis), and the
divide flow (recursion) — of which this was the missing part. Here
it is, on the classic nested-delimiter grammar: an expression is an
atom, or `(` expressions `)`.

The problem is a **position** — a value, per the speculation round's
threaded-cursor stance (positions are immutable values; `peek` and
`consume*` are catalog reads over (tokens, index)). The level has
*two* answers: the parsed node, and the position after it. Two
answers are two sibling collects at one context — the
m-sibling-collects leaning of `barrier-value-crossing-design.md`,
landing its first everyday client — and correspondingly the link has
two answer ports.

```
-- spelling provisional; composes the source opener, end-when, the
-- register, and the link — each cited where it enters
diagram parseNode
  in p
  p -> peek -> split kind of Atom, Open => s

  -- Atom: the leaf alt, no links
  p -> consumeAtom => leafAst, pLeaf

  -- Open: '(' node* ')' — a children walk with the link inside
  p -> consumeOpen => p0                -- past the '('
  open self => ~R                       -- source-openers-design.md
  ~R ~> delay init p0 => cur            -- position register
  cur -> peek -> split close? of Close, More => e
  ~e.Close: -~> end-when                -- stop at ')' (end-when-design.md)
  cur -> level of p => childAst, pChild -- THE LINK: parse one child
  pChild -> step of cur => pEnd         -- child's end = next child's start
  childAst -~> collect => children      -- the children, in order
  pEnd -> consumeClose => pList         -- past the ')'
  children -> listNode => listAst

  ~s.Atom: leafAst
  ~s.Open: listAst
  -~> collect => ast
  ~s.Atom: pLeaf
  ~s.Open: pList
  -~> collect => pAfter
  out ast, pAfter
end
```

Three things this program demonstrates that the fixed-arity examples
could not:

**Variable arity dissolves into drawn structure.** A parenthesized
node has however many children the input says. There is no
variable-arity link shape: the link is an ordinary node, and it
fires *as often as its context does*. Put a link at an alt's top
context and it fires once per instance (mergesort's two, quadtree's
four); put it inside a walk and it fires once per firing of the
walk. The children walk above is a self-driven flow ended by data —
existing vocabulary — and the link inside it parses one child per
firing. Extent-of-recursion is just extent, decided by the same
constructs that decide extent everywhere else.

**Sequential dependence is the register, unchanged.** Sibling
sub-parses are not independent: each child starts where the previous
ended. That is a loop-carried position — the register threads it
(`pChild -> step of cur`), and the position after the *last* child
is the register's final readout (`=> pEnd`, the write-half binder).
No part of "the children depend on each other" touched the link; the
dependence lives in the walk, where the record already keeps it.

**The progress measure is the left-recursion check.** The link's
sub-problem is `cur`, and `cur` is provably past `p`: it descends
from `consumeOpen`, which consumed a token. A grammar that recursed
at the *same* position — `expr := expr '+' term`, transcribed
naively — would hand the link a sub-problem with no consumption on
its wire path, and the measure check would flag exactly that wire.
Left recursion, the classic recursive-descent bug that PEG tooling
detects and rejects, is the progress measure's violation witness.
The check is not invented vocabulary; the field already performs it.

Two honest notes. The walk leans on end-when's inclusive/exclusive
bit (the Close firing must contribute no child) — that bit is
end-when's named residue and this program is one more datum for
deciding it. And the children collect's discharged terminator (left
unbound in the sketch) is not decoration: `RanOut` at that collect
*is* the unclosed-parenthesis error — input exhausted before `)` —
one more instance of the stop/discharge/split-on-tag composition
doing an error path's work. And a real grammar's level head is not a plain split
but an ordered choice among alternatives that can fail
(`expr := let || app || atom`); that is speculation's barrier, and
the link rides inside contenders unchanged — a failed contender's
sub-parses are abandoned as unconsumed values, per that round's
structural-restoration result. The four-part vocabulary composes by
wiring, which is what "parts" was supposed to mean.

Failability composes with one constraint worth recording now: a
sub-parse fails like anything else fails — the link's answer is a
failable value, propagate-by-default up the levels
(`async-flow-design.md`). But Zig's warning transfers verbatim:
inferred error sets are not well-founded over recursion
(`zig-comparison.md`, finding 7). The link boundary is exactly where
payload-set inference must stop — the leaning is that a link
crossing demands a *declared* payload set, the way Zig's recursive
functions demand explicit error sets. Filed with failability's
payload-composition residue.

## Deep rewrite: the unfold client

`focused-update-design.md` deferred `walk`-style rewrite — "change
every node matching P, however deep" — to this round, predicting the
divide flow would force the unfold side its constructed examples had
not. It does, and the composition is short. Blank every `password`
field anywhere in a JSON value:

```
-- spelling provisional
diagram redact
  in v
  v -> split shape of Prim, Arr, Obj => s
  s.Arr -> open list -> level of v -~> collect => arr2
  s.Obj -> fields -> open list => f, ~F          -- f: a (key, value) pair
  f -> key -> split secret? of Hit, Miss => k
  ~k.Hit:  (f -> key), "" -> pair
  ~k.Miss: (f -> key), (f -> val -> level of v) -> pair
  -~> collect
  -~> collect => fs2
  ~s.Prim: s.Prim
  ~s.Arr:  arr2 -> arrNode
  ~s.Obj:  fs2 -> objNode
  -~> collect => out2
  out out2
end
```

Each level is a fixed-depth focused update — open the children,
rewrite, and rebuild through the mirror (`open list` ↔ collect,
`fields` ↔ `objNode`) — with a link at each child locus. The rebuild
per level *is* the unfold half of the fold/unfold pair, exactly as
that round's seam predicted.

And this client closes a conceptual gap between the record's two
recursion stories. Here the division is over *data*: the
sub-problems are the value's strict components, so the structural
shrink measure holds by construction — rung 1 of the ladder, free.
Recursion over data (`trees-and-recursion.md`'s ADT derivation) is
the divide flow in the special case where the division is "take the
strict components," which is why the ADT machinery could promise
termination without asking: its measure was always structural. One
construct, two measure sources; the derivation story and the divide
flow stop being separate species.

## No order among siblings

What order do a node's sub-trees run in? The answer the record's
recent rounds keep giving applies here with full force: **there is
no time among sibling instances** — the only order is data
dependence (`within-firing-effects-design.md`'s stance, one level
up). Mergesort's two half-sorts are order-free; the quadtree's four
quadrants are order-free; the parser's children are ordered *only*
because a register threads a value through them.

Three consequences, each landing on existing vocabulary:

- **A register over the divide flow's instances is ill-formed.**
  There is no drawn order of instances for it to step along — the
  same structural check that forbids a register across concurrent
  bodies (`concurrent-collect-design.md`). The cross-instance
  vocabulary is the link and its answers, nothing else. Where an
  order exists to draw (the parser's children walk), the register
  sits on *that walk*, which is where the order is drawn.
- **Traversal orders are combines, not modes.** Now, you might
  wonder where pre-order, in-order, and post-order went — every
  tree API ships them as modes of the walk. It turns out they are
  properties of the *answer*, not the walk: an in-order listing is
  the combine `leftList ++ [self] ++ rightList`, and moving `self`
  in that concatenation is the whole difference between the three.
  The divide flow has no intrinsic traversal order to configure;
  order is data, drawn in the combine. (This is a dissolution —
  don't re-propose traversal modes as configuration.)
- **Whole-tree aggregation is order-free iff its operator
  commutes.** "Count the comparisons" or "sum all leaf sizes" wants
  a collect over every instance's firings at once. The product
  round's law transfers: a reduce over an order-free extent is
  well-formed exactly when the operator is a commutative monoid
  (`product-flows-design.md`, registers-over-products). For a
  non-commutative aggregate — or a spanning IO handle, which makes
  the missing order *observable* (`effects-design.md`) — the
  linearization residue arrives here exactly as it did over
  products, and it is filed there, not solved here.

The order-freedom is also an unpriced asset: sibling instances are
independent by construction, so a parallel divide-and-conquer is a
scheduling choice, not a program change. Noted for the concurrency
row; nothing here designs it.

## The field sighting, transcribed

The one randomly-sampled recursive loop in three surveys (breadth
item 9; `real-loop-survey.md`, survey 2, sim 2 — mesa's
`cell._neighborhood`): the radius-r neighborhood of a cell is the
union of its neighbors' radius-(r−1) neighborhoods.

```
-- spelling provisional; set collect per collect-family-design.md
diagram neighborhood
  in cell, radius
  radius -> zero? -> split kind of Done, Grow => s
  radius -> minus1 => r2
  cell -> connections -> open list => nb, ~L
  nb, r2 -> level of (cell, radius) -~> collect by union => merged
  ~s.Done: cell -> asSet
  ~s.Grow: merged -> withMember(cell)
  -~> collect => hood
  out hood
end
```

Fuel measure (the radius), a link inside a walk (one per neighbor —
independent this time, no threading), and a set-union combine. The
transcription also sharpens the saturation seam by one useful
notch: mesa's dedup lives in the *value* (the union absorbs
duplicates) while the *firing structure* is still a tree —
overlapping sub-neighborhoods are re-explored, which is why the
field code is wasteful exactly as written. Dedup-in-the-value is
still a divide flow; dedup-of-firings is saturation. When
sub-problems overlap heavily, the divide form stays correct and
becomes the wrong construct *economically* — the guidance datum the
two rows' boundary wanted.

## What this feeds back to the trees row

`trees-and-recursion.md` carries an unresolved fork: does tree
iteration keep its verify-an-ordering-or-fall-back-lazy scheme for
computed-value zipper accesses, or inherit the register discipline
(every cross-firing read is a drawn crossing, checked structurally)?
This round is evidence for the second horn. The three access
directions the zipper's verifier orders are all drawn crossings
here:

- children → parent (post-order; subtree sizes) — the link's answer
  ports;
- parent → children (pre-order; depth, inherited context) — problem
  components;
- sibling → sibling (in-order threading) — a register on the drawn
  children walk.

Every program in this round that the two-layer pattern would have
verified is instead *structurally* sound: the only cross-instance
edges are drawn, and the measure replaces the cycle check. The
leaning fed back to the trees row: the zipper's computed-value
accesses want to be re-read as divide-flow wiring (answers, problem
components, walk registers), retiring dependency analysis and the
lazy fallback from that doc the way the loop-state redesign retired
them for carried state. Not decided here — the trees row owns its
own round — but the current runs one way.

## Against the philosophy

- **Example first, then generalise.** The construction *is* the
  gesture: one level written concretely (it runs on singletons as
  written), then the link declares the generalization. Same arc as
  the register's link transformation — nothing is declared upfront,
  and the intermediate one-level program is a legal program with a
  hole.
- **Inside-out.** No scope: per-instance membership is derived from
  dataflow (downstream of a problem wire), constants reach every
  instance by the prefix rule, and the level's interior is ordinary
  wires readable from outside.
- **No bottlenecks.** A three-wire problem crosses the link as three
  corresponding wires; k answers are k sibling collects and k link
  answer ports. No frame struct, no problem tuple.
- **Building blocks must build.** The +1 ladder: one level (a case
  split, no links) → fixed recursion (add a link) → variable
  recursion (a link inside a walk) → sequenced children (the walk
  gains a register) → alternatives that fail (the head becomes
  speculation's choice). Each rung adds drawn structure; no rung
  rewrites into a different construct.
- **Abstraction is the source of truth.** There is deliberately no
  derived lowering to inspect — the construct is honestly primitive
  (below, dead end 3, for why the stack encoding is not an
  admissible view).
- **One obvious reading.** The drawing is the generic level — "a
  function definition, not a trace" (`trees-and-recursion.md`) —
  and problems are firings. Ontologically: an instance *is* a
  problem, and the recursion tree is the flow's extent, minted at
  runtime, ordered only by the link edges.
- **Sample reality.** The field sighting is real but singular (the
  three random surveys' one recursive draw — survey 2, 1 of 30);
  parsing supplies everyday demand from outside the samples' domains. W stays 3 — a breadth obligation (parsers,
  planners, tree algorithms are rare-but-breaking), not a frequency
  claim. The owed domain sample (below) can re-weight it.

## Dead ends

Recorded in place, each with the reason it should not be
re-proposed.

1. **Materialising the virtual tree to reuse ADT derivation.** You
   might wonder why mergesort's split tree (or the parser's call
   tree) isn't just built as data and folded. It turns out this
   declares structure upfront — the exact thing example-first
   forbids — and it was rejected on those grounds where the limit
   was found (`tough-use-cases-design.md`, use case 3;
   `trees-and-recursion.md`; `focused-update-design.md`, dead end
   5). (Settled rejection, restated here because this doc now owns
   the construct.)
2. **Recursion by self-calling function values.** You might wonder
   why the link isn't simply a first-class function calling itself —
   the fixpoint combinator dressed up. It turns out a function
   waiting to be called has no honest visual form
   (`functions-design.md`), and the link needs none of it: its
   identity is structural (the same page, tied back), exactly as the
   write half references its own read half without a callable
   existing. (Settled rejection.)
3. **The explicit-stack lowering as a derived view.** Every
   recursion can be defunctionalized into a worklist of frames
   driven by a self-driven stream and a register — so you might
   wonder why the divide flow doesn't lower to that, keeping
   "abstraction over readable expansion." It turns out the frames
   are a packed sum ("what phase of which alt was I in, with which
   pending operands") — a tag-and-tuple minted purely to cross a
   structural point, which is the bottleneck anti-pattern verbatim —
   and the encoding linearizes an order-free tree, adding an
   ordering the program never stated. The expansion exists and is
   unreadable *in principle*, not merely in practice, so it is not
   an admissible derived view; the divide flow is primitive the way
   list iteration is. (Settled: "no lowering" from
   `tough-use-cases-design.md`, sharpened to "no admissible
   lowering.")
4. **Traversal-order modes.** Pre/in/post-order as configuration on
   the walk — dissolved above ("No order among siblings"): order is
   the combine's drawing. (Settled dissolution.)
5. **A base-case construct.** Dissolved above ("A leaf is an alt
   with no links"). (Settled dissolution.)

## Open questions

The language hasn't decided any of these.

1. **The link's spelling and anchor.** `level of xs` anchors the
   link at the problem wires and lets the answer boundary be derived
   (the unique collect output of the problem's cone) — but "unique"
   won't always hold, and a drawn (problem, answer) boundary is a
   *level boundary*, which is recognizably the functions row's flow
   skeleton with data holes (`functions-design.md`). The honest
   statement: the divide flow is the first construct that *needs*
   the level boundary, and its spelling should be decided jointly
   with that row and the textual catch-up. The examples' `diagram`
   wrapper is the provisional stand-in.
2. **Mutual recursion.** Expression/statement grammars link *two*
   levels each into the other. Structurally nothing above forbids a
   link naming a sibling level's boundary; the measure must then be
   joint across the group (one measure decreasing around every
   cycle of links), and Zig's inference warning bites hardest here.
   Unworked; wants a worked two-grammar example.
3. **The measure catalog's exact form.** Shrink and progress as
   catalog-row properties carrying witnesses — whose schema is
   `types-design.md` question 4's; the fuel check's precise
   structural statement (drawn decrement + covered zero); what the
   rung-3 warning says and where it surfaces. Decide jointly with
   the checking row.
4. **Whole-tree collects and linearization.** The commutative case
   is free (the product-round law); whether the non-commutative
   case gets an explicit linearization vocabulary or stays
   ill-formed is the same residue the product and effects rounds
   share (`delay-ontology-design.md`), and lands here whenever it
   lands there.
5. **Diagnostics for measure violations.** The left-recursion case
   shows the check can name the offending wire; what the failure
   witness looks like for shrink and fuel violations (and how it
   composes with speculation's diagnosis payloads) is undesigned.
6. **The zipper seam.** Whether the trees row re-reads
   computed-value zipper accesses as divide-flow wiring and retires
   its verifier — that row's decision; this round's leaning is
   recorded above.
7. **Evidence.** How often application code contains
   divide-shaped recursion, and in what costume (hand-rolled
   recursive functions, visitor patterns, `walk` helpers) — fold
   into the saturation row's owed domain sample
   (`open-problems.md`, Evidence owed), which is already sampling
   recursion-adjacent territory.

## What this doesn't address

- **Zipper-context iteration over data trees** — sibling/path/parent
  access on materialized structures stays `trees-and-recursion.md`'s
  own (the seam is question 6).
- **Memoized recursion** — a divide flow with overlapping
  sub-problems wants firing dedup, which is saturation's territory
  (or the served flow's seen-set/memo hinge); naive Fibonacci is the
  boundary witness.
- **Parallel divide** — sibling independence makes it a scheduling
  choice; the concurrency row owns it.
- **The decision-driven merge** — mergesort's other half
  (`tough-use-cases-design.md`, obstruction 1) still has only its
  chooser sketch; this round used `mergeSorted` as an opaque op on
  purpose.
- **Compile.** The obvious form is one named recursive JS function
  per level (problem wires as parameters, answers as returns), links
  as calls, laziness giving demanded-lane-only evaluation; stack
  depth vs CPS for deep trees is decide-in-code
  (`compile-strategy-design.md`).
