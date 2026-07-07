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
on the close's branch.flow. *(2026-07-07: superseded — join is a
binary flow operation, not a close annotation; see "Join is a
binary flow operation" below.)*

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

## Join at an option level (taking up open question 2)

> *(2026-07-07: superseded — see "Join is a binary flow
> operation" below. The fork this section constructs between
> spellings J and F dissolves once join is stated at its proper
> arity: the contested stack `Joined(NodeFlow(optionIter))` was
> an *incomplete* program, not an ambiguous one, and J and F
> were rival conventions for silently completing it. The section
> stays as the record of how the incompleteness surfaced; its
> worked table survives as the four-program table in the
> superseding section.)*

*(Added 2026-07-06.)* Open question 2 below asked whether joining a
stream of options — where the join "transparently skips Nones" — is
the same operation as stream-filter, and suggested a worked example
would settle it. Working the example shows the question is sharper
than it looked: the documents currently in print assign **three
mutually inconsistent answers** to what happens to a non-firing
element, and choosing between the two coherent ones is a real
design decision, not a clarification. This section pins down the
discrepancy, lays out the two candidate resolutions as complete
wrapper algebras, and records what would settle the choice. It does
not make the choice.

### Three readings currently in print

Setting: an option iter opened per element of a stream flow (per
element, the option either fires with a value or doesn't), and a
close on that option iter. What is the close's output as the
enclosing stream layers wrap and join it? The fate of a non-firing
element differs by document:

1. **Skip at the wrap.** `lazy-stream-commute-design.md`,
   "Multi-output independence": the plain non-commuted close
   "yields a `stream<X>` of just the defined values (filter-style
   reading)". A non-firing element contributes no cell, already at
   the plain — unjoined, uncommuted — close.

2. **Keep at the wrap; join never touches it.** The same document,
   "Composing Commuted with Joined", three sections later: the
   plain close yields `stream<stream<option<X>>>` — the option is
   packaged as a per-element *value*, Nones kept — and `Joined`
   merges the two nearest *stream* layers, yielding
   `stream<option<X>>` with the Nones still present (that
   section's worked example: `[Some(2), Some(4), None, Some(8)]`).

3. **Keep at the wrap; skip at the join.** The implemented list
   compile (`lazy-compile-design.md`, "Output form for iter
   chains"): an unjoined close on an option iter yields a
   set-iff-fired value — option data in the undefined encoding —
   while a *joined* close whose walked-up chain crosses the option
   level skips: "`List<Option<X>>` joined produces a list of just
   the defined values — push when Some, skip when None." The
   original language description agrees:
   `flow_language_design.md`, "Filtering with Partial
   Conditionals", presents filtering *as* a JOIN of a partial
   branch's flow with the list flow ("Elements that fail the
   condition don't execute through the partial branch").

Reading 1 contradicts reading 2 inside one document, and is
untenable on its own: if the plain wrap already skips, the
Nones-kept shapes — `stream<option<X>>` and everything the
composition discipline builds from them — become inexpressible from
a closed option. It is presumably loose wording for "the sibling
close that reads filter-style", but the looseness lands exactly on
this open question's fault line, which is why it is worth pinning
down rather than waving through.

Readings 2 and 3 are both coherent, and they genuinely disagree:
`Joined(NodeFlow(optionIter))` means different things under each.
The disagreement traces to one modelling choice: **does the close
on an option iter contribute a chain level or not?** The list
compile starts the walked-up chain at the close's own opener, so
the first `Joined` fuses the option level with the nearest
enclosing sequenceable level — skip semantics fall out of "any
list in chain → list". The composition discipline instead consumes
the option level into the per-element value shape before any stage
applies, so `Joined` only ever sees stream layers — a pure flatten
that can never drop an element.

One vocabulary item makes the algebras below precise. Call a value
shape **partial** when it is a may-not-fire output of a closed
option level (or, later, of a single opened alt): "a value on
iterations where the option fired, nothing on the others". This is
`flow_language_design.md`'s `PARTIAL_BRANCH` propagation and the
implemented compile's set-iff-fired binding. Partiality is
flow-level absence; `option<X>` is data. The two conflate in the
undefined encoding but the algebra needs them distinguished,
because the whole question is *which construct converts flow-level
absence into what*.

### The two candidate algebras

Both algebras agree on the frame: wrapper stacks are
output-construction stages applied inside-out, each stage's
requirement checked when reached, ill-formed stacks rejected — the
shape discipline of `lazy-stream-commute-design.md` survives
intact. They differ in the stage inventory and in what the plain
close contributes.

**Spelling J (join crosses levels — the list precedent).** The
close's chain starts at its own opener. Closing an option level
yields a partial value. An enclosing layer wrapped with no stage
materialises partiality as option data (`stream<option<X>>` — this
is what reading 3's unjoined case does). `Joined` consumes the
nearest unconsumed enclosing level, of either kind: consuming a
stream level with a partial value skips non-firings (filter);
consuming an enclosing option level ANDs the firings (the
`Option<Option<X>>` rule); consuming a stream level with a plain
value flattens (the pure-stream join, unchanged). `Commuted`
consumes the nearest enclosing stream level, requires a partial or
option-shaped value, abort semantics. There is no separate filter
stage: filter *is* join at an option level.

**Spelling F (filter is its own stage — the composition
discipline, completed).** The option level is consumed to option
*data* immediately, as the composition discipline already has it.
`Joined` merges stream layers only and never drops an element —
cardinality-preserving by definition. The skip behaviour, which
this spelling currently lacks (that lack is what reading 1
papered over), is restored as its own stage: `Filtered` converts a
partial or option-shaped per-element value into cell-absence in
the nearest enclosing stream layer, leaving that layer in place
for further stages. The name is deliberate — it extends the
existing case-split `Filtered` to option levels, unifying the
language's two skip constructs under one spelling.

The algebras are not different semantics so much as different
*spellings partitioning the same operation inventory*: J overloads
join with level-kind-dependent behaviour; F splits by behaviour.

### Worked example

Outer stream `S` of inner streams `T`, conceptually
`[[2, 4], [6, 7], [8]]`; per innermost element an option iter on
`maybeEven` (fires with `n` iff even). The close is on the option
iter. Per-element firings: group 1 `[2, 4]` both fire; group 2
`[6, 7]` fires then doesn't; group 3 `[8]` fires. The middle group
is the probe: it fails *partially*, which is what separates
readings that agree on all-or-nothing groups.

| stack | under J | under F |
|---|---|---|
| `NodeFlow(opt)` | `[[Some 2, Some 4], [Some 6, None], [Some 8]]` | same |
| `Joined(NodeFlow)` | `[[2,4],[6],[8]]` — per-group filter, grouping kept | `[Some 2, Some 4, Some 6, None, Some 8]` — flat, Nones kept |
| `Joined(Joined(NodeFlow))` | `[2,4,6,8]` — flat filter | ill-formed (one flat layer left) |
| `Filtered(NodeFlow)` | — (spelled `Joined(NodeFlow)`) | `[[2,4],[6],[8]]` |
| `Joined(Filtered(NodeFlow))` | — (spelled `Joined(Joined(…))`) | `[2,4,6,8]` |
| `Commuted(NodeFlow)` | `[Some [2,4], None, Some [8]]` | same |
| `Commuted(Commuted(NodeFlow))` | `None` (grouped abort) | same |
| `Commuted(Joined(NodeFlow))` | ill-formed (join consumed the partiality; nothing left to commute on) | `None` — flat global abort |
| `Joined(Commuted(NodeFlow))` | ill-formed | ill-formed |
| `Filtered(Commuted(NodeFlow))` | — (re-open needed) | `[[2,4],[8]]` — successful groups' payloads |
| `Joined(Filtered(Commuted(…)))` | — (re-open needed) | `[2,4,8]` — flat |

Every *value* in the table is reachable under either spelling; the
spellings differ in which combinations are single wrapper stacks
and which need auxiliary construction:

- Under J, the flat-Nones-kept shape (`Joined(NodeFlow)` in F)
  takes two closes: close the option unjoined into an option-data
  value per T-element, then a separate joined close on `T` across
  `S` carrying that value. The flat global abort
  (`Commuted(Joined)` in F) is `Commuted(Commuted)` plus a
  value-level flatten of the Some payload — cheap, since the
  commute doc's identity shows the two force the same cells in the
  same order and differ only in payload grouping. The
  filtered-commute shapes take a re-open of the commuted output.
- Under F, the filter shapes each take one `Filtered` stage; no
  auxiliary constructions are needed in the table at all.

Note what the table exposes about the commute doc's rejection of
`Joined(Commuted(…))`: the redirect there — "the thing a user might
have wanted from it … is already the *non-commuted* close on the
same option iter" — is subtly wrong. Flattening the Some payloads
of a per-group commute keeps only *wholly* successful groups:
`[2,4,8]`. The filter-style sibling keeps every firing element
regardless of its group's fate: `[2,4,6,8]`. The `6` is the
witness — even, but in a group that fails at `7`. The two agree
only when every failing group fails wholesale, which is exactly the
kind of coincidence worked examples exist to break. (The rejection
of the stack itself stands under both spellings; only the redirect
needs correcting — to `Joined(Filtered(Commuted(…)))` under F, or
the re-open construction under J.)

### So: is join-over-Nones the same operation as filter?

The question decomposes under the spelling choice:

- **Under J: yes, identically.** The joined close over a chain
  containing an option level *is* the filter reading — same output
  construction, differing from the case-split `Filtered` only in
  the front end that produces the partiality (an option's firing
  vs a discriminator's alt). This is already how the implemented
  list compile behaves, where `emitIterClose` over
  `List<Option<X>>`-joined and `emitFilterClose` share the same
  skip-vs-push shape.
- **Under F: no, by design.** Join is cardinality-preserving,
  always; skipping is `Filtered`'s job, at any level kind. The
  original question's premise ("the join just transparently skips
  Nones") is simply false in this spelling.

Open question 2's own phrasing — a None as "an inner 'stream'
that's empty" — suggests a third account: coerce the option to a
zero-or-one-cell stream and let pure join flatten it away. That
coercion reproduces J's join column exactly, but gets the base
case wrong: the unjoined close would yield a stream of 0/1-streams
where both precedents yield option data. Partiality-as-firing, not
option-as-stream, is the cleaner formalisation, and neither
spelling needs the coercion.

### What is unaffected by the choice

Placement, entirely — under either spelling, `Filtered`/`Joined`/
`Commuted` stacks remain per-close output construction and never
participate in the chain partitioning, by the same argument as for
join and commute individually. The runtime "skip" mechanism (a
non-firing element must advance the chain without emitting a
spurious cell) is `lazy-stream-placement-design.md`'s open
question 1 and is needed under either spelling — the choice moves
*which construct* owns the skip, not whether it exists. *(Since
worked out: that document's "The skip mechanism" — become-the-rest
in the atCons, the same move this document's flatten makes at
atNil — spelling-neutral as predicted.)*

### What would settle it

Considerations, deliberately not weighed here:

- **Continuity.** J is what the implemented list compile does and
  what `flow_language_design.md`'s filtering section describes.
  Choosing F means respelling the implemented
  `List<Option<X>>`-joined rule as `Filtered` (a small migration in
  a sandbox codebase, but a real one) and revising the original
  filtering account. Choosing J means amending the commute doc's
  composition section (its `Joined(NodeFlow)` and
  `Commuted(Joined)` rows are F-spelled).
- **One behaviour per name.** F gives join a single reading —
  structural flatten, never drops data — and unifies the two
  existing skip constructs (case-split `Filtered`, joined option
  chains) under one name. J keeps the skip split across two
  spellings but keeps `Joined` meaning the same thing on list and
  stream flows *as implemented today*.
- **Visibility.** J's defence against "join sometimes drops
  elements" is structural: whether a join can drop is read off the
  kinds of the levels it spans, which the diagram shows (cf.
  `flow_language_design.md`, "Visual Clarity Advantage"). F's
  defence is nominal: the name alone tells you. The language has
  precedent for preferring the structural argument — and also a
  principle ("one obvious reading") that F serves more directly.
- **Compositionality.** F composes skip freely with commute
  (`Filtered(Commuted(…))` and its join are single stacks); J
  reaches those shapes only via re-opens. If filtered-commutes turn
  out to be a wanted pattern, that weighs toward F; if they stay
  exotic, the extra stage buys little.

## Join is a binary flow operation (2026-07-07)

> This supersedes the J/F framing of "Join at an option level"
> above. The correction is not a choice between the two algebras
> but a diagnosis: the program that generated the fork was
> incomplete, and the algebras were rival conventions for
> completing it. With join stated at its proper arity there is
> nothing left to choose. (Terminology, adopted here and going
> forward: **collect**, for the construct the code and earlier
> documents call Close — same construct, better word, and the
> renaming's point is the correction's point: one collect closes
> exactly one flow.)

### The correction

Three statements the wrapper-stack notation did not respect:

1. **A collect closes exactly one flow.** A collect on the
   innermost option flow of a three-deep nesting leaves the two
   enclosing flows open. That is not a complete program; every
   open flow still owes a termination.

2. **Join is a flow operation with two flow inputs and one flow
   output.** Its inputs are an outer flow and the flow
   immediately inside it; its output is the newly combined flow.
   Nesting-adjacency of the operands is a well-formedness
   requirement. (Since a flow has exactly one immediately
   enclosing flow, the inner operand technically determines the
   outer — but naming only one flow is exactly the shorthand
   that caused the trouble below, so both operands are part of
   the operation.) In many situations the combined flow can be
   identified with the outer operand — the outer flow absorbs
   the inner and continues on — which is also how the
   implemented list compile behaves mechanically: a joined
   collect just walks more opener levels; no new flow object
   exists.

3. **Join on just the innermost flow therefore doesn't make
   sense.** `Joined(NodeFlow(optionIter))` names one flow where
   two terminations are owed and two operands are needed. It is
   not a program with two possible meanings; it is not a
   program.

### Where J and F actually disagreed

The old notation attached join to the collect, as a wrapper
stack on the collect's flow reference. That conflates two
different kinds of node — the collect, and the join(s) — into
one, and leaves implicit which flows each stage terminates. J
and F were rival conventions for reading the conflated form: J
read the stack outward from the named flow (the collect's chain
starts at its own opener; each `Joined` absorbs the next
enclosing level), F read the named flow as collected immediately
and the stack as staging over the enclosing layers. Both were
internally consistent; neither could be *right*, because the
notation underdetermined the program. Two coherent algebras with
no semantic way to choose was the tell.

### The law of the combined flow

Stated once, for every operand-kind pair: **the combined flow
fires exactly when the inner operand fires** (the inner's
firings, which occur within the outer's, in time order).
Everything each old algebra defended follows as a theorem:

- join(list, list) fires per inner element — flatten. F's "join
  never drops" is this law: nothing that fires is lost, and a
  non-firing was never a firing.
- join(list, option) fires per Some — filter. J's "filter is
  join at an option level" is this law applied to an option
  inner operand.
- join(option, option) fires iff both fire — the
  `Option<Option<X>>` AND rule.
- join(option, list) fires per inner element, and not at all if
  the outer never fired.

The implemented "any list in chain → list" output rule is the
kind half of the same law: the combined flow is list-kind if
either operand is list-kind (firing count can exceed one),
option-kind if both are options (zero or one firing).

The old dispute — "does join drop the None?" — dissolves. A None
is a non-firing, and the law never mentions non-firings; join
neither drops nor keeps them because they were never firings of
anything. The Nones-kept output the F algebra was protecting is
not a property of join at all: it is a property of *collecting*
the option flow, which converts fired-or-not into data. Which
termination the option flow gets — absorbed by a join, or
collected into option data — is the program's explicit choice,
made per flow.

### The worked example, as four programs

Data `[[2, 4], [6, 7], [8]]`; flows O (outer list), I (inner
list, opened per O-element), P (option on `maybeEven`, opened
per I-element). A complete program terminates every flow, each
by a collect or by being absorbed into its parent via join. The
contested table rows become distinct programs:

| program | output |
|---|---|
| collect P; collect I; collect O | `[[Some 2, Some 4], [Some 6, None], [Some 8]]` |
| collect P; join(O, I); collect the combined flow | `[Some 2, Some 4, Some 6, None, Some 8]` |
| join(I, P); collect the combined flow; collect O | `[[2, 4], [6], [8]]` |
| join(I, P); join(O, that); collect | `[2, 4, 6, 8]` |

Row 2 is what F called `Joined(NodeFlow)`; row 3 is what J
called `Joined(NodeFlow)` and F called `Filtered(NodeFlow)`; row
4 is J's `Joined(Joined)` and F's `Joined(Filtered)`. Every
value in the old table was reachable under both algebras
(sometimes via auxiliary construction) because these were all
real programs; the algebras disagreed only about notation, which
is why the disagreement could not be settled semantically.

### Precedent

`flow_language_design.md`'s original filtering account was
already binary: filtering is presented as a JOIN of a partial
branch's flow with the list flow — two named operands. The
wrapper-stack notation lost the arity, and the J/F fork is what
growing the design on the lossy notation eventually produced.
There is also a resonance with the no-bottleneck principle
(`language-design-philosophy.md`), which characterises the
concurrency join as a barrier with corresponding inputs and
outputs: the flatten join now has the same shape — explicit
corresponding inputs, an explicit output — rather than riding as
an annotation on a collect.

### What survives

- **The skip mechanism** (`lazy-stream-placement-design.md`,
  "The skip mechanism") is unchanged: it is needed exactly when
  a join absorbs an option flow into a list/stream flow (rows 3
  and 4) — become-the-rest at a non-firing element. Programs
  that instead collect the option flow (rows 1 and 2) carry data
  and never skip. The sentence "the choice moves which construct
  owns the skip" resolves: join-with-an-option-inner owns it.
- **Placement-independence.** A collect on a combined flow
  compiles to the same self-contained thunk as today's joined
  closes — the join nodes determine which opener levels the
  thunk's walk spans; chains and cells stay source-aligned. The
  companion documents' phrase "join is per-close output
  construction" should be read as "the join nodes determine the
  structure the collect's output construction consumes"; the
  compiled shape the argument rests on is unchanged.
- **Every output value** in the superseded section's table, as
  the four programs above.

### What this opens

Recorded, not decided:

1. **Does commute become binary too?** `Commuted` consumes an
   enclosing stream layer against an option-shaped value — the
   same two-operand smell (the option flow, and the enclosing
   flow it commutes across). If so, the wrapper-stack notation
   retires entirely, and `lazy-stream-commute-design.md`'s stack
   rows should be re-read as programs over explicit join/commute
   nodes (they all translate).
2. **Representation.** `Expr.res` today spells join as a
   `flowRef` wrapper peeled by the close. Binary join is a flow
   node with two flow inputs, and a collect references exactly
   one flow. Whether the unary spelling survives as sugar (the
   outer operand is derivable from adjacency) or is dropped (the
   sugar is what hid the missing termination) is an ergonomics
   choice. *Update (2026-07-07)*: taken up —
   `first-class-ports-design.md` works out the representation
   (a `Join({outer, inner})` node with one flow output, inside
   a general per-kind port-inventory model that also dissolves
   Branch and `Filtered`), stages the migration, and records
   the unary-sugar question as its migration step 3's exit
   decision.
3. **Naming, which is all that remains of J vs F.** The law
   fixes the semantics of every operand-kind pair; what's left
   is whether option-inner absorption is surfaced under the name
   join or under the name filter (as sugar for the same
   operation). The old visibility debate — structural reading
   off the diagram vs one behaviour per name — lands here,
   deflated to vocabulary: the diagram shows both operands and
   their kinds either way.
4. **What collecting an option flow yields** — option data, the
   undefined encoding, or a distinguished partial value — was
   already an open vocabulary point and is unchanged; it now
   sits on a single construct (collect-on-option) instead of
   being entangled with join.
5. **Multi-consumer completeness.** Flows admit multiple
   collects (multi-close); presumably a flow may likewise be
   absorbed by one consumer's join while another consumer
   collects it. "Every flow terminated" reads per consumer path,
   as multi-close already does.

## Open questions

1. **User-facing form of multi-level join.** For lists we wrote
   `join_(join_(NodeFlow(opener)))`. The same nesting should
   work for streams — `join_(join_(NodeFlow(streamOpener)))`
   produces a two-level flatten of the close's output. Want to
   confirm the runtime cleanly composes the `zipStream`-with-rest
   trick at multiple levels (it should — each level just nests
   one more `zipStream` with the level-above's restFlat as atNil).
   *(2026-07-07: the user-facing form is now two binary join
   nodes rather than a nested wrapper — "Join is a binary flow
   operation" above; the runtime composition question is
   unchanged.)*

2. **Join interaction with stream-filter / stream-option-style
   conditionals.** ~~Joining a stream of options where some are
   None: the join just transparently skips Nones (an inner
   "stream" that's empty contributes nothing to the flat output).
   That's filter-by-another-name. Is it actually the same
   operation, or do they differ subtly? Worth a worked example
   when we get there.~~ **Taken up and sharpened** — see "Join at
   an option level" above. The worked example revealed the
   question is really a choice between two wrapper-algebra
   spellings: J (join crosses the option level with skip
   semantics — the implemented list rule, under which the answer
   is "yes, the same operation") and F (join is always
   cardinality-preserving and skip is a `Filtered` stage — the
   commute doc's composition discipline, under which the answer is
   "no, by design"). Along the way it surfaced an internal
   inconsistency in `lazy-stream-commute-design.md` (its
   "Multi-output independence" and "Composing" sections assume
   different spellings) and a wrong redirect in that doc's
   `Joined(Commuted)` rejection. The spelling choice is left
   open — the section records what would settle it. *(2026-07-07:
   dissolved rather than settled — "Join is a binary flow
   operation" above. The contested stack was an incomplete
   program; with join binary, the two readings are two distinct
   programs and no convention is needed.)*

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
   that specific branch's output. *(2026-07-07: another instance
   of naming only one operand — binary join takes two flows, and
   a Branch names a flow (one alt's), so the question becomes
   simply which flow is the inner operand. See "Join is a binary
   flow operation" above.)*

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
