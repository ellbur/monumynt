# Within-firing effects: ordering without time, and the conditional-flush buffer dissolved

Status: exploration — this chapter teaches a worked proposal with
leanings, prepared for a design conversation. None of it has been
adopted or implemented; read it as "here is a candidate and the case
for it." Its scope is the **within-firing effect ordering** axis that
`effects-design.md` fenced out ("named, not worked"), whose standing
witness is the conditional-flush buffer — breadth item 5 of the
survey record, the one breadth item whose owner was named jointly
(registers + the effect story) and never tested jointly
(`real-loop-survey.md`). This round works that axis. It deliberately
does **not** work the batched-effect construct, bodies-raise, or
cancellation — each stays fenced where its owning round left it.

If you want the background first: `effects-design.md` teaches the
cross-firing thread this chapter extends inward,
`variable-rate-consumption-design.md` teaches split-when and the
running view (this chapter is their second client),
`custom-flows.md` teaches the lifecycle segment, and `core-model.md`
teaches value vs flow wires and the inside-out principle. Prior-art
contact: `reactive-comparison.md` (the ecosystem's flush-timing knobs
and ordering disclaimers) and `lazy-stream-commute-design.md` (the
marker-out-of-sequenceable commute variant).

## Two effects in one firing

Start with the smallest program that has the problem's shape. Per
request, send a header and then a body — two effects inside one
firing, and their order matters:

```
reqs -> open list => req, ~R
req -> connect => ~s              -- a fresh handle inside the firing
~s ~> sendHeader(req) => ~s'      -- first op
~s' ~> sendBody(req) => ~s''      -- second op: ordered by the chain
~s'' ~> closeConn                 -- released within the same firing
```

What orders `sendHeader` before `sendBody`? Nothing new: the second
op consumes the handle the first produced. Operations strung along
one handle's segment are ordered by the segment — each op takes the
handle in and produces the next — and that is true at any
granularity, including inside a single firing. The chain *is* the
order.

That little observation, taken seriously, turns out to be the entire
answer to within-firing ordering. The rest of this chapter is about
taking it seriously: stating it as a rule, and then watching the
hardest known witness — a buffer that is conditionally flushed
partway through some firings — dissolve under it.

## The gap, stated precisely

The effects round settled how effects order **across** firings: a
spanning handle commutes out of the loop — its per-firing segments
concatenated in firing order — so cross-firing order is iteration
order and nothing is annotated. It then fenced the remaining axis in one sentence: the
*conditional-flush* shape "couples effect order to a register's value
and is left to its joint owner (registers + the effect story)"
(`effects-design.md`).

The witness is survey 1's net/http multipart writer (ruby 8, class
8 — "accumulator with multi-site append and conditional reset"):

```ruby
buf = +''
params.each do |key, value, h={}|
  buf << "--#{boundary}\r\n"
  if filename
    buf << "Content-Disposition: ..."
    if ...direct write case...
      flush_buffer(out, buf, chunked_p)   # writes buf to out, buf.clear
      IO.copy_stream(value, out)
    ...
  else
    buf << ...
  end
end
```

A string builder appended at several sites per firing, conditionally
flushed — written to the output channel and cleared — partway through
some firings, so that a raw file copy can be interleaved at the right
position in the output. The survey's diagnosis was exact on both
counts: the one-writeback rule survives structurally (each firing's
final `buf` is one expression), and "what strains is not the
writeback count but the *effects interleaved between the appends* —
the flush must be ordered against the raw copy"
(`real-loop-survey.md`, finding 3).

So the question on the table: **what orders two effects within one
firing, and what is the buffer-with-conditional-reset in drawn
vocabulary?** The round's answer is that the first question is
already answered by machinery the record has, and the second question
dissolves — there is no register in the drawn form of this loop at
all.

## What was already settled before this chapter

Seven things are fixed in the record before this round starts, and
the round leans on all seven rather than reopening them.

1. **Operations along one handle segment are ordered by the
   segment.** The lifecycle pattern draws a handle as a vertical
   segment with operations strung along it; each op consumes the
   handle and produces the next, so ops on one handle are totally
   ordered by wiring (`custom-flows.md`, `visual-language-spec.md`).
   This is true at any granularity, including inside a single
   firing — it is what ordered the header before the body above.

2. **Independent handles commute** — their operations have no
   structural relationship and cross freely; an explicit commute
   between them would be a no-op (`custom-flows.md`). Also true at
   any granularity.

3. **No interior scopes, no magic names.** Inside-out: anything
   readable at a position arrives by a visible wire
   (`language-design-philosophy.md`, principle 2).

4. **Split-when and the law of segments.** A binary flow operation
   (subject, boundary) partitioning a flow into consecutive segments;
   the boundary firing's value rides the segment terminator; the
   final segment ends the way the subject ends; per-segment state
   needs no reset construct — "the nesting is the reset"; per-segment
   readout is discharge (`variable-rate-consumption-design.md`).

5. **The running view.** A collect's output-so-far is readable
   per-firing as the state port of its derived augment form, strict
   prefix, productive by the Delay-crossing rule
   (`variable-rate-consumption-design.md`, Part II).

6. **The spanning handle commutes out of the loop** — per-firing
   segments concatenated in firing order, the handle after the loop
   the concatenation's tail; a nested handle is independent and
   unordered (`effects-design.md`).

7. **Derivation, not retroaction.** No construct reaches into an
   existing flow and changes what other consumers see
   (`end-when-design.md`).

## Within a firing there is no time

The round's first result is a statement, not a construct, and it is
the inside-out principle applied to the *schedule* rather than the
scope:

> **Within a firing there is no time. The only order that exists
> inside a firing is order along a handle's segment. Everything else
> is data dependence.**

Unpacked into its three consequences:

- **Same-handle ops are ordered by the segment they are strung on** —
  already fixed (item 1 above, and the header/body example). Two
  effects within one firing that must happen in order are two
  operations on one handle, and the handle's chain *is* the order.
  Nothing new.

- **Values have no "when."** An effect operation's argument is a
  wire. The question "which value does the flush see — the buffer at
  the moment the flush runs?" is a question about a moment that does
  not exist. Which value an op consumes is *drawn* — whichever port
  its argument wire comes from — never scheduled. There is no "the
  current contents" of anything; there are only named wires carrying
  definite per-firing values.

- **Cross-handle order does not exist, and that is a feature with a
  sharp edge** — worked in its own section below.

Why does imperative code hide this? Because the imperative costume
supplies a total order for free — the statement list — and mutable
variables let value-state and sequencing share one name: `buf` is
simultaneously "the text so far" and "the point in the schedule where
text is pending." The reactive-comparison corpus shows what happens
when a genre keeps ambient time but loses the statement list:
flush-timing knobs (Vue's `flush: 'post'`/`'sync'`, MobX schedulers)
and universal ordering disclaimers ("MobX does not guarantee the
order in which reactions will be run"; Solid: "The order of runs
among multiple effects is not guaranteed") — the ecosystem's APIs are
the shape of the hole (`reactive-comparison.md`). The record's
position is the axiom: order is not ambient at *any* granularity;
where order is meant, it is drawn, and the handle segment is where it
is drawn.

Now, you might wonder why the language doesn't just add an
intra-firing sequencing construct — statement order, or "seq" edges
between ops on different wires — so the author could pin any order
they like. It turns out this would cause problems: within a firing
there is no time; same-handle order is the segment, value-side order
is data (a list), and a free-floating order edge would reintroduce
ambient schedule — the flush-timing-knob genre the reactive corpus
documents as a hole, not a feature. (This is a settled rejection —
please don't re-propose a sequencing construct without new
evidence.)

## The dissolution: the buffer is a segmentation of the op flow

Now the witness loop, read for what it *means* rather than how it is
staged.

**What the loop means.** One ordered sequence of pieces lands on
`out`: text fragments (boundary lines, headers, inline bodies)
interleaved with raw file bodies. That is the entire meaning. The
buffer is not part of it — `buf` exists so that consecutive small
text pieces become one syscall, and so that the raw copy (which
writes to `out` directly, bypassing the string path) lands *between*
the right text pieces. The meaning is "write these pieces, in this
order"; the buffer is a batching of the text runs.

**The appends were never effects.** Read as a drawing, each param
produces one to three *pieces* — values, in a definite order. Several
`buf <<` sites per firing are per-firing piece *production*: a small
list built by ordinary value code (the case split on the param's kind
determines which pieces), opened, and joined into the flat piece
flow. The order among one firing's pieces is **list order — data, not
time**. Nothing effectful has happened yet; a piece is a string or a
file, not an operation. This is why the multi-site-append half of
breadth item 5 never strained the one-writeback rule: it was never
state.

Now, you might wonder whether the piece flow is really a *plan* —
effect descriptions produced now, executed later, the
effects-as-collected-plan pole. It turns out it is not, and the
difference matters: the pieces are values (strings, files), not
effect descriptions; the thread performs every op in drawn order, and
read-your-writes holds — the raw copy actually lands between the
physical writes, which is exactly what the plan pole cannot guarantee
(`effects-design.md`, dead end on the plan-as-default). The buffer
batches a *thread*; it does not renounce execution order. The
batched-effect construct remains its own fenced round. (This reading
is a settled rejection — please don't re-propose the plan reading of
the buffer without new evidence.)

**The flush boundary is a split-when.** The pieces are a case flow —
`Text` and `Raw` alts, a genuine data distinction, not packing. Aim
the `Raw` alt at a split-when as the boundary operand (delimiter
destination: the raw piece belongs to neither text segment; its value
rides the segment terminator, per the law). The subject partitions
into **runs of consecutive text pieces**, one segment per run — and
every part of the imperative idiom finds its drawn name:

- the **buffer** is the per-segment collect — each segment's text
  pieces concatenated into one string;
- the **reset** is the boundary — a new segment's collect starts
  empty, because that is what a nested collect means ("the nesting is
  the reset," verbatim from the split-when theorems — no reset
  construct, no clearing operation);
- the **flush** is one write op per segment, on the `out` handle
  threaded through the *segment* flow (the effects round's spanning
  handle, one level up — the concatenation now runs per segment
  instead of per piece);
- the **raw copy** is the boundary payload — the `Raw` firing's value
  rides the segment terminator, is discharged at the segment's close,
  and feeds a `copyStream` op strung on the same handle *after* that
  segment's write. Within the firing: write, then copy — ordered by
  the segment chain, per the axiom. Across segments: ordered by the
  thread. Nothing else needs ordering, and nothing else is ordered.

Now, you might wonder why the language doesn't just transcribe the
Ruby faithfully — a register carrying the string, the flush op
reading "its value at the flush point," then clearing it. It turns
out this fails twice over: "at the flush point" names a moment that
doesn't exist (values have no when — an op's argument must be a drawn
wire), and the clear would need a reset operation, which is its own
rejection just below. The segmentation form needs neither. (This is a
settled rejection — please don't re-propose the
buffer-as-mid-firing-register without new evidence.)

And you might wonder, separately, why there is no reset operation or
reset port on a register at all — the direct transcription of
`buf.clear`. It turns out this would cause problems: the reset is a
segment boundary, and the nesting is the reset (split-when's
theorem). A reset port would let the effect side reach into value
state — the very entanglement the drawing exists to dissolve — and it
violates derivation-not-retroaction: other readers of the register
would see their past erased. (This is a settled rejection — please
don't re-propose a reset construct without new evidence.)

**The final flush is the final segment.** The law of segments already
says the final segment ends the way the subject ends, terminator
passed through — so the text after the last raw copy is a segment
like any other, and its write happens like any other. The imperative
idiom's classic bug — the forgotten final flush after the loop — is
**unwritable** in the drawn form: there is no separate "remember to
flush at the end" step to forget, because the end is just the last
segment. (Its sibling bug, flushing without clearing or clearing
without flushing, is equally unwritable: the buffer and the reset are
not two operations that could disagree — they are one collect and its
nesting.)

The construct list, end to end (a construct list rather than chains,
deliberately — the op spellings are owed to the textual round, per
effects-design open question 1):

    params:   uncollect the param list                    (subject-of-subject)
    pieces:   per param, the piece list (built by the
              param-kind case split), opened and joined
              into one flat piece flow — each piece
              Text(string) | Raw(file)
    B:        split-when(pieces, Raw-alt), boundary
              element dropped as delimiter (its value
              rides the segment terminator)
    segText:  per segment — collect the Text values,
              concatenated
    ~out:     the output handle, threaded through the
              segment flow (spanning: enters before the
              loop, leaves after, segments in order)
    per segment firing, along the handle:
              write(segText); then discharge the segment
              terminator — Raw(file): copyStream(file);
              subject-RanOut: nothing
    epilogue: the closing "--boundary--" line — an
              ordinary write op downstream of the loop,
              consuming the handle after the loop

No register carries the buffer. No reset exists. The two effects per
firing are two ops on one segment chain. The loop's sentence — "write
the params as multipart, streaming file bodies straight through" — is
the drawing, clause for clause.

One honest micro-difference: the imperative code batches the last
param's trailing text together with the epilogue into one syscall;
the drawing above writes the epilogue separately. Under the
coalescing property of the batching section below this is exactly a
*free* boundary — the difference is one syscall, not meaning — which
is the right place for it to land.

## The coupling point, isolated

The effects round's fence said the conditional-flush shape "couples
effect order to a register's value." The dissolution shows the
coupling was two ordinary wires, seen through one mutable variable:

- **The boundary may read accumulated state.** In the threshold
  variant — flush whenever the pending text exceeds 4KB — the
  boundary predicate reads the running length of the current
  segment's collect. That is the running view / per-segment register
  reading that split-when already worked, productive by the existing
  Delay-crossing rule, verbatim the wrap loop's `cur_len`
  (`variable-rate-consumption-design.md`, "Well-formedness: the
  boundary may read per-segment state"). The *value* side of the
  coupling.

- **The effect consumes the segment's collect.** The write op's
  argument is the segment's collected text — an ordinary value wire
  into an op on the thread. The *effect* side of the coupling.

Two wires, one meeting point: the segment. Effect order never touches
register machinery; state never touches the thread. The entanglement
the survey observed was real, but it was a property of the costume —
one variable doing two jobs — not of the meaning. Breadth item 5's
joint owner turns out to be half right: the effect story (the thread)
and the *segmentation* story own it jointly; the register half
dissolves into the nesting.

## The conditional effect: an empty segment

Strip the buffer away and one residual genuinely-conditional shape
remains: **perform an op on some firings only** — write a warning
line only for malformed entries; the witness loop's copy op, which
fires only on `Raw` terminators. What does the handle do on the
firings where the op doesn't fire?

Nothing — and under the sequencing commute, nothing is a complete
answer. A firing that strings no ops contributes an **empty
segment**, and empty segments concatenate as identity, the same
grounding as the empty loop (`effects-design.md`). The non-firing
alt of the case split simply touches no handle; there is no
pass-through to wire and no reunification to draw.
"Flush-or-not depending on state," in its residual genuine form
(after the buffer costume is gone), is a segment that is sometimes
empty — no rule at all. (An earlier working, under the effects
round's since-dissolved register reading, needed conditional carry
on the marker wire here — the one-writeback rule applied to the
handle. Dissolved with the register: where there is no carried
value there is nothing to carry conditionally.)

## Batching is meaning exactly when write is not a homomorphism

The dissolution places a boundary on the page — the segmentation says
*where* the physical writes fall. Is that meaning, or optimisation?
The honest answer is: it depends on the resource, and the dependency
is a declarable algebraic fact, not a vibe.

For a plain byte sink, consecutive writes coalesce:
`write(a); write(b) ≡ write(a ++ b)`. (In algebraic terms, write is a
monoid homomorphism from string-concatenation to handle-sequencing —
a structure-preserving translation: combining the strings first, or
writing them one after another, comes to the same thing.) Under that
law, **boundary placement is free**: any segmentation of the same
piece flow writes the same bytes, so the split-when is a pure
efficiency choice. Under chunked transfer encoding it is the
opposite — `flush_buffer(out, buf, chunked_p)` emits an HTTP *chunk*,
with a length header on the wire per flush; each write is a frame,
the law fails, and the boundary is **observable meaning**. Datagrams,
line-buffered logs, and websocket messages are the same pole: one
write = one unit the far side can see.

So the property "this handle's `write` coalesces" is a catalog row —
a declared law on the op, trusted like the JS edge, exactly the shape
the collect family already demands of the catalog (a property
carrying a witness; `collect-family-design.md`, feeding checking's
question 4 — since worked, `catalog-schema-design.md`: a laws-family
row whose witness is the two-sided coalescing equation itself). Where the row is present, the segmentation is a free
choice and could in principle be left *uncommitted* — a boundary the
author never places, completed by published rules the way
under-committed order already is (`time-travel-programs-design.md`).
That is flagged, not proposed: the completion-contents row's own rule
is that each addition needs a worked program behind it, and this
round supplies only the candidate. Where the row is absent — chunked
encoding — the boundary must be drawn, and the drawing is then
telling the truth the imperative form hides: *which bytes share a
chunk* is program meaning, visible as which pieces share a segment.

The two classic bugs of the buffer idiom land exactly where a
vocabulary should put them: the forgotten final flush is unwritable
(the final segment is structural), and wrong chunking is *visible*
(the boundary is on the page, not implicit in the interleaving of
mutations and calls).

Related, not reopened: moving IO across data structure is the
marker-out-of-sequenceable commute variant
(`lazy-stream-commute-design.md`) — now worked for the list case as
the effects round's sequencing commute, its runtime design still
deferred. This round's batching
never moves an op across anything — it only chooses segment
boundaries on the op flow's own order — so it composes with, and does
not preempt, that variant's eventual runtime design.

## Cross-handle order, and what a handle is

The axiom's third consequence has a sharp edge that must be faced
rather than smoothed: within a firing, ops on handle A and ops on
handle B interleave *arbitrarily* — independent handles commute, so
the drawing fixes no order between them. Real programs sometimes seem
to want one: "log the line *before* writing the file, so a crash
leaves the log explaining what was attempted."

Now, you might wonder why the language doesn't allow an ordering
annotation — a sequencing edge — between ops on different handles,
for exactly that program. It turns out this would cause problems, and
the reason is about what a handle *is* (the "what does it mean?"
lens, `language-design-philosophy.md`), applied to the handle
itself:

> **A handle is an ordering commitment.** The resource is the
> payload; what the flow-wire *is*, is the total order of the
> operations strung on it. Two operations whose relative order is
> observable are, by that very fact, operations on one resource at
> the granularity where the order is observed.

The log-before-write program is the demonstration. If the crash-time
interleaving of log and file is meaningful, then there is a real
thing whose state both ops advance — the debugging record, the
durable picture a post-mortem reads — and *that* is the resource;
both ops belong on its handle. If no such thing is meant, the order
is genuinely free and the commute is correct. Minting granularity
follows observability: one handle per terminal (not per fd), one per
debugging record (not per file), one per session (the per-session-IO
constraint, `tough-use-cases-design.md` break #3 — the same rule read
from the other side, where *fine* granularity is what's meant). An
ordering demand that seems to span handles is a mis-factoring, and
the fix is in the handle structure, not in a new edge species. An
annotation, by contrast, would let the drawn independence and the
meant dependence disagree — the effects round's rejection of an
author-selected ordered/unordered mode, extended down to firing
scale. (This is a settled rejection — please don't re-propose a
cross-handle ordering annotation without new evidence.)

This is the leaning this round most wants the design conversation to
weigh — it decides what the vocabulary says when a user asks "how do
I make this happen before that?": *put them on the same thread, or
accept that the order is not part of your program's meaning.*

## Worked program: the threshold batcher

The second everyday costume of the same construct — batch writes by
size (a chunked uploader, a log shipper, `BufferedWriter`):

    items:    the record flow (subject)
    pending:  per segment — running view of the segment's
              collect (the bytes so far this batch)
    full?:    case split on len(pending) + len(item) > 4096
              → {overflow, fits}
    B:        split-when(items, overflow-alt), boundary
              element starts the next segment (the record
              that didn't fit opens the next batch)
    ~out:     threaded through the segment flow;
              per segment: write(collected batch)

This is the wrap loop with an effect readout instead of a list
collect — the same drawing, one statement swapped, which is the
two-boundary-crossings property the effects round already named for
B4 (the value flow leaves by collect, the marker flow by the
sequencing commute), extended one level up: *a segment's readout can be a
value (a line) or an effect (a flush), and the segmentation doesn't
care.* The threshold batcher and the text-wrapper are one program
family; the survey found them at opposite ends of the record and the
vocabulary reunites them.

## How this sits against the design principles

- **Example first, then generalise.** The concrete-first path exists
  at every stage: draw the unbatched program (one write op per
  piece — legal, correct, slow), then add the segmentation after the
  fact — interpose the split-when, re-aim the op at the segment's
  collect. Batching is an *addition to a working drawing*, not a
  structure declared before the first piece flows.

- **Inside-out.** The axiom *is* principle 2, extended from scope to
  schedule: no ambient time, no "current contents," no
  position-dependent meaning. Every value an op consumes arrives on a
  visible wire; every order that exists is a visible chain.

- **Foundations before features.** The round adds **no construct**.
  One axiom (a statement about what already exists), one composition
  (split-when + the thread), one catalog property, one leaning about
  what a handle is. Five would-be constructs died on paper — they
  appear through this chapter as the "now, you might wonder"
  passages.

- **Programmer's abstraction level.** "Flush," "batch," "buffer" are
  words in the programmer's vocabulary, and each now has one reading:
  a flush is a segment's write; a batch is a segment; a buffer is a
  segment's collect-in-progress. The imperative idiom's three-way
  entanglement (value, schedule, reset) decodes to one drawing.

- **No bottlenecks.** Nothing is packed to cross anything. The
  Text/Raw distinction is genuine data (a piece *is* text-or-file);
  it crosses the split-when as the alt bundle it already was; the raw
  piece rides the segment terminator; the text values pass to the
  collect as themselves.

- **Abstraction is the source of truth.** Where write coalesces, the
  batched form and the unbatched form are one meaning, and the
  segmentation is placement — the kind of thing the record keeps
  derived, with the flagged completion candidate as the fully-derived
  endpoint. Where write frames, the boundary is authored meaning and
  *stays* on the page. Both directions land consistently.

- **Building blocks must build.** The ladder, walked: op-per-piece →
  **+ batching** (split-when, re-aim the op at the segment collect) →
  **+ threshold boundary** (the boundary split reads the running
  view) → **+ interleaved raw op** (discharge the segment terminator
  into a second op on the chain) → **+ framing semantics** (drop the
  coalescing row; the same drawing, now meaning-bearing) → **+ a
  second independent sink** (its own handle, its own thread — they
  commute). Each rung is an addition; the top of the ladder is the
  net/http loop. No rung changes species.

## What this changes elsewhere, if adopted

- **Breadth item 5 gains a worked owner** and its "untested jointly"
  flag clears: the joint owner is the effect thread + split-when, and
  the register half was the costume. Annotated in
  `real-loop-survey.md`'s breadth list.
- **The effects round's fence closes**: within-firing ordering is no
  longer "named, not worked." Its within-firing sentence — ops strung
  along one segment are ordered by the segment — is confirmed as the
  whole answer, with the axiom making "and nothing else is ordered"
  explicit.
- **Split-when gains its second everyday client** outside the
  variable-rate round's own examples — evidence for that round's
  adoption conversation that the construct carries weight beyond the
  cluster it was designed for.
- **The one-writeback rule gains its first marker-wire client**
  (conditional carry on the thread), and the survey's recorded caveat
  on rb 8 ("what strains is effect ordering, which no writeback count
  addresses") is discharged.
- **Checking's question 4 gains a second concrete row**: the
  write-coalescing law joins the collect family's identity-witness
  rows as catalog content with semantic force.
- **The handle-as-ordering-commitment leaning** feeds the IO row's
  adoption conversation and touches `custom-flows.md`'s granularity
  guidance and `bundle-provenance-design.md`'s open question 4.

## Open questions this round leaves

The language hasn't decided these yet; they are the honest edges of
the proposal.

1. **Spellings.** The per-segment op chain (an op consuming the
   segment's collect), the terminator-discharge-into-op composition,
   and the conditional marker carry all need textual forms — joint
   with the effects round's question 1 and the discharge binder
   convention (`textual-representation-design.md`).
2. **The coalescing row's exact form.** Which op families declare it,
   what the witness is (the collect family's rows carry the identity
   *value*; a law between two op sequences is a different witness
   shape), and whether an uncommitted boundary completed by rules is
   admissible — the latter owed a worked program before the
   completion-contents row will take it.
3. **Multi-close on the op flow.** Two consumers threading one
   spanning handle is the effects round's open question 4, unchanged
   here; segmentation adds the variant "two segmentations of one op
   flow," which presumably falls under the same
   one-threading-consumer rule. Restated, not advanced.
4. **The granularity rule's final form.** "Mint handles at the
   granularity where order is observable" is a leaning with a
   worked-out sense of what a handle *is* behind it, not yet a
   checkable discipline; whether the bundle machinery participates (a
   bundle of handles as a drawn coarse handle) is untouched.
5. **Per-firing piece production ergonomics.** "Several ordered
   contributions per firing" is build-a-list-open-join — correct, and
   three nodes for an everyday gesture; whether it earns a lighter
   authoring path (not a construct) is a textual/authoring question.
