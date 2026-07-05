# Visual Flow Programming Language: Design Document

## Table of Contents

1. [Introduction](#introduction)
2. [Core Design Principles](#core-design-principles)
3. [Flow Fundamentals](#flow-fundamentals)
4. [List Operations](#list-operations)
5. [Flow Partitioning and Case Splits](#flow-partitioning-and-case-splits)
6. [Trees and Recursive Structures](#trees-and-recursive-structures)
7. [Functions](#functions)
8. [Custom Flows](#custom-flows)
9. [Configuration Scopes](#configuration-scopes)
10. [Concurrency and Parallelism](#concurrency-and-parallelism)
11. [Flow Commutativity](#flow-commutativity)
12. [Key Innovations Summary](#key-innovations-summary)

---

## Introduction

This document describes a visual programming language designed around the concept of **flows** - execution contexts that represent iteration, branching, state management, and control flow. Unlike traditional visual programming languages that focus on dataflow, this language makes control flow itself a first-class visual concept.

The language aims to make complex programming concepts accessible to non-experts while maintaining the power needed for sophisticated applications. It does this by:

- Making recursion implicit in primitives rather than requiring manual construction
- Avoiding higher-order functions in favor of visual configuration scopes
- Using spatial layout to reflect semantic relationships
- Separating flow identity from data values

---

## Core Design Principles

### 1. No Time Travel Rule

**Principle:** Flow ordering and nesting relationships must be established at construction time, not determined retroactively.

**Why it matters:** This ensures that the visual structure of the program determines execution order. You can't retroactively change which loop nests within another, and you can't have circular dependencies that would require "time travel" to resolve.

**Implications:**
- Cannot retroactively change which loop nests within another
- Operations that combine flows must take both values AND flow identities as inputs
- Flow structure must be determinable from the visual diagram at design time
- Prevents subtle ordering bugs that would be hard to debug visually

**Example:** When joining two flows, you must specify at construction time which flow is "earlier" in execution order.

### 2. Visual Structure Reflects Semantic Relationships

**Principle:** Visual structure and wire bundling represent semantic relationships, never syntactic limitations.

**Why it matters:** In many programming languages, you're forced to pack unrelated values into tuples or structs just to pass them through a function. This language uses spatial layout to maintain wire identity, eliminating artificial data structures.

**Implications:**
- No artificial tupling just to pass multiple values through a function
- Multiple wires are natural - use spatial layout to maintain identities
- Wire grouping/bundling only when there's genuine semantic relationship
- 2D layout is a semantic tool carrying meaning about relationships

**Example:** When two concurrent HTTP requests complete, their results remain as separate wires (not packed into a tuple), distinguished by spatial position.

### 3. Computation Flows Vertically (Generally)

**Principle:** Computational steps proceed downward in the diagram, with positional/iterative relationships shown horizontally.

**Why it matters:** This creates a consistent mental model where you can trace data flow by following wires downward, and understand iteration by looking at horizontal position.

**Implications:**
- Vertical position = computational progress
- Horizontal position = position in iteration/alternatives
- Diagonal wires = value continuity across iterations
- Makes data flow intuitive and prevents circular dependencies

**Visual model:**
```
Horizontal axis: Position in iteration
Vertical axis: Computational steps
Diagonal lines: Value flowing from one iteration to next
```

### 4. Simplicity Over Expertise

**Principle:** Avoid constructs that require expert knowledge. Make recursion and complex patterns implicit in primitives rather than requiring users to construct them.

**Why it matters:** The language should be accessible to non-programmers while remaining powerful. Complex patterns like recursion, higher-order functions, and manual memory management should be handled by the system, not the user.

**Implications:**
- No manual recursive step-taking (use primitives with built-in recursion)
- Avoid higher-order functions (use configuration scopes instead)
- Structural decomposition too complex (use zippers instead)
- Make common patterns easy, complex patterns possible

**Example:** Instead of requiring users to write recursive functions for tree traversal, the system automatically derives iteration patterns from recursive type definitions.

---

## Flow Fundamentals

### What is a Flow?

A **flow** represents an execution context - an iteration, a sequence of operations, a branching decision point, or a state machine. Flows are the primary organizational structure in this language.

Key characteristics:
- Flows have **identity** separate from the data they contain
- Multiple flows can exist simultaneously (for parallel iteration, conditional branches, etc.)
- Flows can be **opened** (created), **operated on**, and **closed** (completed)
- Flows can be **partitioned** (split into sub-cases) and **closed** together (recombined)

### Flow vs Value Wires

Every flow context produces two distinct types of wires:

#### Flow Identity Wire
- Represents the flow itself as an execution context
- Used for flow operations (commute, join, partition)
- Maintains ordering and nesting constraints
- Cannot be observed as a value - it's purely structural
- Threads through operations to enforce sequencing

**Example:** When processing a list, the flow identity wire ensures operations happen in the correct order relative to the iteration.

#### Value Wire(s)
- Represents data within the flow
- One or more value wires per flow context
- Can be computed upon, transformed, wired to other operations
- These are the actual data being processed

**Example:** When iterating a list, each position has a value wire carrying the element at that position.

### Why Separate Flow and Value Wires?

This separation enables crucial patterns:

**Multiple returns without tupling:**
```
Concurrent join merges flow wires (execution contexts)
but keeps value wires separate (no artificial data structure)
```

**Clean flow composition:**
```
Flow operations don't artificially constrain value operations
Values can pass through flow joins independently
```

**Clear semantics:**
```
Flow wire = "when does this execute?"
Value wire = "what data is being processed?"
```

---

## List Operations

### The Problem with Simple Iteration

Traditional list iteration in functional languages uses operations like `map`, `filter`, and `fold`. But these require higher-order functions - you pass a function as a parameter. In a visual language aimed at non-experts, this is confusing.

The alternative is to have a "list flow" that lets you operate on elements directly. But how flexible should this be?

### Basic List Flow (Limited)

**Uncollect:** Creates a flow from a list, generating flows for processing elements

**Recollect:** Closes a list flow, producing a result list

**What this gives you:**
- Apply same operation to each element (like `map`)
- Symmetric processing across all elements

**What you CAN'T do:**
- Get the second element specifically
- Zip two lists together
- Take first N elements
- Access previous/next elements
- Sliding window operations

**Assessment:** This is a "useful dead end" - simple and common, but not compositionally flexible enough.

### Spread: Making Lists Flexible

> **Design status:** The accumulation parts of this section were superseded by later design work. `prev` as a value operation was rejected (`plans/iteration-with-state-design.md`, "Considered: `prev(x)` as a primitive"); loop-carried state is now the Delay node — `init` input, `prev` output port, `step` input port — whose visual form is the redesigned iteration rail (`iteration-rails-design-notes.md`), which also retired the diagonal-wire picture below. The initial/subsequent positional partition is no longer needed for accumulators: the initial value lives outside the flow, and the first/subsequent distinction is handled by the mechanism. Positional access beyond carried state (`next`, `window`, non-accumulator uses of the partition) remains open, per the rail notes' "What This Leaves Uncovered".

The solution is **spread** - an operation that adds positional structure to a flow.

**How spread works:**
```
spread(flow_wire, value_wire) → produces a spread

A spread makes positional operations available:
- prev(spread) - access previous position
- next(spread) - access next position  
- current(spread) - current position
- window(spread, n) - n surrounding elements
```

**Key insight:** Spread is applied to any value within a flow, not just the original list elements. You can compute intermediate values and then spread them.

### Operations on Spreads

#### 1. Positional Access

Access values at different positions:

```
prev(spread)    - value at previous position
next(spread)    - value at next position
current(spread) - value at current position
```

**Boundary behavior:** Need to handle first/last elements (see Positional Partitioning below)

#### 2. Windowing

Get a list of surrounding elements:

```
window(spread, n) → list of n elements around current position
```

**Dynamic windows:** Size `n` can be computed, not just constant

**Boundary handling:** Windows at edges are shorter
- Position 0: `[elem0, elem1]` (only 2 elements available)
- Position 1: `[elem0, elem1, elem2]` (full 3-element window)
- Position n-1: `[elem(n-2), elem(n-1)]` (only 2 elements)

#### 3. Reduction

Combine all values in a spread to a single value:

```
reduce(spread, combine_operation, initial_value) → single value
```

This **exits the flow** - produces a non-flow value

**Example:** Sum all elements, find maximum, concatenate strings

#### 4. Scan (Derived Operation)

Like reduce but keeps intermediate results:

**How to build it:**
1. Compute accumulated value at each position
2. Spread that accumulated value
3. Access `prev(accumulated_value)` to get running accumulation

**Example - running sum:**
```
Position 0: sum = 0 + elem[0] = 3
Position 1: sum = prev(sum) + elem[1] = 3 + 5 = 8  
Position 2: sum = prev(sum) + elem[2] = 8 + 2 = 10
```

### Positional Partitioning

**Problem:** What happens when you use `prev()` at the first element? There is no previous!

**Wrong solution:** Make `prev()` return an optional value (None at first position)
- Puts the condition in the wrong place conceptually
- Clutters the diagram with case splits on wires
- Doesn't reflect that this is a property of position, not a property of a particular value

**Right solution:** **Partition the flow by position**

**Pattern:**
```
list_flow → [partition by position] → initial_flow (first element)
                                   → subsequent_flow (rest)
```

**In initial_flow:**
- `prev()` operation is not available
- No previous position exists in this context

**In subsequent_flow:**
- `prev()` operation is available
- Previous position exists

**Key insight:** The case split is on the **positional context** (environmental), not on a wire value. This makes the constraint visible and natural.

### Partial Collection

**Question:** Can you collect only some partitions?

**For conditionals (A | B | C):** NO
- Must handle all cases to produce a complete value
- Collecting only A-flow would be a partial function

**For lists:** YES
- Each partition is a complete, valid sublist
- `initial_flow` when collected → first element
- `subsequent_flow` when collected → tail of list

**Example - differentiation:**
```
Compute: current - previous (only valid for subsequent positions)

1. Spread the list flow
2. Partition into initial/subsequent
3. In subsequent flow: compute current - prev(spread)
4. Collect only subsequent flow
5. Result: list one element shorter than input
```

This is **filtering** - selecting which positions to include in output.

### Visual Model: 2D Spread Representation

**Axes:**
- **Horizontal:** Position in iteration (prev → current → next)
- **Vertical:** Computational steps

**Diagonal wires:** Show value continuity across iterations

**How it works:**
```
At position (horizontal=0, vertical=n): tap out previous value
Compute with it (step down vertically)
At position (horizontal=1, vertical=n+1): tap back into current value
```

**Example - running sum visualization:**
```
prev    current    next
 |        |         |
 •──────  |         |    (position 0, step 0: initial sum = 0)
  ╲      |         |
   ╲     •         |    (position 1, step 1: sum = 0 + elem[1])
    ╲   ╱ ╲        |
     ╲ ╱   ╲       •    (position 2, step 2: sum = prev + elem[2])
      •     ╲     ╱
             ╲   ╱
              ╲ ╱
               •
```

The diagonal line represents the sum value flowing forward through iterations, with each iteration adding a new element and producing the next sum.

---

## Flow Partitioning and Case Splits

### Types of Partitioning

Flows can be partitioned in different ways depending on what they represent:

#### Value-Based Partitioning (Sum Types)

**When:** Splitting on value alternatives: `A | B | C`

**Properties:**
- Partitions are mutually exclusive (value is A OR B OR C, never multiple)
- Must handle all cases to produce complete value
- Can join sibling partitions: AB-flow (handles both A and B cases)

**Example:**
```
Shape = Circle | Rectangle | Triangle

shape → [case_split] → Circle_flow
                    → Rectangle_flow
                    → Triangle_flow
```

#### Positional Partitioning (Lists)

**When:** Splitting on position in iteration

**Properties:**
- Each partition is a complete subset
- Can collect partial partitions (produces shorter list)
- Partitions represent different positions (first vs. rest, etc.)

**Example:**
```
list_flow → [partition_by_position] → initial_flow (first element)
                                   → subsequent_flow (remaining elements)
```

#### Structural Partitioning (Trees, ADTs)

**When:** Splitting on structural alternatives in recursive types

**Properties:**
- Partitions based on recursive structure
- Each partition handles different structural case
- Leaf vs. Branch, Nil vs. Cons, etc.

**Example:**
```
Tree = Leaf(value) | Branch(left, right)

tree → [structural_split] → Leaf_flow
                         → Branch_flow
```

### Partition Hierarchy and Scoping

**Scoping rules determine what values are accessible where:**

1. **Parent to child:** Values from parent flow accessible in all child partitions (incorporated as constants)

2. **Child isolation:** Values in a child partition only accessible within that partition and its descendants

3. **Sibling exclusion:** Sibling partitions are mutually exclusive - can't access each other's values

4. **Joining siblings:** Creates new flow where both sets of values are accessible

**Example:**
```
Flow A has value x
Split into A_case and B_case

In A_case: can access x (from parent) and compute y (child-specific)
In B_case: can access x (from parent) and compute z (child-specific)
           cannot access y (sibling A_case's value)

Join A and B: can access x, y, and z
```

### Nested Partitioning and Flattening

**Scenario:** Type with nested alternatives

```
Type = A | B
where B = B1 | B2

Effectively: A | (B1 | B2)
```

**After outer split:**
- A-flow exists
- B-flow exists

**After inner split of B:**
- A-flow still exists
- B-flow still exists
- B1-flow exists
- B2-flow exists

**Equivalence relationship:**
```
B-flow ≡ (B1-flow ∪ B2-flow)
```

**Using the equivalence:**
- Before splitting B: can do operations in B-flow
- After splitting B: B-flow still exists and can be used
- B-flow and {B1, B2} partition are **interchangeable**
- Can close using {A, B} OR {A, B1, B2} - both are complete

**Visual implications:**
- All wires remain visible
- System maintains equivalence relationships
- User chooses convenient representation for each operation

### Generality of Case Splitting

**Important:** Case splitting works uniformly regardless of how types are defined.

**It works the same whether:**
- Alternatives are defined together or as separate types
- You're splitting a top-level sum or a nested one
- The type is built-in or user-defined

**Principle:** Case split is a **generic operation** on any value with alternatives. The compiler doesn't make assumptions about "depth" - user decides how deep to split.

---

## Trees and Recursive Structures

### The Challenge

Trees are inherently multi-dimensional. Unlike lists where you can spread horizontally and compute vertically, trees branch in multiple directions. How do you iterate over a tree without requiring users to write recursive functions?

### Zipper-Based Iteration

A **zipper** is a data structure that provides a "focused" view of a recursive structure with full context.

**What a tree zipper provides:**
- **Current node** focus with its value
- **Path to root** (ancestors) - how we got here
- **Siblings context** - other children of the parent
- **Children** - as a list or individual subtrees
- **Parent** access - the node above

**Key advantage:** Access to context without manual recursive navigation

**Original structure always safe:** Zipper gives access to the original tree structure, which is always safe to access

### Computed Values in Zippers

**Extension:** You can create zippers not just for original structure, but for **computed values** within an iteration.

**Example - computing subtree size:**
```
For each node, compute: 1 + sum(child_subtree_sizes)
```

To access `child_subtree_sizes`, we need values that were computed earlier in the iteration. The zipper should provide access to these.

**Potential problem:** This creates risk of unsound recursion if not careful
- What if node A's value depends on node B's value, and B depends on A?
- Circular dependency would cause infinite recursion

**Solution:** Iteration context specifies what's accessible (see Soundness section below)

### Two-Layer Visual Pattern

Since we can't spread trees spatially like lists, we use a **temporal layering** approach:

#### Upper Layer (Previous Iteration)
- Shows relevant parts with **already-computed values**
- For post-order: children that have been processed
- For pre-order: parent that has been processed
- These values are read-only and available for use

#### Lower Layer (Current Iteration)
- Shows same tree structure
- Currently computing new values
- Can wire from upper layer values

#### Correspondence
- Faint dotted lines connect matching nodes between layers
- Visual structure mirrors (same tree shape)
- Users see this represents same node at different iteration stages

**Example - computing from children:**
```
Upper layer:
      [*]          
     /   \        
  [2]─── [4]───   
   │      │       
   v      v       
  val:2  val:4    ← already computed

Lower layer:
  [*] computing: 2 * 4 = 8
   (wires flow from upper layer children to lower layer parent)
```

**Important:** Shows the **computational pattern** that applies at each node, not the entire tree at once. Like defining a function, not tracing specific execution.

### Generic Pattern Definition

Users don't see specific values (2, 4, etc.). They define the **generic computation pattern**.

**Generic upper layer:**
```
      [node]
      /    \
  [child₁] [child₂] ... [childₙ]
     │        │           │
     v        v           v
  comp_val₁ comp_val₂  comp_valₙ  ← computed values from children
```

**Generic lower layer:**
```
Zipper context:
┌────────────────────────┐
│ node.value             │ ← data at this node
│ node.children: list    │ ← list of child zippers
│ node.parent: zipper?   │ ← optional parent zipper
└────────────────────────┘
         │
         └→ iterate over children list
              │
              └→ for each child: extract computed_value
                 combine values → current node's computed_value
```

**Partitioning for structural cases:**
```
Split on: node.children.length == 0?

Leaf partition:
  └→ return node.value

Branch partition:
  └→ compute from children's computed_values
```

### Soundness and Verification

**User's task:** Write computation using zipper accesses
- Specify which zipper components to use (parent values, child values, etc.)
- Wire together the computation pattern

**Compiler's task:** Verify soundness

#### Verification Process

1. **Analyze dependencies:** Which zipper accesses are used?
2. **Find topological ordering:** Is there a valid traversal order where all dependencies are satisfied?
3. **Accept if valid:** Compile to efficient iteration
4. **Reject if circular:** Fall back to lazy evaluation with warning

#### Valid Patterns (Examples)

✓ **Post-order style:** Compute from children → parent
- Dependencies flow upward in tree
- Process children first, then parent

✓ **Pre-order style:** Compute from parent → children
- Dependencies flow downward in tree
- Process parent first, then children

✓ **In-order style:** Compute from left child and parent → current
- For binary trees
- Left subtree, then node, then right subtree

✓ **Cross-sibling:** Compute from left sibling → right sibling
- Siblings processed left-to-right
- Each depends on previous

#### Invalid Patterns (Examples)

✗ **Circular parent-child:** Depend on both parent and children
- Can't determine which to compute first
- Would require solving circular dependency

✗ **Circular siblings:** Each sibling depends on the other
- No valid ordering exists

#### Lazy Evaluation Fallback

**When verification fails:**
1. Warning to user: "Cannot verify termination, using lazy evaluation"
2. Compile to lazy evaluation
3. May diverge at runtime if actually circular
4. Gives flexibility while providing safety when possible

**Why allow this:**
- Maximum flexibility for users
- Similar to how general recursion is handled in functional languages
- User can experiment and see if pattern terminates

### Automatic Derivation from Recursive ADTs

For ANY recursive algebraic data type, the compiler can mechanically derive iteration capabilities.

#### What Gets Derived

1. **Zipper** - Structural navigation and context
   - How to focus on a node
   - How to access parent, children, siblings
   - How to move focus

2. **Iteration flow** - Abstract iteration capability
   - Agnostic of unwinding depth (singles vs. pairs vs. triples)
   - Provides access to current position
   - Supports navigation operations

3. **Catamorphism/Anamorphism** - Fold and unfold operations
   - Catamorphism: recursively process structure to compute result
   - Anamorphism: build structure from seed value

#### Type Structure Handles Constraints

The recursive type definition itself encodes important constraints:

**Example - Red-Blue Lists:**
```
RedBlueList = RedNil | BlueNil 
            | RedCons(elem, RedBlueList)  -- can transition to blue
            | BlueCons(elem, BlueList)    -- must stay blue

BlueList = BlueNil | BlueCons(elem, BlueList)
```

**Constraint enforcement:**
- When at RedCons, tail is `RedBlueList` (can be red or blue)
- When at BlueCons, tail is `BlueList` (must be blue)
- Type system enforces one-way state transition

**Zipper derivation respects types:**
- Generic zipper derivation works without special cases
- Type constraints automatically maintained
- Partitioning (case splitting) exposes different tail types
- Operations in different partitions see appropriate types

#### Users Compose from Primitives

Unwinding depth and access patterns emerge from usage:

- **Spread** for positional operations
- **Case split** for alternatives (Leaf vs Branch, Nil vs Cons)
- **Window/prev/next** for access patterns
- **Partition** for state-specific operations

**Example:** List iteration depth
- Not specified by compiler
- Emerges from user's spread and window operations
- Can view singles, pairs, triples, arbitrary windows
- Same derived flow supports all patterns

### Heterogeneous Recursive Types

**Not all recursive types are homogeneous.** Consider the Red-Blue list above, or:

**Example - Expression Tree with Type Constraints:**
```
Expr = IntLit(Int)
     | BoolLit(Bool)
     | Add(Expr, Expr)      -- both children must be Int-typed
     | And(Expr, Expr)      -- both children must be Bool-typed
     | IfThenElse(Expr, Expr, Expr)  -- condition Bool, branches same type
```

**Generic derivation handles this:**
- Zipper provides context with typed children
- Case splitting exposes different structural alternatives
- Type constraints in each alternative prevent invalid constructions
- No special cases needed - types do the work

---

## Functions

### Purpose of Functions

In this language, functions serve specific purposes:

**What functions ARE for:**
1. **Code reuse** - Avoid duplicating the same diagram pattern
2. **Abstraction/naming** - Give complex operations meaningful names
3. **Modularity** - Organize large programs into comprehensible pieces

**What functions are NOT for (flows handle these):**
- Bodies of map/filter operations (flows handle element-wise processing)
- First-class values that get passed around (avoiding this complexity)
- Closures with captured scope (too complex for target users)

### Functions as Diagrams with Ports

**Core concept:** A function is a reusable sub-diagram with labeled connection points.

**Ports are connection points:**
- Not special "input/output" constructs
- Just places where the function diagram joins to surrounding context
- Can be value wires, flow wires, context connections
- Multiple inputs, multiple outputs, bidirectional - all supported naturally

**Example - Customer Health Score Function:**

```
Function: calculate_health_score

Ports:
Input:
  - recent_purchases (count)
  - historical_avg (average)
  - engagement_score (0-100)
  - support_sentiment (-1 to +1)
  - payment_status (enum)
  - days_as_customer (int)

Output:
  - health_score (0-100)

Internal diagram:
  - Normalize purchase frequency
  - Weight and combine metrics
  - Handle edge cases (new customers)
  - Apply business rules
```

**Usage contexts:**
1. Monthly reports - wire in individual customer data
2. Cohort analysis - wire in averaged cohort metrics
3. Alert system - wire in real-time computed values
4. A/B testing - wire in experiment group data

Each context provides different inputs, but the scoring logic is identical and encapsulated.

### Functions Interacting with Flows

Functions can interact with flows as naturally as with values:

**Functions can:**
- Take flows as input ports
- Create new flows internally
- Close flows passed to them
- Return flows from output ports
- Thread flows through (input flow → processing → output flow)

**Example - print_string:**

```
Function: print_string

Ports:
Input:
  - io_flow (flow identity wire)
  - text (string value)

Output:
  - io_flow' (flow identity wire, sequenced after print)

Purpose: Thread IO flow to maintain sequencing of print operations
```

**Usage:**
```
io_flow_0 → [print_string("Hello")] → io_flow_1 
                    ↑
                  text="Hello"

io_flow_1 → [print_string("World")] → io_flow_2
                    ↑
                  text="World"
```

The flow threading ensures prints happen in order.

### Function Interface Abstraction

Functions have two levels of representation:

#### Implementation Level (Inside the Function)
- Shows actual flow operations (uncollect, spread, reduce, etc.)
- Full diagram with all details
- What the function author sees and edits

#### Interface Level (Function Signature)
- Abstract description for users of the function
- Shows **flow operations** (transparent)
- Hides **data operations** (opaque)
- What function callers see

**Example - print_string interface:**
```
┌──────────────────────┐
│ io_flow ─┐           │
│          ├─ join ──→ io_flow'
│   text ──┘           │
│   (hidden: actual    │
│    print operation)  │
└──────────────────────┘
```

Users can see:
- IO flow gets joined with a print operation
- Text is consumed (flows in, doesn't flow out)
- Sequenced IO flow comes out

Users don't see:
- How text is formatted
- Implementation details of print command
- Internal string operations

### Why Keep Flow Operations Transparent?

**Critical for verification:**
- Flow structure is never hidden
- Users can trace flow dependencies through function calls
- Preserves "no time travel" guarantees
- Can verify soundness across function boundaries

**Principle:** Function interface is a **"flow skeleton with data holes"**
- You see all the flow wiring
- Just not the data transformations

### Interface Summarization

Interfaces can be simplified using proven-sound transformation rules:

#### Valid Summarization Patterns

**Pattern 1: Sequential Join Collapse**
```
flow → join₁ → flow' → join₂ → flow''
≡
flow → join → flow''
```

**Pattern 2: Identity Elimination**
```
flow → open → immediately close with same structure → flow
≡
flow → flow  (no-op, can be removed)
```

**Pattern 3: Data Operation Hiding**
```
value → compute₁ → compute₂ → compute₃ → result
≡
value → [hidden computation] → result
```

#### How Summarization Works

**Example - print_twice function:**

**Internal implementation:**
```
io_flow → [join: print_string("A")] → io_flow_1 
       → [join: print_string("B")] → io_flow_2
```

**Summarized interface:**
```
┌──────────────────────┐
│ io_flow ─┐           │
│    text1 ├─ join ──→ io_flow'
│    text2 ┘           │
│   (prints both)      │
└──────────────────────┘
```

From caller's perspective:
- IO flow goes in, sequenced IO flow comes out
- Two strings are consumed
- The fact that there are two internal joins doesn't matter externally

**Benefits:**
- Soundness guaranteed by proving each pattern preserves semantics
- Compositional - patterns can apply recursively
- Extensible - can add new patterns as needed
- Keeps interfaces clean while maintaining verification

---

## Custom Flows

### Motivation

Users need domain-specific flow abstractions for:
- **Organizational convenience** - Bundle related flows together
- **Enforcing correct usage** - Ensure operations happen in valid order
- **Domain modeling** - Represent domain concepts as flows

### Two Approaches to Defining Custom Flows

#### 1. Algebraic/Effect Flows (Lifecycle Pattern)

Define flows using creation, operations, and destruction.

**Example - Database Flow:**

```
Creation:
  open_database(io_flow, connection_string) 
    → (database_flow, io_flow')

Operations:
  query(database_flow, io_flow, sql) 
    → (database_flow', io_flow', result)
  
  update(database_flow, io_flow, sql) 
    → (database_flow', io_flow')

Destruction:
  close_database(database_flow, io_flow) 
    → io_flow'
```

**Properties:**
- Enforce operation ordering (can't query closed database)
- Automatically commutative (can cross freely - see Commutativity section)
- Used for: databases, file handles, HTTP servers, transactions

**Use cases:**
- Database connections
- File handles  
- Network sockets
- Transaction scopes
- Any resource with open/use/close lifecycle

#### 2. Syntactic Sugar Flows (Bundling Pattern)

Bundle existing flows for convenience.

**Example - Nested List Flow:**

```
Purpose: 
  Common pattern of nested list iteration
  Normally requires: uncollect outer → uncollect inner → process → recollect inner → recollect outer
  Want: single operation for organizational clarity

Definition:
  Bundles: (outer_list_flow, inner_list_flow)

Provides:
  open_nested_flow(nested_list) → nested_flow
  unbundle(nested_flow) → (outer_flow, inner_flow)
  rebundle(outer_flow, inner_flow) → nested_flow  
  close_nested_flow(nested_flow) → result
```

**Properties:**
- Inherits flow characteristics from components
- Must support unbundle/rebundle for fine-grained control
- Automatically lifts certain operations (see below)

**Use cases:**
- Nested data structure iteration
- Commonly-used flow combinations
- Domain-specific flow groupings

### Visual Representation: Vertical Segment Pattern

Custom flows use a vertical segment to show lifecycle:

```
[creation operation] ──┬── (top vertex)
                       │
                       ╎ flow_wire (vertical segment)
                       │
   [operation] ────────┤ (operations attach to segment)
   [operation] ────────┤
                       │
[destruction] ─────────┴── (bottom vertex)
```

**Benefits:**
- **Visually enforces lifecycle** - operations can only attach within segment
- **Prevents misuse spatially** - can't use operation outside valid scope
- **Shows operation scope** - clear what's inside vs outside the flow
- **Natural boundary** - creation at top, destruction at bottom

**Example - Database Flow Usage:**
```
[open_database] ──┬──→ io continues
                  │
                  ╎ database_flow
                  │
   [query] ───────┤
                  │
   [query] ───────┤
                  │
[close_database] ─┴──→ io continues
```

### Extending to State Machines

The vertical segment pattern generalizes to state machine protocols:

**Example - File Handle States:**
```
io_flow ──→ [open] ──┬──→ io_flow
                     │
                     ╎ opened_state
                     │
    [read] ──────────┤
    [write] ─────────┤
                     │
    [close] ─────────┴──┬──→ io_flow
                        │
                        ╎ closed_state
                        │
    [delete] ───────────┤
                        │
                     [end]
```

**Properties:**
- Each segment = state with specific valid operations
- Each vertex = state transition
- Multiple outgoing = branching states (commit vs rollback)
- Visual structure enforces protocol compliance

**Use cases:**
- Protocol state machines (network protocols, etc.)
- Resource lifecycle with multiple states
- Workflow states
- Game states

### Bundling with Other Flows

**Problem:** Many operations need multiple flow types

Example - Database operations:
- Need `database_flow` for type safety (ensure database is open)
- Need `io_flow` because they perform IO under the hood

**Solution:** Bundle flows together

```
database_bundle = (database_flow, io_flow)
```

**Usage:**

**Default (bundled):**
```
[open_database] → db_bundle
db_bundle → [query] → db_bundle'
db_bundle' → [query] → db_bundle''
```
Visually: one wire representing the bundle

**When you need to interleave IO:**
```
db_bundle → [unbundle] → database_flow
                      → io_flow
                      
database_flow ────┐
                  ├→ [query] → database_flow'
io_flow → [print] → io_flow' ─┐
                               ├→ [rebundle] → db_bundle'
database_flow' ────────────────┘
```

**Key points:**
1. Semantically, both flows always exist and thread through
2. Bundle is **syntactic sugar** for common case
3. Unbundle when you need to access flows separately
4. Type system ensures database flow only used when valid

### Operations on Bundled Flows

When you define a bundled flow, what operations are automatically available?

#### Auto-Lifted Operations (Treat Flow as Atomic Unit)

These operations work on the entire bundle as one unit:

```
commute(bundled_flow, other_flow)
  → Commutes entire bundle as single flow
  
join(bundled_flow, other_flow)
  → Joins entire bundle as single flow
```

**Why these auto-lift:** They don't need to distinguish between bundle components

#### Operations Requiring Unbundle

These operations need access to specific components:

- **Component-specific operations** - filter on outer vs inner list
- **Fine-grained control** - different operations on different components
- **All existing operations** on components remain available

**Pattern for using them:**
1. Unbundle to access components
2. Apply operations to specific components
3. Rebundle to continue

**Principle:** 
- Only lift operations that make sense on the bundle as a whole
- For everything else, provide unbundle/rebundle
- Don't try to auto-translate everything (too complex, too ambiguous)

### What to Specify When Defining Custom Flows

When defining a custom flow type, specify:

**1. Bundle structure** (if bundling)
- Which flows combine?
- Example: database_flow bundles with io_flow

**2. Lifecycle boundaries**
- Creation operation(s)
- Destruction operation(s)
- State transitions if state machine

**3. Bundle/unbundle operations**
- How to access components
- How to recombine

**4. Domain-specific operations**
- Operations on this flow type
- Example: query, update for database_flow

**Do NOT need to specify:**
- **Commutativity** - Automatically inferred from definition method
- **Lifted operations** - Automatic for atomic operations like commute/join
- **Component operation mappings** - Use unbundle instead

**Commutativity inference:**
- Algebraic/effect flows → Automatically commutative
- Bundled flows → Inherit from most restrictive component
- Derived flows (from recursive ADTs) → Structural (non-commutative)

---

## Configuration Scopes

### The Higher-Order Function Problem

Traditional functional programming uses higher-order functions extensively:
```
sort(list, comparator_function)
filter(list, predicate_function)
map(list, transform_function)
```

**Problem for visual language:**
- Passing functions as values is confusing for non-experts
- How do you visually represent a function waiting to be called?
- How do you draw "apply this function to each element"?

### Visual Alternative: Configuration Scopes

**Pattern:** Represent partial application as visual scope

**Traditional:**
```
result = higherOrderFn(data, functionParameter)
```

**Visual language:**
```
data → [open_operation] → operation_context
                       → operation_identity
                             ↓
        [configure behavior here]
                             ↓
operation_identity → [close_operation] → result
```

**What this represents:**
- Opening: "I'm going to do this operation, but not finishing yet"
- Middle: Use intermediate wires by feeding in configuration
- Closing: Finish the operation with configured behavior

### Properties of Configuration Scopes

**Like full flows:**
- Have open/close lifecycle
- Have flow identity wire (for scoping, ordering constraints)
- Visual representation with vertical segment

**Unlike full flows:**
- **Cannot join with self** (doesn't make sense to combine sorts)
- **Cannot commute** (not an execution context)
- **Cannot partition or spread** (not an iteration)
- **Just for configuring the operation**

**Visual representation:**
```
data → [open_sort] ──┬──
                     │
                     ╎ sort_context
                     │
[specify_key] ───────┤  (configure the sort)
                     │
           [close_sort] ──→ sorted_result
```

### Examples

#### Sort Operation

**Without configuration scope (higher-order):**
```
sorted = sort(list, λ(a,b) → a.age < b.age)
```

**With configuration scope:**
```
list → [open_sort] → sort_context
                  → sort_identity
                        ↓
          [specify: use age field for comparison]
                        ↓
sort_identity → [close_sort] → sorted_list
```

**Inside the scope:**
- Access to item being compared
- Wire operations to extract comparison key
- No explicit lambda needed

#### Filter Operation

(Assuming not using list flow for this)

**Traditional:**
```
filtered = filter(list, λ(x) → x > 10)
```

**Configuration scope:**
```
list → [open_filter] → filter_context
                    → item (value in context)
                          ↓
              [compute: item > 10] → boolean
                          ↓
            [close_filter] → filtered_list
```

#### Group-By Operation

**Traditional:**
```
grouped = groupBy(list, λ(x) → x.category)
```

**Configuration scope:**
```
list → [open_groupby] → groupby_context
                     → item
                          ↓
           [extract: item.category] → key
                          ↓
          [close_groupby] → map_of_groups
```

### Event-Driven Pattern: Server Flows

Configuration scopes naturally extend to event-driven programming.

**Example - HTTP Server:**

```
[open_http_server(port)] → server_flow
                        → request (value - represents one request)
                              ↓
                [access request.url, request.body, etc.]
                              ↓
                [compute response]
                              ↓
                [return response value]
                              ↓
server_flow ← [threads through for next request]
              ↓
         [close_server] → cleanup
```

**Characteristics:**

**Both configuration scope AND iteration flow:**
- Configuration: defines how to handle requests (like filter/map configuration)
- Iteration: processes stream of requests (like list iteration)

**Flow represents ongoing process:**
- Not a fixed collection (like list)
- Stream of events
- Each iteration processes one request

**Domain-specific operations:**
```
server_flow ──┬───→ [close_server] → cleanup
              │
              └───→ [get_server_stats] → connection_count, uptime
              │
              └───→ [broadcast_to_all] → (for websockets)
```

**Generalizes to:**
- Any callback-based API
- Event streams
- Async operations
- Message queues
- Reactive programming patterns

---

## Concurrency and Parallelism

### Parallel Pool Pattern

**Use case:** Producer feeding values to pool of consumers for work distribution

**Pattern:**
```
producer → [open_parallel_pool(n=3)] → pool_flow
                                    → datum
                                         ↓
                                  [process datum] → result
                                         ↓
pool_flow → [close_pool] → all_results (collection)
```

**From user's view:**
- Define processing for "one datum at a time"
- Single flow wire, single value wire
- Close to get collected results
- Looks sequential!

**Under the hood (runtime behavior):**
- N parallel workers competing for datums
- Each datum processed by exactly one worker
- Non-deterministic assignment (don't know which worker gets which datum)
- Results collected when pool closes
- Workers may execute concurrently

**Key insight:** Sequential-looking flow has **parallel execution semantics**

**Benefits:**
- User doesn't wire N separate worker paths
- Parallelism is in the flow type's behavior
- Clean abstraction over parallel execution

### Concurrent Fork-Join Pattern

**Use case:** Execute multiple operations concurrently, then combine results

**Example:** Make two HTTP requests concurrently

#### The Tupling Problem

**Traditional approach (bad):**
```
Fork:
  request1 = http_get(url1)
  request2 = http_get(url2)
  
Join:
  combined = (request1, request2)  -- forced to tuple!
  
Use:
  result1 = combined.first          -- then unpack
  result2 = combined.second
```

**Why this is bad:**
- Artificial data structure (tuple) for syntactic reasons
- Not semantic - responses aren't related, just happen to be concurrent
- Constant packing/unpacking in complex programs
- Violates principle: "visual structure reflects semantic relationships"

#### Visual Solution: 2D Join Pattern

The solution exploits separation of flow and value wires:

**Vertical dimension (flow identities merge):**
```
request1_flow ──┐
                ├─→ joined_flow
request2_flow ──┘
```

**Horizontal dimension (value wires pass through independently):**
```
           response1 ──────→ response1
[JOIN]     
           response2 ──────→ response2
```

**Combined visualization:**
```
request1_flow ──┐      response1 ─────→ response1
                ├─→ [JOIN] 
request2_flow ──┘      response2 ─────→ response2
```

**How it works:**

1. **Join operation is 2D:**
   - Merges flow identity wires vertically
   - Lets value wires pass through horizontally

2. **Spatial separation maintains identity:**
   - response1 and response2 are separate wires
   - Positioned horizontally to show they're distinct
   - No artificial data structure

3. **Synchronization is explicit:**
   - Join operation is the sync barrier
   - Both flows must complete before continuing below
   - Visual structure makes this clear

**Key insight:** Flow wires represent execution context (which merges), value wires represent data (which stays separate)

### Concurrent Execution Context

**How to create concurrent flows:**

```
concurrent_execution_context
    ├─→ [fork] → request1_flow
    └─→ [fork] → request2_flow
```

**Properties:**

**Neither flow inherits from the other:**
- request1_flow doesn't depend on request2_flow
- request2_flow doesn't depend on request1_flow
- Both inherit from parent concurrent_execution_context

**Compiler recognizes independence:**
- Can schedule in parallel
- No ordering constraint between them
- Both can execute simultaneously

**Join doesn't violate "no time travel":**
- Flows were independent from construction
- Join doesn't retroactively create dependency
- Just synchronization point

**After join:**
- Single flow wire (merged execution context)
- Multiple value wires (separate data)
- Both wires available for independent use below join point

### Comparison with Conditional Bundles

**Conditional bundle (sequential, mutually exclusive):**
```
value → [case_split] → A-flow (OR)
                    → B-flow
                         ↓
                    [join] → result
```
- Only one branch executes
- Mutually exclusive
- Sequential

**Concurrent bundle (parallel, both execute):**
```
→ [fork_concurrent] → request1-flow (AND)
                   → request2-flow
                         ↓
                    [join_concurrent] → (result1, result2)
```
- Both branches execute
- Concurrent
- Both results available

---

## Flow Commutativity

### The Crossing Problem

**Observation:** In a 2D visual layout, sometimes flow wires need to cross.

**Example:**
```
db1_flow → [operation on db1] ────→ [another operation on db1]
                 ↓ (crossing!)         ↑
db2_flow → [operation on db2] ─────────┘
```

**Question:** Is this allowed? Should flows be able to cross?

### Why Some Flows Can't Cross

**For list flows, crossing is problematic:**

```
list1_flow → [process] ───→ [process]
                ↓ (crossing!)  ↑
list2_flow → [process] ────────┘
```

This would violate the "no time travel rule":
- Can't retroactively determine which loop nests within another
- Crossing would mean: first iterate list1, then in middle switch to list2, then back to list1
- Iteration structure must be determined at construction time

**For tree flows, similar problem:**
- Structural relationships matter
- Can't arbitrarily interleave structural operations

### Why Some Flows CAN Cross

**For database flows, crossing is fine:**

```
db1_flow → [query db1] ────→ [query db1 again]
              ↓ (crossing OK!)   ↑
db2_flow → [query db2] ─────────┘
```

**Why this works:**
- db1 and db2 are independent resources
- Operations on db1 don't affect db2
- No structural relationship to violate
- Operations commute

### Two Categories of Flows

#### Structural Flows (Cannot Cross)

**Examples:** List flows, tree flows, recursive ADT iterations

**Characteristics:**
- Have inherent positional/hierarchical semantics
- Operations depend on structure
- Iteration order matters
- Position in structure is meaningful

**Restriction:** Cannot cross other flows

**To interleave:** Need explicit commutation operation
- Represents semantically significant reordering
- Example: "sequence this list of database operations"

#### Effect Handle Flows (Can Cross Freely)

**Examples:** Database flows, IO flow, file handles, sort contexts, HTTP servers

**Characteristics:**
- Exist to enforce operation ordering/correctness
- No structural relationship between independent handles
- Operations on independent handles commute
- Purely for managing effects

**Freedom:** Can cross other effect handle flows freely

**No commutation needed:** Would be a no-op, would clutter diagram

### Visual Rules

```
✓ db1_flow crosses db2_flow
  (both effect handles, commute)

✓ db_flow crosses io_flow  
  (both effect handles, commute)

✗ list_flow crosses tree_flow
  (both structural, cannot cross, need explicit commute)

✗ list_flow crosses db_flow
  (structural + effect, cannot cross, need explicit commute)
```

### Compositional Commutativity

**For bundled flows:** "Most restrictive wins"

**Effect + Effect = Effect (commutative)**
```
db_flow + io_flow → db_bundle
Can cross other effect flows freely
```

**Structural + Effect = Structural (non-commutative)**
```
list_flow + io_flow → list_io_bundle
Cannot cross, must use explicit commutation
```

**Structural + Structural = Structural (non-commutative)**
```
outer_list_flow + inner_list_flow → nested_list_flow
Cannot cross, structural semantics dominate
```

**Why this works:**
- Simple rule: if ANY component is structural, bundle is structural
- Compositional: can determine bundle properties from components
- Safe: conservative approach (more restrictive is safer)

### Automatic Inference

**No user annotation needed!** Commutativity is inferred from definition method:

**Algebraic/effect flows** (defined with open/operations/close):
- Examples: database, file handle, sort context
- Automatically commutative
- Can cross freely

**Derived flows** (from recursive ADTs):
- Examples: list iteration, tree traversal
- Structural
- Cannot cross

**Bundled flows** (syntactic sugar):
- Inherit from components
- Most restrictive wins

### Benefits

**For users:**
- Don't have to carefully thread independent effect handles
- Natural diagram layout possible
- Only structural flows require care

**For language:**
- Consistent rules
- Compositional properties
- Type-safe

**Example - Natural Usage:**
```
Can write:
  db1_flow → operations ─┐
  db2_flow → operations ─┤ crossing naturally
  file_flow → operations ┘

Instead of forcing:
  db1_flow → op → commute ───┐
  db2_flow → commute → op ───┤ artificial ordering
  file_flow → commute → op ──┘
```

---

## Key Innovations Summary

### 1. Flow/Value Wire Separation

**Innovation:** Separate wires for execution context (flow) vs data (values)

**Enables:**
- 2D join pattern (merge flows, keep values separate)
- Multiple returns without artificial tupling
- Clean flow composition without constraining value operations
- Clear separation of "when" (flow) vs "what" (value)

**Example:**
```
Concurrent join:
  - Flow wires merge vertically (execution contexts combine)
  - Value wires pass through horizontally (data stays distinct)
  - No tuple needed!
```

### 2. Spread Operations

**Innovation:** Make any value in a flow into a spread with positional structure

**Enables:**
- Flexible positional access (prev, next, window)
- User-defined iteration patterns
- Not baking in specific patterns (like "map over list")
- Compositional building blocks

**Example:**
```
Instead of: rigid "iterate over list" operation
Provide: spread + prev/next + window + reduce
Users compose: exact pattern they need
```

### 3. Compositional Partitioning

**Innovation:** Unified model for partitioning flows (sum types, positions, structure)

**Enables:**
- Consistent treatment across different partition types
- Equivalence relationships (B-flow ≡ {B1, B2})
- Partial collection for lists
- Clear scoping rules for values

**Example:**
```
Same partition concepts work for:
  - Conditional branches (A | B | C)
  - List positions (initial | subsequent)
  - Tree structure (Leaf | Branch)
```

### 4. Automatic Derivation from Type Definitions

**Innovation:** Mechanically derive iteration capabilities from recursive ADT definitions

**Enables:**
- No special cases for list, tree, etc.
- User-defined types get iteration for free
- Consistent zipper-based approach
- Type constraints automatically enforced

**Example:**
```
Define: Tree a = Leaf a | Branch (Tree a) (Tree a)
Get automatically:
  - Zipper for navigation
  - Iteration flow
  - Catamorphism/anamorphism
```

### 5. Configuration Scopes

**Innovation:** Visual alternative to higher-order functions using open/configure/close pattern

**Enables:**
- No function values to pass around
- Visual representation of partial application
- Accessible to non-experts
- Natural for event-driven programming

**Example:**
```
Instead of: sort(list, compareFn)
Use: open_sort → configure comparison → close_sort
```

### 6. Automatic Flow Commutativity

**Innovation:** Infer whether flows can cross from how they're defined

**Enables:**
- Natural diagram layout
- No manual annotation needed
- Compositional rules
- Safety (structural flows protected, effect handles flexible)

**Example:**
```
Effect flows (db, file, IO): cross freely
Structural flows (list, tree): explicit commutation needed
Automatic from definition!
```

### 7. Visual Semantics

**Innovation:** 2D layout carries semantic meaning about relationships and dependencies

**Enables:**
- Horizontal = iteration position
- Vertical = computational steps
- Diagonal = value continuity
- Spatial structure prevents circular dependencies

**Example:**
```
List iteration:
  - Spread horizontally (positions)
  - Compute vertically (steps)
  - Diagonal wires (value flows forward)
```

### 8. No Artificial Packing

**Innovation:** Multiple wires maintained through spatial position, not data structures

**Enables:**
- No tupling just to return multiple values
- Wire identity preserved visually
- Natural representation of multiple results
- Visual structure reflects semantic relationships

**Example:**
```
Concurrent requests:
  - Two response wires (not tuple)
  - Spatially separated
  - Join operation synchronizes, doesn't pack
```

### 9. Zipper-Based Iteration

**Innovation:** Provide full context without requiring manual recursive steps

**Enables:**
- Access to parent, children, siblings
- Computed values in context
- Flexible traversal patterns
- No explicit recursion needed

**Example:**
```
Tree zipper provides:
  - Current node
  - Path to root
  - Children
  - User: wire together computation
  - System: verify soundness or use lazy evaluation
```

### 10. Custom Flow Types

**Innovation:** User-extensible flow system with automatic property inference

**Enables:**
- Domain-specific abstractions
- Lifecycle enforcement
- Automatic commutativity inference
- Bundling with inherited properties
- State machine patterns

**Example:**
```
Define database flow:
  - Open/query/close operations
  - Automatically commutative
  - Can bundle with IO
  - Enforces correct usage
```

---

## Design Philosophy Summary

The language embodies several key philosophical commitments:

**1. Accessibility without sacrificing power**
- Make common patterns easy (iteration, branching)
- Make complex patterns possible (custom flows, recursion)
- Hide complexity in primitives, not in user code

**2. Visual structure is semantic**
- Spatial layout reflects relationships
- No artificial visual constraints
- 2D layout carries meaning

**3. Explicit is better than implicit**
- Flow ordering determined at construction
- No "time travel" semantics
- Clear flow structure preserved through abstractions

**4. Compositionality**
- Small primitives combine into complex patterns
- Properties compose (commutativity, bundling)
- Consistent rules across different contexts

**5. Type-driven derivation**
- Let types do the work
- Automatic inference where possible
- User definition determines properties

**6. Visual verification**
- Flow structure always visible
- Can trace dependencies
- Can verify soundness or provide warnings

This creates a language where:
- Non-experts can build complex programs
- Visual structure helps understanding
- Type system prevents errors
- Experts have power and flexibility
- Common patterns are concise
- Complex patterns are achievable
