# The polarity of moving case cells out of a loop

Status: **open problem, elevated to Tier 1** (design conversations,
2026-08-15/16) — a worked conversation record; the fourth
conversation (2026-08-16) adopted the round's first results (the
election rule, the stream-lean retirement, the barrier's expansion —
see the fourth-conversation paragraph below and its section). The
first conversation produced three results that remain firm on paper:
series commutes mean priority termination, time-ordered disjunction
termination requires a single coordinating operation, and two
junction commutes are two loops. Later rounds retired the proposed
**co-flow** distinction and then found the more important distinction
it had been obscuring: a case cell is not a flow wire at all. It is
written `(payload, %Cell)`. Focusing a cell as an option derives an
ordinary flow wire for the cell's **complement**. Thus the full result
bundle is `[(error, %Error), (success, %Success)]`, while its ordinary
success projection is `[~Error, success]`: success is defined exactly
where Error is absent.

`%Cell` does support commuting, but case-cell commute is not bare wire
motion. Moving `(payload, %Cell)` across an enclosing flow changes the
scope of the case claim and transforms its evidence. Across a finite
list, pointwise `A | B` becomes “at least one A, with a selected A
witness” or “all B, with the list of B payloads.” This supersedes the
record's interim claims that every cell owns a `(value, flow)` pair and
that break-on-one-cell cannot be a commute. The open problem is now to
specify the lifting laws supplied by each enclosing flow, their witness
selection policies, and their optional preservation of a prefix. A
first-witness commute can prefix any wire guaranteed to be valid in the
cell's complement; this makes prefix retention orthogonal to commuting
and reopens the exact boundary with collect-until. The other open task
is the exact expansion from compact complement flows such as `~Error`
to case-cell commutes. A **drafted table for the lifting-law
inventory** (open question 2) is appended (2026-08-16, "The
lifting-law inventory: a drafted table") — exploration, unadopted,
prepared for that question's conversation; its central proposal is
that witness selection is an order demand licensed by the
owned-order criterion.
`open-problems.md` carries the ranked row; this document owns the
content.

An **intermediate conversation** (same day, 2026-08-15) is appended
from “The wire-order geometry” on. It explores a visual convention that
makes flow context positional and works two candidate paths:
complement flows and payload-left. It originally rejected complement
flows on arity and leaned toward per-use payload sides. Those ontology
conclusions are superseded by `%Cell`: the arity objection resulted
from requiring a derived complement flow to carry the complement's
packed payload, while the current account keeps payloads on their
individual cells. The positional and series-parallel observations are
retained as design evidence; still nothing is adopted.

A **third conversation** (2026-08-16, appended from “The accident
boundary and the jog” on) produced three results. Series priority was
reframed from a rarity to a trap: two shortening commutes drawn in
series look innocent and mean priority, so the tie must not be
electable by accident, whatever its frequency — and on an unbounded
stream the series form is not merely surprising but unanswerable. The
proposed visual carrier is the **jog**: a commute that may shorten the
iteration visibly displaces the flow wire, under the criterion *jog
iff the output flow's firing set may be a proper subset of the
input's*; firing-set-preserving commutes (IO out of a list) draw
straight through. And a representation lean: cells may be node-local —
per-alt value and cell ports on the split, complement flows as derived
ports of the same node — rather than a third reference kind threaded
through the model. All three are leans, nothing adopted.

A **fourth conversation** (2026-08-16, appended from "The election
rule and the barrier's expansion" on) produced this round's first
**adopted** content. Adopted: the **election rule** — a flow wire
representing an iteration, once shortened by a commute, cannot be
shortened again by a commute without an explicit election (the
commute being the only *implicit* shortener; drawn cuts such as
end-when are their own election) — resolving open question 12(b)
toward election; the **retirement of the stream ill-formedness
lean** (a termination concern that crept into a polarity problem —
the rule is uniform across flow kinds); and the **barrier's
expansion** as fused join → commute → split with a disjoint-union,
provenance-keeping join, resolving question 5 — the same-element
tie policy is the join's outer/inner asymmetry, forced by dataflow
for dependent exits and elected for siblings. The composition
contains exactly one shortening, so the safe merged program is
unmarked while the series form is elected, with no
barrier-specific legislation. Remaining from the round: the
election's concrete form (restriction-adapter node vs node bit)
and the sibling join's expansion against `Complete`'s Cross. Two
candidate restrictions on error flows — linearity on the IO
analogy, and handling transmuting the error flow into a threaded
control wire — were examined and rejected in place.

The conversation this records ran from a narrower starting question
(multiple alternative early terminations from one case split) and
the narrow results are recorded first, because the general
discovery falls out of them.

The early sections retain the legacy notation `~A`, `~B`, and “case
flow” because that is the notation in which the multi-termination
problem was originally worked. Under the current model, those rails
must be read as option/complement flows derived from `%A`, `%B`, and
their bundle, not as the cells themselves. The section “Cells,
projections, and flows” below owns the current vocabulary.

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
ancestor's. The series chain is a second client for that rule.
2026-08-16: the adopted election rule conditions this client — the
admission no longer holds for a shortening operand consulted on
the survivor of another shortening commute unless the election is
drawn; see "The election rule (adopted)" below.)

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
   *(Resolved 2026-08-16: not a new primitive — the fused
   join → commute → split expansion, with the tie question for
   unaligned exits answered by the join's outer/inner asymmetry.
   See "The barrier is join → commute → split" below.)*
3. **Junction commutes** — two loops with different terminations,
   independent outcomes (both can fire).

## Inferring the variant from use

In the time-travel program the user does not have to draw every
commute or join. They expose and route the case flows in ways that
show which relationships are wanted, and inference elaborates the
no-time-travel form. In the ordinary error facet this is deliberately
formulaic: trace `~Error` outward; crossing an enclosing loop inserts
sequence, and crossing error nesting inserts monadic join. The
organizing principle the first conversation reached:

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

**Correction to the time-travel record.**
`time-travel-programs-design.md` currently says completion inserts
bookkeeping only, characterises its insertions by an identity-valued
shadow, and excludes anything that changes firing structure. That is
false of the canonical commute it already admits: sequencing an error
flow out of a list short-circuits the list consumer. Cross supplies a
second warning by assigning previously-unspecified multiplicity. No
value ports does not mean no behavioural effect; these operations act
on execution context rather than by applying a value function.

The boundary this round now proposes instead:

> **Completion may not invent a source, sink, observation, or handling
> intent. It may elaborate an authored under-committed relationship
> into the unique operational flow structure required by that
> relationship and the language's published canonical policies.**

For errors, producing a declared Error cell, routing its visible error
rail outward, and consuming the rail at a failure fact or handler are
the authored intent. The inferred sequence and join nodes may change
runtime demand and termination; they are lawful because that geometry
has one published expansion, not because the nodes are semantically
inert. They are shown faint like every other completion. The older
identity-shadow boundary needs correction in its owning doc.

## Cells, projections, and flows

The current account introduces a separate sigil for case cells:

```
a, %A
```

`%A` says that `a` is the payload/evidence of the selected A cell. It
is not an ordinary flow wire. `~F` remains the notation for a dynamic
flow, including option flows on which undefinedness, commute, and join
operate. The distinction is semantic, not just typographic:

- `%A` is a cell of a sum, carrying evidence that A was selected;
- `~F` is an execution or absence rail whose firings can be transformed
  by flow operations.

A three-way case bundle is therefore written

```
[(a, %A), (b, %B), (c, %C)]
```

and not as three `(value, flow)` pairs. Focusing one cell as an option
produces a partial projection. The option is undefined on the focused
cell's complement:

```
getA : A(a) | B(b) | C(c) -> Option<a>

[(a, %A), (b, %B), (c, %C)]
    |- [~BC, a]
    |- [~AC, b]
    |- [~AB, c]
```

The invariant is: **the flow immediately left of an option value names
the condition under which that value is absent**. `~BC, a` does not
mean that a is carried by a BC cell; it means that the projection to a
is undefined when B or C was selected.

These three option flows are correlated views of one discriminator,
not independent Boolean sources. On an A occurrence, `a` exists,
`~BC` does not fire, and both `~AC` and `~AB` do fire. An elaboration
must retain the originating bundle so that separately routed
complement flows cannot be recombined as though their occurrences were
unrelated.

The binary case hid this rule because each complement is itself one
cell. For Error/Success, the structural bundle is

```
[(error, %Error), (success, %Success)]
```

and its two option projections are

```
[~Success, error]
[~Error, success]
```

The older row

```
error, ~Error, success, ~Success
```

accidentally put the right items next to one another but paired them
incorrectly. Read cyclically, its actual option pairs were
`(~Success, error)` and `(~Error, success)`. The new `%` sigil removes
that ambiguity.

## Case-cell commute changes scope

`%A` is not a flow, but it does support commuting. The operand is the
cell together with its payload/evidence, `(a, %A)`, and crossing an
enclosing flow changes the scope over which the case claim is made.

Open a finite list and split every element into A or B:

```
~List, a, %A, b, %B
```

Commuting `(a, %A)` outward gives

```
a, %A, ~List, b, %B
```

At this point `%B` is pointwise trivial inside the surviving list. If
the list flow is reached, A did not occur, so every surviving element
is guaranteed to be B. Collecting the list transports that trivial
pointwise fact into an aggregate fact:

```
a, %A, listB, %B
```

The type-level operation is

```
List (A + B) -> A + List B
```

and its logical reading is

```
(there exists an A) | (all elements are B)
```

Thus the spelling of each cell stays fixed while its scope changes:

- before commute, `%A` means “this occurrence is A”;
- after commute, `%A` means “at least one occurrence was A,” and `a`
  is the selected existential witness;
- before collect, `%B` means “this surviving occurrence is B” and is
  locally guaranteed;
- after collect, `%B` means “all occurrences were B,” with `listB` as
  the aggregate evidence.

The empty list selects `([], %B)`: “all elements were B” is vacuously
true. For an ordered list, the canonical sequence policy selects the
first A as the witness and short-circuits later traversal. This policy
is part of the commute law, not derivable from the type alone. Other
lawful operations could select the last A, join A payloads, or collect
all As, but they are different programs and need different visible
structure.

This is finite constructive De Morgan duality made operational:

```
not (exists A) = forall (not A) = forall B
```

Case-cell commute is therefore better understood as **scope lifting**
or **quantification across a flow**, rather than as a physical cell
marker sliding unchanged past a wire.

## A case-cell commute may preserve the complement prefix

The minimal type-level operation above discards the B payloads visited
before the first A:

```
List (A + B) -> A + List B
```

That information loss is optional. A first-witness commute may also
retain the traversed complement prefix:

```
List (A + B) -> (List B × A) + List B
```

The two result cells mean:

```
%A: first A occurred; return the preceding B prefix and the A witness
%B: no A occurred; return the complete B list
```

Because both cells contain the same kind of B prefix, the result
factors as

```
List B × Option A
```

where the prefix is the entire list when A never occurs. The
prefix-discarding sequence is a projection of this richer operation:
it forgets `List B` in the `%A` cell.

The capability is more general than retaining B's designated payload.
Let `x` be any wire whose availability is guaranteed throughout A's
complement:

```
not A => x is defined
```

Then the commute can expose `prefixX`:

- in the `%A` cell, it contains x from every occurrence before the
  selected first A;
- in the all-complement cell, it contains x from every occurrence;
- the selected A occurrence is normally outside the prefix;
- later occurrences are not demanded by a short-circuiting commute.

Several complement-valid wires may be prefixed together. A wire valid
in only *part* of A's complement cannot become a plain dense prefix;
its own case/option structure must remain in the collected prefix.
Likewise, a value that depends on the A occurrence is not a prefix
value merely because it is geometrically nearby. This availability
test is the no-smuggling boundary for prefix outputs.

The geometry is awkward for a real semantic reason. `%A` determines
where the prefix ends, but every value in the prefix comes from
`%A`'s complement. The prefix therefore does not naturally live
inside `%A`, even though it is returned alongside the A witness. Two
candidate presentations are:

```
prefixX, [(a, %A), (allRemainder, %AllNotA)]
```

with `prefixX` factored outside the aggregate bundle; or an explicit
shortened **before-A flow** minted by the commute, on which any
complement-valid wires may be collected. In the latter account the
values do not cross through `%A`; `%A` determines the shortened flow's
termination point.

Prefix is meaningful here because the enclosing flow is ordered and
the lifting law selects the first A. Last-witness, all-witness,
unordered, and parallel commute laws require different context outputs
or have no useful prefix at all. Prefix preservation therefore belongs
to a particular case-cell lifting law, not to `%A` in isolation.

## Several cells: priority follows nesting

For a three-way bundle, commuting A first performs

```
List (A + B + C) -> A + List (B + C)
```

meaning “some A occurred, otherwise every element was B or C.” If B
is then commuted from the residual list, the result is nested:

```
A + (B + List C)
```

A therefore has global priority over B, even when a B appeared earlier
in traversal order. This is the cell account of the monadic worked
example above and preserves the result that **series commutes encode
priority order**. Reversing the commutes reverses the priority.

Stopping on whichever of A or B appears first in time is not the same
composition. It needs one operation that considers the two exit cells
together and selects the first matching occurrence while preserving
their separate payloads. Whether that operation is best presented as
a multi-cell commute or as multi-stop collect-until remains open; it
cannot be inferred by pretending two independently commuted cells were
one temporal race.

## Related operations and presentations

The revised vocabulary separates operations that earlier sections
partly conflated:

1. **Flow commute** transforms an ordinary `~F` rail across another
   flow according to the two flow kinds' published law.
2. **Case-cell commute** moves `(payload, %Cell)` across a flow. It
   lifts a pointwise alternative into an aggregate alternative and
   transforms the payload into evidence at the wider scope. Its
   remainder is conditional: `List B` exists only when no A occurred.
3. **Prefix retention** exposes context accumulated while the commute
   remains in the selected cell's complement. It is an optional output
   of a suitable first-witness lifting law, not evidence that no
   commute occurred.
4. **Cut / collect-until** stops a flow and exposes a prefix beside the
   terminating outcome. For a case-derived first stop, it may be the
   fused drawing of case-cell commute plus collection of the shortened
   before-cell flow. Cuts from external terminators or with different
   discharge structure may still need a broader construct family.

The old identity test is therefore too strong in two ways. Its
conclusion “break-on-one-cell is not a commute” treated a cell as a
flow layer that had to move unchanged, and its later distinction
“conditional remainder means commute; unconditional prefix means cut”
treated information retention as an operation boundary. `%A` rejects
the first premise, while the prefix-preserving transformation rejects
the second. Both

```
A + List B
```

and

```
(List B × A) + List B
```

can result from a case-cell scope lift. The remaining cut/commute
distinction, if any, must be stated in terms of authored stopping
structure, fusion, and output correlation rather than the mere
presence of a prefix.

## The error facet under the cell model

The ordinary failure drawing remains intentionally asymmetric:

```
[~Error, success]
```

It is not the Error cell with its payload hidden. It is the option
projection onto the Success cell of

```
[(error, %Error), (success, %Success)]
```

and `~Error` is the projection's undefined flow. The static and dynamic
error forms identify the same selected occurrences from different
perspectives:

- `(error, %Error)` is the structural Error alternative and its
  payload/evidence;
- `~Error` is the dynamic failure rail on which the success projection
  is undefined.

This relationship explains why error handling can be authored almost
entirely in the compact view. Errors are often an afterthought rather
than the computation's subject; tracing thin `~Error` rails outward,
sequencing them at loop boundaries, and joining their nesting occupies
less visual space and makes formulaic plumbing derivable by the editor.
But every compact edit owes an expansion into the cell model.

For list sequence, the expansion is

```
List (Error error + Success success)
    -> Error firstError + Success (List success)
```

or graphically

```
~List, error, %Error, success, %Success
    -> error, %Error, successes, %Success
```

The expanded operation commutes `(error, %Error)` to existential
scope; its complementary `%Success` cell becomes the all-success case.
The compact `~Error` commute and the expanded case-cell commute are two
facets of this one program.

The richer error commute may also preserve any wire guaranteed on the
Success complement before the first Error. Preserving `success` itself
gives

```
List (Error error + Success success)
    -> (List success × Error error) + List success
```

or, factored, a successful prefix beside an optional first Error. The
ordinary all-or-nothing error facet projects this prefix away on the
Error cell; a debugging, progress, or partial-results facet may expose
it. The error rail determines where the prefix ends, while every
prefixed value comes from the no-Error region.

The compact facet is safe only where an edit has a unique expansion,
or one selected by a published canonical rule. If `project` maps a
cell bundle to its complement-flow view, every supported operation
owes the commuting square

```
project(expand(operation)) = operation(project(program))
```

with `expand(operation)` uniquely determined. Sequence needs a witness
policy (first error for an ordered list). Join must retain the
contributing `%Error` cells and their payload associations so that a
later expanded view can recover distinct handlers. A terminal “Did
this code fail?” consumer may explicitly forget those identities and
payloads; structural join may not.

No-smuggling still applies to demanded payloads. If a program asks
only whether failure occurred, no error value wire need leave its
minting split. If a later handler uses `error`, that use authors the
value connection and the editor derives its route through the already
selected `(error, %Error)` witness. Inference routes evidence selected
by the case-cell commute; it does not invent a value or a selection.

## Drawn, not algebraic: the resolution posture

A closing thought from the recording conversation, kept here because
it should shape how the remaining design gets resolved. There is a
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

Applied to this problem: the resolution should not be an algebra that
silently chooses which interaction the author meant. It should be a
**drawing inventory**: distinct, at-a-glance-discriminable gestures
for each interaction this round identified — the layer swap
(flow sequence), the case-cell scope lift, the exit (the escape / stop
lane), the junction
of independent closes, the series nesting (priority), and the single
coordinating node (time-ordered disjunction). The error facet adds an
important economy to that posture: the author may draw the
under-committed **route** — a `~Error` rail heading out across loops
and error layers — while the editor derives the formulaic sequence
and join nodes that make the route operational. The user's geometry
elects the relationship; published expansion rules fill its crossings
and show them faint. The user need not perform clerical effect
plumbing by hand, but the completed reading remains visible.

Two riders recorded with the thought:

- **Laws may veto and expand; only the drawing elects.** Giving up
  algebraic prettiness does not give up laws. The law of the shortened
  flow, the disjointness demand, and the expansion law all still hold.
  Their jobs are validity and deterministic elaboration: witness
  ill-formed combinations, guarantee that a compact drawing means
  what it looks like, and expand a chosen route without asking the
  author to spell its formulaic crossings. They do not choose an
  Error rail, handler, or final failure observation the drawing did
  not request. The identity test remains useful for describing output
  correlation, but neither a conditional remainder nor an
  unconditional prefix decides whether a case cell commuted; the error
  facet's commuting square is the corresponding editor obligation.
- **The theme's countervailing duty.** If every interaction is a
  distinct drawing, the interaction inventory must stay small and
  the drawings discriminable — two interactions that draw nearly
  alike would be strictly *worse* than an algebra, because the
  drawing would carry a distinction the eye cannot. That is the
  acceptance test the visual-leap constraint imposes on any
  resolution: escape, swap, junction, series, and the
  multi-stop node must each answer "how would this draw?" with
  answers a reader cannot confuse. The theme replaces the algebraic
  burden with a legibility burden; it does not remove the burden.

## The wire-order geometry (intermediate conversation, 2026-08-15)

This section records the intermediate geometry investigation that came
after the co-flow conjecture but before the `%Cell` / complement-flow
account above. Its wire-order, payload-position, and series-parallel
observations remain useful. Its ontology does not: Path (A)'s claim
that complement flows are structurally unavailable and Path (B-mixed)'s
`[a, ~A]` lean both assumed that the case cell itself had to be an
ordinary flow. The later `%A` distinction removes that assumption:
`(a, %A)` is the cell, while `~notA` is a derived option projection.
Read the section as a record of the pressure that motivated the new
sigil, not as the current resolution.

A same-day continuation went below the construct inventory to the
drawing conventions themselves, and found that the polarity
distinction can be made *positional* — read off wire order rather
than legislated. Everything in this section is exploratory: one
path was rejected structurally, the other became the intermediate
lean in one of its two forms, and nothing was adopted.

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

### Path (A): complement flows — the intermediate rejection

First path considered: turn case flows back into regular flows by
making the flow wire represent the case *complement* — wires named
`~Success` and `~Error` with the error payload in the `~Success`
flow and vice versa. Rejected in-conversation, and not on
confusion alone (though the names lie): **the complement of an alt
is not an alt.** For {A, B, C}, the wire representing A's
complement fires on B-or-C, and its payload is a packed sum of B's
and C's payloads — the partial-collect merge as a mandatory
bottleneck at every case split, before anything is even consumed.
Under the old assumption that the complement flow itself must carry
the complement payload, Path (A) is only definable for two-cell
bundles without packing. The later `%Cell` account rejects that
assumption: `~BC` is an absence rail derived from `%A`, not a carrier
for B and C's payloads. The rejection is recorded as history, not as a
current constraint.

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
port, two distinct value wires, both visible. (B-mixed) was the
intermediate lean; it is superseded by the separate `%Cell` category.

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

## The accident boundary and the jog (conversation, 2026-08-16)

A third conversation took the series-priority result and asked what
duty it imposes on the drawing, and along the way settled a lean on
what `%Cell` costs the representation.

### Cells as ports on the split (representation lean)

The `%Cell` account may cost less structure than it first appears.
The current `Program.res` Case uncollect already exposes a per-alt
value port and a per-alt flow port; the cell account keeps that
shape — per alt, a value port (the payload) and a **cell port**
(`%A`) — and makes the complement option flows (`~BC`, `~AC`, `~AB`)
*derived ports on the same node* rather than free wires. Under that
reading the correlation constraint stated above ("an elaboration must
retain the originating bundle so that separately routed complement
flows cannot be recombined as though their occurrences were
unrelated") is structural rather than enforced: every consumer of a
complement flow traces to the one split node, which is exactly what
the ports-first representation provides everywhere else. The open
decision reduces to *who may consume a cell port*: if only cell-aware
operations may (case-cell commute, collect branches), with everything
flow-like passing through a derived complement port, then adoption
costs a port-kind tag plus a Check rule — not a third reference
category threaded through Context, Check, and Codegen. The
alternative — `%A` travelling the graph as a genuinely new ref kind
beside `ValuePort` and `FlowPort` — remains possible but should be
taken only if the node-local reading fails somewhere concrete.

### Series priority is a trap, not a rarity

Earlier rounds deprioritized the series form on frequency ("priority
termination is rare enough that it is not being optimized for"). This
round reframed the question: frequency ranks what must be effortless;
it never licenses an accident. Series priority is exactly the kind of
tie `end-when-design.md` already refuses to let be an accident, and
the duty holds however rare the deliberate use is.

The beginner case does not even need case cells. A list computation
in which two operations can fail gives two error flows; commuting
both out of the list, one after the other, looks like the innocent
way to "move both out," and a beginner will read it as *handle
whichever error first causes the computation to fail*. The actual
semantics is priority: even after the second error kind occurs, the
loop keeps running to see whether the first kind ever occurs.

Two aggravations give the trap teeth:

- **The cost is not just the wrong winner.** The series form keeps
  traversing past the first subordinate-error occurrence — extra
  work and repeated side effects on an effectful walk. On an
  unbounded stream it is a **hang**: the second commute needs "the
  dominant error never occurs," a fact a stream can never establish.
  The stream case is therefore not merely illegible but
  unanswerable, and the lean is that `Check` should witness a
  shortening commute whose subject is the survivor of another
  shortening commute *over an unbounded stream* as ill-formed
  outright. Legibility carries the finite case; the genuinely
  dangerous case should simply not be a legal program. *(Lean
  retired 2026-08-16: a termination concern, not ill-formedness —
  see "The stream lean retired". The election rule covers the
  signature uniformly instead.)*
- **Independent exits can tie.** The barrier note above leans on the
  exits being cells of one bundle ("they can never tie at a
  firing"). Two error flows from two *different operations* can both
  fire on the same element, so the coordinating node for the
  beginner's actual program needs a same-element tie policy the
  record has not yet specified. The barrier cannot be the safe
  default gesture for unaligned exits until it has one.

One comfort from the inference section stands: a beginner writing
the *time-travel* form — routing both rails out and handling "the
failure" — hits an alternativeness-demanding consumer and gets the
barrier inferred. The trap is specifically the author who draws the
two commutes explicitly, believing each is an innocent local step.

### Where the illegibility actually lives

Series and junction are already structurally distinct — the second
series commute's subject is the first's survivor output (`~L2`), not
`~L` — so no checker ambiguity exists. The illegibility is that **a
wire passing through a node reads as the same wire continuing**,
while `~L2` is a conditional flow: a stretch that exists only while
the dominant exit stays silent. The priority meaning is invisible
because the shortening is invisible.

Nor can the nesting be drawn spatially: it lives in *outcome space*
(the walk-level `A + (B + List C)`), and the loop's geometry has no
region meaning "inside the no-A alternative." Wire order could carry
it (outermost-leftmost), but only via the global semantic-wire-order
commitment the intermediate conversation records as a worry. A local
mark is the honest carrier.

A **subordination arrow** was worked first: an arrow along the flow
wire from the subordinate commute to the dominant one, read "unless
that ever fires," required by `Check` so that the flat unmarked
series chain is ill-formed — an election marker, so priority cannot
be drawn without confirming it. Superseded in the same conversation
by the jog below, which carries the same content geometrically and
generalizes; recorded here so the arrow is not re-derived.
*(2026-08-16: the arrow's election role returns — the fourth
conversation adopted an election requirement for the flat series
chain, with the restriction-adapter candidate as the arrow reborn
as required structure; the jog remains the legibility carrier.)*

### The jog

The lean: **a commute that may shorten the iteration jogs the flow
wire laterally at the commute node; a firing-set-preserving commute
draws straight through.** Commuting IO out of a list reorders effect
context but every element still runs — same firing set, same flow,
straight wire. A first-witness case commute makes the survivor
conditional — genuinely a different, shorter flow, and the jog is the
honest drawing of that. The criterion is semantic, not stylistic:

> **Jog iff the output flow's firing set may be a proper subset of
> the input's.** Visually "same wire" must mean semantically "same
> firing set."

What the convention buys:

- **Priority depth is cumulative displacement.** Two shortening
  commutes in series leave the wire visibly two steps off the
  original list line; the junction form draws one split point with
  one jog per branch. Series and junction discriminate at a glance,
  which is the countervailing duty's demand.
- **One convention, several clients.** End-when's cut flows and the
  prefix-preserving commute's before-cell flow have the same
  character — wires that look like their ancestor but may stop
  early. The same jog serves all of them; the arrow is not needed
  and the gesture inventory stays small.
- **It survives Cross.** The jog is local to a node — "offset from
  what it was before this node" is meaningful per branch — so it
  does not require the global total wire ordering that open
  question 11 warns against.

What the convention demands: the shortening bit must be readable off
the lifting-law inventory (open question 2), and it is
**per-policy, not per-construct** — a first-witness law shortens
while an all-witness variant traverses fully — so each law's entry
must declare it. That is useful pressure: the drawing forces the
inventory to be explicit about short-circuiting.

What the jog does not do: it is editor-drawn, so it makes the
priority reading legible without being an *election* — an inattentive
reader can still miss a subtle offset. That is accepted for finite
flows under the drawn-not-algebraic posture (legibility is the
promise, not enforcement); the case where inattention is dangerous
rather than surprising is the stream hang, and that is handled above
by ill-formedness, not legibility. *(Superseded 2026-08-16: the
fourth conversation resolved 12(b) the other way — the flat
unmarked series chain is ill-formed everywhere without an explicit
election, uniformly across flow kinds, and the stream lean is
retired as a termination concern.)*

## The election rule and the barrier's expansion (fourth conversation, 2026-08-16)

A fourth conversation asked how to make the series trap harder to
draw, and ended with this round's first adopted content: an
election rule for stacked shortening, the retirement of the stream
ill-formedness lean, and an account of the coordinating node as a
fused composition of existing vocabulary rather than a new
primitive.

### Why other languages do not have this trap

Background established on the way in, kept because it locates the
trap precisely. Exceptions, failure monads, and effect handlers
(Koka, Effekt) all avoid the priority surprise by one shared
property: propagation is an **event on a single shared execution
clock**, interleaved with the iteration itself. Abort discards the
rest of the computation, so at most one failure fact is ever
observed per run — the "second" error never comes to exist, and
"which channel wins" has a forced answer: whichever happened.
Exceptions and failure monads additionally pack every error kind
into one channel (the unwinding mechanism, discriminated by type
at the catch; the monad's single error type) — the sum bottleneck
this language refuses — so first-A-or-B is the only expressible
thing. Koka and Effekt have genuinely unbundled per-effect
channels, the closest neighbours to this language's wires, and
still get time order, because `raise` is a control transfer at the
moment of failure: handler nesting shapes the result type but
never selects among errors, since the losing error's occurrence is
simply never reached. Two abort-only monad-transformer layers are
the same degeneracy — a single stacked traversal stops at the
first failure of either kind, the layer order surfacing only in
the result's nesting.

What is different here: the commute is the **distributive law**
(`sequence`), not `bind` — a whole-flow quantifier over a flow in
which failures are latent data, not a control event during its
traversal. Two commutes are two nested quantifiers; both
whole-flow facts get to exist structurally, so something must
choose between them, and composition order chooses silently.
Haskell contains the same program (`fmap sequence . sequence` —
the monadic worked example above) and avoids the trap only
idiomatically: nobody propagates by distributive law there. Here
the commute *is* the propagation primitive, so the priority form
is the innocent-looking default. A single commute diverges from
the other languages not at all — first-witness sequence of one
error flow is exactly time-ordered. The divergence begins at two
channels, which is where the others pack, and this language, by
the no-bottleneck principle, cannot.

### Two limitations examined and rejected

The conversation first evaluated two candidate restrictions on how
error flows may be used, both rejected — recorded in place,
reason-focused.

**Linearity (the IO analogy).** Rejected: wrong axis. The IO
handle is linear because it names a single-threaded resource
(`effects-design.md`), but that is not why series IO commutes are
harmless — IO commutes are firing-set-preserving (the jog
criterion: they draw straight through), so stacking them composes
innocently. The trap is a property of *shortening*, and the
consumption count points the wrong way: the series chain is the
**linear** composition (`~L` consumed once, `~L2` once), while the
legitimate junction form is the nonlinear one (`~L` consumed
twice, as multi-close does). A linearity restriction on error
flows would outlaw the correct program and leave the trap
standing.

**Handling mints a control wire.** The candidate: a handler does
not discharge the error flow but transmutes it into a universal
control-flow wire that, like IO, lacks collect and nonlinear
consumers, so two independently commuted-and-handled errors leave
two wires nothing can finish. Rejected on four grounds. (1) It
acts at the handlers, downstream of where series and junction
diverge, so it cannot discriminate them: with no combiner for two
control wires the legitimate junction form dies too; with a
"both completed" join (linear, hard to refuse) series completes
again. (2) The common case pays for the rare trap: per-element
result-or-default recovery — no commute anywhere — would mint a
control wire per firing that must thread out of every enclosing
loop. (3) It breaks graceful expansion: adding a fallback to one
deep operation ripples a new threaded wire through every enclosing
structure. (4) It fails the ontology lens: the IO handle earns its
threading by *being* a single-threaded resource; a post-handling
token whose only meaning is the restriction it imposes is a
bureaucratic wire — and it erases the handled-means-gone property
besides.

### The election rule (adopted)

> **A flow wire representing an iteration, once shortened by a
> commute, cannot be shortened again by a commute without an
> explicit election.**

The rule carves at the joint the trap actually occupies: the
commute is the only **implicit** shortener — the one construct
whose shortening is a side effect of a node whose drawn job is
transposition, which is why a wire through it reads as the same
wire continuing. End-when's cut is a drawn node whose entire job
is stopping; stacking end-whens is visibly two cuts, the election
already on the page. So the rule is not "shortening may not
stack": mixed chains stay free (an error commuted out of an
end-when-shortened flow is the ordinary first-error-before-the-
stop), firing-set-preserving commutes stack on survivors without
restriction, and junction and single commutes are untouched. Only
the survivor-of-a-shortening-commute, shortened-again-by-a-commute
signature demands the election.

The election's concrete form is the remaining open piece, with two
candidates. The structural one: refuse the ancestor-aligned
operand admission (the end-when stacking rule, whose second client
the series form is — noted there) for a shortening operand
consulted on a shortened survivor. Then `~B`, aligned to `~L`, is
simply not a well-formed operand against `~L2`, and priority
requires an explicit restriction node re-deriving the operand
against the survivor — the third conversation's superseded
subordination arrow reborn as required structure rather than
decoration. The alternative is a bit on the second commute node:
smaller drawing, but a bespoke `Check` rule. Checked against the
formulaic error facet, the stricter alignment costs nothing: one
error out of nested loops is exactly aligned at every step (after
the inner commute the survivor outcome is per-outer-element), and
the two-error junction form takes `~L`-aligned operands on `~L`
itself — only the series chain trips the rule.

This resolves open question 12(b) toward election: the jog remains
the legibility carrier, but the flat unmarked series chain is
ill-formed, not merely subtle.

### The stream lean retired (adopted)

The third conversation's lean — `Check` witnessing the series
signature ill-formed outright over an unbounded stream — is
retired as a termination concern that crept into a polarity
problem. The unanswerable question there ("does the dominant error
ever occur?") has the same character as a single full collect over
an endless stream, or a find that never matches, and nobody
proposed witnessing those; whether it resolves is a termination
fact about the *particular* stream, invisible to well-formedness
(streams can end — `Stream` is structurally `List` pulled on
demand). With the election rule in place the case needs no special
severity: an *elected* priority chain over a stream that never
ends diverges the way any demanded-but-never-resolved program
diverges. The rule is therefore **uniform across flow kinds** —
one clause, no per-kind severity tiers. The lifting-law
inventory's shortening bit is still owed per law: the jog reads
off it, and now so does the election rule's trigger.

### Ties: priority within a firing, not across the walk

The barrier note's owed same-element tie policy (unaligned exits —
two error flows from different operations can both fire on one
element) resolved against the worry that any tie priority
recreates the accident. The discrimination: series order sets
priority **across the walk** — it reverses time, a B at element 2
losing to an A at element 5, at the cost of silent extra
traversal. A tie policy at the coordinating node sets priority
**within one firing** — consulted only where temporal order has
genuinely run out, with no traversal cost and no hidden nesting.
And a selection is forced, not optional: the node's output must be
a disjoint case bundle (alternativeness is what licensed the node
in the first place), so some order must decide, and node-local
operand order is the visible one — already content in this
language (series order is content, subtraction's operand order is
content), node-local like the jog so it survives Cross, and
dormant for aligned exits (cells of one bundle cannot tie). Fine
print, not an objection: operand order answers *who wins a tie*;
*what counts as a tie* for exits from different nesting depths is
a position-comparison question in series-parallel context, owned
by `Poset.res`. The policy decomposes: tie predicate from the
poset, winner from the order.

### The barrier is join → commute → split

The adopted account of the coordinating node: it is not a new
primitive but the fused composition **join, then commute, then
split**, where the join is the disjoint-union variant. For nested
errors the operation is

```
Either A (Either B c)  ≅  Either (A+B) c
```

— a lossless isomorphism, monadic join control-flow-wise but
stronger than Haskell's `join` in exactly the right direction:
Haskell's conflates the two layers' errors when the types
coincide; this one keeps provenance, which is what the downstream
split needs to recover per-cell handlers, and is exactly what open
question 9 already demands of structural join. The barrier's
machinery and the compact joined-rail's machinery are the same
machinery; question 9's identity-preservation requirement becomes
load-bearing rather than speculative.

The composition genuinely yields time-ordered disjunction, and it
respects the first conversation's theorem: time-ordered
disjunction is inexpressible by any composition of *commutes* —
and join is not a commute. Merging first collapses two channels
into one, so there is one quantifier and one first-witness cut, at
the first firing of the union. The first conversation's demoted
merge-before-commute ("a valid program, not the door") is hereby
elected as the barrier's *expansion* — which also locates where
the missing expressiveness always lived: in the pre-commute merge,
not in any cleverness at the commute.

**The dependent case falls out of the existing formula.** When the
second failable operation consumes the first's output, `~B` is
minted inside `~A`'s success context — the nesting exists in the
dataflow before anyone decides anything, and the priority can only
validly go one way, which join's outer/inner asymmetry transcribes
rather than chooses (per element, at most one of the two can fire;
there are no ties at all). Tracing both rails out, `~B` crosses
`~A`'s error nesting (join inserted) and the joined rail crosses
the loop (one sequence inserted): the compact facet's published
expansion, applied mechanically, *is* the composition. The common
case — sequenced failable operations, the monadic chain shape —
was already correct under the existing rules.

**The sibling case is where the election lives.** For two
independent operations per element there is no dataflow nesting;
wrapping B inside A's success is a fiction (B's operation ran even
on A-failed elements), and choosing which cell is outer is an
election — the tie policy above, now with an ontology: not a
tie-break bit bolted onto a node but *which layer wraps which*,
the asymmetry `Join({outer, inner})` already carries. Ties fold
into the outer cell and the inner's payload on that element is
dropped, forced by the output shape (`A+B` has no both-cell) and
consistent with every exception system. An author who wants
both-fail *observed* is writing a different program whose shape
the record already owns: the sibling-opens Cross's both-fired
cell. The residue of real design work is here: for siblings the
joined rail is the complement of the both-success region that
`Complete`'s Cross describes, so the sibling join's expansion must
be stated against the Cross rather than against nesting.

**Consonance with the election rule.** The composition contains
exactly one shortening commute — join is firing-set-*merging*, not
shortening; the split is downstream of the walk. So the barrier
never triggers the election rule, while the series form always
does, and with no barrier-specific legislation the two programs
come out: *merge your channels, then shorten once* — unmarked,
free, and time-ordered; *shorten twice in series* — marked,
elected, and priority. The safe program is the unelected one and
the trap is the elected one, purely as a consequence of counting
shortenings. The jog agrees: one lateral displacement versus two.

**The bottleneck reconciliation.** The first conversation demoted
merge-before-commute partly because it packs — "the partial-collect
merge packs a sum to pass a structural point and breaks the
unbroken per-case wire from source to handler." The
abstraction-is-source-of-truth principle answers the objection:
the no-bottleneck principle governs the **author's wires**. The
drawn barrier keeps per-cell wires in and per-cell wires out;
join-commute-split is the derived lowering, shown faint like every
completion, and the disjoint union exists only inside it. An
information-preserving internal pack is an encoding, not a
bottleneck — and the losslessness above is the exact condition
under which that claim holds. "A valid program, not the door"
stays true: the author never draws the pack; the expansion spells
it.

## The lifting-law inventory: a drafted table (2026-08-16)

Status of this section: **exploration, nothing adopted.** This is a
drafted answer to open question 2, prepared for that question's
design conversation — not a conversation record. Everything in it is
derived from results the record already carries (the owned-order
criterion, the serializer taxonomy, the collect family's
availability ladder, the drain law, the election rule), and the one
genuinely new move — the licensing claim — is a candidate for the
conversation to accept, amend, or reject. Where the derivation
strains, the strain is flagged rather than smoothed.

### What a law must state: the entry schema

Question 2 asks per enclosing flow kind: does it support case-cell
commute, with what witness policy, what context retention, and what
shortening bit. Working the List law backwards gives the schema an
entry must fill. A lifting law mints **one cell pair and up to two
flows**:

1. **The lifted cell pair.** The selected cell at the wider scope
   (`%A` now meaning "at least one occurrence was A") with its
   witness payload, and the complement cell (`%B` now meaning "all
   occurrences were B").
2. **The survivor flow** — the complement-conditional remainder the
   complement cell's evidence is collected off (`~L2` for the List
   law: exists only if no A occurred; its order inherited from the
   enclosing flow). The aggregate evidence itself is *not* part of
   the law: the author collects the survivor flow with ordinary
   collect vocabulary, so the whole-flow "all B" fact is the kind's
   plain collect and richer readouts follow the collect family. The
   **empty-flow question** resolves the same way: every law selects
   the complement cell vacuously on an empty flow, and what evidence
   exists there follows the availability ladder of whatever collect
   is wired (a list collect has its identity `[]`; a semigroup
   reduce is option-shaped — `collect-family-design.md`).
3. **The before-cell flow** (optional) — the retention output: the
   shortened flow of complement-valid context traversed before the
   selected occurrence, if the law can mint one.

Plus two declared bits per **policy** (not per construct): the
**shortening bit** — may the survivor flow's firing set be a proper
subset of the input's — which the jog reads and which arms the
election rule's trigger; and the **selection policy** itself (which
occurrence supplies the witness), with one policy canonical per kind
and the others drawn as different programs.

### The licensing claim: witness selection is an order demand

The proposal this draft is organized around:

> **A first-witness (or last-witness) lifting law is available
> exactly where the enclosing flow's firings carry an owned total
> order** — the owned-order criterion of
> `delay-ontology-design.md`, acquiring its second client.

"First A" is an order read, the same species of read as the Delay's
"previous firing": both demand that some construct *drew* a total
order on the flow's firings, not merely that one happens at run
time. The incidental-order argument transfers verbatim: selecting a
first witness by an unowned order would let a program observe the
scheduler (concurrent bodies before settle), the lowering
(saturation's member walk — naive and semi-naive would become
different programs), or the runtime's cutoff schedule (the var's
recomputations). A register is a reader of order; so is a
first-witness commute. One criterion, two clients — and the kinds
table cashed there transfers row for row, which is what keeps this
inventory derived rather than legislated.

The claim decomposes a lifting law into three separately-discharged
demands:

- **Selection** needs an owned total order (first/last). All-witness
  selection needs no order at all — there is no selection — and an
  **elected witness** substitutes drawn structure for order (below).
- **Aggregation** (the complement cell's evidence, and all-witness's
  gathered As) needs only the kind's own collect vocabulary —
  ordered kinds collect into sequences, unordered kinds into
  sets/keyed lanes, and no order demand enters that the wired
  collect doesn't itself impose.
- **Retention** (the before-cell flow) needs the order *and* the
  availability guarantee: a prefix is an order notion — "traversed
  before the selected occurrence" — so a kind without owned order
  has no before-cell flow to mint, not merely an inconvenient one.

One observation the List law conceals, recorded because the
completions row forces it: **selection order and presentation order
can differ.** The List law reads one order (walk order) for both;
the completions flow selects in settlement order, while the familiar
field shape (results delivered in subject order — `Promise.all`)
re-presents completions by their subject correlation. The
re-presentation is drawn downstream off the completion's carried
subject identity; it is not part of the law. An entry names the
flow's *own* owned order and nothing else.

### The table

Rows follow `delay-ontology-design.md`'s kinds table; "witness"
abbreviates first/last-witness availability. Canonical policy per
supporting kind is first-witness; last-witness, join-of-witnesses,
and all-witness are lawful drawn variants (different programs, per
the scope-lifting section).

| enclosing kind | order | witness | before-cell flow | shortening (canonical) |
|---|---|---|---|---|
| finite list walk | owned (walk) | yes | yes | yes |
| segment / filtered sub-flow | owned (inherited) | yes | yes | yes |
| stream (pulled) | owned (walk, on demand) | yes | yes (a stream) | yes |
| async stream | owned (arrival) | yes | yes | yes |
| event stream (`changes`) | owned (arrival) | yes | yes | yes |
| completions flow | owned (settlement, minted) | yes | yes (settlement order) | yes — ceases demand on in-flight work |
| case / option, bare; async value; race settlement | degenerate (≤1) | degenerate | none (no traversal) | n/a — the crossing is the join |
| var (recomputations) | incidental | **no** | no | — |
| concurrent bodies (pre-settle); sibling instances; saturation members; unordered exchanges; the frame flow | none | **no** — all-witness or elected only | no | off (all-witness) |
| product {X, Y} | surplus | **no** as spanning — per-axis fibered instead | per axis | per axis |
| IO / effect handle | a wire, not a flow | — | — | — (the IO *flow*'s sequencing commute is firing-set-preserving: bit off, never arms the election) |

Per-family notes, in table order.

**The ordered iterated kinds** (list, segment/filtered, stream,
async stream, `changes`) share one law family — the worked List law.
The policy menu: first-witness (canonical; shortens; jogs; arms the
election trigger), last-witness and join/collect-all-witness
(traverse fully; bit off — establishing "last" or "all" demands
exhaustion, so nothing shortens). The distinction between the eager
and on-demand rows is **not** a law difference: `Stream` is
structurally `List` pulled on demand, and whether the universal
remainder ("all B") is ever established over a particular unbounded
flow is a termination fact about that flow, invisible to
well-formedness — the fourth conversation's adopted retirement of
the stream lean, which this table therefore never mentions again.
The first-witness law over a stream is partly *implemented*: the
sequence commute (`Codegen.emitSequenceCommute`,
`stream<option<X>> → option<stream<X>>`, short-circuiting at the
first absence) is this law's compact option projection, with the
complement evidence delivered as a stream and an absent option
abandoning the rest — a working model for what the before-cell flow
of an on-demand kind looks like (it is itself a stream). For
`changes` and the async stream the order is arrival; endings are
reason-only per the async round, so the complement cell's evidence
collects exactly as the eager twin's does when the flow ends.

**The completions flow** is the family's most instructive row
because settle *minted* its order — the serializer taxonomy's
paradigm. First-witness there is first-failure-in-settlement-order:
the field's fail-fast gather (`Promise.all`). The shortening bit is
set, and its operational content is kind-specific while the bit
stays the same: shortening an eager walk stops traversing;
shortening a completions flow **ceases demand on in-flight bodies
and never starts the unstarted** — delivered as `Cancelled` over the
necessity frontier, exactly `cancellation-design.md`'s account, with
the bounded drain governing what the survivor flow still fires. The
complement cell's evidence ("all bodies settled Ok") exists at the
drain, per the drain law. The before-cell flow is real and useful —
the completions that settled before the first failure, in settlement
order: the partial-results readout. Subject-order presentation is
the drawn re-indexing noted above, not law content.

**The degenerate kinds** (bare case/option, the async value, a
race's settlement) have at most one firing, so first = last = all
and there is no quantifier to apply: **the crossing operation for a
degenerate layer is the join**, the fourth conversation's
disjoint-union, provenance-keeping
`Either A (Either B c) ≅ Either (A+B) c`. This row is where the
error facet's formulaic rule — "crossing an enclosing loop inserts
sequence, and crossing error nesting inserts monadic join" — turns
out to be the inventory read at its two poles: iterated kinds supply
quantifying lifts, degenerate kinds supply the join, and the
formulaic rule is the two families named in facet shorthand. Join is
firing-set-merging, so this row never arms the election rule —
consonant with the barrier expansion containing exactly one
shortening. For the async value specifically, the revised failure
account already places the Ok/Err bundle *on the arrival*, so there
is nothing further for a lift to do that the arrival's own case
bundle doesn't already say.

**The incidental-order row** (the var flow proper) supports no lift
for the register's own sharper reason: quantifying "did any
recomputation produce A" would make the cutoff schedule observable.
The lift belongs on `changes`, which is the same relocation the
incremental round already performed for its register — the criterion
predicting, not merely permitting, where the construct lives.

**The unordered kinds** (concurrent bodies before settle, sibling
divide-flow instances, a saturation round's members, an unordered
facet's exchanges, the frame flow) get no first-witness law — that
is the licensing claim doing its work. What remains is real,
though:

- **The all-witness lift** is available, because it makes no
  selection: `%A` at the wider scope means "at least one member was
  A" with *all* the A evidence aggregated by an unordered collect
  (set, keyed lane, commutative reduce). Structurally this is the
  junction filter pair re-presented as a case bundle keyed on
  emptiness — which is why it costs no order. Its bit is off:
  establishing the complement means exhausting the members
  (saturation: the round completing; concurrent bodies: the drain
  after settle mints order anyway, see next).
- **The elected witness** substitutes drawn structure for owned
  order: mint the order first, then lift downstream of the mint.
  Settle is the paradigm — "first failure" over concurrent bodies is
  not drawn on the body flow at all but on the completions flow,
  downstream of the serializer. The remedy string for a first-witness
  demand on an unordered flow is therefore the serializer taxonomy's:
  **draw the order-minting construct, then commute** — the same
  shape as order-demand's "fold one axis, or Join first," and the
  same rule as "a register is legal exactly downstream of the point
  where order becomes owned."

**The product** is the surplus cell here exactly as it is for the
register: a lift spanning the whole grid demands *one* order and
every axis order is real with none privileged. Per-axis lifting is
ordinary and fibered — commuting a cell out of one axis yields the
List law per fiber of the others (a flow of lifted case bundles over
the surviving axes) — and a genuinely spanning lift rides the
linearization residue's orientation-pinning, owned by
`product-linearization-design.md`. Nothing new is legislated: the
row inherits the surplus classification and its remedies.

**The IO handle** is not a flow, so it takes no lift; the row exists
to keep one prior result adjacent: the IO *flow*'s sequencing
commute out of a list is a flow commute with the shortening bit off
(firing-set-preserving, draws straight through) — the fourth
conversation already used exactly this fact to show series IO
commutes compose innocently. Where an op's *outcome* case-splits,
that is failure vocabulary on the op, and the lifting question
re-enters through whichever iterated kind encloses the op — not
through the handle.

### The election trigger, read off the table

The adopted election rule wanted the shortening bit "readable off
the lifting-law inventory." Read off this draft: the bit is set
exactly on the **first-witness rows of the owned-order kinds** (list
and its restrictions, stream, async stream, `changes`, completions),
and on nothing else — all-witness variants, the degenerate join, IO
sequencing, and unordered all-witness lifts all leave it off. The
election signature is any two bit-set laws stacked in series on one
wire, uniformly across kinds, which is the rule's one clause with no
per-kind severity — the table adds nothing to the rule, it just
makes its trigger enumerable.

### Open edges of this draft

Named for the conversation, in rough order of bite:

1. **The licensing claim itself.** Adopting it makes the owned-order
   criterion load-bearing for a second construct family. The
   alternative — a per-kind legislature that happens to agree with
   the criterion today — should be explicitly considered and, if the
   claim is right, rejected for the usual reason (two tables drift;
   one criterion cannot).
2. **The witness-free short-circuiting existential.** Over an
   unordered kind, "stop as soon as any A appears, payload
   undemanded" observes no order in its *result* — but the work
   performed becomes schedule-dependent, observable through effects.
   The lean consistent with the record: ceasing work once the fact
   is established is demand structure (laziness/cancellation
   territory), not law content — the law's bit stays off, and any
   *demanded* witness payload re-imposes order-or-election. Not
   worked; flagged.
3. **Retention's fine print per kind.** The before-cell flow's
   geometry is open question 4 for the List law already; this table
   adds that for on-demand kinds it is itself a stream (the
   implemented sequence commute models it) and for the completions
   flow it is in settlement order. Whether one geometry serves all
   owned-order rows or the eager and on-demand presentations differ
   belongs to question 4's resolution.
4. **Last-witness has no client.** No program in the record demands
   it; it is listed because it is lawful, not because it earns a
   drawing. Candidate for dropping from the canonical menu until a
   client files — the inventory's countervailing duty is to stay
   small.
5. **The elected witness's concrete form.** Settle-then-lift is one
   election; whether an unordered kind admits a lighter drawn
   election (an operand-order pick at a node, like the tie policy)
   without re-importing the incidental-order accident is unexamined.

## Open questions

1. **Adoption and propagation.** The `%Cell` / complement-flow account
   is worked here, not yet propagated through the owning docs or
   adopted as a repository-wide decision. `open-problems.md`, the core
   model, the failure round, the crossing round, and the time-travel
   completion boundary all need reconciliation. The earlier
   symmetric `(value, flow)` bundle account is superseded.
2. **The lifting-law inventory.** Define which enclosing flow kinds
   support case-cell commute and the evidence transformation each one
   supplies. Finite ordered List has first-witness-or-all-remainder
   and may retain complement-valid prefix wires. Specify whether each
   law discards, exposes, or can optionally expose that context.
   Stream cannot generally establish the universal remainder;
   unordered, parallel, async, and incremental flows each need an
   explicit selection, aggregation, and context-retention policy.
   Each law's entry must also declare its **shortening bit** — may
   the output firing set be a proper subset of the input's — since
   the jog convention reads the drawing off it, and the bit is
   per-policy (first-witness shortens, all-witness does not), not
   per-construct. (2026-08-16: the shortening bit also arms the
   election rule's trigger; and a law's inability to establish the
   universal remainder — Stream — is a termination fact about the
   particular flow, not ill-formedness.) *A drafted table now exists
   (§"The lifting-law inventory: a drafted table" — exploration,
   unadopted): entry schema (cell pair, survivor flow, before-cell
   flow, per-policy shortening bit), the licensing claim (witness
   selection is an order demand — the owned-order criterion's second
   client), the per-kind rows, and five named open edges. The
   question stays open until that draft's conversation.*
3. **The exact compact-facet expansions.** Sequence and monadic error
   join have candidate lifts above. Enumerate every edit the compact
   error facet offers and prove its `%Cell` expansion unique (or name
   the published canonical choice), including several independent
   error sources, several continuation cells, joins across products,
   and a payload requested only after several joined layers.
4. **Prefix geometry and the cut boundary.** Decide whether commute
   mints an explicit before-cell flow, factors collected prefix wires
   outside the aggregate bundle, or uses another readable geometry.
   Determine whether case-derived collect-until is exactly the fused
   prefix-preserving commute, while retaining a broader cut family for
   external terminators, or whether another semantic distinction
   remains.
5. **The multi-cell form's home.** *Resolved (fourth conversation,
   2026-08-16): neither a standalone primitive nor a collect-until
   variant — the fused join → commute → split expansion (see its
   section). The tie policy for unaligned exits is the join's
   outer/inner asymmetry: forced by dataflow for dependent exits,
   elected for siblings, with ties folding into the outer cell.
   Residue: the sibling join's expansion stated against
   `Complete`'s Cross, and the fused drawing itself (per-cell wires
   in and out, the pack internal and shown faint).*
6. **Series commutes collected out of order.** What construct pulls
   the nested outcomes apart into independent closes, if anything.
   Deliberately unworked — priority termination is rare. (Rarity
   still defers this construct, but per the third conversation it no
   longer carries the safety burden for series itself; the jog and
   the stream witness do.)
7. **The inference fine print.** The explicit list of
   alternativeness-demanding consumers (collect branches,
   partial-collect operands, …) that licenses the barrier
   elaboration; plus the precise boundary between a route the author
   elected and a source, sink, observation, or handling intent the
   editor would be inventing. (2026-08-16: the elaboration itself
   shrank — the coordinating node is inserted as join + sequence,
   existing insertion vocabulary; for dependent errors the
   published formula already produces it, so the list is owed
   chiefly for the sibling case.)
8. **OptionIter representation.** The structural option bundle is
   `[(unit, %None), (value, %Some)]`; its projections are
   `[~Some, unit]` and `[~None, value]`. Revisit
   `partial-collect-design.md`'s proposed None flow port in these
   terms: is it displaying `%None`, the complement flow `~None`, or a
   derived projection? The new sigil makes that distinction mandatory.
9. **Joined payload preservation.** Specify the hidden representation
   of a compact joined `~Error` rail. It must retain enough cell
   identity and value association for a later facet expansion to
   recover the distinct handlers, while the explicit final DidFail
   consumer remains free to forget all of them. (2026-08-16: now
   load-bearing — the barrier expansion routes both cells through
   the disjoint-union join, and the downstream split's recovery of
   per-cell handlers is exactly this requirement; the join is a
   lossless isomorphism, `Either A (Either B c) ≅ Either (A+B) c`.)
10. **The multi-depth example.** Draw two commuted cells from different
    nesting depths plus a continuation cell, with complement-prefix
    wires live at both levels. Check that outward cell placement,
    witness payloads, and before-cell flows remain readable rather than
    tangling. This preserves the intermediate conversation's concrete
    leftward-growth test under the current ontology.
11. **Case-cell geometry under Cross.** Re-derive cell commute and
    complement-prefix retention in series-parallel context
    (`Poset.res`). “Left of” must generalize to “on the outward side
    of” independently per branch; no semantic rule should depend on an
    arbitrary total ordering of parallel wires. (The jog is one
    partial answer: being node-local, it needs no total order — but
    the re-derivation of the rest still stands.)
12. **The accident boundary.** *Resolved (fourth conversation,
    2026-08-16).* (a) Dissolved — the stream ill-formedness lean is
    retired as a termination concern that crept into a polarity
    problem: unanswerability is a fact about the particular stream
    (a full collect of an endless stream has the same character and
    is not witnessed), invisible to well-formedness. (b) Resolved
    toward **election**: the flat unmarked series chain is
    ill-formed everywhere — a flow shortened by a commute cannot be
    shortened again by a commute without an explicit election,
    uniformly across flow kinds. Remaining: the election's concrete
    form — the restriction-adapter node (refusing the
    ancestor-aligned operand admission on shortened survivors; the
    subordination arrow as structure) vs a bit on the node.

## What this touches

- `lazy-stream-commute-design.md` — the implemented sequence
  commute is unaffected as a construct; the taxonomy's word and its
  case-flow generalization are what this problem owns.
- `commute-design-notes.md` — the historical options survey;
  polarity note added to its status.
- `end-when-design.md` / `variable-rate-consumption-design.md` —
  revisit the old unconditional-prefix/conditional-remainder boundary.
  A first-witness case-cell commute may preserve an unconditional
  complement prefix, so case-derived collect-until may be its fused
  presentation. External terminators may still require a broader cut
  family. The multi-stop candidate remains joint work. The jog
  convention proposes one visual identity for *all* shortened flows —
  end-when's cut flows and the before-cell flow included — and
  end-when's refusal to let the termination tie be an accident is the
  precedent the third conversation's trap result extends to series
  commutes. The fourth conversation's election rule conditions the
  stacking admission's commute client (a note is placed at
  end-when's restriction rule); end-when's own stacking is
  unaffected — its cuts are drawn elections.
- `failure-payloads-design.md`, `barrier-value-crossing-design.md`
  — re-found the "short-circuit commute" as the compact projection of
  a case-cell scope lift. A selected Error payload pairs with
  `%Error`; `~Error` is the complement flow of the Success projection.
  Re-state the scoop as expansion/routing of the selected `%Error`
  witness.
- `src/Context.res` / `src/Poset.res` — the left-to-right convention
  spatializes an ordered path; open question 11 asks how the case-cell
  and before-cell-flow geometry generalizes under Cross without making
  an arbitrary total wire order semantic.
- `partial-collect-design.md` — the OptionIter None port
  (question 8); the disjointness demand as the inference hook.
- `core-model.md` / `src/Program.res` — the commute paragraph
  eventually needs the `%Cell` category, complement projections,
  case-cell scope lifting, complement-prefix retention, and the
  error-facet presentation once decided. The third conversation's
  node-local lean would keep `Program.res`'s per-alt port shape (a
  cell port beside the value port, complement flows as derived ports
  of the split node) rather than adding a third reference kind.
- `facets-design-notes.md` — the error facet is the first concrete
  client with an edit-and-expand law, not only a view toggle.
- `time-travel-programs-design.md` — correct the false
  identity-shadow/bookkeeping-only boundary. Inferred sequence changes
  demand and termination; completion is licensed by authored intent
  plus a unique published expansion, not behavioural neutrality.
