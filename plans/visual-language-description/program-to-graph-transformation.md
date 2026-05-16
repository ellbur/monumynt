# Plan: Program → Graph Transformation

## Goal

Transform a `Diagram` (language encoding) into a `Graph<Element>` (graph encoding with SVG renderers), suitable for input to the layout algorithm. This is the "semantic layer" described in graph-representation.md — the layer that understands the language and makes all visual decisions.

## Architecture

### Code Organization: Group by Node Kind

Following the expression problem preference stated in the design: code is organized by **node kind**, not by concern. A single function handles everything about the Uncollect node — its shape, its ports, its annotations, its edges. Likewise for every other node kind.

```
src/transformation/
  transform.ts          -- Main entry: Diagram → Graph<Element>
  node-kinds/           -- One function per NodeKind (or small groups)
    literal.ts
    primitive.ts
    aggregate.ts
    disaggregate.ts
    function-call.ts
    uncollect.ts
    collect.ts
    bundle-unbundle.ts
    join.ts
    commute.ts
    effect-operation.ts
    incorporate.ts
    iteration-case-split.ts
    iteration-payload.ts
    iteration-rail.ts
    tap-out.ts
    slot-invocation.ts
    diagram-ports.ts    -- DiagramValueInput/Output, DiagramFlowInput/Output
  common.ts             -- Shared rendering helpers (box shapes, port layout, colors)
  types.ts              -- Types private to the transformation
```

### Why This Grouping

The alternative would be to organize by concern — one file for "port computation", one for "shape computation", etc. But:

1. When adding a new node kind, you'd touch every file.
2. Node kinds vary wildly in visual complexity (a Literal is a small box; an IterationRail has nested arrays with dotted connectors).
3. Grouping by node kind makes each function self-contained and independently testable.

The `common.ts` module prevents duplication by providing building blocks that many node-kind functions share.

---

## Traversal Strategy

### Overview

1. Walk `diagram.nodes` (the `Set<Node>`).
2. Maintain a `Map<Node, TransformedNode>` to track already-visited nodes (since Sources point to Nodes by reference, the same Node may be reachable from multiple inputs).
3. For each unvisited Node, dispatch on `node.kind.type` to the appropriate node-kind function.
4. Each node-kind function returns a `TransformedNode` — a record containing the `GraphNode`, its output ports (keyed by output name), and optionally arrays it belongs to.
5. After all nodes are transformed, collect the roots and build `Graph<Element>`.

### The Dispatch

```typescript
function transformNode(node: Node, ctx: TransformContext): TransformedNode {
  const kind = node.kind;
  switch (kind.type) {
    case 'Literal':              return transformLiteral(kind, ctx);
    case 'Primitive':            return transformPrimitive(kind, ctx);
    case 'Aggregate':            return transformAggregate(kind, ctx);
    case 'Disaggregate':         return transformDisaggregate(kind, ctx);
    case 'FunctionCall':         return transformFunctionCall(kind, ctx);
    case 'Uncollect':            return transformUncollect(kind, ctx);
    case 'Collect':              return transformCollect(kind, ctx);
    case 'Bundle':               return transformBundle(kind, ctx);
    case 'Unbundle':             return transformUnbundle(kind, ctx);
    case 'Join':                 return transformJoin(kind, ctx);
    case 'Commute':              return transformCommute(kind, ctx);
    case 'EffectOperation':      return transformEffectOperation(kind, ctx);
    case 'Incorporate':          return transformIncorporate(kind, ctx);
    case 'IterationCaseSplit':   return transformIterationCaseSplit(kind, ctx);
    case 'IterationPayload':     return transformIterationPayload(kind, ctx);
    case 'IterationRail':        return transformIterationRail(kind, ctx);
    case 'TapOut':               return transformTapOut(kind, ctx);
    case 'SlotInvocation':       return transformSlotInvocation(kind, ctx);
    case 'DiagramValueInput':    return transformDiagramValueInput(kind, ctx);
    case 'DiagramValueOutput':   return transformDiagramValueOutput(kind, ctx);
    case 'DiagramFlowInput':     return transformDiagramFlowInput(kind, ctx);
    case 'DiagramFlowOutput':    return transformDiagramFlowOutput(kind, ctx);
  }
}
```

### Edge Creation: Following Sources

Edges are created when transforming **input** ports. When a node-kind function encounters a `ValueSource` or `FlowSource`, it:

1. Calls `resolveSource(source, ctx)` which ensures the source node is already transformed (transforming it recursively if not).
2. Looks up the source node's output port by name.
3. Creates an `Edge` connecting that output port to the current node's input port.

This means edge creation is driven by the consumer, not the producer — which matches the language encoding where inputs point to outputs.

---

## Transformation Context

A `TransformContext` holds shared state during transformation:

```typescript
interface TransformContext {
  svg: SvgContext;                              // For SVG element creation
  visited: Map<Node, TransformedNode>;          // Avoid duplicate work
  diagram: Diagram;                             // The source diagram
  railState: Map<RailId, RailArrayState>;       // Rail array hierarchy, built inline
}

interface RailArrayState {
  outerArray: GraphArray<Element>;                          // Groups all cases
  caseArrays: Map<CaseName, GraphArray<Element>>;           // Per-case inner arrays
  tapOutSlots: Map<CaseName, TransformedNode[]>;            // Pre-created tap-out-slot graph nodes per case
}
```

The `railState` is fully populated when an IterationRail node is transformed — including pre-created graph nodes for all tap-out slots. When a TapOut node is later encountered, it simply looks up and re-uses the appropriate slot node. No mutation of arrays after construction.

### TransformedNode

```typescript
interface TransformedNode {
  graphNode: GraphNode<Element>;
  outputPorts: Map<string, OutputLogicalPort<Element>>;  // keyed by output name
  containingArray?: GraphArray<Element>;                 // if this node is inside an array
}
```

The `outputPorts` map lets edge creation look up the right port by the `outputName` from a `ValueSource` or `FlowSource`.

---

## Common Rendering Helpers (`common.ts`)

Many node kinds share visual patterns. Rather than duplicating rendering code, `common.ts` provides composable building blocks.

### Shared Visual Building Blocks

```typescript
// Create a labeled box node (rounded rect with text)
// Used by: Literal, Primitive, FunctionCall, EffectOperation, SlotInvocation, etc.
function labeledBox(ctx, id, label, options: {
  inputEdges, outputCount, color?, borderStyle?, annotations?
}): BoxNodeResult

// Create ports along the top/bottom edges of a box, evenly spaced
function distributePortsAlongEdge(id, count, width, side: 'top' | 'bottom'): ...

// Create an edge from a resolved source
function makeEdge(ctx, sourceNode, sourcePort, options?: {
  style?: 'value' | 'flow',
  sourceArrays?: GraphArray[]
}): Edge<Element>

// Port annotations for labeling inputs/outputs
function inputLabel(ctx, name: string): PortAnnotation<Element>
function outputLabel(ctx, name: string): PortAnnotation<Element>

// Node annotations for type/kind indicators
function kindBadge(ctx, text: string): NodeAnnotation<Element>
```

### Wire Styling

Value wires and flow wires need to be visually distinct. The graph layer doesn't have a concept of wire types, but we control this through the `EdgeRenderFn`:

- **Value wires**: solid lines, medium gray
- **Flow wires**: thicker lines, colored (e.g., blue or teal), possibly with a subtle dash pattern or glow

The `makeEdge` helper takes a style parameter and creates an edge with the appropriate render function.

---

## Visual Design Decisions per Node Kind

### Naming Convention for Output Ports

Each node kind defines **named output ports** that correspond to the `outputName` field in `ValueSource`/`FlowSource`. These names must be consistent between the producer and consumer. The names are drawn from what makes sense semantically — they'll also be used for port annotations.

### Node-by-Node Visual Specifications

#### 1. Literal
- **Shape**: Small rounded box
- **Color**: Light warm fill (pale yellow)
- **Label**: String representation of the value
- **Inputs**: None
- **Outputs**: `"value"` — one value port
- **Annotations**: None (the value IS the label)

#### 2. Primitive
- **Shape**: Labeled box
- **Color**: White fill, dark border
- **Label**: Operation name (e.g., `"ADD"`, `"MUL"`)
- **Inputs**: One value port per input in the `inputs` array
- **Outputs**: `"result"` — one value port
- **Annotations**: Port annotations for named inputs if more than one

#### 3. Aggregate
- **Shape**: Labeled box
- **Color**: Light blue fill
- **Label**: Struct type name
- **Inputs**: One value port per field (annotated with field name)
- **Outputs**: `"result"` — one value port
- **Annotations**: Corner badge "AGG", port labels for field names

#### 4. Disaggregate
- **Shape**: Labeled box
- **Color**: Light blue fill
- **Label**: Struct type name
- **Inputs**: `"input"` — one value port
- **Outputs**: One value port per field, named by field name
- **Annotations**: Corner badge "DIS", port labels for field names

#### 5. FunctionCall
- **Shape**: Labeled box, slightly larger
- **Color**: White fill, thicker border (double-line or heavier stroke)
- **Label**: Diagram ID (function name)
- **Inputs**: One value port per arg + one flow port per flowArg
- **Outputs**: Named value and flow output ports (matching the called diagram's outputs)
- **Annotations**: Port labels for parameter names; slot badges if slots are provided
- **Note**: We need to know the called diagram's output names. For now, use generic names or accept them as configuration.

#### 6. Uncollect (all variants)
- **Shape**: Labeled box
- **Color**: Distinctive — green-tinted fill (it "opens" a flow)
- **Label**: `"$"` (the uncollect symbol) with variant indicator
- **Inputs**: Value ports from `inputs` array + flow ports from `outerFlows`
- **Outputs vary by variant**:
  - *Iteration*: `"element"` (value), `"flow"` (flow)
  - *CaseSplit*: `"value"` (value), one flow output per alternative
  - *ConfigScope*: value outputs matching slot inputs, `"flow"` (flow)
- **Annotations**: Variant label (e.g., "iter", "case", "scope") as corner badge

#### 7. Collect (all variants)
- **Shape**: Labeled box
- **Color**: Red-tinted fill (it "closes" a flow)
- **Label**: `"@"` (the collect/recollect symbol) with variant indicator
- **Inputs vary by variant**:
  - *Iteration*: `value` + `flow` (one each)
  - *Case*: one `value` + `flow` pair per alternative
  - *ConfigScope*: slot outputs + `flow`
- **Outputs**: `"result"` — one value port
- **Annotations**: Variant label as corner badge

#### 8. Bundle
- **Shape**: Small labeled box
- **Color**: Neutral gray fill
- **Label**: `"Bundle"`
- **Inputs**: One flow port per flow in `flows`
- **Outputs**: `"bundle"` — one flow port
- **Annotations**: Count badge

#### 9. Unbundle
- **Shape**: Small labeled box
- **Color**: Neutral gray fill
- **Label**: `"Unbundle"`
- **Inputs**: `"bundle"` — one flow port
- **Outputs**: `"flow_0"`, `"flow_1"`, ... — one flow port per count
- **Annotations**: Count badge

#### 10. Join
- **Shape**: Labeled box
- **Color**: Purple-tinted fill (flow recomposition)
- **Label**: `"Join"` or variant name
- **Inputs**: Flow ports from `innerFlows` + `outerFlow`, value ports from `values`
- **Outputs**: One flow port per inner flow (now at outer level), value ports passed through
- **Annotations**: Port labels for flow names

#### 11. Commute
- **Shape**: Labeled box
- **Color**: Purple-tinted fill
- **Label**: `"Commute"` or variant name
- **Inputs**: `innerFlow` + `outerFlow` (flow ports), value ports from `values`
- **Outputs**: Swapped flow ports, value ports passed through
- **Annotations**: Port labels

#### 12. EffectOperation
- **Shape**: Labeled box
- **Color**: Orange-tinted fill (side effects are visually notable)
- **Label**: `"effect.operation"` (e.g., `"IO.print"`)
- **Inputs**: `flow` (flow port) + value ports from `inputs`
- **Outputs**: `"flow"` (flow port) + result value ports
- **Annotations**: Effect type badge

#### 13. Incorporate
- **Shape**: Small labeled box
- **Color**: Neutral
- **Label**: `"Inc"` or `"⊕"`
- **Inputs**: Flow ports from `flows` + `"value"` value port
- **Outputs**: `"value"` — one value port (now with flow dependencies)
- **Annotations**: None

#### 14. IterationCaseSplit
- **Shape**: Labeled box
- **Color**: Green-tinted (flow operation)
- **Label**: Split name (e.g., `"past"`, `"structure"`)
- **Inputs**: `"flow"` — one flow port
- **Outputs**: One flow port per case in the split (named by CaseName)
- **Annotations**: Iteration type name as badge

#### 15. IterationPayload
- **Shape**: Labeled box
- **Color**: Green-tinted
- **Label**: `"Payload"` or iteration type name
- **Inputs**: `"caseFlow"` — one flow port
- **Outputs**: One value port per payload field
- **Annotations**: Field names as port labels

#### 16. IterationRail
- **No direct visual node**: The IterationRail language node does not become a single GraphNode. Instead, it manifests as an **array hierarchy** containing TapIn graph nodes (one per `tapIns` entry).
- **TapIn graph nodes**: Each `TapIn` in the rail's `tapIns` list becomes a small graph node placed inside the appropriate per-case inner array. A TapIn node has:
  - One flow input (from `caseFlow`)
  - One value input (from `value` — the value being written into the rail)
  - No output ports (it's a sink within the rail)
- **Array structure**:
  - Inner arrays (one per case): contain the TapIn nodes for that case, rendered as horizontal connectors (the rail line)
  - Outer array: contains all inner arrays, rendered as vertical connectors between cases
- **Flow input**: The rail's `flow` source connects to the overall iteration context but doesn't produce a visible graph node — it's part of the array structure context.
- **Annotations**: Rail ID label on the outer array's render

#### 17. TapOut
- **Shape**: Small box or dot on the rail
- **Color**: Light green
- **Label**: `"↑"` or slot index
- **Inputs**: `"caseFlow"` — one flow port
- **Outputs**: `"value"` — one value port (the tapped previous-iteration value, going downstream)
- **Placement**: Placed inside the appropriate per-case inner array of the referenced rail. The inner array's render function draws the horizontal rail connector through all TapIn and TapOut nodes together.
- **Recursive TapOut** (`RailReference.ById`): Visually drawn as if it feeds into the rail — it sits on the rail alongside TapIn nodes. Even though it semantically reads a value (output), its visual position on the rail makes it look like it's receiving from the previous iteration. The value output port carries the result away from the rail downward into the program.
- **Direct TapOut** (`RailReference.Direct`): Same visual treatment, placed into the inner array of the directly-referenced rail node.

#### 18. SlotInvocation
- **Shape**: Labeled box
- **Color**: White fill, dashed border (represents a "hole" to be filled)
- **Label**: Slot name
- **Inputs**: Value ports from `args` + flow ports from `flowArgs`
- **Outputs**: Named value and flow output ports
- **Annotations**: Port labels for parameter names

#### 19–22. Diagram Ports (ValueInput, ValueOutput, FlowInput, FlowOutput)
- **Shape**: Small rounded terminal (half-circle or pill shape)
- **Color**:
  - Value ports: neutral/gray
  - Flow ports: blue/teal (matching flow wire color)
- **Label**: Port name
- **Inputs**: DiagramValueOutput has one value input; DiagramFlowOutput has one flow input
- **Outputs**: DiagramValueInput has one value output; DiagramFlowInput has one flow output
- **Annotations**: None (the label is sufficient)
- **Note**: These are the "boundary" of the diagram — they appear at the top (inputs → sources) and bottom (outputs → sinks) of the graph.

---

## Handling Port Ordering Constraints (`rightOf`)

The graph encoding uses `rightOf` on logical ports to encode horizontal ordering constraints. The transformation must set these up based on the language's flow nesting rules:

1. **On a given node**: flow output ports that represent outer contexts go to the LEFT; inner contexts go to the RIGHT. Value ports go to the RIGHT of all flow ports they depend on.

2. **Concretely**: When a node has both flow and value outputs, each value output's logical port gets `rightOf` pointing to the flow port(s) it depends on. When there are multiple flow outputs (e.g., case split), they are ordered outer-to-inner, left-to-right.

3. **On input ports**: Same principle — flow inputs representing outer context appear LEFT; value inputs that depend on those flows appear to their RIGHT.

This ordering is determined per node kind, since each kind knows its own flow/value structure.

---

## Handling Iteration Rails and Tap Nodes

Iteration rails are the most visually complex structure, but they don't require a separate pass. They are transformed inline as they are encountered during normal traversal.

### Visual Model

An iteration rail is drawn as a horizontal line (or thin bar) connecting **tap points** within each case of a case split. Each tap point is a small node sitting on the rail. The graph-representation spec describes this as nested arrays:

- **Outer array** (A0): links different cases together, drawn as a vertical connector
- **Inner arrays** (A1, A2, ...): one per case, each containing tap-out and tap-in nodes, drawn as horizontal connectors

The key insight: **TapIn and TapOut are the visible nodes. The IterationRail language node itself has no direct visual representation** — it manifests as the array structure and connectors that group its tap points.

### Recursive TapOut: Drawn as an Input to the Rail

A `TapOut` with `RailReference.ById` is a recursive tap — it reads a value from a previous iteration. Semantically it is an output (it produces a value), but **visually it is drawn as if it were an input to the rail**. This is because the rail represents a horizontal connection across iterations, and the recursive tap is feeding the "previous value" into the current iteration's rail from the previous iteration.

Concretely: a recursive TapOut node within a case's inner array has:
- One **input** port (the case flow)
- One **output** port (the tapped value — going downstream to the rest of the program)
- A visual position on the rail that looks like it's *receiving* from the rail (the value comes from the rail), even though it's semantically an output of reading from a previous iteration

This means the TapOut graph node's output port carries the tapped value away from the rail, while visually sitting on the rail alongside TapIn nodes (which carry values *into* the rail for the next iteration). The array's render function draws the horizontal connector through all of them.

### Program Encoding: Rails Know Their Shape

The `IterationRailNode` declares which split it spans and has a `cases: Map<CaseName, RailCaseEntry>` with one entry per case. Each case has a `tapIn`. The number of tap-out slots per case is determined by `iterationType.splits[split][case].recursiveSlots` — so the rail knows its full visual shape (how many tap-in and tap-out points per case) without needing to know which TapOut nodes in the program actually reference it.

This follows the principle that how an element is *used* should not affect what that element *is*. The rail declares its structure; TapOut nodes are just consumers.

### Transformation: Inline, Single Pass, No Deferred Mutation

When the traversal encounters an `IterationRail` node, it can build the complete array hierarchy immediately because it knows:
- Which cases exist (from `cases`)
- How many tap-in points per case (one per case entry)
- How many tap-out slots per case (from `iterationType.splits[split][case].recursiveSlots`)
- The case flow for each case (from `cases[caseName].tapIn.caseFlow` — shared by both tap-in and tap-out points in that case)

Steps:

1. **Create tap-in graph nodes**: For each case, create a small graph node for the tap-in. Resolve the `TapIn.caseFlow` and `TapIn.value` sources to create its input edges.

2. **Create tap-out slot graph nodes**: For each case, create graph nodes for each recursive slot (the tap-out points). Each has:
   - One input port with a `caseFlow` edge (the same case flow as the tap-in for that case — resolve it now)
   - One output port (for the tapped value, which downstream consumers will connect to)

   These are fully constructed — no fields left blank.

3. **Create per-case inner arrays**: Group the tap-in and tap-out-slot nodes for each case into a `GraphArray` with a horizontal connector render function.

4. **Create the outer array**: Group all inner arrays into an outer `GraphArray` with a vertical connector render function.

5. **Register in context**: Store the rail state (arrays and tap-out-slot graph nodes) in `ctx.railState` keyed by `RailId`.

When the traversal encounters a `TapOut` node:

1. **Resolve the rail**: Look up the rail by `RailReference` (Direct or ById), call `ensureTransformed` on it.

2. **Find the tap-out-slot graph node**: Using the TapOut's `slotIndex` and case (determined from its `caseFlow`), look up the corresponding tap-out-slot graph node that the rail already created.

3. **Return the slot's output port**: The `TransformedNode` for this TapOut re-uses the tap-out-slot graph node's output port, so downstream consumers connect to the right place on the rail.

No mutation occurs after construction. The rail builds everything — including tap-out slot input edges — because the case flow for each tap-out slot is the same as the case flow for the tap-in in that case, and the rail has that information.

---

## The Main `transform` Function

There is a single traversal pass. Rails, tap nodes, and everything else are transformed inline as encountered, using `ensureTransformed` to handle dependencies in any order.

```typescript
function transformDiagram(diagram: Diagram, svgCtx: SvgContext): Graph<Element> {
  // Phase 1: Initialize context
  const ctx = createTransformContext(diagram, svgCtx);

  // Phase 2: Transform all nodes (single pass)
  // Walk diagram.nodes, transforming each (with recursive source resolution).
  // IterationRail nodes create their array structures when encountered.
  // TapOut nodes ensure their rail is transformed, then join its arrays.
  for (const node of diagram.nodes) {
    ensureTransformed(node, ctx);
  }

  // Phase 3: Collect roots
  // Everything not inside an array is a root.
  // Rail outer arrays are roots; their contents are not.
  const roots = collectRoots(ctx);

  return createGraph(roots);
}
```

---

## Testing Strategy

Each node-kind function is independently testable:

1. **Unit tests per node kind**: Create a minimal `Diagram` with one or two nodes, transform it, and verify the resulting `GraphNode` has the right dimensions, port count, port names, and annotations.

2. **Edge tests**: Create a source-sink pair, transform, and verify the `Edge` connects the correct ports.

3. **Integration tests**: Transform a small but complete program (e.g., the "add constant to list elements" example from the design doc) and verify the full `Graph` structure.

4. **Visual regression tests**: Transform → layout → render → compare SVG output. (Aspirational, not needed immediately.)

---

## Open Questions / Decisions to Make During Implementation

1. **FunctionCall output names**: A FunctionCall references another diagram by ID. We don't have the called diagram in scope during transformation. Options:
   - Require a `DiagramRegistry` in the context that maps DiagramId → Diagram
   - Use generic output names (`"out_0"`, `"out_1"`) and annotate
   - Accept output names as part of a richer FunctionCall node kind

2. **Exact colors and sizing**: The visual specs above are starting points. We should tune them once we can see actual renderings. The important thing is that the structure is correct.

3. **Multiple visual ports per logical port**: The graph encoding supports multiple visual port positions per logical port (the layout algorithm picks the best one). For the initial implementation, we can start with one visual port per logical port and add alternatives later for optimization.
