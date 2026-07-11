# The Race Barrier

Status: exploration — leanings, not adopted.

Race is the concurrency vocabulary's first-of coordination primitive:
given several async values, it settles on whichever finishes first and
tells you which one did. This document works out its semantics beyond the
ports the barrier form already fixes — the settlement law, ties,
reconvergence, arity, abandonment, fairness — and the vocabulary derived
from it: merge, interrupt, and the timeout family. The port/crossing
corner is taken as settled (`barrier-value-crossing-design.md`): values
in, one minted (value, flow) pair per contender, one node. Nothing here
is implemented; the async runtime it presumes does not exist yet.

The demand is measured, not assumed. A concurrency survey of thirty
random orchestration sites (`real-loop-survey.md`, survey 3) found
first-of coordination outweighing all-of by nine to one, and *every*
hand-rolled race reconstructing "who won" from side flags. On that
evidence race leads the concurrency area (`open-problems.md`, Tier 2).

Terms used throughout: an **async cell** is a memoised container that
settles (resolves or rejects) at most once; **settlement** is that event;
a **bundle** is a set of mutually-exclusive **cells**, each cell a place a
value may fire; a **covering** collect terminates every cell of a bundle,
a **partial** collect only some (`partial-collect-design.md`). "Start is
synchronous" and "abandonment ≠ cancellation" are the async model's
(`async-flow-design.md`).

## The law of the barrier

**Form.** Race takes N contenders (N ≥ 1), each an async value. It is the
sum-side multi-input uncollect — values in, exactly as a case split takes
a value in (the full argument is `barrier-value-crossing-design.md`, dead
end 3). Out comes a **bundle of N cells**: cell i fires iff contender i
won, carrying contender i's resolved value as its minted per-cell output.

```
fetch:   fetchD
timeout: after(30)
-> race => r
~r.fetch:   r.fetch -> process -> some
~r.timeout: none
-~> collect => out
```
One firing decides the bundle — whichever of the fetch and the timer
settles first; `out` is the processed response or `none`.

**Starting.** Forcing any collect over the bundle starts all N contenders
— synchronously, in drawn order, before the first await. Start order is
therefore determinate and drawn. For pure contenders it is unobservable;
once effects exist it is observable timing (the caveat start-all carries
everywhere).

**Settlement.** The race settles at the first settlement of any
contender. "First" is well-defined per schedule: the event loop
serialises settlements, so a schedule has exactly one first. Across
schedules the winner is nondeterministic, and the language promises
nothing more — the bundle is the honest representation of that
nondeterminism.

**Ties.** One edge case is not schedule-dependent and is specified rather
than left to the compile: contenders **already settled when the race
starts**. A memoised cell resolves at most once and stays resolved, so a
race wired to an already-resolved cell is ordinary, not exotic (the
survey's lazily-minted milestone cells are often already resolved at
observation). Among contenders settled before the race's first await,
**the lowest-numbered wins** — drawn order is the tie-break. It costs
nothing (it is what `Promise.race` over tagged wrappers does), it is
deterministic, and it is drawn: the priority order is visible on the
canvas. Contenders settling after the start are ordered by the loop, and
no tie is possible.

**Exactly once.** The race settles exactly once; exactly one cell fires;
the others never fire. Losers are not cancelled — their in-flight work
runs to completion into their memoised cells, observable by any other
consumer that independently forces them, GC'd otherwise.

**Failable contenders.** First *settlement* wins, including a rejection.
The winning cell's continuation is then a flow whose terminator has
already fired, and propagation does the rest (`async-flow-design.md`,
"Race also composes cleanly").

## The unary race is the async uncollect

Set N = 1. One contender, one cell; the cell fires iff the contender
settles first, which is always; the minted value is the resolution. That
is the async uncollect, port for port — one value port (the resolved
value), one flow port (the async context), body runs after arrival.

The leaning: **the async open and the race barrier are one construct at
different arities.** Not a coincidence to admire but a graceful-expansion
rung to use.

- *Await a fetch*: async uncollect on `fetchD`, body on its value port.
- *+ a timeout*: add a second contender — wire `timer(5s)` into the same
  uncollect. The existing body is now cell 1's body, untouched; cell 2
  (timer won) gets its value; the collect that closed the body now closes
  the bundle.

The +1 step is an addition to the drawing — one wire and one alt body —
not a rewrite into a different construct. The field version of that same
step (fastify 4) grows a handler-await into a handler-timeout by adding an
`AbortController`, a `setTimeout`, a `reply.sent` flag check, and a paired
`clearTimeout` on a close listener. That distance is what the
identification buys.

Against the identification: the drawing might want "awaiting" and
"racing" to look different (though a barrier line with one contender being
just an open is arguably the point); and the case-split/race analogy is
between the N-ary forms, not the degenerate ones (a unary case split is a
degenerate re-tagging, a unary race is the ordinary open). Neither seems
disqualifying. Held as a leaning; decide with the spec entry. (The
option/async convergence is untouched: option's discriminator is data
checked now, and no arity generalisation changes that.)

## Reconvergence: covering and subset collects

The covering story is inherited whole: the exhaustive close over all
contenders is the covering partial collect over the race bundle
(`partial-collect-design.md`, "Every bundle merges"). The winner's value
reaches the parent context through that node's minted row; the output is
`async<Y>`, because which cell fired isn't known until settlement.

The **subset** merge — collect only some cells, "take cache or replica,
whichever wins" — is sanctioned there too but needs checking against the
async kind, and that check yields this document's one genuinely new
derivation.

A partial collect over cells S ⊊ {1..N} mints a merged flow that fires iff
the winner is in S. As a flow that is **zero-or-one, later**, its bare
version is *unobservable*: an async that never fires is indistinguishable,
forever, from one that hasn't fired yet (`async-flow-design.md`, "Failure
as terminator payload"). A consumer awaiting a bare subset merge whose
race settled elsewhere hangs for the life of the program — a designed
footgun.

But race is exactly the case where the table's escape clause applies: a
later-flow's zero case is meaningful when the termination is itself an
event. Here it is — the race's settlement decides every cell at once, so
"the winner is not in S" becomes true at a knowable moment. The lean:

> **A subset partial collect over a race bundle is failable by
> construction.** Its merged output's terminator fires at the race's
> settlement when the winner is outside S, carrying the fact of
> settling-elsewhere as payload. The covering collect is the degenerate
> case whose terminator is unreachable — which is why the covering form
> reads as infallible with no special rule.

Payload contents, a sub-leaning: the *fact* — which cell won, an index
into the partition — not the winning *value*. Delivering contender j's
value through a collect that does not engage cell j would move a value
across cells the node never touched; the discipline is engage the cell if
you want its value. The alternative (payload carries the winner's value
too) is convenient and dirty; recorded so the conversation can weigh it.

The contrast that makes this specific to async: the same subset merge over
a case split *inside a list iteration* is unremarkable — non-matching
elements just don't fire, the walk continues, the collect terminates with
the walk. The failable completion is the exactly-one-later kind's
instantiation of the partial collect, not a change to the partial collect
in general.

## Nested and flat race

`race(a, race(b, c))` — the inner race covered into an `async<_>`, then
raced against `a` — relates to the flat `race(a, b, c)` thus:

- **They are different programs.** The flat form has three cells and
  delivers the b/c discrimination at the one barrier. The nested form has
  two cells at the outer barrier; the b/c discrimination lives at the
  inner covering collect, inside cell 2's continuation.
- **Their winners agree** (up to the microtask hops the compile inserts):
  the inner race settles at first-of(b, c), the outer at first-of(a,
  that) — the same contender wins either way, with drawn-order ties
  resolving compatibly (a before b before c in both).
- So flattening is a candidate **level-1 recognition**, never a need:
  N-ary drawing means nobody has to write the nested form to get the flat
  meaning, and recognising a nested form that arrives (built
  incrementally, or through a function boundary) is a derived-view
  question for the transformation-levels catalog, not semantics.

## Dynamic contender sets are not race

"First settlement among a set not known at authoring time" is not race.
Race's arity is *structure* — N contender wires, drawn, each with its cell
and continuation — and that is what makes the per-contender correspondence
mean anything: a cell is a *place* in the drawing. A runtime-sized race
would have runtime-many cells, which is no longer a drawable partition.

**First-of-a-dynamic-set is the head of the completions stream**
(`concurrent-collect-design.md` — the settle node's flow output, primitive
at exactly this boundary), not a race. The division of labor:

- **Race**: few contenders, each with its own continuation — handshake vs
  connection-loss, fetch vs timer, done vs shutdown. The survey's sites
  are all arity 2 or 3.
- **Concurrent collect + completions stream**: many/dynamic bodies,
  uniform continuation — take the head for first-of, fold for gather, scan
  a set for supervision.

Recorded as dead end 5 so "parameterise race's arity" is not re-proposed.

## Abandonment at the barrier

Settlement abandons the losers; abandonment is not cancellation; in-flight
losers run to completion, memoised, unobserved unless some other consumer
holds their cell (`async-flow-design.md`). For pure work that is the whole
story. This document does not design cancellation — that is the Tier-1 IO
round's — but it sharpens the interface race presents to it, because the
survey shows where hand-rolled versions bleed:

- websockets 5 cancels both drains in a `finally` after the race —
  cancel-losers-on-settlement, hand-written at every race site.
- aiohttp 2's graceful shutdown escalates through three timeout races,
  each stage cancelling harder, with a `shield` guarding the
  wait-for-the-thing-being-cancelled step.
- websockets 4 (a vendored timeout manager) is the pathology in full:
  interruption delivered *as* task cancellation, then un-counted and
  converted so outer real cancellations still work.

The structural observation: **the lost cell is the cancellation trigger,
and it already exists.** At settlement, every losing cell's never-fires
status is determinate — the same event that writes subset-merge
terminators is the event "contender i is now abandoned by this race." When
the IO round gives the async cell a cancellation capability, race needs no
new ports and no policy: a cancel-on-abandonment behavior keys off the
cells' settlement-determined non-firing. Per-consumer honesty is preserved
— a loser shared with another live consumer is abandoned by the race, not
by the program, and the cell (the unit of sharing) is where that
distinction is visible. A hook with a named trigger, nothing more; the
escalation ladder, `shield`, and release-on-abandonment stay with bracket
and the IO round.

## Fairness

**For race itself the question is vacuous.** One settlement, one winner,
no repetition — nothing to be fair across. The only bias is the
already-settled tie-break, and that is specified, deterministic, and drawn
(lowest-numbered wins), which is better than an arbitration hiding in the
runtime.

**For merge the question is real, and it belongs to the chooser.** Merge
re-races per emission, and under the tie-break a stream whose next head is
always already-settled beats a settled sibling head every round. The
sibling's element is never lost (its cell stays settled and carries over),
but its emission waits until the greedy side has a gap. That is honest
settlement-observation order, not arrival order; "fair" variants
(alternation, oldest-settlement-first) are different per-heads decisions,
not knobs on race. They belong to the decision-driven merge family
(`tough-use-cases-design.md`, use case 3 — chooser by comparison for the
ordered merge, chooser by arrival for the async merge), and land in that
family's round if a program demands one.

## Merge, interrupt, and the timeout family

These are **catalog blocks with derived lowerings — not primitives, and
not mere idioms.** The reason is the reason the decision-driven merge is a
catalog block: the lowering is a corecursive, self-driven walk — race the
heads, emit, recurse with the in-flight loser carried — and raw
corecursion is exactly what the language declines to hand users (the
mergesort round's diagnosis). Nobody should author the recursion;
everybody should be able to read it as the derived view on drop-down.
Merge and interrupt sit beside the async and ordered merges as members of
one family whose lowerings differ only in what decides the head (arrival
vs comparison).

**Interrupt vs end-when: siblings.** `end-when-design.md` records a
conjecture that interrupt and end-when might be one terminator-writing
node (aligned vs unaligned stop), and states the deciding test: whether
checking and compilation genuinely share anything beyond the output type.
Interrupt's mechanical content, inventoried against race's law: per-pull
race construction, the memoised interrupt cell carried across pulls, the
pull boundary as yield point, the cooperative-interruption caveat, and the
tie-break at each pull. End-when's aligned stop has none of these — no
race, no carry, no boundary, no caveat; its check is provenance and its
compile is a conditional in the walk. The two share the output type
(shortened flow, terminator with payload) and the downstream story
(propagate or discharge), nothing else. On the stated test: **siblings** —
a unification would unify a drawing, not a mechanism. Still a leaning
(whether one drawing would mislead more than it teaches is a visual
question this repo doesn't decide), but the mechanical half of the test
has its answer.

**Timeout is not a construct at all.** The survey's most common race guise
(five of thirty sites) dissolves into the vocabulary three ways, by what
carries the deadline:

- *One-shot timeout* — `race(subject, timer(d))`: the +1 contender on an
  async open, per the unary-race ladder.
- *Whole-walk timeout* — `interrupt(stream, timer(d))`: one timer cell
  minted **outside** the walk, raced (memoised, carried) at every pull;
  the deadline covers the whole drain.
- *Per-step timeout* — the same interrupt drawing with the timer minted
  **inside** the per-pull body: a fresh cell per pull, so the deadline
  resets each step. celery 2's `drain_events(timeout=1.0)`-per-round loop
  is this shape, as is uvicorn 1's `should_exit.wait(delay)` heartbeat.

The one-outside vs fresh-inside distinction is node identity — the
ordinary sharing rule (bind once and reuse, or don't) — expressing
deadline scope with no annotation. Both timeout *policies* are one drawing
apart, and a timeout primitive would have needed a mode flag for exactly
this.

The worked contrast is the survey's hardest site. websockets 4 hand-rolls
`async with timeout(...)` as interruption delivered in-band, *as*
cancellation of the current task: a timer that cancels, a four-state enum
to remember why, an exit hook converting the self-inflicted
`CancelledError` to `TimeoutError`, and an un-cancel dance so an outer real
cancellation isn't swallowed. Every piece exists because the interrupt
signal and the cancellation channel are the same channel, so cancellation
provenance must be reconstructed after the fact. The barrier keeps the
channels apart by construction: the timer is a contender, "timer won" is a
cell (structural, not an exception type), the subject's cell is abandoned
(and, post-IO-round, cancelled via the lost-cell trigger) rather than
being the *messenger*, and an outer interrupt is a different race at a
different level, never confusable with this one. The four-state machine
compiles away into the drawing.

(Retry-with-backoff — the other recurring composite — is register + timer
+ failure legs and belongs to the register/end-when ladder; race
contributes only the timer's ordinariness.)

## Provenance fit

Nothing new is needed. Race is one uncollect step in the context path —
async kind, bundle of N cells — the same step shape a case split writes,
with time as the discriminator. Cell sets compare by containment exactly
as for case splits and partial collects; the mixing check meets the race
bundle with no changes; the covering collect peels the step and repackages
the time displacement as its output's async kind. The subset merge's
terminator adds no step kind — failability is a property of the flow, not
of the path.

## Compile notes

Extending the async doc's sketch by the edges pinned here; nothing beyond
the async cell and existing discipline:

- A collect over the race bundle compiles to one async cell. Thunk: start
  all contenders in drawn order; `await Promise.race(tagged)` where each
  contender's promise is mapped to `{tag: i, value}`; dispatch on the tag
  into the winning branch's scope, the per-cell minted binding
  (`__lazyDone__`-style) written there. The tagging is compile-internal,
  never user-visible.
- The drawn-order tie-break is free: `Promise.race` resolves with the
  first already-settled promise in argument order, and the emitted
  argument order is the drawn order.
- A subset merge's thunk is the same race with the complement's tags
  routed to the terminator write instead of a branch.
- Merge/interrupt lowerings carry the loser's still-in-flight cell into
  the recursion; the catalog-block status just means this walk is emitted,
  not authored.

## Against the philosophy

- **No bottlenecks.** Every survey race rebuilt the severed input↔output
  correspondence from side flags (finding 3.2) — what "the wires survive
  only as tag names" looks like in production code. The barrier restores
  it structurally.
- **Building blocks must build.** The +1 ladder is additive at every rung:
  await → *+ timer contender* = timeout → *+ a third contender* (shutdown)
  = the same barrier wider → *whole-walk deadline* = interrupt with the
  timer outside → *per-step deadline* = mint the timer inside → *+
  why-did-it-end* = discharge the terminator. No rung rewrites the
  previous drawing. The unary-race identification is this principle at the
  bottom rung.
- **One obvious reading.** The tie-break is drawn (contender order),
  deadline scope is node placement, discrimination is cells — three facts
  that in the sampled code live in argument conventions, flag names, and
  exception types.
- **Example first.** The law's edges (already-settled ties, subset merges,
  dynamic sets) were each forced by a concrete sampled site or a recorded
  program, not invented for generality.
- **Abstraction is the source of truth.** Merge and interrupt are durable
  catalog blocks over readable corecursive lowerings; flattening nested
  races is a recognition, upward and earned.
- **Foundations before features.** Cancellation is not designed here
  despite the pressure — only its trigger is named, on the object (the
  cell) that already carries the constraint.

## Dead ends

Recorded in place; each with the reason it should not be re-proposed.

1. **A fairness knob on the race barrier.** Race is one-shot; there is no
   repetition to arbitrate. Its only bias is the already-settled
   tie-break, which should stay a drawn, specified order rather than a
   runtime policy. Fairness questions are per-heads-decision questions and
   belong to the merge/chooser family's round.
2. **Timeout as a primitive node.** It is one added contender (one-shot)
   or one interrupt operand (walks), and the two deadline scopes a
   primitive would need a mode for are already expressed by where the
   timer cell is minted. A primitive would duplicate race and hide the
   timer wire. The survey's five timeout sites are all literally
   hand-rolled `race(subject, timer)`.
3. **Interruption delivered in-band via the cancellation channel** (the
   websockets 4 shape: cancel the subject's task to signal timeout,
   convert and un-count afterwards). This is the pattern the barrier
   exists to replace, not a form of it: reusing the abandonment/
   cancellation channel as the signal forces provenance reconstruction
   (state enums, exception conversion, uncancel counting) at every layer
   boundary. Signals are cells; cancellation, when it lands, is an effect
   on abandoned cells — the channels stay distinct.
4. **Late loser outputs on the covering collect** (losers delivered as
   options/after-the-fact values beside the winner). Breaks the
   exactly-one law of the bundle — the covering collect would fire more
   than once per settlement or carry values from cells that never fired. A
   loser's eventual value is already reachable by independently consuming
   its memoised cell; a program that wants all-of-with-first-marked is a
   concurrent join plus a race over the same cells (sharing makes this
   cheap), constructed on purpose.
5. **Dynamic-arity race** (the contender set as runtime data on one
   barrier). Runtime-many cells are not a drawable partition, and the
   per-contender correspondence — the whole point of the barrier — has no
   place to live. First-of-a-dynamic-set is the head of the concurrent
   collect's completions stream, which owns dynamic bodies by design.

## Open questions

1. **Adoption.** Prepared for the design conversation; nothing is marked
   decided.
2. **The unary-race identification.** Async uncollect = race at N = 1 is a
   leaning; the drawn form (does one contender look like an open?) and the
   spec entry should be decided together, with the visual side consulted.
3. **Subset-merge terminator payload.** Failable-by-construction is the
   lean; whether the payload is the bare settled-elsewhere fact, the
   winning cell's index, or (dirtier) the winning value is open, and
   should be decided jointly with the terminator payload-composition
   residue (`async-flow-design.md`).
4. **Cancellation interplay proper.** The lost-cell trigger is the
   recorded hook; the actual capability, delivery, and bracket ordering
   wait on the Tier-1 IO round. Race commits only to needing no new ports
   for it.
5. **The chooser family's round.** The decision-driven merge now also owns
   merge's fairness variants; its round should treat the async merge as a
   member, not a special case.
6. **Spec and text.** Spec entries for the race barrier (and
   merge/interrupt as catalog blocks), plus textual spellings
   (`textual-representation-design.md`), are owed on adoption.
7. **Naming.** Race vs select; interrupt vs until; "contender";
   "settlement." Deferred to the naming sweep
   (`implementation-strategy.md`).
8. **Evidence.** Survey 3's corpora implement infrastructure; an
   application-level sample (how often application code reaches for race vs
   gather vs pool) is the named next round and would re-weight this area.

## What this doesn't address

- **Cancellation and the IO/effects design** — the Tier-1 gap is
  untouched beyond naming race's trigger for it.
- **The concurrent collect's own round** — lifecycle outputs,
  `bounded(n)`-as-resource, and the served flow are designed in
  `concurrent-collect-design.md`; this document only borrows its
  completions stream as the dynamic-set answer.
- **End-when's adoption** — the sibling confirmation here is mechanics
  evidence for that doc's conjecture, not a move in its adoption question.
- **Visual depiction** — barrier lines, cell drawings, and whether a unary
  race looks like an open are the layout side's questions, out of scope in
  this repo.
- **Implementation.** The async runtime (cells, failable terminators,
  stream integration) does not exist in the compiler; nothing here changes
  the recorded dependency order (streams, then async cells, then async
  streams / race / interrupt).
