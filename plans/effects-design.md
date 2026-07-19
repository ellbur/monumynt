# Per-firing effects: the IO thread across a loop

Status: exploration (a worked proposal with leanings, prepared for a
design conversation — not adopted). Scope: the **effects** half of the
Tier-1 IO/effects/cancellation row (`open-problems.md`), and within that,
its most-cited concrete gap — *causing an effect once per firing of a
loop*. The single most common thing sampled loops do is currently
unwritable (`translation-exercise.md` B3; ~42% of sampled loops exist for
their effects). This round works that gap and deliberately does **not**
work cancellation, bracket, within-firing effect ordering, or
bodies-raise — each is fenced below with the reason.

Reading order: `custom-flows.md` (the effect-handle lifecycle, the raw
material), `core-model.md` (value vs flow wires, the register pointer),
and the register sections of `iteration-with-state-design.md`
(`init`/`prev`/`step`/`final`). The prior-art poles are in
`xquery-jq-comparison.md` (the pending update list),
`reactive-comparison.md` (Elm `Cmd`), `effekt-comparison.md` and
`flix-comparison.md` (effects interleaved mid-computation),
`zig-comparison.md` (the bracket/cancellation sub-structure this round
does not touch).

## What the record already fixes

Three things are settled before this round starts, and the round leans on
all three rather than reopening them.

1. **An effect is an operation on a threaded effect-handle flow.** The
   spec already carries the node: `EffectOperation` performs one operation
   (`print`, `writeLine`, `cancel`, …) on an effect flow, taking the flow
   in and producing the flow *after* the operation out; "downstream effect
   operations must use it to keep sequencing" (`visual-language-spec.md`).
   The lifecycle pattern draws it as a vertical segment — creation at the
   top vertex, operations along the segment, destruction at the bottom —
   and forbids attaching an operation outside the segment
   (`custom-flows.md`). The handle rides a *flow* wire (`~io`), not a value
   wire; the marker has no runtime representation
   (`lazy-stream-commute-design.md`).

2. **The pole is the sequenced thread, not the collected plan.** The
   record has named two poles: *effects-as-collected-plan* (XQuery's
   pending update list; Elm's `Cmd`; jq's edge-only effects) and
   *effects-as-sequenced-thread* (Effekt and Flix interleave `println`
   mid-computation as a matter of course; the IO-thread leaning in
   `tough-use-cases-design.md`). Effekt states the asymmetry that decides
   it for us: *they* make effects sequential by default and concurrency
   explicit; *we* get concurrency free from the DAG and make **sequencing**
   the explicit, drawn thing (`effekt-comparison.md`). The IO thread — a
   flow wire whose only job is to order the operations strung along it —
   is that drawn sequencing. This round assumes the thread pole and asks
   what the thread *is* when the operations live under a loop. (The
   collected-plan pole is not discarded — it re-enters below as a distinct
   *batched* construct, for the cases where it is actually wanted.)

3. **Ordering among handles is inferred from the definition, per handle.**
   Independent effect handles commute — their operations have no structural
   relationship, so they cross freely, and an explicit commute between them
   would be a no-op (`custom-flows.md`). Only same-handle operations are
   ordered. `tough-use-cases-design.md` (break #3, per-session IO) attaches
   a concrete program to this: thread *one* handle through a server and
   every session serialises on it, so IO handles must be mintable per
   firing with only same-handle operations ordered. Whatever this round
   proposes must reproduce that: **the order among per-firing effects is
   exactly the order among the handle threads they run on — nothing more.**

## The gap, stated precisely

`translation-exercise.md` B3 is the minimal witness. The source:

```js
for (const key of keys) {
  if (key.match(new RegExp(section + ':'))) {
    this.finishTracker(section, key)
  }
}
```

The filter half is designed vocabulary:

```
keys -> open list => key, ~K
key -> split matchesSection(section) of Hit, Miss => m
~m.Hit ~> join into ~K => ~hits
```

Then, per firing of `~hits`, call `finishTracker`. Inventing the minimum —
an effect op as a stage on the handle's chain:

```
in ~io
~io ~> finishTracker(section, key) in ~hits => ~io'   -- (provisional)
```

And the exercise puts its finger on exactly what nothing defines: *the op
fires per firing of `~hits`, so the handle is inside the iteration — what
is `~io'` outside the loop?* "That is a collect of an effect flow, which
nothing defines. The lifecycle pattern's `(db', io', result)` tuples are
drawn for straight-line code, not for ops under a flow."

So the whole gap is one question: **when an effect operation runs once per
firing, what does the IO thread do at the two boundaries where the loop's
flow meets the handle's flow — the entry (`~io` into the loop) and the
exit (`~io'` out of it)?**

## Why the handle cannot simply be read into each firing

The tempting non-answer: `~io` is in the enclosing context, and
provenance's prefix rule admits an enclosing context's value into a nested
flow directly — `add(ten)` inside a loop just works (`core-model.md`). So
let each firing read `~io`, do its effect, and be done.

This is wrong, and *why* it is wrong is the whole design. The prefix rule
duplicates a value into every firing — ten copies of `10`, all identical
and harmless because `10` is not consumed. An effect handle is the
opposite: it names a **single-threaded resource** — one file, one console,
one connection — and it is *consumed* by each operation, which produces the
next handle. It is **linear**, not duplicable. Read one file handle into
ten firings and you have ten programs each believing it holds the file at
its original position; the record already knows this shape as the register
half's wire linearity (the thread port is consumed exactly once,
`first-class-ports-design.md`).

A linear wire that must visit each firing in turn cannot be prefix-read; it
must be **threaded** — firing *i* consumes the handle firing *i−1* left,
and produces the handle firing *i+1* will consume. And threading a wire
across an iteration, firing *i* reading firing *i−1*'s output, is the one
iteration-boundary edge the language already has a construct for: the
**Delay / register**. So:

> **A per-firing effect is a register whose threaded wire is the IO
> handle.** The handle enters as the register's `init`, each firing's
> operation is the `step` that produces the next handle, and the handle
> after the loop is the register's `final` — one handle out, never a list.

That last clause is the answer to the translation-exercise gap. "Collect of
an effect flow" was undefined because it was the wrong picture: N firings do
not produce N handles to gather. They **thread one handle**, and the thing
outside the loop is the register's `final` — "the value after the flow
completes — the last `step`, or `init` if no iteration ran"
(`first-class-ports-design.md`). An empty loop does no effects and leaves
the handle exactly as it entered: `final = init`, grounded the same way the
empty running-sum is grounded.

Effect *order* falls out for free and correctly: a register folds along its
iteration in firing order, so the writes happen in loop order — which is
what an ordered resource (a file, a log) demands, and demands without a
knob. Nothing is annotated; the order is the iteration's order because the
handle is threaded through the iteration.

### The three-point map this lands on

The register was a back-edge on a **value** wire crossing a Delay.
Saturation is "the register's dual one level up — a back-edge on a **flow**
wire crossing a set collect re-opened" (`saturation-design.md`). The IO
thread is the third point: a back-edge that threads a **marker** wire
across a Delay. It sits on the register's side (it crosses a Delay, one
firing reading the previous firing's output), differing from the running
sum in exactly one respect — the threaded wire carries no readable payload.
You cannot compute on `prev` here; `prev` is "the handle so far," consumed
only by the next effect operation, and `final` is "the handle after the
loop," consumed only by a further operation or the handle's close. The
register construct is not intrinsically about data; it is about a linearly
threaded wire crossing an iteration boundary, and the IO handle is the
marker-flow instance of exactly that. Effects therefore do not need a new
mechanism — they extend the biggest open area (`iteration-with-state-design.md`)
to cover the most-cited effects gap, which is the strongest thing this
round has to say.

## The two shapes of an effect under a loop

The register answer is the whole story only when the handle **spans** the
loop — enters from outside, exits outside. There is a second, equally
common shape where the handle **nests** wholly inside each firing, and the
two are told apart structurally, by where the handle's lifecycle vertices
sit relative to the loop. This is the same "inferred from the definition
method" move `custom-flows.md` already makes for commutativity.

**Shape 1 — the handle spans the loop (threaded; ordered).** The handle is
created outside the loop and consumed outside it; the per-firing operations
are stages strung along it inside. B3 is this shape: `finishTracker` writes
to a tracker that outlives the loop. B4's file pump is this shape:

```
~io ~> writeLine(outLine) in ~W => ~io'
```

One file handle, threaded through the `~W` firings, writes in order,
`~io'` is the file after the last line. This is a register on `~io`;
`~io'` is its `final`. The effects are ordered by the loop, because one
resource cannot be in two firings at once.

A property worth naming, because it is a good one: B4's sibling in the wild
appends to a list instead of writing to the file, and that is *the same
drawing with one statement swapped* — `~io ~> writeLine(outLine) in ~W` (the
register's `final` readout of the handle) becomes `outLine -~> collect ~W`
(the list readout of the elements). The effect and the collect are two
readouts of one loop — one takes the handle out via `final`, the other
takes the elements out via `collect`. That the swap is one line is exactly
what the port table predicts: `final`/`collect` are the two "outside out"
anchors of the same iteration (`first-class-ports-design.md`).

**Shape 2 — the handle nests inside the firing (independent; unordered).**
The whole acquire/use/release segment sits inside one firing of the loop —
a connection opened, used, and closed for that firing alone. Then there is
**no thread across the loop at all**: each firing's handle is a fresh,
independent resource, and by the custom-flow rule independent handles
commute. The effects across firings are unordered, and may run concurrently
— which is precisely the per-session IO requirement
(`tough-use-cases-design.md` break #3): mint the handle per firing and the
sessions do not serialise on each other. Nothing crosses the loop's
collect, because the handle never existed outside it; there is no `~io'` to
define. In the provisional spelling — one scratch connection per request:

```
reqs -> open list => req, ~R
req -> connect => ~s            -- handle minted inside the firing: top vertex under ~R
~s ~> send(req) => ~s'          -- straight-line ops along the handle, no `in` clause
~s' ~> closeConn                -- released within the same firing
```

Every handle vertex sits under `~R`; no register, no `final`, and the N
segments commute.

The distinction is not a mode the author selects; it is *read off the
drawing* — does the handle's top vertex sit outside the loop or inside a
firing? Spanning ⇒ one threaded register ⇒ ordered. Nesting ⇒ N independent
segments ⇒ commute. This is the register-vs-no-register fork made
structural, and it satisfies the tough-use-cases constraint without a new
rule: "only same-handle operations are ordered" becomes "only a *spanning*
handle threads, and only a threaded handle orders."

The mixed everyday case sorts itself: writing each request's log line to
one shared logfile is Shape 1 on the logfile handle (ordered) *and*, if
each request also opens its own scratch file, Shape 2 on the scratch
handles (independent) — two handles, each classified by its own lifecycle,
no interaction to adjudicate.

## Effects over a product inherit the linearization residue

One honest consequence, not a new problem but a sharpening of an existing
one. Over a Cross product, a register folds along the axis its binding
collect gathers, fibered over the rest, and a *full-cube* fold needs a
linearization — which axis first — that is the open residue of the
loop-carried-state row (`iteration-with-state-design.md`, "The product,
re-read through update-cadence and read-range";
`product-flows-design.md`, question 5). A spanning effect handle threaded
through a doubly-nested loop (both axes writing to one file) is exactly a
full-cube fold on a linear wire, so its effect order **is** that
linearization.

The difference effects make: for a pure register the linearization was "a
cost, not a knockout" — a commutative monoid discharges the order demand
entirely, and only a non-commutative running-view reader pays. For effects
the order is *observable by construction* — the bytes land in the file in
one order or another, and no commutativity saves you, because writing is
not commutative. So effects do not open a new question here; they **remove
the escape hatch** from the existing product-linearization residue and
make settling it load-bearing for any program that writes under nested
iteration. Filed back to the loop-carried-state and products rows as the
observable-stakes version of a question they already own.

## What this feeds the Delay-ontology fork

The live open problem in `iteration-with-state-design.md` is *which flow a
register's back-edge binds to* — the collect that gathers it, or an
ancestor uncollect its value descends from. The IO register is a clean data
point for the "provenance fixes the flow, it is not chosen" leaning. The
effect handle's thread is not a value that could plausibly belong to
several flows; it is pinned to the single flow it is threaded through — the
loop whose firings consume and produce it — because a linear resource can
only be threaded where it is actually used. The flow is fixed by *use*, the
most forcing kind of provenance. This does not resolve the fork for
readable registers (whose value genuinely can be in reach of more than one
flow), but it is a witness that at the linear extreme the flow is
determined, not selected — a vote for the value-in-context reading that
recent rounds have been circling.

## What this round does not answer (fenced, with reasons)

- **Cancellation and bracket.** Release-on-abandonment, race-implies-cancel,
  and abandoned pending pulls are the other half of the Tier-1 row and are
  untouched here. Zig supplies the sub-structure any bracket design must
  reproduce — release adjacent to acquisition, cleanup keyed by exit
  reason, the acquire-may-fail/release-must-succeed asymmetry, per-firing
  as well as per-flow attachment (`zig-comparison.md`) — but bracket waits
  on cancellation, which waits on this round's thread being in place first.
  The thread is the carrier a cancellation capability would later ride
  (`async-flow-design.md` records the constraint that the async cell must
  not preclude threading a cancel token); establishing the thread is a
  prerequisite, not the cancellation design. *That round now exists*
  (`cancellation-design.md`, exploration): delivery over the demand
  frontier, `Cancelled` as a terminator lane, the release half consuming
  this round's `final` — consuming the thread, not changing it; the two
  rounds should go to the adoption conversation together.

- **Within-firing effect ordering (the conditional-flush buffer).** This
  round orders effects *across* firings (by the thread) and says nothing
  about two effects *within* one firing whose order is entangled with a
  conditional reset (`real-loop-survey.md`, the net/http buffer;
  `open-problems.md` breadth item 5). That is a distinct axis. The threaded
  handle gives within-firing order the same way — operations strung along
  one segment are ordered by the segment — but the *conditional-flush*
  shape (buffer, and flush-or-not depending on state) couples effect order
  to a register's value and is left to its joint owner (registers + the
  effect story). Named, not worked. *That round now exists*
  (`within-firing-effects-design.md`, exploration): within a firing there
  is no time — the segment sentence above is confirmed as the whole
  answer — and the conditional-flush buffer dissolves into a segmentation
  of the op flow (buffer = per-segment collect, reset = boundary, flush =
  per-segment write, the interleaved raw op discharged from the segment
  terminator); no register appears.

- **The collected-plan / batched pole.** Effects-as-collected-plan (XQuery's
  pending update list: gather effect *descriptions* as values, apply them
  atomically at a barrier, resolve conflicts by declared rules) is not the
  everyday per-firing form — it fails read-your-writes inside the snapshot,
  and its conflict rules are just within-firing ordering resurfacing once
  execution order is renounced (`xquery-jq-comparison.md`). But it is the
  right shape precisely when atomicity and dedup *are* wanted (apply a set
  of edits as one transaction, last-write-wins on a key). That is a
  separate **batched effect** construct — an effect whose value is a plan,
  discharged at a collect — adjacent to this round's threaded effect, not a
  competitor to it. Elm's `Cmd` (the plan with the loop closed: results
  re-enter as events) is the same pole with feedback. Left for its own
  round; flagged here so the thread pole is not misread as denying it.

- **Bodies-raise / lightweight failure.** Whether an effect operation can
  fail and propagate by default — Zig's `try` — is the failability row's
  concrete demand (`open-problems.md`; `async-flow-design.md`, "Do bodies
  raise?"). It interacts with effects (a failed write should propagate) but
  is owned by failability, not decided here. This round assumes the effect
  operation succeeds or that failure is handled by the existing terminator
  machinery.

## Dead ends recorded

Reasons kept short and forward-looking, so they are not re-proposed.

1. **The handle prefix-read into each firing.** Rejected: the prefix rule
   duplicates, and an effect handle is linear — duplicating a
   single-threaded resource into N firings is meaningless (N programs each
   holding the same file at position zero). Linearity is exactly why the
   handle threads (a register) rather than reads (a constant).

2. **The loop crossing as a Cross product of the element flow and the IO
   flow.** Rejected: Cross pairs *independent* flows, and the IO thread is
   the opposite of independent — firing *i+1*'s handle depends on firing
   *i*'s. There is no product because there is no independence; there is a
   fold.

3. **"Collect of an effect flow yields a list of handles."** Rejected (the
   tempting reading the translation exercise surfaced): the handle is a
   flow-context marker, not a value, and N firings thread *one* handle
   rather than emit N. The outside-the-loop handle is the register's
   `final` — one marker — not a collected list.

4. **The collected-plan pole as the *default* for per-firing effects.**
   Rejected as the everyday form (kept as an adjacent batched construct,
   above): it renounces execution order and then re-imports it as conflict
   rules, and it breaks read-your-writes inside a firing — wrong for
   interactive IO, which is most per-firing effects.

5. **An author-selected ordered/unordered mode for effects under a loop.**
   Rejected: the order is not a knob but a structural fact — a spanning
   handle threads and orders; a nested handle is independent and commutes.
   Selecting a mode would let the drawing and the declared order disagree,
   the same reason `custom-flows.md` infers commutativity from the
   definition rather than an annotation.

## Open questions this round leaves

1. **The spelling of the threaded effect op and its two boundaries.** The
   provisional `~io ~> op(args…) in ~loop => ~io'` (translation-exercise
   open question 10) needs the register connection made visible: is `~io'`
   spelled as a `final`-style readout of the loop, and does the `in ~loop`
   phrase carry the spanning-vs-nesting distinction, or does the drawing
   alone? Jointly owned with `textual-representation-design.md` and
   `first-class-ports-design.md`.

2. **Does the marker register reuse the Delay node or need its own?** The
   claim is "the register with a marker wire." Whether that is literally a
   Delay whose wire happens to be a marker, or a sibling node sharing the
   port signature, is an unforced representation choice — but the
   productivity check, the `final` exit anchor, and the empty-loop
   grounding all transfer verbatim, which argues for one node.

3. **The batched-effect construct.** Deferred above, but it owes its own
   round: what a plan-valued effect is, how it discharges at a collect,
   and how conflict resolution reads on the page without becoming the
   invisible ordering XQuery's rules are.

4. **Interaction with multi-close.** One list flow may be collected many
   times. If two sibling closes each thread the *same* spanning handle,
   the handle cannot be in two independent thread-orders at once — this is
   the multiple-collect/shared-grid problem (`iteration-with-state-design.md`)
   in its observable-effects form, and it may force a rule that a spanning
   handle admits exactly one threading consumer. Flagged, not worked.
