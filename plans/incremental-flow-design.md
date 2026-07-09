# Incremental Flows

## What this is for

> Terminology note (2026-07-09): written just before the
> uncollect/collect correction; "close" throughout means collect.

State that varies over time, with dependencies tracked: a value
that is always readable *now*, whose current value changes as its
inputs change; derived values that stay consistent with their
inputs; and the efficiency guarantee that gives the flow its name —
**a mutation triggers at most one recomputation per affected
node**, no matter how many paths connect the mutation to the
reader. The reference point is Jane Street's Incremental library.
We call the flow kind that carries these the **incremental flow**,
and its values **state variables**, written `var<X>` (naming is an
open question, as usual).

This is emphatically *not* the async flow, despite both involving
time. The incremental graph is **fully synchronous**: reading a
var, and the update pass that keeps derived vars consistent, are
plain synchronous computation. Time enters only at the boundary —
mutations are triggered by async events, and async events may need
to fire when a var changes. Those two boundary crossings are the
tricky part, and they get their own sections.

Two breadcrumbs from `async-flow-design.md` point here. Its
external-event-sources section adapted push sources to pull
streams and left the "latest / drop" source kind dangling as
"arguably a different source kind" — that kind turns out to be
this document's `changes` boundary. And its what-this-doesn't-
address list deferred "loop-carried state across async steps" —
the register that accumulates across events is exactly how a
mutable var is built without a mutation effect (see "The mutation
boundary" below).

This is a starting-point document in the same spirit as the async
one: it works out what falls cleanly out of the existing design,
lays out options where a real choice exists, and records the rest
as open questions.

## Where it sits: a third temporal mode

The async doc's now/later table gets a third column. A var is not
*now* (a fixed value) and not *later* (a value that arrives): it
is **always** — at every moment it has exactly one current value,
readable synchronously, and the value at one moment may differ
from the value at another.

|              | now           | later        | always (varying)    |
|--------------|---------------|--------------|---------------------|
| zero-or-one  | option flow   | failable async | —                 |
| exactly one  | (plain value) | async flow   | **incremental var** |
| many         | list flow     | async stream | —                   |

The two dashes are worth explaining, because both are claims:

- **Zero-or-one, always** would be a var that sometimes has no
  value. That is just `var<option<X>>` — the absence is *data*
  that varies, not a property of the flow. A var must always be
  readable; that is the kind's defining property, and it is why
  the initial value is load-bearing throughout this document.
- **Many, always** would be a time-varying *sequence you can
  walk*. But a var deliberately has **no history** — the previous
  value is gone the moment the current one exists. The history of
  a var is an async stream (that is what `changes` produces,
  below), and a time-varying collection is `var<list<X>>` — a
  collection as *data*, varying as a whole. (Propagating *diffs*
  of a varying collection — Jane Street's `incr_map` — is real
  and deferred; open question 6.)

In FRP vocabulary this is the behavior/event split: async streams
are events (things that *happen*, awaited), vars are behaviors
(things that *are*, read). The table says it structurally: the
async column's values are awaitable, the always column's are
readable. What the incremental flow adds beyond "a mutable cell"
is the dependency tracking — derived vars that follow — and that
is all in the open/close structure, next.

## The incremental open

A `var<X>` opens the way the other kinds do. `Open` on a
var-typed input yields one value port — the **current value** —
and one flow port — the **tracking context**. Everything computed
from the value port lands inside the context, and everything
inside the context is *tracked*: it is the stuff that must be
recomputed when the input changes. A close on the flow packages
the body's result back up as a `var<Y>`: a derived variable whose
current value is the body applied to the input's current value,
kept consistent as the input changes.

Comparing the guards across the one-shot kinds:

- Option's body runs **zero or one** times, discriminated by data.
- Async's body runs **exactly one** time, displaced in time.
- The incremental body runs **once per version** — re-evaluated
  whenever the input changes.

So the incremental flow is *recurrent* where option and async are
one-shot, but unlike the many-kinds there is no sequence of
elements: the "iterations" are versions of one value, and only
the latest exists. There is nothing to fold — a close over an
incremental flow doesn't accumulate across versions, it just
repackages the per-version value as a var. (Accumulating across
versions is real and important — a counter *is* that — but it
lives at the event boundary where the versions are events; see
"The mutation boundary".)

One property worth pinning down early because everything else
leans on it: **the value port is readable whenever demand
arrives.** An async open's context is about *availability* — the
body cannot run before the value exists. An incremental open's
context is about *tracking* — the value always exists; the
context records that whoever computes from it must follow it. The
context costs recomputation, not waiting.

## Static dependencies are the concurrent join

Two vars combined — `total` from `price` and `qty` — is the
bread-and-butter operation, and it is the concurrent join again,
exactly as it was for parallel asyncs. Open both vars; the two
tracking contexts are sibling flows; by the no-time-travel rule
their value ports don't combine directly; **Join with multiple
inner flows** merges the contexts, and in the merged context both
current values are available and combine freely. The close yields
`var<Total>` — a derived var that recomputes when *either* input
changes.

No tuple is packed to pass the join — the no-bottlenecks
principle, product form, one more time. `price` and `qty` pass
through as themselves; the reader sees two wires enter the merged
context and one derived value leave.

This is the applicative structure (`map2`, `lift2`), and the
observation that makes the whole design click is: **the wiring
already is the dependency graph.** Jane Street programs *build*
a dependency graph by calling `map2`; here the diagram the
programmer drew *is* that graph. There is nothing to construct
and nothing to keep in sync with the program, because they are
the same object. Semantics structural, not nominal, again.

## Join is switch: the dynamic dependency

The user-facing backbone of the design: the monadic join on state
variables,

    join : var<var<X>> → var<X>

A `var<var<X>>` arises the same way nested flows always arise: a
computation *inside* one var's tracking context that produces a
var. The canonical case — inside `selector`'s context, pick
`varA` or `varB` by the selector's current value; the close
yields `var<var<X>>`; the Join collapses it. The joined var's
current value is the currently-selected inner var's current
value, and it changes when **either** the outer changes (the
selection switches) **or the currently-selected inner** changes.
The *unselected* inner is not a dependency at all: mutations to
it do not touch the joined var.

This is FRP's `switch`, Incremental's `bind`, and it is what
"selecting a dynamically chosen dependency" means: the dependency
graph's *shape* — which edges exist — is itself a function of a
var's current value.

The correspondence with the async flow is exact and worth
stating, because it is the same structural rule read twice:

- **Async**: nesting is sequential (monadic bind, wall time is
  the sum); siblings + concurrent join is parallel (applicative,
  wall time is the max).
- **Incremental**: nesting is *dynamic* (monadic bind, the graph
  can change shape); siblings + concurrent join is *static*
  (applicative, the graph is fixed).

In both, the monadic form is the more expensive one and the
structure makes the cost visible. To know whether a piece of
async runs in parallel, you look for nesting; to know whether a
dependency graph can change shape, you look for a Join collapsing
a `var<var<…>>`. Everything not under such a Join is static, and
a reader (or a compiler) can see that from structure alone. Jane
Street documents `bind` as the operation to avoid when `map2`
suffices, as a *convention*; here the distinction is a visible
structural fact.

Kind-consistency check: join for lists flattens a sequence of
sequences; join for streams splices inner streams end-to-end;
join for vars switches among inner vars. Each is the monadic join
of its kind — for the always-column, "flattening" one level of
var-ness means following the outer's current selection. And as
with lists and streams, switch-join should be the same join
operation, not a new node species. *(2026-07-07: this paragraph
originally said "the same per-close annotation
(`Joined(flowRef)`)"; that spelling has since been superseded by
binary Join nodes — see open question 7's update. The point
stands with the node substituted: switch-join reads as a Join
variant with a var-kinded operand.)* Whether that reuse survives
contact with the Expr graph is open question 7.

## Glitch-freedom, and the pull model

The "at most one update" guarantee is where incremental systems
earn their keep, and the classic failure is the **diamond**:
`a` feeds `b` and `c`; `b` and `c` feed `d`. A naive push system
propagates `a`'s change along one edge at a time, so `d`
recomputes twice — and worse, in between it computes from a
*mixed* state (new `b`, old `c`) that never logically existed.
That transient is a **glitch**. Incremental prevents it with
machinery: topological heights, a priority queue, an explicit
`stabilize` pass — and the dynamic dependencies from `bind` make
maintaining the heights genuinely hard.

Our language is pull, and pull dissolves most of this. The model
that falls out of the existing evaluation discipline:

- **A mutation computes nothing.** Setting a root var stores the
  new value, bumps the root's version, and bumps a global
  generation counter. No propagation, no traversal of dependents
  — the graph doesn't even need dependent edges.
- **A read pulls.** Reading a derived var checks whether its
  inputs changed since the value it holds was computed
  (recursively, versions compared down the input wires), and
  recomputes only along paths where something actually changed.
  Per-generation memoisation makes the check linear: each node
  verifies or recomputes **at most once per generation**,
  regardless of how many paths reach it. That is the diamond
  handled: `d` pulls `b` and `c`, each pulls `a` (second pull
  memoised), `d` recomputes once, from consistent inputs.
- **Glitch-freedom is automatic.** A read is one synchronous
  pass over a *frozen* generation — mutations happen on the
  event loop between turns (the only place they can come from;
  see the boundary sections), never mid-read. Mixed states are
  not merely avoided; they are unconstructible. Push systems
  fight for this property; pull gets it by having no moment at
  which half a propagation is visible.

The user-level guarantee comes out *stronger* than "a single
mutation triggers at most a single update": any number of
mutations between reads trigger at most one update per node —
batching is the default, not a feature. And laziness is
preserved in full: a derived var nobody reads never recomputes,
no matter how often its inputs churn. Ten thousand mutations to
`a` with no read of `d` cost ten thousand version bumps and zero
recomputations.

The pull model also collapses the hardest part of Incremental:
under pull, `bind`'s dynamism is nearly free. A joined var's read
pulls the outer, then pulls whichever inner is *currently*
selected — the "dependency switch" is just which cell this
generation's read path traverses. There is no subscription to
tear down, no subgraph to rebuild, no heights to adjust, because
there were never dependent edges in the first place.

Honesty about the trade: pull pays on read what push pays on
write, and there is a fan-out pathology where pull's price is
genuinely wrong — bad enough that Incremental's push model is
arguably the computation model to aim for, with pull as the
semantic baseline and first implementation. That gets its own
section below ("The push model, and the demand problem"). The
short version: the two are observably identical here (bodies are
pure), so the choice is real but deferrable — a compile-strategy
choice, not a semantics choice.

> **Recorded position (design review, 2026-07-09).** Sharpened:
> pure pull is rejected as the long-term model, not merely
> disfavoured. Beyond the fan-out pathology, it makes partial
> updates to lists and similar structures harder to track. It may
> still serve as the convenient first implementation and remains
> the semantic baseline the hybrid must agree with; the destination
> is push-with-values inside a necessity frontier.

### Cutoff

Version bumps say an input *may* have changed; cutoff is the
refinement that recomputation stops where values are **equal**.
If `b = f(a)` recomputes to the same value it already held, `b`'s
own version doesn't bump, and `d`'s pull of `b` sees "verified,
unchanged" — the cascade stops. In the pull model this is one
equality check at each recomputation, in exactly the right place.

Cutoff is recognisably the **filter of this flow kind** — but on
the *change* dimension, not the value dimension. A filtered close
over a var is ill-formed (a var that sometimes has no value isn't
a var; the zero-or-one column is closed for the always row). What
*can* be suppressed is a change: "this version is not a real
change; don't propagate it." Whether cutoff is built-in structural
equality, an explicit node carrying a user equivalence (Jane
Street lets you set the cutoff function per node), or both, is
open question 2. It matters at the `changes` boundary below,
where a spurious propagation becomes a spurious *event*.

## The push model, and the demand problem

The pull model above fixes the *semantics*. Whether it is also
the right *computation model* is a separate question, and there
is a strong case that it isn't — that Incremental's push model
computes the right amount of work and pull doesn't. This section
works that case, and then the problem that has to be solved
before the push model fits this language: where observers come
from when there is nowhere to call register/deregister.

### Where pull pays wrong

Consider a var `x` with a large fan-out: many derived vars
depend on it, directly or transitively, and all of them are
watched. `x`'s own inputs churn, but cutoff absorbs the churn —
`x`'s *value* rarely changes.

Under push, each mutation recomputes the path down to `x`, the
cutoff says "unchanged", and propagation **stops at `x`**. The
fan-out is never touched. Work per mutation is the dirtied
region up to the cutoff frontier — proportional to genuine
change.

Under pull, there is no moment at which the cutoff can stop
anything, because nothing is computed at mutation time. Each
mutation bumps the global generation, which silently invalidates
every reader's fast path — including readers in unrelated
subgraphs. On its next read, every watcher walks down its input
wires to rediscover, individually, that nothing changed:
per-generation memoisation means `x` itself is verified once,
but the *paths* to it are per-reader. Verification cost is
O(edges reachable from all active readers) per generation, paid
even when the answer is "no change anywhere".

The dirty-bit refinement (Adapton-style: mutations push a dirty
flag along dependent edges, reads verify only dirty paths) does
not fix this, and the reason is instructive: **dirt is
value-free.** A dirty flag must propagate *past* `x`, because at
dirtying time nobody knows `x` will come out equal — so the
whole fan-out gets flagged, and each reader still verifies down
to the cutoff. Only push-with-values can evaluate the cutoff
*during* propagation and stop there. That is the real content of
Incremental's model, and why it is worth trying to keep: **work
proportional to genuine change, bounded by cutoffs, independent
of fan-out beyond them.**

### Push's price, and the structural answer to observers

Push's classic downside is computing values nobody needs. What
Incremental does about it is not optional laziness but
**mandatory observation**: a node recomputes iff it is
*necessary* — some registered observer transitively depends on
it — and observers are explicitly created and released, with
necessity maintained as the graph and the observer set change.

An imperative register/deregister API has no home in this
language; there is no call site to put one at. But the language
doesn't need one, because of a fact already true structurally:
**there is no bare read of a var.** Every consumer is one of
exactly three shapes —

- another var (an interior edge; necessity propagates through
  it),
- a drained `changes` stream (a standing observer),
- a sample at an event (a one-shot read; below).

Consumption is boundary constructs all the way down, and each
boundary construct has a lifecycle the compiler can see.
"Mandatory registration" is not a discipline the user follows;
it is what the language's shape already enforces. The question
reduces to: do the boundaries' lifecycles produce registration
and deregistration *events* at the right moments?

### Registration is the pending pull

The apparent mismatch: the async side is pull-based and lazy, so
it seems either always interested (if the `changes` adapter
registers eagerly, the subgraph computes forever whether or not
the stream is ever drained again) or never positively
*un*interested (a consumer that stops pulling just stops —
silently; abandonment is not an event in a pull world).

But pull-based interest is not continuous — it is expressed at
discrete moments, and those moments have exactly the right
shape. A drain of `changes(v)` proceeds pull by pull, and **a
pending pull is a registration**: it begins when the consumer
forces the next cell (a positive event — the runtime sees the
force) and ends when the change is delivered (another positive
event — the cell resolves). While a pull is pending, `v`'s
subgraph is necessary and mutations push through it, cutoffs
stopping them early — Incremental's model, exactly, over the
region someone is actually waiting on. Between delivery and the
consumer's next pull, no observer exists; a consumer that never
re-pulls has thereby deregistered, with no signal needed beyond
its silence.

Two refinements make this practical:

- **Linger to turn end.** Deregistering at delivery and
  re-registering at the next pull would flip necessity once per
  delivery — and necessity changes are the expensive part of
  Incremental's bookkeeping, amortised there by observers being
  long-lived. But an active drain re-pulls promptly (typically
  within the same turn), so a registration should *linger*: keep
  necessity until end of turn, tear it down only if no re-pull
  arrived. The common case is zero churn, and the deregistration
  event is the turn boundary — prompt, and already this design's
  clock (generation granularity, open question 3).
- **Verify on registration.** A fresh registration (or one
  re-established after a gap) finds the subgraph possibly stale —
  no observer was keeping it current. One pull-style verification
  pass over the newly-necessary region brings it up to date,
  which is also what Incremental does on observe. So the runtime
  needs the versioned-pull machinery *anyway*, for exactly this:
  reading a currently-unnecessary node. Sampling — the one-shot
  read of a var at an event — is the same operation and wants no
  registration at all: samples are sparse, and pull-verify is
  the right cost for them.

The shape that emerges is a **hybrid with a necessity frontier**:
push-with-cutoffs inside the necessary region (the union of
subgraphs under pending-or-lingering registrations), versioned
pull outside it and at registration edges. Pure pull is the
degenerate case where the necessary region is always empty —
which is also the staged implementation path: build pull first
(it fixes the semantics and is far simpler), add the push region
as an optimisation later, and nothing observable moves.

That last claim has a one-line proof: with bodies pure — effects
forbidden inside tracking contexts — push and pull differ only
in *when* a value is computed, never in what it is or in what
`changes` delivers. The choice is invisible except as
performance, which is what makes deferring it safe. (This is a
second independent reason tracking contexts must exclude
effects; re-entrancy was the first.)

One cost moves back in, honestly: within the necessary region,
dependent edges exist again, and switch-join changes them —
Incremental's necessity-under-`bind` bookkeeping, the hard part
pull had dissolved, returns to exactly the extent the push
region is used. Pull outside the frontier keeps it contained,
but it does not vanish.

### The residual hole is the cancellation gap

One case stays ugly: a consumer abandoned *while its pull is
pending*. The registration ends at delivery — but delivery
requires `v` to actually change. Until it does, the subgraph
stays necessary, and mutations that cutoff absorbs keep
recomputing the path up to the cutoff, for nobody. If `v` never
changes again, that continues indefinitely.

This is not a new wart; it is the async doc's **abandonment ≠
cancellation** gap wearing incremental clothes. Deregistration-
on-abandonment *is* cancellation: the pending pull is an async
cell, and the constraint the async doc recorded — the cell
should be able to carry a cancellation capability later — is
exactly what would close the hole (cancelling the cell releases
the registration). Until the IO design supplies that, the
backstops are the usual ones: tolerate the waste (it is bounded
by the first genuine delivery, if one comes), or GC-based
teardown (finalizers releasing registrations, promptness at the
collector's pleasure). Recorded so the IO design inherits this
consumer of the cancellation capability alongside the async
doc's.

## The mutation boundary: events in, hold

Everything above describes a pure dependency structure. Something
has to actually mutate a root var, and the language has no
effects. The move that keeps the var layer pure: **all mutation
enters as event arrival.** The primitive is the classic FRP
`hold`/`stepper`:

    hold : (X, stream<X>) → var<X>       -- stream async

`hold(initial, events)` is a var whose current value is the most
recent event's payload, or `initial` before any event has fired.
Each event arrival is a mutation of this root: store, bump
version, bump generation.

Three observations:

- **The initial value is load-bearing, and familiar.** A var must
  be readable at every moment, including before the first event —
  so a root var cannot exist without an initial value, and the
  initial value is the complete answer for the no-events-yet
  case. This is the same double duty the iteration-state design
  found for the link's initial value (starting point for the
  non-empty case, complete answer for the empty case), arriving
  from the temporal side.
- **The var layer is a derived view of event history.** Given the
  event streams at its roots, the entire incremental graph is
  pure — `hold` plus the dependency structure determines every
  var's value at every moment. There is no `set` effect in the
  language; a var is not a mutable cell you assign, it is a fold
  of events you declare. When the IO design eventually arrives, a
  user-level `set` operation, if wanted, is an event *source*
  (calls arrive on the event loop) feeding a `hold` — sugar, not
  a new kind of mutation. Recorded as open question 5.
- **Accumulation is the register over the event stream.** `hold`
  keeps the *latest* event; a counter needs the latest *plus
  history folded in* — state carried from event to event. That is
  precisely the iteration-state register (the design still
  settling between candidates) applied to an async stream: the
  deferred "loop-carried state across async steps" item, landing
  here as *scan-then-hold*. Count the clicks with a register over
  the click stream; `hold` the running count; every var derived
  from it follows. The iteration-state design and this document
  compose at exactly this point and should keep each other in
  view.

The productivity story carries over too. A cycle in the
incremental graph — a var whose value depends on itself — is
ill-formed by the same rule as iteration state: **every cycle
must cross a register**, which here means the feedback passes
through the event boundary and re-enters at a strictly later
event-loop turn. Instantaneous self-dependence is rejected; a var
updated *by events computed from its own previous value* is fine,
because "previous" is a real earlier turn. Same check, same
precedent (synchronous dataflow causality), new clock: the
event-loop turn is the tick.

## The observation boundary: changes out

The converse crossing: async computation that reacts when a var
changes — re-render when the model updates, send when the status
flips. The primitive:

    changes : var<X> → stream<X>          -- stream async

`changes(v)` is an async stream that delivers `v`'s new value
each time it changes. Draining it is what Incremental calls an
**observer**, and demand flows exactly the way the language wants
it to: the drain forces reads of `v`, the reads pull the
incremental graph, and a var with no drained `changes` (and no
other reader) never recomputes at all. Observation isn't an extra
concept bolted on — it *is* the consumer-side demand the rest of
the language already runs on.

Two properties fall out of the pull model and are worth stating
because they'd be design decisions in a push system:

- **`changes` is a latest-kind source, inherently.** The async
  doc's event-source section offered buffer vs latest/drop and
  suspected latest was "a different source kind, not a policy
  flag." Here it is: a var has no history, so `changes` *cannot*
  buffer — a pull gets the current value, and versions that came
  and went between pulls are not merely dropped, they were **never
  computed** (nobody read them; laziness means unobserved
  generations do zero work). The buffer-kind source exists too,
  but upstream: it is the event stream *feeding* the hold, where
  the events are real arrivals with identities. Downstream of a
  hold you are sampling a value, not collecting occurrences. The
  distinction the async doc groped for is the two sides of `hold`.
- **Cutoff bounds spurious wakeups.** `changes` fires per
  generation *in which `v`'s value actually changed* — a mutation
  upstream that cutoff absorbs never reaches the stream. This is
  where cutoff semantics (open question 2) becomes observable
  behaviour rather than pure optimisation.

One place genuine push is unavoidable, and it should be named
honestly: something has to *schedule* the drain's next pull. A
pending pull of `changes(v)` is an unresolved async cell; when a
mutation lands, someone must notice that the cell can now
resolve. The adapter: a mutation (event arrival at any hold)
schedules a microtask; the microtask visits the pending
change-stream cells, pulls each one's var (per-generation
memoisation makes overlapping visits cheap), and resolves the
cells whose values changed. This is **push of demand, not push of
values** — the microtask does no user computation itself, it just
converts "a generation happened" into "the pending pulls run",
and the pulls do pull-model work as usual. It also sets the
batching grain: mutations within one turn are one generation, so
a drain observes at most one change per turn, seeing the settled
end state and none of the intermediates. Whether the generation
should instead advance per *event* rather than per *turn* — the
difference is observable exactly and only through `changes` — is
open question 3.

### The round trip, and its law

`hold` and `changes` are adjoint-shaped, and the compositions are
worth a law each:

- `changes(hold(i, e))` is *not* `e`: it drops same-value
  arrivals (cutoff), conflates same-turn bursts to the settled
  value, and never replays `i`. It is `e` as *state transitions*
  rather than as occurrences — which is the entire semantic
  content of the hold/changes pair, stated as an inequation.
- `hold(v_now, changes(v))` *is* `v` (same current value at every
  moment) — provided the initial value is `v`'s value at
  subscription. That proviso is the subscribe-time question the
  async doc recorded (its open question 3), biting here: `changes`
  consumers get versions from their subscription onward, which is
  the memoisation-leak-free choice and also the only one
  consistent with versions-never-computed above.

## Worked example: the full loop

Clicks increment a counter; a label shows double the count; a
logger records label changes. One round trip, every piece of this
document once.

    clicks : stream<unit>                          -- event source (async doc)
    count  = hold(0, scan-over(clicks, n => n+1))  -- register + hold: mutation boundary
    label  = open count → n; close (n * 2)         -- derived var: incremental open/close
    log    = drain changes(label)                  -- observer: observation boundary

Forcing trace:

1. Nothing runs at construction — no clicks are subscribed, no
   var computed. The drain of `log` is the demand: it pulls
   `changes(label)`'s first cell, which registers a pending pull
   and (through the hold) starts the click source.
2. A click arrives. The register steps (`0+1`), the hold stores
   `1`, version and generation bump. The microtask fires, visits
   the pending cell, pulls `label`: `label`'s generation is
   stale, it pulls `count` (changed), recomputes `2`, the cell
   resolves with `2`. The logger's body runs; its recursion pulls
   the next cell; a new pending pull is registered.
3. Three clicks arrive in one turn. Three register steps, three
   version bumps, one generation, one microtask: `label` is
   pulled once, recomputes once (`8`), the logger sees one
   change. The intermediate values 4 and 6 were never computed.
4. The logger stops draining. From then on clicks still step the
   register (the hold is live demand on the click stream) but
   `label` is never pulled again — zero recomputation. If nothing
   else holds the click stream's head, dropping the whole graph
   makes even the stepping stop.

Step 3 is the promise of the flow kind in one line: N mutations,
one update. Step 4 is the language's laziness surviving the
boundary crossing intact.

## Interaction with the other flow kinds

- **`var<option<X>>`, `var<result<X,E>>`** — fine, and the right
  encoding for "sometimes absent" / "currently failed" state.
  The absence/failure is data that varies. No commute to
  `option<var<X>>` exists: whether the option is `Some` *varies
  over time*, and a var must always be readable — the commute's
  output kind can't hold the answer. By the commute taxonomy's
  criterion this is a swap with no coherent repackaging; it
  simply isn't in the table.
- **`stream<var<X>>` / commuting var out of stream** — a stream
  of vars is meaningful data (e.g. one var per connected client).
  Commuting it to `var<stream<X>>` would mean a var that changes
  when *any element* changes — a many-input lift. That is
  incremental-collections territory (a dependency on a varying
  *set* of vars) and is deferred with it: open question 6.
- **Failability** — does the always column have a terminator? A
  var that *ends* (its source closed, no further changes ever)
  is plausible and would give `changes` a terminating stream
  rather than an infinite one. Deferred; noted inside open
  question 4, since it is really a question about `changes`'s
  stream kind.

## Compile sketch

This sketches the pull baseline — per "The push model, and the
demand problem", the first implementation, with the push region
layered on later behind the same cell interface. Nothing beyond
the existing cell discipline plus a version word.

    const __gen__ = {n: 0};                        // global generation

    // root (hold)
    const __root__ = (v) => ({v, ver: 0});
    const __setRoot__ = (r, v) => { r.v = v; r.ver++; __gen__.n++; };

    // derived var: verified-at generation, inputs' versions snapshot
    const __derived__ = (t) => ({v: undefined, ver: 0, at: -1, t});
    const __readVar__ = (d) => {
      if (d.at === __gen__.n) return d.v;          // memo: once per generation
      // t() re-pulls inputs, compares their versions to the snapshot,
      // recomputes only if some version moved; returns {v, changed}
      const r = d.t();
      if (r.changed) { d.v = r.v; d.ver++; }       // cutoff: ver bumps only on change
      d.at = __gen__.n;
      return d.v;
    };

- A derived var's thunk closes over its input cells; the
  concurrent join compiles to reading several inputs in one
  thunk; a joined (switch) var's thunk reads the outer, then
  reads whichever inner cell the outer's value selects — the
  dynamic dependency is just a conditional read.
- `hold` compiles to a root cell plus a drain of its event
  stream whose per-event body is `__setRoot__` (and, for
  scan-shaped accumulation, the iteration-state register in the
  walk — per that design when it lands).
- `changes` compiles to an async-stream adapter holding a
  pending-cell registry; `__setRoot__` additionally schedules
  the once-per-turn microtask that pulls registered cells.
- All of this presumes the stream and async runtimes; the
  dependency order extends the async doc's: stream flows, async
  cells, async streams, then incremental cells and the two
  boundary adapters.

## Open questions

1. **Update model.** ~~Pure pull-with-versions (proposed above)
   vs push-dirty hybrid vs an Incremental-style stabilize pass.~~
   **Largely worked out** — see "The push model, and the demand
   problem": the target is a hybrid with a necessity frontier
   (Incremental-style push-with-cutoffs inside the region held
   necessary by pending/lingering registrations; versioned pull
   outside it, at registration edges, and for samples), with
   pure pull as the degenerate case and the staged first
   implementation. The two are observably identical because
   bodies are pure, so the semantics — reads see a frozen
   generation, at most one recompute per node per generation —
   is fixed independently, and no user-visible stabilization
   moment exists in either (the microtask stays invisible
   plumbing). Residual sub-questions: the linger policy
   (turn-end proposed), the cost of necessity maintenance under
   switch-join inside the push region, and prompt deregistration
   on abandonment — which is the cancellation gap, deferred with
   it to the IO design.

2. **Cutoff semantics.** Built-in structural equality, an
   explicit cutoff node carrying a user equivalence, or both.
   Becomes observable through `changes`, so it is semantics, not
   just optimisation. Also: is "cutoff is the filter of the
   always row" a slogan or a real structural identification —
   i.e. should it *be* a Filtered-style annotation on something?

3. **Generation granularity.** Per event-loop turn (proposed —
   bursts conflate, drains see settled states) vs per event
   (every arrival separately observable through `changes`).
   Observable exactly and only at the observation boundary.
   Per-turn matches "N mutations, one update"; per-event may be
   wanted for event-sourcing-shaped programs. Possibly a property
   of the `changes` operation rather than of the graph.

4. **`changes`'s stream kind.** Latest-kind, subscription-suffix,
   infinite — all argued above; each is a decision. Does a
   buffered variant ever make sense (debugging, replay)? Does a
   var end (terminator on the always column), making `changes`
   finite and failable-composable? Ties directly to the async
   doc's open question 3 (event-source retention).

5. **`set` as an effect.** When the IO design arrives, is
   user-level `set` an event source feeding a hold (proposed —
   keeps the var layer pure), or a genuine effect on a var? The
   former means "who can mutate this" is visible as wiring; the
   latter is more conventional and less honest. Also whether two
   independent `set` sites on one var are a merge of event
   streams (they should be — merge already exists).

6. **Incremental collections.** `var<list<X>>` recomputes
   whole-collection consumers per change; `incr_map`-style diff
   propagation is a large, separately-designed layer (and the
   home of the `stream<var>` commute question). Deferred until
   the scalar design is settled and a use case forces it.

7. **Expr-graph representation.** Does the incremental open fit
   `Open`/`Close` as a new openFlowKind with the usual value+flow
   ports? Does switch-join reuse the `Joined(flowRef)` per-close
   annotation, given that here it collapses var-nesting rather
   than merging stream layers? And `hold`/`changes` are
   kind-crossing operations (async↔incremental) with no current
   precedent — nearest neighbours are the commute node (crossing
   as a node with flow wires) and the race barrier (open question
   5 of the async doc, first-class ports), which this pressure
   strengthens from a third direction. *Update (2026-07-07)*: the
   port round now exists — `first-class-ports-design.md`, with
   `hold`/`changes` in its pressure inventory. Two of this
   question's sub-parts shift under it: kind-crossing nodes are
   just nodes whose port inventories mix flow kinds (the
   representation stops being the hard part; the semantics
   remain this document's), and the `Joined(flowRef)` per-close
   annotation this question asks about reusing has itself been
   superseded by binary Join nodes
   (`lazy-stream-join-design.md`, "Join is a binary flow
   operation") — so the switch-join question becomes whether
   switch-join is another Join-node variant with a var-kinded
   operand, which reads more natural, not less.

8. **Naming.** "var" vs cell vs signal vs behavior; "incremental
   flow" vs "reactive flow"; "hold" vs stepper vs latch;
   "changes" vs updates vs observe. Deferred, per tradition.

## What this doesn't address

- **Visual depiction.** What a tracking context, a switch-join,
  or the hold/changes boundary crossings look like on the canvas
  — out of scope in this repo. One note to pass across: the
  tracking context is a *permanent* region (its body re-runs
  forever), unlike iteration contexts that a reader understands
  as "per element"; the visual language may want to distinguish
  standing regions from per-element ones.
- **True concurrency.** One event loop; generations are globally
  serialised. Workers sharing incremental state is far out.
- **Effects inside tracking contexts.** A derived var's body
  re-runs at unpredictable moments driven by demand; an effect
  in there is a re-entrancy hazard (an effect that sets a var
  mid-read would break the frozen-generation invariant), and
  purity of bodies is also what makes the push and pull update
  models observably identical — an effectful body would turn the
  compile-strategy choice into a semantics choice. The IO design
  must either forbid effects inside tracking contexts or defer
  them to the boundary. Flagged now so the IO design inherits
  the constraint, as the async doc did for cancellation.
- **Implementation.** Design first, as with the stream and async
  docs; the runtime this builds on (streams, async cells) doesn't
  exist in the compiler yet. Dependency order recorded in the
  compile sketch.
