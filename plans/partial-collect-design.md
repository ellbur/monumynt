# Partial Collects

> Starting-point document (2026-07-07). This is the round
> `bundle-provenance-design.md` queued as its open question 1 —
> "choose the partial close's semantics, then test the cell-set
> sketch against it" — which is also `flow_language_design.md`'s
> "Multiple Possible Semantics" question and its Future Work #4
> ("Partial Conditional Algebra"), the oldest unformalized corner
> of the original design. The method is inherited from the
> binary-join correction (`lazy-stream-join-design.md`, "Join is
> a binary flow operation"): before choosing between candidate
> semantics, check whether the program the candidates disagree
> about is complete. It isn't, and the question mostly dissolves
> the same way — what remains is one construct, stated below.
> Nothing here is implemented.

Vocabulary as in the companion documents: **bundle** = a
partition of a parent flow's firings; **cell** = one member of
the partition (an alt of a case split, a contender of a race);
**collect** = the construct the code still calls Close;
**the law of the combined flow** = join's semantics ("the
combined flow fires exactly when the inner operand fires").
Ports are as in `first-class-ports-design.md` — this round
builds on that representation and lands after its migration
step 2 (per-alt ports).

## The old question

`flow_language_design.md` left partial conditionals in three
pieces:

1. **The partial open.** `PARTIAL_BRANCH` opens only some
   branches of a conditional — for an optional, just the
   present case.

2. **The semantics menu.** "Closing a partial branch could have
   different semantics: 1. Monadic: unopened branch values pass
   through unchanged. 2. Nothing: unopened branch values become
   Nothing. 3. Other possibilities... Different CLOSE operations
   implement different semantics."

3. **The merge.** `PARTIAL_CLOSE` on two alts of a three-way
   branch "creates an intermediate merged branch (AB)" that can
   be captured into constituents as a parent scope and can
   participate in further merging — with the algebra flagged as
   complex and left as Future Work #4.

The three pieces get three different treatments below: the
first dissolves into ordinary partial *use*, the second
dissolves into distinct complete *programs*, and the third is
the one genuinely new construct — and its algebra, feared
complex, is three short theorems once it is stated as a node.

## The partial open is not a construct

Under first-class ports, a case-split Open carries a value port
and a flow port per alt. "Opening only some branches" is then
not a variant of the Open node; it is referencing only some of
its ports. `PARTIAL_BRANCH` names a *usage pattern*, not a
construct — the same Open node serves the exhaustive program
and the one-sided program, and which one you have is read off
which ports have wires.

The repo already lives this way in degenerate form, as
`bundle-provenance-design.md` noted: `OptionIter` opens only
the Some cell of a two-cell family, and the filter close
consumes one alt of a split while its siblings go unreferenced.
Nothing forces every alt port to be wired; the *collect*'s
coverage demand is what distinguishes exhaustive from partial,
and it is a demand on the collect, not on the open.

One consequence worth making explicit: exclusivity is the
bundle's (the partition always covers, every firing lands in
exactly one cell); *engagement* is the program's, per cell, per
consumer. "Partial" is always a fact about terminations, never
about dispatch.

## The semantics menu, as programs

The binary-join correction's diagnosis transfers verbatim.
"Closing a partial branch" names one flow — the opened alt's —
while the bundle's other cells' terminations are left unstated.
A program in which a flow's termination is unstated is not a
program with several possible meanings; it is not yet a
program. The menu's candidate semantics were rival conventions
for completing it, and once every termination is explicit, each
candidate is a distinct, unambiguous program over the *same*
collect construct:

Take `maybeN` option-shaped, split into cells Some (payload
`n`) and None (no payload). The old menu becomes:

| old name | program | output |
|---|---|---|
| "Nothing semantics" | collect the Some flow alone, value `f(n)` | zero-or-one value at the parent — the implemented set-iff-fired lift |
| "Monadic pass-through" | full collect: `{Some: f(n), None: maybeN}` | option data; the pass-through value is the split's own *input*, an ancestor-context value |
| default value | full collect: `{Some: f(n), None: lit(5)}` | plain value at the parent |
| (filter) | join(enclosing iteration, Some flow), collect the combined flow | skip semantics, by the law's `join(list, option)` row |

"Different CLOSE operations implement different semantics" is
thereby both refuted and satisfied: there is one collect, and
the differences live in the wiring — which flows are
terminated, by what, carrying which values. Note that the
"monadic" and "default" rows are not partial at all: they
engage the None cell's flow in an exhaustive collect. Only the
first and last rows are genuinely partial, and they were never
in tension with the others — they are different programs.

Two details of the old account dissolve alongside:

- **The CAPTURE step.** The old default-value example routed
  the constant through a `CAPTURE(5)` into the unopened flow
  before closing. Under provenance, a `Lit` lives at the root
  context and the collect's demand (each branch's value path a
  prefix of its cell's path) admits it directly. No transport
  node is needed to use an ancestor value in a cell — that is
  the prefix rule doing its job.

- **The garbled example is evidence.** The old example closes
  over a `nothing_flow` that `PARTIAL_BRANCH` never emitted —
  the wiring needs a flow the construct withheld. That is not
  a typo to fix but the tell, in the original document itself,
  that "partial" was about use rather than about the open: the
  moment the program wants to say something about the unopened
  cell, the cell's flow has to exist to be named.

And "3. Other possibilities..." gets a complete answer rather
than an open horizon: a cell flow, like any flow, must be
terminated, and the terminators are enumerable. For a flow
carrying some cells of a bundle:

| termination | result | precedent |
|---|---|---|
| absorbed by a join into an enclosing iteration | filter: keep the firings that land in those cells | the law, `join(list, option-kind)`; the implemented filter close is the singleton case |
| collected alone | zero-or-one data at the bundle's parent context | the implemented option-close lift |
| collected together with disjoint sibling flows | a coarser flow — or, on coverage, a plain value at the parent | the exhaustive case collect is the covering instance |

The third row is the new construct.

## The construct: the partial collect

The old `PARTIAL_CLOSE` signature — values and flows in, a
value and a flow out — was right all along; what it needed was
the frame the rest of this round supplies. Stated as a node:

**A partial collect takes k branches, each a (value, flow)
pair, where the branch flows carry pairwise-disjoint cell sets
of one bundle. It has one value output and one flow output.**

Its semantics is one law, the companion to the law of the
combined flow:

> **The law of the merged flow.** The merged flow fires exactly
> when one of its branch flows fires, and its value output is
> the firing branch's value.

Everything else is a theorem of this law plus the bundle
definition (a partition — at most one cell fires per parent
firing):

- **Kind.** The merged flow fires zero or one time per firing
  of the bundle's parent context: it is option-kind relative to
  the parent. Every rule that applies to an option flow or a
  single alt flow — the join rows, the zero-or-one collect
  lift — applies to a merged flow with no new cases.

- **The exhaustive collect is the full instance.** When the
  branch cell sets cover the bundle, exactly one branch fires
  per parent firing, so the merged flow fires exactly once per
  parent firing — and a flow that fires exactly once per firing
  of its parent, in step with it, *is* the parent flow. Nothing
  distinguishes them; this is the identification today's case
  collect already makes implicitly when it hands back a plain
  value at the parent context rather than a value on a fresh
  flow. `Collect Case` is not a sibling construct to the
  partial collect; it is the covering configuration of the same
  node, with the flow output degenerate.

- **Disjointness is a node demand, not just a wire check.** Two
  branches whose cell sets share a cell ({A,B} with {B,C})
  would both fire when B fires, and the law's "the firing
  branch" would not refer. Ill-formed at the node. The
  provenance sketch's "partial overlap is a clash, not a
  narrowing" at combining nodes is the wire-level shadow of
  this same fact.

- **A single-branch partial collect is the identity.** One
  branch, its flow, its value: the merged flow fires when that
  flow fires with that value — which is just the pair you put
  in. Nothing forbids it; nothing needs it.

- **Associativity.** Merging {A},{B} and then merging the
  result with {C} fires on the same cells with the same values
  as merging {A},{B},{C} at once, or {A} with a merged {B,C}:
  the law only ever consults *which cell fired* and *what value
  that branch carried*, both invariant under bracketing. The
  old document's feared "multiple levels of partial merging
  (AB, AC, BC, ABC, etc.)" is the lattice of disjoint unions
  over the cell inventory, and bracketing is presentation — a
  level-1 recognition could canonicalize it, but nothing
  semantic hangs on it.

On arity: join went binary because its two operands were
asymmetric (outer, inner) and the unary spelling had left one
implicit — the missing operand is what made the J/F fork
possible. The partial collect has no such asymmetry (branches
are interchangeable siblings) and no implicit operand (every
branch is explicit at any arity), and its covering instance —
the existing case collect — is already k-ary. So the node is
k-ary, with binary as the theorem-backed decomposition rather
than the primitive.

### Naming

"Merge" is the natural English for what this node does to
flows, and it is what the old document called the result — but
`async-flow-design.md` has already spent that word on the
stream interleave (`merge(s1, s2)`, racing lifted over
streams). This document says **partial collect** throughout:
it names the construct by its family (the covering instance is
the collect everyone knows) and by what distinguishes it. The
output flow is "the merged flow" in prose, which collides with
nothing. Whether the eventual surfaced name is partial collect,
coalesce, or something better is recorded as an open question;
what should not happen is "merge" meaning two things.

## The merged flow as parent scope

The old document's most interesting claim about `PARTIAL_CLOSE`
was that the merged branch "acts as a parent scope" for its
constituents — capturable into A or B, creating hierarchical
scope structures. Under the cell-set representation this is not
a feature to build; it is the containment theorem from the
provenance sketch, now with a construct to attach to:

A value on the merged flow carries a bundle step with cell set
{A, B}. A computation living in cell A carries {A}. {A} ⊆
{A, B}, so the two are comparable and combine at {A} — the
merged value is directly usable inside either constituent, by
the same rule that lets a root-context value into any cell. No
capture node, no scope declaration; "parent scope" is subset
order doing what it always did.

Worked example — the shape the construct is *for*. An HTTP
response splits four ways: Ok (payload body), Redirect
(payload url), ClientError (payload status), ServerError
(payload status). The two error cases share their handling:

    resp -> open case split => Ok, Redirect, ClientError, ServerError cells

    partial collect {ClientError: status, ServerError: status}
      => errFlow (cells {ClientError, ServerError}), errStatus

    logAndFallback(errStatus)          -- lives at {ClientError, ServerError};
                                       -- runs once per error firing, either kind

    full collect {Ok: parse(body),
                  Redirect: follow(url),
                  errFlow: logAndFallback(errStatus)}   => result

The final collect's branches are keyed by disjoint covering
cell sets — two singletons and a pair — which is the provenance
sketch's generalized coverage demand ("pairwise disjoint and
cover the bundle; alt matching is the all-singletons instance")
landing as the construct's actual signature. And the filter
variant needs nothing new either: from a list of responses,
`join(list flow, errFlow)` + collect keeps exactly the error
responses' statuses — "keep the As and Bs," the law applied to
a merged inner operand.

Note what the containment theorem does *not* license: it never
moves a value from a constituent outward. An {A}-value used
together with an {A,B}-value narrows the combination to {A};
getting a value *to* the merged context from inside cells is
exactly what the partial collect's value threading is for.
Coarsening happens only at the explicit node — the provenance
sketch's explicit-over-implicit clause, now enforced by there
being no other door.

## Every bundle merges

The bundle inventory defined bundles by partition precisely so
that one discipline covers data splits, timing splits, and
structural-position splits. The partial collect inherits that
scope for free:

- **Race.** `async-flow-design.md` rejected `race → alt value`
  as a sum bottleneck and made race a barrier with per-contender
  flows and values; its sanctioned reconvergence is "exhaustive
  close over all contenders." That close *is* the covering
  partial collect over the race bundle — and the partial collect
  makes the subset version meaningful too: merge two of three
  contenders ("either cache or replica — take whichever; the
  full recompute is handled separately"). It also recovers the
  rejected form as an explicit program when genuinely wanted:
  race, then a covering partial collect whose branch values are
  `First(a)` / `Second(b)` constructs the tagged union *as
  data, on purpose* — the bottleneck critique was about the
  construct forcing the packing, and the barrier-plus-collect
  decomposition is strictly more expressive than the packed
  form it replaced.

- **IterationCaseSplit.** The record's splits (initial-vs-step,
  last-vs-non-last) are binary, and a binary bundle's only
  non-trivial merge is the covering one — the split's own
  reconvergence. So no new programs today; the row is here
  because the construct applies unchanged the day a three-case
  structural split exists, with nothing to redesign.

- **Option opens.** The two-cell case, and the reason the
  OptionIter question below exists at all.

The clash side scales identically: mixing values of *disjoint*
cell sets of one bundle at an ordinary combining node is bundle
mixing whatever the bundle's origin — the provenance check
never asks why the construct partitions.

## Fit with bundle provenance

The cell-set sketch was recorded with one reservation: "until
[the partial close's semantics are chosen] there is no
construct for the cell sets to describe." Checking its clauses
against the construct:

- **Containment as comparability** — confirmed; it is the
  parent-scope section above, and the theorem the sketch
  promised ("merged branch acts as a parent scope" becomes
  `{A} ⊆ {A, B}`) holds with the value threading made explicit.
- **Partial overlap is a clash** — confirmed and strengthened:
  overlap is ill-formed already at the partial collect (the
  law's "the firing branch" must refer), so the checker's
  refusal to narrow is backed by there being no node that
  narrows.
- **The generalized collect demand** (pairwise disjoint,
  covering) — confirmed; it is the covering configuration's
  well-formedness condition, with alt matching as the
  all-singletons instance, exactly as sketched.

And the rider question — do unopened cells need to be nameable
in paths? — gets a clean **no**. Paths attach to wires; wires
hang off referenced ports; an unengaged cell contributes no
wire, so no path ever needs its name. Cell-*set* steps enter
paths only through partial collects, whose sets are unions of
cells the program actually engaged. The full set never needs
writing (it is the parent context). The one place the checker
consults cells nobody wired is the coverage check — and that
reads the bundle's cell *inventory*, which lives on the Open
node (its alts list), not in any path.

One refinement to the provenance model, implicit in the sketch
and explicit now: at a bundle step, the context structure is
not a tree but the subset lattice restricted to the sets the
program constructed. Paths remain per-wire unary facts;
comparability remains a two-path computation (prefix on open
steps, containment on bundle steps); nothing relational enters
the store. The propagation skeleton survives untouched.

## Representation and compile

**Spec level.** The spec's `Collect` is defined with
`valueOutputs: {result}, flowOutputs: {}` — the covering
configuration. The generalization: `Case` branches become a
list of `{value: ValueSource, flow: FlowSource}` pairs (keying
by `AlternativeName` survives as the all-singletons display,
but a branch may now reference a merged flow spanning several
cells); the node demands pairwise-disjoint branch cell sets;
covering ⇒ `valueOutputs: {result}, flowOutputs: {}` as today,
partial ⇒ `valueOutputs: {value}, flowOutputs: {flow}`.
Per-configuration port inventories are already spec practice
("depends on variant").

**Expr level.** Lands after `first-class-ports-design.md`
migration step 2, since branches reference alt flow ports:

```rescript
| CollectCase({branches: array<{value: valueRef, flow: flowRef}>})
```

with the port inventory read off coverage. Each branch flow is
an alt flow port or another partial collect's flow port; the
cell set is computed by walking, never stored.

**Compile.** No new machinery class. Every consumer of a merged
flow compiles its own self-contained thunk, per the multi-close
doctrine — the merged flow never materializes as a runtime
object, exactly as join's combined flow never does. The
dispatch if-chain arms group by branch:

- covering: today's `emitCaseClose` unchanged (one arm per
  singleton) or arms spanning cells
  (`if (split.tag === "ClientError" || split.tag === "ServerError")`);
- partial, collected alone: the grouped arms with the
  set-iff-fired `let out;` lift — the option-close shape;
- partial, join-absorbed: the grouped arms pushing inside the
  enclosing for-of — the filter-close shape with a disjunction
  in the guard.

The merged *value* is bound per arm (each arm binds the same
name to its branch's value; exactly one arm runs). Computations
at the merged context can be emitted per arm (code duplicated,
evaluation still once) or once behind a fired-guard — an
emission choice with no semantic content, decidable at
implementation time.

**The OptionIter question.** The old menu's "monadic" and
"default" programs need the None cell's flow for their
exhaustive collect — and the repo's `OptionIter` exposes no
such port, which is why defaulting an option today requires a
general case split with a discriminator. Two consistent
positions:

1. **OptionIter stays filter-only.** No None port; its
   inventory has one openable cell; the coverage check can
   never see a covering collect over it, so the only
   terminations are the partial ones (join-absorb, lone
   collect). Defaulting keeps requiring the general split.
2. **OptionIter is a two-cell split.** The None cell gets a
   flow port (no value port — per-kind irregular inventories
   already accommodate that; Commute has no value ports at
   all). The `open_`/element sugar is unchanged; the None
   handle exists for the programs that want it, and the
   default-value program becomes a covering collect over the
   same open that filtering uses, instead of a re-dispatch.

The lean is 2: it makes "a partial open is a bundle with
unengaged cells" literally true of the representation, and the
cost is one two-armed dispatch shape (`if/else` on
`=== undefined`) in a compiler that already emits both arms
for case splits. But it is severable — nothing else in this
round depends on it — so it is recorded as a decision to take
at implementation time, not silently assumed.

## Against the philosophy

- **Example first, then generalise.** The construct is read off
  the worked programs (the error-handling merge, the option
  default), and its scope beyond case splits is inherited from
  the bundle inventory's samples rather than declared.
- **Inside-out / cases as values.** The merged context is not a
  scope that changes the meaning of what is written "inside"
  it; it is a cell set on wires, and a value's usability
  anywhere is subset order on visible structure. No magic
  names; the pass-through value in the monadic program arrives
  by an ordinary wire from the split's input.
- **Foundations before features.** The round spends its length
  dissolving two-thirds of the old question rather than
  building three constructs; what remains is one node and one
  law.
- **Building blocks at the programmer's level.** "Handle these
  two cases the same way" is programmer vocabulary; the partial
  collect says exactly that, once, instead of duplicated branch
  bodies or an encode-into-data workaround.
- **No bottlenecks.** Nothing is packed to pass a structural
  point: the merged value output is not a tagged union (the
  which-cell information is not packed into it — it stays where
  it always was, on the constituent flows, which remain
  referenceable by other consumers). Deliberate coarsening at
  an explicit node is the *point* of the construct, not a
  bottleneck; and where the packed sum is genuinely wanted, it
  is constructed as data by explicit branch values. One
  reservation is recorded as open question 3: with only one
  value row, two values crossing the same merge must either
  take two partial collects or pack — the multi-row barrier
  shape is the principled completion.
- **Abstraction is the source of truth.** Bracketing-insensitive
  associativity means merge order is presentation; a canonical
  form is derivable and the authored form need not be edited to
  reach it.

## Open questions

1. **The surfaced name.** Partial collect (family-faithful,
   wordy), coalesce, or other; "merge" is spent
   (`async-flow-design.md`'s stream interleave). Decide before
   the word appears in error messages, alongside
   bundle-provenance's `Bundle`/`Unbundle` renaming question.
2. **The OptionIter None port** — position 1 or 2 above; lean
   2; severable, decide at implementation.
3. **Multi-row value correspondence.** k branches × m
   corresponding value rows, outputs one value per row — the
   full barrier shape (race has it per contender;
   `first-class-ports-design.md`'s open question 3 asks the
   same of Join's value ports; the failable discharging
   collect wants per-outcome ports on one collect). With m = 1
   as designed here, a second value crossing the same merge
   takes a second partial collect over the same cells, which
   works but multiplies nodes where the barrier shape would
   multiply ports. Decide the two together — the flatten join,
   the concurrent join, race, and the partial collect should
   agree on how values cross a barrier, or differ for stated
   reasons.
4. **Merged-flow identity.** Two partial collects over the same
   cells with the same values: distinct flows
   (node-identity), or the same flow (structural)? The same
   question as first-class-ports' open question 2 for Join
   nodes, with the same interim answer — bind once and reuse,
   like any shared node; decide for real when something
   observable (stream chain sharing) keys off flow identity.
5. **What collecting an option-kind flow yields** — option
   data, the undefined encoding, or a distinguished partial
   value. Inherited unchanged from the join correction ("What
   this opens," item 4); the partial collect adds pressure to
   settle it, since merged flows multiply the places the
   zero-or-one lift appears, but adds no new considerations.
6. **Streams and commute.** A merged flow is option-kind, so
   `Commuted` over it should behave as over any option level
   (abort semantics keyed to "some engaged cell fired") — but
   the stream documents' wrapper-stack rows predate binary join
   and this construct both; check when they are re-read as
   programs over explicit nodes, per the correction's item 1.
7. **The visual form.** How a partial collect and its merged
   flow render — where the flow wires converge, how the cell
   set is shown, what the containment relation looks like on
   canvas — belongs to the layout documents, out of scope
   here; flagged so it lands on their list.

## What this doesn't address

- **The visual side**, per open question 7.
- **The collect-on-option vocabulary point** (open question 5)
  — this round makes it more visible, not more decided.
- **Race, IterationCaseSplit implementations.** The "every
  bundle merges" section is about the construct's scope, not a
  commitment to build those flows now.
- **The checking machinery.** Bundle provenance's check gains
  the containment case sketched there; implementing the check
  remains the types round's smallest-first-step plan.
- **First-class ports.** This round assumes that migration;
  nothing here changes its steps or its open questions except
  by adding weight to its question 3 (barrier value ports).
