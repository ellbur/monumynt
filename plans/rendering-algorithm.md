# Visual Programming Language Rendering Algorithm

> **Status (2026-07-09).** Layout side — out of scope in this repo, kept
> because the layout algorithm should survive. The algorithm operates on
> the semantics-free graph of `graph-representation.md` and is unaffected
> by the language-side supersessions; only examples that mention rails or
> tap nodes use retired vocabulary (see `rejected-ideas.md` entries 6–7).

This document describes the algorithm for rendering a visual programming language graph. The algorithm follows a layered graph drawing approach, adapted for the specific concepts of the language.

## Overview

The algorithm consists of 12 steps:

1. Compute levels for nodes and arrays
2. Place junctions for wires with the same source that span multiple levels
3. Insert dummy nodes along wires so each edge spans exactly one level
4. Compute mandatory horizontal ordering at each level
5. Pick a particular horizontal ordering at each level, based on crossing heuristics
6. Determine node and port annotation placement, which will affect node size
7. Determine and cut "unwieldy" edges
8. Space nodes horizontally within their levels
9. Determine the (x, y) coordinates of each node
10. Call the node rendering functions
11. Call the array rendering functions
12. Call the edge rendering functions

## Key Concepts

**Levels:** Nodes are assigned to horizontal levels, with level 0 at the bottom (the ultimate sink) and levels increasing upward toward sources.

**Arrays:** Flat, single-level containers with no internal connectivity. All edges involving array contents cross the array boundary.

**Junctions:** Nodes with one input port and one output port, representing a fanout point where a wire splits to multiple destinations. Rendered by the edge rendering function, not the node rendering function.

**Dummy nodes:** Nodes inserted to ensure every edge spans exactly one level. Like junctions, they have one input and one output port and are rendered by the edge rendering function.

**Wire trees:** A recursive structure describing the paths emanating from an output port, including dummy nodes, junctions, cuts, and sinks.

---

## Step 1: Compute Levels for Nodes and Arrays

**Goal:** Assign each node and array to a level based on shortest path to the ultimate sink.

**Algorithm:**

1. Start from the ultimate sink at level 0.
2. For each node or array *A* not inside another array:
   - Find the shortest path (by edge count) from any port within *A* (recursively including contents of nested arrays) to the sink.
   - Assign that path length as *A*'s level.
3. For each array, propagate its level to all direct contents (nodes and subarrays), recursively.

**Notes:**

- Array boundaries do not add to path length; it is purely edge count.
- Since there are no intra-array edges, propagation never creates conflicts.

---

## Step 2: Place Junctions for Wires with the Same Source that Span Multiple Levels

**Goal:** Add explicit junction nodes where a single output port fans out to multiple destinations at different levels.

**Algorithm:**

1. For each source port, collect all outgoing wires.
2. Filter to wires that span at least 2 levels.
3. If fewer than 2 wires remain, stop.
4. Otherwise, create a junction node (one input port, one output port) at level (highest sink level + 1).
5. Redirect all filtered wires to originate from the junction's output port instead of the original source.
6. Add a single wire from the original source to the junction's input port.
7. Repeat from step 2, treating the junction's output port as the source.

**Notes:**

- Junctions have a node ID but no rendering information; they are rendered by the edge rendering function.
- A single source may end up with multiple junctions placed recursively.

---

## Step 3: Insert Dummy Nodes Along Wires So Each Edge Spans Exactly One Level

**Goal:** Ensure every edge in the graph connects nodes exactly one level apart.

**Algorithm:**

1. For each wire spanning more than one level (from level *h* to level *l*, where *h* > *l* + 1):
2. Create dummy nodes at each intermediate level: *h* - 1, *h* - 2, ..., *l* + 1.
3. Replace the original wire with a chain of wires connecting source → dummy → dummy → ... → destination.

**Notes:**

- Each dummy node has one input port and one output port.
- Dummy nodes are rendered by the edge rendering function, not the node rendering function.

---

## Step 4: Compute Mandatory Horizontal Ordering at Each Level

**Goal:** Establish partial orders on nodes and reorderable ports based on `rightOf` constraints.

**Key observations:**

- `rightOf` is a constraint on ports, not nodes.
- Nodes never overlap horizontally: if P1 is on node N1 and P2 is on node N2, and N1 is left of N2, then P1 is left of P2.
- Constraints between ports on different nodes reduce directly to constraints between nodes.
- Constraints between ports on the same node only matter if those ports are reorderable.
- Some ports are reorderable and some are not, as specified by the logical-to-visual port mapping.

**Algorithm:**

1. Collect all explicit `rightOf` constraints between ports.
2. For each level, from top to bottom and bottom to top:
   - Propagate to the adjacent level: for each pair of ports (P1, P2) at this level that both have edges to the adjacent level, if P1 must be right of P2 (directly or transitively), add the corresponding constraint at the adjacent level.
3. For each level, partition constraints into:
   - Cross-node constraints → partial order on nodes
   - Same-node constraints on reorderable input ports → partial order per node
   - Same-node constraints on reorderable output ports → partial order per node

**Output:**

- For each level: a partial order on nodes
- For each node: a partial order on reorderable input ports, and a partial order on reorderable output ports

**Implementation notes:**

- Propagation requires determining transitive relationships without necessarily materializing the full transitive closure.
- A DAG representation with reachability queries is one approach.
- If a cycle is detected, emit a warning and discard conflicting constraints arbitrarily.

---

## Step 5: Pick a Particular Horizontal Ordering at Each Level, Based on Crossing Heuristics

**Goal:** Extend each partial order from step 4 into a total order, choosing among valid orderings to minimize edge crossings.

**Algorithm:**

1. Start with an initial total ordering at each level (any valid topological sort of the partial order).
2. Sweep upward from level 0:
   - For each level *n*, holding level *n-1* fixed, find a total ordering of nodes and reorderable ports at level *n* that:
     - Respects the partial orders from step 4
     - Minimizes crossings between levels *n* and *n-1*
3. Sweep downward from the top level:
   - For each level *n*, holding level *n+1* fixed, find a total ordering that respects partial orders and minimizes crossings between levels *n* and *n+1*.
4. Repeat sweeps until orderings stabilize or a maximum iteration count is reached.

**Notes:**

- Crossings are counted only between adjacent levels.
- All crossings are weighted equally.
- When optimizing a level, jointly choose: total order on nodes, total order on reorderable input ports per node, and total order on reorderable output ports per node.
- For implementation, heuristics like barycenter or median ordering can be used, adjusted to respect partial order constraints.

---

## Step 6: Determine Node and Port Annotation Placement, Which Will Affect Node Size

**Goal:** Determine where annotations are placed, which fixes node dimensions.

**Algorithm:**

1. For each node, note its annotation placements (NE, SE, NW, SW) as already specified in the graph representation.
2. For each port:
   - If it's the leftmost port on its side, place annotation to the left.
   - If it's the rightmost port on its side, place annotation to the right.
   - Otherwise, place annotation to the right.
3. Compute each node's total bounding box, incorporating the node's own dimensions plus all annotation boxes in their determined positions.

**Notes:**

- Annotations are opaque boxes with width and height; their content is irrelevant to layout.
- Annotations are aligned to the top and bottom edge of the node and do not affect its height.

---

## Step 7: Determine and Cut "Unwieldy" Edges

**Goal:** Identify edges that are too long or complex to render as continuous lines, and replace them with labeled stubs.

**Unwieldiness criteria (combined into a score):**

- Number of crossings involving the chain's edges
- Number of levels spanned
- Bubble participation: chains that participate in large "bubbles" (two chains sharing a source and sink that enclose many nodes) are more unwieldy

**Algorithm:**

1. For each chain (sequence of edges with only dummy nodes/junctions between, from real source to real sink), compute an unwieldiness score.
2. Cut chains whose score exceeds a threshold (threshold may depend on overall graph size).
3. Eliminate junctions: for each junction where all outgoing paths have been cut, remove the junction and mark the incoming path as cut as well. Repeat until no more junctions can be eliminated.
4. Group cut chains by their ultimate source port. Multiple cuts from the same source port share a single label.
5. For each cut chain:
   - Remove its dummy nodes from the layout
   - Record the cut for inclusion in the wire tree

**Notes:**

- Only real nodes count when measuring bubble size.
- The exact scoring formula and threshold will require experimentation.
- Labels at the sink end are not merged; each port gets its own label since they represent distinct values.

---

## Step 8: Space Nodes Horizontally Within Their Levels

**Goal:** Assign horizontal positions to all nodes, dummy nodes, and junctions.

**Linear programming formulation:**

**Variables:**

- `x_n` for each node n (including dummy nodes and junctions): its horizontal position

**Constraints:**

- Ordering: for adjacent nodes A, B at the same level (A left of B): `x_A + width_A + spacing <= x_B`
- Dummy nodes and junctions have zero or negligible width

**Objective (minimize):**

- Primary: sum of horizontal edge deviations. For each edge from port P1 to port P2, introduce auxiliary variable `d >= 0` with:
  - `d >= (x_n1 + offset_P1) - (x_n2 + offset_P2)`
  - `d >= (x_n2 + offset_P2) - (x_n1 + offset_P1)`
- Secondary (low weight): sum of all `x_n` (encourages leftward placement when unconstrained)

**Output:** Horizontal position for each node, dummy node, and junction.

**Notes:**

- Port positions within a node are specified in the graph representation.
- Linear programming is preferred over quadratic to avoid excessive movement when the graph is modified.

---

## Step 9: Determine the (x, y) Coordinates of Each Node

**Goal:** Assign vertical positions based on level, accounting for node height and center of gravity.

**Algorithm:**

1. For each node, compute:
   - Ascent: distance from center of gravity to top of node
   - Descent: distance from center of gravity to bottom of node

2. For each level, compute:
   - Max ascent among all nodes at that level
   - Max descent among all nodes at that level

3. Starting from level 0:
   - Establish a baseline y position for level 0
   - For each subsequent level n: baseline = (baseline of level n-1) + (max descent at level n-1) + padding + (max ascent at level n)

4. For each node, its y coordinate (at center of gravity) = baseline of its level

5. Combine with horizontal positions from step 8 to get (x, y) for each node.

**Output:** (x, y) coordinates for every node, dummy node, and junction, where y refers to the center of gravity.

---

## Step 10: Call the Node Rendering Functions

**Goal:** Render all real nodes (not dummy nodes or junctions).

**Algorithm:**

1. For each real node:
   - Call its render function with:
     - Node position (x, y)
     - Annotation positions
     - Any other layout-determined information
   - Collect the rendered output

**Output:** Rendered visuals for all real nodes.

---

## Step 11: Call the Array Rendering Functions

**Goal:** Render array containers.

**Algorithm:**

1. Order arrays from innermost to outermost (nested arrays before their parents).
2. For each array in this order:
   - Call its render function with the positions of its directly contained nodes and subarrays
   - Collect the rendered output

**Output:** Rendered visuals for all arrays.

---

## Step 12: Call the Edge Rendering Functions

**Goal:** Render all wires, including junctions and cut stubs.

**Wire tree structure:**

Each output port has an associated render function that receives a wire tree. The wire tree is a recursive structure:

```
wire_tree =
  | dummy_node: (x, y, rest: wire_tree)
  | junction: (x, y, rest: [wire_tree])
  | cut: (x1, y1, x2, y2, rest: wire_tree)
  | sink: (port, x, y)
```

- `dummy_node`: a point the wire passes through
- `junction`: a point where the wire fans out to multiple destinations
- `cut`: the wire is cut; draw a stub at (x1, y1) and another at (x2, y2), then continue with the rest
- `sink`: the destination input port

**Algorithm:**

1. For each logical output port with outgoing edges:
   - Construct the wire tree describing all chains, junctions, cuts, and sinks emanating from that port
   - Call the port's render function with the wire tree

**Output:** Rendered visuals for all edges.

**Notes:**

- The render function is responsible for all visual decisions: line style, junction appearance, cut stub labels, etc.
- The layout algorithm knows nothing about lines, dots, or visual style; it just provides the structure and positions.
