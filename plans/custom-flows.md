# Custom flows, effect handles, and commutativity

Status: design-only exploration — this chapter teaches a design
sketch that has not been adopted or implemented; read it as "here is
the raw material and the case for it." Related, later work builds on
this: `tough-use-cases-design.md` (custom protocol flows, bracket),
`bundle-provenance-design.md` (open question 4: effect flows and
semantic families), `async-flow-design.md`, `effects-design.md` (the
handle threaded across a loop), and `within-firing-effects-design.md`
(ordering within one firing — the vertical-segment sentence below is
that round's whole answer; its handle-as-ordering-commitment leaning
touches this chapter's granularity guidance).

## A flow that isn't iteration

Every flow you have met so far came from opening a value that holds
elements: a list opens into "each element in turn," an option into
"fires or doesn't." Here is a flow that opens something with no
elements at all — a database connection:

```
conn -> open db => ~D            -- spelling provisional
sql, ~D ~> query => rows, ~D2
~D2 ~> close
```

Read it top to bottom: open a database handle, run one query on it,
close it. In a chain, the handle rides a flow wire (`~D`) the way a
list iteration does — but what this wire carries is not repetition.
It is the *open lifetime of a resource*. Each operation consumes the
handle's flow and emits a successor (`~D` in, `~D2` out), and that
threading is the whole point: the threaded `~D` flow forbids
reordering the query past the close. Once `close` has consumed the
flow, there is no wire left for a later `query` to attach to — "you
cannot query a closed database" is not a runtime check but an
unwireable program.

## The first way to define a custom flow: the lifecycle pattern

So what did it take to define the `db` flow? Three kinds of
operation — creation, use, and destruction:

```
open_database  : in io, conn_string    out db, io'      -- spelling provisional
query          : in db, io, sql        out db', io', result
close_database : in db, io             out io'
```

The `db` flow threads through every operation; you cannot `query`
after `close`, because the closed flow has no wire left to attach
to. A flow defined this way is called an **algebraic / effect
flow**, and the flow exists to enforce operation ordering — no
querying a closed database. The same shape covers databases, file
handles, sockets, transactions: any open/use/close resource.

Now, you might wonder why each signature spells its outputs as a
list of separate ports (`out db', io', result`) rather than packing
them into one tuple-shaped result. An earlier draft did spell these
signatures tuple-style, and it read misleadingly as packing — as if
the operation bundled its outputs into a structure you would have to
tear apart. The signatures list ports, not tuples: each output is
its own wire, per the no-bottleneck principle. (The tuple-style
spelling is retired for that reason.)

## Drawing the lifecycle: the vertical segment

Visually, a custom flow is drawn as a vertical segment: creation at
the top vertex, operations attaching along the segment, destruction
at the bottom vertex. The lifecycle is enforced spatially — an
operation cannot attach outside the segment.

The pattern generalizes to state machines: each segment is a state
with its valid operations, each vertex a transition, and multiple
outgoing segments a branching state (commit vs rollback).

Status of this pattern's future: `tough-use-cases-design.md` keeps
"custom protocol flows" on probation (one concrete demand so far;
watching for a second) and leaves open whether the lightweight form
is a user-defined flow kind or a catalog block with a derived
lowering (a translation to a more concrete form that you can read
but not edit). **Bracket** (acquire/release around a region) is the
related candidate with many demands, waiting on cancellation/IO. The
lifecycle pattern here is the raw material both would draw on.
*Bracket's round now exists* (`cancellation-design.md`,
exploration): not a region — this chapter's lifecycle segment plus a
late-wired release half on the acquiring vertex, firing on any end
of the segment including abandonment.

## The second way: bundling flows together

The lifecycle pattern makes a genuinely new flow. The second way to
define a custom flow makes no new flow at all — it just names a
grouping of existing ones. Suppose your database operations always
thread a `db` flow *and* an `io` flow side by side. You can declare
a `db_bundle` that ties the two together and draw it as one wire,
with `unbundle`/`rebundle` for fine-grained access when you need to
reach a component.

This is purely convenience — syntactic sugar. Semantically, both
component flows always exist and thread through independently; the
bundle changes nothing about what the program means, only how many
wires you draw.

Now, you might wonder why the language doesn't lift *every*
operation on a component flow up to the bundle automatically — if a
`db_bundle` contains a `db` flow, why can't `query` attach straight
to the bundle? It turns out this would cause problems: deciding what
an arbitrary operation means on a bundle is too complex and too
ambiguous. Only the atomic flow operations (commute, join) lift
automatically to a bundle. Everything else must go through
unbundle/rebundle. (This is a settled rejection — please don't
re-propose auto-lifting without new evidence.)

A naming note: "bundle" here is the *organizational* sense — a
drawn-together group of wires — distinct from the semantic
case-bundle of `bundle-provenance-design.md`, which has claimed
seniority on the word. Renaming the organizational pair (candidates
`Tie`/`Untie`, `Gather`/`Scatter`) is an open question recorded
there.

## Which flows may cross each other

Put a database handle and a file handle in the same program and a
question appears: may their operations be reordered past each other?
Compare that with two nested list iterations, where reordering
obviously changes what the program means. There are two categories
of flow here, with different crossing rules:

- **Structural flows** (list, tree, any iteration derived from the
  shape of a data type — "ADT-derived"): position and order are
  meaningful. They never cross implicitly; reordering is an explicit
  commute, defined per flow-kind pair
  (`lazy-stream-commute-design.md`).
- **Effect handle flows** (database, IO, file, server): they exist
  to sequence operations *on one resource*. Independent handles have
  no structural relationship to each other, so their operations
  commute — they cross freely. An explicit commute between two
  independent handles would be a no-op and only clutter the diagram.

Now, you might wonder why you can't just *annotate* a flow as
commutative or not, and decide the crossing rule yourself. It turns
out the language never asks you to: commutativity is **inferred from
the definition method** — an annotation would only restate what the
definition already shows. Algebraic/effect flows are commutative;
ADT-derived flows are structural; and a bundle inherits the most
restrictive of its components, so any structural component makes the
whole bundle structural. (User-annotated commutativity is a settled
rejection — the definition method already carries the answer.)

Two loose ends, recorded rather than resolved here: the
marker-out-of-sequenceable commute variant (IO out of a stream — a
reordering of timing, not of data) is affirmed as real and deferred
in `lazy-stream-commute-design.md` — set aside for later, not
rejected. And whether an effect construct can ever produce a
semantic family (race-shaped branching on outcomes) is open
question 4 in `bundle-provenance-design.md` — the language hasn't
decided this yet.
