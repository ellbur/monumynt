# Graph Representation for Visual Layout

## Overview

This document describes a graph representation designed to separate the visual layout of programs from their semantics. The representation captures everything needed to lay out and render a program visually, without encoding any semantic concepts specific to the programming language.

The separation serves two purposes: it facilitates debugging and testing of the layout system independently from language semantics, and it produces a general-purpose graph representation that could potentially be reused for other visual languages with similar layout requirements.

### Design Philosophy

The transformation from program to graph happens in a semantic layer that understands the language. That layer makes all decisions about what visual elements exist, how large they are, what constraints govern their arrangement, and how they render. The graph representation and layout algorithm that consumes it need not understand why these decisions were made—they only execute them.

This differs from tools like Graphviz, which provide built-in node shapes (box, circle, oval) and styling concepts. Here, the graph representation contains no such abstractions. Each node is a unique visual entity with its own dimensions and render function. The layout algorithm sees only geometry and constraints.

### Identifiers

Entities that can be referenced by other parts of the graph—arrays, nodes, output logical ports, and visual ports—have unique identifiers. These enable traversal algorithms to track visited entities and avoid processing the same entity multiple times. The identifiers are opaque to the layout algorithm; their only purpose is identity comparison.

## Data Structures

### Graph

The top-level structure containing all root elements.

```
Graph
  roots: list of (Node | Array)
```

The roots are elements not contained in any array. The full set of nodes and arrays is found by traversing the containment hierarchy: arrays contain elements, which may be nodes or other arrays.

### Node

A node represents a visual element with defined geometry that occupies a position in the graph.

```
Node
  id: unique identifier
  width: number
  height: number
  center_of_gravity: (x, y)
  input_ports: list of InputLogicalPort
  output_ports: list of OutputLogicalPort
  annotations: list of NodeAnnotation
  render: function(position) → visual output
```

**Purpose**: Nodes are the primary visual elements. In the semantic layer, a node might represent an operation, a literal value, a tap point on an iteration rail, or any other visual component of the program. The graph representation does not distinguish among these—it sees only geometry and connectivity.

**Layout communication**: The `width`, `height`, and `center_of_gravity` tell the layout algorithm the node's bounding box and where to anchor it. The `render` function is called after layout to draw the node at its computed position.

**Containment**: A node may be contained in an array, but the node itself does not store this relationship. Containment is determined by which array lists the node in its elements. Nodes not contained in any array appear in the graph's roots.

### Array

An array is a container that groups nodes (and other arrays) that must appear at the same vertical level.

```
Array
  id: unique identifier
  elements: list of (Node | Array)
  render: function(element_positions) → visual output
```

**Purpose**: Arrays serve two roles in the visual language. First, they constrain multiple visual elements to the same level—for example, the tap points of an iteration rail within a single case of a case split. Second, they provide a visual connector between those elements, such as a dotted line linking tap points.

Arrays can nest. An inner array might contain tap-out and tap-in nodes within one case. An outer array might contain those inner arrays, ensuring all tap points for the same iteration appear at the same level throughout the entire case split.

**Layout communication**: The layout algorithm traverses the containment hierarchy starting from graph roots. When it encounters an array, it treats the array as a unit for level computation: the array's level is determined by the edges that target elements within it. All elements of the array are constrained to that same level. After layout, the algorithm calls the array's render function with the positions of its immediate elements to draw the visual connector.

### Logical Ports

Logical ports are the semantic connection points on a node. Edges connect to logical ports.

#### Output Logical Port

```
OutputLogicalPort
  id: unique identifier
  visual_ports: list of VisualPort
  rightOf: list of references to other OutputLogicalPort on same node
  annotation: optional PortAnnotation
```

**Purpose**: An output logical port represents a point from which data or control flows out of a node. Multiple edges may originate from the same output logical port—these represent the same wire fanning out to multiple destinations.

**Layout communication**: The `rightOf` field specifies wire ordering constraints. If port P1 is in port P2's `rightOf` list, then wires emanating from P1 must appear to the left of wires emanating from P2 in the final layout. This is a partial order; ports not related by `rightOf` constraints may be placed in any relative order.

The layout algorithm propagates these constraints through the graph: if wire A is left of wire B at one level, that relationship persists at subsequent levels until the wires terminate or merge.

The `visual_ports` list specifies the geometric locations where this logical port may be rendered. If multiple visual ports are provided, the layout algorithm chooses which one to use. This enables the semantic layer to specify that certain ports are interchangeable—for example, the two operands of a commutative operation.

#### Ordering Constraint Symmetry

Wire ordering can be specified at either end of a wire—on output ports (at the source) or input ports (at the destination). For a complete, well-formed program, these constraints are redundant: specifying ordering at output ports implies the same ordering at the corresponding input ports, and vice versa.

However, during editing, a program may be incomplete. A flow might be opened (uncollect) but not yet closed (no collect), or closed but not yet opened. In these cases, only one end of the wire exists, and that end must be able to specify ordering constraints.

The layout algorithm uses ordering constraints from whichever ports provide them. If both ends of a wire specify constraints, they should agree; the layout algorithm may warn on inconsistencies but is not required to detect all of them.

#### Input Logical Port

```
InputLogicalPort
  visual_ports: list of VisualPort
  edge: optional Edge
  rightOf: list of references to other InputLogicalPort on same node
  annotation: optional PortAnnotation
```

**Purpose**: An input logical port represents a point at which data or control flows into a node. Each input logical port accepts at most one edge.

**Layout communication**: Like output ports, input ports may have multiple visual port positions, allowing the layout algorithm to choose among them. All input ports with the same set of visual ports are candidates for assignment to those positions—the layout algorithm decides the optimal assignment.

The `rightOf` field specifies wire ordering constraints, just as on output ports. If port P1 is in port P2's `rightOf` list, then wires arriving at P1 must appear to the left of wires arriving at P2.

### Visual Port

A visual port is a geometric location on a node's boundary.

```
VisualPort
  id: unique identifier
  x: number (relative to node)
  y: number (relative to node)
```

**Purpose**: Visual ports define where wires can physically connect to a node. They are purely geometric—the semantic meaning of the port is carried by the logical port that references them.

**Layout communication**: When a logical port has multiple visual ports, the layout algorithm assigns the logical port to exactly one visual port. All edges connected to that logical port will route to or from that position.

Multiple logical ports may share the same set of visual ports. The layout algorithm assigns each logical port to a distinct visual port from the shared set. This enables patterns where two inputs are semantically interchangeable, and the layout should choose the assignment that minimizes crossings.

### Edge

An edge represents a wire connecting an output port to an input port.

```
Edge
  source: path of [Array*, Node, OutputLogicalPort]
  render: function(path_points) → visual output
```

**Purpose**: Edges are the connectors in the graph. They represent data flow, control flow, or any other connection between nodes. The graph representation does not distinguish among these types—that distinction is baked into the render function.

**Source path**: The source is a path through the containment hierarchy: zero or more arrays, followed by the node, followed by the output logical port. For example, if a node N is contained in array A1, which is contained in array A0, and the edge originates from port P on that node, the source path is [A0, A1, N, P].

If the source node is not contained in any array (i.e., it's a graph root), the path is simply [N, P].

**Destination**: The destination of an edge is implicit: an edge lives inside the input logical port it connects to. The edge does not need to encode the destination's containment path because the layout algorithm reaches the destination by traversing the hierarchy and therefore already has that context.

**Layout communication**: The layout algorithm uses the source path to locate the origin point of the wire. It computes a route from source to destination, possibly inserting junction points where multiple edges from the same source port diverge. After layout, it calls the render function with the computed path.

**Junctions**: The graph representation does not contain junction nodes. If multiple edges originate from the same output port, they initially share a path from that port. The layout algorithm decides where they diverge and may render a visual junction at that point. This is a layout decision, not a semantic one.

### Port Annotation

A port annotation is a visual label attached to a logical port.

```
PortAnnotation
  width: number
  height: number
  valid_placements: subset of {East, West}
  render: function(position) → visual output
```

**Purpose**: Port annotations label ports for debugging or user comprehension. They are arbitrary renderables—not necessarily text.

**Layout communication**: The annotation specifies its dimensions and which sides of the port it may be placed on (East or West—North and South would collide with the node or wire). The layout algorithm positions the annotation to avoid collisions with edges, choosing among valid placements as needed.

The annotation attaches to a logical port but is positioned relative to whichever visual port the layout algorithm assigns to that logical port.

### Node Annotation

A node annotation is a visual label attached to a corner of a node.

```
NodeAnnotation
  corner: one of {NE, NW, SE, SW}
  width: number
  height: number
  render: function(position) → visual output
```

**Purpose**: Node annotations provide debugging or supplementary information displayed at a node's corners. Like port annotations, they are arbitrary renderables.

**Layout communication**: Unlike port annotations, node annotations have a fixed corner assignment. The layout algorithm does not choose where to place them—it only accounts for their space when computing overall layout. The render function is called with the position of the specified corner after layout.

## Layout Algorithm Responsibilities

The graph representation specifies what exists and what constraints apply. The layout algorithm determines where everything goes. Specifically, the layout algorithm is responsible for:

**Vertical level assignment**: Computing discrete levels for each node based on graph connectivity. The graph specifies no levels; they are derived from the structure.

**Same-level constraints**: Ensuring that all elements within an array are placed at the same level. Since arrays contain their elements (which may be nodes or other arrays), nested arrays propagate this constraint transitively.

**Horizontal positioning**: Assigning horizontal positions to nodes and wires. The wire ordering constraints specified by `rightOf` on output and input ports must be satisfied, and those constraints propagate through the graph.

**Visual port assignment**: Assigning each logical port to one of its available visual ports. When multiple logical ports share visual ports, each must be assigned to a distinct one.

**Wire routing**: Computing paths for edges from source to destination, including deciding where wires that share a source port should diverge and whether to render visual junctions at those points.

**Annotation placement**: Positioning port annotations (East or West) to avoid collisions with edges. Reserving space for node annotations at their fixed corners.

**Rendering**: After computing positions, calling each element's render function with the appropriate geometric information (position for nodes and annotations, path for edges, element positions for arrays).

## What the Graph Representation Does Not Contain

The following concepts, common in other graph representations, are deliberately absent:

**Semantic types**: No distinction between "flow wires" and "value wires," or between "uncollect nodes" and "literal nodes." The semantic layer makes these distinctions and encodes their visual consequences in geometry, constraints, and render functions.

**Style classes**: No CSS-like styling system. Visual appearance is baked into render functions. Theming, if desired, is handled by the semantic layer when constructing render functions.

**Containment for scoping**: No nested regions representing lexical scope, function bodies, or block structure. The only containment is through arrays, which group elements at the same level. This reflects the language's design, which eliminates containment relationships for control flow constructs.

**Vertical levels**: No explicit level assignments. Levels are computed by the layout algorithm from connectivity.

**Junction nodes**: No explicit junction points. The layout algorithm decides where wires diverge and may render junctions as a visual artifact.

**Complete wire ordering**: No total ordering of wires. Only pairwise constraints (`rightOf`) are specified, at either or both ends of wires. The layout algorithm resolves these into a complete ordering.

## Example: Iteration Rail

To illustrate how the representation captures a complex visual structure, consider an iteration rail spanning two cases of a case split.

Structure:
- Array A0 (outer, links the cases) contains:
  - Array A1 (case 1) contains:
    - Node T1out (tap-out) with one output port
    - Node T1in (tap-in) with one input port
  - Array A2 (case 2) contains:
    - Node T2out (tap-out) with one output port
    - Node T2in (tap-in) with one input port

If an edge from outside targets T1out's input port, its source path would include the full containment chain to the source node.

The layout algorithm:
1. Traverses from graph roots, encountering A0
2. Treats A0 as a unit; its level is determined by edges targeting elements within it
3. Recursively processes A1 and A2, constraining them to A0's level
4. Processes T1out, T1in within A1, constraining them to A1's level
5. Processes T2out, T2in within A2, constraining them to A2's level
6. Transitively, all four tap nodes are at the same level
7. After layout, calls A1's render function with positions of T1out and T1in (draws horizontal connector in case 1)
8. Calls A2's render function with positions of T2out and T2in (draws horizontal connector in case 2)
9. Calls A0's render function with positions of A1 and A2 (draws vertical connector between cases)

The graph representation contains no concept of "iteration rail" or "case split"—only nodes, edges, arrays, and geometry.
