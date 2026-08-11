# The divide flow: recursion over virtual structure

Status: **adopted** (design conversation, 2026-07-23 — the joint
adoption with the function-boundary round): the link
transformation tree-shaped, per-instance membership derived,
leaves as linkless alts, and sibling-instances-have-no-time
— under the recorded anchor constraint (open question 1: the
anchor is an identity, never a value wire; the link's
correspondences are thread-species identifications).
**Revised (design conversation series, 2026-08-11)** — see
"Revision notes (2026-08-11)" at the end of this doc, which
govern where the body differs: the link's spelling lands as the
**site** (an out-port/in-port pair joined by the abstract wire,
bound by threads to the page's own fed and read wires), with the
**hypothetical** ("what would y be if x were v?") as the primary
ontology and a substitution law for nested frames; mutual
recursion is re-founded by inlining (level labels dissolve); the
**termination/measure discipline is retired** (no termination or
soundness checking); and the cyclic back-edge surface is worked
and **rejected**. The open
questions keep their own status where marked; nothing is
implemented. This is the round the
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

*(A consistency pointer, added 2026-08-04: read the `level of xs`
spelling above with open question 1's diagnosis in hand — it uses a
value wire by identity, the `prev` disease, and the recorded
refinement is that **the link is the thread, tree-shaped**, its
correspondences thread-species identifications across realms. The
thread ergonomics round has since made the same correction for the
linear case — `step of` replaced by `@` thread ink,
`iteration-with-state-design.md`, "The ergonomics round, opened
(2026-08-04)" — so the cross-frame role here belongs to thread ink
too; the example's spelling predates that and stands as
provisional.)*

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
there is no drawn guarantee that the chain of demanded links is
finite — the measure discipline that once stood here is retired
(Revision notes, 2026-08-11), and a program whose demanded chain
never bottoms out diverges, as it would in any host language.

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

## Termination: retired

This chapter carried a three-species measure discipline
(structural shrink / cursor progress / drawn fuel, with warned
trust as the floor), adopted 2026-07-23. **Retired (design
conversation, 2026-08-11): the language does no termination or
soundness-of-recursion checking.** The discipline was a
distraction from the construct itself, and its floor was already
warned trust — no program was ever blocked — so nothing semantic
is lost; a diverging recursion diverges, exactly as in the host
language. (Recorded so the discipline isn't re-derived: its best
exhibit was reading left recursion — immediate and indirect — as
a progress-measure violation; that diagnostic goes with it. See
Revision notes, 2026-08-11.)

## Quadtree build: the non-list example

The owed example — a tree from *use*, not from data. Problem: a set
of points, a square region, and (we will discover why) a depth
budget. Build the quadtree: a region with few points is a leaf;
otherwise split the region into four quadrants and recurse.

First, watch the obvious "it gets smaller" intuition fail. "The
sub-problem has fewer points" is *false*: if many points are
coincident (or merely fall in one quadrant), one child can inherit
every point of its parent. Point count does not decrease, and a
divide flow trusting it would recurse forever on ten identical
points. Field quadtrees know this: real implementations bound
depth. So the problem honestly carries a budget:

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

- **The budget is honest program data.** Nothing here shrinks a
  list: the division splits a *region*, the data (points) may not
  shrink at all, and real quadtrees bound depth — so the budget and
  its drawn `minus1` are part of the program, not checking
  apparatus. (The measure ladder that once read this as its rung 2
  is retired.)
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

Two things this program demonstrates that the fixed-arity examples
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
payload-composition residue. *That round now exists*
(`failure-payloads-design.md`, exploration) and relocates the
reason: the inventory fixpoint over a link cycle is monotone on a
finite domain (minting sites are drawn), so inference is
well-founded here — Zig's breakage is type-level genericity and
does not transfer. The declared set survives with its role changed
from necessity to boundary summary: the link is a reuse boundary,
its inventory belongs in the principal property signature, and
*pinning* it by declaration is a checked documentation choice
(too-small declared set = clash with the extra site as witness),
not a demand.

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
sub-problems are the value's strict components. Recursion over data
(`trees-and-recursion.md`'s ADT derivation) is the divide flow in
the special case where the division is "take the strict
components" — the derivation story and the divide flow stop being
separate species. (The measure commentary this paragraph once
carried is retired with the discipline.)

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

A drawn budget (the radius), a link inside a walk (one per neighbor
— independent this time, no threading), and a set-union combine. The
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
edges are drawn — drawn crossings, no dependency analysis. The
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
   lowering." The 2026-08-11 cyclic exploration adds an independent
   confirmation from the representational side — see Revision
   notes, "The cyclic surface, worked and rejected.")
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
   wrapper is the provisional stand-in. *The boundary round now
   exists* (`function-boundary-design.md`, exploration, revised in
   its first design conversation): a boundary is a remembered cut
   whose ports are the crossing wires, and the link **stands on
   that substrate without becoming a call** — instancing,
   membership, and the measure are defined once over the boundary
   object, but the link stays its own page-local, anonymous
   construct (recursion never routes through a named function; the
   recorded reasons are the guard family's register symmetry and
   the extract-to-recurse cliff). `level of` stays this round's
   spelling; mutual recursion gets page-local *level labels* (the
   loop-label precedent), not function names. If adopted, the
   anchor question is answered by the substrate and what remains is
   the label's spelling, jointly with the textual catch-up.

   **Constraint recorded (design conversation, 2026-07-23): the
   program-level anchor must be an identity — a level label or the
   boundary itself — never a value wire.** The conversation
   diagnosed `level of xs` as the `prev` disease
   (`iteration-with-state-design.md`, "Why not a `prev(x)`
   operator?" and its identity-vs-value account): `of xs` uses a
   value wire *by identity, in a value position, unconsumed* —
   real Kramer standing for the Kramer-identity. The decisive
   argument that no value-based anchor can work: imagine recursing
   on a value that starts at `0` — "the cut point at 0" identifies
   nothing, because innumerable wires in a graph carry `0`. What
   the link needs is wire/boundary identity, and identity-use must
   be visually distinct. The refinement that follows: **the link
   is the thread, tree-shaped** — its correspondences are
   thread-species identity assertions ("subA in this realm is the
   xs of a child realm"; "the child's sorted is this realm's
   sortedA"), each wire pair identified once (feed-the-next or
   read-the-answer-back, never both — the thread's
   overspecification rule, one level up). The realms reading is
   affirmed as the right track: recursion frames are realms, one
   wire identity exists across realms, and that is what lets a
   level be referenced without a bottleneck. One survival for the
   editor: *selecting a value wire to cut the graph* may be a fine
   interactive **editing gesture** for creating a level — but it
   is a gesture that resolves to a boundary identity at creation;
   the stored program never anchors on the wire.

   **Refinement (design conversation, 2026-08-04): no boundary at
   all.** The earlier lean ("the divide flow is the first construct
   that needs the level boundary") is overridden: isolating a node
   set as *the recursive function* is unnecessary complexity
   imported from code reuse. Threads identifying points as the same
   across frames, plus a **source of frames**, is enough to make
   code recursive — the recursive "function" is whatever is
   downstream of the link, derived, exactly as the loop body is
   whatever is downstream of the uncollect. What `level of` got
   *right* was needing no drawn boundary; what it got wrong was
   only the wire-misuse (one wire standing for its value in this
   frame and another frame at once — the thread's role). What the
   link irreducibly remains is the **frame source**: its firings
   mint child realms on demand (the tree-shaped sibling of
   uncollect's data-driven frames and `open self`'s self-driven
   ones), and the node is what individuates children — the
   problem-thread and answer-thread that mean the *same* child are
   grouped by anchoring at the same link, which no set of separate
   threads could state alone. The tricky remaining part, named
   honestly: specifying where the frames come from — the frame
   source's form is the open edge, jointly with the thread
   ergonomics round.

   **Closing the spelling (same conversation): `level of` is
   retired.** The construct — general recursive feedback into a
   program, the link — is alive; the spelling is gone. The thread
   is the mechanism for everything that needs to show
   correspondence across frames — registers across iterations, the
   link across levels — with the note that this does not make
   threads part of all iteration: list flows support many kinds of
   iteration with no thread anywhere. A replacement spelling using
   the thread vocabulary (`@`) is owed to the textual catch-up
   round; the examples above stand as the record of the design,
   their `level of` lines to be read as the retired provisional
   form.

   **Closed (design conversation series, 2026-08-11): the
   replacement spelling exists — the site.** See "Revision notes
   (2026-08-11)" below: the link is drawn as an out-port/in-port
   pair joined by the abstract wire, its threads anchored at the
   page's own fed and read wires. What remains owed is only the
   textual catch-up's final glyphs (provisional, as all spellings
   are).
2. **Mutual recursion.** Expression/statement grammars link *two*
   levels each into the other. **Re-founded (2026-08-11 — see
   Revision notes below): mutual recursion reduces by inlining.**
   In the no-boundary world a single-use "call" is just wiring, so
   within a strongly connected reference group only the back edges
   are sites, and most mutual recursion is single recursion plus
   organization; the reuse residue (both members named and reused
   from outside) is two remembered cuts over one node set. The
   joint-measure account that previously occupied this question's
   worked section is deleted with the measure discipline.
3. **The measure catalog's exact form.** Retired with the measure
   discipline (2026-08-11) — no termination checking, so no measure
   catalog. (The catalog-schema round's general admission rule is
   unaffected; it simply has no measure family to admit.)
4. **Whole-tree collects and linearization.** The commutative case
   is free (the product-round law); whether the non-commutative
   case gets an explicit linearization vocabulary or stays
   ill-formed is the same residue the product and effects rounds
   share (`delay-ontology-design.md`), and lands here whenever it
   lands there.
5. **Diagnostics for measure violations.** Retired with the
   measure discipline (2026-08-11).
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

## Revision notes (2026-08-11): the site, the hypothetical, and the retirements

A design conversation series worked the link's surface to a
landing. Where the body above differs, these notes govern.

### The hypothetical is the ontology

A recursion frame is a **hypothetical**: *what would this wire be
if that wire were something else?* The page's own reading of the
link ("sortedA is what this page computes for `sorted`, when its
`xs` is `subA`") was always this sentence; the revision makes it
the primary framing. Frames are hypothetical value-assignments —
not scopes, not regions; the earlier "realms" vocabulary survives
as a synonym.

### The site: the link's drawn form

The link is drawn as a **site**: an **out-port** (the problem
leaves the page) and an **in-port** (the answer arrives), joined
by the **abstract wire** — the same dashed "this depends on that,
through something not drawn here" annotation the late-bound round
adopted (`out p ... in q`, `late-bound-operations-design.md`).
One object, deliberately not a sibling glyph. The site's threads
bind it to the page's own wires:

- the **feed thread** ends at the out-port and starts at the wire
  where the page itself is fed;
- the **read thread** ends at the in-port and starts at the wire
  where the page itself is read (the answer wire).

`served-flow-design.md` had already identified this shape from
the other end ("the recursive provider: the link, in exchange
costume"); the site is that identification drawn. The link
**stands on the port-pair substrate without becoming a call** —
no name, no extraction, no boundary; the never-a-call stance and
its recorded reasons are untouched.

**Individuation.** A child is one dashed-connected group of
ports: mergesort's two children are two disjoint groups; a
3-in/1-out child is three out-ports dash-wired to one in-port.
Minted port identity supplies what "no set of separate threads
could state alone." An in-port with no dashed path from any
out-port is a hypothetical whose answer doesn't depend on what's
varied — witnessed, not guessed.

**The anchor rule, and its reason.** *Feed the child where you
are fed; read it where you are read.* Any other placement is an
observably different program: moving the read point along the
would-be return path slides which frames' pending side-reads sit
on the consumer's demand path (worked with explicit unfoldings —
the factorial variant whose read anchor sits one node later
computes 0 where the intended program computes 6). The rule is
forced by the ontology: the child is *this page, asked again*,
and asking a page means reading its answer — the same answer the
outer consumer reads. A drawing whose return read targets a
different wire than the page's own consumers is witnessed
(self-similarity violation), not reinterpreted.

**Minimal delimitation.** The lambda calculus gets recursion from
a bare cycle because application separates function from argument
— Y has a delimited term to point at. Dataflow deliberately does
not (no forced function boundaries), so recursion must *add*
delimitation — and the minimum is exactly two wire identities:
the fed wire and the read wire. Not a region, not a boundary.
The derived "recursive function" is whatever is downstream of the
fed anchors, exactly as a loop body is whatever is downstream of
the uncollect.

**Environment is derived from the hypothetical.** What varies in
a child is the downstream cone of the fed anchors; everything
else is shared from the minting frame. The per-wire
freeze-vs-redo decision the boundary round records for reuse cuts
does not arise for recursion — the hypothetical answers it.

### Nested frames: the substitution law

> **A site's child frame is the minting frame plus a substitution
> at the fed anchors.** The varied part is the fed anchors'
> downstream cone computed **with sites opaque** (a site
> contributes one dependency edge, out-port to in-port, never the
> child's wires); every wire outside the cone is shared from the
> minting frame.

Nested hypotheticals therefore compose like nested substitutions
— deterministically, because instances form a tree with unique
minting parents ("the instances form a runtime tree"). Checked
against: nested same-anchor sites (the Ackermann shape),
overlapping cones (two sites varying different inputs of one
shared wire), and the alternating frame tree of mutual recursion.
This is capture-avoiding substitution falling out of copy-paste,
with no scope construct anywhere — inside-out holds.

Two coherence witnesses come with the law:

- **Read-downstream-of-feed.** The in-port must depend on the
  out-ports through the page — the abstract wire's derivable
  check.
- **Fed anchors must be mutually independent.** Feeding both x
  and a wire in x's cone over-determines the child (hypothetical
  value vs recomputed value). The feed-side cousin of the
  thread's overspecification rule; witnessed, not repaired.

### Mutual recursion, re-founded

Most mutual recursion is single recursion plus organization. In
the no-boundary world a single-use "call" from A to B is just B's
nodes on the page (copy-paste semantics), so within a strongly
connected reference group everything except the back edges is
plain wiring, and **the irreducible content of mutual recursion
is: the group's back edges, each an ordinary site**. The V/O JSON
grammar collapses to one page with one self-site anchored at the
composite's interface.

The reuse residue — both members named and reused from outside —
lands on a waiting piece of `function-boundary-design.md`: "a
file's node set carries any number of remembered cuts over it."
One node set holds the mutual computation; cut-A and cut-B are
two views of it. Recursion never routes through a named function;
both names exist for reuse; unreached parts of a pasted composite
stay dead under laziness.

**Level labels dissolve.** A site's threads anchor at drawn wires
— interface wires after inlining, interior anchor pairs in the
residue case. Nothing needs a name that isn't a wire. (This
retires the page-local label vocabulary, and with it the last
reference to a "boundary substrate" for recursion.) Interior
anchors are also exactly where inference would have had nothing
to grab — no external consumer pins an interior answer wire —
which is why the site's *drawn* (feed, read) pairing is
load-bearing at mutuality, not decoration.

The joint-measure rule a prior worked section built here (the
strongly-connected-group unit, one quantity per group, the
indirect-left-recursion witness) is deleted with the measure
discipline below. Its structural observation — group-level
properties are invisible to per-level inspection — survives as
history; nothing checks them now.

### Termination checking, retired

Decision (2026-08-11): **the language does no termination or
soundness-of-recursion checking.** The three-species discipline,
the measure catalog, the joint measure, and the violation
diagnostics are deleted as a distraction; the discipline's floor
was already warned trust, so no program's legality changes. A
diverging recursion diverges, as in any host language. (Recorded
so the discipline isn't re-derived; its best exhibit was reading
left recursion — immediate and indirect — as a progress-measure
violation, and that diagnostic goes with it.) This retirement
does **not** touch the register's productivity law
(`iteration-with-state-design.md`, "every cycle crosses a Delay")
— that is well-formedness, not termination: a within-firing
self-dependence is meaningless, not merely non-terminating.

### The cyclic surface, worked and rejected

A back-edge (cyclic-graph) authoring surface for recursion — feed
a value back into an earlier wire and rerun until a case stops
cycling — was worked across several rounds and is **rejected**,
for three independent reasons, recorded so it isn't re-tried:

1. **The clockless latch.** A two-source merge is a stateful
   update in a diagram that has no time ("within a firing there
   is no time"); its lawfulness in the record always came from an
   owned order — the register's driving flow is the clock that
   clocks the latch. The raw cycle has no flow, and at the first
   +1 step (a second carried variable — Fibonacci's swap) the
   simultaneity of the updates is unstated: the dynamic-hazard
   problem of an unclocked circuit. A notation that breaks at its
   first +1 fails the building-blocks-must-build test. (The
   dataflow tradition the cycle appeals to — Lustre, hardware —
   requires the unit delay on every cycle for exactly this
   reason.)
2. **Crossing-placement observability.** For the non-tail double
   cycle (descent edge plus return edge), where the crossings
   fall is observable — the window-slide unfoldings behind the
   anchor rule above (6 vs 0) — so a bare cyclic graph
   under-determines the program; the disambiguating information
   is precisely what the site draws.
3. **The branching collision.** One copy of the wires cannot name
   two children: mergesort's fed wire would need three sources
   and its answer wire two readers with no pairing. (This
   independently confirms dead end 3's verdict from the
   representational side.)

What the exploration salvaged: the anchor rule and the
minimal-delimitation thesis, both worked *on* the cyclic form
before the retreat. Where the cyclic programs land: tail-shaped
loops were never recursion — they are the existing iteration
vocabulary (`open self` + registers + collect-until, the flow
supplying the owned order); a **linear non-tail** recursion's
return phase dissolves into a fold over the descent flow (a
descent loop plus a collect — the register-plus-sibling-collect
shape the compiler already has); **branching with an order-free
combine** is the drawn frontier (saturation's precedent: the
worklist is the lowering of the flow back-edge); **structured
combines** (mergesort's merge, per-child ASTs) are the site's
home — the cyclic form could proceed only by packing frames into
a stack, the bottleneck anti-pattern by name. Deferred, not
rejected: a synchronizing flow-uncollect on the fed wire that
would give the cycle a lawful clock — parked as a lot of work to
get right, not disproven.

### The recursion taxonomy

Three species, one form each: **iteration** (tail-shaped, carried
state — flow-driven, the flow owns the order); the **structural
walk** (`trees-and-recursion.md` — structure that exists); **pure
recursion** (pending work, the frame tree — the site and the
hypothetical). "Is this program tail recursion?" is not a
question here; a loop is drawn as a loop.

### Still open after this round

The **frame source**: the site's firings mint child frames on
demand — the form of "where frames come from" (its relation to
`open self` and the uncollect's data-driven frames) remains the
open edge, jointly with the thread ergonomics round. And the
textual catch-up owes final glyphs for the site and its threads;
every spelling in these notes is provisional.
