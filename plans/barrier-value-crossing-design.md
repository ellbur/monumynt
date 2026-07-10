# How Values Cross a Barrier

> Exploration round (2026-07-10) — **leanings, not an adopted
> design**, prepared for the design conversation. The subject is
> the question `open-problems.md` lists as "one question living
> in four homes, which the docs themselves say to decide
> together": `partial-collect-design.md` open question 3
> (multi-row value correspondence), `first-class-ports-design.md`
> open question 3 (value pass-through ports on Join), the race
> barrier's per-contender outputs (`async-flow-design.md`), and
> the discharging collect's port structure (same document, the
> failability residuals). The no-bottlenecks principle rides on
> the answer. Method: as in `bundle-provenance-design.md`, sample
> the crossings the record already contains and let the rule
> emerge from the samples; and as in the join correction, ask of
> each contested shape whether the program it describes is
> complete. Nothing here is implemented.
>
> Terminology: **uncollect/collect** per the 2026-07-07
> correction (the code says Open/Close); **bundle**, **cell**,
> and **the law of the merged flow** as in
> `partial-collect-design.md`; context paths, comparability, and
> the clash flavors as in `bundle-provenance-design.md`; ports
> and per-kind inventories as in `first-class-ports-design.md`.

## The question, gathered from its homes

Four designs each stopped at the same corner and pointed at the
others:

| Home | The corner |
|---|---|
| `first-class-ports-design.md`, open question 3 | Does the binary Join carry the spec's corresponding value ports, or stay flow-only? "It would be odd for the flatten join and the concurrent join to disagree on port shape for no semantic reason." |
| `async-flow-design.md`, "Racing is a barrier, not a value" | Race has per-contender value + flow output pairs — more port structure than any node carries. Asserted, not derived. |
| `partial-collect-design.md`, open question 3 | k branches × m corresponding value rows: does the partial collect grow rows, or does a second value crossing the merge take a second node? The doc's own reservation calls the multi-row barrier "the principled completion." |
| `async-flow-design.md`, failability residuals | The discharging collect's port structure: `(prefix, terminator)` is "more port structure than current close nodes carry." |

And a fifth interested party: `end-when-design.md`'s readout
leans entirely on the discharge shape, so whatever is decided
here is what first-match, take-until, and poll-until-result
actually read from.

The field pressure is fresh: the concurrency survey
(`real-loop-survey.md`, survey 3, finding 3.2) found that in
every hand-rolled race sampled, "which contender won" was
reconstructed after the fact from side state — flags, None
checks, state enums — never delivered structurally. How values
cross the race barrier is not a representational nicety; it is
the thing that code visibly lacks.

## Five crossings the record already contains

Method first: before proposing a rule, read off what the
existing constructs already do when a value passes one of them.

**The flatten join — nothing crosses.** The implemented compile
never transports a value through a join: a collect on a combined
flow simply references per-element bindings of every level its
walk spans (`lazy-compile-design.md`), and the binary-join
correction explains why that is right rather than expedient —
the combined flow fires exactly when the inner operand fires, so
the combined flow's firings *are* inner firings, and everything
readable per inner firing was already readable there
(`lazy-stream-join-design.md`, the law of the combined flow).
The join changed which terminations exist, not which values are
in reach.

**Cross — availability, stated as such.** The product round says
it in so many words: "Values cross the boundary by the ordinary
invariance rule, as with every other flow node: an axis's
element is readable at the product's points because the product
context is deeper than each axis. No packing, no transport
ports — the no-bottleneck shape" (`product-flows-design.md`).
Cross is a node with flow ports and no value ports.

**The concurrent join — availability again, one step wider.**
The fork-join compile starts both cells and combines both
resolved values in the merged context (`async-flow-design.md`,
"Sequential and parallel are structural"). No port carries `a`
or `b` through the join node; the merged context is simply a
context in which both are readable — which requires the merged
context to sit *above both operand contexts* in the
comparability order. That is exactly the product context the
Cross round added to the provenance model (a context with two
parent axes, comparability a poset, combination at the least
upper bound). The concurrent join is to sibling async flows what
Cross is to sibling iterations: the node that mints the product
context in which siblinghood stops being a time-travel clash.

**End-when — availability, by its own theorem.** "Each firing of
the shortened flow is a firing of the subject, so values from
the subject's context are readable in the shortened flow's
context directly — the same prefix-rule admission that lets an
ancestor's value into any descendant context. No transport
machinery" (`end-when-design.md`). The family's newest member
already obeys the pattern.

**The partial collect — a genuine transport, and the only one.**
Here a value really does move: the merged flow's value output is
"the firing branch's value," carried from k mutually exclusive
cells out to their union. This is *not* derivable from
availability — containment only ever admits values inward
(`{A} ⊆ {A, B}` lets merged-context values into a cell, never a
cell's values out to the merge), and the partial-collect round
made that one-way door a feature: "coarsening happens only at
the explicit node." The partial collect's value row is a value
port because no rule could replace it.

The sample splits cleanly in two, and the split is the design.

## The two mechanisms

**Mechanism 1 — availability.** A value defined upstream of a
barrier stays usable downstream because the barrier's output
context sits at or above the value's context in the context
order — prefix on open steps, containment on cell-set steps,
axis-below-product on product segments. Nothing crosses; the
value was already in reach, and the barrier's flow law is what
put the output context where it is. No ports, no transport
nodes, no packing — and nothing to wire, which is the point:
a pass-through port would be a second, wireable spelling of a
fact the provenance order already states, two vocabularies for
one reading.

Stated once, as a law:

> **The availability law.** Barriers carry no pass-through value
> ports. A value is readable at a context downstream of a
> barrier iff that context is ≥ the value's context in the
> context order, and the barrier's flow law determines where its
> output context sits in that order.

**Mechanism 2 — minted ports.** Some barrier outputs are born at
the node: they are projections, resolutions, selections, or
settlements that exist nowhere upstream as wires. These are
value ports, in the per-kind inventories first-class ports
already models. The mints in the record:

| Node | Minted value outputs | What the mint is |
|---|---|---|
| uncollect (list/option) | `element` | projection of the opened value |
| uncollect (case split) | per-alt payload | projection under dispatch |
| race barrier | per-contender resolved value | resolution at settlement |
| partial collect | the merged value (one row) | selection: the firing branch's value |
| collect | `result` | the fold/packaging of the walk |
| discharging collect | see below | the settlement of the terminator |
| Delay write half | `final` | the register after the flow completes |

The two mechanisms compose, and their composition is the whole
story of a sum barrier: **into a cell by availability, out of a
bundle by the partial collect.** A constant or an ancestor value
is readable inside any race cell or case alt with no machinery
(prefix rule); the winner's value reaches the post-race world
through the covering partial collect's minted row.

One slogan for where each mechanism applies:

- **Product barriers extend contexts.** All operands continue
  together; the output context is above every operand; every
  operand's values stay readable. Nothing to select, so no value
  ports — the concurrent join, Cross, and the flatten join
  (degenerately: its operands were already nested, so the
  combined context adds nothing) are flow-only nodes.
- **Sum barriers refine contexts.** The cells partition the
  parent; per cell, what is readable is the parent's ancestry
  plus that cell's mints; sibling cells stay mutually unreadable
  (bundle mixing, as ever). The only way back out to a coarser
  context is an explicit minted selection — the partial collect.

## The co-location criterion

Mechanism 2 leaves one question: when do several minted outputs
share one node, and when are they several nodes? The record
answers from both directions.

From the multi-close doctrine: one flow, many collects — outputs
multiply as *consumers*, never as node width. Each collect is a
complete construct alone; nothing relates two collects of one
flow except the flow itself, which is an operand, not a node.
Independent outputs are independent nodes.

From bundle provenance: a bundle's cells cannot be independent
nodes. Cell i of a race means "contender i settled *first*" — a
fact about every contender; the exclusivity that the mixing
check enforces is a relation among all the cells, and the
provenance store holds only unary per-wire facts, so the one
place the relation can live is the node that creates the
partition. The same holds for a case split's alts. Cells, with
their per-cell mints, are ports of one node because the
partition is the semantic object.

> **The co-location criterion.** Minted outputs share one node
> exactly when the node's law ties them together — when at least
> one output is only lawful with the others in hand. Outputs
> that are each obtainable by a complete construct of their own
> are separate nodes.

The criterion reproduces every port inventory the record has
already committed to (case split: the partition; race: the
partition; Delay pair: `final` is the write half's own output,
`prev` the read half's — two nodes, because each half is a
complete act), and it decides the two contested corners below.

## The homes, answered

### 1. Join, and the concurrent join: flow-only stands

`first-class-ports-design.md`'s lean — a flow-only
`Join({outer, inner})`, values meeting the join only at
collects — is confirmed, and the reservation attached to it
dissolves. The reservation was that the concurrent join
"genuinely transports values," so the flatten join and the
concurrent join might disagree on port shape for no semantic
reason. Under the availability law they agree, and for a stated
reason: both are product-side barriers, and product-side
crossing is availability. The flatten join's output context is
the inner operand's (nothing new is readable); the concurrent
join's is the product of its operands' (everything on either
side is readable). Neither mints a value; neither carries a
value port.

The construct that *does* differ — race — differs for a stated
reason: it is the sum barrier, its per-cell values are mints,
and mints are ports. The odd-disagreement worry inverts into the
diagnostic: **port shape follows the product/sum character of
the barrier, not the barrier-ness.**

The spec's `Join` signature (values in, "same names" out —
`visual-language-spec.md`) is then the *drawn* form of
availability: where a value wire visually crosses the barrier
line, the diagram may well want to show it crossing. That is a
rendering of the provenance fact, in derived-view territory, not
representation-level structure; the spec's own status note
already anticipates revising the signature "when it lands."
Recorded as the spec-reconciliation item under open questions —
this round does not edit the spec.

### 2. Race: values in, minted pairs out

The async doc's barrier shape — per contender i, an output flow
(fires iff i won) and an output value (i's resolved value) — is
confirmed, and now derived rather than asserted:

- The inputs are async **values**, not opened flows. Race is a
  consumer: its compiled act is to start all contenders and
  await the first settlement — starting is something one does to
  an async cell, not to a context. This is the same shape as the
  case split, which consumes the sum *value*; nobody pre-opens
  the alternatives before dispatching. Race is the sum-side
  multi-input uncollect: it opens N async values into one
  bundle.
- The per-cell values are **mints** — contender i's resolution
  exists nowhere upstream as a wire (the async value is data; if
  some other consumer independently opens the same memoised
  cell, that is a different context, not this barrier's port).
- Cells and their mints **co-locate on one node** by the
  criterion: cell i's law quantifies over every contender.

So the first-class-ports pressure-inventory row for race stands
exactly as written: per-contender value + flow output pairs, on
one construct, fitting the per-kind inventory model directly.

What survey 3 adds is the demand side: the side-flag
reconstructions (finding 3.2 — `request is not None`,
`reply.sent`, four-state enums) are programs paying by hand for
the minted discrimination this port shape delivers. The
reconvergence story is unchanged from `partial-collect-design.md`,
"Every bundle merges": the exhaustive close over contenders is
the covering partial collect over the race bundle, and the
winner's value reaches the parent context through that node's
minted row — into the cell by mint, out of the bundle by
selection.

(The race barrier's own semantics round — fairness, N-ary
composition, abandonment — remains owed per `async-flow-design.md`
question 5. This settles only its port/crossing corner, which is
the corner that was blocking the other three homes.)

### 3. The partial collect: rows are collects

The contested corner: two values crossing the same merge. The
recorded reservation read the options as "either take two
partial collects or pack," and leaned toward a multi-row barrier
node as "the principled completion." Worked concretely, the
dilemma is false — the two-collect spelling was already the
no-pack answer, and what made it look inadequate was an
unexamined assumption that two nodes' outputs would land in two
incomparable contexts.

The worked example, extending the HTTP merge from
`partial-collect-design.md`: the two error cells share their
handling, and the handler needs *two* values across the merge —
the status (for the log line) and the parsed Retry-After (for
the fallback's backoff):

    resp -> open case split
         => Ok, Redirect, ClientError, ServerError cells

    partial collect {CE: status,     SE: status}
      => errFlow,  errStatus
    partial collect {CE: retryAfter, SE: retryAfter}
      => errFlow', errRetry

    logAndFallback(errStatus, errRetry)
      -- one App, combining both merged values

**Theorem (context equality).** The two collects' value outputs
are combinable with no further machinery. Both carry a bundle
step with cell set {CE, SE}; comparability at a bundle step is
containment on cell sets, and the sets are *computed by walking,
never stored* (`partial-collect-design.md`, representation) —
node identity does not enter. Equal sets are mutually contained,
so `errStatus` and `errRetry` live at the same context and the
App is well-formed there.

So m corresponding value rows are **m sibling partial collects
over the same cell sets** — nothing packs, nothing new is
needed, and each row is a complete construct alone, which is
exactly the co-location criterion saying "separate nodes." The
grain is the multi-close doctrine's: a second output of a merge
is added beside the first, and the merge is untouched (the
graceful-expansion +1 test passes additively — as it also would
for the multi-row node, so the deciding argument is the grain of
the record, not the +1 test).

What the multi-row form got right survives as presentation: one
drawn barrier line with m value wires crossing is a natural
*rendering* of m sibling collects sharing a cell set — the same
derived-view move as a `sum`'s lockstep `max`
(`language-design-philosophy.md`, graceful expansion), and a
candidate level-1 recognition entry. The representation stays m
nodes.

Two footnotes, both deferrals kept rather than new decisions:

- The m collects mint m merged *flows* over one cell set; the
  final covering collect references either (coverage reads cell
  sets). Whether same-cells merged flows are one flow or many is
  open question 4 of the partial-collect round, unchanged; the
  interim rule (bind once and reuse) applies.
- The covering instance inherits the answer: a case collect
  stays single-result, and two results over one bundle are two
  collects — which is what the implemented multi-close on case
  splits already does.

### 4. The discharging collect: one port or two, by kind

Discharge is a mint — the terminator, settled, becoming data at
a whole-flow collect. Its port structure splits by the flow
kind's row in the failability table, and both halves follow from
the principles rather than from taste:

**Exactly-one kinds (failable async): one value output, a
settled sum.** The fired value and the failure payload are never
co-present — the flow delivered or it didn't — and they are born
at one settlement with no independent upstream wires, which is
precisely the async round's criterion for when a data sum is
honest rather than a bottleneck. One port: `Ok(x) | Fail(e)`
(spelling aside), case-split downstream like any data. The
first-class-ports pressure table's looser phrase "per-outcome
ports" sharpens to this: outcomes are *data*, and outcome cells
arise only from an ordinary case split after the fact — the
discharge does not mint a second bundle.

**Many kinds (failable list/stream): two value outputs,
`(prefix, terminator)`, on one collect.** Here the two are
co-present — every ending has a prefix *and* a terminator — so
a sum cannot carry them, and a tuple would be the product
bottleneck verbatim: two values packed merely to pass a
structural point. Two ports, then; and they co-locate on one
node by the criterion, non-obviously. The subtlety: each output
*looks* independently obtainable (a fold of what fired; the
terminator as data), which would argue for two sibling collects.
But the standalone total fold — "fold whatever fired, ignore how
it ended" — is an error-swallowing primitive, and
propagate-by-default exists precisely so that failure is never
silently absorbed. The record's stance is that a collect either
propagates the terminator (default; output failable; one
`result` port) or discharges it — takes it in hand as data. The
total prefix is only lawful *at a discharge*, beside the
terminator. That is the criterion's "only lawful with the other
in hand," so the pair shares the node:

> A discharging collect on a many-kind failable flow has two
> value outputs: `prefix` (the fold of what fired — total) and
> `terminator` (the ending, as data). Taking the terminator
> alone is partial use — the prefix port unwired — exactly as
> partial use of any node's ports is already sanctioned.

`end-when-design.md`'s readout is confirmed unchanged: its
whole-flow collect "→ (prefix, terminator)" is this node;
first-match wires the terminator port and leaves the prefix
unwired; take-until-sentinel wires both. The per-kind inventory
model hosts the pair with no new machinery — it joins the Delay
write half's `final` and the case split's per-alt pairs as
inventory rows, which is where `async-flow-design.md` predicted
the pressure would land.

(Terminator payload *types* — composing `E1` and `E2` across
chained failability — remain the async round's residue,
untouched: that is a question about the terminator value, not
about ports.)

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

Nothing new is needed — which is the strongest evidence the
split is right:

- Availability *is* the comparability order
  `bundle-provenance-design.md` and its two extensions already
  define: prefix on open steps, containment on cell-set steps
  (the partial-collect refinement), axis-below-product on
  product segments (the Cross refinement). The law adds no step
  kind; it observes that every barrier's crossing story is
  already a sentence in that vocabulary.
- The race's cells were already a row of the bundle inventory
  ("one flow per contender... exactly one fires per settlement
  of the race"); the mixing check meets them with no changes.
- The concurrent join minting a product context strengthens the
  question `product-flows-design.md` already recorded — whether
  it and Cross are two kinds' faces of one construct (both mint
  the product context; both are flow-only; both make sibling
  values combinable). Strengthened, not decided; it stays with
  the barriers' Expr round.
- The one-way door stands: containment admits inward, the
  partial collect carries outward, and there is no third
  mechanism — so "coarsening happens only at the explicit node"
  is now backed by the full barrier inventory, not just the case
  split's.

## Against the philosophy

- **No bottlenecks.** The principle's two halves each get their
  mechanism. Product side: nothing packs because nothing even
  crosses — the values were in reach all along, and the barrier
  merely built the context where that is true. Sum side: nothing
  packs because selection is an explicit node with one minted
  row per value, never a tag-and-unpack. Where a packed sum or
  product is genuinely wanted, it is constructed as data on
  purpose (the partial-collect round's `First(a)`/`Second(b)`
  example) — data remains fine; only packing-to-pass is ruled
  out, now mechanically.
- **One obvious reading.** A pass-through value port would be a
  second spelling of the availability fact — wire it, or rely on
  the rule? Flow-only barriers leave one reading. Likewise m
  rows on one node vs m nodes: the record keeps one grain
  (consumers multiply as nodes) instead of two.
- **Example first, then generalise.** The law and the criterion
  are read off five crossings the record already contains and
  two implemented behaviors (the joined collect's walk;
  multi-close); no construct was designed and then hunted for
  uses.
- **Building blocks must build.** +1 value across a product
  barrier = one more reference (no edit anywhere); +1 value
  across a merge = one more sibling collect; +1 outcome
  distinction at a discharge = a case split on the terminator
  port. All additions; no species changes.
- **Abstraction is the source of truth.** The drawn barrier with
  corresponding value wires — the spec's Join signature, the
  m-row merge glyph — survives as a derived view over the
  minimal representation, never the thing edited.
- **Foundations before features.** One criterion now, checked
  against every barrier in hand, instead of four port shapes
  decided ad hoc as each construct lands.

## Dead ends

Recorded in place, per convention — each with the reason it
should not be re-proposed:

1. **Universal corresponding value ports** (the spec's Join
   signature as representation-level structure, generalized to
   every barrier). Duplicates the availability order in wireable
   form; the port and the rule can desync, and the checker
   already dissolved its relational needs into per-wire paths
   computed from flow structure. Survives only as a drawn view.
2. **The multi-row partial collect.** Rows are independent —
   each is a complete lawful collect alone — so co-locating them
   contradicts the criterion and the multi-close grain; and the
   packing pressure that motivated the multi-row "principled
   completion" dissolves under the context-equality theorem (two
   sibling collects' outputs share a context and combine
   freely). Survives as a drawn/recognized view of m siblings.
3. **Race over pre-opened flows** (winner values recovered by
   availability, cell i read as a sub-flow of contender i's
   opened context). Tempting — it would make race flow-only —
   but wrong three ways: race's compiled act is to start and
   await the async *values*, which is not an operation on
   contexts; the losing contenders' opened contexts are
   structurally unrelated to the race's partition (they fire on
   their own resolution, race or no race, for whichever consumer
   opened them); and the case-split precedent is values-in — the
   sum-side uncollect consumes the thing whose settlement
   creates the partition.
4. **A tuple (or record) output for the many-kind discharge.**
   `(prefix, terminator)` as one packed value is the product
   bottleneck verbatim: two co-present values packed to pass a
   structural point. Two ports on one node instead.
5. **The absorb collect** — a standalone terminator-swallowing
   total fold ("the prefix, ignoring how it ended"). Erases the
   failure signal by default, which propagate-by-default exists
   to prevent; the total prefix is available only at a
   discharge, beside the terminator it took in hand.

## Open questions

1. **Adoption.** This round is prepared for the design
   conversation; each home doc carries a dated pointer note
   marking its corner as worked here, none as decided.
2. **Spec reconciliation.** On adoption: revise the spec's Join
   signature (drop `values`, or mark the value rows as drawn
   availability), per its own status note; give the discharge
   pair and the race barrier their spec entries; and decide
   whether the m-siblings-one-glyph merge rendering is a level-1
   recognition catalog entry.
3. **Concurrent join × Cross.** Same availability mechanism,
   same product segment, both flow-only — one construct with two
   kind instances, or two constructs? Strengthened here; decide
   at the barriers' Expr round (`product-flows-design.md`,
   relation-to-the-record note).
4. **The race round proper.** Fairness, N-ary composition,
   abandonment/cancellation interplay, and merge/interrupt as
   derived combinators — still owed (`async-flow-design.md`,
   question 5); only the port/crossing corner is worked here.
   *(2026-07-10, later: now written — `race-barrier-design.md`
   takes this list item by item, building on this round's port
   answer unchanged. One addition touches this document's
   subject matter: a subset partial collect over a race bundle
   leans failable-by-construction, its terminator written at the
   settlement that decides all cells — a kind-instantiation of
   the partial collect, not a change to the crossing story.)*
5. **Terminator payload composition** (`E1`/`E2` across chained
   failability) — unchanged from the async residuals, and now
   clearly a value-level question, not a port question.
6. **Merged-flow identity** (partial-collect open question 4) —
   unchanged; the m-siblings answer adds a new place it could
   matter (m redundant merged flows over one cell set, if stream
   chain sharing ever keys off flow identity). Interim rule as
   there: bind once and reuse.
7. **Naming.** "Discharge" as the surfaced word for
   terminator-to-data; the pair's port names (`prefix` /
   `terminator`, or plainer words); deferred to the naming
   sweep, ledgered in `implementation-strategy.md`.

## What this doesn't address

- **Race semantics beyond ports** — per open question 4 above.
- **Cancellation and effects on abandonment** — the Tier-1 gap
  is untouched; nothing here constrains it beyond what the async
  round already recorded.
- **The visual rendering of barriers** — how drawn value wires
  cross a barrier line is the layout side's question, out of
  scope in this repo; this round only says which of those wires
  are representation and which are derived view.
- **Implementation.** Everything here lands on the
  first-class-ports migration (the flow-only Join is its step 3;
  the discharge pair and race arrive with the async work). No
  compiler change is proposed now.
- **Whether end-when is adopted.** Its readout is *cited* as
  designed; confirming the discharge pair does not move that
  round's own adoption question.
