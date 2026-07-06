# Joining Stream Flows

## What this is for

The list-flow `join_` operation lifts a close's output up one
nesting level: a close on an inner list inside an outer list,
joined, ends up pushing into an output array at the outer-loop's
parent scope instead of the inner-loop's parent scope. The
mechanism is inseparable from the imperative scope/array
structure — there's literally a different `const out = []`
allocation location.

> *(2026-07-06: that description is of the retired compile-time-
> placement compile — see `placement-algorithm-notes.md`. In the
> shipped runtime-lazy compile a joined close is one self-contained
> thunk applying the "any list in chain → list" rule
> (`lazy-compile-design.md`), so no binding physically moves
> between scopes; join instead changes how many opener levels the
> thunk's loop nesting walks up. The contrast this paragraph draws
> — streams have no scopes or arrays to express either version of
> that in — holds unchanged.)*

Streams don't have scopes or arrays, so the same mechanism
doesn't translate directly. This document is about what "join"
*means* for stream flows, and whether/how it interacts with the
placement algorithm sketched in
`plans/lazy-stream-placement-design.md`.

This is a placeholder document — we don't have stream flows
implemented yet, and stream-join isn't on the path to the first
working version (commute on a single-output stream doesn't need
it). It exists so we don't lose what we worked out in
conversation, and so we can revisit it when stream-join becomes a
concrete need.

## What join means for streams

A close on an inner stream flow that lives inside an outer stream
flow produces — by default — a `stream<stream<X>>`: each outer
cell yields one inner stream (the inner flow's per-outer-element
evaluation). Joining flattens that: a single `stream<X>` whose
cells are the inner-stream values, concatenated across outer
cells in order.

This is the structural analog of the list case. For lists, the
natural multi-close-on-inner produces `List<List<X>>`; joined,
you get `List<X>`. For streams, the natural is `stream<stream<X>>`;
joined, `stream<X>`.

Multi-level join generalises the same way: `Join^N` flattens N
levels of stream nesting.

The syntactic shape mirrors the list case — `join_(streamFlowRef)`
on the close's branch.flow.

## Effect on placement

Essentially none. Each close's *chain placement* is unaffected by
whether it's joined; the chains feeding a close are determined by
the level's lattice analysis as usual. Joining changes the
close's *output construction* — the function that turns the
chain's per-cell records into the actual emitted output stream —
from a pass-through (stream-of-inner-streams) to a flatten (single
flat stream).

The chains don't know they're feeding a flatten vs a pass-through;
they just emit records. The flatten doesn't know it's reading from
a structured chain; it just pulls stream cells. So the placement
analysis treats join as a property of output construction and
ignores it during chain partitioning.

## Worked example

Source `stream<(a, b)>` where `a` and `b` are lists. Per outer
element, an inner stream flow opens `a` and emits two values per
inner element: `d = m*2`, `t = m*3`. Inner has outputs `D` and
`T`. Outer has:

- `outer.O1`: per outer element, fold `inner.D` into a list.
  Unjoined. Output: `stream<list<int>>`.
- `outer.O2`: `join_(inner.T)` — flatten T-values across all outer
  elements. Output: `stream<int>`.

**Inner placement** (per outer-element instance). Lattice axes
`{D, T}`. Unchanged by anything outer does:

- `decode m` ∈ `{D, T}`
- `m*2` ∈ `{D}`
- `m*3` ∈ `{T}`

Three inner chains, same as the unjoined case. Joining `T`'s
outer consumer doesn't propagate down — inner partitions only
depend on inner's outputs.

**Outer placement.** Lattice axes `{O1, O2}`:

- `decode (a, b)` ∈ `{O1, O2}`
- `listToStream(a)` ∈ `{O1, O2}`
- inner-flow construction ∈ `{O1, O2}`
- `inner.D`'s stream-per-outer-cell ∈ `{O1}`
- `inner.T`'s stream-per-outer-cell ∈ `{O2}`
- O1's per-cell fold-into-list ∈ `{O1}`
- O2's per-cell value-feeding-the-flatten ∈ `{O2}`

Three outer chains, exactly as in the all-unjoined version.

**Forcing pattern.** A consumer pulls O2's flat stream. The pull
interleaves outer and inner forces:

1. First pull → flatten asks outer `{O2}` chain for outer cell 0
   → forces outer `{O1, O2}` (decode + inner-construction) →
   reads inner.T's stream for cell 0 (call it `t₀`).
2. Flatten pulls `t₀`'s first cell → forces inner `{T}` chain →
   forces inner `{D, T}` chain → emits first t-value.
3. Subsequent pulls of O2 → continue pulling `t₀`'s cells.
4. When `t₀` is exhausted → flatten transitions to outer cell 1
   → outer `{O2}` advances → new inner.T stream `t₁` → drain it.

Inner's `{D}` chain is never forced unless O1 is also pulled —
m*2 doesn't run unnecessarily. If O1 is pulled too, inner's `{D}`
chain forces independently at O1's own pace.

## Implementation: no intermediate stream-of-streams

The naïve flatten builds a full `stream<stream<X>>` intermediate
(one inner stream per outer cell, chained), then flattens. For
multi-level joins this allocation compounds. We can avoid it
using `zipStream` with the rest-as-atNil pattern.

`zipStream`'s `atNil` parameter is, in the naïve flatten, the
terminator `SNil`. But it doesn't *have* to be `SNil` — it's
whatever value the zipStream returns when it hits the end of its
stream. If we set `atNil` to be "the rest of the flatten" (i.e.,
the next outer cell's contribution), the inner zipStream
transitions transparently from "emitting cells from this inner
stream" to "continuing with the rest" — without ever materialising
an intermediate.

Sketch (synchronous variant, dropping the prototype's `tick()`):

```rescript
let rec flatten = outerStream =>
  zipStream(outerStream, ready(SNil),
    innerStream => restFlat =>
      // restFlat: Delayed<stream<X>> = the flatten of outerStream's tail
      // We want: traverse innerStream, then transition to restFlat
      zipStream(innerStream,
        // atNil for the inner traversal: when inner is exhausted,
        // become the rest of the flatten (forced one layer deep).
        restFlat->Delayed.flatMap(s => s),
        // atCons for the inner traversal: emit a cell, with the
        // tail being more cells of inner (eventually transitioning
        // to restFlat when inner ends).
        (h, t) => ready(SCons(h, t->Delayed.flatMap(s => s)))
      )->Delayed.flatMap(s => s)
  )
```

Per cell of the flat output: two `Delayed`s (an SCons and a
zipStream recursion frame). No wrapper allocation per outer cell.
The structure is linear in the flat output's length, not in
outer-length × inner-length.

For N-level join: each additional level adds a layer of zipStream
recursion, but no extra wrappers per cell. The cost stays linear
in total emitted cells.

## Mixed joined and unjoined closes

Each close independently chooses joined or not. They share the
underlying chains (because the lattice analysis doesn't care
about join). Their output constructions differ: joined closes
wrap their chain output in flatten; unjoined closes pass it
through (stream-of-streams).

Two close-output streams from one inner flow can have different
join levels — e.g., O1 joined to one level, O2 joined to two
levels (if the nesting goes deeper), O3 not joined at all. The
chain feeding them is the same; only the post-chain construction
differs.

## Zip-when-multi-parents stays within a flow level

A reader of the placement doc might wonder if the multi-parent
zip pattern (a sub-chain reading from incomparable parents in the
lattice) interacts with join — e.g., could a sub-chain need to
zip across different join levels?

It can't. The multi-parent zip arises when a sub-chain at level L
has incomparable parents *also at level L* — they're all chains
over the same source iteration, and zipping just means reading
both at the same source cell. Different join levels would mean
different flows, which means different source iterations; chains
across flows aren't zipped via the partition mechanism (they're
bridged via inner-output-as-outer-value, which is a value
reference, not a zip).

So join and the multi-parent-zip case are structurally
independent: zip stays within a level, join is per-close output
construction within a level. Neither imposes new constraints on
the other.

Commute is independent of the multi-parent zip for the same
reason — it too is per-close output construction. The worked
example (a commuted close short-circuiting mid-zip, siblings
unaffected) is in `lazy-stream-commute-design.md`, "Commute and
the multi-parent zip".

## Open questions

1. **User-facing form of multi-level join.** For lists we wrote
   `join_(join_(NodeFlow(opener)))`. The same nesting should
   work for streams — `join_(join_(NodeFlow(streamOpener)))`
   produces a two-level flatten of the close's output. Want to
   confirm the runtime cleanly composes the `zipStream`-with-rest
   trick at multiple levels (it should — each level just nests
   one more `zipStream` with the level-above's restFlat as atNil).

2. **Join interaction with stream-filter / stream-option-style
   conditionals.** Joining a stream of options where some are
   None: the join just transparently skips Nones (an inner
   "stream" that's empty contributes nothing to the flat output).
   That's filter-by-another-name. Is it actually the same
   operation, or do they differ subtly? Worth a worked example
   when we get there.

3. **Infinite inner streams.** Joining a stream of infinite
   inner streams produces an output stream stuck on the first
   inner. Mathematically reasonable but a footgun. No
   special handling needed; just documentation.

4. **What does join MEAN if the inner flow has multiple outputs?**
   `join_(NodeFlow(innerFlow))` is ambiguous — is the close
   joining a particular inner *output* (NodeFlow(branch_)) or the
   inner flow as a whole? The list case sidestepped this because
   close.flow was always a single opener/branch reference. The
   stream case should too — `join_(NodeFlow(branch_))` joins
   that specific branch's output.

## What this doesn't address

- **Stream-to-list / list-to-stream conversion.** Not needed for
  join semantics — both sides of join are streams.

- **Whether stream-join should exist at all.** Commute is the
  motivating stream operation. Join is convenient if you have
  nested stream flows and want to consume them flat, but we don't
  yet know whether that's a common enough pattern to bother
  with. Defer the decision until we have stream flows working
  for non-join cases.

- **Operations other than flatten that could plausibly be called
  "join".** Zip, interleave, round-robin are all reasonable
  candidates. The flatten reading was picked because it mirrors
  the list case; the others would be new operations with their
  own names.
