# Cancellation and bracket: stopping is drawn, cancelling is delivered

Status: exploration (a worked proposal with leanings, prepared for a
design conversation — not adopted). Scope: the **cancellation** half of
the Tier-1 IO/effects/cancellation row (`open-problems.md`), plus its
construct-shaped consumer, **bracket** (acquire/use/release with release
reachable from abandonment). The effects half is the sibling round
(`effects-design.md`); this round assumes its thread and does not reopen
it. Deliberately not worked here, each fenced at the end: within-firing
effect ordering, the batched-effect construct, the permit-pool catalog
block, true preemption, and the served flow's body-fails leg.

Reading order: `effects-design.md` (the IO thread as a register on a
marker wire — the carrier this round was waiting on), `custom-flows.md`
(the lifecycle segment), `async-flow-design.md` ("Effects, abandonment,
cancellation" and the failability section), `race-barrier-design.md`
("Abandonment at the barrier" — the lost-cell trigger),
`concurrent-collect-design.md` (the drain law),
`incremental-flow-design.md` ("The residual hole is the cancellation
gap"). The prior art is `zig-comparison.md` (findings 6 and 8:
`defer`/`errdefer`'s four properties, cancel-as-await, the cooperative
floor); the field evidence is `real-loop-survey.md` survey 3 (finding
3.6: roughly eight of thirty orchestration sites, containing the
sample's most delicate code).

## What the record already fixes

Seven things are settled before this round starts; the round's job is to
connect them, and its claim to novelty is small on purpose.

1. **Abandonment is not cancellation.** A started promise cannot be
   unstarted; dropping every reference stops anyone *observing* work,
   and laziness guarantees un-pulled work never starts — but work in
   flight runs to completion, its result discarded
   (`async-flow-design.md`). For pure work that is wasted CPU; external
   resources convert it into a correctness hole ("a child process is not
   wasted CPU, it is a zombie holding fds" —
   `tough-use-cases-design.md`, break #3).

2. **The async cell is the carrier.** The recorded constraint: the async
   design must not preclude threading a cancellation capability through
   the cell later — "the cell is the natural carrier, since it is the
   unit that gets started and abandoned" (`async-flow-design.md`).

3. **The trigger already exists at every barrier.** At a race's
   settlement, every losing cell's never-fires status is determinate —
   the same event that writes subset-merge terminators is the event
   "contender i is now abandoned by this race." Per-consumer honesty
   lives at the cell: a loser shared with another live consumer is
   abandoned by the race, not by the program
   (`race-barrier-design.md`). The concurrent collect's interrupt on the
   completions side abandons in-flight bodies the same way
   (`concurrent-collect-design.md`).

4. **The signal channel and the cancellation channel are distinct.**
   Interruption delivered in-band *as* task cancellation is the recorded
   pathology (websockets 4's four-state uncancel dance) and a recorded
   dead end: signals are cells; cancellation, when it lands, is an
   effect on abandoned cells (`race-barrier-design.md`, dead end 3).

5. **The thread is in place.** A spanning effect handle is a register on
   a marker wire; its `final` is the handle after the loop — defined by
   the discharge machinery even when the walk ends early
   (`effects-design.md`, `first-class-ports-design.md`). The effects
   round named the thread "the carrier a cancellation capability would
   later ride"; this round is that rider.

6. **Bracket's required structure is known.** Zig's `defer`/`errdefer`
   supply four properties any bracket must reproduce: release adjacent
   to acquisition; cleanup keyed by exit reason; the infallibility
   asymmetry ("resource allocation may fail; resource deallocation must
   succeed"); attachment at per-firing as well as per-flow granularity
   (`zig-comparison.md`, finding 6). The tough-use-cases round adds:
   kill is not optional; release is itself effectful and async
   (waitpid), with a completion a supervisor may need to observe.

7. **Failability's machinery is general.** A flow kind's termination
   event can carry a payload; consumers propagate it by default and
   discharge it at a whole-flow collect, where it becomes ordinary data
   (`async-flow-design.md`). Zig's `Future.cancel` — "places a
   cancellation request" and *still returns the result* — is the field
   witness that cancellation fits this machinery: the cancelled
   computation terminates, with a readable terminator
   (`zig-comparison.md`, finding 8).

## The gap, stated precisely

The record has six documented arrivals of the same hole: the async doc's
lost racers, the incremental doc's abandoned pending pulls, the tough
round's leaked processes / fds / sockets / vanished clients, the
concurrent collect's "cancel harder" escalation stage, speculation's
effectful failed attempts, and every bracket demand. Each names a
trigger and defers the capability. The question all six defer is one
question:

> **When demand for in-flight work ceases, what — structurally — is the
> thing that happens, and how does the work's cleanup get to run?**

The field answers with an object: a token (`AbortController`, a
cancellation scope, a task handle) constructed by the party that might
stop wanting, threaded by hand into everything that might be stopped,
fired explicitly, caught defensively. Survey 3 shows what that object
costs in practice: check-then-subscribe registration races (undici 1),
task-set bookkeeping with ordering comments (websockets 2, uvicorn 2),
shield-guarded awaits (aiohttp 2), uncancel dances (websockets 4),
cancel-both-in-finally (websockets 5). The design below is one claim
about why all of that machinery exists: **it is a hand-built copy of
demand structure the language already has.**

## The central move: being cancelled is a way a flow ends

Two sentences, and the rest of the round is their consequences.

> **A program never cancels anything. It stops demanding things — and
> every way of stopping is already a drawn construct.** A race settles
> and strands its losers; an interrupt cuts a walk; an end-when ends
> one; a prefix-taking consumer takes its prefix. There is no other
> interior way for demand to cease (checked below).

> **Cancellation is the runtime delivering that ceased demand to the
> work it strands: the stranded flow ends, with a terminator.**
> `Cancelled` joins `Nil | Fail(e) | Stopped(v) | Interrupted(e)` as one
> more way a flow terminates. Everything downstream of that sentence is
> existing machinery: the terminator propagates by default through the
> stranded subtree, registers discharge their `final` at the cut,
> release halves fire keyed on the lane.

This splits the field's cancellation object into three roles and gives
each to something that already exists:

- **The decision** ("stop this") is drawn: race, interrupt, end-when.
  It is never delivered *as* cancellation — that is dead end 4 of the
  race round, kept.
- **The propagation** ("find everything that must stop") is the demand
  structure. Nothing is threaded, because the runtime already knows what
  is demanded by what — that knowledge is what a lazy runtime *is*.
- **The cleanup** ("release what the stranded work holds") is the
  bracket's release half, fired by the stranded flow's own terminator
  like any other discharge.

So there is no cancel token in the vocabulary. `AbortController` is the
demand tree, reified by hand in an eager language that discarded its
demand structure at compile time; a lazy language kept the structure and
can deliver over it. This is the same species of dissolution as
"timeout is not a construct" (`race-barrier-design.md`): the field's
object decomposes into drawn decisions plus derived delivery.

### The frontier identification

The propagation half is not even new machinery — it is machinery another
row already ordered. The incremental round's **necessity frontier**
(pending-or-lingering registrations holding a subgraph necessary,
refCount, watched-holds-alive — `incremental-flow-design.md`,
`reactive-comparison.md`) is exactly demand-liveness accounting, and
that round already observed that its one residual hole — a consumer
abandoned while its pull is pending — "is the async doc's abandonment ≠
cancellation gap in incremental clothing," closable by cancelling the
pending-pull cell.

The identification, made explicit: **liveness, memory, and cancellation
are one frontier.** A cell is live while some consumer's demand holds it
(the refcount is the per-consumer honesty of the race round); when the
last demand goes — a race settles, an interrupt fires, a registration
lapses — the frontier recedes past it; cancellation is the recession
*delivered*, as `Cancelled` terminators, to the in-flight cells the
recession strands. The reactive ecosystem's undisposed-observer leaks
and asyncio's GC'd-mid-flight tasks (uvicorn 5) are the two failure
modes of maintaining this frontier by hand — retaining too long and too
briefly, respectively — and both are accounting bugs in a structure the
runtime can own outright.

## The in-flight window: laziness bounds what cancellation is

An eager language must be able to cancel *anything*, because everything
it might not need is already running. A lazy language's account is
smaller, and worth stating as three cases because two of them are free:

- **Not yet started.** Un-demanded work never starts; a stranded lazy
  suffix is cancelled by never existing. This is most of the eager
  world's cancellation surface, handled by the evaluation model with no
  event at all.
- **Already settled.** A memoised settled cell is past cancelling;
  abandonment just makes it garbage.
- **In flight.** Started under real demand, then stranded. This — the
  **in-flight window** — is the entire subject matter of cancellation
  here. The capability is exactly: deliver a `Cancelled` terminator to
  in-flight cells the frontier's recession strands.

Delivery is at **yield points** — pull and await boundaries — the
record's existing stance ("interruption is checked at pull boundaries,"
`async-flow-design.md`), which is Zig's cooperative floor
(`cancelRequested` polling) given structurally. Effect operations on a
handle are atomic units; delivery lands between them, never inside one,
so a handle's op invariants cannot tear. Effects performed before the
cut happened — the half-write is real, reported honestly by the handle's
state at release (below). Compile-wise, delivery *is* the interrupt
machinery: every yield of an in-flight thunk is raced against its
strand event, inserted by the runtime on the demand side rather than
drawn. That the compile reuses interrupt's shape while the vocabulary
keeps the channels apart is the point: to the cancelled computation,
delivery is indistinguishable from its input ending — which is exactly
what makes it deliverable to code that never mentioned it.

**The foreign edge.** An in-flight *foreign* operation — a fetch in
flight, a blocked read, a sleeping timer, a child process — has no
interior yield points. Each external catalog block therefore carries a
**cancel translation**: how a delivered `Cancelled` maps onto the
foreign API (fetch → AbortSignal; timer → clearTimeout; child → kill;
blocked read → close the fd). This is where `AbortController` survives —
as a compile target at the boundary, beside the trusted-JS edge the
checking round already carries (`types-design.md` question 4), never as
vocabulary.

**A constraint for future optimisers, named now.** The window argument
assumes work starts only under real demand. A speculative optimiser (the
deferred placement pass, or any early-start heuristic) that starts work
without demand must also accept abandonment delivery for what it starts
— otherwise it widens the in-flight window behind the semantics' back.
Binding on any revival of compile-time placement
(`placement-algorithm-notes.md`).

## Silence exists only at the edges

The pull world's classic objection: abandonment is silence, not an
event — a consumer that stops pulling just stops. The dissolution this
round leans on: **inside a drawn program, there is no spelling of
silent abandonment.** A drawn program's demand comes from its declared
outputs; interior demand ceases only when a construct ceases it — a race
settles, an interrupt or end-when fires, a discharge completes, a
prefix-taker is satisfied. Each of those is an event with a place on the
canvas, and each is already recorded as a strand trigger. There is
nothing an interior program can draw that just *goes quiet*.

Silence exists only where the program meets the world, and at each such
edge something is in a position to convert it:

- **The root.** Process exit delivers `Cancelled` at the program's
  declared outputs; the frontier recedes from the top; every in-flight
  cell and every held resource is stranded, delivered, released. "The
  process must die with the program" (tough break #3) is this cascade —
  and aiohttp 3's worker root (spawn, run to completion, shut down
  generators, close) is it hand-rolled.
- **The served edge.** A requester vanishes mid-exchange: the serving
  FFI node converts the transport event into `Cancelled` on that
  exchange's flow. fastify 3 — client disconnect lazily minted as a
  per-request abort signal and delivered *into* the handler — is this
  leg built by hand, in exactly the per-firing shape the served flow's
  question 3 anticipated.

The GC-based teardown the incremental round kept as a stopgap is
demoted, not removed: finalizer-driven release is a **backstop against
runtime accounting bugs**, never the semantics — promptness at the
collector's pleasure is precisely what "deallocation must succeed" and
"the process must die with the program" cannot be built on.

## The Cancelled lane discharges outward only

`Cancelled` is a terminator tag, but not an interchangeable one, and the
asymmetry is the ontological content of this round:

- **Inside the stranded subtree, there is no one to discharge to.**
  `Fail(e)`, `Stopped(v)`, `Interrupted(e)` are dischargeable by the
  program into continued computation — a case split on the settled
  terminator, then onward. A `Cancelled` flow has, by construction, no
  live downstream: the consumer that would receive the continuation is
  the party whose ceased demand caused the terminator. So within the
  stranded subtree the lane has exactly one consumer species: **release
  halves.** No recovery arms, no resumption — which is why the delivered
  terminator needs no cooperation from code that never mentioned
  cancellation.
- **At the boundary, a live consumer reads it as data.** Where stranded
  work is observed from outside by someone still alive — the settle
  node's settled sum, a release-completion cell, a supervisor's fold
  over completions — cancellation is an ordinary case beside `Ok` and
  `Fail` (`concurrent-collect-design.md`'s per-firing discharged sum
  grows a `Cancelled` case). The supervisor consumes it; it doesn't die
  of it.

This is websockets 4's pathology inverted by construction. That code
delivers interruption *as* cancellation and then reconstructs provenance
(state enum, exception conversion, uncancel counting) so an outer real
cancellation still works. Here the two are different lanes written by
different constructs — a drawn interrupt writes `Interrupted(e)` on its
own flow; strand delivery writes `Cancelled` from the demand side — and
an outer cancellation crossing an inner interrupt needs no counting
because nothing conflated them.

Payload: the lean is the bare fact, no payload — matching the
subset-merge payload lean (`race-barrier-design.md`, open question 3):
delivering the abandoning consumer's identity or values through a lane
that consumer never engaged is the same dirtiness. Left open jointly
with failability's payload-composition residue.

## Bracket: the release half is a late-wired body on the acquire

With delivery in place, bracket stops being a construct that *needs*
cancellation and becomes a small amount of structure over it.

**The law.** *Every acquired handle reaches exactly one release, and the
release runs on whichever way the handle's segment ends — normal
terminator, failure terminator, or `Cancelled`.*

**The shape.** No region, no scope — the lifecycle segment
(`custom-flows.md`) already carries the pairing:

- **Acquire** is the segment's top vertex, minting the handle. It is
  failable (a refusal is the ordinary terminator machinery; Zig:
  allocation may fail), and — per `effects-design.md` — where the vertex
  sits *is* the granularity: under a firing, the bracket is per-firing;
  outside the loop with the thread spanning it, per-walk. Zig's
  property 4 (both granularities) costs no second mechanism.
- **Use** is the ops strung along the thread, as today.
- **Release** is a **late-wired body on the acquiring node** — the
  register-write-half two-phase shape (`step of` /
  `first-class-ports-design.md`), spelled provisionally `release of`:

  ```
  path -> openFile => ~f                 -- acquire: top vertex, failable
  ~f ~> write(line) in ~W => ~f'         -- use: ops along the thread
  release of ~f: close                   -- release half, late-wired  (provisional)
  ```

  The release body consumes two things, both already defined: **the
  handle as of the last completed operation** (for a spanning handle,
  the marker register's `final`, which the discharge machinery defines
  at whatever point the walk actually ended — you close the file at the
  position it really reached, half-write and all), and **the
  terminator**, for per-lane discrimination. One body ignoring the tag
  is `defer`; a case split on the tag is `errdefer` with the payload
  readable:

  ```
  release of ~f: term ->                 -- (provisional per-lane form)
    split tag of Done, Failed, Cancelled
    Done:      close
    Failed:    close; path -> unlink     -- undo the partial artifact
    Cancelled: close; path -> unlink
  ```

Adjacency (Zig property 1) is the late wiring itself: the release is
written at the acquire, not at the exits, and there are no exits to
cover because the terminator machinery visits every ending — including
the one no exit-covering code can reach, abandonment.

**Ordering is the thread's, where it matters.** A handle minted *from*
another handle's ops (a channel from a connection) threads it, so the
inner release is upstream of the outer release's input — LIFO forced by
wiring exactly where dependence exists. Independent handles' releases
commute, per the custom-flow rule; no stack discipline is imposed where
none is meant.

**The infallibility asymmetry, structurally.** The use's terminator is
already written when release runs; there is no lane left for release to
fail *into*. So release's hole **demands an infallible filler** — the
demands/offers vocabulary's "this hole demands a pure filler," one
flavor over (`types-design.md`, question 4; `flix-comparison.md`) — and
anything release must report (waitpid status, close errors) is **data on
its completion cell**, never a terminator. Which meets the
tough-use-cases demand from the other side: release is effectful and
async, and its completion is an async value a supervisor can observe
(the keyed-lane replacement serialisation of break #2 consumes exactly
this cell).

**Release is not cancellable.** It runs past the terminator; no demand
remains whose cessation could strand it — the law itself is its demand.
Stated honestly: the release body is the one place execution is not
consumer-demanded, the delivery seam's mirror image (external events are
the push-into-pull seam on the way in; terminator delivery and release
are the seam on the way out). This is `shield`'s legitimate half, made
structural instead of guarded.

## Worked examples

**Race implies cancel (websockets 5, redrawn).** Two stream-drains raced
— server→screen against stdin→server:

```
incoming: drainD                      -- async<unit>: the incoming pump's drain
outgoing: drainD2
-> race => r
~r.incoming: …                        -- server closed first
~r.outgoing: …                        -- user hit ^D first
-~> collect => session
```

The source's `finally: incoming.cancel(); outgoing.cancel();
transport.close()` has no counterpart drawn. At settlement the loser's
cells are stranded (the lost-cell trigger); delivery lands at the
loser's next pull; the socket handle's bracket — whose acquire the
drains share — releases on the `Cancelled` lane. Race needed no new
ports, as its round promised.

**The graceful-shutdown ladder (aiohttp 2, redrawn).** Three stages,
each one node, on the concurrent collect's two sides:

1. *Stop accepting*: interrupt on the **subject** — new firings cease.
2. *Bounded drain*: the completions flow drains to its terminator by the
   drain law; the deadline is `interrupt(completions, timer)`.
3. *Escalate*: the stage-2 interrupt's firing strands the in-flight
   bodies — the delivery this round defines. Each body's brackets
   release on `Cancelled`; a process handle's release *is* the kill.
   "Wait for the thing you are cancelling" — the `shield` — is nothing
   guarded: cancellation is itself a discharge (cancel-as-await), so
   each stranded body still settles, as `Cancelled`, in the completions
   flow; the supervisor's fold reads them as data. A final deadline on
   stubborn releases is one more timer against the release-completion
   cells; the last resort is the root's own cascade.

The four-state machine, the uncancel counter, and the shield are all
structure here — which is the claim finding 3.6 wanted tested against
the sample's hardest site.

**The vanished requester (fastify 3, redrawn).** The serving FFI node
converts transport close into `Cancelled` on that exchange's flow; the
handler body's brackets release; in-flight foreign work under the
handler is cancelled through its catalog translations. Nothing is
lazily minted, wired onward, or checked-then-subscribed by hand. (The
dual leg — the body fails, what does the requester receive — stays with
the served flow's round.)

**The abandoned waiter (undici 5, sketched).** A pool's waiter queue is
pending pulls on permit cells; a waiter whose requester gives up
(timeout on the acquire) is a stranded pending pull — delivery removes
it from the queue, which is the incremental round's
deregistration-on-abandonment, identically. The pool block itself
(permits, fairness of the queue, bounded acquire) stays a fenced round;
this only shows its waiters need no machinery of their own.

## Against the philosophy

- **Inside-out.** No scopes and no regions: the bracket is a pairing on
  a drawn segment; ownership and granularity are read off vertex
  placement; delivery propagates over demand, not over lexical
  containment.
- **No bottlenecks.** Nothing is packed to cross the ending: release
  reads the handle and the terminator as themselves, per lane; a
  supervisor reads stranded work as cases of the settled sum, wires
  intact.
- **Example first.** Every element was forced by a sampled site or a
  recorded program: the ladder by aiohttp 2, the finally-pair by
  websockets 5, the served leg by fastify 3, the retention backstop by
  uvicorn 5 and aiohttp 4, the uncancel inversion by websockets 4, the
  release-observability demand by waitpid.
- **Building blocks must build.** The +1 ladder: straight-line use →
  *+ release* (defer) → *+ per-lane release* (errdefer) → *+ observed
  release completion* (supervised replacement) → *+ drain deadline* →
  *+ escalation*. Each rung adds a node or a lane to the previous
  drawing; the beginner's open/use/close segment is the same drawing
  the shutdown ladder is built from.
- **Abstraction is the source of truth.** The delivered interrupt is
  compile machinery under a vocabulary-level lane, the same
  representation-vs-compilation split as race's tagged promises; the
  ladder is a composition of durable blocks, not a shutdown construct.
- **Foundations before features.** The capability is deliberately
  minimal — one terminator lane, delivered at yield points, over
  accounting another row already ordered — and everything else in the
  field's cancellation APIs is shown as either a drawn decision or a
  hand copy of demand structure.

## Dead ends recorded

Reasons kept short and forward-looking, so they are not re-proposed.

1. **A user-facing cancel token / capability wire** (AbortController as
   vocabulary; a cancel port threaded through computations). Rejected:
   it reifies the demand tree by hand and creates a second source of
   truth that can disagree with actual demand (cancelled-but-demanded,
   demanded-but-cancelled — the field's flag checks are exactly this
   disagreement being reconciled). Signals a *program* sends are
   interrupt cells; the channels stay distinct.

2. **Cancellation as an operation one computation performs on another**
   (`task.cancel()`). Rejected: a write into a sibling's lifecycle that
   no wire carries — action at a distance, condemned by the same
   stances that forbid time travel — and it forces the canceller to
   hold references to everything cancellable, which is precisely the
   task-set bookkeeping the survey found defended by comments. Stopping
   is drawn in the stopper's own flow; delivery is the runtime's.

3. **Delivering cancellation on the Fail lane** (CancelledError).
   Rejected: `Fail` is dischargeable into continued computation, so
   stranded code would have to distinguish "my dependency failed" from
   "nobody wants me" — the websockets-4 uncancel dance is the cost,
   witnessed. `Cancelled` is a lane whose interior discharge does not
   exist, and that restriction is load-bearing.

4. **Bracket as a drawn region or with-block.** Rejected: a region
   makes an interior differ from its exterior (the inside-out
   violation), needs a second story for per-firing cleanup, and
   duplicates what the lifecycle segment already carries. Granularity
   by vertex placement gives Zig's property 4 for free; a region form
   would make it a mode.

5. **GC/finalizer-based release as the semantics.** Rejected:
   promptness at the collector's pleasure cannot carry "deallocation
   must succeed" or "the process must die with the program"; fds and
   children are correctness, not memory. Kept strictly as a backstop
   against runtime accounting bugs.

6. **Preemptive delivery at arbitrary points.** Rejected: JS offers no
   preemption; mid-op delivery would tear handle invariants; and the
   record's pull-boundary stance already defines the yield points.
   What genuinely cannot wait for a yield point is foreign and goes
   through the catalog block's cancel translation instead.

## Open questions this round leaves

1. **Adoption.** Prepared for the design conversation — jointly with
   the effects round: the Tier-1 row's two halves are one conversation,
   since the release half consumes the thread's `final` and the
   delivery rides the frontier.
2. **The Cancelled payload.** Bare fact (the lean) vs provenance (which
   consumer abandoned) — jointly with failability's payload-composition
   residue and the subset-merge payload question.
3. **The release spelling.** `release of <handle>` as the late-wired
   form; whether per-lane release is one body with a split (as drawn
   above) or per-lane bodies; how the release-completion cell is named.
   Jointly owned with `textual-representation-design.md` and
   `first-class-ports-design.md`.
4. **The cancel-translation schema.** What an external catalog block
   declares about its foreign cancellation (idempotence, promptness,
   whether the foreign op reports post-cancel state) — the checking
   round's trusted-JS-edge schema (question 4) gains a second concrete
   content demand beside the identity witnesses.
5. **The permit pool block.** Bracket plus delivery cover the waiters;
   the block itself (permits as permanent tokens, queue fairness,
   failable acquire, `bounded` width × permits —
   `concurrent-collect-design.md` question 4) is now unblocked and owed
   its own round.
6. **Multi-close frontier accounting.** One flow collected by two
   consumers, one of which is abandoned: the frontier's refcount is
   per-cell, but walks share structure — confirm the accounting at walk
   granularity, jointly with the effects round's one-threading-consumer
   question (its open question 4).
7. **The register's final at a Cancelled cut.** The discharge readout
   of a register (and the marker register) under early termination is
   already shared residue with end-when's final-readout anchor; confirm
   `Cancelled` needs nothing beyond that answer.
8. **The at-risk derived view.** The async round asked what the diagram
   shows when a race implies possible cancellation of a subgraph. This
   round's answer is "nothing new is authored" — the candidate is a
   *derived view* highlighting the demand subtree stranded if a given
   contender loses. Layout-side; named here so it is not re-invented as
   structure.
9. **Naming.** "Cancelled" vs "Abandoned" vs "Stranded"; "bracket" vs
   acquire/release; "release" vs "close". Deferred to the naming sweep
   (`implementation-strategy.md`).

## What this doesn't address

- **Within-firing effect ordering** (the conditional-flush buffer) —
  the distinct axis fenced by the effects round, still owned jointly by
  registers + effects.
- **The batched-effect construct** — the collected-plan pole's own
  round, unchanged.
- **The permit pool, the served flow's own round, the chooser family** —
  fenced above and in their owning docs.
- **True preemption and workers** — out of scope with the async round's
  event-loop stance.
- **Visual depiction** — segment drawings, release-half rendering, the
  at-risk view: layout-side, out of scope in this repo.
- **Implementation.** Nothing here exists in the compiler. The
  dependency order extends the async round's: streams, then async
  cells, then frontier accounting (shared with the incremental
  runtime), then delivery and brackets. The interrupt compile is
  reused; the only genuinely new runtime piece is the frontier's strand
  event.
