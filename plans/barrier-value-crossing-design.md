# How Values Cross a Barrier

Status: mixed (design conversation, 2026-07-23) — the **two
mechanisms, the availability law, the co-location criterion, and
corner 1 (flow-only joins) are adopted**, with one clarification
recorded under the law: a value wire does not participate in a
flow operation, so it is neither upstream nor downstream of one —
the ordering is on contexts only. Corner 2 (race) is **adopted with an amendment**: per-contender
(flow, payload) pairs in — the pair the lean, the bare async
value the isomorphic aggregate — race re-read as the partial
collect's async sibling (see its section). Corner 3 (the partial
collect) is **adopted**: m rows = m sibling collects, backed by
the context-equality theorem, with a recorded naming constraint —
the node's surfaced name should not contain "collect" (it stays
in flow-land).
**Corner 4 (the discharging collect) is contested**: the
discharge-barrier direction (`failure-payloads-design.md`, "The
discharge barrier") weakens its settled-sum justification —
fail-as-uncollect gives every failure an independent upstream
wire — and proposes the unbottlenecked barrier form as a live
alternative; do not ratify corner 4 as written without that in
the room. Nothing is implemented. Several other chapters each
stopped at this question and pointed at the others; this is the
one place it is worked through.

## Your first crossing

You will often have a value on one side of a place where flows meet,
and need it on the other side. Here is the simplest program with that
shape — fetch two things at once, then add the results:

```
urlA -> open async => a, ~A
urlB -> open async => b, ~B
~A, ~B ~> join all => ~ab        -- flow-only: no value crosses the node
a, b -> add -~> collect => total -- both values readable in the merged context
```

Read it line by line. Opening an async value gives you two ports: the
value once it arrives (`a`) and the flow that fires when it does
(`~A`); `=> a, ~A` names both. `join all` takes the two flow wires
and gives back one flow, `~ab`, that fires once both have. Then `add`
uses `a` and `b` together, in the after-the-join world, and the
collect closes.

Now look at what did *not* happen: `a` and `b` never entered the
join. Only flow wires did — the comment on that line is literal. Yet
both values are perfectly usable on the far side.

A meeting place like this — a join, a race, a collect, a Cross,
anywhere several flows come together — is called a **barrier**. The
question this chapter answers is: when a value needs to be usable on
the far side of a barrier, how does it get there? The no-bottlenecks
principle rides on the answer, because the wrong answer is to pack
the value into a tuple or tagged union just to carry it across.

The answer turns out to be two mechanisms plus one rule about which
outputs share a node — and the program above already shows the first
mechanism. `a` and `b` reach the far side because they were *never
out of reach*: the joined context sits above both of the contexts
they were born in. Nothing crossed. We will name this
**availability** shortly, and meet the second mechanism (values that
are genuinely *born at* a barrier) through the race and the partial
collect.

A little vocabulary before we go on, so nothing later surprises you.
**Uncollect** and **collect** are the fundamental open/close
operations from the core chapter (the code spells them `Open` and
`Close`). When a case split or a race divides a flow into mutually
exclusive branches, the set of branches is a **bundle** and each
branch is a **cell**. The stack of flows a value lives under is its
**context path**, and **comparability** is the ordering on those
paths — plainly, whether one context sits inside another, which is
what decides whose values are in reach. These are defined properly in
`bundle-provenance-design.md`, `partial-collect-design.md`, and
`first-class-ports-design.md`.

## Where the question came up

This chapter exists because the same question surfaced identically in
four places, each of which stopped at this corner and pointed at the
others:

| Home | The corner |
|---|---|
| `first-class-ports-design.md`, open question 3 | Does the binary Join carry the spec's corresponding value ports, or stay flow-only? "It would be odd for the flatten join and the concurrent join to disagree on port shape for no semantic reason." |
| `async-flow-design.md`, "Racing is a barrier, not a value" | Race has per-contender value + flow output pairs — more port structure than any other node carries. |
| `partial-collect-design.md`, open question 3 | k branches × m corresponding value rows: does the partial collect grow rows, or does a second value crossing the merge take a second node? |
| `async-flow-design.md`, failability residuals | The discharging collect's port structure — `(prefix, terminator)` is more port structure than current collect nodes carry. |

A fifth party depends on the outcome: `end-when-design.md`'s readout
leans entirely on the discharge shape, so first-match, take-until,
and poll-until-result all read from whatever is decided here.

And the demand is real, not theoretical. The concurrency survey
(`real-loop-survey.md`, survey 3, finding 3.2) found that in every
hand-rolled race sampled, "which contender won" was reconstructed
after the fact from side state — flags, `None` checks, state enums —
never delivered structurally. How a value crosses the race barrier is
the thing that hand-written code visibly lacks.

## Reading off what the language already does

Before proposing any rule, it pays to read the record: the design
already contains five places where a value passes a barrier. Watch
what each one actually does.

**The flatten join — nothing crosses.** The implemented compile never
transports a value through a join. A collect on a combined flow
simply references the per-element bindings of every level its walk
spans (`lazy-compile-design.md`). This is right, not merely
expedient: the combined flow fires exactly when the inner operand
fires, so its firings *are* inner firings, and everything readable
per inner firing was already readable there
(`lazy-stream-join-design.md`, the law of the combined flow). The
join changed which terminations exist, not which values are in reach.

**Cross — availability, stated as such.** From
`product-flows-design.md`: "Values cross the boundary by the ordinary
invariance rule… an axis's element is readable at the product's
points because the product context is deeper than each axis. No
packing, no transport ports." Cross is a node with flow ports and no
value ports.

**The concurrent join — availability, one step wider.** This is the
join in your first crossing above. The fork-join compile starts both
cells and combines both resolved values in the merged context
(`async-flow-design.md`, "Sequential and parallel are structural").
No port carries `a` or `b` through the join; the merged context is
simply one in which both are readable — which requires it to sit
*above both* operand contexts in comparability. That is exactly the
product context Cross adds to the provenance model. The concurrent
join is to sibling async flows what Cross is to sibling iterations.

**End-when — availability, by its own theorem.** From
`end-when-design.md`: "Each firing of the shortened flow is a firing
of the subject, so values from the subject's context are readable in
the shortened flow's context directly… No transport machinery."

**The partial collect — a genuine transport, the only one.** Here a
value really moves. A partial collect merges some cells of a bundle
back into one flow, and the merged flow's value output is *the firing
branch's value*, carried from k mutually-exclusive cells out to their
union. This is not derivable from availability — containment only
ever admits values inward (`{A} ⊆ {A, B}` lets merged-context values
into a cell, never a cell's value out to the merge). The
partial-collect design made that one-way door a feature: "coarsening
happens only at the explicit node." The partial collect's value row
is a port because no rule could replace it.

The sample splits cleanly in two, and the split is the design.

## The two mechanisms

**Mechanism 1 — availability.** A value defined upstream of a barrier
stays usable downstream because the barrier's output context sits at
or above the value's context in the context order. Nothing crosses;
the value was already in reach, and the barrier's flow law is what
put the output context where it is.

> **The availability law.** Barriers carry no pass-through value
> ports. A value is readable at a context downstream of a barrier iff
> that context is ≥ the value's context in the context order, and the
> barrier's flow law determines where its output context sits in that
> order.

One clarification recorded at adoption (2026-07-23): **a value
wire does not participate in a flow operation** — it is impossible
to say whether a value wire is upstream or downstream of a join, a
race, or any barrier; position in flow topology is a property of
flows and contexts only. In your first crossing above, the `add`
of `a` and `b` is neither upstream nor downstream of the join. The
law's "downstream" — and this chapter's upstream/downstream
phrasing for values generally — is shorthand for the context
relation: what is ordered is the value's *context* against the
barrier's output context, never the value wire itself. This is
easy to lose when reading the textual form, whose lines are
listed in sequence; it changes nothing in the law.

Why insist the barrier carries *no* pass-through value port, even as
a convenience? Because such a port would be a second, wireable
spelling of a fact the provenance order already states — two
vocabularies for one reading. That is the whole argument against it.
(There was a proposal to add exactly these ports everywhere; you'll
meet it, and why it died, in the join section below.)

**Mechanism 2 — minted ports.** Some barrier outputs are *born at the
node*: projections, resolutions, selections, or settlements that
exist nowhere upstream as wires. These are value ports, held in the
per-kind inventories that first-class ports already models:

| Node | Minted value outputs | What the mint is |
|---|---|---|
| uncollect (list/option) | `element` | projection of the opened value |
| uncollect (case split) | per-alt payload | projection under dispatch |
| race barrier | per-contender resolved value | resolution at settlement |
| partial collect | the merged value (one row) | selection: the firing branch's value |
| collect | `result` | the fold/packaging of the walk |
| discharging collect | see below | the settlement of the terminator |
| Delay write half | `final` | the register after the flow completes (the pair is worked, not yet adopted — `iteration-with-state-design.md`, "The Delay back-edge") |

The two mechanisms compose, and their composition is the whole story
of a sum barrier: **into a cell by availability, out of a bundle by
the partial collect.** A constant or an ancestor value is readable
inside any race cell or case alt with no machinery (the prefix rule);
the winner's value reaches the post-race world through the covering
partial collect's minted row.

Which mechanism applies is read off the barrier's character:

- **Product barriers extend contexts.** All operands continue
  together; the output context is above every operand; every
  operand's values stay readable. Nothing to select, so no value
  ports — the concurrent join, Cross, and the flatten join are
  flow-only. (The flatten join degenerately: its operands were
  already nested, so the combined context adds nothing readable.)
- **Sum barriers refine contexts.** The cells partition the parent;
  per cell, what is readable is the parent's ancestry plus that
  cell's mints; sibling cells stay mutually unreadable (bundle
  mixing, as ever). The only way back to a coarser context is an
  explicit minted selection — the partial collect.

## When minted outputs share a node

Mechanism 2 leaves one question: when do several minted outputs share
one node, and when are they several nodes? The record answers from
both directions.

From multi-close (one flow, many collects — a value output multiplies
as a *consumer*, never as node width): each collect is a complete
construct alone, and nothing relates two collects of one flow except
the flow itself, which is an operand, not a node. Independent outputs
are independent nodes.

From bundle provenance: a bundle's cells *cannot* be independent
nodes. Cell i of a race means "contender i settled first" — a fact
about every contender. The exclusivity the mixing check enforces is a
relation among all the cells, and the provenance store holds only
unary per-wire facts, so the one place that relation can live is the
node that creates the partition. The same holds for a case split's
alts.

> **The co-location criterion.** Minted outputs share one node
> exactly when the node's law ties them together — when at least one
> output is only lawful with the others in hand. Outputs each
> obtainable by a complete construct of their own are separate nodes.

The criterion reproduces every port inventory the record already
committed to (case split's partition; race's partition; the Delay
pair, where `final` is the write half's output and `prev` the read
half's — two nodes because each half is a complete act), and it
decides the two contested corners below.

## The four corners, answered

Now back to the four homes, one at a time, each with its answer
derived from the two mechanisms and the criterion.

### 1. Join and the concurrent join: flow-only stands

The lean in `first-class-ports-design.md` — a flow-only
`Join({outer, inner})`, values meeting the join only at collects — is
confirmed. Your first crossing is the flow-only spelling in the
textual form; here it is again, now with the full story in hand:

```
urlA -> open async => a, ~A
urlB -> open async => b, ~B
~A, ~B ~> join all => ~ab        -- flow-only: no value crosses the node
a, b -> add -~> collect => total -- both values readable in the merged context
```

`a` and `b` reach the merged context by availability (their
provenance is a prefix of `~ab`'s), not by passing through the join —
which is exactly why the node needs no value ports.

The worry attached to the lean dissolves. That worry was that the
concurrent join "genuinely transports values," so it and the flatten
join might disagree on port shape for no semantic reason. Under the
availability law they agree, for a stated reason: both are
product-side barriers, and product-side crossing is availability. The
flatten join's output context is the inner operand's (nothing new
readable); the concurrent join's is the product of its operands'
(everything on either side readable). Neither mints a value; neither
carries a value port.

The construct that *does* differ — race — differs because it is the
sum barrier: its per-cell values are mints, and mints are ports. So
the worry inverts into a diagnostic: **port shape follows the
product/sum character of the barrier, not the barrier-ness.**

Now, you might wonder why the language doesn't just give every
barrier corresponding value ports — the spec's `Join` signature
(values in, "same names" out — `visual-language-spec.md`),
generalized to every barrier as representation-level structure, so a
value visibly rides across the node. It turns out this would cause
problems: it duplicates the availability order in wireable form, so
the port and the rule can desync — two spellings of one fact that can
come apart; and the checker already dissolved its relational needs
into per-wire paths computed from flow structure, so the ports would
carry no information the paths don't. What the spec's signature got
right survives as a *drawn* form of availability: where a value wire
visually crosses the barrier line, the diagram may want to show it
crossing. That is a derived-view rendering of the provenance fact,
not representation-level structure. (This is a recorded dead end of
this proposal — please don't re-propose it without new evidence. It
survives only as a drawn view.)

This round does not edit the spec; reconciling its `Join` signature
is an open question below.

### 2. Race: values in, minted pairs out

The async doc's race shape — per contender i, an output flow (fires
iff i won) and an output value (i's resolved value) — is confirmed,
now derived rather than asserted:

- The inputs are async **values**, not opened flows. Race is a
  consumer: its compiled act is to start all contenders and await the
  first settlement — starting is something one does to an async
  value, not to a context. This mirrors the case split, which
  consumes the sum *value*; nobody pre-opens the alternatives before
  dispatching. Race is the sum-side multi-input uncollect: it opens N
  async values into one bundle.
- The per-cell values are **mints** — contender i's resolution exists
  nowhere upstream as a wire.
- Cells and their mints **co-locate on one node** by the criterion:
  cell i's law quantifies over every contender.

```
fetch:   fetchD
timeout: after(30)
-> race => r
~r.fetch:   r.fetch -> process -> some
~r.timeout: none
-~> collect => out
```
*Two async values race; the winner's cell fires with its resolved
value, and the covering collect over the race bundle carries the
winner's value out to the parent — into the cell by availability, out
of the bundle by selection.*

This is where the survey's finding lands. The side-flag
reconstructions survey 3 found (`request is not None`, `reply.sent`,
four-state enums) are programs paying by hand for exactly the minted
discrimination this port shape delivers.

Now, you might wonder why race doesn't work over pre-opened flows
instead — open each contender first, then race the *contexts*, with
winner values recovered by availability and cell i read as a sub-flow
of contender i's opened context. It's tempting, because it would make
race flow-only like the joins. It turns out this would be wrong three
ways: race's compiled act is to start and await the async *values*,
not to operate on contexts; the losing contenders' opened contexts
are structurally unrelated to the race's partition (they fire on
their own resolution regardless of the race); and the case-split
precedent is values-in — the sum-side uncollect consumes the thing
whose settlement creates the partition. (This is a recorded dead end
of this proposal — please don't re-propose it without new evidence.
The adopted pair form below shares the flows-in *surface* but none
of these mechanics — its cells are minted at the node, its values
carried as mints, its contenders demand-started — so it is not
this dead end.)

**Adopted with an amendment (design conversation, 2026-07-23).**
The corner is decided, but the input shape is amended. The
conversation distinguished three shapes where this chapter weighed
two:

- a **bare async value** — no associated flow wire, the
  computation as one aggregate thing (the values-in form above);
- the **(flow wire, payload value wire) pair** — the opened form,
  the payload descending from the flow's context;
- the dead end above — contexts alone, cells as sub-flows, values
  by availability. Still dead.

Both of the first two are admissible — they are isomorphic, and a
bare value fed to the race is an open, completed or spelled
`-~>` — and **the pair is the lean**, on a stated principle worth
keeping: *a barrier is a control-flow operation and must consume
something that stands for the control flow; a value representing
a computation is valid but esoteric — the higher-order-function
objection again (`configuration-scopes.md`) — so the control flow
should be spelled as a visible flow wire.* The uniformity argument
above is answered rather than defeated: openers (case split, list
open) create control flow from a value, so they take no flow
input; race presupposes existing async computation, and the
precedent for operating on *existing* control flow — join,
commute, end-when — is flow wires in. Under the pair form **race
is the async sibling of the partial collect**: the sum side's
explicit transport node — async context flows in, the
first-settling contender's in-context payload carried out through
the one-way door as a mint. The values-in form fuses an opener
into the transport, and it costs a collect per pipeline contender
(packaging `a -> parse -> transform` in ~A back into an async
value) that the pair form saves — racing `(~A, transformOut)`
directly.

Unchanged by the amendment: the cells and their mints co-locate
on one node (the partition quantifies over all contenders), and
the winner's value is a mint, never availability. Reshaped: the
unary-race leaning — under pairs, **await = open async** (the
opener), and the N=1 race is the degenerate transport, harmless
(the one-cell partial collect's sibling); noted for
`race-barrier-design.md`. One new check: the pair must cohere —
the payload must descend from the flow wire's context (`-~>`
guarantees it by construction; the explicit form gets a
provenance check). The wire-mess cost is acknowledged and filed
to the layout/textual side (`-~>` carries most of it textually:
`a, t -~> race => r`). The amendment rhymes with the
discharge-barrier direction recorded the same day
(`failure-payloads-design.md`): the sum side gets one grammar —
flows plus in-context payloads in, minted bundle out, one law per
barrier (first settlement here; the ending there).

Race's full semantics — fairness, N-ary composition, abandonment —
remain owed (`async-flow-design.md` question 5, taken up in
`race-barrier-design.md`). This settles only the port/crossing corner
that was blocking the other homes.

### 3. The partial collect: rows are collects, not a wider node

The contested corner: two values crossing the same merge. The
recorded reservation read the options as "either take two partial
collects or pack," and leaned toward a multi-row barrier node as "the
principled completion." Worked concretely, the dilemma is false: two
sibling collects were already the no-pack answer. What made them look
inadequate was an unexamined assumption that two nodes' outputs would
land in two incomparable contexts.

Let's work it. Extending the HTTP merge from
`partial-collect-design.md`: two error cells share their handling,
and the handler needs *two* values across the merge — the status code
(for the log line) and the parsed Retry-After (for the backoff). Each
value is its own sibling collect over the same cell set (spelling
provisional):

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
*Two partial collects over the same `{ClientError, ServerError}` cell
set; their two merged values combine in one `logAndFallback` App with
nothing packed.*

But wait — can `errStatus` and `errRetry` legally meet at
`logAndFallback`? They come from two different nodes. Yes, and this
is the fact the multi-row lean missed:

**Theorem (context equality).** The two collects' value outputs are
combinable with no further machinery. Both carry a bundle step with
cell set `{ClientError, ServerError}`; comparability at a bundle step
is containment on cell sets, and the sets are *computed by walking,
never stored* (`partial-collect-design.md`) — node identity does not
enter. Equal sets are mutually contained, so both outputs live at the
same context and the App is well-formed there.

So m corresponding value rows are **m sibling partial collects over
the same cell set.** Nothing packs, nothing new is needed, and each
row is a complete construct alone — which is the co-location
criterion saying "separate nodes." The grain matches multi-close: a
second output of a merge is added beside the first, the merge
untouched.

Now, you might wonder why the language doesn't just let one merge
node grow m value rows — a single multi-row partial collect, which is
what the earlier round leaned toward. It turns out this would cause
problems: the rows are independent (each a complete lawful collect
alone), so co-locating them contradicts the criterion and the
multi-close grain; and the packing pressure that motivated it
dissolves under the context-equality theorem, since two sibling
collects' outputs share a context and combine freely. What the
multi-row form got right survives as presentation: one drawn barrier
line with m value wires crossing is a natural *rendering* of m
sibling collects sharing a cell set — a candidate level-1 recognition
entry. The representation stays m nodes. (This is a recorded dead end
of this proposal — please don't re-propose it without new evidence.
It survives as a drawn/recognized view of m siblings.)

Two deferrals, kept rather than newly decided:

- The m collects mint m merged *flows* over one cell set; the final
  covering collect references either. Whether same-cells merged flows
  are one flow or many is open question 4 of the partial-collect
  round, unchanged; the interim rule (bind once and reuse) applies.
- The covering instance inherits the answer: a case collect stays
  single-result, and two results over one bundle are two collects —
  which is what the implemented multi-close on case splits already
  does.

**Adopted (design conversation, 2026-07-23).** The
context-equality theorem and the m-siblings answer stand; the
multi-row node stays the dead end (surviving as the
drawn/recognized view); both deferrals above are kept. Two notes
from the conversation ride along. First, the sibling flows'
redundancy is understood, not accidental: two partial collects
over one cell set mint interchangeable flows — nobody would draw
a second collect *for the flow*; a second collect exists for its
value row, and the flow duplication is exactly what the
partial-collect round's open question 4 (one flow or many) will
dedupe, with bind-once-and-reuse the interim rule. Second, a
**naming constraint** is recorded (mirrored at
`partial-collect-design.md`, "Naming"): calling this node a
*collect* is not ideal — a regular collect leaves flow-land (flow
in, value out) while this node stays in it (it produces a flow
wire) — so the surfaced name should not contain "collect."

### 4. The discharging collect: one port or two, by kind

The last corner is about failure. A failable flow can end early, and
its ending carries a **terminator** — the "how it ended" signal.
**Discharge** is the moment a whole-flow collect takes that
terminator in hand as ordinary data instead of passing it onward. A
discharge is a mint — the terminator, settled, becoming data at the
collect. Its port structure splits by the flow kind's row in the
failability table, and both halves follow from principle.

**Exactly-one kinds (failable async): one value output, a settled
sum.** The fired value and the failure payload are never co-present —
the flow delivered or it didn't — and they are born at one settlement
with no independent upstream wires. That is precisely when a data sum
is honest rather than a bottleneck. One port: `Ok(x) | Fail(e)`
(spelling aside), case-split downstream like any data. Outcome cells
arise only from an ordinary case split after the fact; the discharge
does not mint a second bundle.

**Many kinds (failable list/stream): two value outputs, on one
collect.** Here the two *are* co-present — every ending has a prefix
*and* a terminator — so a sum cannot carry them.

Now, you might wonder why the discharge doesn't just emit one packed
value, a tuple (or record) of `(prefix, terminator)`. It turns out
this is the product bottleneck verbatim: two co-present values packed
merely to pass a structural point, torn apart immediately after —
exactly what no-bottlenecks forbids. Two ports on one node instead.
(This is a recorded dead end of this proposal — please don't
re-propose it without new evidence.)

And the two ports co-locate on one node by the criterion,
non-obviously. The subtlety: each output *looks* independently
obtainable (a fold of what fired; the terminator as data), which
would argue for two sibling collects.

Now, you might wonder why the language doesn't offer the standalone
half anyway — an "absorb collect," a terminator-swallowing total fold
that gives you "the prefix, ignoring how it ended." It turns out this
would be an error-swallowing primitive: it erases the failure signal
by default, which propagate-by-default exists precisely to prevent. A
collect either propagates the terminator (default; output failable;
one `result` port) or *discharges* it — takes it in hand as data. The
total prefix is only lawful *at a discharge*, beside the terminator
it took in hand. (This is a recorded dead end of this proposal —
please don't re-propose it without new evidence.)

That "only lawful with the other in hand" is the criterion's exact
wording, so the pair shares the node:

> A discharging collect on a many-kind failable flow has two value
> outputs: `prefix` (the fold of what fired — total) and `terminator`
> (the ending, as data). Taking the terminator alone is partial use —
> the prefix port unwired — exactly as partial use of any node's
> ports is already sanctioned.

`end-when-design.md`'s readout is confirmed unchanged: its whole-flow
collect "→ (prefix, terminator)" is this node; first-match wires the
terminator port and leaves the prefix unwired; take-until-sentinel
wires both. Terminator payload *types* — composing `E1` and `E2`
across chained failability — remain the async round's residue,
untouched: a question about the terminator value, not about ports.

## The crossings, tabulated

| Construct | Flow law (where the output context sits) | Value crossing |
|---|---|---|
| flatten join (outer, inner) | fires iff inner fires; context = inner's | availability (degenerate — nothing new readable) |
| concurrent join | fires when all operands have; context = product of operands' | availability (product segment) |
| Cross | once per pair; context = product of axes | availability (stated in its round) |
| end-when (subject, stop) | prefix of subject's firings | availability (prefix admission, its theorem) |
| race | cells partition the parent by first settlement | inputs per contender: (flow, payload) pairs (adopted lean; a bare async value is the completed-open aggregate); mint: per-cell (value, flow) pairs, one node |
| case-split uncollect | cells partition the parent by dispatch | mint: per-alt (value, flow) pairs, one node |
| partial collect | merged flow fires iff a branch fires; context = union cell set | mint: the firing branch's value — one row per node; m rows = m sibling nodes |
| collect (propagating) | terminates; output at parent | mint: `result` (failable if the flow was) |
| collect (discharging, exactly-one kind) | terminates; output at parent | mint: one settled-sum value |
| collect (discharging, many kind) | terminates; output at parent | mint: `(prefix, terminator)` pair, one node |

## Fit with provenance and the checks

Nothing new is needed — which is the strongest evidence the split is
right:

- Availability *is* the comparability order
  `bundle-provenance-design.md` and its extensions already define:
  prefix on open steps, containment on cell-set steps (the
  partial-collect refinement), axis-below-product on product segments
  (the Cross refinement). The law adds no step kind; it observes that
  every barrier's crossing story is already a sentence in that
  vocabulary.
- The race's cells were already a row of the bundle inventory
  ("exactly one fires per settlement of the race"); the mixing check
  meets them unchanged.
- The concurrent join minting a product context strengthens the
  question `product-flows-design.md` already recorded — whether it
  and Cross are two kinds' faces of one construct. Strengthened, not
  decided; it stays with the barriers' Expr round.
- The one-way door stands: containment admits inward, the partial
  collect carries outward, and there is no third mechanism — so
  "coarsening happens only at the explicit node" is now backed by the
  full barrier inventory, not just the case split's.

## Against the philosophy

- **No bottlenecks.** Product side: nothing packs because nothing
  even crosses — the values were in reach all along. Sum side:
  nothing packs because selection is an explicit node with one minted
  row per value, never a tag-and-unpack. A packed sum or product is
  still fine when wanted as data on purpose; only packing-*to-pass*
  is ruled out, now mechanically.
- **One obvious reading.** A pass-through value port would be a
  second spelling of the availability fact. Flow-only barriers leave
  one reading. Likewise m rows on one node vs m nodes: one grain
  (consumers multiply as nodes), not two.
- **Example first, then generalise.** The law and the criterion are
  read off five crossings the record already contains and two
  implemented behaviors (the joined collect's walk; multi-close). No
  construct was designed and then hunted for uses.
- **Building blocks must build.** +1 value across a product barrier =
  one more reference; +1 value across a merge = one more sibling
  collect; +1 outcome distinction at a discharge = a case split on
  the terminator port. All additions; no species changes.
- **Abstraction is the source of truth.** The drawn barrier with
  corresponding value wires survives as a derived view over the
  minimal representation, never the thing edited.

## The dead ends, indexed

Each rejected idea is recorded in place above, in "now, you might
wonder" form, with its full reason; this index is so a design reader
can find them:

1. **Universal corresponding value ports** — in "Join and the
   concurrent join." Duplicates the availability order in wireable
   form; survives only as a drawn view.
2. **The multi-row partial collect** — in "The partial collect."
   Contradicts the criterion and the multi-close grain; its packing
   pressure dissolves under context equality; survives as a
   drawn/recognized view of m siblings.
3. **Race over pre-opened flows** — in "Race." Wrong three ways:
   race consumes values, losers' contexts are unrelated to the
   partition, and the case-split precedent is values-in. (The
   adopted pair form, 2026-07-23, is not this: it shares the
   flows-in surface but mints its cells at the node and carries
   values as mints.)
4. **A tuple output for the many-kind discharge** — in "The
   discharging collect." The product bottleneck verbatim.
5. **The absorb collect** — in "The discharging collect." An
   error-swallowing primitive; the total prefix lives only at a
   discharge, beside the terminator.

## Open questions

The language hasn't decided these yet:

1. **Adoption.** This round is prepared for the design conversation;
   each home doc marks its corner as worked here, none as decided.
2. **Spec reconciliation.** On adoption: revise the spec's Join
   signature (drop `values`, or mark the value rows as drawn
   availability), per its own status note; give the discharge pair
   and the race barrier their spec entries; and decide whether the
   m-siblings-one-glyph merge rendering is a level-1 recognition
   catalog entry.
3. **Concurrent join × Cross.** Same availability mechanism, same
   product segment, both flow-only — one construct with two kind
   instances, or two constructs? Strengthened here; decide at the
   barriers' Expr round (`product-flows-design.md`).
4. **The race round proper.** Fairness, N-ary composition,
   abandonment/cancellation, merge/interrupt as derived combinators —
   now written in `race-barrier-design.md`, building on this round's
   port answer unchanged. One addition touches this subject: a subset
   partial collect over a race bundle leans failable-by-construction,
   its terminator written at the settlement that decides all cells —
   a kind-instantiation of the partial collect, not a change to the
   crossing story.
5. **Terminator payload composition** (`E1`/`E2` across chained
   failability) — unchanged from the async residuals, and clearly a
   value-level question, not a port question. *Now worked*
   (`failure-payloads-design.md`, exploration): the inventory is a
   derived property, composed by propagation — confirming it never
   touches this round's port story.
6. **Merged-flow identity** (partial-collect open question 4) —
   unchanged; the m-siblings answer adds a place it could matter (m
   redundant merged flows over one cell set, if stream chain sharing
   ever keys off flow identity). Interim rule as there: bind once and
   reuse.
7. **Naming.** "Discharge" as the surfaced word for
   terminator-to-data; the pair's port names (`prefix` /
   `terminator`, or plainer words); deferred to the naming sweep,
   ledgered in `implementation-strategy.md`.

## What this doesn't address

- **Race semantics beyond ports** — per open question 4.
- **Cancellation and effects on abandonment** — the Tier-1 gap is
  untouched; nothing here constrains it beyond the async round's
  record.
- **The visual rendering of barriers** — how drawn value wires cross
  a barrier line is the layout side's question, out of scope in this
  repo; this round only says which of those wires are representation
  and which are derived view.
- **Implementation.** Everything here lands on the first-class-ports
  migration (the flow-only Join is its step 3; the discharge pair and
  race arrive with the async work). No compiler change is proposed
  now.
- **Whether end-when is adopted.** Its readout is *cited* as
  designed; confirming the discharge pair does not move that round's
  own adoption question.
