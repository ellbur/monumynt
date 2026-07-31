# End-when: data-driven termination

Status: **adopted** (design conversation, 2026-07-23) — the
construct is settled design; none of it is implemented. Adopted:
the core construct (the law of the shortened flow, the flow-typed
(subject, stop) operand pair) as a standalone everyday node — the
relationships to the decision-driven merge and interrupt stay
exactly the recorded leanings, and the split-when relationship was
settled at the root in the same conversation (the cut refinement,
in "Adoption notes" below: end-when is the cut's prefix
projection) — and the inclusive/exclusive bit as one bit on the
node, exclusive the default reading. The adopting
conversation's rationale and its standing notes (the continuation
seam; the bit's textual direction) are in "Adoption notes" below.
The open questions keep their own status: where one is marked open
it is still open.

You will often want a walk to stop early because of what it sees —
the first match, a sentinel, a value within tolerance. In
conventional code this is `break`, `find`, `takeWhile`, or an
exception. In this language it is one flow operation, **end-when**,
that shortens a flow and records why it stopped. This chapter
builds it from the simplest search you can write, then works
through the harder questions: whether you keep the element that
stopped you, where that choice lives, what happens when two stop
conditions collide, and where the construct's edges are.

(You'll want `core-model.md` first: opens, collects, case splits,
join, and the difference between value wires and flow wires. Each
further piece of vocabulary is introduced as it appears.)

## A first example: find the first match

Here is a search — walk a list, stop at the first element that
matches, and report either the match or that nothing matched:

```
-- spelling provisional (open question 6)
xs -> open list -> split find of Match, Other
  Match: -~> end-when          -- shortened flow: fires until the first Match, then terminates carrying it
-~> collect => prefix, term    -- whole-flow collect: folded prefix + discharged terminator
term -> split ended of Stopped, RanOut
  Stopped: found               -- the match is in hand
  RanOut:  notFound
-~> collect => result
```

Read it top to bottom.

- `open list` opens the list, so each element flows through in
  turn.
- `split find of Match, Other` is an ordinary case split on each
  element: does it match, or not? Nothing about this split is
  special to stopping — it is exactly the wiring you would draw to
  *filter* for matches.
- The `Match` alt feeds **end-when**, the one new node. End-when
  produces a new flow — call it the *shortened flow* — that fires
  element by element, in step with the walk, up to the first
  firing of `Match`. There it ends, and it ends *carrying the
  match*.

How does a flow end "carrying" something? Every flow has a
termination event — its **terminator** — and a terminator can
carry a payload (`async-flow-design.md`, "Failure as terminator
payload"). When a collect consumes a whole flow, the terminator is
**discharged**: it lands in hand as a settled tagged value that
you can case-split like any other value. So:

- `-~> collect => prefix, term` collects the shortened flow. A
  whole-flow collect over a flow that can end early has **two
  value outputs**: the folded prefix (`prefix` — what the walk
  produced before the stop) and the discharged terminator
  (`term`).
- The last split reads the terminator: `Stopped` means the walk
  ended early and the match is in hand; `RanOut` means the list
  ran out before anything matched.

Notice what did *not* appear: no `find` construct, no
option-returning combinator, no special search mode. First-match's
found/not-found outcome is a case split *produced by termination*,
and the failability design already supplies what's needed: at a
whole-flow collect the terminator is discharged into an ordinary
tagged value. First-match is end-when plus a collect plus a
discharge case split — three pieces of existing vocabulary and the
one new node.

Two small notes on the example. The `prefix` output is simply
unused when you only wanted the hit (any/exists discards it). And
the match payload may be the element itself, unit, or something
computed from the element — whatever the match alt carries.

## Why it has this shape

Before anything was proposed, the existing design record already
constrained end-when's shape from five directions. Once those
constraints are assembled, the construct nearly draws itself —
which is why the example above needed almost no new vocabulary.

**Conditions are case splits, not predicates.** The language has
one vocabulary for "does this element satisfy P": a case split
producing a bundle of alt flows. Filtering is already defined that
way — `join(list, case flow)` keeps the firing elements of an alt
(`core-model.md`, "Filtering is a join too"). Higher-order
predicates are rejected outright: a function waiting to be called
has no honest visual form (`configuration-scopes.md`). So
end-when's condition must arrive as a flow, never as a lambda or a
bare boolean.

**Terminators exist and carry payloads.** Every flow kind has a
termination event, and failability — a terminator carrying a
payload — is a uniform dimension, not a per-kind bolt-on
(`async-flow-design.md`, "Failure as terminator payload"). A
consumer that says nothing about the terminator propagates it. At
a whole-flow collect the terminator is *discharged*: it lands in
hand as a settled tagged value, which can then be case-split. A
whole-flow collect over a flow that can end early therefore has
**two value outputs** — the folded prefix, and the terminator.
(This is the machinery the first example leaned on.)

**The terminator-writing family already has one member.**
Interrupt (`async-flow-design.md`, "Interruption:
unless-and-until") derives a stream that ends early when an
external async value fires, writing `Interrupted(e)` as the
derived stream's terminator. End-when is its synchronous sibling.

**The stream runtime already contains the needed move.** The whole
stream-stage inventory reduces to three runtime moves —
emit-and-continue, become-the-rest, abandon-the-rest
(`lazy-stream-placement-design.md`, "The skip mechanism"). Ending
an output stream at a data-determined element is the third move,
which commute already uses. Compiling to an existing move rather
than a fourth is altitude evidence that the construct sits at the
right level.

**No time travel, and flows have many consumers.** Flow ordering
and extent are established at construction, never retroactively
(`core-model.md`); and one flow may be collected any number of
times, each collect an independent consumer of the same one
logical iteration. Any construct that changed a flow's extent
*after* other consumers were wired to it would act retroactively
on them. This constraint shapes the design most — you will see it
again in a moment.

## The construct, precisely

**End-when is a binary flow operation with asymmetric operands
(subject, stop).** Both are flows. `stop` must fire in the
subject's own context, at most once per subject firing — in the
record's vocabulary, *option-kind relative to* the subject, in the
sense `partial-collect-design.md` defines. The output is a new
flow, the *shortened flow*.

Everything the construct means is one law:

> **The law of the shortened flow.** The shortened flow fires with
> each firing of the subject, in step with it, up to but not
> including the first subject firing at which `stop` fires; at that
> firing it terminates, and the terminator's payload is `stop`'s
> value. If `stop` never fires, the shortened flow ends the way the
> subject ends, terminator passed through.

Everything below is a theorem of that law, not extra design:

- **Values from the subject's context are readable in the
  shortened flow directly.** Each firing of the shortened flow is
  a firing of the subject (a prefix of them), so the ordinary
  prefix-rule admission that lets an ancestor's value into any
  descendant context applies (`bundle-provenance-design.md`). No
  transport machinery.
- **The stop condition is ordinary wiring.** Typically `stop` is
  one alt of a case split on per-firing data — exactly the wiring
  filter uses, consumed by a different node. The two everyday
  per-element-condition consumers line up:

  | operation | operands | keeps |
  |---|---|---|
  | join (filter) | (subject, alt flow) | the firings where the alt fires |
  | end-when | (subject, alt flow) | the firings before the alt first fires |

- **Which condition stopped you is free.** Several stop conditions
  merge into one `stop` operand by a partial collect over their
  alts. The merged flow is option-kind relative to the parent
  (that document's kind theorem), so it is a valid `stop`, and the
  law's payload is the firing branch's value. Which condition
  ended the walk rides the terminator with no new machinery. This
  holds *for alts of one split* — the partial collect's branches
  must be disjoint cell sets of one bundle. Conditions from
  independent splits cannot merge; their story is in "Stacking two
  end-whens" below.
- **The empty and total cases are unremarkable.** Stop firing on
  the first subject firing gives a shortened flow with zero
  firings and an immediate terminator-with-payload; stop never
  firing gives the subject back. If the subject is itself
  failable, end-when adds one more tag to the terminator inventory
  (`Nil | Fail(e) | Stopped(v)`, however the failability round
  ultimately spells it) — a tagged value at discharge either way,
  no new cases.

## The walk itself is untouched

The survey demand named this construct "writing the terminator
from inside the walk." Worked against no-time-travel and
multi-close, that phrase needs one refinement: **the terminator is
written on the derived flow, never on the subject.** End-when does
not reach into an existing flow and shorten it; it mints a shorter
flow beside it. Consumers wired to the subject see the full walk;
everything that should stop is collected from the shortened flow.
The choice of what stops is drawn, not implied — if you want the
loop's *other* outputs to stop too, you collect them all from the
shortened flow, and the drawing says so.

Operationally nothing runs past the cut anyway: if every collect
hangs off the shortened flow, no firing beyond the cut is ever
pulled. The subject "continuing" costs nothing unless someone
actually collects it.

Now, you might wonder why the language doesn't just let end-when
shorten the flow it is given — declare "this flow now ends here,"
so every consumer stops together. It turns out this would cause
problems: it would make one consumer's condition retroactively
change what every other collect of the same flow sees, and that is
exactly the retroactivity no-time-travel forbids — applied to
extent instead of nesting. It also breaks the
one-flow-many-collects model structurally: whose condition wins
when two closes want different cuts? And the deriving form loses
nothing, since collecting everything from the shortened flow
expresses the stop-everything reading explicitly. (This is a
recorded rejection — please don't re-propose it without new
evidence.)

You might also wonder why the stop operand must be a flow — why
end-when couldn't take a boolean per firing, or a predicate
lambda, the way `takeWhile` does. It turns out a
`end-when(flow, boolean-per-firing)` — or worse, a predicate
lambda — fails three ways the record already owns. It introduces a
second condition vocabulary beside case splits (the same data test
drawn one way to filter and another way to stop, violating
one-obvious-reading); it loses the payload (the boolean says
*that* you stopped, not *what* stopped you, so poll-until-result
needs a side channel); and in lambda form it is the
higher-order-function shape `configuration-scopes.md` rejects. The
alt-flow operand gets all three right and reuses the filter wiring
verbatim. (This too is a recorded rejection — please don't
re-propose it without new evidence.)

## The same drawing, three more ways

The other everyday guises are the first-match drawing with
different emphasis:

- **Poll-until-result**: the stop alt's payload is the parsed
  success value; the shortened flow's firings are the failed
  attempts (collect them for logging, or don't). A surrounding
  timeout in the wild sample is interrupt — the data-driven and
  event-driven siblings composing in one drawing, each writing its
  own terminator tag, distinguished at discharge.
- **Take-until-sentinel**: the collect's prefix *is* the value;
  the terminator says which sentinel ended it (or that input ran
  dry — the EOF-vs-close_notify distinction is a discharge case
  split, not two loops).
- **Effect walks**: read-until-sentinel pumps whose per-element
  work is a write land as an effect collect over the shortened
  flow; the effects happen for the prefix, and the terminator
  reports why the pumping stopped.

## Stopping because of carried state

In numeric code, loops usually stop *because of* their carried
state — the term got small enough, the error fell within
tolerance. So end-when must compose with loop-carried state, which
in this language means the register designs. Both live register
candidates expose the carried value by wiring — the port form as
the Delay's `prev` output port, the latent form as the combined
flow's `state` port (`iteration-with-state-design.md`, "Where they
agree"). That is the whole composition story: a stop condition on
carried state is a case split wired from a state port, and its alt
is an ordinary `stop` operand. End-when is **candidate-neutral** —
it reads state the way everything else reads state — so it adds no
weight to either side of the register decision.

Here is take-while on the term size (a numeric convergence scan):

```
-- spelling provisional
xs -> open list => a, ~L
~L ~> delay init 0 => st          -- register on the flow; carries the scan state
st, a -> term -> abs -> split size of Converged, Large
  Converged: -~> end-when         -- stop before the first converged firing
-~> collect => terms, ended       -- reduce the terms over the shortened flow; final state off it too
```

Retry-until-tolerance / retry-with-escalation is the same drawing
over a self-driven flow: the register carries the precision, the
stop alt fires when the error is within tolerance and carries the
accepted result, and the terminator payload *is* the loop's value.
The **predicate cursor** — the guise where "termination is the
loop" — is the simplest possible register case: a cursor register,
a self-driven flow, and a stop condition on the cursor's state.
What conventional code writes as the `while` condition is the stop
alt, and the drawing consists of almost nothing else, faithful to
what the loop is.

One genuine subtlety: the register's **final readout** (the write
half's output, `first-class-ports-design.md`) is anchored to a
flow's completed extent. When a shortened flow sits between the
register's flow and every collect, demand never crosses the cut,
so operationally the final value is the state at the cut. But the
rule of *meaning* for which extent a write half's `final` reads,
when subject-flow and shortened-flow consumers coexist, needs
stating rather than inheriting from evaluation order (open
question 4, worked below — "The register final-readout anchor").

## Loops with no source: self-driven flows become usable

Repetition without a source is ordinary, not exotic. The record's
answer to "loop until" had until now been a self-driven flow with
*nothing to end it* except interrupt — which covers timeouts and
shutdown, not "until the data says so." End-when is the missing
half.

Bottom-up mergesort — "repeat until one run remains" — is a
self-driven stream of lists plus end-when plus a final readout.
You might worry that this reads as three ways of saying "until" —
but the concern answers itself once drawn: the three constructs
each say a different word. The self-driven flow says *repeat*, the
register says *what carries*, and end-when says *until* — one
construct per word of the sentence "repeat, carrying runs, until
one run remains." The vocabulary sits at the programmer's
abstraction level precisely because those are three
separately-variable choices, and each varies by swapping its own
piece.

## Do you keep the element that stopped you?

The surveys hand us both boundary conventions in one random draw:
one sampled loop tests the line and *drops* the sentinel (`break`
before the write); another *appends* the terminator chunk and then
tests (inclusive take-until). Both are everyday; both must be one
gesture. Three options were weighed.

Now, you might wonder why the language doesn't just make the cut
exclusive, full stop — anyone who wants the stopping element can
read it from the terminator payload and append it downstream
(option A: exclusive primitive, inclusive by consuming the
payload). It turns out that as the *only* form this causes
problems: it fails expansion continuity for the collect —
"collect a list" stops reading as a list collect and becomes
collect-then-append, a species change for a one-bit variation —
and effect walks have no "append" to compensate with (writing the
terminator chunk would have to duplicate the effect node outside
the walk). (Recorded rejection of exclusive-*only*; exclusive
survives as the default reading below.)

**Option B — one configuration bit on the node: the cut sits
before or after the stop firing.** The shortened flow either
excludes or includes the firing at which `stop` fired; the
terminator payload is present either way. **This is the leaning.**
The variation is genuinely one bit, local to the node; both
settings are lawful under the same law with "up to but not
including" swapped for "up to and including"; and precedent for
node-attached configuration is established (sort's comparator;
configuration scopes generally). Its visual reading is a cut line
drawn before vs after the element mark — layout, out of scope
here; what matters is that the bit is binary and local, not a
construct.

The mirror image — option C, an inclusive primitive with exclusive
derived — you might also wonder about. It turns out it has the
mirror of option A's smell, and the wrong default besides:
first-match, poll-until, and the framing cases all want the match
out-of-band (in the terminator), not appended to the prefix.
Exclusive-with-payload is the shape most guises already are.
(Recorded rejection.)

## Where the bit lives: node or wire (open question 1, worked)

Option B fixes that the inclusive/exclusive choice is one bit; it
leaves open *where* that bit lives — on the end-when node, or on
the stop operand ("the stop wire"). The two homes look like they
should differ in expressiveness, because a stop operand is often a
*merge* of several conditions, and a per-wire bit sounds like it
could give each merged condition its own boundary disposition.
Worked against how the stop operand is actually shaped, the homes
coincide everywhere a program can reach; the apparent extra reach
is available only by turning the bit into data — a move with its
own cost and no witnessed client.

**The stop operand is one wire, even when it is many conditions.**
"Which condition stopped you is free" is realised by a *partial
collect over the stop alts*, whose output is a single option-kind
flow (`partial-collect-design.md`'s kind theorem). The end-when
consumes one stop wire whether the stop is one alt or a k-way
merge. A bit "on the wire" is therefore one bit for the whole
cut — exactly what a bit "on the node" is. In the un-stacked,
possibly-merged case the two homes are notational variants of the
same single bit; there is nothing to decide between them.

**In the stacked form they are literally the same placement.**
Regime 2's genuine ties (see the stacking section below) live only
in the stacked form — independent splits admit no merged node (the
validity gate). A stack is end-when nodes each consuming exactly
one stop wire, so node-bit and wire-bit match up one-to-one, level
by level: the inner node's bit *is* the inner stop wire's bit. The
tie-break theorem — inner-exclusive, inner wins; inner-inclusive,
the tied firing survives into the outer's subject and the outer
wins — is stated identically under both homes. The regime-2 worry
that "the priority reading would need restating" under wire
placement dissolves: wire placement restates nothing, because per
level there is exactly one wire.

**The only true divergence demands the bit below the partial
collect — as data.** To give two *merged* conditions different
boundary dispositions in one end-when, the bit must ride each alt
*before* the partial collect fuses them — i.e. travel as part of
the merged flow's value. That is no longer a cut configuration but
a datum on the value channel: an option flow of (payload,
keep-bit) pairs. It reintroduces a small product into the very
channel end-when kept clean (the stop payload rides the
*terminator*, unpacked), and it has no witnessed client. Whether
the boundary element is kept is a property of *the collected
prefix as a list* — "does this list include its sentinel" — one
fact about one list, not a fact that varies by which sentinel
ended it. A list that keeps its terminator after reason a but
drops it after reason b is heterogeneous for no reason a sampled
program showed.

**Leaning: the bit is on the node.** It configures one cut — the
boundary of one shortened flow — which is one bit about one
prefix. Wire placement buys nothing over node placement wherever a
stack can tie (they coincide there), and buys per-alt bits only by
demoting the bit to data (a bottleneck, unwitnessed). This
resolves open question 1's node-vs-wire half toward the node; the
bit's *drawing* — a cut line before vs after the element mark —
remains layout, out of scope here.

Now, you might wonder why the language doesn't make per-alt
boundary bits the primitive anyway — a lane on each stop alt, so
one merged end-when can keep the boundary element for some reasons
and drop it for others. It turns out this was rejected as the
node's form: it packs a keep-bit product onto the stop value
channel, and no sampled program wants a prefix whose
sentinel-inclusion depends on which sentinel fired. The descent
stays *available* — if a concrete program ever wants per-reason
boundary disposition in a single cut, the bit graduates to a lane
on the merged stop flow, gracefully — but it is not where the
primitive lives. (Recorded rejection of the primitive form; the
graceful descent just described is the only sanctioned route
back.)

## End-when and interrupt: rhyming siblings

With end-when drawn, the difference from interrupt is exactly one
property: **alignment of the stop operand.** End-when's `stop`
fires in the subject's own context, at most once per firing,
checked by provenance (the language's record of which context each
value and flow comes from) — so "did we stop at this firing" is a
synchronous, per-firing question needing no race. Interrupt's stop
operand is an async value from an *unaligned* context, so each
pull races the subject's next cell against it. Same output shape
(a derived flow, shorter, terminator with payload); same
downstream story (propagate or discharge); different check and
different compile.

That symmetry invites a unification conjecture: one
terminator-writing node whose stop operand may be aligned (this
chapter) or unaligned (interrupt), with the race machinery
switched on by the operand's kind. **The leaning is to keep them
siblings, not unify.** What would decide is whether checking and
compilation genuinely share anything beyond the output type — and
they do not: an aligned stop needs no race, no pull boundary, no
cooperative-interruption caveat, so the entire mechanical content
of interrupt is absent. Interrupt's mechanical content inventories
as per-pull race construction, the memoised interrupt cell carried
across pulls, the pull boundary as yield point, the cooperative
caveat, and the per-pull tie-break (`race-barrier-design.md`
supplies these) — none of which an aligned stop has. The only
shared content is the output type and the downstream story, which
is what the conjecture's own test discounts. The remaining open
half is whether one drawing for both would mislead more than it
teaches: an aligned cut is *inside* the walk's causality, an
unaligned one arrives from outside it — arguably a difference the
picture should show. Until a concrete program needs them unified,
they stay siblings with deliberately rhyming shapes.

## What end-when is not: the decision-driven family

Is end-when the decision-driven merge's simplest special case (a
chooser over one head returning advance-or-stop), or separate?
**The leaning: end-when stands alone.** The 80/20 counterweight
separates them cleanly:

- End-when is promoted by *frequency*: eighteen of sixty loops. It
  must be effortless — gesture count is the design pressure, and
  the shape above is one node consuming wiring the program usually
  has anyway.
- The decision-driven merge is a *breadth* obligation: mergesort's
  merge, framing, the tokenizer. It must be possible without too
  much pain; it need not be one gesture.

Deriving the everyday construct from the rare one — end-when as a
one-input merge with a stop verdict — would tax every take-while
with the merge's conceptual weight (choosers, configuration
scopes, per-head verdicts) to buy a unification no sampled program
asked for. What *should* be kept is vocabulary: when the merge
lands, its chooser's verdict inventory (advance-this,
advance-that, stop) should spell "stop" as writing the same
terminator end-when writes, so the family is one family at the
level of meaning even if its members are separate nodes (open
question 3).

Equally out of scope: **data-dependent take** ("advance how far" —
line filling, the tokenizer, protocol framing's read-N-more). That
is the variable-rate-consumption cluster, where the breadth risk
concentrates, and it is *not* this construct: end-when answers
"how long," not "how much per step." That round exists —
`variable-rate-consumption-design.md` reframes "advance how far"
as boundary placement (split-when) and records the first-segment
relationship between the two constructs as a level-1 recognition,
not a unification, the same posture this round takes toward
interrupt.

## By kind, and the compile

Sketches only — this is design; nothing here touches
`src/Compile.res`, and implementation would land after the
first-class-ports migration like the other new nodes. ("Lowering"
below means the translation to a more concrete form — the code a
construct compiles down to.)

- **List**: the cut compiles to `break`. The collect's loop
  carries a terminator local; the stop alt's arm assigns the
  payload and breaks; the inclusive bit moves the push above or
  below the check. Exactly the loop the sampled code wrote by
  hand.
- **Stream**: the cut is per-collect output construction — at the
  stop firing, the fold abandons the rest and becomes the
  terminator, the third of the three existing runtime moves
  (commute's abandon-the-rest, aimed at a terminator value instead
  of a resolved `None`). No fourth move is needed. Laziness
  supplies the rest: nothing past the cut is pulled, so ending the
  output *is* stopping the work.
- **Self-driven**: the stop condition is the emitted loop's
  `while` condition (negated, plus the payload local) — precisely
  the loop shape the survey's self-driven samples wrote.
- **Async stream**: an aligned stop needs no race — the check
  rides the per-cell continuation; this is where the sibling split
  from interrupt is visible in the machinery. Beyond that,
  deferred with the unification question.
- **Incremental**: "changes until a condition, then hold forever"
  is meaningful and untouched here; noted for the incremental doc.

One caveat for the concurrency round: "the *first* firing at which
stop fires" is well-defined on ordered flows (lists, streams,
self-driven), which is everything this round's evidence covers.
Under a concurrent collect, "first" is schedule-determined, the
way race's winner is — if end-when is ever admitted off `serial`,
that non-determinism must be meant, same as race means it.
Flagged, not designed.

## Where this shows up in real code

The examples above were chosen from evidence, not invented. Across
sixty randomly sampled real loops, roughly eighteen terminate
early or on a data condition — more than every stateful class
combined in the first survey, second place in the second
(`real-loop-survey.md`). Early termination is the single biggest
everyday demand the language did not yet serve. Meanwhile the
divide flow, the concurrency items, and the register designs all
had worked designs; the construct ordinary sequential code demands
most had the least.

The demand, gathered from the record, has a stable shape:

- **Four everyday guises** (survey 1). *First-match / any*: the
  found/not-found outcome is a case split *produced by
  termination*. *Take-until-a-sentinel*, with an
  inclusive/exclusive wrinkle — one sampled loop keeps the
  terminator element, another drops it. *Poll-until with a result
  payload*: the loop's value *is* the early exit's payload.
  *Predicate cursors*, where termination is the entire point of
  the loop.
- **The numerics sharpening** (survey 2): in numeric code,
  data-driven termination arrives *fused to a scan* — loops stop
  because of their carried state (take-while on the term size,
  retry-until-tolerance). So end-when must compose with the
  register designs, whichever candidate wins.
- **Tough-use-case demands**: until-loops (bottom-up mergesort's
  "repeat until one run remains"), protocol framing, and the
  decision-driven merge's stop verdict
  (`tough-use-cases-design.md`, inventory item 4).
- **Self-driven flows are unusable without it** (survey 1): a
  self-driven flow — repetition with no source — that has no
  data-driven terminator and no interrupt simply never ends.

## Against the principles

The record checks every proposal against the seven principles
(`language-design-philosophy.md`). End-when's checks:

- **Example first, then generalise.** Termination is added to a
  concrete walk after the fact: build the walk, notice it should
  stop, wire the condition's alt into an end-when. Contrast the
  combinator ladder, where early exit forces an upfront species
  choice (`takeWhile`? `find`? `foldWhile`? an exception?) before
  the body is written.
- **Inside-out / cases as values.** No lambda, no interior scope,
  no magic names; the condition is a visible case split, and the
  stopping outcome is a value (the discharged terminator) you flow
  through.
- **Foundations before features.** The construct is mostly
  assembled from settled pieces (case splits, option-kind flows,
  failability, discharge, the three runtime moves); the genuinely
  new content is one law and one bit. Two dead ends died on paper.
- **Programmer's abstraction level.** "Stop when" is a word in the
  programmer's vocabulary, and it gets one node. First-match is
  not "a fold with an Either trick," it is end-when + discharge,
  readable as what it is.
- **No bottlenecks.** The stop payload rides the terminator
  through the collect; the prefix and the payload emerge as two
  outputs, never packed. Conventional languages route this through
  an exception, a sentinel return, or an accumulator-and-flag
  tuple — the flag-variable idiom the surveys kept meeting is
  precisely the bottleneck form.
- **Abstraction is the source of truth.** End-when's list lowering
  (the `break` loop) is a derived view; the authored program keeps
  the cut.
- **Building blocks must build.** The +1 ladder: a plain collect →
  *+ termination* (add the case split if absent, add one end-when,
  re-aim the collect at the shortened flow — additions and one
  rewire, no rewrite) → *+ use the payload* (case-split the
  discharged terminator) → *+ the condition moves onto carried
  state* (wire the case split from a state port; the register is
  the addition, end-when unchanged) → *+ a second stop condition*
  (partial-collect the alts; end-when unchanged) → *+ an outer
  timeout* (interrupt around it; distinguished at discharge).
  Every rung is an addition to the drawing. The cliff this removes
  is the one the principle was named for: in combinator
  vocabularies a walk that acquires a stop condition abandons
  `.map()`/`.filter()` for a different species; here it acquires
  one node.

## What this changes elsewhere

Nothing in the record is dissolved or corrected; this fills a
named hole. With adoption (2026-07-23) these integrations are
owed: the tough doc's inventory item 4 gains its worked member;
the breadth-set theta kernel and retry-with-escalation get a
concrete owner shape; the bottom-up mergesort composition can be
drawn end to end. `core-model.md` gains end-when a line alongside
join in "Filtering is a join too" (it is the same operand pattern
with a different verb).

## Adoption notes (2026-07-23)

The design conversation adopted the construct as it stands above.
Three notes from that conversation are part of the record:

- **Why standalone won over derivation from split-when.** Beyond
  the gesture-count argument, the deciding reason was incremental
  thinking: end-when lets the author think about the prefix alone
  — there is no second segment to conceive of and then discard.
  Deriving it from split-when would force the discarded remainder
  into the everyday case's mental model, backwards from how the
  sampled programs are conceived. (The first-segment recognition
  this note originally kept was superseded within the same
  conversation by the cut refinement, below — the derivation now
  runs from the root, in the direction this rationale wanted.)

- **The continuation seam.** Inhomogeneous iteration — the
  regex-shaped "loop until this, then loop until that"
  (`raku-grammars-comparison.md`) — needs a way to continue from
  where the cut left off. Nothing adopted here forecloses that:
  the subject beyond the cut is exactly split-when's second
  segment, and the first-segment recognition is the named seam.
  The adoption is of the law, with the stated expectation that
  edge behavior (precisely what "where end-when left off" hands
  to a continuation) may be tweaked when the segmentation and
  grammar vocabulary lands. A tweak there is a refinement of this
  construct, not a reopening of the adoption.

- **The bit is acceptable because it draws, and it must not spell
  as a flag.** The conversation's general aversion to flags was
  overridden by the bit's natural visual form: the delimiter
  drawn inside or outside the mark of the last element — the cut
  line before/after the element mark that open question 1 already
  anticipates (layout-side, out of scope here). Textually the
  direction is to avoid a literal flag: spell the two readings as
  two words, the way ranges do elsewhere (`to` inclusive vs
  `until` exclusive). Filed into open question 6, to be decided
  jointly with split-when's three-valued destination setting —
  one word family, decided once.

- **The cut refinement (same conversation).** Working the
  split-when question arrived at the root concept: end-when and
  split-when branch off one construct, the **cut** ("when" is the
  working word) — it yields (prefix, payload, continuation), and
  to split is to tap the continuation. This cashes the
  continuation seam above: the adoption of the law stands, re-read
  as the cut's *prefix projection*; skip-while is the continuation
  projection; split-when is the cut *iterated*, a derived form,
  not a separate primitive. The anti-unification leaning's reasons
  survive the override — the everyday form stays flat and one
  gesture; it is split-when that wears the derivation. One
  consequence for the bit: the adopted two-valued bit is the
  projection of the root's **three-valued** destination setting
  (prefix / head-of-continuation / dropped) when the continuation
  is unused — without a continuation, starts-next and dropped are
  indistinguishable, which is why binary sufficed here. The cut
  round's open edges (how iteration is drawn without raw
  corecursion; the continuation on RanOut; payload availability
  from the continuation side) are filed in
  `variable-rate-consumption-design.md`, open question 10 — and
  that round is now worked (that doc's Part III, exploration,
  unadopted).

## Open questions

The language hasn't decided these yet. Where a leaning exists it
is stated; nothing here is settled.

1. **The inclusive/exclusive bit's final form.** Decided at
   adoption: one bit, on the node, exclusive the default reading
   (the node-vs-wire half was worked above — the two homes
   coincide wherever a stack can tie and diverge only by demoting
   the bit to data). What remains open is the bit's *drawing* (a
   cut line before vs after the element mark — layout, out of
   scope here; the adopting conversation's inside/outside-the-
   delimiter reading agrees) and confirmation that both survey
   shapes stay one gesture.
2. **Unification with interrupt.** One terminator-writing node
   with aligned/unaligned stop operands, or two rhyming siblings.
   Deliberately unforced; the deciding argument is in the sibling
   section.
3. **Verdict vocabulary with the decision-driven merge.** When the
   merge is designed, its chooser's stop verdict should write the
   same terminator; check then whether anything more than
   vocabulary is shared. *The merge's round now exists and answers
   more strongly than the question hoped*
   (`chooser-family-design.md`, exploration): the merge has no stop
   verdict and no verdict vocabulary at all — stopping a merge
   **is** this chapter's node, drawn on the merge's step flow, with
   the walk-untouched laziness argument applying verbatim. A stop
   lane on the merge node itself is that round's recorded dead end
   4. Nothing is left to align; what the family shares is
   structural (one option-kind operand discipline, one terminator —
   this one).
4. **The register final-readout anchor.** When a shortened flow
   sits between a register's flow and its consumers, which extent
   does the write half's `final` read — and what does it mean if
   subject-flow and shortened-flow collects coexist with one
   register? Worked below ("The register final-readout anchor"):
   the candidate rule is that `final` is a read at a *moment* —
   the completion of a drawn anchor flow, admissible exactly when
   its extent is a prefix of the register's update order — with
   the write half's bare binder as the unanchored default. Not
   adopted; the spelling and the inference question ride the
   `hold` decisions in `delay-ontology-design.md`.
5. **Stacked end-whens.** `end-when(end-when(F, a), b)` versus one
   end-when over the partial-collect merge of a and b. Worked
   below.
6. **Textual form.** The three-arrow textual representation needs
   a spelling for the (subject, stop) operand pair and the
   discharge readout (the samples above are provisional); belongs
   to that document's next round. Two divergences to resolve
   there: this doc writes end-when in lane position with an
   implicit subject (`Match: -~> end-when`) where
   `source-openers-design.md` writes it explicit-binary
   (`~R, ~c.Done ~> end-when => ~W`); and this doc folds the
   discharge into the collect (a second value output) where
   source-openers spells it as a separate flow operation
   (`~W ~> discharge => term`). One spelling family, decided once.
   One constraint from the adopting conversation: the
   inclusive/exclusive bit must not spell as a flag — prefer a
   word pair (`to` vs `until`, the range precedent), decided
   jointly with split-when's three-valued destination setting.
7. **Naming.** "End-when" vs take-while/until — parked in the
   tough doc's question 8. One constraint from this round: the
   name should read as a *flow operation* (like join), not as a
   collect variant, since the readout composition depends on
   understanding that the collect is downstream of the cut.

## Stacking two end-whens and the merged stop (open question 5, worked)

Suppose a walk has two reasons to stop. You can stack two
end-whens — `end-when(end-when(F, a), b)` — or, sometimes, merge
the two conditions into one stop operand ("the partial-collect
merge of a and b") and use one end-when. Are these the same
program? The answer is both agreement and disagreement, in
different regimes, with the boundary drawn by a demand the partial
collect already makes.

### The validity gate the question hides

The partial collect's branches must carry pairwise-disjoint cell
sets **of one bundle** — disjointness is a node demand, and so is
single-bundledness; the merged flow gets its kind theorem
(option-kind relative to the parent) from the bundle being a
partition (`partial-collect-design.md`, "Disjointness is a node
demand"). Two stop conditions that are alts of one case split
satisfy this. Two stop conditions from *independent* splits on the
same firing's data — converged, from a split on the term;
exhausted, from a split on the attempt count — are cells of two
different bundles, and **no partial collect merges them**: both
could fire at one firing, the merged flow would fire twice, and
"the firing branch" would not refer.

So the comparison splits in two: where the merged form exists (one
bundle) and where it does not (independent splits). The "which
condition stopped you is free" consequence holds as stated in the
first regime only.

### A restriction rule the stacked form needs first

`end-when(E1, b)` with `E1 = end-when(F, a)` is only well-formed
if `b` is an admissible stop operand for a subject it was not
built against. `b` fires in *F's* context, option-kind relative to
F; the law demands a stop that fires in the *subject's* context,
and the subject is now E1. The rule, stated rather than inherited:

> **A flow that is option-kind relative to F is an admissible stop
> operand for any end-when whose subject's firings are a subset of
> F's firings (here: a prefix), and the law consults it only at
> subject firings.**

Every E1 firing is an F firing, so b fires at most once per E1
firing; b's firings beyond E1's extent are never consulted (under
demand, never even pulled). This is the flow-wire sibling of the
prefix-rule admission for values (`bundle-provenance-design.md`):
an ancestor context's value is readable in a descendant context;
an ancestor-aligned stop is consultable on a derived prefix flow.
If any form of this round is adopted, the rule needs a home in the
provenance inventory — it is a new admission, not a consequence of
the existing ones.

### Regime 1 — one bundle: they agree, and it is a recognition rule

Let a and b be disjoint cell sets of one bundle in F's context,
both end-whens exclusive, and let i_a, i_b be the indices of the
first subject firing at which each fires (∞ if never). The
partition gives the load-bearing fact: **a and b never fire at the
same firing**, so i_a ≠ i_b whenever both are finite. Work the
three cases:

- **i_b < i_a.** Merged: cut at i_b, payload b's value. Stacked:
  E1's cut lies beyond i_b, so i_b is a firing of E1; the outer
  cuts there with payload b. Equal.
- **i_a < i_b.** Merged: cut at i_a, payload a's value. Stacked:
  E1 cuts at i_a with terminator `Stopped(a)`; b's first firing is
  beyond E1's last firing, so the outer's stop never fires and
  passes E1's terminator through unchanged. Equal, including the
  tag: a passed-through `Stopped` is the same terminator, not a
  wrapped one.
- **Neither fires.** Both forms end the way F ends. Equal.

The inclusive setting commutes with all three cases (replace "up
to but not including" throughout; the partition still forbids
ties), provided all three nodes carry the same bit. Swapping a and
b is symmetric, so stacking order is immaterial here; and the
partial collect's associativity flattens any number of same-bundle
stops into one k-branch merge.

So: **for stops drawn from one bundle, every stacking order and
the single merged end-when mean the same program.** That is the
recognition rule the question hoped for, in
`transformation-levels-design.md` vocabulary: a level-1
recognition whose canonical form is the merged one — one end-when,
one partial collect over the stop alts — with the stackings as
presentations, parallel to the partial collect's own bracketing
result.

### Regime 2 — independent splits: the program that shows disagreement

The counterexample is the survey's own retry-until-tolerance with
a budget: a self-driven flow of attempts; a register carrying the
doubling parameter; two stop conditions on each firing's data —
`converged` (an alt of a split on the error, payload the computed
result) and `exhausted` (an alt of a split on the attempt count,
payload a diagnostic). Independent splits, and genuinely
simultaneous when convergence is achieved exactly at the last
budgeted attempt.

No merged form exists (the gate above). The two stackings, both
exclusive, at a firing i* where both alts fire:

- `end-when(end-when(F, converged), exhausted)`: the inner cuts at
  i*, excluding it; i* is not a firing of the inner's output, so
  the outer never consults `exhausted` there. Terminator
  `Stopped(result)` — the run **succeeded**.
- `end-when(end-when(F, exhausted), converged)`: symmetric.
  Terminator `Stopped(diagnostic)` — the run **failed**, at the
  same firing of the same walk.

Downstream, the discharge case split routes these to different
legs. The two stackings are observably different programs; there
is no canonical form to recognize them into, and there should not
be — the difference is meaningful, and some program wants each.

**The tie-break theorem.** With an exclusive inner, the inner stop
wins ties: the tied firing is cut out of the outer's subject
before the outer looks. With an *inclusive* inner, the tied firing
survives into the outer's subject, so the **outer** stop wins.
Both are theorems of the law — deterministic, no ambiguity. But
the flip is a genuine surprise: the inclusive bit, introduced as a
local one-bit variation on the cut position, also selects stacking
priority when stops can tie. That interaction is an input open
question 1 weighs; it is now worked under "Where the bit lives".
In a stack each level has exactly one stop wire, so wire and node
placement coincide there and the priority reading is unchanged
either way — the interaction is a property of the node bit alone,
and moving the bit onto the wire does not multiply it.

### The authoring reading

Conventional code resolves this same tie silently, by statement
order inside the loop body — `if err < tol: return r` a line above
`if n >= maxiter: raise` is a priority decision nobody drew. Here
the choice is visible structure, and there are exactly two ways to
spell it:

- **Stack**, and the order (with the bits) is the priority —
  drawn, not implied.
- **Split once**, on a discriminator over both facts, producing
  one bundle `{converged, exhausted, continue}` — writing the
  discriminator forces the tie decision into the split itself, and
  the merged form (regime 1) is then available again.

Either way the program says which condition wins; the language
merely refuses to let the tie be an accident. This is the
inside-out principle showing up unplanned: termination priority is
not an artifact of interior statement order, because there is no
interior.

### What this settles, what it leaves

Settled on paper: the recognition rule exists with its scope
exactly the merged form's validity (one bundle, matching bits);
outside that scope stacking order is content, with a stated
tie-break; the counterexample program is concrete and drawn from
the sampled evidence.

Left open: the restriction rule's home in the provenance inventory
(this section states it; adoption would move it). The bit/priority
interaction, once flagged here as an input to open question 1, is
now worked under "Where the bit lives" — it belongs to the node
bit and survives wire placement unchanged. Deliberately *not*
proposed: a warning when stacked stops are not provably
exclusive — the stacked form is deterministic and lawful; whether
ties were *meant* is a question for the elaboration/completion
story (`time-travel-programs-design.md`), not for the checker.

## The register final-readout anchor (open question 4, worked)

Status: worked with a stated candidate rule, **not adopted** — the
case for a rule, prepared for the iteration-state round's
ergonomics conversation. It consumes the straddle account of
`delay-ontology-design.md` ("A stateful value straddles two
flows") and leaves its own spellings to the rounds that own them.

### The question, concretely

Return to the convergence scan from "Stopping because of carried
state": the register steps on the subject flow, the stop condition
splits on the carried state, and every collect hangs off the
shortened flow. What does the write half's binder — the final
readout — *mean*? The record says `final` is "the register's value
after the flow completes" (`iteration-with-state-design.md`, "The
exit anchor comes for free"), and the register's flow is the
*subject* — the full walk. But demand never crosses the cut, so
evaluation yields the state at the cut. If the meaning is "after
the subject completes," lazy evaluation is quietly computing a
different value than the one meant; if the meaning is "whatever
the demand reached," meaning inherits from evaluation order. Both
readings are wrong, and the second is the one this round exists to
rule out.

### `final` is a read at a moment

The reframe comes from the straddle account: a register is an
**update cadence** (one flow, fixed by provenance — read off the
step wire, never chosen) plus **reads**, which are the consumer's
(`delay-ontology-design.md`). The record already holds a family of
register reads: `prev` (per-firing, on the update flow), `hold`
(per-firing, on any flow the update flow is nested within), the
running view (per-firing, the collect's derived register —
`variable-rate-consumption-design.md`, Part II). Each is "the
state as of a moment," with statefulness supplying totality. The
final readout is not a different species: it is the **read at
completion** — the state as of the moment a flow's extent is
done.

The write half's port made this hard to see. `final` drawn as one
port of one node reads as intrinsic to the register — one
register, one exit value. The shortened flow is the smallest case
that separates the register from its readout: one state history,
and *several moments* a program might legitimately read it at —
the cut, the subject's end. So the rule of meaning is a rule
about which moment a given read names:

> **The anchor rule (candidate).** A final readout reads the
> register's state as of the completion of a drawn **anchor
> flow**. The read is well-formed iff the anchor's completed
> extent identifies a downward-closed set — a prefix — of the
> update flow's firing order; its value is the state after
> exactly the steps at those firings, the seed when that prefix
> is empty. The write half's bare binder is the unanchored
> default: it anchors to the register's own update flow.

Which flows are admissible anchors is a theorem list, not new
design:

- **The update flow itself** — the unanchored default; the plain
  fold's total.
- **Any cut-derived prefix of it**: end-when's shortened flow
  (the stacking section's restriction rule already establishes
  its firings are a prefix of the subject's), interrupt's derived
  stream, a bounded prefix take. This is the family the question
  is about.
- **Any flow the update flow is nested within** — the outer
  completion completes the inner. This is `hold`'s terminal read:
  the forward-fill register stepping on the Some-subsequence has
  its final read at the list's completion.
- **Not a join/filter of the update flow.** A filtered
  subsequence is a subset but not a prefix, and "the state after
  a non-contiguous subset of the steps" is no state the register
  ever held. **Cuts anchor finals; filters do not.** A program
  that wants the fold over a filtered subsequence moves the
  *update cadence* onto the filtered flow — the straddle
  account's division of labour, applied rather than amended.

### What the rule gives back

**The convergence loop reads right.** Anchored at the shortened
flow, exclusive bit: the shortened extent is the firings strictly
before the first Converged firing, so the readout is the state
after exactly those steps — which is precisely the state the stop
condition was looking at when it fired. The value you stopped on
is the value you read. The inclusive bit moves the read one step
later (the stopping firing's step is included) — the same one-bit
displacement the compile sketch already has as "the push above or
below the check." The bit composes with the anchor with no
additional rule.

**Coexistence is answered, not arbitrated.** Subject-flow and
shortened-flow collects sharing one register are several reads of
one state history, each naming its own moment. A subject-anchored
final and a cut-anchored final coexist the way two `hold` reads
on different outer flows coexist; demand for each pulls the walk
to its moment and no further. The operational behaviour the
question started from — "the final value is the state at the
cut" — becomes the *correct* value of the cut-anchored read,
rather than an accident of laziness; the subject-anchored read
still means the full walk, and demanding it walks the rest.
Meaning stated; evaluation order back to being an implementation.

**The self-driven residue dissolves into mis-anchoring.**
"`final` on an unshortened self-driven flow is never available"
(`iteration-with-state-design.md`, "What stays open on the pair";
`source-openers-design.md` inherits it) re-reads under the rule:
the unanchored default names an unending flow, so the read's
moment never arrives — not a hazard needing a construct, a read
anchored where no completion exists. The program that stops via
end-when anchors its final at the shortened flow and has an
ordinary value. What remains for the checking round is only the
advisory question it already owns ("no terminator writer
reachable from this collect").

**The readout is terminator-independent.** The shortened flow
completes on `Stopped` and on `RanOut` alike, so a cut-anchored
final is available on both discharge legs — which the readout
composition wants: the RanOut leg of a search typically reads the
fold's total, the Stopped leg reads the payload, and either may
read the register's final.

### A register on the shortened flow itself

The delay-ontology question "which flow is this register over"
has a tempting answer here: put the register *on* the shortened
flow, so its extent is the prefix by construction. When the stop
condition reads the state, that drawing closes a cycle — end-when
→ shortened flow → read half → `prev` → split → stop → end-when —
and working the fixpoint splits it by the bit:

- **Exclusive: ill-founded.** Suppose the stop first fires at
  firing k. Its data is per-firing data *of the shortened flow*,
  so computing stop-at-k requires the shortened flow to fire at
  k — but the exclusive law puts k outside the shortened extent.
  Then stop-at-k was never computed, so nothing stopped the flow,
  so it fires at k after all. No consistent extent exists.
- **Inclusive: well-founded.** Whether the shortened flow fires
  at i consults stops strictly before i only; induction on the
  firing order grounds it. The one-firing lag that makes the
  cycle productive lives in the *end-when node* under its
  inclusive reading — not in any register crossing.

The productivity check as stated ("every cycle crosses a
register's pairing edge") rejects both drawings — rightly for the
exclusive one, conservatively for the inclusive one. No extension
is needed, because the inclusive drawing is a presentation of a
cycle-free canonical form: **a register on a cut of F is the
register on F with its reads anchored at the cut.** The shortened
flow's firings are subject firings carrying the same per-firing
data, so the two registers agree at every reading either can
express — a level-1 recognition, with the on-the-cut drawing as
presentation. Leaning: the canonical form is register-on-subject
plus anchored reads, and the checker keeps its one rule.

### Where the anchor is drawn

The unanchored default reads the register's own flow; the
everyday program wants the cut. Two surfaces are possible: the
author spells the anchor (`final of st over ~W`, provisional —
the same `over` the hold spelling uses, one word family decided
once at the textual round), or the completion machinery infers it
when every consumer of the walk closes the same cut, shown faint
like any completion. This is the same implicit-vs-explicit
instance the straddle account already filed for hold's read-range
crossing (`delay-ontology-design.md`, "Where this leaves the open
fork") — one decision, now with two clients; the rule of meaning
is the anchor's presence either way. One diagram-level note for
the pair's open "shape" bullet: under this rule the write half
completes the register (it holds the step), while final readouts
are reads that name their anchor — the bare binder on the write
statement stays as sugar for the unanchored one.

### What this leaves

Adoption (the iteration-state round's conversation); the
spelling, jointly with `hold ... over` (textual round); the
explicit-vs-inferred anchor bit (completion round, with hold's);
the product corner — over a grid, "a prefix of the update order"
needs the linearization round's orientation before it means
anything, so anchor-over-a-product rides that residue
(`product-linearization-design.md`). If adopted:
`iteration-with-state-design.md`'s "final on self-driven streams"
bullet closes, and `first-class-ports-design.md`'s Delay-row note
gains the anchored reading.
