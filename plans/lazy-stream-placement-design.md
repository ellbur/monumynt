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
outputs that depend on it. Place the computation in the structure
shared by exactly that set: not larger (GC reachability), not smaller
(dedup).

Distinct consumer-sets give distinct chains. The chain count scales
with the number of *distinct* consumer-sets across all computations
— not 2ⁿ, not graph-node-count. In practice it's small.

This is the same principle the eager placement algorithm used:
"place each computation at the deepest scope that includes every
consumer." The medium has changed — scopes were JS blocks, now they're
Delayed-cell chains — but the rule is identical. The work we did to
make that algorithm correct (consumer DAG, SCA of consumer scopes,
the loop-depth concerns) all generalises.

What's new in the stream case is that the "scopes" we're placing into
are derivation chains rather than nested JS blocks. The structure is
not strictly hierarchical — chain {O₁, O₂} and chain {O₁, O₃} both
derive from chain {O₁, O₂, O₃} but neither contains the other.

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

This is the case that needed careful thought. The lattice idea
above is per-flow, but with nested flows there's a real question
of *whose* outputs the lattice is over — the inner flow's, or the
outer flow's. It turns out the right answer is **always the
outermost stream flow's outputs**, and once you see why, the rest
follows.

### A first nested example, where each inner output feeds one outer output

Source is a stream of pairs `(a: list, b: list)`.

- Outer flow opens the source.
- Per outer element, an *inner* stream flow opens `a` and emits per
  inner element two values: `doubled = m*2` and `tripled = m*3`.
  Inner has two outputs.
- Outer has two outputs:
  - `outer.O1`: per outer element, fold inner's doubled stream into
    a list. (Output type: `stream<list<int>>`.)
  - `outer.O2`: per outer element, fold inner's tripled stream into
    a list.

Each computation in the program has a *consumer set among the
outermost stream flow's outputs*, computed by tracing consumers
backwards through *every* flow boundary:

- Inner-level `decode m` is consumed by both `inner.doubled` and
  `inner.tripled`. `inner.doubled` is consumed by `outer.O1`;
  `inner.tripled` by `outer.O2`. So `decode m`'s consumer-set is
  `{outer.O1, outer.O2}`.

- Inner-level `m*2`: consumed by `inner.doubled` only → `{outer.O1}`.

- Inner-level `m*3`: → `{outer.O2}`.

- Outer-level `decode (a, b)`: → `{outer.O1, outer.O2}`.

- Outer-level "construct the inner flow object": → `{outer.O1,
  outer.O2}` (both outer outputs reach into the inner flow).

Computations live at different *levels* — inner-per-element vs
outer-per-element — and within each level they group by their
(outermost) consumer-set:

**Outer level chains** (one per outer source element):

- `{O1, O2}`: decode `(a, b)`, construct inner flow.

**Inner level chains** (one set of chains *per outer source
element*, constructed when the inner flow is constructed):

- `{O1, O2}`: decode `m`.
- `{O1}`: `m*2`.
- `{O2}`: `m*3`.

The inner-level chains live inside the outer-level per-element
scope. When `outer.O1` is dropped, the inner `{O1}` chains (one
per outer element, for all the m*2 values ever computed) become
unreachable; `m*2` evaluations stop being held.

### The case I was hand-wavy about: shared inner output

Now make it harder. Suppose `inner.doubled` is consumed by *both*
`outer.O1` and `outer.O2`, and `inner.tripled` is only consumed by
`outer.O2`. The propagation still works:

- `inner.doubled` is consumed by `outer.O1` and `outer.O2` →
  consumer-set `{O1, O2}`.
- `inner.tripled` → `{O2}`.
- `decode m`: consumed by both inner outputs → union of their
  consumer-sets → `{O1, O2}`.
- `m*2` (consumed by `inner.doubled`) → `{O1, O2}`.
- `m*3` (consumed by `inner.tripled`) → `{O2}`.

Inner level chains:

- `{O1, O2}`: decode m and m*2 (both have this consumer-set).
- `{O2}`: m*3.

Two chains, not three — outside-in propagation correctly merges
`decode m` and `m*2` because they happen to have the same outer
consumer-set even though their *inner* consumer-sets differ.

GC and dedup work as you'd want: dropping `outer.O1` doesn't free
m*2 (still needed by O2 via inner.doubled), but does free nothing
else uniquely held by O1 (which is fine — there isn't anything).
Dropping `outer.O2` frees the entire `{O2}` chain (m*3 stops
running) and `inner.tripled`'s structure becomes unreachable.

The key observation: **the inner flow's *own* output partition
(doubled vs tripled) doesn't determine the inner chain structure;
the *outer* consumer-set does.** Inner partitions can collapse
when outer outputs consume across them; they don't refine when
outer outputs don't distinguish.

So the algorithm is:

1. Identify the outermost stream flow's outputs — these are the
   "axes" of the consumer-set lattice.
2. In one DAG-wide pass, propagate consumer-sets from each
   outermost output backwards through every flow boundary,
   labelling every computation.
3. For each flow level in the program, group its computations by
   consumer-set; each group becomes a chain at that level.

Inside-out doesn't quite work (inner partitions can collapse or
refine based on outer consumption, which is invisible from
inside). Outside-in (in the sense of "what's the lattice over?")
plus DAG-wide propagation (in the sense of "how do we compute each
computation's consumer-set?") is the shape that's correct.

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

## Mixing eager and lazy flows

A diagram can contain both eager list flows and lazy stream flows.
The top-level flow doesn't have to dictate the mode for everything
inside it — each flow can compile in its own mode, with bridges at
the boundaries.

- An eager flow's output (a list) feeding a stream flow: bridge by
  `listToStream(forcedList)`. The list is computed eagerly; the stream
  is a lazy traversal of it.

- A stream flow's output (a stream) feeding an eager flow: force the
  stream to a list (eagerly walk it), then iterate.

The placement principle is the same on both sides — place each
computation in the smallest region that includes all its consumers —
but the *regions* are different: scopes for eager, chains for lazy.
The bridges are explicit conversions; computations on either side of
a bridge can't be placed across it.

This means the algorithm sees a mix of "scope-typed" and "chain-typed"
placement regions, and each computation gets placed in whichever
medium its containing flow uses. Cross-flow consumer-sets still make
sense: an eager-flow value with one consumer in a stream flow lives
in the eager scope of the consumer's containing close, exactly as it
does today; the stream flow's compile sees an already-bound name to
force as needed.

## Algorithm sketch

In one pass over the Expr graph:

1. **Build the consumer DAG.** For each Expr node, record its
   value-port consumers — the same pre-pass the eager algorithm
   already does.

2. **Identify the outermost stream flow's outputs.** These are the
   axes of the consumer-set lattice. If the program has several
   *sibling* top-level stream flows (neither contains the other),
   each is its own independent placement problem with its own
   lattice — they don't share axes.

3. **Propagate consumer-sets backwards.** Each outermost output
   seeds a singleton consumer-set. For every other computation
   reachable from outputs, its consumer-set is the union of its
   direct consumers' consumer-sets. Continues across flow
   boundaries.

4. **Identify the flow level of each computation.** A computation's
   level is determined by which flow's iteration it varies with.
   Outermost-flow computations are per source element; inner-flow
   computations are per (outer-element × inner-element); etc.

5. **Group computations per flow level by consumer-set.** Each
   group becomes a chain at that level. The chain count at a level
   is the number of *distinct* consumer-sets among that level's
   computations, not 2ⁿ.

6. **Emit the chains.** Each chain compiles to a `zipStream` over
   its level's source. The atCons builds a record (object with
   named slots, one per value computed at this chain) for that
   source cell. Sub-chains (chains whose consumer-set is a proper
   subset of another's) derive from their parent chain via
   `Delayed.flatMap`: the sub-chain's atCons pulls the parent
   record from the parent chain's same source cell and uses
   whatever parent-record values it needs, then computes its own
   slot values on top. Forcing the sub-chain forces the parent
   chain (memoised, so cost once per source cell).

7. **Outputs project from their chains.** Output `Oᵢ`'s output
   stream is built from the chain whose consumer-set is the
   smallest set containing `Oᵢ` (the most specialised). That
   chain's record has the slots `Oᵢ` needs (transitively, via
   sub-chain derivation from parents). The output is a
   `Delayed.map` projection from the chain's records to `Oᵢ`'s
   actual emitted value type, or a `zipStream` if `Oᵢ` has its
   own per-element computation beyond what the chain provides.

For a diagram mixing eager and lazy: eager flows compile as today
(scopes), stream flows use the above. Cross-flow values bridge
explicitly via `listToStream` / `forceToList`.

## Relation to the eager placement algorithm

Two pieces carry over identically: the consumer pre-pass, and the
backwards propagation of consumer info. The eager version's
"don't sink past a loop" cap doesn't apply to streams — sinking
into a sub-chain doesn't multiply work, it just changes
reachability — and is replaced by the GC argument the stream case
needs.

If we ever want one compile mode covering both, the placement step
generalises to: for each computation, find the most specific
"region" that contains all its consumers, where a region is a JS
scope (eager) or a Delayed chain (stream) depending on the
containing flow's kind. The bookkeeping is the same.

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

7. **Mixed eager + stream flows.** Confirm cross-flow bridging
   works. May require revising the eager compile to expose a
   value-as-lazy interface to stream callers.

If at any step the design needs revision, revise this document
before continuing. The point of the staged plan is to surface
problems early — finding out at step 6 that the algorithm needs
rework is much cheaper than finding out at step 7.

## What this doesn't address

- **Optimisation of the eager compile.** The placement algorithm
  for eager flows is preserved at `plans/placement-algorithm-notes.md`
  and can come back if/when we want tighter JS for the eager fragment.
  This document is scoped to stream flows.

- **The interaction with iteration rails / loop-carried state.**
  When we add those, they need their own placement story.

- **Performance benchmarking.** We need this eventually, but not
  before something works.
