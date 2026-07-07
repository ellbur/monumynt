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
   exists before `step` is wired" sayable at all.

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
  untouched; only the back-edge wiring note above crosses over.
- **Diagrams as top-level structure.** The spec's Diagram
  boundary nodes (`DiagramValueInput` and friends) are ports of a
  different flavour (a diagram's own interface); related, on the
  README's list, separate.
- **The compile strategy.** Runtime laziness, placement,
  memoisation semantics — all unchanged; this round renames what
  the existing machinery keys on and walks over.
