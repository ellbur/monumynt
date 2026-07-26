# Placement for Lazy Stream Flows

> **Status.** Two designs live here, and the distinction is
> load-bearing:
>
> - **Shape C — the per-node memoised stream — is the committed
>   baseline.** It is the runtime-lazy strategy the eager compile
>   already runs (`lazy-compile-design.md`), transposed to streams:
>   the compiler decides nothing about placement, and correctness
>   never depends on an analysis.
> - **The consumer-set lattice is a deferred optimisation pass over
>   that baseline — committed, not rejected.** It occupies the same
>   category `placement-algorithm-notes.md` occupies for eager flows.
>   What is deferred is the sequencing (build it once the semantics
>   settle), not the decision (one conceptual loop should compile to
>   one loop). It is gated on sequencing, not on benchmarks.
>
> Because multi-output works on the baseline by construction, the
> consumer-set bookkeeping (implementation steps 4–5) is off the
> critical path. Join, discussed in older drafts as a per-close
> "J/F fork," has since been settled — join is a binary flow
> operation (`lazy-stream-join-design.md`); the skip mechanism below
> is unchanged by that correction.

## What a stream flow is

We are adding **stream flows** alongside the existing list flows. A
list flow opens a whole list and iterates it eagerly. A stream flow
opens a value into a per-element flow that is **pulled on demand** —
each element is computed only when a downstream consumer asks for it,
and then only once.

```
xs -> open stream -> double -~> collect => out
-- opens xs into a per-element stream flow, doubles each element on
-- demand, and collects the results back into a stream
```

The motivating use case is commute / sequence — turning a
`stream<Option<X>>` into an `Option<stream<X>>` that short-circuits on
the first `None` without forcing the rest. But stream flows are
general machinery: once they exist, any flow operation that needs
single-pass or on-demand evaluation becomes expressible.

The runtime representation is the `Delayed`-cell stream from the
prototype. Each cell is `Delayed<SNil | SCons(value, Delayed<…>)>`,
forced one layer at a time and memoised by a three-state cache
(unforced / in-progress / done) so each layer computes at most once.
**Multi-output is essential**: one source can feed several consumers
that have pulled to different depths.

## The placement problem

This document is about *where in the stream structure each
computation lives* when a stream flow has more than one output. It is
the same problem the eager placement algorithm solved
(`placement-algorithm-notes.md`, built and retired), expressed
against a different structural medium.

Two pressures pull in opposite directions:

- **GC reachability.** A computation consumed only by output `Oᵢ`
  should live where only `Oᵢ` can reach it, so that dropping `Oᵢ`
  makes it collectable. Otherwise any one retained output pins the
  whole shared structure, leaking work no consumer can observe.
- **Deduplication.** A computation consumed by several outputs should
  live in a structure shared by exactly those outputs, so it runs once
  per source element rather than once per output.

A single physical placement decision does both jobs at once: "what
structure does this value live in?" fixes both who can reach it (GC)
and who shares its computation (dedup).

## Three shapes, and why Shape C is the baseline

Three obvious placements each take one job to an extreme.

**Shape A — one shared fold per source element producing an N-slot
record**, one slot per output. Maximum dedup, no GC: the record keeps
every computation reachable for as long as any single output holds
the chain.

**Shape B — an independent fold per output**, each its own
`zipStream` over the same source. Maximum GC, no dedup: values needed
by all outputs are recomputed once per output, and per-element
decisions run N times. (Adding an output is a self-contained
increment, which matches the eager-loop generalisation property
nicely.)

**Shape C — map-per-intermediate**: every node in the Expr graph
becomes its own memoised stream-derivation cell, chained from its
inputs. Maximum GC *and* maximum dedup. The price is one cell per Expr
node per stream layer per source element — O(graph-nodes ×
source-length × flow-depth) per pull. That is not a constant factor;
it is a real multiplication that grows with nested flows.

**Shape C is the committed baseline.** The explosion argument is not a
reason the shape is wrong — it is the reason the optimisation pass
below stays committed. Here is why the shape is right.

Of the three, Shape C is the only one semantically correct on both
axes. It was historically dismissed on that constant factor alone. But
the eager compile has since accepted exactly that factor: every node
compiles to a `__lazy__` binding, and a node depending on a
per-iteration value re-emits one lazy allocation per iteration inside
each consuming close's thunk (`lazy-compile-design.md`). One heap
object per node per element whose job is "compute at most once, on
demand" — which is precisely a Shape C cell. Shape C is the stream
transposition of the strategy the eager compile runs on purpose,
chosen for the same reason: the compiler decides nothing, and
correctness does not depend on an analysis.

That reframes the whole document. The consumer-set lattice is not
*the* stream compile; it is the **optimisation pass over** the stream
compile.

## What the baseline delivers for free

The baseline is not merely "the lattice minus the effort." One
asymmetry is worth recording. `lazy-compile-design.md` names a cost
of the simple eager model: per-iteration work is not shared across
sibling closes — each close's thunk iterates independently, and a
shared case-split's discriminator runs once per consuming thunk rather
than once total. At the per-iteration level that is Shape B's cost
profile, accepted because thunk-local re-emission is what keeps the
model simple.

Under Shape C that sharing comes back for free. Sibling closes pull
the same per-node memoised streams, so per-element work runs once no
matter how many closes consume it, at whatever pace each consumer
pulls. The stream representation delivers, through plain memoisation,
the cross-close sharing that eager flows gave up when placement was
retired. A multi-close-heavy program might reasonably prefer its flows
stream-kinded for this reason alone.

## The honest costs

Two, and they are what would eventually justify the lattice:

- **Allocation count.** Per source element the baseline allocates one
  cell per node; the lattice allocates one record per distinct
  consumer-set, and consumer-sets are typically far fewer than nodes
  (that observation is the heart of this document). Same asymptotic
  class as the eager compile's per-iteration lazies, but a bigger
  constant.
- **Retention.** An eager close's per-iteration lazies die when the
  block exits. Stream cells are memoised history: with multiple
  consumers, everything back to the slowest cursor stays live, and a
  retained head pins the whole prefix. Per-node cells make that
  history proportionally fatter than per-chain records would. This is
  a genuinely new cost axis relative to the eager compile.

Neither cost affects semantics — which is the point. They are exactly
the concerns the runtime-lazy decision explicitly deferred:
optimisation logic in the compiler was paying down debt the language
had not accumulated yet. Streams should not be held to a stricter
standard than the compile we already ship.

## The optimisation: the consumer-set lattice

For each computation, identify its **consumer set** — the subset of
its flow's outputs that depend on it. Place the computation in the
chain shared by exactly that set: not larger (GC), not smaller
(dedup). Distinct consumer-sets give distinct chains. The chain count
at a flow level scales with the number of *distinct* consumer-sets
there — not 2^|outputs|, not node-count. In practice it is small.

This generalises the eager placement principle ("place each
computation in the smallest region that includes all its consumers").
Eager regions were JS scopes, nested in a tree. Stream regions are
`Delayed` chains, which form a **lattice**: chain `{O₁, O₂}` and chain
`{O₁, O₃}` both derive from `{O₁, O₂, O₃}` but neither contains the
other.

### Single flow

For a single stream flow with N outputs, the lattice is the non-empty
subsets of `{O₁, …, Oₙ}`.

**Partition by tag.** Source is `stream<Either<A, B>>`; output 1 keeps
the A's, output 2 keeps the B's.

```
xs -> open stream -> split tag of A, B
  A: -~> join -~> collect => as
  B: -~> join -~> collect => bs
-- as = a stream of A payloads, bs = a stream of B payloads
```

Consumer-sets: decode tag/payload `{O₁, O₂}`; extract A `{O₁}`;
extract B `{O₂}`. Three chains: a shared chain producing the decoded
tag/payload record per source cell, plus each output's
filter-and-project chain.

**Shared intermediate.** Source is `stream<int>`; output 1 is
`(x+1)*2`, output 2 is `(x+1)*3`.

```
xs -> open stream -> incr -> | double -~> collect => a
| -> triple -~> collect => b
-- incr = x+1 is shared; a is the (x+1)*2 stream, b the (x+1)*3 stream
```

Consumer-sets: decode x `{O₁, O₂}`; `x+1` `{O₁, O₂}`; `(x+1)*2`
`{O₁}`; `(x+1)*3` `{O₂}`. Three distinct consumer-sets → three chains:
the shared `{O₁, O₂}` chain holds decoding and `x+1`; each per-output
chain holds its multiplier and forms the output stream.

Both examples have small chain counts. The pathological 2ⁿ case —
every subset having a distinct-consumer-set computation — does not
arise in typical diagrams. Most have a layer of shared intermediates
on top and a small number of per-output specialisations.

### Nested flows

With nested flows there is a real question of *whose* outputs the
lattice is over — the inner flow's or the outer's. The answer: **each
flow level uses its own outputs as the axes of its own lattice**, and
the partitioning is done independently at each level.

**Why not an outermost-only rule** (every computation's consumer-set
drawn from the outermost flow's outputs)? Because outer consumer-sets
can only *collapse* inner-flow partitions, never *refine* them — and
collapsing loses pull-granularity.

The clearest case. Outer has one output `O1`; inner has two outputs
`D` and `T`, both consumed by `O1`'s value subtree (a per-outer-element
conditional that sometimes pulls `D`, sometimes `T`, sometimes both).
By outermost-only, every inner computation has consumer-set `{O1}`, so
`decode m`, `m*2`, and `m*3` collapse into one chain; forcing it at any
inner element forces all three. If for a given outer element the
conditional only pulls `T`, the `m*2` that only fed `D` runs anyway —
wasted. By per-level: inner's lattice is over `{D, T}`, with `m*2 ∈
{D}`, `m*3 ∈ {T}`, `decode m ∈ {D, T}`. Forcing `T` forces inner's
`{T}` chain (`m*3`) and its parent `{D, T}` chain (`decode m`); `m*2`
is not forced.

The general claim: outer consumer-sets collapse inner partitions but
never refine them, so the correct algorithm uses each level's local
outputs as that level's lattice axes.

**First nested example.** Source is a stream of pairs `(a, b)`. Per
outer element an *inner* stream flow opens `a` and emits, per inner
element, `doubled = m*2` and `tripled = m*3` — two outputs `D`, `T`.
Outer has two outputs: `outer.O1` folds `inner.D`, `outer.O2` folds
`inner.T`.

- *Inner level*, axes `{D, T}`: `decode m` → `{D, T}`, `m*2` → `{D}`,
  `m*3` → `{T}`. Three inner chains. When `outer.O1` pulls `inner.D`
  for some outer element, that pull forces inner's `{D}` chain (`m*2`)
  and its parent `{D, T}` chain (`decode m`); `m*3` is not forced.
  GC: drop `outer.O1` and all the inner `{D}` chains become
  unreachable.
- *Outer level*, axes `{O1, O2}`: `decode (a, b)` → `{O1, O2}`;
  constructing the inner flow on `a` → `{O1, O2}` (needed if either
  outer output needs anything from inner); `inner.D` as an outer value
  → `{O1}`; `inner.T` as an outer value → `{O2}`; each output's fold →
  `{Oᵢ}`. Three outer chains.

Each level's lattice is structurally independent. Cross-level
structure shows up only in that *inner outputs are values at the outer
level* — their outer-level consumer-set fixes their outer-level chain
placement, separately from any inner-level partitioning.

**Shared inner output.** Now `inner.D` is consumed by *both*
`outer.O1` and `outer.O2`; `inner.T` only by `outer.O2`.

- *Inner level* is unchanged by what outer does — still `{D, T}`,
  `{D}`, `{T}`, three chains.
- *Outer level* changes: `inner.D` as an outer value is now `{O1, O2}`,
  `inner.T` is `{O2}`, `decode (a, b)` and inner-flow construction are
  `{O1, O2}`. Outer chains: `{O1, O2}` (decode, inner construction,
  `inner.D`'s stream), `{O2}` (`inner.T`'s stream + O2's fold), `{O1}`
  (O1's fold, reading `inner.D` from `{O1, O2}`).

GC works out: drop `O1` and `inner.D`'s stream stays reachable via the
`{O1, O2}` chain held by `O2` (so `m*2` keeps running, needed for O2's
use of D); drop `O2` and `inner.T`'s stream, outer's `{O2}` chain, and
inner's `{T}` chain all become unreachable, so `m*3` stops, while
`inner.D` stays reachable via O1 and `m*2` keeps running.

### The algorithm

In one pass over the Expr graph, per flow level, treating each level
like a standalone single-flow problem with *its own* outputs as the
lattice axes:

1. **Build the consumer DAG.** For each Expr node, record its
   value-port consumers — the same pre-pass the eager algorithm does.
2. **Identify flow levels.** Each stream flow defines a level; a
   computation's level is the deepest flow whose per-iteration value
   it varies with.
3. **Compute level-local consumer-sets.** For each level-L
   computation, trace consumers within L's own value subtree,
   terminating at L's outputs (its Closes). The consumer-set is the
   subset of L's outputs that reach it. *Do not* trace across flow
   boundaries — deeper flows are their own problem, and outer flows do
   not propagate down.
4. **Group by consumer-set.** Each group is a chain at L. Chain count
   = number of distinct consumer-sets, not 2^|outputs|.
5. **Emit the chains.** Each chain compiles to a `zipStream` over L's
   source; its atCons builds a record (named slots for the values
   computed at this chain) for the source cell. A sub-chain derives
   from its parent via `Delayed.flatMap`: pull the parent record at
   the same source cell, take the parent values it needs, compute its
   own additional slots. Forcing a sub-chain forces its parent
   (memoised, cost once per source cell).
6. **Outputs project from their chains.** Output `Oᵢ` reads the
   smallest chain whose consumer-set contains `Oᵢ` — a `Delayed.map`
   projection, or a small `zipStream` if `Oᵢ` has its own per-element
   computation.
7. **Cross-level integration.** Inner-flow outputs are values at the
   next-outer level, entering step 3 like any value with an outer
   consumer-set determined by what the outer outputs do with them.
   Inner's own chain structure was already decided at step 3 for the
   inner level.
8. **Multi-parent sub-chains are zipped** (see below).

### Chains derive, they do not nest

Partitioning is not recursive: a chain does not split into sub-chains
that split further. Each chain is a flat `zipStream` over the source,
and chains relate by *derivation*, not nesting. Chain X derives from
chain Y when X's atCons reads Y's records as input; both are their own
iterations. So chains form a lattice by consumer-set inclusion where
each node is a separate iteration, and "parenthood" means "X derives
from Y," not "X is contained in Y."

### Multi-parent zip

A sub-chain may have *more than one* incomparable parent. Sub-chain
`{O₁}` is a subset of both `{O₁, O₂}` and `{O₁, O₃}`, and neither of
those is a subset of the other. If `{O₁}`'s atCons uses values from
both, it reads both at each source cell — which is exactly a **zip**:
the two chains are independent iterations now (they have been split
off), so the sub-chain has to thread them back together cell-by-cell.
Mechanically, each iteration does `Delayed.flatMap` on chain A, then
inside that `Delayed.flatMap` on chain B at the same position, then
combines. The shared source plus the `Delayed` memo means source cells
are not recomputed, but each chain's layer allocation happens once per
source cell.

So the runtime needs a `zip` primitive on streams (or its equivalent
via `flatMap` and `zipStream`). Not hard, but a piece the partition
algorithm requires, worth calling out before implementation.

### Per-output vs per-element partitions

The stream case adds a source of partitioning the eager case lacked:
an output can decline to run simply by never being pulled. A value
used only by `Oᵢ` never runs if `Oᵢ` is never forced, regardless of
what any inner flow does. That is the per-output partition the lattice
optimises for.

Inner-flow conditionals — a stream filter, an option-style flow —
still mean some elements are not observed by some outputs, but that is
a *per-element* concern, handled at runtime by laziness (the cell is
not forced if the predicate does not fire). It does not change
compile-time chain structure; it just means the cell at depth K of an
output stream may correspond to a later source element than K. So
partitions split into two kinds:

- **Per-output (compile-time)**: which outputs care about this value
  at all → what chain it lives in.
- **Per-element (runtime)**: among the outputs that care, which
  elements trigger it → handled by `Delayed`-cell laziness, no
  compile-time assistance.

The algorithm handles only the first; the second is the runtime's job.

### Relation to the eager placement algorithm

The consumer pre-pass carries over identically. Backwards propagation
carries over with one structural difference: in the eager version the
lattice of consumer scopes was a tree (scope nesting), and propagation
was one global pass with a deepest-common-ancestor join.
In the stream version the per-level lattice is a powerset lattice, and
each level's propagation is local; across-level structure is handled
by treating inner outputs as ordinary values at the outer level.

The eager version's "don't sink past a loop" cap does not apply to
streams — sinking into a sub-chain does not multiply work, it just
changes reachability — and is replaced by the GC argument. If one
compile mode ever covers both, the principle generalises: for each
computation, find the most-specific region containing all its
level-local consumers, where a region is a JS scope (eager) or a
`Delayed` chain (stream) depending on the containing flow's kind.

## Deferred, not conditional

Why "committed" and not merely "revive when profiles demand it":
profiles may never demand it. Typical workloads may never notice the
constant factor, and under a benchmarks-only gate the lattice would
then never be built. But the naive output has a cost benchmarks do not
measure — it scares people.

The generated JS is read, not just run. Someone evaluating the
language writes what is conceptually a single pass over a list, looks
at the output, and sees five independent loops — one per close — with
the discriminator re-run in each. They do not file a performance bug.
They ask "how can this possibly scale?" and conclude the model is
naive before any benchmark gets a chance to argue otherwise. Output
that looks pathological is evidence against the language, at exactly
the moment trust is being decided.

This rhymes with the language's own philosophy: concreteness is a
derived view, and derived views are meant to be read
(`language-design-philosophy.md`); the compiled JS is the most
concrete view of all. A program whose most concrete view reads as
absurd undermines the claim that the abstractions above it are sound.

So the lattice — and the eager hybrid in
`placement-algorithm-notes.md` — should be built whether or not it
ever turns out to be computationally necessary. What stays deferred is
the sequencing, not the decision. Semantics first still holds:
optimisation logic in the compiler while the flow kinds are still
moving was exactly the debt the retirement paid off, and stream flows
should not be gated on placement landing. But the end state is
committed: one conceptual loop should compile to one loop.

### What survives into the baseline

Three pieces survive unchanged, and one subtlety becomes universal:

- **Level identification** (steps 2 and 7). Which source a node's
  per-element value varies with — the stream analog of the eager
  compile's `deeper` — is not an optimisation. Even one-cell-per-node
  must know which iteration drives each cell, and inner-flow outputs
  still enter the outer level as values.
- **Output construction.** Join, commute, and filter (the companion
  documents) were defined to be independent of chain partitioning:
  they see only a memoised pull interface, and attach to per-node
  chains exactly as they would to lattice chains.
- **The runtime primitives** (step 1) are the same either way.
- **The multi-parent zip** stops being a subtlety and becomes the
  universal case: under per-node chains, every node with two or more
  inputs reads its inputs' streams at the same source position. The
  `zip` primitive is required everywhere, not occasionally.

### Effect on the implementation order

Steps 1–3 are unchanged — already placement-free. Steps 4 and 5
(consumer-set bookkeeping, N outputs) drop off the critical path:
multi-output works on the baseline by construction, so those steps
become the first steps of the *optimisation pass* — committed either
way, taken once the semantics have settled rather than gated on
benchmarks. Step 6 (nested flows) stays, but what it validates shrinks
to level identification and cross-level integration rather than
per-level lattices.

## The skip mechanism and the three runtime moves

A filter collect produces fewer elements than its source has cells.
Does that per-element "skip" disturb the lattice? No — and the reason
is structural.

### Skip lives in output construction; chains never subset

Everything the placement machinery manipulates — lattice chains,
sub-chain derivation, the multi-parent zip, and equally the baseline's
per-node cells — is **source-position-aligned**: one cell per source
element, always. A non-firing element does not delete its cell from
any chain; the chain cell carries the non-firing *as a value* (a
partial value, set iff fired; `lazy-stream-join-design.md`), with
slots the runtime simply never forces. Subsetting happens in exactly
one place: the close's output construction (step 6's projection),
where a non-firing cell contributes no cell to the output stream.

Three consequences:

- **The lattice is untouched**, for a stronger reason than "the
  lattice is per-output-presence": the skip never enters chain
  structure at all. Filter — like join and commute — is per-close
  output construction, invisible to chain partitioning.
- **The multi-parent zip's alignment assumption is never violated.**
  Zipping incomparable parents reads both "at the same source cell,"
  sound because no chain ever subsets. The only depth-K-vs-source-K
  mismatch is between an *output stream* and the source — and nothing
  ever needs to align an output stream with anything. Outputs are
  endpoints.
- **The notation does not move the mechanism.** Whether spelled as a
  per-close stage or as a binary join node absorbing an option flow
  into a list/stream flow (`lazy-stream-join-design.md`), the runtime
  function is the same.

### The atCons expression: become-the-rest

The spurious-cell worry dissolves the same way the flatten's
intermediate stream-of-streams did: at a non-firing element the fold's
atCons does not emit a placeholder cell — it *becomes the rest of the
fold*.

```rescript
// Sketch, same conventions as the flatten in
// lazy-stream-join-design.md (synchronous, no tick()).
let skipAbsent = chain =>
  zipStream(chain, ready(SNil),
    (cell, rest) =>
      // rest: the fold over the tail, one Delayed layer deep
      switch firing(cell) {
      | Some(v) => ready(SCons(v, rest->Delayed.flatMap(s => s)))
      | None => rest->Delayed.flatMap(s => s) // become the rest
      })
// firing element -> emit a cons; non-firing -> continue as the tail's
// fold, so no cell for it ever exists, even transiently
```

The output stream's cells are exactly the firing elements'. And the
move is not new; it is one instance of a single primitive the stages
share — **a fold step may continue with any `Delayed` continuation,
not just a cons of its own making.** The whole stage inventory reduces
to three uses of that primitive:

- **Emit-and-continue** — the ordinary case: produce a cons, continue
  with the tail's fold.
- **Become-the-rest** — skip this element, continue as the tail's
  fold. Filter does this at a non-firing element (above); join does it
  at the end of an inner stream, where atNil becomes the rest of the
  flatten (`lazy-stream-join-design.md`).
- **Abandon-the-rest** — discard the tail entirely and become a
  terminal. Commute does this at a `None`, becoming the resolved
  `None` (`lazy-stream-commute-design.md`, "Effect on placement").

That the whole inventory reduces to one runtime move is some evidence
the stage decomposition sits at the right altitude — and it is
spelling-neutral: the former J/F spellings partition the same three
moves differently between names; neither needs a fourth.

### Two footguns

**Pull amplification is inherent; stack depth is not.** Pulling one
output cell across a run of K consecutive non-firing elements forces K
source cells — that is what filter means, not a defect. But naively it
also *nests* K become-the-rest redirects: forcing the head runs atCons
for cell 0, which returns the tail-fold's `flatMap`, whose force runs
atCons for cell 1, and so on. If `Delayed`'s force recurses through
`flatMap`, the run costs O(K) stack and a sparse filter over a long
source overflows. The prototype never saw this: `tick()`'s event-loop
integration returned to the scheduler between steps, so stripping it
for the synchronous variant (implementation step 1) is what *creates*
the hazard. The fix belongs in the primitive, not the stage: force
must follow `flatMap`/redirect chains **iteratively** — the standard
lazy-runtime indirection-following loop — so a redirect run is a loop,
not a recursion.

**Retention across a forced run.** After the run forces, each of the K
skipped positions' `Delayed` cells memoises the same resulting cons —
computed once, so correctness is fine — but a retained reference into
the run keeps O(K) indirection objects alive alongside the chain cells
they point through. This is the retention cost axis above (memoised
history back to the slowest cursor), with skip runs adding a constant
factor along the run, not a new class. The iterative force loop can
shrink it for free: **path-compress** each cell to the final result
while walking, a one-line addition worth making at the same time.

Both requirements land on implementation step 1.

## Open questions

1. **Self-referential or recursive streams.** Outside our current
   scope, but a stream-typed language grows these eventually. If we
   ever support them, consumer-set propagation needs a fixpoint
   computation instead of a single backwards pass.
2. **Empty consumer sets and dead code.** A computation reachable from
   no output should be dropped. The eager compile does not currently
   care; this is a good chance to handle it uniformly.
3. **Cost of the chain projection step.** Each output projects from a
   chain via `Delayed.flatMap` (and possibly nested projections via
   parent chains). With many chains and outputs the projection cost is
   real but smaller than map-per-intermediate. Worth benchmarking once
   we have running code.
4. **Unifying the two compile strategies.** We currently compile every
   binding as a lazy, no placement. Adding stream flows keeps that:
   stream flows get *no placement at all* (Shape C the baseline), with
   the lattice joining `placement-algorithm-notes.md` in the
   deferred-but-committed category. The larger arm — resurrecting the
   eager placement work and unifying both around one placement core —
   is a bigger lift than it looks: that algorithm was retired as
   premature and its placeholder machinery flagged as fragile.
5. **Single-consumer streams via native generators.** Stream flows
   whose chains are known at compile time to have exactly one consumer
   (no fanout, no multi-close on a parent chain) do not need the dedup
   machinery — they could compile to `function* …` generators instead
   of `Delayed`-cell linked lists: native syntax, JIT-friendly,
   smaller per-cell overhead. An optional optimisation once the general
   compile works: detect single-consumer chains at the lattice stage,
   emit a generator for those and `Delayed` cells for shared ones.
   Probably not worth the effort until benchmarks say per-cell
   overhead matters.

## Implementation order

Staged so we can validate at each step before proceeding. **Steps 1, 2 and 3
are implemented** — see `src/ARCHITECTURE.md` worklist item 10 for what
landed, including two things this plan expected to cost work and which
turned out to be free: multi-output (it works on the baseline by
construction) and level identification for a stream nested inside an
eager flow (the existing let-floating placement already does it). Step 3
cost no placement work either, exactly as
`lazy-stream-commute-design.md` predicted ("chain placement is
untouched"): the commute is output construction, so its emitter is the
step-2 fold with the option's guard as one more level and a different
assembled shape.

1. **Runtime primitives.** Port `Delayed`, `stream`, `zipStream`,
   `listToStream` to the compile target. Synchronous (no promise),
   same three-state cache shape as the prototype, minus the event-loop
   integration. Two requirements from the skip mechanism land here:
   force must follow `flatMap`/redirect chains iteratively (a long
   skip run is otherwise O(run) stack — the hazard `tick()` masked and
   the synchronous variant exposes), and the force loop should
   path-compress the cells it walks.
2. **Single-output stream flow.** One Close compiling to a `zipStream`
   over the source. No placement concerns yet. Verify with a simple
   stream-map test.
3. **Commute / sequence on a single-output stream.** The first real
   stream operation and the motivating feature; getting it working
   validates the runtime shape end-to-end. *Implemented.* It validated
   the shape in the way this plan hoped: the fold turned out to use
   become-the-rest at every firing (accumulating on the side) and
   abandon-the-rest at the first absence, never emit-and-continue — and
   that is also what keeps the walk a redirect chain the iterative force
   loop follows, so the step-1 requirements are what made the step-3
   emitter possible rather than merely safe.
4. **Two-output stream flow.** Introduce the consumer-set bookkeeping
   for two outputs. Verify chain count matches distinct consumer-set
   count on hand-picked examples, and GC behaves (drop one output, see
   memory free; drop the other, see remaining shared work stay
   reachable). *(This is the first step of the optimisation pass — off
   the critical path per the status header, committed either way.)*
5. **N-output single flow.** Generalise. Verify chain count scales
   with distinct consumer-sets, not 2ⁿ.
6. **Nested flows.** Implement and walk through the examples here; this
   validates level identification and cross-level integration. If they
   reveal the algorithm needs revision, revise this document before
   proceeding.

The point of the staged plan is to surface problems early — finding out
at step 6 that the algorithm needs rework is much cheaper than finding
out after.

## What this doesn't address

- **Eager–stream interaction.** Whether and how lists and streams
  bridge (list-to-stream, stream-to-list as language operations) is a
  separate design question and does not affect this algorithm. The
  placement analysis runs entirely inside a stream flow; eager-flow
  values appearing as inputs are just already-bound names to read.
- **Joining stream flows.** Tackled since:
  `lazy-stream-join-design.md` works join out as a flatten and
  concludes it does not affect this algorithm;
  `lazy-stream-commute-design.md` reaches the same conclusion for
  commute. Join has since been recast as a **binary flow operation**,
  under which "per-close output construction" reads as "the join nodes
  determine the structure the collect's output construction consumes";
  the placement-independence conclusion survives the correction.
- **Optimisation of the eager compile.** Preserved at
  `placement-algorithm-notes.md`; can come back when we want tighter
  JS for the eager fragment.
- **Iteration rails / loop-carried state.** When we add those, they
  need their own placement story.
- **Performance benchmarking.** Needed eventually, but not before
  something works.
