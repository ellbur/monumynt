# The core model

This is the short statement of the core that everything else hinges on.
The seven principles behind it are in `language-design-philosophy.md`
(read that first); the code samples here use the textual syntax from
`textual-representation-design.md`.

## Blocks turned inside out

Traditional languages contain control flow in scoped blocks. The body of
a loop or an `if` lives *inside* a construct, and what is visible inside
differs from what is visible outside. This language inverts that. The
interior of what would be a block becomes explicit values and flows,
wired through the diagram. Control flow is not implicit containment; it is
explicit wiring. No construct makes an expression's interior scope differ
from its exterior.

The whole static graph is the program. Wires are structural, not runtime
data flowing through boxes: the graph has meaning when complete, and the
intermediate wires are symbolic — a wire stands for "the element here,"
not a particular value at a particular moment.

## Value wires and flow wires

Every place a flow happens produces two distinct sorts of wire:

- A **value wire** carries data — an element, a branch's payload, a
  result. Values are computed on, transformed, wired onward.
- A **flow wire** carries the execution context itself — *when, and how
  often, does this happen*. It is used only by flow operations (collect,
  join, commute) and cannot be read as a value.

The separation is load-bearing. It is what lets combining constructs pass
values through as themselves (see "Barriers, not bottlenecks"), and it
makes misuse impossible to write down: you cannot apply a function to a
flow wire, because a flow wire is not a value.

## Uncollect and collect

These are the two fundamental operations. Everything iterative is built
from them.

- **Uncollect** — written `open` in the text, `Open` in the code — opens
  a value into a flow. A list opens into a per-element flow; a case-typed
  value opens into a bundle of case flows; an option opens into a
  fires-or-not flow. Out come one or more value ports and a flow port.
- **Collect** — written `collect`, `Close` in the code — terminates a
  flow and produces a value. Collecting a list flow gathers the
  per-element values back into a list; collecting a case flow supplies
  one value per case.

The simplest complete program: open a list, transform each element,
collect back to a list.

```
double = js "x => x * 2"
[1, 2, 3] -> open list -> double -~> collect => out    -- out = [2, 4, 6]
```

`-> open list` opens the list into a per-element flow (the element rides
the `->` wire; the flow rides alongside). `-> double` applies to each
element. `-~> collect` closes the flow — the `-~>` arrow marks a value
crossing *together with its flow* — gathering `[2, 4, 6]`.

One flow may be collected any number of times. This is **multi-close**:
each collect is an independent consumer of the same one logical iteration
— one loop with multiple outputs, not multiple loops. Taps (`|`) let you
do this without naming anything:

```
xs -> open list -> | double -~> collect => doubled
| -> triple -~> collect => tripled
```

Both collects close the same list flow; the element reaches both chains
through the tap. (The current compiler realises each collect as its own
self-contained thunk; see `lazy-compile-design.md`.)

The names uncollect/collect are the canonical ones; the code still says
`Open`/`Close`, and some older examples use the informal glyphs `$`
(uncollect) and `@` (collect).

## No time travel

Flow ordering and nesting are fixed at construction time. They are never
determined retroactively by an operation added later. This is the rule
that makes the drawn structure trustworthy: what you see nested *is*
nested.

The refined form of the rule governs **readings, not gestures**
(`time-travel-programs-design.md`). You may draw an under-committed
program — sibling opens with no stated order, a termination left
deferred — and the editor completes it by published rules, shown faint.
But every *reading* of a program satisfies no-time-travel unconditionally.

## Bringing values into a flow

A value from outside a flow — a constant, or a value from an enclosing
context — does not need any transport machinery. Provenance's prefix rule
admits an enclosing context's value directly, so `add(ten)` inside a loop
just works:

```
ten = 10
[[1, 2], [3]] -> open list -> open list -> add(ten) -~> join -~> collect
=> out                                                 -- [11, 12, 13]
```

Where you want to name the step explicitly, **Incorporate** brings a
value into a flow context — a primitive in its own right. What Incorporate
must *not* be used for is nesting two *sibling* opens (two independently
opened lists) inside one another; that would erase their mutual
independence. The completion for sibling opens inserts a **Cross** node
instead (`product-flows-design.md`).

## Join, and filtering as join

**Join is a binary flow operation** with asymmetric operands, an outer
and an inner. It absorbs the inner flow's firings into the outer flow.

- Flattening a nested list is `join(list, list)` — the `-~> join` in the
  example above merges the inner list's elements into the outer
  iteration, so two levels of list collapse to one.
- **Filtering** is `join(list, case flow)`: keep the elements for which a
  case alt fires, dropping the rest. There is no separate filter
  primitive — filtering is join of a list flow with a case-alt flow.

```
xs -> open list -> split parity of Even, Odd
  Even: -~> join -~> collect => evens        -- the even elements, as a list
  Odd:  -~> join -~> collect => odds
```

(The code still implements join as a per-collect annotation,
`Joined(flowRef)`, which lost the second operand; that spelling is
superseded at the design level by `lazy-stream-join-design.md`.)

## Case splits and bundles

Opening a case-typed value produces a **bundle**: the parent flow's
firings are partitioned into sibling case flows, exactly one of which
fires per firing of the parent. The siblings are mutually exclusive — a
given firing is `Even` or `Odd`, never both.

Because they are mutually exclusive, sibling flows may meet again only at
collecting nodes, never at ordinary combining nodes. Trying to add
`Even`'s value to `Odd`'s value is meaningless (they never coexist), and
the check that catches it is bundle provenance
(`bundle-provenance-design.md`).

```
maybes -> open list -> split isJust of Just, Nothing
  Just:    -> double
  Nothing: 0
-~> collect                    -- the case close: one value per alt, exhaustive
-~> collect                    -- closes the list flow
=> out                         -- e.g. [2, 0, 10]
```

You do not need a special construct to use only *some* branches of a
bundle — terminations of a partially-used bundle are handled by the
**partial collect** (`partial-collect-design.md`), of which the
exhaustive case collect above is the fully-covering instance.

Positional filtering falls out of this. Collecting only some positions of
a partitioned list flow yields a shorter list — differentiation, for
instance, computes `current − previous` and collects only the positions
that *have* a previous. What is **not** part of the model: using a
first-position case as an accumulator seed. The initial value of a
loop-carried accumulator belongs outside the flow, not in a first-position
branch; loop-carried state is the register design
(`iteration-with-state-design.md`, which records the rejected
`stateful(...)` / `prev(x)` shapes and why).

## Barriers, not bottlenecks

Combining constructs are **barriers with corresponding inputs and
outputs**. Wires pass through as themselves — nothing is packed into an
intermediate structure just to get across.

- **Product side.** Joining two concurrent flows merges the *flow* wires;
  the value wires pass through separately. No tuple is packed to cross
  the join.
- **Sum side.** Racing two async flows keeps a separate output per
  contender; no tagged union is packed to cross the race
  (`async-flow-design.md`, "Racing is a barrier, not a value").

Tuples and tagged unions remain perfectly good as genuine data. The
anti-pattern is constructing one *merely* to pass a structural point and
tearing it apart immediately after — that severs the visual thread
between each wire and what it carries.

## Commute

Reordering nested flows is an explicit operation, `commute`, defined per
flow-kind pair (`lazy-stream-commute-design.md` maps the taxonomy). In a
chain, `-~> commute` swaps the two innermost layers. Structural flows
never cross implicitly; effect-handle flows commute freely by nature
(`custom-flows.md`). Over a Cross product, commute is transpose and is
always defined (`product-flows-design.md`).

A common use: close the inner loop first and leave an error layer open
for a later collect.

```
xs -> open list -> mayFail -> open option -~> commute -~> collect
=> perElem                    -- loop closed; option (error) layer still open
perElem -> summarize -~> collect => report
```

## Flow kinds

The one open/collect shape is instantiated by kind. Lists and case/option
are implemented; the rest are designed:

| Kind | Opens into | Collect yields | Where |
|---|---|---|---|
| list | each element, in order | a list | implemented; `lazy-compile-design.md` |
| case / option | the matching alt / fires iff Some | exhaustive value / option | implemented |
| stream | each element, on demand (pull) | a stream | `lazy-stream-*.md` |
| async | the value, later | an async value | `async-flow-design.md` |
| incremental (var) | the current value, over time | a var | `incremental-flow-design.md` |

Failability is a uniform dimension across all kinds — a terminator that
can carry a payload — not a per-kind bolt-on (`async-flow-design.md`).

## Where the rest lives

- Validity without types: `types-design.md`,
  `bundle-provenance-design.md`.
- Loop-carried state: `iteration-with-state-design.md` — the biggest open
  area.
- Ports as first-class, and the program as a node set:
  `first-class-ports-design.md`.
- Editing and history as computation: `transformation-levels-design.md`.
- Real-system pressure testing: `tough-use-cases-design.md`.

Rejected and dissolved ideas are recorded in place, in the doc that owns
the topic, each with the reason it must not be pursued again.
