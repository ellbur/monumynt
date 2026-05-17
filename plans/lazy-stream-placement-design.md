# Placement for Lazy Stream Flows

## What this is for

We're going to add stream flows alongside the existing list flows.
The motivating use case is commute / sequence (`List<Option<X>>` →
`Option<List<X>>` short-circuiting), but stream flows are general
machinery — once they exist, other flow operations that need
single-pass / on-demand evaluation will be expressible too.

The runtime representation is the `Delayed`-cell stream from the
prototype: each cell is `Delayed<SNil | SCons(value, Delayed<…>)>`,
forced one layer at a time, memoised via the three-state cache.
Multi-output is essential — one source feeding multiple consumers
that may have pulled to different depths.

This document is about *where in the stream structure each
computation should live* when a stream flow has multiple outputs.
It turns out to be the same problem as the eager placement algorithm
we built and retired, just expressed against a different structural
medium.

## The pressure

For a stream flow with several outputs there are two pressures
pulling opposite directions:

- **GC reachability.** A computation that's only consumed by output
  `Oᵢ` should live in a structure reachable only from `Oᵢ`. When
  `Oᵢ` is dropped, that structure becomes unreachable and the
  computation can be GC'd. Otherwise any one retained output keeps
  the entire shared structure live, leaking memory for work no
  consumer can observe.

- **Deduplication.** A computation consumed by several outputs
  should live in a structure shared by exactly those outputs, so
  it's computed once per source element, not once per output. The
  alternative is recomputing the same value N times per source
  element, which is wasteful in proportion to fanout.

A single physical placement decision is doing both jobs at once:
"in what structure does this value live?" determines both who can
reach it (GC) and who shares its computation (dedup).

## The naive corners

Three obvious-but-wrong shapes each take one of the two jobs to an
extreme:

**Shape A — shared atCons returning an N-element record.** One
fold per source element produces a record with named slots, one per
output. Compute every output's values at every source element.

- Max dedup; no GC. The record keeps every computation reachable
  for as long as any single output retains the chain.

**Shape B — independent fold per output, each its own `zipStream`
over the same source.** Adding an output is a self-contained increment
(matches the eager-loop generalisation property nicely).

- Max GC; no dedup. Values needed by all outputs are recomputed once
  per output. Per-element decision functions evaluated N times.

**Shape C — map-per-intermediate.** Every node in the Expr graph
becomes its own stream-derivation cell, chained from its inputs.

- Max GC *and* max dedup, paid for by per-source-element allocation
  of one cell per Expr node per stream layer. The structural overhead
  multiplies with nested flows, growing as O(graph-nodes ×
  source-length × flow-depth) per pull. This isn't a constant factor;
  it's a real explosion.

None of the three is the answer alone.

## The principle

For each computation, identify its *consumer set* — the set of
its containing flow's outputs that depend on it. Place the
computation in the chain shared by exactly that set: not larger
(GC reachability), not smaller (dedup).

Distinct consumer-sets give distinct chains. The chain count at a
flow level scales with the number of *distinct* consumer-sets at
that level — not 2|outputs|, not graph-node-count. In practice
it's small.

This generalises the eager placement principle: "place each
computation in the smallest region that includes all its
consumers." For eager flows the regions were JS scopes (nested
in a tree); for stream flows they're Delayed chains (which form
a lattice — chain `{O₁, O₂}` and chain `{O₁, O₃}` both derive
from chain `{O₁, O₂, O₃}` but neither contains the other).

A wrinkle the eager case doesn't have: with nested stream flows,
each flow level is its own independent placement problem with
its own outputs as lattice axes. Outer-level consumer-sets don't
substitute for inner-level analysis (they'd only ever collapse
inner partitions, losing pull-granularity). See "Nested flows"
below.

## Single-flow case

For a single stream flow with N outputs, the consumer-set lattice is
the lattice of non-empty subsets of {O₁, …, Oₙ}. Two examples:

**Partition by tag.** Source is `stream<Either<A, B>>`. Output 1
filters to A's; output 2 filters to B's.

- Decode tag/payload: consumer-set {O₁, O₂}.
- Extract A: consumer-set {O₁}.
- Extract B: consumer-set {O₂}.

Three chains, one per consumer-set. The shared chain produces a
record per source cell containing the decoded tag/payload; O₁'s chain
filters and projects A's; O₂'s does the same for B's.

**Multi-output with a shared intermediate.** Source is `stream<int>`.
Output 1 is `(x+1)*2`. Output 2 is `(x+1)*3`.

- Decode x: {O₁, O₂}.
- x+1: {O₁, O₂}.
- (x+1)*2: {O₁}.
- (x+1)*3: {O₂}.

Three distinct consumer-sets, so three chains. The shared `{O₁, O₂}`
chain holds decoding and `x+1`; each per-output chain holds the
multiplier and forms the actual output stream.

Both examples have small chain counts. The pathological 2ⁿ case
(where every subset has a distinct-consumer-set computation) doesn't
arise in typical diagrams — most diagrams have a layer of shared
intermediates at the top and a small number of per-output
specialisations.

## Nested flows

This is the case that needed careful thought. With nested flows
there's a real question of *whose* outputs the lattice is over —
the inner flow's, or the outer flow's. The right answer turns out
to be **each flow level uses its own outputs as the axes of its
own lattice**, and the partitioning is done independently at each
level.

I initially wrote up an outermost-only rule (every computation's
consumer-set is among the outermost flow's outputs). That's
wrong: outermost consumer-sets can only *collapse* inner-flow
partitions, never refine them — and the collapsing loses
pull-granularity at runtime.

### Why outermost-only fails

The clearest case. Outer has one output `O1`; inner has two outputs
`D` and `T`, both consumed by `O1`'s value subtree (say, by a
per-outer-element conditional: sometimes the body pulls `D`,
sometimes `T`, sometimes both).

By outermost-only every inner computation has consumer-set `{O1}`,
so `decode m`, `m*2`, and `m*3` all collapse into one chain.
Forcing that chain at any inner-element forces all three
computations. If for a given outer element the conditional only
pulls `T`, the `m*2` that only fed `D` runs anyway — wasted.

By per-level (inside-out): inner's lattice is over `{D, T}`.
`m*2` ∈ `{D}`, `m*3` ∈ `{T}`, `decode m` ∈ `{D, T}`. Forcing `T`
forces inner's `{T}` chain (`m*3`) and its parent `{D, T}` chain
(`decode m`). `m*2` (in inner's `{D}` chain) is not forced.

The general claim: outer consumer-sets can collapse inner
partitions but never refine them. Collapsing loses pull-
granularity, so the correct algorithm uses each level's local
outputs as that level's lattice axes.

### First nested example

Source is a stream of pairs `(a: list, b: list)`.

- Outer flow opens the source.
- Per outer element, an *inner* stream flow opens `a` and emits per
  inner element two values: `doubled = m*2` and `tripled = m*3`.
  Inner has two outputs (`D`, `T`).
- Outer has two outputs:
  - `outer.O1`: per outer element, fold `inner.D` into a list.
  - `outer.O2`: per outer element, fold `inner.T` into a list.

**Inner level** (per outer-element instance, with its own
inner-source `a`). Lattice axes: `{D, T}`.

- `decode m`: consumed by both `D` and `T` → `{D, T}`.
- `m*2`: consumed by `D` only → `{D}`.
- `m*3`: → `{T}`.

Three inner chains. When `outer.O1` pulls `inner.D` for some outer
element, that pull forces inner's `{D}` chain (m*2) and its
parent `{D, T}` chain (decode m). `m*3` (in `{T}`) is not forced.
GC: when `outer.O1` is dropped, all the inner `{D}` chains across
outer elements become unreachable.

**Outer level**. Lattice axes: `{O1, O2}`.

- `decode (a, b)`: consumed by everything downstream that needs
  either `a` or `b` → `{O1, O2}`.
- "Construct the inner flow object on `a`": needed if either O1
  (which uses inner.D) or O2 (which uses inner.T) needs anything
  from inner → `{O1, O2}`.
- The inner.D output stream (as a value at outer level): `{O1}`.
- The inner.T output stream: `{O2}`.
- Each outer output's "fold into list" computation: `{Oᵢ}` for
  its own output.

So outer has three chains: `{O1, O2}` (shared decode + inner
construction), `{O1}` (project inner.D, fold), `{O2}` (project
inner.T, fold).

Notice each level's lattice is structurally independent. Inner's
chains are over inner's outputs; outer's chains are over outer's.
Cross-level structure manifests in that *inner outputs are values
at outer level* — their outer-level consumer-set determines their
outer-level chain placement, separately from any inner-level
partitioning.

### Shared inner output

Variation: `inner.D` is consumed by *both* `outer.O1` and
`outer.O2`; `inner.T` is only consumed by `outer.O2`.

**Inner level** is unchanged by what outer does. Inner has two
outputs; computations are partitioned by inner-cs over them:

- `decode m`: `{D, T}`.
- `m*2`: `{D}`.
- `m*3`: `{T}`.

Still three inner chains. When `outer.O1` pulls `inner.D`, it
forces inner's `{D}` and `{D, T}` chains. `m*3` doesn't run for
that pull. When `outer.O2` pulls both `inner.D` and `inner.T`,
all three chains force.

**Outer level** changes. The inner outputs have different outer-cs
than before:

- inner.D as an outer-level value: `{O1, O2}` (consumed by both).
- inner.T as an outer-level value: `{O2}`.
- decode (a, b): `{O1, O2}`.
- inner-flow construction: `{O1, O2}`.

Outer chains:
- `{O1, O2}`: decode (a, b), inner-flow construction, and
  inner.D's stream (an outer value with outer-cs `{O1, O2}`).
- `{O2}`: inner.T's stream and outer.O2's per-element fold logic.
- `{O1}`: outer.O1's per-element fold logic, which pulls
  inner.D from the `{O1, O2}` chain.

GC works correctly: drop `O1`, inner.D's stream still reachable
via outer's `{O1, O2}` chain held by `O2`; `m*2` keeps running
(it's needed for O2's use of D). Drop `O2`, inner.T's stream
unreachable, outer's `{O2}` chain unreachable, inner's `{T}` chain
unreachable, `m*3` stops; inner.D still reachable via O1, so
`m*2` keeps running.

### Algorithm

Per flow level, treat that level like a standalone single-flow
problem using *its own* outputs as the consumer-set axes:

1. For each computation at level L, determine its consumer-set —
   the subset of L's *own* outputs that depend on it. Trace
   transitively through L's own value subtree (without crossing
   into deeper flows — those are their own problem; without
   propagating up into outer flows either).
2. Group level-L computations by consumer-set; each group is a
   chain at level L.

Cross-level relationship: an inner flow's outputs are themselves
values at the next-outer level. They participate in the outer
level's lattice analysis with their outer-cs determined by what
the outer level does with them — but inner's own chain structure
is determined entirely by inner's own outputs.

The placement at every level is local. The lattice at every level
is over local outputs.

## Outputs and flows as consumers

In the eager case, every output executed unconditionally; the
partitions that mattered for placement came from *inner flows* —
case-split alts and option some-bodies that might not run. A value
used only in alt A could sink into alt A, computed only on
iterations where alt A fired.

In the stream case there's a new source of partitioning: an output
can choose not to execute, simply by never being pulled. A value used
only by output `Oᵢ` never runs if `Oᵢ` is never forced, regardless
of what any inner flow does. This is the per-output partition the
placement algorithm is now optimising for.

Inner flow conditionals still contribute partitions in the eager
sense — a stream filter or option-style flow means some elements
aren't observed by some outputs. But this is a *per-element* concern,
handled at runtime by lazy evaluation (the cell isn't forced if the
predicate doesn't fire). It doesn't change the compile-time chain
structure; it just means the cell at depth K of the output's chain
may correspond to a later source element than K.

So in the stream world, partitions split into two kinds:

- **Per-output (compile-time)**: which outputs care about this value
  at all? Determines what chain it lives in.
- **Per-element (runtime)**: for outputs that do care in principle,
  which elements actually trigger the computation? Handled by the
  Delayed-cell laziness without compile-time assistance.

The algorithm only needs to worry about the first. The second is the
runtime's job.

## Chain structure: a lattice, not a hierarchy of sub-partitions

It's tempting to imagine partitioning as recursive — that a chain
might split into sub-chains, which split into sub-sub-chains, etc.
That's not what happens. Each chain is a flat sequence of cells
(its own `zipStream` over the source), and chains relate to each
other by *derivation*, not nesting. Chain X derives from chain Y
when X's atCons reads Y's records as input; both X and Y are
their own iterations.

So chains form a lattice (by consumer-set inclusion) where each
node is a separate iteration, and "parenthood" in the lattice
means "X derives from Y" — not "X is contained in Y."

## When chains need to zip: multiple non-comparable parents

A subtlety: a sub-chain may have *more than one* incomparable
parent chain it needs to read from.

Sub-chain `{O₁}` is a subset of any chain whose consumer-set
includes O₁ — e.g. both `{O₁, O₂}` and `{O₁, O₃}`. Neither of
those is a subset of the other, so neither is a "more specific
parent" of the other. If `{O₁}`'s atCons happens to use values
from both, it has to read both at each source cell.

Reading two unrelated chains at the same source cell is exactly
a *zip* operation — the streams are independent iterations now
(they've been split off into separate chains), so even though
they were originally driven by the same source iteration, the
sub-chain has to thread them back together cell-by-cell.

Mechanically: each iteration of the sub-chain's atCons does
`Delayed.flatMap` on chain A, then inside that, `Delayed.flatMap`
on chain B at the same position, then combines. The shared source
plus the Delayed memo means the source cells aren't recomputed,
but the *chain layer* allocations for A and B happen — once each
per source cell, since both chains are memoised too.

So the runtime needs a `zip` primitive on streams (or its
equivalent, expressed via `flatMap` and `zipStream`). It's not
hard, but it's a piece of the runtime the partition algorithm
requires, and worth calling out before implementation.

## Algorithm sketch

The placement is per flow level, with each level locally
independent of the others. In one pass over the Expr graph:

1. **Build the consumer DAG.** For each Expr node, record its
   value-port consumers — same pre-pass the eager algorithm
   already does.

2. **Identify flow levels.** Each stream flow defines a level.
   A computation's level is the deepest flow whose per-iteration
   value it varies with.

3. **For each flow level, compute level-local consumer-sets.**
   The axes for level L's lattice are L's own outputs (its Closes).
   For each level-L computation, trace consumers within L's own
   value subtree, terminating at L's outputs. The consumer-set is
   the subset of L's outputs that reach the computation.
   *Don't* trace across flow boundaries — that level's lattice is
   local.

4. **Group level-L computations by consumer-set.** Each group is
   a chain at level L. Chain count = number of distinct
   consumer-sets at L, not 2|outputs|.

5. **Emit the chains.** Each chain compiles to a `zipStream` over
   L's source. The atCons builds a record (object with named slots
   for each value computed at this chain) for the source cell.
   Sub-chains (chains whose consumer-set is a proper subset of
   another's) derive from their parent via `Delayed.flatMap`: the
   sub-chain's atCons pulls the parent record from the parent
   chain at the same source cell, takes the parent values it
   needs, and computes its own additional slot values. Forcing
   a sub-chain forces its parent (memoised, so cost once per
   source cell).

6. **Outputs project from their chains.** Output `Oᵢ` at level L
   emits its stream by reading from the chain whose consumer-set
   is the smallest containing `Oᵢ` — that chain has the slots
   `Oᵢ` needs (transitively, via sub-chain derivation from
   parents). The output is a `Delayed.map` projection from the
   chain's records to `Oᵢ`'s actual emitted value type, or a
   small `zipStream` if `Oᵢ` has its own additional per-element
   computation.

7. **Cross-level integration.** Inner-flow outputs are values at
   the next-outer level. They participate in the outer level's
   lattice analysis (step 3) like any other value, with their
   outer consumer-set determined by what outer outputs use them.
   The inner flow's own chain structure was already decided at
   step 3 for the inner level.

8. **Sub-chains with multiple parents are zipped.** When a sub-
   chain X derives from incomparable parents A and B (each a
   superset of X's consumer-set but neither a subset of the
   other), X's atCons reads both A and B at the same source cell
   — a zip-style combination.

## Relation to the eager placement algorithm

The consumer pre-pass carries over identically. The backwards
propagation of consumer info also carries over, but with one
structural difference: in the eager version, the lattice of
consumer scopes was a tree (scope nesting), and propagation was
SCA-shaped — one global pass with a "deepest common ancestor"
join. In the stream version, the per-level lattice is a powerset
lattice (set-of-outputs), and each level's propagation is local.
Across-level structure is handled by treating inner outputs as
values at the outer level (where they re-enter the outer level's
lattice analysis as ordinary values).

The eager version's "don't sink past a loop" cap doesn't apply to
streams — sinking into a sub-chain doesn't multiply work, it just
changes reachability — and is replaced by the GC argument the
stream case needs.

If we ever want one compile mode covering both, the principle
generalises to: for each computation, find the most-specific
region that contains all its level-local consumers, where a
region is a JS scope (eager) or a Delayed chain (stream)
depending on the containing flow's kind. The bookkeeping
differs in shape but not in spirit.

## Open questions

1. **Filter closes and per-element subsetting.** A filter close
   produces fewer elements than its source's input — the output
   chain's "depth K" doesn't correspond to source depth K. I'm
   fairly sure this doesn't affect the consumer-set lattice (the
   lattice is per-output-presence, not per-element) but the per-
   element "skip" mechanism may need to be expressed carefully in
   the atCons so the chain advances correctly without producing a
   spurious cell.

2. **Self-referential or recursive streams.** Outside our current
   scope, but a stream-typed language grows these eventually. If
   we ever support them, the consumer-set propagation needs a
   fixpoint computation instead of a single backwards pass.

3. **Empty consumer sets and dead code.** A computation reachable
   from no output should be dropped. The eager compile doesn't
   currently care; this is a good chance to handle it uniformly.

4. **Cost of the chain projection step.** Each output projects
   from a chain via `Delayed.flatMap` (and possibly nested
   projections via parent chains). With many chains and many
   outputs the projection cost is real but smaller than
   map-per-intermediate. Worth benchmarking once we have running
   code.

5. **Two compile strategies under one roof.** We currently compile
   every binding as a lazy (no placement). Adding stream flows with
   placement gives us two compile strategies in the codebase. Two
   paths forward: stream flows get their own placement-aware
   compile while non-stream stays simple-lazy (smaller step); or
   we unify both around the same placement core and resurrect the
   eager placement work too. I lean toward the smaller step first
   — get stream placement working, then decide whether unification
   pays for itself.

## Implementation order

Staged so we can validate at each step before proceeding:

1. **Runtime primitives.** Port `Delayed`, `stream`, `zipStream`,
   `listToStream` to the compile target. Synchronous (no promise);
   same three-state cache shape as the prototype, minus the
   event-loop integration.

2. **Single-output stream flow.** Get a stream flow with one Close
   compiling correctly to a `zipStream` over the source. No
   placement concerns yet. Verify with a simple stream-map test.

3. **Commute / sequence on a single-output stream.** Implement
   commute as the first real stream operation. This is the
   motivating feature; getting it working validates the runtime
   shape end-to-end.

4. **Two-output stream flow.** Introduce the consumer-set
   bookkeeping for two outputs. Verify chain count matches
   distinct consumer-set count on hand-picked examples, and that
   GC behaves as expected on a microbenchmark (drop one output,
   see memory free; drop the other, see remaining shared work
   stay reachable).

5. **N-output single flow.** Generalise. Verify chain count scales
   with distinct consumer-sets, not 2ⁿ.

6. **Nested flows.** Implement and walk through the examples in
   this doc. If the worked examples reveal the algorithm needs
   revision, revise here before proceeding.

If at any step the design needs revision, revise this document
before continuing. The point of the staged plan is to surface
problems early — finding out at step 6 that the algorithm needs
rework is much cheaper than finding out it after.

## What this doesn't address

- **Eager-stream interaction.** Whether and how lists and streams
  bridge (list-to-stream, stream-to-list as language operations)
  is a separate design question and doesn't affect this
  algorithm. The placement analysis runs entirely inside a stream
  flow; eager-flow values appearing as inputs to a stream flow are
  just already-bound names to read.

- **Joining stream flows.** What "join" means for streams isn't
  obvious — for lists it was just "lift the output up a level";
  for streams it'd have to be redefined. We haven't tackled it,
  and the placement algorithm doesn't depend on it. If we add it
  later it may affect the algorithm.

- **Optimisation of the eager compile.** The placement algorithm
  for eager flows is preserved at `plans/placement-algorithm-notes.md`
  and can come back if/when we want tighter JS for the eager fragment.

- **The interaction with iteration rails / loop-carried state.**
  When we add those, they need their own placement story.

- **Performance benchmarking.** We need this eventually, but not
  before something works.
