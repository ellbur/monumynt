# Iteration with state — how a loop remembers

Status: **the surface decision is made** (design conversation,
2026-07-23): the **visible state thread is the primary framing** —
the register pair stored (the Delay quotient), the thread rendered,
the point (Delay) and the flow (augmented uncollect) its two
projections, used where the path picture honestly degrades. See
"The surface decision" under §"The surface question" for the
adoption's scope, its recorded constraint (the generic-iteration
picture) and caution (constant space may not be enough), and what
is deliberately deferred — the ergonomics round that makes the
thread friendly to the programmer is *not yet worked*, on purpose.
**The ergonomics round is now opened** (design conversation,
2026-08-04) and its first pieces settled — the working approach,
"for now": the thread as a third connector species (`@` sigil,
provisional), **no flow operand on the register** (the frame is
*derived* from the thread's anchors' contexts, with an `in ~flow`
annotation for the residue), anchors as ports, and the exit as a
scoop of the read port at a closer. See "The ergonomics round,
opened (2026-08-04)" below.
Nothing is implemented. The chapter below is kept as the record of
how the decision was reached; read pre-decision passages ("the
language has not yet chosen") in that light.

How does a loop carry a value from one iteration to the next — a
running sum, a maximum-so-far, a Fibonacci pair? In conventional code
you write `sum = 0` before the loop and `sum = sum + x` inside it. But
this language's defining move is that loops have no interior scope —
there is no "inside the loop" for `sum = sum + x` to live in. Working
out the shape of the primitive that replaces it, and recording the dead
ends along the way, is what this document does.

Code samples use the textual syntax from
`textual-representation-design.md` — `->` is a value wire, `~>` a flow
wire, `=> name` names a result, `--` starts a comment. Each new piece
of notation is explained the first time it appears.

## A running sum, up front

Before any of the design conversation, here is a sample of how
iteration with state might be written — a running sum, in the textual
register syntax (spelling provisional; of the candidates below, this
is the port-form surface, Candidate A):

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum
sum, a -> add -> step of sum => total
```

Read it line by line.

- `xs -> open list => a, ~L` opens the list, so that what flows onward
  is each element in turn. The open has two outputs, and the naming
  step names both: `a` is the per-iteration element, and `~L` is the
  *flow* — the "once per element" execution context itself. Flow names
  carry the `~` mark so you can never mistake one for a value.
- `~L ~> delay init 0 => sum` *reads the register*: it attaches a
  `delay` to the flow, with `0` as the value before any iteration has
  happened, and bare `sum` names the previous value — what the carried
  quantity was, one iteration ago (or `0` on the first).
- `sum, a -> add -> step of sum => total` *writes the register*: add
  the previous sum to the element and deposit the result as the next
  step; `total` is the final value.

One running sum, no tuple, no fold declared upfront. A carried value
like this — one initial value, one per-iteration read, one
per-iteration write — is what the design calls a **register**, and
`delay` is the node that holds one. (You will meet it properly under
"Candidate A: Delay as ports.")

Two things about this sample are easy to misread, so let's head them
off now. First, there is no separate collect statement on `~L`, and
none is missing: the write statement is itself the register's collect
— the write half doubles as the feedback collect (§"The equivalence,
worked") — so it terminates the iteration, and `total` is not a
per-iteration value but the final, outside-the-flow one: the completed
sum after the last element, or `0` if the list was empty. Second,
three statements is undeniably a lot of ceremony for adding up a list
— but nobody sums a list this way. A plain sum is a **reducing
collect** (§"Two operations for accumulation"), one ordinary stage in
a chain; the register spelling is for iteration that genuinely carries
state. Whether even that spelling asks too much of a beginner — and
whether the visual thread rendering or a better textual spelling
softens it — is exactly the open surface question (§"The surface
question: point, cell, or thread").

## Reader's guide

The design has converged to a single result-level construct — the
**register pair** (a read half and a write half, wired across the
iteration boundary) — reached by two independent routes that turn out
to describe the same thing under two drawings. ("Result-level" means
the level of the wires and nodes a program actually contains, as
opposed to the editing gestures that produced them; the framing is
from `transformation-levels-design.md`.) The two routes:

- **The Delay node in port form** (§"Candidate A"): one node with an
  `init` input, a `prev` output port, and a `step` input port.
- **The latent-flow augmented uncollect** (§"Candidate B"): generalize
  cuts a value wire and interposes an uncollect that carries the
  accumulator as an extra port pair.

Both are **live**. Neither is rejected. §"The equivalence, worked"
proves them result-level equivalent — one register pair, two drawings
— so at the level of meaning there is nothing left to choose between
them.

What is **still open** is the *surface*: which drawing is primary, what
a beginner meets first, and whether a third drawing — the **visible
state thread** (§"A fourth option") — should be the surface with the
other two as its projections. The bar for that decision: a construct
both *easy for beginners* and *flexible enough for complex code*, with
a smooth ramp between — the beginner's running sum must expand into
the hard cases (a second accumulator, cross-referencing registers,
early-termination) by *adding structure*, never by switching to a
different construct (the "building blocks must build" principle,
`language-design-philosophy.md`).

**A standing caution.** Delay has drawn much of the recent work — the
port/latent equivalence, the productivity check, the fork over what a
Delay *is* (now reframed by the value-in-context model in
`delay-ontology-design.md`, which factors the register into
raw-previous + seed + feedback and relocates the fork to a product's
linearization) — and that concentration is not itself evidence that
Delay is the answer. The live worry is the beginner bar: a surface
built from Delay nodes asks the programmer to write register-transfer
logic (the RTL critique in "The surface question" below — RTL is the
hardware-description style of Verilog, not known for being natural to
beginners), and requiring that of a beginner is exactly the cost this
area exists to avoid. So the register pair is the worked
*result-level* construct, not a committed surface, and the search
stays open to other ways of approaching iteration with state — the
visible state thread (§"A fourth option") is one candidate already in
hand, not presumed the last, and a genuinely different approach may
earn a place *alongside* Delay rather than having to replace it.

The two-phase back-edge construction both candidates rest on is worked
out below, in §"The Delay back-edge: the write half is a node".

## The problem: several accumulators, and no bottleneck

Why is this hard enough to be the biggest open area? Look at what the
two conventional traditions each get wrong.

Imperative loops carry state easily and illegibly. You declare as many
variables as you like, update them independently, read them after the
loop — but the code says nothing about intent. There is no `sum()`,
only an accumulator you must trace by hand to recognize.

Functional languages recover the named-operation clarity (`sum`,
`max`) but impose a **bottleneck**: a multi-output fold packs all
carried state into one tuple, threads it through, and unpacks it every
step. Two accumulators is a 2-tuple; three is a 3-tuple. The packing
obscures what happens, and the outputs lose their identity as separate
things — they become slots.

    fold(list, (0, -inf), (acc, x) => (acc[0] + x, max(acc[1], x)))

The goal is the functional clarity without the bottleneck. Each
carried variable should be independently nameable and independently
readable, with no tuple at any level. **Adding a second accumulator
must not touch the first.** This is the same multi-output goal the
language pursues everywhere (several collects on one uncollect, each
independently readable, no tuple), applied to carried-across-iteration
state.

Three design commitments shape every candidate below — and the running
sum you just read is a sample of writing state while satisfying them:

- **Example first, then generalise.** You write the concrete step
  (`0 + element`) and then apply a transformation that makes it
  iterate. You do not declare a general fold and instantiate it. A
  primitive that forces you to declare the iteration structure upfront
  is suspect; one that starts concrete and identifies a relationship
  is preferred. The tuple bottleneck is itself an instance of the
  anti-pattern — it forces the fold's type (the generalisation) before
  you know all the components.
- **Building blocks at the programmer's level.** `sum` says what it
  means; a tuple-threaded fold is equivalent but communicates nothing.
  The criterion for a primitive is not "is it minimal?" but "does it
  meet the programmer at the level of their own abstractions?" `sum`
  and `max` as two named outputs of one loop is the obvious way to
  write two accumulators; a 2-tuple through a fold is not.
- **Foundations before features.** A wrong foundation compounds: every
  feature built on it inherits the flaw. Rejecting a candidate
  primitive on paper — even after substantial design work — is cheaper
  than implementing the wrong thing and dismantling it later. This is
  why the work below spends more time in critique than in
  construction.

## Why not `stateful(initial, update)`?

Now, you might wonder why the language doesn't just offer a
function-like call — the very first candidate looked like this:

    runningSum = stateful(0, prev + x)

It turns out this would be a wrong foundation — not because it cannot
be made to work, but because every feature built on it would inherit
its flaws. Four problems, each of which the eventual design has to
respect:

- **It looks like a function call but isn't.** The two arguments are
  not peers evaluated in one scope. `initial` (`0`) is evaluated once,
  *outside* the iteration. `update` (`prev + x`) is evaluated once per
  iteration, in a scope where `prev` exists. Different things at
  different times in different scopes, dressed as sibling arguments.
- **`prev` is a scope-contaminating magic name.** Inside `update`,
  `prev` is suddenly in scope. No other expression in the language has
  this property. It is the inside-out anti-pattern the language exists
  to avoid: a construct whose interior scope differs from its
  exterior.
- **It is secretly a case split.** The two arguments are really two
  cases — first iteration (no previous value) and subsequent
  iterations (previous value exists). The language already has case
  splits; `stateful` smuggled one in under a function-call surface.
- **The initial value is misplaced.** `initial` is written inside the
  call but is not inside the flow. It cannot depend on per-iteration
  values — there are none yet. Positioning it as an argument alongside
  the recurrence implies a shared scope that does not exist.

(This is a settled rejection — please don't re-propose it without new
evidence.)

## Why not a `prev(x)` operator?

You might wonder next about a gentler shape: a unary operator
returning `option<X>` — `None` on the first iteration,
`Some(previousValue)` after. This was the second candidate.

It gets the meaning right (first iteration is `None`, the split is
visible, self-reference is just a name binding). But it was set aside,
for four reasons:

- **Its argument is a label, not a value.** Every other operator takes
  values and produces values. `prev(x)` does not read `x`'s value; it
  uses `x` as an identifier to locate "the node labeled `x`, one
  iteration ago." The argument is node identity. Nothing else in the
  value language works this way.
- **It is a flow-level feature written as a value expression.**
  `prev(x)` means something only inside an iteration; outside any flow
  it is meaningless. Yet it is spelled as an ordinary value-layer
  expression with no sign it depends on the surrounding flow. When a
  value is provided by the flow structure (like a list element from
  the uncollect), the language should show that.
- **Many `prev` uses are one case split written many times.**
  `prev(sum)` and `prev(product)` both yield `None` on iteration 0.
  There is only one first-vs-subsequent distinction — it is a property
  of the flow, not of each value. Two `prev` calls imply two
  independent discriminations when there is one.
- **The `None` case belongs outside the flow.** The `None` branch is
  the initial case, evaluated before any iteration; it can only depend
  on outside-flow values. Writing it as an `alt` of an in-flow
  case-split positions it as per-iteration computation. It is not.

**The identity-vs-value account (2026-07-23)** — a sharpening of
the first reason above, from the conversation that adopted the
thread; recorded because it is the deepest statement of why this
family of shapes must not return, and of why the thread is the
right fix. There is a glimmer of usefulness in `prev`'s intuition:
it is not crazy to say there is a *previous world*, and that
everything in the current iteration frame has a counterpart there.
The failure is in how `prev` reaches for the counterpart: you
cannot identify the previous-world version of a thing by pointing
at the current thing — the current value wire binds the *value*
(the flesh-and-blood thing), and the value does not exist in the
previous frame; only the *identity* does. `prev(x)` confuses the
identity of a thing (which exists across frames) with the thing
itself (which doesn't). One could decree that binding a value wire
sometimes means binding its identity — but that distinction would
be visually inapparent, which is exactly the confusion. (The same
principle decided race's inputs: a control-flow operation must
consume what *stands for* the computation, never a bare value from
inside it.) The **thread** is the repair: a visually distinct
species that points at the previous and current wires and asserts
"these are the same identity across iterations" — identity-use
drawn as identity-use. One directional note recorded with it: the
assertion works equally well feeding the *next* frame as reading
from the *previous* one — either alone suffices, and doing both
overspecifies.

Two later additions to this account (same conversation):

- **A fifth reason `prev` fails, purely visual.** Textually, "the
  previous x" reads tolerably because `x` is a *word*. Visually
  there is no word — there is a wire, and the wire runs to the
  *current* node; nothing about it says "previous." Decorating the
  wire with the label "prev" is not visual language, it is a word
  glued onto a picture that says otherwise — frankly confusing.
  The construct must *look like* what it means, and an
  identity-across-frames reference looks like a distinct species
  of line between two places, not a labeled value wire.
- **The generalization (recorded half-finished, deliberately).**
  Many of the record's iteration patterns are versions of one
  idea — *this value, but in that context*: the previous iteration
  (`prev`/the thread), the child realm (the divide flow's link),
  the child realms again (the zipper's computed-value ports, now
  retired as stored surface). All bizarro world. The standing
  challenge is a visual form for cross-context reference that
  doesn't get messy; the **thread** — a little dotted line saying
  "these two nodes share part of their identity despite being in
  different places" — is the best form found so far, adopted as
  the framing and honestly held as *best-so-far, not fully
  satisfying*. (This observation is a supporting datum for the
  value-in-context model, `delay-ontology-design.md`, which owes
  its frequency check before its own conversation.)

(This is a recorded set-aside — but with a caveat: the
value-in-context model of `delay-ontology-design.md` recasts `prev` as
a readout on a wire's context rather than a name lookup, which
dissolves these four objections *without* re-proposing the `prev(name)`
surface. See §"What a Delay is, and which flow binds it" below, and
check the ontology doc before citing these rejections against a
cursor-style `prev`.)

## Where the critiques converge

The two rejections point at a common shape — four prescriptions the
eventual construct has to satisfy:

- **The initial value belongs outside the uncollect.** It should not
  be an input to the flow's uncollect — that would force you to
  enumerate every carried variable when you write the uncollect, the
  tuple bottleneck moved to the uncollect. Instead the initial value
  attaches independently, one per iteration construct.
- **The first-vs-subsequent split is flow-level, not value-level.** It
  is one property of the surrounding flow, expressed once, within
  which all initial values live in the first-iteration scope and all
  carried values in the subsequent scope — not a per-variable
  `case(prev(x))`.
- **The carried value is provided as a port, not conjured by an
  operator.** Like the list element off a list-uncollect node, the
  carried value should be an output the body reads by wiring — visible
  because it was wired in, not because a special-scoped function was
  invoked.
- **Closing initial+step does not close the outer flow.** Combining
  the initial case and the step case ends the first/subsequent
  distinction for *that variable* and produces its current-iteration
  value; the outer list or stream flow stays open and iteration
  continues. This is analogous to partial closure in case splits
  (closing two alts without closing the containing flow).

## The grid the construct must express

Before building anything, it helps to lay out exactly what "iteration
state" involves. As a grid, it has two axes:

- **Variable identities** (rows): `sum`, `max`, `count`, … —
  independently nameable, no tuple.
- **Roles** (columns): assign-initial, assign-iterated,
  access-previous, access-current.

The grid is not fully combinatorial. Three columns are coupled: a
variable participates in *all* of {assign-initial, assign-iterated,
access-previous} or in none of them.

- assign-initial and assign-iterated must coexist — no state without
  both a start and a step.
- access-previous requires both — iteration 0 reads assign-initial,
  later iterations read the previous assign-iterated.
- assign-initial + assign-iterated without access-previous is vacuous:
  updating a value nobody ever reads as a previous value. Not stateful
  at all.

The fourth column, access-current, is independent — a per-iteration
value read within the current iteration (the list element) needs none
of the coupling. *Being stateful is exactly being in the three-way
coupling.*

Does the construct have to *enforce* the coupling by construction? No.
The language already relies on rules of this kind — call them
**quotient constraints**: properties checked on the assembled whole
rather than made impossible piece by piece. Matching alts on a
CaseSplit, a collect compatible with its uncollect, type agreement,
the no-crossing rule — all are quotient constraints. So it is
acceptable that a variable's three slots must refer to one identity,
enforced as a matching constraint rather than built as one inseparable
unit.

## Why not a feedback node with no output?

Now, you might wonder about the feedback operation itself — the thing
that deposits a step value for the next iteration. An early framing
made it a **terminal node with no output**: regular collect produces a
downstream value, but this "stateful-collect" merely consumed the step
value and fed it back, producing nothing.

It turns out this shape is rejected, and the rejection stands: **a
feedback node must have an output.** The "produces nothing, hangs in
the air" quality was a real source of discomfort in a language
otherwise modelled on functional behaviour, and it names a genuine
conflict — but the answer is not to accept an output-less node. Both
live candidates dissolve it, each in its own way:

- The **port form** has no separate feedback node at all — the step is
  an *input port* of the register, so nothing output-less exists.
- The **latent form**'s feedback collect *does* produce something: the
  final value (see §"The equivalence, worked"). The write half (worked
  out below, §"The Delay back-edge: the write half is a node")
  recovers a distinct writing *node* that is not terminal precisely
  because it outputs the final value — the exit anchor the one-node
  contraction had no port for.

(This is a settled rejection of the *output-less* shape — it is kept
on record because the conflict it names is real, and both reframings
above are answers to it. Please don't re-propose an output-less
feedback node.)

## The link: generalize a concrete step

With the dead ends recorded, here is the idea the design actually
runs on. The rejected primitives both asked you to design a general
iterative computation upfront. The **link** does not. Start with a
concrete single-step calculation:

- you have `0`;
- you have `element` (the first element of a list);
- you compute `0 + element`.

Then observe: the result of `0 + element` plays the same role `0`
played. **Link** the result back to where `0` was — "this output and
this input are the same thing across iterations." Before the link
there is no iteration, just a one-step calculation. After it there is.
*The link is the primitive.* Adding a second accumulator is adding a
second link, independently — no tuple, nothing else disturbed.

**The link splits the initial value.** Before the link, `0` is one
thing. After, there are two structurally distinct things: `0`
*outside* the iteration (the initial value, unchanged) and a *previous
result* inside the body, in the position `0` held. One thing became
two. This is example-first made concrete: write the special case, then
generalise by identifying the feedback.

### The link closes the empty-list case

What if the list is empty? Accessing the first element of a list is a
partial operation — the list might be empty, and `0 + element` only
makes sense if an element exists. The link resolves this. If the list
is empty, the iteration runs zero times and the result is just `0`.
The initial value serves double duty:

- the starting "previous" value for a non-empty list, and
- the complete answer for an empty list (zero iterations).

You cannot link without providing an initial value (the empty case
would be unhandled), and providing one without linking is just a
constant. In flow terms the link is *simultaneously* a collect for the
empty case and an uncollect for the iteration — the same act.

A consequence: **access-previous is never option-typed.** The
`prev(x)` candidate returned `option<X>` to handle "first iteration
has no previous." Under the link that case never arises: the initial
value *is* the first previous value, so on every iteration — including
the first — a well-defined previous value is available. The
first/subsequent distinction is handled by the mechanism and is
invisible inside the body.

### The link is a graph transformation, not a program element

You might worry: "you can only stateful-collect once per variable" —
doesn't that limit the link? The worry confuses two levels. At the
*variable* level, one variable has one write slot, and two step values
for it conflict — still true. At the *program* level, the link is a
**transformation** applied to a program to produce a new program: pick
a position, get back a program where that position is an iteration
variable. It can be applied any number of times, each at a *different*
position, each creating one independent variable. No conflict, because
each application makes a new variable at a new position.

Concretely, starting from `e = (1 + 2) + first_element`, you could
link:

- where `1` was — one iterative program;
- where `(1 + 2)` was — a different one, the variable initialized to
  `3`;
- both at once — two independent iteration variables.

The link **cuts** the graph at the identified position. Whatever
computed the value there is replaced by the iteration variable
(initial value on step 0, fed-back value after). Everything downstream
just sees a value; it does not know a cut occurred. When two cut
positions are in a dependency relationship — `(1 + 2)` depends on `1`
— the downstream cut *severs* that dependency below it: after cutting
at `(1 + 2)`, the downstream computation no longer sees the updated
`1` flowing through `+ 2`; it sees the independent variable seeded at
`3`. Each cut is local. This is the argument for the transformation
framing over a declaration framing — a "declare an iteration variable"
approach would have to decide upfront what `(1 + 2)` means when `1` is
also a variable; the transformation sidesteps it, cuts applied one at
a time, no global coordination.

## Worked example: two independent accumulators

Now test the core claim — a second accumulator is a second link, no
tuple. Start non-iterative:

    sum_init = 0
    max_init = -infinity
    element  = list[0]           -- partial: list might be empty
    sum_step = sum_init + element
    max_step = max(max_init, element)

Two constants, one partial access, two computations. Apply two links:

- **Link 1 (sum):** feed `sum_step` back to `sum_init`'s position.
  `sum_init` becomes a variable seeded at `0`; the formula is
  unchanged; the empty case is `0`.
- **Link 2 (max):** feed `max_step` back to `max_init`'s position.
  `max_init` becomes a variable seeded at `-infinity`; formula
  unchanged; empty case is `-infinity`.

The grid after both links:

|  | assign-initial | assign-iterated | access-previous | access-current |
|---|---|---|---|---|
| `sum_init` | `0` (outside) | `sum_step` | `sum_init` (per-iter) | — |
| `max_init` | `-inf` (outside) | `max_step` | `max_init` (per-iter) | — |
| `element` | — | — | — | provided by the list uncollect |

`element` is access-current only. Neither link touches it or the
other. Their only interaction is sharing `element` through the
containing list flow. Different seeds, different steps, neither knows
the other exists; adding a third accumulator (`count`, seeded `0`,
stepped `+1`) is a third independent link. The functional bottleneck
has vanished.

In the register syntax, two independent registers on one loop:

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum
sum, a -> add -> step of sum => total
~L ~> delay init neginf => hi       -- neginf = js "-Infinity"
hi, a -> max -> step of hi => curMax
```

Two `delay`s over the same `~L`, two independent step lines, no tuple.

> TODO (simplify): two pieces of ceremony in this sample are
> bookkeeping the drawing already determines, and should default
> away (precedent: the effects round's never-drawn commute —
> mandatory + unique ⇒ inferred). (1) `init 0` and `init neginf`
> restate the step operators' catalog identities; default a
> register's `init` to the identity witness that already grounds the
> empty reduce-close (`collect-family-design.md`), authored only
> when the step is non-monoidal. (2) `~L ~>` names the flow purely
> to attach; when exactly one enclosing flow is in reach, bind to it
> by default (faint), spelling the flow only in the multi-flow case
> `delay-ontology-design.md` isolates as the genuine choice.

### How the link relates to its flow

Which loop does a link belong to? Two cases, resolving the same way —
the link is *always* tied to a specific flow:

- **Inside an existing flow.** If a list flow is already open, a link
  created within it references that flow. Iteration state is a feature
  of a specific flow, not free-floating.
- **Example-first generalize.** Starting from the concrete program
  above, `element = list[0]` is a partial access — no list flow exists
  yet. Applying the link *is* the generalise step on `list[0]`: "the
  first element" becomes "each element," and the list uncollect is
  born in the same act. The flow and the link are created together.

**The self-driven edge case.** What about a link whose step depends
only on outside-flow values plus its own accumulator — no external
iteration source at all? Applying it creates a flow that is *purely*
the feedback loop — a self-driven stream. Fibonacci is this: two
links, no external list, just the recurrence. Not an error; it falls
out of the same generalise step applied to a computation with no
partial accesses. In the register syntax, cross-referencing registers
with a driving list:

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

Feeding a result back to where it came from sounds circular — is it?
No: `sum_init` on iteration *n* is `sum_step` from iteration *n-1*,
already resolved. The backward edge is sequenced across iterations,
not within one. As a stream:

    sum_init_stream = cons(0, sum_step_stream)
    sum_step_stream = map2(sum_init_stream, element_stream, (+))

This is productive corecursion — that is, a self-referencing stream
definition where each cell of `sum_init_stream` is available one step
before it is needed. Under delayed-cell semantics it resolves without
deadlock; the standard stream-recursion pattern, no new machinery.

## The lambda dead end

The link needs a concrete form in the language. Now, you might wonder
why the language doesn't write it as a `Delay` node with a lambda —
that was in fact the first attempt, and it is dead, but its critique
is what produced both live candidates, so it is worth stating in
full.

    Delay(init, prev => step)

- `init` — the initial value, evaluated outside the iteration; the
  first-step output.
- `prev => step` — a lambda where `prev` is the node's own previous
  output; the body computes the next value.
- output — the previous step's result (or `init` on step 0).

The three-way coupling maps cleanly (`init` = assign-initial, output =
access-previous, body = assign-iterated), all in one node with a
normal output, no matched open/close pair, no output-less terminal
node. Applied to the running sum:

    runningSum = Delay(0, prev => prev + element)

Two accumulators stay independent; cross-references reference the
other node's output directly:

    fib_a = Delay(1, _    => fib_b)
    fib_b = Delay(1, prev => fib_a + prev)

**Why the lambda is rejected.** It turns out the lambda `prev => step`
causes exactly the problem this language forbids: it introduces `prev`
into an *interior scope* — inside the lambda `prev` exists, outside it
does not. That is the inside-out difference again. It is milder than
`stateful`'s magic name (the binding is a visible lambda parameter,
not a keyword conjured into scope), but the concern applies in weaker
form. And the lambda has a tell: for cross-references it goes *unused*
— `fib_a = Delay(1, _ => fib_b)` writes a lambda whose parameter is
ignored, because that step reads another Delay's previous value, not
its own. The lambda is mandatory even when nothing reads `prev`. That
the surface forces a lambda where none is needed is the signal that
the lambda is not the right mechanism.

(This is a settled rejection of the *lambda spelling* — the Delay idea
itself survives, lambda-free, as Candidate A below.)

Two threads answered this critique independently, without seeing each
other, and arrived at two constructs. Both are kept.

## Candidate A: Delay as ports

The first answer: `prev` does not have to be a bound parameter. It can
be an **output port** of the Delay node — read by wiring, exactly as
the current element is read off a list-uncollect node. A Delay node
has three connections, none a lambda:

- **`init`** — an input from outside the flow; the first-step output.
- **a `prev` output port** — the previous step's result (or `init` on
  step 0), read downstream by wiring like any value.
- **a `step` input port** — the value to carry into the next step;
  whatever computes the new value wires *into* it.

This is exactly the construct the running sum at the top of this
chapter was written in: `delay init 0` mints the node, bare `sum` is
its `prev` port, and `step of sum` wires into its `step` port. The
grid maps directly onto the three connections with no scope difference
anywhere (`init` = assign-initial, `prev` port = access-previous,
`step` port = assign-iterated).

**It passes the inside-out test cleanly.** In the lambda form the
interior of `prev => step` is a different scope from its exterior. In
the port form there is no interior: every expression in the body lives
in one scope, and `prev` is a wire off the Delay node, available
wherever any wire is. This is *exactly* how the list element is
provided. Delay's `prev` port is that same mechanism applied to "the
previous step's value" — no more inside-out than list iteration, which
is to say, not at all. It fulfils the earlier prescription verbatim:
the carried value is *provided* as a port and read because it was
wired in.

**It is the iteration rail.** The visual notes
(`iteration-rails-design-notes.md`) reached this node from the other
direction: a horizontal rail crossing the iteration column, with a
tap-down read on the left, a writeback-up on the right, and a dotted
initial value. Those are Delay's three connections (tap-down = `prev`,
writeback-up = `step`, dotted = `init`). The non-visual reasoning
worked toward a lambda; the visual reasoning worked toward read/write
ports; they are the same primitive, and the convergence is evidence it
is the right shape.

**Self-reference and cross-reference become one thing.** The lambda's
unused-parameter awkwardness disappears — there is no parameter to
leave unused. A `step` input is wired from whatever computes the next
value; a `prev` output is read by whoever needs the previous value.
Self-reference (`runningSum`'s step reads its own `prev`) and
cross-reference (`fib_a`'s step reads `fib_b`'s `prev`) are both just
wires:

    runningSum:  init 0   step = (prev of runningSum) + element
    fib_a:       init 1   step = (prev of fib_b)
    fib_b:       init 1   step = (prev of fib_a) + (prev of fib_b)

No lambdas, no unused parameters, no self-vs-cross special case.

**No construction-time cycle.** The lambda form needed the host's
`let rec` because `step` referred to `prev`, which referred to the
node being constructed. The port form needs no value-level recursion.
It uses the node-identity-plus-wiring pattern the codebase already
uses for Open/Close: mint the node (its `prev` port exists immediately
and can be referenced downstream), then wire its `step` and `init` as
a separate, later act — exactly like wiring a Close back to its Open.
The Expr-level mechanism is worked out below (§"The Delay back-edge:
the write half is a node"): the later act mints its own node — a write
half holding the read reference and the step — so nothing mutates the
Delay after construction, the object graph stays a DAG
unconditionally, and the `step → prev` crossing is recovered from the
pairing. The write half's output is the final value: the thread's exit
anchor the one-node contraction had no port for.

Two later findings back the write half from outside. Zig ships the
same decomposition as syntax: a `while` header's continue expression
is the register's step pulled out of the body so `continue` cannot
skip it — un-skippability by construction, which is exactly what the
write half gives (`zig-comparison.md`, finding 1; C's
skip-the-increment bug is the negative witness). And the translation
exercise found the write half's two-statement shape is not
register-specific: `step of`, `boundary of`, and `value of` are all
**late-wired operands** — the textual shape of every construct that
sits on a cycle (`translation-exercise.md`, finding 4), so the
two-phase construction is a general mechanism the register happens to
need first.

**What it costs: the computation graph is not a DAG.** The `step`
input is a back-edge — it wires a downstream value back up into the
node, so the computation graph has a cycle. The current compiler
assumes a DAG (each binding at `deeper(args)`, laziness for ordering),
so a back-edge is the one thing it cannot yet handle. But the
back-edge is not an accident — it *is* the link ("cut the graph, feed
the downstream value back"). The cycle is the primitive, not a side
effect. And the compile target is known: a single mutable `let`
register inside the loop. `init` sets it before the loop, `prev` reads
it at the top, `step` assigns it at the bottom. The graph cycle
becomes a write-after-read on one register in the emitted JS — no
cycle in the generated code, because the cycle was only ever across
iterations.

### Ruling out non-productive cycles structurally

If cycles are allowed, what stops you writing a cycle with no base
case — `x = x + 1`, a value defined in terms of itself at the same
instant? Can the language rule that out structurally? Yes, with one
decidable graph check. In the port form the computation graph has
exactly two kinds of edge:

- **Ordinary value edges** — within one iteration, both endpoints of
  the same step.
- **The Delay crossing** — the internal edge from a Delay's `step`
  input to its `prev` output. This is the *only* edge that crosses an
  iteration boundary: the value into `step` at step *n* emerges from
  `prev` at step *n+1*.

Every back-edge is a Delay crossing, because Delay is the only
construct that makes one. So:

> **A cycle is productive iff it passes through at least one Delay
> crossing.** Equivalently: delete every Delay's `step → prev` edge;
> the remaining graph must be acyclic.

*Sufficiency.* If every cycle crosses a Delay, treating each `prev` as
a source and each `step` as a sink makes the per-iteration graph a
DAG. Iteration *n* resolves in topological order: its inputs are
within-iteration values (DAG) or `prev` ports holding *n-1*'s already
resolved `step` values, or `init` on iteration 0. The base case is
grounded by `init`, which the link cannot exist without. Induction
does the rest. *Necessity.* A cycle with no crossing lies within one
iteration — it asserts `x = f(x)` at the same step, non-productive by
definition. The check rejects exactly the ill-formed programs:

- `x = x + 1`, no Delay — zero crossings. Rejected.
- Fibonacci — every cycle crosses a Delay; deleting crossings leaves
  the graph acyclic. Accepted.
- A Delay whose `step` is wired straight from its own `prev` — one
  crossing. Accepted; vacuous but well-defined (a constant stream).
  Being useless is not being ill-formed.

`init` needs no separate treatment: it is evaluated outside the flow,
so wiring it from a per-iteration value is already ill-formed under
the scoping rules (the "no time travel" family).

The check is a **quotient constraint** — a property of the assembled
graph, not of any single link. It cannot be made by-construction
without reintroducing the declare-upfront framing the link avoids
(cuts are applied one at a time, each locally sensible; only the whole
graph decides productivity). So it joins the existing quotient
constraints, enforced by cycle detection, needing no type-system
machinery.

**Precedent.** This is the standard causality condition of synchronous
dataflow languages, exactly. Lustre's `pre e` (unit delay) with
`init -> pre step` is precisely the Delay node — `init`, `prev`,
`step` — and Lustre accepts a program iff every dependency cycle
crosses a `pre`, checked structurally at compile time. Hardware
description languages enforce the same rule (every combinational loop
must pass a register), and Delay's compile target *is* a register. So
a third independent line converges on this primitive: the non-visual
critique arrived at ports, the visual rail at tap-down/writeback-up,
and the synchronous tradition at unit-delay-with-init — with fifty
years of hardware practice confirming the check is sufficient in the
field.

## Candidate B: the latent-flow augmented uncollect

The second answer to the lambda critique comes from a different
direction. The link is a transformation
(`transformation-levels-design.md` for the transformation/result
framing). This candidate asks its **result-level** form: what wires
and nodes does generalizing actually lay down? The answer needs no
lambda, no `prev` parameter, and no new value-producing node.

**Generalize is a cut on a wire.** Every value wire has an implicit
place to cut it. To generalize, cut a wire and interpose a new
uncollect `U`:

- the **pre-cut producer** becomes an **input** to `U` — the *seed*
  (the initial value, evaluated once outside);
- the **post-cut consumer** reads an **output** of `U` — the
  per-iteration *state* (seed on iteration 0, fed-back step after).

The previous value is neither a new node nor a lambda parameter; it is
`U`'s state output, read by whatever used to consume the cut wire.
"The link splits the initial value" made concrete: one wire, cut,
becomes a seed-in and a state-out.

(The latent place-to-cut on every wire is *not* related to `flowRef`'s
`NodeFlow` being partial. That partiality is just the ordinary fact
that you can name a port a node lacks; the latent flow here is a
separate idea about generalization, not a totalisation of `NodeFlow`.)

**The source flow is a *separate* input to `U`.** The flow being
iterated (a list) is not identified with the generalize flow — it is
*another input* to the same uncollect. `U` zips an external iteration
source with the internal feedback variable (pseudocode, provisional):

```
U : uncollect
     inputs  seed = 0        -- value, from the cut wire's producer
             src  = ~L       -- flow, the list
     outputs state           -- per-iter: the accumulator so far
             element         -- per-iter: from src
element := U.element
sum     := U.state + U.element   -- feedback: sum advances U.state
```

This is recognizably `Open ListIter` with one extra (seed-in,
state-out) pair bolted on — a generalization of an existing node, not
a new species. Its output is a single **combined "list-with-state"
flow** carrying two per-iteration ports.

**Feedback.** The cut supplies seed-in and state-out but does not by
itself say what advances the state — that next iteration's `U.state`
is *this* iteration's `sum`. Two readings: **cursor-as-feedback**
(generalize uses the current output point as the step — works because
of *when* you generalize, build one step then generalize while its
result is the cursor; the leaning) and **explicit feedback wire**
(name both the cut wire and the step wire — needed only for
out-of-order generalizes). §"The equivalence, worked" resolves this:
at the result level the step is always an explicit input;
cursor-as-feedback is an authoring gesture that fills it.

**What it produces.** The uncollect plus the feedback collect yield a
**modified flow** with the iteration variable woven in — this is the
resolution of the output-less-terminal discomfort. The combined flow
comes out of the *uncollect*; the feedback collect outputs the **final
value** (the total, or the seed if nothing fired). Exposing the
running history is then a separate ordinary collect on the modified
flow.

### Worked example: two accumulators, and Fibonacci

Watch the candidate handle the same tests. Starting program, cursor at
`sum`:

```
n0:   0
nLst: list
nEl:  first(nLst)        -- partial access
nSum: n0 + nEl           -- cursor
```

**Generalize 1 (sum).** Cut `n0 → nSum.left`. Interpose `U` (seed `0`,
`src` the list flow, outputs `state`, `element`). `first(nLst)`
generalizes in the same act — "the first element" becomes "each
element," `listFlow` born as the `src` input (the example-first case).
Feedback: `nSum` advances `U.state`.

**Generalize 2 (max).** Cut the `-inf` wire. Interpose `U2` — whose
`src` is **not** the raw list but `U`'s already-combined flow, so the
two stay in lockstep:

```
U2 : inputs  seed = -inf, src = U.flow
     outputs state2, (element, state pass through)
nMax := max(U2.state2, U2.element)
```

Generalizes **stack**: each consumes the current combined flow and
adds one more (seed-in, state-out) pair. Independent seeds,
independent steps, no tuple. "The source flow is another input"
generalizes to "the *current* flow is the next uncollect's `src`," and
the no-bottleneck claim falls out structurally. **Expose** the
accumulators with an ordinary collect on the final combined flow.

**Fibonacci falls out by dropping `src`.** A generalize with no
external source is the same uncollect with no `src` — just seed +
feedback, self-driven. Two such links cross-referencing each other's
state outputs give Fibonacci. Because state outputs are read by node
reference like any wire, self- and cross-reference are uniform — no
privileged "own previous" slot, no unused-parameter awkwardness (the
defect that sank the lambda; the port form dissolves it the same way).

**Where the principles land.** No lambda, so no binding form
introduces an interior scope. The interior/exterior difference for the
cut node (seed outside, carried value inside) still exists — that *is*
iteration state — but it is created by an explicit on-screen cut, not
a magic name; the principle is best read as forbidding *invisible*
interior/exterior differences, not all of them. Generalize is one
operation whose result is a recognizable extension of `Open ListIter`,
reusing the existing flow/uncollect vocabulary.

**The augment shape is shipped, repeatedly.** The comparison rounds
later found this candidate's port list in the field, four times over:
jq's `foreach EXPR as $x (init; update; extract)` is the augment
form's exact port list, shipped (`xquery-jq-comparison.md` — and
XQuery, which has no scan at all, is the negative witness: a dataflow
language without loop-carried state bends its other constructs around
the hole); APL's scan `\` and purrr's `accumulate` are the running
view of the same form (`apl-family-comparison.md`,
`tidyverse-comparison.md`); the JS reactive ecosystem's `scan` is the
register with an optional seed (`reactive-comparison.md`). External
validation that the augment/running view is a real, shippable surface
— evidence for the drawings conversation, not a decision.

## Two operations for accumulation: reducing collect vs augment

Back to a promise from the opening example: nobody writes three
statements to sum a list. Summing can be approached from more than one
direction, and it turns out the directions are not one construct.
Forcing them together is exactly the intent-decoding the
abstraction-level principle warns against. There are **two
operations**, one with two authoring directions:

1. **Running sum, built loop-first.** You have a list uncollect. You
   add an iteration uncollect over the list flow with a `0` seed, add
   it to the element, collect it back to the augmented flow. You
   consciously construct the state variable; the running value is
   available in-loop.
2. **Just summing the list.** You do not think about a running sum;
   you think about *putting `+` between the elements*. Open a flow
   whose value wires are any two components to accumulate, add them,
   close with that value. The empty-list start is the operator's
   **implied identity** (`0` for `+`). Only works for operators with
   an identity.
3. **Running sum, built value-first.** Start with `0`, open a list
   flow, add `0` to the element, then use the latent feed-back flow to
   feed the sum back where `0` fed in.

**Approaches 1 and 3 are the same construct** — the latent-flow
augment (a list-with-state flow), from two authoring directions.
**Approach 2 is a genuinely different operation: a reducing collect**
(spelled *reduce-close* elsewhere in the record) — a collect variant,
a sibling of the ordinary collect. It collapses a flow with an
associative operator, identity implied. It builds **no** state
variable in the authoring surface ("I don't think about a running sum"
is literally true), and it carries information augment does not:

- **The identity comes from the operator, not the user** (`+`→0,
  `*`→1). This is what makes empty→identity and `[a]`→`a` fall out
  (`identity ⊕ a = a` needs a genuine identity; an arbitrary seed will
  not do).
- **The two operands are symmetric** — the associativity assertion.
  Augment's step is asymmetric `state ⊕ element` and claims no such
  thing.
- **Its type shape is a monoid** (`op : T×T→T`) — a monoid being an
  operator that is associative and has an identity value — where
  augment's step is an arbitrary `S×E→S` (accumulator type may differ
  from element type — count, list-building).

So a reader can always tell total-sum from running-sum: different
constructs. The only new machinery reducing collect needs is
**operator identities**.

**Result-level decision: reducing collect is its own node**, carrying
the operator's monoid, and `Compile` *lowers* it — translates it to
the more concrete loop form —
`acc = identity; for (el of list) acc = op(acc, value)`. It is **not**
elaborated into the augment loop on construction. The decisive reason:
elaborating on construction would make reducing collect and "augment +
expose final" persist as the *same* result structure — collapsing the
total-vs-running distinction, making a plain `sum` read as a
running-sum machine whose intermediates nobody uses. The program of
record is the Expr, not the JS; keeping intent in the Expr is the
point. Lowering costs nothing (same `for-of` JS) and preserves the
monoid for possible future reassociation or parallel reduction. It
fits the existing close family (list / case / filter / option),
already discriminated by shape.

**Boundary:** reducing collect is available exactly when the operator
is a known associative monoid; no identity / non-associative falls
back to augment (explicit seed). The degradation is structural: no
monoid, no node. This is refined (not reversed) by
`collect-family-design.md` (status: leanings, not adopted) into a
three-tier ladder — monoid → total; associative-without-identity
(last, min) → reducing collect with an option-shaped output (fires iff
the flow fired); non-associative → augment. The empty-collect question
is the identity question, and structure carries the "no answer" case.

### A second accumulator on a `sum`, via derived-port reference

Suppose you wrote a plain `sum`, and later want to also track `max`,
in lockstep. Does the `sum` have to be rewritten into the augment
form? No — adding a second accumulator does **not** require lowering
the `sum` or editing anything. `sum` (reducing collect) has an
always-available derived level-0 form — the augment iteration — and
that derived form exposes a combined list-with-state flow as an output
port. You build a *new* augment whose `src` **references that derived
port** and adds the `max` state. `sum` stays a pristine reducing
collect; nothing about it is touched. This is the stacking rule
reaching *across the derivation boundary*: the current combined flow
may itself be derived. The mechanism (a wire referencing a derived
result's output port) is developed in
`transformation-levels-design.md`; the only open detail is which
derived ports are exposed (principal outputs like the combined flow,
not derivation internals).

That covers *adding alongside* a `sum`. *Changing the interior*
(making the step decay — no monoid) cannot be a reducing collect, and
is handled without editing: a level-1 `expand` in **materialize mode**
records a step whose result version contains the augment loop's nodes
as ordinary parts, and the decaying version is *built* from those
parts while the sum version persists in history. Rule of thumb:
reference the lens to add; take the parts to change
(`transformation-levels-design.md`, "Two invocation modes").

## The two candidates side by side

Status: **both live**; neither rejected. They are independent
resolutions of the same lambda critique, developed on parallel
threads.

**Where they agree.** No lambda, no interior scope from a binding form
— both read the previous value by wiring. Self- and cross-reference
are uniform (Fibonacci is two links reading each other's state through
ordinary wires; no privileged "own previous"). The initial value lives
outside the flow, one per link, and the link cannot exist without one
(the empty case is closed by the same act). One variable per link, no
tuple. Both are result-level forms of the same link transformation.
Both realize the visual rail (tap-down / writeback-up / dotted initial
map onto port form's `prev`/`step`/`init` and equally onto latent
form's state-out / feedback / seed-in).

**Where they differ.**

- **Node species vs generalized uncollect.** The port form keeps the
  variable in a *new node* (Delay) standing beside the flow it names.
  The latent form weaves it *into the flow*: the cut interposes an
  uncollect that is "Open ListIter with one extra port pair," yielding
  a combined flow whose `state` port sits beside `element`.
- **How the source flow relates.** A Delay *references* its flow. The
  latent uncollect takes the flow as an *input* (`src`) and outputs
  the combined flow — giving it a structural stacking rule (each
  accumulator's uncollect takes the current combined flow as `src`,
  lockstep by construction) that the port form expresses only as many
  Delays referencing one flow.
- **Reading of inside-out.** The port form claims a full pass (`prev`
  is a port like the list element). The latent form concedes the cut
  node *is* different inside vs outside (seed vs carried value) — that
  is what iteration state means — and reads the principle as
  forbidding only *invisible* differences.
- **Companion machinery.** The latent thread additionally brings the
  transformation-levels framing, reducing collect, and derived-port
  references. These are largely independent of the choice (reducing
  collect's lowering could target either form) but were stated in the
  latent form's vocabulary.

### The cross-reference cycle, and Delay as the quotient

Try converting each form into the other, and two facts surface that
matter for the decision.

**Delay is the quotient.** ("Quotient" here in the mathematician's
sense: the description left after forgetting a distinction that
carries no meaning.) Recognition (augment → Delay) is total and
**canonical** — restore the plain uncollect, mint a Delay per
augmentation layer, unwind stacked layers inside-out, forget the stack
order. Lowering (Delay → augment) is total but requires an **arbitrary
choice**: multiple Delays on one flow have no ordering, but stacking
augmentations must choose one, giving n! equally valid results with no
semantic content (every state read is a previous-iteration read; the
state ports have no within-iteration dependency). So Delay → augment →
Delay is the identity, but augment → Delay → augment reproduces the
original only up to stack order. The augmented form draws a
distinction (stack order) that carries no meaning; the Delay form does
not. In the fifth principle's vocabulary, Delay is the more abstract
description and the augmented flow behaves like a *derived view* of it
— recognition is the canonical map, lowering a section. This nominates
Delay as the program of record *if both exist* (it holds only while
stack order stays semantically inert; a future feature sequencing
state updates within an iteration would break the quotient).

**The cross-reference cycle does not go away.** Converting Fibonacci
exposes a hole in the augmented form's acyclicity story. Two Delays,
`fib_b.step` reading `fib_a.prev` and vice versa, become two stacked
augmentations `U₁`, `U₂`. Where does `U₂`'s `src` come from? `U₁`'s
feedback reads `U₂.state`, which exists downstream of `U₂`'s
uncollect, whose `src` is supposed to be `U₁`'s modified flow — a
cycle. Two ways out: emit the combined flow from the *uncollect*
(feedback collect reverts to an output-less consumer, reinstating the
discomfort), or **accept the cycle** (the augmented form needs the
productivity story after all). Either the discomfort or the cycle
returns. This independently supports the recorded position that
**cycles will have to be supported eventually**: even the form
designed to stay acyclic hits one as soon as accumulators
cross-reference, which is Fibonacci — the second example anyone
writes.

## The Delay back-edge: the write half is a node

A register (Delay) is where a loop-carried accumulator lives, and it
is the one place a cycle enters the language. The spec wires a Delay's
`step` input in a second act, *after* its `prev` output is already
referenced — the same two-phase pattern as wiring a Collect to its
Uncollect. But Expr construction is immutable and bottom-up: there is
no "second act on an existing node" without mutation, a tie-the-knot,
or symbolic indirection. This section works out a fourth escape the
list didn't name — **move the edge, not the node**. It is a fact about
the Expr representation, but both candidates above rest on it, so it
lives here; `first-class-ports-design.md`, whose migration it
presupposes, keeps a pointer.

### The three named escapes fail for cause

- **Mutation.** At the diagram level, "wire `step` later" is a field
  assignment on mutable diagram data — an ordinary editing gesture,
  which is why the spec can say it casually. Expr nodes are immutable
  records; there is no second act to perform. A mutable cell smuggled
  in for `step` alone would make Delay the one node whose meaning can
  change after construction — and every consumer of Expr (printer,
  memo, future checks) currently assumes it can't.
- **Tie-the-knot.** `let rec` with deferred evaluation can build a
  cyclic immutable structure — but the port form's supersession of the
  earlier lambda form counted "no `let rec`, no deferred evaluation,
  no circular value dependency at construction time" among its gains.
  Buying construction back with host-language laziness re-imports the
  lambda form's machinery with less visibility than the lambda had.
- **Symbolic indirection.** The spec discarded `ById` references when
  it superseded IterationRail — "replaced by an honest back-edge."
  Resurrecting id-as-reference at the Expr level would undo exactly
  that supersession, and would make Delay the one place in Expr where
  a reference is not a structural pointer.

### Read the wiring analogy literally

Both documents justify the two-phase wiring by the same analogy:
`step` is wired "as a separate, later act — the same two-phase pattern
as wiring a Collect to its Uncollect." Look at *why*
Collect-to-Uncollect needs none of the three escapes at the Expr
level: **the late edge is held by a new node.** The Open is never
revisited; the Close, constructed last, carries every edge of the
wiring act — the flow it closes, the value it collects. The object
graph stays a DAG even though the computation is circular in the
informal sense (the element the Open provides is used in the value the
Close consumes; the pairing carries that loop, not any forward
pointer).

The analogy breaks for Delay only because the spec puts the late edge
*inside the existing node* — `step` is a field of Delay. So make the
analogy literal: the later act mints its own node.

### The shape

The Delay splits into a read half and a write half (names provisional
— tap/writeback in the rail vocabulary would also do):

```
DelayRead:                      DelayWrite:
  flow: FlowSource                read: (the DelayRead node)
  init: ValueSource  (outside)    step: ValueSource  (per-iteration)
  valueOutputs: {prev}            valueOutputs: {final}
```

In the textual form this is the two-statement register — the running
sum from the top of the chapter, annotated:

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum          -- read half; bare `sum` = prev
sum, a -> add -> step of sum => total   -- write half; binder = final
```

Construction is bottom-up with no second act on any node:

1. Mint the read half — its `flow` and `init` are known up front.
   `ValuePort(read, "prev")` exists immediately.
2. Build the step expression, referencing this read's `prev` and any
   other reads' `prev`s (cross-reference needs nothing extra: mint all
   the reads first, then build all the steps).
3. Mint the write half last, holding the read reference and the step.

The object graph is a DAG unconditionally — Fibonacci included:

```
steps -> open list => n, ~L
~L ~> delay init 1 => fa
~L ~> delay init 1 => fb
fb -> step of fa => lastA
fa, fb -> add -> step of fb => lastB
```

Both reads are minted before either step, so the cross-references
(`step_a` reading `prev_b` and vice versa) are ordinary forward wires.
The back-edge — the `step → prev` crossing, the language's one
iteration-boundary edge — is recovered from *identity*: the write
names its read, and the compiler and the productivity check treat the
pair as the crossing. The productivity condition ("every cycle crosses
a register") restates verbatim with "the Delay's internal
`step → prev` edge" read as "the pairing edge write → read."

How the write names its read is a spelling choice with a wrinkle worth
recording: a bare node reference (as `flow` names a node today) is the
lean; the alternative is a dedicated port on the read half — a
*register* or *thread* port — that the write half consumes, making the
read-to-write connection a wire of its own species. The alternative is
resonant: this document's fourth option wants the state's history to
be "a path in the picture," and a thread wire from read to write *is*
that path's rail, present in the representation rather than
reconstructed by the renderer. It also turns the one-write rule into
wire linearity (the thread port is consumed exactly once). Deferred to
the naming question — set aside, not rejected; the pair works
identically under either spelling.

### The exit anchor comes for free

What is the write half's output? The record answers before the
question is asked. The final value is "available as a normal solid
wire emerging from the right end of the rail" — but the *contracted*
one-node Delay has `valueOutputs: {prev}` and `flowOutputs: {}`. The
point projection kept three of the state thread's four anchors
(enter/`init`, tap/`prev`, writeback/`step`) and *lost the exit*.
Nothing in that record says how a program reads a fold's total out of
the Delay form: Delay emits no flow, so the latent form's expose (a
collect on the combined flow) isn't available, and collecting the
`step` values into a list and taking the last element is a distortion
— it materialises the whole history and gets the empty case wrong
(zero iterations should yield `init`; the collected list is empty).

The write half is where the exit was hiding: `final` is the register's
value after the flow completes — the last `step`, or `init` if no
iteration ran, which grounds the empty case exactly as `init` grounds
productivity.

The pair's port signature is Open/Close transposed to the register:

| | outside in | per-iteration out | per-iteration in | outside out |
|---|---|---|---|---|
| collection | source (Open) | element (Open) | value (Close) | result (Close) |
| register | `init` (read) | `prev` (read) | `step` (write) | `final` (write) |

Each half converts across the flow boundary in one direction: the read
half brings an outside value in as the tap; the write half takes a
per-iteration value out as the total. The state thread's four anchors
are exactly the pair's four ports, two per node — which is what "the
thread's endpoints" should mean representationally. The stored-form
arrangement the thread section leans toward ("store the Delay
quotient, render the thread") gets a quotient with all four anchors to
render from, instead of one missing the right end of the rail.

`final` is the *total*, not the *running* value. Exposing the running
sum stays an ordinary close over per-iteration values, so the
total-vs-running distinction (reducing collect must not persist as
"augment + expose final") survives untouched.

### Facing the terminal-node critique

Now, you might wonder: doesn't a write node un-supersede the
stateful-collect this chapter rejected earlier? The record counted "no
matched open/close pair; no terminal node with no output" among
Delay's virtues, and the port form's superseding note says "there is
no separate feedback node at all … so nothing output-less exists." It
turns out the answer is no. The recorded discomfort was
*outputlessness* — "previously, every node was a producer;
stateful-collect is a pure consumer" — not pairedness; the language is
made of pairs. The write half is a producer, and its output is one the
one-node form turns out to need and not have. What the
stateful-collect got wrong was terminating; what it got right — a
distinct node for the writing act — is what constructability forces
back.

What survives as a cost: the one-write-per-read constraint changes
character. On the one-node form it is local — "is the `step` field
wired." On the pair it is a whole-graph counting check: exactly one
write references each read. But this joins a family the record already
made peace with — "one variable has one write slot; two writes
conflict" was called structural, and the well-formedness family (alt
matching, no-crossing, productivity) consists precisely of quotient
constraints "enforced as a check, not by construction." (Under the
thread-port spelling it is wire linearity rather than counting.)

### What it forces to the surface: the program is a node set

One genuinely new consequence. A write half is reachable from a
program's root only through `final`. Consider Fibonacci consumed
one-sided: the result references `final` of register *a* only;
`step_a` reads `prev_b`, so register *b* must advance every iteration
— but *b*'s write half hangs off nothing downstream. Walking inputs
from the root never finds it.

So a compile that encounters a foreign `prev` needs a **write index**
(read-node id → write node), built by a pre-pass — the
`collectBranchesByAlt` move — except the index *cannot* be built from
the root expression when a write is root-unreachable. This forces a
README next step motivated so far only by spec fidelity: **diagrams as
the top-level structure.** The spec keeps an explicit `nodes` set and
justifies it by editing-time disconnection; the write half makes the
node set necessary for *complete* programs.

So **a program with loop-carried state is a node set with
distinguished outputs, not a root expression.** This is why a write
statement's binder may be omitted when the final value is unused, and
why the textual form is a statement list with declared outputs rather
than "the last expression is the result." The interim spelling is
honest and small: the compile entry takes the writes alongside the
root (`compileToBody(root, ~writes)`), stating the requirement without
building Diagram yet.

Root-reachability as the definition of the program is not just
insufficient for Delay write halves — it loses live work in mainstream
runtimes today. The concurrency survey (`real-loop-survey.md`, survey
3, finding 3.4) drew a spawned companion task carrying the comment
"Keep a hard reference to prevent garbage collection" with a
production incident link: asyncio holds tasks weakly, so a complete,
running program whose parts are unreachable from any root gets
collected mid-flight. The node-set consequence has a field bug class
behind it.

### The latent-flow crossover

Both candidates needed the back-edge answer; the crossover is more
than that. §"The cross-reference cycle, and Delay as the quotient"
above records a forced choice between two discomforts for the latent
form: combined flow out of the feedback collect → cross-referencing
accumulators cycle among the augmentations; combined flow out of the
uncollect → the feedback collect is again a terminal node with no
output. The write half's lesson dissolves the second horn: the
feedback collect's output does not have to be the combined flow to be
an output — it can be the **final value**. Combined flow out of the
uncollect (no cycle), final value out of the feedback collect (no
terminal node). The latent form takes exactly this arrangement, and
the equivalence round below shows the pinning is forced rather than
chosen, identifies the feedback collect with the write half, and
proves the two candidates result-level equivalent — one register pair
under two drawings (§"The equivalence, worked: one register, two
drawings").

### Against the philosophy, briefly

Inside-out: unchanged — no scope is introduced; `prev` and `final` are
wires. No bottlenecks: unchanged — two registers are two pairs, no
packing. Example first: the link transformation's steps *are* the
construction order (the concrete step expression exists before the
write half that generalises it). Abstraction as source of truth: the
thread renders over the stored pair, and the pair — unlike the
three-anchor contraction — contains everything the thread draws.

### Effect on the ports migration

None on `first-class-ports-design.md`'s steps 1–4; the pair lands with
the iteration-state round, not with that migration. It presupposes
step 1's `valueRef` (the write's `step`, everyone's reads of `prev`
and `final`) and nothing else.

### What stays open on the pair

- **Diagram-level shape.** Does the spec keep one Delay node, with the
  pair as its Expr-level form — or adopt the pair? Either way the
  spec's inventory needs a home for `final`, which it currently lacks.
- **Naming, and the pairing spelling.** read/write vs tap/writeback;
  bare node reference vs thread port (above); whether the pair renders
  as one glyph (the rail) regardless.
- **Multiple writebacks.** Conditional carry / multi-site update is
  unchanged; if conditional carry is ever a second write node rather
  than a conditional value into one write, the counting check is where
  it lands.
- **`final` on self-driven streams.** A Fibonacci with no external
  source never finishes, so its `final` is never available.
  Demand-time error, type-level impossibility, or a thunk that never
  returns — belongs to the iteration-state round's self-driven-stream
  story. A candidate rule now exists that dissolves this into
  mis-anchoring rather than a hazard: `final` as a read at a drawn
  anchor flow's completion (`end-when-design.md`, "The register
  final-readout anchor" — worked, not adopted); under it the program
  that stops via end-when anchors its final at the shortened flow
  and has an ordinary value.
- **Which flow the read half's `flow` names.** The schema above
  commits to a `flow: FlowSource` field and the examples bind it to
  the uncollect's flow — but *which* flow a Delay is over, when more
  than one is in reach, is the open question of what a Delay *is*
  (`delay-ontology-design.md`); the field's existence does not settle
  it, and its meaning may end up read off provenance (the update
  cadence) rather than authored.

## The equivalence, worked: one register, two drawings

Status: **an exploration with a worked correspondence and leanings,
not an adopted design** — read what follows as an argument the record
finds convincing, not as a committed feature. This takes up the most
promising deciding step — whether the port form's Delay is exactly the
result-level structure the latent-flow transformation lays down. The
answer: **yes — once the latent form's undetermined pieces are pinned,
and the pinning turns out to be forced rather than chosen.** At the
result level the two candidates are one construct — the register pair
— under two drawings, and the open decision moves from meaning to
surface.

### Pinning the feedback collect: it is the write half

The latent form's residue was (a) cursor vs explicit feedback wire,
(b) the concrete form of the feedback collect, (c) the stacking rule —
plus "which side of the feedback collect the combined flow comes out
of." The write half (§"The Delay back-edge: the write half is a node"
above) answers (b) by identification, and the identification is
**forced from three directions at once**:

- **The collect must have an output.** The rejection of the terminal
  stateful-collect stands, full stop. So "combined flow out of the
  uncollect, feedback collect output-less" is not available.
- **The combined flow cannot be that output.** If it is,
  cross-referencing accumulators cycle among the augmentations
  (above).
- **The register still owes exactly one value.** Without a dedicated
  exit, the only readout of a fold's *total* is "collect the state
  port and take the last element" — which materialises the whole
  history and gets the empty case wrong (zero firings must yield the
  seed; the collected list is empty). The missing value is the final
  value.

One arrangement satisfies all three — the write half's:

> **The pinned form.** The augmented uncollect takes `seed` (value,
> from the cut wire's producer) and `src` (flow), and outputs the
> `state` port *and the combined flow*. The feedback collect is the
> write half: it holds the pairing reference to its uncollect and the
> `step` wire, and outputs the **final value**.

Residue (a) then dissolves as a level confusion, not a fork: at the
result level the feedback collect always holds an explicit `step`
input wire — there is no "cursor variant" of the *structure*.
Cursor-as-feedback is an *authoring gesture* that fills that port with
the current cursor at generalize time. The out-of-order worry was
about the gesture's applicability, not the structure (many authoring
paths, one reading).

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
latent uncollect *consumes* the source flow (`src` in, combined flow
out) where the read half *references* it; and the combined flow
carries pass-through ports (`element`, earlier states) the port form
never draws.

### The residue is drawing, not meaning

- **The lockstep lemma.** The augmentation adds no firings and removes
  none: the combined flow fires exactly when `src` fires, one for one.
  So "list-with-state" is *not* a flow kind — the combined flow's kind
  is `src`'s kind, its collects behave as `src`'s collects, the kinds
  table is untouched — and every flow in an augmentation chain has
  identical firings, which makes the erasures safe.
- **The pass-through ports are availability.** The barrier-crossing
  round (`barrier-value-crossing-design.md`) re-read pass-through
  value ports as *availability by provenance*: a value readable in a
  context is readable there without being re-exported through each
  node its flow passes. The combined flow's `element` and
  earlier-state pass-throughs are exactly that — drawn availability,
  not structure. What the augmentation genuinely *mints* is `state`
  and, at the collect, `final`; each is obtainable by a complete
  construct of its own (the read's tap, the write's exit), so they sit
  on separate nodes — agreeing with the pair's grain.
- **Stack order and siblinghood are inert.** Stack order carries no
  meaning (established above). Whether a second accumulator's
  uncollect takes the *combined* flow as `src` (stacked) or the *raw*
  flow (sibling) is equally inert — lockstep is guaranteed by firings,
  joint readability of states is availability, not port plumbing. So
  the stacking rule (residue (c)) is confirmed as a composition and
  simultaneously demoted: it is a drawn convention, not load-bearing
  structure. This softens a listed cost of the latent form ("uncollects
  grow; the same logical iteration exists in several versions"): the
  chain of combined flows is inert drawn structure over one quotient,
  like the lowering's n! stack orders.

### The theorem

> **Result-level equivalence.** Over the pinned form, recognition
> (augment → pair) and lowering (pair → augment) are total;
> recognition is canonical; lowering is a section of it (a right
> inverse — recognize after lowering and you are back where you
> started) up to inert drawn structure (stack order, siblinghood,
> pass-through ports); and both preserve the program's meaning.

Meaning-preservation needs no new machinery: both forms share their
compile target — the register core (init-before, read-at-top,
write-at-bottom, final-after, per firing of the one shared flow). The
correspondence is a bijection — an exact one-to-one match — on the
four anchors preserving every wire into and out of them, so both forms
put the same values through the same register at the same firings, by
induction on firings; the empty case is grounded identically (`final`
= seed when nothing fired); and the total comes out of the
corresponding port on both sides.

**The productivity check transfers verbatim.** Read "the Delay's
`step → prev` crossing" as "the pairing edge, feedback collect →
augmented uncollect," and the condition — every cycle passes through a
crossing — is the latent form's cycle story word for word. A
non-productive configuration is a cycle avoiding every pairing.

**In the stored form, the check is a theorem.** Both forms' Expr
representation is immutable and bottom-up, so the object graph is a
DAG unconditionally (the write-half construction; the pinned collect
is built the same way). In the computation graph every ordinary data
edge runs *against* an object pointer (the consumer holds the
producer), and the only edges running *with* an object pointer are the
pairings (the write holds its read; the collect holds its uncollect).
A cycle of reversed-DAG edges alone is impossible, so every
computation cycle passes through a pairing — which is the productivity
condition. Non-productive programs are therefore unrepresentable in
the stored form; the check's real subject is any surface with mutable
wiring (the diagram editor, where `x = x + 1` is drawable) and any
import path. (The write-count check does *not* dissolve: exactly one
write per read transfers to exactly one feedback collect per
augmentation and remains a counting check in both forms.)

**The one genuine asymmetry: the self-driven corner.** A link with no
external source is, in the latent form, an uncollect with no `src` — a
node that *mints* the self-driven flow. The port form has no
counterpart: its Delay "references its flow," which presupposes a
flow-minting node the record never names (the same hole the text side
hit — `translation-exercise.md`, finding 3). So here the latent form
is not equivalent to the port form; it is *ahead* by one node. The
equivalence holds once the port form borrows that node — a bare
self-driven uncollect whose only content is the flow mint — which it
needs anyway for the corner to be authorable. (`final` on a
self-driven flow is never available; that residue is shared and stays
with the async/stream rounds.) That borrowed node now has its own
round, `source-openers-design.md` (status: leanings, not adopted): a
bare flow-minting uncollect exactly as pinned here — no value ports,
no new flow kind, the sourceless stream — with pacing and the external
pull source worked beside it.

**The standing caveat.** The quotient holds because nothing sequences
state updates within a firing — every crossing is a whole-iteration
delay. A future feature ordering updates within a firing would make
stack order meaningful and break the erasures. The survey evidence
(sixty loops, every register one-writeback; within-iteration chaining
expressed as ordinary value wires — `real-loop-survey.md`) is comfort,
not proof.

### What this decides, and what it does not

The three recorded deciders each land: (1) the feedback mechanic has a
clean concrete form — it is the write half, so the port form does not
win by default; the forms merge, and *both* avoid the non-DAG stored
representation. (2) Compile experience stops discriminating — one
backend consuming the pair (the check free at this level) serves both
surfaces. (3) "They may be the same thing" — confirmed, dissolving
into a transformation-level/result-level distinction, not a design
fork.

Consequences:

- **The adopt-one/adopt-both question is reframed.** At the result
  level there is nothing to adopt-one-of: the language has one
  iteration-state construct, the register pair. The "coexistence must
  be defined" cost collapses; "two compile paths, two well-formedness
  stories" was double-counted — there is one of each. One-obvious-way
  is satisfied at the *reading* level (many drawings, one reading —
  the many-paths/few-readings corollary).
- **Store the pair.** The quotient nominated the Delay side as the
  program of record; the erasure arguments strengthen it (the
  augmented drawing carries *only* inert extras). The augmented flow
  becomes a derived view over the stored pair — machinery already
  load-bearing: reducing collect's derived augment form and the
  running view (`variable-rate-consumption-design.md`) are that view
  in use.

**What this round deliberately does not decide: the surface.** Which
drawings exist, which is primary, what a beginner meets first — that
is the bar from the design review, untouched. The RTL and ST gestalt
critiques (below) survive intact, sharpened if anything: they can no
longer be dodged by "picking the other candidate," because both attach
to drawings of the *same* stored construct. The leaning left for that
conversation: conduct it as "which projections of the register do we
draw, and when does the editor switch projection" — with the
equivalence guaranteeing no choice of drawing forecloses any
semantics.

**Dead ends closed by this round.** Now, you might wonder about four
arrangements the equivalence work considered and closed. Each is a
settled dead end — please do not revisit without new evidence:

1. **Combined flow out of the feedback collect** — the arrangement
   under which the equivalence *fails* (augmentations acquire cycles
   the pair form does not have).
2. **"List-with-state" as a flow kind** — dies on the lockstep lemma
   (no firings of its own, no collect behaviour of its own; a kind
   with no kind content that would fork every row of the kinds table).
   State is ports on a flow, never a kind of flow.
3. **Read-half-as-uncollect** (identifying the Delay read with an
   uncollect even when an external source exists) — makes each
   accumulator re-open the flow, so stacking/siblinghood becomes
   structural rather than inert, destroying the quotient the
   by-reference tie buys. (The self-driven corner is the one place
   read-as-uncollect is right, because there the flow must be minted
   by something.)
4. **Dissolving the write-count check through the correspondence** —
   it does not dissolve; the counting check transfers unchanged (one
   feedback collect per augmentation) and stays a quotient constraint
   in both forms.

## What a Delay is, and which flow binds it — an open problem

Status: **an open problem, moved to its own document** —
`delay-ontology-design.md`. It began here and outgrew the register
story; only the shape of the question and its current state are kept
in place.

The equivalence above pinned the register's *structure*, but left a
prior question implicit: what *is* a Delay — not what it computes, but
what kind of thing it is — and which flow supplies its "next
iteration"? The question is invisible while only one flow is in reach
and *selects the behaviour* the moment more than one is — a commute
between where a carried value originates and where the register is
collected, or a product's several axes. It is the worked instance of
the "what does it mean?" lens (`language-design-philosophy.md`): fully
pinned results, undecided meaning, and the meaning decides real cases.

Where the ontology document currently stands, in brief:

- **Firm:** a Delay is a feature of the flow ("carry to the next
  iteration" is meaningless without one), and it does not thread the
  flow wire the way IO does — IO's wire-threading encodes a temporal
  sequence between operations, and Delays have no mutual order.
- **The fork:** the **collect** that binds the register (candidate 1)
  vs the **ancestor uncollect** its value descends from (candidate 2),
  plus the held-open possibility that Delay is the wrong abstraction.
- **Two reframings dissolve most of it.** The **value-in-context
  model** (an uncollected value as a cursor into its wire's
  firing-indexed sequence) makes the flow provenance-fixed rather than
  chosen — the candidates coincide on sequences and are silent on
  grids. The **update-cadence / read-range split** (a register updated
  inside a filtered inner flow is still readable, held, on the
  unfiltered outer flow — this is `hold`,
  `incremental-flow-design.md`) shows the two candidates were
  answering two different halves of the register all along: provenance
  fixes the *update* flow, the consumer picks the *read* flow.
- **The live residue:** the product's **linearization** — several
  running-view consumers of one non-commutative register reading in
  different orders — the recompute-vs-explicit-axis-reference trade.
  The pure-`final` corner is closed (over a product, `final` is a
  reduced-rank flow, so its consumer names the axis).

One caution for readers of *this* document: the value-in-context model
dissolves the four `prev(x)` rejections recorded above — it recasts
`prev` as a readout on the wire's context rather than a name lookup —
without re-proposing the `prev(name)` surface. Check the ontology doc
before citing those rejections against a cursor-style `prev`.

## The surface question: point, cell, or thread

At the result level there is one construct. The open decision is which
drawing is the surface — what you, the programmer, actually see and
write. Two gestalt critiques frame it, symmetric in an instructive
way:

**The RTL shadow over the point (Delay).** A program built from Delay
nodes looks like Verilog — register-transfer logic, the style hardware
designers use, not known for being natural to beginners. RTL has a
virtue (follow a wire, see the data path) but its timing structure is
invisible: it must be *deduced by counting registers*. A Delay node is
a **point**; everything about "when" happens at that point and must be
reconstructed in the reader's head.

**The ST shadow over the cell (augmented flow).** An iteration
variable woven into a flow starts to look like an imperative program
dressed in flow clothing — a state port resembling a `ST`-monad state
variable, addressed, updated, threaded by convention. At that point it
is imperative programming, and the naturalness visual programming
should provide is lost. The rail notes flagged the same from the
visual side: a generic register with read/write ports "collapses into
the imperative paradigm wearing visual clothing." The augmented flow
is a **cell**.

One erases time from the picture; the other erases the state's
identity as a followable thing.

### A fourth option: the visible state thread

Status: **conjectured fourth option, currently the most promising
direction.** What you should be able to do is *see the state threading
through the loop* — the state's history as a **path** you can follow,
not a point and not a slot.

Promote the redesigned iteration rail from "visual depiction" to **the
construct itself**. A *state thread* is a first-class path with four
anchored connections whose geometry is its meaning:

- it **enters** from the initial value (dotted attach, outside the
  iteration);
- it **crosses** the single generic iteration column, where it has
  exactly one **tap** (per-iteration read) and, later along the
  thread, one **writeback** (per-iteration write) — the stretch
  between is that iteration's state epoch;
- it **exits** as the final value — a first-class endpoint, not a
  separate close bolted on.

Position along the thread *is* time. Following it left to right reads
the whole history: initial value, each read-compute-write epoch, final
value. Nothing about "when" must be deduced.

**The two candidates are its degradations.** Both fall out by *erasing
part of the path*:

- **Contract the thread to a point** — keep only its endpoints,
  discard the drawn path — and you have the Delay node (`init` in,
  `prev`/tap out, `step`/writeback in). This is why Delay feels like
  Verilog: the timing geometry is deleted, so timing must be
  reconstructed by counting.
- **Absorb the thread into the uncollect** — keep only where the path
  crosses the column boundary, discard its identity as a line — and
  you have the augmented flow (the seed-in/state-out pair plus
  feedback). This is why augment feels imperative: the thread's
  followable identity has dissolved into "the flow's state," a cell.

So the fourth option is not a third meaning — it is the claim that the
thread is the *primary surface* and Delay and augment are its two
projections, each used where the path picture degrades:
cross-referencing threads (Fibonacci) are parallel threads with taps
between them (drawable for two or three; dense mutual reference
tangles, and contracting to Delay points is the honest fallback — also
where cycles are unavoidable in any form); whole-flow operations
(stacking generalizes, reducing collect's derived view, referencing
the combined flow as a thing) use the flow projection.

**Where it lands.** The thread's meaning is exactly the register core
(init-before, read, write, final-after); the fourth option is that
core with a *visible surface* on top — the register becomes a drawn
history you can see, answering the objection that the core is "the
imperative picture both surfaces exist to dress." The equivalence
grounds it end to end: "store the pair (the quotient), render the
thread, derive the flow view" is the thread's cheapest realization —
one construct, three drawings: the point (Delay glyph), the flow
(augmented uncollect), the thread (the path with all four anchors,
which the pair, unlike the one-node contraction, fully carries). The
productivity check restates naturally: a cycle is well-formed iff it
passes through a thread's tap-to-writeback epoch — every feedback loop
visibly carried by some thread, the check's subject now something the
user can point at.

**Open points for the thread.**

- **Multiple writebacks.** The clean rule is *one writeback per
  crossing*, with conditional carry expressed as a conditional *value*
  wired into the single writeback. This survived contact with real
  loops: two survey runs, sixty loops across infrastructure and domain
  corpora including dense numerics (`real-loop-survey.md`), plus a
  third independent corpus — the Zig study, whose loops are "registers
  all the way down," found no sample breaking the rule
  (`zig-comparison.md`, clash record). Conditional carry occurred
  three times and expressed exactly as prescribed each time; a
  multi-site-append buffer with conditional reset and a backtracking
  save/restore cursor both reduce to one conditional value per firing;
  an eight-register fixed-point kernel is eight parallel one-writeback
  threads. No sampled loop needed two independent writebacks. Recorded
  caveat: what strains in the reset case is effect *ordering* within
  the firing, which no writeback count addresses.
- **The crossing rule.** Threads are a new wire species. Do
  thread/value and thread/thread crossings fall under the existing
  no-crossing rule, or does the horizontal-rail geometry need its own
  convention?
- **Result-level status.** Is the thread its own result-level
  construct, or a rendering of a stored projection? The cheapest
  version: store the Delay quotient, render the thread, derive the
  flow view — making the fourth option an arrangement of existing
  pieces rather than a new primitive.

### The surface decision (2026-07-23): the thread is the framing

The design conversation adopted the fourth option: **the thread is
the right framing.** Scope of the decision, as taken:

- **Adopted:** the thread as primary surface, realized as
  conjectured above — store the register pair (the Delay
  quotient), render the thread, derive the flow view. The point
  and the flow are the thread's projections, used where the path
  picture degrades (dense cross-referencing recurrences; whole-
  flow operations). With the pair stored and the other drawings
  derived, the coexistence question below resolves **by
  construction** as stored-form asymmetry; the domain split stays
  the named cliff it is.
- **Deliberately deferred:** the ergonomics round. The
  conversation's own words: the really challenging part will be
  working out the details that make the thread *friendly to the
  programmer* — and that work was intentionally not started. The
  open points above (the crossing rule, the one-writeback rule's
  effect-ordering caveat, the result-level fine print) belong to
  that round.
- **A constraint recorded for that round — the generic-iteration
  picture must not get lost.** In a visual language, the way to
  convey summing a list is to draw a point for the prior total
  and a point for a generic element, sum them, and indicate that
  this repeats. The thread's tap→compute→writeback epoch *is*
  that picture, drawn once over the single generic iteration.
  Whatever the ergonomics round does to the rail, the beginner's
  running sum must keep reading as "prior + element → next,
  repeated" — never an unrolled history, never an opaque fold
  glyph.
- **A caution recorded, vague by intention.** The register/thread
  family is constant-space: fixed-shape per-iteration state. The
  conversation registered a feeling that constant-space constructs
  will prove too limiting at some point, and that recursion-shaped
  constructs closer to functional programming will be wanted —
  *what those are is unknown*. The divide flow
  (`divide-flow-design.md`) is the record's current recursion
  story and may or may not be the eventual answer. Recorded so
  the demand is expected when it arrives, not resisted; nothing
  here is worked.

### Coexistence models (if both surfaces are first-class)

If the language exposes more than one drawing as first-class, "what
does a mixed program mean" needs a single answer — provided by a
stored form, a boundary, or a core, not by pairwise conversion. Three
ways, none resting on a proven two-way equivalence:

- **Stored-form asymmetry (derived views).** One form is the program
  of record; the other an always-available read-only derived view (the
  fifth principle's machinery, already needed for reducing collect).
  Only the derivation direction need exist; authoring gestures on the
  view are reinterpreted as edits to the stored form. The quotient
  nominates Delay as stored with the augmented flow as its view.
- **Domain split.** Each form owns scenarios outright (augmented flows
  for single-flow scans, Delay for cross-referencing recurrences and
  self-driven streams). No conversion, a designed boundary. Cost: the
  boundary must be learnable, and a program that grows across it (a
  scan acquiring a cross-referencing accumulator) needs manual
  rewriting at exactly the wrong moment. The seventh principle names
  this precisely: the domain boundary is a designed cliff on a +1 step
  — the failure mode the principle forbids. Of the three models this
  is the one that now needs a "very good argument"; the other two are
  cliff-free (a derived view expands by authoring on the view; a
  common core expands by adding registers).
- **Common core.** Both forms desugar to a shared result-level core —
  the loop register. Mixing meaning is defined once, at the core.
  Cheapest to specify, at the cost that the core — not either surface
  — is where the meaning lives, and the core is exactly the imperative
  register picture both surfaces exist to dress. (The fourth option is
  this model with a visible surface on top — the register dressed in
  geometry as a followable history.)

## The ergonomics round, opened (2026-08-04)

The deferred ergonomics round was opened by a design conversation
working the running sum's drawing, and its first pieces are
settled as the working approach — "for now," revisable as the
round continues. The trigger was an honest reading problem:
`step of sum` puts a wire in a context that changes its meaning,
which has no visual rendering; and `~L ~> delay` has the register
consume a flow wire it does not operate on.

**The thread is a third connector species.** Written with the `@`
sigil (provisional): neither a value wire nor a flow wire, a
thread says *this point corresponds to that point across a frame
change* — here, one iteration to the next. The running sum:

```
xs -> open list => a, ~L
0 @s, a -> add => nextSum @s
nextSum -~> collect last => total    -- exit; see the scoop note below
```

**No flow operand on the register.** `~L ~> delay` was the record's
only value-level construct consuming a flow wire without operating
on it — an anomaly against the derived-context principle stated
three times over (P3; the divide flow's per-instance rule; the
boundary round's per-call rule). Dropped. Taking a flow as input
signifies operating on the flow (taking over control flow); the
register does the opposite — the flow is in control and the
register computes in the environment it provides.

**The frame is derived.** The thread's frame family is the derived
context of its anchors — in the sample, `~L` via `a`, read off the
wiring exactly the way `add`'s per-element-ness is. Check picks up
two obligations: the thread's two anchors must derive the *same*
context (else witness), and the init must be exterior to it (the
ordinary prefix rule — which was the only real work the old flow
operand did).

**Anchors are ports.** The read anchor is an input port receiving
two inks: the solid init wire and the dotted correspondence. Its
law: *the port's value at frame n is the write anchor's value at
frame n−1, or the init when no prior frame exists.* The write
anchor is the source port of the written value. First-class ports
make both addressable; the only new ink is the dotted line. The
rail (`iteration-rails-design-notes.md`) survives untouched as the
layout rendering — the dotted correspondence stretched across the
generic-iteration column; on the wiring side there is no column.

**Explicit frames for the residue — flow as context, drawn.** Two
cases where derivation is silent or ambiguous: nesting (anchors in
`[~L, ~M]` default to the innermost frame; carry-across-the-outer
is said with the record's existing `in` clause — `@s in ~L`), and
pure state loops on self-driven flows (no per-firing operand
anywhere, nothing to derive — the annotation is mandatory).
Visually the explicit case uses **annotation ink**: a dotted touch
from the thread to the flow wire, never a solid wire into a port.
The general vocabulary this settles: *solid-into-port means "I
operate on this flow"; dotted-touch means "I live in this flow's
frames."* Context-membership was never geometric — it is derived,
and the annotation exists only for the residue. One localization
gained: the delay-ontology binding problem (which flow, under a
commute or a product) becomes a question about what the `in`
annotation means there — an annotation question, no longer a
structural-input question.

**The exit is a scoop of the read port.** `collect last` over the
written value loses the empty walk (zero firings, no last, the
init stranded). The settled form: a closer scoops the thread's
*read port*, and the same write-at-n−1-else-init law that governs
frame 0 gives the final value — init included, for the empty walk,
for free. This also decouples the final from any one closer: the
write half no longer doubles as the register's collect; the final
is a scoop at *whichever* closer the author wires (a program cut
by a collect-until scoops state-at-the-cut there; a full-extent
final is a scoop at a full-extent closer — resolving what remained
of the final-readout anchor question in the scoop vocabulary of
`barrier-value-crossing-design.md`).

What this leaves for the round's continuation: the thread crossing
rule (the open point above), the effect-ordering caveat on the
one-writeback rule, the `@` spelling and the anchors' textual
fine print (owed to the textual round), and the stored form's fine
print (the pair remains the stored quotient, its flow reference
now derived-or-annotated rather than wired). The divide flow's
link follows the same correction one dimension up (its
correspondences are already recorded as thread-species —
`divide-flow-design.md`, open question 1, refined 2026-08-04: no
boundary, the link as frame source, the frame source's form the
open edge).

## What is still unresolved

- **The concrete form of the link — narrowed to the surface.** At the
  result level the fork is dissolved: the two candidates are one
  construct, the register pair, under two drawings, with the pinned
  feedback collect being the write half. What remains is the
  **surface** — which drawings exist and which is primary, "one
  construct, three drawings" (point, flow, thread). This is the
  beginner-bar conversation: a construct both easy for beginners and
  flexible for complex code, with a smooth +1 ramp (running sum → +max
  → cross-referencing pair → take-while termination). The RTL and ST
  gestalt critiques are the live tensions there.
- **How the link relates to its flow — surface only.** Resolved
  structurally in both drawings: the link is always tied to a specific
  flow (pre-existing or born with the generalise step), and a link
  with no external source is a self-driven stream (Fibonacci), not an
  error. What remains open is the concrete surface for the attachment
  (naming a flow vs choosing the `src`).
- **What a Delay *is*, and which flow binds it — an open problem, in
  its own document.** Distinct from the surface question above; worked
  in `delay-ontology-design.md` and summarized in §"What a Delay is,
  and which flow binds it" above. Current state in one breath: firm
  that a Delay is a feature of the flow and does not thread the flow
  wire; the collect-vs-ancestor fork dissolves on sequences and is
  silent on grids (the value-in-context model), the two candidates
  answer the register's two halves (update cadence vs read range —
  this is `hold`), and the sole hard residue is a product's
  linearization — several running-view consumers of one
  non-commutative register reading in different orders, the
  recompute-vs-explicit-axis-reference trade.
- **Self-reference and cycles — resolved.** The iteration-boundary
  crossing is the only back-edge, so productivity is the structural
  condition "every cycle passes through a crossing" — a decidable
  whole-graph quotient constraint (like alt-matching and no-crossing),
  enforced by cycle detection, accepting exactly the productive
  programs, and the same causality check synchronous dataflow (Lustre
  `pre`/`->`) and hardware have used for decades. In the stored form
  of either drawing the condition holds by construction, so the
  check's subject is the mutable drawn surface and any import path.
- **Operator identities.** Reduce-close needs each associative
  operator to carry an identity for the empty-list value. How
  identities attach — registry, operator-node property,
  user-extensible for custom monoids — is worked (leanings, not
  adopted) in `collect-family-design.md`: identities attach as catalog
  rows carrying the identity value as witness, user monoids mint rows
  via the algebra facet (trusted like the JS edge), and the flat "no
  monoid, no node" boundary is refined to the three-tier ladder
  (monoid → total; associative-without-identity → option-shaped
  output; non-associative → augment).
- **Which derived ports a reducing collect or augment exposes.**
  Building a second accumulator references the derived combined flow.
  The exact set of principal output ports a derived result exposes for
  reference (versus private derivation internals) needs pinning; see
  `transformation-levels-design.md`.
- **Non-homogeneous iteration** — iterations behaving *conditionally*
  differently at each step, beyond first-vs-subsequent — is explicitly
  set aside as a separate question, not part of this primitive. Named
  so it is not conflated with what is designed here.
- **The environment the construct lives in.** The real-loop surveys
  (`real-loop-survey.md`, two runs, n=60) reweight what surrounds the
  decision. In infrastructure code the simple scan never occurred and
  early termination dominated; the domain sample found the scan alive
  and concentrated in numerics (five scans/folds in thirty draws),
  including an eight-register kernel with a cross-referencing register
  pair (Fibonacci's shape in production) and within-iteration chaining
  (one register's step reading another's *new* value — an ordinary
  value wire in both drawings, confirming stack order stays inert). So
  iteration state is real, domain-shaped, and structurally tame so far
  — and whichever surface is chosen should be evaluated with **early
  exit in the room**: real numeric loops stop *because of* their
  carried state (take-while on term size, retry-until-tolerance), so
  end-when (`tough-use-cases-design.md`) must compose with the
  register/thread designs, and the write half's final-value output and
  a search's readout look like the same port — a unification or a
  coincidence to check. Three shipped witnesses since say unification:
  Zig's `break v` / `else d` pair is exactly the write half's final
  value beside the RanOut discharge, as one expression construct
  (`zig-comparison.md`); purrr's `done(out)` / bare `done()` is the
  same readout as a value inside a fold (`tidyverse-comparison.md`);
  Effekt's `while … else` draws the same end-reason distinction
  (`effekt-comparison.md`). The surveys also put three sightings
  behind the running/history-indexed view of a collect (read-whole,
  read-by-index, read-by-key), worked in
  `variable-rate-consumption-design.md` as the state port of the
  collect's derived augment form — this document's own "second
  accumulator on a sum" mechanism made everyday. If adopted it makes
  the derived augment form load-bearing for ordinary programs —
  pressure on the derived-view machinery, not a thumb on the scale
  between the drawings.
