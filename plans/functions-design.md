# Functions — reusable sub-diagrams

Status: superseded-and-adopted — the boundary construct this
chapter gestured at is now worked and **adopted** in
`function-boundary-design.md` (2026-07-23), including this
chapter's stances (functions for naming/reuse, not for map/filter
bodies, and not first-class values). Read this chapter as the
motivating sketch; the boundary doc is authoritative.
Functions are a language-level construct; the representation-level
machinery they lean on (derived views, principal ports) lives in
`transformation-levels-design.md`, and what a function's boundary
leaves behind when a call is expanded and edited — its boundary
residue under reuse — is in `time-travel-programs-design.md`
("Reuse"). This doc tells the language-level story.

The boundary construct itself — what a diagram boundary *is*, what a
call is, what is per-call and what is shared — is now worked as its
own round (`function-boundary-design.md`, exploration): a function is
a **remembered cut** through the wiring, not a container; ports are
the wires the cut crosses, membership is derived (a node is per-call
iff downstream of an in-port), and the interface below is the cut's
derived summary. Functions per se are about *reuse* — sameness
across sites; recursion is the divide flow's link, which shares the
cut's substrate while staying its own anonymous construct (that
round's first design conversation settled the separation). Read
that round for the construct; this doc remains the tutorial voice
and the record of the settled rejections below.

## Your first function

Suppose you find yourself doubling numbers in several places, and
you'd like to write the doubling down once, give it a name, and use
it wherever you need it. That is what a function is for. Here is
one:

```
diagram double
  in x
  x -> mul(2) => y
  out result = y
end
```

A function is a **reusable sub-diagram**: a piece of program with
labeled connection points where it joins whatever surrounds it.
Those connection points are called **ports**. `in x` marks a place
where a caller's wire comes in; `out result = y` marks a place
where a wire goes back out. A port is nothing special — not a
dedicated input or output construct — just a place where the
sub-diagram joins its surrounding context.

Calling the function is an ordinary chain stage. A caller wires a
value into `x` and reads `result`:

```
5 -> double => ten                    -- topic wires into `x`; binder reads `result`
"hi", ~io ~> print_string => ~io2     -- a flow port is wired with its sigil, like any flow
```

The value flowing down the chain wires into `x`, and the name after
`=>` reads `result`. (The spelling of both the `diagram … end` form
and the call is provisional; the textual doc keeps calls
deliberately thin until diagrams are the top-level structure.)

## Functions and flows

Value wires and flow wires, one input or many, one output or many:
all are ports, handled the same way. So functions interact with
flows as naturally as with values. A function can take a flow as a
port, open a flow internally, collect a flow passed in, return a
flow, or thread a flow straight through.

The second call above already showed a flow port in use — a flow
port is wired with its `~` sigil, like any flow. Here is the
function behind that call, and with it the *threading* shape:

```
diagram print_string           -- spelling provisional
  in s
  in ~io
  s, ~io ~> put => ~io2
  out ~io2 = ~io2
end
```

An IO flow enters, a sequenced IO flow leaves. The returned `~io2`
carries the sequencing, so callers stay ordered — ordering is
preserved because the flow is threaded rather than dropped and
remade. This `print_string` pattern is the model for any function
that participates in an ordered flow.

## What functions are not for

Functions exist for reuse, naming, and modularity. Deliberately,
they are *not* several things they are in other languages. Two
wonderings are worth settling right away.

Now, you might wonder why the doubling program in `core-model.md` —
double every element of a list — never needed a function to name
"the thing done to each element," the way `map(double, xs)` does in
a functional language. It turns out it never does: element-wise
processing is what flows do. You open a list, transform each
element, collect. Functions are **not the bodies of map/filter**;
no function is needed to name the per-element work, because the
per-element work is simply the wiring between the open and the
collect. (This is a settled decision — flows, not functions, own
element-wise processing; please don't re-propose function-bodied
map/filter without new evidence.)

And you might wonder why you can't pass a function around *as a
value* — the comparator handed to a sort, the callback handed to a
server, a function stored in a variable and called later. It turns
out this would cause problems: a function waiting to be called has
no honest visual form. Functions are **not first-class values**
passed around, and **not closures** capturing scope. Higher-order
functions are rejected in favour of *configuration scopes*: instead
of passing the would-be lambda, you open the operation as a scope
and wire the computation into it. The full reason is recorded in
`configuration-scopes.md`. (This is a settled rejection — please
don't re-propose first-class functions without new evidence.)

## What a caller sees: a flow skeleton with data holes

When you call `double`, do you see the `mul(2)` inside? The design
says: a function has two levels of representation.

- **Implementation** — the full diagram, what the author edits.
- **Interface** — what a caller sees. Flow operations stay
  transparent; data operations are hidden as holes.

So a caller of a function sees its *flow skeleton* — which flows
enter, how they are joined or opened or collected — with the data
computations abstracted to holes. A caller sees that an IO flow
gets joined and that a value is consumed; it does not see how that
value was formatted.

A third thing survives on the interface beside the skeleton and the
holes: the function's **open operation pairs** — operations it uses
but does not define (`late-bound-operations-design.md`). A caller
either binds each pair (wires a provider on) or leaves it open, in
which case the demand projects onto the caller's own boundary.

Keeping flow structure visible through a function boundary is
load-bearing, not a display nicety. It is what preserves the
no-time-travel guarantee across calls, and what lets validity
checks trace flow dependencies from caller into callee.

## Interface summarization

An interface can be simplified by rewrite patterns, each proved to
preserve the program's meaning:

- sequential joins collapse to one join;
- open-then-immediately-close cancels;
- a chain of data operations collapses to a single hidden hole.

The patterns compose recursively, so an interface reduces to its
essential flow skeleton. A caller of `print_twice` — which
internally formats and prints two strings — sees one join consuming
two strings, not the two internal joins with formatting between
them.

Status: this summarization idea reappears, generalised, in
`types-design.md` as *generalized programs* — summaries whose
collapse level is a free parameter (properties are the substrate,
generalized programs the display format). If that lands, interface
summarization is likely its special case at the function boundary.
