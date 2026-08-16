# What a Delay is, and which flow binds it

Status: mixed. The **per-kind half is adopted** (2026-07-23): the
owned-order criterion, the order-demand check, and the `hold`
identification — see §"Per-kind \"next iteration\"" for the
adoption's scope. The rest is an open problem, genuinely
unsettled. Update (2026-08-04): the thread ergonomics round
(`iteration-with-state-design.md`) removed the register's flow
operand — frames are derived from the thread's anchors, with an
`in ~flow` annotation for the residue — so this chapter's binding
question is now *localized*: "which flow binds the Delay" becomes
"what the `in` annotation means under a commute or a product," an
annotation question rather than a structural-input one. The open
problem itself is unchanged in substance. This chapter teaches a
construct the design does have — the register, whose carrying half is
called a Delay — and then a question about it the language has *not*
answered: what a Delay actually is, and which flow supplies its "next
iteration" when more than one is in reach. A first pass leaned toward
one answer (collect-binding, below); on reflection three arguments
cut the other way, so the question is recorded here as a live one,
not a resolved one. Read every leaning in this chapter as a leaning.
The question was prompted by the registers-over-products round
(`product-flows-design.md`), which turned out to probe Delay more
than the product. This document grew inside
`iteration-with-state-design.md` until it was a design area of its
own; it is split out here so the register-pair story and this
question can each be read whole.

Before reading this, you will want: the register pair and the
equivalence result (`iteration-with-state-design.md`, "The
equivalence, worked"), the rejected shapes recorded there
(`stateful`, `prev(x)`, the Delay lambda), and Cross /
registers-over-products (`product-flows-design.md`). Code samples
use the textual syntax from `textual-representation-design.md`.

## The construct, in its simplest home

Start with a running sum — the plainest program that carries a value
from one iteration to the next:

```
xs -> open list => x, ~L         -- x: each element; ~L: the list flow
~L ~> delay init 0 => run        -- run: the sum carried from last time
run, x -> add -> step of run => total
```

Read it line by line. Opening the list gives you each element `x`
and the list's flow `~L`. The `delay init 0` line creates the
carrying construct: `run` is the value it carried over from the
previous iteration (`0` on the very first, from the seed `init 0`).
The last line computes this iteration's sum and feeds it back —
`step of run` says "this is the value `run` will carry next time."

That carrying construct is a **Delay**, and the whole loop-carried
arrangement — a read half (`run`) plus a write half (`step`) — is
the **register pair** of `iteration-with-state-design.md`. In
conventional code this program is a fold or a running accumulator.

## What is a Delay, exactly?

Now the question this chapter is about, in plain words. "Carry this
value to the next iteration" presupposes that there *is* a next
iteration — some flow has to supply it. In the running sum above,
which flow that is stays invisible, because only one flow (`~L`) is
in reach. But the moment more than one flow is in reach — a commute
sitting between where a carried value originates and where the
register is collected, or a product's several axes — the answer
*selects the behaviour* of the program. So this is a question about
**meaning**, not wiring, and — the point of recording it — the
meaning selects the behaviour, so it cannot be deferred as mere
naming. (The design record calls this the Delay *ontology*
question; "ontology" is just the philosopher's word for "what the
thing *is*.")

The equivalence result (`iteration-with-state-design.md`, "The
equivalence, worked") pinned the register's *structure* — one
register pair, two drawings — but left this prior question
implicit. It is the worked instance of the "what does it mean?"
lens (`language-design-philosophy.md`): a construct fully pinned at
the level of results whose meaning still decides real behaviour.

Some ground is firm across every candidate answer; some is the open
fork. Firm: a Delay is a feature of the flow, and it does not
thread the flow wire (both taught below). Open: *which* flow
supplies its "next iteration" — the collect that binds it, the
uncollect its value descends from, or something else — and, under
the third argument below, whether Delay is even the right
abstraction.

## A map of this chapter

The question looks small and is not. Here is the through-line,
section by section:

- **Firm ground** (next): a Delay is a feature of the flow, and it
  does not thread the flow wire the way IO does.
- **The fork**: candidate 1 (a delayed computation, bound at the
  collect) versus candidate 2 (a reference to the ancestor
  uncollect), the discriminating commute case, and the three
  considerations that reopened a first-pass leaning.
- **Worked examples**: successive differences over optional
  readings (a nesting — votes for the collect), and the running sum
  over a cross (a product — forces an explicit reference), meeting
  in the disambiguation-vs-wire-mess tension.
- **Two reframings** that between them dissolve most of the fork:
  the **value-in-context model** (an uncollected value is a cursor
  into its wire's firing-indexed sequence — the flow is fixed by
  where the wire came from, not chosen, so the candidates coincide
  on sequences and are silent on grids), and the **update-cadence /
  read-range split** (a register straddling a nest answers the two
  candidates with two different halves of itself — and yields
  `hold`).
- **The product, re-read**: the surviving residue localized — a
  missing *order* in the update half, with the pure-`final` corner
  closed.
- **Per-kind "next iteration"**: the owned-order criterion — a flow
  supplies a "next iteration" exactly when its firings carry a total
  order *owned by the flow's meaning*; the kinds table cashed, the
  clients' register checks unified into one order-demand check, and
  `hold` identified as the register whose step ignores `prev`.
- **Open**: the current state of every strand.

Where it stands after all of that: the collect-vs-ancestor label is
**not the real axis**. The one hard residue is the **product's
linearization** — that is, which reading order several consumers of
one order-sensitive register each walk a multi-axis grid in —
several running-view consumers of one non-commutative register
reading in different orders — the recompute-vs-explicit-
axis-reference trade. Everything else has either coincided, been
answered by provenance (update) and the consumer (read), or been
closed. The per-kind question — which kinds supply a "next
iteration" at all — is since worked below (the owned-order
criterion) and **adopted** (2026-07-23), together with the
order-demand check and the `hold` identification. And the linearization residue
itself has since been worked in its own round
(`product-linearization-design.md`, exploration, unadopted): the
axis is the *drawn orientation* of the flow the register rides —
neither candidate — and the trade reduces to an orientation-pinning
demand; see the Open list's endnotes. The frequency check that round
owed is since **run** (`real-loop-survey.md`, survey 4): the demand
would fire on ~10–13% of nested-loop sites in the domains that
stress it, its everyday client is the spanning ordered emission (the
report-writer) rather than the numeric scan, and in every firing
draw the orientation was already authored in the source — evidence
for the residue's conversation, which remains unheld.

## Firm ground: a Delay is a feature of the flow

"Carry this value to the next iteration" presupposes that there
*is* a next iteration, so a Delay is only meaningful where a flow
supplies one:

- over a list iteration or a self-driven / stream flow — a "next"
  exists;
- **not** over an async or IO flow (a value that arrives later, an
  effect sequenced in time) — there is no within-collection "next
  iteration" to carry to;
- **not** outside any flow — nothing to be "next" of.

(Which kinds actually supply a "next iteration" is worked below, in
§"Per-kind \"next iteration\": the owned-order criterion" — where
"async/IO apparently not" gets its honest refinement: the async
*value*'s no-next is cardinality, not async-ness — an async *stream*
supplies one — and IO's is that the handle is a wire, not a flow.)

One more firm point, visible in the running-sum program: though a
Delay is *drawn* as a computation step (`prev + element`), it is
not one. `prev` is not computed, it is *accessed from the flow*,
the way a list-open's element is. This is why the read is a port,
not an expression (Candidate A of
`iteration-with-state-design.md`): the carried value is provided by
the flow, not conjured.

## Now, you might wonder: why not thread the flow wire, like IO?

If a Delay is a feature of the flow, the tempting move is to make
it *interact with the flow wire* — take the flow wire in and out,
and say "this Delay uses the next-iteration of *that* flow" by
tapping the wire. That is exactly how IO works: its operations
(open a file, …) take the flow wire as input and output, threaded
along it. So you might wonder why the language doesn't just do the
same for Delay.

It turns out this would cause problems. The reason IO threads the
flow wire is specific: **IO operations must be sequenced in time,
and their order along the wire is that sequence.** The
wire-threading exists to *encode a sequence*. Delay has none to
encode — **Delays have no order with respect to each other** (the
inert stack order the equivalence already established as
meaningless). Forcing them onto a shared flow wire would make you,
the author, choose that meaningless order — which Delay is "first"
on the wire — and clutter the diagram with wires that say nothing.
So the very property that *justifies* wire-threading for IO (a real
inter-operation sequence) is precisely what Delay lacks, and its
absence is the argument against wire-threading Delay.

This sharpens the "stack order is inert" finding into a reusable
distinction: **flow-wire-threading is for constructs with a mutual
temporal sequence; a construct with no mutual sequence must not
thread the wire.** IO threads; Delay does not. (This is a settled
rejection — please don't re-propose wire-threading for Delay
without new evidence.)

**Reconciliation with the effects round.** An earlier working of
`effects-design.md` identified the threaded IO handle *with* a
register — "a per-firing effect is a register whose threaded wire
is the IO handle," a Delay carrying a **marker** wire — and this
paragraph used to reconcile that with the rule above (the register
rides the loop's flow; the handle is its payload, not how it finds
its flow). That reading is since dissolved: the effects round now
answers with the **sequencing commute** — commuting an IO flow out
of a list flow concatenates the per-firing segments in firing
order — and no Delay appears in the effects story at all
(`effects-design.md`, "No register appears"). The reconciliation
dissolves with it, and this section's distinction stands cleaner
than before: IO threads its wire because it has a real
inter-operation sequence to encode; Delay has none and must not
thread; the two never share a node. The broadening the register
story was once asked to absorb (a carried wire with no readable
payload) is withdrawn, and `saturation-design.md`'s two-point
duality (value back-edge / flow back-edge) stays two-point.

## Candidate 1: a delayed computation, bound at the collect

If a Delay does not get its flow by tapping a wire, where does its
"next iteration" come from? One answer: **a Delay builds a *delayed
computation* — a value paired with its own one-step-delayed self —
not yet bound to any concrete flow. Collecting the flow collects
that delayed computation and binds it: the collect is what supplies
the "next iteration" the delayed computation was waiting for.** On
its own a Delay is a sequential computation in the abstract; the
collect grounds it in a specific iteration, and the register's
meaning completes there — at its collect, not at the Delay glyph.
This reframes the write half (`iteration-with-state-design.md`,
"The Delay back-edge: the write half is a node"): the feedback
collect is not merely where the step is deposited, it is the *act
of binding* the delayed computation to a flow. Its appeal: it keeps
"orders live at terminations" true for the register too, and it
treats the value wire an uncollect produces as strictly ordinary —
the flow enters only at the collect, visibly, with nothing smuggled
inside the wire (the inside-out instinct, dressed as an answer to
"what is it").

## Candidate 2: reference to the ancestor uncollect

The other answer — which the first pass recorded as *rejected* and
which is now **restored as live** — is that a Delay gets its flow
by *implicitly referencing the uncollect its value wire descends
from*: walk back from `prev + element` to the list-open `element`
came from, and take *that* flow's next iteration.

Why was it first rejected? For treating the value wire as if it
"secretly remembered its flow," clashing with the fiction that an
uncollect hands you an ordinary value wire. But argument 2 below
dissolves that objection — perhaps the fiction is simply wrong, and
a per-iteration value is honestly a *value wire in context*, one
that has a previous and a next the way it has, well, a value. On
that reading the ancestor reference smuggles nothing; it reads
context the wire genuinely carries. So the rejection did not stick,
and the candidate is live again.

It has its own residue, though: **which** ancestor. The worked
example below shows a value whose *innermost* ancestor uncollect
(an option) is the wrong flow to thread — you mean an outer one —
so this candidate owes a rule for picking among the uncollects a
value descends from, and "the nearest" is demonstrably not it.

## When the candidates disagree: a commute in between

The two candidates are not always distinguishable — they diverge
exactly when the **uncollect flow differs from the collect flow**,
that is, when a commute sits between where the carried value
originates and where the register is collected. Then:

- *ancestor-reference:* the Delay threads along the origin
  uncollect's iteration;
- *collect-binding:* the Delay threads along the collect's
  iteration.

Different programs — so this case *forces* the choice of meaning
rather than merely illustrating it. The registers-over-products
round is where the choice bites hardest: under collect-binding a
register over an order-free product folds along the axis its
binding collect gathers; under ancestor-reference it folds along a
fixed axis its value descends from, regardless of consumer.
Argument 1 below is why that difference is not cosmetic.

**"Commute" here is two operations, and the distinction matters.**
The word covers two genuinely different flow-order swaps
(`lazy-stream-commute-design.md`, "The commute-variant taxonomy";
the naming is flagged open there), and the discriminating case
wears a different face under each:

- **Grid transpose** — reversible, value-preserving, defined only
  over a *product* (independent flows), the two orientations
  confluent. A Delay across a transpose is exactly the
  registers-over-products case: both orientations coexist, and the
  question is which axis.
- **Monadic sequence** (what functional programmers call
  *traverse*) — directed, *not* reversible, defined over a
  *dependent* nesting, with real semantic content (short-circuit).
  This is the one the option example uses, and it is why "a
  per-element option can't be commuted out" is wrong: it cannot be
  *transposed* out (no product), but it can be *sequenced* out
  (`List<Option> → Option<List>`,
  `lazy-stream-commute-design.md`). Across a sequence the flow is
  genuinely *restructured*, not re-read, so "origin flow vs collect
  flow" is a sharper divergence than under a transpose.

Both swap flow order, so both were loosely called "commute" — but a
Delay's "next iteration" relates to a *reversible re-reading* and
to a *directed restructuring* differently, so the what-is-it
question has to be asked against each. Below, the optional-readings
example is the sequence face; the registers-over-products round is
the transpose face.

## Why the question reopened: three considerations

The first pass leaned collect-binding. Three considerations
complicate it — the first a cost that turns out to be survivable
(and even sometimes wanted), the second and third pulling toward
the ancestor uncollect or past both:

1. **The multiple-collect / shared-grid problem (the concrete
   one).** Two independent uncollects (x, y) crossed into a
   product, then collected *twice in opposite orders*, are
   implemented by iterating once, storing the n×m grid, and
   transposing for the second consumer — one computation, two
   readings (`product-flows-design.md`;
   `compile-strategy-design.md`). Put a register in the middle.
   Under collect-binding its axis depends on *which* consuming
   collect reads it, so the two consumers want two *different*
   grids (running-sum-down-X vs running-sum-along-Y) — a single
   shared Delay cannot be both, and the compute-once-transpose
   implementation that makes Cross cheap breaks. Under
   ancestor-reference the register's axis is fixed at the Delay,
   "running sum along X" is one point-indexed grid, and it
   transposes like any other product value — the shared-grid
   implementation is preserved.

   **But the rebuttal cuts back toward candidate 1.** This treats
   compute-once-transpose as a property a register must *not*
   break — and that premise is contestable. A delayed computation
   collected two ways is, arguably, honestly *two different
   computations*, and **re-running it once per collect is a
   legitimate implementation, not a defect** — sometimes exactly
   what you want. The cost is not even hidden: a register along any
   axis *other than the innermost* already cannot stream — it must
   store a whole previous fiber and zip it against the current one
   (`product-flows-design.md`, "The inner-axis vs outer-axis
   cost"), and an accumulator over an *outer* loop, which wants
   precisely that, is not infrequent. So argument 1 lands as a real
   **cost** on candidate 1 (products stop being free to transpose
   across a register, and some registers recompute per consumer),
   not as a knockout. Whether that cost is acceptable — versus
   fixing the axis at the Delay and paying candidate 2's price
   instead — is the open weighing, and it is genuinely balanced.

2. **"Previous element" is honest context, not smuggled state.** It
   is not linguistically strange to say: if I have the current
   element of a list, I can have the previous one. That suggests
   the uncollect fiction ("ordinary value wire") is too strong — a
   per-iteration value may be better modelled as a **value wire in
   context**, where the context is precisely that it has a previous
   and a next. If that is what an uncollected value *is*, then the
   ancestor reference is not a clash with anything; it reads
   context the wire carries by its nature. This needs more thinking
   out — it would reshape what an uncollect produces everywhere,
   not only under Delay — but it removes the sole ground on which
   candidate 2 was rejected.

3. **Delay may be the wrong abstraction.** Both candidates assume
   the register/Delay framing is right and only its flow-binding is
   in question. The third possibility is that the framing itself is
   off, and the right construct for loop-carried state binds "next
   iteration" in some way neither candidate captures. Held open,
   not developed.

## Working an example: successive differences over optional readings

The vote and its complication both fit in one small program — a
list of readings, each possibly an error:

```
readings -> open list => r, ~L      -- r : option<number>
r -> open option => v, ~O           -- v : the reading, present iff Some
```

Goal: successive differences of the readings, a Delay holding the
previous one. Which flow does it thread?

**The vote (for the collect, against the *innermost* ancestor).**
The value `v`'s innermost ancestor uncollect is the **option**
(`open option`), and threading the option is meaningless — an
option flow fires at most once, so it has no "previous." The
difference is plainly meant along the **list**, an *outer* flow. So
the innermost-ancestor reading is simply wrong here, which is a
real strike against candidate 2 *if* "ancestor" is read as the
nearest one: the flow you mean is the one a difference gets
**collected** along — the list — not the value's birthplace.
(Candidate 2 survives only if "ancestor" can mean an *outer*
uncollect, which reopens "*which* ancestor?" — itself
underdetermined.)

**Sharpening "which collect."** "Handle the error inside the loop"
then raises the message's worry: now two collects are in scope — an
option-collect (inner, dealing with the error) and the list-collect
(outer) — and a rule of "the *nearest* collect binds" would bind
the option collect, the wrong one. The fix is to bind not the
nearest collect in scope but **the collect that gathers the flow
the Delay is actually on.** The option-collect gathers the *option*
flow (consumed upstream to produce a per-element value); the
Delay's flow is the list-level flow that survives, gathered by the
*list* collect. On that reading the ambiguity dissolves — there is
a unique collect-of-the-Delay's-flow, and it is the list collect.

**Three ways to handle the option, and the commute is a sequence.**
The original framing was "commute the option out to deal with it
later," and it is well-formed — but via *monadic sequence*, not
transpose (the distinction above). A per-element option cannot be
*transposed* out (it is not independent of the list, so there is no
product), but it can be *sequenced* out — `List<Option> →
Option<List>`, short-circuiting to None on the first error
(`lazy-stream-commute-design.md`). That gives option-outer,
list-inner; the differences then thread the inner list in the Some
branch. So there are three handlings, each a different program:
**(a) sequence out** (whole list is None on any error, else
differences over all readings); **(b) filter inside** (drop errors,
differences over the Some-subsequence); **(c) keep positions**
(Delay on the full `~L` with a stated hold-or-skip at each None).
(2026-08-16: handling (a) is, in the case-cell account's vocabulary,
a first-witness **case-cell scope lift** —
`case-commute-polarity-design.md`, Tier-1, nothing adopted — and
whether (a) may also keep the prefix of readings before the first
error is exactly that round's prefix-retention question. The three
handlings stand as three different programs either way.)

**The well-formedness wrinkle, as predicted.** Route (b) makes the
Delay's flow the **Some-subsequence**, so the register "only
updates when the option is Some" — exactly the message's guess.
That is well-defined ("differences of present readings, skipping
errors"), but it is a *different program* from route (c). So
"reference the list" names different flows depending on how the
option was handled upstream — the handling has already changed what
"the list flow" *is* at the Delay's location. That is the example
worth keeping: the same phrase can mean several flows, and only the
drawn structure (which handling, sequence vs filter vs keep) says
which.

**What it settles, and what it doesn't.** The "collect of the
Delay's own flow" rule cleanly disambiguates *nesting* (option
inside list) and votes collect-binding there. It does **not** touch
the case where *one* flow is gathered by *several* collects in
different orders — the product / multiple-collect fork (argument
1), still balanced, still the hard open case. Two distinct
ambiguities, then: nesting (resolved here, toward the collect) and
multi-collect-of-one-flow (the product, open) — and only the second
carries the recompute cost.

## The disambiguation-vs-wire-mess tension

Underneath the vote is a general pull. Because more than one flow
is routinely in scope, a flow-feature like Delay should make *which
flow it means* unambiguous, and the surest way is to have it
**reference the flow explicitly** — which is a vote for every
feature-of-a-flow carrying such a reference. (This is a *read*
reference — "which flow do I mean" — not the in-and-out
wire-threading rejected above; that was rejected for imposing a
meaningless *order among Delays*, which a one-way reference does
not.) The provisional *textual* syntax already carries it: `~L ~>
delay init 0 => sum` names `~L`, and text pays nothing for it. The
**visual** form does pay: every attempt so far to draw the
reference as a wire from the flow to the Delay comes out a mess of
wires, defeating the clarity the reference was for. So the examples
expose a sharp, unresolved sub-problem: **can the flow be fixed
implicitly and reliably** — the "collect of the Delay's own flow"
rule is the current best candidate, and it handles nesting — **so
no explicit visual reference is needed; or is a lightweight visual
flow-reference unavoidable, and if so can it be drawn without the
mess?** This tension, not the collect-vs-ancestor label alone, is
the live obstacle, and it is where more worked examples would pay
off next.

## The product sharpens both: a symmetric flow forces the reference

The optional-readings example is a *nesting*, and nesting is
asymmetric: of the two flows the value descends from (the list and
the option) one is consumed away upstream and one survives to the
Delay, so "the flow the Delay is on" has a unique answer and the
implicit rule reads it off the surviving flow. A **product**
removes that asymmetry, and removing it is what forces the
reference. Take the running sum over a cross — the second-simplest
example after the plain scan:

```
xs -> open list => x, ~x
ys -> open list => y, ~y      -- sibling: cross, not zip
x, y -> add => s              -- one value per (x, y): the product flow {X, Y}
~? ~> delay init 0 => run
run, s -> add -> step of run => total
```

Where the plain scan wrote `~L ~> delay` with `~L` the only flow in
scope, the product leaves `~?` genuinely open: `s` lives on the
product flow {X, Y}, and `~x`, `~y` are two *sibling* candidate
axes — neither consumed, neither surviving over the other. Two
consequences, one for each candidate:

- **Candidate 2's "which ancestor" gets a second, harder failure
  mode.** In the nesting example the wrong ancestor was the
  *innermost* one (the option), and "an outer one" pointed at the
  fix. Here the two ancestors `~x` and `~y` are **incomparable** —
  the product's axis contexts are incomparable by construction
  (`product-flows-design.md`, "The poset") — so "nearest" does not
  even apply: there is no nearest, and no local asymmetry to break
  the tie. Nesting shows the nearest ancestor can be wrong; the
  product shows there need not be a nearest at all.

- **The implicit rule has a flow but no axis.** "The collect that
  gathers the flow the Delay is on" disambiguated nesting because
  one flow survived to *be* that flow. Over a product the Delay's
  flow is the multi-axis {X, Y}, and folding it needs *an axis*,
  which the local wiring does not distinguish — `x, y -> add` is
  symmetric in its two inputs. The rule can name the flow but not
  the axis, and the axis is the whole content (running sum down
  columns vs along rows are different programs — "Registers over
  products", `product-flows-design.md`).

So the product is exactly where the two open items meet, and
meeting there shows they are **one trade, not two puzzles**:

- **Collect-binding pays no reference and buys the recompute
  cost.** A collect reading the register's flow must orient the
  product to gather it at all ("orders live at terminations"), so
  it *already* names an inner axis; the register folds along it and
  nothing new is drawn. The price is argument 1's: two consumers in
  opposite orders name two axes, want two grids, and
  compute-once-transpose breaks. (Residue, since **closed** in
  §"The product, re-read through update-cadence and read-range":
  the pure-`final` corner, where no collect reads the running
  values, seemed to have no consumer to supply the axis — but over
  a product `final` is a reduced-rank flow, so "final along which
  axis" is the choice its consumer makes, and collect-binding needs
  no fall-back. The recompute cost is therefore borne only by the
  corner's complement — several running-view consumers reading a
  non-commutative register in different orders.)

- **Ancestor-reference pays the reference and buys the stable
  grid.** Fixing the axis at the Delay keeps "running sum along X"
  one point-indexed grid that transposes like any product value —
  but the Delay must *say* X, and a symmetric product cannot infer
  it. That is the wire-mess, and here it is unavoidable in **both**
  surfaces: even the textual form must write `~x ~> delay` or `~y
  ~> delay` — the free `~L` inference is gone. The visual form does
  not merely pay the reference, it pays it *ugly*.

The disambiguation-vs-wire-mess tension is therefore not a separate
obstacle beside the collect-vs-ancestor fork; it is the same fork
read from the reference side. Collect-binding *is* the "no explicit
reference" branch (the consumer's unavoidable orientation supplies
the axis); ancestor-reference *is* the "explicit reference" branch
(the axis fixed at the Delay, which a symmetric product cannot
supply implicitly). Paying recompute and paying the reference are
one choice. And the boundary is sharp: the reference is forced
**exactly** on flows symmetric under their axes — products — and is
needed nowhere a single flow survives (plain scans, nested
handlings). That localizes the wire-mess to one construct's
interaction, which is the most the examples have narrowed it to.

## The value-in-context model, examined

Status: worked with leanings, **not adopted** — read this section
as a candidate account and the case for it, not as how the language
works. It takes up the Open list's fifth item — argument 2's
reframing, flagged *unexamined and consequential if true* — because
on examination it does not merely dissolve candidate 2's rejection;
it **reframes the whole collect-vs-ancestor fork** and predicts,
rather than being surprised by, both the product's axis problem and
the transpose cost. The examination reaches into what an uncollect
produces, so it is carried carefully and its global cost stated at
the end.

**The model, precisely.** An uncollected value is not a scalar. It
is a **cursor into the sequence of values its wire takes across the
flow's firings.** At firing *n* the cursor is at position *n*; the
plain value is the cursor's *current-position projection*; `prev`
steps the cursor back one firing, `next` steps it forward. The
sequence a wire is a cursor into is not the source list — it is the
sequence *this wire* takes: for the source element, the list; for
`x * 2`, the doubled elements; for a register's read port, the
accumulated values. "The flow a value is on" (the notion the
sharpened rule already leans on) is precisely "the sequence its
cursor ranges over." Every value on a linearly-ordered flow has
this structure; ignoring it recovers the plain value, so the model
burdens no one until they reach for `prev`/`next` — the scalar
reading *is* the model with the context projected away. That is
the answer to the beginner-bar worry the reframing raised:
value-in-context is a conservative extension, invisible in the
common case.

**It decomposes iteration state into two independent moves.** Once
a value is a cursor, the register is not primitive — it factors:

- **Raw previous** — read the wire's own predecessor. On a wire
  whose firing-0 value is supplied by the flow (a source element,
  any function of source elements), the sequence has nothing before
  position 0, so `prev` at firing 0 is **None**: raw previous is
  *option-typed*. This is the rejected `prev(x)` candidate —
  resurrected honestly, as a readout on the wire's context rather
  than a name lookup (see below). Successive differences of raw
  readings, `x - prev(x)`, need no seed and no register; they need
  the option handled at the boundary.
- **The seed** — insert an initial value *before* position 0. The
  wire's sequence becomes `[init, v0, v1, …]`, `prev` at every
  firing (including the first) reads a defined value, and the
  option vanishes. This is exactly "the link splits the initial
  value" and "access-previous is never option-typed," now stated as
  *what the seed does to the cursor's domain*: it extends the
  sequence one position to the left.

A **register is the composite**: a seed (fills the None) *plus*
self-reference (the wire's next value is computed from its own
`prev` — the feedback). Drop the self-reference and you have a
seeded shift-register (raw `prev` with a default); drop the seed
and you have option-typed raw previous. So `Delay = raw-prev + seed
+ feedback`, and the three-way coupling (assign-initial /
access-previous / assign-iterated) is read off the factorization:
the seed is assign-initial, the cursor's `prev` is access-previous,
the feedback is assign-iterated.

**What this does to the old `prev(x)` rejection.** Now, you might
remember that `iteration-with-state-design.md` rejected a `prev(x)`
construct outright, and wonder how this model can resurrect
something so like it. It turns out the model dissolves each of the
four reasons that sank `prev(x)` — without re-proposing the
original shape:

1. *"The argument is a label, not a value."* Under the model `prev`
   is a readout **on a wire** (like `.field` or a projection), not
   a function taking the identifier `x` to look up "the node one
   iteration ago." It reads structure the wire carries. Reason
   dissolved — *provided* the surface spells `prev` as an operation
   on the cursor, not `prev(name)`.
2. *"A flow-level feature written as a value expression."*
   Dissolved wholesale: **every** per-iteration value is flow-level
   in exactly this sense — a cursor into a flow-indexed sequence.
   The objection singled out `prev` for a property all uncollected
   values share. There is nothing left to single out.
3. *"Many `prev` uses are one case split written many times."* The
   None is not per-variable; it is the flow's own "position 0 has
   no predecessor," shared by construction. You discharge it once
   per wire either by seeding (register) or by handling the option
   (raw prev). No duplicated discrimination.
4. *"The None case belongs outside the flow."* Yes — and that is
   the seed, evaluated outside, extending the sequence leftward.
   Consistent, not contradicted.

So the reframing keeps `prev(x)`'s correct instinct (intrinsic
previous is real) and pays off its debts (the surface is a
wire-readout; the boundary is the seed or an option), landing
candidate 2's "reads context the wire genuinely carries" as a
worked account rather than an assertion. (The original `prev(x)`
spelling stays rejected as recorded in
`iteration-with-state-design.md`; what is dissolved is the grounds,
and only under this not-yet-adopted model.)

**`prev` vs `next`, and why Delay is backward.** The cursor offers
both directions, and the productivity/causality check is exactly
what says which is legal on which flow:

- `prev` is always causal — position *n−1* is already computed when
  firing *n* runs (productive corecursion —
  `iteration-with-state-design.md`, "Within one iteration there is
  no cycle"). Legal on every flow.
- `next` reads position *n+1* — a value not yet produced in
  iteration order. On a **materialized, random-access flow** (a
  stored list) the data exists, so `next` is fine — the
  neighbour-pairing and windowing idioms are `next` on a stored
  list (APL ships exactly this pair as its shift operators `»`/`«`,
  direction visible as structure — `apl-family-comparison.md`). The
  survey's scan-with-full-history (the DP-table fill: a body
  indexing into the collect's own earlier output,
  `real-loop-survey.md` finding 2.5, worked in
  `variable-rate-consumption-design.md` as the history-indexed
  running view) is the same cursor idea with random access over the
  *materialized prefix* — if the cursor model is adopted, the two
  accounts should be connected rather than named twice. On a **live
  stream or a self-referential register** `next` reads across the
  iteration boundary *forward*, reversing the delay; the
  productivity check rejects it (a cycle that avoids the crossing,
  or a read of the uncomputed).

This is a clean account of a fact the record stated but did not
explain: Delay is specifically a *delay* (backward) and not a
*lead* (forward) because backward reference is causal on any flow
while forward reference is causal only where the flow is already
materialized. The same check that rules out `x = x + 1` rules out
`next` on a live register — one condition, now covering both
directions.

**Products: the cursor becomes a grid-point, and that is the axis
problem.** On a linearly-ordered flow "previous" is a step back
along the one order. On a **product** flow `{X, Y}` the cursor is a
**point in a grid**, and a grid point has no intrinsic
predecessor — stepping back along X and stepping back along Y are
both "previous," and neither is privileged (the product's axis
contexts are incomparable, "The poset"). So the value-in-context
model does not *stumble* on products; it **predicts** the axis
problem: a product value's context is a grid coordinate, and `prev`
on a coordinate is underdetermined until an axis names the
linearization — until something says which order to walk the grid
in. The reference the symmetric product forces ("The product
sharpens both") is, in this model, exactly the datum the cursor is
missing — *which axis to walk* — and the model says why it is
missing rather than treating it as an unexplained defect. The
dividing line the examples found (reference forced exactly on
products, needed nowhere a single flow survives) is restated as:
**a flow is a sequence iff its cursor has a unique predecessor; a
product is a grid iff it does not.**

**The commute criterion this hands us.** A plain scalar value is
commute-invariant — transpose a product and the base grid `s = x +
y` transposes for free ("The inner-axis vs outer-axis cost"). A
value that reads its cursor's context is **not** commute-invariant:
transpose permutes which axis is "previous," so a scan-along-X and
a scan-along-Y are different grids, not transposes of each other
(the mechanical fact `product-flows-design.md` records). The model
sharpens *why*, and generalizes the boundary: the thing that breaks
compute-once-transpose is not "a register" but **any read of
`prev`/`next` context**, register or raw. So the checkable
criterion for "free to transpose" vs "drives a genuinely different
computation per orientation" is precisely **"does this value read
flow-context."** That is a refinement of argument 1: the cost
attaches to context-reads in general, of which the register is the
common instance, and a raw `prev(x)` under a transpose carries it
too.

**What it reframes in the fork.** Candidates 1 and 2 were a fork
about *which flow* supplies the Delay's next iteration — the
collect that gathers it, or the ancestor it descends from. The
value-in-context model says the flow is neither *chosen* — it is
just **the flow the wire is on**, the sequence its cursor ranges
over, fixed by provenance, i.e. by where the wire came from (the
barrier-crossing round's "availability by provenance"). There is no
flow to pick. What is left is not *which flow* but **which linear
order on that flow**:

- On a **sequence** (list, stream, any nesting where one flow
  survives) the order is unique, so the two candidates *coincide*
  and both agree with the sharpened collect-binding vote — the
  cursor's predecessor is the previous firing of the surviving
  flow, which is what the collect gathers.
- On a **grid** (product) the order is *not* unique, so both
  candidates underdetermine identically — neither "the collect" nor
  "the ancestor" names an axis, because the flow itself does not
  distinguish one. The residue is the linearization — the choice of
  reading order — and it is a real added datum no flow-choice
  supplies.

So the collect-vs-ancestor label is, on this reading, **not the
axis of the disagreement** — it dissolves on sequences and is
silent on grids. The live content of the open problem is relocated:
*is a product-crossing register's axis supplied by the consumer's
orientation (collect-binding's no-reference branch, paying
recompute) or fixed at the Delay (an explicit axis-reference,
paying the wire-mess)* — which is the one trade "The product
sharpens both" already isolated. Value-in-context did not decide
that trade; it removed the *other* question (which flow) so the
trade stands alone.

**The cost of adopting it, stated honestly.** The model reshapes
what an uncollect *produces* everywhere: an uncollected value is a
cursor, not a scalar, so `prev`/`next` become available on ordinary
per-iteration values, option-typed at the boundary, and commute
stops being a free transpose for any wire that reads context. Three
consequences to weigh before adoption:

- **Raw `prev` is a new everyday surface.** Successive differences,
  neighbour comparison, run-boundary detection all become "read the
  cursor's predecessor and handle the None" — no register, no seed.
  This is either a welcome simplification (the register is now the
  *seeded* special case, not the only door to previous-value) or a
  second way to do a near-thing that the beginner must be steered
  through. It wants the survey's attention: how often is the wanted
  previous the *raw* element vs a *seeded* accumulator
  (`real-loop-survey.md`)?
- **Commute's invariant weakens.** "Values pass through combining
  constructs as themselves" (the no-bottleneck principle) still
  holds for scalars, but a context-reading value's identity now
  includes its cursor order, so the transpose that is free for
  scalars permutes it. This is consistent with what products
  already do to registers; the cost is making the criterion —
  context-read ⇒ not transpose-invariant — a thing the checker and
  the user must know.
- **It does not, by itself, resolve the product.** It explains the
  axis gap; it does not fill it. The one trade above survives
  intact.

**Leaning.** The model is attractive because it *earns* three
things the fork was carrying as brute facts — candidate 2's "honest
context" claim, the product's forced reference, and the transpose
cost — from a single idea (a cursor into a firing-indexed
sequence), and it collapses the collect-vs-ancestor question into
"sequence vs grid," which is decidable structurally. It is **not**
adopted, on two reservations: the everyday-`prev` surface needs the
frequency check before a second previous-value door is blessed, and
"an uncollected value is a cursor" is a claim about the *whole*
language, not this construct, so it should be adopted (if at all)
at the core-model level with the kinds table and the
barrier-crossing availability rule in the room, not from inside the
iteration-state round. The frequency check is since **run**
(`real-loop-survey.md`, survey 5 — thirty carried-state loops,
previous-value sites as the unit): the raw-prev surface is real but
minority (2/30 as a site's primary shape, 8/30 in any role), and at
six of the eight sightings the raw-prev read *rides a loop that
already carries a register* (convergence tests on consecutive
iterates, `pairwise` walks feeding folds, off-by-one bookkeeping) —
the coexistence configuration this model serves with one mechanism;
and the position-0 boundary was discharged by seed or by
construction at every sighting, never tested per firing — the
model's own seed factorization read back from the field, arguing
that any adopted surface should lead with discharge-by-construction
and keep the per-firing option as the fallback costume. Evidence
for the conversation, which remains unheld; the second reservation
(core-model-level adoption) stands untouched. What this examination settles is narrower
and firmer: **the collect-vs-ancestor fork is not the real axis** —
it is empty on sequences and silent on grids — and the live residue
is the product's linearization trade, alone.

## A stateful value straddles two flows: update cadence vs read availability

Status: worked with leanings, **not adopted** — again a candidate
account, taught here with the case for it. Prompted by an
observation that a stateful value updated inside a *filtered* inner
flow can still be read and collected on the *unfiltered* outer
flow — behaviour an ordinary per-iteration value cannot have. It
sharpens the value-in-context reframing: on a nesting the two
candidates were said to *coincide*, but a register straddling the
nest shows they answer **two different questions about two
different halves of the register**, both present at once.

**The observation.** Uncollect a list, uncollect a per-element
option, use the present value to step a register:

```
readings -> open list => r, ~L      -- r : option<number>
r -> open option => v, ~O           -- v present iff Some
~O ~> delay init 0 => prevValid     -- register steps on ~O
v -> step of prevValid => curValid  -- step = this present reading
```

The register's `step` reads `v`, which lives on `~O` (the
Some-subsequence). So the register **updates only when the option
is present** — its update cadence is `~O`, a strict sub-flow of the
list. Read as a *feature of a flow*, it is a feature of `~O`: it
steps once per Some, idles otherwise.

**Yet its value is available on the whole list.** Because the
register is **total** — every read reaches back to the last update,
or to the seed before any — its value is defined at every list
position, not only the Some ones. So we can sample-and-hold it onto
the *unfiltered* list and collect there:

```
curValid -> hold init 0 over ~L => held   -- sample-and-hold onto the list frame
held -~> collect => filled                -- ordinary list collect: forward-fill
```

`filled` is the readings series with every error position replaced
by the last good reading (or the seed `0` before the first) —
last-observation-carried-forward, a standard data-cleaning move. It
is exactly the user's scenario: **step on the inner filtered flow,
read and collect on the outer unfiltered one.** (`hold ... over ~L`
is a provisional spelling; the pre-step vs post-step reading — hold
`curValid` for "the current present value" vs the register's
`prevValid` port for "the previous one" — is the same within-firing
fine point the plain scan already carries, here read onto the outer
frame.)

**Why only a stateful value can do this.** Try it with an ordinary
value. `v` (the present reading) exists *only* on `~O`; at an error
position there is no `v`, so `v -~> collect over ~L` is
ill-formed — a value that does not exist at every firing of the
flow being collected. In the state grid, the access-current column
(`element`, `v`) is **partial** across the outer flow; the three
coupled columns (assign-initial / assign-iterated /
access-previous) are **total** across it, because the register's
meaning is precisely "the value as of the last update." Statefulness
*is* the totalisation that licenses reading across the wider flow.
That is the extra freedom the observation names: **a stateful value
can be observed on any flow its update cadence is nested within; an
ordinary value cannot leave the flow it is born on.**

**This is `hold`.** The reactive round already has this exact shape
across the event/continuous boundary: `hold(initial, events)` is a
var readable at every moment whose value steps only when an event
arrives (`incremental-flow-design.md`, "The mutation boundary").
The construct is also shipped in the field under two independent
names: tidyr's `fill(.direction = "down")` is exactly this
forward-fill register (direction explicit, composed per group —
`tidyverse-comparison.md`), and the JS reactive ecosystem's
scan-then-hold is the same straddle read across the whole genre
(`reactive-comparison.md`, which also notes combineLatest's
wait-for-all caveat as independent confirmation that the initial
value is load-bearing). Map the correspondence: the option-Some
subsequence is `changes` (the sparse update stream), the list is
the frame the value is sampled on, and `hold ... over ~L` is
`hold`. The iteration analogue was implicit; the observation makes
it explicit — **a register whose update flow is nested strictly
inside its read flow is a `hold`**, and forward-fill, sample-at,
and "value as of the last event" are one construct with the
reactive one. The register-over-a-stream in that doc
(`scan-then-hold`) is this same straddle with the stream as the
inner flow.

**So "what flow is a stateful value over" has two answers, not
one:**

- **Update cadence — one flow, fixed by provenance.** The flow
  whose firing advances the register is the finest flow its `step`
  depends on (here `~O`, because `step` reads `v`). This is
  candidate 2's answer (the ancestor the value descends from) —
  *for the write*. It is not chosen; it is read off the step wire.
- **Read availability — a *range* of flows, chosen by the
  consumer.** The value is readable on its update flow and on every
  flow that flow is nested within (`~O`, `~L`, and any outer). A
  collect may be taken on any of them; on an outer one it holds.
  This is candidate 1's answer (the binding collect) — *for the
  read* — generalised from "the flow" to "any containing flow,"
  with hold filling the gap.

On a **plain scan** (no filter, no nest between step and collect)
the update flow *is* the collect flow, the two answers coincide,
and the fork looks like one question — which is exactly why the
value-in-context section found the candidates "coincide on
sequences." The nested-filter register is the smallest case that
**separates** them: `~O` for the write, `~L` for the read. They
were never one question; they were two, made to look like one by
every example in which the two flows happen to be the same.

**The well-formedness constraint.** Reading a register on flow `F`
is well-formed iff its update flow is **nested within** `F` — its
firings a sub-order of `F`'s (0-or-1 Some per list element; more
generally 0-or-many inner firings per outer). Then "the most recent
update at or before this `F`-firing" is always defined, hold is
total, and the seed covers "before any update" (the same empty-case
double-duty the initial value carries throughout the register
design, `iteration-with-state-design.md`). The converse direction
is trivial and not hold at all: reading a register on a flow
*inside* its update flow (an outer-list accumulator read within an
inner-list body) is ordinary outer-value-in-inner availability —
constant across the inner firings, no reach-back involved. Only
**write-nested-inside-read** needs hold, and only statefulness
makes it total.

**Two more programs.** A running count of valid readings, legible
on every row (a progress readout that advances only on real data):

```
readings -> open list => r, ~L
r -> open option => v, ~O
~O ~> delay init 0 => nSeen
nSeen, 1 -> add -> step of nSeen => count
count -> hold init 0 over ~L => held
held -~> collect => progress          -- progress[i] = #valids at or before row i
```

Using the held state in the outer computation *before* collecting —
the user's "still use the value in the unfiltered flow." Tag every
row (error or not) with its gap from the running mean of valid
readings:

```
readings -> open list => r, ~L
r -> open option => v, ~O
~O ~> delay init 0 => sumV
sumV, v -> add -> step of sumV => sumV'
~O ~> delay init 0 => nV
nV, 1 -> add -> step of nV => nV'
sumV', nV' -> safeDiv => mean          -- running mean of valids, lives on ~O
mean -> hold init 0 over ~L => meanHeld  -- now available on every row
r, meanHeld -> gap => tagged           -- outer computation over the full list
tagged -~> collect => report
```

The held mean (stepped on `~O`) is consumed on `~L` alongside the
raw `r`, then the list is collected. The held state crosses from
the filtered flow into the unfiltered computation — precisely the
freedom the observation identified, and impossible for the
ungeneralised present value `v`.

**Where this leaves the open fork.** It does not resolve the
product case — the hard residue "The product sharpens both"
isolated (a register straddling a *product*, where the update flow
is a grid with no unique axis) is untouched; a nesting is not a
product, and one flow still survives at each of the two roles. What
it *does* is retire the framing "pick the one flow a Delay is
over." A stateful value is over an **update flow**
(provenance-fixed, one flow) and readable across a **read range**
(its ancestors, consumer-chosen, held). The collect-vs-ancestor
fork was a false dichotomy on sequences not because the two
coincide but because they answer different halves; the genuine open
question that remains is the product's linearisation, where the
*update* flow itself is a grid. And it hands the
disambiguation-vs-wire-mess tension a new instance on the read
side: whether the surface must *state* the read-range crossing
(`hold ... over ~L`) or can *infer* it from the collect sitting on
an outer flow is the same implicit-vs-explicit question, now for
observation rather than update.

One more read has since joined the family this section opened:
the **final readout** is the at-completion read of the same
state — worked as end-when's open question 4
(`end-when-design.md`, "The register final-readout anchor",
candidate rule, not adopted). Its anchor rule leans on this
section's division verbatim (update cadence fixed, reads
consumer-chosen), extends the read range by cut-derived prefix
flows for the completion case, and files its explicit-vs-inferred
anchor question as a second client of the implicit-vs-explicit
instance above — one decision, two clients.

## The product, re-read through update-cadence and read-range

Status: worked; this section closes the pure-`final` residue. The
straddle section split a register into an **update cadence** (the
flow whose firing advances it, provenance-fixed) and a **read
range** (the flows it can be read on, consumer-chosen), worked it
on a *nesting*, and left the *product* explicitly untouched.
Applied to the product the split does two things: it locates the
linearization difficulty in one half of the register, and it closes
the pure-`final` corner "The product sharpens both" left owed.

**The product keeps one flow for both halves, but makes it a
grid.** On the nested-filter register the halves lived on two
*different* flows — update on `~O`, read on `~L` — and the only
question was which half reads which (resolved: provenance for the
update, the consumer for the read). A product adds no second flow.
The running-sum-over-a-cross register updates on `s`, which lives
on the single product flow {X, Y}, and reads on {X, Y} or any flow
it nests within — both halves name the *same* flow. So the
product's difficulty is not a flow ambiguity at all: the one flow
both halves point at is a **grid, not a sequence**, and only the
update half needs a sequence.

**The difficulty is an order in the update half; the read half is
ordinary.** This is the sharpening the lens buys. On the nest the
update cadence was the *easy, provenance-fixed* half and the read
range the consumer-chosen one; on the product the halves swap
difficulty. The read range stays ordinary — pick an axis and
`final` is a reduced-rank flow (register-along-X ⇒ a Y-flow,
`product-flows-design.md`, "Registers over products"), read and
held like any value. The update cadence is provenance-fixed to *the
flow* {X, Y} but **not to an order on it**: provenance hands the
update half a grid and asks it to advance one firing at a time, and
the grid has no unique next firing. So the whole linearization
residue sits in **one half** — the update cadence's missing order —
independent of the nest's flow-separation, with the read side
carrying none of it. (Value-in-context reached the same point from
the cursor side: a product cursor is a grid-point with no unique
predecessor. The straddle lens adds *which half owns the missing
predecessor* — the write's step, never the read's availability.)

**The pure-`final` corner is not a gap.** Now, you might remember
that "The product sharpens both" flagged a thread the mechanism
seemed to owe: under collect-binding a register with **no
running-view consumer** — only `final` read — has "no consumer to
supply the axis" and must "fall back to the feedback collect's own
orientation." It turns out there is no fall-back to owe, because
over a product **`final` cannot even be named orientation-free.**
Register-along-X folds X and outputs a *Y-flow* (rank n−1);
register-along-Y outputs an X-flow (`product-flows-design.md`,
"Registers over products"). So "the final value" is not a complete
demand over a product — you must ask for *final along which axis*,
and that request is itself the axis choice, made by whoever
consumes the exit value. Collect-binding holds one level out: the
consumer of `final` names the axis exactly as a running-view
collect would. Two sub-cases exhaust the corner:

- **Commutative step** — order-free by the confluence
  (`product-flows-design.md`, "The one order-free exception"); the
  whole cube reduces with no axis named, nothing owed.
- **Non-commutative step** — a scalar `final` over a product is *n*
  nested collects whose nesting *is* the axis permutation (the S₃
  choice), drawn by the author; a lower-rank `final` fixes the
  folded axis by its own rank. Either way the demanded shape pins
  the axis.

So the feedback collect's "own orientation" is never free-floating —
it is read off the rank at which its consumer demands `final`. The
pure-`final` corner closes, and the open case narrows to its exact
complement: **more than one running-view consumer of one
non-commutative register, reading in different orders.** That, and
only that, is argument 1's recompute trade (two consumers, two
grids, compute-once-transpose broken). The product's Delay residue
is thus not "collect-binding owes the pure-`final` axis" but the
single sharp trade already isolated — recompute per consumer
(collect-binding) versus fix the axis at the Delay and transpose
(ancestor-reference) — one construct, one decision.

## Per-kind "next iteration": the owned-order criterion

Status: **adopted** (design conversation, 2026-07-23, in the same
rolling conversation that decided the surface — the thread
framing). Adopted: the owned-order criterion itself, the
order-demand check named below, and the `hold` identification (the
register whose step ignores `prev`); with them the kinds table's
cashings stand as settled answers. Explicitly *not* part of this
adoption: the product-linearization residue and the
value-in-context model, each of which owes its own evidence before
its conversation (the linearization residue's is since delivered —
`real-loop-survey.md`, survey 4; the value-in-context model's
everyday-`prev` check is since delivered too — survey 5, same doc;
both conversations remain unheld). One cashing carries a filed re-read: "the IO
handle is a wire, not a flow" is put in question by the same
conversation's later IO-as-flow direction (`effects-design.md`,
"The IO-as-flow direction") — if the handle wire is the IO flow
wire, whether that flow supplies a "next iteration" under this
criterion needs its own answer. This section takes up the per-kind
question the firm-ground section left parenthetical — *which flow
kinds supply a "next iteration"* — which bounds where a Delay means
anything at all. It stopped being idle taxonomy a while ago:
several rounds now draw or bar registers over non-list flows, each
writing a check this document had not cashed, and their checks do
not obviously agree with the record's firmest prior boundary
statement. This section reconciles them, and the reconciliation
lands on a criterion none of them quite stated. (A proposed second
client was filed 2026-08-16, unadopted: the case-cell lifting-law
inventory's licensing claim — a first-witness commute's "first" is
the same species of order read as the Delay's "previous", so
witness selection is licensed by this criterion —
`case-commute-polarity-design.md`, "The lifting-law inventory: a
drafted table".)

### The clients, and the statement they strain

What the record already does with registers off the list walk:

- `incremental-flow-design.md` steps a register over an event
  stream (scan-then-hold) and re-clocks the productivity check to
  the event-loop turn ("same check, new clock").
- `concurrent-collect-design.md` bars a register threading state
  *between* concurrent bodies (structurally: a Delay whose flow
  feeds a settle node's body operand) while placing one on the
  **completions flow**, stepping in settlement order.
- `late-bound-operations-design.md` / `served-flow-design.md` let a
  provider hold cross-exchange state exactly when its facet is
  sequenced — a register on the exchange flow of an *unordered*
  facet is ill-formed (the exchange-stateless check).
- `async-flow-design.md` defers "a Delay inside an async stream
  flow" as probably-composing, riding this row.
- `divide-flow-design.md` rules registers over sibling instances
  ill-formed ("there is no time among sibling instances") while the
  recursive-descent parser's position register rides an ordinary
  self-driven children walk *inside* one instance.

The firmest prior boundary statement is `flix-comparison.md`'s: a
register feeds a value back along one walk whose **extent is
fixed** by the opened data — offered as why async/IO supply no
"next." Hold it against the clients and it fails in both
directions. An event stream's extent is not fixed at open (no one
knows how many clicks are coming), yet the incremental round steps
a register over it. A completions flow's extent *is* fixed (n
bodies, n settlements) and its register is legal — but so is the
*async value's* extent fixed (one), and it supplies no next worth
the name. Extent-fixedness sorts these flows one way; the record's
registers sort them another. The criterion must be something else.

### Work backwards from the two lists

Flows the record lets a register ride: the list walk; the stream;
the self-driven flow (the Fibonacci opener of
`source-openers-design.md` — there the register is usually the
*point*); the split-when segment flow and the filtered sub-flow
(`~O`, the straddle section — a register on a nested flow
reinitialises per outer firing, `variable-rate-consumption-design.md`);
the async stream; the completions flow; the event stream; the
sequenced facet's exchange flow; the serial inside of one keyed
lane (`served-flow-design.md`'s keyed cache). Flows where it bars
one: concurrent bodies between the sever and the settle; sibling
divide-flow instances; the members of a saturation round; an
unordered facet's exchanges — and, differently, the product grid.

What do all the hosts share that every barred flow lacks? Not
extent-fixedness — both lists have it both ways, as above. Not
synchronicity — the completions flow and the async stream are
event-loop flows and host registers, while the barred lists have
synchronous members. What the hosts share is exactly this: **their
firings carry a total order that is part of the flow's meaning.**
Walk order, demand order, arrival order, settlement order (made
meaning by settle — below), handle order, a lane's serial order: in
every case the order is *drawn* — stated by the constructs that
minted or shaped the flow — and a reader can say which firing is
previous without asking the scheduler. In every barred case there
is no such order to read.

### The criterion

A flow supplies a "next iteration" exactly when its firings are
totally ordered *by the flow's own meaning* — call that an **owned
order**. And with it, this document's one-sentence answer to the
per-kind half of "what is a Delay":

> **A Delay is a demand for the previous firing under its flow's
> owned total order.**

The sentence says where a Delay means anything (wherever an owned
total order exists), what the read half reads (the value as of the
order's predecessor), and what the write half writes (the value
carried to the order's successor). In the cursor vocabulary of the
value-in-context section it shortens further: a wire's cursor has a
unique predecessor iff its flow owns a total order. (Which order a
*grid* linearizes to is the other half of the ontology question,
and this section leaves it exactly where the previous section put
it — untouched.)

A flow can relate to the criterion four ways, and the kinds sort
cleanly into them:

1. **Owned order — Delay legal.** The host list above. The order's
   *source* differs per kind (walked data, demand, arrival,
   settlement, the handle), and that difference is real but shows
   up only in the clock (below), never in the register's meaning.

2. **No order — Delay ill-formed.** Concurrent bodies between sever
   and settle; sibling divide-flow instances; an unordered facet's
   exchanges; a saturation round's members (a set has no firing
   order). Each ban already exists in its own round as "the same
   species of structural check"; the species now has a statement —
   see "The order-demand check, named," below.

3. **Incidental order — Delay ill-formed, for a sharper reason.**
   This is the clause the criterion earns its keep with: it is not
   enough that an order *happens*; the order must be *drawn*.
   Before the settle node, bodies do settle in some real-time
   order — the runtime just has no license to let a program observe
   it (observing it is what `concurrent-collect-design.md`'s dead
   end 3 rejected). A saturation round's members get processed in
   *some* order by whichever lowering runs — but naive and
   semi-naive are lowerings of one drawing (`saturation-design.md`),
   and a register over the member walk would make the lowering
   observable, promoting an implementation schedule into meaning —
   exactly what abstraction-is-the-source-of-truth forbids. The
   incremental *var* flow is the third instance: a var recomputes
   when the runtime decides (cutoffs skip, necessity gates —
   `incremental-flow-design.md`), so "previous recomputation" is
   schedule, not meaning, and a Delay over the var flow proper
   would observe cutoffs. That is *why* the incremental round's
   register rides `changes` — the event stream, whose arrival
   order is owned — and never a var. A register is a reader of
   order; where the order is incidental, what it would read is the
   scheduler.

4. **Degenerate order — Delay well-formed but inert.** A bare
   option or case alt, the async value, a race's settled output:
   totally ordered, trivially, because there is at most one firing.
   A Delay there never steps; `prev` only ever reads the seed. This
   dissolves the old firm-ground bullet's *reason*: the async value
   supplies no next **because it is one firing, not because it is
   async** — the same reason a bare option doesn't, and nobody ever
   felt a need to write "Delay is meaningless over options" as a
   kind fact. What async-ness itself changes is only the clock. So
   the async *stream* composes, cashing `async-flow-design.md`'s
   deferral at the meaning level: its firings arrive in arrival
   order — owned, serialised by the event loop — so "the register
   lives in the walk" is confirmed, with worked examples still owed
   there.

The product is none of the four exactly: it is **surplus order** —
every axis order is real and none is privileged. Not disorder but
an embarrassment of orders; the register's demand for *one* is the
linearization residue, located by this classification as the
surplus cell, not a new species.

### Serializers: where owned order comes from

Owned order is not free-floating; some construct states it, and
following the record's registers shows a small taxonomy of where:

- **Inherited** — the flow restricts or re-delivers an order that
  already exists: a filter's surviving sub-flow, a split-when
  segment, a stream pulled off a list, a keyed lane's serial
  interior. The sub-order of a sequence is a sequence.
- **Minted** — a construct *creates* the order as its content. The
  settle node is the paradigm: settlement order exists incidentally
  before it, and settle's whole meaning is to convert it into a
  drawn flow — the completions flow — whereupon a register is
  legal. A sequenced facet's handle is the same move for exchanges
  (a handle is an ordering commitment,
  `within-firing-effects-design.md`); a merge's output owns an
  order (the order the merge settles its firings in) with the
  *choice law* among admissible interleavings being fairness, the
  chooser family's question — owning an order and choosing it are
  separate. The self-driven opener mints its own firing order
  outright.
- **Ambient** — the event loop serialises delivery, and an event
  stream's kind says "one firing per event, in arrival order," so
  arrival order is kind content with the loop as its deliverer.

This generalises `concurrent-collect-design.md`'s answer into a
rule: **a register is legal exactly downstream of the point where
order becomes owned, and the order-minting construct is where the
diagram shows the synchronisation.** The register-on-completions
was that rule's first instance; the sequenced facet's stateful
provider is its second.

It also makes the criterion checkable with machinery the record
already has. Every flow constructor states what its output's order
is: inherits one, mints one, states none (the sever's body flow,
instance siblings, set members, an unordered serve), or states
several (Cross — the axes, none privileged). So "does this flow own
an order" is a **provenance walk** — the same species of walk that
availability and the flow laws already use — and the check is
structural, no analysis.

### The kinds table, cashed

| flow | next? | whose order |
|---|---|---|
| list walk | yes | walk order of the opened data |
| stream | yes | the same order, delivered on demand |
| self-driven flow | yes | the opener's own firing order |
| segment / filtered sub-flow | yes | the parent's order, restricted |
| async stream | yes | arrival order (clock: event-loop turn) |
| completions flow | yes | settlement order, minted by settle |
| event stream (`changes`) | yes | arrival order (clock: event-loop turn) |
| exchange flow, sequenced facet | yes | handle order |
| keyed lane, within | yes | the lane's serial order |
| case / option, bare | degenerate | ≤1 firing; `prev` reads the seed |
| async value; race's settlement | degenerate | one firing |
| var (recomputations) | no | incidental — the runtime's schedule |
| exchange flow, unordered facet | no | none owned |
| concurrent bodies (sever→settle) | no | settlement order not yet minted |
| sibling divide-flow instances | no | "no time among siblings" |
| saturation round's members | no | a set; lowering order is incidental |
| product {X, Y} | surplus | every axis order real, none privileged |
| IO / effect handle | — | a wire, not a flow (below) |

Two rows deserve their sentence. The **incremental kind splits**:
the var flow proper supplies no next (incidental recomputation
order), its `changes` stream supplies one (owned arrival order) —
which cashes "incremental unexamined" and explains, rather than
merely reports, where the incremental round put its register. And
the **IO handle is not a flow at all**: its order is real and
total — order along the segment — but it is an order *of
operations on a wire*, not of firings of a walk; there is no
uncollect minting per-firing values along it, so there is nothing
for a Delay to be a feature *of*. That is the effects round's
dissolution ("No register appears," `effects-design.md`) restated
as a kinds fact: a register on the handle carries nothing because
the handle's order needs no carrier — the wire-threading *is* the
order. The firm-ground rule gains its converse: IO threads its
wire because its order lives on a wire; Delay must not thread
because its order lives on a flow.

### What extent-fixedness was doing

`flix-comparison.md`'s statement was doing two jobs, and splitting
them resolves the strain rather than refuting the sentence.
Extent-fixedness is the **termination** account: a walk over opened
data terminates by construction, whatever the carried value does —
true where stated, and still the right contrast with saturation's
fed-back extent. It was never the **next-supplying** account: the
event stream and the self-driven flow have no fixed extent and
honest nexts (and honest possible non-termination, which
`source-openers-design.md` already owns — "an infinite producer is
a real program"; termination arrives separately, from end-when),
while the async value has a fixed extent of one and only a
degenerate next. The two properties are independent, with
counterexamples in every quadrant that needs one. The refinement is
recorded here; the flix sentence stands, as a termination account.

### One check, one clock

The productivity check is order-generic and needs no per-kind
restatement. "Every cycle crosses a Delay" makes firing *n*'s
inputs be firing *n−1*'s outputs **under the flow's owned order** —
and the *clock*, the thing that makes firing *n−1* complete before
firing *n* begins, is whatever delivers that order: the walk step
(list), the pull (stream), the event-loop turn (async stream,
completions, `changes`), the handle's exchange (a sequenced facet).
`incremental-flow-design.md`'s "same check, new clock" is the
general statement, not an incremental special: **one check, the
clock a parameter supplied by the flow's order-deliverer.** Each
client's re-clocking is the one check instantiated; nothing is owed
per kind.

### The order-demand check, named

The record kept writing "the same species of structural check as…"
without naming the species: the register-between-concurrent-bodies
ban, the exchange-stateless check on unordered facets, the
registers-over-sibling-instances ban. The species is one check with
one statement:

> **The order-demand check: a Delay's flow must own a total order.**

Its complement is the productivity check, and together they are the
whole discipline of drawn state: productivity says a cycle must
cross a Delay; the order demand says a Delay must sit on an
order-owning flow. State is legal exactly where a drawn order can
carry it. Like productivity, the check is structural — the
order-provenance walk above — and, like productivity, it is a
property of the graph, not of any single node.

One extension follows from the value-in-context section and rides
its adoption: the transpose-cost criterion there ("does this value
read flow-context") generalised the recompute cost from registers
to *any* context-read; the order demand generalises the same way. A
raw `prev` on a wire whose flow owns no order is exactly as
ill-formed as a register there — if the cursor model is adopted,
the order-demand check covers context-reads, of which the Delay is
the seeded, fed-back instance.

### The hold identification

Beside the per-kind question sat the degenerate-register question
from the reactive side: is a `hold` a register whose step ignores
`prev`? (`incremental-flow-design.md` asserts the parallel and
stops short.) With the straddle split and the criterion in hand the
identification can be made, and the leaning is to make it:

**`hold(init, events)` is the register on the event stream whose
step is the projection onto the new value** — `prev` ignored — read
on any containing frame per the straddle section's read-range rule.
Two facts check it. First, its initial value plays exactly the
register seed's double duty (starting point for the non-empty case,
complete answer for no-events-yet) — a correspondence the
incremental round already noticed arriving from the temporal side.
Second — the confirmation the criterion wanted — although hold's
step reads no history, it is **not order-free**: last-write-wins
reads the order (replacement is non-commutative), so even the state
that carries nothing still demands an owned order, because "latest"
is an order word. Hold demands one thing less than a scan — the
carried history — and the same crucial thing: the order. So `hold`
(step = newest) and the scan (step reads `prev`) are two steps of one
construct, and "hold keeps the latest; a counter needs the latest
plus history folded in" is the difference between their step
functions, not between two kinds of thing. The identification is
semantic; the compile may still treat the mutation boundary
specially (`incremental-flow-design.md`'s root cell), as any
lowering may.

### What this section does not settle

The linearization residue is untouched — the product stays the
surplus-order cell, and the recompute-vs-explicit-axis trade stands
exactly as the previous sections left it. Adoption is owed with the
row's own conversation, not here. The fairness of a *merged* flow's
owned order is the chooser family's question, not this one's. And
the context-read extension of the order-demand check is conditional
on the value-in-context model's adoption, which this section does
not advance.

### Dead ends of this round

Recorded so they are not re-proposed:

1. **Extent-fixedness as the next-supplying criterion.** Fails in
   both directions (event stream: no fixed extent, hosts a
   register; async value: fixed extent, degenerate next). It is the
   termination account, and stands as that.
2. **Async-ness as the criterion.** The completions flow and the
   async stream are event-loop flows and host registers; the async
   value's bar is cardinality. Asynchrony changes the clock, never
   the meaning.
3. **Runtime serialisation as sufficient.** Incidental order is the
   counterexample family: pre-settle settlement order, a saturation
   lowering's worklist order, a var's recomputation order are all
   serialised at run time and all barred — the order must be drawn,
   not merely present. (This is the criterion's load-bearing
   clause; weakening it re-opens
   `concurrent-collect-design.md`'s dead end 3 and breaks
   naive/semi-naive as lowerings.)
4. **Per-kind register modes.** A "register mode" per kind (arrival
   mode, settlement mode, …) would fork every row of the kinds
   table for a construct whose meaning is kind-generic — the same
   knife that rejected "list-with-state" as a flow kind
   (`source-openers-design.md`). One construct, one check, one
   clock parameter.
5. **A Delay on the IO handle.** Already dissolved in
   `effects-design.md` ("No register appears"); restated here as a
   kinds fact — the handle is a wire, not a flow — not re-opened.

## Open

The language has not decided any of the following. Here is the
current state of every strand:

- **Which flow binds a Delay** — collect (candidate 1), ancestor
  uncollect (candidate 2), or a specified third flow — is the live
  fork, and it is genuinely balanced: argument 1 is a real cost on
  candidate 1 (products stop transposing freely across a register)
  but *not* a knockout, since re-running a register per collect is
  a legitimate implementation and an outer-axis accumulator wants
  the store-and-zip cost anyway; argument 2 is the deepest pull
  toward candidate 2 (it questions the uncollect fiction the whole
  record leans on). The optional-readings example adds a vote for
  the collect on the *nesting* axis (a value's innermost ancestor
  can be the wrong flow), leaving candidate 2 owing a "which
  ancestor" rule — a debt the running-sum-over-a-cross example then
  deepens: over a product the ancestors are *incomparable*, so
  "nearest" has no referent at all (two failure modes for candidate
  2 — the nearest is wrong, or there is no nearest). **Reframed by
  the value-in-context examination:** if an uncollected value is a
  cursor into its wire's firing-indexed sequence, the flow is not
  *chosen* at all — it is the flow the wire is on, fixed by
  provenance — and the collect-vs-ancestor labels *coincide* on
  sequences (both agree with the collect-binding vote) and are
  *silent* on grids (neither names an axis). So the fork's real
  content is not which flow but the product's linearization,
  isolated below.
- **Which collect, precisely.** Sharpened by the worked example to
  **the collect that gathers the flow the Delay is on** (not "the
  nearest collect in scope"), which disambiguates nesting cleanly.
  It does not resolve the product case (one flow, several
  collects), which stays the balanced argument-1 fork.
- **Update cadence vs read availability — two flows, not one.**
  Worked in §"A stateful value straddles two flows": a register
  updated inside a filtered inner flow (`~O`) is still
  readable/collectable, held, on the unfiltered outer flow (`~L`),
  because statefulness totalises the value where an ordinary
  per-iteration value is partial. So the collect-vs-ancestor fork
  answers two different halves — provenance fixes the *update*
  cadence (one flow), the consumer's collect picks the *read* flow
  (any containing flow, hold filling the gap) — and they only
  *look* like one question on a plain scan, where the two flows
  coincide. This is `hold` (`incremental-flow-design.md`) reached
  from the iteration side. Carried onto the product in §"The
  product, re-read through update-cadence and read-range": the
  product does *not* split the two halves across two flows (both
  name the one grid {X, Y}), so the read half stays ordinary and
  the entire linearization residue relocates into the **update**
  half — an order missing on the one flow, not a flow ambiguity.
  It adds a read-side instance of the disambiguation-vs-wire-mess
  tension.
- **Disambiguation vs the wire-mess.** The pull toward an
  *explicit* flow reference (so which flow is meant is unambiguous)
  is a vote for feature-of-a-flow nodes carrying one; the textual
  form has it for free (`~L ~> delay`), but every visual attempt is
  a mess of wires. Open: fix the flow implicitly (the "collect of
  the Delay's own flow" rule) well enough to need no visual
  reference, or find a lightweight visual reference that is not a
  mess. Sharpened by the running-sum-over-a-cross example ("The
  product sharpens both"): the reference is forced **exactly** on
  flows symmetric under their axes (products) and nowhere a single
  flow survives, and it is not an obstacle *beside* the
  collect-vs-ancestor fork but the same fork from the reference
  side — collect-binding is the no-reference branch (the consumer's
  orientation names the axis, at the recompute cost),
  ancestor-reference the explicit-reference branch (the axis fixed
  at the Delay, at the wire-mess cost). One trade. **Narrowed** in
  §"The product, re-read through update-cadence and read-range":
  the pure-`final` corner it flagged as owed (no running-view
  consumer to supply the axis) is not a gap — over a product
  `final` is a reduced-rank flow, so "final along which axis" is
  the axis choice its consumer makes, and collect-binding holds one
  level out. The one remaining open case is the corner's
  complement: *several running-view consumers of one
  non-commutative register reading in different orders* — exactly
  argument 1's recompute trade, now the sole hard residue. One
  field vote on the "which order" question exists and should be in
  the room when the trade is weighed: dplyr attaches the order to
  the *operation* — its offset verbs take an explicit `order_by =`
  parameter, and its vignettes treat "lag on scrambled rows" as the
  family's footgun (`tidyverse-comparison.md`) — field support for
  ordering attaching to the operation's walk rather than to ambient
  state, i.e. for the branch where the consumer's stated
  orientation supplies the axis. **The residue is since worked in
  its own round** (`product-linearization-design.md`, exploration,
  unadopted), which claims it dissolves with no new construct:
  order-freedom at consumers is licensed by confluence (Option B's
  own defence), the license is void at order-observing consumers
  (register, raw context-read, spanning handle), and there the axis
  is the **drawn orientation of the flow itself** — Cross's stored
  (outer, inner) operands plus authored commutes, ordinary nesting
  from there — neither the binding collect (a downstream operand
  must not select upstream values, and consumer orientation
  conflates fold axis with read order) nor the ancestor. "One
  register read in two orders" becomes unrepresentable — visibly two
  registers sharing the context-free base — and the whole residual
  cost is the *orientation-pinning demand* (authored to the observed
  depth, discharged by commutativity, never triggered by per-firing
  handles). If adopted, the fork closes on this list's "a specified
  third flow." That round also re-reads the dplyr datum: `order_by`
  and arrange-then-scan vote for the order being *stated* at or
  above the observer, which is the drawn-orientation shape.
- **Is "value wire in context" the right model of an uncollected
  value?** Argument 2's reframing — every per-iteration value
  carries a previous and a next — reaches beyond Delay into what
  uncollect *means*. Now **worked with leanings** (§"The
  value-in-context model, examined"): the model factors the
  register into *raw previous* (option-typed, unseeded) + *seed*
  (fills the None) + *feedback*, dissolves the four `prev(x)`
  rejections by making `prev` a wire-readout rather than a name
  lookup, explains backward-only Delay via causality (`next` is
  legal only on materialized flows), and — the payoff — reframes
  the fork above (flow is fixed by provenance; collect-vs-ancestor
  coincide on sequences, silent on grids) and predicts the
  product's axis gap (a product cursor is a grid-point with no
  unique predecessor) and the transpose cost (context-reads, not
  just registers, are non-transpose-invariant). Not adopted: the
  everyday-`prev` surface owed a frequency check — since **run**
  (`real-loop-survey.md`, survey 5: raw-prev is minority and
  mostly a companion read on register-carrying loops; the boundary
  is always discharged, never tested — see the leaning section's
  note) — and "an uncollected value is a cursor" is a
  whole-language claim to be weighed at the core-model level, not
  from inside this round; the conversation is not yet held.
- **Is Delay the right abstraction at all?** Argument 3, held open.
- **Per-kind "next iteration."** Now **worked with leanings**
  (§"Per-kind \"next iteration\": the owned-order criterion"): a
  flow supplies a "next iteration" exactly when its firings carry
  an **owned total order** — an order stated by the constructs that
  minted or shaped the flow, not one that merely happens at run
  time — and a Delay is a demand for the previous firing under
  that order. The clients' checks cash against it one for one: the
  event stream and the completions flow supply a next (arrival and
  settlement order, owned — `incremental-flow-design.md`'s
  scan-then-hold and `concurrent-collect-design.md`'s
  register-on-completions are licensed); the async stream composes
  (`async-flow-design.md`'s deferral confirmed at the meaning
  level, worked examples still owed there); concurrent bodies,
  sibling instances, saturation members, and unordered facets own
  none — their register bans are one species, the **order-demand
  check** (a Delay's flow must own a total order), productivity's
  structural complement; the async value and the bare option own a
  degenerate one (≤1 firing — `prev` only ever reads the seed, so
  "async supplies no next" was cardinality, not async-ness); the
  var flow's recomputation order is *incidental* (state lives on
  `changes`, never on a var); and the IO handle is a wire, not a
  flow. `flix-comparison.md`'s extent-fixedness is refined to the
  termination account only — independent of next-supplying, with
  counterexamples both ways. The productivity check is one check
  with a clock parameter (whatever delivers the owned order), and
  `hold` is identified (leaning) as the register whose step
  ignores `prev` — still order-demanding, since "latest" is an
  order word. Remaining: adoption (with the row's conversation);
  the fairness of a merged flow's owned order stays the chooser
  family's; extending the order-demand check from Delays to raw
  context-reads rides the value-in-context model's adoption.

## The frame menu (exploration, 2026-08-12): offers, not demands

Status: **exploration, unadopted** — a working round on how a
thread indicates *which frame it accesses*, opened by two
concerns: reading the frame source off the thread's anchors alone
is too subtle to be the reading experience, and one carrier can
host several walks (a list iterated by 2s), so the anchors'
carrier under-determines the frame. Recorded here because this is
the chapter's own question — which flow supplies the next
iteration when more than one is in reach — approached from the
surface side.

**A frame is never over a structure; it is over a drawn source
object.** "Iterated by 2s" is not the list plus a stepping
parameter on the thread — it is a *different walk*: a derived
flow whose firings are the pairs (split-when / a pairs
derivation, `variable-rate-consumption-design.md`). Stride-2
frames (one register on the pair-walk) and a width-2 window on
stride-1 frames (the plain walk, two registers in shift
formation) are different programs, and both are explicit once a
frame source must be a walk or a site family, never a bare
carrier.

**The menu is this chapter's adopted table, read in the other
direction.** The owned-order criterion classifies each flow kind
by whether its firings carry an owned total order; read as a
demand it is the order-demand check, and read as an **offer** it
is the menu of frame kinds an anchor's provenance provides — the
flows in reach that own order are the ones offering "next"; a
site offers the hypothetical frame (demands/offers being
`types-design.md`'s existing vocabulary). The thread annotates
the **kind** it accesses (e.g. `next`), never the provider:
naming the provider is rejected on the visual-leap constraint
(`language-design-philosophy.md`) — a textual reference to a flow
is, visually, a wire to it, and a flow wire into a thread reads
as the thread operating on the flow, which it does not (also:
too many wires). Resolution is against the anchors' provenance —
implicit where unique, a **mandatory pin** exactly where
ambiguous (stacked flows, coexisting walks over one carrier),
with the derived resolution always rendered: the completion
posture, applied once more. This generalizes the ergonomics
round's `in ~flow` residue annotation
(`iteration-with-state-design.md`) from a corner case to the
general mechanism, without reintroducing the flow operand (a
reference with a check, not an operand with dataflow — the
abstract wire's authored-over-derivable pattern).

**Markers on the source, ink on the thread** (rendering leanings,
recorded under the visual-leap constraint): the frame is
announced where it is minted — a bracket at the uncollect
labelling the walk's derived body region (a display-time collapse
view, not a scope), the site's C-shape cutout already being the
hypothetical's marker — and the thread's sub-species (structural
vs hypothetical) carries distinct line styles. Redundant encoding
— source marker, thread style, kind annotation, plus the editor
enumerating the menu at any anchor (the suggestion surface,
`program-editing-design.md`) — is the answer to the subtlety
concern; no single clever rule is asked to carry the reading.

**Offers compose along the provenance path** — the round's new
and least-tested claim. A case layer *gates* ("next" refines to
"next kept firing" — exactly the implemented register over a
filtered driving flow, this chapter's route (b)); a product layer
*fibers* ("next of the outer axis" from per-inner anchors is the
implemented fibered register, lawful exactly under
rectangularity); a jagged nesting *blocks* (no alignment —
witnessed). The composition rule has been checked only against
the kinds the compiler exercises; stream, async, incremental, and
the frame flow itself (`divide-flow-design.md`) are unexamined
against it.

Open: the full menu per kind (is "next" the only structural frame
kind? a stream's next is pull-shaped; does an async flow offer
anything?); whether the kind-annotation and the drawn join-chain
authoring are recorded as two paths to one reading; the
mandatory-pin threshold (the leaning: pins stored only where
resolution is ambiguous, the derived resolution always shown);
spellings throughout.
