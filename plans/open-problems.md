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
`implementation-strategy.md` and is deliberately not duplicated here;
compile internals are `compile-strategy-design.md` ("decide in code"
questions stay there); the graphical/layout side is out of scope in
this repo entirely.

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
exploration, neither adopted. *Effects* (`effects-design.md`):
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
bodies-raise / lightweight failure stays owned by failability.

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

**Loop-carried state: the surface decision — I 3, W 5.**
The two live candidates — the Delay pair and the latent-flow augmented
uncollect — are proven result-level equivalent: one register-pair
construct under two drawings (`iteration-with-state-design.md`, "The
equivalence, worked"). The latent form's feedback collect *is* the
write half; the productivity check transfers verbatim and holds by
construction in the stored form; the stack-order/siblinghood/
pass-through residue is inert. So the open decision is no longer
"which semantics" but **which drawings exist and which is primary** —
the beginner bar and the RTL/ST gestalt critiques attach to
renderings.

Remaining: the decision conversation itself; the thread's rendering
questions; the self-driven source opener the port form must borrow —
now worked (`source-openers-design.md`: a bare flow-minting opener, no
value ports, kind answered as the sourceless stream; the
counted↔conditional seam it opens is filed back here as that round's
open question); and operator identities for reduce-close — now worked
jointly with the collect family (`collect-family-design.md`: the
identity question reframed as the empty-collect question, a three-tier
availability ladder, identities as catalog rows carrying the identity
value as witness).

Beside the surface decision sits the row's open problem, now its own
document: the **Delay ontology** — what a Delay *is* and which flow
its "next iteration" binds to (`delay-ontology-design.md`, split out
of the iteration-state doc). Where it stands: firm that a Delay is a
feature of the flow and does not thread the flow wire; the
collect-vs-ancestor fork dissolves on sequences and is silent on
grids (the value-in-context model, worked with leanings, unadopted —
it reshapes uncollect language-wide and owes an everyday-`prev`
frequency check); the two candidates answer the register's two halves
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
closes outright. It owes a frequency check (non-commutative scans
and spanning effects over genuine grids — invisible to loop
sampling by construction) before the demand's ergonomic cost is
weighed. The
per-kind "next iteration" question — formerly the row's most
concrete owed work, with several rounds writing checks on it — is
now worked (`delay-ontology-design.md`, "Per-kind \"next
iteration\": the owned-order criterion", exploration): a flow
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
(leaning) as the register whose step ignores `prev`. The row's
center, the surface decision, is untouched by all of these.

W = 5: ~23% of sampled loops carry state, dominant in numerics; the
substrate proposal in `implementation-strategy.md` is de-risked but
still a flagged decision. Prior art: jq's `foreach (init; update;
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
end-to-end; three dead ends recorded. Remaining: the adoption
conversation; the boundary-destination setting's form (jointly with
end-when's inclusive bit); the stream compile's sequencing constraint;
the fixed-length-segment catalog question; the nested-segmentation
boundary against grammar vocabulary; and the decision-driven merge
(the family's two-flow member), which still has only its chooser
sketch (`tough-use-cases-design.md` item 4).

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
(unmemoized = the divide flow's tree with its measure discipline);
the keyed cache is a partition-plus-lane-register middleware that
turns the tree into a DAG, with cycle detection as a provenance
witness — left recursion's cousin; the server-program question
largely dissolved (a server is a provider; the standing run is a
binding; the node-set consequence's second client); five dead ends,
including exchange-as-two-messages, whose field witness is the
correlation ID as hand-rolled provenance).

Remaining: the adoption conversation (joint with the late-bound
round's — one construct's two ends); the chooser family (also owning
merge fairness *and now cross-client arbitration* — a serving
provider bound at two boundaries has no cross-client order, the
served round's question 2); pacing's per-consumer/per-source bit
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

**Failability's residue — I 3, W 4.**
The core is worked (terminator payloads, propagate-by-default,
discharge at a whole-flow collect — `async-flow-design.md`). Residue:
payload-type composition is unexamined; "do bodies raise?" is flagged
genuinely open; the discharging collect's ports fold into the
barrier-crossing row (Tier 3, now worked with leanings); the
option/async convergence is sharpened but undecided. End-when's readout
composition leans entirely on discharge, so adoption pressure now
arrives from the everyday side too.

Prior art gives both flagged residues field answers. Zig's `try` is
propagate-by-default shipped (bodies-raise: yes, at one keyword's cost
— the strongest witness for the lightweight `fail` direction; a
seven-statement end-when encoding of a raise is not viable as the
everyday form). Error-set algebra: union at merge points, subset→
superset coercion along propagation, inference by default with a named
escape to explicit sets, and the warning that inference breaks on
recursion (a constraint to carry to the divide flow and feedback
forms). `catch |e| switch` with exhaustive error switches is the
discharge + split-on-tag idiom in the mainstream. See `zig-comparison.md`,
`async-flow-design.md`.

**Checking: the deferred design rounds — I 3, W 4.**
The stance is settled (demands/offers, no search, drawable witnesses —
`types-design.md`; paths and clash flavors —
`bundle-provenance-design.md`); implementation is workstream D. The
design-side gaps: recursive shapes (question 2, waiting on the tree
constructs), slots/higher-order signatures (question 3), the catalog
schema and its trusted JS edge (question 4), equality's fine print
(question 8).

Question 4 gains its first concrete content demand from the collect
family (`collect-family-design.md`): catalog rows are properties
carrying value witnesses (the identity value itself), and the algebra
facet is the authoring surface that mints rows for user operators,
trusted like the JS edge. Prior art: Flix's restrictable variants are
the strongest prior art for question 2 (recursive case-set properties
trackable and paying for themselves; their own illegible-at-scale type
algebra supports the drawable-witnesses stance over imported Boolean
indices); "this hole demands a pure filler" is added as demands/offers
vocabulary; `@Terminates` is prior art for declared, checked
termination. See `flix-comparison.md`.

**Functions, reuse, and facets — I 3, W 4.**
The row's center — the demand the record could previously not answer
at all — is now worked: **late-bound operations and the test double**
(`late-bound-operations-design.md`, exploration). An unbound
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

Still narrative-stage or open: the function boundary itself (flow
skeleton with data holes, `functions-design.md`), its conjectured
relationship to summaries-as-generalized-programs (`types-design.md`
read-out 2), and completion's boundary residue
(`time-travel-programs-design.md` question 5). The new round's own
residue: the adoption conversation; the spellings (`op`, `serve`,
binding, splice), owed jointly with the level boundary — the divide
flow's demand — and the textual catch-up (one decision, three
clients); region-scoped rebinding; the serving provider's multi-lane
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
carry a value witness — the identity — not just a named law).

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
row's new Delay-ontology open problem. Unexamined: join on a product (operand-walk rules, question 4); the
provenance product segment against the walk-and-classify algorithm
(question 8). Spec entry and textual spelling are owed bookkeeping.

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
textual spelling; **rank-2 zip's axis handling — Conway's Life needs
Cross to enumerate the neighborhood and zip to overlay it at rank 2, the
record's one localized representation struggle**, riding this row's
n-ary/axis debt; and per-edge alignment (`reduce2`'s length-(n−1) second
input) to the register round. The unexamined interactions above — join
on a product, registers over products, the provenance product segment
(questions 4, 5, 8) — plus tidyr's observed-product vs full-product
distinction (`nesting()` inside `expand`), remain the row's open core;
I stays 3. Honesty: a curated corpus; the owed field sample (real
analysis scripts) should still confirm the scope move. See
`apl-family-comparison.md`, `zig-comparison.md`,
`tidyverse-comparison.md`, `product-flows-design.md`.

## Tier 3 — worked areas with named residue (≈ 9–10)

**End-when: adoption and its open questions — I 2, W 5.**
The exploration round exists with leanings (`end-when-design.md`;
question 5 worked in place). Remaining: the adoption conversation
itself; the inclusive/exclusive bit's final form (node-vs-wire now
worked toward the node; the drawing and the tie-break interaction
resolved with it); interrupt unification; the register
final-readout anchor (touches the iteration-state round); the textual
spelling. Low I is recent work; W = 5 (the surveys' biggest unserved
everyday demand) is why the remaining distance is worth closing soon.

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

**Recursion: the divide flow and trees — I 3, W 3.**
Recursion over virtual structure is now worked
(`divide-flow-design.md`, exploration — moved down from Tier 2 by
this index's maintenance rule): the divide flow is **the link
transformation, tree-shaped** — write one level concretely (an
ordinary case split; a leaf is an alt with no links, dissolving the
base-case construct), then link the sub-problem wires back to the
problem wires. Each link firing mints an instance; per-instance
membership is derived from dataflow (downstream of a problem wire —
everything else is shared by the prefix rule); the link is a barrier
(multi-wire problems cross pairwise); and the construct is honestly
primitive — the defunctionalized stack encoding is ruled inadmissible
as a derived view (frames are a packed sum). Termination is a
**three-species measure discipline**: structural shrink (catalog rows
with witnesses), cursor progress (whose violation witness is exactly
the parser field's left-recursion check), and drawn fuel (the
quadtree budget — the owed non-list example, worked; the catalog is
confirmed not list-shaped), with warned trust as the fenced escape
hatch (derived-iteration precedent; Flix `@Terminates` prior art).
Recursive descent is worked as the first program — variable arity
dissolves into a link inside a drawn walk, sequenced children are the
register on that walk, two answers are two sibling collects — closing
speculation's four-part parsing vocabulary; the `walk`-style deep
rewrite lands as focused-update's unfold client and re-reads
recursion-over-data as the strict-components division, unifying the
ADT-derivation story with the divide flow. Sibling instances have no
time: registers over instances are ill-formed (concurrent-collect
precedent), traversal orders dissolve into combines, and whole-tree
collects are order-free iff commutative (the product-round law). Five
dead ends recorded.

Remaining: the adoption conversation; the link's spelling and anchor
— the **level boundary**, the first construct-driven demand for the
functions row's flow skeleton, to decide jointly with that row;
mutual recursion (a joint measure over a link group; where Zig's
inference warning bites hardest); the measure catalog's schema (joint
with the checking row's question 4); whole-tree linearization (rides
the delay-ontology/product residue); and the **zipper seam** —
whether tree-over-data iteration re-reads its computed-value accesses
as drawn crossings and retires the verify-or-fall-back scheme
(`trees-and-recursion.md` owns that decision; the round's leaning
runs that way). W = 3 as a breadth obligation: the three random
surveys produced one recursive draw (breadth item 9, survey 2 —
transcribed in the round), but
parsing supplies everyday demand from outside the sampled domains,
and parsers/planners/tree algorithms are rare-but-breaking; the
frequency question folds into the saturation row's owed domain
sample. See `divide-flow-design.md`, `trees-and-recursion.md`,
`tough-use-cases-design.md`, `raku-grammars-comparison.md`,
`flix-comparison.md`.

**How values cross a barrier — I 2, W 4.**
Worked (`barrier-value-crossing-design.md`): crossing split into
availability (provenance over the barrier's flow law; no pass-through
value ports anywhere) and minted ports, with a co-location criterion
for which mints share a node. The four corners answered with leanings:
Join and the concurrent join flow-only; race's per-contender (value,
flow) pairs confirmed, values-in; no multi-row partial collect — m rows
are m sibling collects at one context; the discharge one settled-sum
port on exactly-one kinds, the (prefix, terminator) pair on many kinds;
five dead ends recorded. Remaining: the adoption conversation, the
spec-side reconciliation (its Join's value ports re-read as drawn
availability), and the concurrent join × Cross unification question it
strengthened.

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
end-when's discharge); the heuristic-order rung's membership in the
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
owned with `first-class-ports-design.md`); the discharge readout's
binder convention and terminator-only form; the collect family's
spellings — now drafted (`collect-family-design.md`'s consolidated
strawman table: named reduce-closes, `collect by <op>`, the keyed forms
with `from` seeding and an explicit collision operator, a partition
strawman); entry opens' two value ports; identity lanes.

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
  absent from all three random surveys; a domain sample (package/build/
  import tooling, program-analysis code, graph features inside
  applications) would measure how often the shape occurs and in what
  costume (hand-rolled worklists, embedded query engines, union-find),
  informing the saturation row's W. The same sample can carry the
  functions row's condition (does real application code swap
  providers?) and the recursion row's frequency question (how often
  divide-shaped recursion occurs, and in what costume — hand-rolled
  recursive functions, visitor patterns, `walk` helpers).
- **The focused-update frequency question.** The shape is invisible to
  loop sampling by construction, and its comparison corpora are
  document-domain-biased toward it; a sample of application code's
  nested-immutable-update idioms (spread pyramids, builder copies,
  `setIn`/lens libraries, reducer bodies) would measure how often it
  occurs outside document processing, informing that row's W.

The standing method is to be used proactively: when any row above is
worked and its round starts assuming importance rather than measuring
it, sample first.
