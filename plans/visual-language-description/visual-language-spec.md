# Visual Programming Language: Data Representation Specification

## Overview

This document specifies the data structures and types used to represent programs in a visual programming language based on explicit flow control. The representation is:

- **Structural, not semantic**: It describes what nodes exist and how they connect, not which programs are valid
- **Nested**: Inputs point to outputs of other nodes, forming a directed graph traversed by following pointers
- **Language-agnostic**: Described using common constructs (structs, unions, lists, maps, sets)

The language separates **value wires** (carrying data) from **flow wires** (representing iteration/branching context). Both are structurally represented as connections between node ports.

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
RailId: unique identifier for an iteration rail (superseded design — see Delay)
```

---

## Diagrams

A **Diagram** is a reusable sub-program with defined inputs, outputs, and optionally slots where sub-diagrams can be supplied.

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
  rails: Map<RailId, Node>  // index of IterationRail nodes by ID (superseded design — see Delay)
```

The `nodes` field contains all nodes in the diagram. In a complete diagram, most nodes are reachable by recursively following sources from DiagramValueOutput and DiagramFlowOutput nodes, but the explicit set accommodates partially constructed diagrams during editing.

The `rails` field provides lookup of IterationRail nodes by ID, needed to resolve `ById` references in TapOut nodes. It exists only for the superseded IterationRail design; the current Delay node needs no symbolic references (see Delay).

**Slots** allow a diagram to have "cut-outs" where caller-supplied sub-diagrams are inserted. This enables configuration scopes and similar patterns.

```
SlotSignature:
  valueInputs: List<{name: String}>
  valueOutputs: List<{name: String}>
  flowInputs: List<{name: String}>
  flowOutputs: List<{name: String}>
```

---

## Nodes

A **Node** is an operation in the diagram. Each node has a kind that determines its behavior and port structure.

```
Node:
  kind: NodeKind
```

Nodes have named input and output ports for both values and flows. The specific ports depend on the node kind.

---

## Sources

Sources represent the nested pointers from inputs to outputs.

```
ValueSource:
  node: Node
  outputName: String

FlowSource:
  node: Node
  outputName: String
```

A `ValueSource` points to a value output port on another node. A `FlowSource` points to a flow output port on another node.

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

The `slotImplementations` field supplies sub-diagrams for any slots defined in the called function.

---

### Uncollect

Creates a new flow by "opening" an iteration, case split, or configuration scope.

```
Uncollect:
  variant: UncollectVariant
  inputs: List<ValueSource>
  outerFlows: List<FlowSource>

  valueOutputs: {<depends on variant>}
  flowOutputs: {<depends on variant>}
```

The `outerFlows` list specifies which existing flows this new flow should be considered "inner" to, in order from outermost to innermost. This must be explicit because:
1. It cannot always be inferred from value inputs (especially when there are no value inputs)
2. The encoding should not depend on computation steps like tracing up the diagram

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

For `Iteration`, the input is typically a collection (list, tree, etc.). The value outputs are the universal payload fields - those available at every position regardless of case (e.g., `element` for a list). The flow output represents the iteration context. Case-specific payload fields are accessed via `IterationPayload` after case-splitting.

For `CaseSplit`, the input is a value of an alternative type, and the outputs are the payload and flow for each alternative.

For `ConfigScope`, the inputs are whatever the diagram requires, and the outputs are what the slot expects to receive plus an opaque flow representing the suspended scope state.

---

### Collect

Destroys a flow by "closing" an iteration, case split, or configuration scope.

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

For `Iteration`, the inputs are the computed value and flow; the output is the collected result (e.g., a list).

For `Case`, each branch provides its computed value and flow; the output is the recombined alternative value.

For `ConfigScope`, the inputs are what the slot produced plus the flow; the outputs are what the diagram produces.

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

The `count` parameter specifies how many flows are bundled. The `flows` list must have exactly `count` elements.

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

Collapses flow nesting, moving values from an inner flow context to an outer one.

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

Different join variants implement different joining behaviors (e.g., standard join, filter join).

The `innerFlows` list typically has one element for standard joins, but can have multiple for concurrent joins where multiple flows are collapsed simultaneously.

The output values correspond 1-1 with input values (same names). The output flow represents the outer flow after the join.

---

### Commute

> **Open divergence (recorded 2026-07-05, not yet reconciled).** This node
> predates the worked-out commute design in
> `plans/lazy-stream-commute-design.md`, and the two conceptions differ.
> Both are kept side-by-side pending a decision:
>
> - **Node form (this section):** commute is a *swap-and-continue* node.
>   Both flows are re-output with the nesting inverted; computation may
>   continue under the swapped nesting, and values are eventually collected
>   by ordinary closes. Generic over flow kinds via `CommuteVariant`.
> - **Close form (`lazy-stream-commute-design.md`):** commute is a
>   *per-close output annotation* — a `Commuted` flowRef wrapper parallel to
>   `Joined`/`Filtered`. Nothing is re-entered: the close's output is
>   repackaged, e.g. a close on an option iter inside a stream flow yields
>   `option<stream<X>>` instead of `stream<option<X>>`. Worked out
>   concretely only for option-out-of-stream.
>
> The close form is expressible in the node form: it is a Commute
> immediately followed by closing both swapped flows, never computing under
> the swapped nesting. The node form is strictly more general — and that
> generality is exactly what has no design. On eager list flows,
> `plans/commute-design-notes.md` shows that commute with real
> short-circuit semantics raises linearity questions the list flow cannot
> answer; on stream flows, only the close form has been designed. Whether
> "continue computing under the swapped nesting" is implementable, and on
> which flow kinds, is what a reconciliation pass must settle before this
> node's spec can be considered current.

Swaps the nesting order of two flows.

```
Commute:
  variant: CommuteVariant
  innerFlow: FlowSource
  outerFlow: FlowSource
  values: List<{name: String, source: ValueSource}>

  valueOutputs: {<same names as input values>}
  flowOutputs: {inner, outer}
```

**CommuteVariant:**

```
CommuteVariant: OperationName
```

After commute, what was the inner flow becomes outer, and vice versa. The output values correspond 1-1 with input values. Both flows are output as new flows (not pass-through) because commute involves sequencing that downstream nodes may depend on.

---

### EffectOperation

Performs an operation on an effect flow (such as IO, State, or Exception).

```
EffectOperation:
  effect: EffectType
  operation: OperationName
  flow: FlowSource
  inputs: List<ValueSource>

  valueOutputs: {<depends on operation>}
  flowOutputs: {flow}
```

- `effect`: Which effect type (e.g., "IO", "State", "Exception")
- `operation`: Which operation on that effect (e.g., "print", "readLine", "get", "put", "throw")
- `flow`: The incoming effect flow; this operation happens after whatever produced this flow
- `inputs`: Values needed by the operation

The output `flow` is the effect flow after this operation. Downstream effect operations must use this flow to ensure sequencing.

Effect flows:
- Enter diagrams via DiagramFlowInput
- Exit diagrams via DiagramFlowOutput
- Can be bundled/unbundled like other flows
- Can be incorporated into values using Incorporate
- Can be sequenced using Join

---

### Incorporate

Adds flow dependencies to a value, positioning new flows relative to existing flow dependencies.

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

The `flows` list specifies the desired flow dependency order for the output value, from outermost to innermost. Each entry indicates whether the flow is an existing dependency of the input value or a newly incorporated flow.

The output value depends on all flows in the specified order.

**Flow outputs:** Each existing flow in the input list produces a corresponding flow output. This is because existing flows that have newly incorporated flows outer to them must be closed and reopened during implementation, producing new flow wires.

**Examples:**

1. Value `v` with no flow dependency, incorporate into flow `f`:
   - flows: [{f, new}]
   - flowOutputs: {} (no existing flows)
   - Result: v depending on [f]

2. Value `v` depending on [A, B], incorporate C between them:
   - flows: [{A, existing}, {C, new}, {B, existing}]
   - flowOutputs: {A', B'} (reopened versions)
   - Result: v depending on [A', C, B']

3. Value `v` depending on [A, B, C], incorporate D between A and B, and E between B and C:
   - flows: [{A, existing}, {D, new}, {B, existing}, {E, new}, {C, existing}]
   - flowOutputs: {A', B', C'}
   - Result: v depending on [A', D, B', E, C']

---

### IterationCaseSplit

Splits an iteration flow based on structural position (e.g., initial vs step, or last vs non-last).

```
IterationCaseSplit:
  iterationType: IterationType
  split: SplitName
  flow: FlowSource

  valueOutputs: {}
  flowOutputs: {<one per case in the specified split, named by CaseName>}
```

For example, a list iteration might have:
- A "past" split with cases "initial" and "step" → outputs named "initial" and "step"
- A "future" split with cases "last" and "non-last" → outputs named "last" and "non-last"

The output flows are still iteration flows and can be further case-split with a different split, or used with IterationPayload. (The superseded IterationRail design also consumed case-split flows via per-case TapIns; the current Delay design does not — its initial value is wired from outside the flow, so no first/subsequent split is needed for carried state.)

---

### IterationPayload

Accesses case-specific payload fields within a specific case of an iteration.

```
IterationPayload:
  iterationType: IterationType
  caseFlow: FlowSource

  valueOutputs: {<one per case-specific payload field for this case>}
  flowOutputs: {}
```

- `iterationType`: The iteration type, which defines available payload fields per case
- `caseFlow`: The case-split flow, which determines which case's payload fields are available

This is only needed for case-specific payload. Universal payload (like `element` for a list) is output directly from Uncollect.

For a binary tree in the "node" case, this outputs the `element`. The case is determined by which flow is connected to `caseFlow`.

---

### Delay

The loop-carried-variable construct: a value carried from one iteration of a flow to the next. This is **one of two live candidate designs** for iteration state; both supersede the IterationRail / TapIn / TapOut trio preserved below. The other candidate is the **latent-flow representation**: generalize cuts a value wire and interposes an *augmented uncollect* — the flow's opener with a seed input and a per-iteration state output added — with a feedback collect producing the modified flow. Its node schema is not yet pinned down (the feedback-collect mechanic is open), so only Delay is specified here; see `plans/iteration-with-state-design.md`, "Two live candidates, kept side-by-side", for the comparison and what would decide. The reasoning behind Delay is in that document (semantic side: the "link" transformation and the port form) and `iteration-rails-design-notes.md` (visual side: the redesigned rail, which both candidates realize).

```
Delay:
  flow: FlowSource       // the iteration flow this Delay is tied to
  init: ValueSource      // evaluated outside the flow; the value on the first iteration
  step: ValueSource      // per-iteration; the value carried into the next iteration

  valueOutputs: {prev}
  flowOutputs: {}
```

- `flow`: the iteration flow the carried variable spans. A Delay is always explicitly tied to a specific flow.
- `init`: an input from outside the flow. On the first iteration, `prev` outputs this value. Wiring `init` from a per-iteration value is ill-formed (same family as the no-time-travel rule).
- `step`: a per-iteration input. Whatever computes the new carried value wires into this port; the value emerges from `prev` on the next iteration.
- `prev` output: the previous iteration's `step` value (or `init` on the first iteration). Read by ordinary wiring, exactly as a list iteration's `element` is read off its Uncollect.

**One variable per Delay.** Multiple carried variables are multiple Delay nodes; no tuple packing. Cross-references (one Delay's `step` computed from another Delay's `prev`) are ordinary wires — self-reference and cross-reference are not distinguished structurally. Fibonacci is two Delays whose `step` inputs read each other's `prev` outputs.

**No multi-step lookback.** `prev` reaches back exactly one iteration. Two-step lookback is two Delays, one feeding the other — the chain of carried state stays visible.

**No symbolic references.** The `step` input is a back-edge: a diagram containing a Delay is not a DAG. This is deliberate — the back-edge *is* the iteration — and it needs no `ById`-style symbolic indirection. A Delay's `prev` output port exists as soon as the node is created and can be referenced immediately; `step` is wired as a separate, later act — the same two-phase pattern as wiring a Collect to its Uncollect.

**Well-formedness (productivity).** A diagram is well-formed only if deleting every Delay's internal `step → prev` edge leaves the value graph acyclic — i.e. every cycle must pass through a Delay. This is a whole-diagram quotient constraint (like alt matching and no-crossing): enforced as a check, not by construction. It is the standard causality check of synchronous dataflow languages (Lustre's `pre`/`->`).

**Compile target.** A single mutable register in the generated loop: `init` sets it before the loop, `prev` reads it at the top of each iteration, `step` assigns it at the bottom. The cross-iteration cycle never appears within one iteration of the generated code.

**Visual representation.** The redesigned iteration rail: a horizontal line crossing the single generic iteration column, with a tap-down read on the left (= `prev`), a writeback-up on the right (= `step`), and the initial value attached by a dotted line (= `init`). No diagonal, no multi-slot shapes, no ghost columns. See `iteration-rails-design-notes.md`.

---

### IterationRail (superseded)

> **Superseded** (together with TapIn and TapOut) by the current iteration-state candidates — the Delay node above and the latent-flow alternative its note describes. Preserved for the record. What was discarded, and why:
>
> - **Multi-slot lookback** (`slotIndex`, previous-previous, tree-child slots): only single-step `prev` survives; deeper lookback is chained Delays. The general slot shapes were what made the rail visually degenerate under generalization (see `iteration-rails-design-notes.md`).
> - **Per-case TapIns keyed by IterationCaseSplit**: the initial value is not a case of the flow — it is evaluated before the flow produces any iterations and belongs outside it (see "Where the critique points" in `plans/iteration-with-state-design.md`). Delay's `init` is an ordinary outside-the-flow input; no first/subsequent split is required for carried state, and the first/subsequent distinction is handled by the mechanism, invisible inside the flow body.
> - **`ById` symbolic references**: replaced by an honest back-edge plus the productivity check. Two-phase construction (mint the node, wire `step` later) removes the need for symbolic indirection entirely.

Defines an iteration variable that spans an iteration flow, with values defined per case and accessible at recursive positions.

```
IterationRail:
  id: RailId
  iterationType: IterationType
  flow: FlowSource
  tapIns: List<TapIn>

  valueOutputs: {value}
  flowOutputs: {}
```

- `id`: Unique identifier for this rail, used by TapOut nodes that need to reference it by ID (to break cycles)
- `iterationType`: Determines the shape of slots available in each case
- `flow`: The overall iteration flow (pre-split) that this rail spans
- `tapIns`: Definitions for each case

The `value` output is an ordinary value depending on the overall iteration flow. This is what gets passed to Collect.

**TapIn:**

```
TapIn:
  caseFlow: FlowSource
  value: ValueSource
```

- `caseFlow`: The flow for a specific case (obtained from IterationCaseSplit)
- `value`: The value being fed into the rail for this case

Each TapIn provides the rail's value for one case of the iteration.

---

### TapOut (superseded)

> **Superseded by Delay's `prev` output port.** Preserved for the record; see the note on IterationRail.

Accesses the value of an iteration rail at a recursive position.

```
TapOut:
  rail: RailReference
  caseFlow: FlowSource
  slotIndex: Int

  valueOutputs: {value}
  flowOutputs: {}
```

- `rail`: Reference to the iteration rail being accessed
- `caseFlow`: The case-split flow we're accessing from (determines available slots)
- `slotIndex`: Which recursive slot to access (visually, which position on the shape to wire from)

The output `value` is the rail's value at the indicated recursive position.

**RailReference:**

```
RailReference:
  | Direct(node: Node)  // node.kind must be IterationRail
  | ById(railId: RailId)
```

- `Direct`: Structural pointer to the node whose kind is IterationRail. Use when the TapOut's value is not fed back into the same rail (no cycle).
- `ById`: Symbolic reference by identifier. Use when the reference would create a cycle (e.g., counter pattern where TapOut feeds into a computation that feeds back into the same rail's TapIn).

Both forms are semantically equivalent - they differ only in whether the reference is structural or symbolic.

**Visual Representation:**

The iteration rail is drawn as a diagonal "track" spanning the horizontal (iteration) dimension. The shape of each segment is determined by (iterationType, caseName):

For a list (step case) - one slot for previous:
```
    ┌─┐
... │ │ → ...
    └─┘
      ↑
   wire from here = previous value
```

For Fibonacci (step case with depth 2) - two slots:
```
    ┌─┬─┐
... │ │ │ → ...
    └─┴─┘
      ↑ ↑
      │ └── previous-previous (slotIndex: 1)
      └──── previous (slotIndex: 0)
```

For a binary tree (node case) - two slots for children:
```
         ┌─┐
    ... ←│ │→ ...
         └─┘
         / \
   left    right
   (0)      (1)
```

TapIn wires feed values into the rail from above. TapOut wires tap values from specific slots.

**Example: Counter over a list**

A counter that starts at 0 and increments by 1 at each step:

1. Uncollect the list, producing iteration `flow`
2. IterationCaseSplit on `flow` with split "past", producing `initialFlow` and `stepFlow`
3. Create Literal node for 0
4. Create TapOut with:
   - rail: ById(railId) — must use ById because this creates a cycle
   - caseFlow: stepFlow
   - slotIndex: 0
5. Create Primitive Add node taking TapOut's value and literal 1
6. Create IterationRail with:
   - id: railId
   - iterationType: list iteration type
   - flow: the pre-split iteration flow
   - tapIns: [
       {caseFlow: initialFlow, value: (the literal 0)},
       {caseFlow: stepFlow, value: (the Add result)}
     ]
7. Collect with the rail's `value` output and the iteration flow

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

This node can only appear within a diagram that defines the named slot.

---

### DiagramValueInput

Entry point for a value parameter into a diagram.

```
DiagramValueInput:
  name: String

  valueOutputs: {value}
  flowOutputs: {}
```

The `name` must match one of the diagram's declared `valueInputs`.

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

The `name` must match one of the diagram's declared `valueOutputs`.

---

### DiagramFlowInput

Entry point for a flow parameter into a diagram.

```
DiagramFlowInput:
  name: String

  valueOutputs: {}
  flowOutputs: {flow}
```

The `name` must match one of the diagram's declared `flowInputs`.

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

The `name` must match one of the diagram's declared `flowOutputs`.

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

Defines the structure of an iteration, including its universal payload, case splits, and the case-specific fields available in each case.

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

Effect types are built-in; users cannot define custom effects in this version of the language.

---

## Flow Types

Flows created by different mechanisms have different capabilities:

**Iteration flows** (from Uncollect Iteration):
- Can be case-split using IterationCaseSplit
- Can host Delay nodes (loop-carried state; formerly iteration rails)
- Have zipper structure accessible via TapOut (superseded design)
- Used for traversing recursive data structures (lists, trees, etc.)

**Alternative flows** (from Uncollect CaseSplit):
- Represent being in a particular branch of a sum type
- Cannot be case-split further (they already represent a specific case)
- No zipper structure
- Must eventually be recombined via Collect Case

**Opaque flows** (from Uncollect ConfigScope):
- Cannot be case-split or inspected
- Represent bundled wiring that passes through from uncollect to collect
- Implemented as if the entire sub-diagram were inlined

**Effect flows** (from DiagramFlowInput or EffectOperation):
- Enforce sequencing of effectful operations
- No zipper structure
- Threaded through EffectOperation nodes
- Can be incorporated into values, bundled, and joined like other flows

These distinctions are not enforced in the structural representation but are semantic properties of how different flow types can be used.

---

## Notes

### No Time Travel Rule

The representation is designed to support the "no time travel" rule: flow ordering and nesting relationships must be established at construction time. This is why:
- Join takes both inner flow, outer flow, and value as inputs
- Commute takes both flows and values as inputs
- Flow outputs from Join and Commute are new flows, not pass-throughs

### Nested Representation

This is primarily a nested representation where inputs point to outputs. In a complete diagram, all nodes are reachable by starting from the diagram's output nodes (DiagramValueOutput, DiagramFlowOutput) and recursively following all sources, tracking visited nodes to handle sharing. Without Delay nodes the structure is a DAG; each Delay's `step` input is a back-edge, so traversal must treat `step` sources like any other shared reference (visited-set) rather than assuming acyclicity. Acyclicity modulo Delay crossings is the productivity check (see Delay).

However, the diagram also maintains an explicit `nodes` set and `rails` index because:
- During editing, some nodes may be temporarily disconnected
- TapOut nodes using `ById` references need a way to look up rails by ID without structural traversal (superseded design — under Delay, no symbolic references exist and the `rails` index is unnecessary)

### Avoiding Cycles with Rail References (superseded)

> **Superseded.** This note belongs to the IterationRail design. Neither current candidate needs symbolic references. The port-form Delay takes the opposite position: the cycle is not avoided, it is embraced. The `step → prev` back-edge is an ordinary structural connection — the representation is a graph with cycles, not a DAG — and well-formedness is guaranteed by the productivity check (every cycle must pass through a Delay) rather than by keeping the representation acyclic. Construction is two-phase (mint the Delay, wire `step` later), so no symbolic reference is ever needed. The latent-flow candidate avoids the issue differently: feedback is an uncollect/collect pairing on the flow, and under its cursor-as-feedback reading the result graph stays acyclic by construction. See the Delay section and `plans/iteration-with-state-design.md` ("No construction-time cycle"; "Two live candidates, kept side-by-side").

Iteration patterns like counters are inherently self-referential: the value at each position depends on the value at a previous position. To avoid structural cycles in the representation, TapOut uses `RailReference` which can be either:
- `Direct`: A structural pointer, used when no cycle would result
- `ById`: A symbolic identifier, used when the TapOut's value feeds back into the same rail

This is analogous to how lambda calculus uses bound variable names to avoid structural self-reference. The `ById` form is resolved by finding the IterationRail with that ID in scope.

### Types Omitted

Value types (what kind of data flows through value wires) are outside the scope of this specification. They present unique considerations and will be addressed separately.

### Semantic Validity

This specification describes what diagrams can be structurally represented, not which diagrams are semantically valid. Validity checking (type correctness, flow nesting correctness, etc.) is a separate concern built on top of this representation.
