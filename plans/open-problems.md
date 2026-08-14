# Open problems and incomplete areas

A ranked index of where the design record is missing or undecided.
Its only job is to make the gaps findable — it points, broadly, at the
docs (or portions of docs) that own each gap, so "what should be worked
next" doesn't require re-reading everything. It decides nothing and
contains no design content of its own.

## How to read this list

**Broad areas, not work items.** Each row names an area and points at
the doc(s) that own it. The fine-grained open questions live in those
docs, next to the context that produced them and the rejection notes
that keep them honest. Working from this list without reading the
owning doc's status header — and its recorded rejections — is how
re-proposals happen. A row is a door, not a task.

**Two scores, ranked by their product.** Each area carries:

- **Incompleteness (I, 1–5):** how far the area is from a settled
  design. 5 = a name and a demand, nothing worked; 4 = options or
  candidates laid out, core content undesigned; 3 = worked round(s)
  exist but the central decision or major pieces are open; 2 = design
  worked, named residue; 1 = polish.
- **Importance (W, 1–5):** how much a useful overall design needs it.
  5 = the language isn't usable or trustworthy without it; 3 =
  significant but bounded; 1 = gates surface text only.

Rank is roughly I × W, presented in tiers. Adjacent positions within a
tier are noise — do not read the ordering more precisely than the tier
boundaries.

**Frequency is not importance.** The importance score folds in the
80/20 counterweight (`language-design-philosophy.md`, the standing
method's interpretation rule): a rare shape the language must not fail
— a breadth obligation — scores high despite being drawn once. High
survey frequency argues *effortlessness*, which is a different
pressure on the same score.

**This is not a queue.** Always working the top row is exactly the
tunnel vision this format tries to avoid — several areas advance only
when others feed them (evidence reweights scores; the iteration-state
decision wants end-when in the room; barrier ports want race and
partial collect considered together). Drift between tiers is healthy.
Decisions stay in the design conversations; this list only shortens
the search.

**Maintenance.** Whenever an area is worked — a round written, a
decision taken, evidence landed — reassess *both* scores and re-tier
if the product moved. A worked round typically lowers I and sharpens
(not necessarily raises) W. If this index looks stale, trust the
owning docs over it.

**Scope.** Design record only. Implementation sequencing —
workstreams, phases, the cross-cutting ledger — is
`src/ARCHITECTURE.md` (which absorbed the role of the retired
`implementation-strategy.md`) and is deliberately not duplicated here;
compile internals are `compile-strategy-design.md` ("decide in code"
questions stay there); the graphical/layout side is out of scope in
this repo entirely.

**2026-08-04 revision sweep.** One design-conversation series
revised several adopted areas at once; the affected rows below
carry inline updates (end-when → collect-until; failability — fail
dissolved, I raised; loop-carried state — ergonomics round opened;
textual catch-up — new owed spellings). Deltas to rows not
individually rewritten: *variable-rate/cut* — the boundary payload
re-homed to the outer flow, the fused-collect rejection re-grounded
on the mints-a-new-flow criterion, Part III's payload-as-terminator
superseded; *functions/reuse/facets* — the cut re-founded as a node
set with per-wire decisions, copy-paste instance semantics, flow
ports as drawn call-by-name, ops dissolved into port pairs
(`with`-binding rejected), the C-shape with custom flow = C-shaped
sub-diagram used flow-wise, flow-level case selection filed as an
owed construct, contract-as-derived-summary deferred to
types-as-summaries; *barrier crossing* — extended with the scoop,
inferred scoops (route, never select), and the stow/tunnel;
*recursion* — `level of` retired, no level boundary (threads + a
frame source; the frame source's form the open edge); *source
openers* — `open self` as pure frame identity, the frame-source
family connection filed. A cross-cutting principle recorded with
them: provenance is never semantic (`end-when-design.md`, revision
notes, reason 2). Docs carrying explicit "needs updating" notes
from the sweep: `async-flow-design.md`, `speculation-design.md`,
`cancellation-design.md`, `within-firing-effects-design.md`,
`catalog-schema-design.md`, `served-flow-design.md`,
`tough-use-cases-design.md`, `delay-ontology-design.md`. (Update
2026-08-14: the two full re-founding banners are cleared —
`async-flow-design.md` and `speculation-design.md` are rewritten
onto the revised account, superseded shapes recorded in place —
and the sweep's chief owed design piece, the inventory's
re-founding as alt-reach, is now worked
(`failure-payloads-design.md`, final section, unadopted); the
other docs carry lighter read-against inline notes, still standing
where their rounds haven't reopened.)

**2026-08-12 revision sweep.** A second conversation series worked
the recursion area to a landing and retired two standing pieces;
the recursion and functions rows below carry the rewrites. Deltas
to rows not individually rewritten: the **termination/measure
discipline is retired everywhere** (no termination or soundness
checking — stray measure references in other rows read as
historical); the **cyclic back-edge surface is rejected**
(`divide-flow-design.md`, revision notes — three independent
reasons; one synchronizing-uncollect variant deferred, not
rejected); the **visual-leap standing constraint** is recorded
(`language-design-philosophy.md`: thinking about visual
representability is in scope even though building it is not, and a
textual form whose drawing would lie is wrong as text too); the
**frame flow** and the **frame menu** open as new exploration
pieces (the recursion and loop-carried-state rows point at them);
`first-class-ports-design.md` was retired per its own plan
(content absorbed into `core-model.md` and `src/ARCHITECTURE.md`)
and `implementation-strategy.md` retired to a pointer stub; and a
staleness sweep corrected status headers across the record — the
implemented compiler is the five-pass pipeline, and partial
collects, the sibling-opens completion, the provenance core, and
stream flows are implemented; trust the owning docs' dated notes.

---

## Tier 1 — the load-bearing gaps (I × W ≈ 20)

*Empty as of the cancellation round (2026-07-17). The
IO/effects/cancellation row held this tier alone; with both of its
halves now carrying worked exploration rounds, its incompleteness
dropped from 4 to 3 and the row moved to the head of Tier 2, per this
index's own maintenance rule. Nothing there is adopted — the move
records worked-vs-unworked, not settled. Citations across the record to
"the Tier-1 IO round" name that row, not its current tier.*

## Tier 2 — big areas with partial designs (≈ 12–16)

**IO, effects, and cancellation — I 3, W 5.**
The record's most-cited hole, now worked in two halves — both
exploration, neither adopted. **A direction was set at the
2026-07-23 walkthrough**, which deliberately left the row
unadopted (cancellation not yet engaged): **IO is a flow, not a
handle** — an op is an uncollect joining its inner flow upward
into one global IO flow; join's asymmetry is the sequencing (the
IO monad in the record's own vocabulary); the handle wire is
derived as the flow wire, linearity falling out of LIFO-collect;
the flow is forced global (local create/destroy is the lazy-IO
hazard); the within-firing round's handle-granularity leaning
dissolves into a fork/join readability program (symmetric join,
drawn independence, alignment bookkeeping — with the **rail
drawing** as its first concrete win: the global IO wire vertical
in the margin, join points as tap points, position-is-time shared
with the state thread; textually the handle notation is the
synonym, a no-io1-io2 syntax owed); and cross-resource
external interactions (the write-file-then-exec witness, which no
per-resource factoring can capture) are filed as a separate facet
under a recorded stance — **legibility over enforcement**:
external ordering is user-relative (timestamped log appends), so
the language makes sequencedness readable rather than enforcing
rules (`effects-design.md`, "The IO-as-flow direction"). *Effects* (`effects-design.md`):
**commuting an IO flow out of a list flow sequences the
operations** — per-firing segments concatenate in firing order into
one segment, so "collect of an effect flow" (the
translation-exercise gap, `~io'` outside the loop) is the
concatenation's tail — one handle out, never a list; the commute is
mandatory and unique (the handle is linear), so it is never drawn —
consuming the handle after the loop does the job; a *spanning*
handle concatenates and orders effects by iteration order, a
*per-firing-minted* handle is independent and unordered (satisfying
the per-session-IO constraint), the fork read off the drawing not a
mode; the collected-plan pole is retained as an adjacent *batched*
construct, not the everyday form; dead ends recorded, including the
round's own first answer (register on a marker wire — dissolved:
every register port is inert for a marker).
One sharpening that round contributed: effects over a product make the
loop-carried-state row's linearization residue *observable* (writes are
non-commutative, removing the commutative-monoid escape hatch) — a
filing since consumed by that residue's worked round
(`product-linearization-design.md`, exploration: the spanning handle
reads the drawn orientation, no escape hatch needed).
*Cancellation and bracket* (`cancellation-design.md`): **stopping is
drawn, cancelling is delivered** — a program only ceases demand through
drawn constructs (a race settles, an interrupt or end-when fires, a
prefix is taken), and cancellation is the runtime delivering that
ceased demand as one more terminator lane (`Cancelled`) to the
in-flight work it strands, over the demand/necessity frontier the
incremental row already ordered (liveness, memory, and cancellation one
structure); laziness bounds the capability to the in-flight window
(un-started work is cancelled by never starting); there is **no cancel
token** — AbortController dissolves into demand structure the field
reifies by hand, surviving only as the FFI catalog blocks' cancel
translations; the lane discharges outward only (release halves inside
the stranded subtree, ordinary data at any live boundary — the
websockets-4 uncancel pathology inverted); **bracket** is the lifecycle
segment plus a late-wired release half on the acquiring node, consuming
(handle-at-cut, terminator) per lane — Zig's four properties reproduced
without regions, release infallible and uncancellable with its
completion observable as data; silence exists only at the edges (root
exit, vanished requester), converted there by the runtime/FFI; six dead
ends recorded.

A third piece is now worked: *within-firing ordering*
(`within-firing-effects-design.md`, exploration) — within a firing there
is no time (the only intra-firing order is along a handle's segment;
everything else is data dependence), and the conditional-flush buffer
(breadth item 5, the axis's standing witness) dissolves into a
segmentation of the op flow — buffer = per-segment collect, reset =
boundary, flush = per-segment write on the thread, the interleaved raw
op discharged from the segment terminator, so the register half of its
joint ownership was the imperative costume; batching is meaning exactly
when the sink's write doesn't coalesce (a catalog-row law — chunked
encoding is the observable pole); a handle is an ordering commitment,
so a cross-handle order demand marks mis-factored handles, never a new
edge species; five dead ends recorded. Split-when gains its second
everyday client; the conditional effect is an empty segment
(concatenates as identity — no carry machinery).

Residue keeping I at 3: the adoption conversation (one conversation for
the row's halves — the release half consumes the handle after the loop,
and the within-firing round's handle-granularity leaning joins it); the
batched-effect construct's own round; the
permit-pool block (now unblocked by bracket); the threaded op's and the
release half's spellings; the `Cancelled` payload (joint with
failability's composition residue); multi-close — one spanning handle's
single threading consumer, and frontier accounting at walk granularity;
bodies-raise / lightweight failure stays owned by failability (now
worked there — `failure-payloads-design.md`).

W = 5 because ~42% of sampled loops exist to cause effects; roughly
eight of thirty orchestration sites touch
cancellation/abandonment/retention and contain the sample's most
delicate code (`real-loop-survey.md`, survey 3); and both
`async-flow-design.md` (question 2) and `incremental-flow-design.md`
(the pending-pull hole) deferred constraints here that the rounds now
consume. The frequency evidence is measured, not only argued.

Prior art, now consumed structurally rather than pending: XQuery's
pending update list, jq's edge-only effects, and Elm's `Cmd` mark the
collected-plan pole the effects round retains as the batched construct;
the TC39 Signals proposal ships *no* effect construct at all, stopping
exactly at this row. Zig supplies both rounds' field structure —
`defer`/`errdefer`'s four bracket properties, the
allocation-may-fail/deallocation-must-succeed asymmetry,
`Future.cancel`'s cancel-as-await (the cancelled computation still
terminates, readably — the cancellation round's terminator-lane claim
shipped), group-propagated cancellation, and the cooperative floor.
Every Effekt and Flix case study interleaves effects mid-computation —
the row gates ordinary programs, not just effect-heavy ones. See
`translation-exercise.md`, `effekt-comparison.md`, `flix-comparison.md`,
`xquery-jq-comparison.md`, `reactive-comparison.md`, `zig-comparison.md`.

**Loop-carried state after the surface decision — I 2, W 5.**
The surface decision is **made** (2026-07-23,
`iteration-with-state-design.md`, "The surface decision"): the
**visible state thread is the primary framing** — the register pair
stored (the Delay quotient), the point (Delay) and the flow
(augmented uncollect) its two projections, coexistence resolving by
construction as stored-form asymmetry. Recorded with it: the
generic-iteration-picture constraint (the beginner's sum keeps
reading as "prior + element → next, repeated," drawn once over the
generic iteration) and the constant-space caution
(recursion-shaped constructs may eventually be wanted; what they
are is unknown). The two candidates remain proven result-level
equivalent — one register-pair construct under two drawings; the
productivity check holds by construction in the stored form.

Remaining: the **ergonomics round** — now **opened, first pieces
settled** (2026-08-04, `iteration-with-state-design.md`, "The
ergonomics round, opened": the thread as a third connector species
(`@`, provisional), no flow operand on the register — frames
derived from the anchors' contexts, `in ~flow` annotation for the
residue, anchors as ports, the exit a scoop of the read port at
whichever closer the author wires; still owed: the crossing rule,
the one-writeback rule's effect-ordering caveat, the `@` textual
fine print, the stored form's fine print). The register
final-readout anchor is **resolved in the scoop vocabulary** by the
same round (the final is a scoop at the closer you wire — the
worked anchor-rule candidate is superseded); the delay-ontology
binding problem is localized to the annotation's meaning under
commute/product. Also: the self-driven source opener the port form must borrow —
now worked (`source-openers-design.md`: a bare flow-minting opener, no
value ports, kind answered as the sourceless stream; the
counted↔conditional seam it opens is filed back here as that round's
open question); and operator identities for reduce-close — now
**adopted** with the collect family's availability ladder
(2026-07-23, `collect-family-design.md`: the identity question
reframed as the empty-collect question; monoid total, semigroup
option-shaped, non-associative augment-only; identities as catalog
rows carrying the identity value as witness; the runtime-error and
fake-∞ poles confirmed rejected).

Beside the surface decision sits the row's open problem, now its own
document: the **Delay ontology** — what a Delay *is* and which flow
its "next iteration" binds to (`delay-ontology-design.md`, split out
of the iteration-state doc). Where it stands: firm that a Delay is a
feature of the flow and does not thread the flow wire; the
collect-vs-ancestor fork dissolves on sequences and is silent on
grids (the value-in-context model, worked with leanings, unadopted —
it reshapes uncollect language-wide; its owed everyday-`prev`
frequency check is since run, `real-loop-survey.md` survey 5); the
two candidates answer the register's two halves
(update cadence, provenance-fixed, vs read range, consumer-chosen —
this is `hold`); the pure-`final` corner is closed; and the sole hard
residue is a product's **linearization** — several running-view
consumers of one non-commutative register reading in different
orders, the recompute-vs-explicit-axis-reference trade. Effects
sharpen that residue from the other side (`effects-design.md`): a
spanning IO handle under a nested loop makes the linearization
*observable* and removes the commutative-monoid escape hatch. That
residue now carries a worked round of its own
(`product-linearization-design.md`, exploration, unadopted): the
trade dissolves with no new construct — order-freedom at consumers
is licensed by confluence and void at order-observing consumers
(register, context-read, spanning handle); the axis is the drawn
orientation Cross already stores, read as ordinary nesting; the one
cost is an **orientation-pinning demand** (authored to the observed
depth, discharged by commutativity); "one register read in two
orders" becomes unrepresentable, which the round argues is the
truth (two scans are two computations sharing one context-free
base). If its conversation adopts it, the collect-vs-ancestor fork
closes outright. The frequency check it owed is **run**
(`real-loop-survey.md`, survey 4 — thirty nested-loop sites in the
domains that stress the residue): the demand would fire on ~10–13%
of such sites; its everyday client is the spanning ordered emission
(the report-writer), the numeric non-commutative sweep the
rare-but-sharpest member; in every firing draw the orientation was
already authored in the source, and the commutative discharge has
field instances — so the demand's ergonomic cost, against that
sample, is writing down what those programs already wrote down. The
adoption conversation now has its evidence. The
per-kind "next iteration" question — formerly the row's most
concrete owed work, with several rounds writing checks on it — is
now **adopted** (2026-07-23 — `delay-ontology-design.md`, "Per-kind
\"next iteration\": the owned-order criterion"): a flow
supplies a "next iteration" exactly when its firings carry an
**owned total order** — stated by the constructs that minted or
shaped the flow, not merely present at run time — and the clients'
checks cash one for one (event stream and completions flow yes;
concurrent bodies, sibling instances, saturation members, unordered
facets no — one **order-demand check**, productivity's structural
complement; async value degenerate — cardinality, not async-ness;
the var's recomputation order incidental, so state lives on
`changes`; the IO handle a wire, not a flow). Extent-fixedness is
refined to a termination account only; the productivity check
becomes one check with a clock parameter; `hold` is identified
as the register whose step ignores `prev` — all three pieces
(criterion, order-demand check, `hold`) adopted; the
linearization residue and the value-in-context model explicitly
excluded from the adoption — the former's evidence now delivered
(survey 4), and the latter's everyday-`prev` check now delivered
too (`real-loop-survey.md`, survey 5, previous-value sites as the
unit: the register dominates carried state 17/30; raw-prev is
minority and mostly a companion read on register-carrying loops
— 2/30 primary, 8/30 in any role; the position-0 boundary is
always discharged by seed or construction, never tested per
firing; `hold` drew zero). Both model conversations now have
their evidence; neither is held. A 2026-08-12 working round rides
the ontology doc (**"The frame menu"**, exploration): the
owned-order table read as **offers** — a thread names a frame
*kind*, resolved against its anchors' provenance, with pins
mandatory exactly where resolution is ambiguous (the product being
the flagship ambiguous case); its least-tested piece is the
composition-along-provenance claim (a case layer gates, a product
layer fibers, a jagged nesting blocks), unchecked for
stream/async/incremental and the frame flow.

W = 5: ~23% of sampled loops carry state, dominant in numerics; the
register substrate has since landed in code (`src/ARCHITECTURE.md`,
registers and running views implemented). Prior art: jq's `foreach (init; update;
extract)` is the running view shipped (XQuery's lack of a scan clause
is the negative witness); Zig's `while` continue expression is the
register step pulled out of the body so `continue` can't skip it (C's
skip-the-increment bug is the negative witness); tidyverse supplies the
keyed collect's readout family (collapse / pass-through / flatMap /
whole-lane), the group-as-flows vs operator-merge fork, first-appearance
order, and the broadcast-back and keyed-index consumption patterns; APL
and BQN supply the identity catalog and the empty-collect framing. See
`flix-comparison.md`, `xquery-jq-comparison.md`, `apl-family-comparison.md`,
`zig-comparison.md`, `tidyverse-comparison.md`. Companions:
`iteration-with-state-design.md` (the Delay pair, "The Delay
back-edge"),
`iteration-rails-design-notes.md`.

**Variable-rate consumption and the running view of a collect —
I 3, W 4.**
Worked in `variable-rate-consumption-design.md`: "advance how far"
reframed as boundary placement via **split-when** (a segmenting binary
flow operation); the running view answered as the state port of the
collect's derived augment form; breadth items 1, 2, 4 worked
end-to-end; three dead ends recorded. The relationship question is
now **decided** (2026-07-23, in end-when's adopting conversation):
the **cut** ("when" — one construct yielding prefix, payload,
continuation) is the root concept; split-when is not a separate
primitive but the *iterated cut*, expected to live as a
derived/catalog construct over the root; and the
boundary-destination setting is three-valued at the root, on the
node, end-when's binary bit its projection. The cut round itself is
now **worked** (`variable-rate-consumption-design.md`, Part III,
exploration, unadopted): the cut is a two-flow-output node whose
payload rides the prefix's terminator (not a port); the
continuation on RanOut is an empty flow; a continuation-only
consumer reaches the payload by discharging the prefix it was
already forcing (the terminator-only discharge's second client);
the one-node split-when is total by construction while its
unrolling is a spine-shaped divide-flow link kept as a derived
view (with the spent-consultation clause reconciling the two under
starts-next — the round's one new finding); and the finite phase
chain claims Raku's *sequence* combinator. Remaining: that round's
adoption conversation; the running view
(reviewed 2026-07-23 and deliberately left tentative — the
semantics stand, but the drawing is the open problem: a port on
the collect node read as backwards); the stream compile's
sequencing constraint;
the fixed-length-segment catalog question; the nested-segmentation
boundary against grammar vocabulary; and the decision-driven merge
(the family's two-flow member) — now carrying a worked round of its
own (`chooser-family-design.md`, exploration, unadopted): the walk
over k cursors with per-step heads and a late-wired advance operand,
the chooser dissolved into ordinary drawn vocabulary — which also
answers this row's conjecture in the affirmative (interleaving is
drawn, not decided; no N-head chooser anywhere, surface or
lowering).

Prior art has sharpened (not moved) the remaining list. Raku's grammar
ladder gives four combinators over segments — repeat (owned by
split-when), sequence (phased consumption, unowned), alternate (typed
segments, unexamined), recurse (the divide flow's) — and states
question 3's fork: boundaries decidable per-firing are segmentation
vocabulary, boundaries negotiated by trial belong to the speculation
row. XQuery's window clause is split-when shipped as a W3C standard,
adding a new bit beside the destination setting (the unterminated
final segment: emit partial vs drop — XQuery's `only`, to decide
jointly) and gap-tolerant segmentation (windows need not partition;
framing's scan-for-sync is the field client). window(k) locates as the
fixed-size point of a tumbling/sliding × condition/count-bounded
family, whose shipped design space (step/movement, edge handling as a
real dimension, per-window reversal, 2D windows — 2D filing to
Products) comes from APL. The segmented-scan genre (grade-of-grade
flat encodings) is the strongest assembly-language exhibit yet for
split-when + register; tidyr's `cumsum`-key synthesis is a
fourth-ecosystem scan costume. Split-when now also carries the IO row's
within-firing round (`within-firing-effects-design.md`: the
conditional-flush buffer is a segmentation of the op flow) — a second
everyday client from outside this row's own cluster, a datum for the
adoption conversation. See `raku-grammars-comparison.md`,
`xquery-jq-comparison.md`, `apl-family-comparison.md`, `zig-comparison.md`,
`tidyverse-comparison.md`.

**The concurrency constructs — I 3, W 4.**
The area's rounds are landing but nothing is adopted. Worked: the race
barrier (`race-barrier-design.md` — its law and ties, the unary-race
leaning, failable subset merges, the dynamic-set redirect, the
cancellation hook, merge/interrupt/timeout as derived vocabulary;
fairness relocated to the chooser family); source openers and pacing
(`source-openers-design.md` — the self-driven opener as a bare
flow-minting node, the external pull source as a catalog block minting
a failable stream, pacing as a binary flow operation `paced` that puts
the retry composite's floor on paper); the concurrent collect
(`concurrent-collect-design.md` — the species menu fully dissolved:
serial = the nested drawing, keyed = the keyed partition instantiated,
unbounded = one primitive "settle" node minting the **completions
flow** in settlement order, its settled result a per-firing discharged
sum with no main-result port, a drain termination law, `bounded(n)`
split into a width expressible now and shared permits that are
bracket-shaped and fenced to Tier 1; six dead ends); and now the
served flow (`served-flow-design.md` — **one construct, two ends**:
the exchange pair whose client end is late-bound operations' `op`
pair and whose server end is a provider diagram, so "which one is the
server" is a property of a *binding*, the network an FFI client end
and the test harness another — servers testable as pure programs;
the exchange law port-structural (exactly-once = one wire into the
response half; exhaustiveness over exchanges; the responding collect
placeable on any 1–1-corresponding flow by provenance, making the
serial/overlapped/keyed seam free); the dual failure leg answered
(the response lane failable per-exchange, edge policy on the serving
block's catalog row — failure-out, cancel-in, admission); "served" is
*not* a flow kind (pair content, not kind content); the k-operation
provider is a **pre-split bundle** (no dispatch, because no union was
packed); the recursive provider is **the link in exchange costume**
(unmemoized = the divide flow's tree);
the keyed cache is a partition-plus-lane-register middleware that
turns the tree into a DAG, with cycle detection as a provenance
witness — left recursion's cousin; the server-program question
largely dissolved (a server is a provider; the standing run is a
binding; the node-set consequence's second client); five dead ends,
including exchange-as-two-messages, whose field witness is the
correlation ID as hand-rolled provenance).

Remaining: the served flow's two-ends core is now **adopted**
(2026-07-23, riding the joint adoption — one construct's two
ends); the rest of that round stays exploration; the chooser family — the
area's last unworked core — now carries its round
(`chooser-family-design.md`, exploration, unadopted): the
decision-driven merge as a walk over k cursors (heads + a late-wired
advance operand), the chooser dissolved into drawn vocabulary; the
async merge is the walk with a race in the decision position (the
catalog block stands), merge fairness is a register on the step flow
(no knob — race's dead end extended), and cross-client arbitration
(the served round's question 2) is the same merge drawn at a serving
boundary or the edge's ambient arrival order, never a hidden
provider property; pacing's per-consumer/per-source bit
under multi-close (joint with end-when's coexistence question); and
the served round's own residue (the serving blocks' catalog rows,
cacheability's witness property, when-does-a-server-end — each filed
to a named owner). Demanded by three of the five tough
use cases; the event-loop breadth item (7) is the area's acceptance
test in miniature.

Evidence (`real-loop-survey.md`, survey 3 — thirty orchestration
sites): first-of coordination (race/timeout/interrupt) outweighs
all-of nine-to-one, and every hand-rolled race reconstructs the winner
from side flags, so the race barrier led the area;
`bounded(n)`-as-resource and serial-as-default are field-confirmed.
Prior art: RxJS's four flattening strategies are the shipped
concurrency menu (switchMap = interrupt-race, concatMap = serial,
mergeMap(+max) = bounded/unbounded, exhaustMap = drop-newest-while-busy
— a species the menu lacked, filed to the source-boundary buffer/
latest/drop family); React Query is served-flow furniture; Zig's
`io.async`-may-run-synchronously vs `io.concurrent`-fails-as-a-resource
distinction and its select-union note (a tagged union crossing the
race is the sum bottleneck the barrier form dissolves) sharpen the
concurrent collect and race rounds. See `race-barrier-design.md`,
`source-openers-design.md`, `concurrent-collect-design.md`,
`served-flow-design.md`, `translation-exercise.md`,
`effekt-comparison.md`, `flix-comparison.md`,
`xquery-jq-comparison.md`, `reactive-comparison.md`, `zig-comparison.md`.

**Checking: the deferred design rounds — I 3, W 4.**
The stance is settled (demands/offers, no search, drawable witnesses —
`types-design.md`; paths and clash flavors —
`bundle-provenance-design.md`); implementation is workstream D. The
design-side gaps: recursive shapes (question 2, waiting on the tree
constructs — now unblocked, the divide flow and the zipper seam being
decided), slots/higher-order signatures (question 3), and equality's
fine print (question 8). The catalog schema and its trusted JS edge
(question 4) now carries a worked round of its own
(`catalog-schema-design.md`, exploration, unadopted): **the catalog
is one registry of referent-identified entries, not several
tables** — entry/block/row are three grains of one thing; facts sit
in open-ended families (ports, laws, lanes, translations, measures,
expansions), each family earned by a construct that filed it; trust
is graded per fact (definitional vs asserted, every asserted fact
carrying a stated direction of doubt and a displayable witness);
rows are demanded by the same propagation as wire properties (an
operator position is a meta-level port — no second checker); an
admission rule keeps the catalog use-independent (per-use truth is
drawn at the use, never registered — survey 4.3's operator-swap
finding is the field evidence); unregistered JS is the lawful
**empty entry** (silently unchecked, kept safe by the background
super flow, refined monotonically by opt-in registration); and the
**trust manifest** — the asserted facts a given output's validity
rests on — is a derived view, sharpening "soundness relative to the
catalog" from a global caveat into a per-program question. Six dead
ends recorded (name-keyed catalog; per-family separate catalogs;
mandatory registration; facts on instances; the proving checker;
the silently imported interface). The round consumed the filed
demands: the collect family's identity rows with value witnesses
(adopted content, given its schema), the tag-identity round's
lane-references-not-strings (unadopted — the dependency is stated),
the Life round's extent/shape-preservation row, the divide flow's
measure catalog (that client since retired, 2026-08-12 — no
measure family remains to admit), the cancellation and served rounds' edge
translations (slots supplied; fine print stays with its owners),
and the within-firing round's coalescing law. I stays 3: questions
2 and 3 remain undesigned and question 4's round is unadopted.
Prior art: Flix's restrictable variants are
the strongest prior art for question 2 (recursive case-set properties
trackable and paying for themselves; their own illegible-at-scale type
algebra supports the drawable-witnesses stance over imported Boolean
indices); "this hole demands a pure filler" is added as demands/offers
vocabulary; `@Terminates` is prior art for declared, checked
termination. See `flix-comparison.md`, `catalog-schema-design.md`.

**Functions, reuse, and facets — I 3, W 4.**
The row's center — the demand the record could previously not answer
at all — is now **adopted**: **late-bound operations and the test double**
(`late-bound-operations-design.md`, 2026-07-23, in the joint
adoption). An unbound
operation is a request/response port pair on the diagram boundary,
and binding a meaning is wiring a provider onto it at a boundary; the
round is a unification of three worked pieces rather than a new
mechanism. Its two load-bearing results: **the pair is the client end
of a served flow** (a provider is the server end — exactly-once is
the collect's existing law, provider concurrency is the collect
species on the provider's side, and the build-system demands stay
filed on the served flow's round), and **orderedness and provider
state are the same bit** (a facet's handle is the ordering
commitment; a provider may hold cross-exchange state exactly when
the facet is sequenced, and unordered facets get an
exchange-stateless structural check of the registers-under-
concurrent-collect species). The test double is a small ordinary
program (the from-list lexer double = `serve` + a register); the
**policy layer** lands with it as middleware-as-splice — a diagram
offering the facet upward and demanding it downward, stack order
drawn as nesting (handler-land's invisible stack-order hazard
dissolved); fault injection is a configured double
(`FailingAllocator` = value port + exchange-counting register);
demand propagation through nested calls is the placeholder story's
residual demand, with the Zig-style threading noise absorbed by
completion (derived, faint, excludable). Five dead ends recorded
(dynamic scope; provider-as-value-on-a-wire; the tagged-request
single pair as the sum bottleneck; binding by structural match as
search; the bare value hole). Retry middleware inherits the pacing
block; reverse-mode AD is fenced out honestly
(continuation-as-tape is not a provider — if wanted, it is a
transformation-levels derived view).

The row's other center — **the function boundary itself** — is now
**adopted** too (`function-boundary-design.md`, 2026-07-23, the round
three clients jointly demanded): a function is a **remembered cut**
through the wiring, not a container — its ports are the wires the
cut crosses (read off the drawing at extraction, never declared;
the argument list is rejected as the product bottleneck's oldest
costume), membership is *derived* (a node is per-call iff
downstream of an in-port — P3 one level up, the divide flow's rule
shared verbatim), everything else the cone reads is prefix-shared
(closure capture dissolves; call-invariant work is shared by
meaning, not optimisation — what the Lit memoisation already does),
and reusability is a derived check with a drawable witness (the
offending per-context wire surfaces as a demanded port). Its two
load-bearing moves, as adopted: the call and the divide flow's
link sharing one substrate while staying two constructs
(recursion never routes through a named function; the round's
first design conversation settled this against its own first
draft: the guard family's register symmetry, naming as a toll on
recursion, and the extract-to-recurse cliff) — **since revised
(2026-08-12): the link left the substrate entirely** (it is the
site, on the port-pair substrate — `divide-flow-design.md`,
revision notes), level labels dissolved, and the measure
discipline retired ("every cycle crosses a guard" survives as two
guards of three — register productivity and dedup convergence);
and
**the slot dissolves into the op pair** (SlotSignature = facet,
SlotInvocation = exchange, slotImplementations = binding — so the
conditional-signature design, checking question 3, is owed once
instead of twice). The interface needed nothing new: signature =
boundary projection, flow skeleton = read-out 2's summary at a
display-time collapse level, ordering residue and open op pairs
project as ports — and with the link interior to the cone,
**recursiveness is an implementation detail** a caller cannot see.
Function, provider, and the top-level program share the one
substrate under three bindings (the level binding removed
2026-08-12) — the node-set consequence completed. The same conversation added the **use-case account**
(functions exist for reuse only: per-element work is flows,
callbacks are served flows, behavior parameters are op pairs,
organization is display-time collapse — a function is the honest
form exactly where a manufactured shared flow would be a lie) and
**partial cuts** (uncut wires are free wires: the prefix rule
derives a local function's validity region, local → global is
additive wire-cutting, state cadence is visible in which flow a
register binds, and linear values force port-ification — the one
real ownership bite, resolved by the existing fan-out ban). Six
dead ends recorded (the scope/container; the call/link construct
merge — settled by the conversation; the slot species; the
obligatory declared signature; first-class functions restated; the
argument list).

The joint adoption is **done** (2026-07-23): the cut ontology, the
call/link substrate with no-named-recursion, the use-case account,
partial cuts, and no first-class functions — under the
anchor-is-identity constraint, and with a provisional-confidence
marker on the slot-dissolves-into-op-pair piece (adopted as the
working position without the conversation fully engaging it; a
later look may reopen that piece alone). Still open on the row's
center: the cut's edit gestures (editing round); boundary
identity across versions (transformation-levels;
`time-travel-programs-design.md` question 5 rides along); the
conditional signature (checking question 3, unblocked not
advanced); the uncut-read lint threshold (level labels and the
termination-on-interface question both closed 2026-08-12 — labels
dissolved, no termination checking); the
spec-side reconciliation of the Diagram record; and
the function-unit sample (below, Evidence owed). The late-bound
round's own residue: the spellings (`op`, `serve`,
binding, splice), owed with the textual catch-up (the level-boundary
demand was withdrawn by the divide round's "no boundary at all"
refinement; the boundary substrate is adopted for its surviving
clients); region-scoped rebinding (the cut
vocabulary suggests a shape — a region is an anonymous interior
cut — but the facet-ordering interaction stays unworked); the
serving provider's multi-lane
form — now worked (`served-flow-design.md`: the pre-split bundle —
one serving context in handle order, k static lanes, registers on
the parent flow, no dispatch because no union was packed);
default-override scope against completion's pick-late rule. And the
rest of the remaining list, untouched: **extensible alternation**
(Raku's proto regexes; the complete alternative set must stay
viewable somewhere, a facets-flavored derived view); **the decorated
tree** — one tree, stacked per-node decorations, consumers demanding
only what they read; the **authoring gesture** — dplyr's `across` is
k-fold repetition of drawn structure, one gesture producing k
readable nodes; and facets' attachment representation
(`facets-design-notes.md` open edge 3).

Facets now have a recorded statement of intent (`facets-design-notes.md`):
authorable, attachable abstractions (the struct → interface → facet
ladder; algebras and state machines as code facets; a shared facet
between production and test code is what makes the test double
informative), holes without breaking, negative constraints with their
stated direction of doubt, and the explicit bound that facets are views
for a human, not verification. Their first in-record client is the
collect family, which consumes the algebra facet as the authoring
surface for user monoids (with the joint constraint that the facet
carry a value witness — the identity — not just a named law). A
**tractable core** was noted at the 2026-07-23 walkthrough
(`facets-design-notes.md`, "Facets as view toggles"): pure
derived-view toggles over the one representation — wire-species
visibility, layout-constraint sets (the IO rail's join column),
interpretation switches (handle/flow synonym), sequencing wires
with toggleable algebraic layout constraints — implementable
without solving attachment, a substrate the authored-facet ladder
can later build on.

W = 4 (raised from 3) with a condition: three curated corpora
converging (Effekt, Flix, Zig) argue 5, but per the standing method
that move should come from the owed application-level sample — does
real application code swap providers? Prior art: Effekt's test double
as standard-library furniture and provider stacks at the edge; BQN's
arrays-of-functions residue, declined (the round's brief is that the
uncollect's virtual value does the work of every operand slot without a
function being passed); React Query and Zig allocator wrappers
(arena, leak-checking, logging) as policy-layer furniture; Zig's
Allocator/Io as ordinary parameters — the flattest late-bound
mechanism, supporting the provider-on-a-port leaning over any
dynamic-scope reading — and `FailingAllocator` as fault-injection-as-
configuration on the test double. The four witnesses' mechanisms are
now consumed by the round (each capability kept, each mechanism
clash-recorded). See `late-bound-operations-design.md`,
`effekt-comparison.md`, `facets-design-notes.md`,
`raku-grammars-comparison.md`, `flix-comparison.md`,
`apl-family-comparison.md`, `reactive-comparison.md`,
`zig-comparison.md`, `tidyverse-comparison.md`,
`collect-family-design.md`.

**Products: the table, zip, and the unexamined interactions —
I 3, W 4.**
Cross itself is worked (`product-flows-design.md`); n-ary products are
now worked too, against a concrete three-list example (question 3:
flat axis sets confirmed as the denotation, the poset as the subset
lattice of constructed axis sets, the point-indexed table and the three
theorems generalising verbatim — the three-list example is where the
poset's partiality and the S₃ orbit of orientations first become
visible, both caught by existing machinery). **Registers over products
are now worked too** (question 5): a register folds *along the axis its
binding collect gathers*, fibered over the rest (the APL reduce-along-an-axis
shape), not over the whole order-free cube — `final` drops the reduced axis,
the running view keeps full shape, productivity transfers verbatim, a full
cube reduction is the S₃ axis-permutation with a register hat, and a
commutative monoid discharges the order demand entirely (a reduce-close over
a whole product is order-free iff its operator commutes — the A/B confluence
at the register level). The linearized whole-cube fold is a *different*
program (Join then an ordinary register), keeping question 5 clear of
question 4. The round's real lesson was about **Delay**, not the product:
*which flow* fixes the register's axis is an open ontological question, and
the product carries its sharpest evidence (the shared-grid implementation
breaks under a consumer-dependent axis) — feeding the loop-carried-state
row's new Delay-ontology open problem. **Join on a product is now
worked too** (question 4 — `product-flows-design.md`, "Join on a
product", exploration): the operand-walk rules extend over the
context poset with no new witness species — a join chain consumes a
product segment axis-by-axis, each consumption a drawn orientation
commitment graded to the depth the chain reaches (`join(E, axis)`
lawful as drawn, the surviving axes staying a product with their
original exterior), making the join chain the third
orientation-authoring surface beside the collect chain and the
drawn commute — consistent with the linearization round's pinning
demand without depending on it; the n-ary flatten node, the
orientation-free flatten, and the pair-as-one-flow operand recorded
as dead ends. Unexamined: the
provenance product segment against the walk-and-classify algorithm
(question 8 — which now has the join round's product-segment
transition rules as input). Spec entry and textual spelling are
owed bookkeeping.

The **aligned product (zip)** is now worked (`product-flows-design.md`,
"The aligned product (zip)"): Cross's positional sibling — same extent
paired by position vs independent extents paired exhaustively — as a
flow-only barrier whose output is *one widened flow* (not nesting) and
whose demand is co-extent. The central result is the asymmetry with
Cross: Cross's independence is always structurally checkable, but zip's
co-extent is structural only under **shared provenance** (both lanes
downstream of one uncollect by extent-preserving ops — then zip is free,
a re-bundle of wires that already fire together, and k sibling collects
are aligned by this rule), and otherwise a **runtime precondition
asserted at the barrier** with a failure witness — the pole Zig ships as
`for`'s length-equality assertion and APL as a conformance error. The
**value form** landed with it: the multi-wire collect whose product is a
table (k lists that remember they were collected from the same walk) and
whose uncollect returns the aligned wires; the row-splat wart, dplyr's
retreat from purrr's map-arity matrix to `rowwise`, and join suffix
collisions confirmed the open form is wires, not row-structs. Scalar
extension separated cleanly as Incorporate's implicit costume (a clash
note, not zip); indices are a counted source-opener lane borrowing a
sibling's extent (answering translation-exercise finding 10). W = 4
(raised from 3): the data frame is the multi-wire flow **at rest** — k
columns = k value wires, n rows = n firings, alignment retained from
common provenance; the row owns tabular data as a domain, not just
lockstep pairing as an operation. Residue filed to owners: the co-extent
assertion's exact property/precondition form; the table's at-rest and
textual spelling; **rank-2 zip's axis handling — the Conway's Life
struggle — now worked** (`product-flows-design.md`, "The Life residue,
worked", exploration: the overlay is the flow-arity zip, i.e. the
transposing commute under a co-extent license — constructed / proved /
asserted as the license's three suppliers — and the axis-handling
question dissolves, alignment being positional at every level; what
remains is the shape-preservation catalog row, filed to the checking
row's question 4, and the transpose gate-widening edge, filed to the
commute taxonomy); and per-edge alignment (`reduce2`'s length-(n−1)
second input) to the register round. Of the row's formerly unexamined
interactions (questions 4, 5, 8), the first two are now worked — join
on a product and registers over products, both exploration — leaving
the provenance product segment against walk-and-classify (question 8)
plus tidyr's observed-product vs full-product
distinction (`nesting()` inside `expand`) as the row's open core;
I stays 3 (the worked rounds are unadopted and question 8 is
representational groundwork the checks need). Honesty: a curated corpus; the owed field sample (real
analysis scripts) should still confirm the scope move. See
`apl-family-comparison.md`, `zig-comparison.md`,
`tidyverse-comparison.md`, `product-flows-design.md`.

## Tier 3 — worked areas with named residue (≈ 9–10)

**End-when: residue after adoption — I 2, W 5.**
**Adopted** (2026-07-23), **revised (2026-08-04 —
`end-when-design.md`, revision notes): fused with its collect into
collect-until.** No first-class shortened-flow wire; terminators
carry only the *reason* a flow ended, never data; payloads travel
value wires as (flow, value) pairs on the node; either pair
omissible; the bit survives as a pure extent setting, untangled
from payload carriage. The fusion line is recorded (a cut
projection fuses exactly when it mints no new flow — split-when
keeps its outer flow; see the variable-rate row). The register
final-readout anchor question is **resolved in the scoop
vocabulary** (the final is a scoop at the closer you wire; the
worked anchor-rule candidate is superseded). Remaining: the textual
spelling — now larger, owed jointly (collect-until's inline pairs
vs labeled lanes, the word-pair bit spelling, the discharge
readout); the bit's drawing (layout-side, out of scope);
interrupt unification deliberately unforced; the continuation
seam rides the cut round with the collect-until binding expected
(`variable-rate-consumption-design.md`). I stays 2 (the fused
construct is settled design, spellings and the continuation seam
open); W = 5 stands.

Evidence and prior art: the stop/discharge/split-on-tag composition
survived contact with the textual form and reads well
(`translation-exercise.md`), with strawman spellings ready for the
adoption conversation; Effekt's `while … else` and labeled break draw
the same readout distinctions; a W3C windowing use case ends a window
on a three-reason disjunction and re-tests which reason fired — the
side-flags idiom in a standards document (jq's `limit` aborts via a
lexical label; XQuery has no end-when, so termination is the
optimizer's mercy); XState final states with `output` are the
terminator-with-payload discharge; every Zig loop is an expression
whose `break v`/`else d` pair is the discharge's Stopped/RanOut split
lane-for-lane (a `while` over an error union gives `else` the error
payload); purrr's `done(out)`/`done()` is end-when's value form
composed with loop-carried state, its arity a datum for the
inclusive/exclusive bit and the register's final-readout anchor at
once. See `end-when-design.md`, `translation-exercise.md`,
`effekt-comparison.md`, `xquery-jq-comparison.md`, `reactive-comparison.md`,
`zig-comparison.md`, `tidyverse-comparison.md`.

**Completion's contents — I 3, W 3.**
The time-travel machinery is settled; its *contents* are thin by design
— one canonical-table entry, one heuristic — and each addition needs a
worked program behind it. Versioning (a heuristic change is a semantics
change) and completion-diff UX are the sharp residue
(`time-travel-programs-design.md` questions 1–3).

**Transformation-levels: the undesigned operations — I 3, W 3.**
Cherry-pick replay, merge, and the content of an undo step are each
explicitly "undesigned"; the single-native-level assumption is
unfalsified but unproven — named there as the property to verify before
relying on the tower (`transformation-levels-design.md`, "What is
unresolved"). Principle 6 rests on this doc, so the residue is quiet
but real.

**Streams: runtime residue and deferred passes — I 3, W 3.**
Shape C is the committed baseline; the consumer-set lattice is
deferred-but-committed — a *deferred optimisation, not a rejection*
(`lazy-stream-placement-design.md`, status header — a misread-prone
status). Design-side residue: result-commute and the marker/IO commute
variants await their own runtime designs (`lazy-stream-commute-design.md`
question 2 and taxonomy), and the two `Delayed` footguns (pull
amplification, retention across a forced run) are named constraints on
any implementation.

**Incremental flows: the boundary and the collections layer —
I 3, W 3.**
The update-model destination is recorded (push-with-values inside a
necessity frontier; **pure pull rejected long-term**, a first-impl
convenience only). Open: cutoff semantics, `changes`'s stream kind
(ties to async's event-source retention question), `set`-as-effect, and
incremental collections — a large, separately-designed layer
(`incremental-flow-design.md` questions 2–6).

Evidence round (`reactive-comparison.md`): the core is confirmed point
for point by the TC39 Signals proposal (laziness, memoization,
cutoff-with-`equals`, dynamic dependencies = switch-join, pull-model
glitch-freedom); Elm removed reactive variables entirely (its
register-centered replacement is drawable). The necessity frontier is
the genre's shipped shape — watched/unwatched lifecycle hooks, computed
suspension, refCount, inactive-query GC (registration events at the
frontier's edge, as the pending-pull derivation predicted); the
interior algorithm everywhere is dirty/check/clean two-grade staleness,
an intermediate between the rejected value-free dirty bit and
push-with-values, adequate at UI scale. Liveness and memory are one
frontier (watched-holds-alive; the ecosystem's undisposed-observer
leaks are what no-bare-read prevents). Collections gains its shipped
shapes: keyed var families minted on demand, per-key subscriptions,
hierarchical keys with prefix invalidation (provenance's prefix rule in
runtime clothes), update deltas as data, and the identity-vs-position
fork.

**Saturation: closure under rules — I 3, W 3.**
Compute the closure of a seed set under derivation rules until nothing
new appears — graph reachability/cycles/ordering, dependency
resolution, dataflow and program analysis. Now worked in
`saturation-design.md`: the load-bearing result is that **saturation is
the register's dual one level up** — a back-edge on a *flow* wire
crossing a *set collect re-opened*, where the register is a back-edge on
a *value* wire crossing a Delay. The dedup collect does double duty
(monotonicity + convergence), and "the set stopped growing" is the
flow-level analogue of productivity. One round of rules is already
drawable (two uncollects over fact sets, the shared variable as a
Cross-plus-equality-filter equijoin, a set-collect target); **naive vs
semi-naive** (whole-set vs frontier/delta) are lowerings, not two
constructs (decide in code), which keeps the worklist in
assembly-language territory. The **lattice-merge variant** is the keyed
collect by ⊕ under the same feedback (shortest-distance =
keyed-min-collect + back-edge, its algebraic footing in
`collect-family-design.md`); the whole-set register (`f⍣≡`) is the
degenerate scalar-fixpoint neighbour, kept distinct because it carries
no members (no semi-naive, no provenance). Four dead ends recorded.
The shape's first random-draw sightings have since landed
(`real-loop-survey.md`, survey 4, finding 4.6): two hand-rolled
costumes in thirty nested-loop sites — a worklist-with-seen-set
module walk and resolve-until-no-progress passes — both in
general-purpose library code, at a sampling unit where worklists can
appear; "absent from all random surveys" should no longer be cited
bare, though the owed domain sample below stands.

Remaining: the adoption conversation; **termination is not structural**
(Datalog's finiteness/bounded-height condition — the dedup-collect
discipline is necessary, not sufficient; leaning is nothing static,
divergence flagged); **provenance/explanation as a derived view** (a
highlighted sub-DAG of the deriving firings — the most novel residue, a
leaning only); **stratified negation** as a fixed nesting of saturations
under no-time-travel (sketched); and the **served-flow duality** —
now with its first joint working (`served-flow-design.md`: the memo
table and the seen-set are one construct, a keyed collect, written by
opposite drivers; which construct a program draws is which end names
the extent — the goal's cone vs the closure, different drawn programs,
not lowerings of one another; magic sets located as a recognition
between the two drawings; provenance's explanation sub-DAG and the
provider's demand cone identified as one derived view). W = 3 as a
breadth obligation: absent from all three random surveys, everyday
clients domain-concentrated (package/build/import tooling, analysis,
graph features); the frequency question stays on the evidence-owed list.
See `saturation-design.md`, `flix-comparison.md`,
`collect-family-design.md`, `effekt-comparison.md`.

**Recursion: the divide flow, the site, and trees — I 2, W 3.**
Recursion over virtual structure is **adopted**
(`divide-flow-design.md`, 2026-07-23, in the joint adoption with
the function-boundary round) and was **revised through a 2026-08-12
conversation series** — the doc's revision notes govern. Write one
level concretely (an ordinary case split; a leaf is an alt with no
links, dissolving the base-case construct), then link the
sub-problem wires back — and the link's spelling has **landed as
the site**: an out-port/in-port pair joined by the abstract wire
(the late-bound round's own annotation — one object, not a sibling
glyph), its threads anchored at the page's fed and read wires
(*feed the child where you are fed, read it where you are read* —
any other placement is an observably different program), with the
**hypothetical** as the primary ontology ("what would y be if x
were v?") and a substitution law for nested frames (child = the
minting frame plus a substitution at the fed anchors, sites
opaque; two coherence witnesses). Mutual recursion is **re-founded
by inlining** — within a strongly connected reference group only
the back edges are sites; level labels dissolve; the reuse residue
is two remembered cuts over one node set. The
**termination/measure discipline is retired** (no termination or
soundness checking — the three-species ladder, the joint measure,
and the left-recursion diagnostics are deleted, recorded so they
aren't re-derived). The **cyclic back-edge surface is rejected**
(clockless latch; crossing-placement observability; branching
collision), tail-shaped programs landing in the existing iteration
vocabulary — the taxonomy is three species, one form each
(iteration / structural walk / pure recursion). Earlier results
stand: per-instance membership derived from dataflow, multi-wire
problems crossing pairwise, the construct honestly primitive (the
stack encoding inadmissible), recursive descent and the quadtree
worked, sibling instances without time, the dead ends recorded.

Remaining, in rough order of bite: the **frame flow** (exploration,
unadopted — `divide-flow-design.md`, "The frame flow"): the call
tree as a tappable flow — thread-named, rooted at the current
frame, firings = askings (the double-count argument), unowned
order — making whole-tree aggregation an ordinary collect; its
**wound** (tree-structured) form converges with the trees row's
zipper walk (one tree-walking vocabulary, two doors — data tree
and call tree), which reframes the zipper seam once more and is
where a trees-row rework would now start; the **frame source**
question is answered by dissolution (frames are hypothetical
assignments indexed by the tree of askings; the site extends
indices) with the tap's form the residue; the **frame menu**
ripple (which frame a thread accesses — worked in
`delay-ontology-design.md`; see the loop-carried-state row); the
textual glyphs for the site, its threads, and the frame-flow tap
(the catch-up row); and whole-tree linearization (rides the
delay-ontology/product residue, unchanged). The **zipper seam**'s
2026-07-23 decision stands (verifier retired, computed-value
zipper ports re-read as drawn crossings, the compact form a
derived view). W = 3 as a breadth obligation: the three random
surveys produced one recursive draw (breadth item 9, survey 2 —
transcribed in the round), but parsing supplies everyday demand
from outside the sampled domains, and parsers/planners/tree
algorithms are rare-but-breaking; the frequency question folds
into the saturation row's owed domain sample. See
`divide-flow-design.md` (revision notes first),
`trees-and-recursion.md`, `tough-use-cases-design.md`,
`raku-grammars-comparison.md`, `flix-comparison.md`.

**How values cross a barrier — I 2, W 4.**
Worked (`barrier-value-crossing-design.md`), now partly **adopted**
(2026-07-23): the two mechanisms — availability (provenance over the
barrier's flow law; no pass-through value ports anywhere) and minted
ports — the co-location criterion, and corner 1 (Join and the
concurrent join flow-only) are adopted, with a recorded
clarification: a value wire does not participate in a flow
operation — neither upstream nor downstream of it; the ordering is
on contexts only. Corner 2 (race) is adopted with an amendment
(2026-07-23): inputs are per-contender **(flow, payload) pairs** —
the pair the lean on the stated principle that a barrier is a
control-flow operation and its control flow should be a visible
wire; the bare async value admissible as the completed-open
aggregate; race re-read as the partial collect's async sibling;
the unary-race leaning reshaped (await = open async). Corner 3 is
adopted too (same conversation): m rows = m sibling partial
collects, backed by the context-equality theorem (cell sets
computed by walking — merges mint no worlds, openers do), the
multi-row node staying a dead end that survives as a drawn view;
a naming constraint recorded — the partial collect's surfaced
name should not contain "collect" (it stays in flow-land). And
corner 4 is resolved in an amended direction (same conversation):
governed by the stated **one-closer principle** — when a loop's
result has one consumer, one construct closes the loop flow — the
discharging collect stays the single closer but its discharge half
mints outcome cells directly (no packed `term` value; the cell
set checked against the derived inventory, so the anti-swallowing
result is node-local and exhaustiveness is 3c's adopted check);
the `(prefix, term)` pair is demoted to the packed interim
spelling. **Every corner is now decided**; what remains of this
row is the spec-side reconciliation, the concurrent join × Cross
question, and the discharge round's owed details (authored ending
wires vs derived witnesses; the bare-end cell; spellings). **Corner 4 (the discharge's port shape)
is contested** by the discharge-barrier direction
(`failure-payloads-design.md`): fail-as-uncollect gives every
failure an independent upstream wire, weakening the settled-sum
justification — do not ratify as written. Five dead ends recorded.
Remaining besides the corners: the spec-side reconciliation (its
Join's value ports re-read as drawn availability) and the
concurrent join × Cross unification question it strengthened.

**Failability's residue — I 2, W 4** (raised to 3 by the
2026-08-04 revision; back to 2 with the alt-reach round worked,
2026-08-14).
**Revised (2026-08-04 — `failure-payloads-design.md`, revision
notes): the fail node is dissolved** — failure is a case alt, the
short-circuit is the inferred commute (first-B the published
default), short-circuit vs accumulate is carried by where the
alt's collect sits — **and propagate-by-default failable values
are rejected**: terminators carry only the reason a flow ended;
payloads travel drawn value wires (the scoop); the background
super flow survives unchanged. New work this creates, which is why
I rises: `async-flow-design.md`'s failability sections,
`speculation-design.md`'s failable substrate,
`cancellation-design.md`'s `Cancelled` payload, and
`catalog-schema-design.md`'s throw rows (now directed at case
bundles, not terminator lanes) all carry "needs updating" notes
(update 2026-08-14: the first two are done — both docs re-founded
on the revised account, with rejection re-located as an *arrival*
carrying an Ok/Err case bundle and the speculation barrier's
inputs as per-contender pairs; the alt-reach re-founding is now
worked too, next);
the inventory account re-founds as alt-reach property propagation
— now worked (`failure-payloads-design.md`, "The inventory
re-founded as alt-reach", 2026-08-14, unadopted: reasons and
failure data split into two derived questions; the failure side
is the existing case-alt property propagated by existing rules,
read off the completed form; no failure-specific checker channel;
the tag-identity referent rule transfers with lanes dissolving
into alts; the catalog demand re-filed as bundle rows carrying
alt referents); the error arm's prefix question is deliberately
pinned. I drops back to 2: the revision's design debt is worked,
with the round's adoption conversation and the catalog schema's
own re-founding the named remainder. The paragraphs below predate
the revision and stand as the record of the
adopted-then-dissolved shape:

The core is worked (terminator payloads, propagate-by-default,
discharge at a whole-flow collect — `async-flow-design.md`), and the
two flagged residues now carry a worked round of their own
(`failure-payloads-design.md`, now mixed: the **fail node itself is
adopted** — 2026-07-23, with its ontology note (fail is the minting
half of the applicative sequence; the accompanying
commute-completion ruling is general — an implied commute is time
travel and must be inferred *and viewable*, never merely absent) —
and the **edge stance is adopted with an amendment** (same
conversation): bodies total, declared throws as catalog-row lanes,
and undeclared throws landing on the **background super flow** — a
runtime-owned lane that silently commutes out of everything, joins
with itself, stays out of every drawn inventory, and is collectable
where wanted (a collect compiles to try/catch; the supervisor
boundary made drawable; anchor/async-face/naming edges filed in the
doc) — and the **inventory account is adopted too** (same
conversation), so the whole round is now adopted design;
moved down from Tier 2 by
this index's maintenance rule). **Failure is drawn, not thrown**:
bodies never raise ambiently — the raise is `fail`, the
terminator-writing family's third member (one wiring, three
consumers: join keeps an alt's firings, end-when stops before them,
fail aborts at them; exclusive always, no bit; the once-context
degenerate fills the now-column result-as-flow row), with the JS edge
converting *declared* throws by catalog row and undeclared throws
staying edge breaches — so failability is derived and readable (a
flow is failable iff its inventory is nonempty), never annotated.
And **payload composition is neither unification nor mapping**: a
terminator lane is a set of drawn minting sites grouped by tag; the
inventory at any consumer derives by the same monotone propagation as
every other property (union along stacks, nesting, and chained
closes; discharge exhaustiveness = alt matching over the derived
inventory; every lane carries a minting-site witness; the fixpoint is
finite even over recursion), and re-tagging is drawn only where
meaning changes (discharge, transform, re-fail). The round cashes the
checks other rows wrote on it: `Cancelled` carries no payload
(nothing in hand at delivery — the cancellation lean confirmed
structurally); the subset-merge payload stays the bare fact (a
winner's value belongs to the winner's lane); speculation's aggregate
is ordinary data construction over already-discharged payloads; the
divide-flow link's declared sets survive as boundary summaries with
the well-foundedness worry dissolved (Zig's recursion warning is
type-level genericity and does not transfer); the served flow's
response lane and the fault-injecting double are consumed as failable
catalog rows. Five dead ends recorded (ambient bodies-raise; nominal
sets with coercion; mandatory declared sets; the dynamic catch-all as
the model; cause-chain wrapping).

Residue after adoption: tag identity across reuse boundaries —
now carrying its worked round (`failure-payloads-design.md`, "Tag
identity across reuse boundaries", unadopted): the **referent
rule** — a lane's identity is a drawn identification of minting
sites, never a string — with sharing drawn in one of three homes
(a caller-local identification, the facet's lane for providers
and doubles, a catalog-level lane reference), the instance
question answered by the boundary round's per-call quotient, and
the fragility asymmetry restated (a tag outlives any one site;
that is what signatures pin). It files the catalog-schema demand
the question predicted (rows carry lane references, not strings —
question 4) and leaves adoption, the facet-lane shape, and the
qualified spelling open; the **discharge-barrier direction** (noted same day,
details owed: fail as an uncollect of an error flow, the error
wires as drawn arrows to failure points, term-then-split as the
packed sibling, a barrier minting per-site cells plus a completed
cell whose success payload is answered by availability/mint per
kind — contests the crossing round's corner 4); the super flow's
filed edges (collect anchor, async
face, `Cancelled` siblinghood, naming); interrupt's adoption
paperwork (rides the async round; its verdict vocabulary is fixed
by its two adopted siblings); the advisory tier's contents; the
option/async convergence, sharpened
again (an option is the `{Nil}` inventory) but undecided; the
spellings, owed to the textual round jointly with end-when's.
End-when's readout composition leans entirely on discharge, and
end-when is now adopted (2026-07-23), so the family pressure is
live: the everyday member is settled while `fail` and the
inventory account await their conversation.

Prior art, now consumed by the round rather than pending: Zig's `try`
(propagate-by-default at one keyword) and its error-set algebra
(union at merges, subset coercion, inference by default with a named
escape) are re-derived as property propagation rather than type
algebra; Java's checked exceptions and the dynamic `catch (e)` are
the two negative poles the derived-with-optional-pinning posture
sits between. See `failure-payloads-design.md`, `zig-comparison.md`,
`async-flow-design.md`, `translation-exercise.md` (findings B2/C2).

**Speculation: ordered alternatives with rollback — I 3, W 3.**
Try alternatives in drawn order; an attempt can fail; the world is
restored between attempts. Now worked in `speculation-design.md`: the
sum-side barrier that is race's *sequential* sibling (winner by
success-in-drawn-order, not settlement-in-time), with the load-bearing
result that **restoration is not an operation** — it is an emergent
property of immutable values + ordinary sharing + ordered fallback, so
the shared input wire fanning into the contenders *is* the save/restore
pairing breadth item 6 wanted visible. Contenders are failable by
construction; a soft-fail is discharged into "try the next," and the
whole barrier decomposes into a right-nested chain of discharges over
failability. Commitment is worked as the two terminator lanes (soft →
try next, hard → propagate) with a `commit` marker upgrading soft to
hard (Raku's tilde/FAILGOAL); diagnosis is a terminator payload;
concatenation falls out as ordinary position-threading chaining;
recursion is deferred to the divide flow. The +1 ladder (first-success
→ all-results → bounded → heuristic order) holds, heuristic order
bridging to the chooser family. Five dead ends recorded (backtracking
substrate everywhere; rollback-by-allocation-position; continuation/
`alt` as a value; conflating with best-match `|`; `//`'s empty/falsy
conflation).

Remaining: the adoption conversation; primitive-barrier-vs-catalog-block
(shared with race); commit's exact form and its nesting behavior;
diagnosis payload composition (joint with failability's residue and
end-when's discharge — the failability side is now worked,
`failure-payloads-design.md`: the aggregate is ordinary data
construction over already-discharged payloads, so what remains here
is only *which* aggregate, a catalog choice); the heuristic-order rung's membership in the
chooser family; release-of-effectful-attempts (waits on the Tier-1 IO
round — only the trigger is named). W = 3 as a breadth obligation:
parsing and search are rare-but-breaking; the evidence-owed domain
sample would re-weight W, never demote on rarity. Field demand predates
the round (breadth item 6, the backtracking parser's save/restore
cursor; `real-loop-survey.md`, ruby 7's PEG `# choice` block). Prior
art: Raku distinguishes ordered try-in-order choice (`||`) from
best-match-under-a-tie-law choice (`|`, longest-token — race's
structural sibling), not to be conflated; commitment (ratcheting) is
its everyday mode, supporting the threaded-values-as-substrate leaning;
FAILGOAL puts error diagnosis inside the construct. jq is the shipped
*positive* witness for threaded values (zero state-restoration
machinery, because an abandoned alternative is an unconsumed value
stream — caveat: jq owns no consumed-input notion, so parsing still
threads positions). See `speculation-design.md`, `effekt-comparison.md`,
`raku-grammars-comparison.md`, `xquery-jq-comparison.md`.

**Focused update: transform selected loci of a nested value —
I 3, W 3.**
Change part of a large nested value, preserving everything else. Now
worked in `focused-update-design.md`: the construct is **a structural
selection read as a round trip** — the path `.users[].posts[].likes` is
the same chain that *reads* the loci, and the write-back is its
**derived mirror** (`open list` ↔ exhaustive list collect, `.field` ↔
spread, case open ↔ exhaustive case collect), so selection and update
are one drawing read two ways (the lens identification; jq's deepest
win preserved rather than re-invented). Load-bearing result:
**value-selected focused update is a case split with an identity branch,
never a filter** — filter discharges the provenance naming the
unselected positions, so BQN's structural condition (materialize the
mask first) *is* our value/flow discipline (the materialized mask is the
retained case bundle). Multi-locus is the base (paths cross opens →
flows of loci), single-locus the once-firing degenerate; the deep
(`walk`-style) rewrite is named as the divide flow's lift of this
fixed-depth base; the delta output couples to incremental collections
(touched loci = invalidation keys). Five dead ends recorded.

Remaining: the adoption conversation; the path's first-classness
(drawable/computed witness vs chain-shape only); the write-back
spelling; scatter and the conflict rule (index-as-value write, Dyalog's
last-most adopted for the multi-path fan, scatter's membership open);
the derived-view catalog (transpose/reverse/reshape); and the trees-row
seam (deep rewrite = the divide flow's unfold). I = 3: a round exists
with leanings, adoption and major pieces open. W = 3, any move
conditioned on evidence: the shape is invisible to loop sampling by
construction and this round's corpora are domain-biased toward it; the
frequency question (spread pyramids, builder copies, `setIn`/lens
libraries) is on the evidence-owed list. Prior art: jq's
paths-as-one-vocabulary (the positive lens witness) against XQuery's
separate Update facility (the negative); BQN's structural Under supplies
the law, the structural condition, the lens identification, and the
derived-view generalization — BQN *removed* Expand in favour of Under;
purrr's `modify` states the functor laws — three ecosystems agree;
Redux's spread-pyramid and Immer's patches-as-data supply the imperative
costume and the delta output. See `focused-update-design.md`,
`xquery-jq-comparison.md`, `apl-family-comparison.md`,
`reactive-comparison.md`, `tidyverse-comparison.md`.

## Tier 4 — presentation and polish (≤ 7)

**The textual form's catch-up — I 3, W 2.**
The gather rule "needs the most careful specification"; spellings are
owed for Cross and end-when; history serialization is sketched, not
designed (`textual-representation-design.md`, open questions). By design
this doc tracks the representation, so most of its debt clears as other
areas land. The owed-spellings list is concrete
(`translation-exercise.md`): the late-wired-operand generalization of
the write half (`boundary of`, `value of` beside `step of` — jointly
owned with `src/ARCHITECTURE.md`'s decision record, the retired
first-class-ports round); the discharge readout's
binder convention and terminator-only form; the collect family's
spellings — now drafted (`collect-family-design.md`'s consolidated
strawman table: named reduce-closes, `collect by <op>`, the keyed forms
with `from` seeding and an explicit collision operator, a partition
strawman); entry opens' two value ports; identity lanes.
Added by the 2026-08-04 revisions: collect-until's spelling
(inline pairs vs labeled lanes — lanes must stay left-to-right;
`end-when-design.md`, revision notes); the thread's `@` spelling
and its `in ~flow` annotation, replacing `step of`/`delay init`
(`iteration-with-state-design.md`, ergonomics round); the divide
link's respelling with thread vocabulary — `level of` is retired
(`divide-flow-design.md`, open question 1); the race input lanes'
right-to-left inconsistency, with the **inline barrier spelling**
filed as a worked candidate (`textual-representation-design.md`,
"Candidate: the inline barrier spelling"); and the abstract wire
`out p ... in q` (`late-bound-operations-design.md`, revision
notes).
Added by the 2026-08-12 rounds: the **site**'s glyphs — the
out-port/in-port pair, the dashed grouping, and the thread anchors
(`divide-flow-design.md`, revision notes; this supersedes the
`level of` respelling entry above); the thread's **frame-kind
annotation and pin** (`delay-ontology-design.md`, "The frame
menu" — generalizing the `in ~flow` annotation); and the
**frame-flow tap**'s spelling (`open frames along @…`, provisional
— `divide-flow-design.md`, "The frame flow").

**Naming rounds — I 4, W 1.**
Deferred everywhere by tradition, correctly: they gate user-facing text
only. The members are ledgered in `implementation-strategy.md`; one
sweep should eventually take them together (several docs note pairs
that must be decided jointly, e.g. "type" vocabulary with "time
travel").

---

## Evidence owed

Survey rounds are not scored like design areas — evidence *reweights*
the scores above rather than carrying its own. The named next rounds
(`real-loop-survey.md`, "Next round"; method rules in
`language-design-philosophy.md`):

- **An application-level concurrency sample.** Survey 3's corpora
  implement concurrency *infrastructure*; how often application code
  reaches for gather vs race vs pool is still unmeasured. Would give the
  concurrency row's inventory items the frequency treatment the effect
  items already got.
- **UI/browser event-handling in JS** — still under-sampled after
  survey 2. It carries two extra questions: how much real
  event-handling is grammar-shaped (phase-sequenced recognition with
  state — gestures, framing) versus independent-handler-shaped; and the
  statechart-shaped question (an entire library category — XState:
  guards, state-gated events, final states with output — exists because
  reactive cores lack protocol vocabulary; Elm re-derives it as the
  Model-union idiom). This is the sample that can convert the
  custom-protocol-flows probation's category-strength documentation
  into a field sighting (Zig's labeled switch is a systems-language
  sighting, not the UI-population one).
- **A combinator census** — *done*, both corpus families
  (`real-loop-survey.md`, "Combinator census" and "Combinator census:
  the domain corpora"): counting every loop and combinator across the
  survey-1 infrastructure corpora, combinators are ~1/3 of iteration
  constructs (statement loops outnumber them ~2:1 even in Ruby/JS),
  split collect 76% / search 18% / fold 6%; finding 1's "well above
  half needs no state" holds as a ~60% majority, carried mostly by
  stateless statement loops rather than the excluded combinators. The
  domain extension over survey 2's six projects confirmed the census's
  biggest stated bias: fold's combinator share triples (6% → 20%), but
  the rise is graph reduction via `sum`, not the numeric scan — which
  is a statement loop, so it never enters the combinator-fold bucket
  (finding D.1); three.js is the extreme loop-dominated corpus in
  either census (0.03 combinators per loop). Larger n where a
  proportion becomes load-bearing still owed.
- **The saturation frequency question.** Closure-shaped computation was
  absent from the first three random surveys; survey 4 has since
  produced its first two random-draw sightings (hand-rolled worklist
  and fixpoint-passes costumes, at the nested-site unit), so the shape
  is no longer zero-sighted — but a domain sample (package/build/
  import tooling, program-analysis code, graph features inside
  applications) is still owed to measure how often the shape occurs
  and in what costume (hand-rolled worklists, embedded query engines,
  union-find), informing the saturation row's W. The same sample can carry the
  functions row's condition (does real application code swap
  providers?) and the recursion row's frequency question (how often
  divide-shaped recursion occurs, and in what costume — hand-rolled
  recursive functions, visitor patterns, `walk` helpers).
- **The function-unit sample.** Functions are a sampleable unit the
  method's own note already names; the boundary round
  (`function-boundary-design.md`) inherits its demand evidence from
  three curated corpora and owes a random draw of real functions
  classified by: call-site count (once — organization only — vs
  many), recursion (self, mutual, none), behavior parameters (would
  be op pairs), flow threading (would be flow ports), and capture
  patterns (would be prefix reads). Measures what the boundary's
  ergonomics must make effortless; carries the functions row's
  existing W-condition (does application code swap providers?)
  alongside, which the saturation-row sample below also names.
- **The focused-update frequency question.** The shape is invisible to
  loop sampling by construction, and its comparison corpora are
  document-domain-biased toward it; a sample of application code's
  nested-immutable-update idioms (spread pyramids, builder copies,
  `setIn`/lens libraries, reducer bodies) would measure how often it
  occurs outside document processing, informing that row's W.

The standing method is to be used proactively: when any row above is
worked and its round starts assuming importance rather than measuring
it, sample first.
