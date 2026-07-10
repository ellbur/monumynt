# First-Class Ports

> Starting-point document (2026-07-07). The subject has sat at the
> top of the README's next-steps list since that list existed —
> "`compileExpr` conflates a node with its single value output
> port; Join and Branch already strain this" — and is taken up now
> because the pressure has stopped being hypothetical: the
> binary-join correction (`lazy-stream-join-design.md`, "Join is a
> binary flow operation") diagnosed the current `flowRef` wrapper
> spelling as the lossy notation behind a real design fork, and
> explicitly recorded the `Expr.res` representation as what it
> opens. This document collects the accumulated pressures, works
> out the port-level shape, and stages a migration. Nothing here
> is implemented.
>
> Terminology note (2026-07-09): written the day of the
> uncollect/collect renaming, this document uses Open/Uncollect
> and Close/Collect interchangeably — each pair names one node
> kind. Open/Close match the code's constructors; uncollect and
> collect are the settled design-level names.

## The conflation

`Expr.res` has two types: `expr` (a node, carrying an `id` and a
`kind`) and `flowRef` (a reference to a flow). The conflation is
that an `expr` in an input position *is* its own single value
output port — `app(f, [x])` wires "the value of node x" by passing
the node itself. `flowRef` half-separates the flow side:
`NodeFlow(e)` refers to "the flow output port of e" — but it names
the node, not a port, and works only because every node so far has
at most one flow output.

The conflation was the right call when the language was `Lit` and
`App`: one value out, no flows, nothing to name. Its cost is now
visible in the code as three artifacts:

1. **The Branch node.** A case split has a value output and a
   flow output *per alt*. One-value-port-per-node can't say "the
   Just alt's payload," so `Branch({source, alt})` exists to
   reify the selection as a node — a node whose entire content is
   a port name. The spec has no such node: its `Uncollect`
   CaseSplit variant carries `valueOutputs: {one per
   alternative}` and `flowOutputs: {one per alternative}`
   directly, and wires point at them by name.

2. **The `failwith` cases.** An `Open` or `Branch` reached as a
   value outside a consuming collect raises. The real rule is
   "this node's value port is per-iteration / per-alt and only
   exists inside a body of its flow" — a statement about a *port*
   that the compiler can only express as a runtime error on the
   *node*, discovered when `compileExpr` trips over it.

3. **The wrapper stack.** `Joined(flowRef)` and
   `Filtered(flowRef)` annotate a collect's one flow reference
   instead of being operations with their own inputs and outputs.
   The binary-join correction found this out the hard way: the
   stack names one flow where join needs two operands, the
   missing operand made two rival reading conventions (J and F)
   possible, and the fork could not be settled semantically
   because the notation underdetermined the program. Join is a
   flow operation with two flow inputs and one flow output — a
   node with ports — and the wrapper spelling is what hid that.

All three are the same missing concept surfacing three ways.

## The pressure inventory

Method as in the types and bundle-provenance documents: sample
what the design record actually demands, and let the requirement
emerge from the samples.

| Construct | Port structure needed | Where recorded |
|---|---|---|
| Open (list/option iter) | 1 flow out + 1 per-iteration value out | implemented (value side special-cased) |
| Open (case split) | per-alt value out + per-alt flow out | implemented via the Branch workaround |
| Join (binary) | 2 flow in, 1 flow out | `lazy-stream-join-design.md`, "Join is a binary flow operation"; spec's Join node |
| Filter | = join with an alt/option inner operand | same section (the law, row "join(list, option)") |
| Race barrier | N contender flows in; per-contender value + flow out | `async-flow-design.md`, open question 5 |
| Failable-flow discharging collect | per-outcome ports on one collect | `async-flow-design.md`, "Failure as terminator payload" residuals |
| `hold` / `changes` | kind-crossing: async-side ports and incremental-side ports on one node | `incremental-flow-design.md`, open question 7 |
| Commute node | flow ports only — zero value ports | spec, Commute section (reconciled 2026-07-05) |
| Delay | 1 value out (`prev`), inputs wired in two phases | spec, Delay section |

Three observations off the table:

- **Port inventories are per-kind and irregular.** Commute has no
  value ports; Delay has no flow outputs; the race barrier's
  outputs are per-contender pairs. There is no uniform "one value
  + maybe one flow" shape to conflate against — the current
  representation isn't a simplification of the table, it's a
  different table.

- **The strained constructs are exactly the barriers.** The
  no-bottleneck principle characterises joins and races as
  barriers "with pairwise-corresponding inputs and outputs."
  Corresponding inputs and outputs *are* ports; a representation
  without first-class ports cannot host a barrier except by
  packing (the tuple/tagged-union bottleneck the principle
  forbids) or by satellite nodes (Branch again, multiplied).
  Every future flow kind — async, incremental — arrives with
  barrier constructs in hand.

- **The checking documents already assume ports.** The types
  design attaches demands and offers to wires; bundle provenance
  compares per-wire context paths at demand time. A wire is
  "source port → input position." Today the value wires of
  flow-borne values have no structural source: an element value
  is the Open node itself, an alt payload is a Branch node minted
  per use site. The checking machinery's anchors don't exist in
  the representation it is supposed to check.

## The spec already answers this

The divergence is repo-local. `visual-language-spec.md` has had
the port concept from the start:

```
ValueSource:
  node: Node
  outputName: String

FlowSource:
  node: Node
  outputName: String
```

and every node kind declares its `valueOutputs` and `flowOutputs`
inventories. Against that spec, the Expr artifacts read as spec
machinery recreated in distorted form: Branch is a `ValueSource`/
`FlowSource` pair reified as a node because refs weren't
available; the wrapper stack is a chain of the spec's Join nodes
flattened into an annotation because flow-node inputs weren't
available. (The spec does have one selector-shaped node,
`IterationPayload` — but it exists for case-*specific* payload
that appears only after an `IterationCaseSplit`, not as a
workaround for naming; universal payload like `element` is a
plain output port on the Uncollect.)

So this is not a new design so much as closing a gap: deciding
what the spec's port model looks like at the Expr level, where
construction is programmatic ReScript rather than diagram data,
and what the compiler does with it.

## The Expr-level shape

The proposal, in the code's terms:

```rescript
type rec node = {id: int, kind: kind}
and valueRef = ValuePort(node, string)
and flowRef = FlowPort(node, string)
```

- Every input position that today takes an `expr` takes a
  `valueRef`; every flow position takes a `flowRef`.
- Each `kind` defines its port inventory — which names exist on
  which side. Single-output nodes (Lit, App, collect) have one
  value port, conventionally `"value"`; a list/option Open has
  `"flow"` and `"element"`; a case-split Open has a value port
  and a flow port per alt, named by the alt (whether that's the
  bare alt name on both sides or `(alt, Value)` / `(alt, Flow)`
  pairs is a naming-scheme detail); Join has `"flow"`.
- Variant constructors rather than records for the refs, because
  the two refs would otherwise want the same field names and
  top-level record types sharing field names trips Warning 30
  (the `imported`/`local` vs `exported`/`as_` convention).
- `node` identity works exactly as `expr` identity does now: two
  refs to the same node's same port are the same wire source;
  sharing is opt-in by binding the node once. Refs themselves
  stay structural and untagged, as `flowRef` is today.

### Strings below, types above

Port names as strings are spec-faithful, uniform, and printable
in error messages, but nobody should author against them — a
typo'd port name failing at compile-of-Expr time is strictly
worse than what we have. The answer is two-layered, and the
layers already exist in embryo:

- **The representation** uses named ports. This is the level the
  spec, the printer, the checker, and the eventual editor see.
- **The smart constructors** return typed handles, so ReScript
  authoring never spells a string:

```rescript
let it = listIter(xs)
// it.flow    : flowRef   = FlowPort(it.node, "flow")
// it.element : valueRef  = ValuePort(it.node, "element")
let sq  = app(square, [it.element])
let out = collect(it.flow, sq.value)
```

```rescript
let cs = caseSplit(alts, disc, input.value)
let j  = cs.alt("Just")   // {value: valueRef, flow: flowRef}
```

This is the "many authoring paths, few readings" split applied to
the host language: the handle layer is discoverability, the named
ports are the one reading. (The exact ReScript shape of the
handles — per-construct record types with distinct field names,
objects, a module per construct — is an ergonomics detail to
settle in code; `alt` as a function taking the alt name keeps the
handle type finite while alts are per-split data.)

## What dissolves

**Branch.** `branch_(source, alt)` today returns a node used two
ways: as a flowRef target (its flow output is the selected alt's
flow) and as a value (the alt's payload). Under ports both roles
are refs to the case-split node itself: `cs.alt("Just").flow` and
`cs.alt("Just").value`. Note what Branch also did, so it lands
somewhere: it was the *memoisation anchor* for per-alt payload
bindings — `collectBranchesByAlt` walks a collect's value
subtrees hunting Branch nodes whose `(source, alt)` matches, and
pre-memoises each one's id to the alt body's shared
`__lazyDone__(split.value)` binding. Under ports the anchor is
the `(splitNodeId, altValuePort)` pair, pre-memoised directly —
the hunting walk disappears, because every use site already
references the same port of the same node instead of its own
freshly-minted Branch.

**Joined and Filtered.** Both become the binary Join node:

```rescript
| Join({outer: flowRef, inner: flowRef})
```

with one flow output. A collect names exactly one flow (per the
correction); multi-level flatten is a chain of Join nodes; filter
is Join with an alt flow (or option flow) as the inner operand —
the law's `join(list, option)` row, so `Filtered` stops being a
separate concept in the representation. Whether the *authoring*
layer keeps `filter_` as a named sugar for that operand pattern
is the vocabulary question the correction already recorded
(naming, "all that remains of J vs F") — sugar is free once the
representation is right.

One divergence from the spec's Join to flag rather than bury: the
spec's node carries corresponding value ports (`values` in, same
names out) — the no-bottleneck barrier shape, so the diagram
shows where values cross the nesting boundary. The Expr compile
never needed explicit crossings: a collect's value expression
just references per-element bindings, and memoised laziness plus
placement does the transport. The smaller step is a flow-only
Join node at the Expr level, accepting that value crossings stay
derived rather than represented. The checking story survives this
— bundle provenance dissolved its relational look into per-wire
context paths compared at demand time, and those paths are
computed from flow structure, not read off crossing ports. But if
a check ever genuinely needs represented crossings, the spec
shape is where to go, and the port representation is what makes
that a local upgrade instead of a rewrite. Recorded as an open
question.

**The failwith cases** stop being scattered. "Is this ref valid"
becomes one uniform question — does the target node's kind have
that port — checkable in one place at Expr-construction or
compile entry, instead of `failwith` branches discovered when
`compileExpr` reaches the node. The deeper rule ("a per-iteration
value port is only referenceable from inside a body of its flow")
stays a compile-time placement concern, but it becomes *statable*
— see "What becomes checkable" below.

## What the compiler changes

Mechanically modest; the thunk shapes and the emitted JS are
unchanged. The touched machinery:

- **Memo keys.** `ctx.memo: Map<int, …>` keys on node id; it
  becomes `(id, portName)` (or a nested map). Lit/App entries are
  unaffected in substance (their one port). The per-alt and
  per-element pre-memoisation writes `(openId, "element")` /
  `(splitId, alt-value-port)` instead of Open ids and hunted
  Branch ids.

- **Chain walking.** `unwrapJoinedRef` (peel wrappers, count
  depth) and `walkOpenerChain` (follow each level's input up)
  merge into a walk over Join nodes: from the collect's one
  flowRef, a Join node contributes its inner and outer operands,
  an Open terminates a level. The "any list in chain → list"
  output rule reads directly off the operand kinds — it is the
  law's kind half, and the walk now sees the operands the law is
  stated over. Nesting-adjacency of Join operands (the
  correction's well-formedness requirement) is checked in the
  same walk; today's ad-hoc `emitFilterClose` requirement that
  the case split's input sit inside a list iteration becomes an
  instance of it.

- **Collect dispatch.** Today: examine the *shape* of
  `branches[0].flow` after peeling wrappers (a NodeFlow(Branch) ⇒
  case, a Filtered ⇒ filter, …). Under ports: examine the kind
  and port the flowRef names — an Open's iter flow ⇒ iter
  collect; a case-split's alt flows ⇒ case collect; a Join's
  output ⇒ walk the operands. Same dispatch, read off structure
  instead of reconstructed from wrapper shapes.

- **ExprPrint.** Shared-node labels `#N` grow a port suffix where
  a node has more than one (`#3.Just`, `#3.flow`); single-port
  nodes print as today.

## What becomes checkable

The README's second next-step ("well-formedness checks") has been
waiting on this one; the dependency is now statable precisely.
Ports give every wire a structural source `(node, port)`, and
per-kind inventories say which sources exist and which are
flow-borne (per-iteration, per-alt). That is the anchor set for:

- **Ref validity by construction.** The typed-handle layer makes
  "flowRef to a node with no flow port" and "value ref to the
  wrong alt name" unwritable in ReScript; the representation
  check is one inventory lookup.
- **Join operand adjacency.** Checkable by the chain walk, as
  above.
- **Time travel and closed-scope leakage.** Both are "a
  flow-borne value port referenced from a body not inside that
  flow" — currently trusted (the honoured-limitations list) or
  structurally guarded only via the memo's ancestor check. With
  flow-borne-ness a property of the *port*, the check is a
  reachability question over the collect being compiled, not an
  emergent property of memo placement.
- **Provenance paths.** Bundle provenance's per-wire context
  paths get real wires to attach to; the alt segment of a path is
  literally the alt port name the wire hangs off.

None of these checks is implemented by this design — but all of
them are blocked without it, which is why they've stayed on the
trusted list.

## Against the philosophy

- **No bottlenecks.** Ports are what "pairwise-corresponding
  inputs and outputs" means representationally. The barrier
  constructs the principle mandates (concurrent join, race) are
  unrepresentable in the conflated form except by the packing the
  principle forbids. This design is the principle's
  representational prerequisite.
- **Abstraction is the source of truth.** The philosophy already
  speaks port vocabulary: "you build on a derived view *by
  referencing its ports*." Derived views with port
  correspondences — the whole lens discipline of
  `transformation-levels-design.md` — presuppose ports as
  first-class referents.
- **Building blocks at the programmer's abstraction level.**
  Branch is machinery *below* the programmer's vocabulary: no one
  thinks "now insert a port-selection node"; they think "the Just
  alt's payload." The alt port is the programmer's level; the
  node was plumbing showing through.
- **Foundations before features.** Race, `hold`/`changes`, the
  failable discharging collect, and the checking machinery all
  cited this as their missing substrate. One representation
  round now is cheaper than four workaround rounds later — that
  is the principle verbatim.

## Migration, in baby steps

Each step keeps the 80 tests green; test spellings migrate with
the smart constructors, so most churn is mechanical.

1. **valueRef, trivially.** Introduce `valueRef` as
   `ValuePort(node, "value")` and thread it through every input
   position. No node dissolves, no behavior changes; `lit`/`app`
   etc. return handles whose `.value` is the ref. Pure
   plumbing — the point is to make step 2 and 3 diffs about
   their subject.
2. **Per-alt ports; Branch dissolves.** Case-split Opens get
   per-alt value and flow ports; `branch_` becomes sugar
   returning the `{value, flow}` handle for an alt (constructing
   no node); `collectBranchesByAlt` collapses to direct port
   memoisation. Case collects and filter collects reference alt
   ports.
3. **Binary Join nodes; wrappers dissolve.** `Join({outer,
   inner})` lands; `join_`/`filter_` become sugar minting Join
   nodes; `unwrapJoinedRef`/`walkOpenerChain` become the operand
   walk. During migration the unary sugar can derive the outer
   operand from the input structure it already holds — whether
   that sugar *survives* is the correction's recorded ergonomics
   question, decided at the end of this step with the
   representation in hand.
4. **Checks, opportunistically.** The inventory-lookup validity
   check and the join-adjacency check are small once 2 and 3
   land; the flow-borne reachability check (time travel /
   leakage) is its own piece of work and can wait for the types
   round.

Steps 2 and 3 commute; 2-then-3 is preferred only because Branch
is the more local dissolution and exercises the port memoisation
that 3's walk then relies on.

## The Delay back-edge: the write half is a node (taking up open question 6) (2026-07-07)

> Open question 6 below records that the spec's Delay wires `step`
> in a second act after `prev` is already referenced, and that Expr
> construction — immutable and bottom-up — cannot perform a second
> act on an existing node "without mutation, a tie-the-knot, or
> symbolic indirection." This section works the question out. The
> answer is a fourth escape the list didn't name: move the edge,
> not the node. It belongs to the iteration-state round in subject
> matter (both candidates there need it, as the open question
> says), but it is a fact about this representation, so it is
> worked out here; `iteration-with-state-design.md` gets pointer
> notes.

### The three named escapes fail for cause

- **Mutation.** At the diagram level, "wire `step` later" is a
  field assignment on mutable diagram data — an ordinary editing
  gesture, which is why the spec can say it casually. Expr nodes
  are immutable records; there is no second act to perform. A
  mutable cell smuggled into the node for `step` alone would make
  Delay the one node whose meaning can change after construction —
  and every consumer of Expr (printer, memo, future checks)
  currently assumes it can't.
- **Tie-the-knot.** `let rec` with deferred evaluation can build a
  cyclic immutable structure — but the port form's supersession of
  the lambda form counted "no `let rec`, no deferred evaluation,
  no circular value dependency at construction time" among its
  gains. Buying construction back with host-language laziness
  re-imports the lambda form's machinery with less visibility than
  the lambda had.
- **Symbolic indirection.** The spec discarded `ById` references
  when it superseded IterationRail — "replaced by an honest
  back-edge." Resurrecting id-as-reference at the Expr level would
  undo exactly that supersession, and would make Delay the one
  place in Expr where a reference is not a structural pointer.

### Read the wiring analogy literally

Both documents justify the two-phase wiring by the same analogy:
`step` is wired "as a separate, later act — the same two-phase
pattern as wiring a Collect to its Uncollect." Look at *why*
Collect-to-Uncollect needs none of the three escapes at the Expr
level: **the late edge is held by a new node.** The Open is never
revisited; the Close, constructed last, carries every edge of the
wiring act — the flow it closes, the value it collects. The
object graph stays a DAG even though the computation is circular
in the informal sense (the element the Open provides is used in
the value the Close consumes; the pairing carries that loop, not
any forward pointer).

The analogy breaks for Delay only because the spec puts the late
edge *inside the existing node* — `step` is a field of Delay. So
make the analogy literal instead of approximate: the later act
mints its own node.

### The shape

The Delay splits into a read half and a write half (names
provisional — tap/writeback in the rail vocabulary would also do):

```
DelayRead:                      DelayWrite:
  flow: FlowSource                read: (the DelayRead node)
  init: ValueSource  (outside)    step: ValueSource  (per-iteration)
  valueOutputs: {prev}            valueOutputs: {final}
```

Construction is bottom-up with no second act on any node:

1. Mint the read half — its `flow` and `init` are known up front.
   `ValuePort(read, "prev")` exists immediately.
2. Build the step expression, referencing this read's `prev` and
   any other reads' `prev`s (cross-reference needs nothing extra:
   mint all the reads first, then build all the steps).
3. Mint the write half last, holding the read reference and the
   step.

The object graph is a DAG unconditionally — Fibonacci included.
The back-edge — the `step → prev` crossing, the language's one
iteration-boundary edge — is recovered from *identity*: the write
names its read, and the compiler and the productivity check treat
the pair as the crossing. The productivity condition restates
verbatim with "the Delay's internal `step → prev` edge" read as
"the pairing edge write → read."

How the write names its read is a spelling choice with a wrinkle
worth recording: a bare node reference (as `flow` names a node
today) is the lean; the alternative is a dedicated port on the
read half — call it the *register* or *thread* port — that the
write half consumes, making the read-to-write connection a wire
of its own species. The alternative is resonant: the
iteration-state doc's fourth option wants the state's history to
be "a path in the picture," and a thread wire from read to write
*is* that path's rail, present in the representation rather than
reconstructed by the renderer. It also turns the one-write rule
into wire linearity (the thread port is consumed exactly once).
Deferred to the naming question; the pair works identically under
either spelling.

### The exit anchor comes for free

What is the write half's output? The record answers before the
question is asked. The rail notes: the final value is "available
as a normal solid wire emerging from the right end of the rail."
The thread proposal: the thread "**exits** as the final value — a
first-class endpoint, not a separate close bolted on." But the
contracted Delay node has `valueOutputs: {prev}` and
`flowOutputs: {}` — the point projection kept three of the
thread's four anchors (enter/`init`, tap/`prev`,
writeback/`step`) and *lost the exit*. Nothing in the record says
how a program reads a fold's total out of the Delay form: the
latent form's expose (a collect on the combined flow) isn't
available because Delay emits no flow, and collecting the `step`
values into a list and taking the last element is a distortion
that materialises the whole history and gets the empty case wrong
(zero iterations should yield `init`; the collected list is
empty). The write half is where the exit was hiding: `final` is
the register's value after the flow completes — the last `step`,
or `init` if no iteration ran, which grounds the empty case
exactly as `init` grounds productivity.

The pair's port signature is Open/Close transposed to the
register:

| | outside in | per-iteration out | per-iteration in | outside out |
|---|---|---|---|---|
| collection | source (Open) | element (Open) | value (Close) | result (Close) |
| register | `init` (read) | `prev` (read) | `step` (write) | `final` (write) |

Each half converts across the flow boundary in one direction: the
read half brings an outside value in as the tap; the write half
takes a per-iteration value out as the total. The state thread's
four anchors are exactly the pair's four ports, two per node —
which is what "the thread's endpoints" should mean
representationally. The stored-form arrangement the thread
section leans toward ("store the Delay quotient, render the
thread") gets a quotient with all four anchors to render from,
instead of one missing the right end of the rail.

`final` is the *total*, not the *running* value. Exposing the
running sum stays an ordinary close over per-iteration values, so
the total-vs-running distinction the elaboration discussion
insisted on (reduce-close must not persist as "augment + expose
final") survives untouched.

### Facing the terminal-node critique

The record counted "no matched open/close pair; no terminal node
with no output" among Delay's virtues, and the port form's
superseding note says "there is no separate feedback node at all
… so nothing output-less exists." Doesn't a write node
un-supersede the stateful-collect? No. The recorded discomfort
was *outputlessness* — "previously, every node was a producer.
Stateful-collect is a pure consumer" — not pairedness; the
language is made of pairs. The write half is a producer, and its
output is one the one-node form turns out to need and not have.
What the stateful-collect got wrong was terminating; what it got
right — a distinct node for the writing act — is what
constructability forces back.

What survives as a cost: the one-write-per-read constraint
changes character. On the one-node form it is local — "is the
`step` field wired." On the pair it is a whole-graph counting
check: exactly one write references each read. But the record has
already made peace with exactly this — "one variable has one
write slot; two writes conflict" was called structural, and the
well-formedness family (alt matching, no-crossing, productivity)
consists precisely of quotient constraints "enforced as a check,
not by construction." The write-count check joins that family.
(And under the thread-port spelling it is wire linearity rather
than counting.)

### What it forces to the surface: the program is a node set

One genuinely new consequence. A write half is reachable from a
program's root only through `final`. Consider Fibonacci consumed
one-sided: the result references `final` of register *a* only;
`step_a` reads `prev_b`, so register *b* must advance every
iteration — but *b*'s write half hangs off nothing downstream.
Walking inputs from the root never finds it. So a compile that
encounters a foreign `prev` needs a **write index** (read-node id
→ write node) built by a pre-pass — the `collectBranchesByAlt`
move — except the index *cannot* be built from the root
expression when a write is root-unreachable.

This is a forcing argument for a README next step that has so far
been motivated only by spec fidelity: **diagrams as the top-level
structure.** The spec keeps an explicit `nodes` set and justifies
it by editing-time disconnection; the write half makes the node
set necessary for *complete* programs. A program with loop-carried
state is a node set with distinguished outputs, not a root
expression. The interim spelling is honest and small: the compile
entry takes the writes alongside the root
(`compileToBody(root, ~writes)`), which states the requirement
without building Diagram yet.

*(2026-07-10: the node-set consequence now has a field bug class
behind it. The concurrency survey — `real-loop-survey.md`,
survey 3, finding 3.4 — drew a spawned companion task carrying the
comment "Keep a hard reference to prevent garbage collection" with
a production incident link: asyncio holds tasks weakly, so a
complete, running program whose parts are unreachable from any root
gets collected mid-flight. Root-reachability as the definition of
the program is not just insufficient for Delay write halves; it
loses live tasks in mainstream runtimes today.)*

### The latent-flow crossover

Both candidates needed the back-edge answer, per the open
question; the crossover is more than that. The iteration-state
doc's unresolved item "which side of the feedback collect the
combined flow comes out of" records a forced choice between two
discomforts: combined flow out of the feedback collect →
cross-referencing accumulators cycle among the augmentations;
combined flow out of the uncollect → the feedback collect is
again a terminal node with no output. The write half's lesson
dissolves the second horn: the feedback collect's output does not
have to be the combined flow to be an output — it can be the
**final value**. Combined flow out of the uncollect (no cycle),
final value out of the feedback collect (no terminal node).
Whether the latent form wants that arrangement is that
candidate's call, and nothing here makes it; but the either/or as
recorded is no longer exhaustive.

### Against the philosophy, briefly

Inside-out: unchanged — no scope is introduced; `prev` and
`final` are wires. No bottlenecks: unchanged — two registers are
two pairs, no packing. Example first: the link transformation's
steps *are* the construction order (the concrete step expression
exists before the write half that generalises it). Abstraction as
source of truth: the thread renders over the stored pair, and the
pair — unlike the three-anchor contraction — contains everything
the thread draws.

### Effect on the migration

None on steps 1–4; the pair lands with the iteration-state
round, not with this document's migration. It presupposes step
1's `valueRef` (the write's `step`, everyone's reads of `prev`
and `final`) and nothing else.

### What stays open

- **Diagram-level shape.** Does the spec keep one Delay node,
  with the pair as its Expr-level form — or adopt the pair? Either
  way the spec's inventory needs a home for `final`, which it
  currently lacks. The thread's result-level-status question gets
  a sharper referent: the quotient stored is the pair.
- **Naming, and the pairing spelling.** read/write vs
  tap/writeback; bare node reference vs thread port (above);
  whether the pair renders as one glyph (the rail) regardless.
- **Multiple writebacks.** The thread's open point (conditional
  carry, multi-site update) is unchanged; if conditional carry is
  ever a second write node rather than a conditional value into
  one write, the counting check is where it lands.
- **`final` on self-driven streams.** A Fibonacci with no external
  source never finishes, so its `final` is never available.
  Demand-time error, type-level impossibility, or a thunk that
  never returns — belongs to the iteration-state round's
  self-driven-stream story.

## Open questions

1. **Port-name scheme.** Strings at the representation level is
   the lean (spec-faithful, printable); but per-alt ports need a
   convention (`"Just"` bare on each side vs `("Just", Value)` /
   `("Just", Flow)` pairs), and the scheme should match what the
   spec's `outputName` would say so the two levels never need a
   translation table.
2. **Join node identity vs today's structural flowRefs.**
   `flowRef` values today are untagged and equal-by-shape; a Join
   *node* has an id. Two syntactically identical joins of the
   same operands are then two distinct combined flows. For the
   list compile this is mechanically irrelevant (each collect
   walks independently), and multi-consumer completeness (one
   consumer joins a flow while another collects it) positively
   wants distinct join sites to be distinct. But if stream chain
   sharing ever keys off flow identity, "bind the join once and
   reuse it" vs "each collect mints its own" becomes observable
   in chain count. Decide when stream flows land; until then,
   convention: bind once, like any shared node.
3. **Value pass-through ports on Join.** Flow-only at the Expr
   level (the lean, matching the compile) vs the spec's
   corresponding value ports (represented crossings). Revisit if
   a check ever needs crossings represented, or when the
   concurrent join arrives — the async barrier genuinely
   transports values, and it would be odd for the flatten join
   and the concurrent join to disagree on port shape for no
   semantic reason.
4. **Does commute become binary too?** Recorded by the join
   correction; under this design the answer has a concrete home —
   a Commute node with two flow inputs (the option-ish flow and
   the enclosing flow it commutes across) and flow outputs per
   the spec's reconciled node, all expressible once ports exist.
   The stream-commute doc's wrapper-stack rows would then be
   re-read as programs over explicit nodes, as that doc already
   anticipates.
5. **Handle-layer ReScript shape.** Per-construct record types
   (field-name discipline for Warning 30), objects, or a module
   per construct; and whether `caseSplit(…).alt` should be total
   (option-returning) or trusting (raising on a bad alt name)
   given alts are per-split data.
6. **Delay's back-edge.** The spec's Delay wires `step` in a
   second act after `prev` is already referenced — but Expr
   construction is immutable and bottom-up; a back-edge is
   unconstructable without mutation, a tie-the-knot, or symbolic
   indirection. This belongs to the iteration-state round (both
   candidates need an answer), but it lands on this
   representation, and ports are what make "the `prev` output
   exists before `step` is wired" sayable at all. *(2026-07-07:
   taken up — see "The Delay back-edge: the write half is a node"
   above. The escape the list didn't name was to move the edge:
   the later wiring act mints its own node, as Close does, holding
   the step and outputting the final value — the thread's exit
   anchor, which the one-node contraction had lost. Residue
   recorded there: diagram-level shape, naming/pairing spelling,
   the write-count check, `final` on self-driven streams.)*

## What this doesn't address

- **The visual side.** Ports on the canvas are the spec's
  business and already specified (`ValueSource`/`FlowSource`,
  per-kind inventories). This document is the Expr level catching
  up, not a change to the diagram model.
- **The barrier constructs themselves.** Race, the concurrent
  join, `hold`/`changes`, and the failable discharging collect
  each still need their own design/implementation rounds; this
  removes their shared representational blocker, nothing more.
- **Iteration state.** The Delay-vs-latent-flow choice is
  untouched. The back-edge construction both candidates need is
  now worked out above ("the write half is a node"), and one horn
  of the latent form's feedback-collect dilemma dissolves as a
  crossover — but nothing above picks between the candidates.
- **Diagrams as top-level structure.** The spec's Diagram
  boundary nodes (`DiagramValueInput` and friends) are ports of a
  different flavour (a diagram's own interface); related, on the
  README's list, separate.
- **The compile strategy.** Runtime laziness, placement,
  memoisation semantics — all unchanged; this round renames what
  the existing machinery keys on and walks over.
