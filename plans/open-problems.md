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
movement, the row already carries W 5.)*

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
round, Tier 4). W = 5 unchanged: ~23% of sampled loops carry
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
has only its chooser sketch (tough doc item 4).

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
opener blocks the canonical beginner generator.)*

**Failability's residue — I 3, W 4.**
The core is worked (terminator payloads, propagate-by-default,
discharge at a whole-flow collect — `async-flow-design.md`), but
payload-type composition is unexamined, "do bodies raise?" is
flagged genuinely open, the discharging collect's ports fold into
the barrier-crossing row (Tier 3 — now worked with leanings), and
the option/async convergence is sharpened but undecided. End-when's readout composition leans
entirely on discharge, so adoption pressure now arrives from the
everyday side too.

**Checking: the deferred design rounds — I 3, W 4.**
The stance is settled (demands/offers, no search, drawable
witnesses — `types-design.md`; paths and clash flavors —
`bundle-provenance-design.md`); implementation is
workstream D. The *design-side* gaps: recursive shapes (its
question 2, waiting on the tree constructs), slots/higher-order
signatures (question 3), the catalog schema and its trusted JS
edge (question 4), equality's fine print (question 8).

**Recursion: the divide flow and trees — I 4, W 3.**
`trees-and-recursion.md` is narrative-stage (no starting-point
document; flagged so in `implementation-strategy.md`); the divide
flow is a candidate primitive with an unworked termination story
(a non-list example — quadtree — is owed;
`tough-use-cases-design.md` question 4); whether tree iteration
inherits the register discipline is unresolved. Breadth item 9
(the recursive gather) is the field sighting.

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
than exotic.)*

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
and search are rare-but-breaking.

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
`effekt-comparison.md`, finding 6b.)*

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
questions 2–6).

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

**Products: the unexamined interactions — I 3, W 3.**
Cross itself is worked (`product-flows-design.md`); unexamined:
n-ary products against a concrete three-list example, join on a
product (operand-walk rules), registers over products (a fold
demands an order a product doesn't have), and the provenance
product segment against the walk-and-classify algorithm
(questions 3–5, 8). Spec entry and textual spelling are owed
bookkeeping.

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
  survey 2.
- **A combinator census**, and larger n where a proportion
  becomes load-bearing.

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
