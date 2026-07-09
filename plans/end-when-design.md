# End-when: Data-Driven Termination

*Exploration round, 2026-07-09, written directly against the two
real-loop surveys and the tough-use-cases inventory. **Nothing here
is adopted.** The construct this document works out — end-when as a
binary flow operation — is a proposal with leanings, prepared for
the design conversation; per the sampling method's own rule,
evidence reweights but decisions stay in the conversations. What
this round contributes: the demand assembled in one place, the
constraints the existing record already imposes, one candidate
shape worked against those constraints, the choices that remain
with options laid out, and two dead ends recorded so they are not
re-proposed.*

## Why this document exists

End-when is the only top-ranked item in the candidate-block
inventory with no worked design. It was named in
`tough-use-cases-design.md` (inventory item 4, inside the
decision-driven family) as "data-driven terminator writing, the
synchronous sibling of interrupt, writing the terminator from
inside the walk" — a name and a demand, no shape. Then both
real-loop surveys promoted it: across sixty randomly sampled loops,
roughly eighteen terminate early or on a data condition — more than
every stateful class combined in survey 1, second place in survey 2
— making end-when "the biggest unserved everyday demand"
(`real-loop-survey.md`, combined picture). Meanwhile the divide
flow has `trees-and-recursion.md` and a worked entry in the tough
doc, the concurrency items have the server and pool use cases,
and the register designs have the longest document in the record.
The construct ordinary sequential code demands most has the least
design. This round closes that gap on paper.

The demand, gathered from the record:

- **Four everyday guises** (survey 1, finding 4): first-match /
  any (the found/not-found outcome is a case split *produced by
  termination*); take-until-a-sentinel (with an inclusive/exclusive
  wrinkle — python 5 keeps the terminator element, python 4 drops
  it); poll-until with a result payload (ruby 9 — the loop's value
  *is* the early exit's payload); and predicate cursors, where
  termination is the entire point of the loop.
- **The numerics sharpening** (survey 2, finding 2.7): in numeric
  code, data-driven termination arrives *fused to the scan* —
  loops stop because of their carried state (take-while on the
  term size, retry-until-tolerance). So end-when must compose
  with the register designs, whichever candidate wins.
- **The tough-use-cases demands**: until-loops (bottom-up
  mergesort's "repeat until one run remains", recorded as
  "expressible the day end-when exists"), protocol framing, and
  the decision-driven merge's stop verdict.
- **Two breadth-set members** name it in their owner line: the
  theta kernel (item 3: registers + end-when, with legibility as
  the test) and the retry-with-escalation (item 8: register +
  data-driven exit with payload + the readout composition).
- **Self-driven flows are unusable without it** (survey 1,
  finding 6): repetition without a source is ordinary, not exotic
  — and a self-driven flow with no data-driven terminator and no
  interrupt simply never ends.

## What the record already fixes

Before proposing anything, the existing design record constrains
the shape from five directions. Assembling these is most of the
work; the construct then nearly draws itself.

**Conditions are case splits, not predicates.** The language has
one vocabulary for "does this element satisfy P": a case split
producing a bundle of alt flows. Filtering is already defined that
way — join(list, case flow) keeps the firing elements of an alt
(`lazy-stream-join-design.md`, restated in `core-model.md`). And
higher-order predicates are rejected outright: a function waiting
to be called has no honest visual representation
(`configuration-scopes.md`). Whatever end-when is, its condition
must arrive as a flow, not as a lambda or a bare boolean.

**Terminators exist, and they carry payloads.** Every flow kind
has a termination event, and failability — a terminator carrying a
payload — is a uniform dimension, not a per-kind bolt-on
(`async-flow-design.md`, "Failure as terminator payload"). A
consumer that says nothing about the terminator propagates it; at
a whole-flow collect the terminator is *discharged* — in hand as a
settled tagged value, legitimately case-split. A whole-stream
collect over a flow that can end early has **two value outputs**:
the folded prefix, and the terminator.

**The terminator-writing combinator already has one member.**
Interrupt (`async-flow-design.md`, "Interruption:
unless-and-until") derives a stream that ends early when an
external async value fires, writing `Interrupted(e)` as the
derived stream's terminator. Combinator-side failability is
established; end-when was named as its sibling from the start.

**The stream runtime already contains the needed move.** The
whole stream-stage inventory reduces to three runtime moves —
emit-and-continue, become-the-rest, abandon-the-rest
(`lazy-stream-placement-design.md`, "The skip mechanism").
Ending an output stream at a data-determined element is the third
move, which commute already uses. If end-when compiles to an
existing move rather than a fourth, that is altitude evidence of
the same kind the skip section claimed.

**No time travel, and flows have many consumers.** Flow ordering
and extent are established at construction, never retroactively
(`core-model.md`); and one flow may be collected any number of
times, each collect an independent consumer of the same one
logical iteration. Any construct that changed a flow's extent
*after* other consumers were wired to it would act retroactively
on them. This constraint does the most shaping below.

## The shape: a binary flow operation

The proposal, stated the way join was stated after its correction:

**End-when is a binary flow operation with asymmetric operands
(subject, stop). Both are flows. `stop` must fire in the subject's
own context, at most once per subject firing — option-kind
relative to the subject, in the sense `partial-collect-design.md`
defines. The output is a new flow, the *shortened flow*.**

Its semantics is one law:

> **The law of the shortened flow.** The shortened flow fires with
> each firing of the subject, in step with it, up to but not
> including the first subject firing at which `stop` fires; at
> that firing it terminates, and the terminator's payload is
> `stop`'s value. If `stop` never fires, the shortened flow ends
> the way the subject ends, terminator passed through.

Consequences that are theorems of the law rather than extra
design:

- **Each firing of the shortened flow is a firing of the
  subject** (a prefix of them), so values from the subject's
  context are readable in the shortened flow's context directly —
  the same prefix-rule admission that lets an ancestor's value
  into any descendant context (`bundle-provenance-design.md`).
  No transport machinery.
- **The stop condition is ordinary wiring.** Typically `stop` is
  one alt of a case split on per-firing data — exactly the wiring
  filter uses, consumed by a different node. The two everyday
  per-element-condition consumers line up:

  | operation | operands | keeps |
  |---|---|---|
  | join (filter) | (subject, alt flow) | exactly the firings where the alt fires |
  | end-when | (subject, alt flow) | the firings before the alt first fires |

- **Which-condition-stopped-you is free.** Several stop
  conditions merge into one stop operand by a partial collect
  over their alts — the merged flow is option-kind relative to
  the parent (that document's kind theorem), so it is a valid
  `stop` operand, and the law's payload is the firing branch's
  value. Which condition ended the walk rides the terminator with
  no new machinery.
- **The empty and total cases are unremarkable.** Stop firing on
  the first subject firing gives a shortened flow with zero
  firings and an immediate terminator-with-payload; stop never
  firing gives the subject back, terminator propagated. If the
  subject is itself failable, end-when adds one more tag to the
  terminator inventory (`Nil | Fail(e) | Stopped(v)` or however
  the failability round ultimately spells it) — a tagged value at
  discharge either way, no new cases.

### Derivation, not retroaction

The tough doc's phrase was "writing the terminator from inside
the walk." Worked against no-time-travel and multi-close, the
phrase needs one refinement: the terminator is written on the
**derived** flow, never on the subject. End-when does not reach
into an existing flow and shorten it; it mints a shorter flow
beside it. Consumers wired to the subject see the full walk;
everything that should stop is collected from the shortened flow.
The choice of what stops is drawn, not implied — an author who
wants the loop's *other* outputs to stop too collects them all
from the shortened flow, and the drawing says so.

(Operationally nothing runs further than demanded anyway: if
every collect hangs off the shortened flow, no firing past the
cut is ever pulled. The subject "continuing" costs nothing unless
someone actually collects it.)

**Rejected: terminator-writing as retroaction on the subject.**
A version where end-when mutates the subject flow's extent — "this
flow now ends here" — would make one consumer's condition
retroactively change what every other collect of the same flow
sees, which is exactly the retroactivity no-time-travel exists to
forbid, applied to extent instead of nesting. It also breaks the
one-flow-many-collects model structurally (whose condition wins
when two closes want different cuts?). Not to be re-proposed; the
deriving form loses nothing, since collecting everything from the
shortened flow expresses the stop-everything reading explicitly.

**Rejected: a boolean-predicate operand.** A version taking
end-when(flow, boolean-value-per-firing) — or worse, a predicate
lambda — was considered and dropped before it was written down,
for reasons the record already owns: it introduces a second
condition vocabulary beside case splits (violating
one-obvious-reading — the same data test would be drawn one way
to filter and another way to stop); it loses the payload (the
boolean says *that* you stopped, not *what* stopped you, and
poll-until-result then needs a side channel); and in lambda form
it is the higher-order-function shape `configuration-scopes.md`
rejected. The alt-flow operand gets all three right and reuses
the filter wiring verbatim.

## The readout: first-match falls out of discharge

The survey observed that first-match's found/not-found outcome "is
a case split produced by the loop's termination" and guessed the
readout is "naturally option-shaped or alt-shaped." The failability
design already contains exactly this: at a whole-flow collect, the
terminator is discharged into an ordinary tagged value. So:

    subject:   uncollect the list
    condition: case split on the element → {match(payload), other}
    stop:      the match alt
    collect:   whole-flow collect over the shortened flow
               → (prefix, terminator)
    readout:   case split the terminator:
                 Stopped(payload) → found, with the match in hand
                 ran out          → not found

First-match is end-when plus a collect plus the discharge case
split — three pieces of existing vocabulary and the one new node.
No first-match construct, no option-returning combinator. The
prefix output is simply unused when the caller only wanted the
hit (any/exists discards it; the payload may be the element
itself, or unit, or something computed from the element — it is
whatever the match alt carries).

The other guises are the same drawing with different emphasis:

- **Poll-until-result** (ruby 9): the stop alt's payload is the
  parsed success value; the shortened flow's firings are the
  failed attempts (collect them for logging, or don't). The
  enclosing timeout in the wild sample is interrupt — the
  data-driven and event-driven siblings composing in one drawing,
  each writing its own terminator tag, distinguished at
  discharge.
- **Take-until-sentinel** (python 4/5): the collect's prefix *is*
  the value; the terminator says which sentinel ended it (or that
  input ran dry — the pump loops' EOF-vs-close_notify distinction
  is a discharge case split, not two loops).
- **Effect walks**: nothing changes. The read-until-sentinel
  pumps whose per-element work is a write land as an effect
  collect over the shortened flow; the effects happen for the
  prefix, and the terminator reports why the pumping stopped.

## Composing with the register designs

The numerics demand: loops that stop *because of* their carried
state. Both live register candidates expose the carried value by
wiring — the port form as the Delay's `prev` output port, the
latent form as the combined flow's `state` port
(`iteration-with-state-design.md`, "Where they agree"). That is
the whole composition story: a stop condition on carried state is
a case split wired from a state port, and its alt is an ordinary
`stop` operand. End-when is **candidate-neutral** — it reads
state the way everything else reads state, so this round adds no
weight to either side of the register decision.

Take-while on the term size (mpmath's shape, breadth item 3 in
miniature):

    U:      the scan — combined flow with state port
            (or Delay beside the flow; same wiring either way)
    term:   the per-firing term, computed from state/element
    cond:   case split on |term| → {converged, still-large}
    stop:   the converged alt
    E:      end-when(U's flow, stop)
    out:    reduce-collect the terms over E's shortened flow;
            final state readout likewise off E

Retry-until-tolerance / retry-with-escalation (breadth item 8) is
the same drawing over a self-driven flow: the register carries the
precision, the stop alt fires when the error is within tolerance
and carries the accepted result, the terminator payload *is* the
loop's value. And the predicate cursor — the survey's guise where
"termination is the loop" — is the degenerate register case: a
cursor register, a self-driven flow, and a stop condition on the
cursor's state; the thing conventional code writes as the `while`
condition is the stop alt, and the drawing consists of almost
nothing else, which is faithful to what the loop is.

One genuine subtlety surfaces here rather than being smoothed
over: the register's **final readout** (the write half's output,
`first-class-ports-design.md`) is anchored to a flow's completed
extent. When a shortened flow sits between the register's flow
and every collect, demand never crosses the cut, so operationally
the final value is the state at the cut — but the *semantic* rule
for which extent a write half's `final` reads, when subject-flow
and shortened-flow consumers coexist, needs stating rather than
inheriting from evaluation order. Recorded as open question 4.

## Self-driven flows become usable

Survey finding 6: repetition without a source is ordinary. The
record's answer to "loop until" has until now been a self-driven
flow with *nothing to end it* except interrupt — which covers
timeouts and shutdown, not "until the data says so." End-when is
the missing half, and the bottom-up mergesort passage predicted
the composition exactly: "a self-driven stream of lists plus
end-when plus a final readout — expressible the day end-when
exists, and still reading as three constructs coordinated to say
'until'." That reading concern is worth answering now that the
drawing is concrete: the three constructs are not three ways of
saying "until" — the self-driven flow says *repeat*, the register
says *what carries*, and end-when says *until* — one construct
per word of the sentence "repeat, carrying runs, until one run
remains." The vocabulary is at the programmer's abstraction level
precisely because those are three separately-variable choices
(repeat driven by a source instead; carry two things; stop on a
different condition) and each varies by swapping its own piece.

## The stopping element: one bit, both readings

The surveys hand us both boundary conventions in one random draw:
python 4 tests the line and *drops* the sentinel (`break` before
the write); python 5 *appends* the close_notify chunk and then
tests (inclusive take-until). Both are everyday; both must be one
gesture. Three options:

**Option A: exclusive primitive; inclusive by consuming the
payload.** The law above is exclusive; an inclusive consumer
reads the stopping element from the terminator payload and
appends it downstream. Rejected as the *only* form: it fails
expansion continuity for the collect — "collect a list" stops
reading as a list collect and becomes collect-then-append, a
species change for a one-bit variation — and effect walks have no
"append" to compensate with (python 5's write-the-chunk would
have to duplicate the effect node outside the walk).

**Option B: one configuration bit on the node — the cut sits
before or after the stop firing.** The shortened flow either
excludes or includes the firing at which `stop` fired; the
terminator payload is present either way. This is the leaning:
the variation is genuinely one bit, local to the node, both
settings are lawful under the same law with "up to but not
including" swapped for "up to and including," and precedent for
node-attached configuration is established (sort's comparator;
configuration scopes generally). The visual reading should be a
cut line drawn before vs after the element mark — but that is
layout, out of scope here; what matters at this level is that
the bit is binary and local, not a construct.

**Option C: inclusive primitive; exclusive derived.** The mirror
of A, with the mirror smell — and the wrong default besides:
first-match, poll-until, and the framing cases all want the
match out-of-band (in the terminator), not appended to the
prefix. Exclusive-with-payload is the shape most guises already
are.

## Sibling or same node: end-when and interrupt

With end-when drawn, the difference from interrupt is exactly one
property: **alignment of the stop operand.** End-when's `stop`
fires in the subject's own context, at most once per firing,
checked by provenance — so "did we stop at this firing" is a
synchronous, per-firing question needing no race. Interrupt's
stop operand is an async value from an *unaligned* context, so
each pull races the subject's next cell against it. Same output
shape (a derived flow, shorter, terminator with payload); same
downstream story (propagate or discharge); different check and
different compile.

That symmetry invites a unification conjecture: one
terminator-writing node whose stop operand may be aligned (this
document) or unaligned (interrupt), with the race machinery
switched on by the operand's kind. It is recorded here so it
isn't lost, and deliberately not taken: what would decide is
whether the checking and compilation genuinely share anything
beyond the output type (an aligned stop needs no race, no pull
boundary, no cooperative-interruption caveat — the entire
mechanical content of interrupt is absent), and whether one
drawing for both would mislead more than it teaches (an aligned
cut is *inside* the walk's causality; an unaligned one arrives
from outside it — arguably a difference the picture should
show). Until a concrete program needs them unified, they stay
siblings with deliberately rhyming shapes.

## The decision-driven family: scope bounded

The tough doc's open question 5 asked whether end-when is the
decision-driven merge's degenerate case (a chooser over one head
returning advance-or-stop) or separate. This round's position —
a leaning, not a settlement: **end-when stands alone.** The
80/20 counterweight cuts both directions here, and it separates
the two constructs cleanly:

- End-when is promoted by *frequency*: eighteen of sixty loops.
  It must be effortless — gesture count is the design pressure,
  and the shape above is one node consuming wiring the program
  usually has anyway.
- The decision-driven merge is a *breadth* obligation: mergesort's
  merge, framing, the tokenizer. It must be possible without too
  much pain; it need not be one gesture.

Deriving the everyday construct from the rare one — end-when as
a one-input merge with a stop verdict — would tax every
take-while with the merge's conceptual weight (choosers,
configuration scopes, per-head verdicts) to buy a unification no
sampled program asked for. The relationship that *should* be kept
is vocabulary: when the merge lands, its chooser's verdict
inventory (advance-this, advance-that, stop) should spell "stop"
as writing the same terminator end-when writes, so the family is
one family at the semantic level even if its members are separate
nodes. Recorded as open question 3.

Equally deliberately out of scope: **data-dependent take**
("advance how far" — line filling, the tokenizer, protocol
framing's read-N-more). It is the variable-rate-consumption
cluster, where the breadth risk concentrates (breadth items 1
and 2 have no owner), and it is *not* this construct: end-when
answers "how long," not "how much per step." Bounding this round
to the one everyday construct is the baby-steps discipline
applied on purpose; the take question stays with the
decision-driven family round.

## By kind, and the compile

Sketches only — this round is design; nothing here touches
`src/Compile.res`, and implementation would land after the
first-class-ports migration like the other new nodes.

- **List**: the cut compiles to `break`. The collect's loop
  carries a terminator local; the stop alt's arm assigns the
  payload and breaks; the inclusive bit moves the push above or
  below the check. Exactly the loop python 4/5 wrote by hand.
- **Stream**: the cut is per-collect output construction — at the
  stop firing, the fold abandons the rest and becomes the
  terminator, which is the third of the three existing runtime
  moves (commute's abandon-the-rest, aimed at a terminator value
  instead of a resolved `None`). No fourth move is needed, which
  by the skip section's own argument is evidence the construct
  sits at the right altitude. Laziness supplies the rest: nothing
  past the cut is pulled, so ending the output *is* stopping the
  work.
- **Self-driven**: the stop condition is the emitted loop's
  `while` condition (negated, plus the payload local) — the
  compile target is precisely the loop shape the survey's class 5
  samples wrote.
- **Async stream**: an aligned stop needs no race — the check
  rides the per-cell continuation; this is where the sibling
  split from interrupt is visible in the machinery. Beyond that,
  deferred with the unification question.
- **Incremental**: "changes until a condition, then hold forever"
  is meaningful and untouched here; noted for the incremental
  doc's own rounds.

One caveat for the concurrency round: "the *first* firing at
which stop fires" is well-defined on ordered flows (lists,
streams, self-driven), which is everything this round's evidence
covers. Under a concurrent collect, "first" is
schedule-determined, the way race's winner is — if end-when is
ever admitted off `serial`, that non-determinism must be meant,
same as race means it. Flagged, not designed.

## Against the principles

- **Example first, then generalise.** Termination is added to a
  concrete walk after the fact: build the walk, notice it should
  stop, wire the condition's alt into an end-when. Contrast the
  conventional combinator ladder, where early exit forces an
  upfront species choice (`takeWhile`? `find`? `foldWhile`? an
  exception?) before the body is written.
- **Inside-out / cases as values.** No lambda, no interior scope,
  no magic names anywhere in the construct; the condition is a
  visible case split, and the stopping outcome is a value (the
  discharged terminator) you flow through.
- **Foundations before features.** The construct is mostly
  assembled from settled pieces (case splits, option-kind flows,
  failability, discharge, the three runtime moves); the genuinely
  new content is one law and one bit. Two dead ends died on paper
  above.
- **Programmer's abstraction level.** "Stop when" is a word in
  the programmer's vocabulary, and it gets one node. The four
  survey guises are one reading each — first-match is not "a fold
  with an Either trick," it is end-when + discharge, readable as
  what it is.
- **No bottlenecks.** The stop payload rides the terminator
  through the collect; the prefix and the payload emerge as two
  outputs, never packed. (Conventional languages route this
  through an exception, a sentinel return, or an
  accumulator-and-flag tuple — the flag-variable idiom the
  surveys kept meeting is precisely the bottleneck form.)
- **Abstraction is the source of truth.** End-when's list
  lowering (the `break` loop) is a derived view; the authored
  program keeps the cut. Nothing new to say — the construct slots
  into the existing story.
- **Building blocks must build.** The +1 ladder, walked: a plain
  collect → *+ termination* (add the case split if not already
  present, add one end-when, re-aim the collect at the shortened
  flow — additions and one rewire, no rewrite) → *+ use the
  payload* (case-split the discharged terminator) → *+ the
  condition moves onto carried state* (wire the case split from a
  state port; the register is the addition, end-when unchanged) →
  *+ a second stop condition* (partial-collect the alts; end-when
  unchanged) → *+ an outer timeout* (interrupt around it;
  distinguished at discharge). Every rung is an addition to the
  drawing. The cliff this specifically removes is the one the
  principle was named for: in combinator vocabularies, a walk
  that acquires a stop condition abandons `.map()`/`.filter()`
  for a different species; here it acquires one node.

## What this changes elsewhere, if adopted

Nothing in the record is dissolved or corrected by this round; it
fills a named hole. If the design conversation adopts some form
of it: the tough doc's inventory item 4 gains its worked member
(and its "end-when outranks this slot" note gains a referent);
breadth-set items 3 and 8 get a concrete owner shape to be tested
against, and the theta kernel's legibility test (eight registers
+ take-while, drawn) becomes runnable on paper; the bottom-up
mergesort composition can be drawn end to end. `core-model.md`
would gain end-when a line alongside join in "Join, and filtering
as join" (it is the same operand pattern with a different verb)
— but not before adoption.

## Open questions

1. **The inclusive/exclusive bit's final form.** Option B is the
   leaning (one bit on the node, exclusive the default reading);
   what its drawing is, and whether the bit belongs on the node
   or on the stop wire, is open. Both survey shapes must stay one
   gesture.
2. **Unification with interrupt.** One terminator-writing node
   with aligned/unaligned stop operands, or two rhyming siblings.
   Deliberately unforced; what would decide is recorded in the
   sibling section.
3. **Verdict vocabulary with the decision-driven merge.** When
   the merge is designed, its chooser's stop verdict should write
   the same terminator; check then whether anything more than
   vocabulary is actually shared.
4. **The register final-readout anchor.** When a shortened flow
   sits between a register's flow and its consumers, which extent
   does the write half's `final` read — and what does it mean if
   subject-flow and shortened-flow collects coexist with one
   register? Needs a stated rule, not an inherited one; touches
   the iteration-state round.
5. **Stacked end-whens.** end-when(end-when(F, a), b) versus one
   end-when over the partial-collect merge of a and b: the law
   suggests they agree when both stops are alts of splits in F's
   context (first-of-either cut, payload from whichever fired) —
   verify, and if they agree, that is a recognition rule for
   level 1; if they can disagree, find the program that shows it.
6. **Textual form.** The three-arrow textual representation needs
   a spelling for the (subject, stop) operand pair and the
   discharge readout; belongs to that document's next round.
7. **Naming.** "End-when" vs take-while/until — already parked in
   the tough doc's question 8; deferred per tradition. One
   constraint from this round: the name should read as a *flow
   operation* (like join), not as a collect variant, since the
   readout composition depends on understanding that the collect
   is downstream of the cut.
