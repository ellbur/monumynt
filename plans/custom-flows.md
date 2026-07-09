# Custom flows, effect handles, and commutativity

*Distilled 2026-07-09 from the retired design narrative
(`visual-flow-language.md`, git history). Design-only. Later rounds
that bear on this: `tough-use-cases-design.md` (custom protocol
flows, bracket), `bundle-provenance-design.md` (open question 4:
effect flows and semantic families), `async-flow-design.md`.*

## Two ways to define a custom flow

**1. Algebraic / effect flows (lifecycle pattern).** Defined by
creation, operations, and destruction:

```
open_database(io, conn_string) → (db_flow, io')
query(db_flow, io, sql)        → (db_flow', io', result)
close_database(db_flow, io)    → io'
```

The flow exists to enforce operation ordering (no querying a closed
database). Used for databases, file handles, sockets, transactions —
any open/use/close resource.

**2. Bundling (syntactic sugar).** A named grouping of existing flows
(e.g. `db_bundle = (db_flow, io_flow)`), drawn as one wire, with
`unbundle`/`rebundle` for fine-grained access. Semantically both
component flows always exist and thread through; the bundle is
convenience. Note the word "bundle" here is the *organizational*
sense — distinct from the semantic case-bundle of
`bundle-provenance-design.md`, which has claimed seniority on the
word; renaming the organizational pair (`Tie`/`Untie`,
`Gather`/`Scatter`) is an open question there.

Only atomic flow operations (commute, join) lift automatically to a
bundle; everything else goes through unbundle/rebundle — auto-lifting
arbitrary component operations is rejected as too complex and too
ambiguous (`rejected-ideas.md` entry 86).

## The vertical segment

A custom flow is drawn as a vertical segment: creation at the top
vertex, operations attaching along the segment, destruction at the
bottom vertex. The lifecycle is enforced spatially — an operation
cannot attach outside the segment. The pattern generalizes to state
machines: each segment is a state with its valid operations, each
vertex a transition, multiple outgoing segments a branching state
(commit vs rollback).

> **Status.** `tough-use-cases-design.md` keeps "custom protocol
> flows" on probation (one demand; "watch for a second") and leaves
> open whether the lightweight form is a user-defined flow kind or a
> catalog block with a derived lowering. **Bracket** (acquire/release
> around a region) is the related candidate with many demands,
> waiting on cancellation/IO. This doc's lifecycle pattern is the
> raw material both would draw on.

## Structural flows vs effect handles: who may cross

Two categories of flow, with different crossing rules:

- **Structural flows** (list, tree, any ADT-derived iteration):
  position and order are meaningful. They never cross implicitly;
  reordering is an explicit commute, defined per flow-kind pair
  (`lazy-stream-commute-design.md`).
- **Effect handle flows** (database, IO, file, server): they exist to
  sequence operations on a resource; independent handles have no
  structural relationship, so their operations commute. They cross
  freely — an explicit commute between independent handles would be a
  no-op and clutter.

Commutativity is **inferred from the definition method**, never
user-annotated (`rejected-ideas.md` entry 85): algebraic/effect
flows are commutative; ADT-derived flows are structural; bundles
inherit the most restrictive component (any structural component
makes the bundle structural).

> **Status.** The marker-out-of-sequenceable commute variant (IO out
> of a stream — timing, not data) is affirmed as real and deferred in
> `lazy-stream-commute-design.md`; whether an effect construct ever
> produces a semantic family (race-shaped branching on outcomes) is
> `bundle-provenance-design.md` open question 4.
