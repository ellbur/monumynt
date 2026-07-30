# The chooser family: the decision-driven merge, fairness, and arbitration

Status: design-only exploration — this chapter is a worked proposal
prepared for a design conversation; **nothing in it is adopted** and
none of it is implemented. It is the round the record has been
citing as "the chooser family's round": the two-flow decision-driven
merge (`tough-use-cases-design.md`, item 4 — the family's last
unworked member), merge fairness (relocated here by
`race-barrier-design.md`, "Is race fair?"), cross-client arbitration
(`served-flow-design.md`, question 2), the heuristic-order rung
(`speculation-design.md`, question 5), and end-when's verdict-
vocabulary question (`end-when-design.md`, question 3) are all
worked below. The round's one-line result: **the chooser is not a
construct.** One node — the decision-driven merge, a walk over k
cursors — exposes per-step heads and takes a late-wired advance
operand, and every "chooser" in the record's backlog is ordinary
drawn vocabulary (a case split, a race, a register read) wired
between those ports. Code samples use the textual syntax of
`textual-representation-design.md`; every spelling in this chapter
is provisional.

(You'll want `core-model.md` first: opens, collects, case splits,
join, value wires vs flow wires. This chapter also leans on
end-when (`end-when-design.md`, adopted), the register pair
(`iteration-with-state-design.md`), the race barrier
(`race-barrier-design.md`, exploration), and the owned-order
criterion (`delay-ontology-design.md`, adopted); each is recalled
where it is used.)

## The program with no home

Merging two sorted lists is the record's standing example of a loop
the vocabulary cannot draw (`tough-use-cases-design.md`, use case 3,
obstruction 1). Walk both lists with a cursor each; compare heads;
emit the smaller; advance that cursor; repeat. The diagnosis there
was precise: **no input flow drives this iteration.** Neither list's
own walk is the loop — each cursor advances only when the *decision*
says so — and iteration driven by the output's demand is
corecursion, exactly what the language declines to hand users raw.
The honest expression with existing blocks is a self-driven stream
whose carried state is a pair of cursor indices: legal, and
unreadable — "the assembly language of iteration."

That diagnosis named the missing construct (the decision-driven
merge: two flows in, a per-step chooser picks which side advances)
and sketched the chooser as a configuration scope, like sort's
comparator. This round starts from the sketch and asks the question
`variable-rate-consumption-design.md` left pointed at it: the other
two members of the old "advance family" dissolved their choosers —
advance-or-stop became end-when's drawn alt flow, advance-how-far
became split-when's drawn boundary — so *does the merge's chooser
dissolve too? Is the interleaving something drawn, rather than
something decided?*

It does, and it is. Here is the construct that remains once
everything drawable is removed from it.

## The construct: a walk over cursors

**The decision-driven merge is a node with k ≥ 2 subject flows, and
it mints a walk.** (Call the node `merge` for now; naming is
deferred, and "merge" here always means this node, not the async
catalog block, which reappears below as an instance.) Its outputs:

- **The step flow** `~M` — a new flow, one firing per step of the
  walk. Its order is *minted* by the merge: this is the "Minted" row
  of the owned-order taxonomy (`delay-ontology-design.md`, "where an
  order comes from"), so registers and running views are legal on
  `~M` by the ordinary rules. That fact is load-bearing below.
- **One head per subject** — a per-step value port exposing the
  subject's next unconsumed element. A head is option-kind relative
  to `~M` (the sense `partial-collect-design.md` defines): at steps
  where its subject still has elements it fires with that element;
  past exhaustion it does not fire. A head that nobody advances
  holds the *same* element at the next step — heads are cursor
  state, not fresh draws.

And one **late-wired operand**, in the same two-phase form as the
register's write half (`step of sum`, the read half's binder named
by the write half):

- **The advance operand** — for each subject, an alt flow wired back
  into the merge (`advance of <head>`, spelling provisional). A
  firing of subject *i*'s advance lane at a step means: subject
  *i*'s cursor moves past the element its head held. The next step's
  head for that side is the following element (or nothing, if that
  was the last).

Everything the construct means is one law:

> **The law of the walk.** The step flow's first firing exposes each
> subject's first element on its head. Each subsequent firing exists
> exactly when at least one advance lane fired at the previous step,
> and its heads reflect the consumption: advanced sides move to
> their next element, unadvanced sides hold. The step flow ends —
> terminator `RanOut` — at the step where no head fires (every
> subject exhausted). Subject terminators propagate through their
> heads by the ordinary failability rule.

Note what the law does *not* mention: a comparator, a verdict, an
emission, a stop condition, fairness. None of those belong to the
node. The merge contributes the two things no drawn vocabulary can
supply — the meeting point (heads coexisting at one context) and the
minted order (steps happen one at a time, in a definite sequence) —
and everything else is wiring.

## The mergesort merge, drawn

The everyday sorted two-way merge, in provisional spelling:

```
-- spelling provisional throughout
a, b -> merge => ha, hb, ~M          -- heads + the step flow

-- the decision: ordinary wiring from the heads
split present ha, hb of Both, OnlyA, OnlyB    -- presence configuration
  Both:  ha, hb -> le -> split of TakeA, TakeB
           TakeA: -~> advance of ha
           TakeB: -~> advance of hb
  OnlyA: -~> advance of ha          -- b exhausted: drain a
  OnlyB: -~> advance of hb          -- a exhausted: drain b

-- the emission: an ordinary collect over the step flow
~M -~> collect => merged             -- lane per arm, each lane the taken head
  TakeA | OnlyA: ha
  TakeB | OnlyB: hb
```

Read it in three layers.

- **The decision is a case split**, and nothing else. "Compare the
  heads" is `le` feeding a split — the same wiring a filter's
  condition uses, consumed by a different port. The presence
  configuration (both heads, only one) is the ordinary option/
  coverage vocabulary over two option-kind flows; its compact
  textual spelling is owed (open question 3), but nothing about it
  is new semantics. The exhaustion arms are where drain-vs-stop
  is *drawn*: this program drains the survivor; the next section
  stops instead. Zig's `while … else` made the same point about
  readouts — programs genuinely differ here, so the construct must
  not decide it for them (see the auto-drain dead end below).
- **The emission is a collect.** The merged list is a covering
  collect over the step flow whose per-arm value is the taken head —
  the same cell-set collect shape as the HTTP program in
  `partial-collect-design.md`. The merge node has no "output value"
  port at all: what comes out of the walk is whatever you collect
  from `~M`, one value or several (a multi-wire collect yields the
  merged values *and* a which-side lane *and* a running index, if
  you want them — no packing).
- **The advance is the write half.** Each split arm wires the lane
  that advances its side. Exactly the register's two-phase shape:
  the read half exposes state (`prev` there, heads here), ordinary
  wiring computes with it, the write half closes the cycle. The
  cycle is legal because it crosses the merge, as the register's is
  legal because it crosses the Delay.

The elements pass through as themselves — no pair packed to cross
the decision (product bottleneck), no tagged union packed to carry
"which side won" (sum bottleneck; the arms *are* the cells, and a
consumer that wants per-side treatment consumes them separately
instead of collecting the covering merge).

## Theorems of the law

Each of these is a consequence, not extra design:

- **Termination is structural for finite subjects.** Every step but
  the last consumes at least one element (the next step exists only
  if an advance fired), and consumption is bounded by the subjects'
  combined extent. The cursor-progress measure that the divide flow
  must *check* (`divide-flow-design.md`, the second measure species)
  holds here *by construction*: a spinning walk — a step that
  advances nothing and expects a next step — is not ill-formed, it
  is undrawable. This is the same style of result as speculation's
  "restoration is not an operation": the property the field
  hand-checks is emergent from the shape.
- **Stopping is end-when, not a feature.** "Merge until the first
  side exhausts" (don't drain), "merge until the outputs cross a
  threshold," "take the first n of the merge" — all are end-when
  (or the take family) applied to `~M` or to a collect over it, with
  the stop condition drawn from the heads, the arms, or a register,
  like any other stop condition. In the example above, replace the
  `OnlyA`/`OnlyB` arms' advances with an alt feeding
  `end-when(~M, ·)` and the walk stops at the first exhaustion,
  terminator carrying which side survived. The law needs no stop
  verdict, because a step nobody demands never runs: consumers
  collect the shortened flow, and laziness does the rest ("the walk
  itself is untouched," `end-when-design.md`, applies verbatim).
  This answers end-when's open question 3 more strongly than the
  question hoped: the merge's stop does not *share vocabulary with*
  end-when's terminator — it **is** end-when, the same node drawn
  on the step flow. There is no verdict inventory left to align.
- **The heads are the lawful meeting point.** Combining a value from
  flow A's walk with one from flow B's walk is the alignment clash —
  sibling contexts, witnessed as time travel or bundle mixing. The
  heads do not clash: they are minted value ports at `~M`'s own
  context (the barrier-value-crossing "mint" mechanism, the same row
  as the partial collect's merged value), so `ha, hb -> le` is two
  values combining at one context. The merge does for *siblinghood*
  what the Delay does for *pastness*: it mints the one drawn place
  where values that could otherwise never lawfully meet, meet. That
  is what makes it a barrier and not a nesting: subject interiors
  are not open at `~M` — only the heads cross, plus anything
  admitted by the ordinary prefix rule.
- **Owning the order and choosing it are separate** — the split
  `delay-ontology-design.md` recorded, cashed. The merge *owns* the
  step order (mints it; registers legal). The drawn advance wiring
  *chooses* it — which interleaving of the subjects' elements the
  order is. Fairness, priority, alternation are choice laws, and
  choice laws are drawings, not modes.

## The family, member by member

**The ordered merge** is the drawing above: decision by comparison.
Its derived lowering is the cursor-register program the tough doc
wrote out — still correct, still nobody's reading material. The
everyday packaging is a catalog block, `merge by <op>` (spelling
provisional, beside `collect by <op>` in the collect family's
strawman table): sorted-drain semantics, the comparator wired the
way sort's key is. The 80/20 counterweight sits exactly here: the
sorted merge must be *effortless* (the catalog block), while the raw
walk is the *breadth* form that keeps every variant drawable — stop
instead of drain, dedup ties, emit indices, three-way merges.

**The async merge** is the same node with the decision drawn by
*time*: the heads of async subjects are per-step cells, and "decide
by arrival" is a **race of the heads** — race's winner bundle is
per-step, one cell per contender, which is exactly the shape the
advance operand consumes. Wire winner-A to `advance of ha`,
winner-B to `advance of hb`, collect the covering merge. The
record's two deciders — "chooser by comparison" and "chooser by
arrival" (`tough-use-cases-design.md`) — turn out to be two
*constructs in the decision position*: a case split reads the heads'
values; a race reads their settlement. The head-persistence rule
("unadvanced sides hold") is race-barrier's carried loser cell,
stated once at the walk level instead of per lowering. The async
merge stays a catalog block (`race-barrier-design.md` stands
unchanged); what this round adds is that its lowering is now a
*drawing* — the raw merge with a race in the decision — rather than
only an emitted corecursion.

**Fairness** is a drawn decision that reads state, and the state
lives where the owned order is: on `~M`. Alternation is a register
on the step flow (carrying which side went last) read by the
decision — prefer the other side when both heads are ready.
Round-robin over k sides is the same register mod k. The greedy
behaviour race-barrier documents for the lowered async merge (a
constantly-ready side starves a settled sibling *of emission order*,
never of its element) is simply the *register-free* decision; adding
the register is the +1 step, and the drawing says which policy holds
— no knob (see the dead end below). One fairness variant is not
expressible with data in hand today: **oldest-settlement-first**
needs to compare *when* the heads settled, and settlement time is
incidental runtime order, not a drawn value. Making it one is the
settle node's move (convert incidental order into drawn content —
`concurrent-collect-design.md`); whether a settled-at stamp is worth
a catalog row is open question 5, not silently assumed.

**Cross-client arbitration** (`served-flow-design.md`, question 2)
is this construct at a serving boundary. A provider bound at two
boundaries receives the merged exchanges; per-client order is each
client's handle; cross-client order is whoever interleaved the
exchange flows. The answer the merge gives: **if the program wants
to own that order, it draws the merge** — two client exchange flows
as subjects, the provider consuming `~M`'s covering merge. Decision
by arrival (a race of heads) is the neutral default; priority is a
decision reading the request payloads on the heads (data, not
policy); fair-share is the alternation register. An *undrawn*
arbitration — the provider simply bound twice — is the serving
block's ambient arrival order, kind content documented on its
catalog row (the "Ambient" row of the owned-order taxonomy), which
is honest for programs that don't care. What no longer exists is a
third place for arbitration to live: it is either drawn upstream of
the provider or ambient at the edge, never a hidden property of the
provider itself.

**Concatenation, incidentally.** "Advance A while present, then B"
is a decision that ignores the heads' values entirely — the merge
with the trivial choice law is concat. Not proposed as concat's
surface (a drawn sequential join is simpler); recorded because it
locates the construct: the merge is the general *interleave*, and
every deterministic interleaving of k flows is some drawn decision.

**Two non-members**, confirming the family's boundaries:

- **End-when and split-when** stay where their rounds put them.
  Semantically a one-subject merge whose decision is advance-or-stop
  *is* end-when — the degenerate identification the record already
  considered — and the derivation still runs the other way, for the
  recorded 80/20 reason: eighteen of sixty sampled loops must not
  pay for the merge's generality. The merge is accordingly bounded
  at k ≥ 2: with one subject there is no choice, and the one-cursor
  shapes belong to end-when, split-when, and the cut root. What the
  family shares is now *structural* rather than vocabular: one
  option-kind operand discipline (stop alts, boundary alts, advance
  lanes), one terminator (stop *is* end-when's node), one law style.
- **Heuristic-order speculation** (`speculation-design.md`, question
  5) is not a chooser, and dissolves twice over. Raku's `|`
  (best-match) decides *after* the attempts: that is the all-results
  reconvergence already in speculation's +1 ladder, followed by an
  ordinary judged reduce (argmax by token length) — value
  vocabulary, no new construct. Trying alternatives in a *computed*
  order before attempting decides from data in hand, and splits by
  what the alternatives are: **homogeneous** alternatives (same
  computation, different parameter — try mirrors in latency order)
  are a flow of parameter values, so computed-order trial is `sort`
  + the walk + end-when on first success — three existing pieces;
  **heterogeneous** drawn alternatives under a computed total order
  would need k! dispatch to draw honestly, and that is the tell that
  drawn order *is* the construct's meaning — speculation's contract,
  not a parameter of it. The bridge the speculation round saw is
  real but runs through existing vocabulary; nothing lands here.

## What dissolved, and what the sketch got right

The chooser sketch said: "a configuration scope, like sort's
comparator — exposing the two current heads, the user wires the
decision." The instinct was right and survives whole: the decision
is *wired, never passed* — no comparator value, no lambda
(`configuration-scopes.md`'s rejection stands). What the round
removes is the residual *thing*: there is no chooser operand
species, no verdict vocabulary, no per-heads decision protocol. The
heads are ports; the decision is whatever ordinary constructs the
program draws between them; the advance lanes are where the wiring
lands. The variable-rate round's conjecture — "if the merge's round
finds its chooser wanting the same dissolution, the family gets
simpler still" — is confirmed on the same grounds as its own:
the interleaving is drawn, and the leaning it recorded (**no N-head
chooser primitive at the surface**) is not just kept but sharpened —
there is no N-head chooser *anywhere*, surface or lowering; the
lowering's chooser was the corecursive costume of a case split.

Now, you might wonder whether the decision should be a **verdict
value** after all — let the wired computation return
`TakeA | TakeB | Stop` and have the merge interpret it, the way a
comparator returns an ordering. It turns out this fails three ways
the record already owns, and they are exactly end-when's three (its
boolean-operand rejection, one level up): it mints a tagged union
whose only job is to cross into the node — the sum bottleneck, in a
family whose sibling (race) exists to dissolve precisely that; it
introduces a second condition vocabulary beside case splits (the
same comparison drawn one way to filter, another way to merge); and
it detaches the choice from its consequence, so "exactly one verdict
per step, and TakeA only when ha is present" become protocol rules
the checker must state, where the alt-flow form makes them coverage
and provenance facts it already checks — an advance lane downstream
of its own head *cannot* fire without the element in hand. (This is
a recorded dead end — please don't re-propose it without new
evidence.)

You might also wonder whether the merge should carry a **fairness
mode** — `merge(a, b, policy: alternate)` — since fairness variants
are surely common enough to deserve a flag. It turns out this is
race's fairness-knob dead end arriving one construct later, and the
answer strengthens: here the policies are not just specifiable but
*drawable* (a register on `~M` and two arms), so a mode would
duplicate drawn vocabulary as annotation — the policy would sit in
a dropdown while the drawing claims greedy, exactly the
two-sources-of-truth shape the record refuses everywhere. Policies
are decisions; decisions are drawings. (Recorded dead end.)

You might wonder whether the merge should **auto-drain** — consult
the decision only when both heads are present, and advance the
survivor unasked, since every sorted merge ends with a drain. It
turns out the exhaustion arms are exactly where real programs
differ — drain (mergesort), stop (merge-join on the shorter input),
switch strategies (grammar fallback), fail (strict zip-shaped
consumers) — and a construct that hard-wires one reading makes the
others modes or rewrites. Zig's loop `else` is the field's testimony
that the readout at exhaustion is program content, and the collect
family's availability ladder made the same call against defaulting
the empty case. The everyday drain lives one level up, in the
`merge by <op>` catalog block, where a default is a *derived*
drawing you can expand — not a meaning the primitive imposes.
(Recorded dead end.)

And you might wonder whether the merge needs a **stop lane** of its
own — a (k+1)-th advance alternative meaning "end the walk here,"
so that merge-until is self-contained. It turns out this duplicates
end-when inside the node for no structural gain: the stop alt would
write the same terminator, carry the same payload, and obey the same
option-kind discipline, but now the terminator-writing family has a
hidden fourth member and "one construct, one job" is broken for
symmetry's sake. End-when on the step flow already composes, the
laziness argument makes it exact (nothing past the cut is ever
pulled), and the drawing keeps stop conditions in one vocabulary.
(Recorded dead end.)

## By kind, and the compile

Sketches only; nothing here touches `src/`, and implementation sits
behind streams and async cells in the recorded dependency order.

- **Eager subjects (lists).** The lowering is the classical merge
  loop: cursors as locals, the decision split's arms as the branch
  body, arms' collects as pushes. The step flow needs no
  materialisation — it is the loop's iteration count. This is the
  strong-form philosophy argument again: the derived lowering is
  verbatim the code the field writes by hand, and nobody reads it
  unless they ask.
- **Stream subjects.** The step flow is pull-driven: each pull runs
  one decision, pulls at most the advanced heads' successors, and
  the unadvanced head is the carried cell — the `Delayed`
  memoisation gives head-persistence for free. Pull amplification
  is bounded by the law (one advance = one upstream pull); the
  retention footgun is the *unadvanced* head held across a long
  run of opposite-side advances, which is the same one the stream
  docs already track.
- **Async subjects.** The per-step race compiles exactly as
  race-barrier sketched the merge lowering — `Promise.race` of the
  head cells, drawn-order ties — with the winner's arm advancing.
  The step flow is event-loop-clocked; registers on it are the
  legal-by-owned-order case the delay-ontology round already
  cashed.
- **The step flow's kind** is derived from the subjects' (all-eager
  → pulled/stream; any async → async), the same style of rule as
  the any-list rule. The exact table is open question 4.

## How this squares with the design principles

- **Example first.** The construct was extracted from mergesort's
  merge — the record's oldest unplaceable program — and the members
  are the sampled shapes (survey 3's interleavings, the serving
  boundary), not invented generality.
- **No bottlenecks.** Heads cross as themselves; the arms are cells,
  not tags; the merged output is a collect the program draws, wide
  if it wants. Both bottleneck species were candidate designs here
  and both are recorded dead ends (the verdict enum; and packing
  head-pairs to cross a comparator).
- **Inside-out.** The decision is not a scope with magic names: the
  heads are ordinary named ports, the decision is ordinary exterior
  wiring, and the write half closes the cycle exactly as the
  register's does.
- **Building blocks must build.** The +1 ladder: drain merge (the
  catalog block) → *open the block* = the raw walk → +end-when =
  merge-until → +register = alternation/fair-share → +race decision
  = async merge → +k subjects = k-way → drawn at a serving boundary
  = arbitration. No rung rewrites the previous drawing.
- **Abstraction is the source of truth.** `merge by <op>`, the async
  merge, and interrupt stay catalog blocks; their lowerings are now
  drawings in this vocabulary (walk + decision), one drop-down away,
  and the corecursive cursor-register program is the lowering *of
  the drawing*, two levels down and still never anyone's authoring
  surface.
- **What does it mean?** The ontological sentence exists: *the merge
  is the drawn meeting point of sibling flows — it mints the one
  context where their elements lawfully coexist, and the drawn
  choice of interleaving is the program content; everything else is
  ordinary vocabulary at that context.* The Delay analogy (meeting
  point for pastness :: merge for siblinghood) is what made the
  heads' legality obvious rather than special-cased.

## The dead ends, indexed

All recorded in place above, each with the reason it must not be
re-proposed. The index:

1. **The verdict-value chooser** (returned `TakeA|TakeB|Stop` enum)
   — "What dissolved," first passage.
2. **A fairness mode/knob on the merge** — second passage; extends
   `race-barrier-design.md` dead end 1.
3. **Auto-drain (consult-the-decision-only-on-real-choice)** —
   third passage.
4. **A stop lane on the merge node** — fourth passage.
5. Inherited, not re-litigated: the comparator as a passed function
   value (`configuration-scopes.md`); the N-head chooser surface
   primitive (`variable-rate-consumption-design.md`, sharpened here
   to no-chooser-anywhere); timeout/fairness knobs on race
   (`race-barrier-design.md`).

## Open questions

The language hasn't decided any of these yet.

1. **Adoption.** The whole chapter is prepared for the design
   conversation; nothing is marked decided. Natural agenda: the
   walk law, the k ≥ 2 boundary, stop-is-end-when, and the
   dissolution claim itself.
2. **The advance operand's fine print.** At-least-one vs exactly-one
   advance per step: sort-merge-join's tie case wants *both* sides
   advanced in one step (emit once, or once per side, or a pair —
   the join client should be worked before this is fixed). The
   current law says at-least-one; the disjointness/coverage
   discipline for advance lanes should be stated with the same care
   as the partial collect's.
3. **Spellings.** `merge`, the head binders, `advance of` (jointly
   with the late-wired-operand family — `step of`, `boundary of`,
   `value of` — the textual catch-up already owes), the presence-
   configuration split over option-kind heads (the one genuinely
   awkward spelling in the examples above), and `merge by <op>`'s
   place in the collect family's strawman table.
4. **The step flow's kind table.** Derived from subject kinds
   (sketch above); the eager/pulled seam and whether an all-list
   merge may compile to a materialised list without a stream in
   sight. Decide with the compile round, not here.
5. **The settled-at datum.** Oldest-settlement-first fairness needs
   settlement time as drawn data; a runtime-minted stamp is the
   settle-node move applied to cells. Whether any sampled program
   wants it (survey 3 found none) decides if the catalog row exists
   at all — sample before assuming.
6. **Failure at a head.** Propagate-by-default is the law's answer
   (a failing subject fails the walk through its head), but
   drain-then-report wants the failure *discharged at the head* and
   carried as data while the other side drains. Whether a head is a
   discharge site, and what its inventory looks like, is joint with
   `failure-payloads-design.md`'s inventory account.
7. **The cut seam.** A head is a (payload, rest) reading of its
   subject — the cut's shape (`variable-rate-consumption-design.md`,
   the root decision). Whether the merge's subject ports should
   consume *cuts* (making the merge a client of the cut round's
   continuation form) or stay flow ports with head semantics stated
   here, should be settled when the cut round lands; the law was
   written to survive either answer.
8. **Multi-close of one walk.** One merge, one advance wiring (write
   count 1, like the register); a second interleaving of the same
   subjects is a second merge. Confirm that two merges over shared
   subjects are two independent consumers under multi-close, and
   what sharing (if any) the compile may recover.
9. **Evidence.** The application-level concurrency sample
   (`real-loop-survey.md`, "Next round") should carry this round's
   frequency questions: how often application code interleaves by
   data (merge-join shapes, sorted-stream unions) vs by time, and
   whether arbitration at serving boundaries is ever drawn or always
   ambient. Per the standing method, sample before the adoption
   conversation treats importance as measured.
10. **Naming.** "Merge" collides with the async catalog block and
    with `Poset.merge`; "walk," "interleave," "loom" and friends —
    deferred to the naming sweep.

## Prior art

- **Sort-merge join** (every RDBMS): the two-cursor walk with
  advance-both on ties — the strongest field witness for question
  2's tie case, and for the walk's totality (join implementations
  hand-prove the progress property the law here gives structurally).
- **`heapq.merge` / `sort -m`**: k-way ordered merge as everyday
  tooling — the k ≥ 2 generality is shipped practice, not
  speculation.
- **CSP external choice / Go's `select`**: choice among ready
  communications, re-run per step; Go documents pseudo-random
  tie-breaking — a runtime policy exactly where this design puts a
  drawing (and race puts drawn order). A `select` in a loop with
  per-case state updates is the async merge with a register
  decision, hand-rolled.
- **Erlang's selective receive**: arbitration by pattern over
  waiting messages — data-decided cross-client arbitration in the
  field, supporting "priority is a decision reading the heads, not
  an edge policy."
- **RxJS `merge` vs `concat` vs `race`**: the arrival decision, the
  trivial decision, and the one-shot, shipped as three opaque
  operators — the operator-zoo costume of one walk with three
  drawn decisions.
- **Raku `||` vs `|`**: drawn-order trial vs best-match — consumed
  above as speculation's ladder plus a judged reduce, not a chooser.
- **Zig `while … else`**: the exhaustion readout as program syntax —
  the auto-drain dead end's field witness.
