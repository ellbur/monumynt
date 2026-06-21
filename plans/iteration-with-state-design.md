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

## What is still unresolved

This is a work in progress. The following are areas that need further
critique before the primitive can be considered settled:

**The primitive form.** We've identified what the primitive must
accomplish — introduce a carried value, attach an initial value from
outside the flow, express the first/subsequent split at the flow level,
allow independent per-variable handling. We haven't settled on a
concrete syntactic or structural form. The candidates so far have all
been rejected. The right form is still open.

**The sub-close mechanic.** Closing the initial and step cases ends
the first/subsequent split without closing the outer flow. The language
currently has no construct that does this. Whether this is a new close
variant, a generalization of the existing close, or something else
entirely is unresolved. This is probably the hardest piece.

**Non-homogeneous iteration as a separate problem.** The critique of
`prev(x)` surfaced a related but distinct issue: what if different
iterations genuinely behave differently (not just first vs. subsequent,
but conditionally different at each step)? This is the "non-homogeneous
iteration" problem. It's been explicitly set aside as a separate
question and isn't part of the stateful iteration primitive — but it's
worth naming so it doesn't get conflated.

**Whether the first/subsequent split is always user-visible.** Under
the current direction, the first-vs-subsequent distinction is expressed
as a structural case split in the flow. But it's possible that for many
accumulators, the user never needs to inspect that split at all — the
iteration mechanism could handle it invisibly, with the carried value
just being "available" on all iterations (the initial on the first, the
carried on subsequent). Whether to expose the split explicitly or
provide it transparently as a language mechanism is unresolved and
probably depends on what the sub-close mechanic looks like.

**Multiple carried variables.** The design must support two independent
carried variables in one flow without a tuple bottleneck. This should
fall out naturally if the primitive form is right — but it hasn't been
demonstrated with a concrete worked example yet. Testing the candidate
primitive (once one exists) against "running sum and running max in one
loop" is a good critique target.

**Self-reference and cycles.** A carried variable that depends on its
own previous value is a backward edge in the expression graph. The rest
of the language has no cycles. The carried-variable primitive introduces
them in a controlled way — but the exact scope of what's allowed, and
how it interacts with the compiler's memoisation/laziness model, hasn't
been thought through.
