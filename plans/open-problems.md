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

**IO, effects, and cancellation — I 4, W 5.**
The record's most-cited hole: no IO design and no cancellation design.
Two halves. *Effects:* per-firing effects are currently unwritable
(you cannot transcribe `task.cancel()` in a loop); effect *ordering
within a firing* is a breadth item (the conditional-flush buffer) with
only raw material (`custom-flows.md`'s lifecycle pattern), not a
design; bodies-raise / lightweight failure is the second concrete
demand. *Cancellation:* load-bearing — bracket's
release-on-abandonment, race-implies-cancel, and abandoned pending
pulls all arrive at it.

W = 5 because ~42% of sampled loops exist to cause effects, and both
`async-flow-design.md` (question 2) and `incremental-flow-design.md`
(effect-free tracking contexts) defer constraints here that block
their own completion. The cancellation half is measured, not only
argued: roughly eight of thirty orchestration sites touch
cancellation/abandonment/retention, containing the sample's most
delicate code (`real-loop-survey.md`, survey 3).

Prior art supplies structure, not a design. XQuery's Update Facility
reifies per-firing effects as a **pending update list** — effects
gathered by ordinary evaluation, applied atomically at a snapshot
barrier, conflicts resolved by declared rules (the
effects-as-collected-plan pole; its strain points — no
read-your-writes inside the snapshot, conflict rules where
within-firing ordering resurfaces — map onto breadth item 5). jq marks
the same pole degenerately (effects only at pipeline edges). Elm's
`Cmd` is a second effects-as-collected-values witness (the loop closed
through ordinary events re-entering as `Msg`s), and the TC39 Signals
proposal ships *no* effect construct at all, stopping exactly at this
row. For the cancellation half, Zig's `defer`/`errdefer` supply four
properties any bracket design should reproduce: release written
adjacent to acquisition (a late-wired release half on the acquiring
node, fired at the owning flow's discharge), cleanup keyed by exit
reason (per-terminator-lane release), the infallibility asymmetry
(allocation may fail, deallocation must succeed), and per-firing as
well as per-flow attachment; plus `std.Io` cancellation (`Future.cancel`
discharges a readable terminator; group wait propagates cancellation).
Every Effekt and Flix case study interleaves effects mid-computation —
the hole gates ordinary programs, not just effect-heavy ones. See
`translation-exercise.md`, `effekt-comparison.md`, `flix-comparison.md`,
`xquery-jq-comparison.md`, `reactive-comparison.md`, `zig-comparison.md`.

## Tier 2 — big areas with partial designs (≈ 12–16)

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
availability ladder — monoid → total, semigroup → option-shaped,
neither → augment — identities as catalog rows carrying the identity
value as witness, user monoids minted via the algebra facet, the named
collects dissolved into catalog rows, the keyed partition worked as the
primary construct with its four readouts as consumption). New residue: the
**Delay ontology** — what a Delay *is* and which flow its "next iteration"
binds to (`iteration-with-state-design.md`, "What a Delay is": a delayed
computation bound by its collect, not a flow-wire tap nor an
ancestor-uncollect reference; the choice selects behaviour where a commute
or a product's axes puts more than one flow in reach; open sub-questions —
whether "delayed computation" is the right notion, whether a specified
third flow can bind it, which kinds even have a "next iteration"). The
row's center, the surface decision, is untouched by all of these.

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
`first-class-ports-design.md` (the Delay pair),
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
fourth-ecosystem scan costume. See `raku-grammars-comparison.md`,
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
the retry composite's floor on paper); and the concurrent collect
(`concurrent-collect-design.md` — the species menu fully dissolved:
serial = the nested drawing, keyed = the keyed partition instantiated,
unbounded = one primitive "settle" node minting the **completions
flow** in settlement order, its settled result a per-firing discharged
sum with no main-result port, a drain termination law, `bounded(n)`
split into a width expressible now and shared permits that are
bracket-shaped and fenced to Tier 1; six dead ends).

Remaining: the served flow (with its recursive-provider and
keyed-cache demands), the chooser family (also owning merge fairness),
the server-program question (`tough-use-cases-design.md` question 7),
and pacing's per-consumer/per-source bit under multi-close (joint with
end-when's coexistence question). Demanded by three of the five tough
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
`translation-exercise.md`, `effekt-comparison.md`, `flix-comparison.md`,
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

**Recursion: the divide flow and trees — I 4, W 3.**
`trees-and-recursion.md` is narrative-stage (no starting-point
document; flagged so in `implementation-strategy.md`). The divide flow
is a candidate primitive with an unworked termination story (a
non-list example — quadtree — is owed; `tough-use-cases-design.md`
question 4); whether tree iteration inherits the register discipline is
unresolved. Breadth item 9 (the recursive gather) is the field
sighting. Parsing is named as the everyday client of
recursion-over-virtual-structure (`raku-grammars-comparison.md`) — the
divide flow's worked examples so far are constructed, so recursive
descent (nested-delimiter parsing) is a candidate first program with
field precedent when the row's round runs.

**Functions, reuse, and facets — I 4, W 4.**
Narrative-stage: the function boundary (flow skeleton with data holes,
`functions-design.md`), its conjectured relationship to
summaries-as-generalized-programs (`types-design.md` read-out 2),
completion's boundary residue (`time-travel-programs-design.md`
question 5), and facets. A useful language eventually needs reuse; the
deferral is deliberate but should not become permanent by inertia.

The remaining list has grown concrete demands. **Late-bound
operations** — a diagram written against operations whose meaning is
wired in per use; the inside-out form is a request/response port pair
on the boundary, connecting to the served flow — and its everyday
face, **the test double** ("run a diagram that does IO against fake
IO"), which the record currently cannot answer at all. **Extensible
alternation** — extend a case vocabulary without editing its defining
site (Raku's proto regexes; the complete alternative set must stay
viewable somewhere, a facets-flavored derived view). **The policy
layer** — middleware (retry, circuit-break, throttle, sandbox,
atomicity, audit) interposed at the operation boundary; in the row's
leaning, a sub-diagram spliced into the provider wiring, stack order
visible as nesting. **The decorated tree** — one tree, stacked
per-node decorations, consumers demanding only what they read. And an
**authoring gesture** — dplyr's `across` over a static schema is
k-fold repetition of drawn structure; the demand is one gesture
producing k readable nodes, not a runtime construct.

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
configuration on the test double. See `effekt-comparison.md`,
`facets-design-notes.md`, `raku-grammars-comparison.md`,
`flix-comparison.md`, `apl-family-comparison.md`, `reactive-comparison.md`,
`zig-comparison.md`, `tidyverse-comparison.md`, `collect-family-design.md`.

**Saturation: closure under rules — I 5, W 3.**
Compute the closure of a seed set under derivation rules until nothing
new appears — graph reachability/cycles/ordering, dependency
resolution, dataflow and program analysis. One round of rule
application is drawable today (uncollects over fact sets, the
shared-variable constraint as a wire, a set collect); what nothing owns
is the **feedback at the flow level** — firings minting future firings,
termination when the set stops growing. Distinct from the register
(value feedback along a fixed walk) and the divide flow (recursion over
virtual nested structure); dual to the served flow's recursive provider
(demand-driven top-down vs saturation bottom-up), to be worked aware of
each other.

Two scope items: the keyed-merge variant (lattice semantics = keyed
collect merging by a lawful operator; shortest-distance is
keyed-min-collect plus feedback — its algebraic footing is in
`collect-family-design.md`: the keyed collect by ⊕ is a monoid fold
with identity ∅, and lanes being non-empty by construction make
semigroup operators like min total per-lane, which is what
keyed-min-collect needs); and **explanation as an output** (Flix's
provenance queries: why is this member in the closure — witness
firings, drawable; the record's drawable-witnesses instinct surfacing
at runtime). The imperative encoding — frontier queue plus seen-set —
is the standing assembly-language diagnosis in another costume. I = 5:
a name and a demand, nothing worked. W = 3 as a breadth obligation:
absent from all three random surveys; everyday clients are
domain-concentrated (package/build/import tooling, analysis, graph
features); the frequency question is on the evidence-owed list. See
`flix-comparison.md`, `collect-family-design.md`.

**Focused update: transform selected loci of a nested value —
I 5, W 3.**
Change part of a large nested value, preserving everything else. In
drawn vocabulary: uncollect down to the loci, transform there,
re-collect upward with untouched siblings passing through. The
hand-written form — an identity-transform recursion rebuilding every
node to change the few that match — is the standing assembly-language
diagnosis in another costume.

Both shipped relatives built major machinery for exactly this: half of
jq is paths as first-class values (every filter in path context
denotes the loci it selects; every assignment is defined by
LHS-selected paths; `walk`-family deep rewrites), and XQuery grew an
entire separate W3C facility (Update; `copy … modify … return`). Scope
items: selection and update sharing one vocabulary (jq's deepest design
win — the filter that reads a locus is the filter that writes it);
paths as drawable witnesses of loci; multi-locus as the primary case,
not an extension; the tree-rewrite connection to the trees row (jq's
`walk`).

The structure round is done (APL/BQN Under): the **commuting law**
((𝔾 of the update) ≡ compute-after-𝔾, frame untouched), the
**well-formedness condition** (the selection must be structural — loci
fixed as data before write-back; value-dependent selection sanctioned
only by materializing the mask first, jq's paths-as-data rediscovered
as a lawfulness requirement), the **lens identification** (the
structural getter determines the setter), the **derived-view
generalization** (update under reshape/transpose/reverse), and the
multi-locus **conflict rule** (Dyalog's "last-most is assigned").
BQN *removed* its Expand primitive in favor of Under — a
primitive-count dissolution arguing the construct is load-bearing.
I = 5: nothing worked in our vocabulary, but the remaining list is a
worked-round agenda. W = 3, any move conditioned on evidence: the shape
is invisible to loop sampling by construction and this round's corpora
are domain-biased toward it; the frequency question (spread pyramids,
builder copies, `setIn`/lens libraries) is on the evidence-owed list.
Reactive costume: Redux's spread-pyramid docs (the imperative costume
institutionalized), Immer's patches-as-data (the update's natural
output is a delta stream), Solid's path setters — and the coupling that
update loci are invalidation keys, making this row and the incremental
collections layer two ends of one pipe. purrr's `modify` family states
the functor laws outright — jq's paths, BQN's Under, and purrr's modify
agree across three ecosystems. See `xquery-jq-comparison.md`,
`apl-family-comparison.md`, `reactive-comparison.md`, `tidyverse-comparison.md`.

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
question 4. The round's real lesson was about **Delay**, not the product —
the axis comes from the binding collect, not a Delay-side name — feeding the
loop-carried-state row's new Delay-ontology residue. Unexamined: join on a product (operand-walk rules, question 4); the
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
- **A combinator census** — *done* (`real-loop-survey.md`, "Combinator
  census"): counting every loop and combinator across the survey-1
  corpora, combinators are ~1/3 of iteration constructs (statement
  loops outnumber them ~2:1 even in Ruby/JS), split collect 76% /
  search 18% / fold 6%; finding 1's "well above half needs no state"
  holds as a ~60% majority, carried mostly by stateless statement
  loops rather than the excluded combinators. Larger n where a
  proportion becomes load-bearing still owed.
- **The saturation frequency question.** Closure-shaped computation was
  absent from all three random surveys; a domain sample (package/build/
  import tooling, program-analysis code, graph features inside
  applications) would measure how often the shape occurs and in what
  costume (hand-rolled worklists, embedded query engines, union-find),
  informing the saturation row's W. The same sample can carry the
  functions row's condition: does real application code swap providers?
- **The focused-update frequency question.** The shape is invisible to
  loop sampling by construction, and its comparison corpora are
  document-domain-biased toward it; a sample of application code's
  nested-immutable-update idioms (spread pyramids, builder copies,
  `setIn`/lens libraries, reducer bodies) would measure how often it
  occurs outside document processing, informing that row's W.

The standing method is to be used proactively: when any row above is
worked and its round starts assuming importance rather than measuring
it, sample first.
</content>
