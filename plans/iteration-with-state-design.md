# Iteration with state

How does a loop carry a value from one iteration to the next — a running
sum, a maximum-so-far, a Fibonacci pair — in a language whose defining
move is that loops have no interior scope? This is the largest open
design area. This document works out the shape of the primitive and
records the dead ends along the way.

Code samples use the textual syntax from
`textual-representation-design.md`. Terminology predates the
uncollect/collect renaming: "open"/"opener" mean uncollect, "close"
means collect, "reduce-close" the reducing collect.

## Reader's guide

The design has converged to a single result-level construct — the
**register pair** (a read half and a write half, wired across the
iteration boundary) — reached by two independent routes that turn out
to describe the same thing under two drawings:

- **The Delay node in port form** (§"Candidate A"): one node with an
  `init` input, a `prev` output port, and a `step` input port.
- **The latent-flow augmented uncollect** (§"Candidate B"): generalize
  cuts a value wire and interposes an uncollect that carries the
  accumulator as an extra port pair.

Both are **live**. Neither is rejected. §"The equivalence, worked"
proves them result-level equivalent — one register pair, two drawings —
so at the semantic level there is nothing left to choose between them.

What is **still open** is the *surface*: which drawing is primary, what
a beginner meets first, and whether a third drawing — the **visible
state thread** (§"A fourth option") — should be the surface with the
other two as its projections. The bar for that decision: a construct
both *easy for beginners* and *flexible enough for complex code*, with a
smooth ramp between — the beginner's running sum must expand into the
hard cases (a second accumulator, cross-referencing registers,
early-termination) by *adding structure*, never by switching to a
different construct (the "building blocks must build" principle,
`language-design-philosophy.md`).

The two-phase back-edge construction both candidates rest on is worked
out in `first-class-ports-design.md` ("The Delay back-edge: the write
half is a node"). Rejected shapes are recorded in place below with their
reasons: `stateful(...)`, `prev(x)`, the Delay *lambda* form, and the
output-less terminal stateful-collect.

## The problem: multi-accumulator iteration without a bottleneck

Imperative loops carry state easily and illegibly. You declare as many
variables as you like, update them independently, read them after the
loop — but the code says nothing about intent. There is no `sum()`, only
an accumulator you must trace by hand to recognize.

Functional languages recover the named-operation clarity (`sum`, `max`)
but impose a **bottleneck**: a multi-output fold packs all carried state
into one tuple, threads it through, and unpacks it every step. Two
accumulators is a 2-tuple; three is a 3-tuple. The packing obscures what
happens, and the outputs lose their identity as separate things — they
become slots.

    fold(list, (0, -inf), (acc, x) => (acc[0] + x, max(acc[1], x)))

The goal is the functional clarity without the bottleneck. Each carried
variable should be independently nameable and independently readable,
with no tuple at any level. **Adding a second accumulator must not touch
the first.** This is the same multi-output goal the language pursues
everywhere (several closes on one opener, each independently readable, no
tuple), applied to carried-across-iteration state.

Three design commitments shape every candidate below:

- **Example first, then generalise.** You write the concrete step
  (`0 + element`) and then apply a transformation that makes it iterate.
  You do not declare a general fold and instantiate it. A primitive that
  forces you to declare the iteration structure upfront is suspect; one
  that starts concrete and identifies a relationship is preferred. The
  tuple bottleneck is itself an instance of the anti-pattern — it forces
  the fold's type (the generalisation) before you know all the
  components.
- **Building blocks at the programmer's level.** `sum` says what it
  means; a tuple-threaded fold is equivalent but communicates nothing.
  The criterion for a primitive is not "is it minimal?" but "does it
  meet the programmer at the level of their own abstractions?" `sum` and
  `max` as two named outputs of one loop is the obvious way to write two
  accumulators; a 2-tuple through a fold is not.
- **Foundations before features.** A wrong foundation compounds: every
  feature built on it inherits the flaw. Rejecting a candidate primitive
  on paper — even after substantial design work — is cheaper than
  implementing the wrong thing and dismantling it later. This is why the
  work below spends more time in critique than in construction.

The target, in the textual register syntax (spelling provisional; this
is the port-form surface):

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum
sum, a -> add -> step of sum => total
```

`~L ~> delay init 0 => sum` reads the register: bare `sum` is the
previous value, `0` the value before any iteration. `sum, a -> add ->
step of sum => total` writes it: add the previous sum to the element and
deposit the result as the next step; `total` is the final value. One
running sum, no tuple, no fold declared upfront.

## Rejected: `stateful(initial, update)`

The first candidate was a function-like call:

    runningSum = stateful(0, prev + x)

It was rejected — not because it cannot be made to work, but because it
would be a wrong foundation. Four reasons, each of which the eventual
design has to respect:

- **It looks like a function call but isn't.** The two arguments are not
  peers evaluated in one scope. `initial` (`0`) is evaluated once,
  *outside* the iteration. `update` (`prev + x`) is evaluated once per
  iteration, in a scope where `prev` exists. Different things at
  different times in different scopes, dressed as sibling arguments.
- **`prev` is a scope-contaminating magic name.** Inside `update`,
  `prev` is suddenly in scope. No other expression in the language has
  this property. It is the inside-out anti-pattern the language exists to
  avoid: a construct whose interior scope differs from its exterior.
- **It is secretly a case split.** The two arguments are really two
  cases — first iteration (no previous value) and subsequent iterations
  (previous value exists). The language already has case splits;
  `stateful` smuggled one in under a function-call surface.
- **The initial value is misplaced.** `initial` is written inside the
  call but is not inside the flow. It cannot depend on per-iteration
  values — there are none yet. Positioning it as an argument alongside
  the recurrence implies a shared scope that does not exist.

## Considered: `prev(x)`

The second candidate: a unary operator returning `option<X>` — `None` on
the first iteration, `Some(previousValue)` after.

It gets the semantics right (first iteration is `None`, the split is
visible, self-reference is just a name binding). But it was set aside:

- **Its argument is a label, not a value.** Every other operator takes
  values and produces values. `prev(x)` does not read `x`'s value; it
  uses `x` as an identifier to locate "the node labeled `x`, one
  iteration ago." The argument is node identity. Nothing else in the
  value language works this way.
- **It is a flow-level feature written as a value expression.**
  `prev(x)` means something only inside an iteration; outside any flow it
  is meaningless. Yet it is spelled as an ordinary value-layer expression
  with no sign it depends on the surrounding flow. When a value is
  provided by the flow structure (like a list element from the opener),
  the language should show that.
- **Many `prev` uses are one case split written many times.**
  `prev(sum)` and `prev(product)` both yield `None` on iteration 0. There
  is only one first-vs-subsequent distinction — it is a property of the
  flow, not of each value. Two `prev` calls imply two independent
  discriminations when there is one.
- **The `None` case belongs outside the flow.** The `None` branch is the
  initial case, evaluated before any iteration; it can only depend on
  outside-flow values. Writing it as an `alt` of an in-flow case-split
  positions it as per-iteration computation. It is not.

## Where the critiques converge

The two rejections point at a common shape:

- **The initial value belongs outside the opener.** It should not be an
  input to the flow's uncollect — that would force you to enumerate every
  carried variable when you write the opener, the tuple bottleneck moved
  to the opener. Instead the initial value attaches independently, one
  per iteration construct.
- **The first-vs-subsequent split is flow-level, not value-level.** It is
  one property of the surrounding flow, expressed once, within which all
  initial values live in the first-iteration scope and all carried values
  in the subsequent scope — not a per-variable `case(prev(x))`.
- **The carried value is provided as a port, not conjured by an
  operator.** Like the list element off a list-open node, the carried
  value should be an output the body reads by wiring — visible because it
  was wired in, not because a special-scoped function was invoked.
- **Closing initial+step does not close the outer flow.** Combining the
  initial case and the step case ends the first/subsequent distinction
  for *that variable* and produces its current-iteration value; the outer
  list or stream flow stays open and iteration continues. This is
  analogous to partial closure in case splits (closing two alts without
  closing the containing flow).

## The grid the construct must express

Laid out as a grid, iteration state has two axes:

- **Variable identities** (rows): `sum`, `max`, `count`, … —
  independently nameable, no tuple.
- **Roles** (columns): assign-initial, assign-iterated, access-previous,
  access-current.

The grid is not fully combinatorial. Three columns are coupled: a
variable participates in *all* of {assign-initial, assign-iterated,
access-previous} or in none of them.

- assign-initial and assign-iterated must coexist — no state without both
  a start and a step.
- access-previous requires both — iteration 0 reads assign-initial, later
  iterations read the previous assign-iterated.
- assign-initial + assign-iterated without access-previous is vacuous:
  updating a value nobody ever reads as a previous value. Not stateful at
  all.

The fourth column, access-current, is independent — a per-iteration value
read within the current iteration (the list element) needs none of the
coupling. *Being stateful is exactly being in the three-way coupling.*

The coupling need not be enforced by construction. The language already
relies on **quotient constraints** enforced as checks: matching alts on a
CaseSplit, a collect compatible with its opener, type agreement, the
no-crossing rule. So it is acceptable that a variable's three slots must
refer to one identity, enforced as a matching constraint rather than
built as one inseparable unit.

## Rejected shape: the output-less terminal stateful-collect

An early framing made the feedback operation — the thing that deposits a
step value for the next iteration — a **terminal node with no output**:
regular collect produces a downstream value, but stateful-collect merely
consumes the step value and feeds it back, producing nothing.

This shape is rejected, and the rejection stands: **a feedback node must
have an output.** The "produces nothing, hangs in the air" quality was a
real source of discomfort in a language otherwise modelled on functional
behaviour, and it names a genuine conflict — but the answer is not to
accept an output-less node. Both live candidates dissolve it, each in its
own way:

- The **port form** has no separate feedback node at all — the step is an
  *input port* of the register, so nothing output-less exists.
- The **latent form**'s feedback collect *does* produce something: the
  final value (see §"The equivalence, worked"). The write half worked out
  in `first-class-ports-design.md` recovers a distinct writing *node* that
  is not terminal precisely because it outputs the final value — the
  exit anchor the one-node contraction had no port for.

The conflict this shape names is what both reframings answer; that is why
it is kept on record.

## The link: generalize a concrete step

The rejected primitives both asked the user to design a general iterative
computation upfront. The **link** does not. Start with a concrete
single-step calculation:

- you have `0`;
- you have `element` (the first element of a list);
- you compute `0 + element`.

Then observe: the result of `0 + element` plays the same role `0` played.
**Link** the result back to where `0` was — "this output and this input
are the same thing across iterations." Before the link there is no
iteration, just a one-step calculation. After it there is. *The link is
the primitive.* Adding a second accumulator is adding a second link,
independently — no tuple, nothing else disturbed.

**The link splits the initial value.** Before the link, `0` is one thing.
After, there are two structurally distinct things: `0` *outside* the
iteration (the initial value, unchanged) and a *previous result* inside
the body, in the position `0` held. One thing became two. This is
example-first made concrete: write the special case, then generalise by
identifying the feedback.

### The link closes the empty-list case

Accessing the first element of a list is a partial operation — the list
might be empty, and `0 + element` only makes sense if an element exists.
The link resolves this. If the list is empty, the iteration runs zero
times and the result is just `0`. The initial value serves double duty:

- the starting "previous" value for a non-empty list, and
- the complete answer for an empty list (zero iterations).

You cannot link without providing an initial value (the empty case would
be unhandled), and providing one without linking is just a constant. In
flow terms the link is *simultaneously* a close for the empty case and an
open for the iteration — the same act.

A consequence: **access-previous is never option-typed.** The `prev(x)`
candidate returned `option<X>` to handle "first iteration has no
previous." Under the link that case never arises: the initial value *is*
the first previous value, so on every iteration — including the first —
a well-defined previous value is available. The first/subsequent
distinction is handled by the mechanism and is invisible inside the body.

### The link is a graph transformation, not a program element

"You can only stateful-collect once per variable" confused two levels. At
the *variable* level, one variable has one write slot, and two step
values for it conflict — still true. At the *program* level, the link is
a **transformation** applied to a program to produce a new program: pick
a position, get back a program where that position is an iteration
variable. It can be applied any number of times, each at a *different*
position, each creating one independent variable. No conflict, because
each application makes a new variable at a new position.

Concretely, starting from `e = (1 + 2) + first_element`, you could link:

- where `1` was — one iterative program;
- where `(1 + 2)` was — a different one, the variable initialized to `3`;
- both at once — two independent iteration variables.

The link **cuts** the graph at the identified position. Whatever computed
the value there is replaced by the iteration variable (initial value on
step 0, fed-back value after). Everything downstream just sees a value;
it does not know a cut occurred. When two cut positions are in a
dependency relationship — `(1 + 2)` depends on `1` — the downstream cut
*severs* that dependency below it: after cutting at `(1 + 2)`, the
downstream computation no longer sees the updated `1` flowing through
`+ 2`; it sees the independent variable seeded at `3`. Each cut is local.
This is the argument for the transformation framing over a declaration
framing — a "declare an iteration variable" approach would have to decide
upfront what `(1 + 2)` means when `1` is also a variable; the
transformation sidesteps it, cuts applied one at a time, no global
coordination.

## Worked example: two independent accumulators

Test the core claim — a second accumulator is a second link, no tuple.
Start non-iterative:

    sum_init = 0
    max_init = -infinity
    element  = list[0]           -- partial: list might be empty
    sum_step = sum_init + element
    max_step = max(max_init, element)

Two constants, one partial access, two computations. Apply two links:

- **Link 1 (sum):** feed `sum_step` back to `sum_init`'s position.
  `sum_init` becomes a variable seeded at `0`; the formula is unchanged;
  the empty case is `0`.
- **Link 2 (max):** feed `max_step` back to `max_init`'s position.
  `max_init` becomes a variable seeded at `-infinity`; formula unchanged;
  empty case is `-infinity`.

The grid after both links:

|  | assign-initial | assign-iterated | access-previous | access-current |
|---|---|---|---|---|
| `sum_init` | `0` (outside) | `sum_step` | `sum_init` (per-iter) | — |
| `max_init` | `-inf` (outside) | `max_step` | `max_init` (per-iter) | — |
| `element` | — | — | — | provided by list-open |

`element` is access-current only. Neither link touches it or the other.
Their only interaction is sharing `element` through the containing list
flow. Different seeds, different steps, neither knows the other exists;
adding a third accumulator (`count`, seeded `0`, stepped `+1`) is a third
independent link. The functional bottleneck has vanished.

In the register syntax, two independent registers on one loop:

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum
sum, a -> add -> step of sum => total
~L ~> delay init neginf => hi       -- neginf = js "-Infinity"
hi, a -> max -> step of hi => curMax
```

Two `delay`s over the same `~L`, two independent step lines, no tuple.

### How the link relates to its flow

Two cases, resolving the same way — the link is *always* tied to a
specific flow:

- **Inside an existing flow.** If a list flow is already open, a link
  created within it references that flow. Iteration state is a feature of
  a specific flow, not free-floating.
- **Example-first generalize.** Starting from the concrete program above,
  `element = list[0]` is a partial access — no list flow exists yet.
  Applying the link *is* the generalise step on `list[0]`: "the first
  element" becomes "each element," and the list-open is born in the same
  act. The flow and the link are created together.

**The self-driven edge case.** A link whose step depends only on
outside-flow values plus its own accumulator has no external iteration
source. Applying it creates a flow that is *purely* the feedback loop — a
self-driven stream. Fibonacci is this: two links, no external list, just
the recurrence. Not an error; it falls out of the same generalise step
applied to a computation with no partial accesses. In the register
syntax, cross-referencing registers with a driving list:

```
steps -> open list => n, ~L
~L ~> delay init 1 => fa
~L ~> delay init 1 => fb
fb -> step of fa => lastA           -- fa's next value is fb's previous
fa, fb -> add -> step of fb => lastB -- fb's next value is fa + fb
```

Two registers, each reading the other's previous value through an
ordinary wire. No tuple, no lambda, no privileged "own previous" slot.

### Within one iteration there is no cycle

`sum_init` on iteration *n* is `sum_step` from iteration *n-1*, already
resolved. The backward edge is sequenced across iterations, not within
one. As a stream:

    sum_init_stream = cons(0, sum_step_stream)
    sum_step_stream = map2(sum_init_stream, element_stream, (+))

This is productive corecursion — each cell of `sum_init_stream` is
available one step before it is needed. Under delayed-cell semantics it
resolves without deadlock; the standard stream-recursion pattern, no new
machinery.

## From link to concrete construct: the lambda dead end

The link needs a concrete form in the language. The first attempt was a
`Delay` node written with a lambda — and it is dead, but its critique is
what produced both live candidates, so it is worth stating.

    Delay(init, prev => step)

- `init` — the initial value, evaluated outside the iteration; the
  first-step output.
- `prev => step` — a lambda where `prev` is the node's own previous
  output; the body computes the next value.
- output — the previous step's result (or `init` on step 0).

The three-way coupling maps cleanly (`init` = assign-initial, output =
access-previous, body = assign-iterated), all in one node with a normal
output, no matched open/close pair, no output-less terminal node. Applied
to the running sum:

    runningSum = Delay(0, prev => prev + element)

Two accumulators stay independent; cross-references reference the other
node's output directly:

    fib_a = Delay(1, _    => fib_b)
    fib_b = Delay(1, prev => fib_a + prev)

**Why the lambda is rejected.** The lambda `prev => step` introduces
`prev` into an *interior scope* — inside the lambda `prev` exists,
outside it does not. That is exactly the inside-out difference the
language forbids. It is milder than `stateful`'s magic name (the binding
is a visible lambda parameter, not a keyword conjured into scope), but
the concern applies in weaker form. And the lambda has a tell: for
cross-references it goes *unused* — `fib_a = Delay(1, _ => fib_b)` writes
a lambda whose parameter is ignored, because that step reads another
Delay's previous value, not its own. The lambda is mandatory even when
nothing reads `prev`. That the surface forces a lambda where none is
needed is the signal that the lambda is not the right mechanism.

Two threads answered this critique independently, without seeing each
other, and arrived at two constructs. Both are kept.

## Candidate A: Delay as ports

`prev` does not have to be a bound parameter. It can be an **output port**
of the Delay node — read by wiring, exactly as the current element is read
off a list-open node. A Delay node has three connections, none a lambda:

- **`init`** — an input from outside the flow; the first-step output.
- **a `prev` output port** — the previous step's result (or `init` on
  step 0), read downstream by wiring like any value.
- **a `step` input port** — the value to carry into the next step; whatever
  computes the new value wires *into* it.

The grid maps directly onto the three connections with no scope
difference anywhere (`init` = assign-initial, `prev` port =
access-previous, `step` port = assign-iterated).

**It passes the inside-out test cleanly.** In the lambda form the interior
of `prev => step` is a different scope from its exterior. In the port
form there is no interior: every expression in the body lives in one
scope, and `prev` is a wire off the Delay node, available wherever any
wire is. This is *exactly* how the list element is provided. Delay's
`prev` port is that same mechanism applied to "the previous step's
value" — no more inside-out than list iteration, which is to say, not at
all. It fulfils the earlier prescription verbatim: the carried value is
*provided* as a port and read because it was wired in.

**It is the iteration rail.** The visual notes
(`iteration-rails-design-notes.md`) reached this node from the other
direction: a horizontal rail crossing the iteration column, with a
tap-down read on the left, a writeback-up on the right, and a dotted
initial value. Those are Delay's three connections (tap-down = `prev`,
writeback-up = `step`, dotted = `init`). The non-visual reasoning worked
toward a lambda; the visual reasoning worked toward read/write ports;
they are the same primitive, and the convergence is evidence it is the
right shape.

**Self-reference and cross-reference become one thing.** The lambda's
unused-parameter awkwardness disappears — there is no parameter to leave
unused. A `step` input is wired from whatever computes the next value; a
`prev` output is read by whoever needs the previous value. Self-reference
(`runningSum`'s step reads its own `prev`) and cross-reference (`fib_a`'s
step reads `fib_b`'s `prev`) are both just wires:

    runningSum:  init 0   step = (prev of runningSum) + element
    fib_a:       init 1   step = (prev of fib_b)
    fib_b:       init 1   step = (prev of fib_a) + (prev of fib_b)

No lambdas, no unused parameters, no self-vs-cross special case.

**No construction-time cycle.** The lambda form needed the host's
`let rec` because `step` referred to `prev`, which referred to the node
being constructed. The port form needs no value-level recursion. It uses
the node-identity-plus-wiring pattern the codebase already uses for
Open/Close: mint the node (its `prev` port exists immediately and can be
referenced downstream), then wire its `step` and `init` as a separate,
later act — exactly like wiring a Close back to its Open. The Expr-level
mechanism is worked out in `first-class-ports-design.md` ("The Delay
back-edge: the write half is a node"): the later act mints its own node —
a write half holding the read reference and the step — so nothing mutates
the Delay after construction, the object graph stays a DAG
unconditionally, and the `step → prev` crossing is recovered from the
pairing. The write half's output is the final value: the thread's exit
anchor the one-node contraction had no port for.

**What it costs: the computation graph is not a DAG.** The `step` input
is a back-edge — it wires a downstream value back up into the node, so
the computation graph has a cycle. The current compiler assumes a DAG
(each binding at `deeper(args)`, laziness for ordering), so a back-edge
is the one thing it cannot yet handle. But the back-edge is not an
accident — it *is* the link ("cut the graph, feed the downstream value
back"). The cycle is the primitive, not a side effect. And the compile
target is known: a single mutable `let` register inside the loop. `init`
sets it before the loop, `prev` reads it at the top, `step` assigns it at
the bottom. The graph cycle becomes a write-after-read on one register in
the emitted JS — no cycle in the generated code, because the cycle was
only ever across iterations.

### Ruling out non-productive cycles structurally

Can the language rule out cycles with no base case (`x = x + 1`)
structurally? Yes, with one decidable graph check. In the port form the
computation graph has exactly two kinds of edge:

- **Ordinary value edges** — within one iteration, both endpoints of the
  same step.
- **The Delay crossing** — the internal edge from a Delay's `step` input
  to its `prev` output. This is the *only* edge that crosses an iteration
  boundary: the value into `step` at step *n* emerges from `prev` at step
  *n+1*.

Every back-edge is a Delay crossing, because Delay is the only construct
that makes one. So:

> **A cycle is productive iff it passes through at least one Delay
> crossing.** Equivalently: delete every Delay's `step → prev` edge; the
> remaining graph must be acyclic.

*Sufficiency.* If every cycle crosses a Delay, treating each `prev` as a
source and each `step` as a sink makes the per-iteration graph a DAG.
Iteration *n* resolves in topological order: its inputs are
within-iteration values (DAG) or `prev` ports holding *n-1*'s already
resolved `step` values, or `init` on iteration 0. The base case is
grounded by `init`, which the link cannot exist without. Induction does
the rest. *Necessity.* A cycle with no crossing lies within one iteration
— it asserts `x = f(x)` at the same step, non-productive by definition.
The check rejects exactly the ill-formed programs:

- `x = x + 1`, no Delay — zero crossings. Rejected.
- Fibonacci — every cycle crosses a Delay; deleting crossings leaves the
  graph acyclic. Accepted.
- A Delay whose `step` is wired straight from its own `prev` — one
  crossing. Accepted; vacuous but well-defined (a constant stream). Being
  useless is not being ill-formed.

`init` needs no separate treatment: it is evaluated outside the flow, so
wiring it from a per-iteration value is already ill-formed under the
scoping rules (the "no time travel" family).

The check is a **quotient constraint** — a property of the assembled
graph, not of any single link. It cannot be made by-construction without
reintroducing the declare-upfront framing the link avoids (cuts are
applied one at a time, each locally sensible; only the whole graph
decides productivity). So it joins the existing quotient constraints,
enforced by cycle detection, needing no type-system machinery.

**Precedent.** This is the standard causality condition of synchronous
dataflow languages, exactly. Lustre's `pre e` (unit delay) with
`init -> pre step` is precisely the Delay node — `init`, `prev`, `step` —
and Lustre accepts a program iff every dependency cycle crosses a `pre`,
checked structurally at compile time. Hardware description languages
enforce the same rule (every combinational loop must pass a register),
and Delay's compile target *is* a register. So a third independent line
converges on this primitive: the non-visual critique arrived at ports,
the visual rail at tap-down/writeback-up, and the synchronous tradition
at unit-delay-with-init — with fifty years of hardware practice
confirming the check is sufficient in the field.

## Candidate B: the latent-flow augmented uncollect

The link is a transformation (`transformation-levels-design.md` for the
transformation/result framing). This candidate asks its **result-level**
form: what wires and nodes does generalizing lay down? The answer needs
no lambda, no `prev` parameter, and no new value-producing node.

**Generalize is a cut on a wire.** Every value wire has an implicit place
to cut it. To generalize, cut a wire and interpose a new uncollect `U`:

- the **pre-cut producer** becomes an **input** to `U` — the *seed* (the
  initial value, evaluated once outside);
- the **post-cut consumer** reads an **output** of `U` — the per-iteration
  *state* (seed on iteration 0, fed-back step after).

The previous value is neither a new node nor a lambda parameter; it is
`U`'s state output, read by whatever used to consume the cut wire. "The
link splits the initial value" made concrete: one wire, cut, becomes a
seed-in and a state-out.

(The latent place-to-cut on every wire is *not* related to `flowRef`'s
`NodeFlow` being partial. That partiality is just the ordinary fact that
you can name a port a node lacks; the latent flow here is a separate idea
about generalization, not a totalisation of `NodeFlow`.)

**The source flow is a *separate* input to `U`.** The flow being iterated
(a list) is not identified with the generalize flow — it is *another
input* to the same uncollect. `U` zips an external iteration source with
the internal feedback variable (pseudocode, provisional):

```
U : uncollect
     inputs  seed = 0        -- value, from the cut wire's producer
             src  = ~L       -- flow, the list
     outputs state           -- per-iter: the accumulator so far
             element         -- per-iter: from src
element := U.element
sum     := U.state + U.element   -- feedback: sum advances U.state
```

This is recognizably `Open ListIter` with one extra (seed-in, state-out)
pair bolted on — a generalization of an existing node, not a new species.
Its output is a single **combined "list-with-state" flow** carrying two
per-iteration ports.

**Feedback.** The cut supplies seed-in and state-out but does not by
itself say what advances the state — that next iteration's `U.state` is
*this* iteration's `sum`. Two readings: **cursor-as-feedback** (generalize
uses the current output point as the step — works because of *when* you
generalize, build one step then generalize while its result is the
cursor; the leaning) and **explicit feedback wire** (name both the cut
wire and the step wire — needed only for out-of-order generalizes).
§"The equivalence, worked" resolves this: at the result level the step is
always an explicit input; cursor-as-feedback is an authoring gesture that
fills it.

**What it produces.** The uncollect plus the feedback collect yield a
**modified flow** with the iteration variable woven in — this is the
resolution of the output-less-terminal discomfort. The combined flow
comes out of the *uncollect*; the feedback collect outputs the **final
value** (the total, or the seed if nothing fired). Exposing the running
history is then a separate ordinary collect on the modified flow.

### Worked example: two accumulators, and Fibonacci

Starting program, cursor at `sum`:

```
n0:   0
nLst: list
nEl:  first(nLst)        -- partial access
nSum: n0 + nEl           -- cursor
```

**Generalize 1 (sum).** Cut `n0 → nSum.left`. Interpose `U` (seed `0`,
`src` the list flow, outputs `state`, `element`). `first(nLst)`
generalizes in the same act — "the first element" becomes "each element,"
`listFlow` born as the `src` input (the example-first case). Feedback:
`nSum` advances `U.state`.

**Generalize 2 (max).** Cut the `-inf` wire. Interpose `U2` — whose `src`
is **not** the raw list but `U`'s already-combined flow, so the two stay
in lockstep:

```
U2 : inputs  seed = -inf, src = U.flow
     outputs state2, (element, state pass through)
nMax := max(U2.state2, U2.element)
```

Generalizes **stack**: each consumes the current combined flow and adds
one more (seed-in, state-out) pair. Independent seeds, independent steps,
no tuple. "The source flow is another input" generalizes to "the *current*
flow is the next uncollect's `src`," and the no-bottleneck claim falls out
structurally. **Expose** the accumulators with an ordinary collect on the
final combined flow.

**Fibonacci falls out by dropping `src`.** A generalize with no external
source is the same uncollect with no `src` — just seed + feedback,
self-driven. Two such links cross-referencing each other's state outputs
give Fibonacci. Because state outputs are read by node reference like any
wire, self- and cross-reference are uniform — no privileged "own previous"
slot, no unused-parameter awkwardness (the defect that sank the lambda;
the port form dissolves it the same way).

**Where the principles land.** No lambda, so no binding form introduces an
interior scope. The interior/exterior difference for the cut node (seed
outside, carried value inside) still exists — that *is* iteration state —
but it is created by an explicit on-screen cut, not a magic name; the
principle is best read as forbidding *invisible* interior/exterior
differences, not all of them. Generalize is one operation whose result is
a recognizable extension of `Open ListIter`, reusing the existing
flow/uncollect vocabulary.

## Two operations for accumulation: reduce-close vs augment

Summing a list can be approached from more than one direction, and the
directions are not one construct. Forcing them together is exactly the
intent-decoding the abstraction-level principle warns against. There are
**two operations**, one with two authoring directions:

1. **Running sum, built loop-first.** You have a list uncollect. You add
   an iteration uncollect over the list flow with a `0` seed, add it to
   the element, collect it back to the augmented flow. You consciously
   construct the state variable; the running value is available in-loop.
2. **Just summing the list.** You do not think about a running sum; you
   think about *putting `+` between the elements*. Open a flow whose value
   wires are any two components to accumulate, add them, close with that
   value. The empty-list start is the operator's **implied identity**
   (`0` for `+`). Only works for operators with an identity.
3. **Running sum, built value-first.** Start with `0`, open a list flow,
   add `0` to the element, then use the latent feed-back flow to feed the
   sum back where `0` fed in.

**Approaches 1 and 3 are the same construct** — the latent-flow augment
(a list-with-state flow), from two authoring directions. **Approach 2 is
a genuinely different operation: a reduce-close** — a close-variant, a
sibling of the ordinary collect-close. It collapses a flow with an
associative operator, identity implied. It builds **no** state variable in
the authoring surface ("I don't think about a running sum" is literally
true), and it carries information augment does not:

- **The identity comes from the operator, not the user** (`+`→0, `*`→1).
  This is what makes empty→identity and `[a]`→`a` fall out
  (`identity ⊕ a = a` needs a genuine identity; an arbitrary seed will
  not do).
- **The two operands are symmetric** — the associativity assertion.
  Augment's step is asymmetric `state ⊕ element` and claims no such thing.
- **Its type shape is a monoid** (`op : T×T→T`), where augment's step is
  an arbitrary `S×E→S` (accumulator type may differ from element type —
  count, list-building).

So a reader can always tell total-sum from running-sum: different
constructs. The only new machinery reduce-close needs is **operator
identities**.

**Result-level decision: reduce-close is its own node**, carrying the
operator's monoid, and `Compile` *lowers* it to
`acc = identity; for (el of list) acc = op(acc, value)`. It is **not**
elaborated into the augment loop on construction. The decisive reason:
elaborating on construction would make reduce-close and "augment + expose
final" persist as the *same* result structure — collapsing the
total-vs-running distinction, making a plain `sum` read as a running-sum
machine whose intermediates nobody uses. The program of record is the
Expr, not the JS; keeping intent in the Expr is the point. Lowering costs
nothing (same `for-of` JS) and preserves the monoid for possible future
reassociation or parallel reduction. It fits the existing close family
(list / case / filter / option), already discriminated by shape.

**Boundary:** reduce-close is available exactly when the operator is a
known associative monoid; no identity / non-associative falls back to
augment (explicit seed). The degradation is structural: no monoid, no
node. This is refined (not reversed) by `collect-family-design.md`
(status: leanings, not adopted) into a three-tier ladder — monoid →
total; associative-without-identity (last, min) → reduce-close with an
option-shaped output (fires iff the flow fired); non-associative →
augment. The empty-collect question is the identity question, and
structure carries the "no answer" case.

### A second accumulator on a `sum`, via derived-port reference

Adding a second accumulator to a `sum` (also tracking `max`, in lockstep)
does **not** require lowering the `sum` or editing anything. `sum`
(reduce-close) has an always-available derived level-0 form — the augment
iteration — and that derived form exposes a combined list-with-state flow
as an output port. You build a *new* augment whose `src` **references that
derived port** and adds the `max` state. `sum` stays a pristine
reduce-close; nothing about it is touched. This is the stacking rule
reaching *across the derivation boundary*: the current combined flow may
itself be derived. The mechanism (a wire referencing a derived result's
output port) is developed in `transformation-levels-design.md`; the only
open detail is which derived ports are exposed (principal outputs like the
combined flow, not derivation internals).

That covers *adding alongside* a `sum`. *Changing the interior* (making
the step decay — no monoid) cannot be a reduce-close, and is handled
without editing: a level-1 `expand` in **materialize mode** records a step
whose result version contains the augment loop's nodes as ordinary parts,
and the decaying version is *built* from those parts while the sum version
persists in history. Rule of thumb: reference the lens to add; take the
parts to change (`transformation-levels-design.md`, "Two invocation
modes").

## The two candidates side by side

Status: **both live**; neither rejected. They are independent resolutions
of the same lambda critique, developed on parallel threads.

**Where they agree.** No lambda, no interior scope from a binding form —
both read the previous value by wiring. Self- and cross-reference are
uniform (Fibonacci is two links reading each other's state through
ordinary wires; no privileged "own previous"). The initial value lives
outside the flow, one per link, and the link cannot exist without one
(the empty case is closed by the same act). One variable per link, no
tuple. Both are result-level forms of the same link transformation. Both
realize the visual rail (tap-down / writeback-up / dotted initial map
onto port form's `prev`/`step`/`init` and equally onto latent form's
state-out / feedback / seed-in).

**Where they differ.**

- **Node species vs generalized opener.** The port form keeps the variable
  in a *new node* (Delay) standing beside the flow it names. The latent
  form weaves it *into the flow*: the cut interposes an uncollect that is
  "Open ListIter with one extra port pair," yielding a combined flow whose
  `state` port sits beside `element`.
- **How the source flow relates.** A Delay *references* its flow. The
  latent uncollect takes the flow as an *input* (`src`) and outputs the
  combined flow — giving it a structural stacking rule (each accumulator's
  uncollect takes the current combined flow as `src`, lockstep by
  construction) that the port form expresses only as many Delays
  referencing one flow.
- **Reading of inside-out.** The port form claims a full pass (`prev` is a
  port like the list element). The latent form concedes the cut node *is*
  different inside vs outside (seed vs carried value) — that is what
  iteration state means — and reads the principle as forbidding only
  *invisible* differences.
- **Companion machinery.** The latent thread additionally brings the
  transformation-levels framing, reduce-close, and derived-port
  references. These are largely independent of the choice (reduce-close's
  lowering could target either form) but were stated in the latent form's
  vocabulary.

### The cross-reference cycle, and Delay as the quotient

Converting between the forms surfaces two facts that matter for the
decision.

**Delay is the quotient.** Recognition (augment → Delay) is total and
**canonical** — restore the plain opener, mint a Delay per augmentation
layer, unwind stacked layers inside-out, forget the stack order. Lowering
(Delay → augment) is total but requires an **arbitrary choice**: multiple
Delays on one flow have no ordering, but stacking augmentations must
choose one, giving n! equally valid results with no semantic content
(every state read is a previous-iteration read; the state ports have no
within-iteration dependency). So Delay → augment → Delay is the identity,
but augment → Delay → augment reproduces the original only up to stack
order. The augmented form draws a distinction (stack order) that carries
no meaning; the Delay form does not. In the fifth principle's vocabulary,
Delay is the more abstract description and the augmented flow behaves like
a *derived view* of it — recognition is the canonical map, lowering a
section. This nominates Delay as the program of record *if both exist* (it
holds only while stack order stays semantically inert; a future feature
sequencing state updates within an iteration would break the quotient).

**The cross-reference cycle does not go away.** Converting Fibonacci
exposes a hole in the augmented form's acyclicity story. Two Delays,
`fib_b.step` reading `fib_a.prev` and vice versa, become two stacked
augmentations `U₁`, `U₂`. Where does `U₂`'s `src` come from? `U₁`'s
feedback reads `U₂.state`, which exists downstream of `U₂`'s uncollect,
whose `src` is supposed to be `U₁`'s modified flow — a cycle. Two ways
out: emit the combined flow from the *uncollect* (feedback collect reverts
to an output-less consumer, reinstating the discomfort), or **accept the
cycle** (the augmented form needs the productivity story after all). Either
the discomfort or the cycle returns. This independently supports the
recorded position that **cycles will have to be supported eventually**:
even the form designed to stay acyclic hits one as soon as accumulators
cross-reference, which is Fibonacci — the second example anyone writes.

## The equivalence, worked: one register, two drawings

Status: **an exploration with a worked correspondence and leanings, not
an adopted design.** This takes up the most promising deciding step —
whether the port form's Delay is exactly the result-level structure the
latent-flow transformation lays down. The answer: **yes — once the latent
form's undetermined pieces are pinned, and the pinning turns out to be
forced rather than chosen.** At the result level the two candidates are
one construct — the register pair — under two drawings, and the open
decision moves from semantics to surface.

### Pinning the feedback collect: it is the write half

The latent form's residue was (a) cursor vs explicit feedback wire, (b)
the concrete form of the feedback collect, (c) the stacking rule — plus
"which side of the feedback collect the combined flow comes out of." The
write half (`first-class-ports-design.md`) answers (b) by identification,
and the identification is **forced from three directions at once**:

- **The collect must have an output.** The rejection of the terminal
  stateful-collect stands, full stop. So "combined flow out of the
  uncollect, feedback collect output-less" is not available.
- **The combined flow cannot be that output.** If it is, cross-referencing
  accumulators cycle among the augmentations (above).
- **The register still owes exactly one value.** Without a dedicated exit,
  the only readout of a fold's *total* is "collect the state port and take
  the last element" — which materialises the whole history and gets the
  empty case wrong (zero firings must yield the seed; the collected list
  is empty). The missing value is the final value.

One arrangement satisfies all three — the write half's:

> **The pinned form.** The augmented uncollect takes `seed` (value, from
> the cut wire's producer) and `src` (flow), and outputs the `state` port
> *and the combined flow*. The feedback collect is the write half: it holds
> the pairing reference to its uncollect and the `step` wire, and outputs
> the **final value**.

Residue (a) then dissolves as a level confusion, not a fork: at the result
level the feedback collect always holds an explicit `step` input wire —
there is no "cursor variant" of the *structure*. Cursor-as-feedback is an
*authoring gesture* that fills that port with the current cursor at
generalize time. The out-of-order worry was about the gesture's
applicability, not the structure (many authoring paths, one reading).

### The correspondence

With the pinned form, the two candidates carry the same four anchors:

| register anchor | port form (the pair) | latent form (pinned) |
|---|---|---|
| outside in | read half `init` | uncollect `seed` |
| per-iteration out | read half `prev` | uncollect `state` |
| per-iteration in | write half `step` | feedback collect `step` |
| outside out | write half `final` | feedback collect `final` |
| iteration-boundary crossing | pairing, write → read | pairing, collect → uncollect |

The residue — everything not in the table — is exactly two items: the
latent uncollect *consumes* the source flow (`src` in, combined flow out)
where the read half *references* it; and the combined flow carries
pass-through ports (`element`, earlier states) the port form never draws.

### The residue is drawing, not semantics

- **The lockstep lemma.** The augmentation adds no firings and removes
  none: the combined flow fires exactly when `src` fires, one for one. So
  "list-with-state" is *not* a flow kind — the combined flow's kind is
  `src`'s kind, its collects behave as `src`'s collects, the kinds table
  is untouched — and every flow in an augmentation chain has identical
  firings, which makes the erasures safe.
- **The pass-through ports are availability.** The barrier-crossing round
  (`barrier-value-crossing-design.md`) re-read pass-through value ports as
  *availability by provenance*: a value readable in a context is readable
  there without being re-exported through each node its flow passes. The
  combined flow's `element` and earlier-state pass-throughs are exactly
  that — drawn availability, not structure. What the augmentation genuinely
  *mints* is `state` and, at the collect, `final`; each is obtainable by a
  complete construct of its own (the read's tap, the write's exit), so they
  sit on separate nodes — agreeing with the pair's grain.
- **Stack order and siblinghood are inert.** Stack order carries no
  meaning (established above). Whether a second accumulator's uncollect
  takes the *combined* flow as `src` (stacked) or the *raw* flow (sibling)
  is equally inert — lockstep is guaranteed by firings, joint readability
  of states is availability, not port plumbing. So the stacking rule
  (residue (c)) is confirmed as a composition and simultaneously demoted:
  it is a drawn convention, not load-bearing structure. This softens a
  listed cost of the latent form ("openers grow; the same logical
  iteration exists in several versions"): the chain of combined flows is
  inert drawn structure over one quotient, like the lowering's n! stack
  orders.

### The theorem

> **Result-level equivalence.** Over the pinned form, recognition
> (augment → pair) and lowering (pair → augment) are total; recognition is
> canonical; lowering is a section of it up to inert drawn structure (stack
> order, siblinghood, pass-through ports); and both preserve the program's
> meaning.

Meaning-preservation needs no new semantics: both forms share their
compile target — the register core (init-before, read-at-top,
write-at-bottom, final-after, per firing of the one shared flow). The
correspondence is a bijection on the four anchors preserving every wire
into and out of them, so both forms put the same values through the same
register at the same firings, by induction on firings; the empty case is
grounded identically (`final` = seed when nothing fired); and the total
comes out of the corresponding port on both sides.

**The productivity check transfers verbatim.** Read "the Delay's
`step → prev` crossing" as "the pairing edge, feedback collect → augmented
uncollect," and the condition — every cycle passes through a crossing —
is the latent form's cycle story word for word. A non-productive
configuration is a cycle avoiding every pairing.

**In the stored form, the check is a theorem.** Both forms' Expr
representation is immutable and bottom-up, so the object graph is a DAG
unconditionally (the write-half construction; the pinned collect is built
the same way). In the computation graph every ordinary data edge runs
*against* an object pointer (the consumer holds the producer), and the only
edges running *with* an object pointer are the pairings (the write holds
its read; the collect holds its uncollect). A cycle of reversed-DAG edges
alone is impossible, so every computation cycle passes through a pairing —
which is the productivity condition. Non-productive programs are therefore
unrepresentable in the stored form; the check's real subject is any
surface with mutable wiring (the diagram editor, where `x = x + 1` is
drawable) and any import path. (The write-count check does *not* dissolve:
exactly one write per read transfers to exactly one feedback collect per
augmentation and remains a counting check in both forms.)

**The one genuine asymmetry: the self-driven corner.** A link with no
external source is, in the latent form, an uncollect with no `src` — a
node that *mints* the self-driven flow. The port form has no counterpart:
its Delay "references its flow," which presupposes a flow-minting node the
record never names (the same hole the text side hit —
`translation-exercise.md`, finding 3). So here the latent form is not
equivalent to the port form; it is *ahead* by one node. The equivalence
holds once the port form borrows that node — a bare self-driven opener
whose only content is the flow mint — which it needs anyway for the corner
to be authorable. (`final` on a self-driven flow is never available; that
residue is shared and stays with the async/stream rounds.) That borrowed
node now has its own round, `source-openers-design.md` (status: leanings,
not adopted): a bare flow-minting opener exactly as pinned here — no value
ports, no new flow kind, the sourceless stream — with pacing and the
external pull source worked beside it.

**The standing caveat.** The quotient holds because nothing sequences
state updates within a firing — every crossing is a whole-iteration delay.
A future feature ordering updates within a firing would make stack order
meaningful and break the erasures. The survey evidence (sixty loops, every
register one-writeback; within-iteration chaining expressed as ordinary
value wires — `real-loop-survey.md`) is comfort, not proof.

### What this decides, and what it does not

The three recorded deciders each land: (1) the feedback mechanic has a
clean concrete form — it is the write half, so the port form does not win
by default; the forms merge, and *both* avoid the non-DAG stored
representation. (2) Compile experience stops discriminating — one backend
consuming the pair (the check free at this level) serves both surfaces.
(3) "They may be the same thing" — confirmed, dissolving into a
transformation-level/result-level distinction, not a design fork.

Consequences:

- **The adopt-one/adopt-both question is reframed.** At the result level
  there is nothing to adopt-one-of: the language has one iteration-state
  construct, the register pair. The "coexistence must be defined" cost
  collapses; "two compile paths, two well-formedness stories" was
  double-counted — there is one of each. One-obvious-way is satisfied at
  the *reading* level (many drawings, one reading — the
  many-paths/few-readings corollary).
- **Store the pair.** The quotient nominated the Delay side as the program
  of record; the erasure arguments strengthen it (the augmented drawing
  carries *only* inert extras). The augmented flow becomes a derived view
  over the stored pair — machinery already load-bearing: reduce-close's
  derived augment form and the running view
  (`variable-rate-consumption-design.md`) are that view in use.

**What this round deliberately does not decide: the surface.** Which
drawings exist, which is primary, what a beginner meets first — that is
the bar from the design review, untouched. The RTL and ST gestalt
critiques (below) survive intact, sharpened if anything: they can no
longer be dodged by "picking the other candidate," because both attach to
drawings of the *same* stored construct. The leaning left for that
conversation: conduct it as "which projections of the register do we draw,
and when does the editor switch projection" — with the equivalence
guaranteeing no choice of drawing forecloses any semantics.

**Dead ends (this round), do not revisit.**

1. **Combined flow out of the feedback collect** — the arrangement under
   which the equivalence *fails* (augmentations acquire cycles the pair
   form does not have).
2. **"List-with-state" as a flow kind** — dies on the lockstep lemma (no
   firings of its own, no collect behaviour of its own; a kind with no
   kind content that would fork every row of the kinds table). State is
   ports on a flow, never a kind of flow.
3. **Read-half-as-opener** (identifying the Delay read with an uncollect
   even when an external source exists) — makes each accumulator re-open
   the flow, so stacking/siblinghood becomes structural rather than inert,
   destroying the quotient the by-reference tie buys. (The self-driven
   corner is the one place read-as-opener is right, because there the flow
   must be minted by something.)
4. **Dissolving the write-count check through the correspondence** — it
   does not dissolve; the counting check transfers unchanged (one feedback
   collect per augmentation) and stays a quotient constraint in both forms.

## What a Delay is: a delayed computation, bound by its collect

Status: an ontological analysis with a lean, not adopted. Prompted by the
registers-over-products round (`product-flows-design.md`), which turned out
to teach more about Delay than about the product.

The equivalence pinned the *structure* — one register pair, two drawings —
but left a prior question implicit: what *is* a Delay, and to which flow
does its "next iteration" refer? It stays invisible while only one flow is
in reach, and becomes sharp the moment more than one is (a product's
several axes; a commute between where a carried value originates and where
the register is collected). It is a question about **meaning**, not wiring,
and — the point of recording it — the meaning *selects* the behaviour.

**A Delay is a feature of the flow.** "Carry this value to the next
iteration" presupposes that there *is* a next iteration, so a Delay is only
meaningful where a flow supplies one:

- over a list iteration or a self-driven / stream flow — a "next" exists;
- **not** over an async or IO flow (a value that arrives later, an effect
  sequenced in time) — there is no within-collection "next iteration" to
  carry to;
- **not** outside any flow — nothing to be "next" of.

(Which kinds actually supply a "next iteration" — list and stream clearly;
async/IO apparently not; incremental unexamined — wants the kinds table's
attention, since it bounds where Delay is even meaningful.) Though a Delay
is *drawn* as a computation step (`prev + element`), it is not one: `prev`
is not computed, it is *accessed from the flow*, the way a list-open's
element is. This is why the read is a port, not an expression (Candidate A):
the carried value is provided by the flow, not conjured.

### Why Delay does not thread the flow wire

If a Delay is a feature of the flow, the tempting move is to make it
*interact with the flow wire* — take the flow wire in and out, and say
"this Delay uses the next-iteration of *that* flow" by tapping the wire.
That is exactly how IO works: its operations (open a file, …) take the flow
wire as input and output, threaded along it.

But the reason IO threads the flow wire is specific: **IO operations must
be sequenced in time, and their order along the wire is that sequence.**
The wire-threading exists to *encode a sequence*. Delay has none to encode
— **Delays have no order with respect to each other** (the inert stack
order the equivalence already established as meaningless). Forcing them onto
a shared flow wire would make the user choose that meaningless order — which
Delay is "first" on the wire — and clutter the diagram with wires that say
nothing. So the very property that *justifies* wire-threading for IO (a real
inter-operation sequence) is precisely what Delay lacks, and its absence is
the argument against wire-threading Delay.

This sharpens the "stack order is inert" finding into a reusable
distinction: **flow-wire-threading is for constructs with a mutual temporal
sequence; a construct with no mutual sequence must not thread the wire.** IO
threads; Delay does not.

### The positive ontology: a delayed computation, bound at the collect

If a Delay does not get its flow by tapping a wire, where does its "next
iteration" come from? The lean: **a Delay builds a *delayed computation* —
a value paired with its own one-step-delayed self — not yet bound to any
concrete flow. Collecting the flow collects that delayed computation and
binds it: the collect is what supplies the "next iteration" the delayed
computation was waiting for.** On its own a Delay is a sequential
computation in the abstract; the collect grounds it in a specific
iteration, and the register's meaning completes there — at its collect, not
at the Delay glyph. This reframes the write half
(`first-class-ports-design.md`): the feedback collect is not merely where
the step is deposited, it is the *act of binding* the delayed computation to
a flow.

**A rejected alternative, recorded in place.** One could instead say a Delay
gets its flow by *implicitly referencing the uncollect its value wire
depends on* — walk back from `prev + element` to the list-open `element`
came from and take *that* flow's next iteration. Rejected, on ontological
grounds: the fiction of uncollect is that it hands you an **ordinary value
wire**, not a value wire carrying secret flow information. Letting a Delay
reach back through the wire to the ancestor uncollect treats the value wire
as if it silently remembered its flow — an ontology clash. "A Delay builds a
delayed computation, bound at collect" keeps the uncollect's fiction intact:
the wire stays ordinary, and the flow enters only at the collect, visibly.
(This is the inside-out instinct in ontological dress: information should
arrive by a visible act, not be smuggled inside a wire.) Note the honesty
bound — "delayed computation" is the best framing this round found, not a
settled one; whether it is the right *name* and the right binding semantics
is left open below.

### The discriminating case: a commute between origin and collection

The two views are not always distinguishable — they diverge exactly when
the **uncollect flow differs from the collect flow**, i.e. a commute sits
between where the carried value originates and where the register is
collected. Then:

- *uncollect-reference:* the Delay threads along the origin uncollect's
  iteration;
- *collect-binding:* the Delay threads along the collect's iteration.

Different programs — so this is the case that *forces* the ontology to
choose rather than merely illustrating it, and the lean resolves it toward
collect-binding: that is the reading under which "orders live at
terminations" holds for the register too, and under which the register
inherits its orientation from a *consumer* rather than from its value's
history. The registers-over-products round is
the concrete payoff: a register over an order-free product folds along **the
axis its binding collect gathers**, not an axis the Delay names — the
product merely made the choice-of-flow visible by offering more than one
axis to bind to (`product-flows-design.md`, "Registers over products").

### Open

- **Is "delayed computation" the right binding notion?** The best the round
  found, not a settled answer — the name and the binding semantics are both
  open.
- **Can a Delay bind to a *specified* flow?** Whether it is possible, or
  even sensible, to bind a Delay to a flow that is neither its collect's nor
  its value's origin is unexamined.
- **Per-kind "next iteration."** Which flow kinds supply one (the bullet
  list above) wants the kinds table, since it bounds where Delay means
  anything at all.

## The surface question: point, cell, or thread

At the result level there is one construct. The open decision is which
drawing is the surface. Two gestalt critiques frame it, symmetric in an
instructive way:

**The RTL shadow over the point (Delay).** A program built from Delay
nodes looks like Verilog — register-transfer logic, not known for being
natural to beginners. RTL has a virtue (follow a wire, see the data path)
but its timing structure is invisible: it must be *deduced by counting
registers*. A Delay node is a **point**; everything about "when" happens
at that point and must be reconstructed in the reader's head.

**The ST shadow over the cell (augmented flow).** An iteration variable
woven into a flow starts to look like an imperative program dressed in
flow clothing — a state port resembling a `ST`-monad state variable,
addressed, updated, threaded by convention. At that point it is imperative
programming, and the naturalness visual programming should provide is lost.
The rail notes flagged the same from the visual side: a generic register
with read/write ports "collapses into the imperative paradigm wearing
visual clothing." The augmented flow is a **cell**.

One erases time from the picture; the other erases the state's identity as
a followable thing.

### A fourth option: the visible state thread

Status: **conjectured fourth option, currently the most promising
direction.** What the user should be able to do is *see the state
threading through the loop* — the state's history as a **path** you can
follow, not a point and not a slot.

Promote the redesigned iteration rail from "visual depiction" to **the
construct itself**. A *state thread* is a first-class path with four
anchored connections whose geometry is its semantics:

- it **enters** from the initial value (dotted attach, outside the
  iteration);
- it **crosses** the single generic iteration column, where it has exactly
  one **tap** (per-iteration read) and, later along the thread, one
  **writeback** (per-iteration write) — the stretch between is that
  iteration's state epoch;
- it **exits** as the final value — a first-class endpoint, not a separate
  close bolted on.

Position along the thread *is* time. Following it left to right reads the
whole history: initial value, each read-compute-write epoch, final value.
Nothing about "when" must be deduced.

**The two candidates are its degradations.** Both fall out by *erasing part
of the path*:

- **Contract the thread to a point** — keep only its endpoints, discard the
  drawn path — and you have the Delay node (`init` in, `prev`/tap out,
  `step`/writeback in). This is why Delay feels like Verilog: the timing
  geometry is deleted, so timing must be reconstructed by counting.
- **Absorb the thread into the opener** — keep only where the path crosses
  the column boundary, discard its identity as a line — and you have the
  augmented flow (the seed-in/state-out pair plus feedback). This is why
  augment feels imperative: the thread's followable identity has dissolved
  into "the flow's state," a cell.

So the fourth option is not a third semantics — it is the claim that the
thread is the *primary surface* and Delay and augment are its two
projections, each used where the path picture degrades: cross-referencing
threads (Fibonacci) are parallel threads with taps between them (drawable
for two or three; dense mutual reference tangles, and contracting to Delay
points is the honest fallback — also where cycles are unavoidable in any
form); whole-flow operations (stacking generalizes, reduce-close's derived
view, referencing the combined flow as a thing) use the flow projection.

**Where it lands.** The thread's semantics is exactly the register core
(init-before, read, write, final-after); the fourth option is that core
with a *visible surface* on top — the register becomes a drawn history you
can see, answering the objection that the core is "the imperative picture
both surfaces exist to dress." The equivalence grounds it end to end:
"store the pair (the quotient), render the thread, derive the flow view"
is the thread's cheapest realization — one construct, three drawings: the
point (Delay glyph), the flow (augmented opener), the thread (the path with
all four anchors, which the pair, unlike the one-node contraction, fully
carries). The productivity check restates naturally: a cycle is well-formed
iff it passes through a thread's tap-to-writeback epoch — every feedback
loop visibly carried by some thread, the check's subject now something the
user can point at.

**Open points for the thread.**

- **Multiple writebacks.** The clean rule is *one writeback per crossing*,
  with conditional carry expressed as a conditional *value* wired into the
  single writeback. This survived contact with real loops: two survey runs,
  sixty loops across infrastructure and domain corpora including dense
  numerics (`real-loop-survey.md`). Conditional carry occurred three times
  and expressed exactly as prescribed each time; a multi-site-append buffer
  with conditional reset and a backtracking save/restore cursor both reduce
  to one conditional value per firing; an eight-register fixed-point kernel
  is eight parallel one-writeback threads. No sampled loop needed two
  independent writebacks. Recorded caveat: what strains in the reset case is
  effect *ordering* within the firing, which no writeback count addresses.
- **The crossing rule.** Threads are a new wire species. Do thread/value and
  thread/thread crossings fall under the existing no-crossing rule, or does
  the horizontal-rail geometry need its own convention?
- **Result-level status.** Is the thread its own result-level construct, or
  a rendering of a stored projection? The cheapest version: store the Delay
  quotient, render the thread, derive the flow view — making the fourth
  option an arrangement of existing pieces rather than a new primitive.

### Coexistence models (if both surfaces are first-class)

If the language exposes more than one drawing as first-class, "what does a
mixed program mean" needs a single answer — provided by a stored form, a
boundary, or a core, not by pairwise conversion. Three ways, none resting
on a proven two-way equivalence:

- **Stored-form asymmetry (derived views).** One form is the program of
  record; the other an always-available read-only derived view (the fifth
  principle's machinery, already needed for reduce-close). Only the
  derivation direction need exist; authoring gestures on the view are
  reinterpreted as edits to the stored form. The quotient nominates Delay
  as stored with the augmented flow as its view.
- **Domain split.** Each form owns scenarios outright (augmented flows for
  single-flow scans, Delay for cross-referencing recurrences and
  self-driven streams). No conversion, a designed boundary. Cost: the
  boundary must be learnable, and a program that grows across it (a scan
  acquiring a cross-referencing accumulator) needs manual rewriting at
  exactly the wrong moment. The seventh principle names this precisely: the
  domain boundary is a designed cliff on a +1 step — the failure mode the
  principle forbids. Of the three models this is the one that now needs a
  "very good argument"; the other two are cliff-free (a derived view expands
  by authoring on the view; a common core expands by adding registers).
- **Common core.** Both forms desugar to a shared result-level core — the
  loop register. Mixing semantics is defined once, at the core. Cheapest to
  specify, at the cost that the core — not either surface — is where the
  semantics lives, and the core is exactly the imperative register picture
  both surfaces exist to dress. (The fourth option is this model with a
  visible surface on top — the register dressed in geometry as a followable
  history.)

## What is still unresolved

- **The concrete form of the link — narrowed to the surface.** At the
  result level the fork is dissolved: the two candidates are one construct,
  the register pair, under two drawings, with the pinned feedback collect
  being the write half. What remains is the **surface** — which drawings
  exist and which is primary, "one construct, three drawings" (point, flow,
  thread). This is the beginner-bar conversation: a construct both easy for
  beginners and flexible for complex code, with a smooth +1 ramp (running
  sum → +max → cross-referencing pair → take-while termination). The RTL
  and ST gestalt critiques are the live tensions there.
- **How the link relates to its flow — surface only.** Resolved
  structurally in both drawings: the link is always tied to a specific flow
  (pre-existing or born with the generalise step), and a link with no
  external source is a self-driven stream (Fibonacci), not an error. What
  remains open is the concrete surface for the attachment (naming a flow vs
  choosing the `src`).
- **What a Delay *is*, and which flow binds it — ontology, with a lean.**
  Distinct from the surface question above: a Delay is a feature of the flow
  ("carry to the next iteration" is meaningless without one), and the lean
  is that it builds a *delayed computation* bound by its **collect**, not
  one that taps a flow wire (IO's shape, justified there by a temporal
  sequence Delay lacks) nor one that reads secret flow data off its value
  wire (the uncollect fiction forbids it). The choice matters exactly where
  more than one flow is in reach — a commute between origin and collection,
  a product's several axes — so it is meaning selecting behaviour, not
  decoration. Worked in "What a Delay is"; open residue there: whether
  "delayed computation" is the right notion, whether a Delay may bind a
  *specified* third flow, and which kinds even have a "next iteration."
- **Self-reference and cycles — resolved.** The iteration-boundary crossing
  is the only back-edge, so productivity is the structural condition "every
  cycle passes through a crossing" — a decidable whole-graph quotient
  constraint (like alt-matching and no-crossing), enforced by cycle
  detection, accepting exactly the productive programs, and the same
  causality check synchronous dataflow (Lustre `pre`/`->`) and hardware
  have used for decades. In the stored form of either drawing the condition
  holds by construction, so the check's subject is the mutable drawn
  surface and any import path.
- **Operator identities.** Reduce-close needs each associative operator to
  carry an identity for the empty-list value. How identities attach —
  registry, operator-node property, user-extensible for custom monoids — is
  worked (leanings, not adopted) in `collect-family-design.md`: identities
  attach as catalog rows carrying the identity value as witness, user
  monoids mint rows via the algebra facet (trusted like the JS edge), and
  the flat "no monoid, no node" boundary is refined to the three-tier ladder
  (monoid → total; associative-without-identity → option-shaped output;
  non-associative → augment).
- **Which derived ports a reduce-close or augment exposes.** Building a
  second accumulator references the derived combined flow. The exact set of
  principal output ports a derived result exposes for reference (versus
  private derivation internals) needs pinning; see
  `transformation-levels-design.md`.
- **Non-homogeneous iteration** — iterations behaving *conditionally*
  differently at each step, beyond first-vs-subsequent — is explicitly set
  aside as a separate question, not part of this primitive. Named so it is
  not conflated with what is designed here.
- **The environment the construct lives in.** The real-loop surveys
  (`real-loop-survey.md`, two runs, n=60) reweight what surrounds the
  decision. In infrastructure code the simple scan never occurred and early
  termination dominated; the domain sample found the scan alive and
  concentrated in numerics (five scans/folds in thirty draws), including an
  eight-register kernel with a cross-referencing register pair (Fibonacci's
  shape in production) and within-iteration chaining (one register's step
  reading another's *new* value — an ordinary value wire in both drawings,
  confirming stack order stays inert). So iteration state is real,
  domain-shaped, and structurally tame so far — and whichever surface is
  chosen should be evaluated with **early exit in the room**: real numeric
  loops stop *because of* their carried state (take-while on term size,
  retry-until-tolerance), so end-when (`tough-use-cases-design.md`) must
  compose with the register/thread designs, and the write half's
  final-value output and a search's readout look like the same port — a
  unification or a coincidence to check. The surveys also put three
  sightings behind the running/history-indexed view of a collect
  (read-whole, read-by-index, read-by-key), worked in
  `variable-rate-consumption-design.md` as the state port of the collect's
  derived augment form — this document's own "second accumulator on a sum"
  mechanism made everyday. If adopted it makes the derived augment form
  load-bearing for ordinary programs — pressure on the derived-view
  machinery, not a thumb on the scale between the drawings.
</content>
</invoke>
