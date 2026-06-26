# Iteration With State

## Guiding language philosophy: example first, then generalise

A central design principle of this language is that programs should be
written starting from a concrete example and then generalised, rather
than starting from a generalisation and instantiating it.

Conventional language design goes in the opposite direction. A function
declaration in most languages says: "here is a general operation
parameterised by these inputs." The user writes the general form
upfront, even if they arrived at it by thinking about a specific
example. The language forces you to declare the generalisation before
you can express the specific case.

This language inverts that. You write the specific case — concrete
values, concrete computation — and then apply transformations that
generalise it. The generalisation is an *after-the-fact* addition, not
an upfront declaration. This shows up repeatedly:

- **Iteration** (this document): you write one concrete step
  (`0 + element`), then apply a "link" transformation to make it
  iterate. The iteration emerges from identifying the feedback; you
  don't declare a fold function first.
- **Sharing**: you write a computation and then wire its output to
  multiple consumers. You don't declare a function with a name and
  call it twice; sharing is structural.
- **Flow structure generally**: you write expressions and then say
  which flow context they live in. The flow is not a pre-declared
  container that expressions are placed into.

This philosophy has consequences for how language primitives are
designed. A primitive that requires declaring the generalisation
upfront (like `stateful(initial, update)`, which forces you to declare
the iteration structure before writing the body) is suspect. A
primitive that starts with something concrete and then identifies a
relationship (like the link) is preferred.

It also explains why the "functional bottleneck" is a problem: packing
state into a tuple to thread through a fold is forcing a generalisation
(the fold's type) upfront, before you know what all the components are.
Multi-output iteration without a tuple is a consequence of the same
principle: add each accumulator when you need it, not when you open the
loop.

---

## Guiding language philosophy: foundations before features

The design prioritises getting the right building blocks over
accumulating features quickly. A wrong foundation compounds: every
feature built on top of it inherits the flaw, and correcting it later
requires dismantling what was built. It is cheaper to spend time
rejecting candidate primitives — even after substantial design work —
than to implement the wrong thing and discover the flaw downstream.

This is why the design conversation spends so much time in critique
rather than implementation. `stateful(initial, update)` and `prev(x)`
were both rejected not because they couldn't be made to work but
because they would have been wrong foundations. The link primitive is
still being critiqued rather than implemented for the same reason.

The corollary: once the foundations are right, building on them should
be fast and unsurprising. The investment is front-loaded.

---

## Guiding language philosophy: building blocks at the programmer's abstraction level

The language does not subscribe to the Lisp philosophy of minimal
primitives. Lisp's bet is that a handful of extremely simple operations
(lambda, cons, car, cdr) can express everything. The bet is technically
correct but creates a practical problem: when building blocks are much
simpler than the programmer's conceptual vocabulary, there is no one
obvious way to write a given program. Any reader encountering a
hand-rolled accumulator loop has to decode which of many possible
implementations the writer chose. The code is not self-documenting;
it requires mental reconstruction of the intent.

Building blocks are a *vocabulary* for expressing programs. Vocabularies
work when they match the user's conceptual level. A `sum()` operation
is a building block at the right level — it says what it means. A fold
with a packed tuple is technically equivalent but communicates nothing
directly. The programmer's intent is visible in the former and hidden
in the latter.

The goal is that given a problem, there is one obvious way to express
it. "One obvious way" is what makes programs readable across authors
and time. This is why the language provides structured flow operations
(list-open, case-split, option-iter) rather than asking the user to
build iteration from recursion and higher-order functions. It is also
why the multi-output design matters: `sum` and `max` as two named
outputs of one loop is the obvious way to write two accumulators; a
2-tuple threaded through a fold is not.

The criterion for a building block is therefore not "is this the
simplest possible primitive?" but "does this meet the programmer at
the level of their own abstractions?" Simpler is not always better;
appropriate is.

---

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

## The link as a graph transformation, not a program element

The earlier concern that "stateful-collect can only be done once per
variable" was a confusion between two levels.

At the *variable* level: one variable has one write slot. Two step
values for the same variable conflict. This is still true.

At the *program* level: the link is a *transformation* applied to an
existing program to produce a new program. You take a program, identify
a position, and get back a new program where that position is now an
iteration variable. This transformation can be applied as many times as
you like — each time to a different position, each time producing a
different new program, each time creating one independent iteration
variable. There is no conflict because each application creates a
*new* variable at a *different* position.

The concrete-first example makes this clear. Starting from:

    e = (1 + 2) + first_element

You could apply the transformation to:
- where `1` was — producing one new iterative program
- where `(1 + 2)` was — producing a different new iterative program
- both positions simultaneously — producing a program with two
  independent iteration variables

These are not competing writes to the same slot. They are independent
cuts in the graph, each creating its own variable.

### What the transformation does at the graph level

The link *cuts* the computation graph at the identified position.
Whatever was computing the value there — a literal, a sub-expression,
anything — is replaced by the iteration variable (initial value on the
first step, fed-back value on subsequent steps). Everything downstream
of the cut just sees a value at that position; it doesn't know a cut
occurred.

### When two cut positions are in a dependency relationship

In the example above, `(1 + 2)` depends on `1`. If you cut at both:

- The cut at `1` makes `1` an iteration variable.
- The cut at `(1 + 2)` makes `(1 + 2)` a *separate* iteration variable,
  initialized to the original value `3`.

The downstream cut severs the dependency on `1` for everything below
that position. The downstream computation no longer sees the updated
`1` propagating through `+ 2` — it sees the independent iteration
variable instead. Each cut is local: it replaces exactly that position
and leaves everything else as it was.

This is a strong argument for the transformation framing over the
declaration framing. A "declare an iteration variable" approach would
have to decide upfront what `(1 + 2)` means when `1` is also an
iteration variable. The transformation approach sidesteps this
entirely: cuts are local, applied one at a time, with no global
coordination required.

---

## Worked example: two independent accumulators

The core claim — "adding a second accumulator is adding a second link,
independently, no tuple bottleneck" — is tested here concretely.

### The starting program (non-iterative)

    sum_init  = 0
    max_init  = -infinity
    element   = list[0]          // partial: list might be empty
    sum_step  = sum_init + element
    max_step  = max(max_init, element)

No iteration yet. Two concrete constants (`0`, `-∞`), one partial
access (`list[0]`), two computations. `sum_step` and `max_step` are
the results we care about.

### Apply two independent links

**Link 1**: feed `sum_step` back to the position of `sum_init`.

- `sum_init` becomes an iteration variable, initialized to `0`.
- On each subsequent iteration, `sum_init` = previous `sum_step`.
- The formula `sum_step = sum_init + element` is unchanged.
- The empty-list case is resolved: the result is `0`.

**Link 2**: feed `max_step` back to the position of `max_init`.

- `max_init` becomes an iteration variable, initialized to `-infinity`.
- On each subsequent iteration, `max_init` = previous `max_step`.
- The formula `max_step = max(max_init, element)` is unchanged.
- The empty-list case is resolved: the result is `-infinity`.

### What the grid looks like after both links

|  | assign-initial | assign-iterated | access-previous | access-current |
|---|---|---|---|---|
| `sum_init` | `0` (outside) | `sum_step` | `sum_init` (per-iter) | — |
| `max_init` | `-∞` (outside) | `max_step` | `max_init` (per-iter) | — |
| `element` | — | — | — | provided by list-open |

`element` is access-current only — provided by the list flow,
not stateful. Neither link touches it or each other.

### No coordination creep

The two links share `element` via the containing list flow. That is the
only interaction. `sum_init` and `max_init` are independent:

- Different initial values.
- Different step computations.
- Neither knows the other exists.
- Adding a third accumulator (`running_count`, with `count_init = 0`
  and `count_step = count_init + 1`) is a third independent link.
  Nothing about sum or max changes.

This validates the no-tuple-bottleneck claim. The functional
bottleneck — `fold(list, (0, -∞), (acc, x) => (acc[0]+x, max(acc[1],x)))` —
has vanished. Each accumulator is its own thing.

### What the example clarifies about containing flows

There are two cases, and they resolve differently.

**Inside an existing flow.** If a list flow is already open, a link
created within it explicitly references that flow. Iteration state is a
feature of a specific flow — not a free-floating thing. The link is
tied to the flow at the point of creation.

**Example-first generalize.** When you start from the concrete program
above, `element = list[0]` is a partial access — no list flow exists
yet. Applying the link to create `sum_init` is simultaneously applying
a generalise step to `list[0]`: "the first element" becomes "each
element," and the list-open comes into existence as part of the same
act. The link and the flow are created together. You don't first open
the flow and then attach the link; the flow is born in the same step
that creates the iteration variable.

In both cases the link is explicitly tied to a specific flow. The
difference is only whether the flow pre-exists or is created by the
generalise step.

**The "no external source" edge case.** A link whose step depends only
on outside-flow values (plus its own accumulator) has no external
iteration source to generalise from. Applying the link creates a flow
that is purely the feedback loop — a self-driven stream. Fibonacci is
this: two links, no external list, just the recurrence. The flow exists;
it just has no inlet from outside. This is not an error; it falls out of
the same generalise step applied to a computation with no partial
accesses in it.

### What the example clarifies about cycles

Within one iteration there is no cycle. `sum_init` on iteration *n* is
`sum_step` from iteration *n-1*, which is already resolved. The
apparent backward edge is sequenced across iterations, not within one.

Expressed as a stream, the recursion is:

    sum_init_stream = cons(0, sum_step_stream)
    sum_step_stream = map2(sum_init_stream, element_stream, (+))

This is productive corecursion: each cell of `sum_init_stream` is
available one step before it's needed by `sum_step_stream`. Under
`Delayed`-cell semantics, this resolves without deadlock. It's the
standard stream recursion pattern, not something requiring new
machinery.

---

## A candidate for the concrete form: Delay

The central open question is what the link looks like as a concrete
construct in the language. One candidate is a `Delay` node.

### What Delay is

`Delay(init, prev => step)` — a single node with:

- `init`: the initial value, an expression evaluated *outside* the
  iteration. On the first step, this is what the node outputs.
- `prev => step`: a lambda where `prev` is a fresh node representing
  this Delay's own previous output. On each subsequent step, the node
  outputs whatever `step` evaluated to last step.
- **Output**: the previous step's result (or `init` on the first step).

The three-way coupling from the grid falls into place naturally:

- `assign-initial` → `init` argument
- `access-previous` → the Delay's output (= `prev` inside the lambda)
- `assign-iterated` → the lambda body (`step`)

All three are in one construct. No matched open/close pair; no terminal
node with no output. Delay has a normal output, usable anywhere.

### Applied to the worked example

Starting from the concrete program:

    sum_init  = 0
    sum_step  = sum_init + element

Applying the link transformation produces:

    runningSum = Delay(0, prev => prev + element)

The `0` moves to the `init` argument. The `sum_init` position becomes
`prev` (the lambda parameter). The step formula becomes the lambda
body. The substitution is direct and mechanical.

Two independent accumulators remain independent:

    runningSum = Delay(0,       prev => prev + element)
    runningMax = Delay(-∞,     prev => max(prev, element))

No tuple. Neither references the other.

### Cross-delay references: Fibonacci

When one Delay's step depends on another Delay's previous value,
the other Delay's output is just referenced directly:

    fib_a = Delay(1, _    => fib_b)
    fib_b = Delay(1, prev => fib_a + prev)

`fib_a`'s step is just `fib_b` (the previous output of `fib_b`).
`fib_b`'s step is `fib_a + prev` (previous fib_a plus previous fib_b).
The lambda ignores its `prev` parameter when the self-reference isn't
needed. The host language's `let rec` handles the mutual reference.

### Applying the design principles

**Foundations before features.** Delay is one node with one clear
semantics. It doesn't require designing a new open/close pair,
a new terminal-node concept, or a new matching constraint. That's
fewer moving parts to get wrong.

**Example first, then generalise.** The transformation from concrete
to iterative is a direct substitution: initial value → `init`
argument, loop-variable position → `prev` parameter, step formula →
lambda body. The transformation is identifiable and mechanical.

**Building blocks at the programmer's abstraction level.** "Delay
this value by one step, starting from X" is a meaningful abstraction
that meets the programmer's vocabulary. It's not too low (raw
read/write ports) and not too high (hiding the recurrence structure).

**Inside-out / cases as values.** This is the most important
critique of Delay. The lambda `prev => step` introduces `prev` into
the body's scope. Inside the lambda, `prev` is available; outside
it isn't. This is a scope difference — the interior is not the
same as the exterior.

The lambda is better than `stateful(init, update)`: the binding
is visible and explicit (it's a lambda parameter, a standard
mechanism), and `prev` is a normal name rather than a magic keyword
that appears in scope without a visible binding. But the inside-out
concern applies in a weaker form. Whether a lambda boundary is
acceptable under the philosophy is worth critiquing.

### What Delay leaves open

**The lambda for cross-delay non-self-references is awkward.** In
Fibonacci, `fib_a = Delay(1, _ => fib_b)` writes a lambda that
ignores its parameter. The lambda is only needed when the step
references the Delay's *own* previous value; cross-references don't
need it. But the form requires a lambda regardless. This suggests
the lambda might not be the right mechanism — or that self-reference
and cross-reference should be handled differently.

**`let rec` for mutual reference.** The Fibonacci example requires
the host language's `let rec` to express mutual reference between
two Delays. In strict ReScript, `let rec x = f(x)` at the value
level (not function level) only works if the evaluation is deferred.
The lambda in `Delay(1, _ => fib_b)` is a function, so `let rec`
can capture it — but this depends on implementation details that
haven't been verified.

**Does the lambda form pass the inside-out test?** Left as an open
critique. One way to surface the question concretely: is there a
formulation of Delay that *doesn't* require a lambda (and therefore
doesn't introduce an interior scope), but still handles self-reference
without a circular construction-time dependency?

---

## Resolving the lambda: Delay as ports, not a function

The open critique of `Delay(init, prev => step)` is the lambda. It
introduces `prev` into an interior scope — the one place the body
differs from its surroundings — which is the inside-out anti-pattern
the language is built to avoid. The question left open above was
whether there is a formulation that drops the lambda but still handles
self-reference without a construction-time cycle.

There is, and the language already contains it. The lambda is not
essential to Delay; it is an artifact of writing the step *as a
function of* `prev`. But `prev` does not have to be a bound parameter.
It can be an **output port** of the Delay node — read by wiring a
value off it, exactly the way the current element is read off a
list-open node.

### The shape

A Delay node has three connections, none of them a lambda:

- **`init`** — an input from outside the flow. The initial value. On
  the first step, this is what the node outputs.
- **a `prev` output port** — the node's previous-step result (or
  `init` on the first step). Downstream computation reads it by wiring
  to it, like any other value.
- **a `step` input port** — the value to carry into the next step.
  Whatever computes the new value wires *into* this port.

The three-way coupling from the grid maps onto the three connections
directly, with no scope difference anywhere:

- `assign-initial` → the `init` input
- `access-previous` → the `prev` output port
- `assign-iterated` → the `step` input port

### Why this passes the inside-out test

In the lambda form, `prev` exists only inside `prev => step`. The
interior of the lambda is a different scope from the exterior, and the
expression's meaning depends on whether it sits inside that lambda.
That is the violation.

In the port form, there is no interior. Every expression in the flow
body lives in one scope. `prev` is not a name that comes into being
inside a body; it is a wire coming off the Delay node, available
wherever any wire is available. This is *exactly* how the list element
is provided: the list-open node has an output port for "the current
element," and the body reads it by wiring, not by a magic-scoped name.
Delay's `prev` port is the same mechanism applied to "the previous
step's value." The port form is therefore no more inside-out than list
iteration is — which is to say, not at all.

This also fulfils the earlier critique's own prescription (see "The
carried value is introduced by a per-flow-iteration construct, not a
per-node operator"): the carried value should be *provided* as an
output port and read because it has been wired in, not conjured by a
specially-scoped function. The port form is that prescription made
concrete.

### It is the iteration rail

The visual design notes (`iteration-rails-design-notes.md`) arrived at
this same node from the other direction. The rail is a horizontal line
crossing the iteration column with a **tap-down read** on the left and
a **writeback-up** on the right, and an **initial value** attached by a
dotted line. Those are precisely Delay's three connections:

- tap-down read  = the `prev` output port
- writeback-up   = the `step` input port
- dotted initial = the `init` input

The non-visual reasoning in this document worked toward a lambda; the
visual reasoning worked toward read/write ports. They are the same
primitive. The port form is the reconciliation, and the fact that two
independent lines of argument converge on it is evidence it is the
right shape.

### Self-reference and cross-reference become the same thing

The lambda form had an awkwardness: Fibonacci's
`fib_a = Delay(1, _ => fib_b)` writes a lambda whose parameter is
ignored, because that step references another Delay's previous value,
not its own. The lambda is mandatory even when nothing reads `prev`.

In the port form this disappears. There is no parameter to leave
unused. A Delay's `step` input is wired to whatever computes the next
value; a Delay's `prev` output is read by whoever needs the previous
value. Self-reference (`runningSum`'s step reads `runningSum`'s own
`prev`) and cross-reference (`fib_a`'s step reads `fib_b`'s `prev`)
are both just wires. The distinction the lambda forced into the surface
syntax was never real, and the port form does not encode it:

    runningSum:  init 0   step = (prev of runningSum) + element
    fib_a:       init 1   step = (prev of fib_b)
    fib_b:       init 1   step = (prev of fib_a) + (prev of fib_b)

Each line is a node with an `init` and a `step` wired from some
combination of `prev` ports. No lambdas, no unused parameters, no
self-vs-cross special case.

### No construction-time cycle

The lambda form needed the host language's `let rec` because `step`
referred to `prev`, which referred to the node being constructed — a
value-level recursive definition that only works if evaluation is
deferred. The port form needs no value-level recursion at all. It uses
the same node-identity-plus-wiring pattern the codebase already relies
on for Open/Close: a node is minted with an id and its output ports
exist immediately; its input ports are wired as a separate step.

So construction is two-phase, not circular:

1. Mint the Delay node. Its `prev` output port exists now and can be
   referenced downstream immediately.
2. Wire its `step` input (and `init`) — a later, separate act, exactly
   like wiring a Close back to the Open it consumes.

No `let rec`, no deferred evaluation, no circular value dependency at
construction time. The back-edge lives in the wiring, where the rest
of the flow structure already lives.

### What it costs: the graph is no longer a DAG

The price of the port form is honest and small. The `step` input is a
back-edge: it wires a downstream value back up into the Delay node, so
the computation graph contains a cycle. The current compiler assumes a
DAG (it places each binding at `deeper(args)` and relies on laziness
for ordering), so a back-edge is the one thing it cannot yet handle.

But the back-edge is not an accident to be tolerated — it *is* the
link. The "link as a graph transformation" framing said the link cuts
the graph at a position and feeds the downstream value back to it. The
`step → prev` back-edge is that cut made concrete. The cycle is the
primitive, not a side effect of it.

And the compile target is already known: a single mutable `let`
register inside the loop, per the iteration-rails design. `init` sets
the register before the loop; `prev` reads it at the top of the
iteration; `step` assigns it at the bottom. The back-edge in the graph
becomes a write-after-read on one register in the emitted JS — no
laziness, no cycle in the generated code, because the cycle was only
ever across iterations, never within one.

---

## What is still unresolved

This is a work in progress. The following are areas that need further
critique before the primitive can be considered settled:

**The concrete form of the link.** Substantially resolved. The
concrete form is the Delay node expressed *as ports* — an `init`
input, a `prev` output port, and a `step` input port — rather than as
the lambda `Delay(init, prev => step)`. The port form drops the
lambda, so it passes the inside-out test cleanly (`prev` is a wired
output port like the list element, not a name bound in an interior
scope); it removes the unused-parameter awkwardness (self-reference
and cross-reference are both just wires); and it needs no
construction-time cycle (the `step` input is wired as a separate act,
the way Close is wired to Open). It is the same node the visual
iteration-rail design arrived at independently. What this leaves for
later is implementation, not design: the `step` back-edge makes the
computation graph non-acyclic, which the current DAG-assuming compiler
cannot yet handle, and the eventual compile target is a single mutable
`let` register inside the loop (per the iteration-rails notes).

**How the link relates to its flow.** Resolved: the link is always
explicitly tied to a specific flow — either one that pre-exists (inside
an existing flow, the link names it) or one created simultaneously by
the generalise step (example-first, the flow comes into existence as
part of creating the link). A link with no external iteration source
creates a self-driven stream (purely the feedback loop); this is not an
error. What remains open is the concrete syntactic or structural form
for expressing either case — the mechanics of "naming a flow" when
attaching to an existing one, and the mechanics of "the generalise step
creates both."

**Self-reference and cycles.** The worked example shows that within one
iteration there is no cycle — the accumulator value is resolved from the
previous iteration before the current step runs. Expressed as streams,
the recursion is productive corecursion (`cons(initial, step_stream)`)
which Delayed-cell semantics handles without deadlock. What still needs
thought: are there link configurations that produce *non-productive*
recursion (a cycle with no base case), and can the language rule them
out structurally or does it rely on the user not creating them?

**Non-homogeneous iteration as a separate problem.** What if different
iterations behave differently — not just first vs. subsequent, but
conditionally different at each step? This is explicitly set aside as a
separate question and isn't part of the stateful iteration primitive.
Worth naming so it doesn't get conflated with what's being designed
here.
