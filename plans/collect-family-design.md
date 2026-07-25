# The Collect Family: Operator Identities, Named Collects, and the Keyed Collect

Status: mixed — **the availability ladder is adopted** (design
conversation, 2026-07-23): monoid → total, the empty collect
returning the identity carried as a value witness on the catalog
row; semigroup → option-shaped, the result firing iff the walk
fired (where `max`/`min` deliberately live); non-associative → no
reduce-close, the augment form the honest spelling. Both recorded
dead ends were confirmed as rejections at adoption: the empty
collect never runtime-errors (the Dyalog pole), and the catalog
never blesses `-∞`/`+∞` as fake identities. The rest of the
chapter — the named-collect spellings, the keyed collect, the
partition surface — remains exploration; nothing is implemented
(the compiler knows only the list/case/option/filter closes).
Read the unadopted constructs as candidates with the case for
them.

## A first program, and the chapter's first question

You have met the collect that gathers a flow back into a list. Here
is a close cousin — a collect that adds the elements up instead:

```
xs -> open list -~> collect sum => total
```

Each element flows into the collect; instead of accumulating a list,
the collect combines the elements with `+` and yields one number. A
collect that collapses a flow with an operator like this is called a
**reduce-close**. In conventional code this is `reduce` or `fold` —
except that you never wrote a starting value. No `0`, no seed, no
accumulator variable.

So: what is `total` when `xs` is empty? For `sum` the answer feels
obvious — `0`. But try the same question on `collect last` ("the
last value the flow produced"): the last element of an empty flow is
— what? There is no obvious answer, and that question, taken
seriously, organises the first half of this chapter. The second half
takes the same collect vocabulary to the most-requested construct in
the record: group-by.

## What this chapter designs

Three things the record has been requesting under one name, because
the pieces gate each other:

- **Operator identities.** The reduce-close (a close that collapses
  a flow with an associative operator) needs to know an operator's
  identity to be complete. How identities attach — a registry, a
  property, a user-extensible thing — was left open.
- **The collect family's spelling debt.** `collect keyed`, `collect
  set`, `collect last`, `collect any`/`or` are used throughout the
  record and the samples but none is spelled
  (`translation-exercise.md`, finding 6).
- **The keyed collect** — the group-by construct — which four rounds
  of comparison evidence (Flix, XQuery/jq, APL, tidyverse) have
  loaded with structure without a design of its own.

They are one chapter because the named collects *are* catalog
operators (so their spellings depend on how identities attach), the
keyed collect's collision operator is a per-lane reduce-close (so
its totality depends on the identity story), and none of the
spellings can be drafted until the constructs are pinned.

## The words this chapter uses

Defined once, each taught properly where it first matters below. An
**uncollect** (`open`) opens a value into a flow; a **collect**
closes one. A **reduce-close** collapses a flow with a symmetric
associative operator (identity implied, no state variable at the
surface) — the `collect sum` above; an **augment** folds with an
arbitrary asymmetric step `S×E→S`, explicit seed, running value
exposed (`iteration-with-state-design.md`). The **running view** is
a collect's state port over time
(`variable-rate-consumption-design.md`, Part II). **Properties,
demands, offers** are the type machinery of `types-design.md`. A
**bundle** is a partition of a flow's firings into mutually
exclusive lanes; **partial engagement** uses only some
(`bundle-provenance-design.md`, `partial-collect-design.md`).
Spellings in this chapter are provisional; naming is deferred.

## What earlier chapters already settled

Before designing anything, six decisions from other rounds bound the
space. This chapter inherits all of them.

**Reduce-close vs augment is settled.** Two operations: the
reduce-close (symmetric associative operator, identity implied, no
state variable at the surface) and the augment (arbitrary asymmetric
step, explicit seed, running value exposed). The reader can always
tell total-sum from running-sum. Reduce-close is its own result node
carrying the operator's monoid, lowered in compile — that is,
translated to the more concrete seeded-loop form only at compile
time (`iteration-with-state-design.md`).

**Properties attach to operators, not values.** `types-design.md`'s
property table already has the row — *associative, has-identity*,
demanded by reduce-close, offered by operator catalog entries — and
states the identity question is "a question inside this table." So
the answer is a property story, not an annotation story: no program
contains a type, no signature ceremony, no inference-that-chooses.

**No search.** The checker never proves associativity — that is a
theorem about the operator, not a propagatable property. Whatever
attaches the monoid is a *claim*, checked for consistency of use,
trusted for truth (the same stance as JS-boundary assertions).

**Key extraction is ordinary drawn computation.** A key is computed
per firing by ordinary value nodes — never a comparator or extractor
*function* passed as configuration (`configuration-scopes.md`; the
array round's classify-then-place). `cur_column()` is the negative
witness for magic names in key position.

**The running view is defined for every collect** — the state port
of the collect's derived augment form, including read-by-key over a
keyed collect, with strict-prefix causality and the productivity
check (`variable-rate-consumption-design.md`, Part II). This round
inherits it and must not disturb it.

**Partial engagement is owned.** Engaging only some cells of a
bundle needs no special open; terminations are the partial collect's
business (`partial-collect-design.md`). The keyed world lands on the
same stance, not a parallel one.

**No-bottlenecks polices the barrier.** Non-grouping wires must pass
through a keyed partition as themselves — XQuery's "each
non-grouping variable is bound to a sequence" — and its
constant-rebinding bug is the anti-lesson for letting them collapse
to representatives.

---

# Part I: operator identities

## The identity is the value of the empty collect

Start from what an identity is actually *for*. An operator's
identity is needed for exactly one thing: **the value of a
reduce-close over zero firings.** Every other case is determined by
the operator alone. `[a]`→`a` needs `id ⊕ a = a` only to *agree*
with the empty case; the fold itself never consults the identity
when firings exist (the compile lowers to a seeded loop whose seed
is observable only when the body never runs).

So this round adopts the framing: **the identity question is the
empty-collect question.** Asking "what is `+`'s identity?" and "what
is `sum` of an empty flow?" are the same question, and the design
answers the second, because it is stated in the language's own
vocabulary (flows, firings, collects) rather than algebra's.

Three cases, restated in the record's terms:

1. **The operator carries a genuine identity** → the empty collect
   yields it. `sum []` is `0` because `0 ⊕ a = a` genuinely holds.
2. **A seed is supplied** → it is not a reduce-close at all; it is
   the **augment** (explicit seed, asymmetric step), and the empty
   walk yields the seed by pass-through. An optional initial value
   is, in this vocabulary, a *change of construct*, not a parameter.
   No third form exists.
3. **The construct never asks** → the running view (scan): the empty
   walk produces the empty output, and the state port is never read
   because there is no firing to read it at.

Now, you might wonder why the reduce-close can't simply carry its
own empty-flow value — write `collect by myOp`, and attach "and if
the flow is empty, yield this" to the node. It turns out this would
cause problems: that value is just a seed — the augment in disguise;
it collapses the two-operations distinction and un-anchors the
identity from the operator's law (any value could be written, so
`[a]`→`a` no longer falls out). Seeds belong to augment; identities
belong to operators. (This is a settled dead end — please don't
re-propose it without new evidence.)

## The availability ladder: monoid, semigroup, neither

Two algebra words, via examples. An operator that is **associative**
combines the same however you group the steps — `(a+b)+c` equals
`a+(b+c)`. An associative operator *with* an identity value (like
`+` with `0`) is a **monoid**; an associative operator with no
identity (like `last`, which keeps the right operand — what value
`e` could make `last(e, a) = a` *and* `last(a, e) = a`?) is a
**semigroup**.

Now, you might wonder why the language doesn't just raise a runtime
error when a reduce-close by an identity-less operator meets an
empty flow — that is Dyalog APL's shipped answer (DOMAIN ERROR at
runtime). It turns out this would cause problems: it is a runtime
error where structure can carry the absence. The record has a
structural way to say "there may be no answer": the fires-or-not
option shape, which says the same thing statically and is handled
downstream by existing vocabulary. (This is a settled dead end —
please don't re-propose it without new evidence.)

The leaning instead — a **three-tier availability ladder** for
reduce-close, replacing the flat "no monoid, no node":

- **Associative with identity (monoid)** → reduce-close is available
  and its output is **total**. Empty flow → the identity. (`+`→0,
  `×`→1, `and`→true, `or`→false, concat→`[]`, set-union→∅.)
- **Associative without identity (semigroup)** → reduce-close is
  available and its output is **option-shaped**: fires iff the flow
  had at least one firing. `last` of an empty flow is not an error
  and not a sentinel — it is the option's None, honest and
  structural. (`first`, `last`, and — below — `min`/`max`.)
- **Not associative** → no reduce-close. Fall back to augment
  (explicit seed, explicit asymmetry). Unchanged from the original
  decision.

> TODO (simplify): when an augment's step is in fact a catalog
> monoid applied symmetrically, the authored seed restates the
> operator's identity — the same witness the reduce-close already
> infers from. Seed the augment from the catalog in that case, and
> reserve authored seeds for the genuinely asymmetric `S×E→S` steps
> that are augment's reason to exist.

This is the tidyverse `detect`-miss (option-shaped discharge)
adopted as the tier itself, and it is what SQL has always done
(aggregates of an empty group are NULL, except COUNT). The runtime
error disappears: the output's type tells the consumer whether
emptiness is possible, and downstream code handles the option with
ordinary vocabulary (a case split, or the fired-empty completion
where a default is wanted).

**`min`/`max` sit deliberately in the second tier.** You might
wonder why — don't they have identities, −∞ and +∞? It turns out
those numeric identities are representation artifacts — real for JS
floats, absent for a generic ordered value — and a catalog whose
identities depend on the payload's representation would make "total
or option-shaped?" flicker with the wire's shape. So `min`/`max` are
semigroups (option-shaped on empty), and a user who wants the float
behavior writes the augment with a −Infinity seed, visibly. This
keeps every catalog identity a *genuine* identity for every value
the operator accepts. (Putting −∞/+∞ in the catalog is a settled
dead end — please don't re-propose it without new evidence.)

## How identities attach: the catalog row, with the value as witness

The open question "registry, property, or user-extensible thing"
resolves to one answer: **all three are the operator's catalog
entry, carrying the property with its witness value.**

- The property is `associative` (tier 2) or `associative,
  has-identity(v)` (tier 1) — and `has-identity` is not a bare flag:
  it carries the identity **value** `v` as its witness. The offer
  that unlocks a total reduce-close is exactly the value the empty
  collect will yield, sitting in the catalog where it can be shown.
  A reduce-close node displays its operator's identity the way a
  case collect displays its alt coverage.
- The catalog is the same one `types-design.md` already requires for
  the trusted JS edge. Built-in operators ship rows; the starter
  table is small and boring — `+`→0, `×`→1, `and`→true, `or`→false,
  `++`→`[]`, `∪`→∅; `first`/`last`/`min`/`max` associative-only.
- **User extension is an algebra facet.** A user-defined operator is
  a diagram (two ins, one out). Declaring "this is associative,
  identity `e`" is attaching an algebra to it — the manifestation
  `facets-design-notes.md` leans toward working first. The
  declaration is authored and attached, not inferred; the checker
  uses it as an offer; its *truth* is trusted, with the direction of
  doubt stated: a false associativity claim makes
  reassociation/parallel lowering wrong, and a false identity makes
  empty collects wrong — the same trust class as a JS boundary
  assertion, shown with the same "asserted, not verified" grading.
  (What the language consumes is the *offer*, which is types-design
  machinery; the facet is the authoring surface that mints the
  catalog row.)

Now, you might wonder why the checker doesn't verify the claim —
prove your operator associative before trusting it, or infer
associativity from its diagram. It turns out this is ruled out: no
search; associativity is a theorem about the operator, not a
propagatable property. The claim is authored (via the facet) and
trusted, with the direction of doubt stated as above. (This is a
settled dead end — please don't re-propose it without new
evidence.)

Nothing in a *program* changes: the program wires an operator into a
reduce-close; the checker demands `associative` (and `has-identity`
if the output is consumed as total); propagation is the existing
property machinery. **A catalog row is an offer with a witness; user
monoids mint rows via the algebra facet; nothing is annotated in
programs.**

## Named collects are catalog rows, not node species

`collect set`, `collect any`, `collect last` looked like they might
each be a small construct of its own. They are not. Each is the one
reduce-close node with a specific catalog operator:

| strawman spelling | operator | tier | empty flow yields |
|---|---|---|---|
| `-~> collect any` | `or` | monoid (false) | `false` |
| `-~> collect all` | `and` | monoid (true) | `true` |
| `-~> collect sum` / `by add` | `+` | monoid (0) | `0` |
| `-~> collect set` | ordered set-union | monoid (∅) | empty set |
| `-~> collect first` | keep-left | semigroup | None (option) |
| `-~> collect last` | keep-right | semigroup | None (option) |
| `-~> collect min` / `max` | min/max | semigroup | None (option) |
| `-~> collect by <op>` | any catalog/facet operator | per its row | per its tier |

Notes earned by specific sightings:

- **`collect set` is the dedup** (Flix's `deduplicate`; the
  seen-sets of the surveys). The leaning is the *ordered* set —
  first-appearance order, the subject flow's own order surviving —
  because keep-first union is still associative and the record
  favors provenance-respecting order (see Part II). A
  mathematical-set reading is the same row with order quotiented
  away; a presentation question until something demands it. And you
  might wonder whether deduplication deserves a node of its own. It
  turns out it must not get one: `collect set` is a catalog row on
  the existing reduce-close; a distinct node species would be a
  second reading of the same program. (Settled dead end — please
  don't re-propose it without new evidence.)
- **`collect last` is the register's readout costume.** "Last value
  a walk produced" is also a register whose step is the element,
  final value read at discharge. The reduce-close spelling is the
  one to bless — no state variable is meant, and the option shape on
  empty is exactly right — but the equivalence is worth a line so
  nobody proposes both as separate constructs. (`keep-right` is
  associative: `(a·b)·c = c = a·(b·c)`.)
- **`collect any` under multi-close** is the survey's any-changed
  flag: one walk, one output the changed entries, one output the
  flag — now with the flag's collect one word.
- The **count** is `collect sum` over `1` per firing (or a blessed
  `collect count`). Its identity story is why COUNT is SQL's one
  non-NULL aggregate: 0 is a genuine identity.

The general form `collect by <op>` covers user monoids without new
syntax; the named forms are sugar over well-known rows. How many
names get blessed is the naming round's question.

---

# Part II: the keyed collect

## A first grouped program

Suppose each firing of a walk carries a key `k` (say, a department)
and a value `v` (say, a revenue figure), and you want totals per
department. One line:

```
k, v -~> collect keyed by add => totals
```

`totals` is a map-shaped value: one entry per distinct key, each
entry the sum of that key's values. In conventional code this is a
group-by with aggregation — dplyr's `group_by` + `summarise`, SQL's
`GROUP BY ... SUM(...)`, a hand-rolled `map[k] += v` loop. The rest
of Part II unpacks what that one line is made of, because the
everyday spelling is the fused form of something more primitive.

## The construct is a partition; the "collect" is one of its readouts

The primary construct is not "a collect that builds a map." It is
the **keyed partition**: a barrier on a flow that groups its firings
into **lanes** by a per-firing key.

- **In**: a subject flow; a key value, computed per firing by
  ordinary drawn code (no extractor functions, no magic names).
- **Out**: the subject's firings, re-contexted into a two-level
  nesting — an outer **lanes flow** (one firing per distinct key,
  the key riding as a per-lane value wire) and an inner
  **within-lane flow** (that lane's firings, in subject order).
  Every non-key wire crosses the barrier as itself and is present
  per within-lane firing — the no-bottlenecks principle, and
  precisely XQuery's "non-grouping variables become sequences" minus
  the rebinding bug.

This is **group-as-flows adopted as the primary form**, because it
*builds* (principle 7). Aggregation, HAVING-style filtering, nested
reports, per-group anything — all ordinary downstream consumption of
the lanes, +1 step each, no rewrite. The operator-merge form is
derived (below).

A keyed partition is bundle-*like* — a partition of the parent's
firings, exactly one lane per firing — but its cells are
**data-determined**: they exist at runtime, per key seen. The
record's static bundles are wired per-alt (each alt name a distinct
drawn lane with its own wiring). Now, you might wonder why you can't
draw a lane for a particular key — wire up "the lane whose key is
`"foo"`" the way you wire up the `Even` alt of a split. It turns out
this must be impossible: cells are data; drawn structure cannot
depend on runtime keys. A keyed partition **cannot be wired
per-cell** — there is no drawn place for "the lane whose key is
`"foo"`" — and this restriction is what keeps the runtime cell set
checkable: *one* sub-diagram is drawn against the within-lane flow,
instantiated per lane, with the key available as an ordinary value
wire inside. Uniform wiring over dynamic cells; distinct wiring over
static alts. A program that genuinely wants distinct handling for a
known key writes a case split on the key — static alts — before or
inside the partition. The constructs compose instead of blurring.
(Per-cell wiring of a keyed partition is a settled dead end — please
don't re-propose it without new evidence.)

## The readout family: one barrier, four consumptions

Given a keyed partition, the existing close vocabulary already names
every readout:

1. **Collapse** — collect the within-lane flow (any collect: list,
   reduce-close, another keyed partition), then collect the lanes
   flow. One output per lane; the result is keys ⊕ per-lane results:
   **the keyed collect proper**, a map-shaped value. This is dplyr's
   `summarise`, XQuery's post-group aggregation, jq's
   `group_by`+apply.
2. **Pass-through** — the exhaustive per-firing readout: a value
   computed per within-lane firing rides back to the parent walk,
   original order by provenance. This is the case bundle's
   exhaustive collect generalized to data-determined cells (grouped
   `mutate`; grouped `filter` is the same readout feeding a
   keep/drop join). Structurally sound because the partition *is* a
   partition: every parent firing landed in exactly one lane, so
   per-lane values are per-parent-firing values, and the collect at
   the barrier reassembles subject order. No new close species — the
   case collect's law, with the alt set data-determined.
3. **FlatMap** — a per-lane output that is itself a flow, joined
   upward (`reframe`; per-group top-3 reports). Ordinary join, no
   new construct.
4. **Whole-lane engagement** — fold a lane to a verdict and keep or
   drop the *lane* (`filter_out(n() == 1)`). Partial engagement of a
   data-determined bundle: partial-collect vocabulary, applied at
   the lanes flow.

Plus the corollary broadcast-back forces: **the lane as a value.**
Each lane is collectable to a sub-list and re-openable (`nest_by`).
The grouped z-score is then two walks of the lane — collect the
mean, re-walk the sub-list with the mean as ancestor value — the
same two-walk program the flat broadcast-back uses, one nesting
level down. This must appear in the worked examples so nobody
re-invents a within-walk broadcast that violates no-time-travel.

## Operator-merge is the fused special case — and lanes dissolve the identity question

Flix's `Map.insertWith(⊕)`, `pivot_wider`'s `values_fn`, and the
saturation row's keyed-min-collect are all one shape: a keyed
partition whose per-lane collect is a **reduce-close by ⊕**, fused
into one gesture — the `collect keyed by add` of the first grouped
program. In this round's vocabulary it is readout 1 with a specific
inner collect — derived vocabulary, not a sibling construct.

Two structural facts fall out, and they are the payoff for having
done Part I first:

- **A lane is never empty.** A lane exists iff a firing landed in
  it. So the per-lane reduce-close never sees an empty flow, and
  **tier-2 (semigroup) operators are total in keyed position**:
  `collect keyed by last` needs no identity and never yields an
  option — which is why the wild forms (`insertWith`, last-wins
  maps, `values_fn = max`) never ask for one. The identity question
  is the empty-collect question, and keying structurally removes the
  empty case.
- **The keyed collect as a whole is its own monoid fold.** Merging
  two keyed results (union of maps, colliding keys merged by ⊕) is
  associative with identity ∅ whenever ⊕ is associative. Empty
  subject → empty map, always, demanding nothing of ⊕. This is the
  algebraic footing the saturation row's keyed-merge variant wants
  (shortest-distance = keyed-min-collect plus feedback), and what a
  parallel/reassociated lowering would lean on.

## Collisions dissolve

What happens when two firings carry the same key? `pivot_wider`
treats duplicate keys as a problem (`values_fn` demanded, warnings
otherwise); hand-rolled maps silently last-win. Here, **collision is
not a failure mode — it is the ordinary case of a lane with several
firings**, and "what to do about it" is exactly the per-lane collect
choice the construct already requires:

- the bare partition keeps the lane whole (group form — nothing to
  decide);
- the fused form says its operator: `collect keyed by add`, `collect
  keyed by last`.

Now, you might wonder why the language doesn't take one of the two
shipped answers. Make collisions an error, as `pivot_wider` does? It
turns out that making it an error forces the group form to be an
escape hatch instead of the primary construct — collision is a lane
with several firings, the ordinary case. (Settled dead end.) Or
silently keep the last value, as a JS object assignment does? It
turns out that is the ambient-default clash — a meaning chosen by
omission. The one honest spelling costs two words (`by last`).
(Also a settled dead end — please don't re-propose either without
new evidence.)

## Order: first-appearance

In what order do the lanes come out? Three shipped answers exist
(Dyalog first-appearance, jq sorted-by-key, XQuery
implementation-dependent). The leaning is **first-appearance**,
because it is the only candidate that *is* the subject flow's own
order — the lanes flow fires in the order keys first appear, which
is provenance-respecting and deterministic. Sorted output is
ordinary downstream consumption (ordering is data — sort the
collapsed result by key), and implementation-dependent order is
hostile to a record built on drawn structure being trustworthy. This
also makes the ordered `collect set` of Part I the degenerate keyed
partition (key = the element, collapse = `first`) — a pleasing
coincidence, not a design input.

## Initial contents

Some walks seed a table before the walk and amend entries during it
(C3's DP fill). The general form: a keyed collect **with initial
contents** — an initial map whose entries behave as if a firing had
already landed in each seeded lane. In the derived lowering this is
nothing new: the per-lane register (the keyed running view's
substrate) initializes from the seed map's entry instead of from the
lane's first firing. The running-view read-by-key then sees seeded
entries before any firing lands — exactly what the DP fill needs
(values pre-populated for small indices, read back mid-walk).

The initial map is an ordinary value input to the collect (`collect
keyed from seedMap by add`), outside the flow — the same "the
initial value belongs outside the flow" position the register design
established. Note the effect on emptiness: a seeded keyed collect of
an empty subject yields the seed map, consistent with augment's
seed-passes-through, because seeding *is* the augment move made
per-lane.

## The keyed index consumption pattern

Recorded as consumption, not construct (jq's `INDEX`): build the
keyed collect once, read it per-firing of *another* flow. The
get-by-key miss is option-shaped (fires-or-not), the left-join is
the fired-empty completion, and semi/anti joins are a membership
case split against the key set. Nothing new to design; the worked
examples should include one join for a canonical drawing. The only
design content is already stated elsewhere: reads of a *running*
keyed view are prefix-causal
(`variable-rate-consumption-design.md`), while reads of the
*finished* map are ordinary value consumption — two different times,
and the drawn structure (running-view port vs output port) keeps
them visibly distinct.

## The keyed uncollect

`pivot_longer` over a data-keyed table is the inverse end of the
same barrier — a map-shaped value opens into the lanes flow (key as
per-lane value, entries as within-lane firings). Just the uncollect
of the keyed collect's output shape, listed for completeness.

---

## Spelling strawmen, consolidated

Provisional raw material for the textual round.

```
-- named reduce-closes (catalog rows)
flags -~> collect any => anyChanged
xs    -~> collect set => distinct          -- first-appearance order
xs    -~> collect last => finalX           -- option-shaped output

-- general reduce-close by catalog / facet operator
masks -~> collect by and => combined

-- keyed: bare = group form (lanes)
k, v -~> collect keyed => groups           -- map of lane-lists

-- keyed: fused scalar form (collision operator explicit)
k, v -~> collect keyed by add => totals
k, v -~> collect keyed by last => latest

-- keyed with initial contents
k, v -~> collect keyed from seedMap by add => table

-- the partition, unfused (group-as-flows; strawman)
xs -> open list => x, ~L
x -> keyOf => k
k -~> partition => key, ~lanes, ~inLane    -- key rides per lane
x -> len -~> collect ~inLane -~> collect sum => perLaneTotal
key, perLaneTotal -~> collect keyed => totals
```

The last block is the least settled (open question 1): whether
`partition` mints a genuinely nested pair of flows with ordinary
collects doing the rest, or stays fused into `collect keyed`
variants with the partition as its derived view. The leaning is
both — fused as the everyday spelling, the partition as the derived
form it lowers to — the same surface/derived relationship
reduce-close already has to the augment loop.

## Worked examples

**A merge fold** (Flix's `Map.insertWith(pairAdd)`, three times in
one module). Drawn: `k, v -~> collect keyed by pairAdd => counts` —
one line per instance, the operator's associativity claimed by its
facet, no identity needed (lanes are non-empty).

**The DP fill**, with the settled spelling:

```
range5N4 -> open list => n, ~L
~L ~> collect keyed from seed by add => zv   -- minted early (two-phase)
zv!sofar, ... -> termArithmetic => entry     -- running view, read-by-key
n, entry -> value of zv                      -- late-wired contribution
```

Seeding is per-lane augment; `add`'s row makes the amend
associative.

**Any-changed sync**: one walk, multi-close — `changedEntries` a
filtered list collect, `-~> collect any` the flag. The flag's
collect is total (identity false) so the empty-input case needs no
special handling.

**Grouped report with HAVING**: partition by department; per lane
`collect sum` of revenue; whole-lane engagement keeps lanes where
the sum exceeds threshold (readout 4); collapse survivors into the
report map. Each step is +1 on the previous drawing.

**Grouped z-score** (broadcast-back): partition by player; lane as
value (`nest_by`'s move) → collect mean of the sub-list; re-open the
sub-list with the mean as ancestor value; pass-through readout rides
the z back to subject order (readout 2). In the strawman spelling,
mean-centering (the z's core move — two walks of the lane, never a
within-walk broadcast):

```
-- spelling provisional, composed from the strawman table above
scores -> open list => row, ~L
row -> .player => k
k, row -~> collect keyed => byPlayer          -- partition: one lane per player
byPlayer -> open keyed => lane, ~P            -- per player: the lane as a value
lane -> open list -> .score -~> collect by mean => mu   -- walk 1: the lane's mean
lane -> open list => r, ~W                    -- walk 2: mu in scope as an ancestor value
r -> .score -> sub(mu) -~> collect => centered -- per-player centered scores
```

The mean is *finished* before walk 2 opens — the two-walk shape is
what keeps the broadcast-back inside no-time-travel.

## Where this shows up in real code

The evidence, gathered per the sample-reality method. The keyed
collect and the identity question have collected sightings faster
than any other single construct without a design:

| Witness | What it showed |
|---|---|
| Survey 2 (`real-loop-survey.md`) | Three independent hand-rolled monoid folds in thirty draws (logical-and over masks, bitwise-and into self, the OR-fold any-changed flag), each with its identity visible in the seed (`and`→true, `&`→full-mask). |
| `translation-exercise.md`, A4/B5/B6/C3 | `collect last`, `collect any`, `collect set`, `collect keyed` invented on the spot; C3's DP fill added **initial contents** and **collision combine** to the keyed obligations. |
| Flix comparison | Three hand-rolled `Map.insertWith(⊕)` merge folds in one module's *incidental* code; `deduplicate` as the set collect; lattice aggregation (keyed-min-collect plus feedback) at the center of the saturation paradigm. |
| XQuery/jq comparison | The keyed collect's structural fork decided by shipped evidence: **group-as-flows** (groups stay whole, aggregation is downstream) vs **operator-merge** (Flix's `insertWith`), with group-as-flows the form that builds. |
| APL comparison | The first shipped identity **catalog** (Dyalog's 23-row table; DOMAIN ERROR where none exists); BQN's three-way split — derive the identity, take a seed, or never ask — handing the sharpest framing: **the identity question is exactly the empty-collect question**. |
| tidyverse comparison | The keyed partition's **readout family** (collapse / pass-through / flatMap / whole-lane); the group stack as drawn nesting; broadcast-back demanding the group-as-*value*; `pivot_wider` located as the keyed collect (`values_fn` = the operator-merge variant). |

## How this squares with the design principles

- **Example first, then generalise.** Every form is an interposition
  on an existing walk: add a key wire and a barrier to get a
  partition; change a collect's operator word to get a reduce-close;
  add `from seed` to seed it. Nothing declares structure before the
  concrete case exists.
- **Inside-out / cases as values.** Keys are computed by ordinary
  nodes on the element; the key rides into the lane as a value wire
  (the legitimate content of `cur_column()`); no comparator or merge
  *functions* are passed — operators are nodes with catalog rows.
- **No bottlenecks.** Non-key wires cross the partition as
  themselves, per lane; the collapse readout's map packs only at the
  collect, where packing is the point.
- **Building blocks must build.** The +1 ladder is explicit: sum →
  keyed sum (add a key); keyed sum → keyed mean (change the inner
  collect); collapse → pass-through (change the readout, not the
  program); group → HAVING (add a whole-lane filter); scalar map →
  grouped report (unfuse to the partition). No step rewrites into a
  different construct.
- **Abstraction is the source of truth.** Reduce-close stays its own
  node lowered in compile; the fused keyed collect lowers to the
  partition + per-lane registers, and the running view is defined
  through that derived form — derivation downward, reference-only.
- **Frequency is not importance.** The named collects are
  high-frequency conveniences (rank: effortless — one word); the
  keyed partition is both frequent (four ecosystems) and a breadth
  obligation (saturation's keyed-merge; the DP fill). The
  option-shaped tier serves the rare-but-breaking empty case without
  taxing the common one.

## Dead ends, gathered

Eight ideas were considered and settled against in this chapter.
Each appears above in a "now, you might wonder" passage with its
full reason; this list exists so none is re-proposed without new
evidence. The pointers:

1. **Per-use empty values on the collect** — see "The identity is
   the value of the empty collect" (the value is a seed; the augment
   in disguise).
2. **DOMAIN ERROR on empty for identity-less operators** — see "The
   availability ladder" (structure carries the absence; the
   option-shaped tier).
3. **Inferring or verifying associativity** — see "How identities
   attach" (no search; authored claim, trusted, direction of doubt
   stated).
4. **Numeric identities for min/max in the catalog** (−∞/+∞) — see
   the min/max paragraph of the ladder (representation-dependent
   totality flicker; explicit seeded augment instead).
5. **Collision-as-error for the keyed collect** — see "Collisions
   dissolve" (collision is the ordinary case of a multi-firing
   lane).
6. **Silent last-wins for the fused keyed collect** — see
   "Collisions dissolve" (ambient default; `by last` is two words).
7. **A separate dedup node** — see the `collect set` note under
   "Named collects are catalog rows" (a catalog row, not a node
   species).
8. **Per-cell wiring of a keyed partition** — see "The construct is
   a partition" (cells are data; compose a case split on the key
   instead).

## Open questions

None of these is decided; each states its lean where one exists.

1. **The partition's surface vs the fused spellings.** The leaning
   (fused `collect keyed …` everyday; the partition as its derived
   view) mirrors reduce-close/augment — but the readout family
   consumes the partition directly (pass-through, whole-lane,
   flatMap), so either the fused surface needs readout variants or
   the partition needs a first-class drawing. Which readouts get
   fused spellings is open; the construct set is not.
2. **The pass-through readout's port story.** "Collect in subject
   order at the barrier" is stated as the case collect's law
   generalized; the exact ports (a collect on the partition node, or
   does the partition retain the subject flow as an output for
   ordinary multi-close?) need the representation round.
3. **The checking story for data-determined cells.** Bundle
   provenance's checks are stated over static alt sets. The
   uniform-wiring restriction should make the keyed case *easier*
   (one lane sub-diagram, no per-alt coverage question), but the
   provenance path for "which partition a lane came from" needs its
   entry in `bundle-provenance-design.md`'s path grammar.
4. **Key equality.** Structural equality? A user-supplied
   equivalence? Same question the tough doc filed for concurrency's
   keyed lanes; decide once for both.
5. **Unification with concurrency's keyed lanes.** Same word, same
   key vocabulary, different law (longitudinal serialization vs
   partition-and-collect). Whether the data-side partition and the
   sync-side lane are one barrier with two laws or two constructs
   sharing key vocabulary is left to the concurrent collect's round,
   which should read this round first.
6. **The algebra facet's authoring surface.** This round consumes it
   (user monoids mint catalog rows); the facets row owns designing
   it. Joint constraint: the facet must carry a *value* witness (the
   identity), not just a named law.
7. **Which names are blessed** (`sum`, `count`, `mean`?) — the
   naming round's. `mean` specifically is *not* a reduce-close (not
   associative; it is sum⊕count collapsed downstream) and makes a
   good worked example of the boundary.
8. **Segmentation × keying.** The keyed partition must compose with
   split-when (per-key segmentation: sessionisation). Nothing here
   forbids it — the within-lane flow should accept split-when like
   any flow — but no example is worked; owed to whichever round hits
   it first.

## What this changes in `open-problems.md`

- **Loop-carried state row**: the operator-identities item and the
  keyed-collect item — the row's two non-center remnants — now have
  their joint round with leanings. The row's center (the surface
  decision) is untouched.
- **Textual catch-up row**: the collect family's owed spellings move
  from "flagged" to strawmen-with-a-design-behind-them; the
  late-wired `value of` collect appears in a second worked program.
- **Saturation row**: the keyed-merge scope item gains its algebraic
  footing (the keyed collect is itself a monoid fold with identity
  ∅; semigroup operators total per-lane).
- **Checking row**: the catalog question gains its first concrete
  content demand — rows are properties-with-witnesses; the algebra
  facet mints them.
- **Facets row**: the algebra facet gains its first in-record client
  with a stated joint constraint (value witnesses).
