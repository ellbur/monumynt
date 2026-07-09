# Iteration With State

> **Reader's guide (2026-07-09).** This is the record of the biggest
> design area still to get right. The current state, for a reader who
> doesn't need the whole conversation:
>
> - **Two live candidates, deliberately side by side** (§"Two live
>   candidates, kept side-by-side"): the **Delay node in port form**
>   (§"Resolving the lambda") and the **latent-flow augmented
>   uncollect** (§"The latent-flow representation of generalize").
>   Neither is chosen. The adopt-one/adopt-both question and the
>   conjectured **visible state thread** (§"A fourth option") are open
>   (§"What is still unresolved").
> - **The bar for a decision** (design review, 2026-07-09): designs
>   that technically work are easy to produce; what is needed is a
>   design both *easy for beginners to understand* and *flexible
>   enough for complex code*. More work is required before choosing.
> - The Delay back-edge construction both candidates lean on is worked
>   out in `first-class-ports-design.md` (the write half is its own
>   node; the pair supplies the `final` readout).
> - What died on the way is recorded in this document —
>   `stateful(...)` (§"Rejected"), `prev(x)` (§"Considered"), the
>   Delay lambda form (§"A candidate for the concrete form"), the
>   terminal stateful-collect (§"The stateful-collect is a terminal
>   node", whose rejection stands per the recorded position there) —
>   with the old rail machinery's short record under Delay in
>   `visual-language-spec.md` and the rail ideas worth keeping in
>   `iteration-rails-design-notes.md`.
>
> Terminology predates the uncollect/collect correction; "open"
> and "opener" mean uncollect, "close" means collect,
> "reduce-close" the reduce collect.

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

> **Superseded.** This section records an earlier framing in which the
> feedback operation produces nothing. That "produces nothing, hangs in
> the air" quality was a source of discomfort in a language otherwise
> modelled on functional behaviour. Both of the live candidates later in
> this document dissolve it, each in its own way. Under the latent-flow
> representation ("The latent-flow representation of generalize"), the
> feedback operation *does* produce something — the flow as modified by
> the inclusion of the iteration variable — and the final collect
> consumes that modified flow rather than the original. Under the port
> form ("Resolving the lambda: Delay as ports"), there is no separate
> feedback node at all — the step is an *input port* of the Delay node,
> so nothing output-less exists. The "terminal, no output" reading below
> is retained because the conflict it names is what both reframings
> answer.
>
> **Recorded position (design review, 2026-07-09).** The rejection of
> an output-less feedback node stands, full stop: a feedback node must
> have an output. Passages elsewhere in the record that appear to
> soften this are mistaken readings — what the write-half design
> (`first-class-ports-design.md`) recovers is a distinct writing
> *node*, and that node is not terminal precisely because it outputs
> the final value.

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

> **Superseded — twice, independently.** This section describes the
> *lambda form* of Delay, which is dead: its critique — the lambda
> introduces an interior scope, and the lambda parameter goes unused for
> cross-references (`_ => fib_b`) — pointed past it. Two parallel design
> threads then resolved that critique in different directions, without
> seeing each other's arguments, and both resolutions are kept
> side-by-side as live candidates (see "Two live candidates, kept
> side-by-side"):
>
> - **The port form** ("Resolving the lambda: Delay as ports") keeps
>   Delay as one node and turns `prev` into an output port and `step`
>   into an input port — no lambda, wiring only.
> - **The latent-flow representation** ("The latent-flow representation
>   of generalize") reads the unused-parameter awkwardness as a signal
>   that previous-value access was put in the wrong place (private to
>   each node, via a lambda) when it should be a feature of the shared
>   flow — and dissolves the node into an augmented uncollect on the
>   flow itself.
>
> The lambda form is retained here because its critique is what
> motivates both replacements.

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

> **One of two live candidates.** This section and "The latent-flow
> representation of generalize" (below) are independent resolutions of
> the same lambda critique, developed on parallel threads that did not
> see each other. Both are deliberately kept side-by-side; see "Two
> live candidates, kept side-by-side" for the comparison.

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

*(2026-07-07: the Expr-level mechanism for this two-phase wiring is
now worked out in `first-class-ports-design.md`, "The Delay
back-edge: the write half is a node." The analogy to Close-wiring is
made literal rather than approximate: the later act mints its own
node — a write half holding the read reference and the step — so
nothing mutates the Delay after construction and the object graph
stays a DAG unconditionally, with the `step → prev` crossing
recovered from the pairing. The write half's output is the final
value: the thread's exit anchor, which the one-node contraction had
no port for.)*

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

## Ruling out non-productive cycles structurally

The open question on cycles was: are there link configurations that
produce *non-productive* recursion — a cycle with no base case — and
can the language rule them out structurally, or must it rely on the
user not creating them? With the port form settled, the question has a
precise formulation and a precise answer: yes, structurally, with one
decidable graph check.

### The two kinds of edges

In the port form, the computation graph has exactly two kinds of edges:

- **Ordinary value edges** — a node's input wired from another node's
  output. These are all *within one iteration*: both endpoints refer to
  values of the same step.
- **The Delay crossing** — the internal edge from a Delay's `step`
  input to its `prev` output. This is the only edge in the language
  that crosses an iteration boundary: the value wired into `step` at
  step *n* emerges from `prev` at step *n+1*.

Every back-edge is a Delay crossing, because the Delay is the only
construct that creates one. That gives the productivity condition a
purely structural statement:

> **A cycle is productive iff it passes through at least one Delay
> crossing.** Equivalently: delete every Delay's internal `step → prev`
> edge; the remaining graph must be acyclic.

### Why this is exactly right

*Sufficiency.* If every cycle crosses a Delay, then treating each
`prev` port as a source and each `step` port as a sink makes the
per-iteration graph a DAG. Iteration *n* then resolves in topological
order: its inputs are either within-iteration values (DAG, no cycle) or
`prev` ports, which hold iteration *n−1*'s `step` values — already
fully resolved — or `init` on iteration 0. The base case is grounded by
`init`, which the Delay cannot be constructed without (the link
requires an initial value precisely because it closes the empty case).
Induction does the rest.

*Necessity.* A cycle with no Delay crossing lies entirely within one
iteration: it asserts `x = f(x)` *at the same step*, with no earlier
value to seed it. That is the definition of non-productive. So the
check rejects exactly the ill-formed programs and nothing else.

Worked instances:

- `x = x + 1` with no Delay — a cycle with zero crossings. Rejected.
- Fibonacci — `fib_a`'s step reads `fib_b`'s prev and `fib_b`'s step
  reads both prevs. Every cycle crosses a Delay; deleting the crossings
  leaves the prev ports as sources and the graph acyclic. Accepted.
- A Delay whose `step` is wired straight from its own `prev` — one
  cycle, one crossing. Accepted; vacuous but well-defined (a constant
  stream). Being useless is not being ill-formed.

`init` needs no separate productivity treatment. `init` is evaluated
outside the flow, so wiring it from a per-iteration value is already
ill-formed under the existing scoping rules (the same family as "no
time travel"). A cycle through `init` cannot arise in a program that
passes that check.

### It is a quotient constraint, and that is fine

The check is global: productivity is a property of the assembled graph,
not of any single link. It cannot be made by-construction without
reintroducing the declare-the-iteration-upfront framing the link was
designed to avoid — the transformation view applies cuts one at a time,
each locally sensible, and only the whole graph determines whether the
result is productive. So this joins the language's existing quotient
constraints (matching alts on a CaseSplit, close compatible with its
open, no-crossing): enforced as a check, not by construction. The check
itself is trivial — delete the crossings, run a cycle detection — and
needs no type-system machinery.

### Precedent: the synchronous-dataflow causality check

This is not a novel rule; it is the standard causality condition of
synchronous dataflow languages, and the correspondence is exact.
Lustre's `pre e` (unit delay, undefined at the first instant) combined
with `init -> pre step` (initialization) is precisely the Delay node —
`init` input, `prev` output, `step` input — and Lustre accepts a
program iff every dependency cycle crosses a `pre`, checked
structurally at compile time. Hardware description languages enforce
the same rule in the same shape: every combinational loop must pass
through a register, and the Delay's compile target *is* a register.

This makes a third independent line of argument converging on the same
primitive: the non-visual critique (this document) arrived at ports,
the visual rail design arrived at tap-down/writeback-up, and the
synchronous-language tradition arrived at unit-delay-with-init as the
one legitimate way to close a feedback loop — with fifty years of
hardware practice confirming that the "every cycle crosses a delay"
check is sufficient in the field, not just in theory.

---

## The latent-flow representation of generalize

> **The other live candidate.** This section resolves the same lambda
> critique as the port form above, from a different direction and
> without knowledge of it. Both are deliberately kept side-by-side; see
> "Two live candidates, kept side-by-side" for the comparison.

The link is a *transformation* (see `transformation-levels-design.md`
for the two-level transformation/result framing this rests on). The
question here is its **result-level** form: what wires and nodes does
generalizing actually lay down? The answer needs no lambda, no `prev`
parameter, and no new value-producing node.

### Generalize is a cut on a wire

Every value wire has an implicit place to cut it. To generalize, you cut
a wire and interpose a new flow-uncollect `U`:

- The **pre-cut producer** becomes an **input** to `U` — the *seed* (the
  initial value, evaluated once outside the iteration).
- The **post-cut consumer** reads an **output** of `U` — the
  per-iteration *state* (the seed on iteration 0, the fed-back step
  after).

The previous-value is therefore not a new node and not a lambda
parameter; it is `U`'s state output, read by whatever used to consume the
cut wire. This is "the link splits the initial value" (above) made
concrete: one wire, cut, becomes a seed-in and a state-out.

> **Aside, to avoid a wrong connection.** The latent place-to-cut on
> every wire is *not* related to `flowRef`'s `NodeFlow` being a partial
> operation. That partiality is just the ordinary fact that you can name
> an output port a node does not have (like asking a multiplication node
> for a "remainder" port); it is unremarkable. The latent flow here is a
> separate idea about generalization, not a totalisation of `NodeFlow`.

### The source flow is a *separate* input to the uncollect

The flow being iterated over (e.g. a list) is **not identified with** the
generalize flow. It is *another input* to the same uncollect. `U` is a
flow-combiner that zips an external iteration source with the internal
feedback variable:

```
U  : uncollect
      inputs : seed = 0         (value, from the cut wire's producer)
               src  = listFlow  (flow)
      outputs: state            (per-iter: the accumulator so far)
               element          (per-iter: from src)
```

The body reads both ports from `U`:

```
element := U.element
sum     := U.state + U.element
```

This is recognizably `Open ListIter` with one extra (seed-in, state-out)
pair bolted on — a generalization of an existing node, not a new species.
Its output is a single **"list-with-state" flow** carrying two
per-iteration ports.

### The feedback the cut does not pin down

The cut supplies seed-in and state-out. It does **not** by itself say
what advances the state — that next iteration's `U.state` is *this*
iteration's `sum`. That is the link's other end ("the result plays the
role of `0`"). Two readings:

- **Cursor-as-feedback.** Generalize uses the current output point
  (`sum`) as the step. This works *because of when you generalize*: you
  build one concrete step, then generalize while its result is the
  cursor. It keeps generalize a single-wire tap and fits example-first
  exactly (build step → generalize → build next step → generalize). This
  is the leaning.
- **Explicit feedback wire.** Generalize names both the cut wire and the
  step wire. Needed only to generalize out of order or much later.

### What this produces

Putting the halves together, generalize produces the **modified flow**
(this is the resolution of the "terminal node with no output"
discomfort, above): the uncollect plus the feedback collect yield a flow
with the iteration variable woven in. Exposing the accumulator as a
downstream value is then a *separate*, ordinary collect on that modified
flow.

### Worked example: two independent accumulators, concretely

Starting program (cursor at `sum`):

```
n0:   0
nLst: list
nEl:  first(nLst)        -- partial access
nSum: n0 + nEl           -- cursor
```

**Generalize 1 (sum).** Cut `w0 : n0 → nSum.left`. Interpose `U`:

```
U : inputs  seed = 0, src = listFlow
    outputs state, element
nEl  := U.element
nSum := U.state + U.element     -- feedback: cursor nSum advances U.state
```

`first(nLst)` generalizes in the same act: "the first element" becomes
"each element," and `listFlow` comes into existence as the `src` input.
(This is the example-first case from "containing flows", above: the flow
is born with the link.)

**Generalize 2 (max).** Cut `w(-∞)`. Interpose `U2` — whose `src` is
**not** the raw list but `U`'s already-combined flow, so the two stay in
lockstep:

```
U2 : inputs  seed = -inf, src = U.flow
     outputs state2, (passes through element, state)
nMax := max(U2.state2, U2.element)
```

So generalizes **stack**: each consumes the current combined flow and
adds one more (seed-in, state-out) pair. Independent seeds, independent
steps, no tuple. "The source flow is another input to the uncollect"
generalizes to "the *current* flow is another input to the next
uncollect" — and the no-bottleneck claim falls out structurally.

**Expose.** A regular collect on the final combined flow reads each
accumulator's carried value out as a downstream value.

### Fibonacci falls out by dropping `src`

A generalize with no external iteration source is the same uncollect with
no `src` flow input — just seed + feedback, self-driven. Two such links,
cross-referencing each other's state outputs, give Fibonacci. Because
state outputs are read by node reference like any wire, self-reference
and cross-reference are uniform — there is no privileged "own previous"
slot and so no unused-parameter awkwardness (the defect that sank Delay's
lambda form; the port form dissolves it the same way, by making both
kinds of reference plain wires).

### Where the design principles land

- **Inside-out.** No lambda, so no binding form introduces an interior
  scope. The interior/exterior value difference for the cut node (it is
  the seed outside, the carried value inside) still exists — that *is*
  iteration state — but it is created by an explicit, on-screen cut, not
  a magic name. The principle is best read as forbidding *invisible*
  interior/exterior differences, not all of them.
- **Example-first.** The cut is a direct, mechanical transformation of a
  concrete program, applied after the fact.
- **Right abstraction level.** Generalize is one operation; its result
  is a recognizable extension of `Open ListIter`.
- **Foundations before features.** Reuses the existing flow/uncollect
  vocabulary rather than introducing a new node species with a lambda.

## Two operations for accumulation: reduce-close vs augment

Summing a list can be approached from more than one direction, and the
directions are not the same construct. Trying to force them into one
construct is exactly the intent-decoding the "abstraction level"
principle warns against. There are **two operations**, one of which has
two authoring directions.

### The three authoring approaches

1. **Running sum, built loop-first.** You already have a list uncollect.
   You add an iteration uncollect over the list flow with a `0` seed, add
   it to the element, and collect it back to the now-augmented flow. You
   consciously construct the state variable; the running value is
   available in-loop.
2. **Just summing the list.** You do not think about a running sum. You
   think about *putting `+` between the elements*: open a flow whose value
   wires are, abstractly, any two components to be accumulated; add them;
   close the flow with that value. The starting value for the empty list
   is the operator's **implied identity** (`0` for `+`). This only works
   for operators with an identity; for custom calculations you gravitate
   to approach 1 or 3 anyway.
3. **Running sum, built value-first.** Start with `0`, open a list flow,
   add `0` to the element, then use the latent feed-back flow to feed the
   sum back into the wire where `0` fed in.

### Two operations, not three

Approaches **1 and 3 are the same construct** — the latent-flow
augment-loop above (a list-with-state flow) — built from two authoring
directions (explicit uncollect vs latent-flow tap). They converge to one
result-level structure. The running value is exposed; the step is
arbitrary.

Approach **2 is a genuinely different operation: a reduce-close.** It is a
*close-variant*, a sibling of the ordinary collect-close (which gathers a
flow into a list). Reduce-close collapses a flow with an associative
operator, identity implied. It builds **no** state variable in the
authoring surface — "I don't think about a running sum" is literally true
at the construct level. It carries information augment does not:

- **The identity comes from the operator, not the user** (`+`→0, `*`→1,
  `max`→−∞). This is what makes empty→identity and `[a]`→`a` fall out
  (`identity ⊕ a = a` needs a *genuine* identity — an arbitrary seed will
  not do).
- **The two operands are symmetric** — the associativity assertion.
  Augment's step is an asymmetric `state ⊕ element` and carries no such
  claim.
- **Its type shape is a monoid** (`op : T×T→T`, value and result the same
  `T`), where augment's step is an arbitrary `S×E→S` (accumulator type may
  differ from element type — count, list-building, …).

So the reader can always tell total-sum from running-sum: they are
different constructs. The only new machinery reduce-close needs is
**operator identities**.

### Reduce-close is its own result node, lowered in compile

The decision (result-level representation): reduce-close is **its own
node carrying the operator's monoid**, and `Compile` *lowers* it to
`acc = identity; for (el of list) acc = op(acc, value)`. It is **not**
elaborated into the augment loop on construction.

The decisive reason: elaborating on construction would make reduce-close
and "augment + expose final" persist as the *same* result structure —
collapsing the total-vs-running distinction, and making a plain `sum`
read as a running-sum machine whose intermediate values nobody uses. The
program of record is the Expr, not the JS; keeping intent in the Expr is
the point. Lowering in compile costs nothing (same `for-of` JS, no
backend duplication) and preserves the monoid for possible future
reassociation or parallel reduction. It also fits the existing close
family (list / case / filter / option), which is already discriminated by
shape.

Boundary: reduce-close is available exactly when the operator is a known
associative monoid. No identity / non-associative → no reduce-close, fall
back to augment (explicit seed). The degradation is structural: no
monoid, no node.

### A second accumulator on a sum, via derived-port reference

Adding a second accumulator to a `sum` (e.g. also tracking `max`, in
lockstep) does **not** require lowering the `sum` or editing anything.
`sum` (reduce-close) has an always-available derived level-0 form — the
augment iteration — and that derived form exposes a combined
list-with-state flow as an output port. You build a *new* augment whose
`src` **references that derived port** and adds the `max` state. `sum`
stays a pristine reduce-close; nothing about it is touched.

This is the stacking rule ("each generalize takes the current combined
flow as `src`") reaching *across the derivation boundary*: the current
combined flow may itself be derived. The general mechanism — a wire may
reference the output port of a derived result — is developed in
`transformation-levels-design.md`. The only open detail here is which
derived ports are exposed for reference (the principal output ports, such
as the combined flow — not arbitrary derivation internals).

This covers *adding alongside* a `sum`. The other case — *changing the
interior* (e.g. making the step decay, which is no monoid) — cannot be a
reduce-close, and is handled without editing anything: a built-in
level-1 `expand` invoked in **materialize mode** records a construction
step whose result version contains the augment loop's nodes as ordinary
parts (consumers rebuilt to arrive at the corresponding ports), and the
decaying version is then *built* from those parts — a new step and a new
uncollect sharing the seed and `src` wires — while the sum version
persists in the history. Rule of thumb: reference the lens to add; take
the parts to change. See `transformation-levels-design.md`, "Two
invocation modes: lens and materialize."

---

## Two live candidates, kept side-by-side

The lambda critique of `Delay(init, prev => step)` was resolved twice,
independently, on parallel design threads that did not see each other's
arguments: the **port form** ("Resolving the lambda: Delay as ports")
and the **latent-flow representation** ("The latent-flow representation
of generalize"). Rather than force a premature choice, both are kept
side-by-side as live candidates (decision 2026-07-05). This section
records where they agree, where they genuinely differ, and what would
decide between them.

### Where they agree

- **No lambda, no interior scope introduced by a binding form.** Both
  read the previous value by wiring, not by a specially-scoped name.
- **Self-reference and cross-reference are uniform.** Both make
  Fibonacci two links reading each other's state through ordinary
  wires; neither has a privileged "own previous" slot.
- **The initial value lives outside the flow**, one initial value per
  link, and the link cannot exist without one (the empty case is
  closed by the same act that creates the iteration).
- **One variable per link, no tuple bottleneck.** A second accumulator
  is a second independent link.
- **Both are result-level forms of the same link transformation** — the
  transformation-level story ("generalize is a verb applied to a
  concrete program") is shared; the disagreement is only about what
  structure the verb lays down.
- **Both realize the visual rail.** Tap-down read / writeback-up /
  dotted initial map onto the port form's `prev`/`step`/`init` and
  equally onto the latent form's state-out / feedback / seed-in.

### Where they differ

- **Node species vs. generalized opener.** The port form keeps the
  iteration variable in a *new node* (Delay) standing beside the flow it
  names. The latent form weaves it *into the flow*: the generalize cut
  interposes an uncollect that is "Open ListIter with one extra
  (seed-in, state-out) pair," yielding a combined list-with-state flow
  whose `state` port sits beside `element`.
- **How the source flow relates.** A Delay *references* its flow. The
  latent form's uncollect takes the flow as an *input* (`src`) and
  outputs the combined flow — which gives it a structural stacking rule
  (each new accumulator's uncollect takes the current combined flow as
  its `src`, so accumulators stay in lockstep by construction) that the
  port form expresses only as many Delays referencing one flow.
- **The feedback and the cycle story.** The port form's `step` is an
  honest back-edge: the graph stops being a DAG, and well-formedness is
  the productivity check ("every cycle passes through a Delay"), with
  the synchronous-dataflow precedent behind it. The latent form packages
  feedback as an uncollect/collect pairing — under its preferred
  cursor-as-feedback reading the result graph may stay acyclic by
  construction — but its feedback-collect mechanic is not yet pinned
  down, and it has no worked answer to non-productive configurations.
- **Reading of the inside-out principle.** The port form claims a full
  pass: `prev` is a port like the list element, no interior/exterior
  difference at all. The latent form concedes that the cut node *is*
  different inside vs. outside (seed vs. carried value) — that is what
  iteration state means — and reads the principle as forbidding
  *invisible* interior/exterior differences, not all of them.
- **Companion machinery.** The latent-flow thread additionally brings
  the transformation-levels framing (`transformation-levels-design.md`),
  reduce-close, and derived-port references. These are largely
  independent of the choice — reduce-close's lowering could target
  either form — but they were developed against the latent form and are
  stated in its vocabulary.

### The three options and their tradeoffs

Keeping both candidates side-by-side opens a question that is itself a
design decision: does the language eventually adopt *one* of them, or
*both*? That gives three options, each with a real case for and against.

**Option 1: Delay nodes only.**

For:

- **Smallest, most precisely specified construct.** One node species
  with three connections; the schema is already pinned
  (`visual-language-spec.md`). Nothing about the flow vocabulary
  changes.
- **A settled well-formedness story.** The productivity check ("every
  cycle passes through a Delay") is decidable, simple, and carries the
  synchronous-dataflow and hardware precedent — decades of field
  validation, not just theory.
- **Full inside-out pass.** `prev` is read like any port; there is no
  interior/exterior difference anywhere, not even an explicit one.
- **Crisp compile target** (one mutable register), and the node is
  exactly what the visual rail depicts.

Against:

- **The graph stops being a DAG.** The compiler, ExprPrint, every
  traversal, and any future tooling must drop the acyclicity
  assumption, and a whole-graph check enters the language for the sake
  of one node.
- **The tie to the flow is by reference, not by structure.** A Delay
  stands *beside* the flow it names. Multiple accumulators stay in
  lockstep only because they happen to reference the same opener;
  nothing structural enforces it.
- **State is invisible from the flow.** A reader inspecting the opener
  sees no state ports; discovering that a flow carries state means
  finding the Delays that point at it.
- **It is the result, not the verb.** Delay says nothing about the
  example-first authoring story; the generalize transformation needs a
  separate account of what the cut lays down, which the latent-flow
  thread supplies and this one does not.

**Option 2: Augmented flows only.**

For:

- **State is woven into the flow.** The opener carries the (seed-in,
  state-out) pair; a reader of the flow sees its state directly, and
  the combined list-with-state flow is a single referenceable thing.
- **Lockstep by construction.** The stacking rule — each generalize
  takes the current combined flow as its `src` — makes multi-accumulator
  coordination structural rather than incidental, and the
  no-tuple-bottleneck claim falls out of the shape itself.
- **The graph can stay acyclic.** Under cursor-as-feedback the result
  graph needs no back-edge, no productivity check, no non-DAG
  machinery.
- **Extends existing vocabulary.** The augmented uncollect is "Open
  ListIter plus one port pair," and the feedback end is a collect —
  a generalization of nodes the language already has, which is what
  foundations-before-features asks for.
- **Native fit with the transformation-levels machinery** (derived
  views, reduce-close referencing the derived combined flow).

Against:

- **The feedback mechanic is undesigned.** "Close the state variable
  without closing the outer flow" has no pinned concrete form, and
  cursor-as-feedback ties the result structure to authoring order —
  out-of-order generalizes need the explicit-wire variant, which may
  reintroduce the cycles this option avoids (and then it has no
  productivity story at all).
- **Weaker inside-out pass.** The cut node genuinely differs inside
  vs. outside the flow; the principle must be read as forbidding only
  *invisible* differences.
- **Openers grow.** Each accumulator adds ports to the opener, and
  stacked generalizes produce a chain of combined flows — the "same"
  logical iteration exists in several versions, all needing rendering
  and reference conventions.
- **Self-driven streams are a degenerate case.** Fibonacci is an
  iteration opener with no `src`, which is a slightly awkward reading
  of "opening" anything.

**Option 3: Both, with the user choosing per scenario and the ability
to mix and convert.**

For:

- **Each form fits a different authoring moment.** "Delay this one
  value, starting from X" reads naturally when state is a single value
  beside a computation; the augmented flow reads naturally when the
  *flow* is what's stateful (scans, parsers, simulations). Offering
  both meets programmers at their abstraction level per-scenario
  rather than forcing one shape onto all of them.
- **Conversion has a natural home.** The transformation-levels doc
  already treats directional conversions as level-1 operations.
  Delay→augment is a lowering; augment→Delay is a recognition. If the
  candidates are semantically equivalent, "both" is one semantics with
  two presentations, and the choice becomes as cheap as the
  transformation-level/result-level distinction.
- **Defers the decision without blocking implementation.** Evidence
  about which form people actually reach for accrues from use — the
  same empirical stance as the rail notes' "sample real loops" plan.

Against:

- **It strains "one obvious way."** The abstraction-level principle's
  stated goal is that a given program has one obvious expression;
  two first-class forms for iteration state means every reader must
  know both and every writer faces a choice at every use site. This is
  the most direct philosophical cost of the three options.
- **Most machinery.** Two compile paths, two well-formedness stories
  (the productivity check *and* the feedback-collect rules), plus a
  conversion whose round-trip semantics must be specified and kept
  correct.
- **Mixing creates unexamined interactions.** A Delay referencing an
  augmented flow's state port, or an augment whose `src` is a flow
  that Delays also reference, are configurations neither thread has
  worked through.
- **The coexistence must be defined, or it will be accidental.** If
  the two forms are exactly equivalent, having both as *primitives*
  duplicates a construct; if they subtly differ, mixing acquires edge
  semantics nobody chose. Option 3 is principled only if the
  conversion is total and semantics-preserving in both directions —
  which is precisely the unproven equivalence question.

A reading of the balance: option 3's cost collapses if the equivalence
holds — then "both" is really one primitive with two views, the
productivity check transfers through the conversion, and the
one-obvious-way concern softens to a presentation preference (the
many-paths/few-readings corollary: authoring paths may differ so long
as the result-level reading is one thing). If the equivalence fails,
option 3 does not automatically die — coexistence can be organised
without inter-convertibility (see "Coexistence without equivalence"
below) — but it gets more expensive, and the specific way the
equivalence fails would itself be informative about which form is more
fundamental.

### Commentary on the three options (recorded positions, 2026-07-05)

Four positions were taken on the analysis above; they redirect the
work that follows.

**Cycles are probably inevitable.** The prediction: the language will
have to support cycles eventually, whatever happens with iteration
state. Too many real-world concepts are genuinely cyclic to insist
that every one of them be represented acyclically. So "the graph stops
being a DAG" — option 1's headline cost — should be heavily
discounted: it is a cost the language likely pays sooner or later
regardless, and paying it for a well-understood construct with a
decidable check is a good first occasion. (The conversion analysis
below independently supports this: cross-referencing accumulators
reintroduce a cycle in the *augmented* form too — see "The
cross-reference cycle does not go away".)

**The imperative shadow over augmented flows.** The deepest hesitation
about option 2 is not any listed mechanic but a gestalt: an iteration
variable woven into a flow starts to look like an imperative program
dressed up in the language of flows. The state port resembles a state
variable in Haskell's `ST` monad — addressed, updated, threaded by
convention. At that point it is just imperative programming, and the
naturalness that visual programming is supposed to provide is lost.
The rail notes flagged the same failure mode from the visual side: a
generic register with read/write ports "collapses into the imperative
paradigm wearing visual clothing."

**The RTL shadow over Delay.** The symmetric hesitation about
option 1: a program built from Delay nodes starts to look like
Verilog. It is register-transfer logic, which is not known for being
natural to beginners. RTL has a real virtue — you can see the data
path by following a wire — but its timing structure is invisible in
the picture: it has to be *deduced by counting registers*. A Delay
node is a point; everything about "when" happens at that point and
must be reconstructed in the reader's head.

**Equivalence is a convenience, not a precondition.** The balance
paragraph above originally claimed the equivalence question was
load-bearing for coexistence. Position: not convinced. Conversion
between the forms is nice to have, but coexistence can be organised
in ways that do not require it (see "Coexistence without
equivalence").

Finally, a conjecture: there may be a **fourth option** — a construct
that is natural and *visual*, takes inspiration from both candidates,
and degrades into either of them for complicated cases. The key
requirement: the user should be able to **see the state threading
through the loop**, rather than merely infer it. This is developed in
"A fourth option: the visible state thread" below.

### What would decide

- **The feedback mechanic.** If the latent form's feedback collect
  ("close the state variable without closing the outer flow") cannot be
  given a clean concrete form, the port form's step-input wins by
  default. Conversely, if it can, the latent form avoids the non-DAG
  representation entirely.
- **Compile experience.** The port form requires the compiler to accept
  a non-acyclic Expr graph plus a productivity check; the latent form
  requires generalizing Open and adding a feedback-collect consumer.
  Whichever lands more naturally on the existing Open/Close machinery
  is evidence.
- **They may be the same thing.** The port form's Delay may turn out to
  be exactly the result-level expansion that the latent-flow
  transformation lays down — a Delay node being a presentation of the
  (seed-in, state-out, feedback) triple. If so, the choice dissolves
  into a transformation-level/result-level distinction (per
  `transformation-levels-design.md`) rather than a design fork, and the
  productivity check transfers to the latent form directly. Working
  this equivalence out is the most promising next step.

---

## Converting between the two forms

This section works the conversion out in both directions. The result:
both conversions exist and are total, but they are not symmetric — one
direction is canonical and the other requires an arbitrary choice —
and working through the cross-reference case surfaces a cycle in the
augmented form that its acyclicity story had not accounted for.

### Delay → augmented flow (lowering)

Given a Delay `D` with initial value `i` and step wire `s`, tied to a
flow `F` with opener `O`:

1. Replace `O` with the augmented opener `U`: `O`'s inputs plus a
   `seed` input wired from `i`; `O`'s outputs plus a `state` output.
2. Rewire every reader of `D.prev` to `U.state`.
3. Wire `s` into `U`'s feedback collect, which emits the modified
   flow `F′`.
4. Repoint flow-level consumers of `F` (closes, later generalizes) to
   `F′`, per the stacking rule.

For **multiple Delays** `D₁ … Dₙ` on one flow, the conversion stacks
augmentations: choose an order, make `Uₖ`'s `src` the combined flow of
`Uₖ₋₁`. Every state port is visible in the shared body, so arbitrary
cross-references between the accumulators still wire up. But the order
is a *choice*: the Delay form has no ordering among the `Dᵢ`, and no
semantic content hangs on the stack order (every state read is a
previous-iteration read; the state ports have no within-iteration
dependency on each other). The lowering therefore has n! equally valid
results.

### Augmented flow → Delay (recognition)

Given an augmented opener `U` with seed `i`, source `F₀`, state
output, and feedback `s`:

1. Restore the plain opener `O` on `F₀`.
2. Mint a Delay `D` with `init = i`, tied to `O`; rewire readers of
   `U.state` to `D.prev`; wire `s` into `D.step`.
3. Stacked augmentations unwind one layer at a time, inside-out; each
   layer yields one Delay. The stack order is simply forgotten.

This direction is total and **canonical** — no choices anywhere.

### What the asymmetry says

The round trips: Delay → augment → Delay is the identity;
augment → Delay → augment reproduces the original only up to stack
order. So the two forms are semantically inter-convertible, but
structurally the Delay form is the *quotient*: the augmented form
draws a distinction (the stack order) that carries no meaning, and the
Delay form doesn't draw it. In the vocabulary of the fifth principle,
the Delay side is the more abstract description and the augmented flow
behaves like a *derived view* of it — recognition (augment → Delay) is
the canonical map, lowering (Delay → augment) is a section of it. That
is an argument about which form should be the program of record if
both exist; it is *not* an argument about which form should be the
authoring surface, and it holds only so long as the stack order stays
semantically inert (a future feature that sequences state updates
within an iteration would break the quotient).

### The cross-reference cycle does not go away

Converting Fibonacci exposes a hole in the augmented form's
acyclicity story. Two Delays with `fib_b.step` reading `fib_a.prev`
and vice versa convert to two stacked augmentations `U₁`, `U₂`. Now
ask where `U₂`'s `src` comes from. The latent-flow section says the
feedback collect "produces the modified flow" — but `U₁`'s feedback
input reads `U₂.state`, which only exists downstream of `U₂`'s
uncollect, whose `src` is supposed to be `U₁`'s modified flow. That is
a cycle. The two ways out:

- **Emit the combined flow from the uncollect** (the feedback collect
  reverts to a pure consumer with no output) — which reinstates the
  "terminal node with no output" discomfort that the modified-flow
  reframing existed to fix; or
- **Accept the cycle** — in which case the augmented form needs the
  productivity story after all, and its "graph stays acyclic"
  advantage holds only for non-cross-referencing accumulators.

Either the discomfort or the cycle comes back. This is independent
support for the recorded position that cycles will have to be
supported eventually: even the form designed to stay acyclic runs
into one as soon as accumulators reference each other, which is not
an exotic case (Fibonacci is the second example anyone writes). It
also sharpens open question (b) on the feedback collect: the question
is not just its form but which side of it the combined flow comes out
of.

---

## Coexistence without equivalence

Recorded position: conversion is a convenience, not a precondition
for coexistence. Working that out: there are at least three ways to
have both forms in the language that do not rest on a proven two-way
equivalence. What every one of them *does* require is a single answer
to "what does a mixed program mean" — provided by a stored form, a
boundary, or a core, rather than by pairwise conversion.

**Stored-form asymmetry (derived views).** One form is the program of
record; the other is an always-available, read-only derived view (the
fifth principle's machinery, already needed for reduce-close). Only
one direction of conversion needs to exist — the derivation — and it
can even be lossy in the other direction, because nothing is ever
converted back: authoring gestures made on the view are reinterpreted
as edits to the stored form. The quotient result above nominates the
Delay form as the stored one (it draws no meaningless distinctions)
with the augmented flow as its flow-level view; the reverse
arrangement is arguable if the flow-level reading turns out to be
where most building happens.

**Domain split.** Each form owns scenarios outright: say, augmented
flows for single-flow scans, Delay nodes for cross-referencing
recurrences and self-driven streams (where, per the conversion
analysis, the augmented form has a cycle anyway). No conversion at
all; a designed boundary instead. The costs are that the boundary
must be learnable, and a program that grows across it (a scan that
acquires a second, cross-referencing accumulator) needs manual
rewriting at exactly the moment the user is thinking about something
else.

**Common core.** Both forms desugar to a shared result-level core —
ultimately the loop register: init-before, read-at-top,
write-at-bottom, final-after. Mixing semantics is defined once, at
the core, not pairwise between surfaces: a Delay and an augmented
flow in one program mean whatever their registers mean side by side.
Conversion between the surfaces becomes optional tooling. This is the
cheapest coexistence to specify, at the cost that the core — not
either surface — is where the language's actual semantics lives, and
the core is exactly the imperative register picture both surfaces
exist to dress.

---

## A fourth option: the visible state thread

The recorded critiques are symmetric in an instructive way. The Delay
node is a **point**: you can follow the data path, but the timing
structure has collapsed into the node and must be deduced — RTL,
counting registers. The augmented flow is a **cell**: state becomes a
slot of the flow that the body addresses and updates — the `ST` monad,
imperative programming in flow clothing. One erases time from the
picture; the other erases the state's identity as a followable thing.

What the user should instead be able to do is *see the state
threading through the loop*. That names a construct: the state's
history should be a **path** in the picture — a line you can follow —
not a point and not a slot.

### The proposal

Promote the redesigned iteration rail from "visual depiction of the
construct" to **the construct itself**. A *state thread* is a
first-class path with four anchored connections, and its geometry is
its semantics:

- It **enters** from the initial value (the dotted attach, outside
  the iteration).
- It **crosses** the single generic iteration column, where it has
  exactly one **tap** (the per-iteration read) and, later along the
  thread, one **writeback** (the per-iteration write). The stretch
  between tap and writeback is that iteration's state epoch.
- It **exits** as the final value — a first-class endpoint, not a
  separate close bolted on. (The rail notes already had this: the
  final value "emerges from the right end of the rail.")

Position along the thread *is* time. Following the thread from left
to right reads the state's whole history: initial value, then each
iteration's read-compute-write epoch, then the final value. Nothing
about "when" needs to be deduced; the thread displays it.

### The two candidates are its degradations

The point of the thread is that both existing candidates fall out of
it by *erasing part of the path*:

- **Contract the thread to a point** — keep only its connection
  endpoints, discard the drawn path — and you have exactly the Delay
  node: `init` in, `prev` out (the tap), `step` in (the writeback).
  This is why Delay feels like Verilog: it is the thread with its
  timing geometry deleted, so the timing must be reconstructed by
  counting.
- **Absorb the thread into the opener** — keep only where the path
  crosses the column boundary, discard its identity as a line — and
  you have exactly the augmented flow: the (seed-in, state-out) port
  pair plus feedback. This is why augment feels imperative: the
  thread's followable identity has dissolved into "the flow's state,"
  a cell.

So the fourth option is not a third semantics. It is the claim that
the thread is the *primary surface*, and Delay and augment are its two
projections — each legitimate, each used precisely where the path
picture degrades:

- **Cross-referencing threads** (Fibonacci): two parallel threads with
  taps between them. Drawable and still followable for two or three
  threads; for dense mutual reference the picture tangles, and
  contracting to Delay nodes (the point projection) is the honest
  fallback — this is also the case where cycles are unavoidable in
  any form, per the conversion analysis.
- **Whole-flow operations** (stacking further generalizes on a scan,
  reduce-close's derived view, referencing the combined flow as a
  thing): use the flow projection — the augmented flow *is* the
  thread as seen by the flow level.

"Degrading into either for complicated cases" is then literal: the
degradations are the projections, and each complicated case selects
the projection that keeps its structure legible.

### Where it lands on the earlier analysis

- The thread's semantics is exactly the shared core from "Coexistence
  without equivalence": init-before, read, write, final-after. The
  fourth option is that coexistence model with a *visible surface* on
  top — the core stops being a hidden register and becomes the drawn
  thread, which answers the objection that the core is "the
  imperative picture both surfaces exist to dress." Dressed in
  geometry, the register is a history you can see.
- The conversion asymmetry carries over: thread → Delay and
  thread → augment are both erasures (canonical, total); neither
  projection can reconstruct the thread alone, but together with the
  drawn layout they can. The thread is the common refinement the
  quotient analysis was circling.
- The productivity check restates naturally: threads may tap each
  other, and a cycle is well-formed iff it passes through a thread's
  tap-to-writeback epoch — i.e., every feedback loop is visibly
  carried by some thread. The check's subject is now something the
  user can point at.

### Open questions for the thread

- **Multiple writebacks.** The rail notes' uncovered cases —
  conditional carry, multi-site update — reappear. The clean rule is
  one writeback per crossing, with conditional carry expressed as a
  conditional *value* wired into the single writeback. Whether that
  survives contact with real loops is exactly what the rail notes'
  "sample real code" plan should test.
- **The crossing rule.** Threads are a new wire species. Do
  thread/value and thread/thread crossings fall under the existing
  no-crossing rule, or does the thread's horizontal-rail geometry
  need its own convention (the rail already crosses the column's
  vertical wires by design)?
- **Result-level status.** Is the thread a result-level construct of
  its own, or a transformation-level presentation over one of the two
  projections as the stored form? The stored-form-asymmetry model
  suggests: store the point projection (Delay, the quotient), render
  the thread, offer the flow projection as a derived view. That would
  make the fourth option an arrangement of the existing pieces rather
  than a new primitive — which is the cheapest version of it that
  still delivers the visible threading.

## What is still unresolved

This is a work in progress. The following are areas that need further
critique before the primitive can be considered settled:

**The concrete form of the link.** Narrowed to two live candidates,
arrived at independently from the same lambda critique and deliberately
kept side-by-side (see "Two live candidates, kept side-by-side"):

- **The port form**: the Delay node expressed as ports — an `init`
  input, a `prev` output port, and a `step` input port. Passes the
  inside-out test cleanly (`prev` is a wired output port like the list
  element), makes self- and cross-reference both just wires, and needs
  no construction-time cycle (`step` is wired as a separate act, the
  way Close is wired to Open). It is the same node the visual
  iteration-rail design arrived at independently. What it leaves open
  is implementation-shaped: the `step` back-edge makes the computation
  graph non-acyclic, which the current DAG-assuming compiler cannot yet
  handle; the compile target is a single mutable `let` register inside
  the loop (per the iteration-rails notes). *(2026-07-07: the
  representation half of this is worked out — the write half is its
  own node, holding the step and outputting the final value; see
  `first-class-ports-design.md`, "The Delay back-edge." The object
  graph stays a DAG; only the compiler work remains.)*
- **The latent-flow representation**: generalize cuts a wire,
  interposing an uncollect whose seed input is the cut wire's producer
  and whose state output feeds the cut wire's consumer, with the source
  flow as a separate `src` input; the feedback collect produces the
  modified flow. Also drops the lambda and makes self- and
  cross-reference uniform. What it leaves open is design-shaped:
  (a) whether feedback is the cursor or an explicitly named wire;
  (b) the exact form of the feedback collect that closes the state
  variable without closing the outer flow; (c) confirming the stacking
  rule (each generalize takes the current combined flow as `src`) is
  the right composition for arbitrary numbers of accumulators.

Four ways forward exist — adopt the Delay node, adopt augmented flows,
keep both with the user choosing per scenario ("The three options and
their tradeoffs"; conversion worked out in "Converting between the two
forms", coexistence models in "Coexistence without equivalence"), or
the conjectured fourth option: the visible state thread, with Delay
and augment as its point and flow projections ("A fourth option: the
visible state thread"). The conversion analysis established that the
forms are semantically inter-convertible (Delay is the quotient —
recognition is canonical, lowering requires an inert ordering choice)
and that cross-referencing accumulators produce a cycle in *both*
forms, so acyclicity cannot be the deciding criterion. The thread
proposal is currently the most promising direction because it answers
both recorded gestalt critiques (RTL-point and ST-cell) while reusing
the two candidates as its degradations.

**How the link relates to its flow.** Resolved at the structural level,
in both candidates: the link is always explicitly tied to a specific
flow, either pre-existing or created by the same generalise step
(example-first; the flow is born with the link), and a link with no
external iteration source is a self-driven stream (Fibonacci), not an
error. The candidates differ in mechanism: the port form's Delay
*references* its flow; the latent form's uncollect takes the source flow
as a separate `src` input and outputs a combined flow, with later
generalizes taking the current combined flow as their `src` so
accumulators stay in lockstep. What remains open is the concrete
surface for the attachment (naming a flow vs choosing the `src`).

**Self-reference and cycles.** Resolved. The Delay crossing
(`step → prev`) is the only iteration-boundary edge in the language, so
productivity is the structural condition "every cycle passes through a
Delay crossing" — equivalently, deleting the crossings must leave the
graph acyclic. The check is a decidable whole-graph quotient
constraint (like alt-matching and no-crossing), enforced by cycle
detection rather than by construction; it accepts exactly the
productive programs and is the same causality check synchronous
dataflow languages (Lustre's `pre`/`->`) and hardware design have used
for decades. See "Ruling out non-productive cycles structurally." Note
this is stated in the port form's vocabulary (the `step → prev`
crossing). The latent-flow candidate has no worked cycle story yet:
under cursor-as-feedback its result graph may stay acyclic by
construction, but whether the productivity condition transfers — and
what a non-productive configuration even looks like in that form — is
open.

**Non-homogeneous iteration as a separate problem.** What if different
iterations behave differently — not just first vs. subsequent, but
conditionally different at each step? This is explicitly set aside as a
separate question and isn't part of the stateful iteration primitive.
Worth naming so it doesn't get conflated with what's being designed
here.

**Operator identities.** Reduce-close needs each associative operator to
carry an identity (`+`→0, `*`→1, `max`→−∞) for the empty-list value. How
identities attach to operators — a registry, a property on the operator
node, something the user can extend for custom monoids — is not yet
designed.

**Which derived ports a reduce-close (or augment) exposes.** Building a
second accumulator references the derived combined flow. The exact set of
principal output ports a derived result exposes for reference (versus
internal derivation structure that must stay private) needs pinning. See
`transformation-levels-design.md`.

**Which side of the feedback collect the combined flow comes out of.**
Sharpened by the conversion analysis ("The cross-reference cycle does
not go away"): if the modified flow is the feedback collect's output,
cross-referencing accumulators create a cycle among the augmentations;
if it is the uncollect's output, the feedback collect is again a
terminal node with no output. One of the two discomforts must be
accepted (the recorded cycles-are-inevitable position leans toward
accepting the cycle), and the choice shapes the augmented form's
well-formedness story. *(2026-07-07: the either/or is no longer
exhaustive — the feedback collect's output can be the final value
rather than the combined flow, dissolving the terminal-node horn
while the combined flow comes out of the uncollect with no cycle.
See the crossover note in `first-class-ports-design.md`, "The Delay
back-edge.")*

**The state thread's open points.** Whether one-writeback-per-crossing
survives real loops (conditional carry, multi-site update — test
against the rail notes' "sample real code" plan); how threads interact
with the no-crossing rule; and whether the thread is its own
result-level construct or a rendering of a stored projection (the
cheapest version: store the Delay quotient, render the thread, derive
the flow view). See "A fourth option: the visible state thread".
