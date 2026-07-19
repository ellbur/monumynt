# What a Delay is, and which flow binds it

Status: an open problem, genuinely unsettled. This chapter teaches a
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
- **Open**: the current state of every strand.

Where it stands after all of that: the collect-vs-ancestor label is
**not the real axis**. The one hard residue is the **product's
linearization** — that is, which reading order several consumers of
one order-sensitive register each walk a multi-axis grid in —
several running-view consumers of one non-commutative register
reading in different orders — the recompute-vs-explicit-
axis-reference trade. Everything else has either coincided, been
answered by provenance (update) and the consumer (read), or been
closed.

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

(Which kinds actually supply a "next iteration" — list and stream
clearly; async/IO apparently not; incremental unexamined — wants
the kinds table's attention, since it bounds where Delay is even
meaningful.)

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
iteration-state round. What this examination settles is narrower
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
  orientation supplies the axis.
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
  everyday-`prev` surface owes a frequency check, and "an
  uncollected value is a cursor" is a whole-language claim to be
  weighed at the core-model level, not from inside this round.
- **Is Delay the right abstraction at all?** Argument 3, held open.
- **Per-kind "next iteration."** Which flow kinds supply one (list
  and stream yes; async/IO apparently not; incremental unexamined)
  wants the kinds table, since it bounds where Delay means anything
  at all. This is no longer an idle taxonomy question: several
  rounds already *use* registers over non-list flows, writing
  checks this row has not cashed. `incremental-flow-design.md`
  steps a register over an event stream (scan-then-hold) and
  re-clocks the productivity check to the event-loop turn ("same
  check, new clock"); `concurrent-collect-design.md` rules a
  register threading state *between* concurrent bodies ill-formed
  (a new structural check — a Delay whose flow feeds a settle
  node's body operand) while putting a register on the
  **completions flow**, which the event loop serialises, so it
  steps in settlement order; and `async-flow-design.md` defers "a
  Delay inside an async stream flow" as probably-composing.
  (`effects-design.md` was on this client list while it threaded a
  marker register; the sequencing-commute re-reading removed it —
  one fewer check to cash.) Each of these presupposes an answer to
  which kinds supply a "next" — the firmest boundary statement so
  far is `flix-comparison.md`'s: a register is value feedback along
  a walk whose **extent is fixed** by the opened data, which is
  *why* async/IO (extent not fixed at open) supply no "next" — yet
  a completions flow serialised by the event loop plausibly does.
  Reconciling these clients with the kinds table is this row's most
  concrete owed work. Beside it sits the degenerate-register
  question from the reactive side: is a `hold` a register whose
  step ignores `prev`? (`incremental-flow-design.md` asserts the
  parallel, stops short of the identification.)
