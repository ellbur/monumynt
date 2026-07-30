# Commuting Option Out of Stream

Status: current design — the design here is settled, and it now RUNS:
stream flows are implemented and so is this chapter's commute
(`Codegen.emitSequenceCommute`, `src/ARCHITECTURE.md` worklist item 10;
the taxonomy's other row, transpose over a Cross, landed with the poset
round). What is not yet built is the STACKED stages — `Commuted(Joined)`
and `Commuted(Commuted)` under "Composing Commuted with Joined", with
the shape discipline's rejection of `Joined(Commuted)` as its check. The
chapter covers two things: how `commute` is expressed
and compiled as a per-close output construction on stream flows, and
the taxonomy of which flow-kind pairs get a commute variant at all.

> **Reading notes.** This chapter says *close* (the older name for
> *collect*, the operation that terminates a flow into a value). It
> also writes join and commute in the older *wrapper-stack* notation
> — `Joined`, `Filtered`, `Commuted` layered on a close's flow
> reference. At the representation level, *join* is now a binary
> node with two flow inputs (an outer flow and the flow immediately
> inside it) and one flow output, not a per-close wrapper
> (`lazy-stream-join-design.md`, "Join is a binary flow operation").
> So every "Composing Commuted with Joined" row below reads as a
> program over explicit join nodes plus collects that each close
> exactly one flow. Whether *commute* likewise becomes a binary node
> — the option flow and the enclosing flow it commutes across as
> explicit operands — is recorded as open there. The wrapper
> spelling remains accurate as the compile-level view, and the
> commute meaning and variant taxonomy here are current. One scoping
> refinement, folded in below: the same-kind commute the taxonomy
> declines on usefulness grounds has a lawful exception — over a
> Cross product, commute is transpose and is always defined
> (`product-flows-design.md`); the decline applies exactly where the
> nesting is not a product.

## Your first commute

You will often run a step that can fail on every element of a
stream, and want one yes-or-no answer about the whole run: "give me
all the results, or tell me it didn't work out." That is what this
chapter's one specific commute is for: an option flow opened inside
a stream flow, moved outside the stream flow. Inner is option, outer
is stream. In the textual syntax it is a chain (spelling
provisional):

```
src -> open stream -> maybeCompute -> open option -~> commute -~> collect => result
-- result : option<stream<X>>. Some of every value if all fired; None on the first absence.
```

`-> open option` opens each element's `maybeCompute` result into a
fires-or-not flow; `-~> commute` swaps the option layer outside the
stream layer; `-~> collect` closes what is now the outer option.

What changed by adding the commute?

- **Before commute.** The close on the option-per-stream-element
  yields one option-typed value per element, so the output across
  the stream is `stream<option<X>>`.
- **After commute.** The output is `option<stream<X>>` — `Some` of
  all the defined values if every option fired, `None` as soon as
  any element's option is `None`.

If you know Haskell, this is the stream analog of `sequence` on
lists: short-circuit-fail on the first absence. It is also the use
case that brought stream flows into existence — the question "what
should `List<Option<X>>` → `Option<List<X>>` mean?"
(`commute-design-notes.md`) landed on "stream flow with a per-close
commute annotation."

## A worked run

Source `stream<int>`. Per element `n`, an option iter on
`maybeEven(n)` (returns `n` if even, `undefined` if odd). One close
on that option iter, commuted.

For source `[2, 4, 7, 8]`, forcing the result:

- Pull cell 0 → `2`, option → `Some(2)`.
- Pull cell 1 → `4`, option → `Some(4)`.
- Pull cell 2 → `7`, option → `None`. Short-circuit.
- Cell 3 (`8`) is never forced; the source is abandoned.
- Result resolves to `None`.

For source `[2, 4, 8]`:

- Pull cells 0, 1, 2 → all `Some`.
- Source exhausts with no `None` seen.
- Result resolves to `Some(s)`, where `s` is a stream yielding 2, 4,
  8 in order — each cell's `Delayed` already resolved by the time
  the consumer pattern-matches the option.

The result is one option, decided after walking the whole source (or
up to the first `None`).

## Runtime shape

The runtime type is exactly what you asked for:
`Delayed<option<stream<X>>>`. Forcing the outer `Delayed` walks the
chain end-to-end — or to the first `None` — before producing the
option:

- If every per-element option fired, resolve to `Some(s)`, where `s`
  is a stream of the already-forced values.
- If any per-element option was `None`, resolve to `None`. Source
  cells past that point are never forced.

This trades incremental laziness for honesty. You wrote commute,
which means "tell me yes or no for the whole stream," and answering
that demands the whole stream. Consumers downstream of a commuted
close see an `option<stream<X>>` like any other option: they
pattern-match, and in the `Some` case pull cells from the inner
stream. Those pulls are cheap, because the cells were already forced
while the option resolved — but the inner thing is still
structurally a stream, so types stay uniform with the rest of the
system.

Now, you might wonder why the language doesn't try to keep the
result incrementally lazy anyway. An earlier design did try, with a
tagged-end stream constructor (`SFail`). It turns out that solved a
problem the user didn't pose: commute is exactly the place where
laziness has to give, because the answer is one option about the
whole stream. Dropping the trick keeps the design honest. (This is a
settled rejection *as a laziness-preserving trick for commute*;
please don't re-propose it in that role. A tagged-end terminator as
a first-class flow *kind* is a different proposal — see "Failable
streams" in the taxonomy below.)

You might also wonder why the `Some` payload stays a stream at all —
it could equally be a strict list, since every cell is known by the
time the outer option resolves. Keeping it a stream is the more
uniform choice; a call-site that wants a list can collect it
cheaply.

## The core claim: commute is purely a flow operation

Like join, commute is a per-close **output-construction**
annotation. The close's output has a different *shape* —
`option<stream<X>>` instead of `stream<option<X>>` — but the chains
feeding the close are unchanged, and other closes on the same source
can independently commute or not.

Why this works:

- **Cells are shared regardless of packaging.** Streams are
  referentially transparent and lazy — a cell means the same value
  however it is reached, is computed at most once, and only when
  pulled — so per-cell work is shared across consumers via `Delayed`
  memo no matter how each consumer packages its output.
- **Each output is consumed at its own pace.** A commuted output
  forces the chain to completion when its option is forced; a
  non-commuted output stays incrementally lazy. Sharing flows the
  right way — the cells the commuted output pre-resolves are cached
  for the other consumers.
- **The commute decision is about output, not per-element
  computation.** So it does not participate in the per-level lattice
  analysis that the placement algorithm
  (`lazy-stream-placement-design.md`) runs. A commuted close has the
  same chain placement as a non-commuted one; only its
  output-construction function differs.

At the compile level, commute is a flow-ref wrapper parallel to
`Joined` and `Filtered`:

```
| Commuted(flowRef)
```

The wrapped flowRef is a `NodeFlow(optionIter)` (possibly with other
wrappers on top — see "Composing Commuted with Joined"), and the
close it appears in is the close on that option iter. At the
*representation* level the same operation is a node on flow wires
with no value ports (see "The spec's `Commute` node" under "What
this doesn't address"); the `Commuted` wrapper is the compile-level
view of it.

## Multi-output independence

The same per-element option iter can host multiple closes that treat
it differently:

- **One close commuted:** yields `option<stream<X>>` — `None` if any
  element's option was `None`, else `Some` of the all-defined
  values.
- **A sibling close that filters:** yields a `stream<X>` of just the
  defined values, with a normal `SNil` end. This is a *different
  program*, not a plain-vs-commuted flip of the same one: a plain
  close on the option iter yields `stream<option<X>>` with the
  `None`s kept, and the defined-values-only reading requires
  absorbing the option flow into its parent by a join
  (`lazy-stream-join-design.md`, "Join is a binary flow operation" —
  the two readings differ in whether the option flow is collected in
  place or joined into its parent).
- **A third close** with yet another treatment.

Each close shares the underlying chain: the per-element option
result is computed once per source cell via `Delayed` memo and
reused. Forcing the commuted output walks the source to completion
(or to the first `None`); other closes that later pull the same
cells get cached answers cheaply. The outputs have different shapes
— one option, one stream — so they never coordinate at the value
level; they just share per-cell work.

A subtler point: forcing the commuted close before any other
consumer pulls pre-warms every cell of the source. That is not a
coordination bug — it is what "compute the whole stream to answer
one question" implies. A caller that wants the other consumers
genuinely lazy should pull from them first.

## Effect on placement

Minimal, exactly like join. The chains feeding a commuted close are
placed by the standard per-level lattice analysis with no
modification. Commute lives entirely in the close's
output-construction function: at the level of a `zipStream` fold
over the chain, it accumulates `Some` values and either succeeds at
`SNil` (producing `Some(stream)`) or fails on the first `None`
(producing `None`, without forcing the rest of the chain). The
short-circuit is structural — the recursion past the offending cell
is never invoked, so the source isn't pulled past it. Chain
placement is untouched.

## How commute differs from join

Both are per-close output annotations. They differ in four ways:

- **What they produce.** Join produces a flat `stream<X>` (the outer
  stream's elements flattened into the inner stream's). Commute
  produces an `option<stream<X>>` — a single option decided after
  walking the whole source.
- **Laziness.** Join preserves incremental laziness: consumers pull
  cells as they go and the output stays a stream. Commute
  deliberately doesn't — the outer option can't be decided without
  walking the source, so forcing the result forces the chain. This
  is faithful to what you wrote: one yes/no answer about the whole
  stream.
- **What the consumer sees.** Join consumers see a flat stream and
  iterate. Commute consumers see an option and pattern-match; the
  `Some` case carries a stream of values they then pull (cheaply —
  each cell already resolved).
- **Where the operation is rooted.** Both act with an *outer* stream
  flow. Join is on a stream flow that contains another stream flow
  (or has joins stacked). Commute is on an option flow living inside
  a stream flow. The inner flow type is what differs.

None of this changes the placement story: both are per-close output
transformations that ignore the chain partitioning.

## Composing Commuted with Joined

What happens when a program wants both? Setup for this whole
section: an outer stream flow `S`, an inner stream flow `T` opened
per S-element, and an option iter opened per T-element. The close
under consideration is on the option iter; per innermost element it
yields one option-typed value. With no wrappers, each enclosing
stream layer wraps the result, so the output is
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
requirement is met when reached; an ill-formed stack is rejected at
compile time, not given a fallback meaning.

> The discipline here embeds one convention: the close on the option
> iter contributes no layer of its own (the option is consumed to a
> per-element value before any stage applies), so `Joined` only ever
> merges stream layers and never skips a `None`. Under binary join
> nodes (`lazy-stream-join-design.md`), the contested stacks are
> simply incomplete programs, and each row below is a program over
> explicit join nodes plus collects that each close exactly one
> flow. The *frame* — stages inside-out, requirements checked when
> reached, ill-formed stacks rejected — survives that reframing
> intact. (A chain-notation rendering of the six rows is owed with
> that reframing and deliberately not attempted here — join's
> operand adjacency makes the translation design work, not
> transcription; the wrapper rows stay as the record of the
> discipline.)

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
- `Commuted(Joined(NodeFlow(opt)))` — join merges `T`, `S`; commute
  consumes the flat layer. Result `option<stream<X>>` — one global
  answer over everything, grouping lost.
- `Commuted(Commuted(NodeFlow(opt)))` — the first commute consumes
  `T` (per S-element `option<stream<X>>`); the per-element value is
  option-shaped again, so a second commute consumes `S`. Result
  `option<stream<stream<X>>>` — one global answer, grouping kept.
- `Joined(Commuted(NodeFlow(opt)))` — after the commute only one
  layer (`S`) remains, and its per-element value is an option, not a
  stream. Join's requirement fails. **Ill-typed; rejected.**

So `Commuted ∘ Joined` composes and `Joined ∘ Commuted` does not —
and the gap the latter looked like it might fill is already filled
by `Commuted ∘ Commuted`, which the vocabulary expresses. Every
sequence-like target shape over this nesting is reachable by a
well-formed stack; none needs a new primitive.

### Worked example

Source `S` conceptually `[[2, 4], [7], [8]]` (an outer stream of
three inner streams), `maybeEven` per innermost element:

- `Commuted(NodeFlow)`: `[Some([2,4]), None, Some([8])]` — each
  outer element decided independently; pulling the outer stream one
  cell at a time forces only that element's inner walk.
- `Joined(NodeFlow)`: `[Some(2), Some(4), None, Some(8)]` flat.
- `Commuted(Joined(…))`: `None` — short-circuits at `7`; the `8`
  cell and `S`'s third cell are never forced.
- `Commuted(Commuted(…))`: `None` — same forcing trace.

For the all-even source `[[2, 4], [6], [8]]`, the last two give
`Some([2, 4, 6, 8])` and `Some([[2, 4], [6], [8]])` respectively.

A useful identity falls out: `Commuted(Joined(…))` and
`Commuted(Commuted(…))` fail on exactly the same inputs and force
exactly the same cells in the same order. `Commuted(Joined)` walks
the flat elements in reading order — outer first, inner within it —
and stops at the first `None`; `Commuted(Commuted)` forces the
per-S options in order, each walking its own `T` and
short-circuiting within it — the same walk in the same order,
stopped at the same cell. They differ only in how the success
payload is grouped. Empty inner streams behave consistently in
both: an empty `T` contributes nothing (join) or `Some(empty)`
(commute), so all-empty input yields `Some` of an empty structure —
matching the empty-input answer carried over from
`commute-design-notes.md`.

### Laziness is given up per consumed layer

The "commute is where laziness has to give" point refines to:
commute gives up incremental laziness **only for the layers it
consumes.** `Commuted(NodeFlow)` consumes just `T`, so `S` stays a
normal lazy stream — a consumer can pull one outer option at a time
and abandon the rest. `Commuted(Joined)` and `Commuted(Commuted)`
consume everything up to the top, so forcing the result walks the
whole nesting (or short-circuits). You pick how much laziness to
spend by picking which layers the stack consumes.

### Runtime and placement

Nothing new is needed. Each stage is a function on the close's
output construction, exactly as join and commute already are
individually; a stack composes them. `Commuted(Joined)` composes
the `zipStream`-with-rest flatten from `lazy-stream-join-design.md`
with the end-to-end walk from "Effect on placement": the walk pulls
the flat stream, which pulls the flatten, which pulls the sources;
a short-circuit abandons the flatten mid-way, which abandons both
sources. Chain placement is untouched — stacks are per-close output
construction and never participate in the per-level lattice
analysis, for the same reason join and commute individually don't.

Now, you might wonder why the rejected `Joined(Commuted(…))` isn't
simply given the meaning a user might have imagined for it —
"flatten the `Some` payloads, skipping the `None`s." It turns out
this would cause problems: that imagined meaning is **not** the
filter-style sibling close, despite an easy-to-make claim that it
is. Flattening the `Some` payloads of a per-outer-element commute
keeps only *wholly* successful groups; the filter-style sibling
keeps every firing element regardless of its group's fate. On
`[[2, 4], [6, 7], [8]]` with `maybeEven`, the former gives
`[2, 4, 8]` and the latter `[2, 4, 6, 8]` — the `6` is the witness,
even but in a group that fails at `7`. They coincide only when
every failing group fails wholesale. The corrected constructions
for the per-group reading are in `lazy-stream-join-design.md`,
"Join at an option level." Either way, the ill-typed stack is
rejected, not repurposed. (This is a settled rejection — an
ill-formed stack gets a compile-time error, never a fallback
meaning; please don't re-propose the repurposing without new
evidence.)

## Commute and the multi-parent zip

The placement algorithm has one structurally interesting move: when
a sub-chain's consumer-set has two incomparable parents in the
lattice (say `{O₁}` under both `{O₁, O₂}` and `{O₁, O₃}`), the
sub-chain reads both parents at the same source cell — a zip
(`lazy-stream-placement-design.md`, "When chains need to zip"). Does
a commuted close on one of those outputs break the
zip-stays-within-a-level rule?

It doesn't, and the reason is one sentence: **commute and zip live
on opposite sides of the chain interface.** The lattice analysis
computes consumer-sets from the dependency structure — which closes
transitively read which computations — and a close's wrapper stack
(Commuted, Joined, any composition) is not part of that structure.
The stack changes what the close *builds* from its chain's cells,
never which cells it depends on. So the chain graph, zips included,
is identical whether a close is commuted or not. Conversely, a
close's output construction sees only its chain's pull interface —
cells arrive in order, memoised — and cannot tell whether a cell
came from a plain atCons or a zipping one. Commute is invisible to
partitioning; zip is invisible to output construction. The one
surface they share is the memoised pull protocol, built for readers
at different paces.

### Worked example

The example needs three outputs, because incomparable parents
require them (`{O₁}`'s only possible parent with two outputs is
`{O₁, O₂}`).

Source `stream<int>`. Per element `n`:

- `a = fA(n)` — consumed by O₁ and O₂.
- `b = fB(n)` — consumed by O₁ and O₃.
- an option iter on `maybe(a, b)` (`Some` iff some predicate over
  both holds). **O₁ is the commuted close** on it: one
  `option<stream<X>>` over the whole source.
- O₂: plain close, emits `a * 10` per element.
- O₃: plain close, emits `b + 1` per element.

Lattice over `{O₁, O₂, O₃}`:

- `{O₁, O₂}`: `a`.
- `{O₁, O₃}`: `b`.
- `{O₁}`: the option input `maybe(a, b)` and the some-case value.
  Two incomparable parents (`{O₁, O₂}` and `{O₁, O₃}`) — this is
  the zip.
- `{O₂}`: `a * 10`.
- `{O₃}`: `b + 1`.

O₁'s commute played no role in building that table — replacing O₁
with a plain close gives the same five chains.

Forcing trace, three-cell source where `maybe` succeeds at cell 0
and fails at cell 1:

1. A consumer forces O₁'s `Delayed<option<stream<X>>>`. The commute
   walk pulls `{O₁}` cell 0. Its atCons zips: pull `{O₁, O₂}` cell 0
   (forces source cell 0, computes `a₀`), then `{O₁, O₃}` cell 0
   (source cell cached; computes `b₀`), then `maybe(a₀, b₀)` →
   `Some`. The walk records the value and continues.
2. `{O₁}` cell 1 the same way: the zip forces source cell 1,
   computes `a₁` and `b₁`, and `maybe(a₁, b₁)` → `None`.
   Short-circuit: the walk resolves O₁ to `None` and stops pulling.
   `{O₁}` cell 2 is never created, neither zip leg is pulled at
   position 2, and source cell 2 is not forced. Nothing needs
   unwinding — the zip "frame" for position 2 is just the un-forced
   Delayed tail of the `{O₁}` chain.
3. A consumer now drains O₂. `{O₂}`'s chain pulls `{O₁, O₂}` cells 0
   and 1 (cached from steps 1–2), then cell 2 fresh: source cell 2
   forces and `a₂` computes. `b₂` does not compute (nothing pulls
   `{O₁, O₃}` at position 2), and neither does `maybe(a₂, b₂)`
   (nothing pulls `{O₁}` there).

Everything lands where the consumer-set analysis says: work shared
with the commuted close is cached for the siblings up to the
short-circuit point (the pre-warming side effect from "Multi-output
independence", now visible at chain granularity) and computed on the
siblings' own demand past it; work private to the commuted close
stops at the short-circuit and is never revived.

### "Commuting differently" generalises

The same argument covers nested settings where one close is
`Commuted(NodeFlow(…))`, a sibling is `Commuted(Joined(…))`, and a
third is plain. Wrapper stacks are per-close output construction, so
all three share whatever chains the per-level lattice produces, zips
included, and differ only past the pull interface. No combination of
stacks on sibling closes can perturb the chain graph.

## The commute-variant taxonomy

Which flow-kind pairs get a commute variant, which don't, and why.
The organizing criterion:

> A commute operation is needed exactly where there is runtime
> content to repackage or effect timing to re-sequence. Where
> neither flow has a runtime representation, commutativity is free
> and no node is needed.

For any future flow-kind pair, the criterion says whether to design
a variant or note a no-op.

- **Sequenceable × sequenceable, different kinds** (option out of
  stream; result out of stream, per open question 2). The designed
  case: data repackaging with short-circuit. This document.

- **Marker out of sequenceable** (IO out of stream, list, or
  option). A real variant, but it changes *observable timing*, not
  data shape: `stream<IO<X>>` runs effects per pull, interleaved
  with consumer demand; `IO<stream<X>>` runs them all at the point
  the IO executes. No repackaging walk in the data sense — the
  marker has no runtime representation — but the "laziness has to
  give" principle applies in its effect form: the commuted side
  batches all effects up front. There is no short-circuit (markers
  don't fail), so the walk is unconditional. The naturality quotient
  (the identity map-then-commute = commute-then-map, which makes
  "before vs after the commute" unrepresentable) survives effects:
  it concerns *value* wires not interacting with the node, and
  effect ordering rides *flow* wires, which the commute node
  legitimately reorders — the value/flow division of labor working
  as intended. *The list case is now worked* (`effects-design.md`):
  the list/IO commute is defined to sequence — per-firing segments
  concatenate in firing order — and for a spanning handle it is
  mandatory and unique (the handle is linear), so it is never
  drawn; that round's stacking question (IO under an option layer
  that also commutes) is jointly owned with this doc.

- **Marker × marker** (IO with State, etc.). No commute operation:
  neither side has runtime representation, so they already commute —
  closing them out of order is valid as-is. The "free" corner of the
  criterion.

- **Same kind × same kind** (stream out of stream, list out of
  list). Now, you might wonder why you can't commute a stream out of
  a stream. The operation is well-posed, contrary to first
  appearance: it is `sequence` in the nondeterminism monad — every
  way of choosing one element from each inner stream, i.e. the
  cartesian product. Raggedness is no obstacle. But it turns out
  offering it would cause problems: almost nobody who draws nested
  streams wants the outer product, and offering it as "commute"
  would invite accidents — so the language leaves it out, on
  usefulness grounds, not impossibility. This is *not* transpose
  (see the next row). The lawful exception: over a Cross product,
  same-kind commute *is* transpose and is always defined
  (`product-flows-design.md`); the decline applies exactly where the
  nesting is not a product. (A settled decline outside Cross
  products — please don't re-propose it without new evidence of
  demand.)

- **Transpose** (row flow with column flow over tabular data). A
  genuinely different operation from monadic sequence, and the one
  that actually requires rectangularity — exactly what a tabular
  container's invariant supplies and ragged nested streams don't.
  `product-flows-design.md`'s Cross supplies that rectangularity by
  construction, making transpose lawful over any crossed pair; the
  tabular container remains the case where rectangularity comes from
  the data rather than from a Cross. *The from-the-data case is now
  worked* (`product-flows-design.md`, "The Life residue, worked",
  exploration): rectangularity-from-data is the aligned product's
  co-extent, established the two ways co-extent always is — proved
  by shared provenance through shape-preserving ops, or asserted at
  the barrier with a failure witness — so the transpose's license
  has three suppliers (constructed / proved / asserted). Widening
  the implemented gate (`Context.throughCommutes`, constructed
  products only) to admit the other two is that section's filed
  edge, to be reconciled with this row when it lands.

- **Failable streams** — not a commute variant at all, recorded here
  to mark the boundary. A stream whose terminator is `Nil | Fail(e)`
  collapses error and end-of-stream into one flow kind. (This is the
  tagged-end `SFail` mechanism dropped from the runtime design above
  — rejected there as a way to keep commute lazy, but as a
  first-class flow *kind* it is a different proposal.) It fills a
  real gap: the vocabulary has the filter reading (skip failures,
  keep going — the filtering sibling close) and the all-or-nothing
  reading (commuted close), but not *prefix-up-to-failure with
  partial results kept*. And you would not commute an error flow out
  of it — you would **join** the error in: the failure *is* the
  stream's termination, so a per-element error merges into the
  terminator rather than being a nested layer to move out. This has
  been taken up in `async-flow-design.md` ("Failure as terminator
  payload") — interruption supplied the concrete use case, and the
  design generalises to a terminator-payload dimension across flow
  kinds that also covers async rejection; the join-not-commute
  observation holds there verbatim.

- **Asynchronous flows** (computations on an event loop). A topic of
  its own, deferred — set aside for later, not rejected. One
  breadcrumb: the `Delayed` prototype originally had event-loop
  integration that `lazy-stream-placement-design.md` strips
  ("synchronous, minus the event-loop integration"), so when this
  opens there is a known seam to reopen rather than a blank page.

## Open questions

1. **Commute through more layers.** *Resolved* — see "Composing
   Commuted with Joined." Wrappers are output-construction stages
   applied inside-out under a small shape discipline;
   `Commuted(Joined)` and `Commuted(Commuted)` are the two
   meaningful compositions (flat vs grouping-preserving), and
   `Joined(Commuted)` is ill-typed and rejected.

2. **Generalising to result-commute.** `stream<result<X, E>>` →
   `result<stream<X>, E>` is the natural next case after option. The
   meaning carries across cleanly (short-circuit on the first `Err`,
   carrying its payload); whether that's a separate flow primitive
   or a generalisation of option-commute can wait. The language
   hasn't decided this yet.

3. **Other commutes.** *Resolved as a map, not as designs* — see
   "The commute-variant taxonomy." A commute operation exists
   exactly where there is runtime content to repackage or effect
   timing to re-sequence. Marker-out-of-sequenceable is a real
   variant (timing, not data); marker × marker commutes for free;
   same-kind commute is well-posed (nondeterminism-monad sequence,
   the cartesian product) but declined on usefulness grounds outside
   Cross products; transpose belongs to tabular data / Cross;
   failable streams are a flow kind, not a commute (error *joins*
   into the terminator). Individual variants still need their own
   runtime designs when taken up.

4. **Interaction with the multi-parent zip.** *Resolved* — see
   "Commute and the multi-parent zip." Commute is invisible to chain
   partitioning and zip is invisible to output construction, so
   neither can perturb the other; the three-output worked example
   (incomparable parents need at least three) traces a commuted
   close short-circuiting mid-zip with sibling closes unaffected.

## What this doesn't address

- **Commute on eager flows.** The conclusion of that conversation
  (`commute-design-notes.md`) was that list flows can't host commute
  cleanly without becoming linear, and stream flows are the right
  place for it. This document is the stream-flow side; the
  eager-flow story stays as recorded there.

- **Implementing commute.** *Now built* — this chapter's commute, the
  directed sequence, compiles over a stream outer layer
  (`Codegen.emitSequenceCommute`), and the chapter's claim that commute
  is per-close output construction and nothing else is what made the
  emitter cheap: chain placement was untouched, so it is the plain
  stream collect with the option's guard as one more level. One
  observation the design did not have to state and the build did: the
  fold uses become-the-rest at every firing and abandon-the-rest at the
  first `None` — never emit-and-continue, since one answer about the
  whole stream cannot be handed out a cell at a time — and that is also
  what keeps the walk iterative under the primitive's redirect loop.
  What is still design-only here is the stacked stages. The taxonomy's other row
  is already built: **transpose over a Cross is implemented**
  (`src/ARCHITECTURE.md`, poset round). It needed no output
  construction at all, which is the two-operations distinction below
  showing up as a difference in cost: sequence restructures and so
  must walk; transpose only re-reads, so a commute output port
  denotes its operand swapped and the consuming chain becomes another
  permutation indexing the product's one shared table. The compiler
  therefore gates on provenance exactly as the taxonomy says — over a
  crossed pair, transpose; elsewhere, this chapter's still-unbuilt
  walk.

- **The spec's `Commute` node.** The node is the representation, the
  close is the compilation. The node carries flow wires only (no
  value ports), so "computation under the swapped nesting" is not
  expressible — value nodes neither inherit from nor feed the
  commute node, making before-vs-after-the-commute unrepresentable
  (the syntax quotients by the naturality identity:
  map-then-commute = commute-then-map). Closes on the node's output
  flows compile via this document's output construction; when the
  swapped flows are closed separately (close the loop, defer the
  error flow), the compiler treats it as the full commuted close
  plus an immediate re-open of the still-open layer — internal
  bookkeeping only. See the spec's Commute section for the node
  shape and the defer-the-error idiom.

- **Whether "commute" is the right name — and that it currently
  names two operations.** For the option-out-of-stream case,
  "commute" describes the swap (`stream<option>` ↔ `option<stream>`)
  and "sequence" describes the operation (collapse a stream of
  effects into an effect of a stream); both are accurate for that
  one operation, pick one. But the word is stretched further: it
  also labels **grid transpose** (the taxonomy's "Transpose" row and
  the Cross product's transpose in `product-flows-design.md`), which
  is a *genuinely different operation* — reversible and
  value-preserving, gated on rectangularity/independence, the two
  orientations confluent — whereas monadic sequence is directed,
  works on *dependent* nestings, carries semantic content
  (short-circuit), and restructures rather than re-reads. Both "swap
  flow order," which is why one word covers both, but they are not
  one operation with two names; they are two operations. This is not
  merely cosmetic: the question of what a Delay *is* — its binding
  ontology (`delay-ontology-design.md`) — is the second client: a
  register's "next iteration" relates to a reversible re-reading
  (transpose) and to a directed restructuring (sequence)
  *differently*, so conflating them under "commute" hides a real
  fork. The vocabulary should name the two operations distinctly,
  not just choose between "commute" and "sequence" for one of them.
  Deferred, but upgraded from a naming nicety to a two-operations
  distinction with downstream consequences.
