# Variable-rate consumption and the running view of a collect

Status: exploration — a proposal with leanings, not adopted. The two
constructs worked out here (split-when as a segmenting flow operation,
and the running view as a derived port of a collect) are prepared for
the design conversation; per the sampling method's own rule, evidence
reweights the agenda but decisions stay in the conversations.

Two everyday shapes have no owning construct in the record. First,
loops that consume input *at a variable rate* — "consume while it
fits," "read exactly N more bytes," "group while they repeat." Second,
loops that read *the output they have built so far*, mid-walk — the
indent chosen by whether any line has been emitted yet, a DP entry
indexing earlier entries, a substitution looking up an
already-collected definition. This round works both, because in the
richest sampled loop they are interlocked.

## Why the language needs both

This is the record's only Tier-1 area with **no owning construct
anywhere** (`open-problems.md`): three of the nine breadth-set loops —
the wrap loop, the tokenizer-substituter, the DP table fill — have no
designed owner, and the survey locates "where the language's breadth
risk currently concentrates" exactly here (`real-loop-survey.md`, "the
80/20 counterweight"). The end-when round bounded this cluster out on
purpose ("the take question stays with the decision-driven family
round" — `end-when-design.md`). This is that round.

The demand, gathered from the record:

- **The wrap loop** (breadth item 1; survey 1, textwrap). The richest
  loop in either sample: chunks consumed at a variable rate ("consume
  while it fits" — a data-dependent take), the output-so-far read back
  mid-loop twice (the indent chosen by whether any line has been
  emitted; the truncation path *rewriting* `lines[-1]` and breaking).
  The survey's verdict: "nothing in the current or candidate
  inventory covers this loop as one reading."
- **The tokenizer-substituter** (breadth item 2; survey 2). Pull-based
  consumption at a variable rate — nested sub-loops consume more
  tokens depending on what was seen — plus a keyed accumulator written
  *and read back* during the walk (definitions collected, then
  substituted into later references).
- **The DP table fill** (breadth item 4; survey 2). A collect whose
  per-element body indexes into the collect's own earlier output —
  scan-with-full-history, "stronger than the running-view question and
  stronger than window," and "the bread of numerics."
- **The running view, three guises** (survey 2, finding 2.5): the same
  demand sighted independently as read-whole (textwrap's `lines`),
  read-by-index (the DP table), and read-by-key (the tokenizer's
  `variables`) — "a recurring demand, not a curiosity," filed between
  multi-close and the register designs, owned by neither.
- **Protocol framing** (`tough-use-cases-design.md`, use case 5):
  "read exactly N more bytes, where N came from the header" —
  decision-driven consumption from the datagram side.
- **The decision-driven family's unworked members**
  (`tough-use-cases-design.md`, inventory item 4, open question 5):
  the ordered/decision-driven merge has a worked sketch; *data-dependent
  take* — "advance how far" — has only its name. The end-when round
  answered the advance-or-stop half; the advance-how-far half is here.
- **Small everyday sightings**: skip-while (a predicate cursor),
  chunking, run-length-encoding-shaped adjacency grouping.

One observation organises the round: in the wrap loop the two halves
are *interlocked* — the boundary decision ("does this chunk fit?")
depends on the width, which depends on the indent, which depends on
the running view (has any line been emitted yet?). That is why they
are worked together.

## What the record already fixes

As with end-when, assembling the constraints is most of the work.

**Conditions are case splits, not predicates.** One vocabulary for
"does this firing satisfy P": a case split producing alt flows. Filter
consumes such an alt (join); end-when consumes such an alt (stop).
Higher-order predicate arguments are rejected
(`configuration-scopes.md`). Whatever decides a segment boundary must
arrive as a flow.

**Derivation, not retroaction.** End-when's hardest-won rule: a
construct never reaches into an existing flow and changes what other
consumers see; it mints a derived flow beside it
(`end-when-design.md`, "Derivation, not retroaction"). A variable-rate
consumer obeys the same rule — other collects of the same flow see the
full, flat walk.

**The terminator machinery is uniform.** Every flow kind has a
termination event; terminators carry payloads; a whole-flow collect
discharges the terminator into an ordinary tagged value
(`async-flow-design.md`). Anything that ends a *segment* early has
this machinery available per segment.

**Option-kind relative to a parent** is a defined notion: a flow that
fires at most once per firing of the parent, in the parent's context
(`partial-collect-design.md`). A boundary operand will be one, exactly
as end-when's stop operand is.

**The stream runtime has three moves** — emit-and-continue,
become-the-rest, abandon-the-rest (`lazy-stream-placement-design.md`,
"The skip mechanism"). A construct that compiles to these rather than
demanding a fourth is at the right altitude.

**Registers and their check.** Loop-carried state is the register
designs (`iteration-with-state-design.md`, two live candidates); both
expose the carried value by wiring, and productivity is "every cycle
crosses a Delay/register" — decidable, with the synchronous-dataflow
precedent. A register on a nested flow reinitialises per firing of the
outer flow — nested loops already mean this.

**Corecursion is not handed to users raw.** The record's diagnosis of
the ordered merge stands as a warning for this whole family: "manual
cursor bookkeeping is the assembly language of iteration"
(`tough-use-cases-design.md`, obstruction 1). Cursor-register
lowerings may exist and be correct; they must not be the surface.

**Derived views and derived-port reference exist on paper.** A
high-level node has an always-available, read-only derived expansion,
and a wire may reference the derived result's principal ports without
materialising anything (`transformation-levels-design.md`, "Building
on a derived view"; the worked client is reduce-close's augment
expansion, `iteration-with-state-design.md`, "A second accumulator on
a sum"). This round gives that machinery its first *everyday* client.

---

# Part I: variable-rate consumption

## The reframing: "advance how far" is boundary placement

The family's inherited name for this gap — *data-dependent take*,
"advance how far" — carries imperative furniture: a cursor, and a
count of how far to move it. Look instead at what every sampled
instance actually does:

- textwrap consumes chunks *until the line is full* — the chunks of
  one line are a **run** of the chunk sequence;
- the tokenizer consumes tokens *until the declaration ends* — the
  tokens of one declaration are a run of the token stream;
- framing consumes bytes *until the message is complete* — the bytes
  of one message are a run of the byte stream;
- run-length encoding consumes elements *while they repeat* — a run in
  the literal sense.

In each case the "count" — how many elements this step consumed — is
never interesting in itself and never appears in the data. What the
program means is a **partition of the input flow into consecutive
segments with data-determined boundaries**. The count is the
imperative encoding of a boundary position, the same way the flag
variable is the imperative encoding of end-when's terminator. Asking
"advance how far" was asking about the lowering.

So the proposal is not a take with a count operand. It is a segmenting
operation, and the number never appears.

## The shape: split-when, a binary flow operation

**Split-when is a binary flow operation with asymmetric operands
(subject, boundary).** Both are flows. `boundary` must fire in the
subject's own context, at most once per subject firing — option-kind
relative to the subject. The output is a nested flow: an outer flow
with one firing per segment, each carrying an inner flow that fires
with that segment's subject firings, in order.

Its semantics is one law:

> **The law of segments.** Split-when partitions the subject's firings
> into consecutive segments. At each subject firing the boundary is
> consulted; where it fires, a cut is placed. The boundary firing's
> own element goes to the end of the current segment, to the start of
> the next, or to neither, per the node's boundary-destination
> setting. Each segment's inner flow ends with a terminator carrying
> that boundary firing's value; the final segment ends the way the
> subject ends, terminator passed through. Every subject firing lands
> in exactly one segment (or is dropped as a delimiter), and order is
> preserved throughout.

Theorems of the law, not extra design:

- **Join inverts it.** With no dropped delimiters, `join(outer, inner)`
  over the segments reproduces the subject's firings exactly —
  segmentation adds structure without moving, duplicating, or losing
  anything. (With drops, it reproduces the subject filtered by the
  delimiter alt — split-plus-join *is* that filter.)
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
  discharges that segment's terminator: "did this line end because the
  next word didn't fit, or because the words ran out" is a per-segment
  case split on existing machinery, parallel to end-when's readout.
- **The empty and total cases are unremarkable.** A boundary firing
  immediately gives an empty first segment; two adjacent boundary
  firings give an empty segment between them; a boundary that never
  fires gives one segment that is the subject. Empty segments are real
  programs (splitting on adjacent delimiters) and other programs
  filter them out downstream (textwrap's `if cur_line:`) — an ordinary
  filter on the outer flow, not a mode of the node.

The same operand pattern now recurs a third time:

| operation | operands | yields |
|---|---|---|
| join (filter) | (subject, alt flow) | the firings where the alt fires |
| end-when | (subject, stop) | the firings before the stop first fires |
| split-when | (subject, boundary) | the firings, grouped between boundary firings |

Three verbs, one wiring discipline: build a case split on per-firing
data, aim one alt at a flow operation. A user who has learned to
filter has learned most of split-when.

```
-- spelling provisional (open question 8)
tokens -> open list -> split decl of Boundary, Within
  Boundary: -~> split-when      -- outer flow of segments; each carries an inner flow of that declaration's tokens
-~> collect => decls            -- collect the outer flow: a list of per-declaration results
```

The line above says: cut the token stream into declarations wherever
a `Boundary` alt fires, then collect one result per declaration.

## The boundary element's destination: end-when's bit, grown one value

End-when needed one bit (the stopping element in or out). Split-when's
boundary element has three possible destinations, and all three are
everyday, each sighted in the wild:

- **Starts the next segment** (the exclusive reading). The wrap loop:
  the chunk that doesn't fit isn't dropped and doesn't end the line —
  it is the first chunk of the *next* line. Adjacency grouping (RLE,
  groupby) is the same: the element that differs begins the new run.
- **Ends the current segment** (the inclusive reading). Framing: the
  byte that completes the message belongs to the message.
  Take-until-inclusive per segment.
- **Dropped** (the delimiter reading). Splitting on separators:
  str.split, CSV fields, blank-line paragraph splitting. The boundary
  element is neither segment's; its value still rides the segment
  terminator, so "which delimiter" is not lost.

The leaning mirrors end-when's Option B: a genuinely small, local,
enumerated choice on the node (or on the boundary wire — the same open
question as end-when's bit, and the two should be decided together,
since end-when's two values are this three-value setting with "starts
the next segment" degenerated away — there is no next segment after a
stop). Configuration in the established sense, not a construct.

One consequence worth noting rather than smoothing: under the
starts-next reading, the boundary condition at element `e` is
evaluated against the *current* segment's state (does `e` fit in this
line?), and `e` then lands in the *next* segment, whose state starts
fresh. That is not an anomaly — it is precisely what "doesn't fit, so
it goes on the next line" means, and what every chunk_while-family API
does — but the law's phrase "the boundary is consulted at each subject
firing" should be read with this in mind: the consultation happens in
the segment the element would have extended.

## Well-formedness: the boundary may read per-segment state

The wrap loop's boundary reads `cur_len` — the running total of the
current segment. Structurally this is a cycle: split-when produces the
inner flow; a register lives on the inner flow; the boundary split
reads the register's state port; the boundary feeds split-when.

The cycle is productive by the existing rule, not a new one: the
register's state port is a previous-firing read (the strict prefix of
the current segment), so the cycle crosses the register — exactly the
"every cycle passes through a Delay crossing" condition
(`iteration-with-state-design.md`, "Ruling out non-productive cycles
structurally"). Unwound: the boundary decision at firing *e* reads
state folded from firings before *e*; where segments start was decided
at firings before *e*; induction over the subject's order grounds
everything. A boundary wired from the *current* element alone
(sentinel, adjacency against a carried previous element) doesn't even
have the cycle. The construct's hard case lands on a check the
language already runs.

## Prior art

The shape is heavily precedented, which is evidence for the reframing
(the way Lustre's `pre`/`->` was for the Delay):

- **Ruby** `Enumerable#slice_when` / `#chunk_while` — segmentation by
  an adjacent-pair condition; the two names are the boundary-destination
  bit surfacing in an API.
- **Python** `itertools.groupby` — adjacent grouping by key change: a
  split-when whose boundary is "key(e) ≠ key(previous e)", i.e. a case
  split reading a one-element register. Note it is *not* the keyed
  collect / group-by open from the concurrency round, which partitions
  by key value regardless of adjacency — different constructs in the
  wild too, a reassuring confusion already disambiguated by this
  record's vocabulary.
- **SQL's "gaps and islands"** — sessionisation by time gap, islands
  of consecutive activity. Famous as a *hard problem* precisely because
  SQL lacks the construct and it must be built from window functions
  and running counts — a whole genre of blog posts is the field's
  testimony that the missing vocabulary hurts.
- **Parser toolkits' take-while families** — the take-while/span/break
  cluster is the one-segment special case, ubiquitous.

## Worked programs

### The wrap loop, end to end (breadth item 1)

The sharpest standing challenge, drawn. (A construct list rather than
chains, deliberately: the split-when, running-view, and end-when
spellings are each owed to the textual round, so arrow-form text here
would be invented three times over; the list is the composition, not
parseable syntax.)

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

Empty-line suppression (`if cur_line:`) is a filter on the outer flow.
What is honestly not covered: `break_long_words` — splitting a single
chunk that exceeds the width is production *within* an element, not
consumption across elements; it composes as a pre-processing flow
(each chunk opens into fragments) and is out of this construct's
scope, correctly.

The count of coordinated pieces is real — a segmentation, two
registers, a running-view read, an end-when — but compare the sentence
the loop says: "group the words into lines that fit, indenting the
first line differently, stopping at max_lines." Each clause is one
construct; nothing in the drawing is bookkeeping. The survey's
complaint was that the pieces had no owners; the pieces now compose.

### Framing (the datagram parser's read-N-more)

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

The genuinely-numeric count enters as *data* — the header's N feeds a
register the boundary reads — not as a verdict of the construct. That
is the correct division of labour: the language draws the boundary;
the program computes where it falls. Honest assessment: this is
expressible and causally clean, but the two-phase register is a
hand-built state machine at exactly the granularity the custom
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

The consumption structure — variable-rate pull, nested state-dependent
sub-walks — is two nested split-whens, and the mid-walk readback is
one running-view reference. What strains: the real parser's interior
is a grammar, and past two levels of segmentation a grammar wants
grammar-shaped vocabulary (the divide flow's territory, or custom
flows). The breadth test asks "without too much pain," and the honest
answer is: the two shapes that made this loop a breadth item are each
one construct now; a full CSS parser would still be work. That is the
right boundary — split-when is tokenization-and-framing vocabulary,
not a parser generator.

### Skip-while, and the relationship to end-when

The predicate cursor — skip leading matches, keep the rest — is
split-when with a boundary at the first non-match, keeping the *second*
segment: the complement of end-when's prefix in one drawing. This
adjacency is systematic:

- `end-when(F, c)` is the *first segment* of `split-when(F, c)` (with
  the matching destination bit);
- skip-while is the join of the rest;
- take-while / span / break — the whole classical cluster — are
  projections of one cut.

The leaning, following the interrupt precedent exactly
(`end-when-design.md`, "Sibling or same node"): **record the
relationship, do not unify the constructs.** End-when is promoted by
frequency and must stay one everyday gesture with a flat output
(eighteen of sixty loops; its output is a flow, not a flow of flows);
split-when is the breadth construct. A level-1 recognition ("an
end-when is a split-when observed at its first segment") can relate
them in the tower without either construct wearing the other's weight.
What they must share is the boundary/stop operand discipline and the
destination bit's vocabulary — the same family-level sharing as the
verdict-vocabulary rule recorded for the merge (end-when's open
question 3).

## The family, after this round

The tough doc's open question 5 asked: one primitive (chooser over N
heads returning which-advances) or a small family? The picture this
round leaves:

- **advance-or-stop** — end-when. Worked, standalone
  (`end-when-design.md`).
- **advance how far** — dissolved. Not a chooser verdict and not a
  count: boundary placement, owned by split-when.
- **which of two advances** — the decision-driven merge, still owed
  its round. It is genuinely not a segmentation (two subjects, one
  interleaving), and this round leaves it the chooser sketch it has.

The leaning on the question itself: **no N-head chooser primitive at
the surface.** Each family member keeps meeting its own everyday shape
with its own drawing; the chooser — per-step verdicts over heads — is
the shared *lowering* shape (all three lower to cursor-register
programs, which is where "the assembly language of iteration" belongs:
below the surface, readable on request, per the source-of-truth
principle). The family is one family at the semantic-vocabulary level:
stop verdicts write the same terminator, boundary/stop operands obey
the same option-kind discipline, destination bits share one
enumeration. If the merge's round finds its chooser wanting the same
dissolution — interleaving as something drawn rather than decided —
the family gets simpler still; that is that round's question.

## By kind, and the compile

Sketches only; nothing here touches `src/Compile.res`, and
implementation would land after the first-class-ports migration.

- **List subject**: the lowering is the textwrap loop itself — an
  outer while over an inner while, the boundary check deciding the
  inner break, the destination bit deciding whether the element is
  pushed before or after the check (or not at all). That the derived
  lowering is verbatim the code the survey drew at random is the same
  strong-form philosophy argument the ordered merge made: the lowering
  exists, is correct, and nobody should read it unless they ask.
- **Stream subject**: the outer stream's pull produces a segment whose
  inner stream consumes from the shared source cursor; ending a segment
  is abandon-the-rest aimed at the segment's terminator — the third
  existing move, no fourth needed. The real constraint is sequencing:
  inner flows share one underlying cursor, so segments must be consumed
  in order, and an outer consumer that skips ahead forces either
  draining or buffering the skipped segment — the same
  retention/pull-amplification footgun family the stream docs already
  track for `Delayed`. Flagged for the stream rounds, not designed here.
- **Self-driven / async subjects**: nothing kind-specific appears — the
  law is stated over firings and terminators, both uniform. The
  concurrency caveat is end-when's verbatim: "consecutive" is
  order-dependent, so split-when off `serial` means schedule-determined
  segments, which must be meant if admitted.

---

# Part II: the running view of a collect

## The recognition: the record already contains this construct

The three guises — read-whole, read-by-index, read-by-key — ask for
one thing: **the collect's output-so-far, readable per-firing inside
the walk.** The survey filed it between multi-close and the registers.
It belongs to neither; it falls out of machinery the record has
already built, in the iteration-state round's own vocabulary.

A list collect *is* — as a derived view — an augment loop whose
register carries the built list and whose step is append
(`iteration-with-state-design.md`, "Reduce-close is its own result
node, lowered in compile", and "A second accumulator on a sum, via
derived-port reference": the derived augment form and references to its
ports are exactly the mechanism already designed for adding a lockstep
accumulator to a `sum`). That derived register has a state port. **The
running view of a collect is the state port of the collect's derived
augment form.** A keyed collect's derived register carries the
map-so-far; its state port is the read-by-key view. No new node species
anywhere.

So the proposal is a *definition*, not a construct:

> **The running view.** Every collect exposes, as a principal port of
> its derived augment form, its accumulated output: at each firing of
> the collected flow, the value built from the strict prefix of firings
> before this one. The port is read by ordinary wiring, in the
> collect's flow context; reading it never materialises the derivation
> (`transformation-levels-design.md`, "Building on a derived view:
> wires may reference derived ports").

Whether the port is *drawn on the collect node itself* (the friendly
surface) or reached by explicitly referencing the derived view is a
presentation question; the leaning is on the node, defined as the
derived port — one thing, surfaced.

## Causality, and the check that transfers

The strict-prefix time shape is load-bearing. A body that both
contributes to a collect and reads its running view is a cycle: body →
collect → derived register → state port → body. It is productive by the
existing rule — the read crosses the derived register (a previous-firing
read), so "every cycle passes through a Delay crossing" holds — and
non-degenerate: the current firing's own contribution is never visible
to itself. The wrap loop's indent read sees lines emitted *before* this
line, which is what the wild code's `if lines:` meant. The DP fill's
entry *n* reads entries produced at earlier firings, which is what
dynamic programming *is*.

Two boundaries the existing rules already police, stated so nobody
re-derives them:

- **Sibling reads are time travel.** The running view is readable in
  the collect's own flow context (and descendants, by the prefix rule).
  Reading one loop's so-far from a sibling loop not on the same nesting
  chain is the ordinary no-time-travel violation, caught by the
  ordinary check.
- **Reads pin the order.** A collect whose running view is read is
  order-committed — under the concurrency round's species it is
  `serial` by structure (the read means "before" means something). Same
  interaction the registers already have; flagged for that round's
  table.

## The three guises, mapped

- **Read-whole** (textwrap's `lines`): the state port's value, a list;
  emptiness-testing it is a value operation. The first/subsequent-output
  split the survey noticed — "the first-iteration distinction appearing
  in the wild as a read of the accumulated output" — is exactly this: no
  first-firing construct, just an ordinary case split on the running
  view's emptiness.
- **Read-by-index** (the DP table): index into the running list — a
  value operation on the port. The efficiency worry dissolves in
  compile: the collect is materialising an array anyway; the running
  view compiles to reading the accumulator in place, O(1), no copy.
  (Visible in the lowering: `s += ... zeta_values[2*k] ...` — the wild
  code *is* the compile target.)
- **Read-by-key** (the tokenizer's `variables`): the keyed collect's
  running map, `get` by key returning option — the option-shaped miss
  is honest (a reference to a variable not yet defined is a real case
  the wild parser also handles).

## The rewrite guise dissolves

Textwrap's truncation path *rewrites* `lines[-1]` mid-walk. A mutable
running view — writing into a collect's past from the body — would be
retroaction on already-emitted values, exactly what
derivation-not-retroaction forbids, and it is not needed. Worked
against the actual program: the rewrite happens *once, at termination*
— it is not a mid-walk operation at all, it is part of the readout. The
time-forward expression: end-when cuts the segment flow at max_lines;
the discharged terminator says the walk was truncated (and carries what
remained); downstream, on the collected prefix — a plain list value in
hand — the last element is amended. Collect, discharge, amend: all
existing vocabulary, all after the walk, which is when the wild program
actually knows truncation happened too. The mid-walk appearance of the
rewrite in the Python is an artifact of writing the readout inside the
loop body for lack of anywhere else to put it.

General rule worth recording: a "rewrite of the output-so-far"
conditioned on termination belongs downstream of discharge; one
conditioned on later *elements* is a one-firing lookahead, which is
window/negative-delay territory and was drawn in neither survey. If a
sample ever produces the second kind, it files there, not here.

## What this presses on

The running view makes derived-port reference — until now exercised
only by the `sum`+`max` example — **load-bearing for everyday
programs**. Two consequences for other rounds:

- The transformation-levels question "which derived ports are
  principal" (`transformation-levels-design.md`, "What is unresolved";
  echoed in `iteration-with-state-design.md`) gains urgency and a
  concrete first answer to test: *the augment form's state port is
  principal for every collect.*
- The iteration-state decision gains a datum: whichever candidate is
  chosen must leave collects with a coherent derived augment form,
  because the running view is defined through it. Pressure on the
  *machinery*, not a thumb on the scale between the candidates — both
  can express the augment loop; what matters is that the derived-view
  story stays real.

---

## Against the principles

- **Example first, then generalise.** Both proposals are after-the-fact
  additions to a concrete walk: build the flat walk, then place
  boundaries (split-when interposes on existing wiring); build the
  collect, then read its so-far (the port was always there, derived).
  Neither requires declaring structure upfront — contrast a chunking
  combinator parameterised by a size function, which demands the
  generalisation before the first concrete line.
- **Inside-out / cases as values.** No lambdas, no interior scopes, no
  magic names. The boundary is a visible case split; per-segment state
  is a register wired like any register; the running view arrives on a
  wire. Segment terminators are values you discharge.
- **Foundations before features.** Split-when's new content is one law
  and a three-valued bit; everything else — option-kind operands,
  terminators, registers-on-inner-flows, the productivity check,
  discharge — is settled machinery. The running view adds *no*
  construct: it is a definition over the derived-view machinery. Three
  dead ends died on paper (below).
- **Programmer's abstraction level.** "Group these into runs," "the
  lines so far" are words in the programmer's vocabulary, and each gets
  one reading. The gaps-and-islands genre is the counterevidence for
  the status quo: without the vocabulary, the program is a puzzle.
- **No bottlenecks.** Segments pass elements through as themselves — the
  inner flow *is* the subject's firings, not a packed list per segment
  (collecting each segment into a list is a choice made at a collect,
  downstream). The boundary payload rides the segment terminator;
  nothing is tupled to cross the construct.
- **Abstraction is the source of truth.** Split-when's lowering is the
  nested-while program the survey drew; the running view's lowering is
  the in-place accumulator read. Both stay derived views; the authored
  program keeps the segmentation and the port.
- **Building blocks must build.** The ladders, walked:
  - *Plain collect* → **+ segmentation** (add a boundary split and the
    split-when; re-aim the collect at a segment) → **+ per-segment
    state** (a register on the inner flow) → **+ boundary reads the
    state** (rewire the split's input) → **+ per-segment readout**
    (discharge the segment terminator) → **+ outer state** (register or
    running view on the outer flow) → **+ truncation** (end-when on the
    outer flow). The top of this ladder *is the wrap loop* — breadth
    item 1 reached from a plain collect with no species change at any
    rung, the expansion test the breadth set demands.
  - *Collect* → **+ read the so-far** (wire from the port) → **+ read by
    index/key** (value ops on the same wire) → **+ the DP fill** (the
    body's inputs now include the port; nothing else moved). Breadth
    item 4, by additions.
  - The interlock rung: the wrap loop's boundary reading the running
    view (width ← indent ← emptiness) is a wire between the two
    proposals, not a new construct — the composed program is still
    additive.

## What this changes elsewhere, if adopted

Nothing is dissolved or corrected; two named holes get worked
proposals. If the design conversation adopts some form of these:
breadth-set items 1, 2, and 4 gain owners to be tested against; the
tough doc's open question 5 closes (end-when standalone — already
leaned; advance-how-far dissolved into boundary placement; the merge
stays the family's one chooser member, pending its round); survey
finding 2.5's question gets its answer (derived state port, strict
prefix); `core-model.md` would gain split-when a line beside join and
end-when in the operand-pattern family — but not before adoption. The
transformation-levels round inherits the principal-port pressure either
way.

## Open questions

1. **The destination setting's final form.** Three values on the node
   vs an attribute of the boundary wire; its drawing; and the joint
   decision with end-when's two-valued bit (one enumeration, shared).
   The stacked-stops tie-break interaction recorded in end-when's
   question 1 presumably has a sibling here (two boundaries tying at one
   firing — same regime analysis, one bundle vs independent splits —
   assumed to transfer, unverified).
2. **Empty segments.** The law permits them; is downstream filtering the
   whole everyday story, or does the drop-empties idiom deserve a
   recognised spelling (str.split's split-vs-fields distinction suggests
   users will reach for it constantly)?
3. **Nested and phased segmentation vs grammar vocabulary.** Two levels
   served the tokenizer; where is the honest boundary beyond which this
   is the divide flow or custom protocol flows? A worked third program
   (the binary protocol parser from the use-case backlog) would locate
   it.
4. **A fixed-length-segment catalog block.** Framing's two-phase
   register is expressible but state-machine-flavoured; decide whether
   `segments of length n (n from data)` earns a catalog entry with a
   derived lowering onto split-when.
5. **The stream compile's sequencing constraint.** In-order consumption
   of segments, and what an out-of-order outer consumer forces (drain vs
   buffer) — belongs to the stream rounds, with the `Delayed` footguns.
6. **Principal derived ports.** The running view proposes "the augment
   state port is principal for every collect" — confirm in the
   transformation-levels round, and pin which other ports (the combined
   flow, the final value) join it.
7. **Concurrency interactions.** Split-when off `serial`; a running-view
   read pinning a collect to `serial` — both flagged into the
   concurrency round's tables.
8. **Textual spellings.** The (subject, boundary) pair, the destination
   setting, segment-terminator discharge, and the running-view reference
   all need spellings in the three-arrow textual form (the samples above
   are provisional); that document's next round.
9. **Naming.** "Split-when" deliberately rhymes with end-when; "running
   view" vs "so-far" vs the survey's phrase. Deferred, with one
   constraint each: the segment construct's name should read as a flow
   operation yielding *nested* flow (the nesting is the point), and the
   view's name must not suggest mutability.

## Dead ends, recorded

**A count-valued advance verdict.** `advance(k)` — a chooser verdict or
node operand carrying how many elements to consume — was the family's
inherited framing and is rejected as the surface: the count is the
imperative encoding of a boundary (no sampled program's *meaning*
contained the number; every one contained the run), it puts a bare
integer where the record wants drawn structure, and it loses the
boundary payload that discharge gives free. Where the data genuinely is
a count (framing's N), it enters as data — a wire into a register the
boundary reads — not as the construct's verdict. Not to be re-proposed;
the boundary reframing supersedes it.

**A mutable running view.** Letting the body write into the collect's
past (`lines[-1] = ...` mid-walk) — rejected on
derivation-not-retroaction grounds: it would make one consumer's body
retroactively change what every other consumer of the same collect
sees, and it is unnecessary — the sampled rewrite is
termination-conditioned and lands downstream of discharge (the
amend-after pattern above). If a future sample produces an
*element*-conditioned rewrite, that is lookahead (window territory),
still not mutation.

**Variable-rate consumption as a collect mode.** A "collect until full
/ collect n" collect-variant — fusing the boundary into the collect
node — is rejected for end-when's reason exactly: the readout
composition needs the cut upstream of an ordinary collect (so the
segment can be collected, effect-walked, or multi-closed by independent
consumers), and a fused node would re-decide the boundary per consumer
under multi-close. The cut is a flow operation; collects stay collects.
