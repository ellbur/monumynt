# Iteration With State

## Design philosophy: the functional bottleneck

Standard imperative loops handle multi-accumulator iteration naturally:
you declare as many variables as you want, update them independently,
and read them independently after the loop. But the code is opaque —
there's no `sum()`, just an accumulator you have to trace.

Functional languages provide named operations like `sum()`, but impose
a bottleneck: multi-output folds have to pack all state into a single
tuple, thread it through the fold, and unpack it at every step. Two
accumulators means a 2-tuple. Three means a 3-tuple. The packing and
unpacking obscures what's actually happening, and the multiple outputs
(sum, max, etc.) lose their identity as separate things — they're just
slots in a tuple.

The goal here is to get the named-operation clarity of the functional
approach without the bottleneck. Each carried variable should be
independently nameable and independently readable, with no tuple packing
at any level. Adding a second accumulator shouldn't require touching the
first.

This is the same goal as the language's multi-output design generally
(several closes on one opener, each independently readable, no tuple),
applied to carried-across-iteration state.

---

## Rejected: `stateful(initial, update)`

The first candidate primitive was a `stateful` call:

    runningSum = stateful(0, prev + x)

### Why it was rejected

**It looks like a function call but isn't.** The two arguments aren't
peers evaluated in the same scope. `initial` (`0`) is evaluated once
before the iteration begins — it's not inside the flow at all. `update`
(`prev + x`) is evaluated once per iteration, in a scope where `prev`
is available. These are different things living at different times and
different scopes. Treating them as sibling arguments in a function call
papers over that distinction.

**`prev` is a scope-contaminating magic name.** Inside `update`, `prev`
is suddenly in scope. No other expression in the language has this
property. This is the "inside out" anti-pattern the language is trying
to avoid: a construct that makes its interior scope different from the
exterior, making the expression's meaning depend on where it appears.

**It's secretly a case split.** The two arguments are really two cases:
the first-iteration case (no previous value exists) and the
subsequent-iteration case (previous value exists). The language already
has case splits for exactly this purpose — `stateful` was smuggling one
in under a function-call surface.

**The initial value is misplaced.** `initial` is written inside the
`stateful(...)` call, but it isn't inside the flow. It can't depend on
per-iteration values — there are none yet. Syntactically positioning it
as an argument alongside the recurrence expression implies they're in
the same scope, which is false.

---

## Considered: `prev(x)` as a primitive

The second candidate was `prev(x)`: a unary operator whose result is
`option<X>` — `None` on the first iteration, `Some(previousValue)`
subsequently.

### What's right about it

It correctly identifies the semantics: the first iteration produces
`None` (no previous value), subsequent iterations produce `Some`. It
makes the first-vs-subsequent split visible to the user. Self-reference
is just a name binding in the host language, no extra mechanism needed.

### Why it's problematic

**It isn't a function — its argument is a label, not a value.** Every
other operator in the language takes values and produces values. `prev(x)`
doesn't read x's value; it uses `x` as an identifier to locate "the
node labeled x from the previous iteration." The argument is node
identity, not a value. No other operator works this way. This is a
fundamental mismatch with how the rest of the value language is designed.

**It's tied to the containing flow but written as a value expression.**
`prev(x)` only means something inside an iteration flow. Outside any
flow, it's meaningless. But it's written as an ordinary value-layer
expression with no syntactic indication that it's a flow-level feature.
The language should make it clear when something is provided by the
surrounding flow structure (like how the element binding of a list
iteration is provided by the flow opener, not conjured by a special
function call inside the flow).

**Multiple `prev` uses are one case split written as many.** If a user
writes `prev(sum)` and `prev(product)` in the same flow, both produce
`None` on iteration 0 and `Some(...)` on subsequent iterations. There's
only one first-iteration / subsequent-iteration distinction — it's a
property of the flow, not of the individual values. Writing two `prev`
calls implies two independent discriminations when there's really one.

**The `None` case belongs outside the flow.** When you case-split on
`prev(sum)`, the `None` branch is the initial case — evaluated before
the flow has produced any iterations. Per-iteration values don't exist
in it; it can only depend on values from outside the flow. But writing
it as an `alt` of a case-split inside the flow positions it as though
it were part of the per-iteration computation. It isn't. The initial
value belongs outside the flow and should be written outside the flow.

---

## Where the critique points

These rejections converge on a clearer shape, though several pieces are
still unresolved.

### The initial value belongs outside the flow opener

The initial value for a carried variable shouldn't be an input to the
flow's uncollect (open) node. If it were, you'd have to enumerate all
carried variables upfront when writing the open node — that's the tuple
bottleneck again, this time at the opener rather than at the step
function. Instead, the initial value is attached independently, one per
iteration construct, wherever that iteration construct appears.

### The first-vs-subsequent split is a flow-level case split, not a value-level one

The first-iteration / subsequent-iteration distinction is a property of
the surrounding flow, not of any particular value within it. It should
be expressed as a case split on the flow — analogous to how CaseSplit
opens a flow, producing alt-scopes that are structurally separate. The
user doesn't write `case(prev(x)) { None => ..., Some(p) => ... }` for
each carried variable; they express one first/subsequent split on the
flow, within which all initial values live in the first-iteration scope
and all carried values live in the subsequent scope.

### The carried value is introduced by a per-flow-iteration construct, not a per-node operator

Rather than a `prev(x)` value-layer operator that magically reaches
back, the carried value should be *provided* by the iteration mechanism
— visible as an output port of some construct, just as the list element
is an output port of the list-open node. The user reads the carried
value because it's been wired in, not because they've invoked a
special-scoped function.

### Closing the initial and step cases doesn't close the outer flow

This is analogous to partial closure in case splits: closing two alts
of a CaseSplit into a combined value ends the distinction between those
alts, but doesn't require closing the containing list or stream flow.
Here, closing the initial case and the step case together produces the
carried value for the current iteration, ending the first/subsequent
distinction for that variable. The outer flow (list, stream, etc.)
remains open; iteration continues. The exact mechanic for this
"sub-close that doesn't close the outer flow" is not yet designed. It
likely needs its own construct or a generalization of close.

---

## The grid structure

Thinking through what the iteration construct must express, it has a
grid shape with two axes:

- **Variable identities** (rows): `sum`, `max`, `count`, etc. —
  independently nameable, no tuple.
- **Roles** (columns): assign-initial, assign-iterated, access-previous,
  access-current.

The grid is not fully combinatorial. Three of the four columns are
coupled: a variable either participates in all three of
{assign-initial, assign-iterated, access-previous}, or in none of them.

- `assign-initial(x)` and `assign-iterated(x)` must coexist: you can't
  carry state without both a starting point and a step.
- `access-previous(x)` requires both: on iteration 0 it reads from
  `assign-initial`; on subsequent iterations it reads from
  `assign-iterated` of the previous step.
- `assign-initial + assign-iterated` without `access-previous` is
  vacuous: you'd be updating a value that nobody ever reads as a
  previous value. It wouldn't be stateful at all.

The fourth column, `access-current`, is independent. A per-iteration
value can be read in the current iteration without participating in the
three-way coupling. Being stateful is exactly being in the three-way
coupling.

### The quotient approach is acceptable here

The constraint that all three columns must match per-variable doesn't
need to be enforced combinatorially (by construction). The language
already uses quotient constraints elsewhere:

- A CaseSplit uncollect and collect must have matching alts.
- A collect must be compatible with the uncollect that opened its flow.
- Types must match (even though type-checking isn't yet implemented).
- The no-crossing rule.

So it's acceptable that a variable's three slots (initial, step,
access-previous) must refer to the same identity, enforced as a
matching constraint rather than being built as a single inseparable
unit.

---

## The stateful-collect is a terminal node

An important distinction from regular collect/close: the operation that
feeds a step value back into a variable has **no output**.

Regular collect produces a value that flows downstream — its result is
its entire point. Stateful-collect consumes the step value and feeds it
into a slot for the next iteration. Nothing comes out. It terminates a
branch of the computation. This is a new kind of node in the language:
previously, every node was a producer. Stateful-collect is a pure
consumer.

This makes the "two stateful-collects for the same variable would
conflict" property structural, not a design rule: there is one write
slot per variable, and two writes conflict because there's no meaningful
way to combine them into one slot.

It also clarifies that stateful-collect and regular close are
independent operations that both happen to consume per-iteration values:

- **Stateful-collect**: carries a value forward to the next iteration.
  Terminal, no output.
- **Regular close**: exposes a value as output outside the flow.
  Produces a value.

To both carry state forward and expose the running sum as an output,
you need both: a stateful-collect to maintain the state, and a regular
close to produce the output. They are separate things.

---

## The "link" as the primitive: concrete-first

The rejected primitives (`stateful(...)` and `prev(x)`) both required
the user to design a general iterative computation from the start.
There's a different approach that matches how programmers naturally
think.

Start with a concrete single-step computation:

- You have `0`.
- You have `element` (the first element of a list).
- You compute `0 + element`.

Then observe: the result of `0 + element` plays the same role that `0`
played. Link the result back to where `0` was. The link says: "this
output and this input are the same thing across iterations."

Before the link there is no iteration — just a concrete one-step
calculation. After the link there is an iteration. The link IS the
primitive.

Adding a second accumulator is adding a second link, independently.
No tuple packing. Nothing else disturbed.

**The link splits the initial value.** Before the link, `0` is just
`0` — one thing. After the link, there are two structurally distinct
things: `0` outside the iteration (the initial value, unchanged), and
a "previous result" inside the iteration body in the same position
where `0` was. They were one thing; the link makes them two.

**The concrete-first philosophy.** Write the special case (one concrete
step), then generalise by identifying the feedback. You don't need to
design a general fold upfront. The generality emerges from the link.
This matches the language's general direction: making programs valid by
starting with a concrete instance and then abstracting.

---

## The link resolves the empty-case partiality

There is a subtle but important consequence of the link: it resolves a
previously unhandled partial case.

Before the link, accessing the first element of a list is a partial
operation. In the language's flow model, either there is a first element
or there isn't. The "list is empty" case is unhandled — the concrete
computation `0 + element` only makes sense if an element exists.

After the link, the empty case is handled: if the list is empty, the
iteration runs zero times and the result is just `0` (the initial value,
never updated). The initial value serves double duty:

- Starting point for non-empty lists (the first "previous" value before
  any step runs).
- Complete answer for empty lists (the result of zero iterations).

The link closes the previously-open empty-list partiality by
designating the initial value as the base case. This is inseparable
from the act of creating the iteration: you cannot link without
providing an initial value (the empty case would be unhandled), and
providing an initial value without linking is just a constant.

In the language's flow terms: the link is simultaneously a close for
the "list is empty" case and an open for the iteration. These are the
same act.

**A consequence: access-previous is never option-typed.** The earlier
`prev(x)` candidate returned `option<X>` to handle "first iteration has
no previous value." Under the link design, that case doesn't arise:
the initial value IS the first previous value. On every iteration,
including the first, there is a well-defined previous value available.
The first/subsequent distinction is handled entirely by the mechanism
and is invisible inside the flow body.

---

## What is still unresolved

This is a work in progress. The following are areas that need further
critique before the primitive can be considered settled:

**The concrete form of the link.** We understand what the link
accomplishes: it identifies an output and an input position as "the same
thing across iterations," splitting the initial value into two roles and
creating the iteration. We don't yet have a concrete syntactic or
structural form for expressing the link in the language. This is the
central open question.

**How the link attaches to the containing flow.** When you link a
computation back to its input, which flow is the iteration happening
inside? If there's already a list flow open, the link presumably lives
within it. But what if there isn't? Does the link itself open an
iteration? If so, what kind — list, stream, infinite? The relationship
between the link and the containing flow is unclear.

**Multiple carried variables.** The design must support two independent
links in one flow without a tuple bottleneck. This should fall out
naturally — each link is independent — but it hasn't been demonstrated
with a concrete worked example. Testing against "running sum and running
max in one loop" is the right critique target.

**Self-reference and cycles.** The link introduces a backward edge in
the expression graph — from the step output back to the initial-value
position. The rest of the language has no cycles. The link introduces
one in a controlled way (bounded by the iteration structure), but what
exactly is allowed, and how it interacts with the compiler's laziness
model, hasn't been thought through.

**Non-homogeneous iteration as a separate problem.** What if different
iterations behave differently — not just first vs. subsequent, but
conditionally different at each step? This is explicitly set aside as a
separate question and isn't part of the stateful iteration primitive.
Worth naming so it doesn't get conflated with what's being designed
here.
