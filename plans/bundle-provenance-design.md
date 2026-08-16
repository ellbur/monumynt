# Bundle Provenance — values that can never meet

Status: mixed — **2026-08-12 update**: the core mechanism is live.
`Context.res` computes cell-set context paths and the containment
theorem; `Check.res`'s alignment rule does exactly this chapter's "One
check, two clash flavors" — the mixing-vs-time-travel classification —
below (see `src/ARCHITECTURE.md`'s Context/Check rows). Companion to
`types-design.md`, which deferred this as its open question 5; what
remains a worked proposal rather than landed code is partial overlap
(`{A,B}` vs `{B,C}` meeting at `{B}`) beyond the constructed meet —
that is the poset round's. The subject is the oldest open checking
problem in the design record:
preventing invalid mixing of flows from one conditional bundle while
allowing valid nesting of flows from different bundles. The code
samples use the textual syntax of
`textual-representation-design.md`; "close" means collect.

## Two values that can never meet

Here is a program that cannot mean anything:

```
m -> split isJust of Just, Nothing => cs
cs.Just, cs.Nothing -> add          -- CLASH (behavior 1): Just and Nothing
                                    --   never coexist; no value to add
```

The split sends each value of `m` down exactly one of its two cases.
A value available on the Just alt and a value available on the
Nothing alt of the *same* split never coexist: no execution produces
both. So there is nothing for `add` to add — the program is
ill-formed.

And here is the valid way for the two sides to meet again:

```
m -> split isJust of Just, Nothing
  Just:    -> double
  Nothing: 0
-~> collect => out                  -- OK (behavior 3): the one door — an
                                    --   exhaustive collect, one value per alt
```

The collect takes one value per alt and produces a single value
whichever case fired. That is the sanctioned reconvergence — the one
door through which sibling cases meet.

What does the compiler do with the ill-formed program today? Exactly
what it does with time travel: `deeper(a, b)` silently picks one of
the two alt scopes and emits JS whose meaning is an accident of the
depth comparison. This chapter designs the check that catches it
instead.

## Three things the check must get right

The checking problem, stated plainly:

> Prevent invalid mixing of flows from the same conditional bundle
> while allowing valid nesting of flows from different bundles.

Three behaviors have to be reconciled.

1. **Sibling flows of one case split must not be mixed.** That is
   the opening example: a value on the Just alt and a value on the
   Nothing alt of the *same* split never coexist, so an App
   combining them is ill-formed.

2. **Flows from different splits nest freely.** Now, you might
   wonder why the check can't simply be "two case flows never meet
   in one expression." It turns out that rule would ban working
   programs: a case split inside a case split (the nested
   `Maybe<Either<…>>` test), a split inside a list iteration, an
   iteration inside an alt — all fine, all tested. (A rule that
   merely forbade "two case flows meeting in one expression" is
   rejected for exactly this reason — don't re-propose it.)

3. **Sibling flows must eventually meet — through exactly one
   door.** The exhaustive case Collect takes one value per alt and
   is the sanctioned reconvergence; the filter close consumes one
   alt alone and lifts it into an enclosing iteration. So the check
   is not "sibling contexts never interact"; it is "sibling contexts
   interact only at collecting nodes, never at ordinary combining
   nodes."

The check that enforces 1 without breaking 2 and 3 needs to know,
for any two flow contexts, whether they are nested, unrelated, or
siblings of one bundle — which is to say it needs provenance: where
each value came from.

## What makes a bundle

The set of mutually exclusive sibling flows a split creates — the
Just flow and the Nothing flow together — is called a **bundle**.
Before pinning the word down, how many constructs create one? Method
as in `types-design.md`: sample the constructs the record actually
contains, and let the definition emerge from the samples.

| Construct                      | Siblings                     | Exactly one fires per…      | Sanctioned reconvergence            |
|--------------------------------|------------------------------|-----------------------------|--------------------------------------|
| Uncollect CaseSplit            | one flow per alt             | dispatch of the input value | exhaustive case Collect; filter close |
| IterationCaseSplit             | one flow per case of a split | position of the iteration   | per-case use, collected on reconvergence |
| Race barrier                   | one flow per contender       | settlement of the race      | exhaustive close over all contenders |
| Partial branch / partial close | merged sub-branches          | dispatch (coarsened)        | the merge algebra — open, see below  |

Notes on the rows:

- **Uncollect CaseSplit** is the paradigm case and the only one in
  the repo today (`Open CaseSplit` + `Branch` in `Expr.res`).
- **IterationCaseSplit** shows the concept is not about alternative
  *data*: initial-vs-step and last-vs-non-last are splits of an
  iteration flow by structural position, and a value available only
  on the `initial` case never coexists with one on the `step` case
  at the same position. Same discipline, no discriminator function
  anywhere.
- **The race barrier** shows the concept is not about *now*: the
  contenders' output flows are a bundle that must be closed
  together, exhaustively — the discipline of an opened case split
  (`async-flow-design.md`). Mixing two contenders' values is
  ill-formed for the same reason as mixing two alts': exactly one
  ever fires.
- **Partial opens already exist in degenerate form.** The repo's
  `OptionIter` opens only the Some cell of a two-cell family. The
  unopened cell contributes no wire and no value, which is exactly
  why closes over it produce the zero-or-one lift (`let out;` /
  push-if-fired) the compiler already implements. A partial open is
  not outside the bundle concept; it is a bundle with unopened
  cells.

And some things you might expect to be bundles, but aren't:

- **The concurrent join.** Its inner flows all continue together
  into one merged context — one output flow, not a family. It is
  the product barrier; bundles are sum-shaped.
- **Multiple closes on one flow.** Two closes on one list open
  consume the *same* context twice; there are no siblings.
- **`Bundle`/`Unbundle` nodes** — but that needs its own note; see
  "One word, two concepts" just below.

The definition the samples converge on:

> **A bundle is a partition of a parent flow's firings.** A
> bundle-creating construct sits in some context and divides each
> firing of that context among its output flows: every firing lands
> in exactly one cell.

Exclusivity is definitional, not incidental — each row of the table
is a partition (by discriminated tag, by structural position, by
first settlement). Exhaustiveness is a property of *uses*, not of
the bundle: the partition always covers, but a program may open or
close only some cells (partial opens, filter closes), accepting a
zero-or-one lift for the cells it engages.

So every bundle in the record is exclusive, because being a
partition is what makes something a bundle. You might wonder whether
the language needs a second, non-exclusive bundle kind. Nothing in
the record demands one, and by example-first no second kind should
be designed until a construct produces one — this is a "not yet,"
not a rejection.

### One word, two concepts

The design record uses "bundle" in two unrelated senses, and the
collision is latent in the current documents:

- **The semantic family.** A conditional bundle: the set of mutually
  exclusive case flows created by one branching construct — sets of
  flows that must be closed together. `core-model.md` ("Case splits
  and bundles") owns the concept: opening a case-typed value
  partitions the parent flow's firings into sibling case flows,
  exactly one firing per firing of the parent, mutually exclusive,
  meeting again only at collecting nodes.
- **The wiring convenience.** The spec's `Bundle`/`Unbundle` nodes:
  several flows carried on one wire for organizational tidiness,
  explicitly syntactic sugar, unbundled back into the same flows
  they were.

This chapter uses "bundle" exclusively in the first sense, which has
seniority. The two are independent: for provenance purposes the
`Bundle`/`Unbundle` pair is pure transport (whatever facts the
constituent flows carry pass through unchanged), and bundling flows
together never creates a semantic family. Whether the node pair
should be renamed to clear the word (`Tie`/`Untie`,
`Gather`/`Scatter`) is the spec's business, recorded as an open
question.

## The property: where did this value come from?

`types-design.md` already assigned this check its substrate — its
property inventory carries the row

    flow-context chain | demanded by any multi-input combining node
                       | offered by opens (the context each creates)

and its smallest first step makes flow-context alignment (the
time-travel check) the first property to implement. Bundle
provenance is not a second check beside that one. It is the same
check with the property refined.

**The refinement.** The contexts of a program form a tree: the root
is the top-level once-context; each open creates one child of the
context its input lives in; each bundle-creating construct creates
N sibling children, one per cell, marked as cells of that
construct. The property a value wire carries is its **context
path** — the chain of (construct, output) steps from the root to
the context the value lives in. Every step is a visible node and
port; the path is read off the diagram, never declared. The
compiler already materializes exactly this tree: `scopeRef`'s
`parent` chain, with `CaseDispatch.altScopes` as the sibling cells.
The path is not a new artifact; it is a name for one the compile
pipeline grew on its own.

**Offers, demands, transport** follow the value-side pattern of
`types-design.md`:

- Opens and bundle constructs *offer* extended paths on their
  per-context outputs (a `Branch` value port offers the parent path
  extended by its (dispatch, alt) cell).
- Ordinary combining nodes *demand comparability*: all operands'
  paths lie on one root-to-leaf line, i.e. each is a prefix of the
  deepest. The result lives at the deepest path — which is what
  `deeper` already computes, minus the verification.
- Structural nodes *transport*: capture stamps the captured constant
  with the flow's path; join removes the inner segment (the joined
  output lives in the outer context); commute permutes adjacent
  iteration segments; Delay's `prev` carries the path of the flow it
  is tied to (*which* flow that is, when several are in reach, is
  the open question of what a Delay is —
  `delay-ontology-design.md`); `Bundle`/`Unbundle` pass paths
  through untouched.
- Collecting nodes are the one place sibling paths may meet; their
  demand is stated below.

### One check, two clash flavors

When comparability fails, walk the two paths to their last common
context and look at the first divergent pair of steps.

- **Both steps are cells of one bundle construct → bundle mixing.**
  "These two values live in mutually exclusive cases Just / Nothing
  of this one case split; no execution produces both." The witness
  is the shared construct plus the two cell edges — two anchors and
  a drawable connector.
- **Anything else (two independent opens) → time travel.** Two
  sibling contexts with no correspondence between their firings.
  The witness is the two opens.

Worked, the mixing clash from the top of the chapter:

```
m -> split isJust of Just, Nothing => cs
cs.Just  -> double => x          -- x lives at [split → Just]
cs.Nothing -> negate => y        -- y lives at [split → Nothing]
x, y -> add                      -- paths share the split, then diverge:
                                 --   Just vs Nothing — cells of one bundle
                                 --   → bundle mixing; witness = split + both alt edges
```

Contrast the time-travel clash, whose divergent steps are two
*unrelated* opens rather than cells of one construct:

```
listA -> open list => a, ~A
listB -> open list => b, ~B
a, b -> add                      -- last common context is the root; the
                                 --   divergent steps are two opens → time travel
```

Both are clashes in the types chapter's sense — *this cannot mean
anything*, reportable even in a partial diagram — as opposed to
unmet demands, which at a schematic source are just the edge of
construction.

Now, you might wonder why the language doesn't just report one kind
of error for both. It turns out that would blur an honest
difference in *why* each is wrong: two independent list opens'
elements all coexist at runtime but have no canonical pairing; two
sibling cells' values have a perfectly canonical pairing and never
coexist. One diagnostic would blur that; two flavors keep each
explanation honest.

**You might also expect this check to need new machinery — a
relation stored between wires.** `types-design.md` called this check
relational ("these two flows came from the same bundle") and flagged
it as a possible point of difference from the value-side machinery.
With context paths it isn't one — the relational reading dissolves
into per-wire facts: the stored property is unary — each wire
carries its own path — and the same-bundle relation is *computed* at
demand-check time by comparing paths, exactly as chain comparability
already is. Relations appear only in comparisons and witnesses,
never in the store. The propagation skeleton is identical to the
value side's: monotone, no choice points, no new machinery class. No
type system beyond the property layer already designed is needed to
express these constraints.

### The one door: what collecting nodes demand

A case Collect's branches map alts to (value, flow) pairs. (On the
pairing vocabulary see the 2026-08-16 note at open question 3: the
case-cell account reads the alt's flow ref as a cell port; the
demands below are stated on paths and survive either reading.) Its
demand, in path terms:

- the branch flows are exactly the cells of one bundle, covering it
  (this is the existing alt-matching quotient check restated — the
  repo's `consumeCaseClose` already validates same-dispatch and
  coverage);
- each branch's *value* path is a prefix of (or equal to) its cell's
  path — the value lives in that cell or an ancestor context, never
  a sibling and never something deeper that hasn't been closed.

The collect's output lives at the bundle's parent path. The filter
close is the partial version: one cell, value path a prefix of the
cell's, output lifted to an enclosing iteration context with the
zero-or-one accounting the compiler already does. So the door
through which siblings meet (behavior 3) is not an exception to the
mixing rule; it is a different demand, on a different node kind,
checked by the same path comparisons.

## What the check must allow: worked cases

Each is a live pattern (tested in the repo or designed in the
record), annotated with the path relation that admits it.

1. **Ancestor value used in sibling cells.** The shared-`bonus`
   test: a literal at the root context is added to `justB` inside
   the Just alt and used alone in the Nothing alt. The root path is
   a prefix of each alt path — comparable in both uses; each
   combination lives in its alt. The memo sharing one binding
   across sibling alt scopes is untouched.

2. **Nested splits.** `Maybe<Either<…>>`: the inner dispatch lives
   inside the outer's Just cell, so inner alt paths extend the
   outer alt path — ancestor/descendant throughout, never sibling
   cells of one construct.

3. **Partition.** The evens/odds two-filter-close test: each close
   consumes one cell separately; no ordinary combining node ever
   sees two cells; the two output lists live at the loop's parent.
   Nothing to forbid.

```
xs -> open list -> split parity of Even, Odd
  Even: -~> join -~> collect => evens     -- each close consumes one cell alone
  Odd:  -~> join -~> collect => odds
```

4. **Case close + filter close on one dispatch.** Both are
   collecting nodes on the same bundle, one exhaustive and one
   partial. Collecting demands are per-node; they don't conflict.

5. **What must clash.** `app(f, [justVal, nothingVal])` on one
   dispatch — sibling cells, no collecting node: bundle-mixing
   clash, witness = the dispatch plus its Just and Nothing edges.
   The same shape with a race's two contender values, or with
   `initial`-case and `step`-case values of one IterationCaseSplit,
   clashes identically. One rule covering a data split, a timing
   split, and a structural-position split is the payoff of defining
   bundles by partition rather than by alternative types.

## Sketch: merged branches as cell sets

The algebra of partial conditional merging is its own design round,
but the path representation suggests a base for it, recorded here
as a sketch.

Let a bundle step in a path carry a *set* of cells rather than a
single cell: an ordinary `Branch` flow carries a singleton
`{Just}`; a partial close merging alts A and B of a three-way split
produces a flow carrying `{A, B}`; the parent context is the
degenerate full set. A value whose bundle step is S exists at a
firing iff the fired cell is in S. Then:

- **Comparability at the bundle step is containment.** S ⊆ T or
  T ⊆ S: combinable, and the combination lives at the smaller set
  (both values exist exactly when the fired cell is in it). This
  makes "a merged branch acts as a parent scope for its
  constituents" a theorem: `{A} ⊆ {A, B}`, so AB-context values are
  usable inside A. Disjoint sets never coexist — bundle mixing,
  with singletons as the special case.
- **Partial overlap of a *combine* is an inferred incorporate to the
  meet** (revised; see "Revision: overlap is incorporate, not a clash"
  below). Two values combined at incomparable sets `{A, B}` and
  `{B, C}` exist together exactly when the fired cell is in the meet
  `{A, B} ∩ {B, C} = {B}` — the greatest cell set contained in both,
  the intersection in the subset lattice, and it is *unique*. So the
  combination lives at `{B}`, reached by incorporating each operand to
  `{B}`, exactly as a value is incorporated into a flow or narrowed
  across nesting. The one case that stays a **clash** is a disjoint
  meet — the empty set (`{A}` meets `{C}`; `{Just}` meets
  `{Nothing}`): no cell where both exist, no execution that produces
  both, nothing to incorporate *to*. The line is the meet:
  **non-empty ⇒ inferred incorporate, empty ⇒ bundle mixing.**
- **The exhaustive collect generalizes for free**: branch cell sets
  must be pairwise disjoint and cover the bundle. Alt matching is
  the all-singletons instance.

The partial close's own meaning is worked out in
`partial-collect-design.md`: rather than choosing from a menu of
possible meanings, the candidates dissolve into distinct complete
programs, and the construct is the partial collect, whose covering
instance is the exhaustive collect. One refinement: at a bundle step
the context structure is the subset lattice of constructed sets, not a
tree; paths stay unary per-wire facts.

### Revision: overlap is incorporate, not a clash

The sketch above first recorded partial overlap as a hard clash — the
checker must never narrow a combination to the intersection, because
"silently narrowing is inference choosing a meaning." That rule is
**reversed here**, and the reversal is a consistency argument, which is
the new evidence the earlier note asked for.

Making a **more flow-agnostic value more flow-specific is an
incorporate** — the CAPTURE family of `time-travel-programs-design.md`,
value-level shadow the identity. This is true on *both* axes. On the
flow axis: using a non-flow value inside a flow `~a` narrows it into
`~a`'s context; strictly, no-time-travel wants that incorporate drawn
(otherwise it is ambiguous whether the value's own computation runs
inside `~a`'s loop or before it — different programs, different cost).
A time-travel program that omits the incorporate is *completed*: we
derive that the author wants to incorporate **at the last available
opportunity**, keeping the value as agnostic as possible and doing as
much computation outside the loop as possible. The cell axis is the
same relation: a `{A, B}` value is more agnostic than a `{A}` value,
and using it at `{A}` incorporates it (`{A} ⊆ {A, B}` — free, a
reference inward, no recomputation). Combining `{A, B}` with `{B, C}`
is that same incorporate applied to *both* operands, forced only as far
as the meet `{B}` where both exist — the last available opportunity on
the cell axis.

So forbidding cell-axis incorporate while allowing flow-axis
incorporate was inconsistent. If we complete time-travel programs by
inferring incorporates on the flow axis, we complete overlapping-bundle
combines by inferring them on the cell axis. The two are one rule.

The **explicit-over-implicit** worry that motivated the original clash
is answered exactly as `time-travel-programs-design.md` answers the
no-time-travel rule: the inferred incorporate *is* a node, surfaced as
a **derived (faint / `+`) view**, not the checker doing silent
arithmetic. The meet is not a searched-for choice — it is the lattice
meet, unique and ruled — so completion stays deterministic (the
elaborator derives it, never scores candidates). And the derived view
is **graded by surprise**: an obvious subset incorporate (`{A, B}` used
at `{A}`, or a constant used in a loop) may be elided, exactly as
auto-capture is never drawn today; a surprising narrowing (`{A, B}` ×
`{B, C}` ⇒ `{B}`, where the user may not have noticed the combination
only fires on B) is *shown*, so the completion the user gets is on
screen. Showing it is what turns the user-error risk into a visible
fact instead of a prohibition.

**One distinction the reversal must keep.** This concerns a *combine*
(an App merging two values), where the meet is a well-defined
combination context. It does **not** touch a partial collect **node**
whose two *branches* have overlapping cell sets: there the ambiguity is
*selection* — when B fires, both branches fire, and which value the
merged flow carries is undefined — and no meet resolves a selection.
Node-level branch overlap stays ill-formed (the collect's disjointness
demand, `partial-collect-design.md`); only the wire-level combine
becomes an inferred incorporate. Combination is resolved by the meet;
selection is not.

(Settled with this reversal — the wire-level combine over overlapping
cells is an inferred, shown incorporate to the meet, not a clash;
disjoint meets and node-level branch overlap remain clashes. Don't
re-propose blanket overlap-is-a-clash without new evidence.)

## Fit with the compiler: sharpening the smallest first step

`types-design.md`'s smallest first step is flow-context alignment:
check that an App's args' scopes form a chain, with a real error
naming the two offending opens, instead of `deeper` silently
picking. This chapter adds one clause to that same step, at almost
no cost:

- `scopeRef` needs to know what it is a scope *of* — an `origin`
  field (the open, or the (dispatch, alt) cell) set where scopes are
  allocated. The parent chain then *is* the context path.
- On a failed chain check, walk both scopes to their least common
  ancestor. If the two divergent children are alt scopes of one
  `CaseDispatch`, report bundle mixing (naming the dispatch and the
  two alts); otherwise report time travel (naming the two opens).
- The collect-side demands are already enforced: `consumeCaseClose`
  validates same-dispatch and alt coverage today. Nothing new to
  build; the reframing just names which family the existing
  validation belongs to.

Testable in `Main.res` style as expect-a-clash tests: build the
`justVal`/`nothingVal` mixing App, assert the compile reports the
dispatch and both alt names. The race and IterationCaseSplit rows
wait for their constructs; the check meets them with no changes,
since it never looks at *why* a construct partitions — only that
its scopes are marked as sibling cells.

## Philosophy check

- **Example first.** The inventory is sampled from constructs the
  record already contains; the partition definition is read off the
  samples; the cell-set sketch waits for its construct.
- **Derived, never adds.** Paths are read off visible nodes and
  wiring — no annotation, no artifact to keep in sync. A reader who
  knows what each node is could reconstruct every path.
- **No search.** Prefix and containment comparisons; monotone
  propagation; no choice points. Within the solver's remit as
  `types-design.md` scoped it.
- **No error without a witness.** Both clash flavors carry two
  anchors and a wire path; the bundle-mixing caption names the one
  shared construct.
- **Checks, not construction.** You can draw the mixing; the check
  tells you what it means. Example-first authoring and partial
  diagrams are untouched.
- **Explicit over implicit.** Movement between cells happens only at
  explicit collecting nodes; the checker never coarsens, narrows,
  or picks.

## Open questions

The language hasn't decided any of the following yet.

1. **The partial-merge round.** `partial-collect-design.md` chose
   the partial close's meaning and the cell-set sketch survived its
   test. Remaining: whether the unopened cells of a partial *open*
   need to be nameable in paths (the README's `PARTIAL_BRANCH`
   next-step, the same question from the representation side). The
   answer here is no — paths only ever carry cells the program
   engaged; coverage checks read the Open's cell inventory, not
   paths.
2. **The `Bundle`/`Unbundle` name.** Whether the spec's
   organizational node pair should be renamed to leave "bundle"
   unambiguous for the semantic family. Cosmetic but worth doing
   before the word appears in error messages.
3. **Commuting past a case segment.** Commute permutes adjacent
   *iteration* segments of a path. Whether a case segment can ever
   participate (commuting a dispatch out of a loop?) — the
   wrapper-stack shape discipline likely already forbids it, but
   the interaction should be stated rather than assumed when stream
   flows land. (2026-08-16: this question now has an owner — the
   Tier-1 case-cell problem, `case-commute-polarity-design.md`,
   works exactly this as **case-cell commute**, a scope lift
   `List (A + B) -> A + List B` whose operand is the cell with its
   payload, not a path segment sliding unchanged; what a
   provenance path records across one is part of that round's
   adoption/propagation question. "Likely already forbids it" is no
   longer the lean.)
4. **Effect flows.** The spec lets effect flows be bundled and
   joined like other flows, in the organizational sense. If an
   effect construct ever produces a semantic family (branching on
   an effect's outcome looks race-shaped), it should land in the
   inventory table; until then effect flows carry paths like any
   other flow.
5. **Clash reporting surface.** How a compile-time clash is
   represented in the repo's test runner (a result variant? a
   raised exception with structured payload?) — small, but it is
   the first error whose *content* (two anchors, a path) matters to
   a test, so it sets the pattern the value-side clashes of
   `types-design.md`'s step 2 will follow.
