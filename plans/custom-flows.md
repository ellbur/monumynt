# Custom flows, effect handles, and commutativity

Status: design-only exploration. Related, later work builds on this:
`tough-use-cases-design.md` (custom protocol flows, bracket),
`bundle-provenance-design.md` (open question 4: effect flows and
semantic families), `async-flow-design.md`.

## Two ways to define a custom flow

**1. Algebraic / effect flows (the lifecycle pattern).** An effect flow
is defined by three kinds of operation — creation, use, and destruction:

```
open_database(io, conn_string)  -> (db, io')       -- spelling provisional
query(db, io, sql)              -> (db', io', result)
close_database(db, io)          -> io'
```
-- the `db` flow threads through every operation; you cannot `query`
after `close`, because the closed flow has no wire left to attach to.

The flow exists to enforce operation ordering — no querying a closed
database. The same shape covers databases, file handles, sockets,
transactions: any open/use/close resource. In a chain, the handle rides
a flow wire the way a list iteration does:

```
conn -> open db => ~D            -- spelling provisional
sql, ~D ~> query => rows, ~D2
~D2 ~> close
```
-- opens a database handle, runs one query on it, closes it; the
threaded `~D` flow forbids reordering the query past the close.

**2. Bundling (syntactic sugar).** A named grouping of existing flows
drawn as one wire — for instance a `db_bundle` tying a `db` flow to an
`io` flow — with `unbundle`/`rebundle` for fine-grained access.
Semantically both component flows always exist and thread through
independently; the bundle is only convenience.

Only the atomic flow operations (commute, join) lift automatically to a
bundle. Everything else must go through unbundle/rebundle. Auto-lifting
arbitrary component operations is rejected — deciding what an arbitrary
operation means on a bundle is too complex and too ambiguous.

Naming note: "bundle" here is the *organizational* sense, distinct from
the semantic case-bundle of `bundle-provenance-design.md`, which has
claimed seniority on the word. Renaming the organizational pair
(candidates `Tie`/`Untie`, `Gather`/`Scatter`) is an open question
recorded there.

## The vertical segment

A custom flow is drawn as a vertical segment: creation at the top
vertex, operations attaching along the segment, destruction at the
bottom vertex. The lifecycle is enforced spatially — an operation cannot
attach outside the segment. The pattern generalizes to state machines:
each segment is a state with its valid operations, each vertex a
transition, and multiple outgoing segments a branching state (commit vs
rollback).

Status: `tough-use-cases-design.md` keeps "custom protocol flows" on
probation (one concrete demand so far; watching for a second) and leaves
open whether the lightweight form is a user-defined flow kind or a
catalog block with a derived lowering. **Bracket** (acquire/release
around a region) is the related candidate with many demands, waiting on
cancellation/IO. The lifecycle pattern here is the raw material both
would draw on.

## Structural flows vs effect handles: who may cross

There are two categories of flow, with different crossing rules:

- **Structural flows** (list, tree, any ADT-derived iteration): position
  and order are meaningful. They never cross implicitly; reordering is
  an explicit commute, defined per flow-kind pair
  (`lazy-stream-commute-design.md`).
- **Effect handle flows** (database, IO, file, server): they exist to
  sequence operations on a resource. Independent handles have no
  structural relationship, so their operations commute — they cross
  freely. An explicit commute between two independent handles would be a
  no-op and only clutter the diagram.

Commutativity is **inferred from the definition method**, never
user-annotated — an annotation would only restate what the definition
already shows. Algebraic/effect flows are commutative; ADT-derived flows
are structural; a bundle inherits the most restrictive of its
components, so any structural component makes the whole bundle
structural.

Status: the marker-out-of-sequenceable commute variant (IO out of a
stream — a reordering of timing, not of data) is affirmed as real and
deferred in `lazy-stream-commute-design.md`. Whether an effect construct
can ever produce a semantic family (race-shaped branching on outcomes)
is open question 4 in `bundle-provenance-design.md`.
