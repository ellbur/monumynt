# The product's linearization: orientation is meaning where order is observed

Status: **exploration** — a worked round with leanings, prepared for a
design conversation, **not adopted**. This round takes up the one hard
residue the Delay-ontology chapter isolated — which reading order
several consumers of one order-sensitive register each walk a
multi-axis grid in, the recompute-vs-explicit-axis-reference trade
(`delay-ontology-design.md`, "The product, re-read through
update-cadence and read-range") — together with the observable-stakes
version the effects round filed back (`effects-design.md`, "Effects
over a product inherit the linearization residue"). Its claim, held as
a leaning throughout: **the residue dissolves with no new construct.**
The trade's two horns were priced against the wrong mechanisms; the
axis a register needs is already stored in the drawing, on the Cross
node's orientation, and the whole genuine cost is one new demand (the
*orientation-pinning* demand, below). If the claim survives its
conversation, the collect-vs-ancestor fork closes outright — the
answer is the Open list's "a specified third flow," made concrete.
Adoption is owed jointly with the Delay-ontology row's conversation,
not here. The frequency check this round owed before that
conversation is now **run** (`real-loop-survey.md`, survey 4 — see
the Open list's first entry for what it found); the evidence is in,
the decision still isn't.

*(Spelling note, added 2026-08-12: this chapter's code samples use
`~x ~> delay` and `step of`, both of which predate the thread
ergonomics round (`iteration-with-state-design.md`, 2026-08-04 —
no flow operand on the register, `step of` replaced by `@` thread
ink). Read a delay's flow operand as the thread's **pin** — the
per-register naming of its folded axis
(`delay-ontology-design.md`, "The frame menu") — and note the
distinction this chapter already draws survives the re-spelling
exactly: the pin names one register's folded axis; the
**orientation** an order-observing consumer walks the whole grid
in stays on the Cross, once, for every observer. The examples
stand as the record of the design in the retired spelling.)*

Before reading this, you will want: the register pair
(`iteration-with-state-design.md`), the Delay-ontology chapter — in
particular the straddle split (update cadence vs read range), the
value-in-context model, and the owned-order criterion
(`delay-ontology-design.md`) — Cross with its Option A/B fork and
"Registers over products" (`product-flows-design.md`), and the
sequencing commute (`effects-design.md`). Code samples use the textual
syntax of `textual-representation-design.md`; every spelling involving
Cross is provisional (its spelling is on the owed list,
`open-problems.md`, Tier 4).

## The residue, in its smallest programs

Two lists, crossed; a value per point; a running sum. The register
must fold along *an axis*, fibered over the rest — that much is
settled (`product-flows-design.md`, "Registers over products") — and
the residue is who names the axis:

```
xs -> open list => x, ~x
ys -> open list => y, ~y      -- sibling: cross, not zip
x, y -> add => s              -- s: one value per (x, y) point
~? ~> delay init 0 => run     -- along which axis?
run, s -> add -> step of run => total
```

The inherited trade (`delay-ontology-design.md`, "The product sharpens
both"): let the **consumer's collect** name the axis (collect-binding)
and no reference is ever drawn, but two running-view consumers reading
in different orders name two axes, want two different grids, and
compute-once-transpose breaks — the register silently recomputes per
consumer. Or fix the axis **at the Delay** (ancestor-reference) and
the grid is stable, but the Delay must say which axis, a symmetric
product cannot infer it, and every attempt to draw the reference came
out a mess of wires. Paying recompute and paying the reference looked
like the two horns of one forced choice.

The effects round then removed the escape hatch. A commutative
operator discharges a pure register's order demand; a **spanning IO
handle** under a doubly-nested walk has no such out — the bytes land
in the file in one order or the other, writing is not commutative, and
over a *grid* (neither axis enclosing the other) the concatenation
order **is** the linearization (`effects-design.md`). So the residue
gates ordinary programs — any program that writes under nested
iteration over independent axes — and settling it is load-bearing.

## Re-read the license: why order-freedom was ever allowed

Start from the record's own defence of the symmetric product. Option B
("order at the consumers", `product-flows-design.md`) relaxes the
letter of no-time-travel — nesting established at construction — and
the recorded defence is precise: the two orientations of a product are
**confluent**, they provably give the same values, so the consumer's
non-pick is unobservable, "the letter is relaxed exactly where it is
provably meaningless." That sentence carries more weight than it was
asked to. It says order-freedom-at-the-consumer is not a general right
— it is **licensed by unobservability**, case by case.

Now walk the license to the register. A context-reading value is
precisely the case where confluence *fails*: a scan along X and a scan
along Y are different grids, not transposes of each other — the
mechanical fact `product-flows-design.md` records ("The inner-axis vs
outer-axis cost"), which the value-in-context model generalised into a
criterion: **"does this value read flow-context" is exactly what
separates free-to-transpose from
genuinely-different-computation-per-orientation**
(`delay-ontology-design.md`). The effects round adds the third member:
a spanning handle's segment concatenation observes the firing order
directly. Call these the **order-observing consumers** — the Delay
(and `hold`: "latest" is an order word), the raw context-read (if the
cursor model is adopted), and the spanning handle.

The conclusion is short: **at an order-observing consumer, the
license is void.** The pick is observable there, so deferring it to
"whichever consumer, in whatever order it reads" is no longer the
principled relaxation Option B defended — it is promoting a choice
with observable consequences into something no construct states. The
owned-order criterion already has a name for that sin: *incidental
order* — "it is not enough that an order happens; the order must be
drawn" (`delay-ontology-design.md`, the criterion's load-bearing
clause). Where order is unobservable, leave it free; where it is
observed, it must be stated. The question is only *where* it is
stated — and the record, it turns out, already stores an answer.

## The answer is already in the drawing

Cross's adopted lean is **represent A, read B**
(`product-flows-design.md`): the stored node carries an orientation —
its (outer, inner) operands — and its output "presents as ordinary
nesting to everything below it" (theorem 3); the symmetric product
survives as the *recognized reading*, with the transposed
consumption one lawful Commute away (theorem 2). For order-free
consumers the stored orientation is inert — any chain re-reads it
through a faint commute, which is why that doc's TODO leans toward
never authoring those commutes at all.

So the drawing already contains an orientation, stated by a construct,
upstream of the register. Put the two halves together:

> **A register over a product rides the drawn orientation of the flow
> it is on.** The oriented product *is* ordinary nesting (theorem 3);
> a register over ordinary nesting is a construct the record already
> covers; the delay's flow operand names which of the drawn nesting's
> flows it steps on — the inner axis (the streaming register, reset
> per outer firing) or an outer one (the fiber-retaining register) —
> disambiguated by the existing "collect of the Delay's own flow"
> rule, exactly as in the optional-readings nesting.

No new construct. The register's axis question was an **attribution
error**: the axis was being sought at the consumer (candidate 1) or
in the value's ancestry (candidate 2) while it was already stored on
the flow between them. The Open list's third option — "a specified
third flow" — is this, concretely: the oriented product flow itself,
its orientation stated by Cross's operands plus any authored commutes.

Everything the registers-over-products round worked transfers
verbatim and merely re-attributes: fold along one axis fibered over
the rest, `final` at rank n−1, the running view at rank n, the
inner/outer cost gradient, productivity per fiber, the S₃ permutation
as a chain of orientations. None of those results change; only "which
flow fixes the axis" is answered — the drawn one.

The wire-mess dissolves with the same move. The feared reference was a
new species of wire from the Delay glyph to a distant uncollect. The
orientation is instead carried by **operands of flow operations the
vocabulary already has** — Cross's (outer, inner), Commute — nodes the
visual form draws anyway, and the delay's own flow operand (`~x ~>
delay`, already the textual form) keeps only its existing nesting job
of picking among surviving flows. Nothing new is drawn; something
already drawn stops being ignored.

## The fork, closed (a leaning)

With the axis located, the case against each old candidate can be
stated from the record's own principles, and it is worth stating
because it closes the fork rather than merely sidestepping it.

**Against consumer-supplied axes (collect-binding), two arguments.**

First: **meaning must flow forward.** A consumer's operands choose
what to read and in what order to read it — never what upstream
values *are*. Under collect-binding, the orientation named at a
downstream collect selects which values a non-commutative register
upstream produced. That is a downstream choice determining upstream
meaning — the same backward flow the no-time-travel discipline
forbids for values, here smuggled through a fold. The incidental-order
clause is the near statement (a consumer's traversal schedule promoted
into meaning); provenance-determines-availability
(`barrier-value-crossing-design.md`) is the standing forward rule it
violates.

Second: **the conflation.** The consumer's orientation was being
asked to mean two things at once — the register's *fold axis* and the
consumer's *read order*. Those are different demands: a scan-along-X
grid is, once computed, ordinary data — full rank, confluent, freely
read in Y-major order by a consumer that wants rows. Collect-binding
cannot even express "read the X-scan in Y-major order"; its one knob
sets both. With the axis drawn upstream, the two separate along
exactly the straddle split (`delay-ontology-design.md`): the **update
half** takes its order from provenance — the drawn orientation, one
level up — and the **read half** stays consumer-chosen, untouched, as
that section already answered for nestings. The product stops being a
special case of the split; it was the case where the update half's
provenance was missing an order, and the drawn orientation is that
order put back into provenance.

There is also an ontological cost the record should not pay twice.
Candidate 1's coherent reading of "one register, meaning completed at
each collect" is the *delayed computation* — a wire carrying an
unapplied computation, instantiated per binding. The record rejects
that species everywhere it appears: functions are not first-class
values (`functions-design.md`), a provider is not a value on a wire
(`late-bound-operations-design.md`, dead end), a continuation is not
a value (`speculation-design.md`, dead end). Register wires carrying
values again — ordinary, provenance-determined — keeps the pattern
unbroken.

**Against ancestor-reference:** its failure modes stand as recorded
(the nearest ancestor is wrong on nestings; on products there is no
nearest), and the drawn orientation is not a rehabilitation of it —
the axis is read off a *flow operation's* stated operands, not off
the value's ancestry. What survives of candidate 2 is what the
straddle round already kept: provenance fixes the update half.
Provenance now includes the orientation, because the orientation is
drawn.

On sequences the candidates coincided; on grids both are now
superseded by the drawn orientation. That is the whole fork. (The
fork belongs to the Delay-ontology row and closes there or not at
all; this round supplies the case, not the decision.)

## The multi-consumer program, worked

The program that carried the residue — one table, both running sums —
comes out honest:

```
xs -> open list => x, ~x
ys -> open list => y, ~y
~y, ~x ~> cross => ~yx        -- provisional spelling; operands are
                              -- (outer, inner): stored Y-outer, X-inner
x, y -> add => s              -- the base grid: context-free, shared

-- consumer A: running sum along X (down each column)
~x ~> delay init 0 => runA
runA, s -> add -> step of runA => colSum

-- consumer B: running sum along Y (along each row); reads the
-- transposed orientation, so this commute is authored, not faint
~yx ~> commute => ~xy
~y ~> delay init 0 => runB
runB, s -> add -> step of runB => rowSum
```

Read what the drawing now says. The base grid `s` is context-free —
computed once at the product, shared by both chains, transposed for
free: **compute-once-transpose survives exactly for the values it was
ever true of.** The two scans are two drawn registers over two drawn
orientations — visibly two computations, which is what they always
were (different grids, not transposes). The "recompute cost" that
argument 1 charged against collect-binding was never a cost to be
traded away; it was two computations wearing one node, and the
drawing was lying about their number. "One non-commutative register
read in two orders" is not expensive under this account — it is
**unrepresentable**, and unrepresentable is correct, the same way
non-productive registers are unrepresentable rather than checked
away.

A consumer that genuinely wants the *same* scan read the other way —
the X-scan grid traversed Y-major — draws no second register: `colSum`
(the running view, rank 2) is ordinary data, and its transposed
reading is a faint commute like any other confluent consumption. The
conflation is gone because the drawing has separate places for the
two demands.

## The one genuine cost: the orientation-pinning demand

What does this account charge? Exactly one thing. The stored
orientation on a Cross is today allowed to be *heuristic* — chosen by
completion when the node is inserted faint
(`product-flows-design.md`, "What this changes in the completion"),
free to be so precisely because no consumer can observe it. An
order-observing consumer downstream makes the heuristic observable —
and an orientation picked by a heuristic and read by a register is
**incidental order in the criterion's exact sense**, with the
completion heuristic playing the scheduler's role: "a heuristic
change is a semantics change" (`time-travel-programs-design.md`,
question 1) is the same fact as "a register over incidental order
reads the scheduler." The criterion that located the residue also
states its obligation:

> **The orientation-pinning demand: on any path from a Cross to an
> order-observing consumer, the orientation — the Cross's stored
> operands and every commute on the path — is semantics, and must be
> authored (or the completion's pick surfaced loud, never silently
> defaulted), to the depth the consumer observes.**

Notes on each clause, each inheriting existing machinery:

- **A demand, with a witness.** This is a property in
  `types-design.md`'s sense: propagated along the flow wire, its
  failure witness the order-observing node that made the orientation
  observable. No search, drawable.
- **Graded to the observed depth.** A fibered register observes only
  the innermost axis; the outer (n−1)-subcube stays a product, free
  and unpinned — the "orientation is minimal" finding, preserved. A
  scalar non-commutative fold or a spanning handle observes the full
  permutation and pins the whole chain. Nothing is demanded that is
  not observed.
- **Discharged by commutativity.** A commutative-monoid reduce-close
  never observes the order; the catalog row's commutativity flag
  (`collect-family-design.md`) discharges the demand exactly as it
  discharges the axis obligation today. `sum` over a table stays one
  gesture, no orientation drawn — the everyday case pays nothing.
- **Never triggered by independent effects.** A per-firing-minted
  handle (`effects-design.md`, the independent fork) demands no
  order; only the spanning handle pins. The demand discriminates at
  exactly the granularity the effects round drew.
- **The TODO gets its boundary.** `product-flows-design.md`'s lean
  that the transposing Commute "should never be authored" (mandatory
  + unique ⇒ inferable, faint) holds for confluent consumers and
  stops at this demand: a commute on a path to an order-observing
  consumer is precisely the one that must be authored. One rule, both
  regimes: **commutes are derived where confluence holds, authored
  where it fails.**
- **Completion keeps its role, loud.** An author who draws the
  sibling opens and a register but no Cross still gets a completion —
  but where today's insertion could pick silently, under the demand
  the picked orientation at an observing consumer is surfaced as a
  decision (loud-faint or error — the exact form is completion's
  question, below). This hands `time-travel-programs-design.md`'s
  thin contents row a worked program: the case where a completion
  heuristic must *not* be silent, derived from stakes rather than
  taste.

The beginner bar, re-checked: the plain scan is untouched (one flow,
no Cross, no demand); `sum` over a table is untouched (commutative);
the first program that pays is a non-commutative scan over a genuine
grid, and what it pays is stating which way the scan runs — which is
information the program is incomplete without, now demanded where it
was previously lost. The +1 ladder holds: scan → scan-over-a-product
is "add the Cross (or accept its completion) and name the delay's
axis," an addition to the drawing in existing vocabulary, not a
rewrite.

## Effects, worked

The observable-stakes case that removed the escape hatch is
discharged by the same rule, with no Delay anywhere in it:

```
rows -> open list => r, ~R
cols -> open list => c, ~C
~R, ~C ~> cross => ~RC        -- authored: rows outer, cols inner
file -> openFile => io        -- one handle, spanning the grid
r, c -> render => cell
io, cell -> write => io'      -- one write per (r, c) firing
-- consuming io' after the loop concatenates the segments in ~RC's
-- drawn lexicographic order: row-major, stated, never defaulted
```

The sequencing commute concatenates per-firing segments "in firing
order" (`effects-design.md`); the effects round's own boundary was
that nested loops are fine (nesting supplies lexicographic order,
drawn) and only the grid lacked an order. The drawn orientation
converts the grid case *into* the nested case — the oriented product
is ordinary nesting, its lexicographic firing order owned — so the
spanning handle's concatenation order is read off the drawing, and
the never-drawn commute stays never-drawn. Under an unpinned
orientation the demand fires with the handle as witness; the remedy
is to pin (or to mint per-firing handles, if independence was the
truth of the program). The commutative escape hatch is no longer
needed: it was only ever needed to *avoid* stating an order, and the
order is now stated.

This also settles how the order-demand check generalises. The
Delay-ontology round named the check for Delays and extended it,
conditionally, to raw context-reads. The spanning handle is the third
client, and the general statement covers all three:

> **Whatever observes an order demands the flow own one** — a Delay,
> a raw context-read, a spanning handle's concatenation. One check;
> the pinning demand is its product-cell instance.

## The kinds table, amended

The surplus row of the owned-order table
(`delay-ontology-design.md`) re-reads rather than changes. The
**bare product** — the symmetric B-reading — owns no single order:
surplus stands, and a register directly on it stays ill-formed. The
**oriented product** — the A-representation, pinned — is not a new
row at all: it is ordinary drawn nesting, already in the table
("segment / filtered sub-flow: the parent's order, restricted" is the
same species — an owned order stated by structure). The surplus cell
thus gets its serializer, completing the pattern the criterion's
taxonomy started: **settle converts incidental order to owned by
minting; pinning converts surplus order to owned by selecting.** The
two pathological cells each have exactly one construct that redeems
them, and both redemptions are drawn.

The value-in-context model, if adopted, confirms rather than
competes: a product cursor is a grid-point with no unique predecessor
"until an axis names the linearization" — the pinned orientation is
that naming, located in existing structure, and the cursor on an
oriented product has the unique predecessor the model asked for.

## Prior art

The construct this round lands on is shipped, mainstream, and shaped
point for point like the account above.

- **SQL window functions.** `SUM(v) OVER (PARTITION BY y ORDER BY x)`
  is the fibered register with a drawn orientation: `PARTITION BY` is
  the fibering axes, `ORDER BY` is the pinned fold axis — stated *in
  the construct*, per order-observing consumer chain — and the frame
  clause is the read range. That the mainstream data language makes
  the order clause mandatory for running aggregates and omits it for
  plain ones is the pinning demand, graded by observability, as
  shipped syntax. (No SQL comparison round exists in the record; this
  is cited as general prior art, not a worked corpus.)
- **dplyr** (`tidyverse-comparison.md`). The idiom for an ordered
  scan is arrange-then-cumsum — the orientation authored upstream, on
  the flow, before the fold — and the offset verbs take an explicit
  `order_by =` because "lag on scrambled rows" is the family's
  documented footgun. That footgun *is* the unpinned case: an
  order-observing consumer over an orientation nothing stated. The
  field's fix (state the order at or above the observer) is this
  round's; the demand catches statically what dplyr documents as a
  hazard.
- **APL** (`apl-family-comparison.md`). `+/[X]` states the fold axis
  in the operator — locally, cheaply, always — and the array family
  never infers an axis from a consumer. Field support for
  stated-axis-at-the-fold being ergonomically bearable at high
  frequency of use.

The Delay-ontology round read dplyr's `order_by` as a vote for the
consumer's-stated-orientation branch. Re-read against this round it
votes one step sharper: for the order being *stated* rather than
ambient — and its location (on the operation or upstream of it, never
inferred from a downstream reader) is the drawn-orientation shape.

## Against the philosophy

- **Example first, then generalise.** The concrete programs (both
  running sums; the grid write) come first and the demand is read off
  what they observably need; nothing requires declaring orientation
  where no example observes it.
- **Inside-out, no magic names.** The axis arrives at the register by
  visible structure (the oriented flow it rides), not by an ambient
  default or a lookup.
- **Foundations before features.** The round *removes* a candidate
  construct (its own first draft — dead end 1) on finding the
  existing vocabulary sufficient; the one addition is a check, not a
  primitive.
- **Programmer's abstraction level.** "Running total down each
  column" is drawn as exactly that; one reading per program is
  restored precisely where collect-binding would have let one drawing
  mean two programs.
- **No bottlenecks.** Orientation is flow-only (Cross and Commute
  carry no value ports); values cross as themselves; nothing is
  packed.
- **Abstraction is the source of truth.** The symmetric product stays
  the recognized reading wherever confluence holds; the pinned
  orientation is authored commitment exactly where the program's
  meaning depends on it — the same boundary completion already
  respects between derivable and decided.
- **Building blocks must build.** The +1 from scan to
  scan-over-a-grid is additive (a Cross and a named axis); the +1
  from one scan to both-directions is additive (a commute and a
  second register); no rung rewrites into a different construct.

## Dead ends of this round

Recorded so they are not re-proposed:

1. **A new orientation/serializer node ("along"/"orient").** This
   round's own first draft: a binary flow operation (product flow,
   axis flow) → oriented flow, by analogy with settle. Dissolved on
   contact with the record: Cross already stores an orientation and
   Commute already re-orients — the node would duplicate both, and
   "foundations before features" cuts a duplicate before it lands.
   What the analogy was reaching for survives as the pinning demand
   (the surplus cell's redemption is drawn), without a node.
2. **An ambient default linearization** (row-major by convention).
   Incidental order promoted to meaning — the criterion's exact
   target — with dplyr's scrambled-rows footgun as the field witness;
   and a faint completion-inserted commute would silently invert it.
3. **Making Cross semantically ordered** (dropping the B-reading, so
   every product is a nesting, full stop). Destroys Cross's content —
   "each consumer traverses in its own order" is the whole point for
   the order-free majority, and every confluent consumer would pay an
   authored transpose forever. The lens shape (represent A, read B)
   is the point; pinning firms the stored half exactly where read-B
   is unlicensed, and nowhere else.
4. **The axis as an annotation on the Delay glyph** (the primary
   carrier per-register). Serves only Delays — the spanning handle
   observes order with no Delay anywhere — and multiplies per
   context-read under the cursor model. The orientation lives on the
   flow, once, for every observer; the delay's flow operand keeps
   only its existing job of naming a flow among the drawn nesting's.
   *(Update 2026-08-12: the flow operand itself is gone — the
   ergonomics round removed it — and its surviving "existing job"
   is carried by the thread's pin (`delay-ontology-design.md`, "The
   frame menu"). The rejection stands unchanged, and the pin does
   not reopen it: the pin names the register's own folded axis,
   per-register information by nature; it never carries the grid's
   orientation, which is exactly what this dead end forbids putting
   on the register.)*
5. **Mandatory full linearization** (Join first, then an ordinary
   register, as the *only* form). Loses fibering — the everyday form
   of the construct in every shipped relative (SQL's `PARTITION BY`,
   APL's axis fold, dplyr's grouped scans) — and collapses question
   5 into question 4, which the products round deliberately kept
   apart. Join-then-register survives as what it always was: the
   *different*, composed program for state that genuinely crosses
   fibers.

Collect-binding for the product axis is deliberately **not** listed
here: it is a live candidate of the Delay-ontology fork, and the case
against it (meaning-flows-forward; the conflation) is this round's
argument, owed to that row's adoption conversation — not a recorded
rejection.

## Open

- **Adoption.** Joint with the Delay-ontology row's conversation —
  this round claims the fork closes and the residue reduces to the
  pinning demand; both claims are leanings until that conversation.
  What would reopen the trade: field evidence that authors routinely
  want the *same* drawn register re-run per orientation (exploratory
  re-orientation as a workflow). Even then the pressure lands on
  authoring ergonomics (a gesture that mints the second register and
  commute) rather than on consumer-supplied semantics.
- ~~**The frequency check, owed before the demand's cost is
  weighed.**~~ **Run** (`real-loop-survey.md`, survey 4: thirty
  nested-loop sites from numerics / image / report-writer corpora,
  seeded and unfiltered). What it found, held apart from the
  decision: product-shaped chains are 9 of 30 nested sites in those
  domains; the demand would fire on 4 of 30 (3 excluding a flagged
  demo draw) — weekly, not yearly; **in every firing draw the
  orientation was already authored in the source** (loop nesting
  matched to an output grammar, `sorted()` upstream, the in-place
  sweep's subscripts), so against that sample the demand charges
  nothing imperative programs don't already pay — with the stated
  bias that imperative syntax cannot draw an unpinned product, so
  authoredness there is partly the medium (the co-occurrence rate is
  the medium-independent number). The commutative discharge has
  field instances (2 of the 6 spanning consumers — survey finding
  4.3, including the knife-edge case where one operator swap,
  `+=` vs over-paint, is the whole difference); three of the four
  firing draws are spanning *text emission*, so the demand's
  everyday client is the report-writer (the effects face), with the
  numeric non-commutative sweep the rare-but-sharpest member —
  fibered, one axis observed, its order-sensitivity invisible in the
  source (finding 4.4: the legibility case). The
  exploratory-reorientation workflow the adoption bullet above fears
  produced zero sightings, though the medium could not have shown it.
  The adoption conversation now has its evidence; it decides, this
  survey does not.
- **The completion form.** Loud-faint versus error when an inserted
  orientation reaches an observing consumer — completion's row owns
  the choice (`time-travel-programs-design.md`, its
  heuristic-versioning residue is sharpest exactly here); this round
  supplies the worked program its thin-contents rule wanted.
- **The n-ary carrier.** For rank > 2 the stored orientation of a
  Cross chain and the graded demand ("pin only observed depth") need
  the n-ary representation worked — rides the products row's
  n-ary/axis debt (rank-2 zip's Life struggle, which used to ride
  there too, is since worked — `product-flows-design.md`, "The Life
  residue, worked"; untouched here either way).
- **Spellings.** Cross's textual spelling was already owed; the
  authored-commute spelling and how pinnedness renders (the
  authored/faint distinction is load-bearing here) join it, Tier 4.
- **The representation exit.** `product-flows-design.md` records an
  exit from represent-A (promote B if consumers routinely fight the
  stored orientation). The pinning demand is representation-
  independent — under a B representation it becomes "an
  order-observing chain must contain an authored orientation" with
  the same witness — so the exit stays open; only the demand's
  carrier moves.
- **The context-read extension** stays conditional on the
  value-in-context model's adoption, as before
  (`delay-ontology-design.md`); the spanning-handle client is
  unconditional.
