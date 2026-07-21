# Saturation: closure under rules

Status: exploration — this chapter teaches a first worked round with
stated leanings; none of it has been adopted, and none of it is
implemented. Read it as "here is a candidate construct and the case
for it." It also presumes several pieces that are themselves not
built yet: the register (`iteration-with-state-design.md`), the
self-driven opener (`source-openers-design.md`), the keyed collect
(`collect-family-design.md`), and Cross (`product-flows-design.md`).
Spellings are provisional strawmen; naming is deferred.

## The shape: keep going until nothing new appears

Suppose you have a set of edges and want to know which nodes can
reach which. You know the direct edges. And whenever `x` reaches `y`
and there's an edge from `y` to `z`, then `x` reaches `z` — a new
fact, which may in turn enable further facts. Keep applying that rule
until no application produces anything you don't already have. The
final, closed set is your answer.

In conventional code you would write a **frontier/worklist loop**:
seed a queue and a seen-set, pop an item, derive its consequences,
test each against seen, push the new ones, halt when the queue
drains. But notice what you actually *stated*: some seed facts, some
rules that derive facts from facts, and "keep going until the
derivable set is closed." The queue and the seen-set are bookkeeping
— the assembly language of that declarative statement, the same
diagnosis the record has made for the flag (end-when's terminator),
the count (a boundary), and the state machine (a phase structure).
Computing the closed set is called **saturation** (equivalently:
computing the *closure* of the seed set under the rules). This round
asks what the declarative construct is.

The same one shape covers a lot: graph reachability, transitive
closure, cycle detection, topological sort, 2-SAT, class-hierarchy
and taint analyses, dependency resolution, dataflow and program
analysis. Flix ships it as first-class Datalog and reachability is
three lines (`flix-comparison.md`, example 1).

Where does this show up in real code? Honesty first
(`flix-comparison.md`): no closure/saturation shape appeared in the
three random surveys. The everyday clients are domain-concentrated —
package/build/import tooling, program analysis, graph features inside
products. So this is a **breadth obligation**, not an effortlessness
demand; the frequency question is on the evidence-owed list and does
not gate the design.

## One round is already drawable

Before inventing anything, notice how much of a rule the language can
already draw. Take reachability's step rule, in Datalog spelling:

```
Reach(x, z) :- Reach(x, y), Edge(y, z).
```

Take it apart, and most of it is vocabulary the record already has:

- `Reach(x, y)` and `Edge(y, z)` are two **uncollects** over fact
  sets — open the `Reach` set and the `Edge` set, each into a
  per-tuple flow.
- The shared variable `y` is **not a free wire**: the two relations
  are opened independently (sibling flows), so pairing them is a
  **Cross** (`product-flows-design.md`) filtered to the firings where
  `Reach`'s second component equals `Edge`'s first (the equality is
  an ordinary case-alt filter, `join(list, case flow)`,
  `core-model.md`). Name coincidence in Datalog *is* the equijoin —
  the databases' pair-rows-on-equal-fields operation — and the
  equijoin is Cross-plus-equality-filter. (Flix spells the constraint
  by name; the drawn form is two wires meeting at a filter — see the
  clash record.)
- The head `Reach(x, z)` is a **map to a tuple** of the surviving
  components.
- The rule's target is a **set collect** (`-~> collect set`,
  `collect-family-design.md`) — dedup is the set's job.

Several rules feeding one relation are several derivation
sub-diagrams **tapped into one collect** (`core-model.md`,
multi-close): the relation is the union of every rule's output. So
*one round of all rules* — derive every immediate consequence of the
current facts — is a program we can draw today, with no new
construct.

What nothing in the record owns is the **feedback**: the collected
relation is also the opened input of the next round, iterated until
the set stops growing.

## The construct: a flow-level back-edge, the register's dual

Here is the load-bearing claim of this round. You've met one
back-edge already: the **register**
(`iteration-with-state-design.md`) is a back-edge on a **value**
wire, crossing a **Delay** — the previous firing's value returns to
the next firing. Its cycle discipline is *productivity* — every cycle
crosses a register — and it terminates by construction, because the
*extent* of the walk is fixed by the opened data (a list of n
elements fires n times, whatever the carried value does).

**Saturation is the same move one level up: a back-edge on a *flow*
wire, crossing a *collect-then-uncollect*.** The collected relation
(a set collect) is re-opened as the next round's input; the loop
closes at the flow level, not the value level. This is exactly
"feedback at the flow level" (`flix-comparison.md`): the *extent of
iteration itself* is fed back — the firings of round n+1 are minted
by the facts round n derived.

The dual lines up point for point:

| | register | saturation |
|---|---|---|
| back-edge on | a value wire | a flow wire |
| crosses | a Delay | a set collect, re-opened |
| cycle discipline | every cycle crosses a Delay (productivity) | every cycle crosses a **dedup collect** |
| extent | fixed by the opened data | **grows** — new members mint new firings |
| terminates | by construction (fixed extent) | when the set stops growing (**not** by construction) |

The dedup collect is load-bearing in two ways at once. It is what
makes the loop **monotone** — each round's set includes the last
(facts are only added), so the sequence of sets is increasing. And it
is what makes the loop **converge** — a fact already in the set does
not re-fire, so once a round adds nothing, no future round can (the
rules are the same and the input is the same). "The set stopped
growing" is therefore a genuine fixpoint test, and it is the
flow-level analogue of the register's productivity check: where the
register demands *every cycle crosses a Delay* (so state can't be
skipped), saturation demands *every flow cycle crosses a dedup
collect* (so the loop is monotone and can converge).

(The two-point map briefly gained a third point — an earlier working
of `effects-design.md` read the threaded IO handle as a register
carrying a **marker** wire across a Delay. That reading is since
dissolved: effects are now the list/IO sequencing commute, no Delay
involved, and the map is two-point again — value back-edge, flow
back-edge.)

Here is a strawman spelling of reachability with the feedback drawn
(doubly provisional — the visual form of a flow back-edge, like the
register's write half, is the hard part and belongs to the layout
side; this is only to fix the pieces):

```
edges -> open list -~> collect set => reach0    -- seed: Reach = Edge
saturate init reach0 => reach                   -- read half: the current relation, per round
reach -> open set => x, y                       -- reopen the current relation
edges -> open list => y2, z
x, y2 -> eq => hit                              -- the shared variable: an equality filter
(x, y), (y2, z) ~> cross -> keep(hit) -> pair(x, z)
-~> collect set -> feed of reach                -- write half: union the round's facts back
```

*`saturate` is the flow-level counterpart of `delay`, spelled with
the same two-statement read/write discipline (mint the read, wire the
feedback later — token order stays time, names stay
single-assignment): `init` seeds the relation, the read half exposes
the current relation per round, the body derives one round's
consequences into a set collect, and `feed of` deposits the collected
set as the next round's relation. Saturation halts when a round's
collect adds nothing new. The `pair(x, z)` is a genuine relation fact
— data the set stores — not a structure packed to cross the Cross;
the no-bottleneck principle polices packing at barriers, not tuples
as values.*

The point is not the spelling but that the pieces are the register's
pieces raised one level: `init` is the seed (the register's initial
value), the body is one round (the register's step), and the
back-edge is a flow wire through a set collect (the register's value
wire through a Delay).

## Naive and semi-naive are lowerings, not two constructs

You may have noticed something wasteful about the reading above:
reopening the *whole* relation each round re-derives every old fact
from every old fact, which can add nothing. The frontier/worklist the
imperative version reaches for is precisely the fix — the
**semi-naive** evaluation strategy: fire the rules only on the facts
*newly added* last round (the frontier/delta), not the whole set. The
straightforward whole-set reading is **naive** evaluation, which
recomputes everything every round.

These are two *lowerings* — two translations of one declared
construct into a more concrete running form — and the choice between
them is the compiler's, not the programmer's. That is the same stance
as the lazy compile ("decide almost nothing about placement,"
`lazy-compile-design.md`) and principle 6 (abstraction is the source
of truth; concreteness is a derived view). The programmer draws the
flow back-edge and the rules; whether the runtime keeps a delta and
fires only on it is a lowering. Exposing the frontier would
re-surface the assembly language the construct exists to remove.

This matters for the record's honesty. It means "saturation is
drawable as a whole-set register today" (below) and "saturation
deserves its own construct" are *both* true and not in tension: the
register lowering is the naive strategy written by hand; the
construct earns its name by also admitting the semi-naive one and by
carrying provenance (below), neither of which the hand-rolled
whole-set register expresses.

## Isn't this just a register carrying the whole set?

Now, you might wonder why the language needs a new construct at all.
Isn't a saturation just "a register whose carried value is the whole
set, on a self-driven flow, with end-when on `set == prev set`"? The
reduction is tempting, and `source-openers-design.md` records exactly
this shape for the scalar case — APL's `f⍣≡`, iterate a function to a
fixpoint, "is a register on a self-driven flow with end-when on
`state = prev state`."

The reduction is real, but it turns out to be the **degenerate**
reading, and keeping the two distinct is the point:

- `f⍣≡` carries **one opaque value** and asks "did the value stop
  changing." It has no notion of *members*, so it cannot fire per new
  fact (no semi-naive), and it cannot say *why* a value is what it is
  (no provenance). It is the right construct when the state genuinely
  is one value converging (a relaxation step, Newton's method).
- Saturation carries a **set whose members are the flow**. The loop
  is at the level of set membership, which is what lets a round fire
  per newly-derived fact and what lets a member point back at the
  firings that produced it.

So the whole-set register is to saturation what a fold-to-a-scalar is
to `open list` — the collapsed special case, legitimate and sometimes
what you want, but not the general construct. (Note this carefully:
the whole-set register is *kept as the degenerate neighbour*, not
rejected — what's rejected below is only making it the *primary*
reading.) The seam is the one source-openers already flagged (`f⍣n`
counted vs `f⍣≡` to-fixpoint): the register handles the case where
the state is a value; saturation handles the case where the state is
a *set the loop is enumerating*.

## The lattice variant: keyed-merge saturation

Reachability collects to a plain set — dedup by identity. Analyses
want more: shortest-distance keeps, per node, the *minimum* distance
seen, updating it downward as shorter paths are found. Flix spells
this with lattice semantics — `Dist(x; d)` merges duplicate keys by
greatest-lower-bound (`flix-comparison.md`).

This is not a new mechanism. It is the **keyed collect merging by a
lawful operator** (`collect-family-design.md`) sitting where the set
collect sat. Saturation's back-edge is parameterized by its collect:

- **set-union collect** → plain closure (reachability, transitive
  closure). Merge is set-union; identity ∅; monotone by inclusion.
- **keyed collect by ⊕** → lattice analysis. Shortest-distance is
  keyed-**min**-collect; `collect-family-design.md` establishes min
  as a per-lane-total semigroup (lanes non-empty by construction),
  which is exactly what keyed-min-collect needs. Merge is per-key ⊕;
  monotone in the lattice order.

Shortest-distance *is* keyed-min-collect plus this feedback, nothing
else. In the same provisional spelling, single-source shortest
distance over a weighted edge set:

```
src -> pair(0) -~> collect keyed by min => d0   -- seed: {src: 0}
saturate init d0 => dist                        -- read half: current distances
dist -> open keyed => n, dn                     -- per known node: name, distance
edges -> open list => a, b, w                   -- per edge: from, to, weight
n, a -> eq => hit
(n, dn), (a, b, w) ~> cross -> keep(hit)
-> pair(b, dn + w)                              -- a candidate distance for b
-~> collect keyed by min -> feed of dist        -- write half: per-key min merge
```

Rounds stop when no key's value drops — the same halt test, read in
the lattice order. Two things generalize with the swap:

1. The termination test broadens from "no new members" to "no member
   **changed** value" — the keyed map reached a fixpoint in the
   lattice order (a key's value may drop without any key being
   added). This is still "the set stopped growing," read in the
   lattice's order rather than set inclusion, and it is still the
   dedup collect doing the monotonicity bookkeeping.
2. Convergence now needs the lattice to be **bounded-height** (values
   can only descend finitely), the standard Datalog-with-lattices
   condition. The set case is the special lattice (the powerset
   ordered by inclusion, bounded by the finite fact universe).

So the collect family supplies saturation's whole aggregation axis
for free, and the two paradigms — group-by and closure — meet at the
keyed collect: one as a single pass, the other as that pass under a
flow back-edge.

## Provenance: explanation as a derived view

Once you have a closed set, a natural next question is not "what is
derivable" but *why* — which witness facts sit behind a derived fact.
Flix's `pquery` answers exactly that (`flix-comparison.md`). Whatever
owns saturation must say what an explanation of a fixpoint member
*is* — and here the flow-level framing pays off, because the record
already wants **drawable witnesses** (`types-design.md`) and
derivation that is **free and downward** (principle 6).

The leaning: a firing that derives a fact F is fed by the firings
that produced F's inputs (the two opened tuples the Cross paired).
Following those back-edges transitively yields the sub-DAG of firings
that derived F — that sub-DAG *is* the explanation, and it is a
**derived view** (free, downward), read off the run, never authored.
"Why is F in the closure" highlights that sub-DAG; "why is this the
shortest distance" highlights the ⊕-merge chain that won. This is the
record's drawable-witness instinct surfacing at runtime rather than
at check time.

This is the round's most novel residue and it is a leaning, not a
design: the derived-view catalog, whether an explanation is a value
you can compute on or only a view you can look at, and how it
composes with the semi-naive lowering (the delta *is* the frontier of
the explanation DAG) are open. Filed to the trees/derived-view seam
and `types-design.md`.

## Relationships the round must stay aware of

- **The register — value feedback along a fixed walk.** The dual
  worked above. Saturation is not the register and must not be
  lowered to it as its primary reading (the whole-set-register
  section).
- **The divide flow — recursion over virtual structure**
  (`trees-and-recursion.md`, `tough-use-cases-design.md`). Both
  saturation and the divide flow **mint firings at runtime** —
  neither has an extent fixed by the opened data. The distinction is
  **confluence**: the divide flow spawns a *tree* of firings
  (mergesort's split spawns two fresh independent sub-sorts; no
  firing is shared, termination is at base cases), while saturation's
  minted firings **dedup** against the seen-set, so its firing
  structure is a *DAG* with merges and it terminates at a fixpoint.
  Tree without dedup = divide; DAG with dedup = saturation. They are
  the two runtime-extent shapes, told apart by the collect.
- **The served flow — the top-down dual** (concurrency row; Effekt's
  build system, `flix-comparison.md`, `effekt-comparison.md`). A
  served flow's recursive provider pulls: `need(key)` discovers a
  dependency graph *downward* from a goal, demand-driven, memoized.
  Saturation pushes: seeds derive consequences *upward*,
  exhaustively, deduped. Same graph discovered at runtime, opposite
  direction; the served flow's memo table is saturation's seen-set.
  *The served flow is now worked* (`served-flow-design.md`), and the
  joint working confirms the hinge: memo and seen-set are one
  construct (a keyed collect) written by opposite drivers; the
  uncached recursive provider is the divide flow's tree, and the
  cache is exactly what turns it into this round's dedup DAG.
- **End-when — supplies the reading, not the construct.** "Stop when
  no change" is end-when's shape (`end-when-design.md`), but end-when
  shortens a flow from the consumer side over a per-firing alt;
  saturation's termination is the *fixpoint of a set*, tested by the
  dedup collect adding nothing. End-when reads a stop condition; it
  does not close the flow back-edge.
- **Stratified negation — a nesting of saturations.** A rule that
  references the *absence* of a fact (`Missing(x) :- Required(x), not
  Satisfied(x)`) may only run once `Satisfied` is fully saturated —
  otherwise a later-derived `Satisfied` fact would retroactively
  invalidate a `Missing` conclusion. This is Datalog's
  **stratification**, and it lands cleanly on **no time travel**
  (`core-model.md`): the strata form a fixed nesting of saturation
  loops, decided at construction — an inner saturation completes
  before an outer one reads its negation, and "what is nested is
  nested." A negation wired against a not-yet-closed relation is the
  flow-level version of the time-travel clash. Worked only to this
  sketch here; filed as a scope item.

## Dead ends

Each of these is a question a reader might reasonably ask; each has
been asked and answered in this round. The markers say which are
settled rejections.

**Now, you might wonder why the language doesn't expose the worklist
— the frontier queue and the seen-set — as the user-facing shape,
since that is what everyone writes by hand.** It turns out the whole
demonstration (Flix's Datalog) is that the declarative statement
suffices; the queue and the seen-set are assembly language. The
construct is the flow back-edge; the frontier is a lowering
(semi-naive), never a surface. (Settled rejection as a user-facing
shape — don't re-propose without new evidence.)

**You might wonder why naive and semi-naive aren't two constructs, or
at least a knob the user can turn.** It turns out that would
re-surface the worklist: one declared construct, two lowerings — the
compiler's choice (decide in code). (Settled rejection.)

**You might wonder why the derivation graph isn't materialized as a
value first and fed to ADT tree iteration.** It turns out the
fact-dependency graph exists only as firing structure, discovered at
runtime; forcing it into a value upfront is declaring structure
upfront, which example-first forbids — the same rejection the divide
flow earned against mergesort's virtual split tree
(`trees-and-recursion.md`, "Where the derivation stops"). (Settled
rejection.)

**And you might wonder why the whole-set register isn't the *primary*
reading.** This one is *not* a rejection of the neighbour itself: the
whole-set register is a legitimate lowering and the honest construct
for scalar `f⍣≡`. But as the primary reading it hides the per-member
feedback that semi-naive and provenance both need. Kept as the
degenerate neighbour, not rejected — but not the general form.

## Open questions

The language hasn't decided any of these yet.

1. **Termination is not structural.** Unlike the register (fixed
   extent ⇒ halts), saturation halts only if the fact universe is
   finite and no rule manufactures unboundedly new values (Datalog's
   no-function-symbols condition; lattices must be bounded-height).
   "Every flow cycle crosses a dedup collect" is necessary
   (monotonicity) but not sufficient (convergence). Does the language
   check anything, or is divergence a runtime possibility flagged
   like the tree round's lazy-fallback warning? Leaning: nothing
   static (consistent with "no search," `types-design.md`),
   divergence drawn as a possibility. Open.
2. **The visual form of a flow back-edge.** The register's write half
   already strains the drawing (`iteration-with-state-design.md`); a
   *flow* back-edge through a collect is harder. Out of scope here
   (layout side), but the textual spelling (`saturate init …`) is
   owed to `textual-representation-design.md`.
3. **Provenance's form** (above) — the most novel residue, a leaning
   only.
4. **Stratified negation** — sketched as a nesting under
   no-time-travel; the phase-ordering and the check are unworked.
5. **The served-flow duality** — the seen-set/memo hinge is named;
   the joint design is owed once the served flow is worked.
   *First joint working in `served-flow-design.md`:* memo and
   seen-set as keyed collects written by opposite drivers; which
   construct a program draws is which end names the extent (the
   goal's cone vs the closure — different drawn programs, not
   lowerings of one another); magic sets located as a *recognition*
   between the two drawings (transformation-levels territory, never
   a mode); the explanation sub-DAG and the demand cone identified
   as one derived view read from opposite ends. Leanings, not
   adopted.
6. **Frequency** — evidence owed (a domain sample:
   package/build/import tooling, program analysis, graph features),
   already on the list; informs W, does not gate the design.

## Prior art

Flix's first-class Datalog is the shipped positive witness the whole
round leans on: reachability in three lines, lattice semantics for
analyses, `pquery` for provenance, and — decisively — a fixpoint
block that *composes with ordinary code per call*, not as a separate
language stage (`flix-comparison.md`). The negative witness is every
hand-rolled worklist (the frontier queue + seen-set), the standing
assembly-language diagnosis in another costume. The register/Delay
duality is the record's own (`iteration-with-state-design.md`); the
collect family supplies the lattice axis
(`collect-family-design.md`); the served-flow dual is Effekt's build
system read top-down (`effekt-comparison.md`).
