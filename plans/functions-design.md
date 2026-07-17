# Functions

Status: design-only exploration. Functions are a language-level
construct; the representation-level machinery they lean on (derived
views, principal ports) lives in `transformation-levels-design.md`, and
their boundary residue under reuse in `time-travel-programs-design.md`
("Reuse"). This doc tells the language-level story.

## What functions are for — and not for

Functions exist for reuse, naming, and modularity. Deliberately, they
are *not* several things they are in other languages:

- **Not the bodies of map/filter.** Element-wise processing is what
  flows do: you open a list, transform each element, collect. No
  function is needed to name "the thing done to each element."
- **Not first-class values** passed around, and **not closures**
  capturing scope. Higher-order functions are rejected in favour of
  configuration scopes — a function waiting to be called has no honest
  visual form. The reason is recorded in `configuration-scopes.md`.

## Functions are diagrams with ports

A function is a reusable sub-diagram with labeled connection points. A
port is nothing special — not a dedicated input or output construct —
just a place where the sub-diagram joins its surrounding context. Value
wires and flow wires, one input or many, one output or many: all are
ports, handled the same way.

```
diagram double
  in x
  x -> mul(2) => y
  out result = y
end
```
-- a one-input, one-output function; a caller wires a value into `x`
and reads `result`. The call is an ordinary chain stage (spelling
provisional; the textual doc keeps calls deliberately thin until
diagrams are the top-level structure):

```
5 -> double => ten                    -- topic wires into `x`; binder reads `result`
"hi", ~io ~> print_string => ~io2     -- a flow port is wired with its sigil, like any flow
```

Functions interact with flows as naturally as with values. A function
can take a flow as a port, open a flow internally, collect a flow passed
in, return a flow, or thread a flow straight through. The threading
shape is the `print_string` pattern: an IO flow enters, a sequenced IO
flow leaves, and ordering is preserved because the flow is threaded
rather than dropped and remade.

```
diagram print_string           -- spelling provisional
  in s
  in ~io
  s, ~io ~> put => ~io2
  out ~io2 = ~io2
end
```
-- IO flow in, IO flow out; the returned `~io2` carries the sequencing,
so callers stay ordered.

## The interface: a flow skeleton with data holes

A function has two levels of representation:

- **Implementation** — the full diagram, what the author edits.
- **Interface** — what a caller sees. Flow operations stay transparent;
  data operations are hidden as holes.

Keeping flow structure visible through a function boundary is
load-bearing. It is what preserves the no-time-travel guarantee across
calls, and what lets validity checks trace flow dependencies from caller
into callee. A caller sees that an IO flow gets joined and that a value
is consumed; it does not see how that value was formatted.

## Interface summarization

An interface can be simplified by rewrite patterns, each proved
semantics-preserving:

- sequential joins collapse to one join;
- open-then-immediately-close cancels;
- a chain of data operations collapses to a single hidden hole.

The patterns compose recursively, so an interface reduces to its
essential flow skeleton. A caller of `print_twice` — which internally
formats and prints two strings — sees one join consuming two strings,
not the two internal joins with formatting between them.

Status: this summarization idea reappears, generalised, in
`types-design.md` as *generalized programs* — summaries whose collapse
level is a free parameter (properties are the substrate, generalized
programs the display format). If that lands, interface summarization is
likely its special case at the function boundary.
