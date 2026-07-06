# Bundle Provenance

> Starting-point document (2026-07-06), companion to
> `types-design.md`, which deferred this as its open question 5
> ("Sibling design, not this one"). The subject is the oldest open
> checking problem in the design record —
> `flow_language_design.md`'s Future Work #2, "Flow Bundle Type
> Checking" — with a partial answer to its #3 ("General Flow
> Bundle Semantics") falling out along the way. Nothing here is
> implemented.

## The problem

flow_language_design.md, Future Work #2, in full:

> **Challenge:** Prevent invalid mixing of flows from the same
> conditional bundle while allowing valid nesting of flows from
> different bundles.

with three open questions attached: how to track bundle
relationships through operations, what type system can express
the constraints, and how to give clear error messages.

Restated in current vocabulary, and with the third rule the
original left implicit, there are three behaviors to reconcile:

1. **Sibling flows of one case split must not be mixed.** A value
   available on the Just alt of a split and a value available on
   the Nothing alt of the *same* split never coexist: no
   execution produces both. An App combining them is ill-formed —
   and today the compiler does with it exactly what it does with
   time travel: `deeper(a, b)` silently picks one of the two alt
   scopes and emits JS whose meaning is an accident of the depth
   comparison.

2. **Flows from different splits nest freely.** A case split
   inside a case split (the nested `Maybe<Either<…>>` test), a
   split inside a list iteration, an iteration inside an alt —
   all fine and all tested. A rule that merely forbade "two case
   flows meeting in one expression" would ban working programs.

3. **Sibling flows must eventually meet — through exactly one
   door.** The exhaustive case Collect takes one value per alt
   and is the sanctioned reconvergence; the filter close consumes
   one alt alone and lifts it into an enclosing iteration. So the
   check cannot be "sibling contexts never interact"; it is
   "sibling contexts interact only at collecting nodes, never at
   ordinary combining nodes."

The check that enforces 1 without breaking 2 and 3 needs to know,
for any two flow contexts, whether they are nested, unrelated, or
siblings of one bundle — which is to say it needs provenance.

## One word, two concepts

The design record uses "bundle" in two unrelated senses, and the
collision is already latent between two current documents:

- **The semantic family.** flow_language_design's conditional
  bundle: the set of mutually exclusive case flows created by one
  branching construct, "sets of flows that must be closed
  together." `visual-layout-guidelines.md` glosses the same
  sense: *"Bundle: Related flows from a single operation. For
  example, a case split produces a bundle of case flows (one per
  case). These are mutually exclusive execution contexts. These
  flows are collected (not joined) when the branches
  reconverge."*
- **The wiring convenience.** The spec's `Bundle`/`Unbundle`
  nodes and `visual-flow-language.md`'s bundled flows: several
  flows carried on one wire for organizational tidiness,
  explicitly "syntactic sugar," unbundled back into the same
  flows they were.

This document uses "bundle" exclusively in the first sense, which
has seniority. The two are not just distinct but orthogonal: for
provenance purposes the `Bundle`/`Unbundle` node pair is pure
transport (whatever facts the constituent flows carry pass
through unchanged), and bundling flows together never creates a
semantic family. Whether the node pair should be renamed to clear
the word (`Tie`/`Untie`, `Gather`/`Scatter`) is the spec's
business; recorded as an open question.

## What creates a bundle

Method as in the types document: sample the constructs the design
record actually contains, and let the definition emerge from the
samples rather than the other way around.

| Construct                      | Siblings                     | Exactly one fires per…      | Sanctioned reconvergence            |
|--------------------------------|------------------------------|-----------------------------|--------------------------------------|
| Uncollect CaseSplit            | one flow per alt             | dispatch of the input value | exhaustive case Collect; filter close |
| IterationCaseSplit             | one flow per case of a split | position of the iteration   | per-case use, collected on reconvergence |
| Race barrier (async design)    | one flow per contender       | settlement of the race      | exhaustive close over all contenders |
| Partial branch / partial close | merged sub-branches          | dispatch (coarsened)        | the merge algebra — open, see below  |

Notes on the rows:

- **Uncollect CaseSplit** is the paradigm case and the only one
  in the repo today (`Open CaseSplit` + `Branch` in `Expr.res`).
- **IterationCaseSplit** shows the concept is not about
  alternative *data*: initial-vs-step and last-vs-non-last are
  splits of an iteration flow by structural position, and a value
  available only on the `initial` case never coexists with one
  available only on the `step` case at the same position. Same
  discipline, no discriminator function anywhere.
- **The race barrier** shows the concept is not about *now*: the
  contenders' output flows are "a bundle that must be closed
  together, exhaustively — exactly the discipline of an opened
  case split" (`async-flow-design.md`). Mixing two contenders'
  values is ill-formed for the same reason as mixing two alts':
  exactly one of them ever fires.
- **Partial opens already exist in degenerate form.** The repo's
  `OptionIter` is flow_language_design's `PARTIAL_BRANCH`: it
  opens only the Some cell of a two-cell family. The unopened
  cell contributes no wire and no value, which is exactly why
  closes over it produce the zero-or-one lift (`let out;` /
  push-if-fired) the compiler already implements. A partial open
  is not outside the bundle concept; it is a bundle with
  unopened cells.

And what is *not* a bundle:

- **The concurrent join.** Its inner flows all continue together
  into one merged context — one output flow in the spec, not a
  family. It is the product barrier; bundles are sum-shaped.
- **Multiple closes on one flow.** Two closes on one list open
  consume the *same* context twice; there are no siblings.
- **`Bundle`/`Unbundle` nodes**, per the terminology section.

The definition the samples converge on:

> **A bundle is a partition of a parent flow's firings.** A
> bundle-creating construct sits in some context and divides each
> firing of that context among its output flows: every firing
> lands in exactly one cell.

Exclusivity is definitional, not incidental — each row of the
table is a partition (by discriminated tag, by structural
position, by first settlement). Exhaustiveness is a property of
*uses*, not of the bundle: the partition always covers, but a
program may open or close only some cells (partial opens, filter
closes), accepting a zero-or-one lift for the cells it engages.

This is the partial answer to Future Work #3's "what other bundle
types exist?": every bundle in the record is exclusive, because
being a partition is what makes something a bundle. Nothing in
the record demands a second bundle kind, and by example-first no
second kind should be designed until a construct produces one.

## The property: context paths

`types-design.md` already assigned this check its substrate. Its
property inventory contains the row

    flow-context chain | demanded by any multi-input combining
    node | offered by opens (the context each creates)

and its "smallest first step" makes flow-context alignment — the
time-travel check — the first property to implement. Bundle
provenance is not a second check beside that one. It is the same
check with the property refined.

**The refinement.** The contexts of a program form a tree: the
root is the top-level once-context; each open creates one child
of the context its input lives in; each bundle-creating construct
creates N sibling children, one per cell, marked as cells of that
construct. The property a value wire carries is its **context
path** — the chain of (construct, output) steps from the root to
the context the value lives in. Every step is a visible node and
port; the path is read off the diagram, never declared. (The
compiler already materializes exactly this tree: `scopeRef`'s
`parent` chain, with `CaseDispatch.altScopes` as the sibling
cells. The path is not a new artifact; it is a name for one the
compile pipeline grew on its own.)

**Offers, demands, transport** follow the value-side pattern:

- Opens and bundle constructs *offer* extended paths on their
  per-context outputs (a `Branch` value port offers the parent
  path extended by its (dispatch, alt) cell).
- Ordinary combining nodes *demand comparability*: all operands'
  paths lie on one root-to-leaf line, i.e. each is a prefix of
  the deepest. The result lives at the deepest path — which is
  what `deeper` already computes, minus the verification.
- Structural nodes *transport*: capture stamps the captured
  constant with the flow's path; join removes the inner segment
  (the joined output lives in the outer context); commute
  permutes adjacent iteration segments; Delay's `prev` carries
  the path of the flow it is tied to; `Bundle`/`Unbundle` pass
  paths through untouched.
- Collecting nodes are the one place sibling paths may meet, and
  their demand is stated below.

**One check, two clash flavors.** When comparability fails, walk
the two paths to their last common context and look at the first
divergent pair of steps:

- Both steps are cells of one bundle construct → **bundle
  mixing**: "these two values live in mutually exclusive cases
  Just / Nothing of this one case split; no execution produces
  both." The witness is the shared construct plus the two cell
  edges — two anchors and a drawable connector, per the
  witness requirement.
- Anything else (two independent opens) → **time travel**: two
  sibling contexts with no correspondence between their firings.
  The witness is the two opens.

Both are clashes in the types document's sense — *this cannot
mean anything*, reportable even in a partial diagram — as opposed
to unmet demands, which at a schematic source are just the edge
of construction. Note the difference in *why* each is wrong: two
independent list opens' elements all coexist at runtime but have
no canonical pairing; two sibling cells' values have a perfectly
canonical pairing and never coexist. One diagnostic would blur
that; two flavors keep each explanation honest.

**"Relational" dissolves into per-wire facts.** The types
document called this check relational ("these two flows came from
the same bundle") and flagged that as a possible point of
difference from the value-side machinery. With context paths it
isn't one: the stored property is unary — each wire carries its
own path — and the same-bundle relation is *computed* at
demand-check time by comparing paths, exactly as chain
comparability already is. Relations appear only in comparisons
and witnesses, never in the store. The propagation skeleton is
identical to the value side's: monotone, no choice points, no new
machinery class. That answers Future Work #2's "what type system
can express these constraints?" — none beyond the property layer
already designed.

**The collecting-node demand.** A case Collect's branches map
alts to (value, flow) pairs. Its demand, in path terms:

- the branch flows are exactly the cells of one bundle, covering
  it (this is the existing alt-matching quotient check, restated
  — the repo's `consumeCaseClose` already validates same-dispatch
  and coverage);
- each branch's *value* path is a prefix of (or equal to) its
  cell's path — the value lives in that cell or an ancestor
  context, never a sibling and never something deeper that
  hasn't been closed.

The collect's output lives at the bundle's parent path. The
filter close is the partial version: one cell, value path a
prefix of the cell's, output lifted to an enclosing iteration
context with the zero-or-one accounting the compiler already
does. So the door through which siblings meet (behavior 3) is not
an exception to the mixing rule; it is a different demand, on a
different node kind, checked by the same path comparisons.

## What the check must allow: worked cases

Each of these is a live pattern (tested in the repo or designed
in the record), annotated with the path relation that admits it.

1. **Ancestor value used in sibling cells.** The shared-`bonus`
   test: a literal at the root context is added to `justB` inside
   the Just alt and used alone in the Nothing alt. Root path is a
   prefix of each alt path — comparable in both uses; each
   combination lives in its alt. The memo sharing one binding
   across sibling alt scopes is untouched.

2. **Nested splits.** `Maybe<Either<…>>`: the inner dispatch
   lives inside the outer's Just cell, so inner alt paths extend
   the outer alt path — ancestor/descendant throughout, never
   sibling cells of one construct.

3. **Partition.** The evens/odds two-filter-close test: each
   close consumes one cell separately; no ordinary combining node
   ever sees two cells; the two output lists live at the loop's
   parent. Nothing to forbid.

4. **Case close + filter close on one dispatch.** The mixing
   test: both are collecting nodes on the same bundle, one
   exhaustive and one partial. Collecting demands are per-node;
   they don't conflict.

5. **What must clash.** `app(f, [justVal, nothingVal])` on one
   dispatch — sibling cells, no collecting node: bundle-mixing
   clash, witness = the dispatch plus its Just and Nothing
   edges. The same shape with a race's two contender values, or
   with `initial`-case and `step`-case values of one
   IterationCaseSplit, clashes identically — one rule covering a
   data split, a timing split, and a structural-position split is
   the payoff of defining bundles by partition rather than by
   alternative types.

## Sketch: merged branches as cell sets

Future Work #4 — the algebra of partial conditional merging —
is its own design round, not this one, but the path
representation suggests a base for it, recorded here as a sketch.

Let a bundle step in a path carry a *set* of cells rather than a
single cell: an ordinary `Branch` flow carries a singleton
`{Just}`; a partial close merging alts A and B of a three-way
split produces a flow carrying `{A, B}`; the parent context is
the degenerate full set. A value whose bundle step is S exists at
a firing iff the fired cell is in S. Then:

- **Comparability at the bundle step is containment.** S ⊆ T or
  T ⊆ S: combinable, and the combination lives at the smaller
  set (both values exist exactly when the fired cell is in it).
  This makes the old doc's "merged branch acts as a parent scope
  for its constituents" a theorem: `{A} ⊆ {A, B}`, so AB-context
  values are usable inside A. Disjoint sets never coexist —
  bundle mixing, as before, with singletons as the special case.
- **Partial overlap is a clash, not a narrowing.** `{A, B}` meets
  `{B, C}`: the combination would be meaningful exactly when B
  fires, but silently narrowing to the intersection is inference
  choosing a meaning — explicit-over-implicit says that
  coarsening and narrowing across cells happen only at explicit
  nodes (a collect, a partial close), never by the checker's
  arithmetic.
- **The exhaustive collect generalizes for free**: branch cell
  sets must be pairwise disjoint and cover the bundle. Alt
  matching is the all-singletons instance.

What keeps this a sketch: the partial close's own semantics have
multiple candidates in the old document ("Monadic: unopened
branch values pass through unchanged; Nothing: …"), and until one
is chosen there is no construct for the cell sets to describe.
The sketch's claim is only that when that round happens, the
provenance side is ready for it — containment on cell sets, not
new machinery.

## Fit with the compiler: sharpening the smallest first step

`types-design.md`'s smallest first step is flow-context
alignment: check that an App's args' scopes form a chain, with a
real error naming the two offending opens, instead of `deeper`
silently picking. This document adds one clause to that same
step, at almost no cost:

- `scopeRef` needs to know what it is a scope *of* — an `origin`
  field (the open, or the (dispatch, alt) cell) set where scopes
  are allocated. The parent chain then *is* the context path.
- On a failed chain check, walk both scopes to their least
  common ancestor. If the two divergent children are alt scopes
  of one `CaseDispatch`, report bundle mixing (naming the
  dispatch and the two alts); otherwise report time travel
  (naming the two opens).
- The collect-side demands are already enforced:
  `consumeCaseClose` validates same-dispatch and alt coverage
  today. Nothing new to build there; the reframing just names
  which family the existing validation belongs to.

Testable in `Main.res` style as expect-a-clash tests: build the
`justVal`/`nothingVal` mixing App, assert the compile reports the
dispatch and both alt names. The race and IterationCaseSplit rows
of the inventory wait for their constructs; the check meets them
with no changes, since it never looks at *why* a construct
partitions — only that its scopes are marked as sibling cells.

## Philosophy check

- **Example first.** The inventory is sampled from constructs the
  record already contains; the partition definition is read off
  the samples; the cell-set sketch waits for its construct.
- **Derived, never adds.** Paths are read off visible nodes and
  wiring — no annotation, no artifact to keep in sync. A reader
  who knows what each node is could reconstruct every path.
- **No search.** Prefix and containment comparisons; monotone
  propagation; no choice points. Within the solver's remit as
  the types document scoped it.
- **No error without a witness.** Both clash flavors carry two
  anchors and a wire path; the bundle-mixing caption names the
  one shared construct. This is the "how to give clear error
  messages?" answer Future Work #2 asked for in the same breath
  as the check.
- **Checks, not construction.** You can draw the mixing; the
  check tells you what it means. Example-first authoring and
  partial diagrams are untouched.
- **Explicit over implicit.** Movement between cells happens
  only at explicit collecting nodes; the checker never coarsens,
  narrows, or picks.

## Open questions

1. **The partial-merge round.** Choose the partial close's
   semantics (the old document's "multiple possible semantics"),
   then test the cell-set sketch against it — including whether
   the unopened cells of a partial *open* need to be nameable in
   paths (the README's `PARTIAL_BRANCH` next-step is the same
   question from the representation side).
2. **The `Bundle`/`Unbundle` name.** Whether the spec's
   organizational node pair should be renamed to leave "bundle"
   unambiguous for the semantic family. Cosmetic but worth doing
   before the word appears in error messages.
3. **Commuting past a case segment.** Commute permutes adjacent
   *iteration* segments of a path. Whether a case segment can
   ever participate (commuting a dispatch out of a loop?) — the
   wrapper-stack shape discipline likely already forbids it, but
   the interaction should be stated rather than assumed when
   stream flows land.
4. **Effect flows.** The spec lets effect flows be "bundled and
   joined like other flows" — in the organizational sense. If an
   effect construct ever produces a semantic family (branching on
   an effect's outcome looks race-shaped), it should land in the
   inventory table; until then effect flows carry paths like any
   other flow.
5. **Clash reporting surface.** How a compile-time clash is
   represented in the repo's test runner (a result variant? a
   raised exception with structured payload?) — small, but it is
   the first error whose *content* (two anchors, a path) matters
   to a test, so it sets the pattern the value-side clashes of
   the types document's step 2 will follow.
