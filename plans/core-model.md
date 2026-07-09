# The core model

*Distilled 2026-07-09 from the original design narratives
(`flow_language_design.md`, `visual-flow-language.md`, both since
retired — git history has the full originals). This is the short
statement of the core everything else hinges on, in current
vocabulary. The six principles behind it are in
`language-design-philosophy.md`; read that first.*

## Blocks turned inside out

Traditional languages contain control flow in scoped blocks: the body
of a loop or an if lives *inside* a construct, and what is visible
inside differs from what is visible outside. This language inverts
that. The interior of what would be a block becomes explicit values
and flows wired through the diagram. Control flow is not implicit
containment but explicit wiring; no construct makes an expression's
interior scope differ from its exterior.

The whole static graph is the program. Wires are structural, not
runtime data flowing through boxes: the graph has meaning when
complete, and intermediate wires are symbolic.

## Value wires and flow wires

Every flow context produces two distinct sorts of wire:

- A **value wire** carries data — an element, an alt payload, a
  result. Values are computed on, transformed, wired onward.
- A **flow wire** carries the execution context itself — *when/how
  often does this happen* — and is used only by flow operations
  (collect, join, commute). It cannot be observed as a value.

The separation is load-bearing: it is what lets barriers pass values
through as themselves (the no-bottlenecks principle) and what makes
misuse syntactically impossible (you can't App a flow).

## Uncollect and collect

- **Uncollect** (the code's `Open`) opens a value into a flow: a list
  into a per-element flow, a case-typed value into a bundle of case
  flows, an option into a fires-or-not flow. Out come value port(s)
  and flow port(s).
- **Collect** (the code's `Close`) terminates flows and produces a
  value: a list collect gathers per-element values back into a list;
  a case collect supplies one value per case, exhaustively.

One flow may be collected any number of times (multi-close): each
collect is an independent consumer of the same one logical iteration —
one loop with multiple outputs, not multiple loops. (The implemented
compile realises each collect as its own self-contained thunk;
`lazy-compile-design.md`.)

Terminology note: a 2026-07-07 correction settled uncollect/collect as
the names; the code still says `Open`/`Close`, and older docs and
examples use `$` (uncollect) and `@` (collect) as informal glyphs. The
parseable textual form is `textual-representation-design.md`.

## No time travel

Flow ordering and nesting are established at construction time, never
determined retroactively by later operations. This is the rule that
makes the drawn structure trustworthy.

Its modern, refined form: the rule governs **readings, not gestures**
(`time-travel-programs-design.md`). An author may draw an
under-committed program — sibling uncollects, deferred terminations —
and the elaborator completes it by published rules, shown faint,
compiled by translation only. Every *reading* satisfies no-time-travel
unconditionally.

## Bringing values into flows

A value from outside a flow (a constant, an ancestor value) does not
need transport machinery: provenance's prefix rule admits an ancestor
context's value directly (`bundle-provenance-design.md`). Where an
explicit operator is wanted, **Incorporate** brings a value into a
flow context — a meaningful primitive in its own right. What
Incorporate must *not* be used for is nesting two *sibling* uncollects
into one another: that erases their mutual independence, and the
completion inserts a **Cross** there instead
(`product-flows-design.md`).

## Join, and filtering as join

**Join is a binary flow operation** with asymmetric operands
(outer, inner): it absorbs the inner flow's firings into the outer
flow. Flattening a nested list is join(list, list); keeping the
firing elements of a case alt inside a list iteration —
filtering — is join(list, case flow). The old spelling of join as a
per-collect annotation (`Joined(flowRef)`, still what the code
implements) lost the second operand and is superseded at the design
level (`lazy-stream-join-design.md`).

## Case splits and bundles

Opening a case-typed value produces a **bundle**: a partition of the
parent flow's firings into sibling case flows, exactly one of which
fires per firing of the parent. Sibling flows are mutually exclusive;
they may meet again only at collecting nodes, never at ordinary
combining nodes — the check is bundle provenance
(`bundle-provenance-design.md`). Partial use of a bundle (engaging
only some cells) needs no special open; terminations are handled by
the **partial collect** (`partial-collect-design.md`), whose
exhaustive case collect is the covering instance.

Positional filtering falls out: collecting only some of a
partitioned list flow yields a shorter list (e.g. differentiation —
compute `current − previous` and collect only the positions that have
a previous). What is *not* live from the old story is positional
partitioning as the accumulator mechanism — the initial value belongs
outside the flow, not in a first-position case; loop-carried state is
the register design (`iteration-with-state-design.md`, which records
the rejected `stateful(...)`/`prev(x)` shapes and why).

## Barriers, not bottlenecks

Combining constructs are **barriers with corresponding inputs and
outputs**; wires pass through as themselves.

- Product side: joining two concurrent flows merges the *flow* wires;
  the value wires pass through separately. No tuple is packed to
  cross the join (the original "2D join").
- Sum side: racing two async flows keeps per-contender outputs; no
  tagged union is packed to cross the race
  (`async-flow-design.md`, "Racing is a barrier, not a value" — the
  canonical bottleneck illustration).

## Commute

Reordering nested flows is an explicit operation, defined
per flow-kind pair (`lazy-stream-commute-design.md` maps the
taxonomy; the reconciled node carries flow wires only). Structural
flows never cross implicitly; effect-handle flows commute freely by
nature (`custom-flows.md`). Over a Cross product, commute is
transpose and is always defined (`product-flows-design.md`).

## Flow kinds

The one open/collect shape is instantiated by kind:

| Kind | Opens | Collect yields | Design doc |
|---|---|---|---|
| list | each element, in order | list | implemented; `lazy-compile-design.md` |
| case / option | the matching alt / fires-iff-Some | exhaustive value / option-shaped | implemented |
| stream | each element, on demand | stream | `lazy-stream-*.md` |
| async | the value, later | async | `async-flow-design.md` |
| incremental (var) | the current value, over time | var | `incremental-flow-design.md` |

Failability is a uniform dimension — a terminator payload available to
any kind — not a per-kind bolt-on (`async-flow-design.md`).

## Where the rest lives

- Validity without types: `types-design.md` (properties, demands,
  drawable witnesses), `bundle-provenance-design.md`.
- Loop-carried state: `iteration-with-state-design.md` — the two live
  candidates, still the biggest open area.
- Ports as first-class: `first-class-ports-design.md`.
- Programs as node sets, editing, history: `first-class-ports-design.md`
  ("the program is a node set"), `transformation-levels-design.md`.
- Real-system pressure testing and candidate blocks:
  `tough-use-cases-design.md`.

Rejected and dissolved ideas are recorded in place, in the doc that
owns the topic — each with the reason it must not be pursued again.
