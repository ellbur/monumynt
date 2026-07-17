# Joining stream flows

Status: placeholder for stream flows (not yet implemented), but it
carries the correction the whole record now follows: **join is a binary
flow operation.** Read that section first; everything else in the doc is
either the stream-specific consequence of it or the record of the dead
end it replaced.

Stream flows are not on the path to the first working version — commute
on a single-output stream is the motivating stream operation and doesn't
need join. This doc exists so the design worked out in conversation isn't
lost, and so it can be picked up when stream-join becomes a concrete
need. Where it says **collect**, older code and docs say `Close`: same
construct, better word. The renaming's point *is* the correction's point
— one collect closes exactly one flow.

## Join is a binary flow operation

Three statements the earlier wrapper-stack notation did not respect.

1. **A collect closes exactly one flow.** A collect on the innermost
   option flow of a three-deep nesting leaves the two enclosing flows
   open. That is not a complete program; every open flow still owes a
   termination.

2. **Join is a flow operation with two flow inputs and one flow
   output.** Its inputs are an *outer* flow and the flow *immediately
   inside* it; its output is the newly combined flow. Nesting-adjacency
   of the operands is a well-formedness requirement. A flow has exactly
   one immediately enclosing flow, so the inner operand technically
   determines the outer — but naming only one flow is exactly the
   shorthand that caused the trouble, so both operands are part of the
   operation. In many situations the combined flow is identified with
   the outer operand — the outer flow absorbs the inner and continues on
   — which is also how the implemented list compile behaves mechanically:
   a joined collect just walks more opener levels; no new flow object
   exists (`lazy-compile-design.md`).

3. **Join on just the innermost flow doesn't make sense.** Naming one
   flow where two terminations are owed and two operands are needed is
   not a program with two possible meanings — it is not a program.

In the textual syntax (`textual-representation-design.md`), a chained
`-~> join` merges the two innermost layers of the value's flow context,
inner into outer — no operands, because in a chain the inner operand can
only be the value's innermost unconsumed layer:

```
rows -> open list -> open list -> double -~> join -~> collect => flat
```

Flatten-map: two list levels collapse to one, then collect gathers the
flat list.

### The law of the combined flow

Stated once, for every operand-kind pair: **the combined flow fires
exactly when the inner operand fires** — the inner's firings, which
occur within the outer's, in time order. Everything the old debates
argued for follows as a theorem:

- **join(list, list)** fires per inner element — *flatten*. "Join never
  drops" is this law: nothing that fires is lost, and a non-firing was
  never a firing.
- **join(list, option)** fires per Some — *filter*. "Filtering is join
  at an option level" is this law with an option inner operand. There is
  no separate filter primitive.
- **join(option, option)** fires iff both fire — the `Option<Option<X>>`
  AND rule.
- **join(option, list)** fires per inner element, and not at all if the
  outer option never fired.

The implemented "any list in chain → list" output rule
(`lazy-compile-design.md`) is the *kind* half of the same law: the
combined flow is list-kind if either operand is list-kind (firing count
can exceed one), option-kind if both are options (zero or one firing).

### Why "does join drop the None?" was the wrong question

A None is a *non-firing*, and the law never mentions non-firings. Join
neither drops nor keeps them, because they were never firings of
anything. A Nones-kept output is not a property of join at all: it is a
property of *collecting* the option flow, which converts fired-or-not
into data. Which termination an option flow gets — absorbed by a join,
or collected into option data — is the program's explicit choice, made
per flow.

### Four programs, not one ambiguous stack

Data `[[2, 4], [6, 7], [8]]`, with flows O (outer list), I (inner list,
opened per O-element), and P (an option on `maybeEven`, firing with `n`
iff `n` is even, opened per I-element). The middle group `[6, 7]` is the
probe: it fires then doesn't — a *partial* failure, which is what
separates readings that agree on all-or-nothing groups. A complete
program terminates every flow, each by a collect or by being absorbed
into its parent via a join:

| program | output |
|---|---|
| collect P; collect I; collect O | `[[Some 2, Some 4], [Some 6, None], [Some 8]]` |
| collect P; join(O, I); collect the combined flow | `[Some 2, Some 4, Some 6, None, Some 8]` |
| join(I, P); collect the combined flow; collect O | `[[2, 4], [6], [8]]` |
| join(I, P); join(O, that); collect | `[2, 4, 6, 8]` |

The four as chains (option collected to data vs. absorbed by a join is
the only difference that matters):

```
[[2,4],[6,7],[8]] -> open list -> open list -> maybeEven -> open option
  -~> collect -~> collect -~> collect => a   -- [[Some 2, Some 4], …]
```
All three flows collected: nested options kept as data.

```
… -> open option -~> collect -~> join -~> collect => b
-- [Some 2, Some 4, Some 6, None, Some 8]
```
P collected to option data, then join(O, I) flattens the two list
levels: flat, Nones kept.

```
… -> open option -~> join -~> collect -~> collect => c   -- [[2,4],[6],[8]]
```
join(I, P) absorbs the option into the inner list — the *filter* — then
the per-group lists collect, then the outer list: grouping kept.

```
… -> open option -~> join -~> join -~> collect => d      -- [2,4,6,8]
```
Filter, then flatten across O: flat, filtered.

Every value here was reachable under both of the old rival algebras
(below), sometimes via auxiliary construction, because these were all
real programs. The algebras disagreed only about *notation*, which is
why the disagreement could not be settled semantically.

### Precedent and principle

The original filtering account (now in `core-model.md`, "Join, and
filtering as join") was already binary: filtering is a join of a partial
branch's flow with the list flow — two named operands. The wrapper-stack
notation lost that arity, and growing the design on the lossy notation is
what eventually produced the J/F fork below. Binary join also matches the
no-bottleneck principle (`language-design-philosophy.md`), which
characterises the concurrency join as a barrier with corresponding inputs
and outputs: the flatten join now has the same shape — explicit
corresponding inputs, an explicit output — rather than riding as an
annotation on a collect.

## What join means for streams

The list story transfers structurally. A collect on an inner stream flow
that lives inside an outer stream flow produces, by default, a
`stream<stream<X>>`: each outer cell yields one inner stream (the inner
flow's per-outer-element evaluation). Joining the two stream flows
flattens that to a single `stream<X>` whose cells are the inner-stream
values, concatenated across outer cells in order — exactly `List<List<X>>`
→ `List<X>` for the list case, one kind up.

```
rows -> open stream -> open stream -> f -~> join -~> collect => flat
```
Spelling provisional (stream opens/closes aren't implemented). Two
stream levels flatten to one.

Multi-level join generalises the same way: N chained joins flatten N
levels of nesting. In the wrapper era this was a nested
`join_(join_(…))`; it is now simply two binary join nodes, or two
`-~> join` stages in a chain.

Streams have no scopes or arrays, so the list compile's mechanism — a
joined close pushing into an output array allocated at a *different*
scope — has nothing to translate into directly. That contrast is why
this doc exists as its own note. But the semantics is the law above; only
the runtime realisation is stream-specific (see "Implementation" below).

## Effect on placement

Essentially none. A collect's *chain placement* — which chains feed it —
is unaffected by whether a join sits above it; that is fixed by the
level's lattice analysis (`lazy-stream-placement-design.md`) as usual.
The join nodes determine the collect's *output construction*: the
function turning the chain's per-cell records into the emitted stream
goes from a pass-through (stream-of-inner-streams) to a flatten (single
flat stream). The chains don't know they feed a flatten vs. a
pass-through — they just emit records; the flatten doesn't know it reads
from a structured chain — it just pulls cells. So the placement analysis
treats the join nodes as a property of output construction and ignores
them during chain partitioning.

### Worked example

Source `stream<(a, b)>` where `a` and `b` are lists. Per outer element an
inner stream flow opens `a` and emits two values per inner element:
`d = m*2` (output `D`) and `t = m*3` (output `T`). Outer has two collects:

- `outer.O1`: per outer element, fold `inner.D` into a list. No join.
  Output `stream<list<int>>`.
- `outer.O2`: join(outer, inner) carrying `inner.T` — flatten T-values
  across all outer elements. Output `stream<int>`.

**Inner placement** (per outer-element instance), lattice axes `{D, T}`,
unchanged by anything outer does — `decode m ∈ {D,T}`, `m*2 ∈ {D}`,
`m*3 ∈ {T}`. Three inner chains, same as the unjoined case: joining T's
*outer* consumer doesn't propagate down, because inner partitions depend
only on inner's outputs.

**Outer placement**, lattice axes `{O1, O2}`: `decode (a,b)`,
`listToStream(a)`, and inner-flow construction are all in `{O1, O2}`;
`inner.D`'s per-outer-cell stream ∈ `{O1}`; `inner.T`'s ∈ `{O2}`; O1's
fold-into-list ∈ `{O1}`; O2's value-feeding-the-flatten ∈ `{O2}`. Three
outer chains, exactly as in the all-unjoined version.

**Forcing pattern.** A consumer pulls O2's flat stream; the pull
interleaves outer and inner forces:

1. First pull → flatten asks the outer `{O2}` chain for outer cell 0 →
   forces outer `{O1,O2}` (decode + inner-construction) → reads
   `inner.T`'s stream for cell 0 (call it `t₀`).
2. Flatten pulls `t₀`'s first cell → forces inner `{T}` → forces inner
   `{D,T}` → emits the first t-value.
3. Subsequent pulls of O2 continue draining `t₀`.
4. When `t₀` is exhausted, flatten advances the outer `{O2}` chain to
   cell 1 → new stream `t₁` → drain it.

Inner's `{D}` chain never forces unless O1 is also pulled — `m*2` doesn't
run needlessly; if O1 is pulled, `{D}` forces independently at O1's pace.

## Implementation: no intermediate stream-of-streams

The naïve flatten builds a full `stream<stream<X>>` intermediate (one
inner stream per outer cell, chained), then flattens — an allocation that
compounds for multi-level joins. It can be avoided with `zipStream` and
the rest-as-`atNil` pattern.

`zipStream`'s `atNil` parameter is the value returned when its stream
ends. In the naïve flatten that is the terminator `SNil`, but it needn't
be: set `atNil` to "the rest of the flatten" (the next outer cell's
contribution) and the inner traversal transitions transparently from
emitting this inner stream's cells to continuing with the rest — never
materialising an intermediate.

```rescript
let rec flatten = outerStream =>
  zipStream(outerStream, ready(SNil),
    innerStream => restFlat =>
      // restFlat: Delayed<stream<X>> = the flatten of outerStream's tail
      // Traverse innerStream, then transition to restFlat.
      zipStream(innerStream,
        // atNil: when inner is exhausted, become the rest of the flatten.
        restFlat->Delayed.flatMap(s => s),
        // atCons: emit a cell; its tail is more inner cells, eventually
        // transitioning to restFlat when inner ends.
        (h, t) => ready(SCons(h, t->Delayed.flatMap(s => s)))
      )->Delayed.flatMap(s => s)
  )
```

Per cell of the flat output: two `Delayed`s (an `SCons` and a `zipStream`
recursion frame), no wrapper allocation per outer cell. The structure is
linear in the flat output's length, not in outer-length × inner-length.
Each additional join level adds one layer of `zipStream` recursion with
the level-above's `restFlat` as its `atNil` — still no extra per-cell
wrappers, cost still linear in total emitted cells.

### The skip mechanism

A non-firing element (a None) must advance the chain without emitting a
spurious cell. This is `lazy-stream-placement-design.md`'s "The skip
mechanism" (its open question 1), and it is needed exactly when a join
absorbs an option flow into a list/stream flow — the filter programs
(rows 3 and 4 above) — where the runtime becomes the rest at a non-firing
element, the same become-the-rest move the flatten makes at `atNil`.
Programs that instead *collect* the option flow (rows 1 and 2) carry data
and never skip. So join-with-an-option-inner owns the skip; it exists
regardless of how the operation is spelled.

## Mixed joined and unjoined collects

Each collect independently chooses join or not. They share the underlying
chains (the lattice analysis doesn't care about joins); their output
constructions differ — a join above a collect flattens, its absence
passes through. Two collects on one inner flow can have different join
depths — O1 joined one level, O2 joined two levels, O3 not joined — with
the same feeding chain and different post-chain construction.

## Zip-across-parents stays within a flow level

One might worry the multi-parent zip pattern (a sub-chain reading from
incomparable parents in the lattice) interacts with join — could a
sub-chain need to zip across different join depths? It can't. The
multi-parent zip arises when a sub-chain at level L has incomparable
parents *also at level L* — all chains over the same source iteration,
where zipping just means reading both at the same source cell. Different
join depths mean different flows, hence different source iterations;
chains across flows aren't zipped by the partition mechanism — they're
bridged by inner-output-as-outer-value, which is a value reference, not a
zip. So zip stays within a level and join is per-collect output
construction within a level: structurally independent, neither imposing
new constraints on the other. Commute is independent for the same reason
(`lazy-stream-commute-design.md`, "Commute and the multi-parent zip").

## Why the wrapper-stack notation was wrong

This records a dead end so it isn't re-walked. The earlier notation
attached join to the collect as a *wrapper stack* on the collect's flow
reference — `Joined(NodeFlow(optionIter))`, `Joined(Joined(NodeFlow))`,
and so on. That conflates two different kinds of node — the collect and
the join(s) — into one, and leaves implicit which flows each stage
terminates. Attaching a stack to a single named flow names one flow where
two terminations are owed and two operands are needed. It is not a program.

The tell was that the notation admitted two internally consistent but
incompatible readings, with no semantic ground to choose between them:

- **Spelling J** read the stack outward from the named flow: the
  collect's chain starts at its own opener, each `Joined` absorbs the
  next enclosing level. Under J, join crosses an option level with skip
  semantics — "filter is join at an option level," matching the
  implemented list compile.
- **Spelling F** read the named flow as collected immediately and the
  stack as staging over the enclosing layers. Under F, `Joined` merges
  stream/list layers only and is cardinality-preserving by definition;
  skipping is a separate `Filtered` stage that unifies the case-split
  filter and the option-skip under one name.

Two coherent algebras with no way to choose was the diagnosis, not a
choice to be made: the notation *underdetermined the program*. Binary
join dissolves the fork — the contested stack was an incomplete program,
and J and F were rival conventions for silently completing it. With join
stated at its proper arity, the contested rows become the four distinct
programs above. One vocabulary item from that analysis stays useful: a
value shape is **partial** when it is a may-not-fire output of a closed
option level — "a value where the option fired, nothing on the others."
Partiality is flow-level absence; `option<X>` is data. The two conflate
in the `undefined` encoding, but the design keeps them distinct, because
the whole question was which construct converts flow-level absence into
what — and the answer is: collecting an option flow does, join does not.

Two corrections to `lazy-stream-commute-design.md` fell out of this
round, and both have since been applied there (its "Composing Commuted
with Joined" section now distinguishes the per-group commute's
whole-groups-only result `[2, 4, 8]` from the filter-style sibling's
every-firing-element result `[2, 4, 6, 8]` — the `6` is the witness).
Kept here only as the record of where the correction came from; that
doc's composition sections still read in the older wrapper-stack
notation, to be re-read as programs over explicit join/commute nodes.

## Open questions

1. **Runtime composition of multi-level join.** The user-facing form is
   now two binary join nodes (or two `-~> join` stages), not a nested
   wrapper. Confirm the `zipStream`-with-rest trick composes cleanly at
   multiple levels — it should, each level nesting one more `zipStream`
   with the level-above's `restFlat` as `atNil`.

2. **Does commute become binary too?** `Commuted` consumed an enclosing
   stream layer against an option-shaped value — the same two-operand
   smell (the option flow, and the enclosing flow it commutes across). If
   commute is binary, the wrapper-stack notation retires entirely and
   `lazy-stream-commute-design.md`'s stack rows all translate to programs
   over explicit nodes.

3. **Representation.** `Expr.res` today spells join as a `flowRef`
   wrapper peeled by the collect. Binary join is a flow node with two
   flow inputs, and a collect references exactly one flow. Whether the
   unary spelling survives as sugar (the outer operand is derivable from
   adjacency) or is dropped (the sugar is what hid the missing
   termination) is an ergonomics choice. Taken up in
   `first-class-ports-design.md`: a `Join({outer, inner})` node with one
   flow output, inside a general per-kind port-inventory model that also
   dissolves Branch and `Filtered`; it stages the migration and records
   the unary-sugar question as its migration step 3's exit decision.

4. **Naming — all that remains of J vs F.** The law fixes the semantics
   of every operand-kind pair; what's left is whether option-inner
   absorption is surfaced under the name *join* or the name *filter* (as
   sugar for the same operation). The old visibility debate — read the
   drop-behaviour structurally off the diagram vs. one behaviour per name
   — deflates to vocabulary here: the diagram shows both operands and
   their kinds either way.

5. **What collecting an option flow yields** — option data, the
   `undefined` encoding, or a distinguished partial value — was already
   an open vocabulary point and is unchanged; it now sits on a single
   construct (collect-on-option) rather than being entangled with join.

6. **Multi-consumer completeness.** Flows admit multiple collects
   (multi-close); a flow may likewise be absorbed by one consumer's join
   while another consumer collects it. "Every flow terminated" reads per
   consumer path, as multi-close already does.

7. **Infinite inner streams.** Joining a stream of infinite inner streams
   produces an output stuck on the first inner. Mathematically reasonable
   but a footgun; no special handling, just documentation.

## What this doesn't address

- **Stream-to-list / list-to-stream conversion.** Not needed for join
  semantics — both sides of a join are the same kind.
- **Whether stream-join should exist at all.** Commute is the motivating
  stream operation. Join is convenient when you have nested stream flows
  and want them flat, but whether that pattern is common enough to bother
  with is unknown; defer until stream flows work for non-join cases.
- **Operations other than flatten that could be called "join."** Zip,
  interleave, and round-robin are all reasonable candidates. Flatten was
  picked because it mirrors the list case; the others would be new
  operations with their own names.
