# Source Openers: Repetition Without a Source, and the External Pull

> Exploration round (2026-07-11) — **leanings, not an adopted
> design**, prepared for the design conversation. The subject is
> the record's most-witnessed unowned item: the two opener species
> with no authoring form — the **self-driven flow** (repetition
> without a source) and the **external pull source** (an outside
> iterator consumed until it says stop) — plus **pacing**, the
> semantic hole filed with them (the next firing of a self-driven
> flow gated on a per-firing async value). Demand is measured and
> repeatedly confirmed: survey classes 4–5 (six of sixty random
> loops) cannot start on the page (`translation-exercise.md`,
> finding 3), and the Zig round corrected the item's priority —
> the plainest imperative loop lands here, so the opener gates
> ordinary iteration, not just pumps and generators
> (`zig-comparison.md`, finding 2). Method: gather what the record
> already fixes (the iteration-state equivalence round pinned the
> node's existence; end-when pinned its consumption), state the
> smallest node consistent with those pins, then work the two
> species and pacing against the principles with the sampled loops
> as contact evidence. Nothing here is implemented; the stream and
> async runtimes this presumes do not exist in the compiler yet.
>
> Terminology: **uncollect/collect** per the 2026-07-07
> correction; **register**, **write half**, **productivity** as in
> `iteration-with-state-design.md` and
> `first-class-ports-design.md`; **the async cell**, **settlement**
> as in `async-flow-design.md`; **end-when**, **shortened flow**,
> **terminator discharge** as in `end-when-design.md`. Spellings in
> examples are the translation exercise's provisional strawmen,
> still provisional; naming stays deferred per tradition.

## Why this document exists

The record reaches self-driven flows through Fibonacci — a
recurrence with no inlet — which made them feel like a theoretical
edge case until the surveys corrected that: polling, retrying, and
producing are how code talks to the world (`real-loop-survey.md`,
survey 1, finding 6). Since then the item has accumulated more
independent witnesses than any other single gap — and stayed a
name. Every one of the following arrived separately:

| Witness | What it showed |
|---|---|
| Translation exercise, finding 3 | Survey classes 4–5 cannot start on the page; `repeat -> open self` and `source js "…"` invented on the spot as placeholders. |
| Effekt round, finding 6a | The canonical beginner generator (`fib()` yields forever) is blocked on exactly this node. |
| Flix round, finding 4 | Recursive channel producers are self-driven sources, hand-built from recursion. |
| XQuery/jq round, finding 6 | jq's `while`/`until`/`repeat`/`recurse(f; cond)` are the self-driven source hand-built; `input`/`inputs` sight the pull species. |
| APL round, finding 9b | Power (`⍣`) is the bounded / to-fixpoint iterate. |
| Zig round, finding 2 | The counter `while` — the imperative ground floor — transcribes onto the missing node; the stdlib's whole iteration story is pull-until-null (`next() ?T`). |
| Reactive round, §8 | The Elm Architecture's subscriptions, DOM events, and port messages "are source openers." |

And pacing, the hole inside the hole, has its own sighting list:
sleep-between-polls (ruby 9), the backoff reconnect (survey 3,
websockets 1 — step the delay register on the failure leg, reset
on success), undici's retry timer (survey 3), Flix's retry
middleware (stdlib vocabulary — and the functions row's policy
layer is blocked on it), and RxJS `concatMap`'s unbounded-buffer
warning (the same hole read from the backpressure side). The
retry composite — the surveys' named expansion test — cannot be
assembled without it (`translation-exercise.md`, finding 3).

Meanwhile two design rounds now *presuppose* the node. The race
round's derived combinators (merge, interrupt, timeout) have
lowerings that are "corecursive, self-driven walks"
(`race-barrier-design.md`) — derived views onto a construct that
cannot currently be drawn. And the iteration-state equivalence
round found the port form needs to *borrow* a flow-minting node
for the self-driven corner to be authorable at all
(`iteration-with-state-design.md`, "the one genuine asymmetry").
A node that two adopted-or-leaning designs reference and nobody
has designed is exactly the kind of debt this round exists to
close on paper.

## What the record already fixes

Assembling the constraints is most of the design; five directions:

1. **The node's existence and its reading are already pinned.**
   The equivalence round: a link with no external source is, in
   the latent form, "an uncollect with no `src` — a node that
   *mints* the self-driven flow," and the port form borrows that
   node — "a bare self-driven opener whose only content is the
   flow mint, with the reads referencing it." Its dead end 3
   records that the self-driven corner is *the one place*
   read-as-opener is right, "because there the flow must be
   minted by something." This round does not get to redesign
   that; it gets to finish it.

2. **What ends it is already designed.** End-when's round worked
   the composition: "the self-driven flow says *repeat*, the
   register says *what carries*, and end-when says *until*" —
   three separately-variable choices, one construct per word.
   Interrupt covers the event-driven endings. This round adds no
   termination machinery; a self-driven flow with no consumer-side
   shortening simply never ends, and that is its meaning (ruby 2's
   infinite producer is a real program).

3. **State is ports on a flow, never a kind of flow.** The
   equivalence round's dead end 2 killed "list-with-state" as a
   kind: a kind with no kind content forks every row of the kinds
   table. The same knife applies here: "self-driven" must not
   become a sixth row of the kinds table unless it has genuine
   kind content (opens-what, collect-yields-what). It doesn't —
   see "The kind question."

4. **The corecursion stance.** The mergesort round diagnosed
   manual cursor bookkeeping as "the assembly language of
   iteration," and the race round reaffirmed it: catalog blocks
   (decision-driven merge, async merge, interrupt) own the walks
   whose lowerings are corecursive; "nobody should author the
   recursion; everybody should be able to read it as the derived
   view." The opener must be introduced so that it does not read
   as a license to hand-roll those walks.

5. **Failability is a uniform dimension.** Any kind's termination
   event can carry a payload (`async-flow-design.md`). An external
   pull that throws is a failable source; Zig's
   `while (it.next()) |v| … else |err|` is that terminator payload
   sighted in the wild (`zig-comparison.md`, finding 4). The pull
   source gets failure for free; nothing new to design there.

## The self-driven opener: the smallest node that closes the gap

**The node.** One node, no value inputs, no value outputs, one
flow output: the mint. Strawman spelling:

```
open self => ~R
```

(The translation exercise wrote `repeat -> open self => ~R`; the
`repeat ->` operand was scaffolding the node does not need. An
uncollect opens a value into a flow, and here there is no value —
the honest form has an empty operand position, which is itself
the clearest statement of what the node is.)

Everything per-firing on a self-driven flow comes from somewhere
else, and the somewheres are all designed:

- **carried state** — registers: `~R ~> delay init x => r`, with
  `step of r` wired later (the write half);
- **ancestor values** — provenance's prefix rule admits them
  directly, no transport (`bundle-provenance-design.md`);
- **the outside world** — per-firing effectful reads (the Tier-1
  hole; unchanged by this round) or per-firing async values
  (timers — designed).

So the opener genuinely has no per-firing value of its own to
offer, and the port inventory should say so. In particular it
does **not** offer a firing index. The counter is a register when
a program wants one (two statements), and an ambient index is a
recorded clash elsewhere (`apl-family-comparison.md`, the index
origin; `tidyverse-comparison.md`, `cur_column()`) — a magic
value nobody wired. Dead end 1 below.

**Identity and sharing.** By node identity, like everything else:
two `open self` nodes are two independent flows; sharing is
binding the handle once. Nothing new.

**Extent.** Unbounded, by definition — the opener asserts
repetition, not a count. All shortening is consumer-side and
already owned: end-when (data says stop), interrupt (an event
says stop), a stream consumer's bounded demand (`take`-shaped
prefix consumption). A whole-flow collect over an unshortened
self-driven flow does not terminate; that is the same standing
status as any infinite stream, not a new hazard. Whether "no
terminator writer reachable from this collect" should be a
checkable property is filed to the checking row, not answered
here.

**`final`.** A register's `final` on an unshortened self-driven
flow is never available — the residue
`first-class-ports-design.md` already records. With end-when in
the room the readout anchors to the shortened extent, and the
semantic fine print (which extent, when subject-flow and
shortened-flow consumers coexist) is end-when's open question 4.
Inherited, not re-opened.

## The kind question

The translation exercise asked it directly: "what is the flow
kind of bare repetition — a self-driven stream?" The leaning:

**The minted flow is a stream — the sourceless instantiation of
the existing kind — and paced or awaited firings make it an async
stream. No new kind.**

The argument, against the kinds table: a kind earns its row by
its open behaviour and its collect behaviour. The self-driven
flow's collect behaviour is entirely inherited (collect a prefix,
reduce-collect over a shortened extent, effects per firing — all
exactly a stream's). Its open behaviour differs from a list's in
one respect only: firings are minted by demand rather than read
from a value — which is precisely the stream row's "each element,
on demand" with the element column empty. A kind whose every
behaviour is another kind's is not a kind (constraint 3); it is
that kind, opened differently. The opener is a new *node*, not a
new *row*.

The async grade arrives compositionally, the same way it arrives
for everything else: the moment a firing's advancement waits on
settlement — a paced flow (below), or carried state that is
itself async — the flow is an async stream, and the async round's
machinery (cells, sequential-is-nesting, interrupt at the pull
boundary) applies unchanged. Zig's `io.async` note is the right
frame: asynchrony as *possibility* (`zig-comparison.md`, finding
8) — the pure Fibonacci and the paced poll loop are one construct
at two grades, not two constructs.

## Counted repetition is data — and the seam, stated honestly

"Do it n times" does not reach for this opener. A known count is
data: open a range value (`0..n` as a list/stream), and the walk
has n firings — which the Zig round already endorsed from the
other side (an index is "one more aligned lane," `for (items,
0..)`; the range materializes). The APL power operator's two
forms split exactly along this line: `f⍣n` (bounded) is a
register walked over a range; `f⍣≡` (to fixpoint) is a register
on a self-driven flow with end-when on `state = prev state`. The
division of labour is clean: **if the data knows the extent, the
extent is data; if only the walk can discover it, the walk is
self-driven and a terminator-writer ends it.**

The seam this leaves, stated rather than smoothed over: moving a
program from "10 times" to "until converged" swaps the opener — a
range uncollect becomes `open self` + end-when — which is a
construct swap, and principle 7 (graceful expansion) frowns at
rewrites. Two readings of that:

- The bounded form *is* drawable self-driven (counter register +
  end-when), so the ladder is buildable if authored that way, and
  the range form is the fused special case — the same
  primary/derived relationship the keyed collect has with
  operator-merge. Many authoring paths, one reading each.
- Or: the swap is honest, because the program's *meaning* changed
  — its extent moved from data to discovery — and a construct
  change that tracks a meaning change is what principle 4 wants,
  not a violation of principle 7.

The round leans on the second reading but records the first as
live; the choice has surface consequences (does the editor offer
a "make this count conditional" gesture that performs the swap?)
that belong with the iteration-state surface conversation, not
here. Open question 3.

## The corecursion boundary, drawn

The opener makes corecursive programs *writable*, and the record
deliberately declines to hand users raw corecursion. Those two
sentences must be reconciled explicitly or the construct will be
misread — in either direction.

The stance: **the opener is for programs whose repetition is the
program's meaning; it is not for encoding walks that a catalog
block owns.** Poll-until, produce-forever, iterate-to-fixpoint,
retry-with-backoff: in each, "repeat" is what the program *says*,
and the drawing (opener + registers + end-when) is at the
programmer's abstraction level — each node is a word of the
sentence. The ordered merge's cursor pair, interrupt's
race-at-every-pull, merge's carried loser: in each, the
self-driven walk is an *encoding* of a higher construct, and
authoring it by hand is the assembly language the mergesort round
diagnosed. The blocks stay; what the opener changes is that their
**derived lowerings become real programs** — readable, drawable
views — instead of prose descriptions of a node that doesn't
exist. That is the abstraction-is-source-of-truth shape
completing itself: derivation is downward and free, and now the
floor it lands on exists.

(The checking row may eventually want the soft version of this
boundary a linter would enforce — "this self-driven walk is
recognizably an ordered merge" — but recognition-and-suggestion
is completion machinery, and nothing here depends on it.)

## Pacing

### The hole, stated

Three field sightings, one shape: a self-driven flow whose next
firing must wait on a per-firing async value — sleep 5 between
polls, the current backoff before reconnecting, the retry timer.
Today the sleep is just an effect op and "no wire connects it to
the flow's advancement" (`translation-exercise.md`, finding 3).
The demand is not a spelling; it is a semantics: *what gates
firing n+1 of a self-driven flow?* The unpaced answer is "demand
alone." The paced answer must be "demand, and not before this
firing's gate settles."

### Three candidate homes

**(a) A pace port on the opener.** The opener grows an optional
on-cycle operand, late-wired like the register's step
(`pace of R`): a per-firing value whose settlement gates the next
firing. Structurally comfortable — the two-phase
`<port> of <name>` form was generalized for exactly on-cycle
operands (translation exercise, finding 4), and the pace edge is
a computation cycle crossing the opener, a sibling of the
write→read pairing, so productivity extends naturally (every
cycle crosses a whole-iteration boundary).

**(b) Effect sequencing.** The sleep is an effect on the IO
thread; the flow's advancement is sequenced after it. This is not
a design but a restatement of the hole — it is blocked on the
Tier-1 effects round, and it couples pacing (which is often pure:
a timer is an async value, not an effect) to the effect story
unnecessarily. Dead end 2 below.

**(c) A binary flow operation.** `paced(F, g)`: flow in, plus a
per-firing async value `g` computed in the walk; delayed flow
out. Firing n of `~R'` is firing n of `~R`; firing n+1 of `~R` is
demanded only after `g` at firing n has settled; the first firing
is ungated; `g`'s value is discarded — only settlement is
observed. Strawman:

```
open self => ~R
…                                -- the attempt, computed in ~R
sleep(5) in ~R => d              -- per-firing timer (see note)
~R, d ~> paced => ~R'
```

One wrinkle the drawing must not hide: the gate must be **minted
per firing**. A node's context comes from its operands, so a
`sleep(5)` fed only a constant would sit at ancestor context —
one shared timer, settled once, gating nothing after the first
firing. A constant delay therefore enters the walk explicitly
(Incorporate / the `in ~R` placement strawman); a computed delay
(`sleep(bd)` off a register read) is per-firing already. This is
ordinary provenance discipline, not a new rule — but it is the
kind of mistake completion could catch (a paced gate at ancestor
context is almost certainly wrong).

### The leaning: the flow operation, for the company it keeps

Option (c) is the shape the record's own grain predicts. End-when
is a binary flow operation (subject, stop) consuming a per-firing
case flow; interrupt consumes an event; paced consumes a
per-firing async value's settlement. Three members of one family
— *the walk's own data reshaping the walk* — one ending it, one
cutting it from outside, one spacing it. And (c) is strictly more
expressive than (a): a paced flow need not be self-driven.
Rate-limiting a walk over a work list — one API call per second
over a thousand-element list — is the same construct applied to a
sourced flow, and it is a real program shape (the RxJS sighting
is precisely pacing over sourced streams). A pace port fused into
`open self` can never reach it; that asymmetry is what kills the
fused-only form (dead end 3). Whether the fused port survives as
sugar for the common case is a surface question, deferred with
naming.

Failability composes for free: if the gate fails, the paced flow
terminates with that payload, propagate-by-default — the backoff
loop's give-up guards land on the ordinary failability machinery.

### What is genuinely open: who is gated

The sharp residue. Streams are demand-driven with memoized cells,
and one flow collected twice is one logical iteration. If
consumer A consumes `paced(~R, 5s)` and consumer B collects `~R`
bare — or paces it differently — demand reaches `~R`'s cells
through the faster path, and the slower consumer's pacing gates
only itself. Per-consumer pacing (an honest reading of the flow
operation) and per-source pacing (what the field programs mean —
the *poll* happens every 5 seconds, full stop) genuinely differ
under multi-close. End-when has the same coexistence structure
(subject-flow and shortened-flow consumers; its open question 4),
which suggests the two questions want one answer — likely from
the same conversation. For the sampled programs the difference is
invisible (every sighting has a single consumer chain), so the
leaning is to adopt the per-consumer semantics the operation
naturally has and record the per-source demand as the open bit.
Open question 2.

## The external pull source

### The shape

The other species: an outside iterator — `next() ?T`, `getline`,
jq's `input` — consumed until *it* says stop. The discriminator
between the species is **who terminates**: a pull source's extent
belongs to the outside (exhaustion arrives as data); a self-driven
flow's extent belongs to the program (a terminator-writer ends
it). Ruby 9's poll loop is self-driven (the *status field* ends
it, not the connection); python 4's pump is a pull source whose
sentinel handling is layered on top. Programs mix them freely;
the vocabulary should keep them distinct.

The node: a mint whose output is a **failable stream** —

```
lines = source js "() => getline(false)"    -- provisional
lines -> open stream => line, ~P
```

with the outside's three answers mapped onto designed vocabulary:
a value is a firing; exhaustion is the stream's termination event
(RanOut); a raise is the terminator payload (Fail). That mapping
is fixed, not configurable — it is exactly the failable-source
row the Zig round sighted (`else |err|`), and configurability
here would just relitigate failability.

### Block or composition?

The pull source has a candidate lowering in existing (and
pending) vocabulary: a self-driven flow + a per-firing effectful
pull + a case split on exhausted + end-when (exclusive). B4's
transcription is literally this drawing. So is the pull source a
catalog block with a derived lowering, like merge and interrupt?
The leaning: **yes, a catalog block — and the block boundary is
load-bearing**, for two reasons beyond convenience:

1. **The lowering crosses the Tier-1 hole.** The per-firing pull
   is an effectful read; effect-handle threading under a flow is
   undesigned. The block encapsulates the undesigned interior at
   a boundary the language can already speak (a node minting a
   failable stream) — the same move the async round made for push
   sources ("an async stream whose cell resolution is wired to
   event arrival": an adapter whose interior is outside the
   language). When the effects round lands, the lowering becomes
   a real derived view; until then the block is the only honest
   form.
2. **The mapping is invariant.** Exhaustion→RanOut, raise→Fail,
   value→firing is the same seven statements every single use
   would repeat. A fixed pattern every use repeats is the
   definition of a catalog block.

### Push and pull, the pair

The async round designed the push adapter (external event
sources: arrival-resolved cells, buffer-vs-latest, the retention
question). This node is its pull sibling; together they cover the
FFI source surface, and they should be presented as a pair — same
boundary, opposite driver. Everything the async round left open
for push (retention/windowing — its open question 3) applies to
pull sources verbatim and stays exactly as open; nothing here
moves it. One asymmetry worth recording: pull sources are
naturally single-pass (the outside advances when called), so the
memoized-cells retention hazard is *smaller* here only if nobody
keeps the head — the same "cursor-based GC" note, referenced not
re-decided.

## Worked examples, revisited

The transcriptions that motivated the round, redrawn with the
worked forms (spellings still provisional):

**The counter while (Zig's doubling loop)** — unchanged from
`zig-comparison.md` §1 except its first line is now a designed
node rather than a placeholder:

```
open self => ~R
~R ~> delay init 1 => i
i -> mul(2) -> step of i
i -> lt(2000) -> split id of Go, Done => c
~R, ~c.Done ~> end-when => ~W
```

**The beginner generator (Effekt's `fib()`)** — the blocked
canonical producer, unblocked:

```
open self => ~R
~R ~> delay init 0 => a
~R ~> delay init 1 => b
b -> step of a
a, b -> add -> step of b
a -~> collect first(10) ~R => tenFibs      -- bounded demand
```

(the bounded-prefix consumer is stream vocabulary; its spelling
is owed with the collect family's round.)

**Poll-until with pacing (ruby 9)** — C2's transcription, with
the pacing line now a construct instead of a dangling effect:

```
open self => ~R
~io ~> poll(url) in ~R => resp, ~io'       -- effect gap, unchanged
resp -> parse -> get("status")
     -> split statusTag of Pending, Success, Other => st
~st.Other: -> fail
sleep(5) in ~R => d                        -- per-firing timer
~R, d ~> paced => ~R'                      -- next poll waits 5s
~R', ~st.Success ~> end-when => ~W
~W ~> discharge => term
```

(The effect gap is still the effect gap — the poll itself remains
Tier-1 territory. What changed: the `sleep` is wired, and the
program's pacing is part of its reading.)

**Backoff reconnect (survey 3, websockets 1)** — the register
ladder plus pacing, the +1 test the surveys flagged:

```
open self => ~R
~R ~> delay init BACKOFF_MIN => bd
…attempt in ~R…  -> split outcome of Ok, Err => o
~o.Err:  bd -> mul(F) -> min(BACKOFF_MAX)  -~> …  -- escalate
~o.Ok:   BACKOFF_MIN                       -~> …  -- reset
…merged -> step of bd                             -- conditional carry (A4)
sleep(bd) => d
~R, d ~> paced => ~R'
```

Pacing composes with the conditional-carry register exactly as
the survey's +1-ladder claim hoped; jitter still needs
randomness, which is an effect, which is still the effect gap.

**To-fixpoint iterate (APL `f⍣≡`)**:

```
open self => ~R
~R ~> delay init x0 => s
s -> f -> step of s
s -> eq(prev s)? …                          -- converged test
~R, ~c.Converged ~> end-when => ~W          -- final s off ~W
```

**The pump (B4)** — with the pull source as a block, the drawing
shrinks to the sentinel-and-payload logic that is actually the
program; the source line stops being seven pending statements.

## Against the philosophy

- **Example first.** Both nodes are generalized from sampled
  programs (six of sixty loops; seven independent witnesses), not
  declared structure. The bare opener adds *nothing* beyond what
  the examples demanded — no index, no count, no body.
- **Inside-out.** No scope is introduced anywhere: the flow is a
  wire, carried state is register ports, pacing is a wire into a
  flow operation. Nothing inside a self-driven walk sees
  differently than outside it.
- **Foundations before features.** The pull source's interior is
  deliberately *not* designed here — it waits for the effects
  round rather than smuggling an effect story in through an FFI
  node.
- **Programmer's abstraction level.** "Repeat, carrying the
  backoff, paced by it, until success" — four constructs, four
  words of the sentence, each independently swappable.
- **No bottlenecks.** Nothing is packed to cross anything: paced
  passes its subject flow through as itself and observes only
  settlement of its gate.
- **Abstraction as source of truth.** The race round's derived
  lowerings (merge, interrupt) become drawable programs; the
  pull source's lowering will become one when effects land.
  Derived views now have a floor to land on.
- **Graceful expansion.** The ladder holds: bare repeat → +end-when
  (until) → +register (carry) → +paced (spacing) → +failability
  (give-up legs) — each +1 is an added node. The one seam
  (counted→conditional swaps the opener) is stated above with
  both readings, not smoothed over.

## Open questions

1. **Pace's operand sort.** An async value whose settlement is
   observed and value discarded (the leaning — it matches "a
   timer is an async value" and needs no new wire sort), or a
   flow input (a fires-once-per-firing flow gating advancement)?
   Discarding a value's value is faintly unidiomatic; a flow
   operand is faintly circular (which firing of the gate flow
   gates which firing of the subject?). Lay both before the
   conversation.
2. **Per-consumer vs per-source pacing under multi-close.** The
   flow operation is naturally per-consumer; the field programs
   mean per-source; the difference is invisible at one consumer.
   Likely wants one answer with end-when's coexistence question
   (its open question 4).
3. **The counted↔conditional seam.** Range-as-data vs
   self-driven+counter as the primary authoring path for bounded
   repetition, and whether the editor offers the swap as a
   gesture. Belongs with the iteration-state surface conversation.
4. **The pull source's single-pass discipline.** Memoized cells
   make re-walking an already-pulled prefix legal; is that a
   feature (replay) or a retention trap (the async round's
   question 3, verbatim)? Reference, don't fork.
5. **A checkable "nothing ends this collect" property.** A
   whole-flow collect over an unshortened self-driven flow never
   terminates. Whether checking should flag it (and whether
   completion should *suggest* an end-when) files to the checking
   row.
6. **Naming.** `open self` / `repeat`; `source`; `paced` /
   `throttle` / `gate`. Deferred, per tradition, to the naming
   sweep.

## Dead ends (this round)

1. **A firing-index value port on the bare opener.** An ambient
   counter nobody wired — the index-origin clash the APL round
   recorded, and `cur_column()`'s cousin. The counter is a
   two-statement register when wanted; counted repetition is
   range data. Do not revisit.
2. **Pacing as effect sequencing only.** "Sleep, then the flow
   advances" restates the hole (no wire connects the effect to
   advancement), blocks a frequently-pure need (timers) on the
   Tier-1 round, and leaves the paced *reading* undrawn. The
   effects round may later give paced programs an additional
   lowering; it cannot be the design.
3. **The pace port as opener-configuration only** (no flow
   operation). Dies on the rate-limited walk over a data source:
   pacing a sourced flow is the same construct and a real field
   shape (RxJS sighting), unreachable from a port that exists
   only on `open self`. Whether the fused port exists as *sugar*
   stays open; as the only form it is dead.
4. **"Self-driven" as a sixth flow kind.** Same knife as
   list-with-state (equivalence round, dead end 2): every collect
   behaviour is the stream's, so it is a stream opened
   differently — a node, not a row. A kinds-table row would fork
   the table for no kind content.

## What this doesn't address

- **Per-firing effects.** Every example above that touches the
  world still crosses the Tier-1 hole; this round wires the
  *repetition* and its *spacing*, not the effects. The pull
  source's block boundary is explicitly a fence around that hole,
  not a fix for it.
- **The served flow and the server-program question.** A server
  is not just a self-driven accept loop; that row's round is
  still owed (with the recursive provider and keyed cache demands
  filed on it).
- **Entry opens** (a program's own inputs as sources) — sibling
  edge vocabulary, still with the translation exercise's items.
- **Push-source retention/windowing** — async round, question 3,
  untouched.
- **Implementation.** Stream and async runtimes don't exist in
  the compiler; nothing here changes the implementation path
  (`implementation-strategy.md`).
