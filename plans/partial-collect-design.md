# Partial Collects — using only some of a split's branches

Status: exploration — this chapter teaches a worked proposal with
stated leanings. It has not been adopted, and none of it is
implemented; read it as "here is a candidate and the case for it."
It lands after the `first-class-ports-design.md` migration's step 2
(per-alt ports), which the design builds on.

When you split a value into cases, exactly one case fires per firing
of the parent flow, and often you go on to handle every case. Just
as often, though, you only care about *some* of them: keep the
elements that matched, give the ones that didn't a default, handle
two error cases with one piece of code. This chapter is about
programs that use a split only partly — the oldest unformalized
corner of the design, and the place where several branches' results
get merged back into one flow. The short answer it reaches: most of
the apparent difficulty dissolves, and what remains is a single
construct — the **partial collect**.

## A first program: using one branch

Here is a program that keeps only the present values from a list of
options (spelling per `textual-representation-design.md`):

```
-- filter: keep only the Some firings within an enclosing list iteration
xs -> open list -> split isJust of Some, None
  Some: -~> join -~> collect => kept   -- join(list, Some flow) drops the Nones
```

Each element of `xs` is split on `isJust`; the `Some` case's flow is
joined into the enclosing list iteration and collected, so `kept` is
the list of payloads that were present. In conventional code this is
a `filter`. Notice what the program does with the `None` case:
nothing at all. Its flow is simply not wired anywhere. This program
uses the split *partly* — and it already works today; the filter
close in the compiler is exactly this shape.

## The words this chapter uses

The split in that program partitions the list flow's firings: every
element lands in exactly one of `Some` and `None`, never both, never
neither. Such a partition of a parent flow's firings is called a
**bundle** — the alts of a case split form one, and so do the
contenders of a race. Each member of the partition is a **cell**;
here `Some` and `None` are the two cells. A **collect** is the
construct the code still calls `Close`: it terminates a flow and
yields a value. One more law from another chapter does a lot of work
below — **the law of the combined flow**, which is join's meaning:
"the combined flow fires exactly when the inner operand fires"
(`lazy-stream-join-design.md`).

## The question, in three pieces

Older notes left "partial conditionals" as three tangled problems:

1. **The partial open.** A way to open only *some* branches of a
   conditional — for an option, just the present case.
2. **The menu of meanings.** Closing a partly-used conditional
   seemed to admit several rival meanings: unopened branches pass
   through unchanged, or become Nothing, or take a default, plus
   "other possibilities." Different close operations would implement
   the different meanings.
3. **The merge.** Closing two alts of a three-way split "creates an
   intermediate merged branch (AB)" that could itself be a scope and
   participate in further merging — an algebra feared complex.

Each piece gets a different treatment in this chapter. The first
turns out not to be a construct at all. The second turns out not to
be a menu of meanings but a set of *distinct programs*. The third is
the one genuinely new node — and its feared algebra is three short
theorems once the node is stated properly.

## Why there is no "partial open"

Now, you might wonder why the language doesn't have a special
construct for opening only some branches — a partial open, distinct
from the ordinary split. It turns out no such construct is needed,
because the ordinary split already does the job. Under first-class
ports, a case-split Open carries a value port and a flow port *per
alt*. "Opening only some branches" is then not a special Open node;
it is referencing only some of its ports. The same Open serves the
exhaustive program and the one-sided program. Which one you have is
read off which ports are wired.

The repo already lives this way. `OptionIter` opens only the Some
cell of a two-cell family; the filter close (the first program
above) consumes one alt of a split while its siblings go
unreferenced. Nothing forces every alt port to be wired. What
distinguishes exhaustive from partial is the *collect*'s coverage
demand — a demand on the collect, not on the open.

Two facts pull apart here, and keeping them apart is what makes
"partial" precise:

- **Exclusivity is the bundle's.** The partition always covers;
  every firing lands in exactly one cell.
- **Engagement is the program's** — per cell, per consumer. Whether
  a cell's flow is terminated, and how, is a fact about the
  program's wiring.

So "partial" is always a fact about *terminations*, never about
dispatch. (This is a settled dissolution — a "partial open"
construct must not be re-proposed; there is nothing left for it to
do.)

## The menu of meanings, resolved as programs

Now, you might wonder what it *means* to close a partial branch —
older notes treated this as a menu of rival meanings, each needing
its own close operation. It turns out the menu dissolves, and the
way it dissolves is a nice illustration of how the language thinks.
"Closing a partial branch" names one flow — the opened alt's — while
the bundle's other cells' terminations are left unstated. A program
in which a flow's termination is unstated is not a program with
several possible meanings; it is *not yet a program*. The menu's
rival "semantics" were rival conventions for finishing it. Once
every termination is explicit, each becomes a distinct, unambiguous
program over the *same* collect construct.

Take `maybeN`, option-shaped, split into cell `Some` (payload `n`)
and cell `None` (no payload). The old menu becomes four programs.
(One old name needs a gloss: "monadic" pass-through is the
functional-programming tradition's word for chaining option-shaped
values so that a missing value stays missing — here it just means
the `None` branch passes the original option through unchanged.)

| old name | what the program does | output |
|---|---|---|
| "Nothing semantics" | collect the Some flow alone, value `f(n)` | zero-or-one value at the parent — the implemented set-iff-fired lift |
| "monadic pass-through" | full collect `{Some: f(n), None: maybeN}` | option data; the pass-through value is the split's own *input*, an ancestor-context value |
| default value | full collect `{Some: f(n), None: 5}` | plain value at the parent |
| filter | `join(enclosing iteration, Some flow)`, collect the combined flow | skip semantics, by the law's `join(list, option)` row |

Two of the four in textual syntax — the default-value program:

```
-- default value: exhaustive collect, None branch supplies a constant
maybeN -> split isJust of Some, None
  Some: -> f
  None: 5
-~> collect => out              -- plain value; None contributes 5
```

and the filter program, which you have already seen:

```
-- filter: keep only the Some firings within an enclosing list iteration
xs -> open list -> split isJust of Some, None
  Some: -~> join -~> collect => kept   -- join(list, Some flow) drops the Nones
```

"Different close operations implement different semantics" is
thereby both refuted and satisfied: there is one collect, and the
differences live in the wiring — which flows are terminated, by
what, carrying which values. Note that the "monadic" and "default"
rows are not partial at all; they engage the None cell's flow in an
exhaustive collect. Only the first and last rows are genuinely
partial, and they were never in tension with the others — they are
simply different programs. (This too is a settled dissolution — the
menu must not return as a family of close operations.)

Two details of the old account dissolve alongside:

- Now, you might wonder how the constant `5` gets *into* the None
  branch in the default-value program — doesn't a value from outside
  the flow need some transport step? The old account thought so: its
  default-value program routed the constant through a CAPTURE node
  into the unopened flow before closing. It turns out no such step
  exists. Under provenance a `Lit` lives at the root context, and
  the collect's demand (each branch's value path a prefix of its
  cell's path) admits it directly. Using an ancestor value in a cell
  needs no transport node — that is the prefix rule doing its job.
  (Settled dissolution: no CAPTURE step.)
- **The garbled example was the tell.** The old default-value
  example closed over a `nothing_flow` that the partial open never
  emitted — the wiring needed a flow the construct had withheld.
  That is not a typo but evidence that "partial" was about *use*,
  not about the open: the moment the program wants to say anything
  about the unopened cell, the cell's flow has to exist to be named.

And the menu's "other possibilities" entry gets a complete answer
rather than an open horizon. A cell flow, like any flow, must be
terminated, and the terminators are enumerable. For a flow carrying
some cells of a bundle:

| termination | result | precedent |
|---|---|---|
| absorbed by a join into an enclosing iteration | filter: keep the firings that land in those cells | the law, `join(list, option-kind)`; the implemented filter close is the singleton case |
| collected alone | zero-or-one data at the bundle's parent context | the implemented option-close lift |
| collected together with disjoint sibling flows | a coarser flow — or, on coverage, a plain value at the parent | the exhaustive case collect is the covering instance |

The third row is the one thing you haven't met yet. It is the new
construct.

## The construct: the partial collect

Stated as a node:

**A partial collect takes k branches, each a (value, flow) pair,
where the branch flows carry pairwise-disjoint cell sets of one
bundle. It has one value output and one flow output.**

Its meaning is one law, the companion to the law of the combined
flow:

> **The law of the merged flow.** The merged flow fires exactly when
> one of its branch flows fires, and its value output is the firing
> branch's value.

Here is the shape the construct is *for*, worked in full. An HTTP
response splits four ways: `Ok` (payload body), `Redirect` (payload
url), `ClientError` and `ServerError` (payload status). The two
error cases share their handling:

```
resp -> split status of Ok, Redirect, ClientError, ServerError => h
~h.ClientError: h.ClientError
~h.ServerError: h.ServerError
-~> collect => errStatus, ~err        -- partial collect: value + merged flow; ~err spans {ClientError, ServerError}
errStatus -> logAndFallback => fb     -- lives at {ClientError, ServerError}; runs once per error firing, either kind
~h.Ok:       h.Ok -> parse
~h.Redirect: h.Redirect -> follow
~err:        fb
-~> collect => result                 -- exhaustive: two singletons and one pair cover the bundle
```

The first collect is partial — it merges the two error cells and
hands back both a value (`errStatus`, the status whichever error
fired) and the merged flow `~err`. `logAndFallback` runs once per
error firing, of either kind — "handle these two cases the same
way," said once. The final collect's branches are keyed by disjoint
covering cell sets — two singletons and a pair — which is the
provenance sketch's generalized coverage demand ("pairwise disjoint
and cover the bundle; alt matching is the all-singletons instance")
landing as the construct's actual signature. The filter variant
needs nothing new either: from a list of responses,
`join(list flow, errFlow)` + collect keeps exactly the error
responses' statuses — "keep the ClientErrors and ServerErrors," the
law applied to a merged inner operand.

### What follows from the law

Everything else about the construct is a theorem of the law plus the
bundle definition (a partition — at most one cell fires per parent
firing):

- **Kind.** The merged flow fires zero or one time per firing of the
  bundle's parent context: it is option-kind relative to the parent.
  Every rule that applies to an option flow or a single alt flow —
  the join rows, the zero-or-one collect lift — applies to a merged
  flow with no new cases.
- **The exhaustive collect is the full instance.** When the branch
  cell sets cover the bundle, exactly one branch fires per parent
  firing, so the merged flow fires exactly once per parent firing —
  and a flow that fires exactly once per firing of its parent, in
  step with it, *is* the parent flow. `Collect Case` is not a
  sibling construct to the partial collect; it is the covering
  configuration of the same node, with the flow output degenerate.
  (This is the identification today's case collect already makes
  when it hands back a plain value at the parent context rather than
  a value on a fresh flow.)
- **Disjointness is a node demand.** Two branches whose cell sets
  share a cell (`{A,B}` with `{B,C}`) would both fire when B fires,
  and the law's "the firing branch" would not refer. Ill-formed at
  the node — this is a *selection* ambiguity (which branch's value
  does the merged flow carry?), and no meet resolves a selection.
  Note this is **not** the same as the wire-level combine of two
  overlapping-cell values: that *combination* lives at the meet and is
  now an inferred incorporate, not a clash (`bundle-provenance-
  design.md`, "Revision: overlap is incorporate, not a clash"). The
  earlier identification of the two was dropped there — combination is
  resolved by the meet, selection is not; only the node-level branch
  overlap stays ill-formed.
- **A single-branch partial collect is the identity.** One branch,
  its flow, its value: the merged flow fires when that flow fires
  with that value — just the pair you put in. Nothing forbids it;
  nothing needs it.
- **Associativity.** Merging `{A},{B}` and then merging with `{C}`
  fires on the same cells with the same values as merging
  `{A},{B},{C}` at once, or `{A}` with a merged `{B,C}`. The law
  only ever consults *which cell fired* and *what value that branch
  carried*, both invariant under bracketing.

That last theorem retires the third of the three tangled problems.
Now, you might remember the fear that merging opens an algebra of
"multiple levels of partial merging (AB, AC, BC, ABC…)". It turns
out the feared algebra is just the family of disjoint unions over
the cell inventory, ordered by inclusion (a lattice, in the
mathematical term); bracketing is presentation. A level-1
recognition could canonicalize it, but nothing semantic hangs on it.
(Settled dissolution: there is no complex merge algebra to design.)

### Why k branches, not two

Now, you might wonder why the partial collect takes any number of
branches when join — the other flow-combining operation — was
deliberately made binary. It turns out the two cases differ in
exactly the ways that mattered. Join went binary because its two
operands were asymmetric (outer, inner) and the unary spelling had
left one implicit — that missing operand is what made the
join/filter fork possible. The partial collect has no such asymmetry
(branches are interchangeable siblings) and no implicit operand
(every branch is explicit at any arity), and its covering instance —
the existing case collect — is already k-ary. So the node is k-ary,
with binary merging as a theorem-backed decomposition rather than
the primitive. (Settled: binary is not the primitive here.)

### Naming

"Merge" is the natural English for what this node does, but
`async-flow-design.md` has already spent that word on the stream
interleave (`merge(s1, s2)`, racing lifted over streams). This
chapter says **partial collect** throughout: it names the construct
by its family (the covering instance is the collect everyone knows)
and by what distinguishes it. The output flow is "the merged flow"
in prose, which collides with nothing. Whether the eventual surfaced
name is partial collect, coalesce, or something better is an open
question (see below); what must not happen is "merge" meaning two
things.

## The merged flow as parent scope

Look back at the HTTP program: `errStatus` is computed at the merged
context `{ClientError, ServerError}`, and nothing special was
written to make it usable there. The old account's most interesting
claim was that the merged branch "acts as a parent scope" for its
constituents — capturable back into A or B. Under the cell-set
representation this is not a feature to build; it is the containment
theorem from bundle provenance, now with a construct to attach to.

A value on the merged flow carries a bundle step with cell set
`{A, B}`. A computation living in cell A carries `{A}`. Since
`{A} ⊆ {A, B}`, the two are comparable and combine at `{A}` — the
merged value is directly usable inside either constituent, by the
same rule that lets a root-context value into any cell. No capture
node, no scope declaration; "parent scope" is subset order doing
what it always did.

The containment theorem is one-directional. It never moves a value
*out* of a constituent: an `{A}`-value combined with an
`{A,B}`-value narrows to `{A}`. Getting a value *to* the merged
context from inside cells is exactly what the partial collect's
value threading is for. Coarsening happens only at the explicit
node — the provenance sketch's explicit-over-implicit clause, now
enforced by there being no other door.

## Every bundle merges

Everything so far used case splits, but the bundle inventory defines
bundles by partition precisely so that one discipline covers data
splits, timing splits, and structural-position splits. The partial
collect inherits that scope for free:

- **Race.** `async-flow-design.md` rejected `race → alt value` as a
  sum bottleneck and made race a barrier with per-contender flows
  and values; its sanctioned reconvergence is "exhaustive close over
  all contenders." That close *is* the covering partial collect over
  the race bundle — and the partial collect makes the subset version
  meaningful: merge two of three contenders ("either cache or
  replica — take whichever; the full recompute is handled
  separately"). It also recovers the rejected form as an explicit
  program when genuinely wanted: race, then a covering partial
  collect whose branch values are `First(a)` / `Second(b)`
  constructs the tagged union *as data, on purpose*. The bottleneck
  critique was about the construct *forcing* the packing;
  barrier-plus-collect is strictly more expressive than the packed
  form it replaced.
- **IterationCaseSplit.** The record's structural splits
  (initial-vs-step, last-vs-non-last) are binary, and a binary
  bundle's only non-trivial merge is the covering one — the split's
  own reconvergence. No new programs today; the row is here because
  the construct applies unchanged the day a three-case structural
  split exists, with nothing to redesign.
- **Option opens.** The two-cell case, and the reason the OptionIter
  question below exists at all.

The clash side scales identically: mixing values of *disjoint* cell
sets of one bundle at an ordinary combining node is bundle mixing
whatever the bundle's origin. The provenance check never asks why
the construct partitions.

## Fit with bundle provenance

The cell-set sketch in `bundle-provenance-design.md` was recorded
with one reservation: until the partial close's meaning was chosen,
there was no construct for the cell sets to describe. Checking its
clauses against the construct:

- **Containment as comparability** — confirmed; it is the
  parent-scope section above, `{A} ⊆ {A, B}` with the value
  threading made explicit.
- **Partial overlap at the node is a clash** — confirmed for the
  *node*: overlapping branches are ill-formed at the partial collect
  (the law's "the firing branch" must refer). The sketch's separate
  claim about the *wire-level combine* over overlapping cells was
  since revised (`bundle-provenance-design.md`, "Revision: overlap is
  incorporate, not a clash"): that combination lives at the meet and
  is an inferred incorporate. The node still admits no narrowing —
  there is no node that selects among simultaneously-firing branches —
  but the combine does, at the meet, because a combination is not a
  selection.
- **The generalized collect demand** (pairwise disjoint, covering) —
  confirmed; it is the covering configuration's well-formedness
  condition, with alt matching as the all-singletons instance.

The rider question — do unopened cells need to be nameable in
paths? — gets a clean **no**. Paths attach to wires; wires hang off
referenced ports; an unengaged cell contributes no wire, so no path
ever needs its name. Cell-*set* steps enter paths only through
partial collects, whose sets are unions of cells the program
actually engaged. The full set never needs writing (it is the parent
context). The one place the checker consults cells nobody wired is
the coverage check — and that reads the bundle's cell *inventory*,
which lives on the Open node (its alts list), not in any path.

One refinement to the provenance model: at a bundle step the context
structure is not a tree but the subset lattice restricted to the
sets the program constructed — that is, the family of cell sets the
program built, ordered by inclusion. Paths remain per-wire unary
facts; comparability remains a two-path computation (prefix on open
steps, containment on bundle steps); nothing relational enters the
store. The propagation skeleton survives untouched.

## Representation and compile

How would this land in the actual code? Four pieces.

**Spec level.** The spec's `Collect` is defined with `valueOutputs:
{result}, flowOutputs: {}` — the covering configuration. The
generalization: `Case` branches become a list of `{value:
ValueSource, flow: FlowSource}` pairs (keying by `AlternativeName`
survives as the all-singletons display, but a branch may now
reference a merged flow spanning several cells); the node demands
pairwise-disjoint branch cell sets; covering ⇒ `valueOutputs:
{result}, flowOutputs: {}` as today, partial ⇒ `valueOutputs:
{value}, flowOutputs: {flow}`. Per-configuration port inventories
are already spec practice.

**Expr level.** Lands after `first-class-ports-design.md` migration
step 2, since branches reference alt flow ports:

```rescript
| CollectCase({branches: array<{value: valueRef, flow: flowRef}>})
```

with the port inventory read off coverage. Each branch flow is an
alt flow port or another partial collect's flow port; the cell set
is computed by walking, never stored.

**Compile.** No new machinery class. Every consumer of a merged flow
compiles its own self-contained thunk, per the multi-close
doctrine — the merged flow never materializes as a runtime object,
exactly as join's combined flow never does. The dispatch if-chain
arms group by branch:

- covering: today's `emitCaseClose` unchanged (one arm per
  singleton), or arms spanning cells
  (`if (split.tag === "ClientError" || split.tag === "ServerError")`);
- partial, collected alone: the grouped arms with the set-iff-fired
  `let out;` lift — the option-close shape;
- partial, join-absorbed: the grouped arms pushing inside the
  enclosing for-of — the filter-close shape with a disjunction in
  the guard.

The merged *value* is bound per arm (each arm binds the same name to
its branch's value; exactly one arm runs). Computations at the
merged context can be emitted per arm (code duplicated, evaluation
still once) or once behind a fired-guard — an emission choice with
no semantic content, decidable at implementation time.

**The OptionIter question.** The "monadic" and "default" programs
need the None cell's flow for their exhaustive collect — and the
repo's `OptionIter` exposes no such port, which is why defaulting an
option today requires a general case split with a discriminator. The
language hasn't decided this yet; two consistent positions:

1. **OptionIter stays filter-only.** No None port; its inventory has
   one openable cell; the coverage check can never see a covering
   collect over it, so the only terminations are the partial ones
   (join-absorb, lone collect). Defaulting keeps requiring the
   general split.
2. **OptionIter is a two-cell split.** The None cell gets a flow
   port (no value port — per-kind irregular inventories already
   accommodate that; Commute has no value ports at all). The
   `open_`/element sugar is unchanged; the None handle exists for
   the programs that want it, and the default-value program becomes
   a covering collect over the same open that filtering uses,
   instead of a re-dispatch.

The lean is 2: it makes "a partial open is a bundle with unengaged
cells" literally true of the representation, at the cost of one
two-armed dispatch shape (`if/else` on `=== undefined`) in a
compiler that already emits both arms for case splits. But it is
severable — nothing else here depends on it — so it is a decision to
take at implementation time, not silently assumed.

## How this squares with the design philosophy

- **Example first, then generalise.** The construct is read off the
  worked programs (the error-handling merge, the option default);
  its scope beyond case splits is inherited from the bundle
  inventory's samples rather than declared.
- **Inside-out / cases as values.** The merged context is not a
  scope that changes the meaning of what is written "inside" it; it
  is a cell set on wires, and a value's usability anywhere is subset
  order on visible structure. No magic names; the pass-through value
  in the monadic program arrives by an ordinary wire from the
  split's input.
- **Foundations before features.** The design dissolves two-thirds
  of the old question rather than building three constructs; what
  remains is one node and one law.
- **Building blocks at the programmer's level.** "Handle these two
  cases the same way" is programmer vocabulary; the partial collect
  says exactly that, once, instead of duplicated branch bodies or an
  encode-into-data workaround.
- **No bottlenecks.** Nothing is packed to pass a structural point:
  the merged value output is not a tagged union (which-cell
  information stays where it always was, on the constituent flows,
  still referenceable by other consumers). Deliberate coarsening at
  an explicit node is the *point* of the construct, not a
  bottleneck; and where the packed sum is genuinely wanted, it is
  constructed as data by explicit branch values. The one-value-row
  limitation (two values crossing the same merge must take two
  partial collects or pack) is recorded as open question 3 — the
  multi-row barrier shape is the principled completion.
- **Abstraction is the source of truth.** Bracketing-insensitive
  associativity means merge order is presentation; a canonical form
  is derivable and the authored form need not be edited to reach it.

## Open questions

None of these is decided yet; each is stated with its current lean
where one exists.

1. **The surfaced name.** Partial collect (family-faithful, wordy),
   coalesce, or other; "merge" is spent
   (`async-flow-design.md`'s stream interleave). Decide before the
   word appears in error messages, alongside bundle-provenance's
   `Bundle`/`Unbundle` renaming question.
2. **The OptionIter None port** — position 1 or 2 above; lean 2;
   severable, decide at implementation.
3. **Multi-row value correspondence.** k branches × m corresponding
   value rows, outputs one value per row — the full barrier shape
   (race has it per contender; `first-class-ports-design.md`'s open
   question 3 asks the same of Join's value ports). With m = 1 as
   designed here, a second value crossing the same merge takes a
   second partial collect over the same cells. The flatten join, the
   concurrent join, race, and the partial collect should agree on
   how values cross a barrier, or differ for stated reasons — taken
   up in one place, `barrier-value-crossing-design.md`. Its lean: no
   multi-row node; m value rows are m sibling partial collects over
   the same cell sets, whose outputs land at the same merged context
   (containment compares cell sets, computed by walking — node
   identity never enters) and combine freely, so the
   two-collects-or-pack dilemma is false. The m-row barrier survives
   as a drawn/recognized view. Leanings, not adopted.
4. **Merged-flow identity.** Two partial collects over the same
   cells with the same values: distinct flows (node-identity) or the
   same flow (structural)? The same question as first-class-ports'
   open question 2 for Join nodes, with the same interim answer —
   bind once and reuse, like any shared node; decide for real when
   something observable (stream chain sharing) keys off flow
   identity.
5. **What collecting an option-kind flow yields** — option data, the
   undefined encoding, or a distinguished partial value. Inherited
   unchanged from the join correction; the partial collect adds
   pressure to settle it (merged flows multiply the places the
   zero-or-one lift appears) but adds no new considerations.
6. **Streams and commute.** A merged flow is option-kind, so
   `Commuted` over it should behave as over any option level (abort
   semantics keyed to "some engaged cell fired") — but the stream
   documents' wrapper-stack rows predate binary join and this
   construct, so check them when they are re-read as programs over
   explicit nodes.
7. **The visual form.** How a partial collect and its merged flow
   render belongs to the layout documents, out of scope here;
   flagged so it lands on their list.

## What this chapter doesn't cover

- **The visual side**, per open question 7.
- **The collect-on-option vocabulary point** (open question 5) —
  this design makes it more visible, not more decided.
- **Race, IterationCaseSplit implementations.** The "every bundle
  merges" section is about the construct's scope, not a commitment
  to build those flows now.
- **The checking machinery.** Bundle provenance's check gains the
  containment case sketched there; implementing the check remains
  the types round's smallest-first-step plan.
- **First-class ports.** This design assumes that migration; nothing
  here changes its steps or open questions except by adding weight
  to its question 3 (barrier value ports).
