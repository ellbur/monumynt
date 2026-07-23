# Async Flows

Status: exploration — this chapter teaches design work that has not
been adopted and is not implemented. The parts that derive cleanly
from the existing flow model are worked out; racing and failability
carry leanings (worked positions prepared for a design conversation,
not decisions); the rest is recorded honestly as open questions. Read
it as "here is how async would work, and the case for it."

## Your first async program

So far every value in the language has been *there*: you wire it in,
and it exists. But some values arrive later — the response to a
request, the result of a timer, the next message from outside. Here
is a complete program that works with one:

```
url -> open async => resp, ~A       -- resp available only inside ~A, after arrival
resp -> parse -~> collect => out    -- out : async<...>; the body runs post-arrival
```

Read it the way you read every program: left to right, top to
bottom. The input is an async-typed value — a value that will exist,
but does not yet. `open async` opens it, and the `=> resp, ~A` names
its two output ports:

- `resp` is the **value port** — the resolved value, once it arrives.
- `~A` is the **flow port** — the async context itself. (The `~`
  sigil marks a flow name, as always.)

Everything that consumes `resp` lands inside that context: it happens
*after* the value arrives. The `-~> collect` closes the flow, and
packages the body's result back up as an `async<Y>` — a value that
will, in turn, arrive later for whoever consumes `out`.

If you have read `core-model.md`, this shape is an old friend: it is
the open/collect pair, instantiated for a new flow kind. The flow
kind that carries values-arriving-later is the **async flow** — the
"exactly one value, but later" flow. It opens the way an option
opens, except the guard is *time* rather than *presence*.

The structural likeness to the option open is worth pausing on. Both
have a body that runs at most one time, guarded by something about
the input. But the guards differ:

- Option's discrimination is **data**, checked now: present or
  absent.
- Async's discrimination is **time**: not yet, or arrived. There is
  no absent case — an async value always eventually fires (or fails;
  failure gets its own section, "Failure as terminator payload").

So the async open has no discriminator function and no
zero-iterations case. It is a one-shot iteration displaced in time.
And laziness composes exactly as it does everywhere else: nothing
about the async input starts until some consumer actually demands the
result. (Precisely what "starts" means is the next section.)

Here is where the async flow sits among the flow kinds:

|              | now            | later            |
|--------------|----------------|------------------|
| zero-or-one  | option flow    | —                |
| exactly one  | (plain value)  | **async flow**   |
| many         | list flow      | **async stream** |

The "many, later" cell — a stream whose cells resolve asynchronously
— is not a new flow kind. It is the existing stream flow with the
async cell (introduced below) substituted for the synchronous one,
and it is what external event sources and long-running processes are.
Most of this chapter's interesting content lives in that cell. The
dash in the zero-or-one row is not an omission; it is explained and
filled in "Failure as terminator payload."

## What this chapter is about

Computations on an event loop: values that arrive later, processes
that run in interleaved steps, external events that fire when they
fire — including the pattern of a process that does something
repeatedly *unless and until* something interrupts it.

Most of the machinery falls straight out of the existing flow design,
as the first program already showed. What is genuinely new — and what
this chapter spends its length on — is what the synchronous flows
never had to face: what parallel threads look like structurally, what
racing means, and what happens to work that was started and then
overtaken. The `Delayed` prototype behind the stream design once had
event-loop integration that was stripped out ("synchronous, minus the
event-loop integration," per `lazy-stream-commute-design.md`), so
there is a known seam to reopen rather than a blank page.

The compile target is promise-shaped JavaScript. But JS promises have
the wrong creation behaviour for this language — they start running
the moment they are constructed — so getting creation right comes
first.

## The eager-promise problem, and the cell that fixes it

You might wonder why the language doesn't just compile an async value
straight to a JavaScript promise — promises are, after all, exactly
"a value that arrives later." The answer is that a JS promise
conflates two things, and the language wants only one of them:

- **Memoised resolution.** A promise resolves at most once and caches
  its value; every `.then` after resolution sees the cached value.
  This is exactly the discipline the synchronous `Delayed` cells
  already impose, and it is what makes multi-consumer sharing work.
  We want this half.
- **Eager start.** `new Promise(executor)` runs the executor
  immediately. The work begins at construction, whether or not anyone
  will ever look at the result. This violates the language's
  evaluation model, where nothing runs until a consumer pulls.
  Compiling an Expr graph straight to promise construction would make
  building the graph *be* running the program.

The fix is the same shape as `__lazy__`: hold the promise *creation*
in a thunk, and create it on first force.

```js
const __asyncCell__ = (t) => ({p: null, t});
const __startAsync__ = (z) => {
  if (z.p === null) { z.p = z.t(); z.t = null; }
  return z.p;
};
```

This little structure is the **async cell**, and it is the runtime
heart of everything in this chapter. `__startAsync__` returns a
promise; awaiting it is the consumer's business. Two states suffice
where the synchronous cache needed three, because the promise itself
supplies the third: unstarted / started, and within "started" the
promise's own resolve-once caching distinguishes in-flight from
resolved. Concurrent forcers share the one stored promise, so
per-cell work runs at most once regardless of fan-out — the async
analog of the `Delayed` memo.

This isn't just theory-tidiness; real code reaches for exactly this
shape. In the concurrency survey (`real-loop-survey.md`, survey 3,
findings 3.3 and 3.9), a promise minted empty with a separate write
half — often memoised-once and lazily created — was the
most-reached-for primitive, while nobody used `new Promise` for its
designed eager purpose. JS itself has since added
`Promise.withResolvers`. The cell's timing contract also earns its
keep: three surveyed sites existed solely to keep continuations from
running re-entrantly — the "release Zalgo" discipline (never deliver
synchronously on some paths and asynchronously on others) that the
cell provides by construction.

Two vocabulary points fall out, and both matter for everything below:

- **Start is synchronous.** Forcing an async cell creates the promise
  and returns immediately; only *awaiting* yields to the event loop.
  "Start these, then wait for them" is plain sequential code in an
  output-construction thunk, which is what makes the parallel
  patterns below cheap to compile.
- **Abandonment is not cancellation.** A started promise cannot be
  unstarted. Dropping every reference to a cell stops anyone from
  *observing* it, and laziness guarantees un-pulled work never starts
  — but work already in flight runs to completion in JS, its result
  discarded. For pure computation the difference is wasted CPU; once
  effects exist it is observable (see "Effects, abandonment,
  cancellation").

With the cell in hand, the laziness story of the first program can be
said precisely: nothing about the async input starts until some
consumer forces the close's output cell, whose thunk starts the
input, awaits it, runs the body, and resolves.

## One after another, and side by side

Suppose you have *two* things that arrive later. Do they wait for
each other, or run at the same time? In conventional code you decide
with vocabulary — `await` here, `Promise.all` there. In this language
you don't decide at all: the dependency wiring already *is* the
concurrency structure. Nothing needs a `parallel` or `sequential`
keyword.

**Sequential composition is nesting.** If async open B's input is
computed from async open A's resolved value, B cannot start until A
resolves — not because anything was annotated, but because B's input
does not exist earlier:

```
url -> open async => resp, ~A
resp -> next -> open async => body, ~B   -- ~B nested in ~A: starts only after resp
```

Nested async opens are what functional programmers call monadic bind;
wall time is the sum of the two waits.

**Parallel composition is the concurrent join of siblings.** Two
async opens on independent inputs are sibling flows with no
construction-time ordering. By the no-time-travel rule, combining
their value ports directly is ill-formed, exactly as for sibling list
flows. The sanctioned combination is **Join with multiple inner
flows** — the "concurrent join" (the product barrier of
`core-model.md`, "Barriers, not bottlenecks"; the retired
`visual-flow-language.md` drew it as fork-join). Joining the two
async flows merges the contexts; in the merged context both resolved
values are available and combine freely:

```
urlA -> open async => a, ~A
urlB -> open async => b, ~B      -- sibling opens, independent inputs
~A, ~B ~> join all => ~ab        -- concurrent join merges the two contexts
a, b -> combine -~> collect => out   -- both values live in the merged context
```

The close over a concurrent join compiles to start-all, await-all —
trivial because start is synchronous:

```js
const v_out = __asyncCell__(async () => {
  const pa = __startAsync__(cellA);   // both in flight
  const pb = __startAsync__(cellB);   // before either await
  const a = await pa;
  const b = await pb;
  return combine(a, b);
});
```

Wall time is the max, not the sum. This is `Promise.all` derived from
structure rather than named — the applicative/monadic distinction the
retired `flow_language_design.md` drew for sequence operations, now
with observable timing attached. To know whether two async
computations overlap, you look at whether one's opener hangs off the
other's value port. There is no keyword to forget.

## Threads

The word "thread" suggests a big new piece of machinery: a primitive
for spawning an ongoing process that makes progress in steps,
interleaved with others. Now, you might wonder why the language has
no thread primitive. It turns out none is needed, because the thing a
thread *is* already exists: a thread is an **async stream being
drained** — a stream whose cells resolve on the event loop, consumed
by something pulling them one after another.

Two threads in parallel is two async streams whose drains are jointly
demanded — the concurrent join again, one level up. Each drain is
itself an async value (the fold of its stream); joining them starts
both walks; their awaits interleave on the event loop. Progress
alternates wherever either walk is waiting.

This is single-event-loop concurrency, the JS kind: interleaving at
await points, not simultaneous execution. "Parallel threads" here
means concurrent, cooperatively interleaved steps. True parallelism
(workers) is out of scope.

What joint demand does *not* give you is consuming two threads'
outputs incrementally *in arrival order* — for that see merge, under
racing below.

(This is a settled dissolution, not a gap: a thread primitive would
duplicate what async streams and the concurrent join already are.
Please don't re-propose one without new evidence.)

## Racing

The second extra operation the async flow needs. Sometimes you start
two things and want whichever finishes first: a fetch against a
timeout, a computation against a shutdown signal. `race(a, b)` takes
two async contenders and resolves when the first of them does. The
result is a discrimination — **which one won**, plus the winner's
value — so the case-split machinery is clearly nearby. The design
question is how that discrimination is *represented*.

### A race, concretely

Fetch with a timeout. `fetchD : async<Data>`, `after(30) :
async<unit>`.

```
fetch:   fetchD
timeout: after(30)
-> race => r                       -- race barrier; lanes declare contender names
~r.fetch:   r.fetch -> process -> some   -- the fetch-won flow, carrying its value
~r.timeout: none                          -- the timeout-won flow
-~> collect => out                 -- close both lanes together => async<option<...>>
```

The lanes name the two contenders; the collect closes their bundle
exhaustively. Here is what happens when the program runs — the
forcing trace:

1. A consumer forces the close's output cell. Its thunk starts both
   contenders — the fetch's promise and the timer's promise are now
   both in flight — and awaits the first settlement.
2. Say the fetch resolves first. The `~r.fetch` flow fires with
   `data` on its value wire; the close takes that lane's value,
   `some(process(data))`, and resolves.
3. The timer's promise is still in flight. Its cell is memoised: if
   some *other* consumer independently forces the timer, they share
   the in-flight promise. If nobody does, it resolves into an
   unobserved cell and is GC'd. Nothing is cancelled; the loser is
   abandoned.

Determinism: the event loop serialises settlements, so given a
schedule the winner is well-defined; across schedules it is not. The
language promises no more than JS does here — nondeterminism is
inherent to racing, and the case structure is the honest
representation of it.

### Racing is a barrier, not a value

Now, you might wonder why race doesn't just produce an alternative
*value* — mint a tagged union and split it with the ordinary case
machinery, which is the obvious reuse:

    race : (async<A>, async<B>) → async<alt{ First(A) | Second(B) }>

opened with the ordinary async open and split with the ordinary
`CaseSplit`. It turns out the shape is wrong: it forces a
**bottleneck**. Contender `a`'s thread enters the race and re-emerges
as the First alt's flow and value — but only by being packed into a
tagged value and immediately unpacked again. The wire-level identity
between the `a` input and the `a` case is severed; the correspondence
survives only in the tag's name and the reader's head. This is the
sum-shaped dual of the tuple bottleneck the 2D join was designed to
avoid: there, multiple concurrent values refuse to be packed into a
tuple just to pass through a join; here, multiple alternative threads
refuse to be packed into a tagged union just to pass through a race.
(See "No bottlenecks — neither product nor sum" in
`language-design-philosophy.md`; the product instance is worked as
the functional bottleneck in `iteration-with-state-design.md`.)

(This is a settled rejection of the alt-value form as the
*representation* — please don't re-propose it without new evidence.
As you'll see in a moment, it survives in a different role.)

So race is instead a **barrier**: a single multi-input, multi-output
construct whose inputs and outputs correspond pairwise —

- N async inputs, one per contender.
- Per contender `i`, an output **flow** (fires iff contender `i` won)
  and an output **value** (contender `i`'s resolved value, available
  on that flow).
- The output flows form a bundle that must be closed together,
  exhaustively — exactly the discipline of an opened case split. The
  close's output is an `async<Y>`: the close repackages the time
  displacement, since which alt fired is not known until resolution.

Downstream, everything is inherited from case splits unchanged:
exhaustive close, per-alt values, filter closes on one alt. What the
barrier form changes is *upstream identity*: thread `i` passes
straight through the barrier. In wire terms the `i`-th input and the
`i`-th case are one thread, interrupted only by the barrier line
marking "exactly one of these continues."

The duality with the concurrent join is exact:

- **Concurrent join is the product barrier.** N threads enter; all
  continue together; each value passes through individually; no tuple
  is constructed.
- **Race is the sum barrier.** N threads enter; exactly one
  continues; each value passes through individually; no alternative
  is constructed.

`CaseSplit` remains the right tool when the sum already exists *as
data* — a value that genuinely is a tagged union, arriving from
elsewhere. Race is for the sum that arises structurally, from timing;
constructing the data sum only to split it again is precisely the
bottleneck. The rejected alt-value form is not wasted: it survives as
the *compilation* — the emitted JS races tagged promises, with the
tag as internal bookkeeping selecting the branch scope, never a
user-visible value. The same representation-vs-compilation split the
Commute node landed on.

Real code backs both halves of this section (concurrency survey,
`real-loop-survey.md`, survey 3, findings 3.1–3.2). First-of
coordination (race, timeout, interrupt, cancellation) outweighed
all-of coordination nine-to-one across thirty random orchestration
sites — the reverse of this chapter's design attention, which has
fork-join fully worked while race's own semantics round is still owed
(that round now exists: `race-barrier-design.md`). And in every
hand-rolled race, "which contender won" was reconstructed after the
fact from side state — a `request is not None` check, `reply.sent`
flags, a four-state enum plus exception conversion — never delivered
structurally. That is exactly the correspondence the barrier's
per-contender outputs exist to preserve.

### Merge: racing lifted over streams

Fork-join consumes two threads' results at the end; **merge**
consumes them as they arrive. `merge(s1, s2)` interleaves two async
streams in arrival order — and it is just race applied repeatedly:
race the two head cells; on the s1-won flow, emit the head and
recurse with s1's tail and s2's *still-in-flight* head (the memoised
cell carries over — no work is lost or duplicated); symmetrically on
the s2-won flow. Output order is schedule-determined, which is the
point.

## Interruption: unless-and-until

The pattern named in the motivation: a process does something
repeatedly unless and until an external source interrupts it. A
ticker until a click; polling until a shutdown signal; an animation
until a route change.

Shape: an async stream (the process's steps) plus an async value (the
interrupt), combined so the stream ends early when the interrupt
fires. Mechanically this is race at every pull:

    interrupt : (stream<X>, async<E>) → stream'<X>

Each pull of the derived stream races the inner stream's next cell
against the interrupt. Inner wins → emit the cell, recurse (the
interrupt cell is memoised and still in flight — the same race
continues). Interrupt wins → the stream ends, carrying `e`.

Two things worth pinning down:

**The terminator wants a payload.** A stream ended by interruption is
not the same as a stream that ran out, and downstream usually needs
to know which happened and why. This is exactly the **failable
stream** slot the commute taxonomy recorded — a terminator of `Nil |
Interrupted(e)` is the "prefix-up-to-failure with partial results
kept" shape, arrived at from the async side instead of the parsing
side. Interruption may be the concrete use case failable streams were
waiting for (taken up in "Failure as terminator payload").

**Interruption is checked at pull boundaries.** The race happens per
pull, so a step already in flight when the interrupt fires completes
(and is then discarded — the consumer stopped pulling). This is
cooperative interruption with the pull boundary as the yield point.
It falls out of the lazy model for free and is usually what you want;
interrupting *mid-step* requires real cancellation, which is the
effects question. The converse also holds: a consumer that stops
pulling never observes the interrupt at all — laziness means the
interrupt is only ever raced against demand that actually exists.

## Failure as terminator payload

What happens when a fetch *fails*? For a long time this was an open
question, and you might wonder which of the two obvious answers the
language picks: keep the async value infallible and put a
`result<X, E>` inside it (`async<result<X, E>>`), or make the async
flow itself failable as a special feature. It turns out the question
entangles three separately-deferred threads — JS promise rejection,
interrupted streams, and parsing-style failable streams — and worked
together, they are one concept, and it is not specific to async. The
answer to the either/or is *neither, as posed*; the reasoning follows,
and the verdict is stated at the end of this section.

**Every flow kind already has a termination event.** A stream ends
(`Nil`); an option is absent; an async value delivers. What the three
deferred threads each independently wanted is that event *carrying a
payload*:

- A parsing stream ends with `Fail(e)` instead of `Nil` — tokens up
  to the first bad one, plus what was bad about it.
- An interrupted stream ends with `Interrupted(e)` — the steps that
  ran, plus what interrupted them.
- A failing async terminates by *not* delivering — rejection is the
  exactly-one flow's second way to end, with the error as payload.

So this is one dimension, not three features: **a failable flow kind
is a flow kind whose terminator carries a payload.** Which kinds it
applies to falls out of the now/later table, and the table explains
its own gap:

|                        | now             | later             |
|------------------------|-----------------|-------------------|
| exactly one            | (plain value)   | async flow        |
| zero-or-one, bare end  | option flow     | *(unobservable)*  |
| zero-or-one, end+e     | result-as-flow  | **failable async**|
| many, bare end         | list flow       | async stream      |
| many, end+e            | failable list   | **failable stream**|

The dash in the earlier table — "zero-or-one, later" — was not an
accident of omission. In the *now* column, absence is observable by
looking: the data is there or it is not. In the *later* column, bare
absence is unobservable: an async that "just does not fire" is
indistinguishable from one that has not fired *yet*, forever. A
later-flow's zero case is only meaningful if the termination is
itself an event — which is to say, only in the failable row.
Failability is not an add-on to the async flow; it is the only
coherent way the async flow *has* a zero case.

### Two consumption modes: propagate and discharge

What does a consumer of a failable flow do about the terminator? Two
modes, both already existing in spirit.

**Propagation is the default.** A close over the value flow that says
nothing about the terminator passes it through: the output flow kind
keeps the same terminator, payload intact. Mapping over a failable
stream yields a failable stream that ends the same way the input did;
a body hung off a failable async's value port yields a failable async
that, if the input rejects, rejects with the same payload. This is
`.then`-chaining behaviour derived from structure — the walk hits the
terminator, has no instruction about it, and re-emits it. No new
machinery, and failure stays invisible in diagrams that do not handle
it, exactly like a promise chain.

**Discharge is where failure becomes data.** At a whole-flow close,
the terminator is *in hand*: the walk has finished, and
`Nil`-vs-`Fail(e)` is now a settled, genuine tagged value. By the
criterion the race section drew, this is precisely when `CaseSplit`
is the right tool — the sum *exists as data* on the close's output
side. No barrier is needed, and the bottleneck argument does not
bite: unlike race's contenders, the success value and the failure
payload have no independent upstream wires whose identity a packing
would sever. They are born at the same settlement.

For streams, discharge is where the expressiveness gap closes. A
whole-stream close over a failable stream has **two value outputs**:
the folded prefix, and the terminator. The three readings the commute
taxonomy catalogued map onto what you do with them:

- *All-or-nothing*: discard the prefix when the terminator is `Fail`
  — the same reading as the deferred result-commute (commute doc,
  open question 2), reached from the terminator side. Not identical:
  result-commute starts from errors *as element data* and would need
  an error-joining step to land here; whether that step or a separate
  primitive is nicer is that question's remaining content.
- *Prefix-up-to-failure with partial results kept*: use both outputs
  — the gap the taxonomy recorded, closed by making the terminator an
  ordinary value you case-split.
- *Skip-and-continue*: not this design at all — per-element
  recoverable errors are **data** (a stream of results, handled by
  filter closes). The boundary the commute doc drew stands: errors
  that end the flow live in the terminator; errors you recover from
  per element live in the elements.

### The three threads, unified

- **Parsing streams**: the producer ends the stream with `Fail(e)`.
  Source-side failability.
- **Interruption**: the `interrupt` combinator writes
  `Interrupted(e)` as the derived stream's terminator.
  Combinator-side failability — same slot, different provenance.
- **Async rejection**: terminator payload on the exactly-one flow. JS
  rejection at the FFI boundary (where real JavaScript promises enter
  the language) maps into it; a cell whose promise rejects is a flow
  that terminated with payload.
- **Async streams compose the two levels correctly for free**: a
  stream cell that rejects is a stream whose termination arrived
  early — the rejection *joins into the stream's terminator* (the
  stream ends `Fail(e)`), which is the commute doc's "you would join
  the error in, not commute it out" observation landing exactly where
  it predicted.

Race also composes cleanly: racing failable contenders is JS-honest —
first *settlement* wins, including a rejection. Contender `i`'s
output flow fires iff `i` settled first; if it settled by failing,
that lane's continuation is a failable flow whose terminator already
fired, and propagation does the rest — the close's output async
rejects with the winning contender's failure payload. No extra ports
on the race barrier; the failure rides the terminator through it.

So, the verdict on the either/or you might have wondered about —
"keep async infallible and layer `result` inside" versus "make the
async flow failable" — is **neither, as posed.** Layering `result`
inside treats a termination as data prematurely and does nothing for
streams; making the async flow failable as a one-off re-derives the
same design three times. Failability is a uniform dimension on flow
kinds — terminator payloads — with `result`-as-data remaining correct
for element-level errors on the other side of the recover-vs-end
boundary. (Both one-sided forms are settled rejections *as posed*;
what replaced them is the uniform dimension above.)

**What this does not settle:**

- **Payload type composition.** Chaining closes over flows with
  different payload types `E1`, `E2` needs either payload unification
  at joins of failability or an error-mapping operation on the
  terminator. Probably small; not worked out. *Now adopted*
  (`failure-payloads-design.md`, 2026-07-23): neither, as posed —
  the payload sets are derived, not artifacts; a terminator lane is a
  set of drawn minting sites grouped by tag, the inventory at any
  consumer computed by property propagation (union along stacks,
  nesting, chained closes), with an error-mapping stage drawn only
  where meaning changes (discharge, transform, re-fail).
- **Do bodies raise?** A JS `async` function converts thrown
  exceptions into rejections automatically. If compiled bodies
  inherit that, *every* async close is failable whether declared or
  not — JS-honest, but it erases the infallible/failable distinction
  the table draws. The alternative — bodies are total, failure enters
  only at declared sources — is cleaner and less honest. Genuinely
  open. *Now adopted* (`failure-payloads-design.md`, 2026-07-23): the
  cleaner side, with the honesty bill paid at the edge — failure is
  drawn (`fail`, end-when's failure-tagged sibling), declared throws
  enter by catalog row, and undeclared throws land on the
  **background super flow** (a runtime-owned lane outside every
  drawn inventory, collectable where wanted — see that doc's
  adopted edge section), so the infallible/failable distinction
  becomes derived and readable rather than declared.
- **Port structure.** The discharging close's two value outputs
  (prefix + terminator) is more port structure than current close
  nodes carry — the same pressure as the race barrier. Worked with
  the other barrier corners in `barrier-value-crossing-design.md`.
  The lean there: on exactly-one kinds the discharge is one value
  output (the settled sum, as this section argues); on many kinds it
  is the (prefix, terminator) pair on one collect — two ports rather
  than a packed pair (product bottleneck) or two sibling collects
  (the standalone total fold would be an error-swallowing primitive).
  Race's per-contender (value, flow) pairs are derived there from the
  same criterion. Leanings prepared for the design conversation, not
  adopted.
- **Option convergence.** With failure in the flow, the failable
  async and a "later result" are the same thing, and option is the
  payload-less *now* row — a convergence sharpened but not decided
  (see open questions).

## External event sources

Timers, user input, incoming messages: these are *push* sources, and
the language is *pull*. The adapter is an async stream whose cell
resolution is wired to event arrival: cell N's promise resolves when
the Nth event fires.

The mismatch between push and pull shows up when events outpace
pulls. If events N and N+1 arrive before anyone pulls cell N, the
adapter must choose:

- **Buffer** (queue events; every pull gets the next queued event;
  nothing is missed). The natural default — it preserves the stream
  reading exactly.
- **Latest / drop** (a pull gets the most recent event; missed ones
  are gone). Right for "current mouse position"-shaped sources where
  history is noise. This is arguably a different source kind, not a
  policy flag on one kind.

A separate wrinkle: stream cells are memoised, so any consumer can
walk an event stream from the beginning — which means the adapter
retains *every event ever*, live, as long as the stream's head is
reachable. For bounded computations that is fine; for a long-lived
event source it is a leak by design. Event sources probably want
either heads that are deliberately not retained (consumers hold
cursors, history behind the earliest cursor is GC-able — which the
chain structure already gives us if nobody keeps the head) or an
explicit windowing operation. Recorded as an open question.

Push sources have a pull sibling: `source-openers-design.md` works
the external pull source as a catalog block minting a failable
stream, presented as this adapter's pair (same boundary, opposite
driver), along with the self-driven opener and pacing. The retention
question above applies to pull sources verbatim and is referenced
there, not moved.

## Effects, abandonment, cancellation

The language has no side effects yet; the IO marker flow is
designed-ahead vocabulary (the commute taxonomy's
marker-out-of-sequenceable entry). But racing forces the question
earlier than elsewhere, so the shape should be on record:

- **Pure work**: abandonment is invisible to the program's meaning. A
  lost racer or an interrupted step wastes the CPU it already
  consumed and nothing else. The memo even recovers some of the waste
  — anything the abandoned computation shared with a surviving
  consumer is pre-warmed for them, the same effect as the commuted
  close's pre-warming in `lazy-stream-commute-design.md`.
- **Effectful work**: "started but overtaken" is observable. If the
  losing side of a race had already written half its output, the
  program's meaning includes that half-write. JS offers no
  preemption; real cancellation is cooperative
  (AbortController-shaped tokens threaded to the effectful leaves)
  and best-effort.

Options when the IO design arrives, roughly: (a) lost racers' effects
simply happen (JS-honest, and a footgun exactly where races are most
useful); (b) a cancel signal is delivered on abandonment, cooperative
and best-effort; (c) effects are restricted to commit points a race
cannot split. Deciding is premature here; what this chapter
contributes is the constraint that **the async design must not
preclude threading a cancellation capability through the async cell
later** — the cell is the natural carrier, since it is the unit that
gets started and abandoned.

## Commuting async out of stream

`stream<async<X>>` → `async<stream<X>>` fits the commute taxonomy's
"sequenceable × sequenceable, different kinds" slot, next to
option-out-of-stream. The walk is the same shape as option commute's
— consume the stream layer, produce one outer value — with two
differences:

- **No short-circuit.** Async does not fail (before failability
  lands), so the walk is unconditional, like the marker case.
- **A genuinely new degree of freedom: start order.** Option commute
  had one possible walk. Here the walk could await each element's
  async before starting the next (sequential; wall time is the sum)
  or start them all and then await in order (parallel; wall time is
  the max — `Promise.all`).

Which is "commute"? From the laziness principle: commute consumes the
whole stream layer — the user asked one question about the entire
stream, and the consumed layers give up their incremental laziness
(the established per-layer rule). Once the whole layer is demanded
*at once*, starting everything is the natural reading, and start is
synchronous and free. So **commuted async-out-of-stream starts all,
awaits in order** — provided the elements' asyncs are structurally
independent.

Structure guards the exception automatically: if element N+1's async
input depends on element N's *resolved* value, the N+1 cell cannot
even be constructed before N resolves — sequentiality is forced by
the wiring, not by a mode. The same structural rule as the fork-join
section, applied per element.

One honest caveat: for effectful asyncs, start order is observable
timing, and "start all" bakes in one choice. This mirrors the
marker-commute discussion (timing, not data) and should be revisited
with it. If both orders turn out to be wanted, that is two output
constructions, not one with a flag — but deciding needs a concrete
effectful use case.

The infinite-stream footgun from the join doc applies verbatim:
commuting an infinite async stream never resolves (and under
start-all, tries to start unboundedly many cells — the walk should
interleave start with the pull of the next cell, which bounds it
naturally: pull cell N+1, start it, await cell N).

## Compile sketch

Nothing here needs machinery beyond the async cell and the existing
simple-lazy compile discipline:

- `async<X>` at runtime is the `__asyncCell__` two-state cell;
  forcing returns a promise; the promise's own memo covers
  in-flight/resolved.
- An async close compiles to one async cell whose thunk is an `async`
  arrow containing the body — awaits where async opens' value ports
  are read, plain bindings elsewhere. The emitted JS uses
  `async`/`await` freely; the eager-semantics discipline is entirely
  about *creation points* (no promise constructed outside a cell
  thunk), not about avoiding the syntax.
- Concurrent join: start all inner cells, then await, as sketched
  above.
- `race`: the barrier compiles to start-all plus `Promise.race` over
  tagged wrappings (each contender's promise mapped to `{tag, value}`
  before racing), the tag dispatching into the winning branch's scope
  — compile-internal bookkeeping, never a user-visible value.
- Async streams are the existing stream cells with the async cell in
  the `Delayed` position — precisely the prototype's
  event-loop-integrated `Delayed` (`tick()`), un-stripped. The
  placement/chain analysis from `lazy-stream-placement-design.md` is
  untouched: consumer-sets and chains do not care whether a cell's
  force is synchronous or awaited, for the same reason commute and
  join did not — it is all behind the pull interface.

## Open questions

The language hasn't decided everything in this chapter. Here is what
remains genuinely open, and what has since been resolved:

1. **Failure** — *resolved.* See "Failure as terminator payload": one
   design covers async values, interrupted streams, and parsing-style
   failable streams (failability = a payload on the flow kind's
   termination event; propagate by default, discharge to a data sum
   at a whole-flow close). Residual sub-questions — payload type
   composition, whether bodies raise, the discharging close's port
   structure — are recorded at the end of that section. The first two
   now carry their own worked round (`failure-payloads-design.md`,
   exploration); the port structure stays with
   `barrier-value-crossing-design.md`.

2. **Cancellation.** Deferred to the IO design, with the constraint
   recorded above: the async cell must be able to carry a
   cancellation capability later. What does the *diagram* show when a
   race implies possible cancellation of a subgraph? *The IO design's
   cancellation round now exists* (`cancellation-design.md`,
   exploration): the cell carries no token — delivery is a
   `Cancelled` terminator written at yield points to cells stranded
   by ceased demand — and the diagram question's answer there is
   "nothing new is authored"; a derived at-risk view is the named
   candidate.

3. **Event-source retention.** Cursor-based GC of event-stream
   history vs explicit windowing vs "latest"-kind sources. Also
   whether multiple consumers of one event source should ever see
   different suffixes (subscribe-time semantics) or always the same
   memoised sequence.

4. **Start order under commute, once effects exist.** Is
   start-all-await-in-order the only commute, or do sequential and
   parallel walks become two distinct output constructions? Needs a
   concrete effectful use case.

5. **Barrier representation in the Expr graph.** Race needs
   per-contender flow and value output ports on one construct — more
   port structure than any current node kind carries (Branch is the
   nearest precedent). This is largely worked:
   `first-class-ports-design.md` gives the Expr-level representation
   (per-kind port inventories, `ValuePort`/`FlowPort` refs), with the
   race barrier in its pressure inventory as a client — per-contender
   value + flow output pairs fit directly, no Branch-style satellite
   nodes. `barrier-value-crossing-design.md` works the port/crossing
   corner (values-in, minted per-contender pairs, derived from the
   co-location criterion). The barrier's own semantics round exists
   as `race-barrier-design.md`: the barrier's law with drawn-order
   ties, the unary-race-is-the-async-open leaning, subset merges
   landing failable-by-construction, dynamic sets redirected to the
   completions stream, the lost-cell cancellation trigger, and
   merge/interrupt pinned as catalog blocks with corecursive derived
   lowerings. Arity is settled by the barrier form: N-ary from the
   start (the `race(a, race(b, c))` composition question was an
   artifact of the rejected alt-value form). Leanings prepared for
   the design conversation, not adopted.

6. **Is the async open its own kind, or is the option open a
   degenerate async?** They share the one-shot-body shape. Keeping
   them separate seems right (data-discrimination vs
   time-displacement; option has a none case, async does not). With
   failure now in the flow, the convergence sharpened as predicted —
   option is the payload-less *now* row of the failability table,
   failable async the payload-carrying *later* row. Still not merged:
   the now/later distinction (a checkable discriminator vs an
   unobservable-until-event zero case) remains a real difference in
   meaning, not just a compile-target difference.

7. **Fairness and starvation.** Two merged streams where one resolves
   synchronously-fast can starve the other's turn on the event loop
   between pulls. "Whatever the event loop does" is probably the
   honest answer, matching the determinism stance under racing.
   Relocated by `race-barrier-design.md`: for race itself the
   question is vacuous (one settlement; the only bias is the
   specified drawn-order tie-break), and merge's fairness variants
   are per-heads-decision variants belonging to the decision-driven
   merge family's round — confirming the "explicit operation"
   suspicion with an address. A leaning, not adopted.

8. **Naming.** "Async flow" for the kind; the open's constructor name
   (`AsyncIter`? `Await`?); "race" vs "select"; "interrupt" vs
   "until". Deferred, as commute-vs-sequence was.

## What this doesn't address

- **Visual depiction.** What an async open, a concurrent join, a
  race, or an interrupted stream look like on the canvas is the
  visual side's problem, out of scope in this repo. One note worth
  passing across: the fork-join and 2D-join drawings in the retired
  `visual-flow-language.md` (preserved in git history) were designed
  for exactly the concurrent-join meaning used here, so the visual
  vocabulary may already exist.
- **True parallelism.** Workers, shared memory, actual simultaneity.
  This chapter is event-loop concurrency only.
- **Loop-carried state across async steps.** A Delay node inside an
  async stream flow — state threaded from step to step of a
  long-running process — is the reactive-systems bread and butter and
  probably composes without new design (the register lives in the
  walk), but it deserves its own worked examples once the
  iteration-state candidates settle. The check this deferral rode on
  is since paid (`delay-ontology-design.md`, "Per-kind \"next
  iteration\": the owned-order criterion", exploration, not
  adopted): the async *value* supplies only a degenerate "next" (one
  firing — the bar was cardinality, not async-ness), while an async
  *stream* owns its arrival order and so supplies a real one — the
  "probably composes" above is confirmed at the meaning level, with
  the productivity clock the event-loop turn. The worked examples
  are still owed here.
- **Scheduling and priorities.** Beyond fairness (open question 7),
  nothing here about prioritising one thread's progress over
  another's.
- **Implementation.** As with the stream docs: design first, and the
  stream-flow runtime this builds on does not exist in the compiler
  yet either. The dependency order is: stream flows, then async
  cells, then async streams / race / interrupt.
