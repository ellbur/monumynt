# End-when: data-driven termination

Status: exploration — a proposal with leanings, not adopted. The
construct worked out here (end-when as a binary flow operation) is
prepared for the design conversation; per the sampling method's own
rule, evidence reweights the agenda but decisions stay in the
conversations.

End-when is how a walk stops early because of what it sees — the
first match, a sentinel, a value within tolerance. In conventional
code this is `break`, `find`, `takeWhile`, or an exception; in this
language it is one flow operation that shortens a flow and records
why it stopped.

## Why the language needs it

Across sixty randomly sampled real loops, roughly eighteen terminate
early or on a data condition — more than every stateful class
combined in the first survey, second place in the second
(`real-loop-survey.md`). Early termination is the single biggest
everyday demand the language did not yet serve. Meanwhile the divide
flow, the concurrency items, and the register designs all had worked
designs; the construct ordinary sequential code demands most had the
least.

The demand, gathered from the record, has a stable shape:

- **Four everyday guises** (survey 1). *First-match / any*: the
  found/not-found outcome is a case split *produced by termination*.
  *Take-until-a-sentinel*, with an inclusive/exclusive wrinkle — one
  sampled loop keeps the terminator element, another drops it.
  *Poll-until with a result payload*: the loop's value *is* the early
  exit's payload. *Predicate cursors*, where termination is the
  entire point of the loop.
- **The numerics sharpening** (survey 2): in numeric code,
  data-driven termination arrives *fused to a scan* — loops stop
  because of their carried state (take-while on the term size,
  retry-until-tolerance). So end-when must compose with the register
  designs, whichever candidate wins.
- **Tough-use-case demands**: until-loops (bottom-up mergesort's
  "repeat until one run remains"), protocol framing, and the
  decision-driven merge's stop verdict (`tough-use-cases-design.md`,
  inventory item 4).
- **Self-driven flows are unusable without it** (survey 1): a
  self-driven flow — repetition with no source — that has no
  data-driven terminator and no interrupt simply never ends.

## What the record already fixes

Before proposing anything, the existing design record constrains the
shape from five directions. Once these are assembled, the construct
nearly draws itself.

**Conditions are case splits, not predicates.** The language has one
vocabulary for "does this element satisfy P": a case split producing
a bundle of alt flows. Filtering is already defined that way —
`join(list, case flow)` keeps the firing elements of an alt
(`core-model.md`, "Join, and filtering as join"). Higher-order
predicates are rejected outright: a function waiting to be called has
no honest visual form (`configuration-scopes.md`). So end-when's
condition must arrive as a flow, never as a lambda or a bare boolean.

**Terminators exist and carry payloads.** Every flow kind has a
termination event, and failability — a terminator carrying a payload
— is a uniform dimension, not a per-kind bolt-on (`async-flow-design.md`,
"Failure as terminator payload"). A consumer that says nothing about
the terminator propagates it. At a whole-flow collect the terminator
is *discharged*: it lands in hand as a settled tagged value, which can
then be case-split. A whole-flow collect over a flow that can end
early therefore has **two value outputs** — the folded prefix, and
the terminator.

**The terminator-writing combinator already has one member.**
Interrupt (`async-flow-design.md`, "Interruption: unless-and-until")
derives a stream that ends early when an external async value fires,
writing `Interrupted(e)` as the derived stream's terminator. End-when
is its synchronous sibling.

**The stream runtime already contains the needed move.** The whole
stream-stage inventory reduces to three runtime moves —
emit-and-continue, become-the-rest, abandon-the-rest
(`lazy-stream-placement-design.md`, "The skip mechanism"). Ending an
output stream at a data-determined element is the third move, which
commute already uses. Compiling to an existing move rather than a
fourth is altitude evidence that the construct sits at the right
level.

**No time travel, and flows have many consumers.** Flow ordering and
extent are established at construction, never retroactively
(`core-model.md`); and one flow may be collected any number of times,
each collect an independent consumer of the same one logical
iteration. Any construct that changed a flow's extent *after* other
consumers were wired to it would act retroactively on them. This
constraint shapes the design most.

## The shape: a binary flow operation

**End-when is a binary flow operation with asymmetric operands
(subject, stop).** Both are flows. `stop` must fire in the subject's
own context, at most once per subject firing — option-kind relative
to the subject, in the sense `partial-collect-design.md` defines. The
output is a new flow, the *shortened flow*.

Its semantics is one law:

> **The law of the shortened flow.** The shortened flow fires with
> each firing of the subject, in step with it, up to but not
> including the first subject firing at which `stop` fires; at that
> firing it terminates, and the terminator's payload is `stop`'s
> value. If `stop` never fires, the shortened flow ends the way the
> subject ends, terminator passed through.

Everything below is a theorem of that law, not extra design:

- **Values from the subject's context are readable in the shortened
  flow directly.** Each firing of the shortened flow is a firing of
  the subject (a prefix of them), so the ordinary prefix-rule
  admission that lets an ancestor's value into any descendant context
  applies (`bundle-provenance-design.md`). No transport machinery.
- **The stop condition is ordinary wiring.** Typically `stop` is one
  alt of a case split on per-firing data — exactly the wiring filter
  uses, consumed by a different node. The two everyday
  per-element-condition consumers line up:

  | operation | operands | keeps |
  |---|---|---|
  | join (filter) | (subject, alt flow) | the firings where the alt fires |
  | end-when | (subject, alt flow) | the firings before the alt first fires |

- **Which condition stopped you is free.** Several stop conditions
  merge into one `stop` operand by a partial collect over their alts.
  The merged flow is option-kind relative to the parent (that
  document's kind theorem), so it is a valid `stop`, and the law's
  payload is the firing branch's value. Which condition ended the
  walk rides the terminator with no new machinery. This holds *for
  alts of one split* — the partial collect's branches must be
  disjoint cell sets of one bundle. Conditions from independent
  splits cannot merge; their story is in "Stacked end-whens" below.
- **The empty and total cases are unremarkable.** Stop firing on the
  first subject firing gives a shortened flow with zero firings and
  an immediate terminator-with-payload; stop never firing gives the
  subject back. If the subject is itself failable, end-when adds one
  more tag to the terminator inventory (`Nil | Fail(e) | Stopped(v)`,
  however the failability round ultimately spells it) — a tagged
  value at discharge either way, no new cases.

### Derivation, not retroaction

The demand named this "writing the terminator from inside the walk."
Worked against no-time-travel and multi-close, that phrase needs one
refinement: **the terminator is written on the derived flow, never on
the subject.** End-when does not reach into an existing flow and
shorten it; it mints a shorter flow beside it. Consumers wired to the
subject see the full walk; everything that should stop is collected
from the shortened flow. The choice of what stops is drawn, not
implied — an author who wants the loop's *other* outputs to stop too
collects them all from the shortened flow, and the drawing says so.

Operationally nothing runs past the cut anyway: if every collect
hangs off the shortened flow, no firing beyond the cut is ever
pulled. The subject "continuing" costs nothing unless someone
actually collects it.

**Rejected: terminator-writing as retroaction on the subject.** A
version where end-when mutates the subject flow's extent — "this flow
now ends here" — would make one consumer's condition retroactively
change what every other collect of the same flow sees. That is
exactly the retroactivity no-time-travel forbids, applied to extent
instead of nesting. It also breaks the one-flow-many-collects model
structurally: whose condition wins when two closes want different
cuts? The deriving form loses nothing, since collecting everything
from the shortened flow expresses the stop-everything reading
explicitly.

**Rejected: a boolean-predicate operand.** A version taking
`end-when(flow, boolean-per-firing)` — or worse, a predicate lambda —
fails three ways the record already owns. It introduces a second
condition vocabulary beside case splits (the same data test drawn one
way to filter and another way to stop, violating one-obvious-reading);
it loses the payload (the boolean says *that* you stopped, not *what*
stopped you, so poll-until-result needs a side channel); and in
lambda form it is the higher-order-function shape
`configuration-scopes.md` rejects. The alt-flow operand gets all
three right and reuses the filter wiring verbatim.

## The readout: first-match falls out of discharge

First-match's found/not-found outcome is a case split *produced by
termination*. The failability design already supplies it: at a
whole-flow collect the terminator is discharged into an ordinary
tagged value. First-match is then end-when plus a collect plus a
discharge case split — three pieces of existing vocabulary and the
one new node. No first-match construct, no option-returning
combinator.

```
-- spelling provisional (open question 6)
xs -> open list -> split find of Match, Other
  Match: -~> end-when          -- shortened flow: fires until the first Match, then terminates carrying it
-~> collect => prefix, ~term   -- whole-flow collect: folded prefix + discharged terminator
~term -> split ended of Stopped, RanOut
  Stopped: found               -- the match is in hand
  RanOut:  notFound
-~> collect => result
```

The prefix output is simply unused when the caller only wanted the
hit (any/exists discards it). The match payload may be the element
itself, unit, or something computed from the element — whatever the
match alt carries.

The other guises are the same drawing with different emphasis:

- **Poll-until-result**: the stop alt's payload is the parsed success
  value; the shortened flow's firings are the failed attempts
  (collect them for logging, or don't). A surrounding timeout in the
  wild sample is interrupt — the data-driven and event-driven
  siblings composing in one drawing, each writing its own terminator
  tag, distinguished at discharge.
- **Take-until-sentinel**: the collect's prefix *is* the value; the
  terminator says which sentinel ended it (or that input ran dry —
  the EOF-vs-close_notify distinction is a discharge case split, not
  two loops).
- **Effect walks**: read-until-sentinel pumps whose per-element work
  is a write land as an effect collect over the shortened flow; the
  effects happen for the prefix, and the terminator reports why the
  pumping stopped.

## Composing with the register designs

The numerics demand is loops that stop *because of* their carried
state. Both live register candidates expose the carried value by
wiring — the port form as the Delay's `prev` output port, the latent
form as the combined flow's `state` port
(`iteration-with-state-design.md`, "Where they agree"). That is the
whole composition story: a stop condition on carried state is a case
split wired from a state port, and its alt is an ordinary `stop`
operand. End-when is **candidate-neutral** — it reads state the way
everything else reads state — so it adds no weight to either side of
the register decision.

Take-while on the term size (a numeric convergence scan):

```
-- spelling provisional
xs -> open list => a, ~L
~L ~> delay init 0 => st          -- register on the flow; carries the scan state
st, a -> term -> abs -> split of Converged, Large
  Converged: -~> end-when         -- stop before the first converged firing
-~> collect => terms, ~term       -- reduce the terms over the shortened flow; final state off it too
```

Retry-until-tolerance / retry-with-escalation is the same drawing
over a self-driven flow: the register carries the precision, the stop
alt fires when the error is within tolerance and carries the accepted
result, and the terminator payload *is* the loop's value. The
**predicate cursor** — the guise where "termination is the loop" — is
the degenerate register case: a cursor register, a self-driven flow,
and a stop condition on the cursor's state. What conventional code
writes as the `while` condition is the stop alt, and the drawing
consists of almost nothing else, faithful to what the loop is.

One genuine subtlety: the register's **final readout** (the write
half's output, `first-class-ports-design.md`) is anchored to a flow's
completed extent. When a shortened flow sits between the register's
flow and every collect, demand never crosses the cut, so
operationally the final value is the state at the cut. But the
*semantic* rule for which extent a write half's `final` reads, when
subject-flow and shortened-flow consumers coexist, needs stating
rather than inheriting from evaluation order (open question 4).

## Self-driven flows become usable

Repetition without a source is ordinary, not exotic. The record's
answer to "loop until" had until now been a self-driven flow with
*nothing to end it* except interrupt — which covers timeouts and
shutdown, not "until the data says so." End-when is the missing half.

Bottom-up mergesort — "repeat until one run remains" — is a
self-driven stream of lists plus end-when plus a final readout. The
concern that this reads as three ways of saying "until" answers
itself once drawn: the three constructs each say a different word.
The self-driven flow says *repeat*, the register says *what carries*,
and end-when says *until* — one construct per word of the sentence
"repeat, carrying runs, until one run remains." The vocabulary sits
at the programmer's abstraction level precisely because those are
three separately-variable choices, and each varies by swapping its
own piece.

## The stopping element: one bit, both readings

The surveys hand us both boundary conventions in one random draw: one
sampled loop tests the line and *drops* the sentinel (`break` before
the write); another *appends* the terminator chunk and then tests
(inclusive take-until). Both are everyday; both must be one gesture.
Three options were weighed.

**Option A: exclusive primitive; inclusive by consuming the payload.**
The law above is exclusive; an inclusive consumer reads the stopping
element from the terminator payload and appends it downstream.
Rejected as the *only* form: it fails expansion continuity for the
collect — "collect a list" stops reading as a list collect and
becomes collect-then-append, a species change for a one-bit variation
— and effect walks have no "append" to compensate with (writing the
terminator chunk would have to duplicate the effect node outside the
walk).

**Option B: one configuration bit on the node — the cut sits before
or after the stop firing.** The shortened flow either excludes or
includes the firing at which `stop` fired; the terminator payload is
present either way. **This is the leaning.** The variation is
genuinely one bit, local to the node; both settings are lawful under
the same law with "up to but not including" swapped for "up to and
including"; and precedent for node-attached configuration is
established (sort's comparator; configuration scopes generally). Its
visual reading is a cut line drawn before vs after the element mark —
layout, out of scope here; what matters is that the bit is binary and
local, not a construct.

**Option C: inclusive primitive; exclusive derived.** The mirror of A,
with the mirror smell, and the wrong default besides: first-match,
poll-until, and the framing cases all want the match out-of-band (in
the terminator), not appended to the prefix. Exclusive-with-payload is
the shape most guises already are.

## Sibling or same node: end-when and interrupt

With end-when drawn, the difference from interrupt is exactly one
property: **alignment of the stop operand.** End-when's `stop` fires
in the subject's own context, at most once per firing, checked by
provenance — so "did we stop at this firing" is a synchronous,
per-firing question needing no race. Interrupt's stop operand is an
async value from an *unaligned* context, so each pull races the
subject's next cell against it. Same output shape (a derived flow,
shorter, terminator with payload); same downstream story (propagate
or discharge); different check and different compile.

That symmetry invites a unification conjecture: one terminator-writing
node whose stop operand may be aligned (this document) or unaligned
(interrupt), with the race machinery switched on by the operand's
kind. **The leaning is to keep them siblings, not unify.** What would
decide is whether checking and compilation genuinely share anything
beyond the output type — and they do not: an aligned stop needs no
race, no pull boundary, no cooperative-interruption caveat, so the
entire mechanical content of interrupt is absent. Interrupt's
mechanical content inventories as per-pull race construction, the
memoised interrupt cell carried across pulls, the pull boundary as
yield point, the cooperative caveat, and the per-pull tie-break
(`race-barrier-design.md` supplies these) — none of which an aligned
stop has. The only shared content is the output type and the
downstream story, which is what the conjecture's own test discounts.
The remaining open half is whether one drawing for both would mislead
more than it teaches: an aligned cut is *inside* the walk's
causality, an unaligned one arrives from outside it — arguably a
difference the picture should show. Until a concrete program needs
them unified, they stay siblings with deliberately rhyming shapes.

## The decision-driven family: scope bounded

Is end-when the decision-driven merge's degenerate case (a chooser
over one head returning advance-or-stop), or separate? **The leaning:
end-when stands alone.** The 80/20 counterweight separates them
cleanly:

- End-when is promoted by *frequency*: eighteen of sixty loops. It
  must be effortless — gesture count is the design pressure, and the
  shape above is one node consuming wiring the program usually has
  anyway.
- The decision-driven merge is a *breadth* obligation: mergesort's
  merge, framing, the tokenizer. It must be possible without too much
  pain; it need not be one gesture.

Deriving the everyday construct from the rare one — end-when as a
one-input merge with a stop verdict — would tax every take-while with
the merge's conceptual weight (choosers, configuration scopes,
per-head verdicts) to buy a unification no sampled program asked for.
What *should* be kept is vocabulary: when the merge lands, its
chooser's verdict inventory (advance-this, advance-that, stop) should
spell "stop" as writing the same terminator end-when writes, so the
family is one family at the semantic level even if its members are
separate nodes (open question 3).

Equally out of scope: **data-dependent take** ("advance how far" —
line filling, the tokenizer, protocol framing's read-N-more). That is
the variable-rate-consumption cluster, where the breadth risk
concentrates, and it is *not* this construct: end-when answers "how
long," not "how much per step." That round exists —
`variable-rate-consumption-design.md` reframes "advance how far" as
boundary placement (split-when) and records the first-segment
relationship between the two constructs as a level-1 recognition, not
a unification, the same posture this round takes toward interrupt.

## By kind, and the compile

Sketches only — this is design; nothing here touches `src/Compile.res`,
and implementation would land after the first-class-ports migration
like the other new nodes.

- **List**: the cut compiles to `break`. The collect's loop carries a
  terminator local; the stop alt's arm assigns the payload and
  breaks; the inclusive bit moves the push above or below the check.
  Exactly the loop the sampled code wrote by hand.
- **Stream**: the cut is per-collect output construction — at the stop
  firing, the fold abandons the rest and becomes the terminator, the
  third of the three existing runtime moves (commute's
  abandon-the-rest, aimed at a terminator value instead of a resolved
  `None`). No fourth move is needed. Laziness supplies the rest:
  nothing past the cut is pulled, so ending the output *is* stopping
  the work.
- **Self-driven**: the stop condition is the emitted loop's `while`
  condition (negated, plus the payload local) — precisely the loop
  shape the survey's self-driven samples wrote.
- **Async stream**: an aligned stop needs no race — the check rides
  the per-cell continuation; this is where the sibling split from
  interrupt is visible in the machinery. Beyond that, deferred with
  the unification question.
- **Incremental**: "changes until a condition, then hold forever" is
  meaningful and untouched here; noted for the incremental doc.

One caveat for the concurrency round: "the *first* firing at which
stop fires" is well-defined on ordered flows (lists, streams,
self-driven), which is everything this round's evidence covers. Under
a concurrent collect, "first" is schedule-determined, the way race's
winner is — if end-when is ever admitted off `serial`, that
non-determinism must be meant, same as race means it. Flagged, not
designed.

## Against the principles

- **Example first, then generalise.** Termination is added to a
  concrete walk after the fact: build the walk, notice it should
  stop, wire the condition's alt into an end-when. Contrast the
  combinator ladder, where early exit forces an upfront species
  choice (`takeWhile`? `find`? `foldWhile`? an exception?) before the
  body is written.
- **Inside-out / cases as values.** No lambda, no interior scope, no
  magic names; the condition is a visible case split, and the
  stopping outcome is a value (the discharged terminator) you flow
  through.
- **Foundations before features.** The construct is mostly assembled
  from settled pieces (case splits, option-kind flows, failability,
  discharge, the three runtime moves); the genuinely new content is
  one law and one bit. Two dead ends died on paper.
- **Programmer's abstraction level.** "Stop when" is a word in the
  programmer's vocabulary, and it gets one node. First-match is not
  "a fold with an Either trick," it is end-when + discharge, readable
  as what it is.
- **No bottlenecks.** The stop payload rides the terminator through
  the collect; the prefix and the payload emerge as two outputs,
  never packed. Conventional languages route this through an
  exception, a sentinel return, or an accumulator-and-flag tuple —
  the flag-variable idiom the surveys kept meeting is precisely the
  bottleneck form.
- **Abstraction is the source of truth.** End-when's list lowering
  (the `break` loop) is a derived view; the authored program keeps
  the cut.
- **Building blocks must build.** The +1 ladder: a plain collect → *+
  termination* (add the case split if absent, add one end-when,
  re-aim the collect at the shortened flow — additions and one
  rewire, no rewrite) → *+ use the payload* (case-split the
  discharged terminator) → *+ the condition moves onto carried state*
  (wire the case split from a state port; the register is the
  addition, end-when unchanged) → *+ a second stop condition*
  (partial-collect the alts; end-when unchanged) → *+ an outer
  timeout* (interrupt around it; distinguished at discharge). Every
  rung is an addition to the drawing. The cliff this removes is the
  one the principle was named for: in combinator vocabularies a walk
  that acquires a stop condition abandons `.map()`/`.filter()` for a
  different species; here it acquires one node.

## What this changes elsewhere, if adopted

Nothing in the record is dissolved or corrected; this fills a named
hole. If the design conversation adopts some form of it: the tough
doc's inventory item 4 gains its worked member; the breadth-set theta
kernel and retry-with-escalation get a concrete owner shape; the
bottom-up mergesort composition can be drawn end to end.
`core-model.md` would gain end-when a line alongside join in "Join,
and filtering as join" (it is the same operand pattern with a
different verb) — but not before adoption.

## Open questions

1. **The inclusive/exclusive bit's final form.** Option B is the
   leaning (one bit on the node, exclusive the default reading); what
   its drawing is, and whether the bit belongs on the node or on the
   stop wire, is open. Both survey shapes must stay one gesture.
2. **Unification with interrupt.** One terminator-writing node with
   aligned/unaligned stop operands, or two rhyming siblings.
   Deliberately unforced; the deciding argument is in the sibling
   section.
3. **Verdict vocabulary with the decision-driven merge.** When the
   merge is designed, its chooser's stop verdict should write the same
   terminator; check then whether anything more than vocabulary is
   shared.
4. **The register final-readout anchor.** When a shortened flow sits
   between a register's flow and its consumers, which extent does the
   write half's `final` read — and what does it mean if subject-flow
   and shortened-flow collects coexist with one register? Needs a
   stated rule; touches the iteration-state round.
5. **Stacked end-whens.** `end-when(end-when(F, a), b)` versus one
   end-when over the partial-collect merge of a and b. Worked below.
6. **Textual form.** The three-arrow textual representation needs a
   spelling for the (subject, stop) operand pair and the discharge
   readout (the samples above are provisional); belongs to that
   document's next round.
7. **Naming.** "End-when" vs take-while/until — parked in the tough
   doc's question 8. One constraint from this round: the name should
   read as a *flow operation* (like join), not as a collect variant,
   since the readout composition depends on understanding that the
   collect is downstream of the cut.

## Stacked end-whens and the merged stop (open question 5, worked)

The question compares `end-when(end-when(F, a), b)` with one end-when
over "the partial-collect merge of a and b." The answer is both
agreement and disagreement, in different regimes, with the boundary
drawn by a demand the partial collect already makes.

### The validity gate the question hides

The partial collect's branches must carry pairwise-disjoint cell sets
**of one bundle** — disjointness is a node demand, and so is
single-bundledness; the merged flow gets its kind theorem (option-kind
relative to the parent) from the bundle being a partition
(`partial-collect-design.md`, "Disjointness is a node demand"). Two
stop conditions that are alts of one case split satisfy this. Two stop
conditions from *independent* splits on the same firing's data —
converged, from a split on the term; exhausted, from a split on the
attempt count — are cells of two different bundles, and **no partial
collect merges them**: both could fire at one firing, the merged flow
would fire twice, and "the firing branch" would not refer.

So the comparison splits in two: where the merged form exists (one
bundle) and where it does not (independent splits). The "which
condition stopped you is free" consequence holds as stated in the
first regime only.

### A restriction rule the stacked form needs first

`end-when(E1, b)` with `E1 = end-when(F, a)` is only well-formed if
`b` is an admissible stop operand for a subject it was not built
against. `b` fires in *F's* context, option-kind relative to F; the
law demands a stop that fires in the *subject's* context, and the
subject is now E1. The rule, stated rather than inherited:

> **A flow that is option-kind relative to F is an admissible stop
> operand for any end-when whose subject's firings are a subset of
> F's firings (here: a prefix), and the law consults it only at
> subject firings.**

Every E1 firing is an F firing, so b fires at most once per E1 firing;
b's firings beyond E1's extent are never consulted (under demand,
never even pulled). This is the flow-wire sibling of the prefix-rule
admission for values (`bundle-provenance-design.md`): an ancestor
context's value is readable in a descendant context; an
ancestor-aligned stop is consultable on a derived prefix flow. If any
form of this round is adopted, the rule needs a home in the provenance
inventory — it is a new admission, not a consequence of the existing
ones.

### Regime 1 — one bundle: they agree, and it is a recognition rule

Let a and b be disjoint cell sets of one bundle in F's context, both
end-whens exclusive, and let i_a, i_b be the indices of the first
subject firing at which each fires (∞ if never). The partition gives
the load-bearing fact: **a and b never fire at the same firing**, so
i_a ≠ i_b whenever both are finite.

- **i_b < i_a.** Merged: cut at i_b, payload b's value. Stacked: E1's
  cut lies beyond i_b, so i_b is a firing of E1; the outer cuts there
  with payload b. Equal.
- **i_a < i_b.** Merged: cut at i_a, payload a's value. Stacked: E1
  cuts at i_a with terminator `Stopped(a)`; b's first firing is beyond
  E1's last firing, so the outer's stop never fires and passes E1's
  terminator through unchanged. Equal, including the tag: a
  passed-through `Stopped` is the same terminator, not a wrapped one.
- **Neither fires.** Both forms end the way F ends. Equal.

The inclusive setting commutes with all three cases (replace "up to
but not including" throughout; the partition still forbids ties),
provided all three nodes carry the same bit. Swapping a and b is
symmetric, so stacking order is immaterial here; and the partial
collect's associativity flattens any number of same-bundle stops into
one k-branch merge.

So: **for stops drawn from one bundle, every stacking order and the
single merged end-when denote the same program.** That is the
recognition rule the question hoped for, in
`transformation-levels-design.md` vocabulary: a level-1 recognition
whose canonical form is the merged one — one end-when, one partial
collect over the stop alts — with the stackings as presentations,
parallel to the partial collect's own bracketing result.

### Regime 2 — independent splits: the program that shows disagreement

The counterexample is the survey's own retry-until-tolerance with a
budget: a self-driven flow of attempts; a register carrying the
doubling parameter; two stop conditions on each firing's data —
`converged` (an alt of a split on the error, payload the computed
result) and `exhausted` (an alt of a split on the attempt count,
payload a diagnostic). Independent splits, and genuinely simultaneous
when convergence is achieved exactly at the last budgeted attempt.

No merged form exists (the gate above). The two stackings, both
exclusive, at a firing i* where both alts fire:

- `end-when(end-when(F, converged), exhausted)`: the inner cuts at i*,
  excluding it; i* is not a firing of the inner's output, so the outer
  never consults `exhausted` there. Terminator `Stopped(result)` — the
  run **succeeded**.
- `end-when(end-when(F, exhausted), converged)`: symmetric. Terminator
  `Stopped(diagnostic)` — the run **failed**, at the same firing of
  the same walk.

Downstream, the discharge case split routes these to different legs.
The two stackings are observably different programs; there is no
canonical form to recognize them into, and there should not be — the
difference is meaningful, and some program wants each.

**The tie-break theorem.** With an exclusive inner, the inner stop
wins ties: the tied firing is cut out of the outer's subject before
the outer looks. With an *inclusive* inner, the tied firing survives
into the outer's subject, so the **outer** stop wins. Both are
theorems of the law — deterministic, no ambiguity. But the flip is a
genuine surprise: the inclusive bit, introduced as a local one-bit
variation on the cut position, also selects stacking priority when
stops can tie. That interaction is an input open question 1 should
weigh (e.g. if the bit moved onto the stop *wire* rather than the
node, each stop of a stack could carry its own bit, and the priority
reading would need restating).

### The authoring reading

Conventional code resolves this same tie silently, by statement order
inside the loop body — `if err < tol: return r` a line above `if n >=
maxiter: raise` is a priority decision nobody drew. Here the choice is
visible structure, and there are exactly two ways to spell it:

- **Stack**, and the order (with the bits) is the priority — drawn,
  not implied.
- **Split once**, on a discriminator over both facts, producing one
  bundle `{converged, exhausted, continue}` — writing the
  discriminator forces the tie decision into the split itself, and the
  merged form (regime 1) is then available again.

Either way the program says which condition wins; the language merely
refuses to let the tie be an accident. This is the inside-out
principle showing up unplanned: termination priority is not an
artifact of interior statement order, because there is no interior.

### What this settles, what it leaves

Settled on paper: the recognition rule exists with its scope exactly
the merged form's validity (one bundle, matching bits); outside that
scope stacking order is content, with a stated tie-break; the
counterexample program is concrete and drawn from the sampled
evidence.

Left open: the restriction rule's home in the provenance inventory
(this section states it; adoption would move it), and the bit/priority
interaction as an input to open question 1. Deliberately *not*
proposed: a warning when stacked stops are not provably exclusive —
the stacked form is deterministic and lawful; whether ties were
*meant* is a question for the elaboration/completion story
(`time-travel-programs-design.md`), not for the checker.
