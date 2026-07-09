# Functions

*Distilled 2026-07-09 from the retired design narrative
(`visual-flow-language.md`, git history). Design-only. Reusable
diagrams also appear at the representation level in
`transformation-levels-design.md` (derived views, principal ports)
and `time-travel-programs-design.md` ("Reuse" — boundary residue);
this doc is the language-level story.*

## What functions are for — and not for

Functions exist for reuse, naming, and modularity. They are **not**
the bodies of map/filter (flows handle element-wise processing), not
first-class values passed around, and not closures capturing scope —
higher-order functions are rejected in favour of configuration scopes
(`configuration-scopes.md`, which records the reason).

## Functions are diagrams with ports

A function is a reusable sub-diagram with labeled connection points.
Ports are not special input/output constructs — just the places where
the sub-diagram joins its surrounding context. Value wires, flow
wires, multiple inputs, multiple outputs: all supported the same way.

Functions interact with flows as naturally as with values: they can
take flows as ports, open flows internally, collect flows passed in,
return flows, or thread a flow through (the `print_string` shape —
an IO flow in, a sequenced IO flow out, ordering preserved by the
threading).

## The interface: a flow skeleton with data holes

A function has two levels of representation:

- **Implementation** — the full diagram, what the author edits.
- **Interface** — what callers see: all **flow operations remain
  transparent**; data operations are hidden.

Keeping flow structure visible through function boundaries is what
preserves no-time-travel guarantees and lets validity checks trace
flow dependencies across calls. Callers see that an IO flow gets
joined, that a value is consumed; they don't see how the value is
formatted.

## Interface summarization

Interfaces can be simplified by proven-sound rewrite patterns:
sequential joins collapse to one join; open-then-immediately-close
cancels; chains of data operations collapse to one hidden hole. Each
pattern is proved semantics-preserving; patterns compose recursively.
The result: a caller of `print_twice` sees one join consuming two
strings, not two internal joins.

> **Status.** The summarization idea reappears, generalised, in
> `types-design.md`: summaries as *generalized programs* with the
> collapse level a free parameter (properties are the substrate,
> generalized programs the display format). If that lands, interface
> summarization is likely its special case at the function boundary.
