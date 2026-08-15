# The polarity of moving case flows out of a loop

Status: **open problem, elevated to Tier 1** (design conversation,
2026-08-15) — a worked conversation record, nothing adopted. The
conversation produced three results that are firm on paper (series
commutes mean priority termination only; time-ordered disjunction
termination requires a single coordinating node; two junction
commutes are two loops) and one discovery that reopens vocabulary
the record already uses: **break-on-case is not a commute** — the
established sequence commute and the record's break-on-case escape
idiom are *opposite polarities* of moving an option-kind flow out
of a loop, and only one of them actually commutes anything. The
open problem proper is the ontology underneath: whether a case flow
consumed as an exit is a flow at all, or something dual — a
**co-flow**. `open-problems.md` carries the ranked row; this
document owns the content.

A **second conversation** (same day, 2026-08-15) is appended from
"The wire-order geometry" on: a visual convention that makes flow
context positional, under which the polarity distinction becomes
*derivable from wire order* — the sequence commute is an adjacent
transposition the convention draws soundly, the escape is a gesture
it refuses to draw as a crossing, and the co-flow question sharpens
into a payload-*side* question. Two candidate paths are worked:
complement flows (rejected on arity) and payload-left (whose
per-use "both ports" form is the sharpened current lean). Still
exploratory; still nothing adopted.

The conversation this records ran from a narrower starting question
(multiple alternative early terminations from one case split) and
the narrow results are recorded first, because the general
discovery falls out of them.

## The setting

A list flow is open; inside it, each element case-splits into alts
A, B, and C. C continues the loop (its values feed the walk's
work); A and B are meant as early terminations — the walk should be
able to end at an A or a B, delivering that alt's payload at the
walk level. The record already uses case splits this way; what this
round examined is what happens when there are *two* of them.

The first question looks like an ambiguity: with A and B both moved
out as terminations, is this

1. one loop that terminates on the first A **or** B, or
2. two loops, one terminating on the first A and one on the first B?

## Two drawings, not one

The answer starts with a fact about drawings: "move two case flows
out" is not one program. With explicit commutes there are two
distinct wirings:

```
-- in series along L
~L,  ~A ~> commute => ~A2, ~L2
~L2, ~B ~> commute => ~B2, ~L3
```

```
-- junction: L split as for multi-close
~L, ~A ~> commute => ~A2, ~L2
~L, ~B ~> commute => ~B2, ~L3
```

Drawn, the first is two commutes in series along L; the second
splits L with a junction, exactly as multi-close does. And the
junction form settles reading (2) structurally rather than by
convention: `~L2` and `~L3` are *different* shortened lists (the
prefix to the first A vs the prefix to the first B), so no single
collect can serve both — two independent termination criteria force
separate closes, and the two-loop reading is read off the closes.

(A note on the second commute's operand in the series form: `~B` is
built against `~L`'s elements but consulted on the derived subject
`~L2`. This is the same admission `end-when-design.md`'s stacking
section had to state — an ancestor-aligned, option-kind operand is
consultable on a derived flow whose firings are a subset of the
ancestor's. The series chain is a second client for that rule.)

## What the series form means: the monadic worked example

It is tempting to read the series form as reading (1) — one loop,
first-A-or-B. Working the analogous construction in monad-land
shows it is not. Monads (as the *mon-* implies) focus a single
channel at a time, so there is nothing like alternative case flows
— but two distinct option-like monads can be sequenced out of a
list in series:

```haskell
xs :: [Either A (Either B c)]

step1 = sequence xs            -- Either A [Either B c]
step2 = fmap sequence step1    -- Either A (Either B [c])
```

| input | result |
|---|---|
| some A anywhere | `Left (first A)` — regardless of any B, earlier or later |
| no A, some B | `Right (Left (first B))` |
| all C | `Right (Right [cs])` |

On `[C, C, B@2, C, C, A@5, …]` the result is `Left A@5`: **A wins
even though B came first in time**. The series form is **priority
order, not time order**, and four things follow:

- **Alternativeness by nesting.** The two abort outcomes are
  alternatives, but only because the B outcome exists *nested
  inside* the A-side's completed alternative — `Right (Left b)` can
  only exist once no-A has been established.
- **No early exit on the second condition.** Ruling out A is a
  whole-walk obligation; B can be *reported*, never *terminate*. (A
  single-pass fusion exists — abort at the first A, carry
  "first B seen so far", discharge at the end — but note it needs a
  pending register. The priority program compiled to one loop is
  inherently stateful in a way the time-ordered one is not.)
- **Series order is content.** A-first and B-first are different
  programs (priority A vs priority B).
- **Monads cannot spell the unpacked disjunction.** To break on the
  first A-or-B in monad-land you must pack both aborts into one
  channel in the element type (`Either (A + B) c`) and unpack
  downstream. The packing is structural, not stylistic: one channel
  at a time is what *monadic* means. The unpacked time-ordered
  disjunction — one loop, each payload on its own unbroken wire —
  is exactly the program per-alt flow wires are positioned to
  express and monads cannot.

## The time-travel argument, and how the principle is used

The language distinguishes **time-travel programs** from
**no-time-travel programs** (`time-travel-programs-design.md`). A
time-travel program is converted by inference to a no-time-travel
program. The two live under different laws:

- In a **no-time-travel program**, a downstream consumer may not
  change the behavior of an upstream producer. *Any* downstream
  consumer — the next immediate one included, not just a remote
  one.
- In a **time-travel program**, the inference producing the
  no-time-travel form may run arbitrarily deep. A distant consumer,
  or a combination of scattered and seemingly unrelated distant
  consumers, may legitimately alter what is inferred.

In design, the user is usually going to write time-travel programs,
so those should be ergonomic — but a no-time-travel program must
always be derivable, so that has to be possible.

Applied here: could the series drawing mean time-ordered
disjunction? In the series form **every node describing how the
program works is already present — there is nothing left to fill
in**. The interaction of every wire is specified. And the
time-ordered reading would require `~A2` (whose upstream cone is
`~L` and `~A` alone) to fire on fewer walks once the second commute
exists downstream — a wire's behavior altered by its downstream,
which is exactly what the no-time-travel law forbids. A fully
elaborated program that still requires time travel to mean
something cannot mean it. So:

> **Series commutes represent priority termination only.**
> Time-ordered disjunction is not expressible by any composition of
> commutes, in any order.

(Two corrections from within the conversation, recorded so they are
not re-derived: an earlier step proposed *merging the two alts
before the commute* as the only route to a single short circuit —
wrong as an "only", and a bottleneck besides: the partial-collect
merge packs a sum to pass a structural point and breaks the
unbroken per-case wire from source to handler. It survives as *a*
valid program, not the door. A second earlier step proposed a
locality restriction on the *inference* — coordination only
readable off a single consuming node — which confuses the two
levels: locality is the no-time-travel program's law; inference is
lawfully deep and scattered.)

## The no-time-travel inventory

Three lawful ways to move two case flows out of a list:

1. **Series commutes** — priority termination. Assumed for now to
   be collected in order (the closes respect the nesting: the B
   outcome consumed within the A-side's completed alternative);
   collecting them separately as independent closes would need
   something additional to pull them apart, deliberately not worked
   — priority termination is rare enough that it is not being
   optimized for.
2. **The barrier commute** (working name) — time-ordered
   disjunction. A single node that commutes both flow wires through
   *together*, preserving their separate identities, preserving
   that they are alternatives, and keeping it one commute — one
   loop, one shortened prefix, cut at the first A-or-B. (The
   "barrier" is the record's existing answer for wires that must
   coordinate while keeping separate identity — the race barrier is
   the async precedent. Note this one is *aligned*: A and B are
   cells of one bundle per element, so they can never tie at a
   firing, and the construct is deterministic where the async race
   is scheduler-decided. See "Not a commute" below for why the
   working name is probably wrong.)
3. **Junction commutes** — two loops with different terminations,
   independent outcomes (both can fire).

## Inferring the variant from use

In the time-travel program the user does not draw commutes; they
use or collect the case flows in ways that show the flows need
commuting out, and inference picks the no-time-travel variant. The
organizing principle the conversation reached:

> **What a time-travel program declares through its consumption
> shapes is the alternativeness structure of the walk-level outcome
> facts; inference inserts the variant that mints exactly that
> structure.**

- **Outcomes consumed as independent facts → junction.** Separate
  handlers to separate outputs; or the two payloads combined as
  both-needed values, which under two independent option layers is
  the sibling-opens combine Complete already answers with a Cross
  (the both-fired cell). Independence is the default: the weakest
  structure that validates the uses.
- **Outcomes consumed as alternatives → the barrier form.** The
  formal hook exists already: alternativeness is demanded exactly
  where well-formedness *requires* the flows to be cells of one
  bundle — branches of one collect (the disjointness demand of
  `partial-collect-design.md`), operands of one partial-collect
  merge, a covering dispatch over {A-outcome, B-outcome, ran-out}.
  Under junction elaboration such consumers are witnessed
  ill-formed; the (lawfully deep) inference reads the demand and
  inserts the coordinating node instead, consuming `~A` and `~B`
  directly and minting fresh wires. The rejection of the weaker
  elaboration is the selection of the stronger one.
- **Priority needs no inference path at all.** Its natural
  time-travel spelling — use b only inside the no-A alternative —
  elaborates correctly under plain *junction* commutes: the no-A
  branch means the walk contained no A, and in that case
  first-B-of-the-full-walk *is* first-B; laziness recovers the
  efficiency (B2 demanded only down the no-A branch). The priority
  program's outcomes are reachable without ever inferring series;
  series survives as an explicit drawn form. So the inference
  decision is genuinely **binary**: independent or alternative.

The same probe recurs one joint over: whether the walk's collected
output and the abort outcome are themselves alternatives (either
the completed list *or* the error — the `Either` shape → the
conditional/sequence reading) or an independent pair (the prefix
*and* whichever terminator — the shortened-prefix reading). One
reading rule at both joints.

Fine print owed: the enumerable list of alternativeness-demanding
consumers should be kept explicit — it is what keeps the deep
inference predictable rather than spooky.

## The conflation: option flows and case flows

Working the above exposed a conflation the record has been living
with. An option flow is like one case where the alternatives are
disregarded: a value wire in an option flow is the value *in the
case the option is defined*; a value wire in a case flow is the
value *in the case the alt is realized*. Structurally the two are
the same object — option-kind relative to the parent, firing
zero-or-one times per element. But the two idioms read "move it out
of the loop" **oppositely**:

- **Commuting an option flow out** is monadic sequence: stop
  iteration when the option is *undefined*. This has a
  well-established analog in many languages
  (`sequence :: [Maybe a] -> Maybe [a]`), where it universally
  means break-on-undefined. This is the commute the record designed
  and the compiler ships (`lazy-stream-commute-design.md`,
  `Codegen.emitSequenceCommute`).
- **Moving a case alt out** has been read as: stop iteration when
  the case *is defined* — break on A. That is the monadic sequence
  of the alt's *complement*: for `Left | Right`, moving Left out in
  the break-on-Left sense is sequence of the Right-biased Either,
  and vice versa. A user who sees a case flow crossing the loop
  boundary will read break-on-defined — reinforced when a value is
  *scooped* out with it.

The duality is exact — **escape-on-a-cell equals
sequence-of-its-complement** — and for two-cell bundles the two
readings even scoop the same payload: Haskell's
`sequence :: [Either l r] -> Either l [r]` is simultaneously
"sequence of the Right-biased monad" and "escape on Left, scooping
its payload." That is why a whole design conversation could run in
escape polarity while calling it commute.

But the polarity is genuine content, because both polarities
applied to the *same* wire are different programs, both everyday:
sequence(`~Some`) is traverse (all-or-nothing); escape(`~Some`) is
*find* (first-match). So the polarity cannot be inferred from the
operand, and defaulting it from the opener's kind (option opener vs
case opener) would make structurally identical wires read
oppositely by where they came from — the provenance-is-never-
semantic principle violated in flow-wire form
(`end-when-design.md`, revision notes, reason 2).

One framing was considered and rejected in the conversation: a
one-bit polarity setting on the commute node. Rejected as a flag —
the record's standing aversion, sharpened by this being a visual
language: a hidden bit that flips a node's meaning is exactly what
a drawing must not need. Whatever resolves this must be *visible
structure*.

## Not a commute

The sharper result, and the reason the "barrier commute" working
name is probably wrong: **the break-on-case interpretation is not a
commute at all.** The test is where the collected value lives
relative to the moved wire:

- Uncollect a list flow; case split into A and B; move the A wire
  out in the **break-on-A** sense; collect the list flow. The
  resulting collected value is *not* in the A flow — it exists
  exactly when no A ever fired, i.e. it is in **A's complement**
  (which for the two-cell split could even be called B). The flow
  collect order has *not* been commuted; what appeared at the walk
  level is a freshly minted termination structure, not the A layer
  relocated.
- Move the A wire out in the **continue-only-on-A** sense (break on
  the first non-A) and collect: now the resulting value *is* inside
  the commuted-out A flow — outer "A held every time" alternative,
  inner list of A payloads. `list ⋉ A` genuinely became
  `A ⋉ list`. The collect order has in fact been commuted.

So the identity test — *does the collected value land inside the
moved flow?* — separates the two polarities into two different
operations, only one of which is a commute. Three consequences:

1. **The two polarities belong to two construct families the
   record already has.** Sequence polarity is commute (a layer
   swap; the value in the moved flow; conditional remainder).
   Escape polarity is the **cut family** — end-when/collect-until —
   whose derived output is an unconditional prefix plus a
   discharged terminator; escape(`~Some`) and collect-until's
   first-match are the same program. The time-ordered "barrier
   commute" of the inventory above then reads naturally as the
   **multi-stop collect-until**: collect-until's discipline is
   already "outputs correspond to input pairs, arity read off the
   node's own wiring," so two stop pairs give prefix plus per-stop
   lanes — payloads unpacked, coordination at exactly one node.
2. **An earlier finding becomes a corollary.** The conversation had
   observed that stacked cuts are time-ordered (end-when's
   regime-1 theorem: over one bundle every stacking equals the
   merged form) while stacked commutes are priority-ordered, and
   conjectured the rule "constructs whose derived output is an
   unconditional prefix can be time-ordered lawfully; constructs
   whose output is a conditional remainder can only be priority."
   Under the identity test this is no longer a coincidence to
   explain: the two stacking behaviors belong to two different
   operations. A cut's which-stopped alternativeness lives at the
   single discharge (no upstream sibling wires to retro-shrink — no
   time travel); a commute's completed alternative *is* the walk
   that ruled the abort out (nesting, hence priority).
3. **The collision is live in the record, not hypothetical.** The
   failure round's 2026-08-04 revision draws failure programs as
   "split + inferred **short-circuit commute** + collect"
   (`failure-payloads-design.md`), and the scoop generalizes to it
   (`barrier-value-crossing-design.md`). That construct is escape
   polarity under a commute name — by the identity test, the
   collected value of the success path lands in the error alt's
   complement. Whether those passages need renaming or re-founding
   on the cut family is part of this problem.

## The co-flow question

Underneath the vocabulary question is the ontological one — the
record's "what does it mean?" lens. The escape use of a case wire
is not consumed the way flows are consumed: a flow wire says "here
is when, and how often, this happens" and its consumers fold or
transform those firings; an exit wire says "here is where the walk
goes to die" — it is a *destination*, control rather than data. In
the polarity vocabulary of logic: a sum analyzed by cases is used
positively; a sum used as an exit is used at its negative polarity,
like a continuation. Hence the conjecture: **maybe case flows —
or maybe options and errors specifically — are not flows but
co-flows.**

Where the record already touches this:

- **The terminator is the existing near-concept.** Every flow has a
  termination event; the cut family writes terminators from data;
  interrupt writes them from outside; the re-founded failure
  account distinguishes *arrivals* from *endings*. "Errors are
  co-flows" rhymes with "failure rides endings" — and collides with
  the same no-smuggling rule (terminators carry *reason*, never
  data; payloads travel value wires — `end-when-design.md`,
  revision reason 1). If a co-flow is a wire whose firing ends
  enclosing structure *and carries a payload to a handler*, the
  no-smuggling line has to be re-drawn or the payload has to keep
  its separate value wire, as collect-until's stop pairs do.
- **Two candidate homes for the polarity**, both recordable now:
  - **Polarity of kind**: option/error bundles are minted as
    co-flows; data case splits as flows; conversion explicit. Risk:
    same-shaped wires reading oppositely by their opener — the
    provenance worry again — and multi-close freedom suffers (one
    consumer filters on A while another exits on A; a kind-level
    choice forecloses one of them or needs conversion nodes).
  - **Polarity of use**: cells are neutral; the *consuming
    construct* sets polarity — a wire into a join filters, into a
    collect branch dispatches, into a stop lane exits. No flag
    anywhere: the "bit" is which construct the wire enters, which
    is visible structure, and the same alt can serve both polarities
    for different consumers (multi-close preserved). The ontology
    question then relocates: an option's None *is* neither data nor
    ending intrinsically; programs that keep it (optional field,
    matched late) use it positively, programs that abort on it
    (lookup miss) use it negatively — and the language makes the
    choice visible instead of baking it into the type, which is
    precisely what the Maybe monad does *not* do.
- **The drawing** (thinking about it is in scope; building it is
  not): the escape gesture programmers already draw on whiteboards
  is an arrow out the side of the loop box — a wire leaving against
  the nesting direction, carrying a payload to a handler outside.
  If co-flow becomes a wire species, its species could *be* that
  visual direction — which would make the co-flow reading the
  natural drawing of collect-until's stop lane rather than a new
  semantic object. That reconciliation — co-flow as the
  presentation of the cut's stop pair, cut-family semantics
  underneath — is the current lean for the everyday case, with the
  kind-level question left genuinely open for options and errors.

## Drawn, not algebraic: the resolution posture

A closing thought from the recording conversation, kept here because
it should shape how question 1 gets resolved. There is a
recognizable **theme** running through this language — not a
numbered principle, but a recurring move: where other languages
build clever constructs that *automatically decide* how control-flow
interactions resolve (Koka's algebraic effects are the sharp
example), this language gives that up on purpose. If it is drawn so
the user can see it, it does not have to be as algebraically pretty;
so long as the user can see what is going on, that is enough.

The record already contains instances of the move, made
independently:

- **Legibility over enforcement** — the IO round's recorded stance:
  external ordering is made *readable* rather than governed by rules
  (`effects-design.md`, "The IO-as-flow direction").
- **Middleware stack order drawn as nesting** — handler-land's
  invisible stack-order hazard dissolved not by an algebra of
  handler commutation but by making the stack a drawing
  (`late-bound-operations-design.md`).
- **The termination tie** — where conventional code resolves
  priority-vs-first silently by statement order, here the choice is
  visible structure; "the language merely refuses to let the tie be
  an accident" (`end-when-design.md`).
- **Completion shown faint** — the inferred parts of a time-travel
  program are displayed, not silently assumed
  (`time-travel-programs-design.md`).

Applied to this problem: the resolution should not be an algebra of
flow/co-flow interaction — a law set from which the system derives
which polarity or which coordination applies. It should be a
**drawing inventory**: distinct, at-a-glance-discriminable gestures
for each interaction this round identified — the layer swap
(sequence commute), the exit (the escape / stop lane), the junction
of independent closes, the series nesting (priority), and the
single coordinating node (time-ordered disjunction). The user
chooses the interaction by drawing it; nothing chooses for them.
The use-to-variant inference already obeys this posture on the
time-travel side: its inputs are visible consumption shapes (the
enumerated alternativeness-demanding consumers of question 5), and
its output is inserted visible structure, shown like any
completion.

Two riders recorded with the thought:

- **Laws may veto; only the drawing elects.** Giving up algebraic
  prettiness does not give up laws. The law of the shortened flow,
  the disjointness demand, and the no-time-travel law all still
  hold — but their job is *validity* (witnessing ill-formed
  combinations; guaranteeing a drawing means what it looks like),
  never *selection* among meanings. The identity test that cracked
  this problem is algebra used exactly that way — a designer's
  diagnostic instrument, not machinery in the language.
- **The theme's countervailing duty.** If every interaction is a
  distinct drawing, the interaction inventory must stay small and
  the drawings discriminable — two interactions that draw nearly
  alike would be strictly *worse* than an algebra, because the
  drawing would carry a distinction the eye cannot. That is the
  acceptance test the visual-leap constraint imposes on any
  resolution of question 1: escape, swap, junction, series, and the
  multi-stop node must each answer "how would this draw?" with
  answers a reader cannot confuse. The theme replaces the algebraic
  burden with a legibility burden; it does not remove the burden.

## The wire-order geometry (second conversation, 2026-08-15)

A same-day continuation went below the construct inventory to the
drawing conventions themselves, and found that the polarity
distinction can be made *positional* — read off wire order rather
than legislated. Everything in this section is exploratory: one
path is rejected structurally, the other is the current lean in
one of its two forms, and nothing is adopted.

### The deferral intuition, and where None lives

The seed intuition: for an option or error flow, the flow wire is
a handy way of saying "I'm not dealing with this now — save it
for later." In some sense the flow wire *represents the None case*
(the error case, for an error flow). Sharpened: the wire does not
represent None by firing — its firings are the defined elements.
None lives in the wire's **silence**, and while the wire is open
the silence is ambiguous: *not yet* or *never*. The discharge —
silence becoming a definite None — happens where the wire
terminates: at a collect, or, after commuting, at the walk level.
Deferral is outward motion of the discharge point. (This is the
failure round's "failure rides endings" arrived at from the other
direction: the error case is the ending-side of the wire, and
holding the wire is holding the ending open.)

The picture gives the option flow wire an intrinsic **grain**:
firings continue, silence breaks. Sequence polarity runs with the
grain; escape runs against it — which is *why* escape strands the
value (below). That puts some weight back on the kind side of the
scale after the first conversation's polarity-of-use lean; the two
may yet be compatible (a grain on the wire, a gesture chosen at
the consumer), but the tension is recorded.

A corollary sharpening open question 6: **the duality commutes the
flows but never the payload.** Give OptionIter a None flow port
and try to rescue find as a commute by commuting out the *None*
side: the flow structure reads coherently ("the whole walk was
all-None"), but the value wire strands identically, because the
found payload lives on the pole that was broken on. Whichever
spelling is chosen, the payload sides with the exit.
Escape-equals-sequence-of-complement is exact for flow structure
and inexact for value delivery; a None port makes the two
spellings interconvertible as flows and still cannot deliver
find's payload by crossing wires. The payload is what forces the
cut.

### The convention that spatializes context

Take the visual convention: data flows from the top of the page to
the bottom; an uncollect's flow output is to the left of its value
output; value wires sit to the right of the flow wires they depend
on. Then left-to-right order *is* the flow context —
`Context.res`'s ordered path drawn as position, outermost
leftmost. Two consequences fall out:

- **A commute is an adjacent transposition.** Uncollect a list,
  then an option on its element: `[~L, ~O, v]`. The sequence
  commute is the two flow wires crossing — an X — with the value
  wire untouched: `[~O, ~L, v]`. "Commute" becomes true in its
  plainest algebraic sense. And the transposition is *sound*:
  every position in the result reads truthfully — `~O` leftmost
  because definedness is now a fact about the whole computation,
  not any particular element; `v` still adjacent to `~L` because
  within the surviving list every element was defined, so the
  commuted list is the complete firing set of the value wire.

- **The convention refuses to draw break-on-defined.** Try the
  escape reading as a transposition and both ends break at once:
  the value wire is stranded — still drawn in the shortened list,
  but its firing set there is empty, since the surviving prefix
  is exactly the elements where it never fired — and the thing
  that exits leftmost is not a flow over the computation at all;
  it fires at most once, a discharge, not a layer, with no
  legitimate slot in the left-to-right order. The stranded wire
  is Check's flow-borne witness made visible. So the convention
  does more than disambiguate the polarities: it *refuses to
  draw* one of them as a crossing — the drawn-not-algebraic
  posture delivering the swap/exit discrimination for free.

### The payload-side discovery

Now give the error case a payload. The error flow has one flow
wire (firing on success — the success payload rides it) and the
error case in its ending. To carry an error payload, divide the
wire in two: `~Error` and `~Success`, error payload in the
`~Error` flow, success payload in `~Success`. Under the standard
convention this lays out, left to right — `~Error` outer, because
the error is discharged where `~Success`'s silence resolves, one
frame out:

```
~Error   e   ~Success   s
```

And notice what happened. The `~Success` flow is what we used to
*call* the error flow — it is the wire the success payload lives
in. The error payload is not in the old "error flow" at all: it
sits to the old error flow's **left**, while the success payload
sits to its right. The relationship between a flow wire and the
case it represents is *flipped* for case flows relative to other
flows — the origin of the **co-flow** temptation. And it puts the
first conversation's identity-test duality in the mirror: escape =
sequence-of-complement is drawn as left-right reflection.
Negation is the mirror.

### Path (A): complement flows — structurally unavailable

First path considered: turn case flows back into regular flows by
making the flow wire represent the case *complement* — wires named
`~Success` and `~Error` with the error payload in the `~Success`
flow and vice versa. Rejected in-conversation, and not on
confusion alone (though the names lie): **the complement of an alt
is not an alt.** For {A, B, C}, the wire representing A's
complement fires on B-or-C, and its payload is a packed sum of B's
and C's payloads — the partial-collect merge as a mandatory
bottleneck at every case split, before anything is even consumed.
Path (A) is only definable for two-cell bundles. Recorded as
rejected on arity, not taste.

### Path (B): payload to the left — the sandwich

Second path: treat case flows as co-flows, and say that for a
co-flow the payload sits to the *left* of its wire rather than the
right. Open the list: `[~L, elem]`. Case-split the element:
`[~L, a, ~A, b, ~B]`. The escape payload's position now says two
things at once: `a` is right of `~L` — it depends on the element,
it is made from list data — and left of `~A` — it is addressed
*past* the alt wire, to the frame beyond. "Depends on the walk,
delivered outside it" is what an escape payload is, said by
position alone.

Commute `~A` out and the mechanics follow instead of being
legislated: `a` is sandwiched between `~L` and `~A` and may cross
neither, so the transposition must carry it along:

```
[~L, a, ~A, b, ~B]   ~>   [a, ~A, ~L2, b, ~B]
```

The payload cannot strand: it is scooped, or abandoned, or the
gesture is not drawn — it cannot continue being used in the list.
Where the standard convention *refused* to draw escape as a
crossing, this layout *draws it correctly*: stranding stops being
an error a checker catches and becomes a position that cannot
exist. And the exiting unit `[a, ~A]` is recognizably
collect-until's **stop pair** — payload traveling *beside* the
terminator, never inside it. The no-smuggling rule restated as
geometry.

### The fork inside (B): strong vs mixed

The case split above laid *both* alts payload-left. But `b` is the
continue alt — its payload feeds the walk's work, consumed
per-firing *inside* the list, and that use wants the standard
side: `[~B, b]`. So path (B) forks:

- **(B-strong): case alts are uniformly co-flows**, payload always
  left. Then ordinary dispatch — a collect folding both branches
  per element, partial-collect territory — needs a story for
  consuming a payload that sits outside its own wire. No story
  seen yet; not rejected, but unoccupied.
- **(B-mixed): the side is per-use, and one alt wire offers both
  ports** — the conversation's own one-wire-two-payloads
  observation about the error flow ("you wouldn't necessarily
  need another flow wire — one flow wire with both a left
  (co-flow) payload and a right (flow) payload"), generalized.
  The right port is the payload in the **firing frame**:
  per-occurrence data, for dispatch and filtering. The left port
  is the payload in the **discharge frame**: delivered outward,
  for escape.

Under (B-mixed) the flow/co-flow question and the first
conversation's polarity-of-use lean stop competing: there is no
co-flow *kind*, there is a co-flow *side*, and which side the
payload hangs off the wire *is* the polarity — not a hidden bit, a
position. Multi-close survives: one consumer dispatches on A
through the right port while another escapes on A through the left
port, two distinct value wires, both visible. (B-mixed) is the
current lean; unadopted.

### Why options and errors: the two faces

A frame for why the puzzle picked these constructs. For a one-shot
computation, every alt fires at most once and every firing *is* an
ending — the firing frame and the discharge frame coincide, so
either payload side is coherent (`[e, ~Error, s, ~Success]` reads
fine as a standalone error computation). The two sides pull apart
only under repetition, where "per firing" and "at discharge" are
different moments. A list is pure repetition-face; a one-shot case
is pure ending-face; option and error are zero-or-one — a
degenerate repetition *and* an alternative, on the fence between
the faces. That is why nobody is ever confused about what a list
flow wire means, and why the polarity puzzle lives exactly where
it does.

### Tying up the walk level

What closes `[a, ~A, ~L2, b, ~B]` was left genuinely unclear in
the conversation; two tentative readings were laid out, possibly
two halves of one answer:

- **Propagation is iterated transposition.** If the walk sits
  inside another structure `~M`, the pair `[a, ~A]` keeps
  commuting leftward: `[a, ~A, ~M, …]`. The geometry supports it
  for free — the payload stays glued. Re-raising an error is the
  escape commute applied again.
- **Handling is the payload crossing its own wire.** Eventually
  something consumes the outcome as data: a collect over the
  walk-level case {A-fired, ran-out}. In the *handler's* frame,
  `a` is per-firing data of `~A` — the right-side reading,
  `[~A, a]`. So the one transposition the sandwich forbids in
  flight — the payload crossing its own alt wire — is exactly
  what happens at a handler, and only there. Control until the
  flip; data after. Co-flows terminate by converting to flows at
  a handler boundary — which matches how exceptions behave:
  control until the catch, a value at the catch.

### Worries kept on the table

- **Leftward structure growth.** If escape payloads are themselves
  structured (a case-split error payload), structure grows
  leftward — mirrored nesting — and several escapes from several
  depths interleave in the left region. Propagation stacking
  suggests depth reads off position, which would be good; no nasty
  example has been run.
- **Series-parallel.** Left-right is total only along a series
  chain; under `Poset`'s PARALLEL (Cross), "left of" must
  generalize to "on the outward side of," per branch. The sandwich
  argument should be re-run in series-parallel form before it is
  trusted.
- **Wire order becomes semantic.** If position carries meaning,
  the eventual renderer is not free to reorder wires — the
  language commits its drawing to an ordered discipline. Under the
  visual-leap constraint that is arguably a feature ("how would
  this draw?" answered by "it already is the drawing"), but it is
  a commitment, and it is recorded as one.
- **General geometric risk.** Having both flows and co-flows (or
  both payload sides) could create geometric problems not yet
  imagined; the worry was raised in-conversation and stands.

## Open questions

1. **The ontology.** Flow vs co-flow: polarity of kind, polarity of
   use, or co-flow as a wire species presenting the cut family's
   stop lanes. The lean recorded above is polarity-of-use with the
   species presentation; unadopted. *(Second conversation: the
   lean sharpens to (B-mixed) — no co-flow kind, a co-flow
   **side**; the payload's position relative to its own wire is
   the polarity, and the grain observation keeps a kind-flavored
   residue in view. Still unadopted.)*
2. **The vocabulary.** Does "commute" keep only sequence polarity?
   The identity test says the escape idiom should stop being called
   a commute; the failure round's "short-circuit commute" and the
   scoop passages are the live clients to re-read.
3. **The barrier form's home.** Standalone node vs the multi-stop
   collect-until. The fusion line (`end-when-design.md`: a cut
   fuses into its collect exactly when it mints no new flow) is the
   knife: does the disjunction exit ever need walk-level outcome
   *flows* with consumers beyond one collect, or is the discharge
   value's downstream case split always enough?
4. **Series commutes collected out of order.** What construct pulls
   the nested outcomes apart into independent closes, if anything.
   Deliberately unworked — priority termination is rare.
5. **The inference fine print.** The explicit list of
   alternativeness-demanding consumers (collect branches,
   partial-collect operands, …) that licenses the barrier
   elaboration.
6. **OptionIter's None port.** This round adds weight to
   `partial-collect-design.md`'s position 2 (give None a flow
   port): with it, sequence(`~Some`) and escape(`~None`) become
   interconvertible spellings and no idiom is forced by a missing
   port. *(Second conversation: interconvertible as **flow
   structure only** — the duality commutes the flows but never the
   payload, so a None port still cannot make find-with-its-value a
   commute. The payload is what forces the cut.)*
7. **The no-smuggling boundary.** If co-flows carry payloads, the
   terminators-carry-reason-only rule needs restating; joint with
   `failure-payloads-design.md`. *(Second conversation: the
   sandwich reads as no-smuggling kept — `[a, ~A]` is a stop pair,
   payload beside the terminator, never inside it.)*
8. **(B-strong) vs (B-mixed).** Run plain dispatch — a case split
   fully consumed by one collect's branches, no escape anywhere —
   under the both-ports account, and check that the right-port
   story reduces exactly to today's partial-collect semantics with
   nothing left over.
9. **The ugly example.** Two escapes from different depths plus a
   continue alt, all live at once: does the left region tie up or
   tangle? (The leftward-growth worry, made concrete.)
10. **The sandwich under Cross.** Re-derive the payload-carrying
    transposition in series-parallel context (`Poset.res`), where
    "left of" must mean "on the outward side of."

## What this touches

- `lazy-stream-commute-design.md` — the implemented sequence
  commute is unaffected as a construct; the taxonomy's word and its
  case-flow generalization are what this problem owns.
- `commute-design-notes.md` — the historical options survey;
  polarity note added to its status.
- `end-when-design.md` / `variable-rate-consumption-design.md` —
  the cut family gains the escape idiom as a client; the multi-stop
  collect-until candidate and the fusion-line question land there
  if question 3 resolves that way.
- `failure-payloads-design.md`, `barrier-value-crossing-design.md`
  — the "short-circuit commute" naming and the scoop (question 2);
  the second conversation's payload-side account (the error
  payload as the left port of one wire, no second flow wire
  needed) is a candidate re-founding of the failure payload.
- `src/Context.res` / `src/Poset.res` — the left-to-right
  convention is the ordered path spatialized; the Cross
  generalization is question 10.
- `partial-collect-design.md` — the OptionIter None port
  (question 6); the disjointness demand as the inference hook.
- `core-model.md` — the commute paragraph eventually needs the
  polarity distinction once decided.
- `time-travel-programs-design.md` — the design-method statement of
  the two program classes and the two laws (recorded above) is a
  candidate for promotion into that doc.
