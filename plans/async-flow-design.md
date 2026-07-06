# Async Flows

## What this is for

Computations on an event loop: values that arrive later, processes
that run in interleaved steps, external events that fire when they
fire. We call the flow kind that carries these the **async flow**.

The commute taxonomy in `lazy-stream-commute-design.md` deferred
this topic with one breadcrumb: the `Delayed` prototype originally
had event-loop integration that the stream design explicitly
stripped ("synchronous, minus the event-loop integration"), so
there is a known seam to reopen rather than a blank page. This
document reopens it.

The compile target is promise-shaped JavaScript, but promises as
JS defines them have the wrong creation semantics for this
language — they start running the moment they are constructed.
Getting that right is the first section. After that, the
interesting design questions are the ones the synchronous flows
never had to face: what parallel threads of computation look like
structurally, what racing means, and what happens to work that was
started and then overtaken.

This is a starting-point document. It works out the parts that
seem to fall cleanly out of the existing design, lays out options
where a real choice exists, and records the rest as open
questions.

## The eager-promise problem, and the cell that fixes it

A JS promise conflates two things:

- **Memoised resolution.** A promise resolves at most once and
  caches its value; every `.then` after resolution sees the cached
  value. This is exactly the discipline our `Delayed` cells
  already impose, and it's what makes multi-consumer sharing work.
- **Eager start.** `new Promise(executor)` runs the executor
  immediately. The work begins at construction time, whether or
  not anyone will ever look at the result.

The first half we want; the second violates the language's
evaluation model, where nothing runs until a consumer pulls.
Compiling an Expr graph straight to promise construction would
mean building the graph *is* running the program.

The fix is the same shape as `__lazy__`: hold the promise
*creation* in a thunk, and create it on first force.

```js
const __asyncCell__ = (t) => ({p: null, t});
const __startAsync__ = (z) => {
  if (z.p === null) { z.p = z.t(); z.t = null; }
  return z.p;
};
```

`__startAsync__` returns a promise; awaiting it is the consumer's
business. Two states suffice where the synchronous cache needed
three, because the promise itself supplies the third: unstarted /
started, and within "started" the promise's own resolve-once
caching distinguishes in-flight from resolved. Concurrent forcers
share the one stored promise, so per-cell work is computed at most
once regardless of fanout — the async analog of the `Delayed`
memo.

Two vocabulary points fall out:

- **Start is synchronous.** Forcing an async cell creates the
  promise and returns immediately; only *awaiting* yields to the
  event loop. "Start these, then wait for them" is expressible as
  plain sequential code in an output-construction thunk, which is
  what makes the parallel patterns below cheap to compile.
- **Abandonment ≠ cancellation.** A started promise cannot be
  unstarted. Dropping every reference to a cell stops anyone from
  *observing* it, and laziness guarantees un-pulled work never
  starts — but work already in flight runs to completion in JS,
  its result discarded. For pure computation the difference is
  wasted CPU; once effects exist it is observable. See "Effects,
  abandonment, cancellation" below.

## The async flow as an open/close

An `async<X>` opens the way an option does. `Open(AsyncIter?)` on
an async-typed input yields one value port — the resolved value —
and one flow port — the async context. Everything consuming the
value port lands inside the context: it happens *after* the value
arrives. A close on the flow packages the body's result back up as
an `async<Y>`.

The structural likeness to `OptionIter` is strong: a body that
runs at most one time, guarded by something about the input. The
difference is what the guard is about:

- Option's discrimination is **data**, checked now: present or
  absent.
- Async's discrimination is **time**: not yet, or arrived. There
  is no absent case — an async value always eventually fires (or
  fails; failure is deferred to the open questions).

So the async open has no discriminator function and no
zero-iterations case. It is a one-shot iteration displaced in
time. Laziness composes as usual: nothing about the async input
starts until some consumer forces the close's output cell, whose
thunk starts the input, awaits it, runs the body, and resolves.

A small map of where this sits among the flow kinds we have:

|              | now            | later            |
|--------------|----------------|------------------|
| zero-or-one  | option flow    | —                |
| exactly one  | (plain value)  | **async flow**   |
| many         | list flow      | **async stream** |

The "many, later" cell — a stream whose `Delayed` cells resolve
asynchronously — is not a new flow kind at all. It is the existing
stream flow with the async cell substituted for the synchronous
one, and it is what external event sources and long-running
processes are. Most of this document's interesting content lives
in that cell of the table.

## Sequential and parallel are structural

The language principle that semantics should be structural, not
nominal, pays off here: **the dependency wiring already is the
concurrency structure.**

**Sequential composition is nesting.** If async open B's input is
computed from async open A's resolved value, B cannot start until
A resolves — not because anything was annotated, but because B's
input doesn't exist earlier. Nested async opens are monadic bind;
wall time is the sum.

**Parallel composition is the concurrent join of siblings.** Two
async opens on independent inputs are sibling flows with no
construction-time ordering — and by the no-time-travel rule,
combining their value ports directly is ill-formed, exactly as it
is for sibling list flows. The sanctioned combination already
exists in the spec: **Join with multiple inner flows** ("concurrent
join"), the fork-join pattern in `visual-flow-language.md`. Joining
the two async flows merges the contexts; in the merged context both
resolved values are available and combine freely.

The compile of a close over a concurrent join is the start-all,
await-all shape, and it is trivial because start is synchronous:

```js
const v_out = __asyncCell__(async () => {
  const pa = __startAsync__(cellA);   // both in flight
  const pb = __startAsync__(cellB);   // before either await
  const a = await pa;
  const b = await pb;
  return combine(a, b);
});
```

Wall time is the max, not the sum. This is `Promise.all` derived
from structure rather than named — the applicative/monadic
distinction that `flow_language_design.md` drew for SEQUENCE
operations, now with observable timing attached to it.

Note what this means for the reader of a diagram: to know whether
two async computations overlap, you look at whether one's opener
hangs off the other's value port. There is no `parallel` keyword
to forget.

## Threads are async streams; no thread primitive

The user-visible notion of "a thread of computation" — an ongoing
process that makes progress in steps, interleaved with other
processes — needs no new primitive. A thread is an **async
stream being drained**: a stream whose cells resolve on the event
loop, consumed by something that pulls them one after another.

Two threads running in parallel is then two async streams whose
drains are jointly demanded — the concurrent join again, one level
up. Each drain is itself an async value (the fold/commute of its
stream); joining them starts both walks; their awaits interleave
on the event loop. Progress alternates wherever either walk is
waiting.

This is single-event-loop concurrency, the JS kind: interleaving
at await points, not simultaneous execution. The language should
be honest that "parallel threads" means concurrent, cooperatively
interleaved steps. True parallelism (workers) is out of scope
here.

What joint demand does *not* give you is consuming two threads'
outputs incrementally *in arrival order* — for that see merge,
under racing below.

## Racing is a barrier, not a value

The second extra operation the async flow needs. `race(a, b)`
takes two async contenders and resolves when the first of them
does. The result is a discrimination — **which one won**, plus
the winner's value — so the case-split machinery is clearly
nearby. The design question is how the discrimination is
*represented*.

The first draft of this document made race a node producing an
alternative value:

    race : (async<A>, async<B>) → async<alt{ First(A) | Second(B) }>

opened with the ordinary async open and split with the ordinary
`CaseSplit`. The reuse was attractive, but the shape is wrong: it
forces a **bottleneck**. Contender `a`'s thread enters the race
and re-emerges as the First alt's flow and value — but only by
being packed into a tagged value and immediately unpacked again.
The wire-level identity between the `a` input and the `a` case is
severed; the correspondence survives only in the tag's name and
the reader's head. This is the sum-shaped dual of the tuple
bottleneck — the product one — that the 2D join was designed to
avoid: there, multiple concurrent values refuse to be packed into
a tuple just to pass through a join; here, multiple alternative
threads refuse to be packed into a tagged union just to pass
through a race. (See "No bottlenecks — neither product nor sum"
in `language-design-philosophy.md`; the product instance is
worked through as the functional bottleneck problem in
`iteration-with-state-design.md`.)

So race is instead a **barrier**: a single multi-input,
multi-output construct whose inputs and outputs are not unrelated
ports but correspond pairwise —

- N async inputs, one per contender.
- Per contender `i`, an output **flow** (fires iff contender `i`
  won) and an output **value** (contender `i`'s resolved value,
  available on that flow).
- The output flows form a bundle that must be closed together,
  exhaustively — exactly the discipline of an opened case split.
  The close's output is an `async<Y>`: the close repackages the
  time displacement, since which alt fired isn't known until
  resolution.

Downstream, everything is inherited from case splits unchanged:
exhaustive close, per-alt values, filter closes on one alt. What
the barrier form changes is *upstream identity*: thread `i`
passes straight through the barrier. In wire terms the `i`-th
input and the `i`-th case are one thread, interrupted only by the
barrier line that marks "exactly one of these continues."

The duality with the concurrent join is exact and worth stating:

- **Concurrent join is the product barrier.** N threads enter;
  all continue together; each value passes through individually;
  no tuple is constructed.
- **Race is the sum barrier.** N threads enter; exactly one
  continues; each value passes through individually; no
  alternative is constructed.

`CaseSplit` remains the right tool when the sum already exists
*as data* — a value that genuinely is a tagged union, arriving
from elsewhere. Race is for the sum that arises structurally,
from timing; constructing the data sum only to split it again is
precisely the bottleneck. And the rejected alt-value form isn't
wasted: it survives as the *compilation* — the emitted JS races
tagged promises (see the compile sketch), with the tag as
internal bookkeeping selecting the branch scope, never a
user-visible value. The same representation-vs-compilation split
the Commute node landed on.

### Worked example: timeout

Fetch with a five-second timeout. `fetchD : async<Data>`,
`timer(5s) : async<unit>`.

    race(fetchD, timer)
      fetch-won flow, data  ->  Some(process(data))
      timer-won flow, ()    ->  None
    close both flows together  =>  async<option<…>>

Forcing trace:

1. A consumer forces the close's output cell. Its thunk starts
   both contenders — the fetch's promise and the timer's promise
   are now both in flight — and awaits the first settlement.
2. Say the fetch resolves at 3s. The fetch-won flow fires with
   `data` on its value wire; the close takes that branch's
   value, `Some(process(data))`, and resolves.
3. The timer's promise is still in flight. Its cell is memoised:
   if some *other* consumer independently forces the timer, they
   share the in-flight promise and get its value at 5s. If nobody
   does, it resolves at 5s into an unobserved cell and is GC'd.
   Nothing is cancelled; the loser is abandoned.

Determinism: the event loop serialises settlements, so given a
schedule the winner is well-defined; across schedules it is not.
The language should promise no more than JS does here —
nondeterminism is inherent to racing and the case structure is
precisely the honest representation of it.

### Merge: racing lifted over streams

Fork-join consumes two threads' results at the end; **merge**
consumes them as they arrive. `merge(s1, s2)` interleaves two
async streams in arrival order — and it is just race applied
repeatedly: race the two head cells; on the s1-won flow, emit the
head and recurse with s1's tail and s2's *still-in-flight* head
(the memoised cell carries over — no work is lost or duplicated);
symmetrically on the s2-won flow. Output order is schedule-determined, which
is the point of the operation.

## Interruption: unless-and-until

The pattern named in the motivation: a process does something
repeatedly unless and until an external source interrupts it. A
ticker until a click; polling until a shutdown signal; an
animation until a route change.

Shape: an async stream (the process's steps) plus an async value
(the interrupt), combined so the stream ends early when the
interrupt fires. Mechanically this is race at every pull:

    interrupt : (stream<X>, async<E>) → stream'<X>

Each pull of the derived stream races the inner stream's next cell
against the interrupt. Inner wins → emit the cell, recurse (the
interrupt cell is memoised and still in flight — the same race
continues). Interrupt wins → the stream ends, carrying `e`.

Two things worth pinning down:

**The terminator wants a payload.** A stream ended by interruption
is not the same as a stream that ran out, and downstream usually
needs to know which happened and why. This is exactly the
**failable stream** slot the commute taxonomy recorded and
deferred — a terminator of `Nil | Interrupted(e)` is the
"prefix-up-to-failure with partial results kept" shape, arrived at
from the async side instead of the parsing side. Interruption may
be the concrete use case failable streams were waiting for; if so,
the two designs should land together.

**Interruption is checked at pull boundaries.** The race happens
per pull, so a step already in flight when the interrupt fires
completes (and is then discarded — the consumer stopped pulling).
This is cooperative interruption with the pull boundary as the
yield point. It falls out of the lazy model for free and is
usually what you want; interrupting *mid-step* requires real
cancellation, which is the effects question. Also note the
converse: a consumer that stops pulling never observes the
interrupt at all — laziness means the interrupt is only ever
raced against demand that actually exists.

## External event sources

Timers, user input, incoming messages: these are *push* sources,
and the language is *pull*. The adapter is an async stream whose
cell resolution is wired to event arrival: cell N's promise
resolves when the Nth event fires.

The impedance mismatch shows up when events outpace pulls. If
events N and N+1 arrive before anyone pulls cell N, the adapter
must choose:

- **Buffer** (queue events; every pull gets the next queued event;
  nothing is missed). The natural default — it preserves the
  stream reading exactly.
- **Latest / drop** (a pull gets the most recent event; missed
  ones are gone). Right for "current mouse position"-shaped
  sources where history is noise. This is arguably a different
  source kind, not a policy flag on one kind.

A separate wrinkle: stream cells are memoised, so any consumer can
walk an event stream from the beginning — which means the adapter
retains *every event ever*, live, as long as the stream's head is
reachable. For bounded computations that's fine; for a long-lived
event source it's a leak by design. Event sources probably want
either heads that are deliberately not retained (consumers hold
cursors, history behind the earliest cursor is GC-able — which the
chain structure already gives us if nobody keeps the head) or an
explicit windowing operation. Recorded as an open question.

## Effects, abandonment, cancellation

The language has no side effects yet; the IO marker flow is
designed-ahead vocabulary (see the commute taxonomy's
marker-out-of-sequenceable entry). But racing forces the question
earlier than elsewhere, so the shape of the problem should be on
record:

- **Pure work**: abandonment is semantically invisible. A lost
  racer or an interrupted step wastes the CPU it already consumed
  and nothing else. The memo even recovers some of the waste —
  anything the abandoned computation shared with a surviving
  consumer is pre-warmed for them, the same effect as the commuted
  close's pre-warming in `lazy-stream-commute-design.md`.
- **Effectful work**: "started but overtaken" is observable. If
  the losing side of a race had already written half its output,
  the program's meaning includes that half-write. JS offers no
  preemption; real cancellation is cooperative
  (AbortController-shaped tokens threaded to the effectful leaves)
  and best-effort.

Options when the IO design arrives, roughly: (a) lost racers'
effects simply happen (JS-honest, and a footgun exactly where
races are most useful); (b) a cancel signal is delivered on
abandonment, cooperative and best-effort; (c) effects are
restricted to commit points that a race can't split. Deciding is
premature here; what this document contributes is the constraint
that **the async design should not preclude threading a
cancellation capability through the async cell later** — the cell
is the natural carrier for it, since it is the unit that gets
started and abandoned.

## Commuting async out of stream

`stream<async<X>>` → `async<stream<X>>` fits the taxonomy's
"sequenceable × sequenceable, different kinds" slot, next to
option-out-of-stream. The walk is the same shape as option
commute's — consume the stream layer, produce one outer value —
with two differences:

- **No short-circuit.** Async doesn't fail (yet), so the walk is
  unconditional, like the marker case.
- **A genuinely new degree of freedom: start order.** Option
  commute had one possible walk. Here the walk could await each
  element's async before starting the next (sequential; total wall
  time is the sum) or start them all and then await in order
  (parallel; wall time is the max — `Promise.all`).

Which is "commute"? The leading answer, from the laziness
principle: commute consumes the whole stream layer — the user
asked one question about the entire stream, and the layers
consumed give up their incremental laziness (the established
per-layer rule). Once the whole layer is demanded *at once*,
starting everything is the natural reading, and start is
synchronous and free. So: **commuted async-out-of-stream starts
all, awaits in order** — provided the elements' asyncs are
structurally independent.

And structure guards the exception automatically: if element N+1's
async input depends on element N's *resolved* value, the N+1 cell
cannot even be constructed before N resolves — sequentiality is
forced by the wiring, not by a mode. The same structural rule as
the fork-join section, applied per element.

One honest caveat: for effectful asyncs, start order is observable
timing, and "start all" bakes in one choice. This mirrors the
marker-commute discussion (timing, not data) and should be
revisited together with it. If both orders turn out to be wanted,
that is two output constructions, not one with a flag — but
deciding that needs a concrete use case.

The infinite-stream footgun from the join doc applies verbatim:
commuting an infinite async stream never resolves (and under
start-all, tries to start unboundedly many cells — the walk should
interleave start with the pull of the next cell, which bounds it
naturally: pull cell N+1, start it, await cell N).

## Compile sketch

Nothing here needs machinery beyond the async cell and the
existing simple-lazy compile discipline:

- `async<X>` at runtime is the `__asyncCell__` two-state cell;
  forcing returns a promise; the promise's own memo covers
  in-flight/resolved.
- An async close compiles to one async cell whose thunk is an
  `async` arrow containing the body — awaits where async opens'
  value ports are read, plain bindings elsewhere. The emitted JS
  uses `async`/`await` syntax freely; the eager-semantics
  discipline is entirely about *creation points* (no promise
  constructed outside a cell thunk), not about avoiding the
  syntax.
- Concurrent join: start all inner cells, then await, as sketched
  above.
- `race`: the barrier compiles to start-all plus `Promise.race`
  over tagged wrappings (each contender's promise mapped to
  `{tag, value}` before racing), the tag dispatching into the
  winning branch's scope — compile-internal bookkeeping, never a
  user-visible value.
- Async streams are the existing stream cells with the async cell
  in the `Delayed` position — this is precisely the prototype's
  event-loop-integrated `Delayed` (`tick()`), un-stripped. The
  placement/chain analysis from `lazy-stream-placement-design.md`
  is untouched: consumer-sets and chains don't care whether a
  cell's force is synchronous or awaited, for the same reason
  commute and join didn't — it's all behind the pull interface.

## Open questions

1. **Failure.** JS promises reject; our `async<X>` so far cannot.
   Options: keep async infallible and layer result/option inside
   it (`async<result<X, E>>`, handled by the existing flows and
   the eventual result-commute); or make the async flow itself
   failable. The failable-stream thread (taxonomy + interruption
   above) suggests failure-as-terminator is a recurring shape;
   whether one design covers async values, interrupted streams,
   and parsing-style failable streams is worth working out in one
   sitting rather than three.

2. **Cancellation.** Deferred to the IO design, but with the
   constraint recorded above: the async cell should be able to
   carry a cancellation capability later. What does the *diagram*
   show when a race implies possible cancellation of a subgraph?

3. **Event-source retention.** Cursor-based GC of event-stream
   history vs explicit windowing vs "latest"-kind sources. Also
   whether multiple consumers of one event source should ever see
   different suffixes (subscribe-time semantics) or always the
   same memoised sequence.

4. **Start order under commute, once effects exist.** Is
   start-all-await-in-order the only commute, or do sequential
   and parallel walks become two distinct output constructions?
   Needs a concrete effectful use case.

5. **Barrier representation in the Expr graph.** Race needs
   per-contender flow and value output ports on one construct —
   more port structure than any current node kind carries
   (Branch is the nearest precedent). This strengthens the case
   for the first-class port concept already on the README's
   next-steps list; a Race node reached through `go`'s
   node-equals-value-port conflation won't fit. (Arity, at
   least, is settled by the barrier form: N-ary from the start.
   The nested-alternative composition question —
   `race(a, race(b, c))` — was an artifact of the rejected
   alt-value form.)

6. **Is the async open its own kind, or is `OptionIter` a
   degenerate async?** They share the one-shot-body shape. Keeping
   them separate seems right (data-discrimination vs
   time-displacement; option has a none case, async doesn't), but
   if failure lands *in* the async flow the shapes converge
   further. Watch it.

7. **Fairness and starvation.** Two merged streams where one
   resolves synchronously-fast can starve the other's turn on the
   event loop between pulls. Probably "whatever the event loop
   does" is the honest answer, matching the determinism stance
   under racing — but merge-heavy programs may eventually want a
   fairness knob, and it should be an explicit operation if so.

8. **Naming.** "Async flow" for the kind; the open's constructor
   name (`AsyncIter`? `Await`?); "race" vs "select"; "interrupt"
   vs "until". Deferred, as commute-vs-sequence was.

## What this doesn't address

- **Visual depiction.** What an async open, a concurrent join, a
  race, or an interrupted stream look like on the canvas is the
  visual side's problem, out of scope in this repo. One note worth
  passing across: the fork-join and 2D-join drawings in
  `visual-flow-language.md` were designed for exactly the
  concurrent-join semantics used here, so the visual vocabulary
  may already exist.

- **True parallelism.** Workers, shared memory, actual
  simultaneity. This document is event-loop concurrency only.

- **Loop-carried state across async steps.** A Delay node inside
  an async stream flow — state threaded from step to step of a
  long-running process — is the reactive-systems bread and butter
  and probably composes without new design (the register lives in
  the walk), but it deserves its own worked examples once the
  iteration-state candidates settle.

- **Scheduling and priorities.** Beyond fairness (open question
  7), nothing here about prioritising one thread's progress over
  another's.

- **Implementation.** As with the stream docs: design first, and
  the stream-flow runtime (which this builds on) doesn't exist in
  the compiler yet either. The dependency order is: stream flows,
  then async cells, then async streams / race / interrupt.
