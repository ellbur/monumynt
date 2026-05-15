# Visual Layout Guidelines for the Visual Programming Language

This document describes the principles and rules for laying out programs in the visual programming language. These guidelines prioritize implementability, rendering speed, consistency, and stability under incremental edits over compactness or aesthetic optimization.

## Terminology

- **Flow identity wire:** A wire representing an execution context. Comes out of Uncollect (opening a flow) and goes into Collect/Join (closing a flow).
- **Value wire:** A wire carrying data.
- **Bundle:** Related flows from a single operation. For example, a case split produces a bundle of case flows (one per case). These are mutually exclusive execution contexts. These flows are collected (not joined) when the branches reconverge.
- **Aggregation:** A visual convenience combining unrelated flows into a single wire. Encoded as "aggregate in" and "aggregate out" nodes. From the layout algorithm's perspective, these are ordinary nodes and wires.
- **Union flow:** A flow created by linking some (not all) alternatives of a case split. This flow is outer with respect to the individual case flows that contributed to it.
- **Recursive tap-out:** A tap-out from a rail that references its own rail via a unique ID. Used to access values from previous iterations.
- **Late-split junction:** A dummy node inserted where multiple wires from the same output port diverge to different destinations. Keeps wires bundled as long as possible.
- **Named wire point:** A labeled marker that replaces a long wire. The wire disappears into a point at its source and reappears from a matching point at its destination. Purely visual—does not affect layout computation.

## Foundational Principles

### Principle A: Implementability
The layout algorithm must be implementable in software with predictable performance characteristics.

### Principle B: Stability and Predictability
Local changes to the program should produce local changes to the layout. Users should be able to predict where new nodes will appear without the entire diagram reflowing. This rules out force-directed layouts and other L2-norm optimization approaches. Linear programming (L1-norm) is acceptable when optimization is needed. Where possible, layout should be determined by explicit rules without any optimization.

### Principle C: Semantic Fidelity
Visual structure should reflect semantic relationships. The spatial arrangement of elements should communicate meaning about the program's behavior.

## Layout Guidelines

### Guideline 1: Vertical Axis Represents Computation Steps
Computation flows vertically down the page. A node appears below all nodes it depends on. 

**Exception:** Recursive tap-outs reference their own rail, creating a semantic cycle. For layout purposes, these are handled by treating the rail as depending on the recursive tap-out (see Guideline 10).

### Guideline 2: Flow Identity Wire Ordering
Flow identity wires are placed according to their nesting relationship:
- Outer flow wires appear to the left of inner flow wires
- If two flow wires commute (their relative nesting is semantically unconstrained), there is no placement preference between them

This applies to all flow identity wires, including:
- Simple flow wires from Uncollect
- Union flow wires created by linking some (not all) alternatives of a case split (these are outer with respect to the individual case flows that contributed to them)

### Guideline 3: Value Wire Placement Relative to Flows
Value wires are placed to the right of all flow identity wires they depend on.

Beyond this constraint, a value wire inherits its horizontal zone from its source. If a value is produced by a node at horizontal position P, that value starts at position P and may shift rightward to accommodate nested flows, but does not shift leftward.

When a nested flow opens from operations involving a value at position P, that nested flow's zone is inserted at position P. Values already to the right of P shift further right to make room. Values that don't depend on the nested flow maintain their relative ordering—they simply shift if necessary to preserve the constraint that they remain to the right of any flows they depend on.

**Output positioning for flow-manipulating nodes:**

For ordinary computation nodes, all inputs depend on the same set of flows, and outputs inherit that same position.

Nodes that manipulate flows have specific rules for where their outputs are born:
- **Incorporate**: The value output is born to the right of the flow wire (now inside the flow).
- **Collect**: The value output inherits the position the flow wire *would have* if it continued. If the collected flow had an outer flow, the output is positioned relative to that outer flow.
- **Commute**: Positionally equivalent to two collects followed by two uncollects. The value remains inside both flows; the flow wires swap their nesting order.

### Guideline 4: Crossing Minimization
The goal of horizontal ordering is to arrange **wires**, not nodes. At each level boundary (between level N and level N+1), we determine a total ordering of wires that:

1. Respects the partial order from Guidelines 2 and 3
2. Respects node boundaries—ports belonging to the same node cannot be interleaved with ports from another node
3. Respects fixed port orderings within nodes (some ports have fixed order, some are reorderable per Guideline 5)
4. Minimizes crossings among wires that are otherwise unconstrained

A node's horizontal position simultaneously constrains both its input wires (from above) and its output wires (going below). Hard constraints should be consistent across both sides; crossing minimization operates on the remaining degrees of freedom.

**Note:** If constraints on the input side and output side of a node are inconsistent, some constraints must be relaxed. For now, the resolution strategy is unspecified—it may be as simple as arbitrarily dropping constraints until consistency is achieved. A more principled approach may emerge from experience with real programs.

For wires spanning multiple levels, insert dummy nodes at intermediate levels so that every wire spans exactly one level. This converts the problem into ordering nodes/ports at each level, where dummy nodes represent long wires passing through.

A simple heuristic: place each node at the barycenter (average horizontal position) of its neighbors in adjacent levels, breaking ties by source order. More sophisticated heuristics may be used if they maintain stability.

### Guideline 5: Port Ordering Within Nodes
Some nodes have ports in a fixed order (determined by semantics). Other nodes have reorderable ports. The layout algorithm may reorder flexible ports to reduce wire crossings.

Port ordering constraints are defined separately from node type definitions, as they are purely visual properties.

### Guideline 6: Case Split Ordering
Case splits have a natural ordering:
- Initial/base cases (empty collection, None, zero) appear to the left
- Continuing/recursive cases appear to the right

This creates a consistent reading direction where terminating cases precede continuing cases.

For case splits without a natural order, any consistent ordering may be used.

### Guideline 7: Horizontal Dimension Reflects Flow Structure
The horizontal dimension reflects flow structure and case distinctions rather than explicit iteration position. Simple iteration (e.g., over a list) does not create horizontal spread—there is only one visible element position at a time.

Horizontal spread appears in specific situations:
1. **Case splits** — each case occupies a horizontal zone, ordered per Guideline 6, with values clustering near their associated case flows per Guideline 3
2. **Zipper access via tap-out** — when tapping out of an iteration rail to access a zipper, the zipper's slots are arranged horizontally to reflect the iteration structure (e.g., "elements before" and "elements after" for a list)
3. **Tap-out/tap-in pairs** — tap-outs are generally placed to the left of tap-ins, reflecting the temporal flow (accessing the previous value before producing the next)

### Guideline 8: Visual Distinction of Flow Identity Wires
Flow identity wires are visually distinct from value wires through weight, color, style (e.g., dashed vs. solid), or some combination. Users should instantly distinguish execution context wires from data wires.

Different flows should be distinguishable from each other, for example by color.

### Guideline 9: Wire Routing
Wires route orthogonally (Manhattan routing) or with fixed diagonal angles. Corners are rounded to make them visually distinct from crossings—sharp corners occur only at crossings.

Avoid arbitrary curves or splines that create layout instability.

### Guideline 10: Iteration Rail Visualization
Iteration rails are drawn horizontally where possible. The vertical positioning of rails and their tap-outs follows these rules:

1. If a rail R references a node Y (e.g., for its initial value), R is drawn below Y.

2. If a node X references a rail R directly (not through a recursive tap-out), X is drawn below R.

3. **Recursive tap-outs** (tap-outs that reference their own rail via a unique ID) are treated specially for layout: the rail is drawn as if it depends on the recursive tap-out, even though semantically the tap-out is an output. This places the recursive tap-out above the rail, breaking the visual cycle.

4. A rail is visualized as a wide, short node (essentially a horizontal line). TapIn and non-recursive TapOut are ports on this node. Recursive tap-outs are drawn as separate nodes above the rail, with a dotted line connecting back down to the corresponding port position on the rail.

If other constraints make horizontal rails impossible, the rail may be drawn as a diagonal or connected segments, but this should be uncommon.

### Guideline 11: Late-Split Junctions
When multiple wires emanate from the same output port and each spans at least two levels, insert a dummy junction node at the deepest level possible. All wires from that output port emanate from the junction rather than from the original port.

This keeps wires bundled as long as possible before they diverge to different destinations, reducing visual clutter.

### Guideline 12: Named Wire Points for Long Wires
Very long or unwieldy wires may be replaced with named points: the wire disappears into a labeled point at its source, and reappears from a matching labeled point at its destination. This reduces visual clutter without changing the program's meaning.

**Critical:** Named wire points are purely visual. The wire still participates in all horizontal ordering computations as if it were drawn. Only the final rendering omits the wire itself.

**Identifying candidates for cutting:**
- Vertical length is straightforward (difference in levels)
- Horizontal length can only be computed after horizontal positions are assigned
- Total wire length (Manhattan distance) or wire path complexity may be useful metrics

**Deciding when to cut:**
- Not all diagrams need wire cutting—simple diagrams may have no wires that are "too long"
- The decision should be based on overall diagram complexity, not just absolute wire length
- Possible heuristics: cut wires whose length exceeds some fraction of the diagram's total extent, or cut wires when the diagram exceeds a complexity threshold and those wires are outliers

The specific heuristics for identifying unwieldy wires and deciding when cutting is warranted are left unspecified, to be refined through experience with real programs.

## Summary of Axis Semantics

| Axis | Represents |
|------|------------|
| Vertical (top to bottom) | Computation steps / data dependencies |
| Horizontal (left to right) | Flow nesting (outer → inner), case structure, and iteration position |

## Implementation Notes

The layout algorithm should proceed roughly as follows:

1. **Assign vertical levels** based on distance from sink nodes (nodes with no dependents). This places nodes as late as possible, keeping literals and other dependency-free nodes close to where they are used. For rails: (a) treat recursive tap-outs as dependencies of their rail (inverting the semantic direction), and (b) constrain TapIn and TapOut nodes for the same rail to the same level.

2. **Insert late-split junctions** for output ports with multiple wires spanning at least two levels. Place the junction at the deepest level possible (the level of the shallowest consumer, or one level above if needed).

3. **Insert dummy nodes** for wires spanning multiple levels, so every wire spans exactly one level.

4. **Determine partial order on wires** based on flow nesting structure (Guideline 2) and value wire placement rules (Guideline 3).

5. **Apply crossing minimization** to find a total ordering of wires at each level boundary that respects: (a) the partial order, (b) node boundaries (ports from the same node stay together), and (c) fixed port orderings within nodes. Iterate between levels until stable (or for a fixed number of iterations).

6. **Assign exact horizontal positions** to nodes based on the wire orderings. A node spans from its leftmost port to its rightmost port.

7. **Route wires** using orthogonal/Manhattan routing with rounded corners.

8. **Identify and cut long wires** (optional). After routing, compute wire lengths and apply heuristics to decide if any wires should be replaced with named points. This step does not affect layout—it only affects rendering.

9. **Draw iteration rails** as wide horizontal nodes with TapIn and non-recursive TapOut as ports. Draw recursive tap-outs as separate nodes above the rail with dotted lines connecting to their port positions.

Details of each phase will be elaborated in implementation documentation.
