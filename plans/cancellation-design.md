# Cancellation and bracket: stopping is drawn, cancelling is delivered

Status: exploration — this chapter teaches a worked proposal that has
not been adopted yet; none of it is implemented. It was prepared, with
its leanings stated, for a design conversation, so read it as "here is
a candidate and the case for it." Its scope is the **cancellation**
half of the Tier-1 IO/effects/cancellation row (`open-problems.md`),
plus the construct that most needs it, **bracket** — acquire, use,
release, with the release guaranteed to run even when the work is
abandoned partway. The effects half of that row is the sibling chapter
(`effects-design.md`); this chapter assumes its thread and does not
reopen it. Update (2026-08-04): terminators now carry only the
reason a flow ended (`end-when-design.md`, revision notes) — the
`Cancelled` terminator survives as a reason tag, but any payload it
was to carry (open question 2) must arrive by value wire instead;
and bracket now has a home shape — the C-shaped sub-diagram used
flow-wise (`late-bound-operations-design.md`, revision notes
2026-08-04), which this chapter's bracket sections should be
re-read against. Five neighbouring topics are deliberately *not* worked
here, each fenced in the closing section: within-firing effect
ordering, the batched-effect construct, the permit-pool catalog block,
true preemption, and the served flow's body-fails leg.

## What to read first

This chapter connects threads from several earlier ones. If you meet
an unfamiliar construct below, its home is one of these:
`effects-design.md` (the IO thread — a spanning handle's per-firing
segments, commuted out of the loop in firing order — the carrier
this chapter was waiting on), `custom-flows.md` (the
lifecycle segment), `async-flow-design.md` ("Effects, abandonment,
cancellation" and the failability section), `race-barrier-design.md`
("Abandonment at the barrier" — the lost-cell trigger),
`concurrent-collect-design.md` (the drain law), and
`incremental-flow-design.md` ("The residual hole is the cancellation
gap"). The prior art studied is `zig-comparison.md` (findings 6 and 8:
the four properties of `defer`/`errdefer`, cancel-as-await, the
cooperative floor); the field evidence is `real-loop-survey.md`
survey 3 (finding 3.6: roughly eight of thirty orchestration sites
involve cancellation, and they contain the sample's most delicate
code).

## A race, and the question it leaves behind

You will often start two pieces of work and only need whichever
finishes first. Here is a real program shape — a chat session that
runs until *either* the server closes the connection *or* the user
hits Ctrl-D (this is site websockets 5 from survey 3, redrawn):

```
incoming: drainD                      -- async<unit>: the incoming pump's drain
outgoing: drainD2
-> race => r
~r.incoming: …                        -- server closed first
~r.outgoing: …                        -- user hit ^D first
-~> collect => session
```

Two stream-drains are raced — server→screen against stdin→server.
Each contender enters the race on its own labeled lane, and — because
a race is a barrier, not a funnel — each leaves on its own lane too:
`~r.incoming` fires if the incoming drain won, `~r.outgoing` if the
outgoing one did. You handle whichever lane fired, and the collect
closes the session.

Now the question. When the race settles, the *loser* is still in
flight — still pumping bytes through a socket. In the original Python,
the author wrote `finally: incoming.cancel(); outgoing.cancel();
transport.close()` — three lines of explicit stopping-and-cleanup. In
the program above, none of that is drawn. Is that a hole, or a
feature?

This chapter's answer: it is the feature. Nothing needs to be drawn,
because *stopping* already was drawn — the race is the stopping — and
what remains, delivering that stop to the loser and running its
cleanup, is the runtime's job, done over structure the language
already has. The rest of the chapter builds up to exactly what
happens to that loser and its socket.

## Three fates for a piece of work

Start with a fact recorded back in `async-flow-design.md`:
**abandonment is not cancellation**. A started promise cannot be
unstarted. Dropping every reference to it stops anyone *observing* the
work, and laziness guarantees un-pulled work never starts — but work
already in flight runs to completion, its result discarded. For pure
computation that is merely wasted CPU. The moment external resources
are involved, it becomes a correctness hole: "a child process is not
wasted CPU, it is a zombie holding fds" (`tough-use-cases-design.md`,
break #3).

An eager language must be able to cancel *anything*, because
everything it might not need is already running. A lazy language's
account is smaller, and worth stating as three cases — because two of
them cost nothing:

- **Not yet started.** Un-demanded work never starts; a stranded lazy
  suffix is cancelled by never existing. This is most of the eager
  world's cancellation surface, handled by the evaluation model with
  no event at all.
- **Already settled.** A memoised settled cell is past cancelling;
  abandonment just makes it garbage.
- **In flight.** Started under real demand, then stranded — like our
  losing drain. This — the **in-flight window** — is the entire
  subject matter of cancellation here.

The capability this chapter proposes is exactly: deliver a signal to
the in-flight cells that a receding demand strands. What that signal
is, and how it travels, comes next.

## The central idea: being cancelled is a way a flow ends

Two sentences carry the whole design; everything after them is
consequences.

> **A program never cancels anything. It stops demanding things — and
> every way of stopping is already a drawn construct.** A race settles
> and strands its losers; an interrupt cuts a walk; an end-when ends
> one; a prefix-taking consumer takes its prefix. There is no other
> interior way for demand to cease (checked in "Silence exists only at
> the edges" below).

> **Cancellation is the runtime delivering that ceased demand to the
> work it strands: the stranded flow ends, with a terminator.**
> `Cancelled` joins `Nil | Fail(e) | Stopped(v) | Interrupted(e)` as
> one more way a flow terminates. Everything downstream of that
> sentence is existing machinery: the terminator propagates by default
> through the stranded subtree, registers discharge their `final` at
> the cut, release halves fire keyed on the lane.

(A *terminator*, if you're arriving fresh: every flow kind's ending is
an event that can carry a tag and payload — the machinery introduced
for failability in `async-flow-design.md`. To *discharge* a terminator
is to turn it back into ordinary data a live program can look at.)

Conventional runtimes bundle cancellation into one object — an
`AbortController`, a cancellation scope, a task handle. This design
splits that object into three roles and gives each to something that
already exists:

- **The decision** ("stop this") is drawn: race, interrupt, end-when.
  It is never delivered *as* cancellation — that is dead end 4 of the
  race chapter, kept here.
- **The propagation** ("find everything that must stop") is the
  demand structure. Nothing is threaded by hand, because the runtime
  already knows what is demanded by what — that knowledge is what a
  lazy runtime *is*.
- **The cleanup** ("release what the stranded work holds") is the
  bracket's release half, fired by the stranded flow's own terminator
  like any other discharge.

## Why there is no cancel token

Now, you might wonder why the language doesn't just have a cancel
token — an `AbortController`, a cancellation scope, a task handle: an
object constructed by the party that might stop wanting, threaded by
hand into everything that might be stopped, fired explicitly, caught
defensively. That is, after all, how the entire field answers this
question. It turns out this would cause problems: a token rebuilds the
demand tree by hand as a runtime object, and that hand-built copy is a
second source of truth that can disagree with actual demand — a thing
can be cancelled-but-demanded, or demanded-but-cancelled, and the
field's ubiquitous flag checks are exactly this disagreement being
reconciled. Signals that a *program* sends remain interrupt cells; the
signal channel and the cancellation channel stay distinct.
`AbortController` is the demand tree, built by hand in an eager
language that discarded its demand structure at compile time; a lazy
language kept the structure and can deliver over it. This is the same
species of dissolution as "timeout is not a construct"
(`race-barrier-design.md`): the field's object decomposes into drawn
decisions plus derived delivery. (This is a settled rejection —
dead end 1 of this chapter — please don't re-propose it without new
evidence.)

You might also wonder why one computation can't simply cancel another
— a `task.cancel()`, the way asyncio spells it. It turns out this
would cause problems too: it is a write into a sibling's lifecycle
that no wire carries — action at a distance, condemned by the same
stances that forbid time travel — and it forces the canceller to hold
references to everything cancellable, which is precisely the task-set
bookkeeping the survey found defended by nervous ordering comments.
Stopping is drawn in the stopper's own flow; delivery is the
runtime's. (This is a settled rejection — dead end 2 — please don't
re-propose it without new evidence.)

## One bookkeeping: liveness, memory, and cancellation

The propagation half of the design is not even new machinery — it is
machinery another row already ordered. The incremental chapter's
**necessity frontier** (pending-or-lingering registrations holding a
subgraph necessary, refCount, watched-holds-alive —
`incremental-flow-design.md`, `reactive-comparison.md`) is exactly
demand-liveness accounting. And that chapter already observed that its
one residual hole — a consumer abandoned while its pull is pending —
"is the async doc's abandonment ≠ cancellation gap in incremental
clothing," closable by cancelling the pending-pull cell.

Made explicit, the identification is: **liveness, memory, and
cancellation are one frontier.** A cell is live while some consumer's
demand holds it (the refcount is the per-consumer honesty of the race
chapter); when the last demand goes — a race settles, an interrupt
fires, a registration lapses — the frontier recedes past it; and
cancellation is that recession *delivered*, as `Cancelled`
terminators, to the in-flight cells the recession strands.

The field shows both ways this frontier fails when maintained by
hand. The reactive ecosystem's undisposed-observer leaks retain too
long; asyncio's GC'd-mid-flight tasks (site uvicorn 5) retain too
briefly. Both are accounting bugs in a structure the runtime can own
outright.

## How the terminator is delivered

Where, exactly, does a `Cancelled` terminator land in the stranded
work? At **yield points** — pull and await boundaries. This is the
record's existing stance ("interruption is checked at pull
boundaries," `async-flow-design.md`), and it is Zig's cooperative
floor (`cancelRequested` polling) given structurally rather than by
convention.

Effect operations on a handle are atomic units; delivery lands
*between* them, never inside one, so a handle's operation invariants
cannot tear. Effects performed before the cut *happened* — the
half-written file is real, and it is reported honestly by the handle's
state at release (see the bracket section).

Compile-wise, delivery *is* the interrupt machinery: every yield of an
in-flight thunk is raced against its strand event, inserted by the
runtime on the demand side rather than drawn by the author. That the
compile reuses interrupt's shape while the vocabulary keeps the two
channels apart is the point: to the cancelled computation, delivery is
indistinguishable from its input ending — which is exactly what makes
it deliverable to code that never mentioned cancellation at all.

Now, you might wonder why delivery couldn't be preemptive — landing
at any instruction, the way an operating system delivers a signal, so
nothing can ignore it. It turns out this would cause problems:
JavaScript offers no preemption to build on; mid-operation delivery
would tear handle invariants; and the record's pull-boundary stance
already defines the yield points. What genuinely cannot wait for a
yield point is foreign, and goes through the catalog block's cancel
translation instead (next paragraph). (This is a settled rejection —
dead end 6 — please don't re-propose it without new evidence.)

**The foreign edge.** An in-flight *foreign* operation — a fetch in
flight, a blocked read, a sleeping timer, a child process — has no
interior yield points. Each external catalog block therefore carries a
**cancel translation**: how a delivered `Cancelled` maps onto the
foreign API (fetch → AbortSignal; timer → clearTimeout; child → kill;
blocked read → close the fd). This is where `AbortController`
survives — as a compile target at the boundary, beside the trusted-JS
edge the checking chapter already carries (`types-design.md`,
question 4) — never as vocabulary.

**A constraint for future optimisers, named now.** The in-flight
window argument assumes work starts only under real demand. A
speculative optimiser (the deferred placement pass, or any early-start
heuristic) that starts work *without* demand must also accept
abandonment delivery for what it starts — otherwise it widens the
in-flight window behind the meaning's back. This is binding on any
revival of compile-time placement (`placement-algorithm-notes.md`).

## Silence exists only at the edges

The pull world's classic objection to all of this: abandonment is
silence, not an event — a consumer that stops pulling just stops, and
you cannot deliver "nobody wants you" if nobody says so. The
dissolution this chapter leans on: **inside a drawn program, there is
no way to spell silent abandonment.** A drawn program's demand comes
from its declared outputs; interior demand ceases only when a
construct ceases it — a race settles, an interrupt or end-when fires,
a discharge completes, a prefix-taker is satisfied. Each of those is
an event with a place on the canvas, and each is already recorded as a
strand trigger. There is nothing an interior program can draw that
just *goes quiet*.

Silence exists only where the program meets the world, and at each
such edge something is in a position to convert it into an event:

- **The root.** Process exit delivers `Cancelled` at the program's
  declared outputs; the frontier recedes from the top; every in-flight
  cell and every held resource is stranded, delivered, released. "The
  process must die with the program" (tough break #3) is this
  cascade — and site aiohttp 3's worker root (spawn, run to
  completion, shut down generators, close) is it hand-rolled.
- **The served edge.** A requester vanishes mid-exchange: the serving
  FFI node converts the transport event into `Cancelled` on that
  exchange's flow. Site fastify 3 — client disconnect lazily minted as
  a per-request abort signal and delivered *into* the handler — is
  this leg built by hand, in exactly the per-firing shape the served
  flow's question 3 anticipated.

Now, you might wonder why the language doesn't just lean on the
garbage collector for all of this — let finalizers close the files and
kill the children when the stranded cells get collected, the way the
incremental chapter's stopgap did. It turns out this cannot be the
meaning of release: promptness at the collector's pleasure is
precisely what "deallocation must succeed" and "the process must die
with the program" cannot be built on; file descriptors and child
processes are correctness, not memory. The GC-based teardown is
therefore demoted, not removed: finalizer-driven release is kept
strictly as a **backstop against runtime accounting bugs**, never the
semantics. (This is a settled rejection of GC-as-the-meaning —
dead end 5 — please don't re-propose it without new evidence; the
backstop role stays.)

## What you can do with a Cancelled flow

`Cancelled` is a terminator tag, but not an interchangeable one, and
the asymmetry is the heart of what this chapter claims cancellation
*is*:

- **Inside the stranded subtree, there is no one to discharge to.**
  `Fail(e)`, `Stopped(v)`, `Interrupted(e)` are dischargeable by the
  program into continued computation — a case split on the settled
  terminator, then onward. A `Cancelled` flow has, by construction, no
  live downstream: the consumer that would receive the continuation is
  the very party whose ceased demand caused the terminator. So within
  the stranded subtree the lane has exactly one consumer species:
  **release halves.** No recovery arms, no resumption — which is why
  the delivered terminator needs no cooperation from code that never
  mentioned cancellation.
- **At the boundary, a live consumer reads it as data.** Where
  stranded work is observed from outside by someone still alive — the
  settle node's settled sum, a release-completion cell, a supervisor's
  fold over completions — cancellation is an ordinary case beside `Ok`
  and `Fail` (the concurrent collect's per-firing discharged sum grows
  a `Cancelled` case). The supervisor consumes it; it doesn't die of
  it.

Now, you might wonder why the language doesn't just deliver
cancellation on the `Fail` lane — a `CancelledError`, the way Python
does it, so no new lane is needed. It turns out this would cause
problems: `Fail` is dischargeable into continued computation, so
stranded code would have to distinguish "my dependency failed" from
"nobody wants me" — and the websockets-4 uncancel dance is the
witnessed cost of getting that wrong. `Cancelled` is a lane whose
interior discharge does not exist, and that restriction is
load-bearing. (This is a settled rejection — dead end 3 — please
don't re-propose it without new evidence.)

Site websockets 4 is worth dwelling on, because this design is its
pathology inverted by construction. That code delivers interruption
*as* cancellation and then reconstructs where the signal came from
(a state enum, exception conversion, uncancel counting) so that an
outer *real* cancellation still works. Here the two are different
lanes written by different constructs — a drawn interrupt writes
`Interrupted(e)` on its own flow; strand delivery writes `Cancelled`
from the demand side — and an outer cancellation crossing an inner
interrupt needs no counting, because nothing conflated them.

What payload does a `Cancelled` terminator carry? The lean is: the
bare fact, no payload — matching the subset-merge payload lean
(`race-barrier-design.md`, open question 3). Delivering the abandoning
consumer's identity or values through a lane that consumer never
engaged is the same dirtiness in both places. This is left open,
jointly with failability's payload-composition residue (open
question 2 below).

## Bracket: pairing an acquire with its release

With delivery in place, bracket stops being a construct that *needs*
cancellation and becomes a small amount of structure over it. Here is
the whole shape — open a file, write to it, and promise it gets
closed:

```
path -> openFile => ~f                 -- acquire: top vertex, failable
~f ~> write(line) in ~W => ~f'         -- use: ops along the thread
release of ~f: close                   -- release half, late-wired  (provisional)
```

Three parts, no region, no scope — the lifecycle segment
(`custom-flows.md`) already carries the pairing:

- **Acquire** is the segment's top vertex, minting the handle. It is
  failable — a refusal is the ordinary terminator machinery (Zig:
  allocation may fail) — and, per `effects-design.md`, *where the
  vertex sits is the granularity*: place it under a firing and the
  bracket is per-firing; place it outside the loop with the thread
  spanning it and the bracket is per-walk. Zig's property 4 (cleanup
  at both granularities) costs no second mechanism.
- **Use** is the ops strung along the thread, exactly as the effects
  chapter has them.
- **Release** is a **late-wired body on the acquiring node** — the
  same two-phase shape as the register's write half (`step of`; the
  retired first-class-ports round — see `src/ARCHITECTURE.md`),
  spelled provisionally `release of`.

**The law.** *Every acquired handle reaches exactly one release, and
the release runs on whichever way the handle's segment ends — normal
terminator, failure terminator, or `Cancelled`.*

The release body consumes two things, both already defined. First,
**the handle as of the last completed operation** — for a spanning
handle, the tail of the segments concatenated so far: the sequencing
commute truncated at the cut, defined at whatever point the walk
actually ended. You close the file
at the position it really reached, half-write and all. Second, **the
terminator**, so the body can discriminate per lane. One body that
ignores the tag is `defer`; a case split on the tag is `errdefer` with
the payload readable:

```
release of ~f: term ->                 -- (provisional per-lane form)
  split tag of Done, Failed, Cancelled
  Done:      close
  Failed:    close; path -> unlink     -- undo the partial artifact
  Cancelled: close; path -> unlink
```

**Adjacency for free.** Zig's property 1 — release written next to
acquisition — is the late wiring itself: the release is written at the
acquire, not at the exits. And there are no exits to cover, because
the terminator machinery visits every ending — including the one that
no exit-covering code in a conventional language can reach,
abandonment.

**Ordering is the thread's, where it matters.** A handle minted *from*
another handle's ops (a channel from a connection) threads it, so the
inner release is upstream of the outer release's input — last-in,
first-out, forced by wiring exactly where dependence exists.
Independent handles' releases commute, per the custom-flow rule; no
stack discipline is imposed where none is meant.

**Release cannot fail — structurally.** By the time release runs, the
use's terminator is already written; there is no lane left for release
to fail *into*. So release's hole **demands an infallible filler** —
the demands/offers vocabulary's "this hole demands a pure filler," one
flavor over (`types-design.md`, question 4; `flix-comparison.md`).
Anything release must report — a waitpid status, close errors — is
**data on its completion cell**, never a terminator. And that meets
the tough-use-cases demand from the other side: release is itself
effectful and async (waitpid), and its completion is an async value a
supervisor can observe — the keyed-lane replacement serialisation of
break #2 consumes exactly this cell.

**Release is not cancellable.** It runs past the terminator; no demand
remains whose cessation could strand it — the law itself is its
demand. Stated honestly: the release body is the one place in the
language where execution is not consumer-demanded. It is the delivery
seam's mirror image — external events are the push-into-pull seam on
the way in; terminator delivery and release are the seam on the way
out. This is `shield`'s legitimate half, made structural instead of
guarded.

Now, you might wonder why bracket isn't a drawn region or a
with-block — `with open(path) as f:` is, after all, the most familiar
spelling in the field. It turns out this would cause problems: a
region makes an expression's interior differ from its exterior (the
inside-out violation), it needs a second story for per-firing cleanup,
and it duplicates what the lifecycle segment already carries.
Granularity by vertex placement gives Zig's property 4 for free; a
region form would make it a mode. (This is a settled rejection —
dead end 4 — please don't re-propose it without new evidence.)

## Putting it together

**Race implies cancel (websockets 5, resolved).** Back to the opening
example. The source's `finally: incoming.cancel(); outgoing.cancel();
transport.close()` has no counterpart drawn. At settlement the loser's
cells are stranded (the lost-cell trigger); delivery lands at the
loser's next pull; the socket handle's bracket — whose acquire the
drains share — releases on the `Cancelled` lane. Race needed no new
ports, as its chapter promised.

**The graceful-shutdown ladder (aiohttp 2, redrawn).** Three stages,
each one node, on the concurrent collect's two sides:

1. *Stop accepting*: an interrupt on the **subject** — new firings
   cease.
2. *Bounded drain*: the completions flow drains to its terminator by
   the drain law; the deadline is `interrupt(completions, timer)`.
3. *Escalate*: the stage-2 interrupt's firing strands the in-flight
   bodies — the delivery this chapter defines. Each body's brackets
   release on `Cancelled`; a process handle's release *is* the kill.
   "Wait for the thing you are cancelling" — the `shield` — is
   nothing guarded: cancellation is itself a discharge
   (cancel-as-await), so each stranded body still settles, as
   `Cancelled`, in the completions flow, and the supervisor's fold
   reads them as data. A final deadline on stubborn releases is one
   more timer against the release-completion cells; the last resort is
   the root's own cascade.

The original site's four-state machine, uncancel counter, and shield
are all structure here — which is exactly the claim finding 3.6 wanted
tested against the sample's hardest site.

**The vanished requester (fastify 3, redrawn).** The serving FFI node
converts transport close into `Cancelled` on that exchange's flow; the
handler body's brackets release; in-flight foreign work under the
handler is cancelled through its catalog translations. Nothing is
lazily minted, wired onward, or checked-then-subscribed by hand. (The
dual leg — the body fails, what does the requester receive — stays
with the served flow's own round; *now worked there*,
`served-flow-design.md`: the response lane is failable per-exchange,
and the wire-level translation is the serving block's catalog-row
policy beside this round's cancel-in translation.)

**The abandoned waiter (undici 5, sketched).** A pool's waiter queue
is pending pulls on permit cells; a waiter whose requester gives up
(a timeout on the acquire) is a stranded pending pull — delivery
removes it from the queue, which is the incremental chapter's
deregistration-on-abandonment, identically. The pool block itself
(permits, fairness of the queue, bounded acquire) stays a fenced
round; this example only shows its waiters need no machinery of their
own.

## Where this shows up in real code

The design record has six documented arrivals of the same hole: the
async chapter's lost racers, the incremental chapter's abandoned
pending pulls, the tough round's leaked processes / fds / sockets /
vanished clients, the concurrent collect's "cancel harder" escalation
stage, speculation's effectful failed attempts, and every bracket
demand. Each names a trigger and defers the capability. The question
all six defer is one question:

> **When demand for in-flight work ceases, what — structurally — is
> the thing that happens, and how does the work's cleanup get to
> run?**

The field answers with an object: a token (`AbortController`, a
cancellation scope, a task handle) constructed by the party that might
stop wanting, threaded by hand into everything that might be stopped,
fired explicitly, caught defensively. Survey 3 shows what that object
costs in practice: check-then-subscribe registration races (undici 1),
task-set bookkeeping with ordering comments (websockets 2, uvicorn 2),
shield-guarded awaits (aiohttp 2), uncancel dances (websockets 4),
cancel-both-in-finally (websockets 5). The design in this chapter is
one claim about why all of that machinery exists: **it is a hand-built
copy of demand structure the language already has.**

## What was already settled before this chapter

Seven things were fixed in the record before this round started; the
round's job is to connect them, and its claim to novelty is small on
purpose.

1. **Abandonment is not cancellation.** A started promise cannot be
   unstarted; dropping every reference stops anyone *observing* work,
   and laziness guarantees un-pulled work never starts — but work in
   flight runs to completion, its result discarded
   (`async-flow-design.md`). For pure work that is wasted CPU;
   external resources convert it into a correctness hole ("a child
   process is not wasted CPU, it is a zombie holding fds" —
   `tough-use-cases-design.md`, break #3).

2. **The async cell is the carrier.** The recorded constraint: the
   async design must not preclude threading a cancellation capability
   through the cell later — "the cell is the natural carrier, since it
   is the unit that gets started and abandoned"
   (`async-flow-design.md`).

3. **The trigger already exists at every barrier.** At a race's
   settlement, every losing cell's never-fires status is fully known —
   the same event that writes subset-merge terminators is the event
   "contender i is now abandoned by this race." Per-consumer honesty
   lives at the cell: a loser shared with another live consumer is
   abandoned by the race, not by the program
   (`race-barrier-design.md`). The concurrent collect's interrupt on
   the completions side abandons in-flight bodies the same way
   (`concurrent-collect-design.md`).

4. **The signal channel and the cancellation channel are distinct.**
   Interruption delivered in-band *as* task cancellation is the
   recorded pathology (websockets 4's four-state uncancel dance) and a
   recorded dead end: signals are cells; cancellation, when it lands,
   is an effect on abandoned cells (`race-barrier-design.md`, dead
   end 3).

5. **The thread is in place.** A spanning effect handle commutes out
   of the loop, its per-firing segments concatenated in firing
   order; the handle after the loop is the concatenation's tail —
   defined even when the walk ends early, as the concatenation up to
   the cut (`effects-design.md`). The effects
   round named the thread "the carrier a cancellation capability would
   later ride"; this round is that rider.

6. **Bracket's required structure is known.** Zig's `defer`/`errdefer`
   supply four properties any bracket must reproduce: release adjacent
   to acquisition; cleanup keyed by exit reason; the infallibility
   asymmetry ("resource allocation may fail; resource deallocation
   must succeed"); attachment at per-firing as well as per-flow
   granularity (`zig-comparison.md`, finding 6). The tough-use-cases
   round adds: kill is not optional; release is itself effectful and
   async (waitpid), with a completion a supervisor may need to
   observe.

7. **Failability's machinery is general.** A flow kind's termination
   event can carry a payload; consumers propagate it by default and
   discharge it at a whole-flow collect, where it becomes ordinary
   data (`async-flow-design.md`). Zig's `Future.cancel` — "places a
   cancellation request" and *still returns the result* — is the field
   witness that cancellation fits this machinery: the cancelled
   computation terminates, with a readable terminator
   (`zig-comparison.md`, finding 8).

## Against the philosophy

- **Inside-out.** No scopes and no regions: the bracket is a pairing
  on a drawn segment; ownership and granularity are read off vertex
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

## Where the settled rejections live

The six settled rejections of this round are recorded in place above,
each in a "now, you might wonder" passage, so a design reader can find
them: (1) a user-facing cancel token / capability wire, in "Why there
is no cancel token"; (2) cancellation as an operation one computation
performs on another (`task.cancel()`), same section; (3) delivering
cancellation on the `Fail` lane (`CancelledError`), in "What you can
do with a Cancelled flow"; (4) bracket as a drawn region or
with-block, at the end of the bracket section; (5) GC/finalizer-based
release as the meaning of release, in "Silence exists only at the
edges"; (6) preemptive delivery at arbitrary points, in "How the
terminator is delivered." Reasons are kept short and forward-looking
in each spot, so they are not re-proposed.

## Open questions this round leaves

The language hasn't decided these yet; where a leaning exists it is
stated as a leaning, not a decision.

1. **Adoption.** Prepared for the design conversation — jointly with
   the effects round: the Tier-1 row's two halves are one
   conversation, since the release half consumes the handle after
   the loop and the delivery rides the frontier.
2. **The Cancelled payload.** Bare fact (the lean) vs provenance
   (which consumer abandoned) — jointly with failability's
   payload-composition residue and the subset-merge payload question.
   *The joint round now exists* (`failure-payloads-design.md`,
   exploration): the bare-fact lean is confirmed structurally — a
   lane's payload is data its minting site had in hand, and strand
   delivery's minting site has no input wire; the abandoning party
   engaged nothing a value could arrive through.
3. **The release spelling.** `release of <handle>` as the late-wired
   form; whether per-lane release is one body with a split (as drawn
   above) or per-lane bodies; how the release-completion cell is
   named. Jointly owned with `textual-representation-design.md` (the
   first-class-ports round that jointly owned it is retired,
   migration complete).
4. **The cancel-translation schema.** What an external catalog block
   declares about its foreign cancellation (idempotence, promptness,
   whether the foreign op reports post-cancel state) — the checking
   round's trusted-JS-edge schema (question 4) gains a second concrete
   content demand beside the identity witnesses. (The schema round has
   since been worked — `catalog-schema-design.md`, exploration: the
   cancel translation sits in its translations family, graded
   irreducibly asserted, with a missing translation flagged at the
   advisory tier; the fine print above stays owned here.)
5. **The permit pool block.** Bracket plus delivery cover the waiters;
   the block itself (permits as permanent tokens, queue fairness,
   failable acquire, `bounded` width × permits —
   `concurrent-collect-design.md` question 4) is now unblocked and
   owed its own round.
6. **Multi-close frontier accounting.** One flow collected by two
   consumers, one of which is abandoned: the frontier's refcount is
   per-cell, but walks share structure — confirm the accounting at
   walk granularity, jointly with the effects round's
   one-threading-consumer question (its open question 4).
7. **The register's final at a Cancelled cut.** The discharge readout
   of a register under early termination — and, on the effects side,
   the handle as the concatenation-so-far — is already shared residue
   with end-when's final-readout anchor; confirm `Cancelled` needs
   nothing beyond that answer.
8. **The at-risk derived view.** The async round asked what the
   diagram shows when a race implies possible cancellation of a
   subgraph. This round's answer is "nothing new is authored" — the
   candidate is a *derived view* highlighting the demand subtree
   stranded if a given contender loses. Layout-side; named here so it
   is not re-invented as structure.
9. **Naming.** "Cancelled" vs "Abandoned" vs "Stranded"; "bracket" vs
   acquire/release; "release" vs "close". Deferred to the naming sweep
   (`implementation-strategy.md`).

## What this doesn't address

- **Within-firing effect ordering** (the conditional-flush buffer) —
  the distinct axis fenced by the effects round. *Now worked*
  (`within-firing-effects-design.md`, exploration): the buffer
  dissolves into a segmentation of the op flow; the register half of
  the joint ownership was the costume.
- **The batched-effect construct** — the collected-plan pole's own
  round, unchanged.
- **The permit pool, the served flow's own round, the chooser
  family** — fenced above and in their owning docs.
- **True preemption and workers** — out of scope with the async
  round's event-loop stance.
- **Visual depiction** — segment drawings, release-half rendering, the
  at-risk view: layout-side, out of scope in this repo.
- **Implementation.** Nothing here exists in the compiler. The
  dependency order extends the async round's: streams, then async
  cells, then frontier accounting (shared with the incremental
  runtime), then delivery and brackets. The interrupt compile is
  reused; the only genuinely new runtime piece is the frontier's
  strand event.
