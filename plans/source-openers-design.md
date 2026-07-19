# Source Openers: Repetition Without a Source, and the External Pull

Status: exploration — this chapter teaches leanings, not an adopted
design; read every construct here as "a candidate and the case for
it." Nothing is implemented; the stream and async runtimes this
chapter presumes do not exist in the compiler yet.

## A loop with nothing to open

Every iteration in the language so far starts from a *value* you
open: a list opens into a per-element flow, an option into a
fires-or-not flow. But suppose you want the first ten Fibonacci
numbers. There is no list of Fibonacci numbers lying around to open
— the repetition itself *is* the program. What you need is a node
that simply asserts that something repeats:

```
open self => ~R          -- mints a self-driven flow; nothing feeds it
```

No value goes in. No value comes out. The node's one output is a
flow, `~R`, on which things can now happen once per firing. A flow
made this way — repetition with no source — is called a
**self-driven flow**, and this chapter designs the node that mints
it.

Here is the Fibonacci program in full (spellings in this chapter are
provisional placeholders; naming is deferred):

```
open self => ~R
~R ~> delay init 0 => a
~R ~> delay init 1 => b
b -> step of a
a, b -> add -> step of b
a -~> collect first(10) ~R => tenFibs      -- bounded-prefix demand
```

Walk through it. `delay init 0` puts a **register** on the flow: a
value carried across firings, starting at 0. Reading the register
(`a`) gives the value carried *into* the current firing; the `step
of a` statement — the register's **write half**, wired later in the
text — supplies the value carried into the *next* firing. With two
registers stepping each other, `a` and `b` walk the Fibonacci
recurrence, and the last line collects the first ten values of `a`.
(The bounded-prefix collect is stream vocabulary; its spelling is
owed with the collect family's round.) In Effekt this program is the
canonical beginner generator — `fib()`, yielding forever — and until
this node existed it could not even be started on the page.

This document designs the openers for the two common shapes of
iteration that have no value to open:

- **The self-driven flow** — repetition with no source. A recurrence
  (Fibonacci has no inlet), a poll loop, a retry, a producer that
  yields forever. The program *asserts* that something repeats;
  nothing on the page supplies the elements.
- **The external pull source** — an outside iterator (`next() ?T`,
  `getline`, jq's `input`) consumed until *it* says stop.

Plus **pacing**, a piece of meaning that lives inside the
self-driven flow: when the next firing must wait on a per-firing
async value — sleep between polls, a backoff timer before
reconnecting — *what gates firing n+1?*

## The words this chapter leans on

You met most of these in the example above; here they are gathered
once, with where each one is designed:

- An **uncollect** (spelled `open`) opens a value into a flow; a
  **collect** closes one.
- A **register** carries loop state across firings, its **write
  half** wired as a later statement
  (`iteration-with-state-design.md`, `first-class-ports-design.md`).
- **Productivity** is the check that every cycle crosses a register.
- **End-when** shortens a flow from the consumer side; **terminator
  discharge** reads its final value (`end-when-design.md`).
- The **async cell** and **settlement** are from
  `async-flow-design.md`.

## Where this shows up in real code

The self-driven flow reads like a theoretical edge case when you
only meet it through Fibonacci. The loop surveys correct that:
polling, retrying, and producing are how ordinary code talks to the
world (`real-loop-survey.md`). The demand is measured, not assumed.
Six of sixty randomly sampled loops (survey classes 4–5) **cannot
even be started on the page** today (`translation-exercise.md`,
finding 3), and the plainest imperative counter loop lands here too
— so this opener gates ordinary iteration, not just exotic pumps and
generators (`zig-comparison.md`, finding 2).

Independent witnesses, each arrived at separately:

| Witness | What it showed |
|---|---|
| `translation-exercise.md`, finding 3 | Survey classes 4–5 cannot start on the page; `repeat -> open self` and `source js "…"` invented on the spot as placeholders. |
| Effekt comparison | The canonical beginner generator (`fib()` yields forever) is blocked on exactly this node. |
| Flix comparison | Recursive channel producers are self-driven sources, hand-built from recursion. |
| XQuery/jq comparison | jq's `while`/`until`/`repeat`/`recurse(f; cond)` are the self-driven source hand-built; `input`/`inputs` sight the pull species. |
| APL comparison | Power (`⍣`) is the bounded / to-fixpoint iterate. |
| `zig-comparison.md`, finding 2 | The counter `while` — the imperative ground floor — transcribes onto this node; the stdlib's whole iteration story is pull-until-null (`next() ?T`). |
| Reactive comparison | The Elm Architecture's subscriptions, DOM events, and port messages are source openers. |

**Pacing** has its own sightings, all one shape — a self-driven flow
whose next firing waits on a per-firing async value:
sleep-between-polls, the backoff reconnect (step the delay register
on the failure leg, reset on success), a retry timer,
retry-middleware policy, and RxJS `concatMap`'s unbounded-buffer
warning (the same hole read from the backpressure side). The retry
composite — the surveys' named expansion test — cannot be assembled
without it.

Two other designs already *presuppose* this node. The race barrier's
derived combinators (merge, interrupt, timeout) lower to
"corecursive, self-driven walks" (`race-barrier-design.md`) —
derived views onto a construct that cannot yet be drawn. And the
port form of iteration state needs to *borrow* a flow-minting node
for the self-driven corner to be authorable at all
(`iteration-with-state-design.md`). A node two other designs
reference and nobody has designed is the debt this document closes
on paper.

## What earlier rounds already fixed

Most of the design is assembling constraints the record has already
fixed.

1. **The node exists and its reading is settled.** A link with no
   external source is "an uncollect with no `src` — a node that
   *mints* the self-driven flow"
   (`iteration-with-state-design.md`). The self-driven corner is the
   one place reading a node *as* an opener is right, because there
   the flow must be minted by something rather than derived from a
   value. This document finishes that node; it does not redesign it.

2. **What ends it is already designed.** The composition is three
   separately-variable words: the self-driven flow says *repeat*, a
   register says *what carries*, end-when says *until*
   (`end-when-design.md`). Interrupt covers event-driven endings.
   This document adds no termination machinery. A self-driven flow
   with no consumer-side shortening simply never ends — and that is
   its meaning; an infinite producer is a real program.

3. **State is ports on a flow, never a kind of flow.**
   "List-with-state" was rejected as a flow kind because a kind with
   no kind content forks every row of the kinds table. The same
   knife forbids "self-driven" becoming a sixth row (see "Is bare
   repetition a new flow kind?").

4. **Corecursion stays behind catalog blocks.** (Corecursion: a walk
   that manufactures its own next step from its previous one —
   hand-rolled cursor bookkeeping.) Manual cursor bookkeeping is
   "the assembly language of iteration." Catalog blocks
   (decision-driven merge, async merge, interrupt) own the walks
   whose lowerings are corecursive: nobody should author the
   recursion; everybody should be able to read it as the derived
   view (`race-barrier-design.md`). The opener must not read as a
   license to hand-roll those walks.

5. **Failability is a uniform dimension.** Any kind's termination
   event can carry a payload (`async-flow-design.md`). An external
   pull that throws is a failable source — Zig's
   `while (it.next()) |v| … else |err|` is that terminator payload
   in the wild (`zig-comparison.md`, finding 4). The pull source
   gets failure for free.

## The self-driven opener, in full

One node: no value inputs, no value outputs, one flow output — the
mint. That is the `open self => ~R` you saw at the top.

Now, you might wonder why the node isn't spelled
`repeat -> open self => ~R` — that is how the translation exercise
first wrote it. But the `repeat ->` operand is scaffolding. An
uncollect opens a value into a flow; here there is no value, so the
honest form has an empty operand position — which is itself the
clearest statement of what the node is.

Everything per-firing on a self-driven flow comes from elsewhere,
and every "elsewhere" is already designed:

- **carried state** — registers: `~R ~> delay init x => r`, with
  `step of r` wired later as the write half;
- **ancestor values** — provenance's prefix rule admits them
  directly, no transport (`bundle-provenance-design.md`);
- **the outside world** — per-firing effectful reads (the effects
  "Tier-1" hole, unchanged here) or per-firing async values (timers,
  designed).

So the opener has no per-firing value of its own, and the port
inventory says so. In particular, you might wonder why the opener
doesn't offer a **firing index** — surely a loop should know which
iteration it's on? It turns out an ambient index is a magic value
nobody wired — the index-origin clash recorded against
`apl-family-comparison.md` and `tidyverse-comparison.md`'s
`cur_column()`. The counter is a register when a program wants one
(two statements); counted repetition is range data (see below).
(This is a recorded dead end — dead end 1; please don't re-propose
it without new evidence.)

**Identity and sharing** are by node identity, like everything else:
two `open self` nodes are two independent flows; sharing is binding
the handle once.

**Extent is unbounded** — the opener asserts repetition, not a
count. All shortening is consumer-side and already owned: end-when
(data says stop), interrupt (an event says stop), a stream
consumer's bounded demand (a `take`-shaped prefix, like the
`first(10)` in the Fibonacci program). A whole-flow collect over an
unshortened self-driven flow does not terminate — the same standing
status as any infinite stream, not a new hazard. Whether "no
terminator writer reachable from this collect" should be a checkable
property is filed to the checking work, not answered here.

**`final`** on an unshortened self-driven flow is never available —
the residue `first-class-ports-design.md` already records. With
end-when in the room the readout anchors to the shortened extent;
the fine print (which extent, when subject-flow and shortened-flow
consumers coexist) is end-when's open question, inherited not
re-opened.

## Is bare repetition a new flow kind?

Now, you might wonder whether the self-driven flow deserves its own
row in the flow-kinds table — a "self-driven stream" kind beside
list, case, stream, async, and incremental.

**Leaning: no.** The minted flow *is* a stream — the sourceless
instantiation of the existing stream kind — and paced or awaited
firings make it an async stream. No new row.

Here is the argument. A kind earns its row by its open behaviour and
its collect behaviour. The self-driven flow's collect behaviour is
entirely a stream's (collect a prefix, reduce-collect over a
shortened extent, effects per firing). Its open behaviour differs
from a list's in exactly one respect: firings are minted by demand
rather than read from a value — which is precisely the stream row's
"each element, on demand" with the element column empty. A kind
whose every behaviour is another kind's is not a kind; it is that
kind, opened differently. The opener is a new *node*, not a new
*row*. A kinds-table row would fork the table for no kind content —
the same knife that cut "list-with-state." (This is a recorded dead
end — dead end 4; please don't re-propose a sixth row without new
evidence.)

The async grade arrives compositionally, as everywhere else: the
moment a firing's advancement waits on settlement — a paced flow, or
carried state that is itself async — the flow is an async stream,
and the async round's machinery (cells, sequential-is-nesting,
interrupt at the pull boundary) applies unchanged. The pure
Fibonacci and the paced poll loop are one construct at two grades,
not two constructs.

## Counted repetition is data

"Do it n times" does not reach for this opener. A known count is
data: open a range value (`0..n` as a list or stream) and the walk
has n firings. The Zig round endorsed this from the other side — an
index is "one more aligned lane," `for (items, 0..)`. APL's power
operator splits exactly here: `f⍣n` (bounded) is a register walked
over a range; `f⍣≡` (to fixpoint) is a register on a self-driven
flow with end-when on "the step changed nothing" — a comparison of
the register's previous value with its new step value, both ordinary
wires (no `prev` operator; that shape is rejected,
`iteration-with-state-design.md`).

The rule: **if the data knows the extent, the extent is data; if
only the walk can discover it, the walk is self-driven and a
terminator-writer ends it.**

This leaves a seam, stated rather than smoothed over: moving a
program from "10 times" to "until converged" swaps the opener — a
range uncollect becomes `open self` + end-when. Principle 7
(graceful expansion) frowns at rewrites. Two readings:

- The bounded form *is* drawable self-driven (counter register +
  end-when), so the ladder is buildable if authored that way, and
  the range form is the fused special case — many authoring paths,
  one reading each.
- Or the swap is honest, because the program's *meaning* changed:
  its extent moved from data to discovery, and a construct change
  that tracks a meaning change is what the abstraction principle
  wants.

The leaning is the second reading, with the first recorded as live.
The choice has surface consequences (does the editor offer a "make
this count conditional" gesture?) that belong with the
iteration-state surface work. This is open question 3 — the language
hasn't decided it yet.

## The corecursion boundary

The opener makes corecursive programs *writable*, yet the record
deliberately declines to hand users raw corecursion. These
reconcile:

**The opener is for programs whose repetition is the program's
meaning; it is not for encoding walks that a catalog block owns.**
Poll-until, produce-forever, iterate-to-fixpoint,
retry-with-backoff: in each, "repeat" is what the program *says*,
and the drawing (opener + registers + end-when) is at the
programmer's abstraction level — each node a word of the sentence.
The ordered merge's cursor pair, interrupt's race-at-every-pull,
merge's carried loser: in each, the self-driven walk is an
*encoding* of a higher construct, and hand-authoring it is the
assembly language. The catalog blocks stay. What the opener changes
is that their derived lowerings become *real programs* — readable,
drawable views — instead of prose descriptions of a node that
doesn't exist. Derivation is downward and free, and now the floor it
lands on exists.

(The checking work may eventually want the soft version of this
boundary a linter would enforce — "this self-driven walk is
recognizably an ordered merge" — but that is completion machinery,
and nothing here depends on it.)

## Pacing

Suppose your program polls a server, and you want five seconds
between polls. Today a sleep between polls is just an effect op, and
no wire connects it to the flow's advancement
(`translation-exercise.md`, finding 3). The missing piece is a
meaning, not a spelling. The question: *what gates firing n+1 of a
self-driven flow?* Unpaced, the answer is "demand alone." Paced, it
must be "demand, and not before this firing's gate settles."

Three candidate homes for that meaning:

**(a) A pace port on the opener.** The opener grows an optional
on-cycle operand, late-wired like the register's step
(`pace of R`): a per-firing value whose settlement gates the next
firing. Structurally comfortable — the `<port> of <name>` form
already exists for on-cycle operands, and the pace edge is a
computation cycle crossing the opener, a sibling of the write→read
pairing, so productivity extends naturally.

**(b) Effect sequencing.** You might wonder why pacing isn't just
"the sleep is an effect; the flow's advancement is sequenced after
it." It turns out this is not a design but a restatement of the
hole: it is blocked on the effects round, and it couples pacing
(which is often *pure* — a timer is an async value, not an effect)
to the effect story unnecessarily. The effects round may later give
paced programs an additional lowering; it cannot be the design.
(This is a recorded dead end — dead end 2; please don't re-propose
it without new evidence.)

**(c) A binary flow operation.** `paced(F, g)`: flow in, plus a
per-firing async value `g` computed in the walk; delayed flow out.
Firing n of `~R'` is firing n of `~R`; firing n+1 of `~R` is
demanded only after `g` at firing n settles; the first firing is
ungated; `g`'s value is discarded — only settlement is observed.

```
open self => ~R
…                                -- the attempt, computed in ~R
sleep(5) in ~R => d              -- per-firing timer
~R, d ~> paced => ~R'            -- next firing waits for d to settle
```

One wrinkle the drawing must not hide: the gate must be **minted per
firing**. A node's context comes from its operands, so a `sleep(5)`
fed only a constant would sit at ancestor context — one shared
timer, settled once, gating nothing after the first firing. A
constant delay therefore enters the walk explicitly (Incorporate,
spelled `in ~R`); a computed delay (`sleep(bd)` off a register read)
is per-firing already. This is ordinary provenance discipline, not a
new rule — but a paced gate at ancestor context is almost certainly
wrong, and completion could catch it.

**Leaning: the flow operation (c).** It is the shape the record's
grain predicts. End-when is a binary flow operation (subject, stop)
consuming a per-firing case flow; interrupt consumes an event; paced
consumes a per-firing async value's settlement — three members of
one family, *the walk's own data reshaping the walk*: one ending it,
one cutting it from outside, one spacing it.

And (c) is strictly more expressive than (a): a paced flow need not
be self-driven. Rate-limiting a walk over a work list — one API call
per second over a thousand elements — is the same construct on a
*sourced* flow, and a real shape (the RxJS sighting is pacing over
sourced streams). You might wonder whether the pace port of (a)
could be the whole story, with no flow operation. It turns out a
pace port fused into `open self` can never reach the rate-limited
sourced walk; that asymmetry kills the fused-only form. (This is a
recorded dead end — dead end 3.) Whether the fused port survives as
*sugar* for the common case is a deferred surface question — set
aside, not rejected.

Failability composes for free: if the gate fails, the paced flow
terminates with that payload, propagate-by-default — the backoff
loop's give-up guards land on the ordinary failability machinery.

**What is genuinely open: who is gated.** Streams are demand-driven
with memoized cells, and one flow collected twice is one logical
iteration. If consumer A consumes `paced(~R, 5s)` and consumer B
collects `~R` bare — or paces it differently — demand reaches `~R`'s
cells through the faster path, and the slower consumer's pacing
gates only itself. Per-consumer pacing (the honest reading of the
flow operation) and per-source pacing (what the field programs mean
— the *poll* happens every 5 seconds, full stop) genuinely differ
under multi-close. End-when has the same coexistence structure,
which suggests the two questions want one answer. For every sampled
program the difference is invisible (single consumer chain), so the
leaning is to adopt the per-consumer meaning the operation naturally
has and record per-source demand as the open bit. Open question 2 —
undecided.

## The external pull source

The other species: an outside iterator — `next() ?T`, `getline`,
jq's `input` — consumed until *it* says stop. The test that
separates the two species is **who terminates**: a pull source's
extent belongs to the outside (exhaustion arrives as data); a
self-driven flow's extent belongs to the program (a
terminator-writer ends it). A poll loop whose *status field* ends it
is self-driven; a pump whose sentinel arrives from the source is a
pull source. Programs mix them freely, so the vocabulary keeps them
distinct.

The node is a mint whose output is a **failable stream**:

```
lines = source js "() => getline(false)"    -- provisional
lines -> open stream => line, ~P            -- each line is a firing
```

The outside's three answers map onto designed vocabulary: a value is
a firing; exhaustion is the stream's termination event (RanOut); a
raise is the terminator payload (Fail). That mapping is **fixed, not
configurable** — it is exactly the failable-source row Zig sighted
(`else |err|`), and configurability here would just relitigate
failability.

**Block or composition?** The pull source has a candidate lowering
in existing (and pending) vocabulary: a self-driven flow + a
per-firing effectful pull + a case split on exhausted + end-when. Is
it a catalog block with a derived lowering, like merge and
interrupt?

**Leaning: yes, a catalog block — and the block boundary is
load-bearing**, for two reasons beyond convenience:

1. **The lowering crosses the effects hole.** The per-firing pull is
   an effectful read, and effect-handle threading under a flow is
   undesigned. The block encapsulates the undesigned interior at a
   boundary the language can already speak (a node minting a
   failable stream) — the same move the async round made for *push*
   sources (an adapter whose interior is outside the language). When
   effects land, the lowering becomes a real derived view; until
   then the block is the only honest form.
2. **The mapping is invariant.** Exhaustion→RanOut, raise→Fail,
   value→firing is the same handful of statements every use would
   repeat. A fixed pattern every use repeats is the definition of a
   catalog block.

**Push and pull are a pair.** The async round designed the push
adapter (external event sources: arrival-resolved cells,
buffer-vs-latest, the retention question). This node is its pull
sibling; together they cover the FFI source surface — same boundary,
opposite driver — and should be presented together. Everything the
async round left open for push (retention/windowing) applies to pull
verbatim and stays exactly as open. One asymmetry: pull sources are
naturally single-pass (the outside advances when called), so the
memoized-cells retention hazard is smaller here only if nobody keeps
the head — the same "cursor-based GC" note, referenced not
re-decided.

## Worked examples

Spellings provisional, as throughout.

**The counter while (Zig's doubling loop).** Only the first line
changed from the translation exercise — a designed node instead of a
placeholder:

```
open self => ~R
~R ~> delay init 1 => i
i -> mul(2) -> step of i
i -> lt(2000) -> split id of Go, Done => c
~R, ~c.Done ~> end-when => ~W          -- stop when i reaches 2000
```

**The beginner generator (Effekt's `fib()`)** — you met it at the
top of this chapter: the blocked canonical producer, unblocked. Two
registers stepping each other, and a bounded-prefix collect.

**Poll-until with pacing (a poll loop):**

```
open self => ~R
~io ~> poll(url) in ~R => resp, ~io'       -- effect gap, unchanged
resp -> parse -> get("status")
     -> split statusTag of Pending, Success, Other => st
~st.Other: -> fail
sleep(5) in ~R => d                        -- per-firing timer
~R, d ~> paced => ~R'                      -- next poll waits 5s
~R', ~st.Success ~> end-when => ~W         -- stop on success
~W ~> discharge => term
```

The poll itself is still effects territory; what changed is that the
sleep is now *wired* and the pacing is part of the program's
reading.

**Backoff reconnect** — the register ladder plus pacing:

```
open self => ~R
~R ~> delay init BACKOFF_MIN => bd
…attempt in ~R…  -> split outcome of Ok, Err => o
~o.Err:  bd -> mul(F) -> min(BACKOFF_MAX)  -~> …  -- escalate
~o.Ok:   BACKOFF_MIN                       -~> …  -- reset
…merged -> step of bd                             -- conditional carry
sleep(bd) => d
~R, d ~> paced => ~R'
```

Pacing composes with the conditional-carry register exactly as the
+1 ladder hoped. Jitter still needs randomness, which is an effect —
still the effect gap.

**To-fixpoint iterate (APL `f⍣≡`):**

```
open self => ~R
~R ~> delay init x0 => s                    -- s = the previous state
s -> f => s'                                -- one improvement step
s' -> step of s                             -- carry it
s, s' -> eq -> split conv of Converged, Improving => c
~R, ~c.Converged ~> end-when => ~W          -- stop when a step changes nothing; final s' off ~W
```

The convergence test needs no `prev` operator: the register's read
(`s`) *is* the previous value and the step (`s'`) is the new one, so
`state = prev state` is an ordinary comparison of two wires already
in hand.

**The pump** — with the pull source as a block, the drawing shrinks
to the sentinel-and-payload logic that is actually the program; the
source line stops being a run of pending statements.

## Against the philosophy

- **Example first.** Both nodes generalize from sampled programs
  (six of sixty loops; the witness list), not declared structure.
  The bare opener adds nothing beyond what the examples demanded —
  no index, no count, no body.
- **Inside-out.** No scope is introduced: the flow is a wire,
  carried state is register ports, pacing is a wire into a flow
  operation. Nothing inside a self-driven walk sees differently than
  outside it.
- **Foundations before features.** The pull source's interior is
  deliberately *not* designed here — it waits for the effects round
  rather than smuggling an effect story in through an FFI node.
- **Programmer's abstraction level.** "Repeat, carrying the backoff,
  paced by it, until success" — four constructs, four words, each
  independently swappable.
- **No bottlenecks.** Nothing is packed to cross anything: paced
  passes its subject flow through as itself and observes only its
  gate's settlement.
- **Abstraction as source of truth.** The race barrier's derived
  lowerings (merge, interrupt) become drawable programs; the pull
  source's lowering becomes one when effects land. Derived views now
  have a floor to land on.
- **Graceful expansion.** The ladder holds: bare repeat → +end-when
  (until) → +register (carry) → +paced (spacing) → +failability
  (give-up legs) — each +1 an added node. The one seam
  (counted→conditional swaps the opener) is stated above with both
  readings.

## Open questions

The language hasn't decided any of these yet.

1. **Pace's operand sort.** An async value whose settlement is
   observed and value discarded (the leaning — matches "a timer is
   an async value," no new wire sort), or a flow input (a
   fires-once-per-firing flow gating advancement)? Discarding a
   value's value is faintly unidiomatic; a flow operand is faintly
   circular. Both go before the conversation.
2. **Per-consumer vs per-source pacing under multi-close.** The flow
   operation is naturally per-consumer; the field programs mean
   per-source; the difference is invisible at one consumer. Likely
   wants one answer with end-when's coexistence question.
3. **The counted↔conditional seam.** Range-as-data vs
   self-driven+counter as the primary authoring path for bounded
   repetition, and whether the editor offers the swap as a gesture.
   Belongs with the iteration-state surface conversation.
4. **The pull source's single-pass discipline.** Memoized cells make
   re-walking an already-pulled prefix legal; is that a feature
   (replay) or a retention trap? Same as the async round's
   push-retention question; reference, don't fork.
5. **A checkable "nothing ends this collect" property.** A
   whole-flow collect over an unshortened self-driven flow never
   terminates. Whether checking should flag it (and whether
   completion should *suggest* an end-when) files to the checking
   work.
6. **Naming.** `open self` / `repeat`; `source`; `paced` /
   `throttle` / `gate`. Deferred to the naming sweep.

## Dead ends, gathered

Each of these is presented in full where its topic lives — the "now,
you might wonder" passages above — and gathered here so the record
has one list. All four are settled rejections; please don't
re-propose them without new evidence.

1. **A firing-index value port on the bare opener** — an ambient
   counter nobody wired; the index-origin clash, and
   `cur_column()`'s cousin. See "The self-driven opener, in full."
2. **Pacing as effect sequencing only** — restates the hole, blocks
   a frequently-pure need on the effects round, leaves the paced
   *reading* undrawn. See "Pacing," candidate (b).
3. **The pace port as opener-configuration only** (no flow
   operation) — dies on the rate-limited walk over a data source;
   whether the fused port exists as *sugar* stays open; as the only
   form it is dead. See "Pacing."
4. **"Self-driven" as a sixth flow kind** — every collect behaviour
   is the stream's, so it is a stream opened differently — a node,
   not a row. See "Is bare repetition a new flow kind?"

## What this doesn't address

- **Per-firing effects.** Every example that touches the world still
  crosses the effects hole; this round wires the *repetition* and
  its *spacing*, not the effects. The pull source's block boundary
  is a fence around that hole, not a fix for it.
- **The served flow and the server-program question.** A server is
  not just a self-driven accept loop; that design is still owed
  (with the recursive provider and keyed cache demands filed on it).
- **Entry opens** (a program's own inputs as sources) — sibling edge
  vocabulary, still with the translation exercise's items.
- **Push-source retention/windowing** — async round, untouched.
- **Implementation.** Stream and async runtimes don't exist in the
  compiler; nothing here changes the implementation path
  (`implementation-strategy.md`).
