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
`core-model.md` teaches value vs flow wires and points at the
register, and the register sections of
`iteration-with-state-design.md` teach `init`/`prev`/`step`/`final`.
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
handle must thread (like a register) rather than be read in (like a
constant). (This is a settled rejection — please don't re-propose the
prefix-read without new evidence.)

## The answer: the handle threads — it is a register

A linear wire that must visit each firing in turn cannot be
prefix-read; it must be **threaded** — firing *i* consumes the handle
firing *i−1* left behind, and produces the handle firing *i+1* will
consume. And threading a wire across an iteration boundary, one
firing reading the previous firing's output, is the one
iteration-boundary edge the language already has a construct for: the
**Delay / register** (`iteration-with-state-design.md`). So:

> **A per-firing effect is a register whose threaded wire is the IO
> handle.** The handle enters as the register's `init`, each firing's
> operation is the `step` that produces the next handle, and the
> handle after the loop is the register's `final` — one handle out,
> never a list.

That last clause is the answer to the translation-exercise gap.

Now, you might wonder why collecting an effect flow doesn't just
yield a list of handles — that was the tempting reading the
translation exercise surfaced, "a collect of an effect flow." It
turns out that was the wrong picture entirely: the handle is a
flow-context marker, not a value, and N firings do not produce N
handles to gather. They **thread one handle**, and the thing outside
the loop is the register's `final` — one marker — not a collected
list. (This is a settled rejection — please don't re-propose
list-of-handles without new evidence.)

`final` already has exactly the right meaning: "the value after the
flow completes — the last `step`, or `init` if no iteration ran"
(`first-class-ports-design.md`). What should an empty loop do? It
does no effects and leaves the handle exactly as it entered:
`final = init`, grounded the same way the empty running-sum is
grounded.

Effect *order* falls out for free, and falls out correctly: a
register folds along its iteration in firing order, so the writes
happen in loop order — which is what an ordered resource (a file, a
log) demands, and demands without a knob. Nothing is annotated; the
order is the iteration's order, because the handle is threaded
through the iteration.

One more shape you might reach for and shouldn't: you might wonder
whether the meeting of the loop's flow and the IO flow is a **Cross**
product of the two — Cross being the language's node for combining
flows (`product-flows-design.md`). It turns out this can't be right:
Cross pairs *independent* flows, and the IO thread is the opposite of
independent — firing *i+1*'s handle depends on firing *i*'s. There is
no product because there is no independence; there is a fold. (This
is a settled rejection — please don't re-propose the Cross reading
without new evidence.)

### The three-point map this lands on

Step back and the register answer takes a satisfying place in a map
the record was already drawing. The register was a back-edge on a
**value** wire crossing a Delay. Saturation is "the register's dual
one level up — a back-edge on a **flow** wire crossing a set collect
re-opened" (`saturation-design.md`). The IO thread is the third
point: a back-edge that threads a **marker** wire across a Delay. It
sits on the register's side of the map (it crosses a Delay, one
firing reading the previous firing's output), differing from the
running sum in exactly one respect — the threaded wire carries no
readable payload. You cannot compute on `prev` here; `prev` is "the
handle so far," consumed only by the next effect operation, and
`final` is "the handle after the loop," consumed only by a further
operation or the handle's close.

The lesson of the map: the register construct is not intrinsically
about data. It is about a linearly threaded wire crossing an
iteration boundary, and the IO handle is the marker-flow instance of
exactly that. Effects therefore do not need a new mechanism — they
extend the biggest open area (`iteration-with-state-design.md`) to
cover the most-cited effects gap, which is the strongest thing this
chapter has to say.

## The two shapes of an effect under a loop

The register answer is the whole story only when the handle **spans**
the loop — enters from outside, exits outside. There is a second,
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
`~io'` is the file after the last line. This is a register on `~io`,
and `~io'` is its `final`. The effects are ordered by the loop,
because one resource cannot be in two firings at once.

A property worth naming here, because it is a good one: B4's sibling
in the wild appends to a list instead of writing to the file, and
that is *the same drawing with one statement swapped* —
`~io ~> writeLine(outLine) in ~W` (the register's `final` readout of
the handle) becomes `outLine -~> collect ~W` (the list readout of the
elements). The effect and the collect are two readouts of one loop —
one takes the handle out via `final`, the other takes the elements
out via `collect`. That the swap is one line is exactly what the port
table predicts: `final`/`collect` are the two "outside out" anchors
of the same iteration (`first-class-ports-design.md`).

**Shape 2 — the handle nests inside the firing (independent;
unordered).** The whole acquire/use/release segment sits inside one
firing of the loop — a connection opened, used, and closed for that
firing alone. Then there is **no thread across the loop at all**:
each firing's handle is a fresh, independent resource, and by the
custom-flow rule independent handles commute. The effects across
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

Every handle vertex sits under `~R`; no register, no `final`, and the
N segments commute.

Notice what you never do: pick a mode. The distinction is not
something the author selects; it is *read off the drawing* — does the
handle's top vertex sit outside the loop, or inside a firing?
Spanning ⇒ one threaded register ⇒ ordered. Nesting ⇒ N independent
segments ⇒ commute. This is the register-vs-no-register fork made
structural, and it satisfies the tough-use-cases constraint without a
new rule: "only same-handle operations are ordered" becomes "only a
*spanning* handle threads, and only a threaded handle orders."

Now, you might wonder why the language doesn't offer an explicit
ordered/unordered switch for effects under a loop anyway — surely the
author knows what they want? It turns out this would cause problems:
the order is not a knob but a structural fact — a spanning handle
threads and orders; a nested handle is independent and commutes.
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
threaded through a doubly-nested loop — both axes writing to one
file — is exactly a full-cube fold on a linear wire, so its effect
order **is** that linearization.

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
already own.

## What this feeds the open question of what a Delay *is*

The live open problem in `iteration-with-state-design.md` is about
what a Delay's back-edge fundamentally *is* — which flow it binds to:
the collect that gathers it, or an ancestor uncollect its value
descends from. The IO register is a clean data point for the
"provenance fixes the flow, it is not chosen" leaning. The effect
handle's thread is not a value that could plausibly belong to several
flows; it is pinned to the single flow it is threaded through — the
loop whose firings consume and produce it — because a linear resource
can only be threaded where it is actually used. The flow is fixed by
*use*, the most forcing kind of provenance. This does not resolve the
fork for readable registers (whose value genuinely can be in reach of
more than one flow), but it is a witness that at the linear extreme
the flow is determined, not selected — a vote for the
value-in-context reading that recent rounds have been circling.

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
  `final` — consuming the thread, not changing it; the two rounds
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
  terminator machinery.

## Open questions this round leaves

The language hasn't decided these yet; they are the honest edges of
the proposal.

1. **The spelling of the threaded effect op and its two boundaries.**
   The provisional `~io ~> op(args…) in ~loop => ~io'`
   (translation-exercise open question 10) needs the register
   connection made visible: is `~io'` spelled as a `final`-style
   readout of the loop, and does the `in ~loop` phrase carry the
   spanning-vs-nesting distinction, or does the drawing alone?
   Jointly owned with `textual-representation-design.md` and
   `first-class-ports-design.md`.

2. **Does the marker register reuse the Delay node or need its own?**
   The claim is "the register with a marker wire." Whether that is
   literally a Delay whose wire happens to be a marker, or a sibling
   node sharing the port signature, is an unforced representation
   choice — but the productivity check, the `final` exit anchor, and
   the empty-loop grounding all transfer verbatim, which argues for
   one node.

3. **The batched-effect construct.** Deferred above, but it owes its
   own round: what a plan-valued effect is, how it discharges at a
   collect, and how conflict resolution reads on the page without
   becoming the invisible ordering XQuery's rules are.

4. **Interaction with multi-close.** One list flow may be collected
   many times (`core-model.md`, "One loop, several results"). If two
   sibling closes each thread the *same* spanning handle, the handle
   cannot be in two independent thread-orders at once — this is the
   multiple-collect/shared-grid problem
   (`iteration-with-state-design.md`) in its observable-effects form,
   and it may force a rule that a spanning handle admits exactly one
   threading consumer. Flagged, not worked.

The story continues inward from here: what orders two effects
*within* one firing is the subject of
`within-firing-effects-design.md`.
