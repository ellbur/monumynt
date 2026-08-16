# Subordinate flows: controlling whether a flow is sequenced into a broader computation

Status: exploration — the record of a design conversation
(2026-08-16), with one construct proposed (the case collect selecting
flow wires), one ruling (which crossing belongs to which boundary),
and two of the conversation's own first answers dissolved in place.
Nothing here is adopted or implemented. This document is also the
**start of an agenda**: the family of ways a flow's firings do or do
not become part of a broader sequence. The membership table near the
end is the seed of that discussion, expected to grow.

If you want the background first: `effects-design.md` teaches the
per-firing effect thread and — in "The IO-as-flow direction"
(2026-07-23) — the recorded direction this conversation builds on
and confirms: IO is a flow, not a handle; an op uncollects an inner
IO flow that joins into one global IO flow; join's asymmetry *is*
the sequencing; the handle notation is a textual synonym.
`core-model.md` teaches value vs flow wires and the case/filter
pair; `collect-family-design.md` teaches what collects are;
`case-commute-polarity-design.md` is the adjacent case-cell round;
`source-openers-design.md` holds the frame-source family the read
op lands in.

## The program that started it

Read a line of text; if it is `"abc"`, print `"yes"`; otherwise do
nothing. Chosen as an exercise precisely because "otherwise do
nothing" is the interesting half.

In the value fragment — the language as implemented — the program is
a scalar case split closed by a partial collect (`src/Main.res`
section 17, compiled and validated):

```
line -> split check of Abc, Other => cs
cs.Abc -> say => said
~cs.Abc: said
-~> collect => done, ~pf
done -~> collect ~pf => out
```

The do-nothing branch is a branch that *isn't there*: only the Abc
cell is collected, and the program's value is an option, absent when
the line was anything else. The strain is that the effect (the
print) had to be smuggled through a value extern wired to the alt
payload, purely so that it had a context to fire in — the program is
really an IO program wearing value clothes.

Rewriting it with an IO thread (handle spelling, per
`effects-design.md`'s provisional forms) exposed the question this
document exists for:

```
in ~io
~io ~> readLine => line, ~io'
line -> split check of Abc, Other => cs
~io' ~> print("yes") => ~ioYes        -- fires in the Abc cell
...
out ~io''                             -- and what is ~io'' ?
```

The split is opened and never closed. Hanging the op on the Abc
cell says what happens *inside* one cell; nothing in the drawing
says what the IO thread is *after* the split. The first attempt
waved the thread back out by an inferred commute, and it seemed to
work — but only because the example is degenerate: the Other cell
does nothing, so "the empty concatenation" covered for it.

## The probe: an op in both cells

Put an operation in *each* cell — `print("yes")` in Abc,
`print("no")` in Other — and the inferred-commute story has no
answer. Two sibling cells each hold a continuation of the thread;
exactly one of them fired; the thread after the split is **the
firing cell's continuation**. That is not a concatenation — nothing
is being put in order, because at a case boundary at most one thing
happened. It is a **selection**, and selection is the case collect's
own law, already in the record for values:

- value case collect: *the collect's value is the firing branch's
  value.*
- flow case collect: *the collect's flow is the firing cell's
  continuation of the input flow.*

Two parallel sentences, one construct. **The proposal: case collect
lanes may select flow wires, not only value wires.** The case
collect passes the firing branch's input through *verbatim* — it
constructs nothing — so the law extends to a flow wire with no
inconsistency: what comes out is the very wire the firing lane
offered. In the handle spelling the program closes like this:

```
~io' ~> print("yes") => ~ioYes        -- the thread's Abc continuation
~cs.Abc: ~ioYes
~cs.Other: ~io'                       -- identity lane: the thread, untouched
-~> collect => ~io''
```

This is also the no-bottlenecks principle's sum half finally
collected on (`language-design-philosophy.md`): the case collect is
the sum-reconvergence barrier, and a barrier passes wires through
*as themselves*. The IO thread was bottlenecked out of it only
because lanes were value-only.

Graceful expansion holds: unconditional effect → conditional effect
is *insert split, move the op into the cell, close with a collect* —
structure added, nothing rewritten into a different construct.

## Which crossing belongs to which boundary (ruled 2026-08-16)

Mid-conversation, a unified reading was proposed: make **collect**
the single boundary-crossing word for both wire sorts, its law
indexed by flow kind × wire sort — with the list × marker cell
meaning "concatenate segments in firing order". That reading is
**dissolved**, for two reasons, both from the ruling:

1. **It keeps the word while breaking the law.** List collect's law
   is *construction* — gather N inputs into a list. The marker
   crossing constructs nothing (a list of IO wires is a recorded
   rejection, `effects-design.md`), so the "list collect" of a
   marker would be a collect in name only, and the inconsistency
   would have to be special-cased away. The case collect has no
   such problem because its law was never construction: it passes
   the firing branch's input verbatim, for a flow wire exactly as
   for a value.
2. **Commute is the home for wires the author wants to forget,
   because it can be inferred.** The IO thread's whole job is to
   order things silently; the never-drawn, completion-inferred
   commute (`effects-design.md`, "You never draw the commute") is a
   feature, not an omission, and folding it into a drawn collect
   would surrender it.

(Dissolved — please don't re-propose collect-as-the-one-crossing
without new evidence.)

So each boundary keeps the operation whose law already fits:

| boundary | what the crossing means | operation | drawn? |
|---|---|---|---|
| case | selection — the firing cell's continuation | **collect** (flow lanes) | drawn (selection is meaning) |
| list | concatenation — segments in firing order | **commute** | never drawn; inferred, shown faint |

The asymmetry is real and principled: at a case boundary at most one
segment exists, so the crossing selects; at a list boundary many do,
so the crossing orders. One sentence in `effects-design.md`
("collecting the handle at the end of the loop just does the job")
reads as authoring convenience, not as a claim that the loop
crossing *is* a collect; an update note there now points here.

## `in` is the incorporate

The provisional op spelling carried an `in ~flow` clause
(`~io ~> print("yes") in ~cs.Abc => …`) saying which flow the op
fires per firing of. Read visually, that clause is not annotation —
it is the **incorporate** operation, the subordination of a wire to
a deeper flow context (the same operation the unconstructed-meet
rule already names when overlapping cell sets meet:
"overlap is incorporate, not a clash"). And like the sequencing
commute, it is **inferable when unambiguous**: here the op's IO
output has exactly one consumer, the Abc lane of the collect, so
the incorporate is determined by the drawing and can be completed
by published rule, shown faint. The clause is authored only where
a genuine ambiguity exists (the completion discipline's usual
guard: an inference with two candidate homes stays a witness).

## The io-flow core, and the sugar checked against it

The 2026-07-23 direction (`effects-design.md`, "The IO-as-flow
direction") already holds the core ontology: an op does not take a
handle in — it *uncollects*, minting an inner ("baby") IO flow that
joins into one global IO flow, join's asymmetry carrying time, the
handle notation a textual synonym. This conversation put the first
concrete program through that reading, and the desugar is worth
recording because two rules dissolve under it.

The core form of the program:

```
readLine => line, ~r                 -- op mints its baby io flow
line -> split check of Abc, Other => cs
print("yes") => ~p                   -- baby io flow, homed in the Abc cell by the collect
~cs.Abc: ~p
-~> collect => ~c                    -- partial: Other contributes nothing
~r, ~c ~> join => ~io                -- join order is the sequence: read, then maybe print
out ~io
```

Desugaring the handle spelling: `~io ~> readLine => line, ~io'`
makes `~io'` name the sequence-so-far `[~io, ~r]`; the print makes
`~ioYes` name `[~io, ~r, ~p]`; the collect's two lanes select
`[~io, ~r, ~p]` and `[~io, ~r]`. The shared prefix factors out of
both lanes, and what the collect actually decides is only whether
`~p` is present. The handle chain is precisely the **authored
spelling of the join order** — each `~> op =>` link one edge of the
join spine — and the identity lane desugars to the *empty
contribution*.

Three consequences:

- **The covering demand dissolves.** The conversation's first
  answer argued the flow-lane collect must be covering, because "a
  handle cannot be conditionally dropped" — linearity forcing an
  identity lane in every uncovered cell. That rule is an **artifact
  of the handle representation**: in the core nothing enters the
  cell to be conserved — the Other cell simply mints no IO — so the
  core collect is lawfully *partial*, and absence of effects is the
  empty IO flow. Covering-with-identity-lane (sugar) and
  partial-with-absent-branch (core) are the same program seen
  through two spellings; "do nothing is a branch that isn't there"
  holds at the core level after all. (Dissolved — please don't
  re-propose mandatory coverage for flow lanes without new
  evidence. The sugar's bare identity lane — the translation
  exercise's provisional `Plain:` — remains wanted for the *sugar*,
  where the fold needs a value in every branch.)
- **The sibling-linearity rule dissolves with it.** In the sugar,
  `~io'` is consumed by two sibling lanes, and the first answer
  minted a rule for it ("linear wires are consumed once per
  exclusive path"). In the core the two lanes' references to `~io'`
  are references to a shared *prefix*, ordinary fan-out; no rule is
  needed. This is the direction's "no bespoke linearity rule"
  cashing out on a concrete program: nonlinear shapes are not
  checked away, they are **unrepresentable** — the IO vocabulary
  simply contains no duplicating operation (the same reason
  Haskell's IO monad needs no linear types). An author who forks
  the handle into two *non*-exclusive continuations desugars to two
  baby flows joined after the same point with no order between
  them — and the global IO flow's demand for a total order makes
  that an ordering witness from vocabulary Check already owns
  (the order-demand family), not a linearity error. Per-firing
  independent handles fall out as separate global-flow joins whose
  babies never contend — independent-handles-commute as structure
  rather than doctrine.
- **The subordination question is deleted, not answered.** "What
  does it mean to hang a *global* handle inside a cell that might
  not fire" was a genuinely awkward question. In the core nothing
  global is inside the cell: the baby flow is *born* there, and
  the collect lane (or the inferred incorporate) is what homes it.

One worry raised in conversation is answered by the record rather
than by new design: sequencing two sibling babies (`~r` then the
conditional `~c`) needs no new "ordered join" — join's asymmetry
plus associativity already carry it, and the rail normal form
(every baby joining the global wire directly, position along the
wire as time) is the drawn form of exactly that. What the example
adds to the rail is only the **conditional operand**: a 0-or-1 IO
flow selected by a case collect, joining like any other and
contributing nothing when its cell did not fire — the empty-loop
grounding at cardinality ≤ 1.

Also confirmed in passing: `readLine` in the core is value-out +
flow-out with nothing in — an *opener*, exactly as the direction
says ("an op uncollects"), which drops the read op into the
frame-source family noted in `source-openers-design.md`.

## How it draws

The standing visual-leap question has a good answer at both levels.
In the sugar, the thread's lifecycle segment forks through the cell
regions — ops strung on one, a plain pass-through on the other —
and reconverges at the collect vertex: the phi drawing, and an
improvement on the unclosed version, where the op floated in a cell
with no visible reconvergence. In the core, the rail gains a fork:
a baby flow born inside a cell region, its join into the global
wire passing through the cell boundary, the selection read off the
collect vertex. Position along the global wire remains time.

## The membership family (the agenda this document starts)

Stepping back, the example is one instance of a general question:
**what carries a flow's firings into a broader sequence, and what
keeps them out?** The forms seen so far:

| membership | mechanism | drawn? |
|---|---|---|
| always in, at a position | join into the global flow (position = time) | drawn (the join spine / rail) |
| in iff a cell fires | case collect selecting the flow, then join | collect drawn; incorporate inferable |
| in iff kept by a filter | the cell-borne flow joined in directly (join-into, the filter pair) | drawn |
| in across a loop, in firing order | the sequencing commute | never drawn; inferred, faint |
| never in | absence — the empty contribution | nothing to draw |

The second and third rows mirror the value world's pair exactly (a
conditional value leaves a split by case collect or by join-into),
which suggests the family is one structure seen from two wire
sorts. Future rounds are expected to add rows — candidates already
visible in the record include the symmetric join ("I don't care
which happens first"), the async fork's embedded ordering, and
whatever speculation and saturation demand — and to decide which
rows are one construct.

## Open questions

1. **Lane sort scope.** Flow lanes are proposed for *marker* flows
   only. A lane selecting a data flow (lane one offers one list
   flow, lane two another) makes the collect's output a flow whose
   extent is data-dependent — a genuinely new contextual object,
   not asked for by any example yet. Deferred, not rejected.
2. **Collect vs join-into for the conditional effect.** The core
   admits both closes, exactly as the value world does. Are they
   the same program two ways (one reading, two authoring paths),
   and does the printer pick one?
3. **Spellings.** All provisional: the flow lane (`~cs.Abc: ~p`),
   the flow binder on a collect (`=> ~c`), the sugar's bare
   identity lane, and the value+flow op binder
   (`~io ~> readLine => line, ~io'`) — the last is also the
   textual round's owed no-`io1`-`io2` syntax in disguise.
4. **The alignment check.** With the incorporate inferred, an op
   framed in one cell whose continuation is selected by another
   cell's lane should be witnessed (the two must agree). Where
   does that check live — alignment, or coverage?
5. **Interaction with the case-cell round.** A partial flow collect
   selects over a *cell set*; the merged-context rules
   (`partial-collect-design.md`) presumably apply to marker lanes
   unchanged, but nobody has walked a merged-cells IO example yet.
