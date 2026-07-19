# Visual Programming Language: Data Representation Specification

## Overview

This is the diagram-level specification of how programs are represented:
what nodes exist and how they connect. The representation is:

- **Structural, not semantic.** It describes what nodes exist and how
  they wire together, not which programs are valid. Validity — type
  correctness, flow-nesting correctness, collect coverage — is a
  separate layer built on top.
- **Nested.** An input points to an output of another node, so the
  program is a directed graph traversed by following pointers.
- **Language-agnostic.** Described with common constructs (structs,
  unions, lists, maps, sets).

A program separates two sorts of wire:

- A **value wire** carries data — an element, a branch's payload, a
  result. Values are computed on and transformed.
- A **flow wire** carries iteration/branching *context*: when, and how
  often, something happens. Flow wires are read only by flow operations
  (collect, join, commute); a flow wire cannot be read as a value.

Both are the same structural thing — a connection from an input port to
an output port — but keeping the sorts distinct makes misuse
unrepresentable: you cannot apply a function to a flow, because a flow
is not a value.

Code samples throughout use the textual syntax of
`textual-representation-design.md`, glossed one line each. The textual
form is a projection of exactly these nodes and ports — a compact way to
show what a construct looks like when written down.

**Scope.** This spec describes the full diagram model. The implemented
layer (`src/Expr.res`) is a smaller fragment with its own representation
debts; its migration to first-class ports — dissolving Branch and the
`Joined`/`Filtered` wrappers into alt ports and binary Join nodes — is
worked out in `first-class-ports-design.md`. An earlier IterationRail /
TapIn / TapOut machinery for loop-carried state has been removed
(schemas remain in git history); why it died is recorded under Delay,
and the still-usable rail ideas are kept in
`iteration-rails-design-notes.md`.

---

## Primitive Identifiers

```
DiagramId: unique identifier for a diagram
OperationName: identifier for built-in or named operations
FieldName: identifier for struct fields
AlternativeName: identifier for alternatives in a disjoint union
ParamName: identifier for function parameters
FlowParamName: identifier for flow parameters
SlotName: identifier for diagram slots
SplitName: identifier for iteration case splits
CaseName: identifier for cases within a split
```

---

## Diagrams

A **Diagram** is a reusable sub-program with defined inputs, outputs, and
optionally slots where sub-diagrams can be supplied.

```
Diagram:
  id: DiagramId
  name: String
  valueInputs: List<{name: String}>
  valueOutputs: List<{name: String}>
  flowInputs: List<{name: String}>
  flowOutputs: List<{name: String}>
  slots: List<{name: String, signature: SlotSignature}>
  nodes: Set<Node>
```

The `nodes` field contains all nodes in the diagram. In a complete
diagram most nodes are reachable by recursively following sources back
from the `DiagramValueOutput` and `DiagramFlowOutput` nodes, but the
explicit set accommodates partially constructed diagrams during editing.
It is load-bearing for complete programs too: a Delay's write half can be
root-unreachable, so **the program of record is a node set, not a root
expression** (`first-class-ports-design.md`, "the program is a node
set").

**Slots** let a diagram have "cut-outs" where caller-supplied
sub-diagrams are inserted. This enables configuration scopes and similar
patterns.

```
SlotSignature:
  valueInputs: List<{name: String}>
  valueOutputs: List<{name: String}>
  flowInputs: List<{name: String}>
  flowOutputs: List<{name: String}>
```

In the textual form a diagram declares its boundary ports explicitly; an
output is a statement, not an implicit "last expression":

```
diagram sumOf
  in xs
  xs -> open list => a, ~L
  ~L ~> delay init 0 => sum
  sum, a -> add -> step of sum => t
  out total = t
end
```

---

## Nodes

A **Node** is an operation in the diagram. Its kind determines its
behavior and its port structure.

```
Node:
  kind: NodeKind
```

Nodes have named input and output ports for both values and flows. Which
ports exist depends on the node kind.

---

## Sources

Sources are the nested pointers from inputs to outputs.

```
ValueSource:
  node: Node
  outputName: String

FlowSource:
  node: Node
  outputName: String
```

A `ValueSource` points to a value output port on another node; a
`FlowSource` points to a flow output port. In the text these are just
references: a bare name denotes a node's principal value port, `~name`
its principal flow port, and `name.Alt` / `~name.Alt` project to a named
port.

---

## Node Kinds

### Literal

Produces a constant value.

```
Literal:
  value: LiteralValue

  valueOutputs: {value}
  flowOutputs: {}
```

Written as the value itself, or via the extern escape hatch:

```
5                       -- an integer literal
double = js "x => x * 2"   -- an extern (a JsAst expression), named
```

---

### Primitive

Applies a built-in operation to inputs.

```
Primitive:
  op: PrimitiveOp
  inputs: List<ValueSource>

  valueOutputs: {result}
  flowOutputs: {}
```

```
a, b -> add             -- add(a, b); topic-first: -> add(b) means add(a, b)
```

---

### Aggregate

Combines field values into a struct.

```
Aggregate:
  structType: StructType
  fields: Map<FieldName, ValueSource>

  valueOutputs: {struct}
  flowOutputs: {}
```

---

### Disaggregate

Splits a struct into its field values.

```
Disaggregate:
  structType: StructType
  input: ValueSource

  valueOutputs: {<one per field in structType, named by FieldName>}
  flowOutputs: {}
```

---

### FunctionCall

Invokes another diagram.

```
FunctionCall:
  function: DiagramId
  args: Map<ParamName, ValueSource>
  flowArgs: Map<FlowParamName, FlowSource>
  slotImplementations: Map<SlotName, DiagramId>

  valueOutputs: {<defined by function's valueOutputs>}
  flowOutputs: {<defined by function's flowOutputs>}
```

`slotImplementations` supplies sub-diagrams for any slots the called
function defines.

---

### Uncollect

Creates a flow by "opening" an iteration, case split, or configuration
scope. (*Uncollect* is the operation that turns a value into a flow: a
list opens into a per-element flow, a case-typed value into a bundle of
case flows.)

```
Uncollect:
  variant: UncollectVariant
  inputs: List<ValueSource>
  outerFlows: List<FlowSource>

  valueOutputs: {<depends on variant>}
  flowOutputs: {<depends on variant>}
```

`outerFlows` lists the existing flows this new flow is "inner" to, from
outermost to innermost. It must be explicit because:

1. It cannot always be inferred from value inputs — especially when
   there are no value inputs.
2. The encoding must not depend on a computation step like tracing up
   the diagram.

**UncollectVariant:**

```
UncollectVariant:
  | Iteration(operation: OperationName)
      valueOutputs: {<universal payload fields>}
      flowOutputs: {flow}

  | CaseSplit(alternativeType: AlternativeType)
      valueOutputs: {<one per alternative, named by AlternativeName>}
      flowOutputs: {<one per alternative, named by AlternativeName>}

  | ConfigScope(diagram: DiagramId, slotName: String)
      valueOutputs: {<slot's valueInputs>}
      flowOutputs: {flow}
```

For `Iteration`, the input is typically a collection (list, tree, …).
The value outputs are the **universal payload** — fields available at
every position regardless of case (e.g. `element` for a list). The flow
output is the iteration context. Case-specific payload fields are reached
via `IterationPayload` after case-splitting.

For `CaseSplit`, the input is a value of an alternative type; the outputs
are the payload and flow for each alternative.

For `ConfigScope`, the inputs are whatever the diagram requires; the
outputs are what the slot expects, plus an opaque flow representing the
suspended scope state.

The flow kind is part of the node — chosen explicitly, never inferred:

```
xs -> open list => a, ~L                  -- element `a`, flow `~L`
m  -> open option => v, ~O                -- fires with `v` iff Some
r  -> split isJust of Just, Nothing => cs -- CaseSplit; alt ports on `cs`
ys -> open list in ~L => y, ~Y            -- explicit outer-nesting (outerFlows)
```

The `in ~L` clause is `outerFlows`. When nesting is implied by the value
input (opening a value that is itself per-iteration), it is omitted; when
neither implied nor stated, the program is under-committed and the editor
completes it.

---

### Collect

Destroys a flow by "closing" an iteration, case split, or configuration
scope. (*Collect* terminates a flow and produces a value — a list flow
gathers its per-element values back into a list; a case flow supplies one
value per alternative.)

```
Collect:
  variant: CollectVariant

  valueOutputs: {result}
  flowOutputs: {}
```

**CollectVariant:**

```
CollectVariant:
  | Iteration(operation: OperationName, value: ValueSource, flow: FlowSource)

  | Case(alternativeType: AlternativeType, branches: Map<AlternativeName, {value: ValueSource, flow: FlowSource}>)

  | ConfigScope(diagram: DiagramId, slotName: String, slotOutputs: Map<String, ValueSource>, flow: FlowSource)
```

For `Iteration`, the inputs are the computed value and flow; the output
is the collected result (e.g. a list). For `Case`, each branch supplies
its computed value and flow; the output is the recombined alternative
value. For `ConfigScope`, the inputs are what the slot produced plus the
flow; the outputs are what the diagram produces.

An iteration close, and a case close gathering its lanes:

```
a -> double -~> collect => out    -- close a list flow, gather into a list

maybes -> open list -> split isJust of Just, Nothing
  Just:    -> double
  Nothing: 0
-~> collect                       -- the case close: gathers the lanes
-~> collect                       -- closes the list flow
=> out
```

The `-~>` arrow marks a value crossing *together with its flow*, which is
what a collect consumes.

---

### Bundle

Combines multiple flows into a single bundled flow.

```
Bundle:
  count: Int
  flows: List<FlowSource>

  valueOutputs: {}
  flowOutputs: {bundle}
```

`count` says how many flows are bundled; `flows` must have exactly that
many elements.

---

### Unbundle

Splits a bundled flow into its constituent flows.

```
Unbundle:
  count: Int
  bundle: FlowSource

  valueOutputs: {}
  flowOutputs: {<count many, named by index: "0", "1", ..., "(count-1)">}
```

---

### Join

Collapses flow nesting, moving values from an inner flow context to an
outer one. Flattening a nested list is a join of a list flow with a list
flow; **filtering** is a join of a list flow with a case-alt flow (keep
the elements where the alt fires) — there is no separate filter
primitive.

```
Join:
  variant: JoinVariant
  innerFlows: List<FlowSource>
  outerFlow: FlowSource
  values: List<{name: String, source: ValueSource}>

  valueOutputs: {<same names as input values>}
  flowOutputs: {flow}
```

**JoinVariant:**

```
JoinVariant: OperationName
```

Different variants implement different joining behaviors (standard join,
filter join). The output values correspond 1-1 with input values (same
names); the output flow is the outer flow after the join.

In a chain, join is operand-free — it merges the two innermost layers,
inner into outer:

```
rows -> open list -> open list -> double -~> join -~> collect => flat
                                          -- flatten-map: two list levels → one

xs -> open list -> split parity of Even, Odd
  Even: -~> join -~> collect => evens     -- filtering as join of list × alt flow
  Odd:  -~> join -~> collect => odds
```

**Design note — the binary form.** Join is a **binary** flow operation
with asymmetric operands, an outer and an inner (`lazy-stream-join-design.md`,
"Join is a binary flow operation"). Multi-level joins are *chains* of
binary joins, not one node carrying several `innerFlows`. Whether the
node keeps value pass-through ports at all is
`first-class-ports-design.md` open question 3: the lean is **flow-only**,
with values meeting the join only at collects, and the concurrent join is
the case that could justify keeping the ports. The crossing analysis
(`barrier-value-crossing-design.md`) leans flow-only for the flatten join
and the concurrent join both — pass-through reduces to availability by
provenance, and this signature's `values` rows re-read as the drawn form
of that availability. The multi-flow signature above is the older form,
kept as the record until the binary revision is adopted here.

---

### Commute

Swaps the nesting order of two flows.

```
Commute:
  variant: CommuteVariant
  innerFlow: FlowSource
  outerFlow: FlowSource

  flowOutputs: {inner, outer}
```

**CommuteVariant:**

```
CommuteVariant: OperationName
```

After commute, what was inner becomes outer and vice versa. Both flows
are output as *new* flows (not pass-throughs) because commute involves
sequencing that downstream nodes may depend on.

**The node carries flow wires only — no value inputs or outputs.** Value
computations hang off the original opens' value ports and meet the
commute only at a close: a close on a commute-derived flow supplies its
value from ordinary value wires, like any close. Compilation realizes
commute in the close's output construction
(`lazy-stream-commute-design.md`); when the two swapped flows are closed
separately, the compiler treats the node as a full commuted close
followed by an immediate re-open of the still-open layer(s) — internal
bookkeeping, never surfaced as ports. This is the reconciliation of the
node form (the representation) with the per-close form (the
compilation): **the node is the representation; the close is the
compilation.**

Two consequences:

- **"Swap-and-continue" is not a thing.** With no value ports there is
  nothing to wire "under the swapped nesting"; the only consumers of the
  node's output flows are flow operations (closes, joins, further
  commutes). The old question — whether continuing computation under the
  swapped nesting is implementable — is not answered but *dissolved*: no
  such program is expressible.
- **The syntax quotients by naturality.** Because value nodes neither
  inherit from nor feed the Commute node, "before vs. after the commute"
  has no representation: programs equal by the naturality identity
  (map-then-commute = commute-then-map) are the same diagram — the
  strongest form of the one-way-to-read principle. The compiler is free
  to pick evaluation timing; it computes values per element during the
  commuted walk, with the short-circuit skipping the rest. Unobservable
  in a pure language, so the choice is free.

The two output flows need not be closed together. Closing the new inner
flow while leaving the new outer flow open is the **defer-the-error**
idiom: a loop that may fail commutes its option/error flow out of the
loop, closes the loop, and leaves the error flow open to handle later.
The inner close's output is then an ordinary value wire under the
still-open outer flow, referenced by whatever close eventually handles
it.

```
xs -> open list -> mayFail -> open option -~> commute -~> collect
=> perElem                    -- loop closed; option (error) layer still open
perElem -> summarize -~> collect => report
```

A close under a never-closed flow is unreachable (dead by consumer-set
analysis), so deferral is "not now," not "never" — the editor should
surface a never-closed commute-derived flow rather than let it die
silently.

Only option-out-of-stream has a worked-out compile
(`lazy-stream-commute-design.md`); other variants
(result-out-of-stream, marker-out-of-sequenceable, …) share the node
shape but await their own runtime design. Which flow-kind pairs get a
variant at all — and which commute for free or belong to other operations
— is mapped in that document's "The commute-variant taxonomy" section.

**Why not value pass-through ports.** An earlier signature carried
per-element value pass-through ports; those are what made
"swap-and-continue" look like a design obligation. The 1-1
correspondence they encoded is the naturality identity, which the
port-free node expresses better by making the before/after distinction
unrepresentable.

---

### EffectOperation

Performs an operation on an effect flow (IO, State, Exception, …).

```
EffectOperation:
  effect: EffectType
  operation: OperationName
  flow: FlowSource
  inputs: List<ValueSource>

  valueOutputs: {<depends on operation>}
  flowOutputs: {flow}
```

- `effect`: which effect type (e.g. "IO", "State", "Exception").
- `operation`: which operation on it (e.g. "print", "readLine", "get",
  "put", "throw").
- `flow`: the incoming effect flow; this operation happens after whatever
  produced that flow.
- `inputs`: values the operation needs.

The output `flow` is the effect flow after this operation. Downstream
effect operations must use it to keep sequencing.

Effect flows enter diagrams via `DiagramFlowInput`, exit via
`DiagramFlowOutput`, can be bundled/unbundled like other flows, can be
incorporated into values (`Incorporate`), and can be sequenced (`Join`).

---

### Incorporate

Adds flow dependencies to a value, positioning new flows relative to
existing flow dependencies. This is how a value from outside a flow — a
constant, or a value from an enclosing context — is brought into that
flow's context as a named step.

```
Incorporate:
  flows: List<IncorporateFlowSpec>
  value: ValueSource

  valueOutputs: {value}
  flowOutputs: {<one for each existing flow in the list, in order>}
```

**IncorporateFlowSpec:**

```
IncorporateFlowSpec:
  flow: FlowSource
  isExisting: Bool  // true = existing dependency, false = newly incorporated
```

`flows` specifies the desired flow-dependency order for the output value,
outermost to innermost. Each entry says whether the flow is an existing
dependency of the input value or a newly incorporated one. The output
value depends on all flows in that order.

**Flow outputs:** each existing flow in the input list produces a
corresponding flow output, because existing flows that now have newly
incorporated flows *outer* to them must be closed and reopened during
implementation, producing new flow wires.

**Examples:**

1. Value `v` with no flow dependency, incorporate into flow `f`:
   - flows: `[{f, new}]`
   - flowOutputs: `{}` (no existing flows)
   - Result: `v` depending on `[f]`

2. Value `v` depending on `[A, B]`, incorporate `C` between them:
   - flows: `[{A, existing}, {C, new}, {B, existing}]`
   - flowOutputs: `{A', B'}` (reopened versions)
   - Result: `v` depending on `[A', C, B']`

3. Value `v` depending on `[A, B, C]`, incorporate `D` between A and B
   and `E` between B and C:
   - flows: `[{A, existing}, {D, new}, {B, existing}, {E, new}, {C, existing}]`
   - flowOutputs: `{A', B', C'}`
   - Result: `v` depending on `[A', D, B', E, C']`

```
listB -> open list => b, ~B
listA -> incorporate in ~B      -- bring listA into ~B's context (spelling per
                                --   textual-representation-design.md)
```

**One usage is corrected.** Incorporate is a meaningful primitive and
stays. But it must **not** be used to nest two *sibling* uncollects (two
independently opened lists) inside one another — that erases their mutual
independence. For that case the right node is a **Cross**
(`product-flows-design.md`). The Cross node has no spec entry yet; one is
owed when that design lands.

---

### IterationCaseSplit

Splits an iteration flow by structural position (e.g. initial vs. step,
or last vs. non-last).

```
IterationCaseSplit:
  iterationType: IterationType
  split: SplitName
  flow: FlowSource

  valueOutputs: {}
  flowOutputs: {<one per case in the specified split, named by CaseName>}
```

For example, a list iteration might have:

- a "past" split with cases "initial" and "step" → outputs named
  "initial" and "step";
- a "future" split with cases "last" and "non-last" → outputs named
  "last" and "non-last".

The output flows are still iteration flows: they can be case-split again
with a different split, or used with `IterationPayload`.

Carried state does *not* need this split: Delay's initial value is wired
from outside the flow, so no first/subsequent split is required. The
split remains for genuinely positional programs.

---

### IterationPayload

Accesses case-specific payload fields within a specific case of an
iteration.

```
IterationPayload:
  iterationType: IterationType
  caseFlow: FlowSource

  valueOutputs: {<one per case-specific payload field for this case>}
  flowOutputs: {}
```

- `iterationType`: the iteration type, which defines available payload
  fields per case.
- `caseFlow`: the case-split flow, which determines which case's payload
  fields are available.

Needed only for case-specific payload. Universal payload (like `element`
for a list) is output directly from Uncollect. For a binary tree in the
"node" case this outputs the `element`; the case is fixed by which flow
is wired to `caseFlow`.

---

### Delay

The loop-carried-variable construct: a value carried from one iteration
of a flow to the next.

```
Delay:
  flow: FlowSource       // the iteration flow this Delay is tied to
  init: ValueSource      // evaluated outside the flow; the value on the first iteration
  step: ValueSource      // per-iteration; the value carried into the next iteration

  valueOutputs: {prev}
  flowOutputs: {}
```

> *Known gap in this inventory.* The one-node shape above has no home for
> the register's **final value** (the total after the flow completes), and
> the two-phase `step` wiring is not constructible on immutable data. Both
> are answered by the **register pair** — a read half and a write half,
> the write half a node of its own with `final` as its output
> (`iteration-with-state-design.md`, "The Delay back-edge: the write half is
> a node"). Whether the spec keeps one Delay node with the pair as its
> Expr-level form, or adopts the pair, is open there; either way `final`
> needs a home this section currently lacks. A second open question rides
> on `flow`: *which* flow a Delay is tied to when more than one is in
> reach is the Delay ontology (`delay-ontology-design.md`), not settled by
> this field's existence.

- `flow`: the iteration flow the carried variable spans. A Delay is
  always explicitly tied to a specific flow.
- `init`: an input from outside the flow. On the first iteration, `prev`
  outputs this value. Wiring `init` from a per-iteration value is
  ill-formed (same family as the no-time-travel rule).
- `step`: a per-iteration input. Whatever computes the new carried value
  wires into this port; that value emerges from `prev` on the next
  iteration.
- `prev` output: the previous iteration's `step` value (or `init` on the
  first iteration). Read by ordinary wiring, exactly as a list
  iteration's `element` is read off its Uncollect.

The read half and write half are two textual statements — mint the read,
wire the step later:

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum          -- read half; bare `sum` = prev
sum, a -> add -> step of sum => total   -- write half; binder = the new value
```

`init` is kept syntactically apart from per-iteration inputs. That
separation is load-bearing: putting the initial value inside the flow is
the misplacement that got the rejected `stateful(initial, update)` /
`prev(x)` shapes rejected (`iteration-with-state-design.md`).

**One variable per Delay.** Multiple carried variables are multiple Delay
nodes; no tuple packing. Cross-references (one Delay's `step` computed
from another's `prev`) are ordinary wires — self-reference and
cross-reference are not distinguished structurally. Fibonacci is two
Delays whose `step` inputs read each other's `prev` outputs:

```
steps -> open list => n, ~L
~L ~> delay init 1 => fa
~L ~> delay init 1 => fb
fb -> step of fa => lastA
fa, fb -> add -> step of fb => lastB
```

**No multi-step lookback.** `prev` reaches back exactly one iteration.
Two-step lookback is two Delays, one feeding the other — the chain of
carried state stays visible.

**No symbolic references.** The `step` input is a back-edge: a diagram
containing a Delay is not a DAG. This is deliberate — the back-edge *is*
the iteration — and it needs no `ById`-style symbolic indirection. A
Delay's `prev` port exists as soon as the node is created and can be
referenced immediately; `step` is wired as a separate, later act — the
same two-phase pattern as wiring a Collect to its Uncollect.

**Well-formedness (productivity).** A diagram is well-formed only if
deleting every Delay's internal `step → prev` edge leaves the value graph
acyclic — i.e. every cycle must pass through a Delay. This is a
whole-diagram quotient constraint (like alt matching and no-crossing):
enforced as a check, not by construction. It is the standard causality
check of synchronous dataflow languages (Lustre's `pre`/`->`).

**Compile target.** A single mutable register in the generated loop:
`init` sets it before the loop, `prev` reads it at the top of each
iteration, `step` assigns it at the bottom. The cross-iteration cycle
never appears within one iteration of the generated code.

**Visual representation.** The redesigned iteration rail: a horizontal
line crossing the single generic iteration column, with a tap-down read
on the left (= `prev`), a writeback-up on the right (= `step`), and the
initial value attached by a dotted line (= `init`). No diagonal, no
multi-slot shapes, no ghost columns. See
`iteration-rails-design-notes.md`.

**Status — one of two live candidates.** Delay is one of two live
candidate designs for iteration state. Both supersede the retired
IterationRail / TapIn / TapOut trio (schemas in git history), which got
three things wrong: multi-slot lookback made the rail visually degenerate
under generalization (deeper lookback is chained Delays instead);
per-case TapIns put the initial value *inside* the flow when it belongs
outside; and `ById` symbolic references stand in for what is honestly a
back-edge plus the productivity check. The other candidate is the
**latent-flow representation**: generalizing cuts a value wire and
interposes an *augmented uncollect* — the flow's opener with a seed input
and a per-iteration state output added — with a feedback collect
producing the modified flow. Its node schema is not yet pinned down (the
feedback-collect mechanic is open), so only Delay is specified here. The two candidates have since been proven result-level equivalent — one
register pair under two drawings — so the open decision is the surface,
not the semantics. See
`iteration-with-state-design.md`, "The two candidates side by side" and
"The equivalence, worked," for the comparison; the
reasoning behind Delay is there (semantic side: the "link" transformation
and the port form) and in `iteration-rails-design-notes.md` (visual side:
the redesigned rail, which both candidates realize).

---

### SlotInvocation

Invokes a slot within the current diagram.

```
SlotInvocation:
  slotName: String
  args: Map<ParamName, ValueSource>
  flowArgs: Map<FlowParamName, FlowSource>

  valueOutputs: {<defined by slot signature's valueOutputs>}
  flowOutputs: {<defined by slot signature's flowOutputs>}
```

Can only appear within a diagram that defines the named slot.

---

### DiagramValueInput

Entry point for a value parameter into a diagram.

```
DiagramValueInput:
  name: String

  valueOutputs: {value}
  flowOutputs: {}
```

`name` must match one of the diagram's declared `valueInputs`.

---

### DiagramValueOutput

Exit point for a value result from a diagram.

```
DiagramValueOutput:
  name: String
  value: ValueSource

  valueOutputs: {}
  flowOutputs: {}
```

`name` must match one of the diagram's declared `valueOutputs`.

---

### DiagramFlowInput

Entry point for a flow parameter into a diagram.

```
DiagramFlowInput:
  name: String

  valueOutputs: {}
  flowOutputs: {flow}
```

`name` must match one of the diagram's declared `flowInputs`.

---

### DiagramFlowOutput

Exit point for a flow result from a diagram.

```
DiagramFlowOutput:
  name: String
  flow: FlowSource

  valueOutputs: {}
  flowOutputs: {}
```

`name` must match one of the diagram's declared `flowOutputs`.

---

## Supporting Types

### AlternativeType

Defines the alternatives for a disjoint union.

```
AlternativeType:
  alternatives: List<AlternativeName>
```

---

### IterationType

Defines the structure of an iteration: its universal payload, case
splits, and the case-specific fields available in each case.

```
IterationType:
  name: OperationName
  universalPayload: List<FieldName>  // available at every position
  splits: Map<SplitName, Map<CaseName, IterationCase>>

IterationCase:
  payloadFields: List<FieldName>  // case-specific payload
  recursiveSlots: Int  // how many slots in this case's shape
```

**Example: List Iteration**

```
IterationType:
  name: "list"
  universalPayload: [element]  // every position has an element
  splits:
    past:
      initial:
        payloadFields: []
        recursiveSlots: 0
      step:
        payloadFields: []
        recursiveSlots: 1  // slot 0 = previous
    future:
      last:
        payloadFields: []
        recursiveSlots: 0
      non-last:
        payloadFields: []
        recursiveSlots: 1  // slot 0 = next
```

**Example: Binary Tree Iteration**

```
IterationType:
  name: "binaryTree"
  universalPayload: []  // no universal payload; element only exists at nodes
  splits:
    structure:
      leaf:
        payloadFields: []
        recursiveSlots: 0
      node:
        payloadFields: [element]  // case-specific: only nodes have elements
        recursiveSlots: 2  // slot 0 = left, slot 1 = right
```

---

### StructType

Defines the structure of an aggregate type.

```
StructType:
  name: String
  fields: List<FieldName>
```

---

### EffectType

Identifies a built-in effect.

```
EffectType: OperationName  // e.g., "IO", "State", "Exception"
```

Effect types are built-in; users cannot define custom effects in this
version of the language.

---

## Flow Types

Flows created by different mechanisms have different capabilities:

**Iteration flows** (from Uncollect Iteration):
- Can be case-split using `IterationCaseSplit`.
- Can host Delay nodes (loop-carried state; formerly iteration rails).
- Used for traversing recursive data structures (lists, trees, …).

**Alternative flows** (from Uncollect CaseSplit):
- Represent being in a particular branch of a sum type.
- Cannot be case-split further (they already represent a specific case).
- No zipper structure.
- Must eventually be recombined via Collect Case.

**Opaque flows** (from Uncollect ConfigScope):
- Cannot be case-split or inspected.
- Represent bundled wiring that passes through from uncollect to collect.
- Implemented as if the entire sub-diagram were inlined.

**Effect flows** (from DiagramFlowInput or EffectOperation):
- Enforce sequencing of effectful operations.
- No zipper structure.
- Threaded through EffectOperation nodes.
- Can be incorporated into values, bundled, and joined like other flows.

These distinctions are not enforced in the structural representation but
are semantic properties of how each flow type can be used.

---

## Notes

### No Time Travel Rule

The representation is designed to support the "no time travel" rule: flow
ordering and nesting relationships must be established at construction
time, never determined retroactively. This is why:

- Join takes both an inner flow and an outer flow (binary — one inner
  flow per node, per the Join section's design note; whether it keeps
  value ports is open there, and the point here needs only the two flow
  operands).
- Commute takes both flows as inputs (it carries no value ports — see the
  Commute section).
- Flow outputs from Join and Commute are new flows, not pass-throughs.

### Nested Representation

This is primarily a nested representation where inputs point to outputs.
In a complete diagram, all nodes are reachable by starting from the
diagram's output nodes (DiagramValueOutput, DiagramFlowOutput) and
recursively following all sources, tracking visited nodes to handle
sharing. Without Delay nodes the structure is a DAG; each Delay's `step`
input is a back-edge, so traversal must treat `step` sources like any
other shared reference (visited-set) rather than assuming acyclicity.
Acyclicity modulo Delay crossings is the productivity check (see Delay).

The diagram also maintains an explicit `nodes` set because during editing
some nodes may be temporarily disconnected — and because a complete
program is a node set (see the Diagram section).

Self-reference needs no symbolic indirection: the cycle is embraced, not
avoided. Delay's `step → prev` back-edge is an ordinary structural
connection, well-formedness comes from the productivity check, and
construction is two-phase (mint the Delay, wire `step` later). The
retired alternative — `ById` symbolic references à la bound variable
names — died with the rail design (see the status note under Delay);
resurrecting id-as-reference would make Delay the one place a reference
is not a structural pointer (`first-class-ports-design.md`, "The three
named escapes fail for cause").

### Types Omitted

Value types (what kind of data flows through value wires) are outside the
scope of this specification. They present unique considerations and will
be addressed separately.

### Semantic Validity

This specification describes what diagrams can be structurally
represented, not which diagrams are semantically valid. Validity checking
(type correctness, flow-nesting correctness, etc.) is a separate concern
built on top of this representation.
