# The Race Barrier

> Exploration round (2026-07-10) — **leanings, not an adopted
> design**, prepared for the design conversation. The subject is
> the round `async-flow-design.md`'s open question 5 has owed
> since the barrier form was adopted: race's semantics beyond its
> ports — the barrier's law, ties, reconvergence, arity,
> abandonment, fairness, and the combinators derived from it
> (merge, interrupt, the timeout family). The port/crossing
> corner is *not* re-worked here: values-in, per-contender
> minted (value, flow) pairs, one node, is taken as worked from
> `barrier-value-crossing-design.md` and only cited. Demand is
> fresh and measured: the concurrency survey
> (`real-loop-survey.md`, survey 3, findings 3.1–3.2) found
> first-of coordination outweighing all-of nine-to-one in thirty
> random orchestration sites, with every hand-rolled race
> reconstructing "who won" from side flags — on that evidence the
> race round leads the concurrency area
> (`open-problems.md`, Tier 2). Method: state the law precisely,
> then walk the questions the record has filed against it,
> answering each from the law plus the principles, with the
> survey's sites as the contact evidence. Nothing here is
> implemented; the async runtime it presumes does not exist yet.
>
> Terminology: **uncollect/collect** per the 2026-07-07
> correction; **cell**, **bundle**, **covering/partial collect**
> as in `partial-collect-design.md`; **the async cell**,
> **settlement**, **start is synchronous**, and **abandonment ≠
> cancellation** as in `async-flow-design.md`; **mint** and
> **availability** as in `barrier-value-crossing-design.md`.

## What is owed, gathered

The record's open items against race, each taken up below:

| Where filed | The item |
|---|---|
| `async-flow-design.md`, question 5 | "The barrier's own design round still owes its semantics" — the representation blocker dissolved, nothing else did. |
| `async-flow-design.md`, question 7 | Fairness and starvation, especially under merge. |
| `async-flow-design.md`, question 8 | Naming (race vs select; interrupt vs until) — stays deferred, per tradition. |
| `barrier-value-crossing-design.md`, question 4 | "Fairness, N-ary composition, abandonment/cancellation interplay, and merge/interrupt as derived combinators — still owed." |
| `partial-collect-design.md`, "Every bundle merges" | Subset merges over the race bundle sanctioned ("either cache or replica — take whichever") but never worked against the async kind's unobservable zero case. |
| `end-when-design.md`, "Sibling or same node" | The unification conjecture — one terminator-writing node with aligned/unaligned stop — deliberately untaken, with the deciding test stated. This round supplies the mechanics-side half of that test. |
| Survey 3, findings 3.1–3.2, 3.6 | The field demand: timeout is the dominant guise; discrimination is always rebuilt from side state; cancellation-adjacent sites are the sample's most delicate code. |

## The law of the barrier

The async doc asserted the shape; here it is stated as a law,
with the edges pinned.

**Form.** Race takes N contenders, N ≥ 1, each an async
**value** (values-in — race is the sum-side multi-input
uncollect; the case-split precedent and the full argument are in
the crossing round, dead end 3 there). Out comes a **bundle of N
cells**: cell i fires iff contender i won, carrying contender
i's resolved value as its minted per-cell output.

**Starting.** Forcing any collect over the bundle starts all N
contenders — synchronously, in drawn order, before the first
await (`async-flow-design.md`, "start is synchronous"). Start
order is therefore determinate and drawn. For pure contenders it
is unobservable; once effects exist it is observable timing, the
same caveat the commute round recorded for start-all — noted, not
resolved here.

**Settlement.** The race settles at the first settlement of any
contender. "First" is well-defined per schedule: the event loop
serialises settlements, so given a schedule there is exactly one
first (`async-flow-design.md`, determinism note). Across
schedules the winner is nondeterministic, and the language
promises nothing more — the bundle structure is the honest
representation of that nondeterminism.

**Ties.** One edge case is *not* schedule-dependent and should be
specified rather than left to fall out of the compile: contenders
**already settled when the race starts** (memoised cells resolve
at most once and stay resolved; a race wired to an
already-resolved cell is ordinary, not exotic — the survey's
lazily-minted milestone cells are often already-resolved at
observation, aiohttp 1). Among contenders settled before the
race's first await, **the lowest-numbered wins** — drawn order is
the tie-break. This costs nothing (it is what `Promise.race` over
the tagged wrappers does), it is deterministic, and it is
*drawn*: the reader can see the priority order on the canvas.
Contenders settling after the start are ordered by the loop, and
no tie is possible.

**Exactly once.** The race settles exactly once; exactly one cell
fires; the others never fire. Losers are not cancelled — their
in-flight work runs to completion into their memoised cells,
observable by any *other* consumer that independently forces
them, GC'd otherwise (the abandonment stance, unchanged; taken up
below).

**Failable contenders.** First *settlement* wins, including a
rejection; the winning cell's continuation is then a flow whose
terminator already fired, and propagation does the rest. Worked
in `async-flow-design.md` ("Race also composes cleanly"); cited,
not re-derived.

## The unary race is the async uncollect

A leaning this round adds, read directly off the law: set N = 1.
One contender; one cell; the cell fires iff the contender settles
first, which is always; the minted value is the resolution. That
is the async uncollect, port for port — one value port (the
resolved value), one flow port (the async context), body runs
after arrival.

So the lean: **the async open and the race barrier are one
construct at different arities.** Not a coincidence to admire but
a graceful-expansion rung to use:

- *Await a fetch*: async uncollect on `fetchD`, body on its value
  port. The beginner's drawing.
- *+ a timeout*: **add a second contender** — wire `timer(5s)`
  into the same uncollect. The existing body is now cell 1's
  body, untouched; cell 2 (timer won) gets its value. The collect
  that closed the body now closes the bundle.

The +1 step is an addition to the drawing — one wire and one alt
body — not a rewrite into a different construct. Compare the
field version of the same step: fastify 4 grows a handler-await
into a handler-timeout by adding an `AbortController`, a
`setTimeout`, a `reply.sent` flag check, and a paired
`clearTimeout` on a close listener. That distance is exactly what
the identification buys.

What would argue against the identification: the drawing might
want "awaiting" and "racing" to look different (a barrier line
with one contender is just an open — which is arguably the
point, not a problem); and the case-split/race analogy breaks at
N = 1 differently (a unary case split is a degenerate
re-tagging, a unary race is the ordinary open — the analogy is
between the N-ary forms, not the degenerate ones). Neither seems
disqualifying. Held as a leaning; decide with the spec entry.

(The option/async convergence — async question 6 — is untouched
by this: option's discriminator is data checked now, and no
arity generalisation changes that.)

## Reconvergence: the covering collect, and where subset merges land

The covering story is settled elsewhere and inherited whole: the
exhaustive close over all contenders is the covering partial
collect over the race bundle
(`partial-collect-design.md`, "Every bundle merges"); the
winner's value reaches the parent context through that node's
minted row; the output is an `async<Y>` because which cell fired
isn't known until settlement.

The *subset* merge is sanctioned there too ("either cache or
replica — take whichever; the full recompute is handled
separately") but was never checked against the async kind's own
table, and checking it yields this round's one genuinely new
derivation.

A partial collect over cells S ⊊ {1..N} mints a merged flow that
fires iff the winner is in S. As a flow that is **zero-or-one,
later** — and the failability table
(`async-flow-design.md`, "Failure as terminator payload") says
the bare version of that row is *unobservable*: an async that
never fires is indistinguishable, forever, from one that hasn't
fired yet. A consumer awaiting a bare subset merge whose race
settled elsewhere hangs for the life of the program. The bare
reading is a designed footgun.

But race is precisely the case where the table's own escape
clause applies: "a later-flow's zero case is only meaningful if
the termination is itself an event." Here the termination *is*
an event — the race's settlement decides every cell at once, so
"the winner is not in S" becomes true at a knowable moment. The
lean, then:

> **A subset partial collect over a race bundle is failable by
> construction.** Its merged output's terminator fires at the
> race's settlement when the winner is outside S, carrying the
> fact of settling-elsewhere as payload. The covering collect is
> the degenerate case whose terminator is unreachable — which is
> why the covering form reads as infallible with no special
> rule.

Payload contents, a sub-leaning: the *fact* (which cell won —
an index into the partition, a fact about the bundle), not the
winning *value*. Delivering contender j's value through a
collect that does not engage cell j would move a value across
cells the node never touched — the coarsening-only-at-the-
explicit-node discipline says engage the cell if you want its
value. The alternative (payload carries the winner's value too)
is convenient and dirty; recorded so the conversation can weigh
it.

Note the contrast that makes this specific to async: the same
subset merge over a case split *inside a list iteration* is
unremarkable — non-matching elements just don't fire, the walk
continues, the collect terminates with the walk. The failable
completion is the exactly-one-later kind's instantiation of the
partial collect, not a change to the partial collect in general.
The kind table stays in charge.

## Nested and flat

`race(a, race(b, c))` — the inner race covered into an
`async<_>`, then raced against `a` — was flagged in the original
question 5 as an artifact of the rejected alt-value form, with
N-ary-from-the-start as the fix. With the law stated, the
relationship can be pinned rather than waved at:

- **They are different programs.** The flat `race(a, b, c)` has
  three cells and delivers the b/c discrimination at the one
  barrier. The nested form has two cells at the outer barrier;
  the b/c discrimination lives at the inner covering collect,
  inside cell 2's continuation.
- **Their winners agree** (up to the microtask hops the compile
  inserts): the inner race settles at first-of(b, c), the outer
  at first-of(a, that) — the same contender wins either way,
  with drawn-order ties resolving compatibly (a before b before
  c in both).
- So flattening is a candidate **level-1 recognition**, never a
  need: N-ary drawing means nobody has to *write* the nested
  form to get the flat meaning, and if one arrives (built
  incrementally, or through a function boundary) recognising it
  is a derived-view question for the transformation-levels
  catalog, not semantics.

Nothing here needs deciding now; recorded so the arity question
stops resurfacing.

## Dynamic contender sets are not race

The survey and the tough doc both contain the shape "first
settlement among a set not known at authoring time" — and the
record already rejected the authoring-time-wired combinator for
dynamic sets once: merge over an unbounded, growing set of
completion asyncs was tough-doc break #1, and the answer was not
a dynamic merge but a missing *output* of the concurrent collect
(the completions stream, in settlement order).

The same answer covers first-of: **first-of-a-dynamic-set is the
head of the completions stream**, not a race. Race's arity is
structure — N contender wires, drawn, each with its cell and its
continuation. That is what makes the barrier's per-contender
correspondence mean anything: a cell is a *place* in the
drawing. A runtime-sized race would have runtime-many cells,
which is no longer a drawable partition; it is a flow of
settlements, and the flow constructs own it. The division of
labor:

- **Race**: few contenders, each with its own continuation —
  the handshake vs connection-loss, fetch vs timer, done vs
  shutdown shapes. The survey's C2/C3 sites are all arity 2 or
  3.
- **Concurrent collect + completions stream**: many/dynamic
  bodies, uniform continuation — take the head for first-of,
  fold for gather, scan a set for supervision.

Recorded as dead end 5 below so "parameterise race's arity"
doesn't get re-proposed.

## Abandonment at the barrier

What race promises today is inherited unchanged: settlement
abandons the losers; abandonment is not cancellation; in-flight
losers run to completion, memoised, unobserved unless some other
consumer holds their cell (`async-flow-design.md`, the cell
section and "Effects, abandonment, cancellation"). For pure work
that is the whole story. This round does not design cancellation
— that is the Tier-1 IO round's, deliberately — but it can
sharpen the *interface* race will present to it, because the
survey shows exactly where the hand-rolled versions bleed:

- websockets 5 cancels both drains in a `finally` after the
  race — cancel-losers-on-settlement, written by hand at every
  race site.
- aiohttp 2's graceful shutdown escalates through three timeout
  races, each stage cancelling harder, with a `shield` guarding
  the wait-for-the-thing-being-cancelled step.
- websockets 4 (the vendored timeout manager) is the pathology
  in full: interruption delivered *as* task cancellation, then
  un-counted and converted so outer real cancellations still
  work.

The structural observation race contributes: **the lost cell is
the cancellation trigger, and it already exists.** At
settlement, every losing cell's never-fires status is
determinate — the same event that (per the subset-merge
derivation above) writes terminators is the event "contender i
is now abandoned *by this race*." When the IO round gives the
async cell its cancellation capability (the constraint already
recorded there), race needs no new ports and no policy: a
cancel-on-abandonment behavior, whatever its shape, keys off the
cells' settlement-determined non-firing. Per-consumer honesty is
preserved — a loser shared with another live consumer is
abandoned by the race, not by the program, and the cell (the
unit of sharing) is exactly where that distinction is visible.

Recorded as a hook with a named trigger, nothing more. The
escalation ladder, `shield`, and release-on-abandonment stay
with bracket and the IO round.

## Fairness

Async question 7, answered by relocation:

**For race itself the question is vacuous.** One settlement, one
winner, no repetition — there is nothing to be fair *across*.
The only bias race carries is the already-settled tie-break, and
that is specified, deterministic, and drawn (lowest-numbered
wins), which is better than an arbitration hiding in the
runtime.

**For merge the question is real, and it belongs to the chooser.**
Merge re-races per emission, and under the tie-break a stream
whose next head is always already-settled beats a settled sibling
head every round — the sibling's element is never lost (its cell
stays settled and carries over), but its emission waits until the
greedy side has a gap. That is honest settlement-observation
order, not arrival order; "fair" variants (alternation, oldest-
settlement-first) are different per-heads decisions, not knobs
on race. And the record already has the construct family whose
configuration *is* the per-heads decision: the decision-driven
merge (`tough-use-cases-design.md`, use case 3 — chooser by
comparison for the ordered merge, chooser by arrival for the
async merge). Fairness variants are chooser variants. They land
in that family's round if a program ever demands one; the async
doc's suspicion ("an explicit operation if so") is confirmed
with an address attached.

## The derived combinators: merge, interrupt, and the timeout family

The async doc derived merge and interrupt informally ("race
applied repeatedly", "race at every pull"). This round pins
their status: **catalog blocks with derived lowerings, not
primitives and not mere idioms.**

The reason is the same one that made the decision-driven merge a
catalog block: the lowering is a corecursive, self-driven walk —
race the heads, emit, recurse with the in-flight loser carried —
and raw corecursion is exactly what the language declines to
hand users (the mergesort round's diagnosis). Nobody should
author the recursion; everybody should be able to read it as the
derived view when they drop down. That is the
abstraction-is-source-of-truth shape, with the async merge and
the ordered merge now visibly two members of one family whose
lowerings differ only in what decides the head (arrival vs
comparison).

**Interrupt vs end-when: the sibling stance, confirmed from the
mechanics side.** `end-when-design.md` recorded the unification
conjecture (one terminator-writing node, aligned/unaligned stop)
and stated what would decide it: "whether the checking and
compilation genuinely share anything beyond the output type."
With race's law stated, interrupt's mechanical content can be
inventoried exactly: per-pull race construction, the memoised
interrupt cell carried across pulls, the pull boundary as the
yield point, the cooperative-interruption caveat, and (from this
round) the tie-break at each pull. End-when's aligned stop has
*none* of these — no race, no carry, no boundary, no caveat; its
check is provenance and its compile is a conditional in the
walk. The two constructs share the output type (shortened flow,
terminator with payload) and the downstream story (propagate or
discharge), and nothing else. On the stated test, that reads as:
**siblings, confirmed** — the unification would unify a drawing,
not a mechanism. Still a leaning (the conjecture's other half,
whether one drawing would mislead more than it teaches, is a
visual question this repo doesn't decide), but the mechanical
half of the test now has its answer.

**Timeout is not a construct at all.** The survey's most common
race guise (C2, five of thirty sites) dissolves into the
vocabulary three ways, by what carries the deadline:

- *One-shot timeout* — `race(subject, timer(d))`: the +1
  contender on an async open, per the unary-race ladder. The
  async doc's worked example, unchanged.
- *Whole-walk timeout* — `interrupt(stream, timer(d))`: one
  timer cell minted **outside** the walk, raced (memoised,
  carried) at every pull; the deadline covers the whole drain.
- *Per-step timeout* — the same interrupt drawing with the timer
  minted **inside** the per-pull body: a fresh cell per pull, so
  the deadline resets each step. celery 2's
  `drain_events(timeout=1.0)`-per-round loop is this shape, as
  is uvicorn 1's `should_exit.wait(delay)` heartbeat.

The one-outside vs fresh-inside distinction is node identity —
the language's ordinary sharing rule (bind once and reuse, or
don't) — expressing deadline scope with no annotation. That is
the strongest form of "timeout is an idiom": both timeout
*policies* are one drawing apart, and a timeout primitive would
have needed a mode flag for exactly this.

**The worked contrast, against the survey's hardest site.** What
websockets 4 hand-rolls — `async with timeout(...)` — is
interruption delivered in-band, *as* cancellation of the current
task: a timer that cancels, a four-state enum to remember why,
an exit hook converting the self-inflicted `CancelledError` to
`TimeoutError`, and an un-cancel dance so an outer real
cancellation isn't swallowed. Every piece of that machinery
exists because the interrupt signal and the cancellation channel
are the same channel, so provenance of the cancellation must be
reconstructed after the fact — the temporal version of the
side-flag discrimination in finding 3.2. The barrier form keeps
the channels apart by construction: the timer is a contender,
"timer won" is a cell (structural, not an exception type), the
subject's cell is abandoned (and, post-IO-round, cancelled via
the lost-cell trigger) rather than being the *messenger*, and an
outer interrupt is a different race at a different level, never
confusable with this one. The four-state machine compiles away
into the drawing.

(Retry-with-backoff — the survey's other recurring composite —
is register + timer + failure legs and belongs to the
register/end-when ladder recorded in finding 3.8; race
contributes only the timer's ordinariness. Not this round's.)

## Provenance fit

Nothing new is needed. Race is one uncollect step in the context
path — async kind, bundle of N cells — the same step shape a
case split writes, with time as the discriminator. Cell sets
compare by containment exactly as for case splits and partial
collects; the mixing check meets the race bundle with no changes
(already noted in the crossing round); the covering collect
peels the step and repackages the time displacement as its
output's async kind. The subset merge's terminator adds no step
kind either — failability is a property of the flow, not of the
path (`async-flow-design.md`).

## Compile notes

Extending the async doc's sketch by the edges this round pinned;
nothing beyond the async cell and the existing discipline:

- A collect over the race bundle compiles to one async cell.
  Thunk: start all contenders in drawn order; `await
  Promise.race(tagged)` where each contender's promise is mapped
  to `{tag: i, value}`; dispatch on the tag into the winning
  branch's scope, the per-cell minted binding
  (`__lazyDone__`-style) written there. Compile-internal
  tagging, never user-visible — unchanged from the async doc.
- The drawn-order tie-break is free: `Promise.race` resolves
  with the first already-settled promise in argument order, and
  the emitted argument order is the drawn order.
- A subset merge's thunk is the same race with the complement's
  tags routed to the terminator write instead of a branch —
  reject/resolve-with-terminator per however failable-flow
  terminators are represented when the failability runtime
  lands.
- Merge/interrupt lowerings carry the loser's still-in-flight
  cell into the recursion — already sketched in the async doc;
  the catalog-block status just means this walk is emitted, not
  authored.

## Against the philosophy

- **No bottlenecks.** The barrier form was born from this
  principle and the crossing round mechanised it; this round
  adds the field verification loop: every survey race rebuilt
  the severed correspondence from side flags (finding 3.2),
  which is what "the wires survive only as tag names" looks
  like in production code.
- **Building blocks must build.** The +1 ladder is now explicit
  and additive at every rung: await → *+ timer contender* =
  timeout → *+ a third contender* (shutdown) = the same barrier
  wider → *whole-walk deadline* = interrupt with the timer
  outside → *per-step deadline* = mint the timer inside →
  *+ why-did-it-end* = discharge the terminator. No rung
  rewrites the previous drawing. The unary-race identification
  is this principle applied to the bottom rung.
- **One obvious reading.** The tie-break is drawn (contender
  order), deadline scope is node placement, and the
  discrimination is cells — three facts that in the sampled code
  live in argument conventions, flag names, and exception types
  respectively.
- **Example first.** The law's edges (already-settled ties,
  subset merges, dynamic sets) were each forced by a concrete
  sampled site or a recorded program, not invented for
  generality.
- **Abstraction is the source of truth.** Merge and interrupt
  are durable catalog blocks over readable corecursive
  lowerings, the same cut as sort and the decision-driven
  merge; flattening nested races is a recognition, upward and
  earned.
- **Foundations before features.** Cancellation is *not*
  designed here despite the pressure — only its trigger is
  named, on the object (the cell) that already carries the
  constraint. The IO round keeps its scope.

## Dead ends

Recorded in place, per convention — each with the reason it
should not be re-proposed:

1. **A fairness knob on the race barrier.** Race is one-shot;
   there is no repetition to arbitrate. Its only bias is the
   already-settled tie-break, which should stay a drawn,
   specified order rather than a runtime policy. Fairness
   questions are per-heads-decision questions and belong to the
   merge/chooser family's round.
2. **Timeout as a primitive node.** It is one added contender
   (one-shot) or one interrupt operand (walks), and the two
   deadline scopes that a primitive would need a mode for are
   already expressed by where the timer cell is minted. A
   primitive would duplicate race and hide the timer wire. The
   survey's five timeout sites are all literally hand-rolled
   `race(subject, timer)`.
3. **Interruption delivered in-band via the cancellation
   channel** (the websockets 4 shape: cancel the subject's task
   to signal timeout, convert and un-count afterwards). This is
   the pattern the barrier exists to replace, not a candidate
   form of it: reusing the abandonment/cancellation channel as
   the signal forces provenance reconstruction (state enums,
   exception conversion, uncancel counting) at every layer
   boundary. Signals are cells; cancellation, when it lands, is
   an effect on abandoned cells — the channels stay distinct.
4. **Late loser outputs on the covering collect** (losers
   delivered as options/after-the-fact values beside the
   winner). Breaks the exactly-one law of the bundle — the
   covering collect would fire more than once per settlement or
   carry values from cells that never fired. A loser's eventual
   value is already reachable, explicitly, by independently
   consuming its memoised cell; a program that wants
   all-of-with-first-marked is a concurrent join plus a race
   over the same cells (sharing makes this cheap), constructed
   on purpose.
5. **Dynamic-arity race** (the contender set as runtime data on
   one barrier). Runtime-many cells are not a drawable
   partition, and the per-contender correspondence — the whole
   point of the barrier — has no place to live. First-of-a-
   dynamic-set is the head of the concurrent collect's
   completions stream, which owns dynamic bodies by design
   (tough-doc break #1's resolution).

## Open questions

1. **Adoption.** This round is prepared for the design
   conversation; the owning docs carry dated pointer notes,
   nothing is marked decided.
2. **The unary-race identification.** Async uncollect = race at
   N = 1 is this round's leaning; the drawn form (does one
   contender look like an open?) and the spec entry should be
   decided together, with the visual side consulted where that
   conversation happens.
3. **Subset-merge terminator payload.** Failable-by-construction
   is the lean; whether the payload is the bare settled-elsewhere
   fact, the winning cell's index, or (dirtier) the winning
   value, is open — and it should be decided jointly with the
   terminator payload-composition residue
   (`async-flow-design.md`), since both are questions about what
   terminators carry.
4. **Cancellation interplay proper.** The lost-cell trigger is
   the recorded hook; the actual capability, delivery, and
   bracket ordering wait on the Tier-1 IO round. Race commits
   only to needing no new ports for it.
5. **The chooser family's round.** The decision-driven merge
   (tough-doc item 4's remaining member) now also owns merge's
   fairness variants; its round should treat the async merge as
   a member, not a special case.
6. **Spec and text.** Spec entries for the race barrier (and
   merge/interrupt as catalog blocks), plus textual spellings,
   are owed bookkeeping on adoption
   (`textual-representation-design.md`'s catch-up list).
7. **Naming.** Race vs select; interrupt vs until; "contender";
   "settlement." Deferred to the naming sweep, ledgered in
   `implementation-strategy.md` (async question 8 unchanged).
8. **Evidence.** Survey 3's corpora implement infrastructure;
   the application-level sample (how often application code
   reaches for race vs gather vs pool) is still the named next
   round and would re-weight this area's remaining items.

## What this doesn't address

- **Cancellation and the IO/effects design** — the Tier-1 gap
  is untouched beyond naming race's trigger for it.
- **The concurrent collect's own round** — lifecycle outputs,
  `bounded(n)`-as-resource, and the served flow are the
  concurrency area's other members; this round only borrowed
  the completions stream as the dynamic-set answer.
  *(2026-07-11: now written — `concurrent-collect-design.md`;
  the borrowed completions stream is designed there as the
  settle node's one flow output, primitive at exactly the
  dynamic-set boundary dead end 5 drew.)*
- **End-when's adoption** — the sibling confirmation here is
  mechanics evidence for that doc's conjecture, not a move in
  its adoption question.
- **Visual depiction** — barrier lines, cell drawings, and
  whether a unary race looks like an open are the layout side's
  questions, out of scope in this repo.
- **Implementation.** The async runtime (cells, failable
  terminators, stream integration) does not exist in the
  compiler; nothing here changes the recorded dependency order
  (streams, then async cells, then async streams / race /
  interrupt).
