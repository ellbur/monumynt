# Commuting Option Out of Stream

## What this is for

A specific commute: an option flow opened inside a stream flow, moved
outside the stream flow. Inner is option; outer is stream. Before:
the close on the option-per-stream-element yields one option-typed
value per element, so the natural output across the stream is
`stream<option<X>>`. After commute: the output is `option<stream<X>>`
— Some of the all-defined values if every option fired, None as soon
as any element's option is None.

Semantically this is the stream analog of Haskell's `sequence` on
lists: short-circuit-fail on the first absence. It's also the
motivating use case that brought us to stream flows in the first
place — the design conversation that started "what should `List<
Option<X>>` → `Option<List<X>>` mean?" landed on "stream flow with
a per-close commute annotation."

This document is about how to express commute in the flow language
and what the runtime needs to support it.

## The hypothesis: commute is purely a flow operation

Like join, commute can be a per-close output-construction
annotation. The close's output has a different *shape* —
`option<stream<X>>` instead of `stream<option<X>>` — but the
chains feeding the close are unchanged, and other closes on the
same source can independently commute or not.

The intuition for why this works:

- Streams are referentially transparent and lazy: every cell is
  computed at most once and only when pulled, so per-cell work is
  shared across consumers via `Delayed` memo regardless of how
  each consumer packages its output.
- Each output is independently consumed at its own pace. A
  commuted output forces the chain to completion when its option
  is forced; a non-commuted output stays incrementally lazy.
  Sharing flows the right way: the cells the commuted output
  pre-resolves become cached for the other consumers.
- The commute decision is a property of the per-close output
  construction, not of the per-element computation — so it doesn't
  participate in the per-level lattice analysis.

The placement algorithm from `lazy-stream-placement-design.md` is
unaffected: a commuted close has the same chain placement as a
non-commuted one; only the close's output-construction function
differs.

## What commute looks like in the language

A flow-ref wrapper, parallel to `Joined` and `Filtered`:

    | Commuted(flowRef)

The wrapped flowRef is a `NodeFlow(optionIter)` (possibly with
other wrappers on top — see open questions). The close it appears
in is the close on that option iter.

User-facing code (sketch):

    let outerStream = open_(StreamIter, srcStream)
    let perElemOption = open_(OptionIter, app(maybeCompute, [outerStream]))
    let result = close_(commute_(NodeFlow(perElemOption)), perElemOption)
    // result is option<stream<X>> in user-conceptual terms; see "runtime
    // shape" below for what it actually is in JS.

Whether this exact syntax is right is a smaller question — the
semantic point is that commute is a flowRef wrapper.

## Runtime shape

The runtime type is just what the user asked for:
`Delayed<option<stream<X>>>`. Forcing the outer `Delayed` walks the
chain end-to-end (or to the first None) before producing the
option:

- If every per-element option fired, resolve to `Some(s)` where `s`
  is a stream of the already-forced values.
- If any per-element option was None, resolve to `None`. Source
  cells past that point are never forced.

This trades incremental laziness for honesty: the user wrote
commute, which means "tell me yes/no for the whole stream," and
answering that demands the whole stream. Consumers downstream of a
commuted close see an `option<stream<X>>` like any other option —
they pattern-match, and in the Some-case pull cells from the inner
stream. Because the cells were already forced during the option's
resolution, those pulls are cheap; but structurally the inner thing
is still a stream so types stay uniform with the rest of the
system.

The earlier draft of this doc tried to preserve incremental
laziness by introducing a tagged-end stream constructor (`SFail`).
That was solving a problem the user didn't pose: commute is exactly
the place where laziness has to give, because the answer is one
option about the whole stream. Dropping the trick keeps the design
honest.

(Implementation choice: the inner stream could equally well be a
strict list, since by the time the outer option resolves every cell
is known. Keeping it as a stream is the more uniform choice;
call-sites that want a list can collect it cheaply.)

## Worked example

Source: `stream<int>`. Per element `n`, an option iter on
`maybeEven(n)` (returns `n` if even, undefined if odd). One close
on that option iter, commuted.

For source `[2, 4, 7, 8]`:

- Consumer forces the result.
- The commute machinery pulls cell 0 → `2`, option → `Some(2)`.
- Pulls cell 1 → `4`, option → `Some(4)`.
- Pulls cell 2 → `7`, option → `None`. Short-circuit.
- Cell 3 (`8`) is never forced; the source is abandoned.
- Result resolves to `None`.

For source `[2, 4, 8]`:

- Pulls cells 0, 1, 2 → all `Some`.
- Source exhausts with no `None` seen.
- Result resolves to `Some(s)` where `s` is a stream yielding 2,
  4, 8 in order — each cell's `Delayed` is already resolved by
  the time the consumer pattern-matches the option.

The result is one option, decided after walking the whole source
(or up to the first None). Consumers downstream see the option
shape they asked for.

## Multi-output independence

The same per-element option iter can host multiple closes that
treat it differently:

- One close commuted: yields `option<stream<X>>` — `None` if any
  element's option was `None`, else `Some` of the all-defined
  values.
- Another close non-commuted: yields a `stream<X>` of just the
  defined values (filter-style reading), with normal `SNil` end.
- A third close possibly with yet another treatment.

Each close shares the underlying chain — the per-element option
result is computed once per source cell via `Delayed` memo and
reused across consumers. Forcing the commuted output walks the
source to completion (or to the first `None`); the other closes
that subsequently pull the same source cells get cached answers
cheaply. The two outputs have different shapes — one option, one
stream — so they don't coordinate at the value level; they just
happen to share per-cell work.

A subtler point: forcing the commuted close before any other
consumer pulls has the side effect of pre-warming every cell of
the source. That's not a coordination bug — it's just what
"compute the whole stream to answer one question" implies. If a
caller wants to keep the other consumers genuinely lazy, they
should pull from those consumers first.

## Effect on placement

Minimal, just like join. The chains feeding a commuted close are
placed using the standard per-level lattice analysis with no
modification. Commute is a property of the close's
output-construction function: it walks the chain end-to-end (or
until short-circuiting on a `None`) and packages the result as an
`option<stream<X>>`.

The close's output-construction function — at the level of a
`zipStream` fold over the chain — accumulates Some-values and
either succeeds at `SNil` (producing `Some(stream)`) or fails on
the first `None` (producing `None`, without forcing the rest of
the chain). The short-circuit is structural: the recursion past
the offending cell is never invoked, so the source isn't pulled
past it.

The placement story doesn't change; only the close's output
construction does.

## How commute differs from join

Both are per-close output annotations. The differences:

- **What they produce.** Join produces a flat `stream<X>` (with the
  outer stream's elements flattened into the inner stream's).
  Commute produces an `option<stream<X>>` — a single option that's
  decided after walking the whole source.

- **Laziness.** Join preserves incremental laziness: consumers pull
  cells as they go and the output stays a stream. Commute
  deliberately doesn't: the outer option can't be decided without
  walking the source, so forcing the result forces the chain. This
  is faithful to what the user wrote — they asked for one yes/no
  answer about the whole stream.

- **What the consumer sees.** Join consumers see a flat stream and
  iterate. Commute consumers see an option and pattern-match; the
  Some-case carries a stream of values they can then pull (cheaply,
  since each cell is already resolved).

- **Where the operation is rooted.** Join is on a stream flow that
  contains another stream flow (or has Joineds stacked). Commute
  is on an option flow that lives inside a stream flow. The
  *outer* flow is stream in both cases, but the *inner* flow type
  differs.

These differences don't change the placement story — both are
per-close output transformations that ignore the chain
partitioning.

## Composing Commuted with Joined

(This resolves open question 1 below.)

Setup for all of this section: an outer stream flow `S`, an inner
stream flow `T` opened per S-element, and an option iter opened per
T-element. The close under consideration is on the option iter; per
innermost element it yields one option-typed value. With no wrappers,
each enclosing stream layer wraps the result, so the output is
`stream<stream<option<X>>>` — per S-element, a stream over T of
per-element options.

### The shape discipline

Each wrapper is an output-construction stage, applied inside-out
(nearest to the `NodeFlow` first). A stage consumes enclosing stream
layers and/or transforms the per-element value shape:

- **Joined** merges the two nearest unconsumed stream layers into
  one flat layer. It requires at least two layers remaining; the
  per-element value shape is untouched.
- **Commuted** consumes the nearest unconsumed stream layer. It
  requires the per-element value to be option-shaped: `option<W>`
  per element of that layer becomes one `option<stream<W>>` at the
  layer's parent.

Layers still unconsumed when the stack is exhausted wrap the result
as ordinary streams. A stack is well-formed iff every stage's
requirement is met when it is reached; an ill-formed stack is
rejected at compile time, not given a fallback meaning.

Running the discipline over the S/T/option nesting (layers nearest
first: `[T, S]`, per-element value `option<X>`):

- `NodeFlow(opt)` — `stream<stream<option<X>>>`. No stages.
- `Commuted(NodeFlow(opt))` — commute consumes `T`: per S-element
  one `option<stream<X>>`; `S` wraps. Result
  `stream<option<stream<X>>>` — a per-inner-stream commute, decided
  independently per outer element, with `S` still incrementally
  lazy.
- `Joined(NodeFlow(opt))` — join merges `T` and `S`: result
  `stream<option<X>>`, flat across all (outer, inner) pairs.
- `Commuted(Joined(NodeFlow(opt)))` — join merges `T`,`S`; commute
  consumes the flat layer. Result `option<stream<X>>` — one global
  answer over everything, grouping lost.
- `Commuted(Commuted(NodeFlow(opt)))` — first commute consumes `T`
  (per S-element `option<stream<X>>`); the per-element value is now
  option-shaped again, so a second commute consumes `S`. Result
  `option<stream<stream<X>>>` — one global answer, grouping kept.
- `Joined(Commuted(NodeFlow(opt)))` — after the commute only one
  layer (`S`) remains, and its per-element value is an option, not
  a stream. Join's requirement fails. **Ill-typed; rejected.**

So the answer to "do they compose meaningfully?" is: `Commuted ∘
Joined` yes, `Joined ∘ Commuted` no — and the gap the latter looked
like it might fill is actually filled by `Commuted ∘ Commuted`,
which the vocabulary already expresses. Every sequence-like target
shape over this nesting is reachable by a well-formed stack; none
needs a new primitive.

### Worked example

Source `S` conceptually `[[2, 4], [7], [8]]` (an outer stream of
three inner streams), `maybeEven` per innermost element:

- `Commuted(NodeFlow)`: `[Some([2,4]), None, Some([8])]` — each
  outer element decided independently; pulling the outer stream one
  cell at a time forces only that element's inner walk.
- `Joined(NodeFlow)`: `[Some(2), Some(4), None, Some(8)]` flat.
- `Commuted(Joined(…))`: `None` — short-circuits at `7`; the `8`
  cell and `S`'s third cell are never forced.
- `Commuted(Commuted(…))`: `None` — same forcing trace (see below).

For the all-even source `[[2, 4], [6], [8]]`, the last two give
`Some([2, 4, 6, 8])` and `Some([[2, 4], [6], [8]])` respectively.

A useful identity falls out: `Commuted(Joined(…))` and
`Commuted(Commuted(…))` fail on exactly the same inputs and force
exactly the same cells in the same order. `Commuted(Joined)` walks
the flat elements lexicographically and stops at the first `None`;
`Commuted(Commuted)` forces the per-S options in order, each of
which walks its own `T` and short-circuits within it — the same
lexicographic walk, stopped at the same cell. They differ only in
how the success payload is grouped. Empty inner streams behave
consistently in both: an empty `T` contributes nothing (join) or
`Some(empty)` (commute), so all-empty input yields `Some` of an
empty structure, matching the empty-input answer carried over from
`commute-design-notes.md`.

### Laziness is given up per consumed layer

The "commute is where laziness has to give" point from the runtime
section refines to: commute gives up incremental laziness **only for
the layers it consumes**. `Commuted(NodeFlow)` consumes just `T`, so
`S` stays a normal lazy stream — a consumer can pull one outer
option at a time and abandon the rest. `Commuted(Joined)` and
`Commuted(Commuted)` consume everything up to the top, so forcing
the result walks the whole nesting (or short-circuits). The user
picks how much laziness to spend by picking which layers the stack
consumes.

### Runtime and placement

Nothing new is needed. Each stage is a function on the close's
output construction, exactly as join and commute already are
individually; a stack composes them. `Commuted(Joined)` composes the
`zipStream`-with-rest flatten from `lazy-stream-join-design.md` with
the end-to-end walk from "Effect on placement" above — the walk
pulls the flat stream, which pulls the flatten, which pulls the
sources; short-circuit abandons the flatten mid-way, which abandons
both sources. Chain placement is untouched: stacks are per-close
output construction and never participate in the per-level lattice
analysis, for the same reason join and commute individually don't.

On the rejected `Joined(Commuted(…))`: the thing a user might have
wanted from it — "flatten the Some payloads, skipping the Nones" —
is the filter-style reading, which is already the *non-commuted*
close on the same option iter (see "Multi-output independence"). It
is a sibling close, not a wrapper stack; the ill-typed stack should
not be given that meaning.

## Open questions

1. **Commute through more layers.** ~~`Commuted(Joined(NodeFlow(…)))`
   or `Joined(Commuted(NodeFlow(…)))` — do these compose
   meaningfully?~~ **Resolved** — see "Composing Commuted with
   Joined" above: wrappers are output-construction stages applied
   inside-out under a small shape discipline; `Commuted(Joined)`
   and `Commuted(Commuted)` are the two meaningful compositions
   (flat vs grouping-preserving), and `Joined(Commuted)` is
   ill-typed and rejected.

2. **Generalising to result-commute.** `stream<result<X, E>>` →
   `result<stream<X>, E>` is the natural next case after option.
   The semantics carry across cleanly (short-circuit on the first
   Err, carrying its payload); whether that's a separate flow
   primitive or a generalisation of option-commute can wait.

3. **Other commutes.** Case-split out of stream, option out of
   list (the original eager case we deferred), list out of option
   — each is its own pattern with its own runtime semantic. Out of
   scope here.

4. **Interaction with the placement algorithm's multi-parent
   zip.** Two closes commuting differently on the same source —
   does this create any structural interaction that breaks the
   zip-stays-within-a-level rule? I think no (commute is per-close
   output, doesn't participate in chain structure), but worth a
   concrete two-output example.

## What this doesn't address

- **Commute on eager flows.** We had a long conversation about
  this (`plans/commute-design-notes.md`); the conclusion was that
  list flows can't host commute cleanly without becoming linear,
  and stream flows are the right place for it. This doc is about
  the stream-flow side. The eager-flow story is what it was.

- **Implementing commute.** This document is design; implementation
  comes after the basic stream-flow runtime is in place.

- **The spec's `Commute` node.**
  `visual-language-description/visual-language-spec.md` specs commute
  as a swap-and-continue *node*: both flows are re-output with the
  nesting inverted, and computation may continue under the swapped
  nesting before values are collected. This document's per-close
  `Commuted` annotation is the special case where both swapped flows
  are closed immediately. The general node form has no design yet;
  the divergence is recorded side-by-side in the spec's Commute
  section.

- **Whether commute is the right name.** "Commute" describes the
  swap (`stream<option>` ↔ `option<stream>`); "sequence" describes
  the operation (collapse a stream of effects into an effect of a
  stream). Both are accurate; pick one for the language. Defer.
