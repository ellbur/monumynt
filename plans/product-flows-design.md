# Product Flows — when two loops meet

Status: exploration — this chapter teaches a worked proposal with a
recorded lean, not an adopted feature. None of it is implemented. Read
it as "here is a candidate and the case for it." It assumes the ports
migration (landed — `src/Program.res` is ports-first; Cross is a flow
node with ports, like Join). The chapter supersedes part of
`time-travel-programs-design.md`'s disposition 4 and closes that
document's open question 4; correction notes are placed there.

This is the chapter about what happens when two loops meet. Its main
construct is **Cross**, for two flows that are combined asymmetrically
— one nests inside the other — but *independently*, where the inner
flow's shape does not depend on the outer element. We'll call that the
**mutual-constant** relationship, and you'll see it grow out of a
concrete program before it gets a definition.

Along the way the chapter also works Cross's positional sibling, the
**aligned product** (working name **zip**) — pairing two flows of the
*same* extent by position rather than every firing with every firing —
together with its value form, the multi-wire collect (the table). See
"The aligned product (zip)" below. And it works how a **register folds
over a product** (open question 5): along one axis, run once per value
of the other axes — the reduce-along-an-axis shape — not over the
whole order-free cube. (Which flow fixes that axis reopened a question
about what a Delay *is*.) See "Registers over products" below.

A vocabulary note before we start: this chapter says **uncollect** and
**collect** for open/close (the code still says Open/Close). The new
construct's working name is **Cross**; other candidates are listed
under Naming in the open questions.

## The program that demands it

Start with the smallest program that needs something the language
doesn't have yet. You have two lists — neither derived from the other
— and you want to combine every element of one with every element of
the other. You uncollect each list on its own:

```
listX -> open list => x, ~x
listY -> open list => y, ~y
x, y -> add => s
```

(`=> x, ~x` names both of the uncollect's output ports: `x` is the
element — the value port — and `~x` is the flow, the "once per
element" context.) The wire `s` now carries one sum per *pair*: for
each x and each y, the value `x + y`.

Now collect the sums. There are two nested iterations here, so you
collect twice — and you get to choose which iteration is inner and
which is outer. Suppose you want *both* readings — the sums grouped
per y, and also the sums grouped per x. Here is the full program: two
lists, uncollected side by side, neither derived from the other;
elements combined; two terminations in opposite orders:

```
listX -> open list => x, ~x
listY -> open list => y, ~y
x, y -> add => s
s -~> collect => sPerY -~> collect => out1    -- ~x inner, ~y outer
s -~> collect => sPerX -~> collect => out2    -- ~y inner, ~x outer
```

`out1` is, per y, the list of x+y over all x; `out2` is the transpose
— the same values, grouped the other way.

How should this *run*? That part is already settled: the
compile-strategy round worked out how this executes without
duplicating the user's `add`. The values form an n×m table indexed by
iteration points, the points are order-free, and each consumer
traverses the shared table in its own order
(`compile-strategy-design.md`). Picture a spreadsheet: one cell per
(x, y) pair, `add` run once per cell, one reader walking it row by
row and another column by column.

The gap is that the *language* can't yet say what the runtime is
doing. The natural spelling — pick one orientation as primary, build
that nesting, and let the other consumer read it transposed — wants a
**transpose operation to insert**, and there isn't one.

Now, you might wonder why the language doesn't just have a list
transpose — an operation that turns a list of lists on its side. It
turns out the design record already declined one, and for a good
reason: nested lists can be ragged (the inner lists can have different
lengths), and a ragged nesting has no transpose. But look at *our*
nested lists: they cannot be ragged, precisely because neither flow
inherits from the other — every y sees the same xs. The record's
reason for declining transpose is absent exactly here, and the
language has no way to notice. (The decline stands for nested lists in
general; what recovers transpose for this program is the guarded
commute below, not a general list transpose.)

Worse, the completion the language *does* sanction makes the
situation unrecoverable. You might wonder: why not complete the
program with Incorporate — capture `listY`'s sibling into the other
flow and uncollect it there, the way completion handles a value used
inside a loop? It turns out this erases the very fact the author
drew. Completing by Incorporate — capturing `listX` into `~y` and
uncollecting it there — produces a program that *reads as dependent
nesting*: structurally indistinguishable from an inner flow whose
source is computed from the outer element. The mutual-constant
relationship the author drew (siblinghood!) is erased by the very
translation meant to preserve the meaning. By "abstraction is the
source of truth," completion should insert the most abstract operator
that is true of the program, and for sibling opens Incorporate is not
it. (This misuse of Incorporate is corrected below, in "What this
changes in the completion" — Incorporate itself survives for its real
job. Please don't re-propose Incorporate as the sibling-opens
completion without new evidence.)

Sit with the program for a moment and two recognitions follow:

1. **The missing transpose is commute.** The language already has an
   operation that swaps adjacent nesting levels: commute (see
   `core-model.md`). Commute carries no value ports, and it is
   quotiented by naturality — meaning that mapping values before or
   after the swap is the same program, so the swap is purely a flow
   fact. `commute(list, list)` was left undefined because of
   raggedness; *product-ness is exactly the condition under which it
   is defined*. This is a new row in the commute-variant taxonomy
   (`lazy-stream-commute-design.md`), gated on provenance — where the
   flows came from — rather than on kind.
2. **Siblinghood at authoring time is the witness of independence.**
   Two uncollects where neither derives from the other are mutually
   constant *by construction* — each flow's shape is invariant of the
   other's element. The program already contains the independence
   fact, structurally; the job is to keep it, not to infer it.

## The construct

Here is the construct those recognitions call for. **Cross** is a
flow operation in the same species as Commute and the binary Join: a
node with flow ports and **no value ports**.

- **Inputs:** two flows whose contexts are incomparable (siblings,
  possibly at a distance — neither nests inside the other).
- **Outputs:** the same two flows, now nested — pairwise
  corresponding, barrier-style: each input flow has its own output,
  nothing is packed together to get across.
- **Demand:** the operands are **mutually invariant** — neither
  operand's firing structure varies with the other's element.
  Concretely: neither flow's source, nor anything determining its
  firings, has the other flow in its flow-variable set. This is
  checkable with existing machinery — the flow-variable set is the
  annotate pass's per-node fact (`compile-strategy-design.md`) — and
  the demand is a property in `types-design.md`'s sense, with a
  witness (the node that introduced the dependence) when it fails.
- **The law of the crossed flow:** *the crossed pair fires once per
  pair of operand firings; each axis's element rides unchanged.*

That one law gives you three consequences, worth stating as short
theorems because everything later leans on them:

1. **Rectangularity.** Per outer firing, the inner traversal is the
   same sequence of firings (from the law plus the invariance
   demand). Nested collects over a crossed pair can never be ragged.
2. **Commute is total on crossed pairs.** The transposed orientation
   is the same product read the other way; nothing can fail.
   `commute(list, list)` enters the commute table with this guard:
   defined iff the nesting is a product.
3. **Kinds are unchanged downstream.** A crossed pair presents as
   ordinary nesting to everything below it — collects, joins, the
   any-list rule — so no downstream construct needs a product special
   case.

Because Cross has no value ports, its value-level shadow is the
identity — it does nothing to any value — and the naturality quotient
applies (map-then-cross = cross-then-map). That is exactly the
admission test for completion's insertion inventory
(`time-travel-programs-design.md`, "completion inserts only
operations whose value-level shadow is the identity") — so **Cross is
insertable**: the editor may add one on your behalf, rendered faint,
like an incorporate or a commute chain.

How do values get across, if Cross has no value ports? By the
ordinary invariance rule, the same way as at every other flow node:
an axis's element is readable at the product's points because the
product context is deeper than each axis (see "The context model").
No packing, no transport ports — the no-bottleneck shape.

## Asymmetric or symmetric: the one real fork

There are two ways to hold the construct, and the choice is closer to
a spelling than a meaning — worth recording why.

**Option A — oriented Cross plus lawful commute.** Cross takes
(outer, inner) operands, like Join. Its output is ordinary oriented
nesting carrying the product guarantee. The transposed reading is one
Commute node away (theorem 2). Completion for the two-lists program
inserts one Cross in a canonical orientation and one faint Commute
for the chain that reads the other way.

**Option B — symmetric product, order at the consumers.** The
mutual-constant relationship is genuinely symmetric, and the
product's points are order-free — the language-level twin of the
compile's point-indexed table. Under B, Cross commits no orientation;
each consuming operation supplies its own. And the suppliers are all
*already asymmetric*: a collect chain's sequence orders its
traversal; a Join's (outer, inner) operands orient a flatten. Orders
live at terminations — exactly how `time-travel-programs-design.md`
reads collects, as the authored commitments. No Commute is ever
inserted.

The tension with Option B: it relaxes the letter of the
no-time-travel rule ("nesting established at construction"). The
defence is the rule's own purpose, the same one the time-travel
document borrows from Koka: the rule protects *one reading per
program*, and for a product the two orientations are confluent — they
provably give the same values; that is what the invariance demand
means — so the non-pick is unobservable and principled, not sloppy.
The letter is relaxed exactly where it is provably meaningless.

How do the options relate? A = B plus a stored orientation plus a
commute spelling. Nothing is lost in either direction — a Cross node
in the graph keeps the independence fact, so re-reading it the other
way is always recoverable (unlike the Incorporate lowering, which is
genuinely lossy). B is the more abstract description; A-oriented
forms are its derived views, one per consumer chain — the familiar
lens shape: store the abstract thing, derive the committed thing,
free and downward.

**The lean: represent A, read B.** The stored node carries an
orientation (chosen by completion heuristics when inserted, or by the
author when drawn), because A's output is ordinary nesting and
*nothing downstream needs to change*: collects, joins, provenance
walks, and the compiler all consume nesting they already understand,
and the transposed consumer reads through a Commute that theorem 2
makes lawful. B survives as the recognized reading — "these two
orientations are the same product" — a statement the Cross node
itself witnesses, available to the editor, the checker, and any
future recognize-family entry, without a representational move.

> TODO (simplify): that Commute should never be authored. Over a
> Cross it is total (theorem 2) and uniquely determined by the
> consumer's read orientation — mandatory + unique ⇒ inferable, the
> effects round's never-drawn-commute precedent. The consumer reads
> in the order it wants; the editor inserts the transpose faint,
> `time-travel-programs-design.md`-style, instead of the author
> hunting for "a transpose operation to insert." And
the lean has a recorded exit: if experience shows consumers routinely
fighting the stored orientation, promoting B to the representation is
a local change (the node stops carrying an orientation; consumers
already supply their own). Starting at B would instead require
teaching every consumer about unordered contexts on day one.
Foundations first, but smallest true step.

## Partial products: filtering, in three regimes

The construct also answers the raggedness question it was partly
motivated by — what happens when you filter one of the flows and then
want both orders? Filtering splits into three regimes, distinguished
by the same flow-variable sets that gate the invariance demand:

- **Filter an axis by its own element** (predicate on y alone,
  independent of the cross): the filtered flow's shape is still
  invariant of `~x` — the same rows survive for every x. Still a
  product, still crossable, still transposable. Rectangular, just
  smaller.
- **Filter per point** (predicate on both x and y): this does *not*
  break the product. Per-point absence is *data at the point* — a
  hole in the table — not a change in the table's shape. Both
  traversal orders remain well-defined: they visit the same point set
  and skip the same holes. Each consumer chain absorbs the per-point
  option flow in its own orientation (an ordinary
  join-with-option-inner, after that chain's orientation). The two
  collected outputs are ragged *as data*, and they are not transposes
  of each other — they are two legitimate readings of one partial
  table, and nobody claimed otherwise.
- **Shape depends on the other flow's value** (the inner *source* is
  computed from the outer element): no product exists. This is true
  raggedness; the nesting is dependent; one order is meaningful and
  the transpose is not. An attempt to cross such flows — or to
  collect a dependent nesting in the reversed order — fails the
  invariance demand, with the dependence-introducing node as the
  witness.

The first two regimes keep both readings; the third keeps one; and
the checker tells them apart without new machinery.

## What this changes in the completion

`time-travel-programs-design.md` is revised in two places; notes are
placed there pointing here.

**The insertion inventory.** Cross joins it, and **replaces
Incorporate for flow–flow nesting** (the NEST_WITHIN family). The
sibling-opens fix — worked example 1's `INCORPORATE(listA)` — becomes
a Cross insertion: the more abstract operator that is true,
preserving the mutual-constant fact instead of erasing it, and
leaving the program open to a later transposed consumer without
re-completion.

Incorporate is not retired. It survives for what remains its job —
bringing a *value* into a flow context (the CAPTURE family), which
auto-capture already performs silently. Only its misuse for nesting
two sibling opens is corrected to Cross. Note the directed
constraints still do their work: the collect order in example 1 still
determines which orientation the inserted Cross carries.

**Disposition 4 splits, and mostly dissolves.** Crossed terminations
over mutually invariant sibling opens — the worked example 4 shape —
stop being contradictory: completion inserts *one* Cross (plus, under
Option A, one faint Commute for the reversed chain), both chains read
the same product. You might wonder what happened to the "rescue" that
document worried about — duplicating opens per consumer path,
doubling the iteration structure behind the user's back. It turns out
the rescue is never needed: nothing is duplicated, neither structure
nor work. Open question 4 closes by dissolution. What remains
genuinely contradictory:

- **within-chain cycles** — a single termination chain whose own
  constraints force A inside B and B inside A; no reading exists for
  that output;
- **reversed order on a dependent nesting** — the third filtering
  regime; no product exists to transpose;
- **bundle mixing** — untouched, as ever; the missing fact there is
  an execution, not an ordering.

This supersedes the compile-strategy document's earlier per-chain
completion (which resolved disposition 4 by duplicating opens), and
is better on every axis that one paid on — no duplicated opens in the
program, no duplicated work at runtime, one faint node instead of
per-chain insertion sets. (The duplicating-opens completion is
dissolved — superseded by Cross; please don't revive it without new
evidence.)

## The context model

What does a Cross do to the bookkeeping that tracks where every value
may be used? Bundle provenance's context structure gains its second
non-tree feature (the first: partial-collect's subset lattice at
bundle steps). A Cross introduces a **product context**: a context
with two parent axes. The comparability order becomes a genuine poset
— a partial order, where some pairs of contexts are comparable and
some are not:

- each axis context ≤ the product context;
- the two axis contexts remain incomparable to each other;
- everything below the product nests as usual.

The rules that consume the order generalise verbatim: a combining
node demands its operands' contexts lie on one chain of the poset (an
axis value and a product value combine at the product); the memo's
reuse rule — stored context ≤ requesting context — is unchanged as
stated; `deeper` becomes "least upper bound, if one exists" (the
smallest context both operands fit inside — and now there may not be
one). Per-wire context paths stay unary facts; the product segment
records its axis set, the same move the partial-collect document made
for cell sets.

**Availability is monotone; a combine's home is exact.** These are two
different uses of the poset and they must not be conflated. The memo's
reuse rule is *monotone in ⊆*: a value at a sub-product `{Y,Z}` is
available inside the loop of any larger product `{X,Y,Z}` (sub-product
≤ product). But *where a combine lives* is **exact**: combining an
`X`-value with a `Y`-value has its home at the product of exactly
`{X,Y}`, never at a larger drawn `{X,Y,Z}` that merely contains it —
consistent with the n-ary rule that a flat cross builds no
sub-products. When no exact `{X,Y}` product is constructed the combine
is **under-determined**, and the resolution is *not* to make Cross
carry combination detail, nor to silently reuse a larger product (which
is ambiguous the moment two incomparable larger products both cover the
combine — `{X,Y,Z}` and `{X,Y,W}` with no `{X,Y}`). Recall Cross was
introduced to give *natural-feeling time-travel programs* a meaning,
not as a construct users typically hand-author; so **an
under-determined cross is just another time-travel program**, made
concrete by completion inserting the exact `Cross(X,Y)` (shown faint)
compatibly with the rest of the program — the same treatment every
sibling combine gets. The checker/merge therefore reports the gap
rather than picking; completion fills it. (Implemented in `Poset.merge`
— exact-axis match, else `Incomparable`.)

## Compile

How does a Cross run? The compile target is the point-indexed table
of `compile-strategy-design.md`'s revised two-context section — the
Cross node is that mechanism's representation, and the mechanism is
the node's runtime. The essentials from the compile side:

- A node whose flow-variable set spans a product's axes memoises **at
  the product context**, as a point-indexed structure — one entry per
  point, computed on first force by whichever consumer arrives first.
  User-written computation runs **once per point**, regardless of how
  many consumers traverse in how many orders. (This honours the
  sharing convention: sharing is opt-in via binding, and a bound
  node's work is not duplicated.)
- **Whole-table first.** For the eager fragment, one lazy whose thunk
  builds the full table in the stored orientation, with the
  transposed consumer indexing it, is fully adequate — eager collects
  always consume their flow completely, so per-cell granularity buys
  nothing yet. Under stream kinds the table refines to per-cell
  `Delayed` cells (a 2D grid — Shape C over a product), where partial
  consumption exists to exploit. (Per-cell granularity is set aside
  for later, not rejected — it waits for stream kinds.)
- The internal build order of the table is unobservable for pure
  values — not a semantic pick, no faint rendering needed. (Under
  Option A it naturally follows the stored orientation.)
- **The honest cost is retention, not duplication.** Two traversal
  orders of a product cannot both stream ephemeral values off a
  single computation; whatever the slower consumer hasn't reached
  stays live, in the worst case the whole table. For the eager
  fragment this is bounded (the table dies with the last consuming
  thunk); for streams it is the recorded retention axis, amplified —
  grid cells don't get the free cursor-GC that chain cells do.
  Recompute-per-consumer remains available as a future *opt-in* cost
  policy, never the default. (Set aside, not rejected.)
- **Effects:** once-per-point is also the right effect meaning when
  effect kinds arrive — each effect happens once — but the *order* of
  points remains schedule-dependent (the first-forcing consumer sets
  it). The compile-strategy document's open question 1 (effects ×
  divergent consumers) covers this unchanged: an effectful node's
  ordering should be directed by its effect flow, or clash.

## Relation to the rest of the record

- **The product barrier family.** The no-bottleneck principle names
  the concurrent join as the product barrier for async — and the
  concurrency narrative already says of fork-join that "forked flows
  are mutually independent from construction, so join is pure
  synchronization." Cross is the same species' iteration citizen:
  mutual independence by construction, pairwise-corresponding flows
  through a barrier, no packing. Whether the async concurrent join
  and Cross are two kinds' faces of one construct is worth asking
  when the barriers get their Expr round (they share the now-landed
  ports representation — `src/ARCHITECTURE.md`).
- **Not the list monad.** Now, you might wonder why the language
  doesn't just sequence the two lists the way a functional language's
  list monad would — nest one comprehension in the other and be done.
  It turns out the record already rejected that for this program, and
  Cross is not it: the monadic outer product *linearises* — one flat
  sequence in a canonical order, replacing the author's two readings
  with a third — whereas Cross flattens nothing and orders nothing
  the author didn't. A join applied to a crossed pair *is* available,
  and honestly: flattening a table requires choosing row- or
  column-major, and Join's (outer, inner) operands state the choice.
  (This is a settled rejection — please don't re-propose the
  list-monad sequencing without new evidence.)
- **Recognition.** An Incorporate-shaped nesting whose inner source
  is invariant of the outer flow is a product that wasn't drawn as
  one. "Collapse to a Cross" is a recognize-family catalog entry —
  upward, partial, earned — and it is what makes old-style
  completions and hand-drawn dependent-looking programs upgradeable.
- **The visual side** (out of scope here, noted for the record):
  iteration already draws 2D — position across, computation down — so
  a product of two iterations is naturally a plane's worth of
  structure. How that renders is the visual repo's question; the
  representation here is what it would render.

## Against the philosophy

How does Cross measure against the language's design principles
(`language-design-philosophy.md`)?

- **Example first, then generalise.** The two-lists program is the
  concrete gesture; Cross is the identified relationship, inserted or
  drawn after the value computation exists. The construct never
  requires declaring the product upfront — it is read off
  siblinghood.
- **Inside-out / cases as values.** No scopes; the table is structure
  you flow through; elements arrive by visible wires.
- **No bottlenecks.** Cross is a barrier with pairwise corresponding
  flow inputs and outputs and no value packing — the principle's own
  shape, extended to iteration.
- **Building blocks at the programmer's abstraction level.** "All
  pairs of these two lists," read as a table, is a programmer-level
  concept (every spreadsheet user holds it); the incorporated
  loop-in-loop was the plumbing-level encoding of it.
- **Foundations before features.** The construct was admitted by a
  forcing program, not by generality hunger; the fork (A vs B) is
  recorded with its lean and its exit.
- **Abstraction is the source of truth.** The product is the truer
  description; oriented nestings are derived views; the Incorporate
  lowering — which destroyed the abstraction — is replaced by an
  insertion that keeps it. Derivation (committing an orientation) is
  free and downward; recognition (product from dependent-looking
  nesting) is earned and upward.

## Smallest first step

If Cross gets built, this is the order — each piece testable in
`Main.res` style; assumes the ports migration (landed — `src/Program.res`
is ports-first; Cross is a flow node with ports, like Join).

1. **The invariance fact.** Per-node flow-variable sets in the
   annotate pass (needed by the compile rebuild anyway); the
   mutual-invariance check as a function of two flows, with witness.
2. **The Cross node** (Option A shape: oriented, flow-only), plus
   theorem-2 commute legality over it. Compile via the whole-table
   lazy; tests: the two-lists program with both orders, values
   compared against hand-built tables; an outer-stmt/golden test
   pinning that `add`'s work appears once.
3. **Completion inserts Cross** for sibling opens — replacing the
   directed-Incorporate rewrite in `time-travel-programs-design.md`'s
   smallest first step 2, which should be built straight to Cross
   rather than built twice. Tests: example 1 completes to a Cross;
   example 4 completes to Cross + Commute; a dependent-nesting
   reversal clashes with the right witness.
4. **Partial products** ride the partial-collect/filter work: a
   per-point option absorbed per-orientation; test both readings of
   one filtered table.

## N-ary products: the three-list example (open question 3, worked)

So far every example had two axes. Two axes never forced the context
model's poset to do any work: two axes have exactly one product and
one transpose, so every question the model raises is answered
trivially. Three lists are where the machinery first has to earn its
shape — which is why open question 3 asked for a concrete three-list
example before committing to "flat axis sets." Worked below: the
presumption holds, and the example exercises three things the
two-axis case could not.

The program — three lists uncollected side by side, none derived from
the others, elements combined:

```
listX -> open list => x, ~x
listY -> open list => y, ~y
listZ -> open list => z, ~z
x, y, z -> f => s
```

`s` is one value per (x, y, z) triple — a 3-axis product, an n×m×p
cube. A consuming collect chain nests the three terminations in
*some* order; there are 3! = 6 orders, and they read the cube along
its six axis permutations (the two-axis pair of transposes,
generalised).

**Associativity: the nesting tree is how you wrote it; the axis set
is what it means.** Cross is binary, so a three-axis product is
authored by nesting — `cross(x, cross(y, z))`, or
`cross(cross(x, y), z)`, or a flat three-way cross if the surface
offers one. (Prefix `cross(…)` throughout this section is schematic
exposition, not the textual form — Cross's textual spelling is owed,
open question 1.) By the law (fire once per tuple of operand firings,
each axis rides unchanged) and mutual invariance, all three build the
*same* cube: the same point set and the same top context {X, Y, Z}.
So the meaning is the **flat, order-free axis set** — exactly the
presumption, and exactly the move partial-collect made for cell sets.
Many authoring paths converge to one product; the reading is the
product, not the tree that built it ("one obvious reading per
program, however many authoring paths converge to it").

Where the nestings *do* differ is which **intermediate** products
they construct. `cross(x, cross(y, z))` builds a {Y, Z} context on
the way to {X, Y, Z}; `cross(cross(x, y), z)` builds {X, Y}; a flat
three-way cross builds neither. This is not a wart — it is the author
naming a sub-product. If they wrote `cross(y, z)` as a sub-expression
and a consumer collects over just y and z (holding x), the {Y, Z}
context is a real, wanted thing; if they wrote a flat cross, they did
not ask for it and it is absent. This is the graceful-expansion
shape: the flat product is the simple case, and naming a sub-product
is *adding structure* to reach a sub-product consumer, never a
rewrite into a different construct.

**The poset is the subset lattice of the axis sets actually
constructed** — the cell-set refinement's shape
(`bundle-provenance-design.md`, "subset lattice of constructed sets,
not a tree"), confirmed a second time and now by a different
construct. Not a tree, and not the full powerset of {X, Y, Z}: only
the axis sets some Cross built. Comparability is containment; a
combining node demands its operands lie on one chain, and `deeper` is
"the least upper bound among constructed sets, if one exists" — the
two-axis rule verbatim.

The three-list example is the first place that "if one exists" bites.
Suppose someone builds `cross(x, y)` = {X, Y} and, separately,
`cross(y, z)` = {Y, Z}, and never a common super-product. A value at
{X, Y} and a value at {Y, Z} share axis Y but are incomparable, and
there is **no constructed common superset** — {X, Y, Z} was never
built. Combining them would demand a value per (x, y, z), i.e. it
*demands the full product exist*; because it does not, the combine is
ill-formed until a Cross supplies {X, Y, Z}. This is the right
answer, and it is delivered by the existing rule (no least upper
bound ⇒ no context to combine at) and the existing remedy (insert a
Cross, gated by the invariance demand, witnessed if it fails). Two
axes could never show this — two axes have one product and always a
least upper bound. The concrete three-list example is what makes the
poset's partiality visible, and it lands on machinery already
written.

**The table indexing generalises verbatim.** A node whose
flow-variable set spans the three axes memoises at the product
context as a point-indexed cube — one entry per (x, y, z) point, `f`
run **once per point** regardless of how many of the six consumers
traverse in how many orders. Whole-table-first still suffices for the
eager fragment: one lazy builds the full cube in the stored
orientation, the other five consumers index it. The honest cost —
retention — amplifies with rank (the cube stays live until the
slowest consumer finishes), exactly as the two-axis note predicted;
under stream kinds the cube refines to per-cell `Delayed` cells, a 3D
grid. No new mechanism, more indices.

**The three theorems survive at rank 3.** *Rectangularity:* per
any-axis firing the remaining sub-product traversal is the same
sequence (mutual invariance across all axes), so nested collects over
the cube are never ragged. *Commute totality:* every adjacent pair in
any nesting of the product is *itself* a product — any subset of a
product's axes is a sub-product by invariance — so an adjacent
Commute is always defined, and the six orders are reached by chains
of adjacent Commutes (adjacent swaps generate all six permutations of
three things — the group S₃). *Kinds unchanged:* a triple-nested
crossed flow presents as ordinary triple nesting downstream. The
"represent one orientation, read the rest" lean carries: the stored
form is one of the six permutations, and each other reading is a
faint Commute-chain away — and the reading is the *permutation*, not
the chain, because the naturality quotient identifies any two
adjacent-Commute chains realising the same permutation (the symmetry
of a Cartesian product is coherent).

**Lean.** Represent n-ary products as flat axis sets — the meaning is
the set; the binary-Cross nesting tree is authoring detail that
additionally names whichever sub-products the author bound. Keep the
poset as the subset lattice of constructed axis sets, with `deeper` =
least-upper-bound-if-it-exists and no-lub routing to "insert a
Cross," both already in the two-axis rules. Nothing new is needed at
rank n that rank 2 did not already carry; rank 3 is where the
*partiality* of the poset and the S₃ orbit of orientations first
become observable, and both were caught by existing machinery — the
sign that "flat axis sets" was the right presumption to commit to.

Two residues, both minor, filed to their owners rather than worked
here:

- **Which orientation is canonical for a flat n-ary cross** (which of
  the six the stored form picks, and how completion chooses it) is
  the n-ary face of open question 1 and the textual form's
  Cross-spelling question — does the text name a full permutation?
  Two axes name at most a single swap; n axes name a permutation.
- **A fold or a join over the cube** demands a single traversal order
  that the order-free product does not supply. The register half is
  now worked ("Registers over products", question 5): a register
  folds *along a named axis*, and a full cube reduction is the S₃
  axis-permutation this section identified, wearing its register hat
  — the order chosen at the consumer, as with two axes. The join half
  is now worked too ("Join on a product", question 4): the cube's
  linearization is a chain of joins whose operand sequence is the
  permutation, drawn as data on the page.

## The aligned product (zip): Cross's positional sibling

Cross is one of two ways two flows combine, and until now the chapter
has only worked the one. Cross pairs *every* firing of one flow with
*every* firing of the other — independent extents, an n×m table,
mutual invariance. Its sibling pairs firing *i* with firing *i* — one
shared extent, paired by position. That is the **aligned product**,
working name **zip**. The two are the products row's pair: Cross
multiplies firings, zip identifies them.

The demand for zip is not speculative. Three comparison studies
converged on it independently: APL's pervasion (`1 2 + 3 4`) is the
array family's single most-used operation and its ground floor —
blend, interleave, weighted average, inner product, and
sort-one-by-another are all instances (`apl-family-comparison.md`,
finding 2); Zig makes multi-object `for (a, b) |x, y|` the *primary*
loop construct, arriving at aligned pairing from the imperative side
(`zig-comparison.md`, finding 3); and the tidyverse's data frame is k
equal-length columns whose row view and column view are one value
(`tidyverse-comparison.md`, finding 1). Until this round the only zip
in the record was a *compile-level* stream primitive (the
multi-parent zip of `lazy-stream-placement-design.md`) — mechanism
without authoring vocabulary. Conway's Life is the record's one
localized representation struggle precisely because it needs *both*
products at once — Cross to enumerate the 3×3 neighborhood, zip to
overlay nine same-shape grids pointwise (`apl-family-comparison.md`,
§9).

### The program that demands it

Start again from a small program. A pointwise combine of two lists
the author means to walk together:

```
xs -> open list => x, ~x
ys -> open list => y, ~y     -- meant as the same walk as xs, by position
x, y -> add => s
s -~> collect => out
```

Nothing drawn says the two walks *are* the same walk. Read as it
stands, the two uncollects are independent, and their only lawful
product is Cross — an n×m table, when the author meant the length-n
diagonal. The gap is that the language has no way to say "these two
walks advance together," just as (before Cross) it had no way to say
"these two walks are independent." Same missing vocabulary, opposite
fact.

### The construct

The aligned product is a flow operation in the Cross / Commute /
binary Join species: a node with flow ports and **no value ports**.
Its shape is the mirror of Cross's:

- **Inputs:** two (or more) flows of the **same extent**.
- **Output:** **one** flow — *not* nested. Both lanes ride the same
  firings; the barrier *widens* the walk with the second lane's value
  wire rather than multiplying its firings. (This is the visible
  contrast with Cross, whose output is nesting.)
- **Demand:** the operands are **co-extent** — the same firing
  structure.
- **The law:** *the aligned flow fires once per shared firing; each
  lane's element rides that firing.*

Consequences of the law, as short theorems mirroring Cross's:

1. **No new firings.** The output has exactly the shared extent; a
   collect over it is length-n, never n×m. This is what tells zip and
   Cross apart at the site of use — same two operands, different
   barrier, different extent. (Cross's theorem 1 was rectangularity;
   zip's is that it adds no rows at all.)
2. **Values ride, they don't pack.** Both lanes' elements are
   readable at the shared firings by the ordinary invariance rule; no
   tuple is built to carry them across. The wires stay separate wires
   — the no-bottleneck shape, a barrier with corresponding inputs and
   one widened output.
3. **Kinds unchanged downstream.** The widened flow presents as an
   ordinary flow; a collect, join, or register consumes it with no
   zip special case — exactly as a crossed pair presents as ordinary
   nesting.

### The witness of co-extent — the one real asymmetry with Cross

Cross and zip are not quite symmetric, and the asymmetry is this
round's central finding. **Cross's demand (mutual invariance) is
always structurally checkable** — the flow-variable set is the
annotate pass's per-node fact, and siblinghood-at-authoring-time
witnesses independence. **Zip's demand (co-extent) is structurally
checkable only sometimes.** Two regimes fall out, distinguished by
the same provenance the invariance demand already computes:

- **Same-provenance zip — structural, and free.** When both lanes
  trace back to *one* uncollect through extent-preserving operations
  (value-only maps, per-firing work — anything that neither opens nor
  collects nor filters), they fire in lockstep *by construction*.
  Their co-extent is not a claim to be checked; it is one walk
  carrying two wires. Here zip is degenerate: it re-bundles wires
  that already share firings. This is the common case and it costs
  nothing — the analog of Cross reading independence off siblinghood,
  run the other way. In particular, **k sibling collects of one walk
  are aligned by this rule** — which is why the value form below is
  the same construct, not a new one.

- **Distinct-provenance zip — a barrier assertion.** When the lanes
  come from *different* uncollects (two independently sourced lists
  claimed to be equal-length), co-extent is not structural; it is a
  runtime coincidence. The node then carries a **co-extent
  precondition asserted at the barrier** — checked once, at the
  walk's start, not per firing — with a **terminator/witness when it
  fails** (the shorter lane runs out). Raggedness here is a
  *failure*, the exact opposite of Cross's per-point regime where
  absence is a hole in the table and both readings survive.

The honest one-liner: **Cross's independence is always static; zip's
co-extent is static under shared provenance and a runtime
precondition otherwise.** Two shipped languages put the check exactly
at the barrier and not per element — Zig asserts length-equality "at
the start of the loop" and APL raises a conformance error before the
pervasion runs. So the co-extent demand is a property in
`types-design.md`'s sense where provenance discharges it, and a
checked precondition with a failure witness where it does not — one
construct, two discharge paths, chosen by whether the annotate pass
already proves the extents equal.

### The value form — the multi-wire collect and the table

The aligned product has a rest state, and it is the missing half the
tidyverse study named. A **multi-wire collect** takes several wires
of one flow at one barrier and produces a value that keeps their
correspondence: a **table** — k value wires become k columns, n
firings become n rows, cell *i* of every column belonging to firing
*i*. Its **uncollect gives the wires back**, already aligned (a
same-provenance zip of the columns, aligned because they were
collected together). The flow-level pairing and the value-level table
are one construct seen from both sides: *a table is k lists that
remember they were collected from the same walk.*

Now, you might wonder why the table doesn't open into one row-struct
per firing — a record with a field per column, the way a data frame
hands you rows. It turns out the value opens into k **wires, not one
row-struct**, and the tidyverse corpus argues the point three times
over:

- **The row-splat wart.** `pmap(df, f)` splats every column into
  `f`'s arguments, so a consumer of two of three columns errors on
  the unused third. On wires, an unused column is simply an
  unconnected port.
- **The arity matrix.** map / map2 / pmap × typed suffixes is a
  combinatorial family that exists only because aligned inputs arrive
  as loose values; dplyr documents retreating from it and re-adding
  `rowwise()` so the table itself carries the alignment. The whole
  matrix collapses to one uncollect when the aligned wires are a
  drawn fact.
- **Suffix collisions.** Joins auto-rename colliding columns `.x` /
  `.y` — the one-namespace cost of packing wires into a single field
  set. Wires don't collide; names label wires, they don't key a
  lookup.

The column axis is the *wire* axis (drawn structure — names, types,
one per variable); the row axis is the *firing* axis (runtime
extent); their non-independence is rectangularity — every firing
carries every wire. k sibling collects that *forget* they shared a
walk are the record's current state; the table is those k lists
*remembering* it, and remembering is the whole content.

### Scalar extension is Incorporate, not zip

You might wonder why a lone value can't silently pair with a flow the
way APL pairs a scalar with a vector — APL's scalar-extension rule
lifts a lone value to pair with every element, no ceremony. In our
vocabulary that rule reads as **Incorporate's implicit costume**: a
value made available at every firing. That is auto-capture, already
silent, and it is emphatically *not* the aligned product. Zip pairs
two flows; Incorporate lifts a value into one. Keep them distinct.
For the clash record: APL's implicitness is a hazard — a rank
mismatch that happens to conform silently computes the wrong program
— so the value-into-flow lift stays a drawn Incorporate, and the
co-extent assertion above is what catches a genuine two-flow
mismatch, never an inferred rank rule that papers over it. (Implicit
scalar-to-flow lifting as a zip rule is a settled rejection — please
don't re-propose it without new evidence.)

### Indices as an aligned lane

Zig's `for (items, 0..) |item, i|` derives the index's extent from
its sibling: the index is not a loop mode, it is one more aligned
lane. In our vocabulary an **index is a counted source opener**
(`source-openers-design.md`) with no independent extent, zipped
against the data flow, which fixes its length — the aligned product's
degenerate lane where one operand borrows the other's extent.
Same-provenance keeps it free: the index lane is aligned with the
walk it counts by construction. This answers the translation
exercise's open note on whether iteration-by-index deserves better
than `range(len(a))` plus two index applications (finding 10) — it
does, and the better form is a zip lane, not a new construct.

### Rank-2 and n-ary — the Life residue

Conway's Life needs Cross (enumerate the 3×3 neighborhood) and zip
(overlay nine same-shape grids pointwise) at once, at rank 2 — the
grids are 2D. The aligned product makes Life *drawable*; the round
that established the construct filed the rank-2/axis-handling
residue forward rather than working it. **It is now worked below**
("The Life residue, worked") — the overlay turns out to be the
*flow-arity* face of this same construct, landing on the transpose
under a co-extent license, and the "axis handling" half of the
filed question dissolves.

### Per-edge alignment (a second target, filed)

purrr's `reduce2` aligns its second input with the **gaps between**
firings — one element shorter, used for separators
(`reduce2(letters[1:4], c("-", ".", "-"), …)`). Not every aligned
lane is firing-to-firing: the edge between consecutive firings is a
distinct, shippable alignment target, adjacent to the register's
previous-firing machinery. Noted as a residue for the iteration-state
round rather than worked here — the aligned product's primary case is
firing-aligned, and edge-alignment is one added lane offset, not a
different construct. (Set aside for the register round, not
rejected.)

### The Life residue, worked: rank-2 alignment and the flow-arity zip

The record's one localized representation struggle
(`apl-family-comparison.md`, §9): Scholes's Life is a one-liner in
APL — nine shifted copies of the board, summed pointwise, the rule
pervasive arithmetic — and the filed verdict was "drawable only
after the aligned product exists, and clumsy at rank 2." This
section draws it end to end and extracts what the clumsiness
actually was. Two of its three parts dissolve into machinery this
chapter already has; the third is a catalog demand, filed where
catalog demands go.

The program, in provisional spelling throughout:

```
offs = [1, 0, -1]
offs -> open list => dr, ~dr       -- bind once, walk twice:
offs -> open list => dc, ~dc       --   two independent offset axes
~dr, ~dc -> cross                  -- 9 offset firings; (0,0) included

board, dr, dc -> rotate => shifted -- one whole shifted grid per firing

shifted -> open list => srow, ~row -- the nesting: offsets > rows > cells
srow    -> open list => s,    ~cell

-- the overlay: transpose the offset axis innermost, two adjacent
-- swaps (offsets ↔ rows, then offsets ↔ cells), each licensed by
-- co-extent:   offsets > rows > cells  ~>  rows > cells > offsets
s -~> collect by add => n          -- per position: nine values summed

-- the rule, pointwise on the original board — a rank-2
-- same-provenance zip of board's walk with the transposed walk:
board -> open list => brow, ~brow
brow  -> open list => b,    ~bcell
n -> eq3 => born                   -- Scholes: sum counts self, so
n -> eq4 => four                   --   next = (n=3) ∨ (b ∧ n=4)
four, b -> and => survives
born, survives -> or => next
next   -~> collect => nextRow      -- close cells
nextRow -~> collect => nextBoard   -- close rows
```

Cross for the offsets and a whole-value `rotate` per firing were
always comfortable. The two moves that were not, and what each turns
out to be:

**The overlay is the aligned product at *flow arity* — and that is
the transpose.** The zip drawn earlier in this chapter has *drawn*
arity: k lanes, k wires into one barrier. Life's nine lanes are not
drawn — they are the *firings of the offset flow*, and unrolling
them into nine wires would trade the offsets' data-ness away.
Aligning lanes that arrive as a flow means turning
`offsets > positions` into `positions > offsets` — and that
operation already has a name: the transposing commute. The commute
taxonomy (`lazy-stream-commute-design.md`, the Transpose row) gates
transpose on rectangularity and names two suppliers: a Cross, which
supplies it *by construction*, and "the tabular container… where
rectangularity comes from the data." This section fills in the
second supplier: **rectangularity-from-data is exactly co-extent,
and it is established the two ways co-extent always is** — proved
by shared provenance (all nine grids derive from one `board`
through shape-preserving `rotate`, so their walks are co-extent by
construction) or asserted at the barrier with a failure witness
(APL's conformance error, one check per swap, never per element).
One license — extent invariance across the swapped axis — three
suppliers: constructed (Cross), proved (provenance), asserted
(precondition). The k-lane zip and the licensed transpose are one
fact at two arities, the way the filter and the partial collect are
one construct at two widths. At rank 2 the transpose is a chain of
two adjacent swaps, which is nothing new either — the S₃
adjacent-swap story from the n-ary section, with a license per swap
instead of a blanket product. (One pleasant corollary of licensing
per swapped axis: the board need not be rectangular. Nine
*identically ragged* grids overlay lawfully — the swaps past
`offsets` need invariance across offsets only — which the array
family's rank-2 container cannot even represent.)

**The transposed shared axes are position-only, and that is already
zip's law.** After the transpose, whose row walk is the `~row`
axis? All nine, identified — and the identified axis carries no
element of its own, because the row *value* still depends on which
grid, readable only with the offset level open. This is not a new
wrinkle; it is the aligned product's law read at flow arity: *the
aligned flow fires once per shared firing and carries no element —
each lane's element rides that firing.* The shared axis is pure
position — the same fact as the index lane ("indices as an aligned
lane" above): position is the one thing co-extent walks genuinely
share.

**Zip has no axis handling.** The filed residue asked how a rank-2
zip picks which axes align. Worked, the question dissolves:
alignment is positional at *every* level, levels are paired in
drawn nesting order, and the license composes levelwise (outer
extents equal; per-position inner extents equal — one
shared-provenance discharge covers all levels at once, which is
what the final zip of `board`'s walk against the transposed walk
uses). Pairing grid A's rows with grid B's *columns* is not a zip
parameter — it is a drawn transpose upstream, then the ordinary
levelwise zip. Axes are commute's business; alignment never
permutes, so it never names axes. The n-ary half of the filed
residue was already worked (flat axis sets, above); with the axis
half dissolved, the Life filing is closed.

What remains, honestly:

- **The catalog demand — shape preservation as a property row.**
  The shared-provenance discharge walks through `rotate`, a
  whole-value App, and provenance through a value App is opaque:
  the nine grids are nine different values, co-extent only because
  rotation preserves shape. So the proved regime needs an
  **extent/shape-preserving** catalog property (a row with a
  witness, like the collect family's identity rows) for the ops the
  walk crosses — permutations, `reverse`, `rotate`, per-element
  maps. Without the row, the program still draws: the license falls
  back to the asserted regime, which is precisely APL's runtime
  conformance error. Files to the checking row's catalog-schema
  question (`types-design.md`, question 4), its third client after
  the identity rows and the lane references. (That round has since
  been worked — `catalog-schema-design.md`, exploration: shape
  preservation is a laws-family row whose witness is the extent
  equation displayed across the op, and the fall-back-to-asserted
  behaviour above is its severity grading: a missing row is not
  even a warning.)
- **The gate-widening edge.** The transposing commute is gated to
  constructed products today (`Context.throughCommutes` and the
  taxonomy's Cross case); admitting the proved and asserted
  suppliers widens that gate and should be reconciled with the
  commute taxonomy's rows and, eventually, Check's join-adjacency
  carve-out. Design-side this section is that reconciliation's
  input; nothing here touches code.
- **The stencil alternative.** Life can also be drawn without nine
  whole-grid rotations — read the neighborhood by index within one
  walk — and that is the window/stencil family's territory
  (`variable-rate-consumption-design.md`'s fixed-length-segment
  question, APL's 2D-window filing), not this chapter's. The
  Scholes construction was chosen *because* it is the no-indexing
  form.

Now, you might wonder whether the language should have a **rank-2
zip node** — an aligned product parameterized by which axes align,
so Life's overlay is one barrier instead of a transpose chain plus
levelwise alignment. It turns out the parameter would duplicate
drawn vocabulary as annotation: alignment is positional at every
level (there is nothing to parameterize once the nesting order is
drawn), and any non-default axis pairing is a commute upstream —
so the parameterized node would carry, as configuration, exactly
the information the drawing already states, the two-sources-of-
truth shape the record refuses everywhere. (This is a recorded
dead end — please don't re-propose it without new evidence.)

You might also wonder whether grids deserve their own **rank-2 flow
kind** — a "grid flow" whose firings are cells with row/column
structure, so Life never stacks two opens. It turns out rank is
nesting depth, already owned: the two-level walk, the transpose
chain, and the levelwise zip each reuse machinery every other
program shares, while a grid kind would re-own iteration, product,
commute, and alignment as kind content — the "one construct
re-deriving the vocabulary" shape the custom-flows round warns
against. The array family's evidence cuts the same way: APL's rank
is uniform nesting plus laws, not a second iteration concept.
(Recorded dead end.)

### Against the philosophy

- **Example first, then generalise.** The pointwise-combine program
  is the concrete gesture; the aligned product is the identified
  relationship (co-extent), read off shared provenance where present
  — never declared upfront.
- **No bottlenecks.** A barrier with corresponding flow inputs and
  one widened output, no value packing — the principle's own shape,
  the positional twin of Cross.
- **Building blocks at the programmer's abstraction level.** "Walk
  these two lists together" is a programmer-level concept (every zip,
  every data frame holds it); the index-plus-lookup encoding was the
  plumbing-level costume.
- **Graceful expansion.** The simple case (two same-provenance wires)
  is free; adding a distinct-provenance lane *adds* the co-extent
  assertion — structure added, never a rewrite into a different
  construct. The table is the same construct at rest; opening it adds
  no construct.
- **Abstraction is the source of truth.** The table is k lists that
  remember one walk; the loose k lists are the derived, forgetful
  view. Provenance is the truth; alignment is the fact retained from
  it, free and downward, exactly as with Cross's independence.

### Building it: smallest first step

Ordered so each piece is testable in `Main.res` style; assumes the
ports migration (landed — `src/Program.res` is ports-first).

1. **Same-provenance recognition.** The provenance/flow-variable fact
   already needed for Cross's invariance demand, run the other way:
   two wires are co-extent iff they trace to one uncollect through
   extent-preserving ops. Free zip is then a re-bundle, no node
   emitted.
2. **The aligned-product node** (flow-only, co-extent demand), with
   the barrier assertion plus failure witness for the
   distinct-provenance case. Compile: the stream-level multi-parent
   zip primitive already exists (`lazy-stream-placement-design.md`) —
   the gap was authoring vocabulary, now supplied. Tests:
   pointwise-combine of two lists, same-provenance (free) and
   distinct-provenance (asserted); the distinct-ragged case fails at
   the barrier with the shorter lane as witness.
3. **The multi-wire collect / table** as the value form: k wires in
   at one barrier → a k-column value; uncollect → k aligned wires.
   Tests: a table round-tripped through collect/uncollect preserving
   alignment; a two-of-three-column consumer leaves the third an
   unconnected port (no row-splat error).
4. **Index-as-lane and per-edge alignment** ride source openers and
   the register round respectively — not built here.

## Registers over products (open question 5, worked)

A product is order-free by construction — its points carry a poset,
not a sequence, and that order-freedom is the whole content of Cross
(each consumer traverses in its own order,
`time-travel-programs-design.md`). A register
(`iteration-with-state-design.md`) is the opposite: it threads a
carried value from one firing to the next, so it *demands* a
sequence. Open question 5 asked what a register over a product means
when the product supplies no order.

Worked below: the register does not fold **over the product**; it
folds **along one of its axes**, fibered over the rest — run once per
value of the other axes — the APL reduce-along-an-axis shape. And
once that is seen, everything else (the orientation it pins, its
result's rank, productivity, the running view) is the ordinary
register meaning already worked, applied per fiber. Nothing
product-specific remains except the choice of *which* axis — and that
choice turns out to expose an **open question about what a Delay
itself is**, which is the round's real lesson. Which flow fixes the
register's axis? Two candidates (`delay-ontology-design.md`): the
**collect** that binds the register (so the axis is a consumer's
choice), or the **ancestor uncollect** the carried value descends
from (so the axis is fixed at the Delay, independent of consumer).
The results in this section — reduce along *one* axis, fibered over
the rest — hold under both; only the attribution of *who names the
axis* differs. And the product is where the sharpest evidence lives:
the shared-grid implementation (iterate once, store the n×m table,
transpose for the other consumer) **breaks** if a register's axis
depends on which consuming collect reads it (the two consumers would
need two different grids), which cuts toward fixing the axis *at the
Delay* — the ancestor-uncollect candidate. The ontology round weighs
this as a real cost on collect-binding rather than a knockout
(recompute-per-consumer is a legitimate implementation), so the fork
stays balanced. Recorded there as open; below, "the register's axis"
means whichever flow that question settles on. (The question has
since been worked in its own round —
`product-linearization-design.md`, exploration, unadopted — whose
claim is that the axis is *neither* candidate: it is the drawn
orientation this chapter already stores on the Cross node, read
through "represent A, read B," with an orientation-pinning demand
where an order-observing consumer sits downstream. Everything in this
section is independent of that outcome and transfers verbatim.)

### The program that demands it

A running sum over a crossed pair — two lists, their pairwise sums,
and now an accumulator:

```
xs -> open list => x, ~x
ys -> open list => y, ~y      -- sibling of xs; cross, not zip
x, y -> add => s              -- one value per (x, y) point: an n×m table
```

`s` is a value at the product context {X, Y}. Now put a register on
it. The question the order-free table forces immediately: **a running
sum in which direction?** Down each column (accumulate over x, one
running total per y)? Along each row (over y, per x)? Over the whole
thing (one grand total)? Three different programs, and the product —
deliberately — names none of them. The register has to say which, and
*saying which is the entire design question*. In the register
spelling the choice is visible as which flow the delay names — and
nothing in the symmetric wiring supplies it:

```
-- spelling provisional; the delay's flow reference is the axis choice
~x ~> delay init 0 => run             -- along X: fold down each column…
run, s -> add -> step of run => colTotal   -- …final = one total per y (a Y-flow)
```

versus `~y ~> delay …` (along each row, final an X-flow) versus the
plain scan's `~L ~> delay` with no `~L` to infer — the `~?` the
ontology round works from (`delay-ontology-design.md`, "The product
sharpens both").

*(Consistency pointer, added 2026-08-12: the `~x ~> delay` spelling
above predates the thread ergonomics round
(`iteration-with-state-design.md`, 2026-08-04) — the register has
no flow operand; its frame is derived from the thread's anchors,
with an annotation for the residue. The design question this
section states — "saying which is the entire design question" — is
unchanged and sharpened: the symmetric wiring is exactly the case
where derivation is ambiguous, so the product is the flagship
client of the **mandatory pin** — the thread names which axis's
"next" it accesses (`delay-ontology-design.md`, "The frame menu";
the product layer's fibering offer). Read `~x ~> delay init 0 =>
run` as: a register whose thread is pinned to the X axis.
Everything else in this section transfers verbatim.)*

### The finding: reduce along an axis, fibered over the rest

The answer is the array family's, item for item
(`apl-family-comparison.md`, finding 1: `/` reduce and `\` scan *fold
or accumulate along an axis*). A register over the product {X, Y}
folds **along one axis** — call it its axis, say X (which flow fixes
it is the open question above) — meaning:

> for each fixed y, run an ordinary register along the X-fiber; state
> does not cross between different y's.

That is `+/[X]` (Dyalog `⌿`, BQN `˝˘`): reduce the matrix along the X
axis, producing one result per y. The register's `final` output is
therefore not a scalar but a **Y-flow** — rank n−1 (one fewer axis),
the reduced axis gone, the surviving axes still a flow. A register
along Y instead fibers the other way and yields an X-flow. The order
it pins is only the **within-axis** order of its axis — which every
list axis already carries — and the product's **cross-axis**
order-freedom is never touched, *because state never crosses axes*.
Rectangularity (theorem 1) is what makes this well-formed: every
X-fiber is the same sequence of firings for every y, so "run a
register along the X-fiber" is defined identically at each y.

**A register over a product is just an ordinary register whose
surrounding context is the other axes.** The product context is
deeper than each axis ("The context model"); a register-along-X is a
register whose iterated flow is the X axis and whose seed lives in
the Y context — exactly the shape of a register nested inside an
outer list loop, which the register design already covers. The only
thing the product adds over a plain list is that the flow has more
than one axis, so *which* axis the register threads along is no
longer forced. You might wonder whether a register could just reduce
"the whole product" as one sequence, no axis named. It turns out that
is ill-formed for the ordinary reason (no order exists), with the
remedy being "fold one axis, or Join first" (below) — and one
principled exception, the commutative case, also below. No new
register machinery — the product just made the axis a live choice,
whose resolution is the open Delay-ontology question.

### The orientation is minimal

The oriented traversal question 5 flagged is real, but it pins
**less** than a linearization. In a symmetric product {X, Y} neither
axis is outer; to run a register along X *fibered over* Y you must
read the product Y-outer/X-inner. The register along X induces
exactly that orientation and no more: it puts the reduced axis
innermost and leaves the fibering axes outer, still a product, still
order-free among themselves. This is "orders live at terminations;
the order is chosen at the consumer" (Option B) with the register as
one more consumer — it orients the product only to the depth it folds
and hands the rest onward unoriented. For an n-cube, folding X leaves
an (n−1)-subcube outer, which the next consumer orients (or reduces)
in its turn. (Whether the orientation "lives at" the binding collect
or is fixed at the ancestor uncollect is the open question above;
either way it is this-minimal.)

### The inner-axis vs outer-axis cost

Reduce along *which* axis is not cost-neutral, and the asymmetry is
where an outer-loop accumulator hides. Take the product traversed
X-inner, Y-outer:

- **Register along the inner axis (X).** Consecutive firings of the
  X-fiber are adjacent in the traversal, so the register *streams*:
  accumulate across the inner sweep, reset the seed at each new y.
  One live accumulator, no retention — the cheap, obvious case.
- **Register along the outer axis (Y).** "Previous" now means the
  previous *outer* iteration's element at the same inner position —
  the value at (x, y−1), which the traversal visited a whole inner
  sweep ago. Realizing it means **storing the entire previous inner
  list (the previous X-fiber) and zipping it positionally with the
  current one.** The Y-register is fibered over X, but because X is
  traversed *inside* Y, its |X| parallel fibers all advance once per
  outer step, so the whole fiber must be retained across the inner
  sweep.

The store-and-zip is not a wart — it is exactly what an **accumulator
over an outer loop** *is* (compare this row to the previous row;
carry a per-column running total across rows), and wanting that is
not infrequent. So a register over a product carries a real cost
gradient — the inner axis streams, any outer axis retains a fiber —
and choosing the axis is also choosing the cost.

This is also the mechanical fact behind a point in the Delay-ontology
debate (`delay-ontology-design.md`): the two orientations of a
register are not two readings of *one* grid, they are two *different
computations*. The base value grid (`s = x + y`) transposes for free,
but a **scan** along X (`sum over x′≤x at fixed y`) and a scan along
Y (`sum over y′≤y at fixed x`) are different grids — not transposes
of each other — and a **reduce** along X (a Y-flow) and along Y (an
X-flow) are different outputs. So there is no single grid a register
can build once and serve both orientations from (outside the
commutative case below); a consumer that wants the other orientation
drives a genuinely different computation, which is why "re-run the
register per collect" is a legitimate implementation and not merely a
failure to share.

Reducing a rank-n product **all the way to a scalar** is *n* nested
registers — one per axis — not one register over the cube.
Register-along-X gives a Y-flow; a register-along-Y over *that* gives
a scalar. The nesting order is an **axis permutation**, and — the
point — it is a genuine choice with genuine consequences: the
register is not assumed commutative, so reduce-along-X-then-Y and
reduce-along-Y-then-X are different computations (as `+/+/M` and a
non-commutative `⍤/⍤/M` differ in the array world). This is the S₃
orbit of the n-ary section wearing its register hat: the six
orientations of the cube are the six axis-permutations a full
reduction can pick, and the author picks one exactly as they pick a
collect chain's nesting order. No orientation is canonical; each is a
different, legitimate fold, and the product kept all six available
precisely so the register could choose.

### The one order-free exception: a commutative monoid

There is exactly one case where a register *may* reduce over the
whole product with no axis named, and it is the register-level twin
of the A-vs-B confluence argument. When the operator is a
**commutative** associative operator with an identity (a commutative
monoid — `+`, `×`, `min`, `max`, count, set-union: an operator where
the grouping and the order of operands both wash out), every axis
order and even every linearization give the same result: `+/,M`
(ravel then sum) equals `+/+/M`, and the pick is unobservable. So a
**reduce-close** (`iteration-with-state-design.md`'s monoid fold, the
"just sum the table" operation) over a product is well-defined and
order-free *iff its operator commutes* — the operator's own law
discharges the order demand the way shared provenance discharges
zip's co-extent demand and the way the invariance demand makes
Cross's non-pick meaningless. The letter of "a fold needs an order"
is relaxed exactly where it is provably meaningless. A
**non-commutative** register (or a reduce-close on a non-commutative
operator — string concatenation folded over a table) must name the
axis or the axis permutation; commutativity is the property in
`types-design.md`'s sense that, when present, lets the whole-product
reduction stand. This lands the collect family's identity/algebra
machinery (`collect-family-design.md`) a second job: the catalog row
that carries a monoid's identity can carry its commutativity too, and
commutativity is the witness that "reduce over the product" needs no
orientation.

### Productivity transfers verbatim

The register's productivity check — *every cycle passes through a
Delay crossing; delete each crossing and the graph is acyclic*
(`iteration-with-state-design.md`) — carries over with **no new
machinery**. Within each fiber the register is an ordinary
along-one-axis register, and the Delay crossing (`step → prev`) is
still the only iteration-boundary edge. Fibering does not add edges;
it instantiates the *same* structural crossing once per point of the
reduced-away axis's complement, each fiber's run grounded by its own
seed (`init`, one value per outer point, evaluated in the outer
context — it may vary with the fibering coordinate but never with the
iterated axis, the ordinary "no time travel" rule). In the stored
form the check stays a **theorem**: the pairing (write → read) is
still the only edge running with an object pointer, so every
computation cycle still passes through one, and the fibering is a
runtime multiplicity of that one crossing, not a new edge.
Non-productive register-over-product programs are unrepresentable for
the same reason plain non-productive registers are.

### The running view keeps the shape

The register's running view — the state port of its derived augment
form (`variable-rate-consumption-design.md`) — over a product is
`+\[X]` (scan along an axis): it keeps the **full product shape**
(rank unchanged), the value at each point being the accumulation so
far along X *within that point's fiber*. This is the ordinary running
view applied fiberwise, and it inherits BQN's observation that a scan
never needs an identity (finding 8) — here it also never needs a
cross-axis order, because the running value at a point depends only
on that point's own fiber up to that point. So the two readouts of a
register over a product are: `final` (reduce, rank n−1) and the
running view (scan, rank n) — the same pair a register over a list
gives, one rank higher.

### Boundary with question 4: the linearized fold is Join-then-register

You might wonder about the reading the product *does not* give —
thread state through **all** the points in one linear walk, state
carrying from the end of one fiber into the start of the next. It is
not lost; it is a **different program**, and a composed one. It is
exactly the list-monad linearization the chapter already declined for
Cross ("Not the list monad"): flatten the product to a single
sequence, committing row- or column-major, then fold. In our
vocabulary that is **Join the product** (which commits an orientation
via Join's (outer, inner) operands — question 4) **then an ordinary
register** on the resulting single-axis flow. Two constructs, a
composition, no new meaning — and the clean separation of questions 5
and 4: the register over a product folds *along an axis* and needs no
linearization; the register over a *joined* product folds a linear
walk and gets its order from the Join. Question 5 never has to
re-derive linearization, and question 4's operand-walk rules are
where the row/column-major choice is spelled (now worked — "Join on
a product": the choice is the chain's operand sequence).

### The state thread over a product (the drawing)

Question 5 also asked what this means for the state thread's drawing
(the fourth-option surface, `iteration-with-state-design.md`). A
thread crosses "the single generic iteration column"; over a product
there are several axes, and the thread crosses **only its axis's
column**, replicated (fibered) across the others. Reducing a matrix
along X is a *family of parallel threads*, one per y — the APL `+/`
picture exactly (sum each column → a row of totals): each thread
enters at its fiber's seed (which may vary with y), taps and writes
back down its own column, and exits into the `final` Y-flow.
Iteration already draws 2D (position across, computation down), so a
register along one axis of a product is naturally a plane's worth of
parallel threads tiled along the fibering axis — the visual side's
question, but the representation is: n−1 axes of independent thread
copies over the register's one iterated axis. Dense cross-referencing
across threads (Fibonacci's shape) is an independent matter — it
lives *within* a fiber and contracts to Delay points there, as on a
plain list.

### Against the philosophy

- **Example first, then generalise.** The running sum over a table is
  the concrete gesture; "along which axis" is the identified
  relationship, read off the register's named iteration axis — never
  a fold-shape declared upfront.
- **No bottlenecks.** The register folds one axis and leaves the rest
  as flow; nothing is packed into a tuple to carry the un-reduced
  axes across the fold. The result is a lower-rank flow,
  corresponding axes riding through — the principle's own shape at
  the register.
- **Building blocks at the programmer's level.** "Running total down
  each column" is a spreadsheet-level concept; the
  linearized-then-folded encoding was the plumbing costume, and it is
  still reachable (Join first) when actually wanted.
- **Foundations before features.** The construct is the ordinary
  register plus one obligation (name the axis), admitted by a forcing
  program (the three-direction ambiguity), with the commutative
  exception recorded as the one place the obligation lifts.
- **Abstraction is the source of truth.** The order-free product is
  the truer description; the register's axis is a minimal induced
  orientation (innermost only) and downward — the same lens shape as
  Cross's stored orientation, now at the fold.

### Smallest first step

Rides the register round and the Cross node; testable in `Main.res`
style once first-class ports and Cross land.

1. **A register over a product folds along exactly one axis.** The
   check rejects a whole-product register with the "no order"
   witness, the remedy being "fold one axis or Join." (For a
   commutative-monoid reduce-close, the requirement lifts — the
   catalog row's commutativity flag discharges it.) Which flow fixes
   that axis — the binding collect or the ancestor uncollect — is the
   open Delay-ontology question and must be settled before this is
   built; the shared-grid argument (intro) leans it toward a fixed
   ancestor axis.
2. **Reduce along an axis.** Compile a register-along-X over a
   crossed pair to a per-fiber accumulator (one register run per y),
   `final` a Y-flow; test against a hand-built table of per-column
   sums, and against a non-commutative fold to pin that axis order is
   observable.
3. **The running view** (scan along an axis) keeping full product
   shape; test the point-indexed running values against a hand-built
   scan.
4. **Full reduction as an axis permutation** — two nested registers
   over a cube in both orders, values compared to confirm the orders
   differ for a non-commutative operator and agree for a commutative
   one.

## Join on a product (open question 4, worked)

Status of this section: exploration (worked 2026-08-02), not
adopted. Question 4 asked for one thing — the operand-walk rules
extended to join chains that span a product's axes and an enclosing
flow — and this section works them. The finding, in one line: **a
join chain over a product is an orientation-authoring surface — the
walk consumes the product segment axis-by-axis, each consumption a
drawn commitment of that axis to the current depth — and the
extension adds no new witness species.** Where this section touches
`product-linearization-design.md` (exploration, unadopted) the
relationship is consistency, not dependency; the alignment is
called out where it occurs.

### The program that demands it

The report-writer — survey 4's everyday client for spanning ordered
emission (`real-loop-survey.md`, finding 4.2) — over a per-company
table:

```
companies -> open list => co, ~co
co.depts    -> open list => d, ~d      -- two axes, opened per company
co.quarters -> open list => q, ~q
~d, ~q -> cross                        -- the per-company table
d, q -> cell => r                      -- one revenue cell per (dept, quarter)
```

The report wants one flat flow of lines, company > dept > quarter:

```
~d, ~q  -> join => ~dq                 -- commits dept-major
~co, ~dq -> join => ~line              -- absorbs the pair into the company walk
r -> format => txt
txt -~> collect => report              -- flat, in the committed order
```

Two joins, a chain spanning the product's axes *and* the enclosing
flow. Every rule this section states is readable off this program.

### The linear walk rule, stated once

The existing rule is implicit in the join round's adjacency demand
and explicit only in code (`unwrapJoinedRef`/`walkOpenerChain` —
the functions the retired first-class-ports round said "become the
operand walk" — see `src/ARCHITECTURE.md`). Stated once, so the
extension has something to
extend: **a join chain denotes a contiguous segment of the nesting
chain, and adjacency between operands is checked between
constituents** — the outer operand's *innermost* constituent must
be the immediate parent of the inner operand's *outermost*
constituent. (`join(E, join(A, B))` checks E against A;
`join(join(E, A), B)` checks A against B.) The combined flow is
identified with the outer operand — absorption — so a chain's
output context is its outermost constituent's, extended by
everything absorbed. Two immediate consequences the record already
uses: chains compose associatively (any bracketing that consumes
the same levels in the same order is one combined flow — same
firing set, same order), and a chain is exactly the shape the
filtered axis already is (`join(list, case-alt)` — an axis may *be*
a chain, and the compile walks it).

### Over a product: three moves

**Full flatten — `join(A, B)` over the crossed pair.** Under the
chapter's represent-A lean the stored Cross output is ordinary
nesting, so the flatten is the linear rule verbatim: `join(A, B)`
walks the stored orientation; `join(B, A)` reads through the faint
transpose (theorem 2 makes it lawful; the TODO above already says
the commute is never authored — the operand order *is* the read
orientation, and the editor supplies the transpose). The combined
flow's firing set is the product's points; its **order** is
lexicographic in the operand order — row-major or column-major,
spelled exactly where the registers section promised question 4
would spell it ("Boundary with question 4"). This is where the
alignment with `product-linearization-design.md` shows: the joined
flow is a single flow, so any downstream order-observer (an
ordered collect, a register on the combined flow, a spanning
handle) observes the full permutation — and the operand order is
precisely the authored orientation that round's pinning demand
asks for. A join chain is thus the third orientation-authoring
surface, beside the nested collect chain and the drawn commute —
and for order-*oblivious* consumers (the commutative-monoid
reduce-close), the two flattens are confluent by the catalog row's
commutativity flag, so an author who doesn't care pays nothing:
under-committed operand order is completable with a canonical
orientation shown faint, harmless by confluence, exactly as an
under-determined cross is completed. Where a consumer *does*
observe order, completion must not pick — the orientation is
meaning, and the remedy is authoring the operand order. (Same
shape as completion refusing to manufacture a join on an undrawn
filtered axis: inserted operators must be value-level identities,
and a meaning-bearing order is not one.)

**Partial flatten across the boundary — `join(E, A)`.** The
genuinely new move: the outer operand is the enclosing flow, the
inner operand *one axis* of a product opened inside it. Adjacency
holds without consulting any orientation — the context model
already places each axis's context immediately below the enclosing
context (axes are siblings under E; the product context sits below
them) — so the join is well-formed as drawn. What it does:

- The combined flow `~EA` fires once per (e, a) — E absorbs the
  axis, ordinary absorption.
- The surviving axes remain a product **with their extent fact
  intact**: B's chain is still per-company, invariant of `a`. This
  is the "a product carries its own exterior" machinery the
  per-group cartesian product already built — the sub-product's
  exterior stays E, its shared table built once per e and re-read
  per a; a consumer that opens `~q` under a `~EA` firing walks the
  shared per-company chain, and the user's computation still runs
  once per point.
- The orientation content is **graded**: `join(E, A)` pins A
  outermost *among the axes* and says nothing about the order of
  the survivors — the "orientation is minimal" finding, preserved.
  Over a cube, `join(E, A)` leaves {B, C} an unoriented
  sub-product; a full linearization of a cube is a chain of three
  joins whose operand sequence is the S₃ permutation, drawn as
  data on the page rather than carried as configuration.

The everyday client is real: keep the report's quarters as columns
— `join(~co, ~d)` mints the row flow, and per row a nested
`~q`-collect yields the cells list. One join fewer, one nesting
kept, and the drawing says which.

**Flatten within an axis.** Already owned: an axis may itself be a
join chain (the filtered axis), and the operand walk recurses —
adjacency against a chain operand uses its outermost/innermost
constituents, as in the linear rule. Nothing product-specific.

### The extended rule, in one statement

> **The operand walk over the poset.** A join chain consumes
> context-poset material downward from its outermost constituent:
> serial levels one at a time (the linear rule), and a product
> segment axis-by-axis, each axis consumption removing that axis
> from the segment's set and committing it to the current depth of
> the walk. Adjacency for `join(X, Y)`: the context of Y's
> outermost constituent is covered, in the poset, by the context of
> X's innermost constituent — where a product segment's axes are
> each covered by the segment's exterior. A chain's committed axis
> sequence is drawn orientation, graded to the depth the chain
> reaches; the surviving axis set stays a product over the combined
> flow with its original exterior.

Provenance bookkeeping falls out (and is filed to question 8's
reconciliation as input): under a join, the product segment in the
combined flow's context path shrinks by the absorbed axis; at
singleton the segment degenerates to ordinary nesting; fully
consumed, it vanishes. The transition rules are exactly what the
walk-and-classify algorithm needs at a product segment.

### Witness-neutral

The extension adds no new ill-formed shape and no new witness
species, which is worth stating because it was not obvious in
advance:

- `join(A, E)` — inner not below outer — fails the existing
  adjacency demand, unchanged.
- A join skipping a serial level fails adjacency, unchanged.
- A join over a *dependent* nesting in the reversed order (the
  third filtering regime) fails the invariance demand with the
  dependence-introducing node as witness, unchanged — no product
  exists to orient.
- Contradictory commitments within one chain are unconstructable
  (each flow has one termination per consumer path), and *sibling*
  chains committing different orientations are the two-readings
  case the chapter already blesses — two legitimate traversals of
  one shared table, no duplication of structure or work.

### Compile prediction

Nothing new to emit. A collect over a fully joined product is the
point-indexed table walked in the committed lexicographic order —
another permutation indexing the one shared table, exactly as the
transposing commute compiles; a partially joined product is the
per-group machinery with the combined flow as exterior. The
prediction, in the stream round's style: the emitters that exist
cover this when the poset round's worklist item lands; design-side
there is nothing product-specific left in join.

### Dead ends

1. **The n-ary flatten node.** You might wonder whether a cube
   should flatten in one k-ary join that names its full
   permutation. It turns out the parameter duplicates drawn
   vocabulary as annotation — the binary chain already states the
   permutation as operand order on the page, one commitment per
   node — the same two-sources-of-truth shape the rank-2
   parameterized zip died of. (Settled within this proposal —
   don't re-propose without new evidence.)

2. **The orientation-free flatten.** You might wonder whether join
   over a product could emit a genuinely unordered flow, deferring
   order forever. It turns out a flow's firings are ordered
   wherever order is observed, so the unordered output is either
   unobserved (then the canonical faint completion is already
   harmless — no new species needed) or observed (then the order
   is meaning and *must* be authored — the pinning demand). An
   unordered-flow kind would re-own at the flow level what the
   product context already states at the context level. (Settled —
   don't re-propose without new evidence.)

3. **Joining the pair as one flow.** You might wonder whether
   `join(E, pair)` should exist — the product's points as a single
   inner operand, one join instead of a chain. It turns out there
   is no pair flow: Cross outputs the two flows nested, and a
   points-flow operand would be the packed tuple crossing a
   barrier — the product bottleneck in flow clothes. The chain
   *is* the construct. (Settled — don't re-propose without new
   evidence.)

### What this leaves

The adoption conversation (jointly with this chapter's other
unadopted sections); the canonical orientation completion picks
for the order-oblivious case (the n-ary face of question 1,
unchanged); the interaction with mixed-kind axes (question 6 —
a joined stream axis inherits the stream round's sequencing
constraint); and question 8's walk-and-classify reconciliation,
which now has this section's product-segment transition rules as
input.

## Open questions

The language hasn't decided these yet. Where a question is marked
"worked," this chapter reached a finding, and the entry records it
along with what remains.

1. **A vs B storage.** The lean above (represent oriented, read
   symmetric) has a recorded exit; revisit if consumers fight the
   stored orientation in practice, or when the textual form has to
   print a Cross (does the text name an orientation?).
2. **Naming.** Cross, product, table, cross-join, "mutual capture."
   Interacts with the user-facing vocabulary rounds
   (`types-design.md` open question 1); also whether
   commute-on-product deserves the name *transpose* in user-facing
   text.
3. **N-ary products and associativity — worked** ("N-ary products:
   the three-list example"). Flat axis sets confirmed as the meaning;
   the binary-Cross nesting tree is authoring detail that
   additionally names any bound sub-products; the poset is the subset
   lattice of constructed axis sets (the cell-set shape), with the
   lub-may-not-exist behaviour first visible at three axes and caught
   by the existing "insert a Cross" remedy. Residue: the canonical
   orientation of a flat n-ary cross (the n-ary face of question 1
   and the textual Cross-spelling), and fold/join order over the cube
   (questions 5 and 4).
4. **Join on a product — worked** ("Join on a product"). The
   operand-walk rules extended over the poset: a join chain
   consumes a product segment axis-by-axis, each consumption a
   drawn orientation commitment graded to the depth the chain
   reaches; `join(E, axis)` is lawful without consulting
   orientation (axes hang immediately below the enclosing context)
   and leaves the surviving axes a product with their original
   exterior; the extension is witness-neutral, and the join chain
   is the third orientation-authoring surface beside the collect
   chain and the drawn commute. Residue: the canonical orientation
   for the order-oblivious completion (question 1's n-ary face),
   mixed-kind joined axes (question 6), and question 8's
   reconciliation, which gains the product-segment transition
   rules as input.
5. **Registers over products — worked, and it reopened a Delay
   question** ("Registers over products"). A register folds *along
   one axis*, fibered over the rest (the APL reduce-along-an-axis
   shape), not over the whole product: `final` drops the reduced axis
   (rank n−1), the running view keeps full shape, the axis is a
   minimal induced orientation (innermost only), and productivity and
   the stored-form theorem transfer verbatim (the Delay crossing
   instantiated per fiber) — all independent of *which flow* fixes
   the axis. That last point is the round's deeper yield: **which
   flow binds a Delay** is an open question about what a Delay *is*
   (`delay-ontology-design.md`), and this section carries its
   sharpest evidence — the shared-grid implementation of products
   breaks under consumer-order-dependent binding, which cuts toward
   fixing the axis at the Delay (the ancestor uncollect). The
   ontology round weighs this as a real *cost* on collect-binding,
   not a knockout (re-running a register per collect is a legitimate
   implementation, and an outer-axis accumulator wants the
   store-and-zip cost anyway); the fork stays genuinely balanced
   there. Two findings: a full reduction is an axis *permutation*
   (the S₃ orbit with a register hat; non-commutative folds observe
   the order); and a commutative monoid discharges the order demand
   entirely, so a reduce-close over a whole product is order-free iff
   its operator commutes (the A/B confluence at the register level;
   the collect-family catalog row carries the commutativity witness).
   The linearized whole-cube fold is a *different* program — Join the
   product (question 4, committing an orientation) then an ordinary
   register — so question 5 needs no linearization of its own.
   The reopened Delay question is since worked in
   `product-linearization-design.md` (exploration, unadopted): the
   axis is the stored orientation itself — this chapter's own
   represent-A lean, firmed into meaning exactly where an
   order-observing consumer makes it observable (the
   orientation-pinning demand) — dissolving the shared-grid argument
   (two consumers in two orders are honestly two drawn registers over
   one shared context-free base). Residue: the state thread's
   *visual* tiling over a product (the layout repo's), and the
   axis-naming's textual spelling (the textual-form row).
6. **Mixed-kind axes.** `cross(list, option)` is a table with a
   0-or-1 axis — is that a construct anyone wants directly, or just a
   degenerate case the theorems cover? Cross over stream axes gives a
   lazily-materialised 2D grid whose pull behaviour (which axis
   advances on a pull?) needs the stream round's attention. Cross
   with async/incremental axes is deferred to those kinds' own
   rounds.
7. **Retention policy.** The whole-table lazy retains the full
   product until its consumers finish; grid cells retain along the
   slower cursor. Whether the language ever wants an explicit
   "recompute rather than retain" annotation, and where it would
   live, is deferred until something measurable exists.
8. **Provenance representation.** The product segment in context
   paths (axis sets, poset comparability) is sketched above but
   should be worked against `bundle-provenance-design.md`'s
   walk-and-classify algorithm before the checks land.
9. **The aligned product (zip) — worked** ("The aligned product
   (zip)"). Cross's positional sibling: same extent paired by
   position, output a single widened flow (not nesting), demand =
   co-extent. The central finding is the asymmetry with Cross —
   co-extent is structural under shared provenance (free, a
   re-bundle) but a runtime precondition asserted at the barrier
   otherwise (Zig/APL's shipped shape). Its value form is the
   multi-wire collect (the table). Residue, filed to owners: the
   exact form of the co-extent assertion at the property/precondition
   boundary (`types-design.md`); the table's textual and at-rest
   spelling (the textual-form row); rank-2 zip's axis handling, the
   Life exhibit — **now worked** ("The Life residue, worked": the
   overlay is the flow-arity zip, i.e. the transpose under a
   co-extent license; the axis-handling question dissolves —
   alignment is positional at every level, axes are commute's
   business; residue = the shape-preservation catalog row and the
   transpose gate-widening edge, each filed); and per-edge
   alignment's home (the iteration-state/register round).
10. **Whether an *ambiguous cross* is owed its own combinator — the
    order-incompatible-combine ambiguity, which keeps moving rather
    than vanishing.** There is a lineage worth naming. **Incorporate**
    is unambiguous for its designed job — a value into an unrelated
    flow. *Generalizing* it to mix two values whose flow stacks are
    order-incompatible reopens a space: many merges of the two stacks
    are possible, so a generalized incorporate would have to *specify*
    which. That specification turned out to be the wrong thing to
    demand, because the mixed value can be collected twice in
    *different* orders ("The program that demands it") — so the honest
    representation is not a chosen merge order but the *absence* of
    sequencing, which is exactly **Cross** (the order-free product).
    But abstracting the order away is why Cross *under*-determines: an
    exact product may not be constructed, and which product a
    subset-combine belongs to is not fixed ("Availability is monotone;
    a combine's home is exact"). So the space of possible combinations
    did not disappear with Cross — it *moved*, from "pick an order"
    (Incorporate, too specific) to "which product, and is there one"
    (Cross, under-determined). The current lean resolves the residue by
    completion — an under-determined cross is just another time-travel
    program (above) — but the open question is whether some programs
    will want to represent an **ambiguous cross explicitly**: a
    combinator that carries the under-determination as a first-class,
    parameterizable fact rather than deferring it. Filed, not answered;
    the exit is that if completion produces too many gaps or unnatural
    fills, this combinator is where the specification would live.
