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

> *(2026-07-06: two per-element faces are conflated here.
> Computations that don't run for a non-firing element are
> laziness proper — unforced slots in a cell that exists, as this
> paragraph says. An element contributing *no output cell at all*
> is the skip, which is not an unforced cell but a redirect in
> the close's output construction; chains themselves never
> subset, so "the output's chain" in the last sentence should
> read "the output stream". Worked out in "The skip mechanism"
> below.)*

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

## The baseline, revisited (2026-07-06)

> Postscript. Open question 5 below records that the eager compile
> is now runtime-lazy with no placement, and asks how two compile
> strategies should coexist. This section runs the reasoning that
> retired the eager placement algorithm — semantics first,
> optimisation logic deferred until the language accumulates the
> debt — against *this* algorithm, and finds it lands the same
> way. The semantics-first baseline for streams turns out to be
> something this document already named, and dismissed one
> paragraph later.

### Shape C is the runtime-lazy compile, transposed to streams

Of the three naive corners, Shape C (map-per-intermediate: every
Expr node its own memoised stream derivation) is the only one that
is semantically right on both axes — the analysis above grants it
max GC *and* max dedup — and it was rejected purely on constant
factors: one cell per Expr node per source element.

But the eager compile has since accepted exactly that constant
factor. Every node compiles to a `__lazy__` binding, and a node
that depends on a per-iteration value re-emits one lazy allocation
per iteration inside each consuming close's thunk
(`lazy-compile-design.md`). Per node, per element, one heap object
whose job is "compute at most once, on demand" — which is
precisely what a Shape C cell is. Shape C is not a naive corner to
be engineered past before shipping; it is the stream transposition
of the strategy we now run on purpose, chosen for the same reason:
the compiler decides nothing, and correctness does not depend on
an analysis.

That reframes this document. The consumer-set lattice is not *the*
stream compile; it is the optimisation pass over the stream
compile — the same category `placement-algorithm-notes.md` now
occupies for eager flows. Both documents then have the same shape:
a principled compile-time analysis, deferred but committed
("Deferred, not conditional" below), sitting above a
dumb-but-correct lazy baseline.

### What the baseline gives that the eager compile doesn't

One asymmetry worth recording, because it means the baseline is
not merely "the lattice minus the effort." `lazy-compile-design.md`
names the cost of the simple eager model: per-iteration work is
not shared across sibling closes — each close's thunk iterates
independently, and a shared case-split's discriminator runs once
per consuming thunk rather than once total. At the per-iteration
level that is Shape B's cost profile, accepted because thunk-local
re-emission is what keeps the model simple.

Under Shape C the sharing comes back for free. Sibling closes pull
the same per-node memoised streams, so per-element work runs once
regardless of how many closes consume it, at whatever pace each
consumer pulls. The stream representation delivers, through plain
memoisation, the cross-close sharing that eager flows gave up when
placement was retired. A multi-close-heavy program might
reasonably prefer its flows stream-kinded for this reason alone.

### What does not dissolve into the baseline

Three pieces of this document survive unchanged, and one subtlety
becomes ubiquitous rather than special:

- **Level identification** (algorithm steps 2 and 7). Which source
  a node's per-element value varies with — the stream analog of
  the eager compile's `deeper` — is not an optimisation. Even
  one-cell-per-node has to know which iteration drives each cell,
  and inner-flow outputs still enter the outer level as values.
  This is the part of the algorithm the baseline keeps.
- **Output construction.** Join, commute, filter (the companion
  documents) were already defined to be independent of chain
  partitioning — they see only a memoised pull interface. They
  attach to per-node chains exactly as they would to lattice
  chains; nothing in either companion document assumed the lattice
  beyond that interface.
- **The runtime primitives** (implementation order step 1) are the
  same either way.
- **The multi-parent zip** stops being a subtlety and becomes the
  universal case: under per-node chains, every node with two or
  more inputs reads its inputs' streams at the same source
  position. The `zip` primitive this document calls out is still
  required — everywhere, not occasionally.

### The honest costs

Two, and they are what would eventually justify the lattice:

- **Allocation count.** Per source element, the baseline allocates
  one cell per node; the lattice allocates one record per distinct
  consumer-set, and consumer-sets are typically far fewer than
  nodes (that observation is the heart of this document). Same
  asymptotic class as the eager compile's per-iteration lazies,
  but a bigger constant.
- **Retention.** An eager close's per-iteration lazies die when
  the iteration's block exits. Stream cells are memoised history:
  with multiple consumers, everything back to the slowest cursor
  stays live, and a retained head pins the whole prefix. Per-node
  cells make that history proportionally fatter than per-chain
  records would. This is a genuinely new cost axis relative to the
  eager compile — the one place where "the same constant factor we
  already accepted" understates.

Neither cost affects semantics. Which is the point: they are
exactly the kind of concern the runtime-lazy decision explicitly
deferred ("optimisation logic in the compiler was paying down debt
the language hadn't accumulated yet"), and streams shouldn't be
held to a stricter standard than the compile we already ship.

### Deferred, not conditional

The framing so far — an optimisation to revive "when profiles
demand it" — is too weak, and it's worth recording why (this came
out of pushback on the first draft of this postscript): profiles
may never demand it. Typical workloads may never notice the
constant factor, and under a benchmarks-only gate the lattice
would then never be built. But the naive output has a cost
benchmarks don't measure — it scares people.

The generated JS is read, not just run. Someone evaluating the
language writes what is conceptually a single pass over a list,
looks at the output, and sees five independent loops — one per
close — with the discriminator re-run in each. They do not file a
performance bug. They ask "how can this possibly scale?" and
conclude the model is naive, before any benchmark gets a chance
to argue otherwise. The output is evidence about the language,
and output that looks pathological is evidence against it, at
exactly the moment trust is being decided.

This rhymes with the language's own philosophy: concreteness is a
derived view, and derived views are meant to be read
(`language-design-philosophy.md`). The compiled JS is the most
concrete view of all. A program whose most concrete view reads as
absurd undermines the claim that the abstractions above it are
sound.

So: the lattice — and the eager hybrid in
`placement-algorithm-notes.md` — should be done, whether or not
it ever turns out to be necessary from a computational
standpoint. What stays deferred is the sequencing, not the
decision. Semantics first still holds — optimisation logic in the
compiler while the flow kinds are still moving was exactly the
debt the retirement paid off, and stream flows shouldn't be gated
on placement landing. But the end state is committed: one
conceptual loop should compile to one loop.

### Effect on the implementation order

Steps 1–3 are unchanged — they were already placement-free. Steps
4 and 5 (consumer-set bookkeeping, N outputs) drop off the
critical path: multi-output works on the baseline by construction,
so those steps become the first steps of the *optimisation pass* —
committed either way ("Deferred, not conditional" above), taken
once the semantics have settled rather than gated on benchmarks.
Step 6 (nested flows) stays, but what it validates shrinks to
level identification and cross-level integration rather than
per-level lattices.

## The skip mechanism (taking up open question 1) (2026-07-06)

> Open question 1 below worried that a filter close — one that
> produces fewer elements than its source has cells — might need
> its per-element "skip" expressed carefully in the atCons to
> advance correctly without emitting a spurious cell, and guessed
> that the consumer-set lattice is unaffected. The guess is right,
> and the reason it is right is worth pinning down, because the
> skip has since become load-bearing:
> `lazy-stream-join-design.md`'s "Join at an option level" shows
> that whichever spelling wins its open choice — join crosses
> levels (J) or `Filtered` as its own stage (F) — this mechanism
> is needed unchanged. This section fixes where the skip lives,
> gives the atCons expression, and records the two real footguns
> the expression must survive. It does not touch the J/F choice.

### Skip lives in output construction; chains never subset

Everything the placement machinery manipulates — lattice chains,
sub-chain derivation, the multi-parent zip, and equally the
baseline's per-node cells ("The baseline, revisited" above) — is
**source-position-aligned**: one cell per source element, always.
A non-firing element does not delete its cell from any chain; the
chain cell carries the non-firing *as a value* (the join doc's
partial value — set iff fired), with slots the runtime simply
never forces. Subsetting happens in exactly one place: the
close's output construction (the projection of step 6), where a
non-firing cell contributes no cell to the output stream.

Three things follow:

- **The lattice is untouched**, as the question guessed, and for
  a stronger reason than "the lattice is per-output-presence":
  the skip never enters chain structure at all. Filter — like
  join and commute in the companion documents — is per-close
  output construction, invisible to chain partitioning.
- **The multi-parent zip's alignment assumption is never
  violated.** Zipping incomparable parents reads both "at the
  same source cell"; that is sound because no chain ever subsets.
  The only depth-K-vs-source-K mismatch is between an *output
  stream* and the source — and nothing ever needs to align an
  output stream with anything. Outputs are endpoints.
- **The spelling choice doesn't move the mechanism.** Under J the
  skip sits inside a joined close's output construction; under F
  it is the `Filtered` stage's. Same runtime function either way.

### The atCons expression: become the rest

The spurious-cell worry dissolves the same way the flatten's
intermediate stream-of-streams did: at a non-firing element, the
fold's atCons doesn't emit a placeholder cell — it *becomes the
rest of the fold*.

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
```

No spurious cell exists even transiently — the output stream's
cells are exactly the firing elements'. And the move is not new;
it is the third instance of one primitive the stages already use:
a fold step may continue with *any* Delayed continuation, not
just a cons of its own making.

- **Join** redirects at the end of an inner stream: atNil becomes
  the rest of the flatten (`lazy-stream-join-design.md`).
- **Filter** redirects at a non-firing element: atCons becomes
  the rest of the fold (above).
- **Commute** redirects at a None to a terminal: atCons abandons
  the rest entirely and becomes the resolved `None`
  (`lazy-stream-commute-design.md`, "Effect on placement").

Emit-and-continue, become-the-rest, abandon-the-rest. That the
whole stage inventory reduces to one runtime move is some
evidence the stage decomposition sits at the right altitude — and
it is spelling-neutral evidence: J and F partition the same three
moves differently between names; neither needs a fourth.

### Two footguns

**Pull amplification is inherent; stack depth is not.** Pulling
one output cell across a run of K consecutive non-firing elements
forces K source cells — that is what filter means, not a defect.
But naively it also *nests* K become-the-rest redirects: forcing
the head runs atCons for cell 0, which returns the tail-fold's
flatMap, whose force runs atCons for cell 1, and so on. If
`Delayed`'s force recurses through flatMap, the run costs O(K)
stack, and a sparse filter over a long source overflows. The
prototype never saw this: `tick()`'s event-loop integration
returned to the scheduler between steps, so stripping it for the
synchronous variant (implementation-order step 1) is what
*creates* the hazard. The fix belongs in the primitive, not the
stage: force must follow flatMap/redirect chains iteratively —
the standard lazy-runtime indirection-following loop — so a
redirect run is a loop, not a recursion. Recorded as a
requirement on step 1 below.

**Retention across a forced run.** After the run forces, each of
the K skipped positions' Delayed cells memoises the same
resulting cons — computed once, so correctness is fine — but a
retained reference into the run keeps O(K) indirection objects
alive alongside the chain cells they point through. This is the
cost axis "The honest costs" already records (memoised history
retained back to the slowest cursor), with skip runs adding a
constant factor along the run, not a new class. The iterative
force loop can shrink it for free: snap each followed cell to the
final result while walking (path compression), a one-line
addition worth making at the same time.

### What this settles

The lattice is unaffected, for the structural reason above; the
careful atCons expression is the flatten's own become-the-rest
move applied at a non-firing element; and the real risks live in
the `Delayed` primitive (iterative force, path compression), not
in any stage. What stays open is exactly what was open before:
which language construct *owns* the skip — the J/F spelling
choice — on which this section is deliberately silent, because
both spellings compile to this mechanism.

## Open questions

1. **Filter closes and per-element subsetting.** ~~A filter close
   produces fewer elements than its source's input — the output
   chain's "depth K" doesn't correspond to source depth K. I'm
   fairly sure this doesn't affect the consumer-set lattice (the
   lattice is per-output-presence, not per-element) but the per-
   element "skip" mechanism may need to be expressed carefully in
   the atCons so the chain advances correctly without producing a
   spurious cell.~~ **Taken up** — see "The skip mechanism"
   above. The lattice is indeed unaffected, for a stronger reason
   than the parenthetical guessed: the skip lives entirely in
   per-close output construction and chains never subset, so no
   chain's depth K ever diverges from source depth K. The careful
   atCons expression is become-the-rest (the flatten's own trick
   at atNil, applied at a non-firing atCons), with two
   requirements pushed down into the `Delayed` primitive:
   iterative force (long skip runs must not recurse) and
   path compression while forcing.

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

   *Update (2026-07-06):* "The baseline, revisited" above argues
   the smaller step is smaller than this question assumed: not
   "stream flows get their own placement-aware compile" but
   "stream flows get no placement at all" — Shape C as the
   baseline, with the lattice joining
   `placement-algorithm-notes.md` in the deferred-but-committed
   optimisation category ("Deferred, not conditional" above).
   Also note the "resurrect the eager placement work"
   arm now reads differently than when this was written: that
   algorithm was retired as premature and its placeholder
   machinery flagged as fragile, so unification is a bigger lift
   than this question priced in.

6. **Single-consumer streams via native generators.** Stream flows
   whose chains are known at compile time to have exactly one
   consumer (no fanout, no multi-close on a parent chain) don't
   need the dedup machinery — they could compile to `function* …`
   generators instead of Delayed-cell linked lists. Native syntax,
   JIT-friendly, smaller per-cell overhead. Worth keeping in mind
   as an optional optimisation once the general placement-based
   compile is working: detect single-consumer chains at the lattice
   stage, emit a generator for those, Delayed cells for shared
   ones. Probably not worth the implementation effort until
   benchmarks tell us per-cell overhead matters.

## Implementation order

Staged so we can validate at each step before proceeding:

1. **Runtime primitives.** Port `Delayed`, `stream`, `zipStream`,
   `listToStream` to the compile target. Synchronous (no promise);
   same three-state cache shape as the prototype, minus the
   event-loop integration.

   *Update (2026-07-06):* two requirements from "The skip
   mechanism" above land here: force must follow
   flatMap/redirect chains iteratively (a long run of skipped
   elements is otherwise O(run) stack — a hazard the prototype's
   `tick()` masked and the stripped synchronous variant exposes),
   and the force loop should path-compress the cells it walks.

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
  later it may affect the algorithm. *(Since tackled:
  `lazy-stream-join-design.md` works join out as per-close output
  construction — a flatten — and concludes it does not affect
  this algorithm; `lazy-stream-commute-design.md` reaches the
  same conclusion for commute.)*

- **Optimisation of the eager compile.** The placement algorithm
  for eager flows is preserved at `plans/placement-algorithm-notes.md`
  and can come back if/when we want tighter JS for the eager fragment.

- **The interaction with iteration rails / loop-carried state.**
  When we add those, they need their own placement story.

- **Performance benchmarking.** We need this eventually, but not
  before something works.
