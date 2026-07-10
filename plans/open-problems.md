# Open problems and incomplete areas

*Ranked index, first assessed 2026-07-09. This document exists to
make the record's gaps findable — it points, broadly, at the docs
(or portions of docs) where design is missing or undecided, so that
"what should be worked next" doesn't require re-reading everything.
It decides nothing and contains no design content of its own.*

## How to read this list

**Broad areas, not work items.** Each row names an area and points
at the doc(s) that own it. The fine-grained open questions live in
those docs, next to the context that produced them and the
rejection notes that keep them honest. Working from this list
without reading the owning doc's status header — and its recorded
rejections — is how re-proposals happen. The row is a door, not a
task.

**Two scores, ranked by their product.** Each area carries:

- **Incompleteness (I, 1–5):** how far the area is from a settled
  design. 5 = a name and a demand, nothing worked; 4 = options or
  candidates laid out, core content undesigned; 3 = worked
  round(s) exist but the central decision or major pieces are
  open; 2 = design worked, named residue; 1 = polish.
- **Importance (W, 1–5):** how much a useful overall design needs
  it. 5 = the language isn't usable or trustworthy without it;
  3 = significant but bounded; 1 = gates surface text only.

Rank is roughly I × W, presented in tiers. Adjacent positions
within a tier are noise — do not read the ordering more precisely
than the tier boundaries.

**Frequency is not importance.** The importance score folds in the
80/20 counterweight (`language-design-philosophy.md`, the standing
method's interpretation rule): a rare shape the language must not
fail — a breadth obligation — scores high despite being drawn
once. High survey frequency argues *effortlessness*, which is a
different pressure on the same score.

**This is not a queue.** Always working the top row is exactly the
tunnel vision this format tries to avoid — several areas advance
only when others feed them (evidence reweights scores; the
iteration-state decision wants end-when in the room; barrier ports
want race and partial collect considered together). Drift between
tiers is healthy. Decisions stay in the design conversations; this
list only shortens the search.

**Maintenance rule.** Whenever an area is worked — a round
written, a decision taken, evidence landed — reassess *both*
scores, re-tier if the product moved, and date the change in the
assessment log at the end. A worked round typically lowers I and
sharpens (not necessarily raises) W. Stale scores are worse than
no scores; if the log's last entry is old, trust the docs over
this index.

**Scope.** Design record only. Implementation sequencing —
workstreams, phases, the cross-cutting ledger — is
`implementation-strategy.md` and is deliberately not duplicated
here; compile internals are `compile-strategy-design.md` ("decide
in code" questions stay there); the graphical/layout side is out
of scope in this repo entirely.

---

## Tier 1 — the load-bearing gaps (I × W ≈ 20)

**IO, effects, and cancellation — I 4, W 5.**
The record's most-cited hole: `tough-use-cases-design.md` names
"no IO design, no cancellation" among its known gaps and calls the
cancellation gap load-bearing (bracket's release-on-abandonment,
race-implies-cancel, and abandoned pending pulls all arrive at
it); effect *ordering within a firing* is flagged by the survey
(breadth item 5, the conditional-flush buffer) and has only raw
material (`custom-flows.md`'s lifecycle pattern), not a design.
W = 5 because ~42% of sampled loops exist to cause effects, and
both `async-flow-design.md` (question 2) and
`incremental-flow-design.md` (effect-free tracking contexts) defer
constraints here that block their own completion. *(2026-07-10: the
cancellation half is now measured, not only argued — the
concurrency survey found roughly eight of thirty orchestration
sites touching cancellation/abandonment/retention, containing the
sample's most delicate code; `real-loop-survey.md`, survey 3,
finding 3.6.)* *(2026-07-10, later: the effects half gained its
everyday failure mode — the translation exercise found per-firing
effects simply unwritable (`translation-exercise.md`, finding 1:
"you cannot transcribe `task.cancel()` in a loop"), and
bodies-raise / lightweight failure surfaced as the same row's
second concrete demand (its finding 2).)* *(2026-07-10, later:
external confirmation from the Effekt comparison
(`effekt-comparison.md`, finding 5) — every one of their nine case
studies freely interleaves effects mid-computation, i.e. the hole
gates ordinary programs, not just effect-heavy ones; no score
movement, the row already carries W 5.)* *(2026-07-10, later: same
witness from the Flix comparison (`flix-comparison.md`, finding 3)
— purity there is the typed mirror of drawn effects, every example
interleaves effects, and `spawn @ region` (task lifetime bounded by
a drawn scope) is mainstream confirmation for the cancellation
half. Confirmation only; no score movement.)* *(2026-07-10, later:
the XQuery/jq comparison (`xquery-jq-comparison.md`, finding 8)
handed the row its **first structural prior art** rather than
another confirmation — XQuery's Update Facility answers per-firing
effects by reifying them: a pending update list (an unordered
collection of update primitives, gathered by ordinary evaluation,
applied atomically at a snapshot barrier, conflicts resolved by
declared rules — the effects-as-collected-plan pole of the design
space), with its strain points (no read-your-writes inside the
snapshot; conflict rules are where within-firing ordering
resurfaces) mapping onto breadth item 5. jq marks the same pole
degenerately: effects only at the pipeline's edges — viable for a
guest tool, not a host language. Structure, not a design; no score
movement.)* *(2026-07-10, later: the reactive comparison
(`reactive-comparison.md`, finding 5) — the hole acknowledged at
standards level: the TC39 Signals proposal ships **no effect
construct** ("effect scheduling is subtle and often ties into
framework rendering cycles"), stopping exactly at this row. Elm's
`Cmd` is the second effects-as-collected-values witness, with the
loop closed through ordinary events (results re-enter as `Msg`s).
The two shipped output poles — recompute-and-diff (Elm/React) vs
fine-grained push (Solid) — are both drawable (derived view +
boundary focused update vs per-var `changes` drains), so the pole
is per-consumer wiring, not a language commitment. Universal
effect-ordering disclaimers ("MobX does not guarantee the order")
are the IO thread's mirror; Elm's ports supply the FFI-boundary
stance (few, owned, message-shaped). Scores unchanged.)*
*(2026-07-10, later: the Zig comparison (`zig-comparison.md`,
findings 6, 8) handed the **cancellation/bracket half** its
structural prior art, complementing the pending-update-list prior
art on the effects half — `defer`/`errdefer` supply four
properties any bracket design should reproduce: release written
adjacent to acquisition (in the record's terms a late-wired
release half on the acquiring node, the `<port> of <name>`
two-phase form, fired at the owning flow's discharge); cleanup
keyed by exit reason (errdefer = per-terminator-lane release,
error payload capturable); the infallibility asymmetry ("Resource
allocation may fail; resource deallocation must succeed"); and
per-firing as well as per-flow attachment (defer in a loop body).
Plus the new `std.Io` cancellation cluster: `Future.cancel` is
"equivalent to await but places a cancellation request" —
cancellation *discharges a readable terminator*; group wait
propagates cancellation to members (scope-bound lifetime's second
witness); `cancelRequested` polling as the cooperative floor.
Structure, not a design; scores unchanged.)*

## Tier 2 — big areas with partial designs (≈ 12–16)

**Loop-carried state: the surface decision — I 3, W 5.**
*(Was "the candidate decision", I 4, Tier 1 — the record's
self-declared biggest open area — until the 2026-07-10 equivalence
round, `iteration-with-state-design.md`, "The equivalence, worked":
the latent form's feedback collect pinned as the write half (forced
by three standing positions at once), the two live candidates
proven result-level equivalent — one register-pair construct under
two drawings — with the productivity check transferring verbatim
and holding by construction in the stored form, and the
stack-order/siblinghood/pass-through residue shown inert.)*
Remaining: the decision conversation itself, reframed from "which
semantics" to "which drawings exist and which is primary" — the
beginner bar and the RTL/ST gestalt critiques attach to renderings,
and the thread's rendering questions live here; the self-driven
source opener the port form must borrow (shared with the
concurrency row's source-opener item); operator identities for
reduce-close, unattached (three hand-rolled monoid folds in the
surveys press on this; jointly with the collect family's spelling
round, Tier 4). *(2026-07-10: the Flix comparison
(`flix-comparison.md`, finding 6) added the strongest sighting
cluster yet for the operator-identity/keyed-collect item — three
hand-rolled `Map.insertWith` merge folds in one application module,
plus lattice aggregation sitting at the center of the saturation
row's paradigm, plus a set/distinct collect (`deduplicate`). Scores
unchanged.)* *(2026-07-10, later: the XQuery/jq comparison
(`xquery-jq-comparison.md`, findings 5–6) — jq's `foreach (init;
update; extract)` is the running view / augment form shipped,
named, and everyday in the corpus's most field-like code, and
XQuery's total lack of a scan clause is the negative witness:
running-state queries there bend through windows and recursion.
The keyed-collect item gains its primary/derived fork:
group-as-flows (XQuery/jq's shipped form — non-grouping wires
become per-group flows; aggregation, HAVING, and reports as
ordinary downstream consumption; the form that builds) vs
operator-merge (Flix's `insertWith`, the fused special case), with
the dynamic-alt-set note that a keyed partition's cells are
data-determined lanes, not a static bundle. Scores unchanged.)*
*(2026-07-10, later: the APL-family comparison
(`apl-family-comparison.md`, findings 5, 8) — the
operator-identities item gains a shipped **catalog** (Dyalog's
23-operator identity table; empty reduce yields the identity or
DOMAIN ERROR) and its sharpest framing: the identity question is
exactly the **empty-collect question** — BQN's three-way split
(derive the identity for an empty fold; take a seed via the
initial-value port, dissolving the need; the scan never asks —
empty in, empty out). The keyed collect's third consecutive
round: group output order now has three shipped answers
(first-appearance / sorted / unspecified; provenance favors
first-appearance), BQN's classify-then-place decomposition argues
key extraction is ordinary drawn computation rather than node
configuration, and ¯1-drop is keyed partial engagement. Scores
unchanged.)*
*(2026-07-10, later: the Zig comparison (`zig-comparison.md`,
finding 1) — the write-half design confirmed from the imperative
mainstream: Zig's `while` continue expression is the register
step pulled out of the body and attached to the loop precisely so
`continue` cannot skip it; C's skip-the-increment bug class is
the negative witness for making the step structural. Scores
unchanged.)*
*(2026-07-10, later: the tidyverse comparison
(`tidyverse-comparison.md`, findings 2, 3, 6) — the keyed
collect's fourth consecutive round, this time supplying its
**readout family**: one keyed partition barrier consumed several
ways — collapse (dplyr `summarise`: one output per group, keys ⊕
aggregates, the keyed collect as already recorded), **pass-through**
(grouped `mutate`/`filter`: per-firing values riding back to the
parent walk in original order — the case bundle's exhaustive
collect generalized to data-determined cells; new structure),
flatMap (`reframe`: per-lane output that is itself a flow joined
upward), and whole-lane engagement (`filter_out(n() == 1)`). The
group *stack* confirmed as drawn nesting (summarise pops one
level; `.groups` is the how-many-levels choice as API). Two
corollaries recorded: the **broadcast-back** composite (`x -
mean(x)`, grouped z-scores — a fold consumed by a re-walk of its
own source; two walks, not time travel; under grouping it
requires the per-group value, the lane collected to a re-openable
sub-list — group-as-flows' group-as-*value* corollary, which
dplyr ships independently as `nest_by`), and the **keyed index**
consumption pattern (joins: build lanes once, read per-firing of
another flow; left join = the fired-empty completion; jq's
`INDEX` made everyday). Also `pivot_wider` located as the keyed
collect itself (its `values_fn` collision case is the
operator-merge variant). Scores unchanged.)*
W = 5 unchanged: ~23% of sampled loops carry
state, dominant in numerics; `implementation-strategy.md`'s
substrate proposal is de-risked but still a flagged decision.
Companions: `first-class-ports-design.md` (the Delay pair),
`iteration-rails-design-notes.md`.

**Variable-rate consumption and the running view of a collect —
I 3, W 4.**
*(Was I 5 — the record's only ownerless Tier-1 cluster — until the
2026-07-09 exploration round, `variable-rate-consumption-design.md`:
"advance how far" reframed as boundary placement via split-when, a
segmenting binary flow operation; the running view answered as the
state port of the collect's derived augment form; breadth items 1,
2, 4 worked end-to-end; three dead ends recorded.)* Remaining: the
adoption conversation itself, the boundary-destination setting's
form (jointly with end-when's inclusive bit), the stream compile's
sequencing constraint, the fixed-length-segment catalog question,
and the nested-segmentation boundary against grammar vocabulary.
The decision-driven merge — the family's two-flow member — still
has only its chooser sketch (tough doc item 4). *(2026-07-10: the
Raku comparison round (`raku-grammars-comparison.md`, findings 1,
2, 4) gave the grammar-vocabulary boundary its shape — the grammar
ladder's four combinators over segments (repeat: owned by
split-when; sequence — phased consumption, the start/body/end
pattern, a consumer that takes a prefix and yields the rest —
unowned; alternate — typed segments — unexamined; recurse — the
divide flow's), with question 3's fork stated: boundaries decidable
per-firing are segmentation vocabulary, boundaries negotiated by
trial are the speculation row's. Also a confirmation sweep:
Raku's `%`/`%%` separator quantifiers are a fourth wild sighting of
the destination enumeration; computed counts are prior art for the
catalog question; post-order `make`/`made` confirms the
per-segment-value-at-discharge skeleton. Beyond-text demand (event
grammars, framing, sessionisation) files here too, with the
measurement question handed to the owed UI sample. Scores
unchanged — the remaining list is sharper and longer, the center
untouched.)* *(2026-07-10, later: the XQuery/jq comparison
(`xquery-jq-comparison.md`, findings 3–4) — the window clause is
split-when shipped as a W3C standard: a full confirmation sweep
plus three new pieces. Question 1 gains the neighborhood-bindings
alternative (window conditions read the boundary's
`previous`/`next` items, so each destination is a phrasing rather
than a knob — fifth wild sighting of the enumeration, first
non-enumerated form); a **new enumerated bit** lands beside the
destination setting — the unterminated final segment (input ends
mid-segment: emit partial vs drop; XQuery's `only`), to be decided
jointly with the existing bit; and **gap-tolerant segmentation**
(windows need not partition — items outside any window are
dropped; framing's scan-for-sync is the field client) joins as a
variant of the same construct. window(k) locates as the
fixed-size point of a tumbling/sliding × condition/count-bounded
family, and positional end conditions answer question 4's form
(counts as data on position bindings). The 3.0 windowing use
cases are mostly complex-event recognition matching the grammar
ladder rung for rung (a strong prior for the owed UI sample, not
a substitute), and the per-key pairing query's strain shows keyed
partition must compose with segmentation. Scores unchanged.)*
*(2026-07-10, later: the APL-family comparison
(`apl-family-comparison.md`, findings 3, 4, 9) — the window(k)
design space arrives shipped three ways (N-wise reduce,
windows-as-value, centered Stencil), with parameters sighted:
step/movement (step=k unifies windowing with fixed-length
split-when), **edge handling as a real dimension** (Stencil pads
and reports the padding per-invocation; N-wise truncates — the
unterminated-segment bit at both edges of a symmetric construct),
per-window reversal, and 2D windows (which file to the products
row). The FinnAPL segmented-scan genre (grade-of-grade flat
encodings for per-segment running state, with the community
benchmarking flat vs nested) is the strongest assembly-language
exhibit yet for split-when + register; Partition's drop-zeros is
another gap-tolerant-segmentation sighting. Scores unchanged.)*
*(2026-07-10, later: the Zig comparison (`zig-comparison.md`) —
small note: `std.mem.window(T, buf, size, advance)` ships
window(k) with an independent step parameter and emits the
partial final window (the unterminated-final-segment bit set to
"emit"), one more point in the window family's design space.
Scores unchanged.)* *(2026-07-10, later: the tidyverse comparison
(`tidyverse-comparison.md`, finding 10) — a fourth-ecosystem
assembly-language sighting for split-when: tidyr's contact-list
example synthesizes a grouping key from row order
(`cumsum(field == "name")`) because the vocabulary lacks
boundary-driven segmentation — the scan costume of the construct.
Rolling aggregates named as a family but delegated out of dplyr
is a small demand datum on window(k). Scores unchanged.)*

**The concurrency constructs — I 3, W 4.**
Concurrent collect (inventory item 1; its species menu partly
dissolved into wiring, but `bounded(n)` resists), the served flow
(item 2), the race barrier's own semantics round (owed per
`async-flow-design.md` question 5), fairness, and "what is a
program for a server?" (`tough-use-cases-design.md` question 7).
Demanded by three of the five tough use cases. The event-loop
breadth item (7) is this area's acceptance test in miniature.
*(2026-07-10: evidence landed —
`real-loop-survey.md`, survey 3, thirty orchestration sites from
six server/async corpora. Scores unchanged (nothing designed got
designed), but the within-area ranking is sharpened: first-of
coordination (race/timeout/interrupt) outweighed all-of nine-to-one
and every hand-rolled race reconstructs the winner from side flags,
so the race barrier's round leads this area, ahead of the collect
species menu; `bounded(n)`-as-resource and serial-as-default are
field-confirmed; the concurrent collect's lifecycle outputs gained
a bug class they would prevent.)* *(2026-07-10, later: the race
round is written — `race-barrier-design.md`, building on the
crossing round's port answer: the barrier's law and ties, the
unary-race leaning, failable subset merges, the dynamic-set
redirect, the cancellation hook, merge/interrupt/timeout as
derived vocabulary; fairness answered by relocation to the
chooser family. I 4 → 3: the area's lead item now has worked
leanings, but the concurrent collect's own round, the served
flow, and the server-program question remain, and nothing is
adopted.)* *(2026-07-10, later: the translation exercise added
two items to this row's remaining list — source openers (the FFI
pull source and the self-driven flow have no authoring form, so
survey classes 4–5 cannot start on the page) and **pacing**: a
self-driven flow whose next firing waits on a per-firing async
value (sleep-between-retries), a semantic hole with three field
sightings that blocks the retry composite;
`translation-exercise.md`, finding 3.)* *(2026-07-10, later: the
Effekt comparison (`effekt-comparison.md`, findings 4, 6a) handed
the served flow's round two demands — the recursive provider (a
server defined partly by requests back to itself) and the keyed
cache in front of a served flow, both from the build-system case
study — and added an outside witness that the missing source
opener blocks the canonical beginner generator.)* *(2026-07-10,
later: the Flix comparison (`flix-comparison.md`, finding 4) —
timeout-as-ordinary-contender confirms the race round's derived
timeout; the **default arm (poll)** is a derived form the race
round's vocabulary hasn't named (a race with one
immediately-settled contender that loses all ties — well-defined
under the drawn-order tie law); `spawn @ region` confirms
scope-bound task lifetime as a mainstream default; recursive
channel producers are the third source-opener witness; and the
retry middleware is a fourth pacing sighting, now as stdlib
vocabulary — the functions row's policy layer is blocked on it.
Scores unchanged.)* *(2026-07-10, later: the XQuery/jq comparison
(`xquery-jq-comparison.md`, finding 6) — fifth source-opener
witness: jq's `while`/`until`/`repeat`/`recurse(f; cond)` are the
self-driven source hand-built from recursion plus the comma
operator; `input`/`inputs` sight the pull-based FFI source
species. Scores unchanged.)* *(2026-07-10, later: the reactive
comparison (`reactive-comparison.md`, finding 3) — RxJS's four
flattening strategies are the collect-concurrency menu shipped as
the async lingua franca: switchMap = interrupt-race, concatMap =
serial (its unbounded-buffer warning is pacing/backpressure
sighting six), mergeMap(+max) = bounded/unbounded — and
**exhaustMap names a species the menu lacks**: drop-newest-while-
busy, a non-queueing serial; handed to the concurrent collect's
round. The served flow gains React Query's model as furniture:
keyed async state with staleness policy (fresh-until, refetch on
mount/refocus/reconnect), retry-with-backoff, and gc of inactive
keys. Scores unchanged.)*
*(2026-07-10, later: the Zig comparison (`zig-comparison.md`,
findings 2, 8) — a **priority correction on the source opener**:
Zig's plainest counter `while` transcribes onto the self-driven
flow, and the stdlib's whole iteration story is pull-until-null
(`next() ?T`) — the opener gates ordinary loops, not just pumps
and generators; seventh and most institutional witness. The
concurrent collect's round gains the asynchrony-as-possibility /
concurrency-as-failable-resource-claim distinction (`io.async`
may run synchronously — the DAG's stance in API form;
`io.concurrent` fails with `ConcurrencyUnavailable`, slotting
beside `bounded(n)`-as-resource). The race round gains the
select-union note: `io.select` packs a tagged union to cross the
race (the sum bottleneck), but discriminated by contender name —
discrimination-must-be-structural confirmed, the packing what the
barrier form dissolves. Scores unchanged.)*

**Failability's residue — I 3, W 4.**
The core is worked (terminator payloads, propagate-by-default,
discharge at a whole-flow collect — `async-flow-design.md`), but
payload-type composition is unexamined, "do bodies raise?" is
flagged genuinely open, the discharging collect's ports fold into
the barrier-crossing row (Tier 3 — now worked with leanings), and
the option/async convergence is sharpened but undecided. End-when's readout composition leans
entirely on discharge, so adoption pressure now arrives from the
everyday side too. *(2026-07-10: the Zig comparison
(`zig-comparison.md`, finding 7) gave both flagged residues field
answers. Bodies-raise: yes, at one keyword's cost — `try` is
propagate-by-default shipped, the strongest witness for the
lightweight `fail` direction (the seven-statement end-when
encoding of a raise is not viable as the everyday form).
Payload-type composition: error-set algebra shipped — union at
merge points (`||`), subset-to-superset coercion along
propagation, inference by default with a named escape to explicit
sets, and the warning that inference breaks on recursion (a
constraint to carry to the divide flow and feedback forms).
`catch |e| switch` with exhaustive error switches is the
discharge + split-on-tag idiom in the mainstream. Prior art, not
a design; scores unchanged.)*

**Checking: the deferred design rounds — I 3, W 4.**
The stance is settled (demands/offers, no search, drawable
witnesses — `types-design.md`; paths and clash flavors —
`bundle-provenance-design.md`); implementation is
workstream D. The *design-side* gaps: recursive shapes (its
question 2, waiting on the tree constructs), slots/higher-order
signatures (question 3), the catalog schema and its trusted JS
edge (question 4), equality's fine print (question 8).
*(2026-07-10: the Flix comparison (`flix-comparison.md`, findings
3, 5, 7b) — restrictable variants are the strongest prior art yet
for question 2 (recursive case-set properties trackable and
paying for themselves), with their own illegible-at-scale type
algebra supporting the drawable-witnesses stance over imported
Boolean indices; "this hole demands a pure filler" added as
demands/offers vocabulary; `@Terminates` noted as prior art for
declared, checked termination. Scores unchanged.)*

**Recursion: the divide flow and trees — I 4, W 3.**
`trees-and-recursion.md` is narrative-stage (no starting-point
document; flagged so in `implementation-strategy.md`); the divide
flow is a candidate primitive with an unworked termination story
(a non-list example — quadtree — is owed;
`tough-use-cases-design.md` question 4); whether tree iteration
inherits the register discipline is unresolved. Breadth item 9
(the recursive gather) is the field sighting. *(2026-07-10: the
Raku comparison round (`raku-grammars-comparison.md`, §4) named
parsing as the everyday client of recursion-over-virtual-structure
— the divide flow's worked examples so far are constructed;
recursive descent (nested-delimiter parsing) is a candidate first
program with field precedent when the row's round runs. Scores
unchanged.)*

**Functions, reuse, and facets — I 4, W 4.**
Also narrative-stage: the function boundary (flow skeleton with
data holes, `functions-design.md`), its conjectured relationship
to summaries-as-generalized-programs (`types-design.md` read-out
2), completion's boundary residue
(`time-travel-programs-design.md` question 5), and facets
(recorded in `tough-use-cases-design.md`'s addenda as "too big a
topic to explore now"). A useful language eventually needs reuse;
the deferral is deliberate but should not become permanent by
inertia. *(2026-07-10: W 3 → 4 — the Effekt comparison round
(`effekt-comparison.md`, findings 1–2) added two demands to the
remaining list: **late-bound operations** (a diagram written
against operations whose meaning is wired in per use — the
inside-out form is a request/response port pair on the boundary,
connecting to the served flow) and its everyday face, **the test
double** ("run a diagram that does IO against fake IO"), which the
record currently cannot answer at all. Four of nine Effekt case
studies rest on this capability; testing makes it everyday rather
than exotic.)* *(2026-07-10, later: the facets half now has a
recorded statement of intent — `facets-design-notes.md`, from the
design conversation the test-double finding prompted: facets as
authorable, attachable abstractions (the struct → interface →
facet ladder; algebras and state machines as code facets; shared
facet between production and test code as what makes the test
double informative), holes without breaking, negative constraints
with their stated direction of doubt, and the explicit bound that
facets are views for a human, not verification. Scores unchanged —
intuitions recorded, nothing worked; the doc's open edge 2 records
the leaning that a first round should work one manifestation (the
algebra facet + test double) rather than a general theory.)*
*(2026-07-10, later: the Raku comparison round
(`raku-grammars-comparison.md`, finding 5) — late-bound operations
gained its second independent witness (one grammar under
interchangeable, optional action classes; capability confirmed, the
method-name-reflection mechanism recorded as a clash), and the
remaining list gains **extensible alternation**: extend a case
vocabulary — an alternation and its dispatching consumers — without
editing the defining site (Raku's proto regexes; their motivating
complaint is verbatim the unbuildable-upon complaint), with the
tension flagged that the complete alternative set must stay
viewable somewhere (a facets-flavored derived view). Scores
unchanged.)* *(2026-07-10, later: the Flix comparison
(`flix-comparison.md`, findings 2, 3, 7e) — late-bound operations
and the test double gain their third and strongest witness: the
double is standard-library furniture there, and ordinary
applications are assembled as provider stacks at the edge. The
remaining list gains the **policy layer** (middleware —
cross-cutting operational policy interposed at the operation
boundary: retry, circuit-break, throttle, sandbox, atomicity,
audit; in the row's leaning, a sub-diagram spliced into the
provider wiring, with stack order visible as nesting) and the
**decorated tree** (one tree, stacked per-node decorations,
consumers demanding only what they read — facets' second
independent witness), plus the purity mirror's demand that the
function boundary pass a filler's effect/failability wires through
visibly. W held at 4 with the condition recorded: three curated
corpora converging argues 5, but per the standing method that
move should come from the owed application-level sample — does
real application code swap providers?)* *(2026-07-10, later: the
APL-family comparison (`apl-family-comparison.md`, finding 1) —
the operator-catalog audit filed the family's genuinely
higher-order residue here: arrays of functions and dispatch over
*computations* (BQN's `◶` tables beyond the case split) are the
late-bound-operations demand in array costume. BQN's rationale
for first-class functions is recorded as the position the record
declines — they removed a syntactic obstacle, we decline the
semantics (the round's brief: the uncollect's virtual value does
the work of every operand slot without a function being passed).
Scores unchanged.)* *(2026-07-10, later: the reactive comparison
(`reactive-comparison.md`, finding 3) — the policy layer's second
witness-as-furniture: React Query ships retry/backoff/staleness/
gc as declarative query config interposed between consumers and
the async source. Scores unchanged.)* *(2026-07-10, later: the
Zig comparison (`zig-comparison.md`, finding 8) — late-bound
operations' fourth witness and the flattest mechanism yet:
Allocator/Io as **ordinary parameters**, no capability machinery
at all, supporting the row's inside-out provider-on-a-port
leaning over any dynamic-scope reading. The test-double question
gains **fault injection as configuration**
(`std.testing.FailingAllocator` — "fails after N allocations,
useful for making sure out of memory conditions are handled
correctly"); allocator wrappers (arena, leak-checking, logging)
are the policy layer's third furniture witness. Scores
unchanged.)* *(2026-07-10, later: the tidyverse comparison
(`tidyverse-comparison.md`, finding 8) — the remaining list gains
the **authoring gesture** demand: dplyr's `across` (apply one
operation to k schema-selected columns, output names computed) is,
over a static schema, k-fold repetition of drawn structure — the
demand is one gesture producing k readable nodes (a schematic
sub-diagram instantiated per wire; the many-authoring-paths /
one-reading stance), not a runtime construct. Over data-keyed
tables it is the keyed uncollect, already owned. `cur_column()`
recorded as a magic-name clash whose legitimate content is the
lane-key wire. Scores unchanged.)*

**Speculation: ordered alternatives with rollback — I 4, W 3.**
*(New row, 2026-07-10, from the Effekt comparison round —
`effekt-comparison.md`, finding 3.)* Try alternatives in drawn
order; an attempt can fail; the world is restored between
attempts. Field demand predates the round (breadth item 6, the
backtracking parser: "wants the save/restore pairing visible";
`real-loop-survey.md`), and the comparison found the shape twice
independently (parser, pretty-printer-as-search). Pieces exist —
race's drawn-order ties (`race-barrier-design.md`), failability's
fail, the chooser family (`tough-use-cases-design.md` item 4),
registers (express save/restore but illegibly) — but nothing owns
the construct. The recorded leaning for its round: a sequential,
ordered race-sibling with failable contenders, consumed input
threaded as positional values so restoration is structural (the
contrast with Effekt's allocation-position rollback is the
argument); check the +1 ladder first-success → all-results →
bounded → heuristic order. W 3 as a breadth obligation: parsing
and search are rare-but-breaking. *(2026-07-10: the Raku comparison
round (`raku-grammars-comparison.md`, finding 3) — the third
independent arrival at the shape — handed the row structure:
ordered try-in-order choice (`||`) and best-match choice under a
tie law (`|`, longest-token matching — race's structural sibling)
are distinct constructs in the wild, not to be conflated;
commitment (ratcheting) is Raku's everyday mode, supporting the
threaded-values leaning (speculation as a bounded construct, not a
backtracking substrate); and the round added a scope item neither
prior sighting named — a failed parse must say what it expected
(Raku's FAILGOAL): error diagnosis belongs to the construct. Two
clash notes recorded there: rollback semantics chosen by a distant
declarator; tie laws whose inputs depend on where a spec stops
being declarative. Scores unchanged — prior-art structure, nothing
worked.)* *(2026-07-10, later: the XQuery/jq comparison
(`xquery-jq-comparison.md`, finding 9a) — the shipped *positive*
witness for the threaded-values leaning: jq is a nondeterministic
language (value streams, `empty` backtracks, `first`/`limit`
commit via a lexical label) with zero state-restoration machinery,
because an abandoned alternative is just an unconsumed value
stream. Caveat recorded so the row doesn't over-claim: jq owns no
consumed-input notion, so restoration-free abandonment comes free
there; the parsing case still has to thread positions. Clash note:
jq's `//` conflates flow-level absence with value-level falsiness
— unwritable under the value/flow wire sort, and jq's
documentation burden is the evidence for keeping the sorts.
Scores unchanged.)*

**Saturation: closure under rules — I 5, W 3.**
*(New row, 2026-07-10, from the Flix comparison round —
`flix-comparison.md`, finding 1.)* Compute the closure of a seed
set under derivation rules until nothing new appears — graph
reachability/cycles/ordering, dependency resolution, dataflow and
program analysis. One round of rule application is drawable today
(uncollects over fact sets, the shared-variable constraint as a
wire, a set collect); what nothing owns is the **feedback at the
flow level** — firings minting future firings, termination when
the set stops growing. Distinct from the register (value feedback
along a fixed walk) and from the divide flow (recursion over
virtual nested structure); dual to the served flow's recursive
provider (Effekt's build system — demand-driven top-down vs
saturation bottom-up), to be worked aware of each other. Two
scope items attached: the keyed-merge variant (lattice semantics =
keyed collect merging by a lawful operator; shortest-distance is
keyed-min-collect plus feedback — joint with the collect family's
operator-identity question) and **explanation as an output**
(Flix's provenance queries: why is this member in the closure —
witness firings, drawable; squarely the record's
drawable-witnesses and derivation-is-downward instincts surfacing
at runtime). The imperative encoding — frontier queue plus
seen-set — is the standing "assembly language" diagnosis in a
fourth costume. I 5: a name and a demand, nothing worked. W 3 as
a breadth obligation: absent from all three random surveys;
everyday clients are domain-concentrated (package/build/import
tooling, analysis, graph features); frequency question handed to
the evidence-owed list.

**Focused update: transform selected loci of a nested value —
I 5, W 3.**
*(New row, 2026-07-10, from the XQuery/jq comparison round —
`xquery-jq-comparison.md`, finding 7.)* Change part of a large
nested value, preserving everything else. Both shipped relatives
built major machinery for exactly this: half of jq is paths as
first-class values (every filter, in path context, denotes the
loci it selects; every assignment is defined by LHS-selected
paths; `walk`-family deep rewrites), and XQuery grew an entire
separate W3C facility (Update; `copy ... modify ... return`) to
say "a changed copy of this tree" at all. The hand-written form —
XQuery's identity-transform recursion, rebuilding every node to
change the few that match — is the standing assembly-language
diagnosis in a fifth costume. In drawn vocabulary: uncollect down
to the loci, transform there, re-collect upward with untouched
siblings passing through. Scope items attached: selection and
update sharing one vocabulary (jq's deepest design win — the
filter that reads a locus is the filter that writes it); paths as
drawable witnesses of loci (provenance adjacency, and jq's
paths-as-data programs show the reflective tier is everyday);
multi-locus as the primary case, not an extension; the
tree-rewrite connection to the trees row (jq's `walk` =
every-matching-node rewrite). I 5: a name and a demand, nothing
worked. W 3 with any move conditioned on evidence: the shape is
invisible to loop sampling by construction and this round's
corpora are domain-biased toward it; the frequency question (its
imperative costume — spread pyramids, builder copies, `setIn`/
lens libraries) is on the evidence-owed list. *(2026-07-10: the
APL-family comparison (`apl-family-comparison.md`, finding 7) —
the row's structure round, one round after it opened. BQN's
structural Under supplies the **commuting law** ((𝔾 of the
update) ≡ (compute after 𝔾), frame untouched), the
**well-formedness condition** (the selection must be structural —
loci fixed as data before the write-back; value-dependent
selection sanctioned only by materializing the mask first — jq's
paths-as-data rediscovered as a lawfulness requirement), the
**lens identification made by the shipped doc itself** (the
structural getter determines the setter), and the **derived-view
generalization** (update under reshape/transpose/reverse:
compute in a reversible re-presentation, write back). Dyalog's
indexed assignment adds the multi-locus **conflict rule**
("last-most is assigned" on repeated indices — the PUL
compatibility question's cousin), and BQN *removed* its Expand
primitive in favor of Under — a primitive-count dissolution
arguing the construct is load-bearing. I 5 / W 3 held: nothing
worked in our vocabulary, but the remaining list is now a
worked-round agenda.)* *(2026-07-10, later: the reactive
comparison (`reactive-comparison.md`, finding 2) — the reactive
costume: Redux's Immutable Update Patterns page teaches the
spread pyramid as a core skill (the imperative costume
institutionalized as documentation — feeds the frequency
condition without discharging it); Immer's draft-recording adds
**patches as data** (op/path/value with inverses;
fork-and-rebase) — the update's natural output is a delta stream;
Solid's path setters are multi-locus updates by index list,
range, or predicate. New coupling recorded: in a reactive
setting, **update loci are invalidation keys** — this row and the
incremental collections layer are two ends of one pipe. Scores
unchanged.)* *(2026-07-10, later: the tidyverse comparison
(`tidyverse-comparison.md`, finding 9) — the sixth witness, third
ecosystem, and the most law-abiding: purrr's `modify` family
(shape-preserving update of selected elements, rest untouched)
states the functor laws outright (`modify(x, identity) === x`;
composition), `modify_if`/`modify_at` select loci by predicate or
name, and `modify_in` writes at a pluck path — jq's paths, BQN's
Under, and purrr's modify now agree across three ecosystems.
tidyr's `hoist` supplies the read half (pluck paths selecting
*out* of depth). The frequency sample can add
`modify_at`/`modify_in` to its idiom list. Scores unchanged.)*

**Products: the table, zip, and the unexamined interactions —
I 3, W 4.**
*(Moved from Tier 3, 2026-07-10 — W 3 → 4 after the tidyverse
comparison round; row retitled from "the unexamined
interactions".)* Cross itself is worked
(`product-flows-design.md`); unexamined: n-ary products against a
concrete three-list example, join on a product (operand-walk
rules), registers over products (a fold demands an order a product
doesn't have), and the provenance product segment against the
walk-and-classify algorithm (questions 3–5, 8). Spec entry and
textual spelling are owed bookkeeping. *(2026-07-10: the APL-family
comparison (`apl-family-comparison.md`, finding 2) promoted **the
aligned product (zip)** from the translation exercise's "note, not
a demand" to a named demand on this row: the family's ground floor
is lockstep pairing (pervasion, blend, mesh, inner product), and
the showpiece audit localized the record's only real
representation struggle to it — Life needs Cross to enumerate the
neighborhood and zip to overlay it, at rank 2. The aligned product
is Cross's positional sibling (same extent paired by position vs
independent extents paired exhaustively); the compile already owns
a stream-level zip primitive, so the gap is authoring vocabulary.
The family's rank-2 evidence (2D windows, transpose-heavy idioms)
attaches to questions 3–5. Scalar extension recorded as
Incorporate's implicit costume — capability confirmed, implicitness
clashed.)* *(2026-07-10, later: the Zig comparison
(`zig-comparison.md`, finding 3) — the aligned product's second
shipped witness, from the imperative side and as the **primary
loop syntax**: multi-object `for (a, b) |x, y|` with the
length-equality side condition asserted at the barrier ("at the
start of the loop", not per element), and indices as one more
aligned lane (`for (items, 0..)` — the unbounded range takes its
extent from its siblings), which answers the translation
exercise's range-materializing note in the affirmative.)*
*(2026-07-10, later: the tidyverse comparison
(`tidyverse-comparison.md`, finding 1) — the round that raised W.
The data frame is the multi-wire flow **at rest**: k columns = k
value wires, n rows = n firings, alignment retained from common
provenance ("a data frame bundles together multiple vectors so
that everything is tracked together"). The row gains the aligned
product's **value form** as a named demand — the multi-wire
collect whose product is a table (k lists that remember they were
collected from the same walk) and whose uncollect returns the
wires; k sibling collects today forget they shared a walk. The
row-splat wart (`function(x, y, ...)`), dplyr's documented retreat
from purrr's map-arity matrix to table-native `rowwise`, and join
suffix collisions argue the open form is wires, not row-structs.
Small new data: per-edge alignment (`reduce2`'s length-(n−1)
second input — values aligned with the gaps between firings) and
the observed-product vs full-product distinction (tidyr's
`nesting()` inside `expand`). W 3 → 4: the row now owns tabular
data as a domain, not just lockstep pairing as an operation —
three consecutive rounds landed their central evidence here, and
an entire mainstream ecosystem is organized around the row's
missing value form. Honesty: a curated corpus; the move is about
the row's scope, and the owed field sample (real analysis
scripts) should confirm it.)*

## Tier 3 — worked areas with named residue (≈ 9–10)

**End-when: adoption and its open questions — I 2, W 5.**
The exploration round exists with leanings
(`end-when-design.md`; question 5 worked in place). Remaining: the
adoption conversation itself, the inclusive/exclusive bit's final
form (now with the tie-break interaction as an input), interrupt
unification, the register final-readout anchor (touches the
iteration-state round), the textual spelling. Low I is recent
work; W = 5 (the surveys' biggest unserved everyday demand) is
why the remaining distance is worth closing soon. *(2026-07-10:
first transcription evidence — the stop/discharge/split-on-tag
composition survived contact with the textual form and reads
well, with strawman spellings for the flow-op form, the bit, and
the terminator-only readout ready for the adoption conversation;
`translation-exercise.md`, B1/B2/C2 and finding 5.)* *(2026-07-10,
later: a small outside confirmation — Effekt's `while ... else`
(an on-normal-exit branch) and labeled break are the same readout
distinctions the terminator-discharge design already draws;
`effekt-comparison.md`, finding 6b.)* *(2026-07-10, later: the
XQuery/jq comparison (`xquery-jq-comparison.md`, findings 4, 9b)
— the strongest outside witness yet for the discriminated
terminator readout: a W3C windowing use case ends a window on a
three-reason disjunction (timeout / Barbara-in / Anton-out) and
must re-test in a `where` which reason fired — the side-flags
idiom survey 3 diagnosed, appearing in a standards document. Also:
XQuery's `count $rank where $rank <= 3` top-N filters without
stopping (the language has no end-when; termination is the
optimizer's mercy), while jq's `limit` genuinely aborts via
`label`/`break` — a drawn-ish lexical label. Scores unchanged.)*
*(2026-07-10, later: the reactive comparison
(`reactive-comparison.md`, finding 7) — XState's final states
("can no longer receive any events... can have `output` data,
which is sent to the parent machine") are the terminator-with-
payload discharge confirmed from the statechart side. Scores
unchanged.)* *(2026-07-10, later: the Zig comparison
(`zig-comparison.md`, finding 4) — the strongest syntax-level
confirmation yet: every Zig loop is an expression whose `break v`
/ `else d` pair is the discharge's Stopped/RanOut split
lane-for-lane, and a `while` over an error union gives `else`
the error payload — the failable source's terminator payload in
the wild. Labeled break across nesting is the readout targeting
an outer flow. Scores unchanged.)* *(2026-07-10, later: the
tidyverse comparison (`tidyverse-comparison.md`, finding 9) —
end-when's **value form**, shipped in a resolutely functional
interface: purrr's `done(out)` returned from inside a
`reduce`/`accumulate` step means "stop, this is the answer," bare
`done()` means "the previous accumulator was the answer" — early
exit composed with loop-carried state as a returned value, with
the inclusive/exclusive readout appearing as the wrapper's arity
(a datum for the bit and for the register's final-readout anchor
at once); in `accumulate` it truncates the emitted trajectory.
`detect`'s miss returning `NULL`/default is the option-shaped
discharge. Scores unchanged.)*

**Completion's contents — I 3, W 3.**
The time-travel machinery is settled; its *contents* are thin by
design — one canonical-table entry, one heuristic — and each
addition needs a worked program behind it. Versioning (a heuristic
change is a semantics change) and completion-diff UX are the
sharp residue (`time-travel-programs-design.md` questions 1–3).

**Transformation-levels: the undesigned operations — I 3, W 3.**
Cherry-pick replay, merge, and the content of an undo step are
each explicitly "undesigned"; the single-native-level assumption
is unfalsified but unproven — named there as the property to
verify before relying on the tower
(`transformation-levels-design.md`, "What is unresolved").
Principle 6 rests on this doc, so the residue is quiet but real.

**Streams: runtime residue and deferred passes — I 3, W 3.**
Shape C is the committed baseline; the consumer-set lattice is
deferred-but-committed (`lazy-stream-placement-design.md`, status
header — a misread-prone status, per the index). Design-side
residue: result-commute and the marker/IO commute variants await
their own runtime designs (`lazy-stream-commute-design.md`
question 2 and taxonomy), and the two `Delayed` footguns (pull
amplification, retention across a forced run) are named
constraints on any implementation.

**Incremental flows: the boundary and the collections layer —
I 3, W 3.**
The update-model destination is recorded (push-with-values inside
a necessity frontier; pure pull rejected long-term). Open: cutoff
semantics, `changes`'s stream kind (ties to async's event-source
retention question), `set`-as-effect, and incremental collections
— a large, separately-designed layer (`incremental-flow-design.md`
questions 2–6). *(2026-07-10: the reactive comparison round
(`reactive-comparison.md`) was this row's evidence round. The core
is confirmed point for point by the TC39 Signals proposal
(laziness, memoization, cutoff-with-`equals`, dynamic dependencies
= switch-join, pull-model glitch-freedom independently derived);
Elm removed reactive variables entirely (the register-centered
architecture that replaced them is drawable in existing
vocabulary — the round's §8). The **necessity frontier is the
genre's shipped shape**: watched/unwatched lifecycle hooks (TC39,
Preact), computed suspension (MobX), refCount (RxJS),
inactive-query GC — registration events at the frontier's edge,
exactly as the pending-pull derivation predicted; the interior
algorithm everywhere is **dirty/check/clean** two-grade staleness
(Reactively's coloring; TC39's ~dirty~/~checked~ states) — an
intermediate option between the rejected value-free dirty bit and
push-with-values, adequate at UI scale, recorded as such.
Liveness and memory are one frontier (watched-holds-alive; the
ecosystem's chronic undisposed-observer leaks are what no-bare-read
prevents). Flush-timing knobs (pre/post/sync/custom) are question
3's generation granularity as per-consumer API; cutoff surfaces as
a stream operator (`distinctUntilChanged`), per question 2's
prediction; staleness-as-policy (fresh-until, refetch-on-signal)
noted at the async boundary. Question 6 (collections) gains its
shipped shapes: keyed families of vars minted on demand
(atomFamily, observable.map's absent keys), per-key subscriptions
as the fan-out answer, hierarchical keys with prefix invalidation
(provenance's prefix rule in runtime clothes), update deltas as
data (Immer patches — the focused-update row's loci arriving as
this row's keys), and the `<For>`/`<Index>` identity-vs-position
fork as a semantic decision. Scores unchanged — evidence, not
design; the remaining list is much sharper.)*

**How values cross a barrier — I 2, W 4.**
*(Was I 4 — one question living in four homes — until the
2026-07-10 round, `barrier-value-crossing-design.md`: crossing
split into availability (provenance over the barrier's flow law;
no pass-through value ports anywhere) and minted ports, with a
co-location criterion for which mints share a node. The four
corners each answered with leanings: Join and the concurrent join
flow-only; race's per-contender (value, flow) pairs confirmed,
values-in; no multi-row partial collect — m rows are m sibling
collects at one context; the discharge one settled-sum port on
exactly-one kinds, the (prefix, terminator) pair on many kinds;
five dead ends recorded.)* Remaining: the adoption conversation,
the spec-side reconciliation (its Join's value ports re-read as
drawn availability), and the concurrent join × Cross unification
question it strengthened.

## Tier 4 — presentation and polish (≤ 7)

**The textual form's catch-up — I 3, W 2.**
The gather rule "needs the most careful specification"; spellings
are owed for Cross and end-when; history serialization is
sketched, not designed (`textual-representation-design.md`, open
questions). By design this doc tracks the representation, so most
of its debt clears as other areas land. *(2026-07-10: the
translation exercise turned "spellings owed" into a concrete
list, with strawmen for each (`translation-exercise.md`, findings
4–8): the late-wired-operand generalization of the write half
(`boundary of`, `value of` beside `step of` — the exercise's most
useful notation finding, jointly owned with
`first-class-ports-design.md`); the discharge readout's binder
convention and terminator-only form; the collect family's
spellings (keyed/set/last/any) jointly with the operator-identity
question; entry opens' two value ports; identity lanes. Scores
unchanged — the list is sharper, not shorter.)*

**Naming rounds — I 4, W 1.**
Deferred everywhere by tradition, correctly: they gate user-facing
text only. The members are ledgered in
`implementation-strategy.md`; one sweep should eventually take
them together (several docs note pairs that must be decided
jointly, e.g. "type" vocabulary with "time travel").

---

## Evidence owed

Survey rounds are not scored like design areas — evidence
*reweights* the scores above rather than carrying its own. The
named next rounds (`real-loop-survey.md`, "Next round (updated)";
method rules in `language-design-philosophy.md`):

- **A concurrency-focused sample** (server/async-heavy codebases)
  — would give inventory items 1–3 the frequency treatment items
  4–5 got, directly informing the concurrency row above. *(Done,
  2026-07-10 — survey 3 in `real-loop-survey.md`, sampling
  orchestration sites rather than loops. Its named successor: an
  application-level sample — survey 3's corpora implement
  concurrency infrastructure; how often application code reaches
  for gather vs race vs pool is still unmeasured.)*
- **UI/browser event-handling in JS** — still under-sampled after
  survey 2. *(2026-07-10: the Raku comparison round gave this
  sample a second question to carry — how much real event-handling
  is grammar-shaped (phase-sequenced recognition with state:
  gestures, framing) versus independent-handler-shaped; it would
  also supply or deny the custom-protocol-flows probation its
  second demand; `raku-grammars-comparison.md`, finding 2.)*
  *(2026-07-10, later: the reactive comparison round added the
  statechart-shaped question — an entire library category
  (XState: guards, state-gated events, final states with output)
  exists because reactive cores lack protocol vocabulary, and Elm
  re-derives the same structure as the Model-union idiom with
  model-dependent subscription sets; the probation's second
  demand now has category-strength documentation behind it, and
  this sample is what can convert that into the field sighting
  the probation requires; `reactive-comparison.md`, finding 7.)*
  *(2026-07-10, later: the Zig comparison added the shape's first
  field sighting anywhere — labeled switch (`continue :state
  .next`, added in 0.14 with the stated virtue that state
  transitions become "unambiguous, explicit, and immediately
  understandable") shipping in Zig's own production tokenizer —
  a systems-language sighting, not yet the UI-population one this
  sample is for; the probation re-read belongs to its owning
  doc; `zig-comparison.md`, finding 5.)*
- **A combinator census**, and larger n where a proportion
  becomes load-bearing.
- **The saturation frequency question** *(2026-07-10, from the Flix
  comparison round)* — closure-shaped computation was absent from
  all three random surveys; a domain sample (package/build/import
  tooling, program-analysis code, graph features inside
  applications) would measure how often the shape occurs in the
  wild and in what costume (hand-rolled worklists, embedded query
  engines, union-find), informing the new saturation row's W. The
  same sample can carry the functions row's condition: does real
  application code swap providers (test doubles, middleware), or
  is that architecture confined to languages that make it cheap?
- **The focused-update frequency question** *(2026-07-10, from the
  XQuery/jq comparison round)* — the shape (change selected loci
  of a nested value, preserve the rest) is invisible to loop
  sampling by construction, and the round's corpora are
  document-domain-biased toward it; a sample of application code's
  nested-immutable-update idioms (spread pyramids, builder copies,
  `setIn`/lens libraries, reducer bodies) would measure how often
  it occurs outside document processing, informing the new row's
  W.

The standing method is to be used proactively: when any row above
is worked and its round starts assuming importance rather than
measuring it, sample first.

---

## Assessment log

Reassess and append here whenever a row's area is worked; keep
entries to one line per change, dated, with the score movement and
the reason.

- **2026-07-09** — first assessment, all rows, against the record
  as of the end-when round (and its worked question 5).
- **2026-07-09** (later) — variable-rate consumption / running view:
  I 5 → 3 (exploration round written,
  `variable-rate-consumption-design.md`; split-when + the
  derived-state-port running view; breadth items 1, 2, 4 worked),
  W 4 unchanged; product 20 → 12, moved Tier 1 → Tier 2. The
  adoption conversation and the merge's own round remain.
- **2026-07-10** — concurrency constructs: evidence landed (survey
  3, `real-loop-survey.md` — thirty orchestration sites), scores
  unchanged at I 4 / W 4; within-area ranking sharpened (race
  barrier round first; `bounded(n)`-as-resource confirmed). IO,
  effects, and cancellation: scores unchanged at I 4 / W 5; the
  cancellation half of W is now measured (~8 of 30 sites), not only
  argued.
- **2026-07-10** (later) — how values cross a barrier: I 4 → 2
  (round written, `barrier-value-crossing-design.md`; availability
  vs minted ports, the co-location criterion, all four corners
  answered with leanings), W 4 unchanged; product 16 → 8, moved
  Tier 2 → Tier 3. The adoption conversation and the spec
  reconciliation remain; the race barrier's own semantics round
  (concurrency row) is unblocked at its port corner but otherwise
  still owed.
- **2026-07-10** (later still) — concurrency constructs: I 4 → 3
  (the area's lead item worked — `race-barrier-design.md`, the
  race barrier's semantics round; async question 7 answered by
  relocation; end-when's unification conjecture gets its
  mechanics-side answer), W 4 unchanged; product 16 → 12, stays
  Tier 2. Remaining in the row: the concurrent collect's own
  round (lifecycle outputs, `bounded(n)`), the served flow, the
  chooser family (now also owning merge fairness), and the
  server-program question.
- **2026-07-10** (later still) — translation exercise run
  (`translation-exercise.md`: thirteen sampled loops transcribed
  into the textual form). Scores unchanged everywhere — the round
  produced pressure and content, not designs. IO/effects (Tier 1):
  everyday failure mode identified (per-firing effects
  unwritable; bodies-raise). Concurrency (Tier 2): source openers
  and the pacing hole added to the remaining list. End-when
  (Tier 3): first transcription evidence plus strawman spellings.
  Textual catch-up (Tier 4): owed-spellings list made concrete,
  led by the late-wired-operand generalization. New small
  candidates with pressure: window(k) (strongest evidence yet),
  the collect family's joint spelling-and-identity round, entry
  opens, zip (a note, not a demand).
- **2026-07-10** (later still) — loop-carried state: I 4 → 3 (the
  row's named most-promising step worked — the Delay/latent
  equivalence proven at result level, with the feedback collect
  pinned as the write half; `iteration-with-state-design.md`, "The
  equivalence, worked"), W 5 unchanged; product 20 → 15, moved
  Tier 1 → Tier 2 and renamed "the candidate decision" → "the
  surface decision." The decision conversation remains, reframed
  as a surface choice; operator identities and the self-driven
  source opener (shared with the concurrency row) remain.
- **2026-07-10** (later still) — first learning-from-other-languages
  round (`effekt-comparison.md`: Effekt's nine case studies + tour,
  read against the record; a curated-corpus evidence genre — biases
  stated in the doc, frequencies mean nothing). One new row:
  speculation — ordered alternatives with rollback, I 4 / W 3,
  Tier 2 (two corpus sightings joining breadth item 6; pieces in
  race/failability/chooser/registers, no owner). Functions, reuse,
  and facets: W 3 → 4 (late-bound operations and the test double —
  the record has no answer to "run a diagram against fake IO";
  product 12 → 16, stays Tier 2). Concurrency row: served flow
  gains the recursive provider + keyed cache demands. IO/effects
  (Tier 1) and end-when (Tier 3): confirmation notes only.
- **2026-07-10** (later still) — facets: intuitions recorded
  (`facets-design-notes.md`, from the design conversation prompted
  by the test-double finding — authorable/attachable facets, holes
  without breaking, negative constraints, views-not-verification).
  Functions/reuse/facets row scores unchanged at I 4 / W 4:
  nothing worked, but the facets half moved from a name in an
  addendum to a statement of intent with named open edges, and the
  row now carries the leaning for its first round (one
  manifestation — the algebra facet + test double).
- **2026-07-10** (later still) — second learning-from-other-languages
  round (`raku-grammars-comparison.md`: Raku's grammar/regex
  documentation read against the record — a documentation corpus,
  one step more curated than Effekt's examples; no field sightings,
  structure only). No score movement anywhere; four rows gain dated
  notes: variable-rate consumption (the grammar ladder — the
  phase-sequence rung unowned, question 3's deterministic/trial
  fork, a confirmation sweep for split-when's destination
  enumeration and catalog question), speculation (two choice
  constructs, commitment-as-default, error diagnosis added to the
  round's scope), recursion/divide flow (parsing as the everyday
  client of recursion-over-virtual-structure), functions/reuse/
  facets (late-bound operations' second witness; extensible
  alternation added with its viewability tension). Evidence owed:
  the UI/browser sample gains the grammar-shaped-vs-handler-shaped
  question.
- **2026-07-10** (later still) — third learning-from-other-languages
  round (`flix-comparison.md`: the Flix example suite, ~190
  programs, read against the record — a curated corpus with mixed
  levels; the three small apps noted as the genre's most field-like
  sightings so far, still not random-sample evidence). One new row:
  saturation — closure under rules, I 5 / W 3, Tier 2 (flow-level
  feedback unowned; keyed-merge and provenance-explanation scope
  items attached; dual to the served flow's recursive provider).
  Functions/reuse/facets: remaining list gains the policy layer
  (middleware) and the decorated tree; late-bound operations + test
  double gain their third and strongest witness; W held at 4 with
  the move to 5 conditioned on the owed application-level sample.
  Concurrency: dated note (default-arm/poll to the race round;
  scope-bound spawn; third source-opener witness; fourth pacing
  sighting). Checking: dated note (restrictable variants as
  recursive-shapes prior art; purity demands; `@Terminates`).
  Loop-carried state: operator-identities sightings cluster.
  IO/effects (Tier 1): confirmation note only. Evidence owed: the
  saturation frequency question added.
- **2026-07-10** (later still) — fourth learning-from-other-languages
  round (`xquery-jq-comparison.md`: XQuery's FLWOR/window/group-by
  machinery, use cases, and Update Facility, plus jq's manual and
  community cookbook — the family's two shipped relatives; the
  reading-rule flip for close relatives recorded: the risk is
  mistaking familiarity for validation, so read hardest where they
  strain). One new row: focused update — transform selected loci
  of a nested value, preserving the rest — I 5 / W 3, Tier 2
  (paths-as-values and a whole W3C facility as the two shipped
  answers; the identity-transform recursion as the assembly
  language; frequency sample owed). IO/effects (Tier 1): first
  *structural* prior art — the pending update list (effects as
  collected values, applied at a snapshot barrier). Variable-rate:
  the window-clause sweep (neighborhood bindings on question 1;
  the new unterminated-final-segment bit; gap-tolerant
  segmentation; window(k) located in the family; question 4's
  form); event recognition matches the grammar ladder. Loop-carried
  state: `foreach` as the shipped running view; the keyed collect's
  primary/derived fork (group-as-flows vs operator-merge).
  Concurrency: fifth source-opener witness. End-when: the
  side-flags witness in a spec. Speculation: the shipped
  threaded-values witness. Core confirmations recorded in the doc
  (the tuple stream as barriers-not-bottlenecks; implicit
  flattening as the anti-lesson for explicit join). Scores
  unchanged everywhere except the new row.
- **2026-07-10** (later still) — fifth learning-from-other-languages
  round (`apl-family-comparison.md`: FinnAPL's 707 idioms, Dyalog
  reference pages and notebooks, BQN's argued docs and BQNcrate,
  J fragments — read under a stated brief: no higher-order
  surface; the round hunts example programs the drawn vocabulary
  struggles with). No new row; no score movement. The
  operator-catalog audit maps the family's second-order layer
  item-for-item onto the record's first-order constructs
  (validating the brief), with the higher-order residue filed on
  the functions row. Products row: **aligned product (zip)**
  promoted from note to demand — the round's one localized
  representation struggle (Life needs Cross and zip at once, at
  rank 2). Focused update: the structure round (Under's commuting
  law, the structural-selection condition, the lens
  identification, derived-view updates, the conflict rule, the
  Expand dissolution). Variable-rate: window(k)'s shipped design
  space (step, edge handling, 2D) and the segmented-scan
  assembly-language exhibit. Loop-carried state: the identity
  catalog and the empty-collect framing; keyed collect's order/
  decomposition/partiality round. Idiom-library epistemology
  recorded: 707 maintained phrases prove the demands and price
  the encoding.
- **2026-07-10** (later still) — sixth learning-from-other-languages
  round (`reactive-comparison.md`: Elm and the JS state libraries —
  TC39 Signals, MobX, Solid, Vue, Preact, Reactively, RxJS, Redux/
  Immer, XState, React Query, Recoil — run against a stated brief:
  the monad-like reactive-variable core is already the incremental
  flow (verified: TC39 matches the row point for point; Elm
  removed signals), with seven boundary questions as the round's
  schedule). No new row; no score movement. Incremental flows: the
  evidence round (necessity frontier as the genre's shipped shape;
  watched/unwatched hooks as the derived registration events;
  dirty/check/clean as the intermediate algorithm; collections
  layer's shipped shapes — keyed var families, per-key
  subscription, prefix invalidation, deltas, the
  identity-vs-position fork). IO/effects: the TC39 punt as
  standards-level acknowledgment; Elm `Cmd` as second
  effects-as-data witness; two drawable output poles; ordering
  disclaimers as the IO thread's mirror. Focused update: the
  reactive costume plus the loci-are-invalidation-keys coupling.
  Concurrency: the flattening strategies as the shipped
  concurrency menu, exhaustMap as a new species, pacing sighting
  six, React Query as served-flow furniture. Functions: policy
  layer's second furniture witness. End-when: final-states
  discharge confirmation. Evidence owed: the UI sample gains the
  statechart-shaped question (custom-protocol-flows' second
  demand at category strength, awaiting its field sighting).
  Clash record led by auto-tracking (dependency graphs inferred
  from execution traces — the invisible wire at ecosystem scale,
  with its documented footgun bill).
- **2026-07-10** (later still) — seventh learning-from-other-languages
  round (`zig-comparison.md`: the Zig language reference read at
  source plus the stdlib as field code — tokenizer, mem iterators
  and window, the new `std.Io`, FailingAllocator — run under a
  stated brief: Zig is the imperative mainstream's deliberate
  redesign of C's control flow, so each modification is read as a
  field-tested claim about where raw imperative control flow
  fails, checked against the record's constructs). No new row; no
  score movement. Central confirmation: Zig's redesigned loop
  headers decompose into exactly the record's constructs — the
  `while` header is (end-when, register write half) pulled out of
  the body; `break v`/`else d` is the discharge's readout split
  shipped as expression syntax. IO/effects (Tier 1): the
  bracket/cancellation half's structural prior art
  (defer/errdefer's four properties; cancel-as-await; group
  propagation). Failability: both flagged residues gain field
  answers (try; error-set algebra). Concurrency: source-opener
  priority correction (the imperative ground floor; seventh
  witness), asynchrony-as-possibility vs failable concurrency
  claim, the select-union note. Functions: fourth late-bound
  witness (ordinary parameters), fault injection on the test
  double, policy layer's third witness. Products: zip's second
  shipped witness as primary loop syntax. Custom-protocol-flows
  probation: third arrival and first field sighting (labeled
  switch in the production tokenizer, 13% besides) — noted on the
  evidence-owed UI sample, decision left with the owning doc.
  Clash record led by visibility-by-prohibition vs by-drawing
  (same Zen, opposite mechanism).
- **2026-07-10** (later still) — eighth learning-from-other-languages
  round (`tidyverse-comparison.md`: dplyr/tidyr/purrr vignettes
  plus purrr's reference examples, read under the stated question
  "is a table more than a list of structs?" — a curated showcase
  corpus with inverted ergonomics (R is column-major), late-added
  constructs read as field reports). No new row — tabular data
  deliberately dissolves onto existing rows, which is the round's
  strongest result. **Products: W 3 → 4, product 9 → 12, moved
  Tier 3 → Tier 2, retitled** "the table, zip, and the unexamined
  interactions" — the data frame is the multi-wire flow at rest;
  the aligned product gains its value form as a named demand (the
  multi-wire collect/uncollect; k lists that remember they were
  collected from the same walk), plus per-edge alignment and the
  observed-product datum; the move is about the row's scope, with
  the field sample owed. Loop-carried state (keyed collect): the
  readout family (collapse / pass-through / flatMap / whole-lane),
  the broadcast-back composite with its group-as-value corollary,
  the keyed-index consumption pattern, pivot_wider located as the
  keyed collect. End-when: `done()` as the value-form witness.
  Focused update: sixth witness (modify family, functor laws
  stated). Variable-rate: fourth-ecosystem split-when
  assembly-language sighting (cumsum key synthesis).
  Functions/reuse: the authoring-gesture demand (across over
  static schema). Clash record led by ambient magic names and
  grouping as a mode bit, with purrr's recycling/typed-suffix
  tightenings recorded as a shipped correction toward the barrier
  law and wire sorts.
