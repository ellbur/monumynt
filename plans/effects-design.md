# Per-firing effects: the IO thread across a loop

Status: exploration — this chapter teaches a worked proposal with
leanings, prepared for a design conversation. None of it has been
adopted or implemented; read it as "here is a candidate and the case
for it." Its scope is the **effects** half of the Tier-1
IO/effects/cancellation row (`open-problems.md`), and within that the
row's most-cited concrete gap: *causing an effect once per firing of
a loop*. This round deliberately does **not** work cancellation,
bracket, within-firing effect ordering, or bodies-raise — each of
those is fenced off near the end of this chapter, with the reason it
waits.

If you want the background first: `custom-flows.md` teaches the
effect-handle lifecycle (the raw material this chapter builds from),
`core-model.md` teaches value vs flow wires, and
`lazy-stream-commute-design.md` teaches commute — an inner flow
moved outside its enclosing flow — which is the shape this
chapter's answer takes.
The prior-art poles are in `xquery-jq-comparison.md` (the pending
update list), `reactive-comparison.md` (Elm `Cmd`),
`effekt-comparison.md` and `flix-comparison.md` (effects interleaved
mid-computation), and `zig-comparison.md` (the bracket/cancellation
sub-structure this round does not touch).

## The simplest effectful loop

Sooner or later you will want a loop to *do* something — print a line
for each element, write a row for each record — rather than only
compute a value. Here is the smallest such program: print each
element of a list.

```
lines -> open list => line, ~L
in ~io                              -- the console handle, from outside
~io ~> print(line) in ~L => ~io'    -- (provisional spelling)
```

The first line you know from `core-model.md`: open the list, so that
`line` is each element in turn and `~L` is the loop's flow — the
"once per element" context. The new thing is `~io`. It is an **effect
handle**: a flow wire that stands for a resource — here the console;
elsewhere a file, a connection, a tracker. `print` is an **effect
operation**: it takes the handle in, prints once per firing of `~L`
(that is what the `in ~L` clause says), and produces the handle
*after* the operation, `~io'`. Anything that wants to print after
this loop consumes `~io'`, and is thereby ordered after it.

(The spelling here is provisional — pinning it down is this chapter's
open question 1. The *picture* it draws, though, is the chapter's
whole subject: what does that handle do at the two ends of the
loop?)

Doing an effect per firing is the single most common thing sampled
loops do: about 42% of the sampled loops exist for their effects
(`translation-exercise.md` B3). That is what makes this small program
worth a chapter.

## What was already settled before this chapter

Three things are fixed in the record before this round starts, and
the round leans on all three rather than reopening them. Each one
showed up, in miniature, in the print program above.

1. **An effect is an operation on a threaded effect-handle flow.**
   The spec already carries the node: `EffectOperation` performs one
   operation (`print`, `writeLine`, `cancel`, …) on an effect flow,
   taking the flow in and producing the flow *after* the operation
   out; "downstream effect operations must use it to keep sequencing"
   (`visual-language-spec.md`). The lifecycle pattern draws a handle
   as a vertical segment — creation at the top vertex, operations
   strung along the segment, destruction at the bottom — and forbids
   attaching an operation anywhere outside the segment
   (`custom-flows.md`). Note that the handle rides a *flow* wire
   (`~io`), never a value wire; it is a marker with no runtime
   representation (`lazy-stream-commute-design.md`). You cannot
   compute on a handle; you can only string operations along it.

2. **The pole is the sequenced thread, not the collected plan.**
   There are two ways a language can relate effects to a dataflow
   program, and the record has named both poles.
   *Effects-as-collected-plan* gathers effect *descriptions* as
   values and applies them at a barrier — XQuery's pending update
   list, Elm's `Cmd`, jq's edge-only effects.
   *Effects-as-sequenced-thread* interleaves the effects with the
   computation — Effekt and Flix interleave `println` mid-computation
   as a matter of course, and the IO-thread leaning in
   `tough-use-cases-design.md` is the same pole. Effekt states the
   asymmetry that decides it for us: *they* make effects sequential
   by default and concurrency explicit; *we* get concurrency free
   from the DAG and make **sequencing** the explicit, drawn thing
   (`effekt-comparison.md`). The IO thread — a flow wire whose only
   job is to order the operations strung along it — is that drawn
   sequencing. This chapter assumes the thread pole and asks what the
   thread *is* when the operations live under a loop. (The
   collected-plan pole is not discarded — it re-enters below as a
   distinct *batched* construct, for the cases where it is actually
   wanted.)

3. **Ordering among handles is inferred from the definition, per
   handle.** Independent effect handles commute — their operations
   have no structural relationship, so they cross freely, and an
   explicit commute between them would be a no-op
   (`custom-flows.md`). Only same-handle operations are ordered.
   `tough-use-cases-design.md` (break #3, per-session IO) attaches a
   concrete program to this: thread *one* handle through a server and
   every session serialises on it, so IO handles must be mintable per
   firing, with only same-handle operations ordered. Whatever this
   chapter proposes must reproduce that: **the order among per-firing
   effects is exactly the order among the handle threads they run
   on — nothing more.**

## The gap, stated precisely

`translation-exercise.md` B3 is the minimal witness — a real sampled
loop, one conditional effect per element. The source:

```js
for (const key of keys) {
  if (key.match(new RegExp(section + ':'))) {
    this.finishTracker(section, key)
  }
}
```

The filter half is designed vocabulary you have already met
(splitting is from `core-model.md`, joining a case flow into a list
flow is how the language filters):

```
keys -> open list => key, ~K
key -> split matchesSection(section) of Hit, Miss => m
~m.Hit ~> join into ~K => ~hits
```

Then, per firing of `~hits`, call `finishTracker`. Inventing the
minimum — an effect op as a stage on the handle's chain, in the same
provisional spelling as the print program:

```
in ~io
~io ~> finishTracker(section, key) in ~hits => ~io'   -- (provisional)
```

And the translation exercise puts its finger on exactly what nothing
defines: *the op fires per firing of `~hits`, so the handle is inside
the iteration — what is `~io'` outside the loop?* "That is a collect
of an effect flow, which nothing defines. The lifecycle pattern's
`(db', io', result)` tuples are drawn for straight-line code, not for
ops under a flow."

So the whole gap is one question: **when an effect operation runs
once per firing, what does the IO thread do at the two boundaries
where the loop's flow meets the handle's flow — the entry (`~io`
into the loop) and the exit (`~io'` out of it)?**

## Why you can't just read the handle into each firing

Now, you might wonder why the language doesn't just let each firing
read the handle directly. After all, `~io` sits in the enclosing
context, and the prefix rule of provenance tracking admits an
enclosing context's value into a nested flow with no machinery at
all — `add(ten)` inside a loop just works (`core-model.md`). So let
each firing read `~io`, do its effect, and be done.

It turns out this would cause problems, and *why* it is wrong is the
whole design. The prefix rule works by duplicating a value into every
firing — ten copies of `10`, all identical and harmless, because `10`
is not consumed by being used. An effect handle is the opposite of
that: it names a **single-threaded resource** — one file, one
console, one connection — and each operation *consumes* it, producing
the next handle. It is **linear**: it must be used exactly once, not
copied. Read one file handle into ten firings and you have ten
programs each believing it holds the file at its original position.
The record already knows this shape as the register half's wire
linearity — the thread port is consumed exactly once
(`first-class-ports-design.md`). Duplicating a single-threaded
resource into N firings is meaningless; linearity is exactly why the
handle must be threaded through the firings — each firing holding
its own stretch of the handle, following the last firing's — rather
than read in (like a constant). (This is a settled rejection —
please don't re-propose the prefix-read without new evidence.)

## The answer: commuting IO out of the loop sequences the operations

A linear wire that must visit each firing in turn cannot be
prefix-read; each firing holds its own stretch of the handle — the
**segment** of operations that firing performs. So inside the loop,
the IO flow sits nested under the loop's flow: one segment per
firing. The question "what is `~io'` outside the loop?" is then a
question the language already has a word for. An inner flow moving
outside its enclosing flow is a **commute**
(`lazy-stream-commute-design.md`), and the list/IO commute is
*defined* to sequence:

> **Commuting an IO flow out of a list flow concatenates the
> per-firing segments, in firing order, into one segment.** The
> handle enters at the head of the first firing's segment; `~io'` is
> the tail of the last — one handle out, never a list.

That last clause is the answer to the translation-exercise gap.

Sequencing is not a mechanism bolted onto the commute; it is the
only thing the crossing *can* mean, forced by facts the record
already holds. Operations along one segment are ordered by the
segment (`custom-flows.md`). The handle is linear and unique — one
console, one file — so after the loop the N segments cannot sit
side by side: there is only one handle for them to be segments
*of*. Concatenation is the only available shape, and firing order
is the only order the loop offers. Effect *order* therefore falls
out for free, and falls out correctly: the writes land in loop
order — which is what an ordered resource (a file, a log) demands,
and demands without a knob. Nothing is annotated.

The empty loop grounds itself the same way: zero segments
concatenate to nothing, so `~io'` is `~io` — the handle leaves
exactly as it entered, no effects done.

Now, you might wonder why collecting an effect flow doesn't just
yield a list of handles — that was the tempting reading the
translation exercise surfaced, "a collect of an effect flow." It
turns out that was the wrong picture entirely: the handle is a
flow-context marker, not a value, and N firings do not produce N
handles to gather. Their segments concatenate into one, and the
thing outside the loop is that one segment's tail — one marker — not
a collected list. (This is a settled rejection — please don't
re-propose list-of-handles without new evidence.)

One more shape you might reach for and shouldn't: you might wonder
whether the meeting of the loop's flow and the IO flow is a **Cross**
product of the two — Cross being the language's node for combining
flows (`product-flows-design.md`). It turns out this can't be right:
Cross pairs *independent* flows, and the IO thread is the opposite of
independent — firing *i+1*'s segment follows firing *i*'s. There is
no product because there is no independence; there is a
concatenation. (This is a settled rejection — please don't
re-propose the Cross reading without new evidence.)

### You never draw the commute

For the option/stream commute, commuting is a *choice*: the same
option-per-element close is lawful commuted
(`option<stream<X>>`) and uncommuted (`stream<option<X>>`), so the
choice must be drawn. The list/IO commute has no such alternative —
the un-commuted crossing would be the list of handles rejected
above — so for a spanning handle the commute is mandatory and
unique. A mandatory, unique operation needs no glyph. The author
simply strings operations along `~io` inside the loop and consumes
the handle after it; that the handle crossed the boundary — and
therefore that the segments concatenated — is read off the drawing.
This is the same move the language already makes for
under-committed programs: the editor completes what the drawing
determines, faint, and the author never spells it
(`time-travel-programs-design.md`). Collecting the handle at the
end of the loop just does the job.

One ruling from the 2026-07-23 design conversation binds this
section (recorded at `failure-payloads-design.md`, "What fail is —
the ontology note"): "never drawn" means **never authored, never
absent** — implicitly inferring a commute is time travel, and the
language allows time travel only under the completion discipline,
so the implied commute must be inferred by published rule *and
available for the author to see*, faint. The half of open
question 1 below that asked whether the faint completed form is
worth showing at all is answered: showing it is required.

### No register appears (a dissolved reading)

The first working of this round answered differently: "a per-firing
effect is a register whose threaded wire is the IO handle" — the
handle as `init`, each firing's operation as `step`, `~io'` as
`final`, with a three-point map (value register / saturation / IO
thread) unifying the three as back-edges crossing an iteration
boundary. That reading is **dissolved**, and the reason is worth
recording. Every register port is inert for a marker: `prev` ("the
handle so far") admits no reading, the step is just the firing's
segment, `final` is just the segment's tail. All that remained of
the register was the ordering — which the commute definition states
directly. A register that holds a running sum earns its vocabulary:
the reader sees the carried value and the need to carry it. A
register that sequences effects carries nothing and teaches
nothing; it described the operational *lowering* (a threaded fold —
still a fine way to implement the concatenation), not the meaning,
and abstraction is the source of truth
(`language-design-philosophy.md`). The commute reading also keeps
one ordering principle at every level: within a firing, order is
order along the segment (`within-firing-effects-design.md`); across
firings, the crossing concatenates segments — segment order all the
way up, no second order-source introduced by a fold. (Dissolved —
please don't re-propose register-on-a-marker-wire without new
evidence.)

## The two shapes of an effect under a loop

The sequencing commute is the whole story only when the handle
**spans** the loop — enters from outside, exits outside. There is a second,
equally common shape, where the handle **nests** wholly inside each
firing. The two are told apart structurally, by where the handle's
lifecycle vertices sit relative to the loop — the same "inferred from
the definition, not annotated" move `custom-flows.md` already makes
for commutativity.

**Shape 1 — the handle spans the loop (threaded; ordered).** The
handle is created outside the loop and consumed outside it; the
per-firing operations are stages strung along it inside. B3 is this
shape: `finishTracker` writes to a tracker that outlives the loop.
B4's file pump is this shape:

```
~io ~> writeLine(outLine) in ~W => ~io'
```

One file handle, threaded through the `~W` firings, writes in order;
`~io'` is the file after the last line — the tail of the
concatenated segment. The effects are ordered by the loop, because
one resource cannot be in two firings at once.

A property worth naming here, because it is a good one: B4's sibling
in the wild appends to a list instead of writing to the file, and
that is *the same drawing with one statement swapped* —
`~io ~> writeLine(outLine) in ~W` (the handle carried out of the
loop) becomes `outLine -~> collect ~W` (the list readout of the
elements). The effect and the collect are the two ways one loop
crosses its own boundary — the value flow leaves by collect, the
marker flow leaves by the sequencing commute — and swapping between
them is one line.

**Shape 2 — the handle nests inside the firing (independent;
unordered).** The whole acquire/use/release segment sits inside one
firing of the loop — a connection opened, used, and closed for that
firing alone. Then there is **no thread across the loop at all**:
each firing's handle is a fresh, independent resource, and by the
custom-flow rule independent handles commute (commute in
`custom-flows.md`'s independent-handles sense — they reorder freely
past each other — not the nesting commute above). The effects across
firings are unordered, and may run concurrently — which is precisely
the per-session IO requirement (`tough-use-cases-design.md` break
#3): mint the handle per firing and the sessions do not serialise on
each other. Nothing crosses the loop's collect, because the handle
never existed outside it; there is no `~io'` to define. In the
provisional spelling — one scratch connection per request:

```
reqs -> open list => req, ~R
req -> connect => ~s            -- handle minted inside the firing: top vertex under ~R
~s ~> send(req) => ~s'          -- straight-line ops along the handle, no `in` clause
~s' ~> closeConn                -- released within the same firing
```

Every handle vertex sits under `~R`; nothing crosses the boundary,
and the N segments are mutually unordered.

Notice what you never do: pick a mode. The distinction is not
something the author selects; it is *read off the drawing* — does the
handle's top vertex sit outside the loop, or inside a firing?
Spanning ⇒ segments concatenated in loop order ⇒ ordered. Nesting ⇒
N independent segments ⇒ unordered. This is the
ordered-vs-independent fork made structural, and it satisfies the
tough-use-cases constraint without a new rule: "only same-handle
operations are ordered" becomes "only a *spanning* handle crosses
the boundary, and only the crossing orders."

Now, you might wonder why the language doesn't offer an explicit
ordered/unordered switch for effects under a loop anyway — surely the
author knows what they want? It turns out this would cause problems:
the order is not a knob but a structural fact — a spanning handle
concatenates and orders; a nested handle is independent and
unordered.
Selecting a mode would let the drawing and the declared order
disagree, which is the same reason `custom-flows.md` infers
commutativity from the definition rather than from an annotation.
(This is a settled rejection — please don't re-propose an
author-selected mode without new evidence.)

The mixed everyday case sorts itself out. Writing each request's log
line to one shared logfile is Shape 1 on the logfile handle
(ordered) *and*, if each request also opens its own scratch file,
Shape 2 on the scratch handles (independent) — two handles, each
classified by its own lifecycle, no interaction to adjudicate.

## Effects over a product inherit the linearization residue

One honest consequence — not a new problem, but a sharpening of an
existing one. Over a Cross product, a register folds along the axis
its binding collect gathers, fibered over the rest (that is: run
independently for each value of the other axis), and a *full-cube*
fold — folding over the whole grid — needs a linearization: a choice
of which axis runs first. That choice is the open residue of the
loop-carried-state row (`iteration-with-state-design.md`, "The
product, re-read through update-cadence and read-range";
`product-flows-design.md`, question 5). A spanning effect handle
under a doubly-nested loop — both axes writing to one file — must
concatenate segments across the whole grid, and a grid has no
firing order until an axis order is chosen: the concatenation order
**is** that linearization. (Nested loops proper are fine — nesting
supplies lexicographic order, drawn; the residue is the *grid*,
where neither axis encloses the other.)

Here is the difference effects make. For a pure register, the
linearization was "a cost, not a knockout" — a commutative monoid (a
combining operation for which order genuinely doesn't matter, like
addition) discharges the order demand entirely, and only a
non-commutative running-view reader pays. For effects the order is
*observable by construction* — the bytes land in the file in one
order or the other, and no commutativity saves you, because writing
is not commutative. So effects do not open a new question here; they
**remove the escape hatch** from the existing product-linearization
residue, and make settling it load-bearing for any program that
writes under nested iteration. Filed back to the loop-carried-state
and products rows as the observable-stakes version of a question they
already own. (The filing has since been consumed:
`product-linearization-design.md` — exploration, unadopted — works
the residue with the spanning handle as one of its three
order-observing clients. Its answer for this section's case: the
grid's concatenation order is the *drawn orientation* of the crossed
flows — Cross's stored operands plus authored commutes — which
converts the grid case into the nested case this section already
calls fine; an unpinned orientation under a spanning handle fails an
orientation-pinning demand with the handle as witness, and the
never-drawn commute stays never-drawn.)

## What this no longer feeds the open question of what a Delay *is*

The first working of this round, with its register reading, offered
the IO thread as a data point for the live Delay-ontology fork
(`delay-ontology-design.md`, via `iteration-with-state-design.md`):
a linear resource pinned by *use* to the one flow it is threaded
through, a vote for provenance-fixes-the-flow. With the register
reading dissolved, no Delay appears anywhere in the effects story,
and that datum is withdrawn as stated — the weaker observation that
a linear wire's segments are pinned to the loop whose firings hold
them survives, but it is no longer evidence *inside* the Delay
question. The decoupling cuts both ways and both are good: effects
no longer wait on the Delay fork being settled, and the Delay fork
loses a witness it would have had to explain.

## What this chapter does not cover (fenced, with reasons)

Each of these is set aside deliberately — deferred to its own round,
not rejected. The reasons matter, so here they are in full.

- **Cancellation and bracket.** Release-on-abandonment,
  race-implies-cancel, and abandoned pending pulls are the other half
  of the Tier-1 row and are untouched here. Zig supplies the
  sub-structure any bracket design must reproduce — release adjacent
  to acquisition, cleanup keyed by exit reason, the
  acquire-may-fail/release-must-succeed asymmetry, per-firing as well
  as per-flow attachment (`zig-comparison.md`) — but bracket waits on
  cancellation, which waits on this chapter's thread being in place
  first. The thread is the carrier a cancellation capability would
  later ride (`async-flow-design.md` records the constraint that the
  async cell must not preclude threading a cancel token);
  establishing the thread is a prerequisite, not the cancellation
  design. *That round now exists* (`cancellation-design.md`,
  exploration): delivery over the demand frontier, `Cancelled` as a
  terminator lane, the release half consuming this chapter's
  `~io'` — consuming the thread, not changing it; the two rounds
  should go to the adoption conversation together.

- **Within-firing effect ordering (the conditional-flush buffer).**
  This chapter orders effects *across* firings (by the thread) and
  says nothing about two effects *within* one firing whose order is
  entangled with a conditional reset (`real-loop-survey.md`, the
  net/http buffer; `open-problems.md` breadth item 5). That is a
  distinct axis. The threaded handle gives within-firing order the
  same way — operations strung along one segment are ordered by the
  segment — but the *conditional-flush* shape (buffer, and
  flush-or-not depending on state) couples effect order to a
  register's value and is left to its joint owner (registers + the
  effect story). Named, not worked. *That round now exists*
  (`within-firing-effects-design.md`, exploration): within a firing
  there is no time — the segment sentence above is confirmed as the
  whole answer — and the conditional-flush buffer dissolves into a
  segmentation of the op flow (buffer = per-segment collect, reset =
  boundary, flush = per-segment write, the interleaved raw op
  discharged from the segment terminator); no register appears.

- **The collected-plan / batched pole.** Effects-as-collected-plan —
  XQuery's pending update list: gather effect *descriptions* as
  values, apply them atomically at a barrier, resolve conflicts by
  declared rules — is fenced here, but with a distinction worth
  keeping precise. Now, you might wonder why that isn't the *default*
  way per-firing effects work — collect the plan, run it after the
  loop. It turns out this would cause problems as an everyday form:
  it renounces execution order and then re-imports it as conflict
  rules (its conflict rules are just within-firing ordering
  resurfacing once execution order is renounced,
  `xquery-jq-comparison.md`), and it breaks read-your-writes inside a
  firing — inside the snapshot, a firing cannot see its own earlier
  effects — which is wrong for interactive IO, and interactive IO is
  most per-firing effects. (Rejecting it *as the default* is settled
  — please don't re-propose that without new evidence.) But the plan
  pole is not rejected as a construct: it is the right shape
  precisely when atomicity and dedup *are* wanted (apply a set of
  edits as one transaction; last-write-wins on a key). That is a
  separate **batched effect** construct — an effect whose value is a
  plan, discharged at a collect — adjacent to this chapter's threaded
  effect, not a competitor to it. Elm's `Cmd` (the plan with the loop
  closed: results re-enter as events) is the same pole with feedback.
  Left for its own round; flagged here so the thread pole is not
  misread as denying it.

- **Bodies-raise / lightweight failure.** Whether an effect operation
  can fail and propagate by default — Zig's `try` — is the
  failability row's concrete demand (`open-problems.md`;
  `async-flow-design.md`, "Do bodies raise?"). It interacts with
  effects (a failed write should propagate) but is owned by
  failability, not decided here. This chapter assumes the effect
  operation succeeds, or that failure is handled by the existing
  terminator machinery. *The owning round now exists*
  (`failure-payloads-design.md`, exploration): failure is drawn, and
  a failable effect operation is a failable catalog row — its lanes
  enter the inventory like any source's, nothing effect-specific.

## Open questions this round leaves

The language hasn't decided these yet; they are the honest edges of
the proposal.

1. **The spelling of the threaded effect op and its two boundaries.**
   The provisional `~io ~> op(args…) in ~loop => ~io'`
   (translation-exercise open question 10) needs the boundary story
   confirmed on the page: the commute itself is never authored, so
   does the `in ~loop` phrase carry the spanning-vs-nesting
   distinction, or does the drawing alone? The second half of this
   question — is the faint completed form worth showing at all? —
   is answered (2026-07-23, the commute-completion ruling: showing
   it is required; see "You never draw the commute" above).
   The spelling half remains, jointly owned with
   `textual-representation-design.md` and
   `first-class-ports-design.md`.

2. **Stacking with other commutes.** When the effect ops sit under
   an option-in-list whose option layer also commutes out
   (`lazy-stream-commute-design.md`), the two crossings have an
   order: does the IO concatenation include the segments of firings
   that ran before the option layer short-circuited on a `None`, or
   not? This is the one known place where "concatenate in firing
   order" must say more, and where the dissolved register reading
   might have answered differently — the divergence that would make
   the ontological choice observable. Jointly owned with
   `lazy-stream-commute-design.md`.

3. **The batched-effect construct.** Deferred above, but it owes its
   own round: what a plan-valued effect is, how it discharges at a
   collect, and how conflict resolution reads on the page without
   becoming the invisible ordering XQuery's rules are.

4. **Interaction with multi-close.** One list flow may be collected
   many times (`core-model.md`, "One loop, several results"). The
   handle's linearity gives half the rule for free — the
   commuted-out segment is one wire with one consumer — but if two
   sibling closes iterate independently, which close's iteration
   does the concatenation bind to? This is the
   multiple-collect/shared-grid problem
   (`iteration-with-state-design.md`) in its observable-effects
   form. Flagged, not worked.

The story continues inward from here: what orders two effects
*within* one firing is the subject of
`within-firing-effects-design.md`.
