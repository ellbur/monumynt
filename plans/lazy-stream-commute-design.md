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
annotation. The close's output is built differently — instead of
emitting a value per source cell (including options), it emits
Some-values until None, then fails the stream — but the chains
feeding the close are unchanged, and other closes on the same
source can independently commute or not.

The intuition for why this works:

- Streams are referentially transparent and lazy: every cell is
  computed at most once and only when pulled, so it's fine to not
  know until the very end whether the stream will be interrupted.
- Each output is independently pulled; one commuting and another
  not collecting doesn't create a coordination problem the way it
  did for eager loops (where one consumer's `break` would have
  truncated everyone).
- The commute decision is a property of the per-close output
  construction, not of the per-element computation — so it doesn't
  participate in the per-level lattice analysis.

The placement algorithm from `lazy-stream-placement-design.md` is
unaffected: a commuted close has the same chain placement as a
non-commuted one; only the close's output-emission function
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

## Runtime shape: a stream with a tagged end

Concretely, what is `option<stream<X>>` at runtime?

The naïve type — `Delayed<option<stream<X>>>` — loses laziness. To
know if the option is Some or None, we'd have to scan the entire
source up to the first None or completion, before producing
anything. The stream-of-values inside the Some-case can't be
emitted incrementally.

The right runtime representation is **a stream with a tagged end**:

    type streamNext<'a> =
      | SNil               // natural end — succeeded
      | SCons('a, stream<'a>)
      | SFail              // abnormal end — failed (e.g., hit None)

Consumers iterate as usual. They see `SCons` cells until they hit
the end; the end is either `SNil` (the source ran out with all
options defined — the conceptual "option is Some") or `SFail` (a
None was encountered — the conceptual "option is None").

The user-visible type isn't literally `option<stream<X>>`; it's
`stream<X>-with-possibly-failure`. The two are functionally
equivalent for the common use case of "consume the stream, then
decide Some/None at the end."

This generalises cleanly: `SFail` could carry an error value
(`SFail(E)`), giving us "stream with `Result<stream<X>, E>`
semantics" in one move. That's the natural generalisation if we
ever want commute on something richer than option (e.g.,
`stream<result<X, E>>` → `result<stream<X>, E>`).

For the option case specifically, `SFail` carries nothing (or
`unit`).

## Worked example

Source: `stream<int>`. Per element `n`, an option iter on
`maybeEven(n)` (returns `n` if even, `undefined` if odd). Close on
that option iter is the only close; the close's flow ref is
`commute_(NodeFlow(perElemOption))`.

Compile target (sketch):

    const result = compileStreamFlow(...)
    // result is a stream<int>-with-tagged-end

At each source cell:

- Force source cell K → `n_k`.
- Force the option chain (`undefined` for odd `n_k`, `n_k` for
  even).
- The commuted close's output construction:
  - If option result is defined → emit `SCons(n_k, tail)`.
  - If option result is undefined → emit `SFail`, and don't bother
    forcing further source cells.

For source `[2, 4, 7, 8]`:
- Cell 0: `2`, even → emit `SCons(2, …)`.
- Cell 1: `4`, even → emit `SCons(4, …)`.
- Cell 2: `7`, odd → emit `SFail`.
- Cell 3 (`8`) is never forced — the source was abandoned.

The consumer pulls the result stream:
- First pull: `SCons(2, …)`.
- Second pull: `SCons(4, …)`.
- Third pull: `SFail`.

The consumer interprets the `SFail` as "the option is None overall;
my Some-case would have been `[2, 4]` had I been collecting, but
since I saw an SFail, the whole result is None."

## Multi-output independence

The same per-element option iter can host multiple closes that
treat it differently:

- One close commuted: emits values for defined elements, `SFail`
  on the first undefined.
- Another close non-commuted: e.g. emits values for defined
  elements, skips undefined (the filter-style reading), giving a
  `stream<X>` with normal `SNil` end.
- A third close possibly with yet another treatment.

Each close shares the underlying chain (the per-element option
result, computed once per source cell via `Delayed` memo) but
applies its own output-emission function to produce its own
output stream. Each consumer pulls independently, at its own
pace, to its own end.

If at runtime one consumer pulls the commuted output to its
`SFail` and stops, the other consumers keep pulling source cells
beyond that point and get more values. The two outputs don't
coordinate. This is exactly the property eager loops couldn't
deliver — there, one commute consumer's `break` would have
truncated everyone else.

## Effect on placement

Minimal, just like join. The chains feeding a commuted close are
placed using the standard per-level lattice analysis with no
modification. Commute is a property of the close's output-emission
function: it terminates on `SFail` instead of running to `SNil`.

The close's output-emission function pulls cells from its chain
(per-cell option values) and produces stream cells (`SCons` or
`SFail` or `SNil`). The function shape:

    let rec commuteOutput = (chainStream) =>
      zipStream(chainStream,
        ready(SNil),                    // chain ran out → SNil
        head => rest =>
          switch head {
          | Some(x) => ready(SCons(x, rest->Delayed.flatMap(s => s)))
          | None => ready(SFail)        // short-circuit
          })

The `ready(SFail)` returned for the None case doesn't reference
`rest` — so `rest` never forces, and the chain stops being pulled.
The producer's recursion past the None never runs, exactly as we
sketched for sequence in the early stream conversation.

## How commute differs from join

Both are per-close output annotations. The differences:

- **What they emit on the trivial case.** Join emits `SCons(x,
  innerStream)` and lets the inner stream's own structure handle
  whether to keep emitting. Commute emits `SCons(x, tail)` for
  Some and `SFail` for None.

- **The end semantics.** Join's output ends when both outer and
  inner exhaust (`SNil`). Commute's output ends either on `SNil`
  (success, all options Some) or `SFail` (any None).

- **What the consumer sees.** Join consumers see a flat stream;
  the success/failure distinction doesn't arise. Commute consumers
  see `SCons*` ending with `SNil` or `SFail`, and have to decide
  what to do with the latter.

- **Where the operation is rooted.** Join is on a stream flow that
  contains another stream flow (or has Joineds stacked). Commute
  is on an option flow that lives inside a stream flow. The
  *outer* flow is stream in both cases, but the *inner* flow type
  differs.

These differences don't change the placement story — both are
per-close output transformations that ignore the chain
partitioning.

## Open questions

1. **Commute through more layers.** `Commuted(Joined(NodeFlow(…)))`
   or `Joined(Commuted(NodeFlow(…)))` — do these compose meaningfully?
   The first might mean "join (flatten) the resulting stream, then
   commute the whole thing"; the second might mean the reverse.
   Worth thinking through with an example before claiming they work.

2. **Generalising `SFail` to carry an error.** For option-commute,
   `SFail` doesn't carry a value. For result-commute (`stream<result
   <X, E>>` → `result<stream<X>, E>`), `SFail` would carry the E.
   Probably worth designing `SFail(failurePayload)` from the start
   so the option case is just the unit-payload specialisation.

3. **Other commutes.** Case-split out of stream, option out of
   list (the original eager case we deferred), list out of option
   — each is its own pattern with its own runtime semantic. Out of
   scope here.

4. **What the user-visible type really is.** We've been writing
   `option<stream<X>>` as a conceptual type, but the actual runtime
   thing is `stream<X>-with-tagged-end`. How does the user
   interface with this — do they pull and pattern-match on the
   end? Do we provide a `collect : stream-with-fail → option<list>`
   helper? Probably both, but worth thinking about.

5. **Interaction with the placement algorithm's multi-parent
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

- **Whether commute is the right name.** "Commute" describes the
  swap (`stream<option>` ↔ `option<stream>`); "sequence" describes
  the operation (collapse a stream of effects into an effect of a
  stream). Both are accurate; pick one for the language. Defer.
