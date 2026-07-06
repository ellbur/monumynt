# Visual Flow-Based Programming Language Design

## Overview

This document describes a visual programming language with a unique approach to control flow that "turns blocks inside out." Instead of traditional scoped blocks (if/else, loops, functions), the language represents control flow through explicit flow operations where the "interior" of what would be a block becomes a manipulable value in the visual flow graph.

## Core Philosophy

### Blocks Turned Inside Out

Traditional programming languages use scoped blocks to contain code:
```
for (item in list) {
  // code inside here
}
```

This language inverts that relationship. The "inside" of the block becomes explicit values and flows that can be manipulated, combined, and transformed. Control flow is not implicit containment but explicit wiring of flow identities through the diagram.

### Visual Structure Has Semantic Meaning

Unlike runtime data flow diagrams, the entire static graph structure has semantic meaning. Wires represent structural/symbolic elements rather than runtime data flows. The complete graph must be constructed before it has executable semantics.

### Explicit Over Implicit

The language favors explicit operations over automatic inference. It aims to be no more magical or unpredictable than typical functional programming, just expressed differently through visual composition. Users must explicitly choose operation nodes rather than relying on type inference or constraint solving to determine behavior.

## Fundamental Concepts

### 1. Flow Identities

Flows are first-class entities in the language, represented as wires that can be manipulated and composed.

**Basic Flow Opening (Uncollect):**
```
ls -> $ => a, x
```
- `ls`: input list
- `$`: uncollect operation that "opens" the list into a flow
- `a`: value wire (current element)
- `x`: flow wire (flow identity)

The `$` operator produces two outputs:
1. A value representing the current element
2. A flow identity that tracks the iteration context

**Flow Closing (Recollect):**
```
b, x -> @ => out
```
- `b`: transformed value
- `x`: flow identity
- `@`: recollect operation that "closes" the flow back into a list
- `out`: resulting list

### 2. Flow Dependencies

Every value in the language has an associated flow dependency - the flow context(s) it belongs to. Flow dependencies must be aligned before values can be combined in operations.

**Flow-Independent Values (Constants):**
Constants exist outside any flow context and must be explicitly captured into a flow before use.

**Capture Operation:**
```
x -> CAPTURE(b) => b_in_flow
```
Takes a constant `b` and a flow identity `x`, producing the constant in the flow's context.

**Example - Adding Constant to List Elements:**
```
ls -> $ => a, x
x -> CAPTURE(2) => two_in_flow
a, two_in_flow -> ADD => result
result, x -> @ => out
```

### 3. Multiple Flows and Ordering

When multiple flows exist, their ordering relationship must be explicitly established. Closing operations cannot retroactively determine flow ordering.

**The No Time Travel Rule:**
> Flow ordering must be established at construction time, not determined retroactively by later closing operations.

**Nested Flows - Simple Case:**
```
outer_list -> $ => inner_list, x_outer
inner_list -> $ => a, x_inner
// Process a
a, x_inner -> @ => processed_inner
processed_inner, x_outer -> @ => result
```

In this case, the nesting is clear because `inner_list` is produced by the outer flow.

**Independent Flows - Ordering Problem:**
```
list1 -> $ => a1, x1
list2 -> $ => a2, x2
// x1 and x2 have no ordering relationship!
```

When two flows are opened independently (side by side), there's no inherent ordering between them.

### 4. Solutions to Flow Ordering

**Solution 1: Explicit Derivation**
Treat the second flow as visually deriving from the first, even if semantically independent:
```
list1 -> $ => a1, x1
x1 -> DERIVE -> list2 -> $ => a2, x2
```

This establishes that `x2` is nested within `x1` at creation time.

**Solution 2: Vertical Positioning (Partial Solution)**
Use vertical position where lower flows are "inner" and higher flows are "outer." However, this creates a time travel problem: the nesting structure isn't determined until flows are closed, violating our design principle.

**Preferred Approach:**
Explicit derivation is preferred because it establishes nesting relationships immediately at construction time.

### 5. Bringing Values Into Flows

When values from different flow contexts need to interact, explicit operations align their flow dependencies.

**Nesting Operation:**
```
a, y, x -> NEST_WITHIN => a_nested, y_nested
```
Takes a value and flow from one context and nests them within another flow `x`. Semantically equivalent to closing flow `y` and reopening it nested within `x`.

**Cross-Flow Operations Require Alignment:**
Before combining values from different flows, their flow dependencies must be aligned through CAPTURE or NEST_WITHIN operations.

## Flow Operations

### Visual Constraint: No Crossing Without Explicit Operations

Flow wires cannot cross visually without explicit operations defining the crossing semantics. This ensures visual clarity and prevents ambiguous interpretations.

### Sequence Operations (Applicative)

Sequence operations coordinate multiple flows, establishing ordering relationships.

**Example - List of Optionals to Optional of List:**
```
outer_list -> $ => optional_val, x_outer
optional_val -> $ => inner_val, x_inner

inner_val, x_inner, x_outer -> SEQUENCE => val_seq, y_outer, y_inner
```

The SEQUENCE operation:
- Takes values and flows from both contexts
- Produces new flows with flipped ordering
- Transforms values to match new flow contexts
- Implements "fail fast" semantics for optionals

### Monadic Join Operations

Join operations flatten nested flow structures.

**Joined Uncollect (Upfront Joining):**
```
outer_list -> $ => inner_list, x_outer
inner_list, x_outer -> $_JOINED => a
a, x_outer -> @ => flattened_list
```

The `$_JOINED` operation establishes joining at creation time.

**Post-hoc Join Operation:**
```
outer_list -> $ => inner_list, x_outer
inner_list -> $ => a, x_inner

a, x_inner, x_outer -> JOIN => a_joined
a_joined, x_outer -> @ => flattened_list
```

The JOIN operation:
- Takes the inner value, inner flow (consumed), and outer flow (referenced)
- Closes the inner flow
- Produces a value in the outer flow context only
- Semantically equivalent to close-then-reopen with `$_JOINED`

**Critical Point:** JOIN must take values as input, not just flow identities, to properly transform values when changing flow contexts.

## Conditional Branching

### Flow Bundles

Conditional branches create flow bundles - sets of flows that must be closed together.

**Optional Value Branch:**
```
optional_val -> BRANCH => nothing_flow, present_flow, inner_value
```
- `nothing_flow`: flow identity for Nothing case
- `present_flow`: flow identity for Some case  
- `inner_value`: unwrapped value (depends only on `present_flow`)

**Closing a Flow Bundle:**
```
value_for_nothing, nothing_flow, value_for_present, present_flow -> CLOSE_BUNDLE => result
```

Both branches must be closed together, providing values for each case.

### Partial Conditionals

Partial conditionals open only some branches of a conditional.

**One-Sided Branch:**
```
optional_val -> PARTIAL_BRANCH => present_flow, inner_value
```

**Monadic Semantics:**
When closing a partial branch:
- If runtime value matches the opened branch: execute flow and produce result
- If runtime value is the other branch: flow doesn't execute, propagate empty/nothing

**Example - Default Value:**
```
optional_val -> PARTIAL_BRANCH => present_flow, inner_value

present_flow -> CAPTURE(5) => five_in_nothing_flow
inner_value, present_flow, five_in_nothing_flow, nothing_flow -> CLOSE => result
```

Note: The constant 5 must be captured into the nothing flow before closing.

### Visual Clarity Advantage

In Haskell, left-biased vs right-biased monad instances are nominal (determined by name). In this visual language, the behavior is structural - you can see which branches are opened.

### Multiple Possible Semantics

Closing a partial branch could have different semantics:
1. Monadic: unopened branch values pass through unchanged
2. Nothing: unopened branch values become Nothing
3. Other possibilities...

Different CLOSE operations implement different semantics.

### Partial Conditional Merging

**Three-Way Branch with Partial Close:**
```
three_way_val -> BRANCH => a_flow, b_flow, c_flow, a_val, b_val, c_val

a_val, a_flow, b_val, b_flow -> PARTIAL_CLOSE => ab_val, ab_flow
```

Creates an intermediate merged branch (AB) that can:
- Be captured into constituent branches (A or B) as a "parent scope"
- Participate in further merging
- Create hierarchical scope structures

The algebra of partial merging is complex and requires careful formalization (future work).

## Filtering and Multiple Outputs

### Filtering with Partial Conditionals

```
list -> $ => a, x
a -> CHECK_CONDITION => bool_val
bool_val -> PARTIAL_BRANCH => true_flow, a_kept

a_kept, true_flow, x -> JOIN => joined_flow, filtered_value
filtered_value, joined_flow -> @ => filtered_list
```

The JOIN operation combines the partial conditional flow with the original list flow. Elements that fail the condition don't execute through the partial branch.

### Multiple Flow Outputs

A single flow can be closed multiple times to produce multiple outputs:

```
list -> $ => a, x

a -> TRANSFORM1 => b
b, x -> @1 => list1

a -> TRANSFORM2 => c
c, x -> @2 => list2
```

**Semantics:** Single iteration producing multiple outputs per element (like one loop with multiple append operations).

### Partitioning with Full Conditionals

```
list -> $ => a, x
a -> IS_EVEN_BRANCH => even_flow, odd_flow, a_even, a_odd

a_even, even_flow, x -> JOIN1 => joined_even, even_val
even_val, joined_even -> @1 => evens_list

a_odd, odd_flow, x -> JOIN2 => joined_odd, odd_val
odd_val, joined_odd -> @2 => odds_list
```

Using a full conditional (exhaustive, mutually exclusive branches) makes it visually clear that each element goes to exactly one output.

**Advantage Over Functional Languages:**
This pattern is tedious in languages like Haskell, requiring either multiple traversals or verbose manual folds. The visual structure naturally expresses multi-way partitioning.

## Design Principles Summary

### 1. Explicit Flow Identity
Flows are first-class entities with explicit identities (wires) that can be manipulated.

### 2. No Retroactive Semantics (No Time Travel)
Flow ordering and nesting relationships must be established at construction time, not determined by later operations.

### 3. Explicit Capture and Alignment
Values from different flow contexts cannot be directly combined. Explicit operations (CAPTURE, NEST_WITHIN, JOIN) align flow dependencies.

### 4. Visual Enforceability
Flow crossings are visually detectable, providing immediate feedback about structural violations.

### 5. Structural Semantics
Where possible, semantics should be determined by visual structure rather than nominal types or names.

### 6. No Implicit Magic
The language should be no more magical than typical functional programming - explicit operation nodes are required rather than automatic inference.

### 7. Complete Graph Semantics
The entire graph structure has meaning only when complete. Intermediate wires are symbolic/structural, not runtime values.

## Future Work and Open Questions

### 1. Pull-Based to Explicit Transformation

**Challenge:** Can we allow users to write in a more flexible, pull-based style where nesting isn't specified upfront, then automatically transform it into explicit form?

**Approach:**
- User writes using simple flow-only operations
- Automatic elaboration pass inserts NEST_WITHIN, CAPTURE, and value transformations
- Resolves all flow dependencies and establishes ordering

**Benefits:**
- User convenience while maintaining semantic clarity
- Separation of concerns: users think in terms of logic, compiler handles mechanics

**Open Questions:**
- What are the transformation rules?
- How to handle ambiguous cases?
- When is automatic elaboration impossible?

### 2. Flow Bundle Type Checking

> **Taken up** (2026-07-06): `plans/bundle-provenance-design.md` works this out in current vocabulary (context paths compared at combining nodes; one check with time-travel and bundle-mixing as its two clash flavors), including the error-message question. It also gives a partial answer to #3 below (every bundle in the design record is a partition of a parent flow's firings — exclusive by definition) and a sketch toward #4 (merged branches as cell sets).

**Challenge:** Prevent invalid mixing of flows from the same conditional bundle while allowing valid nesting of flows from different bundles.

**Requirements:**
- Track flow provenance (which bundle each flow came from)
- Context-dependent validity:
  - Flows from same Either bundle: cannot be nested
  - Flows from different Either bundles: can be nested
- Distinguish between different bundle types (conditional vs other semantic structures)

**Open Questions:**
- How to track bundle relationships through operations?
- What type system can express these constraints?
- How to give clear error messages?

### 3. General Flow Bundle Semantics

**Observation:** Flow bundles are a general structural concept, not just for conditionals.

**Speculation:**
- Other bundle types where same-bundle nesting is valid
- Different semantic rules for different bundle types
- Compositional algebra of bundle operations

**Open Questions:**
- What other bundle types exist?
- What operations are valid on general bundles?
- How do different bundle types interact?

### 4. Partial Conditional Algebra

**Challenge:** Formalize the algebra of partial conditional merging.

**Complexity:**
- Multiple levels of partial merging (AB, AC, BC, ABC, etc.)
- Capturing from merged branches into constituent branches
- Ensuring type safety and semantic correctness

**Open Questions:**
- What operations are valid on partially merged conditionals?
- How to track scope hierarchies?
- What are the composition laws?

### 5. Implementation of Flow Junctions

**Question:** When a single flow is closed multiple times (multiple outputs), does this require special runtime implementation?

**Considerations:**
- Is iteration happening once or multiple times?
- How are multiple outputs coordinated?
- Performance implications

**Note:** This was deferred during design discussion but needs resolution for implementation.

### 6. Vertical Positioning as Syntax Sugar

**Idea:** Could vertical positioning be used as convenient notation that gets elaborated into explicit derivation?

**Approach:**
- Users position flows vertically
- System automatically inserts derivation relationships based on position
- Maintains visual clarity while ensuring explicit semantics

**Challenges:**
- What happens when position is ambiguous?
- How to handle 2D layouts vs strict vertical ordering?
- When should users be forced to use explicit operations?

## Comparison to Traditional Paradigms

### vs. Imperative Loops
**Traditional:**
```
for (item in list) {
    item = item + 2;
    result.append(item);
}
```

**Flow Language:**
```
ls -> $ -> (+2) -> @ => result
```

Control flow is explicit wiring rather than implicit block scope.

### vs. Functional Programming
**Haskell:**
```haskell
map (+2) list
filter even list
partition even list
```

**Flow Language:**
- Similar expressiveness
- Visual structure makes flow dependencies explicit
- Multi-way operations (like partition) are more natural
- Same level of predictability, different representation

### vs. Dataflow Languages
**Typical Dataflow:**
- Nodes process runtime data flowing through
- Wires carry actual values during execution

**Flow Language:**
- Wires are symbolic/structural
- Entire graph has meaning only when complete
- Flow identities are compile-time constructs

## Notation Conventions

Throughout this document:
- `->` denotes wiring/connection
- `=>` denotes naming (not an operation)
- `OPERATION` denotes operation nodes
- `value_wire` denotes value wires (lowercase)
- `flow_wire` denotes flow identities (lowercase with x, y prefixes typically)

## Conclusion

This visual programming language represents a novel approach to expressing computation by making control flow an explicit, first-class concept. Through flow identities, explicit capture operations, and visual enforcement of structural constraints, it aims to provide the rigor and predictability of functional programming while leveraging the clarity that visual representations can provide.

The language maintains several key principles:
- No retroactive determination of semantics (no time travel)
- Explicit operations over implicit inference
- Visual structure reflects semantic meaning
- Complete graphs define executable programs

Many aspects remain to be formalized, particularly around automatic elaboration, type checking, and the algebra of partial conditionals. However, the core concepts provide a solid foundation for a practical visual programming language that "turns blocks inside out."
