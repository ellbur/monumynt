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
constraints here that block their own completion.

**Loop-carried state: the candidate decision — I 4, W 5.**
The record's self-declared biggest open area
(`iteration-with-state-design.md`; reader's guide at the top). Two
live candidates deliberately side by side, but the latent form's
feedback collect has "no pinned concrete form," the Delay/latent
equivalence is unproven (named there as the most promising next
step), the visible state thread is a conjecture, and operator
identities for reduce-close are unattached (three hand-rolled
monoid folds in the surveys press on this). W = 5: ~23% of
sampled loops carry state, dominant in numerics;
`implementation-strategy.md` flags the substrate choice as its
single riskiest proposal. Companions:
`first-class-ports-design.md` (the Delay pair),
`iteration-rails-design-notes.md`.

## Tier 2 — big areas with partial designs (≈ 12–16)

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

**The concurrency constructs — I 4, W 4.**
Concurrent collect (inventory item 1; its species menu partly
dissolved into wiring, but `bounded(n)` resists), the served flow
(item 2), the race barrier's own semantics round (owed per
`async-flow-design.md` question 5), fairness, and "what is a
program for a server?" (`tough-use-cases-design.md` question 7).
Demanded by three of the five tough use cases; nothing worked
end-to-end. The event-loop breadth item (7) is this area's
acceptance test in miniature. Evidence is also thin — see the
evidence section below.

**How values cross a barrier — I 4, W 4.**
One question living in four homes, which the docs themselves say
to decide together: `partial-collect-design.md` question 3
(multi-row value correspondence), `first-class-ports-design.md`
question 3 (Join value pass-through ports), race's per-contender
outputs, and the discharging collect's port structure
(`async-flow-design.md`). The no-bottlenecks principle rides on
the answer; deciding it in one place unblocks a corner of each of
those designs.

**Failability's residue — I 3, W 4.**
The core is worked (terminator payloads, propagate-by-default,
discharge at a whole-flow collect — `async-flow-design.md`), but
payload-type composition is unexamined, "do bodies raise?" is
flagged genuinely open, the discharging collect's ports fold into
the barrier question above, and the option/async convergence is
sharpened but undecided. End-when's readout composition leans
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

**Functions, reuse, and facets — I 4, W 3.**
Also narrative-stage: the function boundary (flow skeleton with
data holes, `functions-design.md`), its conjectured relationship
to summaries-as-generalized-programs (`types-design.md` read-out
2), completion's boundary residue
(`time-travel-programs-design.md` question 5), and facets
(recorded in `tough-use-cases-design.md`'s addenda as "too big a
topic to explore now"). A useful language eventually needs reuse;
the deferral is deliberate but should not become permanent by
inertia.

## Tier 3 — worked areas with named residue (≈ 9–10)

**End-when: adoption and its open questions — I 2, W 5.**
The exploration round exists with leanings
(`end-when-design.md`; question 5 worked in place). Remaining: the
adoption conversation itself, the inclusive/exclusive bit's final
form (now with the tie-break interaction as an input), interrupt
unification, the register final-readout anchor (touches the
iteration-state round), the textual spelling. Low I is recent
work; W = 5 (the surveys' biggest unserved everyday demand) is
why the remaining distance is worth closing soon.

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
of its debt clears as other areas land.

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
  4–5 got, directly informing the concurrency row above.
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
