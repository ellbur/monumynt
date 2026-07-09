# Commuting Option Out of Stream

> Terminology note (2026-07-09): this document predates the
> uncollect/collect correction (says close throughout) and spells
> join/filter in the wrapper-stack notation (`Joined`, `Filtered`,
> `Commuted` on a close's flow reference). The wrapper spelling of
> *join* is superseded by binary Join nodes
> (`lazy-stream-join-design.md`, "Join is a binary flow operation");
> its "Composing Commuted with Joined" rows should be re-read as
> programs over explicit join nodes plus collects, per that
> section. Whether commute also becomes a binary node is recorded
> there as open. The commute semantics and the variant taxonomy here
> are current.

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

(Since reconciled: at the *representation* level commute is a node
on flow wires with no value ports — see "The spec's `Commute`
node" under "What this doesn't address". The `Commuted` wrapper
here remains accurate as the compile-level view; the semantics and
composition discipline in this document apply unchanged.)

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

  > *(2026-07-06: "non-commuted" is loose here — under this
  > document's own shape discipline ("Composing Commuted with
  > Joined" below) the plain close yields `stream<option<X>>`,
  > Nones kept; the defined-values-only reading requires either a
  > skip stage or, in the implemented list compile's spelling, a
  > join across the option level. The discrepancy is worked out in
  > `lazy-stream-join-design.md`, "Join at an option level" — and
  > since resolved by that document's "Join is a binary flow
  > operation" (2026-07-07): the two readings are two distinct
  > programs, differing in whether the option flow is collected
  > in place or absorbed into its parent by a join.)*

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

> *(2026-07-06: this discipline embeds one contestable choice — the
> close on the option iter contributes no layer of its own (the
> option is consumed to a per-element value before any stage
> applies), so `Joined` only ever merges stream layers and can
> never skip a None. That conflicts with the implemented list
> compile, where the walked-up chain starts at the close's own
> opener and the first `Joined` on an option close *is* the skip
> ("`List<Option<X>>` joined produces a list of just the defined
> values"). The two candidate algebras are laid out side by side in
> `lazy-stream-join-design.md`, "Join at an option level"; the rows
> affected if the list-precedent spelling wins are
> `Joined(NodeFlow(opt))` and `Commuted(Joined(…))`. The frame of
> the discipline — stages inside-out, requirements checked when
> reached, ill-formed stacks rejected — survives either choice.)*

> *(2026-07-07: the choice has since dissolved — join is a binary
> flow operation (two flow inputs, an outer flow and the flow
> immediately inside it; one flow output), not a per-collect
> stage, and the contested stacks were incomplete programs. See
> `lazy-stream-join-design.md`, "Join is a binary flow
> operation". This section's rows all translate to programs over
> explicit join nodes plus collects that each close exactly one
> flow; whether commute likewise becomes binary — the option flow
> and the enclosing flow it commutes across as explicit operands
> — is recorded there as an open follow-up.)*

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

> *(2026-07-06: the rejection stands, but the redirect is wrong.
> Flattening the Some payloads of a per-outer-element commute keeps
> only *wholly* successful groups; the filter-style sibling keeps
> every firing element regardless of its group's fate. On
> `[[2, 4], [6, 7], [8]]` with `maybeEven` the former gives
> `[2, 4, 8]`, the latter `[2, 4, 6, 8]` — the `6` is the witness,
> even but in a group that fails at `7`. They coincide only when
> every failing group fails wholesale, which this document's
> worked example (`[[2, 4], [7], [8]]`) happened to satisfy. The
> corrected constructions for the per-group reading are in
> `lazy-stream-join-design.md`, "Join at an option level".)*

## Commute and the multi-parent zip

(This resolves open question 4 below.)

The placement algorithm has one structurally interesting move:
when a sub-chain's consumer-set has two incomparable parents in
the lattice (say `{O₁}` under both `{O₁, O₂}` and `{O₁, O₃}`),
the sub-chain's atCons reads both parents at the same source
cell — a zip (`lazy-stream-placement-design.md`, "When chains
need to zip"). The question was whether a commuted close on one
of those outputs creates any interaction that breaks the
zip-stays-within-a-level rule.

It doesn't, and the reason can be said in one sentence: commute
and zip live on opposite sides of the chain interface. The
lattice analysis computes consumer-sets from the dependency
structure — which closes transitively read which computations —
and a close's wrapper stack (Commuted, Joined, any composition)
is not part of that structure; it changes what the close *builds*
from its chain's cells, never which cells it depends on. So the
chain graph, including any zips inside it, is identical whether a
close is commuted or not. Conversely, a close's output
construction sees only its chain's pull interface — cells arrive
in order, memoised — and cannot tell whether a cell was produced
by a plain atCons or a zipping one. Commute is invisible to
partitioning; zip is invisible to output construction. The one
surface they do share is the memoised pull protocol, which is
built for readers at different paces.

That's the argument; here is the concrete example the open
question asked for. It has three outputs rather than two — the
multi-parent zip needs incomparable parents, which two outputs
can't produce (`{O₁}`'s only possible parent is `{O₁, O₂}`).

### Worked example

Source `stream<int>`. Per element `n`:

- `a = fA(n)` — consumed by O₁ and O₂.
- `b = fB(n)` — consumed by O₁ and O₃.
- An option iter on `maybe(a, b)` (Some iff some predicate over
  both holds). O₁ is the **commuted** close on it: one
  `option<stream<X>>` over the whole source.
- O₂: plain close, emits `a * 10` per element.
- O₃: plain close, emits `b + 1` per element.

Lattice over `{O₁, O₂, O₃}`:

- `{O₁, O₂}`: `a`.
- `{O₁, O₃}`: `b`.
- `{O₁}`: the option input `maybe(a, b)` and the some-case
  value. Two incomparable parents (`{O₁, O₂}` and `{O₁, O₃}`) —
  this is the zip.
- `{O₂}`: `a * 10`.
- `{O₃}`: `b + 1`.

Note that O₁'s commute played no role in building that table —
replacing O₁ with a plain close gives the same five chains.

Forcing trace for a three-cell source where `maybe` succeeds at
cell 0 and fails at cell 1:

1. A consumer forces O₁'s `Delayed<option<stream<X>>>`. The
   commute walk pulls `{O₁}` cell 0. Its atCons zips: it pulls
   `{O₁, O₂}` cell 0 (which forces source cell 0 and computes
   `a₀`), then `{O₁, O₃}` cell 0 (source cell cached; computes
   `b₀`), then computes `maybe(a₀, b₀)` → `Some`. The walk
   records the value and continues.
2. `{O₁}` cell 1 the same way: the zip forces source cell 1,
   computes `a₁` and `b₁`, and `maybe(a₁, b₁)` → `None`.
   Short-circuit: the walk resolves O₁ to `None` and stops
   pulling. `{O₁}` cell 2 is never created, neither zip leg is
   pulled at position 2, and source cell 2 is not forced. Nothing
   needs unwinding — the zip "frame" for position 2 is just the
   un-forced Delayed tail of the `{O₁}` chain.
3. A consumer now drains O₂. `{O₂}`'s chain pulls `{O₁, O₂}`
   cells 0 and 1 — cached from steps 1–2 — then cell 2 fresh:
   source cell 2 forces and `a₂` computes. `b₂` does not compute
   (nothing pulls `{O₁, O₃}` at position 2), and neither does
   `maybe(a₂, b₂)` (nothing pulls `{O₁}` there).

Everything lands where the consumer-set analysis says it should:
work shared with the commuted close is cached for the siblings up
to the short-circuit point (the pre-warming side effect from
"Multi-output independence", now visible at chain granularity)
and computed on the siblings' own demand past it; work private to
the commuted close stops at the short-circuit and is never
revived by the siblings.

### "Commuting differently" generalises

The open question's phrasing — two closes commuting *differently*
on the same source — also covers nested settings where one close
is `Commuted(NodeFlow(…))`, a sibling is `Commuted(Joined(…))`,
and a third is plain. The same argument applies unchanged:
wrapper stacks are per-close output construction ("Composing
Commuted with Joined" above), so all three share whatever chains
the per-level lattice produces, zips included, and differ only
past the pull interface. No combination of stacks on sibling
closes can perturb the chain graph.

## The commute-variant taxonomy

(This resolves open question 3 below.)

Which flow-kind pairs get a commute variant, which don't, and why.
The organizing criterion: **a commute operation is needed exactly
where there is runtime content to repackage or effect timing to
re-sequence.** Where neither flow has a runtime representation,
commutativity is free and no node is needed. For any future
flow-kind pair, this criterion says whether to design a variant or
note a no-op.

- **Sequenceable × sequenceable, different kinds** (option out of
  stream; result out of stream per open question 2). The designed
  case: data repackaging with short-circuit. This document.

- **Marker out of sequenceable** (IO out of stream, list, or
  option). A real variant, but what it changes is *observable
  timing*, not data shape: `stream<IO<X>>` runs effects per pull,
  interleaved with consumer demand; `IO<stream<X>>` runs them all
  at the point the IO executes. No repackaging walk in the data
  sense — the marker has no runtime representation — but the
  "commute is where laziness has to give" principle applies in its
  effect form: the commuted side batches all effects up front.
  There is no short-circuit (markers don't fail), so the walk is
  unconditional. The naturality quotient survives effects: the
  quotient concerns *value* wires not interacting with the node,
  and effect ordering is carried by *flow* wires, which the
  commute node legitimately reorders. That is the value/flow
  division of labor working as intended.

- **Marker × marker** (IO with State, etc.). No commute operation:
  neither side has runtime representation, so they already commute
  — closing them out of order is valid as-is. This is the "free"
  corner of the criterion.

- **Same kind × same kind** (stream out of stream, list out of
  list). Well-posed, contrary to first appearance: it is
  `sequence` in the nondeterminism monad — every possible way of
  choosing one element from each inner stream, i.e. the cartesian
  product. Raggedness is no obstacle. Left out anyway, on
  usefulness grounds: almost nobody who draws nested streams wants
  the outer product, and offering it as "commute" would invite
  accidents. Note this is *not* transpose — see next.

- **Transpose** (row flow with column flow over tabular data). A
  genuinely different operation from monadic sequence, and the one
  that actually requires rectangularity — which is exactly what a
  tabular container's invariant supplies and ragged nested streams
  don't. The taxonomy slot is coherent, but it belongs to the
  (future) tabular-data design, not here.

- **Failable streams** — not a commute variant at all, recorded
  here to mark the boundary. A stream whose terminator is
  `Nil | Fail(e)`: the notions of error and end-of-stream collapse
  into one flow kind. (Runtime-wise this is the tagged-end `SFail`
  constructor an earlier draft of this document introduced and
  dropped — rejected there as a *mechanism* for keeping commute
  lazy, but as a first-class flow kind it is a different proposal.)
  It would fill a real expressiveness gap: the vocabulary has the
  filter reading (skip failures, keep going — non-commuted close)
  and the all-or-nothing reading (commuted close), but not
  *prefix-up-to-failure with partial results kept*. And you would
  not commute an error flow out of it — you would **join** the
  error in: the failure is the stream's termination, so a
  per-element error merges into the terminator rather than being a
  nested layer to move out. Deferred pending concrete use cases
  (parsing-shaped ones seem likeliest: tokens until the first bad
  one, partial results still valuable). *Update*: taken up in
  `async-flow-design.md` ("Failure as terminator payload") —
  interruption supplied the concrete use case, and the design
  generalises to a terminator-payload dimension across flow
  kinds that also covers async rejection; the join-not-commute
  observation above holds there verbatim.

- **Asynchronous flows** (computations on an event loop). A whole
  topic of its own; deferred. One breadcrumb: the `Delayed`
  prototype originally had event-loop integration that
  `lazy-stream-placement-design.md` explicitly strips
  ("synchronous, minus the event-loop integration"), so when this
  opens there is a known seam to reopen rather than a blank page.

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

3. **Other commutes.** ~~Case-split out of stream, option out of
   list (the original eager case we deferred), list out of option
   — each is its own pattern with its own runtime semantic. Out of
   scope here.~~ **Resolved (as a map, not designs)** — see "The
   commute-variant taxonomy" above: the criterion is that a
   commute operation exists exactly where there is runtime content
   to repackage or effect timing to re-sequence. Marker-out-of-
   sequenceable is a real variant (timing, not data); marker ×
   marker commutes for free; same-kind commute is well-posed
   (nondeterminism-monad sequence, the cartesian product) but left
   out on usefulness grounds; transpose is a different operation
   belonging to tabular data; failable streams are a flow kind,
   not a commute (error *joins* into the terminator). Individual
   variants still need their own runtime designs when taken up.

4. **Interaction with the placement algorithm's multi-parent
   zip.** ~~Two closes commuting differently on the same source —
   does this create any structural interaction that breaks the
   zip-stays-within-a-level rule? I think no (commute is per-close
   output, doesn't participate in chain structure), but worth a
   concrete two-output example.~~ **Resolved** — see "Commute and
   the multi-parent zip" above: the "I think no" holds. Commute is
   invisible to chain partitioning and zip is invisible to output
   construction, so neither can perturb the other; the worked
   example (three outputs — incomparable parents need at least
   three) traces a commuted close short-circuiting mid-zip with
   sibling closes unaffected.

## What this doesn't address

- **Commute on eager flows.** We had a long conversation about
  this (`plans/commute-design-notes.md`); the conclusion was that
  list flows can't host commute cleanly without becoming linear,
  and stream flows are the right place for it. This doc is about
  the stream-flow side. The eager-flow story is what it was.

- **Implementing commute.** This document is design; implementation
  comes after the basic stream-flow runtime is in place.

- **The spec's `Commute` node.** *(Reconciled 2026-07-05.)* The
  former divergence — node-form "swap-and-continue" vs this
  document's per-close packaging — resolved as: the node is the
  representation, the close is the compilation. The node carries
  flow wires only (no value ports), so "computation under the
  swapped nesting" is not expressible — value nodes neither inherit
  from nor feed the commute node, making before-vs-after-the-commute
  unrepresentable (the syntax quotients by the naturality identity
  map-then-commute = commute-then-map). Closes on the node's output
  flows compile via this document's output construction; when the
  swapped flows are closed separately (close the loop, defer the
  error flow), the compiler treats it as the full commuted close
  plus an immediate re-open of the still-open layer — internal
  bookkeeping only. See the spec's Commute section for the
  reconciled node shape and the defer-the-error idiom.

- **Whether commute is the right name.** "Commute" describes the
  swap (`stream<option>` ↔ `option<stream>`); "sequence" describes
  the operation (collapse a stream of effects into an effect of a
  stream). Both are accurate; pick one for the language. Defer.
