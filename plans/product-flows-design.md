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

## Open questions

1. **A vs B storage.** The lean above (represent oriented, read symmetric)
   has a recorded exit; revisit if consumers fight the stored orientation
   in practice, or when the textual form has to print a Cross (does the
   text name an orientation?).
2. **Naming.** Cross, product, table, cross-join, "mutual capture."
   Interacts with the user-facing vocabulary rounds (`types-design.md`
   open question 1); also whether commute-on-product deserves the name
   *transpose* in user-facing text.
3. **N-ary products and associativity.** `cross(x, cross(y, z))` vs a flat
   three-axis product — presumably flat axis sets, the same move
   partial-collect made for cell sets, but the poset and the table
   indexing should be worked against a three-list example before
   committing.
4. **Join on a product.** Flattening commits an orientation via Join's
   operand order — fine — but the interaction with multi-level joins (a
   join *chain* over a product's axes plus an enclosing flow) needs the
   operand-walk rules extended.
5. **Registers over products.** A fold demands an order, so a Delay whose
   flow operand is a product axis must be pinned to an oriented traversal.
   What that means for the state thread's drawing and for productivity is
   unexamined.
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
