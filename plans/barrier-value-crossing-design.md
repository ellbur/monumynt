# How Values Cross a Barrier

Status: exploration — a proposal with leanings, not adopted. Nothing here
is implemented.

A *barrier* is a combining construct — a join, a race, a collect, a
Cross — that several flows meet at. The question this doc settles: when a
value needs to be usable on the far side of a barrier, how does it get
there? The no-bottlenecks principle rides on the answer, because the wrong
answer is to pack the value into a tuple or tagged union just to carry it
across.

The question surfaced identically in four places, each of which stopped at
this corner and pointed at the others:

| Home | The corner |
|---|---|
| `first-class-ports-design.md`, open question 3 | Does the binary Join carry the spec's corresponding value ports, or stay flow-only? "It would be odd for the flatten join and the concurrent join to disagree on port shape for no semantic reason." |
| `async-flow-design.md`, "Racing is a barrier, not a value" | Race has per-contender value + flow output pairs — more port structure than any other node carries. |
| `partial-collect-design.md`, open question 3 | k branches × m corresponding value rows: does the partial collect grow rows, or does a second value crossing the merge take a second node? |
| `async-flow-design.md`, failability residuals | The discharging collect's port structure — `(prefix, terminator)` is more port structure than current collect nodes carry. |

A fifth party depends on the outcome: `end-when-design.md`'s readout leans
entirely on the discharge shape, so first-match, take-until, and
poll-until-result all read from whatever is decided here.

The demand is real, not theoretical. The concurrency survey
(`real-loop-survey.md`, survey 3, finding 3.2) found that in every
hand-rolled race sampled, "which contender won" was reconstructed after
the fact from side state — flags, `None` checks, state enums — never
delivered structurally. How a value crosses the race barrier is the thing
that hand-written code visibly lacks.

Terminology used throughout: **uncollect/collect** are the fundamental
open/close operations (the code says `Open`/`Close`); a **bundle** is the
set of mutually-exclusive cells a case split or race partitions a flow
into; a **cell** is one such branch; a value's **context path** is the
stack of flows it lives under, and **comparability** orders those paths.
These are defined in `bundle-provenance-design.md`,
`partial-collect-design.md`, and `first-class-ports-design.md`.

## Read the record first: five crossings that already exist

Before proposing a rule, read off what the existing constructs already do
when a value passes one of them.

**The flatten join — nothing crosses.** The implemented compile never
transports a value through a join. A collect on a combined flow simply
references the per-element bindings of every level its walk spans
(`lazy-compile-design.md`). This is right, not merely expedient: the
combined flow fires exactly when the inner operand fires, so its firings
*are* inner firings, and everything readable per inner firing was already
readable there (`lazy-stream-join-design.md`, the law of the combined
flow). The join changed which terminations exist, not which values are in
reach.

**Cross — availability, stated as such.** From `product-flows-design.md`:
"Values cross the boundary by the ordinary invariance rule… an axis's
element is readable at the product's points because the product context is
deeper than each axis. No packing, no transport ports." Cross is a node
with flow ports and no value ports.

**The concurrent join — availability, one step wider.** The fork-join
compile starts both cells and combines both resolved values in the merged
context (`async-flow-design.md`, "Sequential and parallel are
structural"). No port carries `a` or `b` through the join; the merged
context is simply one in which both are readable — which requires it to
sit *above both* operand contexts in comparability. That is exactly the
product context Cross adds to the provenance model. The concurrent join is
to sibling async flows what Cross is to sibling iterations.

**End-when — availability, by its own theorem.** From
`end-when-design.md`: "Each firing of the shortened flow is a firing of
the subject, so values from the subject's context are readable in the
shortened flow's context directly… No transport machinery."

**The partial collect — a genuine transport, the only one.** Here a value
really moves: the merged flow's value output is *the firing branch's
value*, carried from k mutually-exclusive cells out to their union. This
is not derivable from availability — containment only ever admits values
inward (`{A} ⊆ {A, B}` lets merged-context values into a cell, never a
cell's value out to the merge). The partial-collect design made that
one-way door a feature: "coarsening happens only at the explicit node."
The partial collect's value row is a port because no rule could replace
it.

The sample splits cleanly in two, and the split is the design.

## The two mechanisms

**Mechanism 1 — availability.** A value defined upstream of a barrier
stays usable downstream because the barrier's output context sits at or
above the value's context in the context order. Nothing crosses; the value
was already in reach, and the barrier's flow law is what put the output
context where it is.

> **The availability law.** Barriers carry no pass-through value ports. A
> value is readable at a context downstream of a barrier iff that context
> is ≥ the value's context in the context order, and the barrier's flow
> law determines where its output context sits in that order.

A pass-through port would be a second, wireable spelling of a fact the
provenance order already states — two vocabularies for one reading. That
is the whole argument against it.

**Mechanism 2 — minted ports.** Some barrier outputs are *born at the
node*: projections, resolutions, selections, or settlements that exist
nowhere upstream as wires. These are value ports, held in the per-kind
inventories that first-class ports already models:

| Node | Minted value outputs | What the mint is |
|---|---|---|
| uncollect (list/option) | `element` | projection of the opened value |
| uncollect (case split) | per-alt payload | projection under dispatch |
| race barrier | per-contender resolved value | resolution at settlement |
| partial collect | the merged value (one row) | selection: the firing branch's value |
| collect | `result` | the fold/packaging of the walk |
| discharging collect | see below | the settlement of the terminator |
| Delay write half | `final` | the register after the flow completes (the pair is worked, not yet adopted — `iteration-with-state-design.md`, "The Delay back-edge") |

The two mechanisms compose, and their composition is the whole story of a
sum barrier: **into a cell by availability, out of a bundle by the partial
collect.** A constant or an ancestor value is readable inside any race
cell or case alt with no machinery (the prefix rule); the winner's value
reaches the post-race world through the covering partial collect's minted
row.

Which mechanism applies is read off the barrier's character:

- **Product barriers extend contexts.** All operands continue together;
  the output context is above every operand; every operand's values stay
  readable. Nothing to select, so no value ports — the concurrent join,
  Cross, and the flatten join are flow-only. (The flatten join
  degenerately: its operands were already nested, so the combined context
  adds nothing readable.)
- **Sum barriers refine contexts.** The cells partition the parent; per
  cell, what is readable is the parent's ancestry plus that cell's mints;
  sibling cells stay mutually unreadable (bundle mixing, as ever). The
  only way back to a coarser context is an explicit minted selection — the
  partial collect.

## The co-location criterion

Mechanism 2 leaves one question: when do several minted outputs share one
node, and when are they several nodes? The record answers from both
directions.

From multi-close (one flow, many collects — a value output multiplies as a
*consumer*, never as node width): each collect is a complete construct
alone, and nothing relates two collects of one flow except the flow
itself, which is an operand, not a node. Independent outputs are
independent nodes.

From bundle provenance: a bundle's cells *cannot* be independent nodes.
Cell i of a race means "contender i settled first" — a fact about every
contender. The exclusivity the mixing check enforces is a relation among
all the cells, and the provenance store holds only unary per-wire facts,
so the one place that relation can live is the node that creates the
partition. The same holds for a case split's alts.

> **The co-location criterion.** Minted outputs share one node exactly
> when the node's law ties them together — when at least one output is
> only lawful with the others in hand. Outputs each obtainable by a
> complete construct of their own are separate nodes.

The criterion reproduces every port inventory the record already committed
to (case split's partition; race's partition; the Delay pair, where
`final` is the write half's output and `prev` the read half's — two nodes
because each half is a complete act), and it decides the two contested
corners below.

## The four homes, answered

### 1. Join and the concurrent join: flow-only stands

The lean in `first-class-ports-design.md` — a flow-only
`Join({outer, inner})`, values meeting the join only at collects — is
confirmed. The worry attached to it dissolves. That worry was that the
concurrent join "genuinely transports values," so it and the flatten join
might disagree on port shape for no semantic reason. Under the
availability law they agree, for a stated reason: both are product-side
barriers, and product-side crossing is availability. The flatten join's
output context is the inner operand's (nothing new readable); the
concurrent join's is the product of its operands' (everything on either
side readable). Neither mints a value; neither carries a value port. In
the textual form (the flow-only spelling this round confirms):

```
urlA -> open async => a, ~A
urlB -> open async => b, ~B
~A, ~B ~> join all => ~ab        -- flow-only: no value crosses the node
a, b -> add -~> collect => total -- both values readable in the merged context
```

`a` and `b` reach the merged context by availability (their provenance is
a prefix of `~ab`'s), not by passing through the join — which is exactly
why the node needs no value ports.

The construct that *does* differ — race — differs because it is the sum
barrier: its per-cell values are mints, and mints are ports. So the
worry inverts into a diagnostic: **port shape follows the product/sum
character of the barrier, not the barrier-ness.**

The spec's `Join` signature (values in, "same names" out —
`visual-language-spec.md`) is then the *drawn* form of availability: where
a value wire visually crosses the barrier line, the diagram may want to
show it crossing. That is a derived-view rendering of the provenance fact,
not representation-level structure. This round does not edit the spec;
reconciliation is an open question below.

### 2. Race: values in, minted pairs out

The async doc's race shape — per contender i, an output flow (fires iff i
won) and an output value (i's resolved value) — is confirmed, now derived
rather than asserted:

- The inputs are async **values**, not opened flows. Race is a consumer:
  its compiled act is to start all contenders and await the first
  settlement — starting is something one does to an async value, not to a
  context. This mirrors the case split, which consumes the sum *value*;
  nobody pre-opens the alternatives before dispatching. Race is the
  sum-side multi-input uncollect: it opens N async values into one bundle.
- The per-cell values are **mints** — contender i's resolution exists
  nowhere upstream as a wire.
- Cells and their mints **co-locate on one node** by the criterion: cell
  i's law quantifies over every contender.

```
fetch:   fetchD
timeout: after(30)
-> race => r
~r.fetch:   r.fetch -> process -> some
~r.timeout: none
-~> collect => out
```
*Two async values race; the winner's cell fires with its resolved value,
and the covering collect over the race bundle carries the winner's value
out to the parent — into the cell by availability, out of the bundle by
selection.*

The side-flag reconstructions survey 3 found (`request is not None`,
`reply.sent`, four-state enums) are programs paying by hand for exactly
the minted discrimination this port shape delivers.

Race's full semantics — fairness, N-ary composition, abandonment — remain
owed (`async-flow-design.md` question 5, taken up in
`race-barrier-design.md`). This settles only the port/crossing corner that
was blocking the other homes.

### 3. The partial collect: rows are collects, not a wider node

The contested corner: two values crossing the same merge. The recorded
reservation read the options as "either take two partial collects or
pack," and leaned toward a multi-row barrier node as "the principled
completion." Worked concretely, the dilemma is false: two sibling collects
were already the no-pack answer. What made them look inadequate was an
unexamined assumption that two nodes' outputs would land in two
incomparable contexts.

Extending the HTTP merge from `partial-collect-design.md`: two error cells
share their handling, and the handler needs *two* values across the
merge — the status code (for the log line) and the parsed Retry-After (for
the backoff). Each value is its own sibling collect over the same cell set
(spelling provisional):

```
resp -> split status of Ok, Redirect, ClientError, ServerError => h
~h.ClientError: h.ClientError -> statusCode
~h.ServerError: h.ServerError -> statusCode
-~> collect => errStatus, ~err
~h.ClientError: h.ClientError -> retryAfter
~h.ServerError: h.ServerError -> retryAfter
-~> collect => errRetry, ~err2
errStatus, errRetry -> logAndFallback => out
```
*Two partial collects over the same `{ClientError, ServerError}` cell set;
their two merged values combine in one `logAndFallback` App with nothing
packed.*

**Theorem (context equality).** The two collects' value outputs are
combinable with no further machinery. Both carry a bundle step with cell
set `{ClientError, ServerError}`; comparability at a bundle step is
containment on cell sets, and the sets are *computed by walking, never
stored* (`partial-collect-design.md`) — node identity does not enter.
Equal sets are mutually contained, so both outputs live at the same
context and the App is well-formed there.

So m corresponding value rows are **m sibling partial collects over the
same cell set.** Nothing packs, nothing new is needed, and each row is a
complete construct alone — which is the co-location criterion saying
"separate nodes." The grain matches multi-close: a second output of a
merge is added beside the first, the merge untouched.

What the multi-row form got right survives as presentation: one drawn
barrier line with m value wires crossing is a natural *rendering* of m
sibling collects sharing a cell set — a candidate level-1 recognition
entry. The representation stays m nodes.

Two deferrals, kept rather than newly decided:

- The m collects mint m merged *flows* over one cell set; the final
  covering collect references either. Whether same-cells merged flows are
  one flow or many is open question 4 of the partial-collect round,
  unchanged; the interim rule (bind once and reuse) applies.
- The covering instance inherits the answer: a case collect stays
  single-result, and two results over one bundle are two collects — which
  is what the implemented multi-close on case splits already does.

### 4. The discharging collect: one port or two, by kind

Discharge is a mint — the terminator, settled, becoming data at a
whole-flow collect. Its port structure splits by the flow kind's row in
the failability table, and both halves follow from principle.

**Exactly-one kinds (failable async): one value output, a settled sum.**
The fired value and the failure payload are never co-present — the flow
delivered or it didn't — and they are born at one settlement with no
independent upstream wires. That is precisely when a data sum is honest
rather than a bottleneck. One port: `Ok(x) | Fail(e)` (spelling aside),
case-split downstream like any data. Outcome cells arise only from an
ordinary case split after the fact; the discharge does not mint a second
bundle.

**Many kinds (failable list/stream): two value outputs, on one collect.**
Here the two *are* co-present — every ending has a prefix *and* a
terminator — so a sum cannot carry them, and a tuple would be the product
bottleneck verbatim. Two ports, then; and they co-locate on one node by
the criterion, non-obviously. The subtlety: each output *looks*
independently obtainable (a fold of what fired; the terminator as data),
which would argue for two sibling collects. But the standalone total fold
— "fold whatever fired, ignore how it ended" — is an error-swallowing
primitive, and propagate-by-default exists precisely so failure is never
silently absorbed. A collect either propagates the terminator (default;
output failable; one `result` port) or *discharges* it — takes it in hand
as data. The total prefix is only lawful *at a discharge*, beside the
terminator. That is the criterion's "only lawful with the other in hand,"
so the pair shares the node:

> A discharging collect on a many-kind failable flow has two value
> outputs: `prefix` (the fold of what fired — total) and `terminator`
> (the ending, as data). Taking the terminator alone is partial use — the
> prefix port unwired — exactly as partial use of any node's ports is
> already sanctioned.

`end-when-design.md`'s readout is confirmed unchanged: its whole-flow
collect "→ (prefix, terminator)" is this node; first-match wires the
terminator port and leaves the prefix unwired; take-until-sentinel wires
both. Terminator payload *types* — composing `E1` and `E2` across chained
failability — remain the async round's residue, untouched: a question
about the terminator value, not about ports.

## The crossings, tabulated

| Construct | Flow law (where the output context sits) | Value crossing |
|---|---|---|
| flatten join (outer, inner) | fires iff inner fires; context = inner's | availability (degenerate — nothing new readable) |
| concurrent join | fires when all operands have; context = product of operands' | availability (product segment) |
| Cross | once per pair; context = product of axes | availability (stated in its round) |
| end-when (subject, stop) | prefix of subject's firings | availability (prefix admission, its theorem) |
| race | cells partition the parent by first settlement | mint: per-cell (value, flow) pairs, one node |
| case-split uncollect | cells partition the parent by dispatch | mint: per-alt (value, flow) pairs, one node |
| partial collect | merged flow fires iff a branch fires; context = union cell set | mint: the firing branch's value — one row per node; m rows = m sibling nodes |
| collect (propagating) | terminates; output at parent | mint: `result` (failable if the flow was) |
| collect (discharging, exactly-one kind) | terminates; output at parent | mint: one settled-sum value |
| collect (discharging, many kind) | terminates; output at parent | mint: `(prefix, terminator)` pair, one node |

## Fit with provenance and the checks

Nothing new is needed — which is the strongest evidence the split is
right:

- Availability *is* the comparability order `bundle-provenance-design.md`
  and its extensions already define: prefix on open steps, containment on
  cell-set steps (the partial-collect refinement), axis-below-product on
  product segments (the Cross refinement). The law adds no step kind; it
  observes that every barrier's crossing story is already a sentence in
  that vocabulary.
- The race's cells were already a row of the bundle inventory ("exactly
  one fires per settlement of the race"); the mixing check meets them
  unchanged.
- The concurrent join minting a product context strengthens the question
  `product-flows-design.md` already recorded — whether it and Cross are
  two kinds' faces of one construct. Strengthened, not decided; it stays
  with the barriers' Expr round.
- The one-way door stands: containment admits inward, the partial collect
  carries outward, and there is no third mechanism — so "coarsening
  happens only at the explicit node" is now backed by the full barrier
  inventory, not just the case split's.

## Against the philosophy

- **No bottlenecks.** Product side: nothing packs because nothing even
  crosses — the values were in reach all along. Sum side: nothing packs
  because selection is an explicit node with one minted row per value,
  never a tag-and-unpack. A packed sum or product is still fine when
  wanted as data on purpose; only packing-*to-pass* is ruled out, now
  mechanically.
- **One obvious reading.** A pass-through value port would be a second
  spelling of the availability fact. Flow-only barriers leave one reading.
  Likewise m rows on one node vs m nodes: one grain (consumers multiply as
  nodes), not two.
- **Example first, then generalise.** The law and the criterion are read
  off five crossings the record already contains and two implemented
  behaviors (the joined collect's walk; multi-close). No construct was
  designed and then hunted for uses.
- **Building blocks must build.** +1 value across a product barrier = one
  more reference; +1 value across a merge = one more sibling collect; +1
  outcome distinction at a discharge = a case split on the terminator
  port. All additions; no species changes.
- **Abstraction is the source of truth.** The drawn barrier with
  corresponding value wires survives as a derived view over the minimal
  representation, never the thing edited.

## Dead ends

Recorded in place, each with the reason it should not be re-proposed.

**1. Universal corresponding value ports** — the spec's Join signature
generalized to every barrier as representation-level structure. Rejected:
it duplicates the availability order in wireable form; the port and the
rule can desync; and the checker already dissolved its relational needs
into per-wire paths computed from flow structure. Survives only as a drawn
view.

**2. The multi-row partial collect** — one merge node growing m value
rows. Rejected: rows are independent (each a complete lawful collect
alone), so co-locating them contradicts the criterion and the multi-close
grain; and the packing pressure that motivated it dissolves under the
context-equality theorem, since two sibling collects' outputs share a
context and combine freely. Survives as a drawn/recognized view of m
siblings.

**3. Race over pre-opened flows** — winner values recovered by
availability, cell i read as a sub-flow of contender i's opened context.
Tempting because it would make race flow-only, but wrong three ways:
race's compiled act is to start and await the async *values*, not to
operate on contexts; the losing contenders' opened contexts are
structurally unrelated to the race's partition (they fire on their own
resolution regardless of the race); and the case-split precedent is
values-in — the sum-side uncollect consumes the thing whose settlement
creates the partition.

**4. A tuple (or record) output for the many-kind discharge** —
`(prefix, terminator)` as one packed value. Rejected: it is the product
bottleneck verbatim, two co-present values packed to pass a structural
point. Two ports on one node instead.

**5. The absorb collect** — a standalone terminator-swallowing total fold
("the prefix, ignoring how it ended"). Rejected: it erases the failure
signal by default, which propagate-by-default exists to prevent. The total
prefix is available only at a discharge, beside the terminator it took in
hand.

## Open questions

1. **Adoption.** This round is prepared for the design conversation; each
   home doc marks its corner as worked here, none as decided.
2. **Spec reconciliation.** On adoption: revise the spec's Join signature
   (drop `values`, or mark the value rows as drawn availability), per its
   own status note; give the discharge pair and the race barrier their
   spec entries; and decide whether the m-siblings-one-glyph merge
   rendering is a level-1 recognition catalog entry.
3. **Concurrent join × Cross.** Same availability mechanism, same product
   segment, both flow-only — one construct with two kind instances, or two
   constructs? Strengthened here; decide at the barriers' Expr round
   (`product-flows-design.md`).
4. **The race round proper.** Fairness, N-ary composition,
   abandonment/cancellation, merge/interrupt as derived combinators — now
   written in `race-barrier-design.md`, building on this round's port
   answer unchanged. One addition touches this subject: a subset partial
   collect over a race bundle leans failable-by-construction, its
   terminator written at the settlement that decides all cells — a
   kind-instantiation of the partial collect, not a change to the crossing
   story.
5. **Terminator payload composition** (`E1`/`E2` across chained
   failability) — unchanged from the async residuals, and clearly a
   value-level question, not a port question.
6. **Merged-flow identity** (partial-collect open question 4) — unchanged;
   the m-siblings answer adds a place it could matter (m redundant merged
   flows over one cell set, if stream chain sharing ever keys off flow
   identity). Interim rule as there: bind once and reuse.
7. **Naming.** "Discharge" as the surfaced word for terminator-to-data;
   the pair's port names (`prefix` / `terminator`, or plainer words);
   deferred to the naming sweep, ledgered in
   `implementation-strategy.md`.

## What this doesn't address

- **Race semantics beyond ports** — per open question 4.
- **Cancellation and effects on abandonment** — the Tier-1 gap is
  untouched; nothing here constrains it beyond the async round's record.
- **The visual rendering of barriers** — how drawn value wires cross a
  barrier line is the layout side's question, out of scope in this repo;
  this round only says which of those wires are representation and which
  are derived view.
- **Implementation.** Everything here lands on the first-class-ports
  migration (the flow-only Join is its step 3; the discharge pair and race
  arrive with the async work). No compiler change is proposed now.
- **Whether end-when is adopted.** Its readout is *cited* as designed;
  confirming the discharge pair does not move that round's own adoption
  question.
