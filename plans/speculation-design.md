# Speculation: ordered alternatives with rollback

Status: exploration — leanings, not adopted. Nothing here is
implemented; the failable flow kind it presumes does not exist yet
(`async-flow-design.md`, "Failure as terminator payload").

Speculation is try-in-order choice: several alternatives, drawn in
order, each of which may fail; the first that succeeds wins; the world
is restored between attempts so a failed alternative leaves no trace.
Parsing (recursive descent), search with constraint failure, and
best-effort fallbacks are its clients. This document works out its
semantics — the barrier's law, how restoration is expressed, its
relationship to the race barrier, commitment and diagnosis, and the +1
ladder — and records where its pieces already live.

The gap is well-witnessed. Three comparison rounds arrived at the same
shape independently: Effekt's parser and pretty-printer, both built on
`Nondet` (`alt`/`fail`) over ordered choice with rollback
(`effekt-comparison.md`, findings 2–3); Raku's `||` (ordered
try-in-order choice, distinct from `|`'s best-match)
(`raku-grammars-comparison.md`, finding 3); and jq's zero-rollback
nondeterminism, the shipped *positive* witness for the leaning this
document adopts (`xquery-jq-comparison.md`, §9). The field sighting
predates all three: a machine-generated PEG parser's `# choice` block —
try an alternative, `break` on success, else reset `self.pos` to a
saved snapshot and try the next (`real-loop-survey.md`, ruby 7; breadth
item 6, "save/restore cursor; wants the save/restore *pairing*
visible"). No construct owns it. Registers can express the save/restore
but illegibly; nothing makes the pairing legible.

## The concrete example

An expression is a `let` or an application — Effekt's `or { parseLet() }
{ parseApp() }`. Each is a **failable** computation over the input: it
reads the current position, consumes some tokens, and either succeeds
(producing an AST and an advanced position) or fails (its terminator
fires). `parseLet` reads the first token; if it is not `let`, it fails
cheaply, and `parseApp` is tried against the *same* position.

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
tries them in drawn order, stopping at the first success. The winner's
result reaches `expr` through its cell; the loser is never run once the
winner succeeds (or, if `parseLet` ran and failed, `parseApp` reads the
unchanged `p`).

## The heart: restoration is structural, not an operation

The delicate property of a backtracking program is *what gets restored
between attempts*. In Effekt it is invisible — decided by where a `var`
sits relative to a handler, two programs differing only in allocation
position printing different results (`effekt-comparison.md`, "the
comparison's sharpest observation"). In the PEG parser it is a manual
`self.pos = _save2` reset, correct only if every mutation is paired with
its restore. Both fail "the drawn structure is trustworthy."

In a dataflow formulation there is nothing to restore, because there is
nothing mutated. The input position is an immutable **value**. An
alternative that consumes from `p` produces a *new* position value; the
old `p` still sits on its wire. A failed alternative produced nothing,
so its would-be advanced position reached nothing downstream. The next
alternative reads the same `p` — the same wire — and therefore starts
from the original position by construction.

So restoration is not a feature of speculation. It is an **emergent
property** of three things the language already has:

- **immutable values** — advancing the cursor mints a new value, never
  overwrites,
- **ordinary sharing** — the input fans out to every alternative (a
  tap; `core-model.md`, sharing is opt-in via binding),
- **ordered fallback** — the barrier below.

The save/restore *pairing* breadth item 6 wanted visible is the input
wire fanning into the alternatives. There is no save node and no restore
node — the picture shows every alternative reading the same position,
which *is* the invariant. jq is the shipped witness that this works: a
whole alternatives-and-failure story on pure value streams with zero
rollback machinery, "because an abandoned alternative is a value stream
nobody consumed further." Its caveat is the thing we supply that jq
lacks: jq owns *no consumed-input notion* (it never parses; its
backtracking is over derived values), so it gets restoration free by
never having a cursor. A parser must thread the position; the leaning is
that threading it as an ordinary value is enough, and the picture is the
better for it.

## The law of the barrier

**Form.** Speculation takes N contenders (N ≥ 1), each a **failable**
computation. It is a sum-side multi-input uncollect — the same shape as
a case split and the race barrier (`barrier-value-crossing-design.md`,
values in, one minted row per cell). Out comes a **bundle of N cells**:
cell *i* fires iff contenders 1..*i*−1 all failed *and* contender *i*
succeeded, carrying contender *i*'s success value as its minted per-cell
output. Exactly one cell fires, or none (all failed).

**Ordering is the primary selection.** Contenders are attempted in drawn
order. Contender *i*+1 runs *only if* contender *i* fails. This is the
axis on which speculation differs from everything temporal: order is not
a tie-break (as in race), it is the whole selection rule. Later
contenders are not merely lower-priority — they are not evaluated at all
until earlier ones have failed, which laziness delivers for free (force
contender *i*+1 only when contender *i*'s terminator has fired;
`lazy-compile-design.md`).

**Selection is by success, not settlement.** A contender that *fails* is
passed over. This is why contenders are failable by construction: "fail"
is how a contender says "not me, try the next." A contender's failure
terminator is **discharged** at the speculation barrier into "advance to
the next contender" — it does not propagate. Only when *every* contender
has failed does speculation itself fail, propagating an aggregate
terminator (see "Diagnosis").

**Failable by construction.** The contenders' failability is not
optional decoration; it is the barrier's input contract, exactly as
race's contenders are async values. A non-failable contender is a
contender that always wins if reached — a legitimate degenerate case (an
unconditional final alternative, the `else` of the choice).

## Speculation is the race barrier's sequential sibling

Race and speculation are the two sum-side barriers. They share the
form — values in, a bundle of N cells, exactly one fires, per-contender
correspondence, no tagged union packed (`core-model.md`, "Barriers, not
bottlenecks"). They differ on one axis: **what decides the winner.**

| | race | speculation |
|---|---|---|
| contenders | async values | failable computations |
| all run? | yes, concurrently, in drawn order | no — next only on prior failure |
| winner is | first to **settle** (temporal) | first to **succeed** (ordered) |
| drawn order | tie-break only | the primary selection |
| a "loser" | abandoned in-flight, memoised | never run, or failed and discharged |
| restoration | n/a (independent asyncs) | structural: the shared input wire |

Raku ships both and keeps them distinct: `||` is the speculation shape
(drawn order, try/fail/restore); `|` is longest-token matching — "all
branches notionally raced, the longest wins, ties by a published law" —
which is structurally the race barrier's law-with-ties, with "longest /
most specific" where race has "first settled"
(`raku-grammars-comparison.md`, finding 3). A future round must not
conflate them; Raku needing both is the evidence the distinction is
real. Recorded as dead end 4.

## Speculation as a chain of discharges

The barrier's meaning decomposes into pieces the record already owns.
Ordered fallback of two contenders A, B over shared input `p` is:

> run A(`p`); **discharge** its terminator — success ⇒ output;
> soft-fail ⇒ run B(`p`), discharge *its* terminator — success ⇒
> output; fail ⇒ propagate the aggregate.

That is a case split on A's terminator (Success / SoftFail) whose
SoftFail branch contains B, itself discharged — a **right-nested chain
of discharges**, N contenders deep. It is expressible today from
failability's propagate/discharge (`async-flow-design.md`) plus a
case-split on the terminator; nobody should author it, exactly as nobody
authors race's merge/interrupt corecursion (`race-barrier-design.md`,
"Merge, interrupt, and the timeout family"). The flat N-ary drawing is
what the user draws; the nested-discharge chain is its derived lowering,
inspectable on drop-down (principle 6). Whether the flat form is a fresh
primitive barrier or a catalog block over that lowering is open (open
question 2) — the same primitive-vs-catalog question race carries.

## Commitment: the everyday mode, and where diagnosis is born

Ratcheting is Raku's default: `token` and `rule` never back up, `regex`
backtracks, and the docs steer users to the ratcheting declarators —
"most grammar code never backtracks; the speculative engine is the
exception, opted into locally." This is the substrate leaning made
concrete: threaded values everywhere (nothing to roll back), speculation
a *bounded, local* construct drawn exactly where alternatives-with-
fallback is wanted — not a backtracking substrate under the whole
language.

Within a contender, commitment distinguishes two kinds of failure. Once
Raku's tilde `'(' ~ ')' <expr>` has matched the open delimiter, a
missing close is not a non-match — it fires a user-definable `FAILGOAL`
("Cannot find ')' near position 4"). Mapped onto our two terminator
lanes:

- **soft fail** — no match; the contender declined. Discharged by the
  enclosing speculation ⇒ try the next contender.
- **hard fail** — the contender committed past a point and then could
  not continue. Propagates *past* the speculation barrier ⇒ the whole
  parse fails with a diagnosis; later contenders are **not** tried.

The leaning: a **commit** marker on a contender's wire upgrades any
subsequent `fail` from soft to hard — the drawn analogue of the tilde's
commitment. `fail` is failability's lightweight terminator write;
`commit` changes only how the enclosing speculation discharges what
comes after it. Both stay drawn; neither is a value the code inspects.
(Commit's exact form — a node, a wire property, per-contender vs a
general failability marker shared with async — is open question 3.)

## Diagnosis: what a failed parse says

Error reporting is part of the construct's territory, not a layer on top
(`raku-grammars-comparison.md`, finding 3). Two cases, both terminator
payloads:

- **All contenders soft-failed.** Speculation's own terminator carries
  the aggregate — "none of {parseLet, parseApp, …} matched at `p`" —
  built from each contender's declined-expectation. This is the honest
  "no alternative matched," and it names the alternatives because they
  are drawn cells.
- **A contender hard-failed.** Its committed diagnosis propagates
  directly, bypassing "try next" — the FAILGOAL "expected ')' near
  position 4," which is more specific than the aggregate precisely
  because the contender got far enough to know what it wanted.

Payload composition (how the aggregate is built, whether it is a list of
expectations or a merged set, how position is carried) folds into
failability's terminator payload-composition residue
(`async-flow-design.md`) and end-when's discharge readout
(`end-when-design.md`) — decide jointly. Open question 4.

## Concatenation and recursion — what speculation does *not* need

With position-as-value, **concatenation is ordinary chaining.** Match
this, then that, over one cursor is: `p -> matchThis -> p' -> matchThat
-> p''` — each step takes a position and returns an advanced one, wired
forward. No new construct; the position threads exactly like any value
in a chain. This is the natural home of the rung
`raku-grammars-comparison.md` §2 called "the record is missing" — it is
not missing, it is the forward chain, once the cursor is a value.
Speculation is the only genuinely new piece; commit sits on the chain;
`fail` is failability's.

**Recursion — nested structure — is the divide flow's**, deferred here.
Recursive descent (nested-delimiter parsing, `'(' ~ ')' <expr>` with
`<expr>` calling back) is recursion over *virtual* structure: the parse
tree exists only as the walk's call structure until it materializes.
That is `trees-and-recursion.md`'s territory (the divide flow, still
narrative-stage; `tough-use-cases-design.md`, the mergesort limit). The
parsing vocabulary is thus four parts — **speculation** (ordered
choice), **position-threading** (concatenation, ordinary chaining),
**commit + fail** (commitment and diagnosis), and **the divide flow**
(recursion) — of which only speculation is worked here. Recursive
descent is a candidate first program for the divide flow's round with
field precedent (`open-problems.md`, the recursion row).

## Effects and abandonment — the Tier-1 boundary

Pure attempts abandon for free: a failed alternative that only produced
*values* (an AST fragment, a candidate layout) leaves nothing behind
when the next is tried, because values on unconsumed wires simply go
unread. Effekt's pretty-printer resets a mutable output buffer between
attempts; in our formulation the emitted document is a value per
attempt and the reset is free (`effekt-comparison.md`, finding 3). This
is the whole story for parsing and search over pure input.

An attempt that causes **real effects** (opens a file, writes a socket)
and then fails is a different matter — its effects need
release-on-abandonment, which is bracket and cancellation, the Tier-1 IO
round (`open-problems.md`, Tier 1; `zig-comparison.md`, `defer`/
`errdefer`). Speculation over effectful attempts inherits that gap
whole: the failed contender's discharge is *also* the trigger to release
what it acquired, structurally the same event as race's lost-cell
cancellation trigger (`race-barrier-design.md`, "Abandonment at the
barrier"). Named, not designed — speculation commits only to needing no
new ports for it.

## The +1 ladder

Each rung is an addition to the drawing, over the same bundle of
attempts (principle 7).

- **first-success** (the base) — the priority-first collect over the
  ordered bundle: stop at the first firing cell. One result + one
  advanced position out.
- **+ all-results** — collect *all* cells that fire, to a list, instead
  of stopping at the first. Same bundle, a different reconvergence
  (multi-close-flavored): the ambiguous-parse / all-valid-layouts case.
  Laziness makes the two genuinely different evaluations of one drawing
  — priority-first forces contender *i*+1 only on *i*'s failure;
  collect-all forces every contender.
- **+ bounded** — take the first K successes, or bound the search
  depth/width: a `take`-count on the collect (`variable-rate-
  consumption-design.md`, the take family).
- **+ heuristic order** — order the contenders by a computed priority
  rather than drawn order: a comparator wired into the ordering, the
  bridge to the **chooser family** (`tough-use-cases-design.md`, item 4)
  and Raku's `|` (best-match) beside `||` (drawn order). This is where
  speculation touches the decision-driven family; its round should take
  the async merge, the ordered merge, and heuristic-order speculation as
  members of one family whose lowerings differ only in what decides the
  head.

## Reconvergence and provenance

Inherited from race with no changes (`race-barrier-design.md`,
"Reconvergence" and "Provenance fit"). The covering collect over the
ordered bundle is the exhaustive close — exactly one cell fired, so it
fires once; contenders whose results are differently-typed convert to a
common type in their own cell bodies before the covering collect, or the
output stays a case/sum. Speculation is one uncollect step in the
context path — a bundle of N cells, ordered-choice discriminator — the
same step shape a case split and a race write; cell sets compare by
containment; the mixing check meets the bundle unchanged. The aggregate
failure adds no step kind — failability is a property of the flow, not
of the path.

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

A committed contender writes `commit` on its chain before the `fail`
that should become hard. The advanced position rides out of the covering
collect beside `expr` for the next stage to thread.

The `+all-results` rung is the same bundle with a different
reconvergence — each firing lane joined into a list collect instead of
the stop-at-first covering collect (the ambiguous-parse case):

```
p -> | parseLet
     | parseApp
-> speculate => r
~r.parseLet:  r.parseLet -> LetNode -~> join -~> collect => parses
~r.parseApp:  r.parseApp -> AppNode -~> join      -- same collect, via the joins
```

(Sketch only; the collect-all form forces every contender where
priority-first forces contender *i*+1 only on *i*'s failure — the
laziness difference stated in the ladder.) Exact spellings —
the fan-to-contenders form, `commit`, the two-output (result, position)
collect, the all-results reconvergence, and the aggregate diagnosis
binder — are owed to the textual round.

## Against the philosophy

- **No bottlenecks.** A sum-side barrier: one cell out, per-contender
  correspondence, no tagged union packed for the consumer to re-split.
  The PEG parser's `break`-on-success flag and its reconstructed cursor
  are what the severed correspondence looks like in generated code.
- **Inside-out — cases as values.** The alternatives are drawn
  contenders, not scopes; the input is a value wire, not ambient state;
  commitment is a drawn marker, not a handler's position. Effekt's
  `alt(): Bool` returns a bool the code inspects — meaning by position,
  the thing the drawn form discards while keeping the capability.
- **Building blocks must build.** The +1 ladder is additive at every
  rung; heuristic order is the one that changes the drawing most, and it
  is one comparator wired into the ordering.
- **One obvious reading.** Ordered choice is contender order;
  restoration is the shared input wire; commitment is a `commit` node —
  three facts that in the sampled code live in a `break` flag, a manual
  `self.pos` reset, and (in Effekt) allocation position.
- **Example first.** The law's pieces were each forced by a concrete
  witness — the let-or-app choice, the tilde's commitment, the
  pretty-printer's constraint failure — not invented for generality.
- **Foundations before features.** Cancellation of effectful attempts is
  not designed here despite the pressure; only its trigger is named, on
  the discharge event that already carries it.

## Dead ends

Recorded in place; each with the reason it should not be re-proposed.

1. **A backtracking substrate everywhere** (rollback as an ambient
   capability under the whole language, PEG/Effekt-style). Rejected: it
   makes the most delicate property invisible and puts restoration cost
   on every program. The leaning is the inverse — threaded values as the
   substrate (no rollback anywhere), speculation a bounded construct
   opted into locally. Raku's ratchet-by-default is the field witness
   that this covers most of practice.
2. **Rollback by allocation position, or a mutable cursor with paired
   restore** (Effekt's mechanism; the PEG `self.pos` reset). Rejected:
   the correctness of a backtracking program becomes unreadable in the
   program text. Restoration must be structural — the shared input wire
   — not a semantic reset that must be kept paired by hand.
3. **The continuation, or `alt(): Bool`, as a value the code inspects.**
   Rejected: control is structure, not a value. The alternatives are
   drawn cells; which one fired is a cell, not a returned tag or bool.
4. **Conflating ordered choice with best-match choice.** Drawn-order
   try/fail/restore (speculation, Raku `||`) is a different construct
   from best-match-under-a-law over simultaneous contenders (the race
   barrier's shape, Raku `|`). A tie law over "longest / most specific"
   is race with a different settlement rule, not speculation. Keep them
   distinct; Raku shipping both is the evidence.
5. **A `//`-style empty-or-falsy fallback operator** (fire the next
   alternative when the left yields "no value *or* a falsy value," jq's
   `//`). Rejected by the value/flow wire sort: flow-absence (a
   soft-fail) is not a value, and a contender that produced `false`
   *succeeded*. Speculation dispatches on the terminator (fail vs
   success), never on value falsiness. jq spends paragraphs
   disentangling the two; two wire sorts make the conflation unwritable
   (`xquery-jq-comparison.md`, §9).

## Open questions

1. **Adoption.** Prepared for the design conversation; nothing marked
   decided.
2. **Primitive barrier vs catalog block.** Whether the flat N-ary
   speculation is a primitive (race's sibling) or a catalog block over
   the right-nested discharge chain. Same question race carries; decide
   together, since the answer likely wants to be uniform across the two
   sum-side barriers.
3. **Commit's form.** Node vs wire property; per-contender vs a general
   failability marker shared with async and streams; how it composes
   with nested speculations (a commit inside contender *i* of an inner
   speculation — does it commit the inner, the outer, or both?).
4. **Diagnosis payload.** The aggregate-of-alternatives on all-fail and
   the pass-through of a committed diagnosis; decide jointly with
   failability's payload composition and end-when's discharge readout.
5. **The heuristic-order rung and the chooser family.** Whether
   heuristic-ordered speculation is a member of the decision-driven
   family (`tough-use-cases-design.md`, item 4) or a separate rung; its
   round should treat drawn-order and comparator-order as one family, as
   Raku's `||`/`|` pairing suggests.
6. **Effect-bearing attempts.** Release-on-abandonment for a failed
   effectful contender waits on the Tier-1 IO/cancellation round;
   speculation commits only to needing no new ports (the discharge event
   is the trigger).
7. **Spec and text.** Spec entry and textual spellings (`commit`, the
   fan-to-contenders form, the two-output collect, the aggregate binder)
   are owed on adoption.
8. **Evidence.** Parsing and search are rare-but-breaking — a breadth
   obligation, not a frequency to chase (the shape is a singleton in the
   surveys by construction). A domain sample (parsers, layout engines,
   constraint search) would measure the costume it occurs in
   (hand-rolled `# choice` blocks, PEG generators, combinator libraries)
   and re-weight this row's W, never demote it on rarity alone.

## What this doesn't address

- **Recursion over virtual structure** — recursive descent's nesting is
  the divide flow's (`trees-and-recursion.md`), deferred; speculation
  supplies the choice, not the recursion.
- **Cancellation / release of effectful attempts** — the Tier-1 IO round
  (`open-problems.md`); only the trigger is named here.
- **The chooser family's own round** — heuristic order touches it; the
  two-flow decision-driven merge and merge fairness stay with
  `tough-use-cases-design.md`, item 4.
- **Failability's payload composition** — how terminator payloads
  combine is `async-flow-design.md`'s residue; speculation adds the
  aggregate-of-alternatives as a client, not a design.
- **Visual depiction** — barrier lines, how a contender fan reads, and
  whether `commit` has a glyph are the layout side's, out of scope in
  this repo.
- **Implementation.** The failable flow kind does not exist in the
  compiler; nothing here changes the recorded dependency order (streams,
  then async cells / failability, then race / speculation).
