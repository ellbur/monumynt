# Variable-rate consumption and the running view of a collect

*Or: cutting one walk into segments, and reading what you have built
so far.*

Status: mixed after the cut decision (design conversation,
2026-07-23); none of it is implemented. The conversation that
adopted end-when (`end-when-design.md`, adoption notes) also
settled this chapter's relationship question, at the root: the
**cut** ("when") is the root concept — one construct yielding
(prefix, payload, continuation) — and **split-when is not a
separate primitive**: it is re-founded as the *iterated cut*,
expected to live as a derived/catalog construct over the cut
(users are not handed raw corecursion — the merge/interrupt
precedent). Everything this chapter works — the law of segments,
the destination setting, the boundary-reads-own-state analysis,
the evidence — carries over to the iterated form unchanged; read
"split-when the node" below as "the iterated cut." The cut
round's own open edges are filed as open question 10 — **and that
round is now worked** (Part III below, exploration, not adopted):
the cut's port shape (two flow outputs, the payload a terminator
not a port), the continuation on RanOut (an empty flow), payload
availability from the continuation side (the prefix's discharged
terminator, an exterior-value admission), the iterated form's
standing (the node total by construction, its unrolling a
spine-shaped link and a derived view only), the finite phase
chain (claiming Raku's *sequence*), and the spent-consultation
clause. The running
view (Part II) remains exploration: the same conversation reviewed
it and deliberately left it tentative — the semantics (the
definition, the strict prefix) were not doubted, but how to draw
the read understandably is unresolved, and a port on the collect
node read as a little backwards (see the note under the
definition). A worked candidate, not adopted.

Revised (design conversation, 2026-08-04, following end-when's
collect-until revision): terminators carry only the *reason* a
flow ends, never data, so the boundary payload is re-homed from
the segment terminator to a **value output on the outer flow** —
once per segment, its natural context. The law of segments and the
fused-collect rejection are amended in place below (the rejection
re-grounded: the iterated cut mints the outer flow, the home of
once-per-segment values, which is why it stays a flow operation
while the single cut fused into collect-until). Part III's
payload-as-terminator account is superseded on that point — see
its status note.

Two everyday shapes of loop have, so far, no owning construct
anywhere in this design record. The first is the loop that consumes
its input *at a variable rate* — "consume while it fits," "read
exactly N more bytes," "group while they repeat." The second is the
loop that reads *the output it has built so far*, mid-walk — an
indent chosen by whether any line has been emitted yet, a table
entry computed from earlier entries, a substitution looking up a
definition collected a moment before. This chapter works both,
because in the richest loop either survey sampled the two are
interlocked: you cannot finish the one without the other. An earlier
round (`end-when-design.md`) deliberately set this cluster aside for
a round of its own; this is that round. The full evidence — which
sampled loops demand these shapes, and how urgently — is gathered in
"Where this shows up in real code," near the end of the chapter.

---

# Part I: variable-rate consumption

## A loop that eats more than one element at a time

Here is the simplest program where consuming one element per step
isn't the right shape. Suppose you have the characters of a
sentence, and you want the words. Open the characters and each
firing of the flow is one character — but a word *spans several
characters*. There is no per-character answer to "what word is
this?"; a word only exists once you have grouped a run of characters
together. In conventional code you would write a loop inside a loop:
the outer loop starts a word, the inner loop keeps pulling
characters until it sees a space, and a cursor variable tracks how
far you have read.

Notice something about that description, though. When you *say* what
the program does — "the words are the runs of letters between the
spaces" — no cursor appears, and no count of characters appears
either. What you actually mean is: place a cut at every space. The
runs between the cuts are the words.

In the proposed construct, that program looks like this (the
spelling is provisional — open question 8):

```
-- spelling provisional (open question 8)
chars -> open list -> split kind of Space, Letter
  Space: -~> split-when         -- outer flow of segments; each carries an inner flow of one word's characters
-~> collect => words            -- collect the outer flow: one result per word
```

Read it the way you read a filter: build a case split on the
per-firing data (is this character a space?), then aim one alt at a
flow operation. Here the flow operation is **split-when**: wherever
the `Space` alt fires, a cut is placed, and what comes out is the
same characters, grouped into segments — one segment per word. The
rest of Part I develops this construct carefully; but the whole idea
is already in this example.

## Four real loops, one shape

The design record inherited a name for this gap: *data-dependent
take*, or "advance how far." That name carries imperative furniture
with it — a cursor, and a count of how far to move the cursor. Look
instead at what every sampled instance of the shape actually does:

- textwrap consumes chunks *until the line is full* — the chunks of
  one line are a **run** of the chunk sequence;
- the tokenizer consumes tokens *until the declaration ends* — the
  tokens of one declaration are a run of the token stream;
- framing consumes bytes *until the message is complete* — the bytes
  of one message are a run of the byte stream;
- run-length encoding consumes elements *while they repeat* — a run
  in the literal sense.

In each case the "count" — how many elements this step consumed — is
never interesting in itself and never appears in the data. What the
program means is a **partition of the input flow into consecutive
segments with data-determined boundaries**. The count is the
imperative encoding of a boundary position, the same way the flag
variable is the imperative encoding of end-when's terminator. Asking
"advance how far" was asking about the lowering — the translation to
a more concrete, cursor-shaped form — rather than about the meaning.

So the proposal is not a take with a count operand. It is a
segmenting operation, and the number never appears.

Now, you might wonder why the language doesn't just offer the count
directly — an `advance(k)` verdict, a chooser verdict or node
operand carrying how many elements to consume. That was in fact the
family's inherited framing. It turns out this is the wrong surface,
for three reasons: the count is the imperative encoding of a
boundary (no sampled program's *meaning* contained the number; every
one contained the run); it puts a bare integer where the record
wants drawn structure; and it loses the boundary payload that
discharge gives free (you will see below that each segment's
terminator carries the boundary firing's value — a count-based
construct has nowhere to put that). Where the data genuinely *is* a
count — framing's "read N more bytes," with N from the header — it
enters as data: a wire into a register that the boundary reads, not
as the construct's verdict. (This is a settled rejection — the
boundary reframing supersedes it; please don't re-propose it without
new evidence.)

## The ground rules, from earlier chapters

As with end-when, assembling the constraints is most of the work.
Everything split-when and the running view lean on is machinery the
record has already fixed; here is the inventory, because the
proposals use every item.

**Conditions are case splits, not predicates.** The language has one
vocabulary for "does this firing satisfy P": a case split producing
alt flows. Filter consumes such an alt (join); end-when consumes
such an alt (stop). Higher-order predicate arguments are rejected
(`configuration-scopes.md`). Whatever decides a segment boundary
must arrive as a flow.

**Derivation, not retroaction.** End-when's hardest-won rule: a
construct never reaches into an existing flow and changes what other
consumers see; it mints a derived flow beside it
(`end-when-design.md`, "Derivation, not retroaction"). A
variable-rate consumer obeys the same rule — other collects of the
same flow see the full, flat walk.

**The terminator machinery is uniform.** Every flow kind has a
termination event; terminators carry payloads; a whole-flow collect
discharges the terminator into an ordinary tagged value
(`async-flow-design.md`). Anything that ends a *segment* early has
this machinery available per segment.

**Option-kind relative to a parent** is a defined notion: a flow
that fires at most once per firing of the parent, in the parent's
context (`partial-collect-design.md`). A boundary operand will be
one, exactly as end-when's stop operand is.

**The stream runtime has three moves** — emit-and-continue,
become-the-rest, abandon-the-rest (`lazy-stream-placement-design.md`,
"The skip mechanism"). A construct that compiles to these rather
than demanding a fourth is at the right altitude.

**Registers and their check.** Loop-carried state is the register
designs (`iteration-with-state-design.md`, two live candidates);
both expose the carried value by wiring, and the well-formedness
check is "every cycle crosses a Delay/register" — decidable, with
the synchronous-dataflow precedent. A register on a nested flow
reinitialises per firing of the outer flow — nested loops already
mean this.

**Hand-rolled cursor loops are not handed to users raw.** The
record's diagnosis of the ordered merge stands as a warning for this
whole family: "manual cursor bookkeeping is the assembly language of
iteration" (`tough-use-cases-design.md`, obstruction 1).
Cursor-register lowerings may exist and be correct; they must not be
the surface.

**Derived views and derived-port reference exist on paper.** A
high-level node has an always-available, read-only derived
expansion, and a wire may reference the derived result's principal
ports without materialising anything
(`transformation-levels-design.md`, "Building on a derived view";
the worked client is reduce-close's augment expansion,
`iteration-with-state-design.md`, "A second accumulator on a sum").
This chapter gives that machinery its first *everyday* client, in
Part II.

## The shape: split-when, a binary flow operation

Here is the construct the opening example used, stated precisely.

**Split-when is a binary flow operation with asymmetric operands
(subject, boundary)** — asymmetric meaning the two operands play
different roles, as join's do. Both are flows. The `boundary` must
fire in the subject's own context, at most once per subject firing —
option-kind relative to the subject, in the sense above. The output
is a nested flow: an outer flow with one firing per segment, each
carrying an inner flow that fires with that segment's subject
firings, in order.

Its whole meaning is one law:

> **The law of segments.** Split-when partitions the subject's
> firings into consecutive segments. At each subject firing the
> boundary is consulted; where it fires, a cut is placed. The
> boundary firing's own element goes to the end of the current
> segment, to the start of the next, or to neither, per the node's
> boundary-destination setting. The boundary firing's value is
> emitted as a value output on the outer flow — once per segment,
> its natural context; option-kind relative to the outer flow,
> since the final segment has no boundary firing. (Revised
> 2026-08-04: it formerly rode the segment terminator; terminators
> now carry only the reason a flow ends, never data —
> `end-when-design.md`, revision notes.) Each segment's inner flow
> ends with a terminator saying it ended at a cut; the final
> segment ends the way the subject ends, terminator passed through.
> Every subject firing lands in exactly one segment (or is dropped
> as a delimiter), and order is preserved throughout.

## What follows from the law

The following are theorems of the law, not extra design — each falls
out of the one statement above:

- **Join inverts it.** With no dropped delimiters,
  `join(outer, inner)` over the segments reproduces the subject's
  firings exactly — segmentation adds structure without moving,
  duplicating, or losing anything. (With drops, it reproduces the
  subject filtered by the delimiter alt — split-plus-join *is* that
  filter.)
- **Per-segment values are subject values.** Each inner firing is a
  subject firing, so everything readable at a subject firing is
  readable in the segment body directly — the same prefix-rule
  admission as everywhere else (`bundle-provenance-design.md`). No
  transport machinery.
- **Per-segment state costs nothing new.** A register on the inner
  flow reinitialises at each outer firing — just what registers on
  nested flows mean. "Reset per line," "reset per message" needs no
  reset construct; the nesting is the reset.
- **Per-segment readout is discharge.** A whole-segment collect
  discharges that segment's terminator: "did this line end because
  the next word didn't fit, or because the words ran out" is a
  per-segment case split on existing machinery, parallel to
  end-when's readout.
- **The empty and total cases are unremarkable.** A boundary firing
  immediately gives an empty first segment; two adjacent boundary
  firings give an empty segment between them; a boundary that never
  fires gives one segment that is the subject. Empty segments are
  real programs (splitting on adjacent delimiters) and other
  programs filter them out downstream (textwrap's `if cur_line:`) —
  an ordinary filter on the outer flow, not a mode of the node.

Now, you might wonder why split-when is a separate operation at all
— why the language doesn't just give collect a mode: "collect until
full," "collect n," a collect-variant that fuses the boundary
decision into the collect node itself. With end-when's fusion into
collect-until (2026-08-04, `end-when-design.md`, revision notes)
the question sharpened — the single cut *did* fuse, so why not the
iterated one? — and the same conversation re-grounded the answer:
**the iterated cut mints a new flow and the single cut does not.**
The outer flow — one firing per segment — is structure that exists
in no prior flow, and it is the home of every once-per-segment
value: the boundary payload, per-segment collect outputs. A fused
node cannot supply that home; fusing away the outer flow would
leave those values with no flow to live in. (The earlier grounding
— independent consumers of one segment would each re-decide the
boundary under multi-close — survives as a supporting cost; it is
the same repeat-the-wires cost collect-until accepts as tidiness
at the prefix, where no new flow is at stake.) A flow output
exists where there is a need: split-when produces its nested flow
because once-per-segment values need it; an unfused collect-until
could produce a truncated flow the same way (emitting the terminal
immediately as a constant wire), but doesn't, because no need has
been sighted. The rejection of the fused segment-collect stands —
please don't re-propose it without new evidence.

## The same wiring pattern, a third time

If you have learned to filter, you have learned most of split-when
already. The same operand pattern now recurs a third time:

| operation | operands | yields |
|---|---|---|
| join (filter) | (subject, alt flow) | the firings where the alt fires |
| end-when | (subject, stop) | the firings before the stop first fires |
| split-when | (subject, boundary) | the firings, grouped between boundary firings |

Three verbs, one wiring discipline: build a case split on per-firing
data, aim one alt at a flow operation. Here it is on the token
stream of the tokenizer example (again, spelling provisional):

```
-- spelling provisional (open question 8)
tokens -> open list -> split decl of Boundary, Within
  Boundary: -~> split-when      -- outer flow of segments; each carries an inner flow of that declaration's tokens
-~> collect => decls            -- collect the outer flow: a list of per-declaration results
```

The line above says: cut the token stream into declarations wherever
a `Boundary` alt fires, then collect one result per declaration.

## Where does the boundary element go?

There is one genuinely local choice on the node, and you have
already met its little sibling: end-when needed one bit (is the
stopping element in, or out?). Split-when's boundary element has
three possible destinations, and all three are everyday — each is
sighted in the wild:

- **Starts the next segment** (the exclusive reading). The wrap
  loop: the chunk that doesn't fit isn't dropped and doesn't end the
  line — it is the first chunk of the *next* line. Adjacency
  grouping (run-length encoding, groupby) is the same: the element
  that differs begins the new run.
- **Ends the current segment** (the inclusive reading). Framing: the
  byte that completes the message belongs to the message.
  Take-until-inclusive, per segment.
- **Dropped** (the delimiter reading). Splitting on separators:
  str.split, CSV fields, blank-line paragraph splitting. The
  boundary element is neither segment's; its value is still emitted
  on the outer flow, so "which delimiter was it" is not lost. (Our
  opening words-from-characters example uses this reading — the
  space belongs to no word.)

With the cut decision (2026-07-23) this setting is **three-valued
at the root**: the boundary element goes to the prefix
(inclusive), to the head of the continuation (starts-next), or
nowhere (dropped). It lives on the node, following end-when's
adopted node-home. End-when's adopted two-valued bit is this
setting's *projection* when the continuation is unused — and the
projection is what made "exclusive" look binary: without a
continuation, starts-next and dropped are indistinguishable;
with one, they are two settings (continue from the sentinel vs
skip the delimiter). The spelling is one word family — end-when's
`to`/`until` direction plus a third word for dropped — decided
once in the textual round. This is configuration in the
established sense, not a construct.

One consequence worth noting rather than smoothing: under the
starts-next reading, the boundary condition at element `e` is
evaluated against the *current* segment's state (does `e` fit in
this line?), and `e` then lands in the *next* segment, whose state
starts fresh. That is not an anomaly — it is precisely what "doesn't
fit, so it goes on the next line" means, and what every
chunk_while-family API does — but the law's phrase "the boundary is
consulted at each subject firing" should be read with this in mind:
the consultation happens in the segment the element would have
extended.

## When the boundary reads the segment's own state

Here is the construct's hard case, and it turns out to land on a
check the language already runs.

The wrap loop's boundary reads `cur_len` — the running total of the
current segment. Structurally this is a cycle: split-when produces
the inner flow; a register lives on the inner flow; the boundary
split reads the register's state port; the boundary feeds
split-when. Is that legal?

Yes, and by the existing rule, not a new one: the register's state
port is a previous-firing read (the strict prefix of the current
segment), so the cycle crosses the register — exactly the "every
cycle passes through a Delay crossing" condition
(`iteration-with-state-design.md`, "Ruling out non-productive cycles
structurally"). Unwound: the boundary decision at firing *e* reads
state folded from firings before *e*; where segments start was
decided at firings before *e*; induction over the subject's order
grounds everything. A boundary wired from the *current* element
alone (a sentinel test, or adjacency against a carried previous
element) doesn't even have the cycle.

## You have met this construct before

The shape is heavily precedented in other languages, which is
evidence for the reframing (the way Lustre's `pre`/`->` was for the
Delay):

- **Ruby** `Enumerable#slice_when` / `#chunk_while` — segmentation
  by an adjacent-pair condition; the two names are the
  boundary-destination bit surfacing in an API.
- **Python** `itertools.groupby` — adjacent grouping by key change:
  a split-when whose boundary is "key(e) ≠ key(previous e)", i.e. a
  case split reading a one-element register. Note it is *not* the
  keyed collect / group-by open from the concurrency round, which
  partitions by key value regardless of adjacency — different
  constructs in the wild too, a reassuring confusion already
  disambiguated by this record's vocabulary.
- **SQL's "gaps and islands"** — grouping events into sessions by
  time gap; islands of consecutive activity. Famous as a *hard
  problem* precisely because SQL lacks the construct and it must be
  built from window functions and running counts — a whole genre of
  blog posts is the field's testimony that the missing vocabulary
  hurts.
- **Parser toolkits' take-while families** — the
  take-while/span/break cluster is the one-segment special case,
  ubiquitous.

## Worked programs

### The wrap loop, end to end (breadth item 1)

The sharpest standing challenge in the breadth set, drawn in full.
(A construct list rather than chains, deliberately: the split-when,
running-view, and end-when spellings are each owed to the textual
round, so arrow-form text here would be invented three times over;
the list is the composition, not parseable syntax.)

    chunks:   uncollect the chunk list                  (subject)
    lineLen:  register on the inner flow — init 0,
              step = state + len(chunk)                 (per-segment)
    width:    indent-dependent width (see Part II — the running view)
    fits?:    case split on lineLen.state + len(chunk) > width
              → {overflow, fits}
    B:        split-when(chunks, overflow-alt),
              boundary element starts next segment
    lines:    per segment — collect the chunks, join with the
              indent prefix → one line; outer collect gathers lines
    indent:   initial vs subsequent — reads whether the line
              collect's running view is empty (Part II)
    truncate: end-when on the outer segment flow (a count register's
              alt fires at max_lines); the discharged terminator says
              truncation happened and carries what remained; the
              placeholder amendment to the last line happens
              downstream, on the collected prefix (Part II — the
              rewrite dissolves)

Empty-line suppression (`if cur_line:`) is a filter on the outer
flow. What is honestly not covered: `break_long_words` — splitting a
single chunk that exceeds the width is production *within* an
element, not consumption across elements; it composes as a
pre-processing flow (each chunk opens into fragments) and is out of
this construct's scope, correctly.

The count of coordinated pieces is real — a segmentation, two
registers, a running-view read, an end-when — but compare the
sentence the loop says: "group the words into lines that fit,
indenting the first line differently, stopping at max_lines." Each
clause is one construct; nothing in the drawing is bookkeeping. The
survey's complaint was that the pieces had no owners; the pieces now
compose.

### Framing (the datagram parser's read-N-more)

"Read exactly N more bytes, where N came from the header":

    bytes:    the incoming byte stream                  (subject)
    st:       register on the inner flow — a two-alt value:
              Header(got) → counts header bytes, computes N at the
              4th; Body(remaining) → counts down
    done?:    case split: Body(0) after this byte → boundary alt,
              payload = the parsed header
    B:        split-when(bytes, done-alt), boundary element ends
              the current segment
    msgs:     per segment — the message bytes, with the header on
              the segment terminator

The genuinely-numeric count enters as *data* — the header's N feeds
a register the boundary reads — not as a verdict of the construct.
That is the correct division of labour: the language draws the
boundary; the program computes where it falls. Honest assessment:
this is expressible and causally clean, but the two-phase register
is a hand-built state machine at exactly the granularity the custom
protocol flows question (`tough-use-cases-design.md`, inventory item
7) worries about. A catalog "fixed-length segment" block with the
obvious derived lowering would make the everyday case one gesture
(open question 4).

### The tokenizer-substituter (breadth item 2)

Two levels of the same construct plus Part II's running view:

    tokens:       the token stream                      (subject)
    decl?:        boundary — a declaration ends where the next
                  variable_name begins (starts-next reading)
    B1:           split-when(tokens, decl-boundary) → declarations
    within one declaration:
      phase sub-segments (name, whitespace run, definition run) —
      split-when again, on the inner flow, with adjacency
      conditions (token-kind changes)
    variables:    keyed collect of (name, definition-tokens),
                  contributed per declaration
    substitute:   inside later declarations, a variable_ref token
                  reads variables' running view by key (Part II)
                  and opens the stored tokens in its place

The consumption structure — variable-rate pull, nested
state-dependent sub-walks — is two nested split-whens, and the
mid-walk readback is one running-view reference. What strains: the
real parser's interior is a grammar, and past two levels of
segmentation a grammar wants grammar-shaped vocabulary (the divide
flow's territory, or custom flows). The breadth test asks "without
too much pain," and the honest answer is: the two shapes that made
this loop a breadth item are each one construct now; a full CSS
parser would still be work. That is the right boundary — split-when
is tokenization-and-framing vocabulary, not a parser generator.

### Skip-while, and the relationship to end-when

The predicate cursor — skip leading matches, keep the rest — is
split-when with a boundary at the first non-match, keeping the
*second* segment: the complement of end-when's prefix in one
drawing. This adjacency is systematic:

- `end-when(F, c)` is the *first segment* of `split-when(F, c)`
  (with the matching destination bit);
- skip-while is the join of the rest;
- take-while / span / break — the whole classical cluster — are
  projections of one cut.

You might wonder, then, whether end-when and split-when should just
be one construct. This round's leaning was **record the
relationship, do not unify** — and the design conversation of
2026-07-23 *overrode the leaning while keeping its reasons*. The
leaning's reasons were that end-when is promoted by frequency and
must stay one everyday gesture with a flat output (eighteen of
sixty sampled loops; a flow, not a flow of flows) — reasons
against making end-when wear split-when's weight. The decision
inverts the derivation instead: both branch off one root, the
**cut** ("when"), one construct yielding (prefix, payload,
continuation), all flat. The everyday author taps prefix and
payload alone — that *is* end-when, the cut's prefix projection,
one gesture, no second segment conceived; skip-while is the
continuation projection; span/break tap both; and split-when is
the cut *iterated*, the derived form that alone carries nesting.
The level-1 recognition this passage used to carry ("an end-when
is a split-when observed at its first segment") is superseded by
the root reading — the derivation now runs the other way. What
the projections share is unchanged and now structural: one
boundary/stop operand discipline, one destination setting
(three-valued at the root, above) — the same family-level sharing
as the verdict-vocabulary rule recorded for the merge (end-when's
open question 3).

## The advance family, after this round

The tough doc's open question 5 asked: one primitive (a chooser over
N heads returning which-advances) or a small family? The picture
this round leaves:

- **advance-or-stop** — end-when. Worked, standalone
  (`end-when-design.md`).
- **advance how far** — dissolved. Not a chooser verdict and not a
  count: boundary placement, owned by split-when.
- **which of two advances** — the decision-driven merge. It is
  genuinely not a segmentation (two subjects, one interleaving), and
  this round left it the chooser sketch it had. *Its round now
  exists* (`chooser-family-design.md`, exploration).

The leaning on the question itself: **no N-head chooser primitive at
the surface.** Each family member keeps meeting its own everyday
shape with its own drawing; the chooser — per-step verdicts over
heads — is the shared *lowering* shape (all three lower to
cursor-register programs, which is where "the assembly language of
iteration" belongs: below the surface, readable on request, per the
source-of-truth principle). The family is one family at the
semantic-vocabulary level: stop verdicts write the same terminator,
boundary/stop operands obey the same option-kind discipline,
destination bits share one enumeration. If the merge's round finds
its chooser wanting the same dissolution — interleaving as something
drawn rather than decided — the family gets simpler still; that is
that round's question. *That round now exists and answers yes*
(`chooser-family-design.md`, exploration): the interleaving is
drawn — the merge exposes per-step heads and takes a late-wired
advance operand, the decision between them being an ordinary case
split, race, or register read — and this passage's leaning sharpens
to *no N-head chooser anywhere, surface or lowering* (the lowering's
chooser was the corecursive costume of a case split).

## By kind, and the compile

Sketches only; nothing here touches `src/Compile.res` — the ports
migration these sketches assumed has since landed (`src/Program.res`
is ports-first).

- **List subject**: the lowering is the textwrap loop itself — an
  outer while over an inner while, the boundary check deciding the
  inner break, the destination bit deciding whether the element is
  pushed before or after the check (or not at all). That the derived
  lowering is verbatim the code the survey drew at random is the
  same strong-form philosophy argument the ordered merge made: the
  lowering exists, is correct, and nobody should read it unless they
  ask.
- **Stream subject**: the outer stream's pull produces a segment
  whose inner stream consumes from the shared source cursor; ending
  a segment is abandon-the-rest aimed at the segment's terminator —
  the third existing move, no fourth needed. The real constraint is
  sequencing: inner flows share one underlying cursor, so segments
  must be consumed in order, and an outer consumer that skips ahead
  forces either draining or buffering the skipped segment — the same
  retention/pull-amplification footgun family the stream docs
  already track for `Delayed`. Flagged for the stream rounds, not
  designed here.
- **Self-driven / async subjects**: nothing kind-specific appears —
  the law is stated over firings and terminators, both uniform. The
  concurrency caveat is end-when's verbatim: "consecutive" is
  order-dependent, so split-when off `serial` means
  schedule-determined segments, which must be meant if admitted.

---

# Part II: the running view of a collect

## The question the indent asks

Back to the wrap loop for a moment. While it is building its list of
lines, it has to choose an indent for each new line — and the rule
is "the first line gets the initial indent; every later line gets
the subsequent indent." How does the loop know, mid-walk, whether
this is the first line? The wild Python asks `if lines:` — it looks
at *the very list it is building* and checks whether anything is in
it yet.

That gesture — a loop reading the output it has built so far, while
still walking — turns up over and over. It has three guises: reading
the whole output-so-far (textwrap's `lines`), reading it by index (a
dynamic-programming table whose entry *n* is computed from earlier
entries), and reading it by key (the tokenizer's `variables` map,
written during the walk and looked up later in the same walk). All
three ask for one thing: **the collect's output-so-far, readable
per-firing inside the walk.**

## The recognition: the record already contains this construct

The survey filed this demand between multi-close and the register
designs. It belongs to neither; it falls out of machinery the record
has already built, in the iteration-state round's own vocabulary.

A list collect *is* — as a derived view — an augment loop whose
register carries the built list and whose step is append
(`iteration-with-state-design.md`, "Reduce-close is its own result
node, lowered in compile", and "A second accumulator on a sum, via
derived-port reference": the derived augment form, and references to
its ports, are exactly the mechanism already designed for adding a
lockstep accumulator to a `sum`). That derived register has a state
port. **The running view of a collect is the state port of the
collect's derived augment form.** A keyed collect's derived register
carries the map-so-far; its state port is the read-by-key view. No
new node species anywhere.

So the proposal is a *definition*, not a construct:

> **The running view.** Every collect exposes, as a principal port
> of its derived augment form, its accumulated output: at each
> firing of the collected flow, the value built from the strict
> prefix of firings before this one. The port is read by ordinary
> wiring, in the collect's flow context; reading it never
> materialises the derivation (`transformation-levels-design.md`,
> "Building on a derived view: wires may reference derived ports").

Whether the port is *drawn on the collect node itself* (the friendly
surface) or reached by explicitly referencing the derived view is a
presentation question; the leaning is on the node, defined as the
derived port — one thing, surfaced.

The design conversation of 2026-07-23 reviewed this proposal and
**deliberately left it tentative**. The semantics were not
doubted — reading what has been built so far is implementable, and
the definition above says what it means. What kept it from
adoption is the drawing: how to draw the read *understandably* is
unresolved, and a port on the collect node struck the conversation
as a little backwards — the collect's one job is to be the place
where the flow becomes a value at the end, and a mid-walk output
port muddies that reading. The next round here should treat the
surface as the open problem and the definition as its fixed
semantic target.

## Reading the past is safe: the check that transfers

The strict-prefix time shape in the definition is load-bearing. A
body that both contributes to a collect and reads its running view
is a cycle: body → collect → derived register → state port → body.
It is productive by the existing rule — the read crosses the derived
register (a previous-firing read), so "every cycle passes through a
Delay crossing" holds — and non-degenerate: the current firing's own
contribution is never visible to itself. The wrap loop's indent read
sees lines emitted *before* this line, which is what the wild code's
`if lines:` meant. The DP fill's entry *n* reads entries produced at
earlier firings, which is what dynamic programming *is*.

Two boundaries the existing rules already police, stated so nobody
re-derives them:

- **Sibling reads are time travel.** The running view is readable in
  the collect's own flow context (and descendants, by the prefix
  rule). Reading one loop's so-far from a sibling loop not on the
  same nesting chain is the ordinary no-time-travel violation,
  caught by the ordinary check.
- **Reads pin the order.** A collect whose running view is read is
  order-committed — under the concurrency round's species it is
  `serial` by structure (the read means "before" means something).
  Same interaction the registers already have; flagged for that
  round's table.

## The three guises, mapped

- **Read-whole** (textwrap's `lines`): the state port's value, a
  list; emptiness-testing it is a value operation. The
  first/subsequent-output split the survey noticed — "the
  first-iteration distinction appearing in the wild as a read of the
  accumulated output" — is exactly this: no first-firing construct,
  just an ordinary case split on the running view's emptiness.
- **Read-by-index** (the DP table): index into the running list — a
  value operation on the port. The efficiency worry dissolves in
  compile: the collect is materialising an array anyway; the running
  view compiles to reading the accumulator in place, O(1), no copy.
  (Visible in the lowering: `s += ... zeta_values[2*k] ...` — the
  wild code *is* the compile target.)
- **Read-by-key** (the tokenizer's `variables`): the keyed collect's
  running map, `get` by key returning option — the option-shaped
  miss is honest (a reference to a variable not yet defined is a
  real case the wild parser also handles).

## Rewriting the past?

There is a fourth guise in the wild code that the running view does
*not* — and must not — cover as written. Textwrap's truncation path
*rewrites* `lines[-1]` mid-walk: when the line limit is hit, it
amends the last line with a placeholder.

Now, you might wonder why the language doesn't just make the running
view mutable — let the body write into the collect's past
(`lines[-1] = ...` mid-walk). It turns out this would cause
problems: writing into a collect's past from the body is retroaction
on already-emitted values, exactly what derivation-not-retroaction
forbids — it would make one consumer's body retroactively change
what every other consumer of the same collect sees. And it is not
needed. Worked against the actual program: the rewrite happens
*once, at termination* — it is not a mid-walk operation at all, it
is part of the readout. The time-forward expression: end-when cuts
the segment flow at max_lines; the discharged terminator says the
walk was truncated (and carries what remained); downstream, on the
collected prefix — a plain list value in hand — the last element is
amended. Collect, discharge, amend: all existing vocabulary, all
after the walk, which is when the wild program actually knows
truncation happened too. The mid-walk appearance of the rewrite in
the Python is an artifact of writing the readout inside the loop
body for lack of anywhere else to put it. If a future sample ever
produces an *element*-conditioned rewrite (rather than a
termination-conditioned one), that is lookahead — window territory —
still not mutation. (This is a settled rejection of the mutable
running view — please don't re-propose it without new evidence.)

General rule worth recording: a "rewrite of the output-so-far"
conditioned on termination belongs downstream of discharge; one
conditioned on later *elements* is a one-firing lookahead, which is
window/negative-delay territory and was drawn in neither survey. If
a sample ever produces the second kind, it files there, not here.

## What this presses on

The running view makes derived-port reference — until now exercised
only by the `sum`+`max` example — **load-bearing for everyday
programs**. Two consequences for other rounds:

- The transformation-levels question "which derived ports are
  principal" (`transformation-levels-design.md`, "What is
  unresolved"; echoed in `iteration-with-state-design.md`) gains
  urgency and a concrete first answer to test: *the augment form's
  state port is principal for every collect.*
- The iteration-state decision gains a datum: whichever candidate is
  chosen must leave collects with a coherent derived augment form,
  because the running view is defined through it. Pressure on the
  *machinery*, not a thumb on the scale between the candidates —
  both can express the augment loop; what matters is that the
  derived-view story stays real.

---

## Against the principles

How the two proposals square with the seven design principles
(`language-design-philosophy.md`):

- **Example first, then generalise.** Both proposals are
  after-the-fact additions to a concrete walk: build the flat walk,
  then place boundaries (split-when interposes on existing wiring);
  build the collect, then read its so-far (the port was always
  there, derived). Neither requires declaring structure upfront —
  contrast a chunking combinator parameterised by a size function,
  which demands the generalisation before the first concrete line.
- **Inside-out / cases as values.** No lambdas, no interior scopes,
  no magic names. The boundary is a visible case split; per-segment
  state is a register wired like any register; the running view
  arrives on a wire. Segment terminators are values you discharge.
- **Foundations before features.** Split-when's new content is one
  law and a three-valued bit; everything else — option-kind
  operands, terminators, registers-on-inner-flows, the productivity
  check, discharge — is settled machinery. The running view adds
  *no* construct: it is a definition over the derived-view
  machinery. Three dead ends died on paper — the three settled
  rejections recorded in the "you might wonder" passages through
  this chapter.
- **Programmer's abstraction level.** "Group these into runs," "the
  lines so far" are words in the programmer's vocabulary, and each
  gets one reading. The gaps-and-islands genre is the
  counterevidence for the status quo: without the vocabulary, the
  program is a puzzle.
- **No bottlenecks.** Segments pass elements through as themselves —
  the inner flow *is* the subject's firings, not a packed list per
  segment (collecting each segment into a list is a choice made at a
  collect, downstream). The boundary payload rides the segment
  terminator; nothing is tupled to cross the construct.
- **Abstraction is the source of truth.** Split-when's lowering is
  the nested-while program the survey drew; the running view's
  lowering is the in-place accumulator read. Both stay derived
  views; the authored program keeps the segmentation and the port.
- **Building blocks must build.** The ladders, walked:
  - *Plain collect* → **+ segmentation** (add a boundary split and
    the split-when; re-aim the collect at a segment) →
    **+ per-segment state** (a register on the inner flow) →
    **+ boundary reads the state** (rewire the split's input) →
    **+ per-segment readout** (discharge the segment terminator) →
    **+ outer state** (register or running view on the outer flow) →
    **+ truncation** (end-when on the outer flow). The top of this
    ladder *is the wrap loop* — breadth item 1 reached from a plain
    collect with no species change at any rung, the expansion test
    the breadth set demands.
  - *Collect* → **+ read the so-far** (wire from the port) →
    **+ read by index/key** (value ops on the same wire) → **+ the
    DP fill** (the body's inputs now include the port; nothing else
    moved). Breadth item 4, by additions.
  - The interlock rung: the wrap loop's boundary reading the running
    view (width ← indent ← emptiness) is a wire between the two
    proposals, not a new construct — the composed program is still
    additive.

## Where this shows up in real code

The evidence that motivated this round, gathered from the record.
This is the record's only Tier-1 area with **no owning construct
anywhere** (`open-problems.md`): three of the nine breadth-set loops
— the wrap loop, the tokenizer-substituter, the DP table fill — have
no designed owner, and the survey locates "where the language's
breadth risk currently concentrates" exactly here
(`real-loop-survey.md`, "the 80/20 counterweight"). The end-when
round bounded this cluster out on purpose ("the take question stays
with the decision-driven family round" — `end-when-design.md`).
This chapter is that round.

The demand, item by item:

- **The wrap loop** (breadth item 1; survey 1, textwrap). The
  richest loop in either sample: chunks consumed at a variable rate
  ("consume while it fits" — a data-dependent take), the
  output-so-far read back mid-loop twice (the indent chosen by
  whether any line has been emitted; the truncation path *rewriting*
  `lines[-1]` and breaking). The survey's verdict: "nothing in the
  current or candidate inventory covers this loop as one reading."
- **The tokenizer-substituter** (breadth item 2; survey 2).
  Pull-based consumption at a variable rate — nested sub-loops
  consume more tokens depending on what was seen — plus a keyed
  accumulator written *and read back* during the walk (definitions
  collected, then substituted into later references).
- **The DP table fill** (breadth item 4; survey 2). A collect whose
  per-element body indexes into the collect's own earlier output —
  scan-with-full-history, "stronger than the running-view question
  and stronger than window," and "the bread of numerics."
- **The running view, three guises** (survey 2, finding 2.5): the
  same demand sighted independently as read-whole (textwrap's
  `lines`), read-by-index (the DP table), and read-by-key (the
  tokenizer's `variables`) — "a recurring demand, not a curiosity,"
  filed between multi-close and the register designs, owned by
  neither.
- **Protocol framing** (`tough-use-cases-design.md`, use case 5):
  "read exactly N more bytes, where N came from the header" —
  decision-driven consumption from the datagram side.
- **The decision-driven family's unworked members**
  (`tough-use-cases-design.md`, inventory item 4, open question 5):
  the ordered/decision-driven merge has a worked sketch;
  *data-dependent take* — "advance how far" — has only its name. The
  end-when round answered the advance-or-stop half; the
  advance-how-far half is here.
- **Small everyday sightings**: skip-while (a predicate cursor),
  chunking, run-length-encoding-shaped adjacency grouping.

One observation organises the round: in the wrap loop the two halves
are *interlocked* — the boundary decision ("does this chunk fit?")
depends on the width, which depends on the indent, which depends on
the running view (has any line been emitted yet?). That is why they
are worked together.

## What this changes elsewhere, if adopted

Nothing is dissolved or corrected; two named holes get worked
proposals. If the design conversation adopts some form of these:
breadth-set items 1, 2, and 4 gain owners to be tested against; the
tough doc's open question 5 closes (end-when standalone — already
leaned; advance-how-far dissolved into boundary placement; the merge
stays the family's one chooser member, pending its round); survey
finding 2.5's question gets its answer (derived state port, strict
prefix); `core-model.md` would gain split-when a line beside join
and end-when in the operand-pattern family — but not before
adoption. The transformation-levels round inherits the
principal-port pressure either way.

## Open questions

The language hasn't decided any of the following yet:

1. **The destination setting's final form.** Decided at the cut
   decision (2026-07-23): three values at the root, on the node
   (following end-when's adopted node-home), end-when's two-valued
   bit its projection when the continuation is unused. Remaining:
   the drawing (layout-side); the word triple's spelling (jointly
   with end-when's `to`/`until` direction — one family, textual
   round); and the stacked-stops tie-break interaction recorded in
   end-when's question 1 presumably has a sibling here (two
   boundaries tying at one firing — same regime analysis, one bundle
   vs independent splits — assumed to transfer, unverified).
2. **Empty segments.** The law permits them; is downstream filtering
   the whole everyday story, or does the drop-empties idiom deserve
   a recognised spelling (str.split's split-vs-fields distinction
   suggests users will reach for it constantly)?
3. **Nested and phased segmentation vs grammar vocabulary.** Two
   levels served the tokenizer; where is the honest boundary beyond
   which this is the divide flow or custom protocol flows? A worked
   third program (the binary protocol parser from the use-case
   backlog) would locate it.
4. **A fixed-length-segment catalog block.** Framing's two-phase
   register is expressible but state-machine-flavoured; decide
   whether `segments of length n (n from data)` earns a catalog
   entry with a derived lowering onto split-when.
5. **The stream compile's sequencing constraint.** In-order
   consumption of segments, and what an out-of-order outer consumer
   forces (drain vs buffer) — belongs to the stream rounds, with the
   `Delayed` footguns.
6. **Principal derived ports.** The running view proposes "the
   augment state port is principal for every collect" — confirm in
   the transformation-levels round, and pin which other ports (the
   combined flow, the final value) join it.
7. **Concurrency interactions.** Split-when off `serial`; a
   running-view read pinning a collect to `serial` — both flagged
   into the concurrency round's tables.
8. **Textual spellings.** The (subject, boundary) pair, the
   destination setting, segment-terminator discharge, and the
   running-view reference all need spellings in the three-arrow
   textual form (the samples above are provisional); that document's
   next round.
9. **Naming.** "Split-when" deliberately rhymes with end-when;
   "running view" vs "so-far" vs the survey's phrase. Deferred, with
   one constraint each: the segment construct's name should read as
   a flow operation yielding *nested* flow (the nesting is the
   point), and the view's name must not suggest mutability. The cut
   decision adds a member: the root's name ("when" is the
   conversation's working word) — decided with the family.
10. **The cut round's open edges** (filed at the cut decision,
    2026-07-23). *Now worked below* ("The cut round", Part III) —
    all three edges carry worked answers, none adopted:
    - **How iteration is drawn.** All-segments = tapping the
      continuation repeatedly — a corecursive unrolling, and the
      record declines to hand users raw corecursion. Worked: the
      one-node form is total by construction; the unrolling is a
      spine-shaped link (a derived view, never a surface); the
      "catalog block vs level-1 recognition vs both" question
      resolves as both-with-distinct-jobs.
    - **The continuation on RanOut.** Worked: an empty flow, never
      an option-kind one; "did a cut happen" lives on the prefix's
      terminator alone.
    - **Payload availability from the continuation side.** Worked:
      the payload's one home is the prefix's terminator; a
      continuation-only consumer discharges the prefix it was
      already forcing; the flow-borne check passes as an ordinary
      exterior-value admission.

---

# Part III: the cut round (open question 10, worked)

Status: worked, **not adopted** — the round the cut decision
(2026-07-23) filed here: the root construct's own account, prepared
for a design conversation. It consumes end-when's adopted law and
its stacking section's restriction rule (`end-when-design.md`), the
divide flow's adopted measure discipline
(`divide-flow-design.md`), the owned-order criterion
(`delay-ontology-design.md`), and the barrier-value-crossing
adoptions; it decides nothing. Everything in Parts I and II stands
unchanged — this part is about the root the decision named, not a
revision of the segments story.

*Revision note (2026-08-04): the payload-carriage account below is
superseded on one point by end-when's collect-until revision
(`end-when-design.md`, revision notes): terminators carry only the
reason a flow ends, never data. In the iterated form the boundary
payload is a value output on the outer flow (Part I's amended
law); the everyday single-cut owner is the fused collect-until,
whose terminal output is an ordinary value output on the node. For
a single unfused cut, the admissible form is the node emitting the
payload immediately as a constant value wire (the register
final-readout precedent — a value anchored to a completed extent),
a construction currently without a sighted need; it sits in
tension with the crossing-round stance cited under "the payload is
not a port" and with dead end 2, a tension to argue only if the
construction is ever needed. "Payload availability from the
continuation side" re-poses as reading that constant; its
exterior-context admission argument carries over unchanged.*

## The construct, precisely

**The cut is a binary flow operation with asymmetric operands
(subject, boundary) and two flow outputs (prefix, continuation).**
The operand discipline is end-when's verbatim: the boundary fires
in the subject's own context, at most once per subject firing —
option-kind relative to the subject.

Everything the node means is one law:

> **The law of the cut.** The prefix fires with each firing of the
> subject, in step with it, up to the first subject firing at
> which the boundary fires; there it terminates, and its
> terminator's payload is the boundary's value. The continuation
> fires with each subject firing after the cut, in step with the
> subject, and ends the way the subject ends, terminator passed
> through. The boundary firing's own element goes to the end of
> the prefix, to the head of the continuation, or to neither, per
> the node's three-valued destination setting. If the boundary
> never fires, the prefix is the whole subject (terminator passed
> through) and the continuation is empty, carrying the subject's
> terminator.

The decision's triple — (prefix, payload, continuation) — is the
cut's *information content*, not its port inventory. **The payload
is not a port.** It rides the prefix's terminator, discharged at a
whole-flow collect exactly as end-when adopted; the cut is a flow
operation with flow outputs only, per the crossing round's adopted
stance (a value wire is neither upstream nor downstream of a flow
operation — `barrier-value-crossing-design.md`). A payload value
port on the node would give the same value two homes and would be
a pass-through value port on a barrier, both of which that round
rejects. (Recorded dead end 2, below.)

The projections, restated on the port inventory:

- **End-when is the cut with the continuation unconsumed.**
  Nothing about the adopted drawing changes; the everyday author
  still conceives the prefix alone.
- **Skip-while is the cut with the prefix uncollected** — but not
  unwalked; see the payload section below.
- **Span/break tap both ports of one cut.** The classical tuple
  form is the packed costume; here the two flows emerge as
  themselves, no product bottleneck.

## The continuation on RanOut

If the boundary never fires, the continuation is **an empty flow,
not a nonexistent one**. Three reasons, one home:

- The field's evidence is uniform: every dropWhile-family
  operation returns the empty collection, not an absence — the
  downstream consumer's shape must not change with the data.
- "Did a cut happen" already has a home: the prefix's discharged
  terminator (`Stopped(v)` vs the subject's own ending). Making
  the continuation's *existence* carry the same bit would state
  one fact in two places.
- In the iterated form the final segment must be the same species
  as every other segment (the law of segments already says so:
  "the final segment ends the way the subject ends"). An
  option-kind continuation would make the last level of the
  unrolling a different construct than the rest.

A failable subject passes its terminator to *both* outputs: if the
subject fails before any boundary firing, the prefix ends
`Fail(e)` and the empty continuation carries `Fail(e)` too. That
is not duplication of meaning — it is the multi-close model doing
what it always does (several independent consumers of one walk
each discharge the terminator they reach), and a consumer that
handles the failure on one side and ignores the other is drawing
exactly that choice.

Now, you might wonder why the continuation isn't option-kind —
present only when the cut happened, so that a consumer "knows"
structurally. It turns out this packs a sum around a flow for no
client (no sampled skip-while wants a missing-vs-empty
distinction), moves the Stopped/RanOut bit out of its terminator
home into a second structural home, and breaks the iterated form's
uniformity as above. (Recorded dead end 1 — please don't
re-propose it without new evidence.)

## Payload availability from the continuation side

Skip-while taps only the continuation. Where is the boundary's
payload readable? Start from an operational fact the drawing
should honour rather than hide: **you cannot demand the
continuation without walking the prefix.** The continuation's
first firing is defined by where the boundary first fired, so
demand for it forces every prior subject firing and every boundary
consultation. A continuation-only program has the prefix walk in
its cone whether it draws a collect there or not.

So the account needs no new machinery: the payload's one home is
the prefix's terminator, and a continuation-side consumer reaches
it by **collecting the prefix and using only the discharged
terminator** — the folded prefix simply unused, exactly as the
first-match example already leaves `prefix` unused when only the
hit matters (`end-when-design.md`). The light spelling for this —
a terminator-only discharge, no fold binder — is already on the
textual round's owed list (`open-problems.md`, Tier 4, "the
discharge readout's binder convention and terminator-only form");
this round adds its second client.

The check the question asked for: the discharged terminator is a
value settled at most once per walk, in the walk's **exterior**
context (the prefix's completion is an event of the exterior, not
of any firing). Combining it with continuation-borne values is
therefore the ordinary ancestor-into-descendant admission — the
same prefix-rule shape as reading any exterior value inside a
loop — and the flow-borne rule is satisfied without a new
admission. What would *not* pass is the converse (reading a
per-firing prefix value from the continuation's context), and that
is the ordinary sibling clash, correctly witnessed.

One coincidence worth naming so it doesn't get promoted into
mechanism: under the starts-next destination the payload *is* the
continuation's head element — the same firing, reachable as
per-firing data. That is a fact about one destination setting, not
a second route: the terminator stays the canonical home because it
is destination-independent, and "the head element, read specially"
would be a magic position, which the inside-out principle forbids.

## How iteration is drawn: the iterated cut

The decision expected split-when to "live as a derived/catalog
construct over the cut," and filed the structural question: catalog
block, level-1 recognition, or both? Work it from both ends.

**The chain cannot be drawn.** All-segments = cut, tap the
continuation, cut again — one cut node per segment, and the
segment count is data. No finite drawing exists, so the chain is
not an authorable surface, and it is not a catalog block's
expansion either: a catalog block lowers to a *drawing*, and there
is no drawing here to lower to. This is the raw corecursion the
record declines to hand users, now with the reason stated
structurally rather than as taste.

**The one-node form is total by construction.** Split-when as
Part I states it consults the boundary once per subject firing and
places at most one cut per consultation — a single pass. A finite
subject therefore yields finitely many segments with no measure
owed, no productivity question, no rung of any ladder. That is the
decisive argument for the node being the everyday surface: the
chain form owes a termination story; the node form cannot even
express the question.

**The unrolling is a spine-shaped link.** The derived view the
decision asked for exists, and it is not new vocabulary: one level
is one cut plus that segment's consumers, and the tail is the same
level again with the subject rebound to the continuation — which
is precisely the divide flow's **link** (`divide-flow-design.md`),
applied to a tree that happens to be a spine (every instance has
at most one child). Split-when's derived expansion is a linked
cut. Two checks other rounds wrote are cashed immediately:

- **The segment flow's order is owned.** Each instance is its
  parent's continuation, so the outer flow of segments carries a
  total order *stated by the link edges* — owned in the
  owned-order criterion's sense (`delay-ontology-design.md`), not
  merely present at run time. Registers on the outer segment flow
  are therefore legal, which the wrap loop's truncation (a count
  register feeding end-when on the outer flow) already assumed
  without saying why.
- **The link's measure is discharged by construction.** Each level
  spends at least one boundary consultation (next paragraph), so
  the sub-problem is always at a strictly advanced consultation
  position — the progress species, held structurally. This is why
  the node is total while a hand-drawn linked cut merely *can*
  be.

**The consultation is spent at the cut.** One clause the unrolling
forces into the open, and the round's one genuinely new finding.
The subtle destination is starts-next: the boundary firing's
element heads the continuation, but its *consultation* is spent —
the continuation's boundary is the restriction to firings strictly
after the cut. Without this clause the unrolled form diverges
where the node does not: a boundary firing at a segment's head
would cut again at the same position, minting empty segments
forever. With it, the unrolling and the node agree everywhere,
including the leading-empty-segment case (boundary at the
subject's first firing: one empty segment, then the walk proceeds
from the next consultation). The field's APIs embody the same
clause without stating it: chunk_while consults *adjacent pairs*,
so a chunk's first element never boundaries by itself, and
textwrap's overlong chunk still lands on a line — "every line
takes at least one chunk" — rather than looping. The restriction
rule end-when's stacking section stated (a flow option-kind
relative to F is an admissible boundary for any subject whose
firings are a subset of F's, consulted only at subject firings) is
exactly the lemma the restricted boundary needs — that rule's
second client, strengthening its case for a home in the provenance
inventory.

**So: both, with distinct jobs.** The structural question's
answer. Split-when is a first-class construct whose definition is
the law of segments — not sugar, because the totality above is a
property of the node form that no finite expansion carries. The
spine-shaped linked cut is its **derived view** in the
transformation-levels sense: read-only, materialised never,
consulted when someone asks "what is this doing per segment." And
the **level-1 recognition** connects a *hand-drawn* linked cut to
the node exactly when the chain is uniform — the same boundary
wiring re-instantiated per level, one destination setting
throughout — with the node as the canonical form. A non-uniform
chain is not recognised into anything, because it is a different
program; that is the next section.

## Phased consumption: the finite chain

Between one cut and the iterated cut sits a form the record had
named but never owned: **a finite chain of cuts through
continuations.** Cut the header off the stream, then cut the body
by a different rule; parse the preamble, then the payload. Raku's
grammar ladder called it *sequence* — "phased consumption,
unowned" (`raku-grammars-comparison.md`) — and this round claims
it: k phases are k−1 drawn cuts, each phase's boundary its own
drawn condition, either on the subject's per-firing data (admitted
on the later phases by the restriction rule) or on phase-local
state (a register on that phase's continuation). Finite, drawn, no
corecursion, no measure owed — the phase count is on the page. The
tokenizer's per-declaration interior (name, whitespace run,
definition run — Part I's worked program) re-reads as a three-phase
chain, which is the more honest drawing than a second uniform
split-when, because the phases differ in kind.

Two boundaries of the form, so it isn't over-claimed:

- **Phases decided by trial are not phases.** The Raku round's
  fork stands: a boundary decidable per-firing is segmentation
  vocabulary; a boundary negotiated by attempting a parse and
  failing belongs to speculation (`speculation-design.md`). The
  chain composes *with* speculation (a contender may contain a
  chain) but does not absorb it.
- **A cyclic phase structure is the divide flow, and the measure
  is genuinely owed.** "Loop until this, then loop until that,
  repeat" closes the chain into a drawn cycle — a link on the last
  continuation, back to the first phase's subject position. That
  is ordinary linked recursion, and the author owes its measure
  like any link's. The natural witness is the consultation
  position (the progress species), and the violation shape is the
  left-recursion sibling: **a phase that can spend no consultation
  — an empty prefix under starts-next — hands its own position to
  itself.** The one-node split-when is immune (its consultations
  are spent by construction); only a hand-linked cycle can express
  the violation, and the divide flow's existing diagnostic (name
  the link edge with no consumption on its wire path) already
  names it.

## State across the cut

A small result that falls out of the port shape, recorded because
it answers a question the framing example raised. Framing's parser
state must *survive* a cut (the header knowledge carries into the
body); the wrap loop's line state must *reset* at one (each line
starts empty). Neither needs a mode: run-on state is a register on
the **subject**, whose reads at continuation firings are ordinary
subject-firing reads (continuation firings are subject firings);
per-segment state is a register on the segment's **inner flow**,
reinitialised by nesting as Part I already establishes. The two
drawings say the two meanings — which flow the register binds *is*
the reset policy, one more instance of "the nesting is the reset"
rather than a carry-over bit on the node.

## Against the principles

- **Example first.** The cut is met as end-when (one projection,
  one concrete walk) before the root is ever named; the
  continuation is an addition to a drawing that already works.
- **Inside-out.** Both outputs are flows on wires; the payload is
  a discharged value; no interior scope, no magic head element
  (the coincidence under starts-next is named and declined).
- **Foundations before features.** The law of the cut is
  end-when's law plus one output; the new content of this round is
  one clause (the spent consultation) and three answers assembled
  from adopted machinery. Four dead ends died on paper.
- **No bottlenecks.** Prefix and continuation emerge as two flows,
  never a packed pair; span/break's tuple is named as the costume.
- **Abstraction is the source of truth.** The spine-shaped
  unrolling is a derived view; the authored program keeps the
  node. The corecursion lives below the surface, readable on
  request — the merge/interrupt precedent the decision cited, now
  with the mechanism identified (the link).
- **Building blocks must build.** End-when → *+ tap the
  continuation* (skip-while; the node was already a cut) → *+ a
  second cut on the continuation* (phased consumption) → *+ close
  the chain with a link* (grammar-shaped iteration, measure owed)
  — and, on the other branch, → *split-when* (the uniform iterated
  form as one node). No rung rewrites the previous drawing.

## Dead ends

Recorded in place, each with the reason it should not be
re-proposed.

1. **The continuation as option-kind** (present only on Stopped).
   Rejected above: no client wants missing-vs-empty, the
   Stopped/RanOut bit already lives on the prefix's terminator,
   and the iterated form's last level would change species.
2. **The payload as a value port on the cut node.** Rejected
   above: a flow operation carries no value ports
   (`barrier-value-crossing-design.md`, adopted), and the
   terminator home is end-when's adopted machinery — a port would
   be a second home for one value.
3. **The corecursive chain as the surface.** The decision's own
   posture, now with the structural reason: the chain has no
   finite drawing and owes a measure; the node is total by
   construction. The chain survives as the derived view only.
4. **Separate prefix and continuation node species** — a
   standalone "rest-when" beside end-when, each consuming
   (subject, boundary). Rejected: two nodes would draw two cuts
   that coincide only by the accident of identical wiring, where
   the record's sharing discipline demands the shared thing be
   drawn once (sharing is opt-in via binding, never via textual
   coincidence); one node with two flow outputs makes the
   coincidence structural.
5. **A per-segment re-arming mode** (a bit for whether the
   boundary "re-arms" after each cut). Dissolves: re-arming is the
   spent-consultation clause, which is uniform — the boundary is
   consulted once per subject firing, full stop. There is nothing
   to configure.

## What this changes, and what it leaves

If a design conversation adopts this round's answers: question
10's three edges close; Raku's *sequence* combinator gains an
owner (the finite chain), completing that ladder's four rows
(repeat = split-when, sequence = chained cuts, recurse = the
divide flow, alternate still unexamined); the restriction rule
gains its second client and should move into the provenance
inventory; the owned-order criterion's check on the segment flow
is cashed (registers on the outer flow are grounded, not assumed);
and the spent-consultation clause should be folded into the law of
segments' consultation sentence, where it has been implicit.

Left open, with owners: adoption itself; the continuation port's
spelling and the terminator-only discharge's binder form (the
textual round, jointly with the destination word-triple); the
drawing of a two-output cut node (layout, out of scope here);
whether `alternate` (typed segments) is a destination of this
family or its own construct (unexamined, filed with question 3's
grammar boundary); and the anchor rule's continuation corner —
trivial as far as this round can see (the continuation completes
exactly when the subject does, so it adds no new anchor moment),
noted so the anchor round confirms rather than inherits it.
