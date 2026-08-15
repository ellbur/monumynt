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

## Open questions

1. **The ontology.** Flow vs co-flow: polarity of kind, polarity of
   use, or co-flow as a wire species presenting the cut family's
   stop lanes. The lean recorded above is polarity-of-use with the
   species presentation; unadopted.
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
   port.
7. **The no-smuggling boundary.** If co-flows carry payloads, the
   terminators-carry-reason-only rule needs restating; joint with
   `failure-payloads-design.md`.

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
  — the "short-circuit commute" naming and the scoop (question 2).
- `partial-collect-design.md` — the OptionIter None port
  (question 6); the disjointness demand as the inference hook.
- `core-model.md` — the commute paragraph eventually needs the
  polarity distinction once decided.
- `time-travel-programs-design.md` — the design-method statement of
  the two program classes and the two laws (recorded above) is a
  candidate for promotion into that doc.
