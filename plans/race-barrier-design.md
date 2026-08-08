# The Race Barrier

*Or: waiting for whichever finishes first.*

Status: exploration — this chapter teaches leanings that have not
been adopted. Nothing in it is implemented, and the async runtime it
presumes does not exist yet. Read every "race does X" below as "the
current proposal is that race does X" — prepared for the design
conversation, not decided. One update from the crossing side
(2026-07-23, `barrier-value-crossing-design.md`, corner 2 —
adopted with an amendment): race's inputs are per-contender
**(flow wire, payload value wire) pairs** (a bare async value is
admissible as the completed-open aggregate), race re-read as the
partial collect's async sibling. That reshapes this chapter's
unary-race leaning: under pairs, **await = open async** (the
opener), and the N=1 race is the degenerate transport rather than
the await — read the unary-race section with that amendment in
mind, and read the chapter's examples, which wire bare contenders,
as the aggregate spelling of the pairs (consistency pass
2026-08-04: the pairs are the construct; the bare form is the
completed-open shorthand, recoverable by provenance in text and by
editing steps in the visual editor).

You will often want to start several things at once and act on
whichever finishes first: a network fetch or a timer, a handshake or
a connection loss, a result or a shutdown signal. The construct for
that is **race** — the concurrency vocabulary's first-of
coordination primitive. Given several async values, it settles on
whichever finishes first and tells you which one did.

This chapter works out race's meaning beyond the ports the barrier
form already fixes — the settlement law, ties, reconvergence, how
many contenders there can be, what happens to the losers, fairness —
and the vocabulary derived from race: merge, interrupt, and the
timeout family. One corner is taken as settled going in: the
port/crossing story (`barrier-value-crossing-design.md`) — values
in, one minted (value, flow) pair per contender, one node. Two rules
of the async model (`async-flow-design.md`) are assumed throughout
and explained where they first matter: "start is synchronous" and
"abandonment is not cancellation."

## Your first race

Here is a fetch guarded by a timeout:

```
fetch:   fetchD
timeout: after(30)
-> race => r
~r.fetch:   r.fetch -> process -> some
~r.timeout: none
-~> collect => out
```

Read it top to bottom. `fetchD` is an async value — the fetch,
already wired up; `after(30)` is a timer. Each is a **contender** in
the race. An async value in this language lives in an **async
cell**: a container that remembers its answer — it *settles*
(resolves or rejects) at most once, and once settled it stays
settled forever (memoised, in the jargon). **Settlement** is that
event: the moment a cell gets its answer.

The race's output `r` is a **bundle** of two **cells** — a set of
mutually-exclusive places, each cell a place a value may fire, of
which exactly one will. `~r.fetch:` introduces the body that runs if
the fetch won; on that path, `r.fetch` is the fetch's resolved
value, and the body processes it into `some`. `~r.timeout:` is the
body for the timer winning, which just supplies `none`. The
`-~> collect` at the end closes both cells back into one value. A
collect that terminates every cell of a bundle is called a
**covering** collect; one that terminates only some of them is a
**partial** collect (`partial-collect-design.md`) — both return
later in this chapter.

One firing decides the bundle — whichever of the fetch and the timer
settles first; `out` is the processed response or `none`.

In general, race takes N contenders (N ≥ 1), each an async value. It
is the sum-side multi-input uncollect — values in, exactly as a case
split takes a value in (the full argument for that form is
`barrier-value-crossing-design.md`, dead end 3). Out comes a bundle
of N cells: cell i fires iff contender i won, carrying contender i's
resolved value as its minted per-cell output.

Now, you might wonder why the race doesn't just hand back a single
value — the winner's result packed together with a tag saying who
won, the way JavaScript's `Promise.race` gives you one promise
result. It turns out this would pack a tagged union merely to cross
the barrier, and unpacking it on the far side severs the visual
thread between each contender wire and its continuation — exactly
the sum-side bottleneck the design forbids (the principle is "no
bottlenecks"; the async statement of it is `async-flow-design.md`,
"Racing is a barrier, not a value"). The severed correspondence is
not hypothetical: every hand-rolled race in the survey below rebuilt
"who won" from side flags after the fact. So the barrier keeps a
separate output per contender instead — each cell is a *place*, and
the winner's value arrives at its own place. (This is a settled
rejection, recorded in `barrier-value-crossing-design.md` and
`async-flow-design.md` — please don't re-propose it without new
evidence.)

## Where this shows up in real code

The demand for race is measured, not assumed. A concurrency survey
of thirty random orchestration sites (`real-loop-survey.md`,
survey 3) found first-of coordination outweighing all-of by nine to
one, and *every* hand-rolled race reconstructing "who won" from side
flags. On that evidence race leads the concurrency area
(`open-problems.md`, Tier 2). Individual survey sites — websockets,
aiohttp, celery, uvicorn, fastify — appear throughout this chapter
where they bear on a specific point.

## The law of the barrier

**Starting.** Forcing any collect over the bundle starts all N
contenders — synchronously, in drawn order, before the first await.
Start order is therefore determinate and drawn. For pure contenders
it is unobservable; once effects exist it is observable timing (the
caveat start-all carries everywhere in the async design).

**Settlement.** The race settles at the first settlement of any
contender. "First" is well-defined per schedule: the event loop
serialises settlements, so a given schedule has exactly one first.
Across schedules the winner may differ from run to run —
nondeterministic — and the language promises nothing more. The
bundle is the honest representation of that nondeterminism: rather
than pretending the winner is knowable, the drawing gives each
possible winner its own place.

**Ties.** One edge case is not schedule-dependent, and the language
specifies it rather than leaving it to the compile: contenders
**already settled when the race starts**. This is ordinary, not
exotic — a memoised cell resolves at most once and stays resolved,
so a race wired to an already-resolved cell simply sees it settled
(the survey's lazily-minted milestone cells are often already
resolved at observation). Among contenders settled before the
race's first await, **the lowest-numbered wins** — drawn order is
the tie-break. This rule costs nothing (it is what `Promise.race`
over tagged wrappers does anyway), it is deterministic, and it is
drawn: the priority order is visible on the canvas. Contenders
settling after the start are ordered by the event loop, and no tie
is possible there.

**Exactly once.** The race settles exactly once; exactly one cell
fires; the others never fire. The losers are not cancelled — their
in-flight work runs to completion into their memoised cells, where
it is observable by any other consumer that independently forces
them, and garbage-collected otherwise.

Now, you might wonder whether the covering collect could also
deliver the losers' values once they eventually arrive — say, as
option values delivered after the fact beside the winner, so one
node gives you "the first, marked, and then the rest." It turns out
this breaks the exactly-once law of the bundle: the covering collect
would fire more than once per settlement, or would carry values from
cells that never fired. A loser's eventual value is already
reachable by independently consuming its memoised cell; and a
program that wants all-of-with-first-marked is a concurrent join
plus a race over the same cells (sharing makes this cheap),
constructed on purpose. (This is a recorded dead end — please don't
re-propose it without new evidence.)

**Failable contenders.** First *settlement* wins — including a
rejection. If the winning contender failed, the winning cell's
continuation is a flow whose terminator has already fired, and
propagation does the rest (`async-flow-design.md`, "Race also
composes cleanly").

## One contender: the race that is just an await

Set N = 1. One contender, one cell; the cell fires iff the contender
settles first, which is always; the minted value is the resolution.
That is the async uncollect — the ordinary "open an async value and
run a body when it arrives" — port for port: one value port (the
resolved value), one flow port (the async context), body runs after
arrival.

The leaning: **the async open and the race barrier are one construct
at different arities** — one node family, differing only in how many
contenders are wired in. Not a coincidence to admire but a
graceful-expansion rung to use:

- *Await a fetch*: async uncollect on `fetchD`, body on its value
  port.
- *Add a timeout*: add a second contender — wire `timer(5s)` into
  the same uncollect. The existing body is now cell 1's body,
  untouched; cell 2 (timer won) gets its value; the collect that
  closed the body now closes the bundle.

The +1 step is an addition to the drawing — one wire and one alt
body — not a rewrite into a different construct. Compare the field
version of the very same step (survey site fastify 4): growing a
handler-await into a handler-timeout there means adding an
`AbortController`, a `setTimeout`, a `reply.sent` flag check, and a
paired `clearTimeout` on a close listener. That distance is what the
identification buys.

Against the identification: the drawing might want "awaiting" and
"racing" to look different (though a barrier line with one contender
being just an open is arguably the point); and the case-split/race
analogy is between the N-ary forms, not the degenerate ones (a unary
case split is a degenerate re-tagging, while a unary race is the
ordinary open). Neither seems disqualifying. Held as a leaning;
decide with the spec entry. (The option/async convergence is
untouched by this: option's discriminator is data checked now, and
no generalisation over contender count changes that.)

## Getting one value back out

The first program ended with a collect over both cells. That
covering story is inherited whole: the exhaustive close over all
contenders is the covering partial collect over the race bundle
(`partial-collect-design.md`, "Every bundle merges"). The winner's
value reaches the parent context through that node's minted row; the
output is `async<Y>`, because which cell fired isn't known until
settlement.

What about collecting only *some* of the cells — "take cache or
replica, whichever wins," ignoring a third contender? That
**subset** merge is sanctioned there too, but it needs checking
against the async kind specifically, and that check yields this
chapter's one genuinely new derivation.

A partial collect over cells S ⊊ {1..N} mints a merged flow that
fires iff the winner is in S. Ask what kind of flow that is: one
that fires **zero or one times, later**. The async design has a
warning about exactly that shape: its bare version is
*unobservable* in the zero case — an async that never fires is
indistinguishable, forever, from one that hasn't fired yet
(`async-flow-design.md`, "Failure as terminator payload"). A
consumer awaiting a bare subset merge whose race settled elsewhere
would hang for the life of the program — a designed footgun.

But race is exactly the case where that table's escape clause
applies: a later-flow's zero case is meaningful when the termination
is itself an event. Here it is — the race's settlement decides every
cell at once, so "the winner is not in S" becomes true at a knowable
moment. The lean:

> **A subset partial collect over a race bundle is failable by
> construction.** Its merged output's terminator fires at the race's
> settlement when the winner is outside S, carrying the fact of
> settling-elsewhere as payload. The covering collect is the
> degenerate case whose terminator is unreachable — which is why the
> covering form reads as infallible with no special rule.

What should that terminator carry? A sub-leaning: the *fact* — which
cell won, an index into the partition — not the winning *value*.
Delivering contender j's value through a collect that does not
engage cell j would move a value across cells the node never
touched; the discipline is: engage the cell if you want its value.
The alternative (the payload carries the winner's value too) is
convenient and dirty; it is recorded here so the design conversation
can weigh it.

One contrast makes clear why this derivation is specific to async.
The same subset merge over a case split *inside a list iteration* is
unremarkable — non-matching elements just don't fire, the walk
continues, and the collect terminates with the walk. The failable
completion is the exactly-one-later kind's instantiation of the
partial collect, not a change to the partial collect in general.

## Races within races

What if a contender is itself a race? `race(a, race(b, c))` — the
inner race covered into an `async<_>`, then raced against `a` —
relates to the flat `race(a, b, c)` like this:

- **They are different programs.** The flat form has three cells and
  delivers the b/c discrimination at the one barrier. The nested
  form has two cells at the outer barrier; the b/c discrimination
  lives at the inner covering collect, inside cell 2's continuation.
- **Their winners agree** (up to the microtask hops the compile
  inserts): the inner race settles at first-of(b, c), the outer at
  first-of(a, that) — the same contender wins either way, with
  drawn-order ties resolving compatibly (a before b before c in
  both).
- So flattening is a candidate **level-1 recognition**, never a
  need: N-ary drawing means nobody has to write the nested form to
  get the flat meaning, and recognising a nested form that arrives
  anyway (built incrementally, or through a function boundary) is a
  derived-view question for the transformation-levels catalog, not a
  question of meaning.

## What if you don't know how many contenders?

Now, you might wonder why the contender set can't be runtime data —
one barrier fed a list of asyncs whose length is only known when the
program runs. It turns out "first settlement among a set not known
at authoring time" is not race at all. Race's contender count (its
arity) is *structure* — N contender wires, drawn, each with its cell
and continuation — and that is what makes the per-contender
correspondence mean anything: a cell is a *place* in the drawing. A
runtime-sized race would have runtime-many cells, which is no longer
a drawable partition.

First-of-a-dynamic-set is instead **the head of the completions
stream** (`concurrent-collect-design.md` — the settle node's flow
output, primitive at exactly this boundary), not a race. The
division of labor:

- **Race**: few contenders, each with its own continuation —
  handshake vs connection-loss, fetch vs timer, done vs shutdown.
  The survey's sites are all arity 2 or 3.
- **Concurrent collect + completions stream**: many or dynamic
  bodies with a uniform continuation — take the head for first-of,
  fold for gather, scan a set for supervision.

(This is a recorded dead end — dead end 5 in the index below — so
"parameterise race's arity" is not re-proposed without new
evidence.)

## When the race is over: abandonment

Settlement abandons the losers; abandonment is not cancellation;
in-flight losers run to completion, memoised, unobserved unless some
other consumer holds their cell (`async-flow-design.md`). For pure
work that is the whole story.

This chapter does not design cancellation — that belongs to the
Tier-1 IO round — but it sharpens the interface race presents to it,
because the survey shows exactly where hand-rolled versions bleed:

- websockets 5 cancels both drains in a `finally` after the race —
  cancel-losers-on-settlement, hand-written at every race site.
- aiohttp 2's graceful shutdown escalates through three timeout
  races, each stage cancelling harder, with a `shield` guarding the
  wait-for-the-thing-being-cancelled step.
- websockets 4 (a vendored timeout manager) is the pathology in
  full: interruption delivered *as* task cancellation, then
  un-counted and converted so outer real cancellations still work.
  (It returns below, in the timeout family.)

The structural observation: **the lost cell is the cancellation
trigger, and it already exists.** At settlement, every losing cell's
never-fires status is determinate — the same event that writes
subset-merge terminators is the event "contender i is now abandoned
by this race." When the IO round gives the async cell a cancellation
capability, race needs no new ports and no policy: a
cancel-on-abandonment behavior keys off the cells'
settlement-determined non-firing. Per-consumer honesty is preserved:
a loser shared with another live consumer is abandoned by the race,
not by the program, and the cell — the unit of sharing — is where
that distinction is visible. A hook with a named trigger, nothing
more; the escalation ladder, `shield`, and release-on-abandonment
stay with bracket and the IO round.

## Merge, interrupt, and the timeout family

Race by itself is one-shot. The recurring shapes built from it —
merging two streams as elements arrive, interrupting a walk when a
signal fires, timing things out — are **catalog blocks with derived
lowerings: not primitives, and not mere idioms.** (A "lowering" is
the translation to a more concrete form — the readable, derived view
of what the block does underneath.) The reason is the reason the
decision-driven merge is a catalog block: the lowering is a
self-driven walk that produces each step from the last — corecursive,
in the jargon: race the heads, emit, recurse with the in-flight
loser carried — and raw corecursion is exactly what the language
declines to hand users (the mergesort round's diagnosis). Nobody
should author the recursion; everybody should be able to read it as
the derived view on drop-down. Merge and interrupt sit beside the
async and ordered merges as members of one family whose lowerings
differ only in what decides the head (arrival vs comparison).

**Interrupt vs end-when: siblings.** `end-when-design.md` records a
conjecture that interrupt and end-when might be one
terminator-writing node (unaligned vs aligned stop), and states the
deciding test: whether checking and compilation genuinely share
anything beyond the output type. Inventory interrupt's mechanical
content against race's law and you get: per-pull race construction,
the memoised interrupt cell carried across pulls, the pull boundary
as yield point, the cooperative-interruption caveat, and the
tie-break at each pull. End-when's aligned stop has none of these —
no race, no carry, no boundary, no caveat; its check is provenance
and its compile is a conditional in the walk. The two share the
output type (a shortened flow, terminator with payload) and the
downstream story (propagate or discharge), nothing else. On the
stated test: **siblings** — a unification would unify a drawing, not
a mechanism. Still a leaning (whether one drawing would mislead more
than it teaches is a visual question this repo doesn't decide), but
the mechanical half of the test has its answer.

**Timeout is not a construct at all.** The survey's most common race
guise (five of thirty sites) dissolves into the vocabulary three
ways, by what carries the deadline:

- *One-shot timeout* — `race(subject, timer(d))`: the +1 contender
  on an async open, per the unary-race ladder above.
- *Whole-walk timeout* — `interrupt(stream, timer(d))`: one timer
  cell minted **outside** the walk, raced (memoised, carried) at
  every pull; the deadline covers the whole drain.
- *Per-step timeout* — the same interrupt drawing with the timer
  minted **inside** the per-pull body: a fresh cell per pull, so the
  deadline resets each step. celery 2's
  `drain_events(timeout=1.0)`-per-round loop is this shape, as is
  uvicorn 1's `should_exit.wait(delay)` heartbeat.

The one-outside vs fresh-inside distinction is node identity — the
ordinary sharing rule (bind once and reuse, or don't) — expressing
deadline scope with no annotation.

Now, you might wonder why the language doesn't just provide a
timeout primitive, given how common the shape is. It turns out
timeout is one added contender (for one-shots) or one interrupt
operand (for walks), and the two deadline scopes a primitive would
need a mode flag for are already expressed by where the timer cell
is minted — both timeout *policies* are one drawing apart. A
primitive would duplicate race and hide the timer wire. The survey's
five timeout sites are all literally hand-rolled
`race(subject, timer)`. (This is a recorded dead end — please don't
re-propose it without new evidence.)

The worked contrast is the survey's hardest site. websockets 4
hand-rolls `async with timeout(...)` as interruption delivered
in-band, *as* cancellation of the current task: a timer that
cancels, a four-state enum to remember why, an exit hook converting
the self-inflicted `CancelledError` to `TimeoutError`, and an
un-cancel dance so an outer real cancellation isn't swallowed. Every
piece exists because the interrupt signal and the cancellation
channel are the same channel, so cancellation provenance must be
reconstructed after the fact. The barrier keeps the channels apart
by construction: the timer is a contender, "timer won" is a cell
(structural, not an exception type), the subject's cell is abandoned
(and, post-IO-round, cancelled via the lost-cell trigger) rather
than being the *messenger*, and an outer interrupt is a different
race at a different level, never confusable with this one. The
four-state machine compiles away into the drawing.

Now, you might wonder whether delivering interruption through the
cancellation channel could be embraced as a legitimate form of the
construct rather than dismissed as pathology. It turns out this is
the pattern the barrier exists to replace, not a form of it: reusing
the abandonment/cancellation channel as the signal forces provenance
reconstruction — state enums, exception conversion, uncancel
counting — at every layer boundary. Signals are cells; cancellation,
when it lands, is an effect on abandoned cells — the channels stay
distinct. (This is a recorded dead end — please don't re-propose it
without new evidence.)

(Retry-with-backoff — the other recurring composite — is register +
timer + failure legs and belongs to the register/end-when ladder;
race contributes only the timer's ordinariness.)

## Is race fair?

For race itself the question is vacuous. One settlement, one winner,
no repetition — nothing to be fair across. The only bias is the
already-settled tie-break, and that is specified, deterministic, and
drawn (lowest-numbered wins), which is better than an arbitration
hiding in the runtime.

Now, you might wonder whether the race barrier should carry a
fairness knob anyway — a mode for alternation, say, or
oldest-first. It turns out there is nothing for such a knob to
govern: race is one-shot, with no repetition to arbitrate, and its
only bias — the already-settled tie-break — should stay a drawn,
specified order rather than a runtime policy. Fairness questions are
per-heads-decision questions and belong to the merge/chooser
family's round. (This is a recorded dead end — please don't
re-propose it without new evidence.)

For **merge** the question is real, and it belongs to the chooser.
Merge re-races per emission, and under the tie-break a stream whose
next head is always already-settled beats a settled sibling head
every round. The sibling's element is never lost (its cell stays
settled and carries over), but its emission waits until the greedy
side has a gap. That is honest settlement-observation order, not
arrival order; "fair" variants (alternation,
oldest-settlement-first) are different per-heads decisions, not
knobs on race. They belong to the decision-driven merge family
(`tough-use-cases-design.md`, use case 3 — chooser by comparison for
the ordered merge, chooser by arrival for the async merge), and land
in that family's round if a program demands one.

## How race fits the provenance check

Nothing new is needed. Race is one uncollect step in the context
path — async kind, bundle of N cells — the same step shape a case
split writes, with time as the discriminator. Cell sets compare by
containment exactly as for case splits and partial collects; the
mixing check meets the race bundle with no changes; the covering
collect peels the step and repackages the time displacement as its
output's async kind. The subset merge's terminator adds no step
kind — failability is a property of the flow, not of the path.

## What the compiled code would look like

These notes extend the async doc's sketch by the edges pinned in
this chapter; nothing beyond the async cell and existing discipline
is needed:

- A collect over the race bundle compiles to one async cell. Its
  thunk: start all contenders in drawn order;
  `await Promise.race(tagged)` where each contender's promise is
  mapped to `{tag: i, value}`; dispatch on the tag into the winning
  branch's scope, with the per-cell minted binding
  (`__lazyDone__`-style) written there. The tagging is
  compile-internal, never user-visible.
- The drawn-order tie-break is free: `Promise.race` resolves with
  the first already-settled promise in argument order, and the
  emitted argument order is the drawn order.
- A subset merge's thunk is the same race with the complement's tags
  routed to the terminator write instead of a branch.
- Merge/interrupt lowerings carry the loser's still-in-flight cell
  into the recursion; the catalog-block status just means this walk
  is emitted, not authored.

## How this squares with the design principles

- **No bottlenecks.** Every survey race rebuilt the severed
  input↔output correspondence from side flags (finding 3.2) — what
  "the wires survive only as tag names" looks like in production
  code. The barrier restores it structurally.
- **Building blocks must build.** The +1 ladder is additive at every
  rung: await → *+ timer contender* = timeout → *+ a third
  contender* (shutdown) = the same barrier wider → *whole-walk
  deadline* = interrupt with the timer outside → *per-step deadline*
  = mint the timer inside → *+ why-did-it-end* = discharge the
  terminator. No rung rewrites the previous drawing. The unary-race
  identification is this principle at the bottom rung.
- **One obvious reading.** The tie-break is drawn (contender order),
  deadline scope is node placement, discrimination is cells — three
  facts that in the sampled code live in argument conventions, flag
  names, and exception types.
- **Example first.** The law's edges (already-settled ties, subset
  merges, dynamic sets) were each forced by a concrete sampled site
  or a recorded program, not invented for generality.
- **Abstraction is the source of truth.** Merge and interrupt are
  durable catalog blocks over readable corecursive lowerings;
  flattening nested races is a recognition, upward and earned.
- **Foundations before features.** Cancellation is not designed here
  despite the pressure — only its trigger is named, on the object
  (the cell) that already carries the constraint.

## The dead ends, indexed

All of this chapter's dead ends are recorded in place above, each in
the "you might wonder" passage of the section that owns it, with the
full reason it should not be re-proposed. For the design reader, the
index:

1. **A fairness knob on the race barrier** — "Is race fair?"
2. **Timeout as a primitive node** — "Merge, interrupt, and the
   timeout family."
3. **Interruption delivered in-band via the cancellation channel**
   (the websockets 4 shape) — "Merge, interrupt, and the timeout
   family."
4. **Late loser outputs on the covering collect** — "The law of the
   barrier," after the exactly-once rule.
5. **Dynamic-arity race** — "What if you don't know how many
   contenders?"

(The tagged-union race result, rejected in "Your first race," is
recorded upstream — `barrier-value-crossing-design.md`, dead end 3,
and `async-flow-design.md`, "Racing is a barrier, not a value" — not
numbered here.)

## Open questions

The language hasn't decided any of these yet.

1. **Adoption.** The whole chapter is prepared for the design
   conversation; nothing is marked decided.
2. **The unary-race identification.** Async uncollect = race at
   N = 1 is a leaning; the drawn form (does one contender look like
   an open?) and the spec entry should be decided together, with the
   visual side consulted.
3. **Subset-merge terminator payload.** Failable-by-construction is
   the lean; whether the payload is the bare settled-elsewhere fact,
   the winning cell's index, or (dirtier) the winning value is open,
   and should be decided jointly with the terminator
   payload-composition residue (`async-flow-design.md`). *The joint
   round now exists* (`failure-payloads-design.md`, exploration): the
   bare fact is confirmed by lane integrity — the winner's value
   belongs to the winner's lane, and a consumer that wants to know
   which contender won should consume the bundle's cells, not fish it
   from a loser's terminator.
4. **Cancellation interplay proper.** The lost-cell trigger is the
   recorded hook; the actual capability, delivery, and bracket
   ordering wait on the Tier-1 IO round. Race commits only to
   needing no new ports for it. *The round now exists*
   (`cancellation-design.md`, exploration): the trigger is consumed
   as drawn — settlement strands the losers' cells, delivery rides
   the demand frontier, and race indeed needed no new ports.
5. **The chooser family's round.** The decision-driven merge now
   also owns merge's fairness variants; its round should treat the
   async merge as a member, not a special case. *The round now
   exists* (`chooser-family-design.md`, exploration): the async
   merge is a member as asked — the walk with a race of the heads
   in the decision position, head-persistence being this chapter's
   carried loser cell stated at the walk level — and the fairness
   variants are drawn decisions reading a register on the step
   flow, extending this chapter's fairness-knob dead end (a mode
   would annotate what a drawing already states). The catalog-block
   status of merge and interrupt is unchanged.
6. **Spec and text.** Spec entries for the race barrier (and
   merge/interrupt as catalog blocks), plus textual spellings
   (`textual-representation-design.md`), are owed on adoption.
7. **Naming.** Race vs select; interrupt vs until; "contender";
   "settlement." Deferred to the naming sweep
   (`implementation-strategy.md`).
8. **Evidence.** Survey 3's corpora implement infrastructure; an
   application-level sample (how often application code reaches for
   race vs gather vs pool) is the named next round and would
   re-weight this area.

## What this chapter doesn't cover

- **Cancellation and the IO/effects design** — the Tier-1 gap is
  untouched beyond naming race's trigger for it.
- **The concurrent collect's own round** — lifecycle outputs,
  `bounded(n)`-as-resource, and the served flow are designed in
  `concurrent-collect-design.md`; this chapter only borrows its
  completions stream as the dynamic-set answer.
- **End-when's adoption** — the sibling confirmation here is
  mechanics evidence for that doc's conjecture, not a move in its
  adoption question.
- **Visual depiction** — barrier lines, cell drawings, and whether a
  unary race looks like an open are the layout side's questions, out
  of scope in this repo.
- **Implementation.** The async runtime (cells, failable
  terminators, stream integration) does not exist in the compiler;
  nothing here changes the recorded dependency order (streams, then
  async cells, then async streams / race / interrupt).
