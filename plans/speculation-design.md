# Speculation: ordered alternatives with rollback

Status: exploration — this chapter teaches a worked proposal that has
not been adopted yet; everything below is a leaning, not a decision.
None of it is implemented. Read it as "here is a candidate and the
case for it."

**Re-founded (2026-08-14).** The failability substrate was rewritten
onto the 2026-08-04 revisions (`failure-payloads-design.md` and
`end-when-design.md`, revision notes): a contender's success and
decline are the two sides of a drawn case fork — (flow, value)
pairs, not a payload-carrying terminator — the barrier consumes
per-contender pairs (matching race's pairs amendment,
`barrier-value-crossing-design.md`), endings carry reasons only,
and every diagnosis travels a drawn value wire. The
ordered-alternatives core (try in order, rollback by structure,
first success wins) is untouched. Open question 4 (diagnosis
payload) is mostly closed on that account.

## Trying things in order

You will sometimes want a program to try several ways of getting a
result, one after another, and keep the first that works. Parsers
live on this shape: an expression might be a `let` or might be a
function application, so you try to read a `let`, and if that
doesn't fit, you try to read an application *from the same place in
the input*. Search that hits a constraint and backs up to try the
next candidate is the same shape, and so are best-effort fallbacks
("use the config file; failing that, the defaults").

The construct for this shape is called **speculation**: several
alternatives, drawn in order, each of which may fail; the first that
succeeds wins; and the world is restored between attempts, so a
failed alternative leaves no trace. This chapter works out what
speculation *is* — the rule the construct obeys, how that
restoration is expressed, how speculation relates to the race
barrier, what committing to an alternative and diagnosing a failure
look like, and the ladder of variations — and records where its
pieces already live in the design record. The evidence that the gap
is real, gathered from three language-comparison rounds and a field
sighting, is collected in "Where this shows up in real code" below.

## The first example: a `let` or an application

Here is the concrete case the whole design grew from. An expression
is a `let` or an application — in Effekt you would write
`or { parseLet() } { parseApp() }`.

Each alternative is a computation over the input that can end in one
of two ways. `parseLet` reads the current position, consumes some
tokens, and either *succeeds* — producing an AST and an advanced
position — or *fails*: it ends without producing a result. In the
revised failure vocabulary (`failure-payloads-design.md`, revision
notes 2026-08-04) that fork is a drawn case alt, not a special
terminator: a contender presents a success side and a decline side,
each an ordinary (flow, value) pair, and a computation with both
sides is called **failable**. (On the pairing vocabulary: the
case-cell account — `case-commute-polarity-design.md`, Tier-1,
nothing adopted — reads a case alt's pair as `(payload, %Cell)`
with the compact rails derived projections; the contender fork as a
drawn case alt is unaffected.) `parseLet` reads the first token; if
it is not `let`, it fails cheaply — its decline side fires — and
`parseApp` is tried against the *same* position.

```
parseLet:  p -> ...          -- fails if the head token isn't `let`
parseApp:  p -> ...          -- fails if the head token isn't callable
-> speculate => r
~r.parseLet:  r.parseLet -> LetNode
~r.parseApp:  r.parseApp -> AppNode
-~> collect => expr          -- one AST; whichever alternative won
```

`p` is the input position — a value, threaded explicitly. Both
alternatives read it through an ordinary fan-out (a tap). `speculate`
tries them in drawn order, stopping at the first success. What comes
out of it is a **bundle** — a family of sibling flows of which at
most one fires — with one **cell** per alternative. The winner's
result reaches `expr` through its cell; the loser is never run once
the winner succeeds (or, if `parseLet` ran and failed, `parseApp`
reads the unchanged `p`).

## Rollback for free: restoration is structural, not an operation

The delicate property of any backtracking program is *what gets
restored between attempts*. In Effekt it is invisible — decided by
where a `var` sits relative to a handler, so that two programs
differing only in allocation position print different results
(`effekt-comparison.md`, "the comparison's sharpest observation").
In the machine-generated PEG parser sampled in the field it is a
manual `self.pos = _save2` reset, correct only if every mutation is
paired with its restore. Both fail the standard this language holds
itself to: "the drawn structure is trustworthy."

Look back at the drawing above and notice what it does *not*
contain: no save step, no restore step. In a dataflow formulation
there is nothing to restore, because there is nothing mutated. The
input position is an immutable **value**. An alternative that
consumes from `p` produces a *new* position value; the old `p` still
sits on its wire. A failed alternative produced nothing, so its
would-be advanced position reached nothing downstream. The next
alternative reads the same `p` — the same wire — and therefore
starts from the original position by construction.

So restoration is not a feature of speculation. It is an **emergent
property** of three things the language already has:

- **immutable values** — advancing the cursor mints a new value,
  never overwrites,
- **ordinary sharing** — the input fans out to every alternative (a
  tap; `core-model.md`, sharing is opt-in via binding),
- **ordered fallback** — the rule of the barrier, next section.

The save/restore *pairing* that breadth item 6 of the survey wanted
made visible *is* the input wire fanning into the alternatives.
There is no save node and no restore node — the picture shows every
alternative reading the same position, and that picture *is* the
invariant.

jq is the shipped witness that this works: a whole
alternatives-and-failure story on pure value streams with zero
rollback machinery, "because an abandoned alternative is a value
stream nobody consumed further." Its caveat is the thing we supply
that jq lacks: jq owns *no consumed-input notion* (it never parses;
its backtracking is over derived values), so it gets restoration
free by never having a cursor. A parser must thread the position;
the leaning is that threading it as an ordinary value is enough, and
the picture is the better for it.

## The rule speculation obeys

Now the construct precisely. In the language's vocabulary,
speculation is an uncollect on the *sum* side — the "one of several
alternatives" side where case splits live, as opposed to the product
side where independent things are combined. And it is a **barrier**:
a point several wires cross together, each output corresponding to
one input, with nothing packed into an intermediate structure to get
across.

**Form.** Speculation takes N contenders (N ≥ 1), each a **failable**
computation. It is a sum-side multi-input uncollect — the same shape
as a case split and the race barrier — and, like race after its
pairs amendment, its inputs are per-contender **pairs**: contender
*i*'s success side arrives as a (flow, value) pair, and its decline
side as another (`barrier-value-crossing-design.md`, corner 2 and
the revision notes' scoop — the barrier's law selects a contender,
which is what licenses minting the selected pair's value at the
output). Out comes a **bundle of N cells**: cell *i* fires iff
contenders 1..*i*−1 all failed *and* contender *i* succeeded,
carrying contender *i*'s success value as its minted per-cell
output. Exactly one cell fires, or none (all failed).

**Ordering is the primary selection.** Contenders are attempted in
drawn order. Contender *i*+1 runs *only if* contender *i* fails.
This is the axis on which speculation differs from everything
temporal: order is not a tie-break (as it is in race), it is the
whole selection rule. Later contenders are not merely
lower-priority — they are not evaluated at all until earlier ones
have failed, which laziness delivers for free (force contender *i*+1
only when contender *i*'s decline side has fired;
`lazy-compile-design.md`).

**Selection is by success, not settlement.** A contender that
*fails* is passed over. This is why contenders are failable by
construction: the decline side firing is how a contender says "not
me, try the next." A contender's decline pair is consumed **at the
speculation barrier** — wired in there, absorbed, turned into
"advance to the next contender" — it goes nowhere else. Only when
*every* contender has failed does speculation itself end without a
winner; that ending's flow side carries the *reason* (all
declined), and the diagnosis is ordinary data built from the
decline pairs already in hand (see "What a failed parse says").

**Failable by construction.** The contenders' failability is not
optional decoration; it is the barrier's input contract, exactly as
race's contenders are async values. A non-failable contender is a
contender that always wins if reached — a legitimate degenerate case
(an unconditional final alternative, the `else` of the choice).

## Speculation is the race barrier's sequential sibling

Race and speculation are the two sum-side barriers. They share the
form — values in, a bundle of N cells, exactly one fires,
per-contender correspondence, no tagged union packed
(`core-model.md`, "Barriers, not bottlenecks"). They differ on one
axis: **what decides the winner.**

| | race | speculation |
|---|---|---|
| contenders | async values | failable computations |
| all run? | yes, concurrently, in drawn order | no — next only on prior failure |
| winner is | first to **settle** (temporal) | first to **succeed** (ordered) |
| drawn order | tie-break only | the primary selection |
| a "loser" | abandoned in-flight, memoised | never run, or failed and its decline consumed |
| restoration | n/a (independent asyncs) | structural: the shared input wire |

Raku ships both and keeps them distinct: `||` is the speculation
shape (drawn order, try/fail/restore); `|` is longest-token
matching — "all branches notionally raced, the longest wins, ties by
a published law" — which is structurally the race barrier's
law-with-ties, with "longest / most specific" where race has "first
settled" (`raku-grammars-comparison.md`, finding 3). A future round
must not conflate them; Raku needing both is the evidence the
distinction is real. Recorded as dead end 4 below.

## What the flat drawing unfolds into

The barrier's meaning decomposes into pieces the record already
owns. Ordered fallback of two contenders A, B over shared input `p`
is:

> run A(`p`) — success ⇒ output; declined ⇒ run B(`p`) — success ⇒
> output; declined ⇒ the all-declined ending, its aggregate built
> from the declines in hand.

That is A's success/decline fork — an ordinary case split — with B
sitting in the declined alt's continuation, itself forked: a
**right-nested chain of case handlings**, N contenders deep. It is
expressible today from the revised failure vocabulary (one split
per contender, each declined alt containing the next — the same
family as the inferred short-circuit commute,
`failure-payloads-design.md`, revision notes); nobody should author
it, exactly as
nobody authors the mutually-recursive merge/interrupt pair
underneath race (`race-barrier-design.md`, "Merge, interrupt, and
the timeout family"). The flat N-ary drawing is what you draw; the
nested-handling chain is its derived **lowering** — its translation
to a more concrete form — inspectable on drop-down (principle 6:
abstraction is the source of truth, and the concrete form is a
read-only derived view). Whether the flat form is a fresh primitive
barrier or a catalog block over that lowering is open (open question
2) — the same primitive-vs-catalog question race carries.

## Committing, and the everyday mode that never backs up

Most parsing code, it turns out, never backtracks at all.
Ratcheting is Raku's default: `token` and `rule` never back up,
`regex` backtracks, and the docs steer users to the ratcheting
declarators — "most grammar code never backtracks; the speculative
engine is the exception, opted into locally." This is the substrate
leaning made concrete: threaded values everywhere (nothing to roll
back), speculation a *bounded, local* construct drawn exactly where
alternatives-with-fallback is wanted — not a backtracking substrate
under the whole language.

Within a contender, commitment distinguishes two kinds of failure.
Once Raku's tilde `'(' ~ ')' <expr>` has matched the open delimiter,
a missing close is not a non-match — it fires a user-definable
`FAILGOAL` ("Cannot find ')' near position 4"). Mapped onto our
vocabulary, a contender's non-success side has two alts:

- **soft fail (declined)** — no match. Its pair is consumed by the
  enclosing speculation ⇒ try the next contender.
- **hard fail** — the contender committed past a point and then
  could not continue. Its pair crosses on the barrier's own
  hard-fail output, bypassing "try next" ⇒ the whole parse ends
  with that diagnosis; later contenders are **not** tried. Nothing
  propagates unseen: the diagnosis is a value on a drawn wire from
  the contender's minting split, through the barrier's pair, to
  wherever it is handled.

The leaning: a **commit** marker on a contender's chain upgrades
any subsequent fail from soft to hard — the drawn analogue of the
tilde's commitment: it changes which alt the contender's later
fails land on, and thereby which of the barrier's two consumptions
receives them. Both stay drawn; neither is a value the code
inspects. (Commit's exact form — a node, a wire property,
per-contender vs a general marker shared with async — is open
question 3.)

## What a failed parse says

Error reporting is part of the construct's territory, not a layer on
top (`raku-grammars-comparison.md`, finding 3). Two cases; in both,
the diagnosis is a value on a drawn wire, and the ending's flow
side carries only the reason:

- **All contenders soft-failed.** The barrier's no-winner ending
  fires (reason: all declined), and the aggregate — "none of
  {parseLet, parseApp, …} matched at `p`" — is ordinary data
  construction over the decline pairs' values, all in hand at the
  barrier. It is the honest "no alternative matched," and it names
  the alternatives because they are drawn cells.
- **A contender hard-failed.** Its committed diagnosis crosses on
  the barrier's hard-fail pair, bypassing "try next" — the FAILGOAL
  "expected ')' near position 4," which is more specific than the
  aggregate precisely because the contender got far enough to know
  what it wanted.

Which aggregate to build (a list of expectations, a merged set,
furthest-position) is a value-level catalog choice for the parsing
domain — open question 4, the only part of the old
payload-composition rider left after the failure round consumed the
rest (`failure-payloads-design.md`).

## What speculation does *not* need

You might expect a parsing construct to come with machinery for
sequencing ("match this, then that") and for nesting. It needs
neither.

With position-as-value, **concatenation is ordinary chaining.**
Match this, then that, over one cursor is: `p -> matchThis -> p' ->
matchThat -> p''` — each step takes a position and returns an
advanced one, wired forward. No new construct; the position threads
exactly like any value in a chain. This is the natural home of the
rung `raku-grammars-comparison.md` §2 called "the record is
missing" — it is not missing, it is the forward chain, once the
cursor is a value. Speculation is the only genuinely new piece;
commit sits on the chain; failure is failability's — a drawn Error
alt of a case fork, since the `fail` node's dissolution
(`failure-payloads-design.md`, revision notes, 2026-08-04).

**Recursion — nested structure — is the divide flow's**, deferred
here. Recursive descent (nested-delimiter parsing, `'(' ~ ')'
<expr>` with `<expr>` calling back) is recursion over *virtual*
structure: the parse tree exists only as the walk's call structure
until it materializes. That is `trees-and-recursion.md`'s territory
(the divide flow, still narrative-stage;
`tough-use-cases-design.md`, the mergesort limit). The parsing
vocabulary is thus four parts — **speculation** (ordered choice),
**position-threading** (concatenation, ordinary chaining), **commit
+ failure** (commitment and diagnosis — drawn case forks and
value-wire diagnoses, per the re-founding note), and **the divide
flow** (recursion) — of which only speculation is worked here. Recursive
descent is a candidate first program for the divide flow's round
with field precedent (`open-problems.md`, the recursion row).

## When an attempt has real side effects

Pure attempts abandon for free: a failed alternative that only
produced *values* (an AST fragment, a candidate layout) leaves
nothing behind when the next is tried, because values on unconsumed
wires simply go unread. Effekt's pretty-printer resets a mutable
output buffer between attempts; in our formulation the emitted
document is a value per attempt and the reset is free
(`effekt-comparison.md`, finding 3). This is the whole story for
parsing and search over pure input.

An attempt that causes **real effects** (opens a file, writes a
socket) and then fails is a different matter — its effects need
release-on-abandonment, which is bracket and cancellation, the
Tier-1 IO round (`open-problems.md`, Tier 1; `zig-comparison.md`,
`defer`/`errdefer`). Speculation over effectful attempts inherits
that gap whole: the failed contender's discharge is *also* the
trigger to release what it acquired, structurally the same event as
race's lost-cell cancellation trigger (`race-barrier-design.md`,
"Abandonment at the barrier"). Named, not designed — speculation
commits only to needing no new ports for it.

## Building up from the base: the +1 ladder

The complex cases must be reachable from the simple one by adding
structure to the drawing (principle 7: building blocks must build).
Each rung below is an addition over the same bundle of attempts.

- **first-success** (the base) — the priority-first collect over the
  ordered bundle: stop at the first firing cell. One result + one
  advanced position out.
- **+ all-results** — collect *all* cells that fire, to a list,
  instead of stopping at the first. Same bundle, a different
  reconvergence (multi-close-flavored): the ambiguous-parse /
  all-valid-layouts case. Laziness makes the two genuinely different
  evaluations of one drawing — priority-first forces contender *i*+1
  only on *i*'s failure; collect-all forces every contender.
- **+ bounded** — take the first K successes, or bound the search
  depth/width: a `take`-count on the collect
  (`variable-rate-consumption-design.md`, the take family).
- **+ heuristic order** — order the contenders by a computed
  priority rather than drawn order: a comparator wired into the
  ordering, the bridge to the **chooser family**
  (`tough-use-cases-design.md`, item 4) and Raku's `|` (best-match)
  beside `||` (drawn order). This is where speculation touches the
  decision-driven family; its round should take the async merge, the
  ordered merge, and heuristic-order speculation as members of one
  family whose lowerings differ only in what decides the head.

## After the choice: reconvergence and provenance

How do the cells come back together, and how does the rest of the
language check that they are used soundly? Both answers are
inherited from race with no changes (`race-barrier-design.md`,
"Reconvergence" and "Provenance fit"). The covering collect over the
ordered bundle is the exhaustive close — exactly one cell fired, so
it fires once; contenders whose results are differently-typed
convert to a common type in their own cell bodies before the
covering collect, or the output stays a case/sum. Speculation is one
uncollect step in the context path — a bundle of N cells,
ordered-choice discriminator — the same step shape a case split and
a race write; cell sets compare by containment; the mixing check
meets the bundle unchanged. The aggregate failure adds no step
kind — failability is a property of the flow, not of the path.

## Textual sketch (owed)

Mirroring race's lane spelling (`race-barrier-design.md`;
`textual-representation-design.md` owes the real form):

```
p -> | parseLet     -- the shared input, fanned to each contender
     | parseApp
-> speculate => r
~r.parseLet:  r.parseLet -> LetNode
~r.parseApp:  r.parseApp -> AppNode
-~> collect => expr
```

A committed contender writes `commit` on its chain; fails after it
land hard. The advanced position rides out of the covering collect
beside `expr` for the next stage to thread.

The `+all-results` rung is the same bundle with a different
reconvergence — each firing lane joined into a list collect instead
of the stop-at-first covering collect (the ambiguous-parse case):

```
p -> | parseLet
     | parseApp
-> speculate => r
~r.parseLet:  r.parseLet -> LetNode -~> join -~> collect => parses
~r.parseApp:  r.parseApp -> AppNode -~> join      -- same collect, via the joins
```

(Sketch only; the collect-all form forces every contender where
priority-first forces contender *i*+1 only on *i*'s failure — the
laziness difference stated in the ladder.) Exact spellings — the
fan-to-contenders form, `commit`, the two-output (result, position)
collect, the all-results reconvergence, and the aggregate diagnosis
binder — are owed to the textual round.

## Where this shows up in real code

The gap is well-witnessed. Three comparison rounds arrived at the
same shape independently: Effekt's parser and pretty-printer, both
built on `Nondet` (`alt`/`fail`) over ordered choice with rollback
(`effekt-comparison.md`, findings 2–3); Raku's `||` (ordered
try-in-order choice, distinct from `|`'s best-match)
(`raku-grammars-comparison.md`, finding 3); and jq's zero-rollback
nondeterminism, the shipped *positive* witness for the leaning this
document adopts (`xquery-jq-comparison.md`, §9). The field sighting
predates all three: a machine-generated PEG parser's `# choice`
block — try an alternative, `break` on success, else reset
`self.pos` to a saved snapshot and try the next
(`real-loop-survey.md`, ruby 7; breadth item 6, "save/restore
cursor; wants the save/restore *pairing* visible"). No construct
owns it. Registers can express the save/restore but illegibly;
nothing makes the pairing legible.

## Against the philosophy

- **No bottlenecks.** A sum-side barrier: one cell out,
  per-contender correspondence, no tagged union packed for the
  consumer to re-split. The PEG parser's `break`-on-success flag and
  its reconstructed cursor are what the severed correspondence looks
  like in generated code.
- **Inside-out — cases as values.** The alternatives are drawn
  contenders, not scopes; the input is a value wire, not ambient
  state; commitment is a drawn marker, not a handler's position.
  Effekt's `alt(): Bool` returns a bool the code inspects — meaning
  by position, the thing the drawn form discards while keeping the
  capability.
- **Building blocks must build.** The +1 ladder is additive at every
  rung; heuristic order is the one that changes the drawing most,
  and it is one comparator wired into the ordering.
- **One obvious reading.** Ordered choice is contender order;
  restoration is the shared input wire; commitment is a `commit`
  node — three facts that in the sampled code live in a `break`
  flag, a manual `self.pos` reset, and (in Effekt) allocation
  position.
- **Example first.** The law's pieces were each forced by a concrete
  witness — the let-or-app choice, the tilde's commitment, the
  pretty-printer's constraint failure — not invented for generality.
- **Foundations before features.** Cancellation of effectful
  attempts is not designed here despite the pressure; only its
  trigger is named, on the discharge event that already carries it.

## Dead ends

Recorded in place, each with the reason it should not be
re-proposed.

1. **A backtracking substrate everywhere.** Now, you might wonder
   why the language doesn't just make rollback an ambient capability
   under the whole language, PEG/Effekt-style, so that any
   computation anywhere can be undone. It turns out this would cause
   problems: it makes the most delicate property — what gets
   restored — invisible, and it puts restoration cost on every
   program. The leaning is the inverse — threaded values as the
   substrate (no rollback anywhere), speculation a bounded construct
   opted into locally. Raku's ratchet-by-default is the field
   witness that this covers most of practice. (This is a settled
   dead end — please don't re-propose it without new evidence.)

2. **Rollback by allocation position, or a mutable cursor with
   paired restore.** You might wonder why the language doesn't adopt
   Effekt's mechanism (what is restored is decided by where state is
   allocated relative to a handler) or the PEG parser's (a mutable
   `self.pos` with a hand-paired reset). It turns out that the
   correctness of a backtracking program then becomes unreadable in
   the program text. Restoration must be structural — the shared
   input wire — not a semantic reset that must be kept paired by
   hand. (This is a settled dead end — please don't re-propose it
   without new evidence.)

3. **The continuation, or `alt(): Bool`, as a value the code
   inspects.** You might wonder why "which alternative won" isn't
   simply returned as a value — a boolean or a tag — for the program
   to branch on. It turns out this trades structure for position:
   control is structure, not a value. The alternatives are drawn
   cells; which one fired is a cell, not a returned tag or bool.
   (This is a settled dead end — please don't re-propose it without
   new evidence.)

4. **Conflating ordered choice with best-match choice.** You might
   wonder whether speculation and race-like best-match could be one
   construct with a knob. It turns out they must stay distinct:
   drawn-order try/fail/restore (speculation, Raku `||`) is a
   different construct from best-match-under-a-law over simultaneous
   contenders (the race barrier's shape, Raku `|`). A tie law over
   "longest / most specific" is race with a different settlement
   rule, not speculation. Keep them distinct; Raku shipping both is
   the evidence. (This is a settled dead end — please don't
   re-propose it without new evidence.)

5. **A `//`-style empty-or-falsy fallback operator.** You might
   wonder why the language doesn't offer jq's `//` — fire the next
   alternative when the left yields "no value *or* a falsy value."
   It turns out this is rejected by the value/flow wire sort:
   flow-absence (a soft-fail) is not a value, and a contender that
   produced `false` *succeeded*. Speculation dispatches on which
   side of the contender's fork fired (declined vs succeeded) — a
   flow fact — never on value falsiness. jq spends
   paragraphs disentangling the two; two wire sorts make the
   conflation unwritable (`xquery-jq-comparison.md`, §9). (This is a
   settled dead end — please don't re-propose it without new
   evidence.)

## Open questions

The language hasn't decided any of these yet.

1. **Adoption.** Prepared for the design conversation; nothing
   marked decided.
2. **Primitive barrier vs catalog block.** Whether the flat N-ary
   speculation is a primitive (race's sibling) or a catalog block
   over the right-nested handling chain. Same question race
   carries; decide together, since the answer likely wants to be
   uniform across the two sum-side barriers.
3. **Commit's form.** Node vs wire property; per-contender vs a
   general failability marker shared with async and streams; how it
   composes with nested speculations (a commit inside contender *i*
   of an inner speculation — does it commit the inner, the outer, or
   both?).
4. **Diagnosis payload.** Mostly closed by the failure round and
   its 2026-08-04 revision (`failure-payloads-design.md`): the
   decline pairs' values are in hand at the barrier, so the
   aggregate is ordinary data construction — no new composition
   mode — and a committed diagnosis crosses on the barrier's
   hard-fail pair, a drawn wire, never a propagating terminator.
   What remains is only *which* aggregate (list, merged set,
   furthest-position), a value-level catalog choice for the parsing
   domain (that doc's open question 3 names the same residue from
   the other side).
5. **The heuristic-order rung and the chooser family.** Whether
   heuristic-ordered speculation is a member of the decision-driven
   family (`tough-use-cases-design.md`, item 4) or a separate rung;
   its round should treat drawn-order and comparator-order as one
   family, as Raku's `||`/`|` pairing suggests. *The family's round
   now exists and answers: not a member* (`chooser-family-design.md`,
   exploration) — best-match (Raku's `|`) is this chapter's own
   all-results rung followed by an ordinary judged reduce (argmax is
   value vocabulary); computed-order trial over *homogeneous*
   alternatives (same computation, different parameter) is sort +
   walk + end-when-on-first-success, three existing pieces; and over
   *heterogeneous* drawn alternatives a computed total order would
   need k! dispatch to draw honestly, which is the tell that drawn
   order is this construct's meaning, not a parameter of it.
6. **Effect-bearing attempts.** Release-on-abandonment for a failed
   effectful contender waits on the Tier-1 IO/cancellation round;
   speculation commits only to needing no new ports (the discharge
   event is the trigger).
7. **Spec and text.** Spec entry and textual spellings (`commit`,
   the fan-to-contenders form, the two-output collect, the aggregate
   binder) are owed on adoption.
8. **Evidence.** Parsing and search are rare-but-breaking — a
   breadth obligation, not a frequency to chase (the shape is a
   singleton in the surveys by construction). A domain sample
   (parsers, layout engines, constraint search) would measure the
   costume it occurs in (hand-rolled `# choice` blocks, PEG
   generators, combinator libraries) and re-weight this row's W,
   never demote it on rarity alone.

## What this doesn't address

- **Recursion over virtual structure** — recursive descent's nesting
  is the divide flow's (`trees-and-recursion.md`), deferred;
  speculation supplies the choice, not the recursion. *The round now
  exists* (`divide-flow-design.md`, exploration): recursive descent
  is worked as its first program, with the link riding inside
  contenders unchanged — a failed contender's sub-parses abandon as
  unconsumed values, per this round's structural-restoration result —
  completing the four-part parsing vocabulary named above.
- **Cancellation / release of effectful attempts** — the Tier-1 IO
  round (`open-problems.md`); only the trigger is named here. *The
  round now exists* (`cancellation-design.md`, exploration): a
  failed contender's discharge strands its demand subtree like any
  other cessation, and its acquisitions release through the ordinary
  bracket lanes — nothing speculation-specific was needed.
- **The chooser family's own round** — heuristic order touches it;
  the two-flow decision-driven merge and merge fairness stay with
  `tough-use-cases-design.md`, item 4.
- **Failability's own design** — the failure vocabulary (splits as
  minting sites, endings reason-only, payloads by wire, the
  inferred short-circuit commute) is `failure-payloads-design.md`'s;
  speculation adds the aggregate-of-alternatives as a client, not a
  design, and the round consumed it: the aggregate is data
  construction over pairs in hand, no new composition mode.
- **Visual depiction** — barrier lines, how a contender fan reads,
  and whether `commit` has a glyph are the layout side's, out of
  scope in this repo.
- **Implementation.** The failure vocabulary does not exist in the
  compiler; nothing here changes the recorded dependency order
  (streams, then async cells / failability, then race /
  speculation).
