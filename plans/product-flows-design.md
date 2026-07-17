# Product Flows

Status: exploration — a proposal with a recorded lean, not adopted. Not
implemented. Assumes the `first-class-ports-design.md` migration (Cross is
a flow node with ports, like Join).

This document introduces **Cross**, a construct for two flows that are
combined asymmetrically — one nests inside the other — but *independently*,
where the inner flow's shape does not depend on the outer element. Call
that the **mutual-constant** relationship. Cross supersedes part of
`time-travel-programs-design.md`'s disposition 4 and closes its open
question 4; correction notes are placed there.

It also works Cross's positional sibling, the **aligned product (zip)** —
pairing two flows of the *same* extent by position rather than every firing
with every firing — together with its value form, the multi-wire collect
(the table). See "The aligned product (zip)" below. And it works how a
**register folds over a product** (open question 5): along one axis, fibered
over the rest — the reduce-along-an-axis shape — not over the whole
order-free cube. (Which flow fixes that axis reopened an ontological
question about Delay itself.) See "Registers over products" below.

Terminology: **uncollect/collect** for open/close (the code still says
Open/Close). Working name for the new construct: **Cross** (candidates
under Naming).

## The program that demands it

Two lists, uncollected side by side, neither derived from the other;
elements combined; two terminations in opposite orders:

```
listX -> open list => x, ~x
listY -> open list => y, ~y
x, y -> add => s
s -~> collect => sPerY -~> collect => out1    -- ~x inner, ~y outer
s -~> collect => sPerX -~> collect => out2    -- ~y inner, ~x outer
```

`out1` is, per y, the list of x+y over all x; `out2` is the transpose.
The compile-strategy round settled how this *runs* without duplicating the
user's `add`: the values form an n×m table indexed by iteration points,
points are order-free, and each consumer traverses the shared table in its
own order (`compile-strategy-design.md`).

The gap is that the *language* can't yet say what the runtime is doing.
The natural spelling — pick one orientation as primary, build that
nesting, and let the other consumer read it transposed — wants a
**transpose operation to insert**, and there isn't one. The design record
declined a list transpose because nested lists can be ragged. But these
nested lists *cannot* be ragged, precisely because neither flow inherits
from the other. The record's reason for declining transpose is absent
exactly here, and the language has no way to notice.

Worse, the sanctioned completion makes the situation unrecoverable.
Completing by Incorporate — capturing `listX` into `~y` and uncollecting
it there — produces a program that *reads as dependent nesting*:
structurally indistinguishable from an inner flow whose source is computed
from the outer element. The mutual-constant relationship the author drew
(siblinghood!) is erased by the very translation meant to preserve the
meaning. By "abstraction is the source of truth," completion should insert
the most abstract operator that is true of the program, and for sibling
opens Incorporate is not it.

Two recognitions follow:

1. **The missing transpose is commute.** Commute already swaps adjacent
   nesting levels, carries no value ports, and is quotiented by
   naturality. `commute(list, list)` was undefined because of raggedness;
   *product-ness is exactly the condition under which it is defined*. This
   is a new row in the commute-variant taxonomy
   (`lazy-stream-commute-design.md`), gated on provenance rather than on
   kind.
2. **Siblinghood at authoring time is the witness of independence.** Two
   uncollects where neither derives from the other are mutually constant
   *by construction* — each flow's shape is invariant of the other's
   element. The program contains the independence fact structurally; the
   job is to keep it, not to infer it.

## The construct

**Cross** is a flow operation in the same species as Commute and the
binary Join: a node with flow ports and **no value ports**.

- **Inputs:** two flows whose contexts are incomparable (siblings,
  possibly at a distance).
- **Outputs:** the same two flows, now nested — pairwise corresponding,
  barrier-style.
- **Demand:** the operands are **mutually invariant** — neither operand's
  firing structure varies with the other's element. Concretely: neither
  flow's source, nor anything determining its firings, has the other flow
  in its flow-variable set. This is checkable with existing machinery —
  the flow-variable set is the annotate pass's per-node fact
  (`compile-strategy-design.md`) — and the demand is a property in
  `types-design.md`'s sense, with a witness (the node that introduced the
  dependence) when it fails.
- **The law of the crossed flow:** *the crossed pair fires once per pair
  of operand firings; each axis's element rides unchanged.*

Consequences of the law, as short theorems:

1. **Rectangularity.** Per outer firing, the inner traversal is the same
   sequence of firings (from the law plus the invariance demand). Nested
   collects over a crossed pair can never be ragged.
2. **Commute is total on crossed pairs.** The transposed orientation is
   the same product read the other way; nothing can fail. `commute(list,
   list)` enters the commute table with this guard: defined iff the
   nesting is a product.
3. **Kinds are unchanged downstream.** A crossed pair presents as ordinary
   nesting to everything below it — collects, joins, the any-list rule —
   so no downstream construct needs a product special case.

Because Cross has no value ports, its value-level shadow is the identity,
and the naturality quotient applies (map-then-cross = cross-then-map).
That is the admission test for completion's insertion inventory
(`time-travel-programs-design.md`, "completion inserts only operations
whose value-level shadow is the identity") — **Cross is insertable**,
faint, like an incorporate or a commute chain.

Values cross the boundary by the ordinary invariance rule, as with every
other flow node: an axis's element is readable at the product's points
because the product context is deeper than each axis (see "The context
model"). No packing, no transport ports — the no-bottleneck shape.

## Asymmetric or symmetric: the one real fork

There are two ways to hold the construct, and the choice is closer to a
spelling than a semantics — worth recording why.

**Option A — oriented Cross plus lawful commute.** Cross takes (outer,
inner) operands, like Join. Its output is ordinary oriented nesting
carrying the product guarantee. The transposed reading is one Commute node
away (theorem 2). Completion for the two-lists program inserts one Cross
in a canonical orientation and one faint Commute for the chain that reads
the other way.

**Option B — symmetric product, order at the consumers.** The
mutual-constant relationship is genuinely symmetric, and the product's
points are order-free — the language-level twin of the compile's
point-indexed table. Under B, Cross commits no orientation; each consuming
operation supplies its own. The suppliers are all *already asymmetric*: a
collect chain's sequence orders its traversal; a Join's (outer, inner)
operands orient a flatten. Orders live at terminations — exactly how
`time-travel-programs-design.md` reads collects, as the authored
commitments. No Commute is ever inserted.

The tension with Option B: it relaxes the letter of the no-time-travel
rule ("nesting established at construction"). The defence is the rule's
own purpose, the same one the time-travel document borrows from Koka: the
rule protects *one reading per program*, and for a product the two
orientations are confluent — that is what the invariance demand means — so
the non-pick is unobservable and principled, not sloppy. The letter is
relaxed exactly where it is provably meaningless.

The relationship between the options: A = B plus a stored orientation plus
a commute spelling. Nothing is lost in either direction — a Cross node in
the graph keeps the independence fact, so re-reading it the other way is
always recoverable (unlike the Incorporate lowering, which is genuinely
lossy). B is the more abstract description; A-oriented forms are its
derived views, one per consumer chain — the familiar lens shape: store the
abstract thing, derive the committed thing, free and downward.

**The lean: represent A, read B.** The stored node carries an orientation
(chosen by completion heuristics when inserted, or by the author when
drawn), because A's output is ordinary nesting and *nothing downstream
needs to change*: collects, joins, provenance walks, and the compiler all
consume nesting they already understand, and the transposed consumer reads
through a Commute that theorem 2 makes lawful. B survives as the
recognized reading — "these two orientations are the same product" — a
statement the Cross node itself witnesses, available to the editor, the
checker, and any future recognize-family entry, without a representational
move. If experience shows consumers routinely fighting the stored
orientation, promoting B to the representation is a local change (the node
stops carrying an orientation; consumers already supply their own).
Starting at B would instead require teaching every consumer about
unordered contexts on day one. Foundations first, but smallest true step.

## Partial products: filtering, in three regimes

The construct also answers the raggedness question it was partly motivated
by — what happens when someone filters one of the flows and then wants
both orders. Filtering splits into three regimes, distinguished by the
same flow-variable sets that gate the invariance demand:

- **Filter an axis by its own element** (predicate on y alone,
  independent of the cross): the filtered flow's shape is still invariant
  of `~x` — the same rows survive for every x. Still a product, still
  crossable, still transposable. Rectangular, just smaller.
- **Filter per point** (predicate on both x and y): this does *not* break
  the product. Per-point absence is *data at the point* — a hole in the
  table — not a change in the table's shape. Both traversal orders remain
  well-defined: they visit the same point set and skip the same holes.
  Each consumer chain absorbs the per-point option flow in its own
  orientation (an ordinary join-with-option-inner, after that chain's
  orientation). The two collected outputs are ragged *as data*, and they
  are not transposes of each other — they are two legitimate readings of
  one partial table, and nobody claimed otherwise.
- **Shape depends on the other flow's value** (the inner *source* is
  computed from the outer element): no product exists. This is true
  raggedness; the nesting is dependent; one order is meaningful and the
  transpose is not. An attempt to cross such flows — or to collect a
  dependent nesting in the reversed order — fails the invariance demand,
  with the dependence-introducing node as the witness.

The first two regimes keep both readings; the third keeps one; and the
checker tells them apart without new machinery.

## What this changes in the completion

`time-travel-programs-design.md` is revised in two places; notes are
placed there pointing here.

**The insertion inventory.** Cross joins it, and **replaces Incorporate
for flow–flow nesting** (the NEST_WITHIN family). The sibling-opens fix —
worked example 1's `INCORPORATE(listA)` — becomes a Cross insertion: the
more abstract operator that is true, preserving the mutual-constant fact
instead of erasing it, and leaving the program open to a later transposed
consumer without re-completion.

Incorporate is not retired. It survives for what remains its job —
bringing a *value* into a flow context (the CAPTURE family), which
auto-capture already performs silently. Only its misuse for nesting two
sibling opens is corrected to Cross. Note the directed constraints still
do their work: the collect order in example 1 still determines which
orientation the inserted Cross carries.

**Disposition 4 splits, and mostly dissolves.** Crossed terminations over
mutually invariant sibling opens — the worked example 4 shape — stop being
contradictory: completion inserts *one* Cross (plus, under Option A, one
faint Commute for the reversed chain), both chains read the same product,
and the "rescue" the document worried about (duplicating opens per
consumer path, doubling iteration structure behind the user's back) is
never needed — nothing is duplicated, neither structure nor work. Open
question 4 closes by dissolution. What remains genuinely contradictory:

- **within-chain cycles** — a single termination chain whose own
  constraints force A inside B and B inside A; no reading exists for that
  output;
- **reversed order on a dependent nesting** — the third filtering regime;
  no product exists to transpose;
- **bundle mixing** — untouched, as ever; the missing fact there is an
  execution, not an ordering.

This supersedes the compile-strategy document's earlier per-chain
completion (which resolved disposition 4 by duplicating opens), and is
better on every axis that one paid on — no duplicated opens in the
program, no duplicated work at runtime, one faint node instead of
per-chain insertion sets.

## The context model

Bundle provenance's context structure gains its second non-tree feature
(the first: partial-collect's subset lattice at bundle steps). A Cross
introduces a **product context**: a context with two parent axes. The
comparability order becomes a genuine poset:

- each axis context ≤ the product context;
- the two axis contexts remain incomparable to each other;
- everything below the product nests as usual.

The rules that consume the order generalise verbatim: a combining node
demands its operands' contexts lie on one chain of the poset (an axis
value and a product value combine at the product); the memo's reuse rule —
stored context ≤ requesting context — is unchanged as stated; `deeper`
becomes "least upper bound, if one exists." Per-wire context paths stay
unary facts; the product segment records its axis set, the same move the
partial-collect document made for cell sets.

## Compile

The compile target is the point-indexed table of
`compile-strategy-design.md`'s revised two-context section — the Cross
node is that mechanism's representation, and the mechanism is the node's
runtime. The essentials from the compile side:

- A node whose flow-variable set spans a product's axes memoises **at the
  product context**, as a point-indexed structure — one entry per point,
  computed on first force by whichever consumer arrives first.
  User-written computation runs **once per point**, regardless of how many
  consumers traverse in how many orders. (This honours the sharing
  convention: sharing is opt-in via binding, and a bound node's work is
  not duplicated.)
- **Whole-table first.** For the eager fragment, one lazy whose thunk
  builds the full table in the stored orientation, with the transposed
  consumer indexing it, is fully adequate — eager collects always consume
  their flow completely, so per-cell granularity buys nothing yet. Under
  stream kinds the table refines to per-cell `Delayed` cells (a 2D grid —
  Shape C over a product), where partial consumption exists to exploit.
- The internal build order of the table is unobservable for pure values —
  not a semantic pick, no faint rendering needed. (Under Option A it
  naturally follows the stored orientation.)
- **The honest cost is retention, not duplication.** Two traversal orders
  of a product cannot both stream ephemeral values off a single
  computation; whatever the slower consumer hasn't reached stays live, in
  the worst case the whole table. For the eager fragment this is bounded
  (the table dies with the last consuming thunk); for streams it is the
  recorded retention axis, amplified — grid cells don't get the free
  cursor-GC that chain cells do. Recompute-per-consumer remains available
  as a future *opt-in* cost policy, never the default.
- **Effects:** once-per-point is also the right effect semantics when
  effect kinds arrive — each effect happens once — but the *order* of
  points remains schedule-dependent (the first-forcing consumer sets it).
  The compile-strategy document's open question 1 (effects × divergent
  consumers) covers this unchanged: an effectful node's ordering should be
  directed by its effect flow, or clash.

## Relation to the rest of the record

- **The product barrier family.** The no-bottleneck principle names the
  concurrent join as the product barrier for async — and the concurrency
  narrative already says of fork-join that "forked flows are mutually
  independent from construction, so join is pure synchronization." Cross
  is the same species' iteration citizen: mutual independence by
  construction, pairwise-corresponding flows through a barrier, no
  packing. Whether the async concurrent join and Cross are two kinds'
  faces of one construct is worth asking when the barriers get their Expr
  round (they share the first-class-ports prerequisite).
- **Not the list monad.** The record already rejected sequencing two lists
  in the list monad for this program, and Cross is not that: the monadic
  outer product *linearises* — one flat sequence in a canonical order,
  replacing the author's two readings with a third — whereas Cross
  flattens nothing and orders nothing the author didn't. A join applied to
  a crossed pair *is* available, and honestly: flattening a table requires
  choosing row- or column-major, and Join's (outer, inner) operands state
  the choice.
- **Recognition.** An Incorporate-shaped nesting whose inner source is
  invariant of the outer flow is a product that wasn't drawn as one.
  "Collapse to a Cross" is a recognize-family catalog entry — upward,
  partial, earned — and it is what makes old-style completions and
  hand-drawn dependent-looking programs upgradeable.
- **The visual side** (out of scope here, noted for the record): iteration
  already draws 2D — position across, computation down — so a product of
  two iterations is naturally a plane's worth of structure. How that
  renders is the visual repo's question; the representation here is what it
  would render.

## Against the philosophy

- **Example first, then generalise.** The two-lists program is the
  concrete gesture; Cross is the identified relationship, inserted or
  drawn after the value computation exists. The construct never requires
  declaring the product upfront — it is read off siblinghood.
- **Inside-out / cases as values.** No scopes; the table is structure you
  flow through; elements arrive by visible wires.
- **No bottlenecks.** Cross is a barrier with pairwise corresponding flow
  inputs and outputs and no value packing — the principle's own shape,
  extended to iteration.
- **Building blocks at the programmer's abstraction level.** "All pairs of
  these two lists," read as a table, is a programmer-level concept (every
  spreadsheet user holds it); the incorporated loop-in-loop was the
  plumbing-level encoding of it.
- **Foundations before features.** The construct was admitted by a forcing
  program, not by generality hunger; the fork (A vs B) is recorded with
  its lean and its exit.
- **Abstraction is the source of truth.** The product is the truer
  description; oriented nestings are derived views; the Incorporate
  lowering — which destroyed the abstraction — is replaced by an insertion
  that keeps it. Derivation (committing an orientation) is free and
  downward; recognition (product from dependent-looking nesting) is earned
  and upward.

## Smallest first step

Ordered so each piece is testable in `Main.res` style; assumes the
first-class-ports migration (Cross is a flow node with ports, like Join).

1. **The invariance fact.** Per-node flow-variable sets in the annotate
   pass (needed by the compile rebuild anyway); the mutual-invariance
   check as a function of two flows, with witness.
2. **The Cross node** (Option A shape: oriented, flow-only), plus
   theorem-2 commute legality over it. Compile via the whole-table lazy;
   tests: the two-lists program with both orders, values compared against
   hand-built tables; an outer-stmt/golden test pinning that `add`'s work
   appears once.
3. **Completion inserts Cross** for sibling opens — replacing the
   directed-Incorporate rewrite in `time-travel-programs-design.md`'s
   smallest first step 2, which should be built straight to Cross rather
   than built twice. Tests: example 1 completes to a Cross; example 4
   completes to Cross + Commute; a dependent-nesting reversal clashes with
   the right witness.
4. **Partial products** ride the partial-collect/filter work: a per-point
   option absorbed per-orientation; test both readings of one filtered
   table.

## N-ary products: the three-list example (open question 3, worked)

Two axes never forced the poset to do any work: two axes have exactly one
product and one transpose, so every question the context model raises is
answered trivially. Three lists are where the machinery first has to earn
its shape — which is why open question 3 asked for a concrete three-list
example before committing to "flat axis sets." Worked below: the
presumption holds, and the example exercises three things the two-axis case
could not.

The program — three lists uncollected side by side, none derived from the
others, elements combined:

```
listX -> open list => x, ~x
listY -> open list => y, ~y
listZ -> open list => z, ~z
x, y, z -> f => s
```

`s` is one value per (x, y, z) triple — a 3-axis product, an n×m×p cube. A
consuming collect chain nests the three terminations in *some* order; there
are 3! = 6 orders, and they read the cube along its six axis permutations
(the two-axis pair of transposes, generalised).

**Associativity: the nesting tree is representational, the axis set is the
denotation.** Cross is binary, so a three-axis product is authored by
nesting — `cross(x, cross(y, z))`, or `cross(cross(x, y), z)`, or a flat
three-way cross if the surface offers one. (Prefix `cross(…)` throughout
this section is schematic exposition, not the textual form — Cross's
textual spelling is owed, open question 1.) By the law (fire once per tuple
of operand firings, each axis rides unchanged) and mutual invariance, all
three build the *same* cube: the same point set and the same top context
{X, Y, Z}. So the denotation is the **flat, order-free axis set** — exactly
the presumption, and exactly the move partial-collect made for cell sets.
Many authoring paths converge to one product; the reading is the product,
not the tree that built it ("one obvious reading per program, however many
authoring paths converge to it").

Where the nestings *do* differ is which **intermediate** products they
construct. `cross(x, cross(y, z))` builds a {Y, Z} context on the way to
{X, Y, Z}; `cross(cross(x, y), z)` builds {X, Y}; a flat three-way cross
builds neither. This is not a wart — it is the author naming a sub-product.
If they wrote `cross(y, z)` as a sub-expression and a consumer collects over
just y and z (holding x), the {Y, Z} context is a real, wanted thing; if
they wrote a flat cross, they did not ask for it and it is absent. This is
the graceful-expansion shape: the flat product is the simple case, and
naming a sub-product is *adding structure* to reach a sub-product consumer,
never a rewrite into a different construct.

**The poset is the subset lattice of the axis sets actually constructed** —
the cell-set refinement's shape (`bundle-provenance-design.md`, "subset
lattice of constructed sets, not a tree"), confirmed a second time and now
by a different construct. Not a tree, and not the full powerset of
{X, Y, Z}: only the axis sets some Cross built. Comparability is
containment; a combining node demands its operands lie on one chain, and
`deeper` is "the least upper bound among constructed sets, if one exists" —
the two-axis rule verbatim.

The three-list example is the first place that "if one exists" bites.
Suppose someone builds `cross(x, y)` = {X, Y} and, separately,
`cross(y, z)` = {Y, Z}, and never a common super-product. A value at {X, Y}
and a value at {Y, Z} share axis Y but are incomparable, and there is **no
constructed common superset** — {X, Y, Z} was never built. Combining them
would demand a value per (x, y, z), i.e. it *demands the full product
exist*; because it does not, the combine is ill-formed until a Cross
supplies {X, Y, Z}. This is the right answer, and it is delivered by the
existing rule (no lub ⇒ no context to combine at) and the existing remedy
(insert a Cross, gated by the invariance demand, witnessed if it fails).
Two axes could never show this — two axes have one product and always a
lub. The concrete three-list example is what makes the poset's partiality
visible, and it lands on machinery already written.

**The table indexing generalises verbatim.** A node whose flow-variable set
spans the three axes memoises at the product context as a point-indexed
cube — one entry per (x, y, z) point, `f` run **once per point** regardless
of how many of the six consumers traverse in how many orders. Whole-table-
first still suffices for the eager fragment: one lazy builds the full cube
in the stored orientation, the other five consumers index it. The honest
cost — retention — amplifies with rank (the cube stays live until the
slowest consumer finishes), exactly as the two-axis note predicted; under
stream kinds the cube refines to per-cell `Delayed` cells, a 3D grid. No
new mechanism, more indices.

**The three theorems survive at rank 3.** *Rectangularity:* per any-axis
firing the remaining sub-product traversal is the same sequence (mutual
invariance across all axes), so nested collects over the cube are never
ragged. *Commute totality:* every adjacent pair in any nesting of the
product is *itself* a product — any subset of a product's axes is a
sub-product by invariance — so an adjacent Commute is always defined, and
the six orders are reached by chains of adjacent Commutes (adjacent
transpositions generate S₃). *Kinds unchanged:* a triple-nested crossed
flow presents as ordinary triple nesting downstream. The "represent one
orientation, read the rest" lean carries: the stored form is one of the six
permutations, and each other reading is a faint Commute-chain away — and the
reading is the *permutation*, not the chain, because the naturality quotient
identifies any two adjacent-Commute chains realising the same permutation
(the symmetry of a Cartesian product is coherent).

**Lean.** Represent n-ary products as flat axis sets — the denotation is
the set; the binary-Cross nesting tree is authoring detail that
additionally names whichever sub-products the author bound. Keep the poset
as the subset lattice of constructed axis sets, with `deeper` =
lub-if-it-exists and no-lub routing to "insert a Cross," both already in the
two-axis rules. Nothing new is needed at rank n that rank 2 did not already
carry; rank 3 is where the *partiality* of the poset and the S₃ orbit of
orientations first become observable, and both were caught by existing
machinery — the sign that "flat axis sets" was the right presumption to
commit to.

Two residues, both minor, filed to their owners rather than worked here:

- **Which orientation is canonical for a flat n-ary cross** (which of the
  six the stored form picks, and how completion chooses it) is the n-ary
  face of open question 1 and the textual form's Cross-spelling question —
  does the text name a full permutation? Two axes name at most a single
  swap; n axes name a permutation.
- **A fold or a join over the cube** demands a single traversal order that
  the order-free product does not supply. The register half is now worked
  ("Registers over products", question 5): a register folds *along a named
  axis*, and a full cube reduction is the S₃ axis-permutation this section
  identified, wearing its register hat — the order chosen at the consumer,
  as with two axes. The join half (question 4, operand-walk over the cube)
  is unchanged and stays that round's.

## The aligned product (zip): Cross's positional sibling

Cross is one of two ways two flows combine, and until now the doc has only
worked the one. Cross pairs *every* firing of one flow with *every* firing
of the other — independent extents, an n×m table, mutual invariance. Its
sibling pairs firing *i* with firing *i* — one shared extent, paired by
position. That is the **aligned product**, working name **zip**. The two
are the products row's pair: Cross multiplies firings, zip identifies them.

The demand is not speculative. Three comparison studies converged on it
independently: APL's pervasion (`1 2 + 3 4`) is the array family's single
most-used operation and its ground floor — blend, interleave, weighted
average, inner product, and sort-one-by-another are all instances
(`apl-family-comparison.md`, finding 2); Zig makes multi-object `for (a, b)
|x, y|` the *primary* loop construct, arriving at aligned pairing from the
imperative side (`zig-comparison.md`, finding 3); and the tidyverse's data
frame is k equal-length columns whose row view and column view are one
value (`tidyverse-comparison.md`, finding 1). Until this round the only zip
in the record was a *compile-level* stream primitive (the multi-parent zip
of `lazy-stream-placement-design.md`) — mechanism without authoring
vocabulary. Conway's Life is the record's one localized representation
struggle precisely because it needs *both* products at once — Cross to
enumerate the 3×3 neighborhood, zip to overlay nine same-shape grids
pointwise (`apl-family-comparison.md`, §9).

### The program that demands it

A pointwise combine of two lists the author means to walk together:

```
xs -> open list => x, ~x
ys -> open list => y, ~y     -- meant as the same walk as xs, by position
x, y -> add => s
s -~> collect => out
```

Nothing drawn says the two walks *are* the same walk. Read as it stands,
the two uncollects are independent, and their only lawful product is Cross
— an n×m table, when the author meant the length-n diagonal. The gap is
that the language has no way to say "these two walks advance together,"
just as (before Cross) it had no way to say "these two walks are
independent." Same missing vocabulary, opposite fact.

### The construct

The aligned product is a flow operation in the Cross / Commute / binary
Join species: a node with flow ports and **no value ports**. Its shape is
the mirror of Cross's:

- **Inputs:** two (or more) flows of the **same extent**.
- **Output:** **one** flow — *not* nested. Both lanes ride the same
  firings; the barrier *widens* the walk with the second lane's value wire
  rather than multiplying its firings. (This is the visible contrast with
  Cross, whose output is nesting.)
- **Demand:** the operands are **co-extent** — the same firing structure.
- **The law:** *the aligned flow fires once per shared firing; each lane's
  element rides that firing.*

Consequences of the law, as short theorems mirroring Cross's:

1. **No new firings.** The output has exactly the shared extent; a collect
   over it is length-n, never n×m. This is what tells zip and Cross apart
   at the site of use — same two operands, different barrier, different
   extent. (Cross's theorem 1 was rectangularity; zip's is that it adds no
   rows at all.)
2. **Values ride, they don't pack.** Both lanes' elements are readable at
   the shared firings by the ordinary invariance rule; no tuple is built to
   carry them across. The wires stay separate wires — the no-bottleneck
   shape, a barrier with corresponding inputs and one widened output.
3. **Kinds unchanged downstream.** The widened flow presents as an ordinary
   flow; a collect, join, or register consumes it with no zip special case
   — exactly as a crossed pair presents as ordinary nesting.

### The witness of co-extent — the one real asymmetry with Cross

Cross and zip are not quite symmetric, and the asymmetry is this round's
central finding. **Cross's demand (mutual invariance) is always
structurally checkable** — the flow-variable set is the annotate pass's
per-node fact, and siblinghood-at-authoring-time witnesses independence.
**Zip's demand (co-extent) is structurally checkable only sometimes.** Two
regimes fall out, distinguished by the same provenance the invariance
demand already computes:

- **Same-provenance zip — structural, and free.** When both lanes trace
  back to *one* uncollect through extent-preserving operations (value-only
  maps, per-firing work — anything that neither opens nor collects nor
  filters), they fire in lockstep *by construction*. Their co-extent is not
  a claim to be checked; it is one walk carrying two wires. Here zip is
  degenerate: it re-bundles wires that already share firings. This is the
  common case and it costs nothing — the analog of Cross reading
  independence off siblinghood, run the other way. In particular, **k
  sibling collects of one walk are aligned by this rule** — which is why
  the value form below is the same construct, not a new one.

- **Distinct-provenance zip — a barrier assertion.** When the lanes come
  from *different* uncollects (two independently sourced lists claimed to
  be equal-length), co-extent is not structural; it is a runtime
  coincidence. The node then carries a **co-extent precondition asserted at
  the barrier** — checked once, at the walk's start, not per firing — with
  a **terminator/witness when it fails** (the shorter lane runs out).
  Raggedness here is a *failure*, the exact opposite of Cross's per-point
  regime where absence is a hole in the table and both readings survive.

The honest one-liner: **Cross's independence is always static; zip's
co-extent is static under shared provenance and a runtime precondition
otherwise.** Two shipped languages put the check exactly at the barrier and
not per element — Zig asserts length-equality "at the start of the loop"
and APL raises a conformance error before the pervasion runs. So the
co-extent demand is a property in `types-design.md`'s sense where
provenance discharges it, and a checked precondition with a failure witness
where it does not — one construct, two discharge paths, chosen by whether
the annotate pass already proves the extents equal.

### The value form — the multi-wire collect and the table

The aligned product has a rest state, and it is the missing half the
tidyverse study named. A **multi-wire collect** takes several wires of one
flow at one barrier and produces a value that keeps their correspondence: a
**table** — k value wires become k columns, n firings become n rows, cell
*i* of every column belonging to firing *i*. Its **uncollect gives the
wires back**, already aligned (a same-provenance zip of the columns,
aligned because they were collected together). The flow-level pairing and
the value-level table are one construct seen from both sides: *a table is k
lists that remember they were collected from the same walk.*

The value opens into k **wires, not one row-struct**, and the tidyverse
corpus argues the point three times over:

- **The row-splat wart.** `pmap(df, f)` splats every column into `f`'s
  arguments, so a consumer of two of three columns errors on the unused
  third. On wires, an unused column is simply an unconnected port.
- **The arity matrix.** map / map2 / pmap × typed suffixes is a
  combinatorial family that exists only because aligned inputs arrive as
  loose values; dplyr documents retreating from it and re-adding
  `rowwise()` so the table itself carries the alignment. The whole matrix
  collapses to one uncollect when the aligned wires are a drawn fact.
- **Suffix collisions.** Joins auto-rename colliding columns `.x` / `.y` —
  the one-namespace cost of packing wires into a single field set. Wires
  don't collide; names label wires, they don't key a lookup.

The column axis is the *wire* axis (drawn structure — names, types, one per
variable); the row axis is the *firing* axis (runtime extent); their
non-independence is rectangularity — every firing carries every wire. k
sibling collects that *forget* they shared a walk are the record's current
state; the table is those k lists *remembering* it, and remembering is the
whole content.

### Scalar extension is Incorporate, not zip

APL's scalar-extension rule — a lone value silently lifted to pair with a
vector — reads in our vocabulary as **Incorporate's implicit costume**: a
value made available at every firing. That is auto-capture, already silent,
and it is emphatically *not* the aligned product. Zip pairs two flows;
Incorporate lifts a value into one. Keep them distinct. For the clash
record: APL's implicitness is a hazard — a rank mismatch that happens to
conform silently computes the wrong program — so the value-into-flow lift
stays a drawn Incorporate, and the co-extent assertion above is what
catches a genuine two-flow mismatch, never an inferred rank rule that
papers over it.

### Indices as an aligned lane

Zig's `for (items, 0..) |item, i|` derives the index's extent from its
sibling: the index is not a loop mode, it is one more aligned lane. In our
vocabulary an **index is a counted source opener** (`source-openers-design.md`)
with no independent extent, zipped against the data flow, which fixes its
length — the aligned product's degenerate lane where one operand borrows
the other's extent. Same-provenance keeps it free: the index lane is
aligned with the walk it counts by construction. This answers the
translation exercise's open note on whether iteration-by-index deserves
better than `range(len(a))` plus two index applications (finding 10) — it
does, and the better form is a zip lane, not a new construct.

### Rank-2 and n-ary — the Life residue, filed forward

Conway's Life needs Cross (enumerate the 3×3 neighborhood) and zip (overlay
nine same-shape grids pointwise) at once, at rank 2 — the grids are 2D. The
aligned product makes Life *drawable*; it stays clumsy until the
n-ary/axis-handling questions land. But those are the same open questions
the Cross side already carries: n-ary products are worked above; a zip over
a 2D grid is a rank-2 aligned product (nine lanes of one grid-shaped walk)
whose axis handling rides the products row's residue, not this section's.
Filed forward, not worked here — the round establishes the construct and
its co-extent story; rank-2 structure is the products row's standing debt.

### Per-edge alignment (a second target, filed)

purrr's `reduce2` aligns its second input with the **gaps between** firings
— one element shorter, used for separators
(`reduce2(letters[1:4], c("-", ".", "-"), …)`). Not every aligned lane is
firing-to-firing: the edge between consecutive firings is a distinct,
shippable alignment target, adjacent to the register's previous-firing
machinery. Noted as a residue for the iteration-state round rather than
worked here — the aligned product's primary case is firing-aligned, and
edge-alignment is one added lane offset, not a different construct.

### Against the philosophy

- **Example first, then generalise.** The pointwise-combine program is the
  concrete gesture; the aligned product is the identified relationship
  (co-extent), read off shared provenance where present — never declared
  upfront.
- **No bottlenecks.** A barrier with corresponding flow inputs and one
  widened output, no value packing — the principle's own shape, the
  positional twin of Cross.
- **Building blocks at the programmer's abstraction level.** "Walk these
  two lists together" is a programmer-level concept (every zip, every data
  frame holds it); the index-plus-lookup encoding was the plumbing-level
  costume.
- **Graceful expansion.** The simple case (two same-provenance wires) is
  free; adding a distinct-provenance lane *adds* the co-extent assertion —
  structure added, never a rewrite into a different construct. The table is
  the same construct at rest; opening it adds no construct.
- **Abstraction is the source of truth.** The table is k lists that
  remember one walk; the loose k lists are the derived, forgetful view.
  Provenance is the truth; alignment is the fact retained from it, free and
  downward, exactly as with Cross's independence.

### Building it: smallest first step

Ordered so each piece is testable in `Main.res` style; assumes the
first-class-ports migration.

1. **Same-provenance recognition.** The provenance/flow-variable fact
   already needed for Cross's invariance demand, run the other way: two
   wires are co-extent iff they trace to one uncollect through
   extent-preserving ops. Free zip is then a re-bundle, no node emitted.
2. **The aligned-product node** (flow-only, co-extent demand), with the
   barrier assertion plus failure witness for the distinct-provenance case.
   Compile: the stream-level multi-parent zip primitive already exists
   (`lazy-stream-placement-design.md`) — the gap was authoring vocabulary,
   now supplied. Tests: pointwise-combine of two lists, same-provenance
   (free) and distinct-provenance (asserted); the distinct-ragged case
   fails at the barrier with the shorter lane as witness.
3. **The multi-wire collect / table** as the value form: k wires in at one
   barrier → a k-column value; uncollect → k aligned wires. Tests: a table
   round-tripped through collect/uncollect preserving alignment; a
   two-of-three-column consumer leaves the third an unconnected port (no
   row-splat error).
4. **Index-as-lane and per-edge alignment** ride source openers and the
   register round respectively — not built here.

## Registers over products (open question 5, worked)

A product is order-free by construction — its points carry a poset, not a
sequence, and that order-freedom is the whole content of Cross (each
consumer traverses in its own order, `time-travel-programs-design.md`). A
register (`iteration-with-state-design.md`) is the opposite: it threads a
carried value from one firing to the next, so it *demands* a sequence.
Open question 5 asked what a register over a product means when the
product supplies no order. Worked below: the register does not fold **over
the product**; it folds **along one of its axes**, fibered over the rest —
the APL reduce-along-an-axis shape — and once that is seen, everything else
(the orientation it pins, its result's rank, productivity, the running
view) is the ordinary register semantics already worked, applied per fiber.
Nothing product-specific remains except the choice of *which* axis — and
that choice turns out to expose an **open ontological question about Delay
itself**, which is the round's real lesson. Which flow fixes the register's
axis? Two candidates (`delay-ontology-design.md`): the **collect** that binds the register (so the
axis is a consumer's choice), or the **ancestor uncollect** the carried
value descends from (so the axis is fixed at the Delay, independent of
consumer). The results in this section — reduce along *one* axis, fibered
over the rest — hold under both; only the attribution of *who names the
axis* differs. And the product is where the sharpest evidence lives: the
shared-grid implementation (iterate once, store the n×m table, transpose for
the other consumer) **breaks** if a register's axis depends on which
consuming collect reads it (the two consumers would need two different
grids), which cuts toward fixing the axis *at the Delay* — the
ancestor-uncollect candidate. The ontology round weighs this as a real
cost on collect-binding rather than a knockout (recompute-per-consumer is
a legitimate implementation), so the fork stays balanced. Recorded there
as open; below, "the register's axis" means whichever flow that question
settles on.

### The program that demands it

A running sum over a crossed pair — two lists, their pairwise sums, and now
an accumulator:

```
xs -> open list => x, ~x
ys -> open list => y, ~y      -- sibling of xs; cross, not zip
x, y -> add => s              -- one value per (x, y) point: an n×m table
```

`s` is a value at the product context {X, Y}. Now put a register on it. The
question the order-free table forces immediately: **a running sum in which
direction?** Down each column (accumulate over x, one running total per y)?
Along each row (over y, per x)? Over the whole thing (one grand total)?
Three different programs, and the product — deliberately — names none of
them. The register has to say which, and *saying which is the entire design
question*. In the register spelling the choice is visible as which flow the
delay names — and nothing in the symmetric wiring supplies it:

```
-- spelling provisional; the delay's flow reference is the axis choice
~x ~> delay init 0 => run             -- along X: fold down each column…
run, s -> add -> step of run => colTotal   -- …final = one total per y (a Y-flow)
```

versus `~y ~> delay …` (along each row, final an X-flow) versus the plain
scan's `~L ~> delay` with no `~L` to infer — the `~?` the ontology round
works from (`delay-ontology-design.md`, "The product sharpens both").

### The finding: reduce along an axis, fibered over the rest

The answer is the array family's, item for item (`apl-family-comparison.md`,
finding 1: `/` reduce and `\` scan *fold or accumulate along an axis*). A
register over the product {X, Y} folds **along one axis** — call it its
axis, say X (which flow fixes it is the open question above) — meaning:

> for each fixed y, run an ordinary register along the X-fiber; state does
> not cross between different y's.

That is `+/[X]` (Dyalog `⌿`, BQN `˝˘`): reduce the matrix along the X axis,
producing one result per y. The register's `final` output is therefore not
a scalar but a **Y-flow** — rank n−1, the reduced axis gone, the surviving
axes still a flow. A register along Y instead fibers the other way and
yields an X-flow. The order it pins is only the **within-axis** order of its
axis — which every list axis already carries — and the product's
**cross-axis** order-freedom is never touched, *because state never crosses
axes*. Rectangularity (theorem 1) is what makes this well-formed: every
X-fiber is the same sequence of firings for every y, so "run a register
along the X-fiber" is defined identically at each y.

**A register over a product is just an ordinary register whose surrounding
context is the other axes.** The product context is deeper than each axis
("The context model"); a register-along-X is a register whose iterated flow
is the X axis and whose seed lives in the Y context — exactly the shape of a
register nested inside an outer list loop, which the register design already
covers. The only thing the product adds over a plain list is that the flow
has more than one axis, so *which* axis the register threads along is no
longer forced. A register that reduces "the whole product" as one sequence
is ill-formed for the ordinary reason (no order exists), with the remedy
being "fold one axis, or Join first" (below). No new register machinery —
the product just made the axis a live choice, whose resolution is the open
Delay-ontology question.

### The orientation is minimal

The oriented traversal question 5 flagged is real, but it pins **less** than
a linearization. In a symmetric product {X, Y} neither axis is outer; to run
a register along X *fibered over* Y you must read the product
Y-outer/X-inner. The register along X induces exactly that orientation and
no more: it puts the reduced axis innermost and leaves the fibering axes
outer, still a product, still order-free among themselves. This is "orders
live at terminations; the order is chosen at the consumer" (Option B) with
the register as one more consumer — it orients the product only to the depth
it folds and hands the rest onward unoriented. For an n-cube, folding X
leaves an (n−1)-subcube outer, which the next consumer orients (or reduces)
in its turn. (Whether the orientation "lives at" the binding collect or is
fixed at the ancestor uncollect is the open question above; either way it is
this-minimal.)

### The inner-axis vs outer-axis cost

Reduce along *which* axis is not cost-neutral, and the asymmetry is where an
outer-loop accumulator hides. Take the product traversed X-inner, Y-outer:

- **Register along the inner axis (X).** Consecutive firings of the X-fiber
  are adjacent in the traversal, so the register *streams*: accumulate
  across the inner sweep, reset the seed at each new y. One live
  accumulator, no retention — the cheap, obvious case.
- **Register along the outer axis (Y).** "Previous" now means the previous
  *outer* iteration's element at the same inner position — the value at
  (x, y−1), which the traversal visited a whole inner sweep ago. Realizing
  it means **storing the entire previous inner list (the previous X-fiber)
  and zipping it positionally with the current one.** The Y-register is
  fibered over X, but because X is traversed *inside* Y, its |X| parallel
  fibers all advance once per outer step, so the whole fiber must be
  retained across the inner sweep.

The store-and-zip is not a wart — it is exactly what an **accumulator over
an outer loop** *is* (compare this row to the previous row; carry a
per-column running total across rows), and wanting that is not infrequent.
So a register over a product carries a real cost gradient — the inner axis
streams, any outer axis retains a fiber — and choosing the axis is also
choosing the cost.

This is also the mechanical fact behind a point in the Delay-ontology
debate (`delay-ontology-design.md`): the two
orientations of a register are not two readings of *one* grid, they are two
*different computations*. The base value grid (`s = x + y`) transposes for
free, but a **scan** along X (`sum over x′≤x at fixed y`) and a scan along Y
(`sum over y′≤y at fixed x`) are different grids — not transposes of each
other — and a **reduce** along X (a Y-flow) and along Y (an X-flow) are
different outputs. So there is no single grid a register can build once and
serve both orientations from (outside the commutative case below); a
consumer that wants the other orientation drives a genuinely different
computation, which is why "re-run the register per collect" is a legitimate
implementation and not merely a failure to share.

Reducing a rank-n product **all the way to a scalar** is *n* nested
registers — one per axis — not one register over the cube. Register-along-X
gives a Y-flow; a register-along-Y over *that* gives a scalar. The nesting
order is an **axis permutation**, and — the point — it is a genuine choice
with genuine consequences: the register is not assumed commutative, so
reduce-along-X-then-Y and reduce-along-Y-then-X are different computations
(as `+/+/M` and a non-commutative `⍤/⍤/M` differ in the array world). This
is the S₃ orbit of the n-ary section wearing its register hat: the six
orientations of the cube are the six axis-permutations a full reduction can
pick, and the author picks one exactly as they pick a collect chain's
nesting order. No orientation is canonical; each is a different, legitimate
fold, and the product kept all six available precisely so the register could
choose.

### The one order-free exception: a commutative monoid

There is exactly one case where a register *may* reduce over the whole
product with no axis named, and it is the register-level twin of the A-vs-B
confluence argument. When the operator is a **commutative** associative
operator (a commutative monoid — `+`, `×`, `min`, `max`, count, set-union),
every axis order and even every linearization give the same result: `+/,M`
(ravel then sum) equals `+/+/M`, and the pick is unobservable. So a
**reduce-close** (`iteration-with-state-design.md`'s monoid fold, the "just
sum the table" operation) over a product is well-defined and order-free
*iff its operator commutes* — the operator's own law discharges the order
demand the way shared provenance discharges zip's co-extent demand and the
way the invariance demand makes Cross's non-pick meaningless. The letter of
"a fold needs an order" is relaxed exactly where it is provably
meaningless. A **non-commutative** register (or a reduce-close on a
non-commutative operator — string concatenation folded over a table) must
name the axis or the axis permutation; commutativity is the property in
`types-design.md`'s sense that, when present, lets the whole-product
reduction stand. This lands the collect family's identity/algebra machinery
(`collect-family-design.md`) a second job: the catalog row that carries a
monoid's identity can carry its commutativity too, and commutativity is the
witness that "reduce over the product" needs no orientation.

### Productivity transfers verbatim

The register's productivity check — *every cycle passes through a Delay
crossing; delete each crossing and the graph is acyclic*
(`iteration-with-state-design.md`) — carries over with **no new machinery**.
Within each fiber the register is an ordinary along-one-axis register, and
the Delay crossing (`step → prev`) is still the only iteration-boundary
edge. Fibering does not add edges; it instantiates the *same* structural
crossing once per point of the reduced-away axis's complement, each fiber's
run grounded by its own seed (`init`, one value per outer point, evaluated
in the outer context — it may vary with the fibering coordinate but never
with the iterated axis, the ordinary "no time travel" rule). In the stored
form the check stays a **theorem**: the pairing (write → read) is still the
only edge running with an object pointer, so every computation cycle still
passes through one, and the fibering is a runtime multiplicity of that one
crossing, not a new edge. Non-productive register-over-product programs are
unrepresentable for the same reason plain non-productive registers are.

### The running view keeps the shape

The register's running view — the state port of its derived augment form
(`variable-rate-consumption-design.md`) — over a product is `+\[X]` (scan
along an axis): it keeps the **full product shape** (rank unchanged), the
value at each point being the accumulation so far along X *within that
point's fiber*. This is the ordinary running view applied fiberwise, and it
inherits BQN's observation that a scan never needs an identity (finding 8) —
here it also never needs a cross-axis order, because the running value at a
point depends only on that point's own fiber up to that point. So the two
readouts of a register over a product are: `final` (reduce, rank n−1) and
the running view (scan, rank n) — the same pair a register over a list
gives, one rank higher.

### Boundary with question 4: the linearized fold is Join-then-register

The reading the product *does not* give — thread state through **all** the
points in one linear walk, state carrying from the end of one fiber into the
start of the next — is not lost; it is a **different program**, and a
composed one. It is exactly the list-monad linearization the doc already
declined for Cross ("Not the list monad"): flatten the product to a single
sequence, committing row- or column-major, then fold. In our vocabulary that
is **Join the product** (which commits an orientation via Join's (outer,
inner) operands — question 4) **then an ordinary register** on the resulting
single-axis flow. Two constructs, a composition, no new semantics — and the
clean separation of questions 5 and 4: the register over a product folds
*along an axis* and needs no linearization; the register over a *joined*
product folds a linear walk and gets its order from the Join. Question 5
never has to re-derive linearization, and question 4's operand-walk rules
are where the row/column-major choice is spelled.

### The state thread over a product (the drawing)

Question 5 also asked what this means for the state thread's drawing (the
fourth-option surface, `iteration-with-state-design.md`). A thread crosses
"the single generic iteration column"; over a product there are several
axes, and the thread crosses **only its axis's column**, replicated
(fibered) across the others. Reducing a matrix along X is a *family of
parallel threads*, one per y — the APL `+/` picture exactly (sum each column
→ a row of totals): each thread enters at its fiber's seed (which may vary
with y), taps and writes back down its own column, and exits into the
`final` Y-flow. Iteration already draws 2D (position across, computation
down), so a register along one axis of a product is naturally a plane's
worth of parallel threads tiled along the fibering axis — the visual side's
question, but the representation is: n−1 axes of independent thread copies
over the register's one iterated axis. Dense cross-referencing across
threads (Fibonacci's shape) is orthogonal — it lives *within* a fiber and
contracts to Delay points there, as on a plain list.

### Against the philosophy

- **Example first, then generalise.** The running sum over a table is the
  concrete gesture; "along which axis" is the identified relationship, read
  off the register's named iteration axis — never a fold-shape declared
  upfront.
- **No bottlenecks.** The register folds one axis and leaves the rest as
  flow; nothing is packed into a tuple to carry the un-reduced axes across
  the fold. The result is a lower-rank flow, corresponding axes riding
  through — the principle's own shape at the register.
- **Building blocks at the programmer's level.** "Running total down each
  column" is a spreadsheet-level concept; the linearized-then-folded
  encoding was the plumbing costume, and it is still reachable (Join first)
  when actually wanted.
- **Foundations before features.** The construct is the ordinary register
  plus one obligation (name the axis), admitted by a forcing program (the
  three-direction ambiguity), with the commutative exception recorded as
  the one place the obligation lifts.
- **Abstraction is the source of truth.** The order-free product is the
  truer description; the register's axis is a minimal induced orientation
  (innermost only) and downward — the same lens shape as Cross's stored
  orientation, now at the fold.

### Smallest first step

Rides the register round and the Cross node; testable in `Main.res` style
once first-class ports and Cross land.

1. **A register over a product folds along exactly one axis.** The check
   rejects a whole-product register with the "no order" witness, the remedy
   being "fold one axis or Join." (For a commutative-monoid reduce-close,
   the requirement lifts — the catalog row's commutativity flag discharges
   it.) Which flow fixes that axis — the binding collect or the ancestor
   uncollect — is the open Delay-ontology question and must be settled
   before this is built; the shared-grid argument (intro) leans it toward a
   fixed ancestor axis.
2. **Reduce along an axis.** Compile a register-along-X over a crossed pair
   to a per-fiber accumulator (one register run per y), `final` a Y-flow;
   test against a hand-built table of per-column sums, and against a
   non-commutative fold to pin that axis order is observable.
3. **The running view** (scan along an axis) keeping full product shape;
   test the point-indexed running values against a hand-built scan.
4. **Full reduction as an axis permutation** — two nested registers over a
   cube in both orders, values compared to confirm the orders differ for a
   non-commutative operator and agree for a commutative one.

## Open questions

1. **A vs B storage.** The lean above (represent oriented, read symmetric)
   has a recorded exit; revisit if consumers fight the stored orientation
   in practice, or when the textual form has to print a Cross (does the
   text name an orientation?).
2. **Naming.** Cross, product, table, cross-join, "mutual capture."
   Interacts with the user-facing vocabulary rounds (`types-design.md`
   open question 1); also whether commute-on-product deserves the name
   *transpose* in user-facing text.
3. **N-ary products and associativity — worked** ("N-ary products: the
   three-list example"). Flat axis sets confirmed as the denotation; the
   binary-Cross nesting tree is authoring detail that additionally names any
   bound sub-products; the poset is the subset lattice of constructed axis
   sets (the cell-set shape), with the lub-may-not-exist behaviour first
   visible at three axes and caught by the existing "insert a Cross" remedy.
   Residue: the canonical orientation of a flat n-ary cross (the n-ary face
   of question 1 and the textual Cross-spelling), and fold/join order over
   the cube (questions 5 and 4).
4. **Join on a product.** Flattening commits an orientation via Join's
   operand order — fine — but the interaction with multi-level joins (a
   join *chain* over a product's axes plus an enclosing flow) needs the
   operand-walk rules extended.
5. **Registers over products — worked, and it reopened a Delay question**
   ("Registers over products"). A register folds *along one axis*, fibered
   over the rest (the APL reduce-along-an-axis shape), not over the whole
   product: `final` drops the reduced axis (rank n−1), the running view keeps
   full shape, the axis is a minimal induced orientation (innermost only),
   and productivity and the stored-form theorem transfer verbatim (the Delay
   crossing instantiated per fiber) — all independent of *which flow* fixes
   the axis. That last point is the round's deeper yield: **which flow binds
   a Delay** is an open ontological question (`delay-ontology-design.md`), and this section carries its
   sharpest evidence — the shared-grid implementation of products breaks
   under consumer-order-dependent binding, which cuts toward fixing the
   axis at the Delay (the ancestor uncollect). The ontology round weighs
   this as a real *cost* on collect-binding, not a knockout (re-running a
   register per collect is a legitimate implementation, and an outer-axis
   accumulator wants the store-and-zip cost anyway); the fork stays
   genuinely balanced there.
   Two findings: a full reduction is an axis *permutation* (the S₃ orbit
   with a register hat; non-commutative folds observe the order); and a
   commutative monoid discharges the order demand entirely, so a
   reduce-close over a whole product is order-free iff its operator commutes
   (the A/B confluence at the register level; the collect-family catalog row
   carries the commutativity witness). The linearized whole-cube fold is a
   *different* program — Join the product (question 4, committing an
   orientation) then an ordinary register — so question 5 needs no
   linearization of its own. Residue: the state thread's *visual* tiling
   over a product (the layout repo's), and the axis-naming's textual
   spelling (the textual-form row).
6. **Mixed-kind axes.** `cross(list, option)` is a table with a 0-or-1
   axis — is that a construct anyone wants directly, or just a degenerate
   case the theorems cover? Cross over stream axes gives a
   lazily-materialised 2D grid whose pull semantics (which axis advances
   on a pull?) need the stream round's attention. Cross with
   async/incremental axes is deferred to those kinds' own rounds.
7. **Retention policy.** The whole-table lazy retains the full product
   until its consumers finish; grid cells retain along the slower cursor.
   Whether the language ever wants an explicit "recompute rather than
   retain" annotation, and where it would live, is deferred until
   something measurable exists.
8. **Provenance representation.** The product segment in context paths
   (axis sets, poset comparability) is sketched above but should be worked
   against `bundle-provenance-design.md`'s walk-and-classify algorithm
   before the checks land.
9. **The aligned product (zip) — worked** ("The aligned product (zip)").
   Cross's positional sibling: same extent paired by position, output a
   single widened flow (not nesting), demand = co-extent. The central
   finding is the asymmetry with Cross — co-extent is structural under
   shared provenance (free, a re-bundle) but a runtime precondition
   asserted at the barrier otherwise (Zig/APL's shipped shape). Its value
   form is the multi-wire collect (the table). Residue, filed to owners:
   the exact form of the co-extent assertion at the property/precondition
   boundary (`types-design.md`); the table's textual and at-rest spelling
   (the textual-form row); rank-2 zip's axis handling, the Life exhibit
   (this row's n-ary/axis residue, not the zip section's); and per-edge
   alignment's home (the iteration-state/register round).
